// scsi_fw_host -- the SHIPPED firmware/scsi_service.c, compiled for the host
// against a model of its two hardware neighbours: the pc98_scsi register
// window behind the mgmt mailbox (Peripherals.sv's eight registers, the
// control file, the 8 KB buffer and its two pointers) and the target-dataslot
// engine that lands image bytes in the bridge RAM.
//
// The firmware is plain C99 poking volatile pointers. Compiled as C++ the
// register macros become proxy objects, so every `*REG = v` and every read of
// `*REG` runs the model's side effects -- the auto-incrementing ports, the
// command toggle -- without one edit to the source under test.
//
//   scsi_fw_host probe <image>   mount the file the way main.c does and print
//                                {base, cylinders, heads, spt, sectors}; the
//                                SCSI boot bench feeds these to its target
//   scsi_fw_host selftest        build flat / NHD / HDI / VHD / refused images
//                                and check mount, MODE SENSE pages 3/4,
//                                READ CAPACITY, READ10/WRITE10 offsets
//
// Build: scripts/sim_scsi_fw.sh (any host c++; not part of the RV32 image).
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

// ---------------------------------------------------------------- the model
namespace mock {

enum RegId {
    MGMT_ADDR, MGMT_WDATA, MGMT_TRIG, MGMT_RDATA,
    BRAM_ADDR, BRAM_RDATA, BRAM_WDATA, SCSI_MEDIA, OTHER
};

// pc98_scsi + Peripherals' mgmt registers
uint8_t  ctrl[26];
uint8_t  dbuf[8192];
uint32_t rdptr, wrptr;
uint8_t  aux, status;
int      cmd_req, cmd_ack;
uint8_t  cmd_byte;
uint32_t mg_reg_addr, mg_buf_addr;

// softcpu_fdd_bridge latches and the bridge RAM
uint32_t mgmt_addr, mgmt_wdata, mgmt_rdata;
uint32_t bram[1024];
uint32_t bram_addr;
uint32_t media;

std::vector<uint8_t> image;     // the Hard Disk slot's file
int tds_calls;

void mgmt_write(uint32_t reg, uint32_t v)
{
    switch (reg) {
    case 0: if (v & 1) cmd_ack = cmd_req; break;
    case 1: mg_reg_addr = v & 31; break;
    case 2: if (mg_reg_addr < 26) ctrl[mg_reg_addr] = (uint8_t) v;
            mg_reg_addr = (mg_reg_addr + 1) & 31; break;
    case 3: mg_buf_addr = v & 8191; break;
    case 4: dbuf[mg_buf_addr] = (uint8_t) v; mg_buf_addr = (mg_buf_addr + 1) & 8191; break;
    case 5: aux = (uint8_t) v; break;
    case 6: status = (uint8_t) v; break;
    case 7: if (v & 1) rdptr = 0; if (v & 2) wrptr = 0; break;
    }
}

uint32_t mgmt_read(uint32_t reg)
{
    uint32_t r = 0;
    switch (reg) {
    case 0: r = ((uint32_t) cmd_byte << 8) | (uint32_t) (cmd_req ^ cmd_ack); break;
    case 2: r = mg_reg_addr < 26 ? ctrl[mg_reg_addr] : 0;
            mg_reg_addr = (mg_reg_addr + 1) & 31; break;
    case 4: r = dbuf[mg_buf_addr]; mg_buf_addr = (mg_buf_addr + 1) & 8191; break;
    }
    return r;
}

void reg_write(int id, uint32_t v)
{
    switch (id) {
    case MGMT_ADDR:  mgmt_addr = v; break;
    case MGMT_WDATA: mgmt_wdata = v; break;
    case MGMT_TRIG:
        if (!(mgmt_addr & (1u << 9))) { fprintf(stderr, "non-SCSI mgmt op\n"); exit(2); }
        if (v & 1) mgmt_write(mgmt_addr & 15, mgmt_wdata);
        if (v & 2) mgmt_rdata = mgmt_read(mgmt_addr & 15);
        break;
    case BRAM_ADDR:  bram_addr = v & 1023; break;
    case BRAM_WDATA: bram[bram_addr] = v; bram_addr = (bram_addr + 1) & 1023; break;
    case SCSI_MEDIA: media = v; break;
    default: break;
    }
}

uint32_t reg_read(int id)
{
    switch (id) {
    case MGMT_RDATA: return mgmt_rdata;
    case BRAM_RDATA: { uint32_t v = bram[bram_addr]; bram_addr = (bram_addr + 1) & 1023; return v; }
    default: return 0;
    }
}

struct RegRef {
    int id;
    RegRef &operator=(uint32_t v) { reg_write(id, v); return *this; }
    operator uint32_t() const { return reg_read(id); }
};
struct RegPtr {
    int id;
    RegRef operator*() const { return RegRef{id}; }
};

} // namespace mock

// ------------------------------------------------- softcpu_regs.h stand-in
#define SOFTCPU_REGS_H                      // the real header stays out
#define FDD_MGMT_ADDR   (mock::RegPtr{mock::MGMT_ADDR})
#define FDD_MGMT_WDATA  (mock::RegPtr{mock::MGMT_WDATA})
#define FDD_MGMT_TRIG   (mock::RegPtr{mock::MGMT_TRIG})
#define FDD_MGMT_RDATA  (mock::RegPtr{mock::MGMT_RDATA})
#define FDD_BRAM_ADDR   (mock::RegPtr{mock::BRAM_ADDR})
#define FDD_BRAM_RDATA  (mock::RegPtr{mock::BRAM_RDATA})
#define FDD_BRAM_WDATA  (mock::RegPtr{mock::BRAM_WDATA})
#define SOFT_SCSI_MEDIA (mock::RegPtr{mock::SCSI_MEDIA})
#define FDD_MGMT_WR     (1 << 0)
#define FDD_MGMT_RD     (1 << 1)
#define SCSI_TARGET     (1 << 9)
#define SMGMT_CTRL    0x0
#define SMGMT_REGIDX  0x1
#define SMGMT_REGDATA 0x2
#define SMGMT_BUFPTR  0x3
#define SMGMT_BUFDATA 0x4
#define SMGMT_AUXSTAT 0x5
#define SMGMT_STATUS  0x6
#define SMGMT_PTRCLR  0x7
#define SECTOR_BYTES    512
#define SECTOR_WORDS    128
#define HDD0_SLOT_ID    5
#define FDD_TDS_READ    1
#define FDD_TDS_WRITE   2
#define HB_MARK(c)      ((void) 0)

// The dataslot engine: `bytes` at file `offset` into/out of the bridge RAM
// from word 0. A transfer past the end of the file fails, as APF's does.
static int tds_transfer(uint32_t slot, uint32_t offset, uint32_t dir, uint32_t bytes)
{
    mock::tds_calls++;
    if (slot != HDD0_SLOT_ID || (offset & 3) || bytes > 4096
        || (uint64_t) offset + bytes > mock::image.size())
        return 0;
    for (uint32_t i = 0; i < bytes; i++) {
        uint32_t w = i >> 2, sh = (i & 3) * 8;
        if (dir == FDD_TDS_READ) {
            if (!sh) mock::bram[w] = 0;
            mock::bram[w] |= (uint32_t) mock::image[offset + i] << sh;
        } else {
            mock::image[offset + i] = (uint8_t) (mock::bram[w] >> sh);
        }
    }
    return 1;
}

#include "../../firmware/scsi_service.c"

// ------------------------------------------------------------- the guest
static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); \
                              printf(__VA_ARGS__); printf("\n"); } } while (0)

// One command the way the option ROM issues it: the CDB at control index 3,
// a write of CMD toggles the request, the service runs, auxstatus bit 7 and
// the status byte come back. Returns the status; the reply stays in dbuf.
static int guest_cmd(const uint8_t *cdb, int n)
{
    memset(mock::ctrl + 3, 0, 12);
    memcpy(mock::ctrl + 3, cdb, n);
    mock::cmd_byte = 0x20;
    mock::cmd_req ^= 1;
    mock::aux = 0;
    scsi_poll();
    if (!(mock::aux & 0x80)) return -1;
    return mock::status;
}

static uint8_t rd(uint32_t i) { return mock::dbuf[i]; }

static void put32(std::vector<uint8_t> &v, uint32_t at, uint32_t x)
{
    for (int i = 0; i < 4; i++) v[at + i] = (uint8_t) (x >> (8 * i));
}
static void put16(std::vector<uint8_t> &v, uint32_t at, uint32_t x)
{
    v[at] = (uint8_t) x; v[at + 1] = (uint8_t) (x >> 8);
}

// Sector payloads: byte j of LBA n is (n * 7 + j) & 0xFF, so an off-by-
// header or off-by-one read shows.
static void fill(std::vector<uint8_t> &v, uint32_t base, uint32_t sectors)
{
    for (uint32_t n = 0; n < sectors; n++)
        for (uint32_t j = 0; j < 512; j++)
            v[base + n * 512 + j] = (uint8_t) (n * 7 + j);
}

static void mount(const std::vector<uint8_t> &img)
{
    mock::image = img;
    scsi_init();
    scsi_mount((uint32_t) img.size());
}

struct Want { uint32_t base, c, h, s, sectors; };

static void expect_geometry(const char *what, Want w)
{
    printf("%-28s base=%u C=%u H=%u S=%u sectors=%u\n", what,
           scsi_base, scsi_cyls, scsi_heads, scsi_spt, scsi_sectors);
    CHECK(scsi_sectors == w.sectors, "%s: sectors %u != %u", what, scsi_sectors, w.sectors);
    if (!w.sectors) { CHECK(mock::media == 0, "%s: media lamp set", what); return; }
    CHECK(scsi_base == w.base, "%s: base %u != %u", what, scsi_base, w.base);
    CHECK(scsi_cyls == w.c && scsi_heads == w.h && scsi_spt == w.s,
          "%s: CHS %u/%u/%u != %u/%u/%u", what, scsi_cyls, scsi_heads, scsi_spt, w.c, w.h, w.s);

    // TEST UNIT READY, READ CAPACITY
    uint8_t tur[6] = {0x00};
    CHECK(guest_cmd(tur, 6) == 0, "%s: TUR", what);
    uint8_t cap[10] = {0x25};
    CHECK(guest_cmd(cap, 10) == 0, "%s: READ CAPACITY", what);
    uint32_t last = ((uint32_t) rd(0) << 24) | (rd(1) << 16) | (rd(2) << 8) | rd(3);
    CHECK(last == w.sectors - 1, "%s: last lba %u", what, last);

    // MODE SENSE(6), DBD, page 4 then page 3 -- what the ROM's disk_init reads
    uint8_t ms4[6] = {0x1A, 0x08, 0x04, 0, 36, 0};
    CHECK(guest_cmd(ms4, 6) == 0, "%s: MODE SENSE p4", what);
    CHECK(rd(3) == 0 && rd(4) == 0x04 && rd(5) == 0x16, "%s: p4 header", what);
    uint32_t cyl = (rd(6) << 16) | (rd(7) << 8) | rd(8);
    CHECK(cyl == w.c && rd(9) == w.h, "%s: p4 cyl %u heads %u", what, cyl, rd(9));
    uint8_t ms3[6] = {0x1A, 0x08, 0x03, 0, 36, 0};
    CHECK(guest_cmd(ms3, 6) == 0, "%s: MODE SENSE p3", what);
    CHECK(rd(4) == 0x03 && ((rd(14) << 8) | rd(15)) == w.s
          && ((rd(16) << 8) | rd(17)) == 512, "%s: p3 spt %u", what, (rd(14) << 8) | rd(15));
    // without DBD: an 8-byte descriptor first, then page 4
    uint8_t ms4d[6] = {0x1A, 0x00, 0x04, 0, 36, 0};
    CHECK(guest_cmd(ms4d, 6) == 0 && rd(3) == 8 && rd(12) == 0x04 && rd(17) == w.h,
          "%s: MODE SENSE p4 with descriptor", what);
    // allocation length truncates, status still GOOD
    uint8_t ms3f[6] = {0x1A, 0x08, 0x3F, 0, 255, 0};
    CHECK(guest_cmd(ms3f, 6) == 0 && rd(0) == 3 + 48 && rd(4) == 0x03 && rd(28) == 0x04,
          "%s: MODE SENSE 3F", what);

    // READ10 of the last two sectors: payload from base + lba * 512
    uint32_t lba = w.sectors - 2;
    uint8_t r10[10] = {0x28, 0, (uint8_t) (lba >> 24), (uint8_t) (lba >> 16),
                       (uint8_t) (lba >> 8), (uint8_t) lba, 0, 0, 2, 0};
    CHECK(guest_cmd(r10, 10) == 0, "%s: READ10", what);
    int bad = 0;
    for (uint32_t j = 0; j < 1024; j++)
        bad += mock::dbuf[j] != mock::image[w.base + lba * 512 + j];
    CHECK(!bad, "%s: READ10 payload, %d bytes differ", what, bad);
    // ... and one past the end is ILLEGAL REQUEST
    uint32_t end = w.sectors;
    uint8_t r10e[10] = {0x28, 0, (uint8_t) (end >> 24), (uint8_t) (end >> 16),
                        (uint8_t) (end >> 8), (uint8_t) end, 0, 0, 1, 0};
    CHECK(guest_cmd(r10e, 10) == 2, "%s: READ10 past end", what);
    uint8_t rs[6] = {0x03, 0, 0, 0, 18, 0};
    CHECK(guest_cmd(rs, 6) == 0 && rd(2) == 5, "%s: sense key %u", what, rd(2));

    // WRITE10 lands at base + lba * 512 and nowhere else
    std::vector<uint8_t> before = mock::image;
    for (uint32_t j = 0; j < 512; j++) mock::dbuf[j] = (uint8_t) (0xA5 ^ j);
    uint8_t w10[10] = {0x2A, 0, 0, 0, 0, 1, 0, 0, 1, 0};
    CHECK(guest_cmd(w10, 10) == 0, "%s: WRITE10", what);
    bad = 0;
    for (size_t j = 0; j < before.size(); j++) {
        bool in = j >= w.base + 512 && j < w.base + 1024;
        uint8_t want = in ? (uint8_t) (0xA5 ^ (j - w.base - 512)) : before[j];
        bad += mock::image[j] != want;
    }
    CHECK(!bad, "%s: WRITE10 footprint, %d bytes wrong", what, bad);
}

static void expect_refused(const char *what)
{
    printf("%-28s sectors=%u (refused)\n", what, scsi_sectors);
    CHECK(scsi_sectors == 0 && mock::media == 0, "%s: should not mount", what);
    uint8_t tur[6] = {0x00};
    CHECK(guest_cmd(tur, 6) == 2, "%s: TUR should be CHECK CONDITION", what);
    uint8_t rs[6] = {0x03, 0, 0, 0, 18, 0};
    CHECK(guest_cmd(rs, 6) == 0 && rd(2) == 2, "%s: NOT READY sense", what);
}

static int selftest()
{
    // flat: np21w .hdn geometry, 8 x 25 x size/200 (4096 sectors -> 20 cyl)
    {
        std::vector<uint8_t> v(4096 * 512);
        fill(v, 0, 4096);
        mount(v);
        expect_geometry("flat 2 MB", {0, 20, 8, 25, 4096});
    }
    // NHD: 512-byte header, C/H/S from it (300 x 8 x 17), data after it
    {
        uint32_t c = 300, h = 8, s = 17, n = c * h * s;
        std::vector<uint8_t> v(512 + n * 512);
        memcpy(v.data(), "T98HDDIMAGE.R0", 15);
        put32(v, 0x110, 512); put32(v, 0x114, c);
        put16(v, 0x118, h); put16(v, 0x11A, s); put16(v, 0x11C, 512);
        fill(v, 512, n);
        mount(v);
        expect_geometry("NHD 300/8/17", {512, c, h, s, n});
    }
    // HDI: 4096-byte header (Anex86), 100 x 8 x 32
    {
        uint32_t c = 100, h = 8, s = 32, n = c * h * s;
        std::vector<uint8_t> v(4096 + n * 512);
        put32(v, 0x08, 4096); put32(v, 0x0C, n * 512); put32(v, 0x10, 512);
        put32(v, 0x14, s); put32(v, 0x18, h); put32(v, 0x1C, c);
        fill(v, 4096, n);
        mount(v);
        expect_geometry("HDI 100/8/32", {4096, c, h, s, n});
    }
    // VHD (Virtual98): 220-byte header, totals field authoritative
    {
        uint32_t c = 40, h = 8, s = 25, n = c * h * s;
        std::vector<uint8_t> v(220 + n * 512);
        memcpy(v.data(), "VHD1.00", 7);
        put16(v, 0x8E, 512); v[0x90] = (uint8_t) s; v[0x91] = (uint8_t) h;
        put16(v, 0x92, c); put32(v, 0x94, n);
        fill(v, 220, n);
        mount(v);
        expect_geometry("VHD 40/8/25", {220, c, h, s, n});
    }
    // 256-byte-sector HDI (SASI-made): this board cannot serve it
    {
        uint32_t c = 153, h = 4, s = 33, n = c * h * s;
        std::vector<uint8_t> v(4096 + n * 256);
        put32(v, 0x08, 4096); put32(v, 0x0C, n * 256); put32(v, 0x10, 256);
        put32(v, 0x14, s); put32(v, 0x18, h); put32(v, 0x1C, c);
        mount(v);
        expect_refused("HDI 256-byte sectors");
    }
    // a flat image whose IPL starts with zeros but whose "header" does not
    // describe the file stays flat
    {
        std::vector<uint8_t> v(1000 * 512);
        fill(v, 0, 1000);
        memset(v.data(), 0, 16);
        put32(v, 0x08, 4096); put32(v, 0x10, 512);
        put32(v, 0x14, 17); put32(v, 0x18, 8); put32(v, 0x1C, 9999);
        mount(v);
        expect_geometry("flat, HDI-looking zeros", {0, 5, 8, 25, 1000});
    }
    printf(fails ? "SELFTEST FAIL (%d)\n" : "SELFTEST PASS\n", fails);
    return fails ? 1 : 0;
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "probe")) {
        FILE *f = fopen(argv[2], "rb");
        if (!f) { perror(argv[2]); return 2; }
        fseek(f, 0, SEEK_END);
        long n = ftell(f);
        fseek(f, 0, SEEK_SET);
        std::vector<uint8_t> v((size_t) n);
        if (fread(v.data(), 1, v.size(), f) != v.size()) { perror("read"); return 2; }
        fclose(f);
        mount(v);
        printf("base=%u cyl=%u heads=%u spt=%u sectors=%u\n",
               scsi_base, scsi_cyls, scsi_heads, scsi_spt, scsi_sectors);
        return scsi_sectors ? 0 : 1;
    }
    if (argc == 2 && !strcmp(argv[1], "selftest"))
        return selftest();
    fprintf(stderr, "usage: %s probe <image> | selftest\n", argv[0]);
    return 2;
}
