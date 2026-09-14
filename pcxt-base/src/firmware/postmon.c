#include <stdint.h>
#include "softcpu_regs.h"
#include "vkb_draw.h"
#include "vkb_ui.h"
#include "postmon.h"
#include "sdramtest.h"

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
#define POST_ROMRD  ((volatile uint32_t *) 0x50000044) // bytes the CPU read at F000:D880
#define POST_ROMRD1 ((volatile uint32_t *) 0x5000004C)
#define POST_ROMRD2 ((volatile uint32_t *) 0x50000050)
#define POST_ROMRD3 ((volatile uint32_t *) 0x50000054)
#define POST_ROMLD0 ((volatile uint32_t *) 0x50000058) // what the BIOS LOADER wrote there
#define POST_ROMLD1 ((volatile uint32_t *) 0x5000005C)
#define POST_ROMLD2 ((volatile uint32_t *) 0x50000060)
#define POST_ROMLD3 ((volatile uint32_t *) 0x50000064)
#define POST_ROMLDN ((volatile uint32_t *) 0x50000068)
#define POST_RLF    ((volatile uint32_t *) 0x5000006C) // {fifo high water, words dropped}
#define POST_TVRAM  ((volatile uint32_t *) 0x50000080) // {tvram last addr, write count}
#define POST_TVC0   ((volatile uint32_t *) 0x50000084) // row 0 cells 0-3, codes
#define POST_TVC1   ((volatile uint32_t *) 0x50000088) // cells 4-7
#define POST_TVA0   ((volatile uint32_t *) 0x5000008C) // row 0 cells 0-3, attributes
#define POST_TVA1   ((volatile uint32_t *) 0x50000090) // cells 4-7
#define POST_TVH0   ((volatile uint32_t *) 0x50000094) // row 0 cells 0-3, HIGH bytes
#define POST_TVH1   ((volatile uint32_t *) 0x50000098) // cells 4-7
#define POST_TVF0   ((volatile uint32_t *) 0x5000009C) // row buffer's view, cells 0-3
#define POST_TVF1   ((volatile uint32_t *) 0x500000A0) // cells 4-7
#define POST_FRB    ((volatile uint32_t *) 0x500000A4) // {f_valid beats, f_req pulses}
#define POST_MEMSZ  ((volatile uint32_t *) 0x500000A8) // {f0 count, [0501], A3FEA}
#define POST_KEY    ((volatile uint32_t *) 0x500000AC) // {gdc pitch, last {make,code}, count}
#define POST_GDC    ((volatile uint32_t *) 0x500000B0) // {unk count, unk cmd, disp_on, SAD}
#define POST_INT    ((volatile uint32_t *) 0x500000B4) // {INTR level, INTR rising edges}
#define POST_KBD    ((volatile uint32_t *) 0x500000B8) // {0x41 reads, IRQ1 rises}
#define POST_IOH0   ((volatile uint32_t *) 0x50000070) // I/O ports written, newest two
#define POST_IOH1   ((volatile uint32_t *) 0x50000074) // ... older two
#define POST_IOST   ((volatile uint32_t *) 0x50000078) // {itf_bank, io write count}
#define POST_ROMRDN ((volatile uint32_t *) 0x50000048) // how many of them were seen

// The self-test master, reused to read guest memory while the guest runs. It
// takes the bus through hold acknowledge, which is what the BIOS loader does.
#define ST_ADDR   ((volatile uint32_t *) 0x50000000)
#define ST_WDATA  ((volatile uint32_t *) 0x50000004)
#define ST_TRIG   ((volatile uint32_t *) 0x50000008)
#define ST_STATUS ((volatile uint32_t *) 0x5000000C)
#define ST_BUSY   (1u << 8)

// Shown by default -- see postmon.h. The panel and the vkb/settings overlays
// share one framebuffer and one VKB_CTRL bit, so hiding the panel must not pull
// the bit out from under an overlay that is open.
//
// The panel itself is compiled out of the SDRAM_SELFTEST build: that build's
// main() never returns from the self-test, so the tick and the ROM capture
// would be dead weight in a 24 KB ROM that build now fills to the brim too
// (the boot font load, osd_font.c, lives in every image). The toggle stays --
// the virtual keyboard's button binding reaches it from the timer interrupt.
static int postmon_shown = 1;

void postmon_toggle(void)
{
    postmon_shown = !postmon_shown;
}

#ifndef SDRAM_SELFTEST

__attribute__((unused))
static void guest_poke(uint32_t addr, uint8_t v)
{
    *ST_ADDR = addr;
    *ST_WDATA = v;
    *ST_TRIG = 1u;                       // write
    for (uint32_t i = 0; i < 2000u; i++)
        if (!(*ST_STATUS & ST_BUSY))
            break;
}

__attribute__((unused))
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
// PANEL_H is the LAST ROW + 10, and a row drawn past it has no background
// behind it and is cut off -- which is what MSW/SZ/F0 did on the first try at
// row 182 against PANEL_H 182.
//
// The panel is drawn over the guest's text screen: the OSD framebuffer is
// 640x200 against a 640x400 raster, so it is centred at y=100 and each of its
// lines is one guest line. 112 rows therefore cover guest lines 100-211 --
// text rows 7 to 14 -- and everything above and below stays readable. Nine
// rows of spent diagnostics came out (the ROM read/load dumps, the slot
// sizes, the FIFO drops and the row buffer's view) and the two live rows
// moved up into the hole rather than leaving it, which is what took the
// panel from 200 down to 112.
//
// 182, not 162: TVF and FRB were drawn on row 92 on top of RD0, three fields
// in one row's worth of space. They cannot share a row either -- TVF is a
// label plus eight bytes (28 of the panel's 40 columns) and FRB is another
// 13 -- so the panel grew by two rows rather than one of them staying
// unreadable. 192 adds the MSW/SZ/F0 row on top of that; OSD_FB_HEIGHT is
// 200, so it still fits. 200 adds the GDC row at 190 and is the whole
// framebuffer -- there is no room for another.
#define PANEL_H 122

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

#ifdef MACHINE_PC98
// One segment's window: its digit, then the lowest and highest offset seen in
// it. Drawn through a helper, so check_osd_layout cannot evaluate the x
// expressions and does not see these fields -- which is safe only because
// rows 62 and 72 now belong to this and to nothing else.
#endif

// ---------------------------------------------------------- ROM capture
//
// Read once, with the guest held, and show the cached bytes afterwards. See
// postmon.h for why it cannot be read live.
// The first 256 bytes of the BIOS entry at FD800, so the firmware can COMPARE
// instead of dump. The machine boots there now.
//
// These are the PC-9801UX BIOS (md5 3af0ae01), file offset 0x15800. They used
// to be the old VM-family image, and after the ROM set was replaced the panel
// read BAD 0F2 AT 000 -- 242 of 256 bytes "wrong" from the very first one,
// which is what a CORRECT new ROM looks like against a stale expectation. If
// this ever disagrees again, check which ROM is on the card before suspecting
// the SDRAM path.
//
// Regenerate with:
//   python3 -c "d=open('bios.rom','rb').read()[0x15800:0x15A00]; ..." 
static const uint8_t bios_head[256] = {
    0xEB, 0x02, 0xEB, 0x30, 0xFA, 0x33, 0xC0, 0x8E, 0xD8, 0xE4, 0x35, 0xA8,
    0x80, 0x75, 0x09, 0x8E, 0x16, 0x06, 0x04, 0x8B, 0x26, 0x04, 0x04, 0xCB,
    0xC7, 0x06, 0xF8, 0x04, 0xEE, 0xEA, 0xC7, 0x06, 0xFA, 0x04, 0x00, 0x00,
    0xC7, 0x06, 0xFC, 0x04, 0xFF, 0xFF, 0xBA, 0x3D, 0x04, 0xB0, 0x10, 0xEA,
    0xF8, 0x04, 0x00, 0x00, 0xFA, 0xB8, 0x30, 0x00, 0x8E, 0xD0, 0xBC, 0xFE,
    0x00, 0xEB, 0x41, 0x90, 0x36, 0x09, 0x36, 0x09, 0xF0, 0x08, 0x36, 0x09,
    0x36, 0x09, 0x36, 0x09, 0x36, 0x09, 0x36, 0x09, 0x38, 0x06, 0x44, 0x0E,
    0x37, 0x09, 0x37, 0x09, 0x3D, 0x18, 0x37, 0x09, 0x37, 0x09, 0x37, 0x09,
    0x37, 0x09, 0x37, 0x09, 0x37, 0x09, 0x37, 0x09, 0x37, 0x09, 0x37, 0x09,
    0x37, 0x09, 0x37, 0x09, 0xBD, 0x0A, 0x96, 0x15, 0x80, 0x06, 0x82, 0x1A,
    0x00, 0x05, 0x36, 0x09, 0x00, 0x00, 0x00, 0x02, 0x8C, 0xC8, 0x8E, 0xD8,
    0x33, 0xC0, 0x8E, 0xC0, 0xFC, 0xBE, 0x40, 0x00, 0x33, 0xFF, 0xB9, 0x1E,
    0x00, 0xA5, 0x8C, 0xC8, 0xAB, 0xE2, 0xFA, 0x26, 0xF6, 0x06, 0x00, 0x05,
    0x80, 0x75, 0x07, 0xA5, 0xB8, 0x00, 0xE8, 0xAB, 0xEB, 0x03, 0x83, 0xC7,
    0x04, 0xA5, 0x8C, 0xC8, 0xAB, 0x33, 0xC0, 0x8E, 0xD8, 0xE4, 0x42, 0xA8,
    0x02, 0x75, 0x06, 0xB8, 0x36, 0x09, 0xA3, 0x40, 0x00, 0xB0, 0x02, 0xE6,
    0x32, 0xB9, 0x0A, 0x00, 0xE2, 0xFE, 0xB0, 0x40, 0xE6, 0x32, 0xB0, 0x02,
    0xE6, 0x43, 0xB9, 0x0A, 0x00, 0xE2, 0xFE, 0xB0, 0x40, 0xE6, 0x43, 0xB9,
    0x0A, 0x00, 0xE2, 0xFE, 0xB0, 0x5E, 0xE6, 0x43, 0xB9, 0x0A, 0x00, 0xE2,
    0xFE, 0xB4, 0x03, 0xCD, 0x18, 0xBA, 0x88, 0x01, 0xB0, 0x27, 0xEE, 0xB9,
    0x00, 0x01, 0xE2, 0xFE, 0xBA, 0x8A, 0x01, 0xB0, 0x0F, 0xEE, 0xC6, 0x06,
    0x4C, 0x05, 0x0E, 0xE4,
};

static uint32_t rom_bad;      // how many of the 256 disagree
static uint32_t rom_first;    // offset of the first, or 0x100 if none
static uint8_t  rom_a[8];     // eight bytes from there: what memory holds
static uint8_t  rom_b[8];     // eight bytes from there: what the file holds

void postmon_capture_rom(void)
{
    // Watch the BIOS entry, since that is where the machine now starts.
    // The BIOS entry: FD800 is EB 02 EB 30 FA 33 C0 8E D8 E4 35 ... on the UX
    *POST_ROMWIN = 0x0FD80u;

    // A damage map, not a hex dump. FFFF0 came back byte-perfect while
    // F800E0 was unrecognisable -- not from any of the three ROM images -- so
    // the question is which parts of the 32 KB arrived, not what one of them
    // says. One byte from the head of each 4 KB page covers the lot.
    //
    // The file's values are FA 10 72 01 00 00 00 00; the last four pages read
    // 00 in the image itself, so only the first four carry information.
    rom_bad = 0;
    rom_first = 0x100u;
    for (uint32_t i = 0; i < 256u; i++) {
        if (sdram_peek(0xFD800u + i) != bios_head[i]) {
            rom_bad++;
            if (rom_first == 0x100u)
                rom_first = i;
        }
    }
    // Eight bytes from the first disagreement, memory against file.
    uint32_t base = (rom_first < 0x100u) ? rom_first : 0u;
    if (base > 248u)
        base = 248u;
    for (uint32_t i = 0; i < 8; i++) {
        rom_a[i] = sdram_peek(0xFD800u + base + i);
        rom_b[i] = bios_head[base + i];
    }
}

void post_mon_tick(void)
{
    static uint32_t last_status = 0xFFFFFFFFu;
    static int placed = 0;

    // An overlay owns the framebuffer while it is open, and this panel used to
    // paint over it every tick. That made the settings menu unreadable -- and
    // the menu is where the button that hides this panel is bound, so the one
    // way to get the panel out of the way was behind the panel.
    if (vkb_ui_overlay_open()) {
        placed = 0; // the overlay moves the origin; re-place on the way back
        return;
    }

    if (!postmon_shown) {
        *VKB_CTRL = 0u;
        placed = 0; // re-place the strip when it comes back
        return;
    }

    // POST_STATUS freezes after the first pass through POST, so this settles;
    // the counters below keep moving and are what show a reboot loop.
    uint32_t status = *POST_STATUS;
    uint32_t maxrst = *POST_MAXRST;
    uint32_t live   = *POST_LIVE;
    uint32_t tvram = *POST_TVRAM;
    static uint32_t last_maxrst = 0xFFFFFFFFu;
    static uint32_t last_live = 0xFFFFFFFFu;
    static uint32_t last_tvram = 0xFFFFFFFFu;
    // LIVE is the point of this build: when the guest stops, it settles on
    // whatever the CPU is spinning in. Redraw whenever it moves.
    // Staleness is judged on the POST COUNT ALONE.
    //
    // It used to include `live`, and live is the guest's last memory address --
    // it changes on every access, so "nothing has changed" was never true and
    // the gate never fired. That is why testB24 showed no vectors, and it is
    // also why I read that run as a reset loop: the symptom was my gate, not
    // the guest.
    // Where the guest's accesses ARE, not just where the last one was.
    //
    // LIVE is one address sampled at whatever rate this loop runs, and a
    // number that will not sit still looks the same whether the machine is
    // sweeping the memory test through 640 KB or going round a handful of
    // bytes of garbage. Those are opposite diagnoses and the readout could
    // not tell them apart, which is why "LIVE is flailing" has been reported
    // three times without settling anything.
    //
    // So: bucket the samples by 64 KB segment and show all sixteen counts.
    // A memory test is 0-9 lit with F (the code it runs from); a loop in one
    // place is one segment lit and the rest dark. FR is the highest address
    // seen below A0000 in the window -- the sweep's frontier, which climbs
    // window over window while a test is running and does not while it is not.
#ifdef MACHINE_PC98
    static uint8_t  seg_hit[16], seg_show[16];
    static uint16_t seg_lo[16], seg_hi[16], seg_lo_s[16], seg_hi_s[16];
    static uint32_t seg_n = 0, seg_front = 0, seg_front_show = 0;
    for (int i = 0; i < 8; i++) {
        uint32_t a = *POST_LIVE & 0xFFFFFu;
        uint32_t g = a >> 16, off = a & 0xFFFFu;
        // Which segment is not enough on its own: a segment is 64 KB and a
        // loop is a few bytes. The extent inside it is what names the routine.
        if (seg_hit[g] == 0u) {
            seg_lo[g] = (uint16_t) off;
            seg_hi[g] = (uint16_t) off;
        } else {
            if (off < seg_lo[g]) seg_lo[g] = (uint16_t) off;
            if (off > seg_hi[g]) seg_hi[g] = (uint16_t) off;
        }
        if (seg_hit[g] < 255u) seg_hit[g]++;
        if (a < 0xA0000u && a > seg_front) seg_front = a;
    }
    // 4096 samples: long enough that the window spans real guest time at any
    // plausible rate for this loop, short enough to still be a window.
    if ((seg_n += 8u) >= 4096u) {
        for (int i = 0; i < 16; i++) {
            seg_show[i] = seg_hit[i];
            seg_lo_s[i] = seg_lo[i];
            seg_hi_s[i] = seg_hi[i];
            seg_hit[i] = 0;
        }
        seg_front_show = seg_front;
        seg_front = 0;
        seg_n = 0;
    }
#endif

    static uint32_t idle_ticks = 0;
    uint32_t count_now = status >> 16;
    static uint32_t last_count = 0xFFFFFFFFu;
    if (count_now == last_count) {
        if (idle_ticks < 1000000u) idle_ticks++;
    } else {
        last_count = count_now;
        idle_ticks = 0;
    }
    // The redraw gate skips the WHOLE function, including the *VKB_CTRL = 1
    // at the end that turns the overlay on. On PC/AT that was harmless because
    // POST codes and the live address changed constantly, so it ran all the
    // time. On PC-98 nothing here ever changes -- no port-0x80 progress, and a
    // guest that has stopped -- so the gate can hold shut and the overlay is
    // never enabled at all. Which is what "no OSD" looks like.
    //
    // Enable it before deciding whether to redraw: it costs one store and it is
    // not the expensive part.
    *VKB_CTRL = 1u;

    if (status == last_status && maxrst == last_maxrst && live == last_live
        && tvram == last_tvram
        && idle_ticks != 4000u) {
        return;                            // nothing worth redrawing
    }
    last_tvram = tvram;
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

    // Which I/O ports the guest has written, newest first, and whether the ITF
    // has handed over yet.
    //
    // UNCONDITIONAL, and it has to be. This started inside the block gated on
    // post_max >= 0x08 -- which is a port-0x80 progress code, a PC/AT thing
    // that a PC-98 never writes. So on the machine it was added for, the gate
    // never opened and the readout never appeared: the first PC-98 build came
    // back reporting "POST 00" and nothing else, because POST 00 is the reset
    // value of a field that machine does not use.
    //
    // Reading these costs nothing -- they are registers in the monitor, not bus
    // accesses -- so there is no reason to gate them at all. On PC-98 the ITF's
    // route to the hand-over runs 0x0461 then 0x043D, so 043D arriving and BANK
    // going 0 is the whole of P1.
#ifdef MACHINE_PC98
    {
        uint32_t io0 = *POST_IOH0, io1 = *POST_IOH1, ios = *POST_IOST;
        // Four ports now, on their own row.
        //
        // Two of them shared row 12 with N and BANK and the row ran to column
        // 37, which put BANK -- the field that build existed to show -- off the
        // readable part of the screen. The panel has empty rows below, so the
        // history gets one to itself and nothing has to be dropped: the ITF is
        // running, and the sequence of ports it touches is how far it got.
        osd_draw_string(&fb, 4, 12, "IO", OSD_LABEL);
        hex(4 + 3 * 8, 12, io0 & 0xFFFFu, 4);
        hex(4 + 8 * 8, 12, io0 >> 16, 4);
        hex(4 + 13 * 8, 12, io1 & 0xFFFFu, 4);
        hex(4 + 18 * 8, 12, io1 >> 16, 4);
        osd_draw_string(&fb, 4 + 23 * 8, 12, "N", OSD_LABEL);
        dec(4 + 25 * 8, 12, ios & 0xFFFFu);
        // BANK stays on this row, pushed right: the panel is forty columns and
        // four ports plus N reach thirty, so it fits with room to spare. The
        // rows below look empty on a PC-98 screen but every one of them carries
        // PC/AT-only fields that the layout check still counts.
        osd_draw_string(&fb, 4 + 31 * 8, 12, "BANK", OSD_LABEL);
        // hex, not dec: it is one bit, and dec() has no fixed width so the
        // layout check has to assume five digits and calls the row off-panel.
        hex(4 + 36 * 8, 12, (ios >> 16) & 1u, 1);
    }
#endif

    osd_draw_string(&fb, 4, 22, "ADDR", OSD_LABEL);
    hex(4 + 5 * 8, 22, *POST_ADDR & 0xFFFFFu, 5);

    // MAX and RST were PC/AT-only, and their absence cost a night: "is the
    // guest looping or restarting?" is the first question a blank screen
    // raises, and on PC-98 the panel could not answer it. MAX stays quiet
    // here (the PC-98 BIOS writes no port-80 progress, so it is always 00),
    // but the restart counter is the machine's own, and it is the one number
    // that separates a hang from a reset loop.
    // Right of LDN's dec(), which the layout check must assume is five digits
    // wide (it ends at column 26).
    osd_draw_string(&fb, 4 + 27 * 8, 22, "RST", OSD_LABEL);
    // hex, fixed width: dec() has no fixed width and the check would then
    // have to assume five digits and call the row off-panel.
    hex(4 + 31 * 8, 22, maxrst & 0xFFFFu, 4);
#ifndef MACHINE_PC98
    osd_draw_string(&fb, 4 + 36 * 8, 22, "MAX", OSD_LABEL);
    hex(4 + 40 * 8, 22, (maxrst >> 16) & 0xFFu, 2);
#endif

    // Words the ROM-load FIFO threw away, and how deep it ever got.
    //
    // Unconditional for the same reason the IO line is. A nonzero DROP means
    // the image in memory is incomplete before the CPU executes an
    // instruction, so it is the first thing worth knowing on ANY machine --
    // and it was sitting behind a PC/AT progress code a PC-98 never writes.
    // It is also the check that has to be repeated every time something makes
    // the SDRAM consumer slower.
    {
    #ifdef MACHINE_PC98
    // What the guest's ROM actually holds, read through the self-test master.
    //
    // RD0 covers sixteen bytes at FFFF0 and nothing else, so a fault that
    // spares the reset vector and corrupts the rest reads as "the ITF started
    // and then went somewhere odd" -- which is what the port trace showed: the
    // ITF's port-init table takes every port number from the ODD byte of a
    // word, and the hardware wrote 000C/000D where a correct ROM gives 0439,
    // 0077, 0073. F800E0 is that loop and the first bytes of its table, so the
    // file's own values are printed underneath as the key.
    {
        // BAD = how many of the first 256 bytes disagree, AT = the first one.
        // On the POST row, which this machine leaves half empty.
        osd_draw_string(&fb, 4 + 24 * 8, 2, "BAD", OSD_LABEL);
        hex(4 + 28 * 8, 2, rom_bad, 3);
        osd_draw_string(&fb, 4 + 32 * 8, 2, "AT", OSD_LABEL);
        hex(4 + 35 * 8, 2, rom_first, 3);
        // A control, on the same path. F800E0 came back all zeros, but the
        // peek runs through the self-test master, which was built to work with
        // the 8088 held in reset -- and the guest is running now. A read that
        // loses its arbitration returns a stale zero, which looks exactly like
        // an empty ROM.
        //
        // FFFF0 is the one place whose contents are already known: RD0 shows
        // the CPU reading EA 00 00 00 F8 there, and LD0 two rows up shows what
        // the loader wrote. If this row matches LD0, the peek works and F800E0
        // really is empty. If it comes back zeros too, the peek is the thing
        // that is broken and F800E0 says nothing.
    }
#endif
    }

    // testB27 answered it: F8 2E 41 D6 against F8 2E E8 D2 in the image.
    // The read IS corrupt, and the pair 41 D6 appears nowhere in the 64 KB
    // image, so it is not one address aliasing onto another. Word D880 came
    // back perfect and word D882 came back with BOTH bytes wrong, which
    // also rules out a swapped DQ lane. Sixteen bytes now, to see whether
    // the damage alternates by word, runs, or is a single word.

    // And what the BIOS LOADER put there in the first place, taken off its
    // own FSM rather than the bus. RD is what the CPU took in; LD is what
    // was written. The two together say which half is broken:
    //
    //   LD E8 D2, RD 41 D6  -> written correctly, not kept or not read
    //   LD 41 D6            -> the loader delivered the wrong bytes

#ifdef MACHINE_PC98
    osd_draw_string(&fb, 4 + 17 * 8, 22, "LDN", OSD_LABEL);
    dec(4 + 21 * 8, 22, *POST_ROMLDN & 0xFFu);
#endif

    osd_draw_string(&fb, 4, 32, "LIVE", OSD_LABEL);
    hex(4 + 5 * 8, 32, live & 0xFFFFFu, 5);
    osd_draw_string(&fb, 4 + 12 * 8, 32, "HIGH", OSD_LABEL);
    hex(4 + 17 * 8, 32, *POST_LIVEMX & 0xFFFFFu, 5);

#ifdef MACHINE_PC98
    // Row 52 is free on this machine: it belongs to the vector dump, which is
    // gated on a restart that never happens here.
    //
    // One digit per 64 KB segment, 0 (never seen this window) to F (saturated
    // -- the counter is capped so a busy segment cannot roll back to zero and
    // read as dark).
    {
        // Packed four bits to a segment, two words of eight, because sixteen
        // separate one-digit calls cost 160 bytes of a ROM with 24 K in it.
        uint32_t p0 = 0, p1 = 0;
        for (int i = 0; i < 8; i++) {
            uint32_t c = seg_show[i], d = seg_show[i + 8];
            p0 = (p0 << 4) | (c > 15u ? 15u : c);
            p1 = (p1 << 4) | (d > 15u ? 15u : d);
        }
        osd_draw_string(&fb, 4, 52, "SEG", OSD_LABEL);
        hex(4 + 4 * 8, 52, p0, 8);
        hex(4 + 12 * 8, 52, p1, 8);
        osd_draw_string(&fb, 4 + 21 * 8, 52, "FR", OSD_LABEL);
        (void) seg_lo_s; (void) seg_hi_s;
        hex(4 + 24 * 8, 52, seg_front_show, 5);

        // The extents, for the two highest-numbered live segments and the two
        // lowest. High is where the code is (E8000-FFFFF is ROM on this
        // machine); low is where it is working. Four segments lit is what the
        // first reading gave -- 0, 1, D and E -- and the four ranges name the
        // loop between them.

        // Row 0's first eight cells, snooped off the bus as the guest writes
        // them -- passive, because the self-test master cannot reach the text
        // VRAM at all: the arbiter raises address_enable_n for its accesses
        // and tvram_mem_select is qualified with ~address_enable_n. Reaching
        // for it with guest_peek froze the machine and reported the read's own
        // address as the guest's position.
        //
        // The ITF's message record is E1 'MEMORY 000KB OK': attribute E1 is
        // white, visible, no reverse. If the codes are 4D 45 4D 4F ... and the
        // screen still has no letters in it, the fault is downstream of the
        // VRAM, in the glyph path.
        {
            uint32_t c0 = *POST_TVC0, c1 = *POST_TVC1;
            uint32_t a0 = *POST_TVA0, a1 = *POST_TVA1;
            osd_draw_string(&fb, 4, 62, "TVC", OSD_LABEL);
            for (int i = 0; i < 4; i++)
                hex(4 + (4 + i * 3) * 8, 62, (c0 >> (i * 8)) & 0xFFu, 2);
            for (int i = 0; i < 4; i++)
                hex(4 + (16 + i * 3) * 8, 62, (c1 >> (i * 8)) & 0xFFu, 2);
            osd_draw_string(&fb, 4, 72, "TVA", OSD_LABEL);
            for (int i = 0; i < 4; i++)
                hex(4 + (4 + i * 3) * 8, 72, (a0 >> (i * 8)) & 0xFFu, 2);
            for (int i = 0; i < 4; i++)
                hex(4 + (16 + i * 3) * 8, 72, (a1 >> (i * 8)) & 0xFFu, 2);
            // The high bytes: every one of these should read 00 once the
            // message has been written. Anything else two-byte-flags its cell
            // -- the letter goes to the kanji path and the screen shows a
            // solid block where it should be, which is what run#191 drew.
            {
                uint32_t h0 = *POST_TVH0, h1 = *POST_TVH1;
                osd_draw_string(&fb, 4, 82, "TVH", OSD_LABEL);
                for (int i = 0; i < 4; i++)
                    hex(4 + (4 + i * 3) * 8, 82, (h0 >> (i * 8)) & 0xFFu, 2);
                for (int i = 0; i < 4; i++)
                    hex(4 + (16 + i * 3) * 8, 82, (h1 >> (i * 8)) & 0xFFu, 2);
            }
        }

        // NO bus-master readback here, and that is the point.
        //
        // This row briefly read A0000 and A2000 through guest_peek to settle
        // whether the VRAM held the right bytes. It settled something else:
        // the machine stopped, N frozen at 84, and LIVE reading A200E -- which
        // is not where the guest was, it is the eighth byte THIS read asked
        // for. guest_peek takes the bus through hold acknowledge, and a read
        // of the text VRAM does not hand it back.
        //
        // postmon has been here before; the note above the vector block says
        // an ext read "destroyed the measurement it was meant to support".
        // Reading the guest's own video memory while it runs needs a passive
        // snoop in post_monitor, not the bus master.
    }
#endif

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
    //
    // ALL OF IT IS PC/AT ONLY, and the comment above says why without acting
    // on it: the gate is post_max >= 0x08, a port-0x80 progress code a PC-98
    // never writes, so on this machine the reads never happen and the rows
    // never draw. Compiled in, it was still 24 K of ROM spent on a branch that
    // cannot run -- and it owns rows 42-82, which is where a readout that CAN
    // run has to go.
#ifndef MACHINE_PC98
    static int vectors_read = 0;
    static uint32_t v16_seg = 0, v16_off = 0;
    static uint32_t v16b_seg = 0, v16b_off = 0;

    // MUST be past the memory test before taking the bus.
    //
    // The gate used to be "the POST count has been still for a while", and POST
    // 04 -- the base 64 KB memory test -- is by far the longest step, so the
    // condition came true in the middle of it and guest_peek started competing
    // with the test it was meant to observe. That is what turned testB21-23
    // into POST 54, and adding eight more reads for the ROM window reproduced
    // it immediately.
    //
    // post_max >= 0x08 means POST 04 is finished and passed. Until then this
    // build touches nothing.
    if (!vectors_read && idle_ticks >= 4000u && ((maxrst >> 16) & 0xFFu) >= 0x08u) {
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

        // The ext-port readback that used to be here is GONE. run#105 tried it
        // and it failed twice over:
        //
        //   it does not work -- MEM came back F8 51 51 51 51 51, the first
        //   access right and the rest a constant, the same shape as the
        //   self-test master's own sweep returning 11 11 11 ...
        //
        //   and it destroyed the measurement it was meant to support. An ext
        //   access drives the guest bus with AEN high, so those six reads
        //   landed in the ROM window's slots: N went 16 to 22 and RD0's first
        //   six bytes became the ext port's answer instead of the CPU's.
        //
        // Both are fixed at the source now -- the window is qualified with
        // ~address_enable_n, and the question is answered by snooping the BIOS
        // LOADER's writes instead, which needs no working ext read at all.
        vectors_read = 1;
    }

    // (The option-ROM window is answered: testB26 read C000 as 00 00 00 00 with
    // a null pointer at 0x67, so there is no stray 55 AA signature and that
    // hypothesis is closed. The line is reused for a second read instead.)
    if (vectors_read) {
        // What the CPU actually READ at F000:D880-D883, snooped off the bus.
        //
        // Reading that region with the self-test master returned
        // 11 11 11 11 11 11 11 11 -- a constant, not memory -- so the master's
        // read of the BIOS region is broken and its answer is worthless here.
        // The bus snoop is passive and is the same mechanism that caught the
        // write, which reproduces exactly (F000:412E on two runs).
        //
        // The BIOS image holds F8 2E E8 D2 at D880-D883. The guest wrote 412E,
        // so it saw 2E then 41: expect this to read F8 2E 41 D2 if the CPU's
        // read is what is corrupt.
        //
        // Second read of 16h, and our own scratch round trip.
        osd_draw_string(&fb, 4, 52, "16h#2", OSD_LABEL);
        hex(4 + 6 * 8, 52, v16b_seg, 4);
        osd_draw_string(&fb, 4 + 10 * 8, 52, ":", OSD_LABEL);
        hex(4 + 11 * 8, 52, v16b_off, 4);

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
        // What MEM and RD0 should both be, so the screen carries its own key.
        osd_draw_string(&fb, 4 + 15 * 8, 42, "WANT EA 00 00 00 F8", OSD_LABEL);
    } else {
        // Not on PC-98. This whole branch is gated on post_max >= 0x08, a
        // port-0x80 progress code that machine never writes, so the line would
        // read "WAITING" forever -- a permanent PC/AT leftover on a PC-98
        // screen, which reads as a symptom and is not one.
#ifndef MACHINE_PC98
        osd_draw_string(&fb, 4, 42, "VEC -- WAITING (MAX<08)", OSD_LABEL);
#endif
    }
#endif

    // History, oldest first, so the path through POST is visible at a glance.
    // PC/AT only: these are port-0x80 progress codes, and on PC-98 the row
    // belongs to the I/O trace -- which is what they were colliding with.
#ifndef MACHINE_PC98
    uint32_t hi = *POST_HIST_H, lo = *POST_HIST_L;
    osd_draw_string(&fb, 4 + 11 * 8, 12, "SEQ", OSD_LABEL);
    for (int i = 0; i < 4; i++)
        hex(4 + (15 + i * 3) * 8, 12, (hi >> (24 - i * 8)) & 0xFFu, 2);
    for (int i = 0; i < 4; i++)
        hex(4 + (27 + i * 3) * 8, 12, (lo >> (24 - i * 8)) & 0xFFu, 2);
#endif

#ifdef MACHINE_PC98
    // Did the BIOS ever write a character? The text plane is A0000-A3FFF;
    // the count is the answer to "why is the screen still just a cursor".
    // Row 42 is where the PC/AT build shows its VEC line; on PC-98 it is
    // free, and the first try at row 92 landed on top of RD0.
    {
        uint32_t tv = *POST_TVRAM;
        osd_draw_string(&fb, 4, 42, "TVW", OSD_LABEL);
        hex(4 + 4 * 8, 42, tv & 0xFFFFu, 4);
        osd_draw_string(&fb, 4 + 13 * 8, 42, "AT", OSD_LABEL);
        hex(4 + 16 * 8, 42, 0xA0000u | ((tv >> 16) & 0x3FFFu), 5);
    }

    // Why MEMORY stops at 128KB, in three bytes.
    //
    //   MSW  A3FEA as the GUEST read it. The ITF sizes RAM from this byte
    //        alone (F8B58: and al,7 / clamp 4 / (n+1)*2 vs the 64 KB count),
    //        so 04 = 640 KB and 00 = stop after one 128 KB block.
    //        pc98_tvram pre-seeds 04; this is whether the guest gets it.
    //   SZ   what the ITF concluded, from its OR [0501],DH at F8B91.
    //   F0   OUT 0F0h requests. That instruction IS how POST hands over --
    //        one is normal and owns the boot chime. Climbing means the loop.
    {
        uint32_t m = *POST_MEMSZ;
        osd_draw_string(&fb, 4, 92, "MSW", OSD_LABEL);
        hex(4 + 4 * 8, 92, m & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 8 * 8, 92, "SZ", OSD_LABEL);
        hex(4 + 11 * 8, 92, (m >> 8) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 15 * 8, 92, "F0", OSD_LABEL);
        hex(4 + 18 * 8, 92, (m >> 16) & 0xFFu, 2);

        // KEY: how far a key press gets. The count is pc98_kbd_ps2's output
        // strobes and the code is the last event ({make, PC-98 code}) -- so
        // this is BEFORE the 8251 and before IRQ1.
        //
        // Zero after pressing keys puts the fault in the virtual keyboard, the
        // vkb_stb toggle or pocket_keyboard's queue. Climbing puts it
        // downstream: the 8251 model, IRQ1 off its RxRDY, or the guest.
        uint32_t k = *POST_KEY;
        osd_draw_string(&fb, 4 + 22 * 8, 92, "KEY", OSD_LABEL);
        hex(4 + 26 * 8, 92, k & 0xFFu, 2);
        hex(4 + 29 * 8, 92, (k >> 8) & 0xFFu, 2);

        // GDC: where the TEXT renderer is pointed, against where the guest
        // writes (TVW/AT above). pc98_text_render takes SAD and PITCH from the
        // master GDC, so characters can be in TVRAM and off the screen at the
        // same time -- SAD moved and the renderer followed it somewhere else.
        //
        //   SAD  display start, words. 0000 with PITCH 50 is the normal
        //        80-column screen from the top of the plane.
        //   P    pitch, words per line. 50 is 80 columns.
        //   D    disp_on.
        //   U    commands the decode did not recognise: the count, then the
        //        last opcode. Anything but 00 means the guest asked for
        //        something this GDC does not implement.
        uint32_t g = *POST_GDC;
        osd_draw_string(&fb, 4, 102, "SAD", OSD_LABEL);
        hex(4 + 4 * 8, 102, g & 0x7FFFu, 4);
        osd_draw_string(&fb, 4 + 10 * 8, 102, "P", OSD_LABEL);
        hex(4 + 12 * 8, 102, (k >> 16) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 16 * 8, 102, "D", OSD_LABEL);
        hex(4 + 18 * 8, 102, (g >> 15) & 1u, 1);
        osd_draw_string(&fb, 4 + 21 * 8, 102, "U", OSD_LABEL);
        hex(4 + 23 * 8, 102, (g >> 24) & 0xFFu, 2);
        hex(4 + 26 * 8, 102, (g >> 16) & 0xFFu, 2);


        // INT: rising edges of INTR into the CPU, and its current level.
        // Zero means the guest has never been interrupted -- no timer, no
        // keyboard -- which is the shape that leaves BASIC having cleared the
        // screen and drawn its function key line and then stopped.
        uint32_t iv = *POST_INT;
        osd_draw_string(&fb, 4 + 30 * 8, 102, "INT", OSD_LABEL);
        hex(4 + 34 * 8, 102, iv & 0xFFFFu, 4);

        // IRQ / RD: the keyboard's last two hops, after KEY.
        //
        //   KEY  the translator emitted the event   (255+ seen)
        //   IRQ  the 8251 raised RxRDY -> IRQ1 for it
        //   RD   the guest came and read the byte at 0x41
        //
        // IRQ 00 blames the 8251 model or its RxRDY. IRQ climbing with RD 00
        // blames the PIC mask or the vector -- the interrupt was raised and
        // nobody served it. Both climbing puts the key inside the guest and
        // the fault somewhere past the hardware.
        uint32_t kb = *POST_KBD;
        osd_draw_string(&fb, 4, 112, "IRQ", OSD_LABEL);
        hex(4 + 4 * 8, 112, kb & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 8 * 8, 112, "RD", OSD_LABEL);
        hex(4 + 11 * 8, 112, (kb >> 8) & 0xFFu, 2);
    }
#endif

    *VKB_CTRL = 1u;
}

#endif // !SDRAM_SELFTEST
