// In-core SDRAM self-test -- see sdramtest.h and docs/P0_SELFTEST_SPEC.md.

#include <stdint.h>
#include "softcpu_regs.h"
#include "vkb_draw.h"
#include "sdramtest.h"

// Self-test window into guest SDRAM (region 0x5). core_top's ext-port master
// performs the access; these registers only hand it the parameters. It has its
// own region because every decode in 0x2 matches on cpu_mem_addr[4:2] and so
// ignores bit 5 -- 0x20000030 would have aliased onto OSD_ACTION at 0x10.
#define ST_ADDR   ((volatile uint32_t *) 0x50000000) // W: guest address[19:0]
#define ST_WDATA  ((volatile uint32_t *) 0x50000004) // W: byte to write
#define ST_TRIG   ((volatile uint32_t *) 0x50000008) // W: bit0 write, bit1 read
#define ST_STATUS ((volatile uint32_t *) 0x5000000C) // R: {busy[8], rdata[7:0]}

#define ST_BUSY (1u << 8)

// The master has its own 200-cycle guard, so an access that never completes
// still returns. This bound only covers the bus handshake and is deliberately
// SMALL: run#61 showed nothing at all on screen, and one of the two candidate
// causes was every access spinning here, which at the old 100000 would have
// taken hours over 64 KB. A stuck access must degrade to a wrong answer we can
// read, never to a hang.
#define ST_SPIN 2000u

static uint32_t st_wait(void)
{
    uint32_t s = 0;
    for (uint32_t i = 0; i < ST_SPIN; i++) {
        s = *ST_STATUS;
        if (!(s & ST_BUSY))
            return s;
    }
    return s; // still busy: caller sees the stale byte, which shows up as a miss
}

static void sd_poke(uint32_t addr, uint8_t v)
{
    *ST_ADDR = addr;
    *ST_WDATA = v;
    *ST_TRIG = 1u; // write
    st_wait();
}

static uint8_t sd_peek(uint32_t addr)
{
    *ST_ADDR = addr;
    *ST_TRIG = 2u; // read
    return (uint8_t) (st_wait() & 0xFFu);
}

// Address-derived pattern. A constant would pass even if the address lines were
// scrambled, which is exactly one of the things still on the table.
static uint8_t pat(uint32_t a)
{
    return (uint8_t) (((a * 0x9Du) ^ 0x5Au) & 0xFFu);
}

// ---------------------------------------------------------------- reporting
//
// NOT CGA text VRAM. testB11 wrote there and nothing appeared, and simulation
// then showed why: an ext-port access runs under BUS_ARBITER's hold
// acknowledge, Bus_Arbiter.sv drives address_enable_n from it, and
// Peripherals.sv gates cga_mem_select on ~address_enable_n. So the CGA never
// claims those cycles. External masters can write SDRAM -- RAM.sv does not
// look at address_enable_n, which is why the BIOS loader works -- but they
// cannot write CGA VRAM at all. That channel is architecturally dead.
//
// So: the OSD overlay, whose pixel path is now verified in tb_selftest_soc.

static const osd_fb_t fb = {0, 0, OSD_FB_WIDTH, OSD_FB_HEIGHT};

// vkb_ui owns this normally: the origin comes from the presented raster and is
// written BEFORE the overlay is enabled.
static void osd_show(void)
{
    uint32_t raster = *OSD_RASTER;
    uint32_t w = raster & 0x3FFu;
    uint32_t h = (raster >> 16) & 0x3FFu;
    uint32_t x = (w > OSD_FB_WIDTH) ? (w - OSD_FB_WIDTH) / 2u : 0u;
    uint32_t y = (h > OSD_FB_HEIGHT) ? (h - OSD_FB_HEIGHT) / 2u : 0u;
    *OSD_ORIGIN = (y << 16) | x;
    *VKB_CTRL = 1u;
}

static void put_hex(int x, int y, uint32_t v, int digits)
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

static void put_dec(int x, int y, uint32_t v)
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

static void say(int row, const char *s) { osd_draw_string(&fb, 8, row * 10 + 8, s, OSD_LABEL); }

// ---------------------------------------------------------------------- test

#define BASE_LEN 0x10000u // the base 64 KB: what three beeps points at

void sdram_selftest_run(void)
{
    // Overlay up and a banner drawn before any SDRAM access, so "nothing on
    // screen" and "the test stalled" can never look the same again.
    //
    // The panel fill is NOT decoration. OSD_LABEL is palette 5, 0x101010 --
    // near black. testB13 cleared to OSD_CLEAR (palette 0, transparent) and
    // drew that straight over the splash, so the text was rendered exactly as
    // simulated and invisible on the panel. settings_ui fills with a light
    // colour first for this reason; do the same.
    osd_clear_screen();
    osd_fill_rect(&fb, 0, 0, OSD_FB_WIDTH, OSD_FB_HEIGHT, OSD_KEYFACE);
    osd_show();
    say(0, "SDRAM SELFTEST");

    sd_poke(0x00040u, 0xA5u);
    say(1, "PILOT  WANT A5 GOT");
    put_hex(8 + 19 * 8, 1 * 10 + 8, sd_peek(0x00040u), 2);

    // Bank 1 under sdram_mp's addr[10:9] mapping; KFSDRAM keeps this whole
    // region in bank 0, which is the difference being hunted.
    sd_poke(0x00240u, 0x5Au);
    say(2, "PILOT2 WANT 5A GOT");
    put_hex(8 + 19 * 8, 2 * 10 + 8, sd_peek(0x00240u), 2);

    uint32_t errors = 0, first_addr = 0;
    uint8_t first_got = 0, first_want = 0;
    int failed = 0;

    // Write the whole region before reading any of it: interleaving would hide
    // damage a later write does to an earlier address.
    for (uint32_t a = 0; a < BASE_LEN; a++) {
        if ((a & 0xFFFu) == 0) { say(4, "WRITE"); put_hex(8 + 6 * 8, 4 * 10 + 8, a, 5); }
        sd_poke(a, pat(a));
    }
    for (uint32_t a = 0; a < BASE_LEN; a++) {
        if ((a & 0xFFFu) == 0) { say(4, "READ "); put_hex(8 + 6 * 8, 4 * 10 + 8, a, 5); }
        uint8_t got = sd_peek(a);
        if (got != pat(a)) {
            if (!failed) { failed = 1; first_addr = a; first_got = got; first_want = pat(a); }
            errors++;
        }
    }

    for (;;) {
        if (!failed) {
            say(6, "PASS 64K");
        } else {
            say(6, "FAIL @");
            put_hex(8 + 7 * 8, 6 * 10 + 8, first_addr, 5);
            say(6, "");
            osd_draw_string(&fb, 8 + 14 * 8, 6 * 10 + 8, "GOT", OSD_LABEL);
            put_hex(8 + 18 * 8, 6 * 10 + 8, first_got, 2);
            osd_draw_string(&fb, 8 + 22 * 8, 6 * 10 + 8, "WANT", OSD_LABEL);
            put_hex(8 + 27 * 8, 6 * 10 + 8, first_want, 2);

            // The decode is the point: sdram_mp spreads this region over four
            // banks where KFSDRAM keeps it in bank 0.
            say(7, "BANK");
            put_dec(8 + 5 * 8, 7 * 10 + 8, (first_addr >> 9) & 3u);
            osd_draw_string(&fb, 8 + 8 * 8, 7 * 10 + 8, "ROW", OSD_LABEL);
            put_hex(8 + 12 * 8, 7 * 10 + 8, first_addr >> 11, 4);
            osd_draw_string(&fb, 8 + 18 * 8, 7 * 10 + 8, "COL", OSD_LABEL);
            put_hex(8 + 22 * 8, 7 * 10 + 8, first_addr & 0x1FFu, 3);

            // One bad byte and total garbage have different causes.
            say(8, "ERRORS");
            put_dec(8 + 7 * 8, 8 * 10 + 8, errors);
            osd_draw_string(&fb, 8 + 18 * 8, 8 * 10 + 8, "OF 65536", OSD_LABEL);
        }
    }
}
