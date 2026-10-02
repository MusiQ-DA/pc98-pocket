/* np2run.c — minimal headless libretro driver for np2kai.
 *
 * Boots a PC-98 disk image (.hdm/.fdd) on np2kai_libretro.dylib, runs a
 * fixed number of emulated frames, then dumps the text-VRAM layer
 * (physical 0xA0000, 80x25, even bytes = character) so an agent can read
 * benchmark output (e.g. CPUBENCH's "Ratio to the first PC9801").
 *
 * Usage:
 *   ./np2run <frames> <image.hdm> [-sysdir DIR] [-dump FILE] [-poll N]
 *
 *     <frames>     emulated frames (~fps each; see av_info, usually 60)
 *     <image.hdm>  passed to retro_load_game -> mounted as FDD
 *     -sysdir DIR  libretro system dir (needs DIR/np2kai/{bios,itf,font}.rom)
 *                  default: "."
 *     -dump FILE   after the run, write raw SYSTEM_RAM to FILE
 *     -poll N      dump the 80x25 text screen every N frames (0=only end)
 *     -mark STR    stop early once STR appears on the text screen
 *
 * Build:
 *   cc -O2 -o np2run np2run.c -ldl
 *
 * The dylib next to the binary (or -lib PATH). ROM layout per
 * docs/NP2KAI_HARNESS.md.  Remove <sysdir>/np2kai/np2kai.cfg or stale
 * config overrides the model/dipsw answers below.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <dlfcn.h>

/* ---- libretro decls (subset) ---- */
#define RETRO_API_VERSION 1
#define RETRO_DEVICE_NONE 0
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT        10
#define RETRO_ENVIRONMENT_GET_VARIABLE            15
#define RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE     17
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE       27
#define RETRO_ENVIRONMENT_GET_CAN_DUPE            14
#define RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS   11
#define RETRO_ENVIRONMENT_SET_DISK_CONTROL_IFACE  13
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY    9
#define RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME     18
#define RETRO_ENVIRONMENT_GET_PERF_INTERFACE      28
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS        16
#define RETRO_MEMORY_SYSTEM_RAM                   0

#define RETRO_PIXEL_FORMAT_0RGB1555 0
#define RETRO_PIXEL_FORMAT_XRGB8888 1
#define RETRO_PIXEL_FORMAT_RGB565   2

struct retro_variable { const char *key; const char *value; };
struct retro_game_info { const char *path; const void *data; size_t size; const char *meta; };
struct retro_system_av_info {
    struct { int width, height; int max_width, max_height; float aspect_ratio; } geometry;
    struct { double fps, sample_rate; } timing;
};
struct retro_log_callback { void (*log)(int level, const char *fmt, ...); };

static int    (*r_init)(void);
static void   (*r_deinit)(void);
static void   (*r_set_environment)(void*);
static void   (*r_set_video_refresh)(void*);
static void   (*r_set_audio_sample)(void*);
static void   (*r_set_audio_sample_batch)(void*);
static void   (*r_set_input_poll)(void*);
static void   (*r_set_input_state)(void*);
static void   (*r_get_system_av_info)(struct retro_system_av_info*);
static void   (*r_set_controller_port_device)(unsigned, unsigned);
static void   (*r_reset)(void);
static void   (*r_run)(void);
static bool   (*r_load_game)(const struct retro_game_info*);
static void   (*r_unload_game)(void);
static void*  (*r_get_memory_data)(unsigned);
static size_t (*r_get_memory_size)(unsigned);

static const char *sysdir = ".";
static int pixfmt = RETRO_PIXEL_FORMAT_XRGB8888;

static const char *var_lookup(const char *key) {
    if (!strcmp(key, "np2kai_model"))        return "PC-9801VM";
    if (!strcmp(key, "np2kai_clk_base"))     return "2.4576 MHz";
    { const char *m = getenv("NP2_CLK_MULT");
      if (!strcmp(key, "np2kai_clk_mult"))  return m ? m : "4"; }
    if (!strcmp(key, "np2kai_keyboard"))     return "Reset";
    if (!strcmp(key, "np2kai_FastMC"))       return "ON";
    return NULL;
}

static void logcb(int level, const char *fmt, ...) {
    (void)level;
    va_list ap; va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

static bool env_cb(unsigned cmd, void *data) {
    switch (cmd) {
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        *(const char**)data = sysdir;
        return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        struct retro_variable *v = data;
        v->value = var_lookup(v->key);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        int f = *(const int*)data;
        if (f == RETRO_PIXEL_FORMAT_XRGB8888 || f == RETRO_PIXEL_FORMAT_RGB565) {
            pixfmt = f;
            return true;
        }
        return false;
    }
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
        struct retro_log_callback *l = data;
        l->log = logcb;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        *(bool*)data = false;
        return true;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        *(bool*)data = true;
        return true;
    case RETRO_ENVIRONMENT_SET_DISK_CONTROL_IFACE:
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
        return true;
    default:
        return false;
    }
}

static void video_cb(const void *data, unsigned w, unsigned h, size_t pitch) {
    (void)data; (void)w; (void)h; (void)pitch;
}
static void audio_cb(int16_t l, int16_t r) { (void)l; (void)r; }
static size_t audio_batch_cb(const int16_t *d, size_t frames) { (void)d; return frames; }
static void input_poll_cb(void) {}
static int16_t input_state_cb(unsigned port, unsigned dev, unsigned idx, unsigned id) {
    (void)port; (void)dev; (void)idx; (void)id;
    return 0;
}

/* PC-98 text VRAM: 80x25 cells, word = {code, attr} at phys 0xA0000. */
static void dump_screen(uint8_t *ram, char out[25][81]) {
    for (int row = 0; row < 25; row++) {
        for (int col = 0; col < 80; col++) {
            uint8_t c = ram[0xA0000 + (row * 80 + col) * 2];
            out[row][col] = (c >= 0x20 && c < 0x7F) ? (char)c : ' ';
        }
        out[row][80] = 0;
        /* strip trailing spaces */
        for (int i = 79; i >= 0 && out[row][i] == ' '; i--) out[row][i] = 0;
    }
}

static void print_screen(char scr[25][81]) {
    fputs("-------- screen --------\n", stdout);
    for (int i = 0; i < 25; i++) printf("%s\n", scr[i]);
    fputs("------------------------\n", stdout);
}

int main(int argc, char **argv) {
    setbuf(stdout, NULL); /* np2kai's deinit may exit() early — keep stdout unbuffered */
    const char *libpath = "./np2kai_libretro.dylib";
    const char *image = NULL;
    const char *dumpfile = NULL;
    const char *mark = NULL;
    long frames = 0;
    int poll_n = 0;

    if (argc < 3) {
        fprintf(stderr, "usage: %s <frames> <image.hdm> [-sysdir D] [-lib P] [-dump F] [-poll N] [-mark STR]\n", argv[0]);
        return 2;
    }
    frames = atol(argv[1]);
    image = argv[2];
    for (int i = 3; i + 1 < argc; i += 2) {
        if (!strcmp(argv[i], "-sysdir")) sysdir = argv[i+1];
        else if (!strcmp(argv[i], "-lib")) libpath = argv[i+1];
        else if (!strcmp(argv[i], "-dump")) dumpfile = argv[i+1];
        else if (!strcmp(argv[i], "-poll")) poll_n = atoi(argv[i+1]);
        else if (!strcmp(argv[i], "-mark")) mark = argv[i+1];
    }

    void *dl = dlopen(libpath, RTLD_NOW | RTLD_LOCAL);
    if (!dl) { fprintf(stderr, "dlopen %s: %s\n", libpath, dlerror()); return 1; }
#define SYM(n) do { *(void**)(&r_##n) = dlsym(dl, "retro_" #n); \
        if (!r_##n) { fprintf(stderr, "missing retro_" #n "\n"); return 1; } } while (0)
    SYM(init); SYM(deinit); SYM(set_environment); SYM(set_video_refresh);
    SYM(set_audio_sample); SYM(set_audio_sample_batch); SYM(set_input_poll);
    SYM(set_input_state); SYM(get_system_av_info); SYM(set_controller_port_device);
    SYM(reset); SYM(run); SYM(load_game); SYM(unload_game);
    SYM(get_memory_data); SYM(get_memory_size);
#undef SYM

    r_set_environment(env_cb);
    r_set_video_refresh(video_cb);
    r_set_audio_sample(audio_cb);
    r_set_audio_sample_batch(audio_batch_cb);
    r_set_input_poll(input_poll_cb);
    r_set_input_state(input_state_cb);

    r_init();

    struct retro_system_av_info av;
    r_get_system_av_info(&av);
    fprintf(stderr, "[np2run] av: %dx%d @%.2ffps pixfmt=%d\n",
            av.geometry.width, av.geometry.height, av.timing.fps, pixfmt);

    struct retro_game_info gi = { image, NULL, 0, NULL };
    if (!r_load_game(&gi)) { fprintf(stderr, "load_game failed\n"); return 1; }

    /* Guest RAM: prefer dlsym("mem") — np2kai's 2MB flat array (includes
     * 0xA0000 TVRAM).  retro_get_memory_data(SYSTEM_RAM) only returns the
     * extended-RAM region (CPU_EXTMEM), which is NULL on 640KB models. */
    uint8_t *ramp = dlsym(dl, "mem");
    if (!ramp) {
        ramp = r_get_memory_data(RETRO_MEMORY_SYSTEM_RAM);
        if (ramp) fprintf(stderr, "[np2run] using SYSTEM_RAM (ext only)\n");
    } else {
        fprintf(stderr, "[np2run] mem symbol @%p\n", ramp);
    }
    if (!ramp) fprintf(stderr, "[np2run] no RAM access\n");

    char scr[25][81];
    int found = 0;
    for (long f = 0; f <= frames; f++) {
        r_run();
        if (f == 0) continue; /* first run just does pre_main */
        int do_dump = (poll_n && (f % poll_n) == 0) || f == frames || mark;
        if (do_dump) {
            uint8_t *ram = ramp;
            if (!ram) break;
            dump_screen(ram, scr);
            if (poll_n && (f % poll_n) == 0) {
                fprintf(stderr, "[np2run] frame %ld (~%.1fs)\n", f, f / av.timing.fps);
                print_screen(scr);
            }
            if (mark) {
                for (int r = 0; r < 25; r++)
                    if (strstr(scr[r], mark)) { found = 1; break; }
                if (found) { fprintf(stderr, "[np2run] mark hit at frame %ld\n", f); break; }
            }
        }
    }

    /* final screen */
    if (ramp) { dump_screen(ramp, scr); print_screen(scr); }
    if (dumpfile && ramp) {
        FILE *fp = fopen(dumpfile, "wb");
        if (fp) { fwrite(ramp, 1, 0x200000, fp); fclose(fp); }
        fprintf(stderr, "[np2run] dumped 2MB -> %s\n", dumpfile);
    }
    r_unload_game();
    r_deinit();
    return found ? 0 : 0;
}
