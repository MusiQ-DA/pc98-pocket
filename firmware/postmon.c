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
#define POST_CUR    ((volatile uint32_t *) 0x5000012C) // {CSR count, en, bl, top, bot, cell}
#define POST_CT     ((volatile uint32_t *) 0x50000130) // {byte count, 3 bytes after the last 4B}
#define POST_RST    ((volatile uint32_t *) 0x50000134) // the guest-reset terms
#define POST_INT    ((volatile uint32_t *) 0x500000B4) // {INTR level, INTR rising edges}
#define POST_KBD    ((volatile uint32_t *) 0x500000B8) // {0x41 reads, IRQ1 rises}
#define POST_IRQL   ((volatile uint32_t *) 0x500000BC) // {IF, timer ticks, IRQ levels}
#define POST_PIC    ((volatile uint32_t *) 0x500000C0) // {ISR, IMR, IRR} of the master PIC
#define POST_INTA   ((volatile uint32_t *) 0x500000C4) // {vector byte, INTA count}
#define POST_IVT13  ((volatile uint32_t *) 0x500000C8) // INT 13h vector {seg, off}
#define POST_IVT12  ((volatile uint32_t *) 0x500000CC) // INT 12h vector {seg, off}
#define POST_PIC2   ((volatile uint32_t *) 0x500000D0) // slave PIC {ISR, IMR, IRR}
#define POST_MOTOR  ((volatile uint32_t *) 0x500000D4) // {pulses, arms} of the motor timers
#define POST_STRB1  ((volatile uint32_t *) 0x500000D8) // {data strobes, 0xCC strobes}
#define POST_STRB2  ((volatile uint32_t *) 0x500000DC) // {0xBE strobes, 0x94 strobes}
#define POST_LCTRL  ((volatile uint32_t *) 0x500000E0) // last control byte the glue saw
#define POST_WPATH  ((volatile uint32_t *) 0x500000E4) // {io_write strobes, decode clocks}
#define POST_RWLVL  ((volatile uint32_t *) 0x500000E8) // {write levels, read levels}
#define POST_FDCX   ((volatile uint32_t *) 0x500000EC) // {results read, DOR, irq rises, MSR}
#define POST_FDCY   ((volatile uint32_t *) 0x500000F0) // {last read byte, 0, CC, 94}
#define POST_FDCZ   ((volatile uint32_t *) 0x500000F4) // the last four FIFO bytes
#define POST_FDCW   ((volatile uint32_t *) 0x500000F8) // {drops, accepts, reply_left, 0}
#define POST_FDCZ1  ((volatile uint32_t *) 0x50000100) // FIFO bytes 4..7 back
#define POST_FDCZ2  ((volatile uint32_t *) 0x50000104) // FIFO bytes 8..11 back
#define POST_FDCV   ((volatile uint32_t *) 0x50000108) // {0, last port, dead, live}
#define POST_LIVPC  ((volatile uint32_t *) 0x50000110) // {ip, cs} of the retired instruction
#define POST_DRAIL  ((volatile uint32_t *) 0x50000114) // {ip, cs} at the ROM-exit edge
#define POST_LAND   ((volatile uint32_t *) 0x50000118) // {ip, cs} of the first non-ROM instruction
#define POST_RING01 ((volatile uint32_t *) 0x5000011C) // the two newest retired ROM IPs
#define POST_RING23 ((volatile uint32_t *) 0x50000120) // the two older ones
#define POST_FR0    ((volatile uint32_t *) 0x50000124) // {byte, 20-bit addr} of the newest ROM read
#define POST_FR1    ((volatile uint32_t *) 0x50000128) // the one before
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
#define PANEL_H 192

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

// One segment's window: its digit, then the lowest and highest offset seen in
// it. Drawn through a helper, so check_osd_layout cannot evaluate the x
// expressions and does not see these fields -- which is safe only because
// rows 62 and 72 now belong to this and to nothing else.

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



static uint32_t romw_off  = 0;            // next chunk's file offset

static uint32_t romw_bad_at  = 0xFFFFFFFFu;  // first mismatch, guest linear
static uint8_t  romw_bad_file = 0, romw_bad_ram = 0;

void postmon_capture_rom(void)
{
    // Watch the stack LIVE dances on when everything else is frozen:
    // 0x110A0-0x110AF. If the CPU is hammering the drive probe, this window
    // catches the return addresses the pushes leave behind -- they name the
    // outer loop directly. Passive, like every ROMWIN read.
    *POST_ROMWIN = 0x14Eu;

    // A damage map, not a hex dump. FFFF0 came back byte-perfect while
    // F800E0 was unrecognisable -- not from any of the three ROM images -- so
    // the question is which parts of the 32 KB arrived, not what one of them
    // says. One byte from the head of each 4 KB page covers the lot.
    //
    // The file's values are FA 10 72 01 00 00 00 00; the last four pages read
    // 00 in the image itself, so only the first four carry information.
    // THE FULL 96 KB, once, against the dataslot original, while the guest
    // is still held: the bus belongs to the softcore and the peek cannot
    // starve anyone. A byte that arrived wrong from the stream (or a weak
    // cell that flips at write time -- deterministic, the same byte every
    // boot, which is what an identical derail site on every boot smells
    // like) is caught here, before the guest ever executes it.
    for (uint32_t off = 0; off < 0x18000u && romw_bad_at == 0xFFFFFFFFu;
         off += 256u) {
        *FDD_TDS_ID = 1;
        *FDD_TDS_OFFSET = off;
        *FDD_TDS_BRIDGE = 0x60000000u;
        *FDD_TDS_LENGTH = 256;
        *FDD_TDS_CLR = 1;
        *FDD_TDS_TRIG = FDD_TDS_READ;
        uint32_t to = 4000000u, st = 0;
        while (!((st = *FDD_TDS_STATUS) & FDD_TDS_DONE) && --to) {}
        if (to == 0 || (st & FDD_TDS_ERR)) {
            romw_bad_at = 0x1FFFFFu;         // marker: the reference failed
            romw_bad_file = st & 0xFF;
            romw_bad_ram  = 0xEE;
            break;
        }
        *FDD_BRAM_ADDR = 0;
        for (uint32_t i = 0; i < 256u; i += 4u) {
            uint32_t w = *FDD_BRAM_RDATA;     // one WORD per read, low byte first
            for (uint32_t b = 0; b < 4u; b++) {
                uint8_t want = (w >> (b * 8)) & 0xFF;
                uint8_t have = sdram_peek(0xE8000u + off + i + b);
                if (want != have) {
                    romw_bad_at   = 0xE8000u + off + i + b;
                    romw_bad_file = want;
                    romw_bad_ram  = have;
                    break;
                }
            }
            if (romw_bad_at != 0xFFFFFFFFu)
                break;
        }
    }
    romw_off = 0x18000u;                     // scan finished marker
}

// The ROM-copy watcher: the BIOS the CPU executes lives in SDRAM, streamed
// from the dataslot at boot. One flipped byte in that copy is one corrupted
// instruction and a derailed boot -- exactly the shape on the metal. The
// boot-time check reads only the first 256 bytes once; this one walks the
// whole 96 KB forever, pulling the ORIGINAL bytes back from the dataslot
// through the target-dataslot path and comparing against the copy in place.
// One 256-byte chunk per ~50000 loop passes: about a percent of the bus.


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

    // The repaint rate. This runs from the softcore's main loop, which spins
    // far faster than any eye needs, and LIVE -- a sampled guest address --
    // changes on effectively every call while the guest runs. Gating on "a
    // value moved" therefore repainted at the loop rate: clear, draw, clear,
    // draw, and the OSD showed the average of the two, which is the flicker
    // that made the panel unreadable on a running machine. So LIVE no longer
    // gates anything (the comment above said it didn't; the code disagreed),
    // and a repaint happens only when a SLOW field moved, or anyway once
    // every 65536 calls -- a few times a second at this loop's pace.
    static uint32_t calls = 0;
    calls++;
    if (status == last_status && maxrst == last_maxrst
        && tvram == last_tvram
        && (calls & 0xFFFFu) != 0u
        && idle_ticks != 4000u) {
        return;                            // nothing worth redrawing yet
    }
    last_tvram = tvram;
    last_status = status;
    last_maxrst = maxrst;

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

    // Words the ROM-load FIFO threw away, and how deep it ever got.
    //
    // Unconditional for the same reason the IO line is. A nonzero DROP means
    // the image in memory is incomplete before the CPU executes an
    // instruction, so it is the first thing worth knowing on ANY machine --
    // and it was sitting behind a PC/AT progress code a PC-98 never writes.
    // It is also the check that has to be repeated every time something makes
    // the SDRAM consumer slower.
    {
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
        hex(4 + 28 * 8, 2, romw_off ? 0u : 0u, 3); // retired spot check: always 0
        osd_draw_string(&fb, 4 + 32 * 8, 2, "AT", OSD_LABEL);
        hex(4 + 35 * 8, 2, 0u, 3);
        // The continuous watcher's verdict: RW = the offset it has walked to
        // (so you can see it live), R! = the first rot it ever caught, with
        // the file byte and what SDRAM holds instead. FF = clean so far.
        osd_draw_string(&fb, 4 + 34 * 8, 122, "RW", OSD_LABEL);
        hex(4 + 37 * 8, 122, romw_off >> 10, 2);   // 60 = scanned all 96 KB
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

    osd_draw_string(&fb, 4 + 17 * 8, 22, "LDN", OSD_LABEL);
    dec(4 + 21 * 8, 22, *POST_ROMLDN & 0xFFu);

    // HLD: the guest-reset terms, six one-digit fields, the hardware-band
    // strip's replacement -- same bits, legible. On row 82 after the TVH
    // block, which is the only real estate left (row 22's RST already means
    // max/restarts). In this order:
    //   SH soft_guest_hold   GH guest_hold_sync2   BL bios_ever_loaded
    //   IR interact_reset    RS reset (the guest)  LK ~RESET (PLL lock)
    // A lit bit is a term HOLDING the machine: BL 0 = the ROM loader never
    // finished; GH 1 with BL 1 = the boot hold never cleared; LK 0 = PLLs.
    uint32_t rt = *POST_RST;
    osd_draw_string(&fb, 224, 82, "HLD", OSD_LABEL);
    hex(250, 82, rt & 1u, 1);
    hex(260, 82, (rt >> 1) & 1u, 1);
    hex(270, 82, (rt >> 4) & 1u, 1);
    hex(280, 82, (rt >> 5) & 1u, 1);
    hex(290, 82, (rt >> 6) & 1u, 1);
    hex(300, 82, (rt >> 7) & 1u, 1);

    osd_draw_string(&fb, 4, 32, "LIVE", OSD_LABEL);
    hex(4 + 5 * 8, 32, live & 0xFFFFFu, 5);
    osd_draw_string(&fb, 4 + 12 * 8, 32, "HIGH", OSD_LABEL);
    hex(4 + 17 * 8, 32, *POST_LIVEMX & 0xFFFFFu, 5);

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
        // The V30's own CS:IP, retired-instruction granularity: the exact
        // instruction the machine is stuck on, against LIVE's RAM address.
        // The SEG/FR extent dump that shared this row is retired -- PC is the
        // one datum that ends the archaeology.
        {
            uint32_t pc = *POST_LIVPC;
            osd_draw_string(&fb, 4, 52, "PC", OSD_LABEL);
            hex(4 + 3 * 8, 52, (pc >> 16) & 0xFFFFu, 4);
            osd_draw_string(&fb, 4 + 7 * 8, 52, ":", OSD_LABEL);
            hex(4 + 8 * 8, 52, pc & 0xFFFFu, 4);
        }
        {
            // R0..R3: the last four retired ROM IPs (newest first), frozen
            // at the ROM exit -- the instruction sequence that derailed.
            // The layout: PC takes cols 0-12, R + four 4-hex IPs take
            // 14-31, all on this one row; DP retired into ring_ip0.
            uint32_t r01 = *POST_RING01, r23 = *POST_RING23;
            osd_draw_string(&fb, 4 + 14 * 8, 52, "R", OSD_LABEL);
            hex(4 + 15 * 8, 52, (r01 >> 16) & 0xFFFFu, 4);
            hex(4 + 19 * 8, 52, r01 & 0xFFFFu, 4);
            hex(4 + 23 * 8, 52, (r23 >> 16) & 0xFFFFu, 4);
            hex(4 + 27 * 8, 52, r23 & 0xFFFFu, 4);
        }
        {
            // L: the landing CS:IP -- the first non-ROM instruction the CPU
            // executed, on the R! row's right half (that row is empty while
            // the ROM watcher has nothing to report).
            uint32_t ld = *POST_LAND;
            osd_draw_string(&fb, 4 + 10 * 8, 22, "L", OSD_LABEL);
            hex(4 + 11 * 8, 22, ld & 0xFFFFu, 4);


        {
            // The two newest ROM-window reads: address then the byte the
            // bus actually returned. Against the file, this is the fetch
            // path's honesty test.
            uint32_t f0 = *POST_FR0;
        // CS: the cursor, as the master GDC holds it, packed ccEaaatb --
        // CSRW/CSRFORM count, enable, cell address, slice top, slice bottom.
        // cc 00 = the BIOS never sent a cursor command; E 0 = the
        // [0x53B]|0x80 enable never landed; t/b 0 with E 1 = the table
        // CSRFORM never ran and the cursor is a hairline; all sane = the
        // render path. One hex call: the panel row and the ROM budget both
        // wanted it that way.
        uint32_t cu = *POST_CUR;
        osd_draw_string(&fb, 200, 32, "CS", OSD_LABEL);
        hex(216, 32, cu, 8);

        // CT: the bytes that followed the LAST CSRFORM (4B) command, as the
        // GDC saw them on port 0x60: <n> (leftmost digit) is how many came
        // before another command cut the run, then the first three bytes in
        // order. The BIOS's cursor ON/OFF is one byte (n=1), the table form
        // three (n=3); anything else says the writes are shifted or shared.
        // One hex call, same reason as CS above.
        uint32_t ct = *POST_CT;
        osd_draw_string(&fb, 200, 62, "CT", OSD_LABEL);
        hex(216, 62, ct & 0x0FFFFFFFu, 7);
            osd_draw_string(&fb, 4 + 23 * 8, 42, "F", OSD_LABEL);
            hex(4 + 24 * 8, 42, f0 & 0xFFFFFu, 5);
            hex(4 + 30 * 8, 42, (f0 >> 24) & 0xFFu, 2);
        }
        }
        (void) p0; (void) p1; (void) seg_front_show;

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

    // History, oldest first, so the path through POST is visible at a glance.
    // PC/AT only: these are port-0x80 progress codes, and on PC-98 the row
    // belongs to the I/O trace -- which is what they were colliding with.

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
        (void)m;
        // STK: the snoop window's first eight bytes, low address left, on
        // the whole row -- the window parks on 0x500, the flags the boot
        // polls while everything else is frozen, and SZ/F0/KEY stand down
        // for the one build it takes to read them.
        // R!: the ROM watcher's catch, on the row the dead STK display
        // vacated -- file offset of the first rot, the byte the file has,
        // and the byte SDRAM actually holds.
        if (romw_bad_at != 0xFFFFFFFFu) {
            osd_draw_string(&fb, 4, 92, "R!", OSD_LABEL);
            hex(4 + 3 * 8, 92, romw_bad_at - 0xE8000u, 5);
            osd_draw_string(&fb, 4 + 9 * 8, 92, "F", OSD_LABEL);
            hex(4 + 10 * 8, 92, romw_bad_file, 2);
            osd_draw_string(&fb, 4 + 13 * 8, 92, "M", OSD_LABEL);
            hex(4 + 14 * 8, 92, romw_bad_ram, 2);
        }

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

        // Why the CPU stopped being interrupted. INT above froze while LIVE
        // kept moving, so the guest is running with nothing reaching it.
        //
        //   IL    INTR as a LEVEL, out of the PIC. The V30's own IF is not
        //         reachable -- v30_core's dbg_regs is inside `ifndef SYNTHESIS
        //         -- so this asks from the other side: INTR held high with the
        //         count frozen means the CPU is refusing it, i.e. IF=0.
        //   TMR   timer ticks, saturating. Frozen means the PIT stopped and
        //         there is nothing left to interrupt with.
        //   LVL   the master PIC's eight request lines, live:
        //         bit0 timer, bit1 keyboard, bit2 vsync, bit3 uart2,
        //         bit4 uart, bit5 -, bit6 fdd, bit7 slave.
        //
        // TMR frozen blames the PIT: nothing left to interrupt with. TMR
        // moving with IL 1 and INT frozen blames the guest -- the PIC is
        // asking and the CPU will not take it. TMR moving with IL 0 and INT
        // frozen blames the PIC: masked, or stuck in-service because an EOI
        // never landed.
        uint32_t il = *POST_IRQL;
        osd_draw_string(&fb, 4 + 16 * 8, 112, "IL", OSD_LABEL);
        hex(4 + 19 * 8, 112, (iv >> 16) & 1u, 1);
        osd_draw_string(&fb, 4 + 22 * 8, 112, "TMR", OSD_LABEL);
        hex(4 + 26 * 8, 112, (il >> 16) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 30 * 8, 112, "LVL", OSD_LABEL);
        hex(4 + 34 * 8, 112, (il >> 8) & 0xFFu, 2);

        // The master PIC's own registers -- the last blind spot. IL 0 with a
        // request line high says the chip has the request and is not passing
        // it on, and only these three say which:
        //
        //   R  IRR, requests latched
        //   M  IMR, masked off -- a SET bit is masked
        //   S  ISR, in service. A set bit blocks itself and everything BELOW
        //      it until an EOI clears it, and IRQ0 is the top of the master,
        //      so S 01 stuck means nothing else on this chip can ever arrive.
        uint32_t pc = *POST_PIC;
        osd_draw_string(&fb, 4, 122, "R", OSD_LABEL);
        hex(4 + 2 * 8, 122, pc & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 6 * 8, 122, "M", OSD_LABEL);
        hex(4 + 8 * 8, 122, (pc >> 8) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 12 * 8, 122, "S", OSD_LABEL);
        hex(4 + 14 * 8, 122, (pc >> 16) & 0xFFu, 2);

        // The vector byte the CPU actually received at the last INTA, and
        // how many acknowledges there have been. The two-PIC cascade is
        // protocol-clean (tb_pic_cascade) while the machine still parked
        // the BIOS in the drive probe, so delivery has to be watched on
        // metal:
        //
        //   V 13/12  a drive interrupt was delivered -- look at IVT13/12
        //   V 09     the keyboard (unmasked all boot) -- normal while idle
        //   V 0F     the master answered its own cascade line (spurious)
        //   V 00/other  the acknowledge came back wrong
        uint32_t pv = *POST_INTA;                 // {0, vector byte, count}
        osd_draw_string(&fb, 4 + 18 * 8, 122, "V", OSD_LABEL);
        hex(4 + 20 * 8, 122, (pv >> 16) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 24 * 8, 122, "x", OSD_LABEL);
        hex(4 + 25 * 8, 122, pv & 0xFFFFu, 4);

        // The two FDC vectors as last written by the guest, seg:off. The
        // drive probe interrupts through INT 13h (2HD) / INT 12h (2DD);
        // zeros mean the BIOS never installed them before the interrupt
        // fired. The healthy pair reads FD80:22F7 and FD80:2369.
        uint32_t v13 = *POST_IVT13, v12 = *POST_IVT12;
        osd_draw_string(&fb, 4, 132, "V13", OSD_LABEL);
        hex(4 + 4 * 8, 132, (v13 >> 16) & 0xFFFFu, 4);
        osd_draw_string(&fb, 4 + 9 * 8, 132, ":", OSD_LABEL);
        hex(4 + 10 * 8, 132, v13 & 0xFFFFu, 4);
        osd_draw_string(&fb, 4 + 16 * 8, 132, "V12", OSD_LABEL);
        hex(4 + 20 * 8, 132, (v12 >> 16) & 0xFFFFu, 4);
        osd_draw_string(&fb, 4 + 25 * 8, 132, ":", OSD_LABEL);
        hex(4 + 26 * 8, 132, v12 & 0xFFFFu, 4);

        // The drive probe's interrupt, link by link. The slave PIC's three
        // (r2/m2/s2 -- a SET m2 bit is masked) and the motor timer's arms
        // and expiry pulses. MA 00 means the 0xCC write never armed the
        // timer (a decode or window problem); MA>0 with r2's bit2/3 empty
        // means the pulse died between the glue and the slave; r2 set with
        // the master's R bit7 clear means the slave is holding it back
        // (mask or priority); everything set with V unchanged means the
        // master never passed it up.
        uint32_t p2 = *POST_PIC2, mo = *POST_MOTOR;
        osd_draw_string(&fb, 4, 142, "r2", OSD_LABEL);
        hex(4 + 3 * 8, 142, p2 & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 6 * 8, 142, "m2", OSD_LABEL);
        hex(4 + 9 * 8, 142, (p2 >> 8) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 12 * 8, 142, "s2", OSD_LABEL);
        hex(4 + 15 * 8, 142, (p2 >> 16) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 18 * 8, 142, "MA", OSD_LABEL);
        hex(4 + 21 * 8, 142, mo & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 24 * 8, 142, "MP", OSD_LABEL);
        hex(4 + 27 * 8, 142, (mo >> 8) & 0xFFu, 2);
        // The window register, 0xBE's last byte. Bit0 picks the live port
        // group (1 = 0x90/0x92/0x94, the 2HD one) and steers the
        // controller's interrupt lines. The motor circuit at 0xCC is
        // outside that guard -- it arms on any 0xCC write -- so G no longer
        // predicts MA.
        osd_draw_string(&fb, 4 + 30 * 8, 142, "G", OSD_LABEL);
        hex(4 + 32 * 8, 142, (mo >> 16) & 0xFFu, 2);

        // Strobe witnesses: did the glue's write strobe fire AT ALL, per
        // port? nBE/n94/nCC/nD count 0xBE / 0x94 / 0xCC / data-port writes
        // the glue saw; LB is the last control byte it carried. All zero
        // while the IO trace shows the writes means the strobe generation
        // -- not the glue -- is the dead link.
        uint32_t s1 = *POST_STRB1, s2 = *POST_STRB2, lb = *POST_LCTRL;
        osd_draw_string(&fb, 4, 152, "nBE", OSD_LABEL);
        hex(4 + 4 * 8, 152, s2 >> 16, 2);
        osd_draw_string(&fb, 4 + 7 * 8, 152, "n94", OSD_LABEL);
        hex(4 + 11 * 8, 152, s2 & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 14 * 8, 152, "nCC", OSD_LABEL);
        hex(4 + 18 * 8, 152, s1 & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 21 * 8, 152, "nD", OSD_LABEL);
        hex(4 + 24 * 8, 152, s1 >> 16, 2);
        osd_draw_string(&fb, 4 + 27 * 8, 152, "LB", OSD_LABEL);
        hex(4 + 30 * 8, 152, lb & 0xFFu, 2);
        // The last byte written to 0xBE -- chgreg, the window register.
        // Bit 0 picks which port group is live (1 = 0x9x / 2HD); the BIOS
        // flips it on the way into the 2DD probe, and a value stuck at FB
        // while the probe hammers 0xC8 is the dead-window hang in one byte.
        osd_draw_string(&fb, 4 + 33 * 8, 152, "CH", OSD_LABEL);
        hex(4 + 36 * 8, 152, (*POST_FDCY >> 16) & 0xFFu, 2);

        // The write path counted in PERIPHERALS itself: EX = pc98_io_exact
        // clocks, RD/WR = read/write levels on the FDC selects, ST = the
        // raw io_write_n strobe (any port). EX 00 convicts the decode;
        // RD>0 WR 00 convicts io_write_n for these ports; WR>0 ST 00
        // convicts the edge detector.
        // The read side of the MSR poll, which is the boot's inner loop. LV
        // counts reads that REACHED floppy.v; DD counts the ones the window
        // guard turned away, which the chipset answers 0xFF -- and 0xFF & D0
        // is D0, so a guest polling a dead window waits for a busy bit that
        // will never fall. LP is the last FDC port read: 90/92 is the 2HD
        // window, C8/CA the 2DD one. MS only moves on a live read, so MS D0
        // beside RL 0 means the guest has been reading something else.
        //
        // This row replaces EX/RD/WR/ST: the write path they convicted is
        // fixed and they have all been saturated for three builds.
        uint32_t fv = *POST_FDCV;
        osd_draw_string(&fb, 4, 162, "LV", OSD_LABEL);
        hex(4 + 3 * 8, 162, fv & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 6 * 8, 162, "DD", OSD_LABEL);
        hex(4 + 9 * 8, 162, (fv >> 8) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 12 * 8, 162, "LP", OSD_LABEL);
        hex(4 + 15 * 8, 162, (fv >> 16) & 0xFFu, 2);
        // LR: the port of the last I/O read, period -- names the poll loop
        // the CPU is spinning in right now when everything else is frozen.
        osd_draw_string(&fb, 4 + 18 * 8, 162, "LR", OSD_LABEL);
        hex(4 + 21 * 8, 162, (fv >> 24) & 0xFFu, 2);
        // What the CPU last READ from the slave PIC's IMR port -- against
        // m2, which is the register itself. F7 here and the guard passes;
        // anything with bit 3 set and the probe is bailing on a ghost.
        osd_draw_string(&fb, 4 + 24 * 8, 162, "0A", OSD_LABEL);
        hex(4 + 27 * 8, 162, *POST_FDCW & 0xFFu, 2);

        // The controller itself. MS is the MSR the guest last read -- 80
        // means RQM with the chip idle and ready, C0 means it wants to be
        // read, 10 in bit 4 is a command in progress. IQ counts floppy.v's
        // irq RISES: 00 with commands going in (nD) says the chip never
        // asked for attention, and then DO says whether it was allowed to --
        // bit 3 of the DOR is the interrupt enable, and it is built from the
        // guest's bit 3 at the last 0x94 write. RD counts result bytes read
        // back. 94 and CC are the last byte written to each control port,
        // kept apart: LB above mixes them.
        uint32_t fx = *POST_FDCX, fy = *POST_FDCY;
        // Seven fields at a five-column pitch. 94 and CC are gone: both have
        // read 48 on every build since they started arriving, and the space
        // buys the command stream below. CA counts the bytes floppy.v took
        // AS A COMMAND, CD the ones it dropped because it was busy or
        // mid-result, RL the result bytes it is still holding.
        uint32_t fw = *POST_FDCW;
        osd_draw_string(&fb, 4, 172, "MS", OSD_LABEL);
        hex(4 + 2 * 8, 172, fx & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 5 * 8, 172, "IQ", OSD_LABEL);
        hex(4 + 7 * 8, 172, (fx >> 8) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 10 * 8, 172, "DO", OSD_LABEL);
        hex(4 + 12 * 8, 172, (fx >> 16) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 15 * 8, 172, "RD", OSD_LABEL);
        hex(4 + 17 * 8, 172, (fx >> 24) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 20 * 8, 172, "CA", OSD_LABEL);
        hex(4 + 22 * 8, 172, (fw >> 16) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 25 * 8, 172, "CD", OSD_LABEL);
        hex(4 + 27 * 8, 172, (fw >> 24) & 0xFFu, 2);
        osd_draw_string(&fb, 4 + 30 * 8, 172, "RL", OSD_LABEL);
        hex(4 + 32 * 8, 172, (fw >> 8) & 0x0Fu, 1);

        // The command stream, TWELVE bytes, oldest on the left. 03 xx xx is
        // a SPECIFY, 07 uu a RECALIBRATE of unit uu, 08 a SENSE INTERRUPT
        // STATUS, 04 uu a SENSE DRIVE STATUS. Four bytes only showed the
        // tail, and a tail read two ways cost a build: the sequence
        // reconstructed from 07 03 08 08 passed in simulation while the
        // machine it came from hung. RB is the last byte read back out.
        osd_draw_string(&fb, 4, 182, "FW", OSD_LABEL);
        hex(4 + 3 * 8, 182, *POST_FDCZ2, 8);
        hex(4 + 11 * 8, 182, *POST_FDCZ1, 8);
        hex(4 + 19 * 8, 182, *POST_FDCZ, 8);
        osd_draw_string(&fb, 4 + 28 * 8, 182, "RB", OSD_LABEL);
        hex(4 + 31 * 8, 182, (fy >> 24) & 0xFFu, 2);

        // [0x480] itself, the single byte that matters, in this row's
        // remaining right margin: bit 4 is "a 2HD drive exists", the flag
        // every motor-on and every SENSE DRIVE STATUS probe in the INT 1Bh
        // driver consults. Read off the softcore's own bus, so it costs the
        // guest nothing to draw.
        osd_draw_string(&fb, 4 + 30 * 8, 122, "W", OSD_LABEL);
        {
            volatile uint32_t *romd = (volatile uint32_t *) 0x50000044u;
            hex(4 + 32 * 8, 122, romd[0] & 0xFFu, 2);
        }
    }

    *VKB_CTRL = 1u;
}

#endif // !SDRAM_SELFTEST
