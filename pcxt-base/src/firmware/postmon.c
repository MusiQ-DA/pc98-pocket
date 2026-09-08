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
#define POST_IVT16A ((volatile uint32_t *) 0x5000002C) // {wr_count, seg, off_hi}
#define POST_IVT16B ((volatile uint32_t *) 0x50000030) // off
#define POST_WRCNT  ((volatile uint32_t *) 0x50000034) // {aen_count, any_count}
#define POST_WRADDR ((volatile uint32_t *) 0x50000038) // last memory write address
#define POST_IVTTCH ((volatile uint32_t *) 0x5000003C) // {raw_strobes, ivt_touch}
#define POST_LOWCYC ((volatile uint32_t *) 0x50000040) // {rd_low, wr_low}

// The self-test master, reused to read guest memory while the guest runs. It
// takes the bus through hold acknowledge, which is what the BIOS loader does.
#define ST_ADDR   ((volatile uint32_t *) 0x50000000)
#define ST_WDATA  ((volatile uint32_t *) 0x50000004)
#define ST_TRIG   ((volatile uint32_t *) 0x50000008)
#define ST_STATUS ((volatile uint32_t *) 0x5000000C)
#define ST_BUSY   (1u << 8)

static void guest_poke(uint32_t addr, uint8_t v)
{
    *ST_ADDR = addr;
    *ST_WDATA = v;
    *ST_TRIG = 1u;                       // write
    for (uint32_t i = 0; i < 2000u; i++)
        if (!(*ST_STATUS & ST_BUSY))
            break;
}

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
#define PANEL_H 98

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
    static uint32_t v16b_seg = 0, v16b_off = 0;
    static int scratch_bad = 0;
    if (!vectors_read && idle_ticks >= 4000u) {
        // Read INT 16h TWICE. testB26 came back 7044:FC36 where F000:E82E was
        // written, and 5000:FE56 where F000:FE6E was -- bit errors, not
        // misplaced table entries. Two reads separate the two possible causes
        // in one hardware run:
        //
        //   the pair differs  -> the READ is unstable
        //   the pair agrees   -> memory is holding wrong data, so the write
        //                        (or retention) is at fault
        v16_off = guest_peek(0x58) | ((uint32_t) guest_peek(0x59) << 8);
        v16_seg = guest_peek(0x5A) | ((uint32_t) guest_peek(0x5B) << 8);
        v16b_off = guest_peek(0x58) | ((uint32_t) guest_peek(0x59) << 8);
        v16b_seg = guest_peek(0x5A) | ((uint32_t) guest_peek(0x5B) << 8);
        v1a_off = guest_peek(0x68) | ((uint32_t) guest_peek(0x69) << 8);
        v1a_seg = guest_peek(0x6A) | ((uint32_t) guest_peek(0x6B) << 8);

        // And a write/read of our own into a scratch byte the BIOS is done
        // with, to see whether a fresh round trip survives at all.
        for (uint32_t i = 0; i < 8; i++) {
            guest_poke(0x00300u + i, (uint8_t) (0x5Au ^ (i * 0x9Du)));
        }
        for (uint32_t i = 0; i < 8; i++) {
            if (guest_peek(0x00300u + i) != (uint8_t) (0x5Au ^ (i * 0x9Du)))
                scratch_bad++;
        }
        vectors_read = 1;
    }

    // (The option-ROM window is answered: testB26 read C000 as 00 00 00 00 with
    // a null pointer at 0x67, so there is no stray 55 AA signature and that
    // hypothesis is closed. The line is reused for a second read instead.)
    if (vectors_read) {
        // Second read of 16h, and our own scratch round trip.
        osd_draw_string(&fb, 4, 52, "16h#2", OSD_LABEL);
        hex(4 + 6 * 8, 52, v16b_seg, 4);
        osd_draw_string(&fb, 4 + 10 * 8, 52, ":", OSD_LABEL);
        hex(4 + 11 * 8, 52, v16b_off, 4);
        osd_draw_string(&fb, 4 + 17 * 8, 52, "SCR", OSD_LABEL);
        dec(4 + 21 * 8, 52, (uint32_t) scratch_bad);

        // What the guest actually PUT there, snooped off the bus as POST 05's
        // install loop wrote it. Reading the vector back after the hang shows
        // the aftermath instead; this shows the cause.
        uint32_t a = *POST_IVT16A;
        osd_draw_string(&fb, 4, 62, "WROTE", OSD_LABEL);
        hex(4 + 6 * 8, 62, (a >> 8) & 0xFFFFu, 4);
        osd_draw_string(&fb, 4 + 10 * 8, 62, ":", OSD_LABEL);
        hex(4 + 11 * 8, 62, *POST_IVT16B & 0xFFFFu, 4);
        osd_draw_string(&fb, 4 + 17 * 8, 62, "NW", OSD_LABEL);
        dec(4 + 20 * 8, 62, a >> 24);

        // Which term of the snoop filter is wrong: writes seen at all, writes
        // seen with AEN low, and where the last one went.
        uint32_t w = *POST_WRCNT;
        osd_draw_string(&fb, 4, 72, "WR", OSD_LABEL);
        dec(4 + 3 * 8, 72, w & 0xFFFFu);
        osd_draw_string(&fb, 4 + 9 * 8, 72, "RD", OSD_LABEL);
        dec(4 + 12 * 8, 72, w >> 16);
        uint32_t tt = *POST_IVTTCH;
        osd_draw_string(&fb, 4 + 26 * 8, 72, "T", OSD_LABEL);
        dec(4 + 28 * 8, 72, tt & 0xFFFFu);

        // The raw strobes and how long they sit low. RAW is
        // {mem_rd_n, mem_wr_n, io_wr_n, aen_n}: F means all idle-high, and a
        // bit stuck at 0 is the answer on its own.
        uint32_t lc = *POST_LOWCYC;
        osd_draw_string(&fb, 4, 82, "RAW", OSD_LABEL);
        hex(4 + 4 * 8, 82, (tt >> 16) & 0xFu, 1);
        osd_draw_string(&fb, 4 + 7 * 8, 82, "WLO", OSD_LABEL);
        dec(4 + 11 * 8, 82, lc & 0xFFFFu);
        osd_draw_string(&fb, 4 + 18 * 8, 82, "RLO", OSD_LABEL);
        dec(4 + 22 * 8, 82, lc >> 16);
        osd_draw_string(&fb, 4 + 18 * 8, 72, "AT", OSD_LABEL);
        hex(4 + 21 * 8, 72, *POST_WRADDR & 0xFFFFFu, 5);

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
