/* Minimal public OpenSSL 1.0.2 EVP/HMAC ABI; implementation stays on the device. */
typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;
typedef struct evp_cipher_st EVP_CIPHER;
typedef struct evp_md_st EVP_MD;
extern EVP_CIPHER_CTX *EVP_CIPHER_CTX_new(void);
extern void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX *);
extern const EVP_CIPHER *EVP_aes_256_gcm(void);
extern const EVP_MD *EVP_sha256(void);
extern int EVP_DecryptInit_ex(EVP_CIPHER_CTX *, const EVP_CIPHER *, void *, const unsigned char *, const unsigned char *);
extern int EVP_DecryptUpdate(EVP_CIPHER_CTX *, unsigned char *, int *, const unsigned char *, int);
extern int EVP_DecryptFinal_ex(EVP_CIPHER_CTX *, unsigned char *, int *);
extern int EVP_CIPHER_CTX_ctrl(EVP_CIPHER_CTX *, int, int, void *);
extern unsigned char *HMAC(const EVP_MD *, const void *, int, const unsigned char *, size_t, unsigned char *, unsigned int *);

static unsigned char session_key[32];
static int mac256(const unsigned char *key, const void *data, size_t size, unsigned char *out) {
    unsigned int length=0;
    return HMAC(EVP_sha256(),key,32,data,size,out,&length)&&length==32?0:-1;
}

static int decrypt_frame(int length) {
    if(length<36)return -1;
    unsigned char *cipher=malloc(length),*plain=malloc(length);
    if(!cipher||!plain){free(cipher);free(plain);return -1;}
    FILE *f=fopen("/mnt/us/kindle-desk/frame.part","rb");
    int ok=f&&fread(cipher,1,length,f)==(size_t)length;
    if(f)fclose(f);
    EVP_CIPHER_CTX *ctx=EVP_CIPHER_CTX_new();int n=0,end=0;
    ok=ok&&ctx&&EVP_DecryptInit_ex(ctx,EVP_aes_256_gcm(),NULL,NULL,NULL)==1
      &&EVP_CIPHER_CTX_ctrl(ctx,0x9,12,NULL)==1
      &&EVP_DecryptInit_ex(ctx,NULL,NULL,session_key,cipher)==1
      &&EVP_DecryptUpdate(ctx,plain,&n,cipher+12,length-28)==1
      &&EVP_CIPHER_CTX_ctrl(ctx,0x11,16,cipher+length-16)==1
      &&EVP_DecryptFinal_ex(ctx,plain+n,&end)==1;
    if(ctx)EVP_CIPHER_CTX_free(ctx);
    if(ok){
        f=fopen("/mnt/us/kindle-desk/frame.part","wb");
        ok=f&&fwrite(plain,1,n+end,f)==(size_t)(n+end);
        if(f&&fclose(f))ok=0;
    }
    free(cipher);free(plain);return ok?0:-1;
}
