// In-core SDRAM self-test -- see sdramtest.h and docs/P0_SELFTEST_SPEC.md.

#include <stdint.h>
#include "softcpu_regs.h"
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

// ------------------------------------------------- reporting via CGA text VRAM
//
// run#61 and run#63 both came back "splash, nothing else" -- not even the
// banner that is drawn before any SDRAM access. So the OSD overlay is not a
// usable output channel here, and two hardware runs were spent learning only
// that.
//
// CGA text VRAM is. The splash itself is a text-mode screen copied into it
// (Peripherals.sv: SPLASH_COPY / TEXT_CLEAR_SIZE 16384), so we know for a fact
// it is on screen right now. Writing character/attribute pairs there needs no
// OSD compositor, no origin register and no overlay enable.
//
// It also splits the remaining question by itself: 0xB0000-0xBFFFF is excluded
// from SDRAM in RAM.sv, so these writes exercise the ext-port master WITHOUT
// touching the SDRAM controller. Text appearing means the firmware runs and the
// master works, and anything wrong after that is the SDRAM's.

#define CGA_TEXT 0xB8000u
#define CGA_ATTR 0x0Fu // white on black

static void vram_putc(uint32_t row, uint32_t col, char c)
{
    uint32_t off = CGA_TEXT + (row * 80u + col) * 2u;
    sd_poke(off, (uint8_t) c);
    sd_poke(off + 1u, CGA_ATTR);
}

static void vram_puts(uint32_t row, uint32_t col, const char *s)
{
    for (uint32_t i = 0; s[i] && (col + i) < 80u; i++)
        vram_putc(row, col + i, s[i]);
}

static void vram_hex(uint32_t row, uint32_t col, uint32_t v, int digits)
{
    for (int i = digits - 1; i >= 0; i--) {
        uint32_t nib = v & 0xFu;
        vram_putc(row, col + (uint32_t) i,
                  (char) (nib < 10 ? '0' + nib : 'A' + (nib - 10)));
        v >>= 4;
    }
}

static void vram_dec(uint32_t row, uint32_t col, uint32_t v)
{
    char buf[11];
    int n = 0;
    if (v == 0)
        buf[n++] = '0';
    while (v && n < 10) {
        buf[n++] = (char) ('0' + (v % 10u));
        v /= 10u;
    }
    for (int i = 0; i < n; i++)
        vram_putc(row, col + (uint32_t) i, buf[n - 1 - i]);
}

// ---------------------------------------------------------------------- test

#define BASE_LEN 0x10000u // the base 64 KB: what three beeps points at

void sdram_selftest_run(void)
{
    // First thing, before anything can go wrong: prove the firmware got here
    // and the ext-port master can write. If this line does not appear, nothing
    // below matters and the two candidates are "firmware never reaches this
    // function" and "the ext master does not work at all".
    vram_puts(2, 2, "SELFTEST START");

    // Pilot on real SDRAM. Separate line so it is obvious whether we got past
    // the VRAM write. GOT should read A5.
    sd_poke(0x00040u, 0xA5u);
    vram_puts(3, 2, "PILOT WANT A5 GOT");
    vram_hex(3, 20, sd_peek(0x00040u), 2);

    // A second pilot in a different bank: bank = addr[10:9] for sdram_mp, so
    // 0x00240 is bank 1 where 0x00040 is bank 0. KFSDRAM keeps this whole
    // region in bank 0, which is the difference we are hunting.
    sd_poke(0x00240u, 0x5Au);
    vram_puts(4, 2, "PILOT2 WANT 5A GOT");
    vram_hex(4, 21, sd_peek(0x00240u), 2);

    uint32_t errors = 0;
    uint32_t first_addr = 0;
    uint8_t first_got = 0, first_want = 0;
    int failed = 0;

    // Write the whole region, then read the whole region. Interleaving would
    // hide damage a later write does to an earlier address, which is the shape
    // of most SDRAM faults.
    for (uint32_t a = 0; a < BASE_LEN; a++) {
        if ((a & 0xFFFu) == 0) {
            vram_puts(6, 2, "WRITE");
            vram_hex(6, 8, a, 5);
        }
        sd_poke(a, pat(a));
    }

    for (uint32_t a = 0; a < BASE_LEN; a++) {
        if ((a & 0xFFFu) == 0) {
            vram_puts(6, 2, "READ ");
            vram_hex(6, 8, a, 5);
        }
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

    if (!failed) {
        vram_puts(8, 2, "PASS 64K");
    } else {
        vram_puts(8, 2, "FAIL @");
        vram_hex(8, 9, first_addr, 5);
        vram_puts(8, 16, "GOT");
        vram_hex(8, 20, first_got, 2);
        vram_puts(8, 24, "WANT");
        vram_hex(8, 29, first_want, 2);

        // sdram_mp maps {row, bank, col} = addr[19:11], addr[10:9], addr[8:0].
        // Printing the decode is the point: KFSDRAM's mapping keeps this whole
        // region in bank 0 while sdram_mp spreads it over all four.
        vram_puts(9, 2, "BANK");
        vram_dec(9, 7, (first_addr >> 9) & 3u);
        vram_puts(9, 10, "ROW");
        vram_hex(9, 14, first_addr >> 11, 4);
        vram_puts(9, 20, "COL");
        vram_hex(9, 24, first_addr & 0x1FFu, 3);

        // One bad byte and total garbage have completely different causes.
        vram_puts(10, 2, "ERRORS");
        vram_dec(10, 9, errors);
        vram_puts(10, 20, "OF 65536");
    }

    // Redraw forever: if the splash timer expires it clears text VRAM
    // (Peripherals.sv splash_clear), and the result must survive that.
    for (;;) {
        if (!failed) {
            vram_puts(8, 2, "PASS 64K");
        } else {
            vram_puts(8, 2, "FAIL @");
            vram_hex(8, 9, first_addr, 5);
            vram_puts(8, 16, "GOT");
            vram_hex(8, 20, first_got, 2);
            vram_puts(8, 24, "WANT");
            vram_hex(8, 29, first_want, 2);
            vram_puts(9, 2, "BANK");
            vram_dec(9, 7, (first_addr >> 9) & 3u);
            vram_puts(9, 10, "ROW");
            vram_hex(9, 14, first_addr >> 11, 4);
            vram_puts(9, 20, "COL");
            vram_hex(9, 24, first_addr & 0x1FFu, 3);
            vram_puts(10, 2, "ERRORS");
            vram_dec(10, 9, errors);
            vram_puts(10, 20, "OF 65536");
        }
    }
}
