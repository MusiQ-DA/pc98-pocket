// gdc_draw_host -- the SHIPPED firmware/gdc_service.c driving the REAL
// pc98_gdc_draw RTL (Verilated), checked against np21w's own LINE.
//
// The firmware is compiled for the host the scsi/fdd_fw_host way: its
// register macros become proxies (GDC_HOST_REGS), so serve_slave() runs
// unchanged -- the fast-path decode, the CSRW split, the charger pick --
// and its LN_* stores land on the Verilated engine, which also sees the
// same snapshot words pc98_gdc would present and is clocked while the
// firmware polls. The engine's service-channel
// ops go to a model of the GVRAM sequencer's svc port with a random accept
// latency: own-plane raw reads, and writes that are plain, GRCG RMW
// (v = v & ~d | tile & d, every plane), GRCG TDW (tile, data ignored) or
// EGC (recorded only).
//
// The reference is np21w io/gdc_sub.c gdcsub_vectl + io/gdc_pset.c gdcpset
// verbatim (REG16 arithmetic, the clip, psettbl / withrmw / withtdw) on a
// second copy of the same VRAM. After every line the four planes must be
// identical; for the word-wide chargers (TDW, EGC) the engine's write
// trace must also equal the dot-by-dot (addr & ~1, addr | 1) pairs np21w's
// withtdw/withegc imply, so every lit dot's position is checked one by one.
//
//   gdc_draw_host [n] [seed] [kinds]    kinds: l line, p dot, r rect (default lpr)
//   gdc_draw_host bench [lat_rd [lat_rmw [lat_tdw]]]
//
// Build: scripts/sim_gdc_draw.sh (needs Verilator; no --timing).

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "Vpc98_gdc_draw.h"
#include "verilated.h"

namespace mock {

Vpc98_gdc_draw *eng;
uint64_t cycles;

// ---- RNG (xorshift64*) ------------------------------------------------------
uint64_t rs = 88172645463325252ull;
uint32_t rnd() { rs ^= rs >> 12; rs ^= rs << 25; rs ^= rs >> 27; return (uint32_t) ((rs * 2685821657736338717ull) >> 32); }

// ---- VRAM: four planes by np21w's plane-select index (E, B, R, G) ---------
uint8_t vram[4][0x8000];
uint8_t tile[4];
uint32_t accel;             // ST_ACCEL: {page, egc, rmw, grcg}
struct Wr { uint32_t a; uint8_t d; };
std::vector<Wr> trace;      // charger writes, word modes

int plane_of(uint32_t a)
{
    switch (a >> 15) {
    case 0x1C: return 0; // E0000
    case 0x15: return 1; // A8000
    case 0x16: return 2; // B0000
    case 0x17: return 3; // B8000
    default: fprintf(stderr, "svc op outside GVRAM: %05x\n", a); exit(2);
    }
}

uint8_t svc_op(bool we, uint32_t a, uint8_t d)
{
    int p = plane_of(a);
    uint32_t o = a & 0x7FFF;
    if (!we)
        return vram[p][o];
    bool armed = accel & 5, egc = accel & 4, rmw = accel & 2;
    if (!armed) {
        vram[p][o] = d;
    } else if (egc) {
        trace.push_back({a, d});
    } else if (rmw) {
        for (int q = 0; q < 4; q++) vram[q][o] = (uint8_t) ((vram[q][o] & ~d) | (tile[q] & d));
    } else {
        trace.push_back({a, d});
        for (int q = 0; q < 4; q++) vram[q][o] = tile[q];
    }
    return 0;
}

// ---- the sequencer's svc port: level req, done until req drops ------------
bool sv_pend, sv_done;
int sv_lat;
int lat_fix = -1;           // bench: fixed accept latency per op kind
int lat_rd = 2, lat_wr = 2, lat_rmw = 13, lat_tdw = 6;
uint64_t busy_cycles;
uint8_t sv_rdata;
uint64_t n_ops;

void tick()
{
    eng->st_done  = sv_done;
    eng->st_rdata = sv_rdata;
    if (eng->busy) busy_cycles++;
    eng->clk = 0; eng->eval();
    eng->clk = 1; eng->eval();
    cycles++;
    eng->wr = 0;
    if (!eng->st_req) {
        sv_done = sv_pend = false;
    } else if (!sv_pend && !sv_done) {
        sv_pend = true;
        if (lat_fix < 0)
            sv_lat = (int) (rnd() % 5);
        else
            sv_lat = !eng->st_we ? lat_rd : !(accel & 5) ? lat_wr
                   : (accel & 4) ? lat_tdw : (accel & 2) ? lat_rmw : lat_tdw;
    } else if (sv_pend) {
        if (sv_lat-- <= 0) {
            sv_rdata = svc_op(eng->st_we, eng->st_addr, eng->st_wdata);
            sv_pend = false;
            sv_done = true;
            n_ops++;
        }
    }
}

// ---- register proxies -----------------------------------------------------
enum RegId { R_LN0, R_LN1, R_LN2, R_LN3, R_ACCEL, R_ST_ADDR, R_ST_WDATA, R_ST_TRIG,
             R_ST_STATUS, R_GDCD_STATUS, R_GDCD_DONE, R_OTHER };
uint32_t st_addr, st_wdata, st_rd;
uint32_t snapw[6];

void reg_write(int id, uint32_t v)
{
    if (id <= R_LN3) {
        eng->wr = 1;
        eng->wr_sel = (uint8_t) id;
        for (int i = 0; i < 6; i++) eng->snap[i] = snapw[i];
        eng->wr_data = v;
        tick();
        return;
    }
    tick();
    switch (id) {
    case R_ST_ADDR:  st_addr = v; break;
    case R_ST_WDATA: st_wdata = v; break;
    case R_ST_TRIG:  st_rd = svc_op(v & 1, st_addr & 0xFFFFF, (uint8_t) st_wdata); break;
    default: break;
    }
}

uint32_t reg_read(int id)
{
    switch (id) {
    case R_LN3: {
        int k = 1 + (int) (rnd() % 4);
        while (k--) tick();
        return eng->busy;
    }
    case R_ACCEL: return accel;
    case R_ST_STATUS: return st_rd;
    default: return 0;
    }
}

struct RegRef {
    int id;
    mutable bool used = false;
    RegRef &operator=(uint32_t v) { used = true; reg_write(id, v); return *this; }
    operator uint32_t() const { used = true; return reg_read(id); }
    ~RegRef() { if (!used) reg_read(id); }
};
struct RegPtr {
    int id;
    RegRef operator*() const { return RegRef{id}; }
};

} // namespace mock

#define SOFTCPU_REGS_H
#define GDC_HOST_REGS
#define HB_MARK(c) ((void) 0)
#define ST_ADDR   (mock::RegPtr{mock::R_ST_ADDR})
#define ST_WDATA  (mock::RegPtr{mock::R_ST_WDATA})
#define ST_TRIG   (mock::RegPtr{mock::R_ST_TRIG})
#define ST_STATUS (mock::RegPtr{mock::R_ST_STATUS})
#define ST_PEND   (1u << 8)
#define ST_ACCEL  (mock::RegPtr{mock::R_ACCEL})
#define GDCD_STATUS(ch) (mock::RegPtr{mock::R_GDCD_STATUS})
#define GDCD_SNAPW(ch)  ((volatile uint32_t *) mock::snapw)
#define GDCD_DONE(ch)   (mock::RegPtr{mock::R_GDCD_DONE})
#define LN_XY  (mock::RegPtr{mock::R_LN0})
#define LN_GO  (mock::RegPtr{mock::R_LN3})

#include "../../firmware/gdc_service.c"

// ---- np21w, verbatim -------------------------------------------------------
// io/gdc_sub.c (vectdraw's figures, gdcsub_write) and io/gdc_pset.c on a
// second VRAM. The parameter block is the snapshot pc98_gdc hands over:
// VECTW at 0, CSRW at 11, TEXTW at 15 (two bytes: the firmware and the
// engine both repeat them through the eight-byte PRAM window), ZOOM 17,
// the WRITE command 18, MASK 19, CODE 21.
namespace ref {

typedef uint16_t REG16;
uint8_t vram[4][0x8000];
uint64_t drawn;     // dots inside the clip
int mode;           // 0 plain, 1 rmw, 2 tdw, 3 egc
int plane;          // csrw >> 14 & 3
int op;
uint16_t pattern;
REG16 px0, py0;     // gdcpset_prepare's pset.x / pset.y
std::vector<mock::Wr> trace;
static const uint32_t seg[4] = { 0xE0000, 0xA8000, 0xB0000, 0xB8000 };
struct VD { int x, y, x2, y2; };
static const VD vectdir[16] = {
    { 0, 1, 1, 0}, { 1, 1, 1,-1}, { 1, 0, 0,-1}, { 1,-1,-1,-1},
    { 0,-1,-1, 0}, {-1,-1,-1, 1}, {-1, 0, 0, 1}, {-1, 1, 1, 1},
    { 0, 1, 1, 1}, { 1, 1, 1, 0}, { 1, 0, 1,-1}, { 1,-1, 0,-1},
    { 0,-1,-1,-1}, {-1,-1,-1, 0}, {-1, 0,-1, 1}, {-1, 1, 0, 1}};

void func(int dot, unsigned addr, unsigned bit)
{
    uint8_t m = (uint8_t) (0x80 >> bit);
    if (mode == 0) {
        uint8_t &v = vram[plane][addr];
        switch (op) {
        case 0: if (dot) v |= m; else v &= (uint8_t) ~m; break;
        case 1: if (dot) v ^= m; break;
        case 2: if (dot) v &= (uint8_t) ~m; break;
        default: if (dot) v |= m; break;
        }
        return;
    }
    if (!dot) return; // _nop
    if (mode == 1) { // withrmw
        for (int q = 0; q < 4; q++) vram[q][addr] = (uint8_t) ((vram[q][addr] & ~m) | (mock::tile[q] & m));
        return;
    }
    // withtdw / withegc: the word the dot is in
    uint32_t w = seg[plane] + (addr & ~1u);
    trace.push_back({w, (uint8_t) ((addr & 1) ? 0 : m)});
    trace.push_back({w | 1, (uint8_t) ((addr & 1) ? m : 0)});
    if (mode == 2)
        for (int q = 0; q < 4; q++) { vram[q][addr & ~1u] = mock::tile[q]; vram[q][addr | 1u] = mock::tile[q]; }
}

void gdcpset(REG16 x, REG16 y)
{
    unsigned dot = pattern & 1;
    pattern = (uint16_t) ((pattern >> 1) + (dot << 15));
    if (y > 409) return;
    else if (y == 409) { if (x >= 384) return; }
    else { if (x >= 640) return; }
    drawn++;
    func((int) dot, (y * 80u) + (x >> 3), x & 7);
}

void prepare(uint32_t csrw, uint16_t pat)
{
    pattern = pat;
    px0 = (uint16_t) ((((csrw & 0x3fff) % 40) << 4) + ((csrw >> 20) & 0x0f));
    py0 = (uint16_t) ((csrw & 0x3fff) / 40);
}

unsigned w16(const uint8_t *b, int i) { return b[i] | (b[i + 1] << 8); }

void vectp(const uint8_t *b, uint32_t csrw, uint16_t pat) { prepare(csrw, pat); gdcpset(px0, py0); }

void vectl(const uint8_t *b, uint32_t csrw, uint16_t pat)
{
    prepare(csrw, pat);
    REG16 x = px0, y = py0;
    unsigned dc = w16(b, 1) & 0x3fff, i;
    uint16_t step;
    unsigned d1 = w16(b, 7);
    if (dc == 0) { gdcpset(x, y); return; }
    switch (b[0] & 7) {
    case 0: for (i = 0; i <= dc; i++) { step = (uint16_t) ((((d1 * i) / dc) + 1) >> 1); gdcpset((REG16) (x + step), y++); } break;
    case 1: for (i = 0; i <= dc; i++) { step = (uint16_t) ((((d1 * i) / dc) + 1) >> 1); gdcpset(x++, (REG16) (y + step)); } break;
    case 2: for (i = 0; i <= dc; i++) { step = (uint16_t) ((((d1 * i) / dc) + 1) >> 1); gdcpset(x++, (REG16) (y - step)); } break;
    case 3: for (i = 0; i <= dc; i++) { step = (uint16_t) ((((d1 * i) / dc) + 1) >> 1); gdcpset((REG16) (x + step), y--); } break;
    case 4: for (i = 0; i <= dc; i++) { step = (uint16_t) ((((d1 * i) / dc) + 1) >> 1); gdcpset((REG16) (x - step), y--); } break;
    case 5: for (i = 0; i <= dc; i++) { step = (uint16_t) ((((d1 * i) / dc) + 1) >> 1); gdcpset(x--, (REG16) (y - step)); } break;
    case 6: for (i = 0; i <= dc; i++) { step = (uint16_t) ((((d1 * i) / dc) + 1) >> 1); gdcpset(x--, (REG16) (y + step)); } break;
    case 7: for (i = 0; i <= dc; i++) { step = (uint16_t) ((((d1 * i) / dc) + 1) >> 1); gdcpset((REG16) (x - step), y++); } break;
    }
}

void vectr(const uint8_t *b, uint32_t csrw, uint16_t pat)
{
    prepare(csrw, pat);
    unsigned d = w16(b, 3) & 0x3fff, d2 = w16(b, 5) & 0x3fff, i;
    REG16 x = px0, y = py0;
    const VD *dir = vectdir + (b[0] & 7);
    for (i = 0; i < d; i++)  { gdcpset(x, y); x += dir->x;  y += dir->y; }
    for (i = 0; i < d2; i++) { gdcpset(x, y); x += dir->x2; y += dir->y2; }
    for (i = 0; i < d; i++)  { gdcpset(x, y); x -= dir->x;  y -= dir->y; }
    for (i = 0; i < d2; i++) { gdcpset(x, y); x -= dir->x2; y -= dir->y2; }
}

// gdc.c vectdraw: each figure from its own gdcpset_prepare
void vectdraw(const uint8_t *b)
{
    uint32_t csrw = b[11] | (b[12] << 8) | (b[13] << 16) | ((uint32_t) b[14] << 24);
    uint16_t textw = (uint16_t) w16(b, 15);
    uint8_t vope = b[0];
    if (!(vope & 0x78)) vectp(b, csrw, textw);
    if (vope & 0x08) vectl(b, csrw, textw);
    if (vope & 0x40) vectr(b, csrw, textw);
}

} // namespace ref

using mock::rnd;

// A random draw. kinds: 'l' line, 'p' lone dot, 'r' rectangle
static uint32_t rnd14()
{
    uint32_t r = rnd() % 20;
    return r < 10 ? rnd() % 64 : r < 17 ? rnd() % 640 : r < 19 ? rnd() % 4096 : rnd() % 16384;
}

static void make_snap(char kind, uint8_t *b)
{
    for (int i = 0; i < 24; i++) b[i] = (uint8_t) rnd();
    b[23] = 0;
    uint8_t oct = (uint8_t) (rnd() & 7);
    uint8_t sl = (uint8_t) ((rnd() & 1) << 7);
    uint32_t dc = rnd14(), d = rnd14(), d2 = rnd14(), d1;
    if (rnd() % 20 < 17) d1 = dc ? rnd() % (2 * dc + 1) : rnd() & 0xFFFF;
    else d1 = rnd() & 0xFFFF;
    switch (kind) {
    case 'p': b[0] = (uint8_t) (oct | sl); break;
    case 'r': b[0] = (uint8_t) (0x40 | oct | sl | ((rnd() % 8 == 0) ? 0x08 : 0)); break; // sometimes + LINE
    default:  b[0] = (uint8_t) (0x08 | oct | sl); break;
    }
    uint32_t junk = (rnd() & 3) << 14;   // VECTW's top bits are junk to np21w
    b[1] = (uint8_t) dc; b[2] = (uint8_t) ((dc | junk) >> 8);
    junk = (rnd() & 3) << 14;
    b[3] = (uint8_t) d;  b[4] = (uint8_t) ((d | junk) >> 8);
    junk = (rnd() & 3) << 14;
    b[5] = (uint8_t) d2; b[6] = (uint8_t) ((d2 | junk) >> 8);
    b[7] = (uint8_t) d1; b[8] = (uint8_t) (d1 >> 8);
    uint32_t csrw = (rnd() & 0x3FFF) | ((rnd() & 3) << 14) | ((rnd() & 0xF) << 20) | (rnd() & 0xFF000000u);
    if (rnd() % 4 == 0) csrw = (csrw & ~0x3FFFu) | (16000 + rnd() % 384); // bottom rows
    for (int i = 0; i < 4; i++) b[11 + i] = (uint8_t) (csrw >> (8 * i));
    uint16_t pat = (uint16_t) ((rnd() & 3) ? rnd() : ((rnd() & 1) ? 0xFFFF : 0x0000));
    b[15] = (uint8_t) pat; b[16] = (uint8_t) (pat >> 8);
    b[18] = (uint8_t) (rnd() & 3);
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    long n = argc > 1 ? atol(argv[1]) : 100000;
    if (argc > 2 && strcmp(argv[1], "bench")) mock::rs ^= strtoull(argv[2], 0, 0) * 0x9E3779B97F4A7C15ull;
    const char *kinds = argc > 3 ? argv[3] : "lpr";
    mock::eng = new Vpc98_gdc_draw;
    mock::eng->reset = 1;
    mock::tick(); mock::tick();
    mock::eng->reset = 0;
    mock::tick();

    for (auto &pl : mock::vram) for (auto &b : pl) b = (uint8_t) rnd();
    memcpy(ref::vram, mock::vram, sizeof ref::vram);
    if (argc > 1 && !strcmp(argv[1], "bench")) {
        // Engine clk_pico per line for fixed svc latencies (pico cycles from
        // the op's launch to its done, excluding those two edges): plain
        // read/write, a GRCG RMW write (four planes read+write), TDW/EGC.
        mock::lat_fix = 1;
        if (argc > 2) mock::lat_rd = mock::lat_wr = atoi(argv[2]);
        if (argc > 3) mock::lat_rmw = atoi(argv[3]);
        if (argc > 4) mock::lat_tdw = atoi(argv[4]);
        struct L { const char *n; uint32_t csrw, dc, d1; uint8_t oct; };
        static const L ls[] = {
            { "horizontal 640", 0, 639, 0, 2 },
            { "vertical 400",  0, 399, 0, 0 },
            { "diagonal 400",  0, 399, 798, 1 },
            { "shallow 640x200", 0, 639, 400, 1 },
            { "short 32x9",    40 * 100 + 10, 31, 18, 1 },
        };
        static const uint32_t accs[3] = { 0x0, 0x3, 0x1 };
        static const char *an[3] = { "plain", "grcg-rmw", "grcg-tdw" };
        for (int a = 0; a < 3; a++)
            for (const L &l : ls) {
                mock::accel = accs[a];
                uint8_t b[24] = {0};
                b[0] = (uint8_t) (0x08 | l.oct);
                b[1] = (uint8_t) l.dc; b[2] = (uint8_t) (l.dc >> 8);
                b[7] = (uint8_t) l.d1; b[8] = (uint8_t) (l.d1 >> 8);
                for (int i = 0; i < 4; i++) b[11 + i] = (uint8_t) (l.csrw >> (8 * i));
                b[15] = 0xFF; b[16] = 0xFF;
                b[18] = 0;
                for (int i = 0; i < 6; i++)
                    mock::snapw[i] = b[4 * i] | (b[4 * i + 1] << 8) | (b[4 * i + 2] << 16) | ((uint32_t) b[4 * i + 3] << 24);
                uint64_t c0 = mock::busy_cycles, o0 = mock::n_ops;
                serve_slave(0x200u | GDC_OP_VECTE);
                uint64_t c = mock::busy_cycles - c0;
                printf("%-9s %-16s %5u dots %6llu svc ops %7llu clk_pico = %6.1f us, %.3f us/dot\n", an[a], l.n,
                       l.dc + 1, (unsigned long long) (mock::n_ops - o0), (unsigned long long) c,
                       c * 6 / 42.95, c * 6 / 42.95 / (l.dc + 1));
            }
        return 0;
    }

    long fails = 0;
    uint64_t kdots[128] = {0}, kcyc[128] = {0}, kops[128] = {0}, kn[128] = {0};
    size_t nk = strlen(kinds);
    for (long t = 0; t < n; t++) {
        char kind = kinds[rnd() % nk];
        uint8_t b[24];
        make_snap(kind, b);
        int mode = (int) (rnd() % 10);
        mode = mode < 4 ? 0 : mode < 7 ? 1 : mode < 9 ? 2 : 3;
        static const uint32_t accel_of[4] = { 0x0, 0x3, 0x1, 0x5 };
        mock::accel = accel_of[mode] | ((rnd() & 1) ? 0 : (mode == 3 ? 2 : 0)); // EGC overrides RMW
        for (auto &tl : mock::tile) tl = (uint8_t) rnd();
        for (int i = 0; i < 6; i++)
            mock::snapw[i] = b[4 * i] | (b[4 * i + 1] << 8) | (b[4 * i + 2] << 16) | ((uint32_t) b[4 * i + 3] << 24);

        // ---- engine, through the firmware ----
        mock::trace.clear();
        uint64_t c0 = mock::busy_cycles, o0 = mock::n_ops;
        serve_slave(0x200u | GDC_OP_VECTE);
        if (mock::eng->busy) { printf("draw %ld: engine still busy after the firmware returned\n", t); fails++; }

        // ---- np21w ----
        ref::trace.clear();
        ref::mode = mode;
        ref::plane = (int) ((b[12] >> 6) & 3);
        ref::op = b[18] & 3;
        ref::drawn = 0;
        ref::vectdraw(b);
        kn[(int) kind]++;
        kdots[(int) kind] += ref::drawn;
        kcyc[(int) kind] += mock::busy_cycles - c0;
        kops[(int) kind] += mock::n_ops - o0;

        bool bad = memcmp(ref::vram, mock::vram, sizeof ref::vram) != 0;
        bool badt = false;
        if (mode >= 2) {
            badt = ref::trace.size() != mock::trace.size();
            for (size_t i = 0; !badt && i < ref::trace.size(); i++)
                badt = ref::trace[i].a != mock::trace[i].a || ref::trace[i].d != mock::trace[i].d;
        }
        if (bad || badt) {
            fails++;
            if (fails <= 10) {
                printf("MISMATCH draw %ld kind %c mode %d:", t, kind, mode);
                for (int i = 0; i < 23; i++) printf(" %02x", b[i]);
                printf(" %s%s\n", bad ? "vram " : "", badt ? "trace" : "");
                int shown = 0;
                for (int q = 0; q < 4 && shown < 8; q++)
                    for (int o = 0; o < 0x8000 && shown < 8; o++)
                        if (ref::vram[q][o] != mock::vram[q][o]) {
                            printf("  plane %d +%04x (y %d xb %d): np21w %02x engine %02x\n", q, o, o / 80, o % 80,
                                   ref::vram[q][o], mock::vram[q][o]);
                            shown++;
                        }
                if (badt) printf("  trace: np21w %zu writes, engine %zu\n", ref::trace.size(), mock::trace.size());
            }
            memcpy(ref::vram, mock::vram, sizeof ref::vram);
        }
    }
    for (int k = 0; k < 128; k++)
        if (kn[k])
            printf("kind %c: %8llu draws %10llu on-screen dots  %.2f svc ops/dot  %.2f engine clk/dot\n", k,
                   (unsigned long long) kn[k], (unsigned long long) kdots[k],
                   kdots[k] ? (double) kops[k] / kdots[k] : 0.0, kdots[k] ? (double) kcyc[k] / kdots[k] : 0.0);
    printf("%ld draws, %ld mismatches\n", n, fails);
    printf(fails ? "RESULT: FAIL\n" : "RESULT: PASS\n");
    delete mock::eng;
    return fails ? 1 : 0;
}
