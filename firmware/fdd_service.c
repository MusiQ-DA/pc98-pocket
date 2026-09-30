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

#include "settings_ui.h"
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

// The geometry a wrapped image (FDI or D88) declared for the mounted
// media, in {spt, cyls, heads, is_1024} -- zero spt means the image is a
// plain raw stream and fdd_mount falls back to the size table. The
// header's geometry wins because the size table only knows the standard
// formats: a 15-sector 2HD or 16-sector BASIC disk lands on the wrong
// row by sector count.
static uint32_t fdd_img_geom[2][4];

// Set when the mounted image is a D88 (track-offset table + per-sector
// headers): fdd_poll then maps LBAs through d88_offset instead of the
// raw base + lba*width arithmetic.
static uint8_t fdd_d88[2];
static uint8_t fdd_d88_wp[2];

// FDI (the T98/np21w family's format): a 0x20-byte header in front of the raw
// image -- {dummy, fddtype, headersize, fddsize, sectorsize, sectors,
// surfaces, cylinders}, little-endian words (np21w diskimage/fd/fdd_xdf.c).
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
    fdd_img_geom[drive][0] = 0;
    if (hsize >= 0x20 && hsize <= 0x1000
        && ssize >= 128 && ssize <= 4096
        && spt >= 1 && spt <= 255
        && surf == 2 && cyl >= 1 && cyl <= 127
        && raw + hsize > file - 1024 && raw + hsize < file + 1024) {
        fdd_base[drive] = hsize;
        fdd_img_geom[drive][0] = spt;
        fdd_img_geom[drive][1] = cyl;
        fdd_img_geom[drive][2] = surf;
        // The controller's N accepts only 512 or 1024; a size between or
        // above them is unusable either way, so only the 1024 case sets it.
        fdd_img_geom[drive][3] = (ssize == 1024) ? 1 : 0;
    }
}

// D88 (the emulator family's tagged format): a 0x2B0 header -- 0x20 bytes
// of name/type/size, then 164 track-base offsets -- followed by track
// blobs, each a run of 16-byte sector headers {c,h,r,n,count,...} glued
// to their data (np21w diskimage/fd/fdd_head_d88.h). Tracks index as
// cyl*2 + head, which is exactly what the controller's CHS->LBA walk
// produces, so lba/spt is the track slot and lba%spt+1 the R to find.
#define D88_TRACKS   164
#define D88_HDRSIZE  (0x20 + D88_TRACKS * 4)
#define D88_SECHDR   16

// Fetch `bytes` from a byte offset into the bridge RAM. Thin wrapper so the
// D88 walkers read headers and data through one path.
static int fdd_read_at(uint32_t drive, uint32_t off, uint32_t bytes)
{
    return tds_transfer(drive ? FDD1_SLOT_ID : FDD0_SLOT_ID, off,
                        FDD_TDS_READ, bytes);
}

// Probe the mounted image for a D88 header. The format has no magic, so the
// check is structural: fd_size must equal the file, the first track must
// sit exactly past the header, and every populated track must point inside
// the file. On success fdd_img_geom is filled from the image's own records
// (track 0's sector count and N, the table's last used cylinder), which --
// like the FDI path -- beats guessing from the byte count.
static void fdd_probe_d88(uint32_t drive, uint32_t sectors)
{
    uint32_t file = sectors * 512;
    fdd_d88[drive] = 0;
    fdd_d88_wp[drive] = 0;
    fdd_img_geom[drive][0] = 0;   // no wrapped geometry unless a probe sets it
    // The bridge RAM is 1 KB -- bytes 512+ hold the settings window -- so the
    // 688-byte header lands in two reads: 512 B at 0 covers the name/type/
    // size fields plus track entries 0-119, the remaining 176 B at 0x200
    // the rest of the table.
    if (!fdd_read_at(drive, 0, 512) || !fdd_read_at(drive, 0x200, 176)) {
        return;
    }
    // The second transfer landed in the same window, so pull the table tail
    // into a scratch array first, then re-fetch the head window.
    uint32_t tail[44];
    uint32_t fd_size, first, protect;
    int populated = 0, last = 0, odd = 0;
    *FDD_BRAM_ADDR = 0;
    for (int i = 0; i < 44; i++) {
        tail[i] = *FDD_BRAM_RDATA;
    }
    for (int i = 0; i < 44; i++) {
        int idx = 120 + i;
        uint32_t t = tail[i];
        if (t) {
            if (t < D88_HDRSIZE || t >= file + 512) {
                return;                  // points outside the image
            }
            populated++;
            last = idx;
            odd |= idx & 1;
        }
    }
    if (!fdd_read_at(drive, 0, 512)) {
        return;
    }
    *FDD_BRAM_ADDR = 0;
    uint32_t w[128];
    for (int i = 0; i < 128; i++) {
        w[i] = *FDD_BRAM_RDATA;
    }
    fd_size = w[7];                      // bytes 0x1C-0x1F
    protect = w[6];                      // bytes 0x18-0x1B (protect = 0x1A)
    first   = w[8];                      // trackp[0], byte 0x20
    for (int i = 0; i < 120; i++) {
        uint32_t t = w[8 + i];
        if (t) {
            if (t < D88_HDRSIZE || t >= fd_size) {
                return;                  // points outside the image
            }
            populated++;
            last = i;
            odd |= i & 1;
        }
    }
    if (!populated || first != D88_HDRSIZE
        || fd_size + 512 < file || fd_size > file + 512) {
        return;                          // empty, or size mismatch
    }
    // Track 0's first sector header supplies spt and the media's N.
    if (!fdd_read_at(drive, first, D88_SECHDR)) {
        return;
    }
    *FDD_BRAM_ADDR = 0;
    uint32_t h[4];
    for (int i = 0; i < 4; i++) {
        h[i] = *FDD_BRAM_RDATA;
    }
    uint32_t n       = (h[0] >> 24) & 0xFF;
    uint32_t trk_spt = h[1] & 0xFFFF;    // sectors-in-track count
    if (!trk_spt || trk_spt > 32) {
        return;
    }
    fdd_d88[drive] = 1;
    fdd_d88_wp[drive] = (protect & 0x00100000) ? 1 : 0;  // protect bit4, byte 0x1A
    fdd_img_geom[drive][0] = trk_spt;
    // Double-sided media runs tracks cyl*2+head; a D88 can mark a disk
    // single-sided by leaving every odd slot empty.
    fdd_img_geom[drive][1] = last / 2 + 1;
    fdd_img_geom[drive][2] = odd ? 2 : 1;
    fdd_img_geom[drive][3] = (n == 3) ? 1 : 0;
}

// Resolve an LBA to a data byte offset in a D88 image: the track's base
// from the table, then a walk of the sector headers until one's r matches
// (np21w searchsector_d88 matches by r, which keeps interleaved tracks
// right). Returns 0 on an empty track, a short/overrun walk, or a bad
// header -- the caller treats 0 as "sector not found" and stops.
static uint32_t d88_offset(uint32_t drive, uint32_t lba)
{
    uint32_t spt = fdd_img_geom[drive][0];
    uint32_t trk = 0, l = lba;
    while (l >= spt) {                    // mul-only softcore: subtract-loop
        l -= spt;
        trk++;
    }
    uint32_t want_r = l + 1;
    if (!fdd_read_at(drive, 0x20 + trk * 4, 4)) {
        return 0;
    }
    *FDD_BRAM_ADDR = 0;
    uint32_t pos = *FDD_BRAM_RDATA;
    if (!pos) {
        return 0;
    }
    for (uint32_t i = 0; i < spt; i++) {
        if (!fdd_read_at(drive, pos, D88_SECHDR)) {
            return 0;
        }
        *FDD_BRAM_ADDR = 0;
        uint32_t h0 = *FDD_BRAM_RDATA;   // bytes 0-3: c, h, r, n
        uint32_t h1 = *FDD_BRAM_RDATA;   // bytes 4-7: count, mfm, del, stat
        *FDD_BRAM_RDATA;                 // bytes 8-11: stat tail, seektime, rsv
        uint32_t h3 = *FDD_BRAM_RDATA;   // bytes 12-15: rsv, rpm, size
        (void) h1;
        uint32_t r     = (h0 >> 16) & 0xFF;
        uint32_t dsize = (h3 >> 16) & 0xFFFF;
        if (r == want_r) {
            return pos + D88_SECHDR;
        }
        if (!dsize || dsize > 4096) {
            return 0;                    // corrupt walk, stop
        }
        pos += D88_SECHDR + dsize;
    }
    return 0;
}


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

// The PC-98's own formats. A 2HD disk is 77 cylinders, 8 sectors, 2 heads of
// 1024 bytes (N=3) = 1232 KB; a 2DD is 80/8/2 of 512s = 640 KB (with a
// 9-sector 720 KB variant). 1.44 MB is a later PC-9821 format, listed ahead of
// 2HD because its sector count is higher -- each row's count is computed from
// its own sector width, so the ordering picks the right row for every size
// that exists. An 80/15/2 table would answer 1.2 MB for a
// 1232 KB image, which no PC-98 disk is.
static const struct fdd_geom fdd_geoms[] = {
    { 2880, 80, 18, 2, 0 }, // 1.44 MB (PC-9821)
    { 2464, 77,  8, 2, 1 }, // 2HD 1232 KB -- the standard PC-98 disk, N=3
    { 1440, 80,  9, 2, 0 }, // 2DD 720 KB
    { 1280, 80,  8, 2, 0 }, // 2DD 640 KB
    {    0, 80,  8, 2, 0 }, // anything smaller: 2DD shape, sized by the image
};

// Crude busy-wait, long enough to separate the eject from the insert below.
static void spin(uint32_t n)
{
    for (volatile uint32_t i = 0; i < n; i++) {
    }
}

// The drives' media state, for the OSD's Floppy rows. `sectors` is the last
// image mounted (0 = never), `inserted` is whether the controller is being
// told the media is there. An eject only clears PRESENT and keeps the size,
// so the OSD can put the same image back without the Pocket menu.
static uint32_t fdd_sectors[2];
static uint8_t  fdd_inserted[2];

// The mounted image's identity for the per-disk settings table
// (settings_ui.c). The bridge never sees the picked file's name, so the disk's
// own bytes stand in: a 32-bit FNV-1a over the first and the middle 512-byte
// block of the raw image, folded with the sector count. The IPL alone would
// collide across same-format DOS disks, and any single sector could be one a
// save game rewrites -- two spread samples keep both failures rare. A hash of
// 0 is the "no disk" sentinel to the settings side, so it is never returned.
static uint32_t fdd_image_hash(uint32_t drive, uint32_t sectors)
{
    uint32_t h = 2166136261u; // FNV-1a offset basis; the prime is a zmmul mul
    h ^= sectors;
    h *= 16777619u;
    uint32_t bytes = sectors * SECTOR_BYTES;
    for (uint32_t s = 0; s < 2; s++) {
        if (s && bytes < 2 * SECTOR_BYTES) {
            break; // a one-sector image has only the one block to sample
        }
        uint32_t off = fdd_base[drive]
                     + (s ? ((bytes >> 1) & ~(SECTOR_BYTES - 1u)) : 0);
        if (!tds_transfer(drive ? FDD1_SLOT_ID : FDD0_SLOT_ID,
                          off, FDD_TDS_READ, SECTOR_BYTES)) {
            continue;
        }
        *FDD_BRAM_ADDR = 0;
        for (int i = 0; i < SECTOR_WORDS; i++) {
            uint32_t w = *FDD_BRAM_RDATA;
            h ^= w & 0xFF;         h *= 16777619u;
            h ^= (w >> 8) & 0xFF;  h *= 16777619u;
            h ^= (w >> 16) & 0xFF; h *= 16777619u;
            h ^= w >> 24;          h *= 16777619u;
        }
    }
    return h ? h : 1;
}

// Derive a drive's geometry from its image size (in sectors) and push it to the
// controller, ejecting first so the controller flags a media change, then marking
// the media present and writable. drive selects the controller's drive A (0) or B
// (1) via the management-bus drive bit.
void fdd_mount(uint32_t drive, uint32_t sectors)
{
    // D88 first: its checks (fd_size == file, trackp[0] == 0x2B0) are
    // structural and strong, and an FDI's own arithmetic could otherwise
    // pass on a D88's header words. FDI runs only for non-D88 images.
    fdd_probe_d88(drive, sectors);
    if (!fdd_d88[drive]) {
        fdd_probe_fdi(drive, sectors); // sets fdd_base+geometry for an FDI
    }
    struct fdd_geom fdi = { 0, fdd_img_geom[drive][1], fdd_img_geom[drive][0],
                            fdd_img_geom[drive][2], fdd_img_geom[drive][3] };
    const struct fdd_geom *g = &fdi;
    if (!fdi.spt) {
        g = &fdd_geoms[0];
        for (int i = 0; i < (int) (sizeof(fdd_geoms) / sizeof(fdd_geoms[0])); i++) {
            if (sectors >= fdd_geoms[i].min_sectors) {
                g = &fdd_geoms[i];
                break;
            }
        }
    }

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
    mgmt_write(drive, FMGMT_WRPROT, fdd_d88_wp[drive]);
    mgmt_write(drive, FMGMT_PRESENT, 1);
    fdd_sectors[drive] = sectors;
    fdd_inserted[drive] = 1;
    if (!drive) {
        // Drive A's image picks the settings profile: mount applies the disk's
        // own saved settings (or the global set), unbind returns to global.
        settings_disk_mounted(fdd_image_hash(drive, sectors));
    }
}

// Eject: the controller stops reporting media, so the guest sees NOT READY
// (and the change line for the next insert). The image size is remembered.
void fdd_eject(uint32_t drive)
{
    if (drive > 1 || !fdd_inserted[drive]) {
        return;
    }
    mgmt_write(drive, FMGMT_PRESENT, 0);
    fdd_inserted[drive] = 0;
}

// Insert: put the remembered image back. A drive that has never been mounted
// has nothing to put in; the Pocket menu's data slot is the way in for that.
void fdd_insert(uint32_t drive)
{
    if (drive > 1 || fdd_inserted[drive] || !fdd_sectors[drive]) {
        return;
    }
    fdd_mount(drive, fdd_sectors[drive]);
}

// Unbind: eject and forget the image so insert cannot bring it back. The
// dataslot keeps its bytes -- only a host rebind mounts the drive again.
void fdd_unbind(uint32_t drive)
{
    if (drive > 1) {
        return;
    }
    fdd_eject(drive);
    fdd_sectors[drive] = 0;
    if (!drive) {
        settings_disk_mounted(0); // no image: the settings context is global again
    }
}

int fdd_is_inserted(uint32_t drive)
{
    return drive < 2 && fdd_inserted[drive];
}

uint32_t fdd_mounted_sectors(uint32_t drive)
{
    return drive < 2 ? fdd_sectors[drive] : 0;
}

// Answer one pending controller request. Register 0 reports the active request's
// drive in bit 15 and the LBA in the low bits, so it selects which image dataslot
// the sector is moved to or from. A read pulls the sector from that dataslot and
// streams it to the controller FIFO; a write drains the FIFO and persists it to that
// dataslot. The reg-0 read and the FIFO are drive-agnostic in floppy.v, so only the
// slot id and the sector width are keyed on the drive. Writes reach the SD file
// directly, so nothing else is needed here. The return is nonzero when a
// request was serviced, so the main loop's idle spacing can skip working
// passes -- the sector traffic IS the bus load the spacing exists to limit,
// and the request stays raised while more sectors wait.
// POSTMON-visible counters, one per leg of a read request, so a stalled boot
// says which link died: SEEN polls that found the request up, PUSH sectors
// streamed into the controller fifo, ERR dataslot transfers that failed or
// timed out, LBA the last reg-0 (drive bit + lba), AFT the request bits still
// up right after a push (nonzero = the fifo never filled, or the next sector
// was already asked for).
uint32_t fdd_dbg_seen, fdd_dbg_pushed, fdd_dbg_err, fdd_dbg_lba, fdd_dbg_aft;
uint32_t fdd_dbg_gap;
static uint32_t gap_polls;

int fdd_poll(void)
{
    uint32_t req = *FDD_REQUEST;
    if (!req) {
        // Polls between services measure the BIOS's turnaround: a drained
        // sector re-asks within a few loops, a parked drain only after the
        // guest's own timeout, so the gap separates them by orders.
        gap_polls++;
        return 0;
    }
    fdd_dbg_gap = gap_polls;
    gap_polls = 0;
    if (req & FDD_REQ_READ) {
        uint32_t reg0 = mgmt_read(0, FMGMT_PRESENT);
        uint32_t drv = (reg0 & FDD_LBA_DRIVE) ? 1 : 0;
        uint32_t bytes = fdd_sector_words[drv] * 4;
        uint32_t slot = drv ? FDD1_SLOT_ID : FDD0_SLOT_ID;
        uint32_t lba = reg0 & FDD_LBA_MASK;
        uint32_t off = fdd_d88[drv] ? d88_offset(drv, lba)
                                  : fdd_base[drv] + lba * bytes;
        fdd_dbg_seen++;
        fdd_dbg_lba = reg0;
        // Push only on a good read; a failed transfer (or a D88 walk that
        // found no such sector) must not stream stale bytes.
        if (off && tds_transfer(slot, off, FDD_TDS_READ, bytes)) {
            push_sector(drv);
            fdd_dbg_pushed++;
            fdd_dbg_aft = *FDD_REQUEST;
        } else {
            fdd_dbg_err++;
        }
    } else if (req & FDD_REQ_WRITE) {
        uint32_t reg0 = mgmt_read(0, FMGMT_PRESENT);
        uint32_t drv = (reg0 & FDD_LBA_DRIVE) ? 1 : 0;
        uint32_t bytes = fdd_sector_words[drv] * 4;
        uint32_t slot = drv ? FDD1_SLOT_ID : FDD0_SLOT_ID;
        uint32_t lba = reg0 & FDD_LBA_MASK;
        uint32_t off = fdd_d88[drv] ? d88_offset(drv, lba)
                                  : fdd_base[drv] + lba * bytes;
        // pull_fifo already completes the controller's write; a failed persist has no
        // path back to the guest, so the result is not acted on here.
        pull_fifo(drv);
        if (off) {
            tds_transfer(slot, off, FDD_TDS_WRITE, bytes);
        }
    }
    return 1;
}
