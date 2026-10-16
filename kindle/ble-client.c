#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <time.h>
#include <dlfcn.h>
#include "crypto.h"
#include <kindlebt/kindlebt.h>
#include <kindlebt/kindlebt_log.h>
#include <ace/bluetooth_beacon_api.h>

static sessionHandle session;
static bleConnHandle connection;
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
static int discovered, ready, result;
static bdAddr_t address;
static uint8_t received[1024];
static size_t received_size;
static uint32_t discovered_services;
static char last_revision[17], last_command[17];
static uint8_t stream_buffer[262144];
static int stream_size, stream_expected, stream_ready, stream_error;
static uint8_t service_uuid[16] = {0xe0,0x7e,0x10,0x00,0x7a,0x51,0x4c,0x44,0xa6,0x5a,0x5d,0x45,0x53,0x4b,0x00,0x01};
static uint8_t (*extract_name)(aceBT_BeaconScanRecord_t*, aceBT_bdName_t*);
static uint8_t (*extract_uuid)(aceBT_BeaconScanRecord_t*, aceBT_uuid_t*, uint8_t);
static void registered(aceBT_status_t status) {
    pthread_mutex_lock(&mutex);
    result=status; ready=1; pthread_cond_signal(&condition);
    pthread_mutex_unlock(&mutex);
}

static void scan_result(aceBT_scanInstanceHandle handle, aceBT_BeaconScanRecord_t* record) {
    (void)handle;
    aceBT_bdName_t name = {0};
    aceBT_uuid_t uuids[16] = {0};
    int match = 0;
    if (extract_name) {
        extract_name(record, &name);
        match = !memcmp(name.name, "Kindle Desk", 11);
    }
    if (extract_uuid) {
        int count = extract_uuid(record, uuids, 16);
        for (int i=0; i<count && i<16; i++) {
            uint8_t reverse[16];
            for (int j=0; j<16; j++) reverse[j] = uuids[i].uu[15-j];
            if (!memcmp(uuids[i].uu, service_uuid, 16) || !memcmp(reverse, service_uuid, 16)) match=1;
        }
    }
    if (match) {
        pthread_mutex_lock(&mutex);
        address = record->addr; discovered = 1;
        pthread_cond_signal(&condition);
        pthread_mutex_unlock(&mutex);
    }
}

static int wait_flag(int *flag, int seconds) {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline); deadline.tv_sec += seconds;
    pthread_mutex_lock(&mutex);
    while (!*flag) {
        if (pthread_cond_timedwait(&condition, &mutex, &deadline)) {
            pthread_mutex_unlock(&mutex); return -1;
        }
    }
    pthread_mutex_unlock(&mutex); return 0;
}

static void on_read(bleConnHandle handle, bleGattCharacteristicsValue_t value, status_t status) {
    (void)handle;
    pthread_mutex_lock(&mutex);
    result = status;
    received_size = value.blobValue.size;
    if (received_size > sizeof(received) || !value.blobValue.data) {
        received_size = 0; result = -100;
    } else memcpy(received, value.blobValue.data, received_size);
    ready = 1; pthread_cond_signal(&condition);
    pthread_mutex_unlock(&mutex);
}

static void on_write(bleConnHandle handle, bleGattCharacteristicsValue_t value, status_t status) {
    (void)handle; (void)value;
    pthread_mutex_lock(&mutex);
    result=status; ready=1; pthread_cond_signal(&condition);
    pthread_mutex_unlock(&mutex);
}
static void on_database(bleConnHandle handle, bleGattsService_t *db, uint32_t count) {
    (void)handle; (void)db; discovered_services=count;
}
static void on_notification(bleConnHandle handle, bleGattCharacteristicsValue_t value) {
    (void)handle;
    const uint8_t *p=value.blobValue.data;int size=value.blobValue.size;
    pthread_mutex_lock(&mutex);
    if(stream_expected>0) {
        uint32_t offset=p&&size>=4?(uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24:UINT32_MAX;
        if(!p||size<5||offset!=(uint32_t)stream_size||size-4>stream_expected-stream_size) {
            stream_error=1;stream_ready=1;
        } else {
            memcpy(stream_buffer+stream_size,p+4,size-4);stream_size+=size-4;
            if(stream_size==stream_expected)stream_ready=1;
        }
        if(stream_ready)pthread_cond_signal(&condition);
    }
    pthread_mutex_unlock(&mutex);
}

static int read_value(bleGattCharacteristicsValue_t value) {
    pthread_mutex_lock(&mutex); ready=0; received_size=0; pthread_mutex_unlock(&mutex);
    int status=bleReadCharacteristic(session, connection, value);
    if (status) return status;
    if (wait_flag(&ready, 15)) return -101;
    return result;
}

static int write_value(bleGattCharacteristicsValue_t *value, const uint8_t *bytes, size_t count) {
    // The discovered record retains its original allocation; write uses a stack copy.
    bleGattCharacteristicsValue_t copy=*value;
    copy.blobValue.data=(uint8_t*)bytes; copy.blobValue.size=count; copy.blobValue.offset=0;
    copy.format=BLE_FORMAT_BLOB;
    pthread_mutex_lock(&mutex); ready=0; pthread_mutex_unlock(&mutex);
    int status=bleWriteCharacteristic(session, connection, &copy, ACEBT_BLE_WRITE_TYPE_RESP_REQUIRED);
    if (status) return status;
    if (wait_flag(&ready, 15)) return -102;
    return result;
}

static struct aceBT_gattCharRec_t* characteristic(bleGattsService_t *db, uint32_t count, int suffix) {
    uuid_t id={.type=ACEBT_UUID_TYPE_128};
    uint8_t normal[16];memcpy(normal,service_uuid,16);normal[3]=suffix;
    for(int i=0;i<16;i++)id.uu[i]=normal[15-i];
    return utilsFindCharRec(db,count,id,16);
}

static int number(const char* json,const char* key) {
    char pattern[64];snprintf(pattern,sizeof(pattern),"\"%s\"",key);
    const char* p=strstr(json,pattern);if(!p)return -1;
    p=strchr(p,':');return p?atoi(p+1):-1;
}

static int hex_field(const char* json,const char* key,char* out,size_t length) {
    char pattern[64];snprintf(pattern,sizeof(pattern),"\"%s\"",key);
    const char* p=strstr(json,pattern);if(!p)return -1;
    p=strchr(p,':');if(!p)return -1;
    p=strchr(p,'"');if(!p)return -1;p++;
    for(size_t i=0;i<length;i++) {
        if(!((p[i]>='0'&&p[i]<='9')||(p[i]>='a'&&p[i]<='f')))return -1;
        out[i]=p[i];
    }
    out[length]=0;return p[length]=='"'?0:-1;
}

static int device_command(bleGattCharacteristicsValue_t command, bleGattCharacteristicsValue_t *control) {
    int status=read_value(command);if(status)return status;
    if(received_size==1&&received[0]==0)return 0;
    if(received_size!=50)return -120;
    uint8_t expected[32];if(mac256(session_key,received,18,expected))return -121;
    unsigned int difference=0;for(int i=0;i<32;i++)difference|=expected[i]^received[18+i];
    if(difference)return -122;
    char seq[17];memcpy(seq,received,16);seq[16]=0;
    for(int i=0;i<16;i++)if(!strchr("0123456789abcdef",seq[i]))return -123;
    int code=received[16],value=received[17];
    if(code<1||code>5||value>24)return -124;
    if(!strcmp(seq,last_command))return 0;
    FILE *out=fopen("/mnt/us/kindle-desk/command.req.tmp","w");if(!out)return -125;
    fprintf(out,"%s %d %d\n",seq,code,value);fclose(out);
    rename("/mnt/us/kindle-desk/command.req.tmp","/mnt/us/kindle-desk/command.req");
    for(int i=0;i<25;i++) {
        char done[17]={0};unsigned int c,b,w,m,s;
        out=fopen("/mnt/us/kindle-desk/command.done","r");
        int fields=out?fscanf(out,"%16s %u %u %u %u %u",done,&c,&b,&w,&m,&s):0;
        if(out)fclose(out);
        if(fields==6&&!strcmp(seq,done)&&c==(unsigned int)code&&b<=255&&w<=255&&m<=1&&s<=1) {
            uint8_t ack[54]={8};memcpy(ack+1,seq,16);ack[17]=c;ack[18]=b;ack[19]=w;ack[20]=m;ack[21]=s;
            if(mac256(session_key,ack,22,ack+22))return -126;
            status=write_value(control,ack,sizeof(ack));
            if(!status)memcpy(last_command,seq,17);
            printf("device command=%d status=%u brightness=%u warmth=%u mode=%u\n",code,s,b,w,m);
            return status;
        }
        sleep(1);
    }
    return -127;
}

static int send_device_state(bleGattCharacteristicsValue_t *control) {
    static uint32_t counter;
    static time_t last_report;
    static char last_touch[17];
    time_t now=time(NULL);
    if(now-last_report>=15) {
        unsigned b,c,l,w,m;
        FILE *f=fopen("/mnt/us/kindle-desk/telemetry","r");
        int n=f?fscanf(f,"%u %u %u %u %u",&b,&c,&l,&w,&m):0;
        if(f)fclose(f);
        if(n==5&&(b<=100||b==255)&&(c<=1||c==255)&&(l<=24||l==255)&&(w<=24||w==255)&&m<=1){
            uint8_t packet[42]={9};uint32_t seq=++counter;
            for(int i=0;i<4;i++)packet[1+i]=(seq>>(i*8))&255;
            packet[5]=b;packet[6]=c;packet[7]=l;packet[8]=w;packet[9]=m;
            if(mac256(session_key,packet,10,packet+10))return -128;
            int status=write_value(control,packet,sizeof(packet));if(status)return status;
            last_report=now;
        }
    }
    char touch[17]={0};unsigned x,y;
    FILE *f=fopen("/mnt/us/kindle-desk/touch.req","r");
    int n=f?fscanf(f,"%16s %u %u",touch,&x,&y):0;if(f)fclose(f);
    if(n==3&&strlen(touch)==16&&strspn(touch,"0123456789abcdef")==16&&x<1236&&y<1648&&strcmp(touch,last_touch)){
        uint8_t packet[53]={10};memcpy(packet+1,touch,16);
        packet[17]=x&255;packet[18]=x>>8;packet[19]=y&255;packet[20]=y>>8;
        if(mac256(session_key,packet,21,packet+21))return -129;
        int status=write_value(control,packet,sizeof(packet));if(status)return status;
        strcpy(last_touch,touch);
    }
    return 0;
}

static int transfer(bleGattCharacteristicsValue_t *control, bleGattCharacteristicsValue_t info,
                    bleGattCharacteristicsValue_t data) {
    uint8_t command=5;
    puts("pinning frame");
    int status=write_value(control,&command,1);if(status)return status;
    puts("reading metadata");
    status=read_value(info);if(status)return status;
    if(received_size>=sizeof(received))return -103;
    char meta[1025];memcpy(meta,received,received_size);meta[received_size]=0;
    int bytes=number(meta,"bytes"),pages=number(meta,"pages"),chunk=number(meta,"chunk");
    char sha[65],revision[17];
    printf("frame metadata: %s\n",meta);
    if(bytes<8||bytes>262144||pages<1||pages>2048||chunk!=160||pages!=(bytes+159)/160 ||
       hex_field(meta,"sha256",sha,64)||hex_field(meta,"revision",revision,16))return -104;
    if(!strcmp(revision,last_revision))return 0;
    FILE *out=fopen("/mnt/us/kindle-desk/frame.part","wb");if(!out)return -105;
    (void)data;
    pthread_mutex_lock(&mutex);
    stream_size=0;stream_expected=bytes;stream_error=0;stream_ready=0;
    pthread_mutex_unlock(&mutex);
    command=7;status=write_value(control,&command,1);
    if(!status&&(wait_flag(&stream_ready,100)||stream_error))status=-106;
    pthread_mutex_lock(&mutex);stream_expected=0;pthread_mutex_unlock(&mutex);
    if(!status&&fwrite(stream_buffer,1,bytes,out)!=(size_t)bytes)status=-107;
    if(fclose(out)&&!status)status=-108;
    if(status)return status;
    FILE *check=popen("sha256sum /mnt/us/kindle-desk/frame.part","r");
    char actual[128]={0};
    if(!check)return -109;
    int valid=fgets(actual,sizeof(actual),check)&&!strncmp(actual,sha,64);
    int exit_status=pclose(check);
    if(!valid||exit_status)return -110;
    if(decrypt_frame(bytes))return -114;
    out=fopen("/mnt/us/kindle-desk/frame.part","rb");uint8_t magic[8];
    int png=out&&fread(magic,1,8,out)==8&&!memcmp(magic,"\x89PNG\r\n\x1a\n",8);
    if(out)fclose(out);if(!png)return -111;
    if(rename("/mnt/us/kindle-desk/frame.part","/mnt/us/kindle-desk/frame.png"))return -112;
    uint8_t ack[49]={4};memcpy(ack+1,revision,16);
    if(mac256(session_key,ack,17,ack+17))return -115;
    status=write_value(control,ack,49);if(status)return status;
    out=fopen("/mnt/us/kindle-desk/frame.ready.tmp","w");if(!out)return -113;
    fprintf(out,"%s\n",revision);fclose(out);
    if(rename("/mnt/us/kindle-desk/frame.ready.tmp","/mnt/us/kindle-desk/frame.ready"))return -116;
    // The user partition is a FUSE/VFAT overlay. Flush the PNG and rename
    // metadata before retaining it as the next boot's cached frame.
    if(system("sync"))return -117;
    printf("received revision=%s bytes=%d sha256=%s\n",revision,bytes,sha);fflush(stdout);
    memcpy(last_revision,revision,sizeof(last_revision));
    for(int i=0;i<20;i++) {
        char rendered[32]={0};out=fopen("/mnt/us/kindle-desk/frame.displayed","r");
        if(out){fgets(rendered,sizeof(rendered),out);fclose(out);}
        if(!strncmp(rendered,revision,16)){
            ack[0]=6;mac256(session_key,ack,17,ack+17);
            status=write_value(control,ack,49);if(status)return status;break;
        }
        sleep(1);
    }
    return 0;
}

int main(int argc,char **argv) {
    write(1,"client entered\n",15);
    setvbuf(stdout,NULL,_IOLBF,0);
    uint8_t auth[33]={1},key_bytes[32];
    FILE* key=fopen("/mnt/us/kindle-desk/pairing-key.bin","rb");
    if(!key||fread(key_bytes,1,32,key)!=32){fprintf(stderr,"missing pairing key\n");return 2;}
    fclose(key);
    key=fopen("/mnt/us/kindle-desk/command.done","r");
    if(key){fscanf(key,"%16s",last_command);fclose(key);}
    if(getuid()==0&&(setgid(1003)||setuid(1003))){perror("bluetooth uid");return 3;}
    alarm(120);
    kindlebt_set_log_level(LOG_LEVEL_WARN);
    printf("uid=%d; checking BLE\n",getuid());
    printf("BLE support=%d\n",isBLESupported());
    int status=openSession(ACEBT_SESSION_TYPE_DUAL_MODE,&session);
    printf("openSession=%d\n",status);if(status)return 4;
    status=enableRadio(session);printf("enableRadio=%d\n",status);
    status=bleRegister(session);printf("bleRegister=%d\n",status);if(status)return 5;
    void *lib=dlopen("libace_bt.so",RTLD_LAZY|RTLD_GLOBAL);if(!lib)return 6;
    status_t (*register_scan)(sessionHandle,aceBT_beaconCallbacks_t*)=dlsym(lib,"aceBT_RegisterBeaconClient");
    status_t (*start_scan)(sessionHandle,aceBT_BeaconClientId,aceBT_scanInstanceHandle*)=dlsym(lib,"aceBT_startBeaconScanWithDefaultParams");
    status_t (*stop_scan)(aceBT_scanInstanceHandle)=dlsym(lib,"aceBT_stopBeaconScan");
    extract_name=dlsym(lib,"aceBT_scanRecordExtractName");
    extract_uuid=dlsym(lib,"aceBT_scanRecordExtractUuid");
    if(!register_scan||!start_scan||!stop_scan){puts("scan API unavailable");return 7;}
    aceBT_beaconCallbacks_t callbacks={.size=sizeof(callbacks),.scanResults=scan_result,
        .onclientRegistered=registered};
    ready=0;
    status=register_scan(session,&callbacks);printf("RegisterBeacon=%d\n",status);if(status)return 8;
    if(wait_flag(&ready,15)||result){puts("Beacon registration failed");return 8;}
    aceBT_scanInstanceHandle scan=NULL;
    status=start_scan(session,0xffff,&scan);printf("scan=%d\n",status);if(status)return 9;
    int found=wait_flag(&discovered,35);stop_scan(scan);
    if(found){puts("Kindle Desk not discovered");return 10;}
    puts("Kindle Desk discovered");
    if(argc>1&&!strcmp(argv[1],"--scan-only")){closeSession(session);return 0;}
    bleGattClientCallbacks_t gatt_callbacks={.size=sizeof(gatt_callbacks),
        .on_ble_gattc_read_characteristics_cb=on_read,.on_ble_gattc_write_characteristics_cb=on_write,
        .notify_characteristics_cb=on_notification,
        .on_ble_gattc_get_gatt_db_cb=on_database};
    status=bleRegisterGattClient(session,&gatt_callbacks);printf("gattRegister=%d\n",status);if(status)return 11;
    status=bleConnect(session,&connection,&address,ACE_BT_BLE_CONN_PARAM_HIGH,
                      ACEBT_BLE_GATT_CLIENT_ROLE,ACE_BT_BLE_CONN_PRIO_MEDIUM);
    printf("connect=%d\n",status);if(status)return 12;
    status_t (*request_mtu)(bleConnHandle,int)=dlsym(lib,"aceBT_bleRequestMtu");
    if(request_mtu)printf("requestMtu=%d\n",request_mtu(connection,247));
    sleep(2);
    status=bleDiscoverAllServices(session,connection);printf("discoverServices=%d\n",status);if(status)return 13;
    sleep(2);
    bleGattsService_t *db=NULL;uint32_t count=0;
    status=bleGetDatabase(connection,&db,&count);
    if(!count)count=discovered_services;
    printf("gattDatabase=%d services=%u\n",status,count);if(status)return 14;
    struct aceBT_gattCharRec_t *info=characteristic(db,count,1),*control=characteristic(db,count,2),*data=characteristic(db,count,3),
        *command=characteristic(db,count,4);
    if(!info||!control||!data||!command)return 15;
    uint8_t reset=0;
    status=write_value(&control->value,&reset,1);if(status)return 16;
    status=read_value(info->value);if(status||received_size!=16){printf("challenge=%d bytes=%zu\n",status,received_size);return 16;}
    uint8_t message[35];
    memcpy(message,"kindle-desk-auth-v2",19);memcpy(message+19,received,16);
    if(mac256(key_bytes,message,sizeof(message),auth+1))return 16;
    memcpy(message,"kindle-desk-data-v2",19);
    if(mac256(key_bytes,message,sizeof(message),session_key))return 16;
    memset(key_bytes,0,sizeof(key_bytes));
    status=write_value(&control->value,auth,sizeof(auth));printf("authenticate=%d\n",status);if(status)return 16;
    status=bleSetNotification(session,connection,data->value,true);
    printf("subscribe=%d\n",status);if(status)return 16;
    sleep(1);
    alarm(0);
    do {
        alarm(120);
        status=send_device_state(&control->value);
        if(!status)status=device_command(command->value,&control->value);
        if(!status&&access("/mnt/us/kindle-desk/native-settings",F_OK))
            status=transfer(&control->value,info->value,data->value);
        printf("transfer=%d\n",status);fflush(stdout);
        alarm(0);
        if(status)break;
        if(argc>1&&!strcmp(argv[1],"--once"))break;
        sleep(1);
    } while(1);
    bleDisconnect(connection);closeSession(session);
    return status?17:0;
}
