/* np2run.c — minimal headless libretro driver for np2kai.
 *
 * Boots a PC-98 disk image (.hdm/.fdd) on np2kai_libretro.dylib, runs a
 * fixed number of emulated frames, then dumps the text-VRAM layer
 * (physical 0xA0000, 80x25, even bytes = character) so an agent can read
 * benchmark output (e.g. CPUBENCH's "Ratio to the first PC9801").
 *
 * Usage:
 *   ./np2run <frames> <image.hdm> [-sysdir DIR] [-dump FILE] [-poll N]
 *                                  [-mark STR] [-beef ADDR] [-shot FILE.ppm]
 *
 *     <frames>     emulated frames (~fps each; see av_info, usually 60)
 *     <image.hdm>  passed to retro_load_game -> mounted as FDD
 *     -sysdir DIR  libretro system dir (needs DIR/np2kai/{bios,itf,font}.rom)
 *                  default: "."
 *     -dump FILE   after the run, write raw SYSTEM_RAM to FILE
 *     -poll N      dump the 80x25 text screen every N frames (0=only end)
 *     -mark STR    stop early once STR appears on the text screen
 *     -shot FILE   save the final video frame as a binary PPM (P6)
 *     -beef ADDR   poll bench.asm mailbox at ADDR, print records, stop
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

static const char *shotfile;              /* -shot FILE: save last frame as PPM */
static uint8_t    *shot_fb;
static unsigned    shot_w, shot_h, shot_pitch;

static void write_shot(const char *path);
static long frame_ctr;
static const char *shotdir;
static long shot_every = 60;
static long shot_from = 0;
static long shot_to = 1000000000L;
static long poke_frame[8];
static unsigned poke_addr[8], poke_val[8];
static int npoke = 0, poke_done[8] = {0};

/* NP2WATCH="physaddr:value": start saving every frame once that 16-bit cell
 * equals value.  A small ring keeps the frames just before the trigger, so a
 * one-frame event is never missed.  NP2WATCHPRE / NP2WATCHPOST tune the
 * window (defaults 12 / 240).  Uses NP2SHOTDIR. */
static uint8_t *g_ram;
static long watch_addr = -1;
static unsigned watch_val;
static long watch_post = 240;
static int watch_pre = 12, watch_armed = 1, watch_hit = 0;
static long watch_hit_frame;
static long watch_dump_delta = -1;
static int watch_dump_done = 0;
static const char *watch_dump_prefix;
#define RING_MAX 32
static uint8_t *ring[RING_MAX];
static long ring_frame[RING_MAX];
static int ring_n = 0, ring_pos = 0;

static void ring_dump(void) {
    if (!shot_fb) return;
    uint8_t *cur = malloc((size_t)shot_h * shot_pitch);
    if (!cur) return;
    memcpy(cur, shot_fb, (size_t)shot_h * shot_pitch);
    for (int i = 0; i < ring_n; i++) {
        int idx = (ring_pos - ring_n + i + RING_MAX) % RING_MAX;
        if (!ring[idx]) continue;
        memcpy(shot_fb, ring[idx], (size_t)shot_h * shot_pitch);
        char path[512];
        snprintf(path, sizeof path, "%s/f%05ld.ppm", shotdir, ring_frame[idx]);
        write_shot(path);
    }
    memcpy(shot_fb, cur, (size_t)shot_h * shot_pitch);
    free(cur);
}

static void video_cb(const void *data, unsigned w, unsigned h, size_t pitch) {
    frame_ctr++;
    if (!shotfile || !data || !w || !h) return;
    if (w != shot_w || h != shot_h || pitch != shot_pitch) {
        free(shot_fb);
        shot_fb = malloc((size_t)h * pitch);
        shot_w = w; shot_h = h; shot_pitch = pitch;
        for (int i = 0; i < RING_MAX; i++) { free(ring[i]); ring[i] = NULL; }
        ring_n = ring_pos = 0;
    }
    if (shot_fb) memcpy(shot_fb, data, (size_t)h * pitch);
    if (watch_addr >= 0 && g_ram && shotdir) {
        unsigned v = g_ram[watch_addr] | (g_ram[watch_addr + 1] << 8);
        if (watch_armed && v == watch_val) {
            watch_armed = 0;
            watch_hit = 1;
            watch_hit_frame = frame_ctr;
            fprintf(stderr, "[np2run] watch hit f=%ld val=%#x\n", frame_ctr, v);
            ring_dump();
            if (shot_fb) {
                char path[512];
                snprintf(path, sizeof path, "%s/f%05ld.ppm", shotdir, frame_ctr);
                write_shot(path);
            }
        } else if (watch_armed && shot_fb) {
            int idx = ring_pos;
            size_t sz = (size_t)shot_h * shot_pitch;
            if (!ring[idx]) ring[idx] = malloc(sz);
            if (ring[idx]) memcpy(ring[idx], data, sz);
            ring_frame[idx] = frame_ctr;
            ring_pos = (ring_pos + 1) % RING_MAX;
            if (ring_n < RING_MAX) ring_n++;
        }
    }
    int in_ring_window = watch_hit && frame_ctr > watch_hit_frame &&
                         frame_ctr <= watch_hit_frame + watch_post;
    if (shotdir && shot_fb && watch_hit && in_ring_window) {
        char path[512];
        snprintf(path, sizeof path, "%s/f%05ld.ppm", shotdir, frame_ctr);
        write_shot(path);
    } else if (shotdir && shot_fb && frame_ctr >= shot_from && frame_ctr <= shot_to &&
        frame_ctr % shot_every == 0) {
        char path[512];
        snprintf(path, sizeof path, "%s/f%05ld.ppm", shotdir, frame_ctr);
        write_shot(path);
    }
}

/* Write the latest frame as a binary PPM (P6). The core delivers RGB565 or
 * XRGB8888 depending on the negotiated pixfmt; expand both to RGB888. */
static void write_shot(const char *path) {
    if (!shot_fb) { fprintf(stderr, "[np2run] -shot: no frame seen\n"); return; }
    FILE *fp = fopen(path, "wb");
    if (!fp) { perror("shot"); return; }
    fprintf(fp, "P6\n%u %u\n255\n", shot_w, shot_h);
    int bpp = (pixfmt == RETRO_PIXEL_FORMAT_XRGB8888) ? 4 : 2;
    for (unsigned y = 0; y < shot_h; y++) {
        const uint8_t *row = shot_fb + (size_t)y * shot_pitch;
        for (unsigned x = 0; x < shot_w; x++) {
            uint8_t rgb[3];
            if (bpp == 4) {
                rgb[0] = row[x*4+2]; rgb[1] = row[x*4+1]; rgb[2] = row[x*4];
            } else {
                uint16_t v = row[x*2] | (row[x*2+1] << 8);
                rgb[0] = ((v >> 11) & 0x1F) * 255 / 31;
                rgb[1] = ((v >>  5) & 0x3F) * 255 / 63;
                rgb[2] = ( v        & 0x1F) * 255 / 31;
            }
            fwrite(rgb, 1, 3, fp);
        }
    }
    fclose(fp);
    fprintf(stderr, "[np2run] frame -> %s (%ux%d)\n", path, shot_w, shot_h);
}
static void audio_cb(int16_t l, int16_t r) { (void)l; (void)r; }
static size_t audio_batch_cb(const int16_t *d, size_t frames) { (void)d; return frames; }
static void input_poll_cb(void) {}

/* -keys "frame:retrok,..." holds a keyboard key for 3 frames. RETRO_DEVICE_KEYBOARD
 * is dev 3; np2kai routes RETROK_* into the PC-98 matrix. */
#define KEY_MAX 32
static struct { long frame; int key; } keys[KEY_MAX];
static int  nkeys;
static void parse_keys(const char *spec) {
    const char *p = spec;
    while (*p && nkeys < KEY_MAX) {
        keys[nkeys].frame = strtol(p, (char**)&p, 10);
        if (*p == ':') p++;
        keys[nkeys].key = (int)strtol(p, (char**)&p, 10);
        nkeys++;
        if (*p == ',') p++;
    }
    fprintf(stderr, "[np2run] %d key events\n", nkeys);
}
static int16_t input_state_cb(unsigned port, unsigned dev, unsigned idx, unsigned id) {
    (void)port; (void)idx;
    if (dev == 3) {                      /* RETRO_DEVICE_KEYBOARD */
        for (int i = 0; i < nkeys; i++)
            if ((int)id == keys[i].key &&
                frame_ctr >= keys[i].frame && frame_ctr < keys[i].frame + 3)
                return 1;
    }
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
    long beef_addr = -1; /* mailbox sentinel address, e.g. 0x70000 */

    if (argc < 3) {
        fprintf(stderr, "usage: %s <frames> <image.hdm> [-sysdir D] [-lib P] [-dump F] [-poll N] [-mark STR] [-beef ADDR] [-shot F.ppm]\n", argv[0]);
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
        else if (!strcmp(argv[i], "-beef")) beef_addr = strtol(argv[i+1], NULL, 0);
        else if (!strcmp(argv[i], "-shot")) shotfile = argv[i+1];
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

    { const char *ks = getenv("NP2KEYS"); if (ks) parse_keys(ks);
      const char *sd = getenv("NP2SHOTDIR"); if (sd) { shotdir = sd; const char *se = getenv("NP2SHOTEVERY"); if (se) shot_every = atol(se); if (shot_every < 1) shot_every = 1; }
      { const char *sf = getenv("NP2SHOTFROM"); if (sf) shot_from = atol(sf);
        const char *st = getenv("NP2SHOTTO"); if (st) shot_to = atol(st); }
      { const char *pk = getenv("NP2POKE");
        if (pk) { const char *p = pk;
          while (*p && npoke < 8) {
            long f = strtol(p, (char**)&p, 0); if (*p != ':') break; p++;
            unsigned a = (unsigned)strtoul(p, (char**)&p, 0); if (*p != ':') break; p++;
            unsigned v = (unsigned)strtoul(p, (char**)&p, 0);
            poke_frame[npoke]=f; poke_addr[npoke]=a; poke_val[npoke]=v; npoke++;
            if (*p == ',') p++;
          }
        } }
      { const char *wt = getenv("NP2WATCH");
        if (wt) {
          char *end; watch_addr = strtol(wt, &end, 0);
          if (*end == ':') watch_val = (unsigned)strtoul(end + 1, NULL, 0);
          else watch_addr = -1;
          const char *wp = getenv("NP2WATCHPRE"); if (wp) watch_pre = atoi(wp);
          const char *wq = getenv("NP2WATCHPOST"); if (wq) watch_post = atol(wq);
          if (watch_pre < 0) watch_pre = 0; if (watch_pre > RING_MAX) watch_pre = RING_MAX;
          const char *wd = getenv("NP2WATCHDUMP");
          if (wd) { watch_dump_delta = atol(wd); watch_dump_prefix = getenv("NP2DUMPPREFIX"); }
          shot_from = 0; shot_to = -1;   /* periodic shots off; watch drives them */
          fprintf(stderr, "[np2run] watch %#lx==%#x pre=%d post=%ld\n",
                  watch_addr, watch_val, watch_pre, watch_post);
        } }
      if (shotdir) shotfile = "-"; }
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
    g_ram = ramp;

    char scr[25][81];
    /* NP2DUMPAT="f1,f2,..." NP2DUMPPREFIX=path: in-run RAM snapshots, so two
     * states of the same deterministic run can be diffed without run-to-run
     * RNG noise (the game seeds from the PIT counter). */
    const char *dumpat = getenv("NP2DUMPAT");
    const char *dumppfx = getenv("NP2DUMPPREFIX");
    int found = 0;
    for (long f = 0; f <= frames; f++) {
        r_run();
        for (int pi = 0; pi < npoke; pi++)
            if (!poke_done[pi] && frame_ctr >= poke_frame[pi] && ramp) {
                ramp[poke_addr[pi]] = poke_val[pi] & 0xff;
                ramp[poke_addr[pi]+1] = (poke_val[pi] >> 8) & 0xff;
                poke_done[pi] = 1;
                fprintf(stderr, "[np2run] poke f=%ld addr=%#x val=%#x\n",
                        frame_ctr, poke_addr[pi], poke_val[pi]);
            }
        if (watch_hit && !watch_dump_done && watch_dump_delta >= 0 && ramp &&
            watch_dump_prefix && frame_ctr >= watch_hit_frame + watch_dump_delta) {
            char path[512];
            snprintf(path, sizeof path, "%s_w.bin", watch_dump_prefix);
            FILE *fw = fopen(path, "wb");
            if (fw) { fwrite(ramp, 1, 0x200000, fw); fclose(fw);
                      fprintf(stderr, "[np2run] watch dump f=%ld -> %s\n", frame_ctr, path); }
            watch_dump_done = 1;
        }
        if (f == 0) continue; /* first run just does pre_main */
        if (dumpat && ramp && dumppfx) {
            const char *p = dumpat;
            while (*p) {
                long at = strtol(p, (char **)&p, 10);
                while (*p == ',') p++;
                if (at == f) {
                    char path[512];
                    snprintf(path, sizeof path, "%s_%ld.bin", dumppfx, f);
                    FILE *fp2 = fopen(path, "wb");
                    if (fp2) { fwrite(ramp, 1, 0x200000, fp2); fclose(fp2); }
                    fprintf(stderr, "[np2run] in-run dump %ld -> %s\n", f, path);
                }
            }
        }
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
        /* bench.asm mailbox: word0=0xBEEF sentinel, word1=count, then
         * records {id, tick_lo, tick_hi, units_lo, units_hi} 5 words each. */
        if (ramp && beef_addr >= 0 &&
            ramp[beef_addr] == 0xEF && ramp[beef_addr+1] == 0xBE) {
            int n = ramp[beef_addr+2] | (ramp[beef_addr+3] << 8);
            fprintf(stderr, "[np2run] mailbox sentinel at frame %ld, %d records\n", f, n);
            for (int i = 0; i < n && i < 60; i++) {
                uint8_t *p = ramp + beef_addr + 4 + i*10;
                uint16_t id   = p[0] | p[1]<<8;
                uint32_t tick = p[2] | p[3]<<8 | ((uint32_t)(p[4]|p[5]<<8))<<16;
                uint32_t unit = p[6] | p[7]<<8 | ((uint32_t)(p[8]|p[9]<<8))<<16;
                printf("MBX %02u ticks=%u units=%u\n", id, tick, unit);
            }
            found = 1;
            break;
        }
    }

    /* final screen */
    if (ramp) { dump_screen(ramp, scr); print_screen(scr); }
    if (dumpfile && ramp) {
        FILE *fp = fopen(dumpfile, "wb");
        if (fp) { fwrite(ramp, 1, 0x200000, fp); fclose(fp); }
        fprintf(stderr, "[np2run] dumped 2MB -> %s\n", dumpfile);
    }
    if (shotfile) write_shot(shotfile);
    r_unload_game();
    r_deinit();
    return found ? 0 : 0;
}
