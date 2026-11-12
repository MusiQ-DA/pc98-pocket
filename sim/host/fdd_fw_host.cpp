// fdd_fw_host -- the SHIPPED firmware/fdd_service.c + disk_tds.c, compiled
// for the host against a model of their hardware neighbours: floppy.v's
// management registers (reg 0 = {drive, LBA}, the FIFO the sector is pushed
// into), the 1024-word bridge RAM and the APF target-dataslot engine.
//
// Same trick as scsi_fw_host: compiled as C++ the register macros become
// proxy objects, so every `*REG = v` runs the model with no edit to the
// source under test.
//
//   fdd_fw_host <image> [flat]   mount <image> as drive A, then read every
//                                LBA the controller can name -- in order,
//                                in reverse, and in a seeded random order --
//                                and compare each pushed sector with the
//                                same LBA of <flat> (a raw C/H/R-ordered
//                                image); with no <flat>, <image> itself is
//                                taken as raw
//   fdd_fw_host selftest         a synthetic 2HD D88 and its raw twin
//
// Build: scripts/sim_fdd_fw.sh (any host c++; not part of the RV32 image).
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace mock {

enum RegId {
    REQUEST, MGMT_ADDR, MGMT_WDATA, MGMT_TRIG, MGMT_PUSH, MGMT_RDATA,
    BRAM_ADDR, BRAM_RDATA, BRAM_WDATA,
    TDS_ID, TDS_OFFSET, TDS_BRIDGE, TDS_LENGTH, TDS_TRIG, TDS_STATUS, TDS_CLR,
    VKB, OTHER
};

// floppy.v's mgmt side
uint32_t geom[2][8];               // regs 1-6 as written, per drive
uint32_t reg0;                     // {drive bit 15, LBA} of the request
uint32_t request;                  // FDD_REQUEST
std::vector<uint8_t> fifo;         // bytes pushed for the current request

// softcpu_fdd_bridge
uint32_t mgmt_addr, mgmt_wdata, mgmt_rdata;
uint32_t bram[1024];
uint32_t bram_addr;
uint32_t tds_id, tds_off, tds_bridge, tds_len, tds_status;
int      tds_calls;

std::vector<uint8_t> image[2];     // the floppy slots' files (ids 3, 4)
uint32_t slot_size[2];             // what APF reports for the slot, bytes

void mgmt_op(uint32_t trig)
{
    uint32_t drv = (mgmt_addr >> 4) & 1, reg = mgmt_addr & 15;
    if (mgmt_addr & ~0x1Fu) { fprintf(stderr, "non-floppy mgmt op %x\n", mgmt_addr); exit(2); }
    if (trig & 1) {
        if (reg == 15) fifo.push_back((uint8_t) mgmt_wdata);
        else geom[drv][reg] = mgmt_wdata;
    }
    if (trig & 2) mgmt_rdata = reg == 0 ? reg0 : 0;
}

// The APF target-dataslot read/write: `len` bytes at file `off` to/from the
// bridge RAM at `bridge`. Dataslot byte 0 lands in the low byte of its word
// (softcpu_fdd_bridge reverses the bus byte order on port A). A transfer that
// runs past the end of the file fails, as APF's does.
void tds_go(uint32_t dir)
{
    tds_calls++;
    tds_status = 1;
    int s = tds_id == 3 ? 0 : tds_id == 4 ? 1 : -1;
    uint32_t w0 = (tds_bridge - 0x60000000u) >> 2;
    if (s < 0 || (tds_bridge & 3) || (tds_bridge >> 28) != 6
        || (uint64_t) tds_off + tds_len > slot_size[s]
        || w0 + ((tds_len + 3) >> 2) > 1024) {
        tds_status |= 2;
        return;
    }
    for (uint32_t i = 0; i < tds_len; i++) {
        uint32_t w = w0 + (i >> 2), sh = (i & 3) * 8;
        if (dir & 1) {
            if (!sh) bram[w] = 0;
            bram[w] |= (uint32_t) image[s][tds_off + i] << sh;
        } else {
            image[s][tds_off + i] = (uint8_t) (bram[w] >> sh);
        }
    }
}

void reg_write(int id, uint32_t v)
{
    switch (id) {
    case MGMT_ADDR:  mgmt_addr = v; break;
    case MGMT_WDATA: mgmt_wdata = v; break;
    case MGMT_TRIG:  mgmt_op(v); break;
    case MGMT_PUSH:  mgmt_wdata = v; mgmt_op(1); break;
    case BRAM_ADDR:  bram_addr = v & 1023; break;
    case BRAM_WDATA: bram[bram_addr] = v; bram_addr = (bram_addr + 1) & 1023; break;
    case TDS_ID:     tds_id = v; break;
    case TDS_OFFSET: tds_off = v; break;
    case TDS_BRIDGE: tds_bridge = v; break;
    case TDS_LENGTH: tds_len = v; break;
    case TDS_CLR:    tds_status = 0; break;
    case TDS_TRIG:   tds_go(v); break;
    default: break;
    }
}

uint32_t reg_read(int id)
{
    switch (id) {
    case REQUEST:    return request;
    case MGMT_RDATA: return mgmt_rdata;
    case BRAM_RDATA: { uint32_t v = bram[bram_addr]; bram_addr = (bram_addr + 1) & 1023; return v; }
    case TDS_STATUS: return tds_status;
    default: return 0;
    }
}

// A bare `*REG;` statement is a read in C (volatile), but in C++ it only
// builds a RegRef and drops it -- the auto-incrementing BRAM port would not
// step. So a RegRef nobody wrote or read performs its read on the way out.
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

// ------------------------------------------------- softcpu_regs.h stand-in
#define SOFTCPU_REGS_H
#define SETTINGS_UI_H
#define FDD_REQUEST     (mock::RegPtr{mock::REQUEST})
#define FDD_MGMT_ADDR   (mock::RegPtr{mock::MGMT_ADDR})
#define FDD_MGMT_WDATA  (mock::RegPtr{mock::MGMT_WDATA})
#define FDD_MGMT_TRIG   (mock::RegPtr{mock::MGMT_TRIG})
#define FDD_MGMT_PUSH   (mock::RegPtr{mock::MGMT_PUSH})
#define FDD_MGMT_RDATA  (mock::RegPtr{mock::MGMT_RDATA})
#define FDD_BRAM_ADDR   (mock::RegPtr{mock::BRAM_ADDR})
#define FDD_BRAM_RDATA  (mock::RegPtr{mock::BRAM_RDATA})
#define FDD_BRAM_WDATA  (mock::RegPtr{mock::BRAM_WDATA})
#define FDD_TDS_ID      (mock::RegPtr{mock::TDS_ID})
#define FDD_TDS_OFFSET  (mock::RegPtr{mock::TDS_OFFSET})
#define FDD_TDS_BRIDGE  (mock::RegPtr{mock::TDS_BRIDGE})
#define FDD_TDS_LENGTH  (mock::RegPtr{mock::TDS_LENGTH})
#define FDD_TDS_TRIG    (mock::RegPtr{mock::TDS_TRIG})
#define FDD_TDS_STATUS  (mock::RegPtr{mock::TDS_STATUS})
#define FDD_TDS_CLR     (mock::RegPtr{mock::TDS_CLR})
#define FDD_REQ_READ    (1 << 0)
#define FDD_REQ_WRITE   (1 << 1)
#define FDD_MGMT_WR     (1 << 0)
#define FDD_MGMT_RD     (1 << 1)
#define FDD_TDS_READ    (1 << 0)
#define FDD_TDS_WRITE   (1 << 1)
#define FDD_TDS_DONE    (1 << 0)
#define FDD_TDS_ERR     (7 << 1)
#define FMGMT_PRESENT 0x0
#define FMGMT_WRPROT  0x1
#define FMGMT_CYLS    0x2
#define FMGMT_SPT     0x3
#define FMGMT_TOTAL   0x4
#define FMGMT_HEADS   0x5
#define FMGMT_SECSIZE 0x6
#define FMGMT_FIFO    0xF
#define FDD_LBA_MASK  0x7FFF
#define FDD_LBA_DRIVE 0x8000
#define FDD_BRIDGE_BASE 0x60000000
#define SECTOR_BYTES    512
#define SECTOR_WORDS    128
#define DISK_SPIN_LIMIT 4000000u
#define FDD0_SLOT_ID    3
#define FDD1_SLOT_ID    4
#define HB_MARK(c)      ((void) 0)
#define DTBL_ADDR       (mock::RegPtr{mock::OTHER})
#define DTBL_DATA       (mock::RegPtr{mock::OTHER})
static void settings_disk_mounted(uint32_t) {}

#include "../../firmware/disk_tds.c"
#include "../../firmware/fdd_service.c"

// ------------------------------------------------------------- the guest
static int fails;

static std::vector<uint8_t> load(const char *p)
{
    FILE *f = fopen(p, "rb");
    if (!f) { perror(p); exit(2); }
    std::vector<uint8_t> v;
    uint8_t b[65536];
    size_t n;
    while ((n = fread(b, 1, sizeof b, f)) > 0) v.insert(v.end(), b, b + n);
    fclose(f);
    return v;
}

static void mount(const std::vector<uint8_t> &img)
{
    mock::image[0] = img;
    mock::slot_size[0] = (uint32_t) img.size();
    fdd_mount(0, (uint32_t) img.size() >> 9);   // core_top: bytes >> 9
}

// One controller read request for `lba`, served the way fdd_poll serves it.
static bool serve(uint32_t lba, std::vector<uint8_t> &out)
{
    mock::fifo.clear();
    mock::reg0 = lba & 0x7FFF;
    mock::request = 1;
    fdd_poll();
    mock::request = 0;
    out = mock::fifo;
    return !out.empty();
}

static void run(const char *what, const std::vector<uint8_t> &flat)
{
    uint32_t spt = mock::geom[0][3], heads = mock::geom[0][5], cyls = mock::geom[0][2];
    uint32_t total = mock::geom[0][4], ss = mock::geom[0][6] ? 1024 : 512;
    printf("%s: mounted C=%u H=%u S=%u total=%u N=%u wp=%u d88=%u\n", what,
           cyls, heads, spt, total, ss, mock::geom[0][1], fdd_d88[0]);
    if (total * ss != flat.size()) {
        printf("FAIL %s: geometry %u x %u != flat %zu\n", what, total, ss, flat.size());
        fails++;
        return;
    }
    std::vector<uint32_t> order;
    for (uint32_t l = 0; l < total; l++) order.push_back(l);
    for (uint32_t l = total; l-- > 0;) order.push_back(l);
    uint32_t x = 12345;
    for (uint32_t i = 0; i < 4 * total; i++) {
        x = x * 1103515245u + 12345u;
        order.push_back((x >> 8) % total);
    }
    int bad = 0;
    for (uint32_t l : order) {
        std::vector<uint8_t> got;
        bool ok = serve(l, got);
        bool same = ok && got.size() == ss
                 && !memcmp(got.data(), flat.data() + (size_t) l * ss, ss);
        if (!same) {
            if (bad < 10)
                printf("FAIL %s: LBA %u (C%u H%u R%u): %s\n", what, l,
                       l / (spt * heads), (l / spt) % heads, l % spt + 1,
                       ok ? "wrong bytes" : "no sector pushed");
            bad++;
        }
    }
    printf("%s: %zu reads, %d bad, %d dataslot transfers\n", what, order.size(), bad,
           mock::tds_calls);
    fails += bad;
}

// A 2HD D88 (77 x 2 x 8 x 1024) built the way the emulators write one, and
// the raw image it should read back as. Byte j of LBA n is (n * 7 + j).
static void build_d88(std::vector<uint8_t> &d88, std::vector<uint8_t> &flat)
{
    const uint32_t C = 77, H = 2, S = 8, SS = 1024;
    flat.assign(C * H * S * SS, 0);
    for (uint32_t n = 0; n < C * H * S; n++)
        for (uint32_t j = 0; j < SS; j++) flat[n * SS + j] = (uint8_t) (n * 7 + j);
    d88.assign(0x2B0, 0);
    memcpy(d88.data(), "SELFTEST", 8);
    d88[0x1B] = 0x20;                                   // 2HD
    for (uint32_t t = 0; t < C * H; t++) {
        uint32_t base = (uint32_t) d88.size();
        for (int i = 0; i < 4; i++) d88[0x20 + t * 4 + i] = (uint8_t) (base >> (8 * i));
        for (uint32_t r = 1; r <= S; r++) {
            uint8_t h[16] = {0};
            h[0] = (uint8_t) (t / H); h[1] = (uint8_t) (t % H); h[2] = (uint8_t) r; h[3] = 3;
            h[4] = (uint8_t) S; h[14] = (uint8_t) SS; h[15] = (uint8_t) (SS >> 8);
            d88.insert(d88.end(), h, h + 16);
            const uint8_t *p = flat.data() + ((t * S) + r - 1) * SS;
            d88.insert(d88.end(), p, p + SS);
        }
    }
    uint32_t sz = (uint32_t) d88.size();
    for (int i = 0; i < 4; i++) d88[0x1C + i] = (uint8_t) (sz >> (8 * i));
}

int main(int argc, char **argv)
{
    if (argc >= 2 && !strcmp(argv[1], "selftest")) {
        std::vector<uint8_t> d88, flat;
        build_d88(d88, flat);
        mount(d88);
        run("D88 2HD", flat);
        mount(flat);
        run("raw 2HD", flat);
    } else if (argc >= 2) {
        std::vector<uint8_t> img = load(argv[1]);
        std::vector<uint8_t> flat = argc >= 3 ? load(argv[2]) : img;
        mount(img);
        run(argv[1], flat);
    } else {
        fprintf(stderr, "usage: fdd_fw_host selftest | <image> [flat]\n");
        return 2;
    }
    printf(fails ? "RESULT: FAIL\n" : "RESULT: PASS\n");
    return fails ? 1 : 0;
}
