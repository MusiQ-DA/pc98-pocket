// gdc_service.c -- the GDC drawing processor, served by the softcore.
//
// The RTL (pc98_gdc) latches each EXECUTE-class command (VECTE 0x6C, TEXTE
// 0x68) with a snapshot of the vector parameters and throttles the guest --
// the FIFO-empty status bit stays clear -- until this engine retires it.
// What runs here is np2kai's engine (io/gdc_sub.c + io/gdc_pset.c) with the
// VRAM layer retargeted: every pixel is a read-modify-write of one guest
// byte through the self-test master, which takes the bus through hold --
// cycle stealing, exactly what the real chip's memory cycles did.
//
// np2's own scoping is kept: only the SLAVE draws (np2kai gdc.c guards with
// "id != GDCWORK_MASTER"); the master's EXECUTEs retire immediately. GRCG-
// with-GDC (port 0x7C bit 3) is not carried over yet -- its tile registers
// live in RTL this side cannot see -- so drawing in that mode falls back to
// plain replacement on the selected plane. TEXTE currently draws the 16-bit
// TEXTW pattern rather than the full 8-byte PRAM pattern; the snapshot
// widens when a title proves it matters.

#include "softcpu_regs.h"

// The self-test master, the same registers postmon peeks guest memory with:
// one trigger, then poll the request level down.
#define ST_ADDR   ((volatile uint32_t *) 0x50000000)
#define ST_WDATA  ((volatile uint32_t *) 0x50000004)
#define ST_TRIG   ((volatile uint32_t *) 0x50000008)
#define ST_STATUS ((volatile uint32_t *) 0x5000000C)
#define ST_PEND   (1u << 8)

// The two channels' register windows. The 0x140 block is the master, 0x180
// the slave: {status, snap0..snap4} then the done register at +0x1C.
#define GDCD_STATUS(ch) ((volatile uint32_t *) (0x50000140u + (ch) * 0x40u))
#define GDCD_SNAPW(ch)  ((volatile uint32_t *) (0x50000144u + (ch) * 0x40u))
#define GDCD_DONE(ch)   ((volatile uint32_t *) (0x5000015Cu + (ch) * 0x40u))

#define GDC_CH_MASTER 0
#define GDC_CH_SLAVE  1
#define GDC_OP_VECTE  0x6Cu
#define GDC_OP_TEXTE  0x68u

// The snapshot, nineteen bytes in the order the RTL packs them: VECTW's
// eleven, CSRW's four (np2 reads a dword -- the fourth byte's high nibble
// is the dot address), TEXTW's two, ZOOM, the WRITE-mode byte.
struct gdc_snap {
    uint8_t ope;
    uint8_t dc_lo, dc_hi;
    uint8_t d_lo, d_hi;
    uint8_t d2_lo, d2_hi;
    uint8_t d1_lo, d1_hi;
    uint8_t dm_lo, dm_hi;
    uint8_t csrw[4];
    uint8_t textw[2];
    uint8_t zoom;
    uint8_t write_mode;
};

// np2's direction table: {x, y, x2, y2} steps for octants 0-7 and the
// SL-flavoured 8-15 (io/gdc_sub.c vectdir).
static const int8_t vectdir[16][4] = {
    { 0, 1, 1, 0 },
    { 1, 1, 1, -1 },
    { 1, 0, 0, -1 },
    { 1, -1, -1, -1 },
    { 0, -1, -1, 0 },
    { -1, -1, -1, 1 },
    { -1, 0, 0, 1 },
    { -1, 1, 1, 1 },
    { 0, 1, 1, 1 },
    { 1, 1, 1, 0 },
    { 1, 0, 1, -1 },
    { 1, -1, 0, -1 },
    { 0, -1, -1, -1 },
    { -1, -1, -1, 0 },
    { -1, 0, -1, 1 },
    { -1, 1, 0, 1 },
};

// np2's gdcplaneseg order: EAD bits 15-14 select the plane; the bases are
// the hardware windows (A8000=B, B0000=R, B8000=G, E at E0000).
static const uint32_t plane_base[4] = { 0xE0000, 0xA8000, 0xB0000, 0xB8000 };

// np2's gdcbitreverse, built at boot: a table would cost 256 ROM bytes.
static uint8_t bitreverse[256];
static int gdc_inited = 0;

// The softcore has no divider (nodiv-verify gates it), so every division
// here goes through the restoring long divide ide_service.c uses.
static uint32_t udiv32(uint32_t n, uint32_t d, uint32_t *rem)
{
    uint32_t q = 0u, r = 0u;
    if (d == 0u) {
        if (rem) {
            *rem = 0u;
        }
        return 0u;
    }
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) {
            r -= d;
            q |= 1u << i;
        }
    }
    if (rem) {
        *rem = r;
    }
    return q;
}

static void init_bitreverse(void)
{
    for (int i = 0; i < 256; i++) {
        uint8_t r = 0, v = (uint8_t) i;
        for (int b = 0; b < 8; b++) {
            r = (uint8_t) ((r << 1) | (v & 1u));
            v >>= 1;
        }
        bitreverse[i] = r;
    }
}

// One guest byte through the self-test master, postmon's guest_peek idiom:
// bounded, so a wedged bus degrades to a wrong pixel rather than a hang.
static uint8_t vr_read8(uint32_t addr)
{
    uint32_t s = 0;
    *ST_ADDR = addr & 0xFFFFFu;
    *ST_TRIG = 2u; // read
    for (uint32_t i = 0; i < 2000u; i++) {
        s = *ST_STATUS;
        if (!(s & ST_PEND)) {
            break;
        }
    }
    return (uint8_t) (s & 0xFFu);
}

static void vr_write8(uint32_t addr, uint8_t v)
{
    *ST_ADDR = addr & 0xFFFFFu;
    *ST_WDATA = v;
    *ST_TRIG = 1u; // write
    for (uint32_t i = 0; i < 2000u; i++) {
        if (!(*ST_STATUS & ST_PEND)) {
            break;
        }
    }
}

// The pset state np2's gdcpset_prepare/gdcpset carry.
static struct {
    uint16_t pattern;
    uint16_t x, y;
    uint32_t base;
    uint8_t op; // 0 replace 1 complement 2 clear 3 set
} pset;

static void pset_prepare(uint32_t csrw, uint16_t pat, uint8_t ope)
{
    pset.pattern = pat;
    pset.base = plane_base[(csrw >> 14) & 3u];
    pset.op = ope & 3u;
    // np2 hardcodes forty words per drawing line (640 dots); PITCH unused.
    uint32_t rem;
    pset.y = (uint16_t) udiv32(csrw & 0x3FFFu, 40u, &rem);
    pset.x = (uint16_t) ((rem << 4) + ((csrw >> 20) & 0x0Fu));
}

static void pset_at(int x, int y)
{
    uint8_t dot = pset.pattern & 1u;
    pset.pattern = (uint16_t) ((pset.pattern >> 1) | ((uint16_t) dot << 15));
    x &= 0xFFFF;
    y &= 0xFFFF;
    if (y > 409 || (y == 409 ? (x >= 384) : (x >= 640))) {
        return;
    }
    uint32_t addr = pset.base + (uint32_t) y * 80u + (uint32_t) (x >> 3);
    uint8_t bit = (uint8_t) (0x80u >> (x & 7));
    uint8_t v = vr_read8(addr);
    switch (pset.op) {
    case 0: // replace: the pattern bit decides
        v = dot ? (uint8_t) (v | bit) : (uint8_t) (v & ~bit);
        break;
    case 1: // complement
        if (dot) {
            v ^= bit;
        }
        break;
    case 2: // clear
        if (dot) {
            v &= (uint8_t) ~bit;
        }
        break;
    default: // set
        if (dot) {
            v |= bit;
        }
        break;
    }
    vr_write8(addr, v);
}

// ---- the primitives, np2's algorithms verbatim ---------------------------

static void vectl(const struct gdc_snap *g)
{
    uint32_t dc = (g->dc_lo | ((uint32_t) g->dc_hi << 8)) & 0x3FFFu;
    if (dc == 0) {
        pset_at(pset.x, pset.y);
        return;
    }
    uint32_t d1 = g->d1_lo | ((uint32_t) g->d1_hi << 8);
    int x = pset.x, y = pset.y;
    switch (g->ope & 7) {
    case 0:
        for (uint32_t i = 0; i <= dc; i++) {
            pset_at(x + (int) ((udiv32(d1 * i, dc, 0) + 1) >> 1), y++);
        }
        break;
    case 1:
        for (uint32_t i = 0; i <= dc; i++) {
            pset_at(x++, y + (int) ((udiv32(d1 * i, dc, 0) + 1) >> 1));
        }
        break;
    case 2:
        for (uint32_t i = 0; i <= dc; i++) {
            pset_at(x++, y - (int) ((udiv32(d1 * i, dc, 0) + 1) >> 1));
        }
        break;
    case 3:
        for (uint32_t i = 0; i <= dc; i++) {
            pset_at(x + (int) ((udiv32(d1 * i, dc, 0) + 1) >> 1), y--);
        }
        break;
    case 4:
        for (uint32_t i = 0; i <= dc; i++) {
            pset_at(x - (int) ((udiv32(d1 * i, dc, 0) + 1) >> 1), y--);
        }
        break;
    case 5:
        for (uint32_t i = 0; i <= dc; i++) {
            pset_at(x--, y - (int) ((udiv32(d1 * i, dc, 0) + 1) >> 1));
        }
        break;
    case 6:
        for (uint32_t i = 0; i <= dc; i++) {
            pset_at(x--, y + (int) ((udiv32(d1 * i, dc, 0) + 1) >> 1));
        }
        break;
    default:
        for (uint32_t i = 0; i <= dc; i++) {
            pset_at(x - (int) ((udiv32(d1 * i, dc, 0) + 1) >> 1), y++);
        }
        break;
    }
}

static void vectt(const struct gdc_snap *g, uint16_t pat)
{
    if (g->ope & 0x80) { // SL: the pattern runs backwards
        pat = (uint16_t) (((uint16_t) bitreverse[pat & 0xFF] << 8) | bitreverse[pat >> 8]);
    }
    uint8_t multiple = (uint8_t) ((g->zoom & 15u) + 1u);
    uint32_t sx = (((uint32_t) g->d_lo | ((uint32_t) g->d_hi << 8)) - 1u) & 0x3FFFu;
    sx += 1u;
    if (sx >= 768u) {
        sx = 768u;
    }
    const int8_t *dir = vectdir[g->ope & 7];
    for (uint8_t muly = multiple; muly; muly--) {
        int cx = pset.x, cy = pset.y;
        for (uint32_t xrem = sx; xrem; xrem--) {
            uint8_t mulx = multiple;
            if (pat & 1u) {
                pat = (uint16_t) ((pat >> 1) | 0x8000u);
                while (mulx--) {
                    pset_at(cx, cy);
                    cx += dir[0];
                    cy += dir[1];
                }
            } else {
                pat >>= 1;
                while (mulx--) {
                    cx += dir[0];
                    cy += dir[1];
                }
            }
        }
        pset.x = (uint16_t) (pset.x + dir[2]);
        pset.y = (uint16_t) (pset.y + dir[3]);
    }
}

static void vectr(const struct gdc_snap *g)
{
    uint32_t d = ((uint32_t) g->d_lo | ((uint32_t) g->d_hi << 8)) & 0x3FFFu;
    uint32_t d2 = ((uint32_t) g->d2_lo | ((uint32_t) g->d2_hi << 8)) & 0x3FFFu;
    int x = pset.x, y = pset.y;
    const int8_t *dir = vectdir[g->ope & 7];
    for (uint32_t i = 0; i < d; i++) {
        pset_at(x, y);
        x += dir[0];
        y += dir[1];
    }
    for (uint32_t i = 0; i < d2; i++) {
        pset_at(x, y);
        x += dir[2];
        y += dir[3];
    }
    for (uint32_t i = 0; i < d; i++) {
        pset_at(x, y);
        x -= dir[0];
        y -= dir[1];
    }
    for (uint32_t i = 0; i < d2; i++) {
        pset_at(x, y);
        x -= dir[2];
        y -= dir[3];
    }
}

// Circles: np2 interpolates off a 4097-entry sqrt table (8 KB); the same
// curve comes from s = 32768*sin(pi/4 * i/m), computed with one Newton step
// on the half-angle identity -- close to a dot at r = 2047.
static void vectc(const struct gdc_snap *g)
{
    uint32_t r = ((uint32_t) g->d_lo | ((uint32_t) g->d_hi << 8)) & 0x3FFFu;
    uint32_t m = udiv32(r * 10000u + 14141u, 14142u, 0);
    if (!m) {
        pset_at(pset.x, pset.y);
        return;
    }
    uint32_t i0 = ((uint32_t) g->dm_lo | ((uint32_t) g->dm_hi << 8)) & 0x3FFFu;
    uint32_t t = ((uint32_t) g->dc_lo | ((uint32_t) g->dc_hi << 8)) & 0x3FFFu;
    int x = pset.x, y = pset.y;
    if (t > m) {
        t = m;
    }
    for (uint32_t i = i0; i <= t; i++) {
        // All 32-bit: the softcore has no divider, and 64-bit division
        // pulls in __udivdi3 the nodiv gate exists to forbid.
        uint32_t a = udiv32(i * 32768u, m, 0); // Q15, <= 32768
        uint32_t b = udiv32(i * 23170u, m, 0); // Q15, <= 23170
        uint32_t k = a * b;                    // Q30, <= 7.6e8
        uint32_t s = b;                        // one Newton step on sqrt(k)
        if (s) {
            s = (s + udiv32(k, s, 0)) / 2u; // Q30/Q15 = Q15
        }
        uint32_t dx = (s * r + 16384u) >> 15;
        switch (g->ope & 7) {
        case 0:
            pset_at(x + (int) dx, y + (int) i);
            break;
        case 1:
            pset_at(x + (int) i, y + (int) dx);
            break;
        case 2:
            pset_at(x + (int) i, y - (int) dx);
            break;
        case 3:
            pset_at(x + (int) dx, y - (int) i);
            break;
        case 4:
            pset_at(x - (int) dx, y - (int) i);
            break;
        case 5:
            pset_at(x - (int) i, y - (int) dx);
            break;
        case 6:
            pset_at(x - (int) i, y + (int) dx);
            break;
        default:
            pset_at(x - (int) dx, y + (int) i);
            break;
        }
    }
}

// TEXTE: DC/D are the cell size in dots; the octant plus the SL bit choose
// the text-flavoured direction. The pattern is the 16-bit TEXTW stand-in
// until the snapshot widens (see the header note).
static void gdc_text(const struct gdc_snap *g)
{
    uint8_t multiple = (uint8_t) ((g->zoom & 15u) + 1u);
    uint32_t sy = (((uint32_t) g->dc_lo | ((uint32_t) g->dc_hi << 8)) & 0x3FFFu) + 1u;
    uint32_t sx = (((uint32_t) g->d_lo | ((uint32_t) g->d_hi << 8)) - 1u) & 0x3FFFu;
    sx += 1u;
    if (sx >= 768u) {
        sx = 768u;
    }
    if (sy >= 768u) {
        sy = 768u;
    }
    uint8_t pat[8];
    pat[0] = g->textw[0];
    pat[1] = g->textw[1];
    for (int i = 2; i < 8; i++) {
        pat[i] = pat[i & 1];
    }
    const int8_t *dir = vectdir[((g->ope & 0x80) >> 4) + (g->ope & 7)];
    int patnum = 0;
    while (sy--) {
        for (uint8_t muly = multiple; muly; muly--) {
            int cx = pset.x, cy = pset.y;
            patnum--;
            uint8_t bit = pat[patnum & 7];
            for (uint32_t xrem = sx; xrem; xrem--) {
                uint8_t mulx = multiple;
                if (bit & 1u) {
                    bit = (uint8_t) ((bit >> 1) | 0x80u);
                    while (mulx--) {
                        pset_at(cx, cy);
                        cx += dir[0];
                        cy += dir[1];
                    }
                } else {
                    bit >>= 1;
                    while (mulx--) {
                        cx += dir[0];
                        cy += dir[1];
                    }
                }
            }
            pset.x = (uint16_t) (pset.x + dir[2]);
            pset.y = (uint16_t) (pset.y + dir[3]);
        }
    }
}

// ---- the service loop entry ----------------------------------------------

// The done protocol: level 1, then 0. Peripherals edge-detects the rise and
// retires the EXECUTE, running the 7220's vector reset in the GDC itself.
static void retire(int ch)
{
    *GDCD_DONE(ch) = 1u;
    for (volatile int i = 0; i < 20; i++) {
    }
    *GDCD_DONE(ch) = 0u;
}

void gdc_poll(void)
{
    if (!gdc_inited) {
        init_bitreverse();
        gdc_inited = 1;
    }
    // np2 draws only on the slave; the master's EXECUTEs still retire so
    // its throttle releases.
    for (int ch = GDC_CH_SLAVE; ch >= GDC_CH_MASTER; ch--) {
        uint32_t st = *GDCD_STATUS(ch);
        if (!(st & 2u)) { // no request pending
            continue;
        }
        if (ch == GDC_CH_SLAVE) {
            struct gdc_snap g;
            const volatile uint32_t *w0 = GDCD_SNAPW(ch);
            uint32_t w[5];
            for (int i = 0; i < 5; i++) {
                w[i] = w0[i];
            }
            uint8_t *b = (uint8_t *) &g;
            for (int i = 0; i < 19; i++) {
                b[i] = (uint8_t) (w[i >> 2] >> ((i & 3) * 8));
            }
            uint32_t csrw = g.csrw[0] | ((uint32_t) g.csrw[1] << 8) | ((uint32_t) g.csrw[2] << 16) |
                            ((uint32_t) g.csrw[3] << 24);
            uint16_t textw = g.textw[0] | ((uint16_t) g.textw[1] << 8);
            pset_prepare(csrw, textw, g.write_mode);
            if (!(g.ope & 0x78u)) {
                pset_at(pset.x, pset.y); // vectp: a single dot
            }
            if (g.ope & 0x08u) {
                vectl(&g);
            }
            if (g.ope & 0x10u) {
                vectt(&g, textw);
            }
            if (g.ope & 0x20u) {
                vectc(&g);
            }
            if (g.ope & 0x40u) {
                vectr(&g);
            }
            if ((st & 0xFFu) == GDC_OP_TEXTE) {
                gdc_text(&g);
            }
        }
        retire(ch);
    }
}
