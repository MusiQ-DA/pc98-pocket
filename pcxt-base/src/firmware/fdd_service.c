// Floppy service loop for the PicoRV32 disk softcore.
//
// The controller (floppy.v) raises a request whenever it needs to move a sector,
// and this code answers it over the management bus. A read request: fetch the LBA
// and drive, pull that sector from the selected drive's image dataslot into the
// bridge RAM over the APF target-dataslot handshake, then stream the 512 bytes into
// the controller's management FIFO. A write request is the mirror: drain the 512
// bytes the controller has queued in that FIFO into the bridge RAM, then persist
// them to the dataslot. Each pass moves one sector and runs again while the request
// holds.
//
// Written sectors reach the SD file through target-dataslot writes.
//
// The geometry table and the register protocol follow MiSTer's x86 support
// (Main_MiSTer support/x86/x86.cpp), retargeted from the HPS to this softcore.

#include "softcpu_regs.h"

// One management-bus write: latch drive + register + 16-bit data, then trigger.
static void mgmt_write(uint32_t drive, uint32_t reg, uint32_t data)
{
    *FDD_MGMT_ADDR = (drive << 4) | (reg & 0xF);
    *FDD_MGMT_WDATA = data & 0xFFFF;
    *FDD_MGMT_TRIG = FDD_MGMT_WR;
}

// One management-bus read: trigger, then return the captured value. The trigger
// and the readback are separate instructions, so the single-cycle bus strobe and
// its capture have completed by the time the readback executes.
static uint32_t mgmt_read(uint32_t drive, uint32_t reg)
{
    *FDD_MGMT_ADDR = (drive << 4) | (reg & 0xF);
    *FDD_MGMT_TRIG = FDD_MGMT_RD;
    return *FDD_MGMT_RDATA & 0xFFFF;
}

// The sector length each drive was mounted with, in words, keyed by drive so
// the sector movers below know how much to move. The controller's request
// carries a drive bit; its FIFO is one per chip, so only the length is
// drive-keyed.
static uint32_t fdd_sector_words[2] = { 128, 128 };

// Where drive X's raw image starts inside its file: zero, or the header an
// FDI wraps it in (see fdd_probe_fdi).
static uint32_t fdd_base[2] = { 0, 0 };

// FDI (the T98/np2 family's format): a 0x20-byte header in front of the raw
// image -- {dummy, fddtype, headersize, fddsize, sectorsize, sectors,
// surfaces, cylinders}, little-endian words (np2kai diskimage/fd/fdd_xdf.c).
// The slot's sector count cannot tell it from raw -- the header is under one
// sector -- so the mount reads the first 32 bytes and believes the header's
// own arithmetic: headersize + sectorsize*sectors*surfaces*cylinders must
// land within a sector of the size the slot reported.
static void fdd_probe_fdi(uint32_t drive, uint32_t sectors)
{
    uint32_t slot = drive ? FDD1_SLOT_ID : FDD0_SLOT_ID;
    fdd_base[drive] = 0;
    if (sectors < 4) {
        return;                       // nothing that small is an FDI
    }
    if (!tds_transfer(slot, 0, FDD_TDS_READ, 32)) {
        return;
    }
    uint32_t w[8];
    *FDD_BRAM_ADDR = 0;
    for (int i = 0; i < 8; i++) {
        w[i] = *FDD_BRAM_RDATA;       // word i = file bytes 4i..4i+3
    }
    uint32_t hsize = w[2];            // headersize
    uint32_t ssize = w[4];            // sectorsize
    uint32_t spt    = w[5];           // sectors per track
    uint32_t surf   = w[6];           // surfaces
    uint32_t cyl    = w[7];           // cylinders
    uint32_t raw    = ssize * spt * surf * cyl;
    uint32_t file   = sectors * 512;  // the slot's size, truncated to sectors
    if (hsize >= 0x20 && hsize <= 0x1000
        && ssize >= 128 && ssize <= 4096
        && spt >= 1 && spt <= 255
        && surf == 2 && cyl >= 1 && cyl <= 127
        && raw + hsize > file - 1024 && raw + hsize < file + 1024) {
        fdd_base[drive] = hsize;
    }
}

// Stream the sector now in the bridge RAM into the controller FIFO, in order.
// The bridge RAM holds the sector little-endian, so the low byte of each word is
// the earlier file byte. The FIFO register address is set once for the whole run.
// The length is the mounted media's sector width -- 512 bytes for every format
// but a PC-98 2HD, whose sectors are 1024.
static void push_sector(uint32_t drive)
{
    *FDD_BRAM_ADDR = 0;
    *FDD_MGMT_ADDR = (drive << 4) | FMGMT_FIFO;
    for (int i = 0; i < (int) fdd_sector_words[drive]; i++) {
        uint32_t w = *FDD_BRAM_RDATA;
        for (int b = 0; b < 4; b++) {
            *FDD_MGMT_WDATA = (w >> (b * 8)) & 0xFF;
            *FDD_MGMT_TRIG = FDD_MGMT_WR;
        }
    }
}

// Drain the sector the controller has queued for a write out of its FIFO and
// into the bridge RAM, in order. Mirror of push_sector: the first byte popped is
// the earliest file byte, so it lands in the low byte of the first RAM word.
// Length is the media's sector width, as above.
static void pull_fifo(uint32_t drive)
{
    *FDD_BRAM_ADDR = 0;
    *FDD_MGMT_ADDR = (drive << 4) | FMGMT_FIFO;
    for (int i = 0; i < (int) fdd_sector_words[drive]; i++) {
        uint32_t w = 0;
        for (int b = 0; b < 4; b++) {
            *FDD_MGMT_TRIG = FDD_MGMT_RD;
            w |= (*FDD_MGMT_RDATA & 0xFF) << (b * 8);
        }
        *FDD_BRAM_WDATA = w;
    }
}

// Standard PC floppy geometries, largest first; the first whose sector count the
// image meets wins. Matches the size thresholds MiSTer's x86 support uses.
struct fdd_geom {
    uint32_t min_sectors;
    uint32_t cyls;
    uint32_t spt;
    uint32_t heads;
    uint32_t is_1024;   // sector length: 512 << this, from the format's N
};

#ifdef MACHINE_PC98
// The PC-98's own formats. A 2HD disk is 77 cylinders, 8 sectors, 2 heads of
// 1024 bytes (N=3) = 1232 KB; a 2DD is 80/8/2 of 512s = 640 KB (with a
// 9-sector 720 KB variant). 1.44 MB is a later PC-9821 format, listed ahead of
// 2HD because its sector count is higher -- each row's count is computed from
// its own sector width, so the ordering picks the right row for every size
// that exists. The PC/AT table would answer 1.2 MB (80/15/2 of 512s) for a
// 1232 KB image, which no PC-98 disk is.
static const struct fdd_geom fdd_geoms[] = {
    { 2880, 80, 18, 2, 0 }, // 1.44 MB (PC-9821)
    { 2464, 77,  8, 2, 1 }, // 2HD 1232 KB -- the standard PC-98 disk, N=3
    { 1440, 80,  9, 2, 0 }, // 2DD 720 KB
    { 1280, 80,  8, 2, 0 }, // 2DD 640 KB
    {    0, 80,  8, 2, 0 }, // anything smaller: 2DD shape, sized by the image
};
#else
static const struct fdd_geom fdd_geoms[] = {
    { 5760, 80, 36, 2, 0 }, // 2.88 MB
    { 3360, 80, 21, 2, 0 }, // 1.68 MB
    { 2880, 80, 18, 2, 0 }, // 1.44 MB
    { 2400, 80, 15, 2, 0 }, // 1.2 MB
    { 1440, 80,  9, 2, 0 }, // 720 KB
    {  720, 40,  9, 2, 0 }, // 360 KB
    {  640, 40,  8, 2, 0 }, // 320 KB
    {  360, 40,  9, 1, 0 }, // 180 KB
    {    0, 40,  8, 1, 0 }, // 160 KB
};
#endif

// Crude busy-wait, long enough to separate the eject from the insert below.
static void spin(uint32_t n)
{
    for (volatile uint32_t i = 0; i < n; i++) {
    }
}

// Derive a drive's geometry from its image size (in sectors) and push it to the
// controller, ejecting first so the controller flags a media change, then marking
// the media present and writable. drive selects the controller's drive A (0) or B
// (1) via the management-bus drive bit.
void fdd_mount(uint32_t drive, uint32_t sectors)
{
    const struct fdd_geom *g = &fdd_geoms[0];
    for (int i = 0; i < (int) (sizeof(fdd_geoms) / sizeof(fdd_geoms[0])); i++) {
        if (sectors >= fdd_geoms[i].min_sectors) {
            g = &fdd_geoms[i];
            break;
        }
    }
    fdd_probe_fdi(drive, sectors);   // sets fdd_base when the file is an FDI

    mgmt_write(drive, FMGMT_PRESENT, 0);
    spin(100000);
    mgmt_write(drive, FMGMT_CYLS, g->cyls);
    mgmt_write(drive, FMGMT_SPT, g->spt);
    mgmt_write(drive, FMGMT_TOTAL, g->cyls * g->spt * g->heads);
    mgmt_write(drive, FMGMT_HEADS, g->heads);
    // The controller keys its FIFO-full threshold and the N of a READ ID off
    // this, and the sector movers below key their byte count off the same
    // table row, so both always agree with what the media was declared to be.
    mgmt_write(drive, FMGMT_SECSIZE, g->is_1024);
    fdd_sector_words[drive] = g->is_1024 ? 256 : 128;
    mgmt_write(drive, FMGMT_WRPROT, 0);
    mgmt_write(drive, FMGMT_PRESENT, 1);
}

// Answer one pending controller request. Register 0 reports the active request's
// drive in bit 15 and the LBA in the low bits, so it selects which image dataslot
// the sector is moved to or from. A read pulls the sector from that dataslot and
// streams it to the controller FIFO; a write drains the FIFO and persists it to that
// dataslot. The reg-0 read and the FIFO are drive-agnostic in floppy.v, so only the
// slot id and the sector width are keyed on the drive. Writes reach the SD file
// directly, so nothing else is needed here.
void fdd_poll(void)
{
    uint32_t req = *FDD_REQUEST;
    if (req & FDD_REQ_READ) {
        uint32_t reg0 = mgmt_read(0, FMGMT_PRESENT);
        uint32_t drv = (reg0 & FDD_LBA_DRIVE) ? 1 : 0;
        uint32_t bytes = fdd_sector_words[drv] * 4;
        uint32_t slot = drv ? FDD1_SLOT_ID : FDD0_SLOT_ID;
        uint32_t off = fdd_base[drv] + (reg0 & FDD_LBA_MASK) * bytes;
        // Push only on a good read; a failed transfer must not stream stale bytes.
        if (tds_transfer(slot, off, FDD_TDS_READ, bytes)) {
            push_sector(drv);
        }
    } else if (req & FDD_REQ_WRITE) {
        uint32_t reg0 = mgmt_read(0, FMGMT_PRESENT);
        uint32_t drv = (reg0 & FDD_LBA_DRIVE) ? 1 : 0;
        uint32_t bytes = fdd_sector_words[drv] * 4;
        uint32_t slot = drv ? FDD1_SLOT_ID : FDD0_SLOT_ID;
        uint32_t off = fdd_base[drv] + (reg0 & FDD_LBA_MASK) * bytes;
        // pull_fifo already completes the controller's write; a failed persist has no
        // path back to the guest, so the result is not acted on here.
        pull_fifo(drv);
        tds_transfer(slot, off, FDD_TDS_WRITE, bytes);
    }
}
