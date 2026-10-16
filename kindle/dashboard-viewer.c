/* A real X application: native Kindle dialogs remain above the dashboard.
 * GTK2 is supplied by the device. Resolve its public C ABI at runtime so we
 * neither bundle proprietary libraries nor depend on a device SDK's headers.
 */
#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <time.h>
#include <stdint.h>

typedef void *Ptr;
#define API(ret, name, args) static ret (*name) args
API(int, gtk_init_check, (int *, char ***));
API(Ptr, gtk_window_new, (int));
API(void, gtk_window_set_title, (Ptr, const char *));
API(void, gtk_window_set_default_size, (Ptr, int, int));
API(void, gtk_window_set_decorated, (Ptr, int));
API(Ptr, gtk_event_box_new, (void));
API(Ptr, gtk_image_new, (void));
API(void, gtk_image_set_from_pixbuf, (Ptr, Ptr));
API(void, gtk_container_add, (Ptr, Ptr));
API(void, gtk_widget_add_events, (Ptr, int));
API(void, gtk_widget_show_all, (Ptr));
API(void, gtk_widget_queue_draw, (Ptr));
API(void, gtk_main, (void));
API(void, gtk_main_quit, (void));
API(unsigned long, g_signal_connect_data, (Ptr, const char *, void (*)(void), Ptr, Ptr, int));
API(unsigned int, g_timeout_add, (unsigned int, int (*)(Ptr), Ptr));
API(void, g_object_unref, (Ptr));
API(Ptr, gdk_pixbuf_new_from_file, (const char *, Ptr));
API(int, gdk_pixbuf_get_width, (Ptr));
API(int, gdk_pixbuf_get_height, (Ptr));
API(int, gdk_event_get_root_coords, (Ptr, double *, double *));
API(unsigned int, gdk_event_get_time, (Ptr));
API(Ptr, gdk_display_get_default, (void));
API(void, gdk_display_sync, (Ptr));
API(void, gdk_window_process_all_updates, (void));

static Ptr image, window;
API(void, gtk_widget_hide, (Ptr));
API(Ptr, gdk_x11_display_get_xdisplay, (Ptr));
API(int, XGetInputFocus, (Ptr, unsigned long *, int *));
API(int, XFetchName, (Ptr, unsigned long, char **));
API(int, XQueryTree, (Ptr, unsigned long, unsigned long *, unsigned long *, unsigned long **, unsigned int *));
API(int, XFree, (Ptr));
static volatile sig_atomic_t exiting;
static double down_x, down_y;
static unsigned int down_time;
static int touching;
static char revision[32], pending[32];
static const char *local;
static unsigned int open_count;

static void local_path(char *out, size_t size, const char *name) {
    snprintf(out, size, "%s/%s", local, name);
}
static int exists(const char *name) {
    char path[512]; local_path(path, sizeof(path), name);
    return access(path, F_OK) == 0;
}
static void stop_signal(int sig) { (void)sig; exiting = 1; }
static int no_delete(Ptr w, Ptr e, Ptr data) {
    (void)w; (void)e; (void)data; return 1;
}
static int press(Ptr w, Ptr event, Ptr data) {
    (void)w; (void)data;
    touching = gdk_event_get_root_coords(event, &down_x, &down_y);
    down_time = gdk_event_get_time(event);
    return 1;
}
static int release(Ptr w, Ptr event, Ptr data) {
    (void)w; (void)data;
    double x, y;
    if (touching && gdk_event_get_root_coords(event, &x, &y)
        && down_y <= 120 && y - down_y >= 120
        && x - down_x < 300 && down_x - x < 300
        && gdk_event_get_time(event) - down_time < 1800) {
        pid_t child = fork();
        if (child == 0) {
            execlp("lipc-set-prop", "lipc-set-prop", "com.lab126.kppchromebar",
                   "configurePillState", "openedBySwipe", (char *)NULL);
            _exit(127);
        }
        if (child > 0) {
            ++open_count;
            fprintf(stderr, "native quick settings requested (%u)\n", open_count);
            fflush(stderr);
        }
    }
    touching = 0;
    return 1;
}
static int read_revision(char *out) {
    FILE *file = fopen("frame.ready", "r");
    if (!file) return 0;
    int ok = fscanf(file, "%31s", out) == 1;
    fclose(file);
    return ok && strlen(out) == 16 && strspn(out, "0123456789abcdef") == 16;
}
static int load_frame(void) {
    Ptr pixbuf = gdk_pixbuf_new_from_file("frame.png", NULL);
    if (!pixbuf) return 0;
    int ok = gdk_pixbuf_get_width(pixbuf) == 1236 && gdk_pixbuf_get_height(pixbuf) == 1648;
    if (ok) gtk_image_set_from_pixbuf(image, pixbuf);
    g_object_unref(pixbuf);
    return ok;
}
/* Walk from GTK's focused child to its named application window. */
static int focus_kind(void) {
    Ptr display = gdk_x11_display_get_xdisplay(gdk_display_get_default());
    unsigned long current; int revert;
    XGetInputFocus(display, &current, &revert);
    for (int depth=0; depth<8 && current>1; ++depth) {
        char *name=NULL; int kind=0;
        if (XFetchName(display, current, &name) && name) {
            if (strstr(name, "ID:uk.felixf.kindledesk")) kind=1;
            else if (strstr(name, "L:A_") &&
                     (strstr(name, "ID:com.lab126.KPPMainApp_") ||
                      strstr(name, "ID:com.lab126.booklet.home_"))) kind=2;
            else if (*name) kind=3;
            XFree(name);
        }
        if (kind) return kind;
        unsigned long root, parent, *children=NULL; unsigned count=0;
        if (!XQueryTree(display,current,&root,&parent,&children,&count)) break;
        if (children) XFree(children);
        if (current==root) break;
        current=parent;
    }
    return 0;
}
static int tick(Ptr data) {
    (void)data;
    if (exiting || exists("viewer.quit")) { gtk_main_quit(); return 0; }
    int focus = focus_kind();
    if (focus == 2) {
        gtk_widget_hide(window);
        gtk_widget_show_all(window);
        fprintf(stderr, "restored dashboard above native home\n");
    }
    /* Only acknowledge after GTK's paint has run, followed by an X sync. */
    if (*pending && focus == 1) {
        gdk_window_process_all_updates();
        gdk_display_sync(gdk_display_get_default());
        FILE *file = fopen("frame.displayed.tmp", "w");
        if (file) {
            fprintf(file, "%s\n", pending);
            if (fclose(file) == 0 && rename("frame.displayed.tmp", "frame.displayed") == 0)
                strcpy(revision, pending);
        }
        *pending = 0;
    }
    char next[32];
    if (!*pending && read_revision(next) && strcmp(next, revision) && load_frame()) {
        strcpy(pending, next);
        gtk_widget_queue_draw(image);
    }
    return 1;
}
int main(int argc, char **argv) {
    local = getenv("KINDLE_DESK_LOCAL");
    if (!local) local = "/tmp/kindle-desk-ui";
    if (argc != 2 || chdir(argv[1])) return 2;
    void *gtk = dlopen("libgtk-x11-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!gtk) { fprintf(stderr, "%s\n", dlerror()); return 3; }
#define LOAD(name) do { *(void **)(&name) = dlsym(gtk, #name); if (!name) { fprintf(stderr, "missing %s\n", #name); return 3; } } while (0)
    LOAD(gtk_widget_hide); LOAD(gdk_x11_display_get_xdisplay);
    LOAD(XGetInputFocus); LOAD(XFetchName); LOAD(XQueryTree); LOAD(XFree);
    LOAD(gtk_init_check); LOAD(gtk_window_new); LOAD(gtk_window_set_title);
    LOAD(gtk_window_set_default_size); LOAD(gtk_window_set_decorated);
    LOAD(gtk_event_box_new); LOAD(gtk_image_new); LOAD(gtk_image_set_from_pixbuf);
    LOAD(gtk_container_add); LOAD(gtk_widget_add_events); LOAD(gtk_widget_show_all);
    LOAD(gtk_widget_queue_draw); LOAD(gtk_main); LOAD(gtk_main_quit);
    LOAD(g_signal_connect_data); LOAD(g_timeout_add); LOAD(g_object_unref);
    LOAD(gdk_pixbuf_new_from_file); LOAD(gdk_pixbuf_get_width); LOAD(gdk_pixbuf_get_height);
    LOAD(gdk_event_get_root_coords); LOAD(gdk_event_get_time);
    LOAD(gdk_display_get_default); LOAD(gdk_display_sync); LOAD(gdk_window_process_all_updates);
    if (!getenv("DISPLAY")) setenv("DISPLAY", ":0", 1);
    if (!gtk_init_check(&argc, &argv)) return 4;
    image = gtk_image_new();
    if (!load_frame()) { fprintf(stderr, "invalid cached portrait frame\n"); return 5; }
    window = gtk_window_new(0);
    Ptr events = gtk_event_box_new();
    gtk_window_set_title(window, "L:A_N:application_ID:uk.felixf.kindledesk_PC:N_O:U");
    gtk_window_set_default_size(window, 1236, 1648);
    gtk_window_set_decorated(window, 0);
    gtk_container_add(events, image);
    gtk_container_add(window, events);
    gtk_widget_add_events(events, (1 << 8) | (1 << 9));
    g_signal_connect_data(events, "button-press-event", (void (*)(void))press, NULL, NULL, 0);
    g_signal_connect_data(events, "button-release-event", (void (*)(void))release, NULL, NULL, 0);
    g_signal_connect_data(window, "delete-event", (void (*)(void))no_delete, NULL, NULL, 0);
    signal(SIGTERM, stop_signal); signal(SIGINT, stop_signal); signal(SIGCHLD, SIG_IGN);
    gtk_widget_show_all(window);
    gdk_window_process_all_updates();
    gdk_display_sync(gdk_display_get_default());
    char path[512]; local_path(path, sizeof(path), "viewer.ready");
    FILE *file = fopen(path, "w");
    if (!file) return 6;
    fprintf(file, "%ld\n", (long)getpid()); fclose(file);
    g_timeout_add(500, tick, NULL);
    gtk_main();
    unlink(path);
    return 0;
}
