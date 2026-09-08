#include <stdint.h>
#include "softcpu_regs.h"
#include "vkb_draw.h"
#include "postmon.h"

// post_monitor window (region 0x5, read-only).
#define POST_STATUS ((volatile uint32_t *) 0x50000010) // {count[31:16], prev[15:8], code[7:0]}
#define POST_ADDR   ((volatile uint32_t *) 0x50000014) // last guest memory address
#define POST_HIST_L ((volatile uint32_t *) 0x50000018) // newest four codes
#define POST_HIST_H ((volatile uint32_t *) 0x5000001C) // oldest four
#define POST_MAXRST ((volatile uint32_t *) 0x50000020) // {max[23:16], restarts[15:0]}
#define POST_LIVE   ((volatile uint32_t *) 0x50000024) // live guest memory address
#define POST_LIVEMX ((volatile uint32_t *) 0x50000028) // highest address ever touched

// The self-test master, reused to read guest memory while the guest runs. It
// takes the bus through hold acknowledge, which is what the BIOS loader does.
#define ST_ADDR   ((volatile uint32_t *) 0x50000000)
#define ST_TRIG   ((volatile uint32_t *) 0x50000008)
#define ST_STATUS ((volatile uint32_t *) 0x5000000C)
#define ST_BUSY   (1u << 8)

static uint8_t guest_peek(uint32_t addr)
{
    uint32_t s = 0;
    *ST_ADDR = addr;
    *ST_TRIG = 2u;                       // read
    for (uint32_t i = 0; i < 2000u; i++) {
        s = *ST_STATUS;
        if (!(s & ST_BUSY))
            break;
    }
    return (uint8_t) (s & 0xFFu);
}

// A strip along the top. Everything outside it stays palette 0 (transparent),
// so the guest's picture shows through and this does not hide a working POST.
#define PANEL_X 0
#define PANEL_Y 0
#define PANEL_W 320
#define PANEL_H 68

static const osd_fb_t fb = {0, 0, OSD_FB_WIDTH, OSD_FB_HEIGHT};

static void hex(int x, int y, uint32_t v, int digits)
{
    char buf[9];
    for (int i = digits - 1; i >= 0; i--) {
        uint32_t nib = v & 0xFu;
        buf[i] = (char) (nib < 10 ? '0' + nib : 'A' + (nib - 10));
        v >>= 4;
    }
    buf[digits] = 0;
    osd_draw_string(&fb, x, y, buf, OSD_LABEL);
}

static void dec(int x, int y, uint32_t v)
{
    char buf[11], out[11];
    int n = 0;
    if (v == 0)
        buf[n++] = '0';
    while (v && n < 10) {
        buf[n++] = (char) ('0' + (v % 10u));
        v /= 10u;
    }
    for (int i = 0; i < n; i++)
        out[i] = buf[n - 1 - i];
    out[n] = 0;
    osd_draw_string(&fb, x, y, out, OSD_LABEL);
}

void post_mon_tick(void)
{
    static uint32_t last_status = 0xFFFFFFFFu;
    static int placed = 0;

    // POST_STATUS freezes after the first pass through POST, so this settles;
    // the counters below keep moving and are what show a reboot loop.
    uint32_t status = *POST_STATUS;
    uint32_t maxrst = *POST_MAXRST;
    uint32_t live   = *POST_LIVE;
    static uint32_t last_maxrst = 0xFFFFFFFFu;
    static uint32_t last_live = 0xFFFFFFFFu;
    // LIVE is the point of this build: when the guest stops, it settles on
    // whatever the CPU is spinning in. Redraw whenever it moves.
    // Staleness is judged on the POST COUNT ALONE.
    //
    // It used to include `live`, and live is the guest's last memory address --
    // it changes on every access, so "nothing has changed" was never true and
    // the gate never fired. That is why testB24 showed no vectors, and it is
    // also why I read that run as a reset loop: the symptom was my gate, not
    // the guest.
    static uint32_t idle_ticks = 0;
    uint32_t count_now = status >> 16;
    static uint32_t last_count = 0xFFFFFFFFu;
    if (count_now == last_count) {
        if (idle_ticks < 1000000u) idle_ticks++;
    } else {
        last_count = count_now;
        idle_ticks = 0;
    }
    if (status == last_status && maxrst == last_maxrst && live == last_live
        && idle_ticks != 4000u) {
        return;                            // nothing worth redrawing
    }
    last_status = status;
    last_maxrst = maxrst;
    last_live = live;

    if (!placed) {
        // vkb_ui writes the origin from the presented raster before it raises
        // VKB_CTRL; do the same, or the strip lands somewhere unhelpful.
        uint32_t raster = *OSD_RASTER;
        uint32_t w = raster & 0x3FFu;
        uint32_t h = (raster >> 16) & 0x3FFu;
        uint32_t x = (w > OSD_FB_WIDTH) ? (w - OSD_FB_WIDTH) / 2u : 0u;
        uint32_t y = (h > OSD_FB_HEIGHT) ? (h - OSD_FB_HEIGHT) / 2u : 0u;
        *OSD_ORIGIN = (y << 16) | x;
        placed = 1;
    }

    // OSD_LABEL is near black, so it needs a light panel behind it to be read
    // at all -- testB13 drew label text over the picture and was invisible.
    osd_fill_rect(&fb, PANEL_X, PANEL_Y, PANEL_W, PANEL_H, OSD_KEYFACE);

    osd_draw_string(&fb, 4, 2, "POST", OSD_LABEL);
    hex(4 + 5 * 8, 2, status & 0xFFu, 2);
    osd_draw_string(&fb, 4 + 8 * 8, 2, "PREV", OSD_LABEL);
    hex(4 + 13 * 8, 2, (status >> 8) & 0xFFu, 2);
    osd_draw_string(&fb, 4 + 16 * 8, 2, "N", OSD_LABEL);
    dec(4 + 18 * 8, 2, status >> 16);

    osd_draw_string(&fb, 4, 12, "ADDR", OSD_LABEL);
    hex(4 + 5 * 8, 12, *POST_ADDR & 0xFFFFFu, 5);

    osd_draw_string(&fb, 4, 22, "MAX", OSD_LABEL);
    hex(4 + 4 * 8, 22, (maxrst >> 16) & 0xFFu, 2);
    osd_draw_string(&fb, 4 + 7 * 8, 22, "RESTARTS", OSD_LABEL);
    dec(4 + 16 * 8, 22, maxrst & 0xFFFFu);

    osd_draw_string(&fb, 4, 32, "LIVE", OSD_LABEL);
    hex(4 + 5 * 8, 32, live & 0xFFFFFu, 5);
    osd_draw_string(&fb, 4 + 12 * 8, 32, "HIGH", OSD_LABEL);
    hex(4 + 17 * 8, 32, *POST_LIVEMX & 0xFFFFFu, 5);

    // Vectors are read ONCE, after the guest has already restarted at least
    // once.
    //
    // testB24 never showed them because the guest is not stalling -- it keeps
    // writing POST codes, so the "has it been still for a while" gate never
    // fired. It is in a reset loop, not a hang. Waiting for RESTARTS to reach 1
    // means the first pass through POST is left completely alone (which is what
    // testB21-23 got wrong), and by then one disturbed pass costs nothing.
    // Read the vectors once the POST count has been still for a while. The
    // guest hangs rather than restarting (RESTARTS stays 0 on hardware), so
    // waiting for a restart never fires either -- testB25 sat on
    // "VEC -- WAITING RESTART" indefinitely. Quiet means POST is over and
    // taking the bus for a few reads disturbs nothing.
    static int vectors_read = 0;
    static uint32_t v16_seg = 0, v16_off = 0, v1a_seg = 0, v1a_off = 0;
    if (!vectors_read && idle_ticks >= 4000u) {
        v16_off = guest_peek(0x58) | ((uint32_t) guest_peek(0x59) << 8);
        v16_seg = guest_peek(0x5A) | ((uint32_t) guest_peek(0x5B) << 8);
        v1a_off = guest_peek(0x68) | ((uint32_t) guest_peek(0x69) << 8);
        v1a_seg = guest_peek(0x6A) | ((uint32_t) guest_peek(0x6B) << 8);
        vectors_read = 1;
    }

    // The option-ROM window, read at the same time.
    //
    // POST 11 means the BIOS scanned C000-C800, believed it found an option
    // ROM, and called into it -- and did not come back. But nothing loads a ROM
    // there: the BIOS memory test only covers 0x00000-0x07FFF, so C0000 is
    // uninitialised SDRAM. If it happens to read 55 AA, the signature check
    // passes and the machine calls into whatever garbage follows.
    //
    // So print the four bytes the scanner looked at, and the far pointer it
    // stored at 0x67. 55 AA there is the whole explanation.
    static uint32_t c0[4] = {0, 0, 0, 0};
    static uint32_t romptr_off = 0, romptr_seg = 0;
    if (!vectors_read && idle_ticks >= 4000u) {
        for (int i = 0; i < 4; i++) c0[i] = guest_peek(0xC0000u + (uint32_t) i);
        romptr_off = guest_peek(0x67) | ((uint32_t) guest_peek(0x68) << 8);
        romptr_seg = guest_peek(0x69) | ((uint32_t) guest_peek(0x6A) << 8);
    }

    if (vectors_read) {
        osd_draw_string(&fb, 4, 52, "C000", OSD_LABEL);
        for (int i = 0; i < 4; i++) hex(4 + (5 + i * 3) * 8, 52, c0[i], 2);
        osd_draw_string(&fb, 4 + 18 * 8, 52, "PTR", OSD_LABEL);
        hex(4 + 22 * 8, 52, romptr_seg, 4);
        hex(4 + 27 * 8, 52, romptr_off, 4);

        osd_draw_string(&fb, 4, 42, "16h", OSD_LABEL);
        hex(4 + 4 * 8, 42, v16_seg, 4);
        osd_draw_string(&fb, 4 + 8 * 8, 42, ":", OSD_LABEL);
        hex(4 + 9 * 8, 42, v16_off, 4);
        osd_draw_string(&fb, 4 + 15 * 8, 42, "1Ah", OSD_LABEL);
        hex(4 + 19 * 8, 42, v1a_seg, 4);
        osd_draw_string(&fb, 4 + 23 * 8, 42, ":", OSD_LABEL);
        hex(4 + 24 * 8, 42, v1a_off, 4);
    } else {
        osd_draw_string(&fb, 4, 42, "VEC -- POST STILL RUNNING", OSD_LABEL);
    }

    // History, oldest first, so the path through POST is visible at a glance.
    uint32_t hi = *POST_HIST_H, lo = *POST_HIST_L;
    osd_draw_string(&fb, 4 + 11 * 8, 12, "SEQ", OSD_LABEL);
    for (int i = 0; i < 4; i++)
        hex(4 + (15 + i * 3) * 8, 12, (hi >> (24 - i * 8)) & 0xFFu, 2);
    for (int i = 0; i < 4; i++)
        hex(4 + (27 + i * 3) * 8, 12, (lo >> (24 - i * 8)) & 0xFFu, 2);

    *VKB_CTRL = 1u;
}
