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

// The master has its own 200-cycle guard, so a stuck controller returns a wrong
// answer rather than hanging. This bound only covers the bus handshake itself
// and exists so a broken build cannot wedge the softcore before it can draw.
#define ST_SPIN 100000u

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

static const osd_fb_t fb = {0, 0, OSD_FB_WIDTH, OSD_FB_HEIGHT};

static void put_hex(int x, int y, uint32_t v, int digits, uint8_t color)
{
    char buf[9];
    for (int i = digits - 1; i >= 0; i--) {
        uint32_t nib = v & 0xFu;
        buf[i] = (char) (nib < 10 ? '0' + nib : 'A' + (nib - 10));
        v >>= 4;
    }
    buf[digits] = 0;
    osd_draw_string(&fb, x, y, buf, color);
}

static void put_dec(int x, int y, uint32_t v, uint8_t color)
{
    char buf[11];
    int n = 0;
    if (v == 0)
        buf[n++] = '0';
    while (v && n < 10) {
        buf[n++] = (char) ('0' + (v % 10u));
        v /= 10u;
    }
    char out[11];
    for (int i = 0; i < n; i++)
        out[i] = buf[n - 1 - i];
    out[n] = 0;
    osd_draw_string(&fb, x, y, out, color);
}

// ---------------------------------------------------------------------- test

#define BASE_LEN 0x10000u // the base 64 KB: what three beeps points at

void sdram_selftest_run(void)
{
    uint32_t errors = 0;
    uint32_t first_addr = 0;
    uint8_t first_got = 0, first_want = 0;
    int failed = 0;

    // Pass 1: write the whole region, then read the whole region. Interleaving
    // write and read per address would hide damage that a later write inflicts
    // on an earlier one, which is the shape of most SDRAM faults.
    for (uint32_t a = 0; a < BASE_LEN; a++)
        sd_poke(a, pat(a));

    for (uint32_t a = 0; a < BASE_LEN; a++) {
        uint8_t got = sd_peek(a);
        if (got != pat(a)) {
            if (!failed) {
                failed = 1;
                first_addr = a;
                first_got = got;
                first_want = pat(a);
            }
            errors++;
        }
    }

    // Pass 2: refresh hold. Everything above is already written, so simply wait
    // and re-read a sample. Only a refresh fault shows up here.
    uint32_t retention_errors = 0;
    if (!failed) {
        for (volatile uint32_t d = 0; d < 400000u; d++)
            ;
        for (uint32_t a = 0; a < BASE_LEN; a += 251u) {
            uint8_t got = sd_peek(a);
            if (got != pat(a)) {
                if (!failed) {
                    failed = 1;
                    first_addr = a;
                    first_got = got;
                    first_want = pat(a);
                }
                retention_errors++;
            }
        }
    }

    osd_clear_screen();
    osd_draw_string(&fb, 8, 8, "SDRAM SELFTEST", OSD_LABEL);

    if (!failed) {
        osd_draw_string(&fb, 8, 24, "PASS  BYTES ", OSD_LABEL);
        put_dec(8 + 12 * 8, 24, BASE_LEN, OSD_LABEL);
    } else {
        osd_draw_string(&fb, 8, 24, "FAIL @", OSD_LABEL);
        put_hex(8 + 7 * 8, 24, first_addr, 5, OSD_LABEL);
        osd_draw_string(&fb, 8 + 13 * 8, 24, "GOT", OSD_LABEL);
        put_hex(8 + 17 * 8, 24, first_got, 2, OSD_LABEL);
        osd_draw_string(&fb, 8 + 20 * 8, 24, "WANT", OSD_LABEL);
        put_hex(8 + 25 * 8, 24, first_want, 2, OSD_LABEL);

        // sdram_mp maps {row, bank, col} = addr[19:11], addr[10:9], addr[8:0].
        // KFSDRAM puts bank in addr[23:22], which this design never drives, so
        // its base 64 KB sits entirely in bank 0 while sdram_mp spreads the
        // same region over all four. Printing the decode is the whole point.
        osd_draw_string(&fb, 8, 40, "BANK", OSD_LABEL);
        put_dec(8 + 5 * 8, 40, (first_addr >> 9) & 3u, OSD_LABEL);
        osd_draw_string(&fb, 8 + 8 * 8, 40, "ROW", OSD_LABEL);
        put_hex(8 + 12 * 8, 40, first_addr >> 11, 4, OSD_LABEL);
        osd_draw_string(&fb, 8 + 18 * 8, 40, "COL", OSD_LABEL);
        put_hex(8 + 22 * 8, 40, first_addr & 0x1FFu, 3, OSD_LABEL);

        // One bad byte and total garbage have completely different causes.
        osd_draw_string(&fb, 8, 56, "ERRORS", OSD_LABEL);
        put_dec(8 + 7 * 8, 56, errors, OSD_LABEL);
        osd_draw_string(&fb, 8 + 18 * 8, 56, "OF", OSD_LABEL);
        put_dec(8 + 21 * 8, 56, BASE_LEN, OSD_LABEL);

        if (retention_errors) {
            osd_draw_string(&fb, 8, 72, "RETENTION FAILS", OSD_LABEL);
            put_dec(8 + 16 * 8, 72, retention_errors, OSD_LABEL);
        }
    }

    *VKB_CTRL = 1u; // show the overlay and leave it up
}
