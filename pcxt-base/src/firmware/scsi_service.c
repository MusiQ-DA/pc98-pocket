// SCSI (PC-9801-55) service for the PicoRV32 disk softcore.
//
// pc98_scsi.sv is only the board's register window: an indirect index at
// 0xCC0, a data register at 0xCC2 that post-increments it, and a byte port at
// 0xCC6 onto an 8 KB buffer. Writing the CMD register (index 0x18) toggles a
// request; everything after that happens here.
//
// This is a SCSI-1 direct-access target. The guest builds a command descriptor
// block in control registers 0x03 onwards -- SCSICTR_CDB in np2kai's table --
// and this code reads it out, works against the HDD image dataslot, fills or
// drains the buffer and writes the status back. The bridge RAM and the
// target-dataslot engine are shared with the floppy and IDE paths.
//
// Same division of labour np2kai uses: its scsibios.res is `CB 90 90` entries
// plus a `55 AA` signature, about a kilobyte of nothing, with every command
// handled on the host side (cbus/scsicmd.c). A command interpreter in RTL was
// never affordable on a device at 91% ALM.
#include <stddef.h>
#include "softcpu_regs.h"

// SCSI-1 group 0 and group 1 opcodes this target answers. Anything else gets
// CHECK CONDITION with ILLEGAL REQUEST, which is what a real target does and
// what lets the BIOS probe without hanging.
#define SCSI_TEST_UNIT_READY 0x00
#define SCSI_REZERO          0x01
#define SCSI_REQUEST_SENSE   0x03
#define SCSI_FORMAT_UNIT     0x04
#define SCSI_READ6           0x08
#define SCSI_WRITE6          0x0A
#define SCSI_SEEK6           0x0B
#define SCSI_INQUIRY         0x12
#define SCSI_MODE_SELECT6    0x15
#define SCSI_MODE_SENSE6     0x1A
#define SCSI_START_STOP      0x1B
#define SCSI_READ_CAPACITY   0x25
#define SCSI_READ10          0x28
#define SCSI_WRITE10         0x2A
#define SCSI_SEEK10          0x2B

// Status byte, index 0x17 on the board.
#define SCSI_GOOD            0x00
#define SCSI_CHECK_CONDITION 0x02

// Sense keys, byte 2 of the sense data.
#define SENSE_NO_SENSE       0x00
#define SENSE_NOT_READY      0x02
#define SENSE_ILLEGAL_REQ    0x05

// The CDB lives at control register 0x03 (np2kai cbus/scsiio.tbl, SCSICTR_CDB).
#define CDB_BASE 0x03
#define CDB_MAX  12

static uint32_t scsi_sectors;      // image size, 512-byte blocks; 0 = no disk
static uint8_t  scsi_sense_key;
static uint8_t  scsi_asc;          // additional sense code
static int      scsi_ack;          // our copy of the request toggle

static void scsi_mgmt_write(uint32_t reg, uint32_t data)
{
    *FDD_MGMT_ADDR = SCSI_TARGET | (reg & 0xF);
    *FDD_MGMT_WDATA = data & 0xFFFF;
    *FDD_MGMT_TRIG = FDD_MGMT_WR;
}

static uint32_t scsi_mgmt_read(uint32_t reg)
{
    *FDD_MGMT_ADDR = SCSI_TARGET | (reg & 0xF);
    *FDD_MGMT_TRIG = FDD_MGMT_RD;
    return *FDD_MGMT_RDATA;
}

// Read the CDB. The index register auto-increments on every data access, so
// the index is set once and the block streams out -- the same property the
// guest relies on to write it.
static void scsi_get_cdb(uint8_t *cdb)
{
    scsi_mgmt_write(SMGMT_REGIDX, CDB_BASE);
    for (int i = 0; i < CDB_MAX; i++)
        cdb[i] = (uint8_t) (scsi_mgmt_read(SMGMT_REGDATA) & 0xFF);
}

// Put one byte into the data buffer at the current pointer. Callers rewind the
// pointer once and then stream, so the address is not re-sent per byte.
static inline void scsi_put(uint8_t v)
{
    scsi_mgmt_write(SMGMT_BUFDATA, v);
}

static inline uint8_t scsi_get(void)
{
    return (uint8_t) (scsi_mgmt_read(SMGMT_BUFDATA) & 0xFF);
}

static void scsi_rewind_write(void)  { scsi_mgmt_write(SMGMT_PTRCLR, 2); }
static void scsi_rewind_read(void)   { scsi_mgmt_write(SMGMT_PTRCLR, 1); }
static void scsi_buf_seek(uint32_t p){ scsi_mgmt_write(SMGMT_BUFPTR, p); }

static void scsi_complete(uint8_t status)
{
    scsi_mgmt_write(SMGMT_STATUS, status);
    // auxstatus bit 7 is the WD33C93's INT: the command is finished and there
    // is something to collect. The guest reads 0xCC0, which clears it.
    scsi_mgmt_write(SMGMT_AUXSTAT, 0x80);
}

static void scsi_fail(uint8_t key, uint8_t asc)
{
    scsi_sense_key = key;
    scsi_asc = asc;
    scsi_complete(SCSI_CHECK_CONDITION);
}

static void scsi_ok(void)
{
    scsi_sense_key = SENSE_NO_SENSE;
    scsi_asc = 0x00;
    scsi_complete(SCSI_GOOD);
}

// Move one 512-byte sector from the image into the buffer. The dataslot lands
// it in the bridge RAM a 32-bit word at a time; the buffer takes bytes, little
// end first, so the image's byte order survives.
static int scsi_push_sector(uint32_t lba)
{
    if (!tds_transfer(HDD0_SLOT_ID, lba, FDD_TDS_READ))
        return 0;
    *FDD_BRAM_ADDR = 0;
    for (int i = 0; i < SECTOR_WORDS; i++) {
        uint32_t w = *FDD_BRAM_RDATA;
        scsi_put((uint8_t) (w & 0xFF));
        scsi_put((uint8_t) ((w >> 8) & 0xFF));
        scsi_put((uint8_t) ((w >> 16) & 0xFF));
        scsi_put((uint8_t) ((w >> 24) & 0xFF));
    }
    return 1;
}

static int scsi_drain_sector(uint32_t lba)
{
    *FDD_BRAM_ADDR = 0;
    for (int i = 0; i < SECTOR_WORDS; i++) {
        uint32_t b0 = scsi_get();
        uint32_t b1 = scsi_get();
        uint32_t b2 = scsi_get();
        uint32_t b3 = scsi_get();
        *FDD_BRAM_WDATA = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    }
    return tds_transfer(HDD0_SLOT_ID, lba, FDD_TDS_WRITE);
}

// The buffer is 8 KB, so a transfer is capped at sixteen blocks per command.
// The disk BIOS issues far smaller ones; a request past the cap is answered
// short rather than overrun, which a target is allowed to do.
#define SCSI_MAX_BLOCKS 16

static void scsi_do_read(uint32_t lba, uint32_t blocks)
{
    if (!scsi_sectors) { scsi_fail(SENSE_NOT_READY, 0x3A); return; }
    if (blocks == 0) { scsi_ok(); return; }
    if (blocks > SCSI_MAX_BLOCKS) blocks = SCSI_MAX_BLOCKS;
    if (lba >= scsi_sectors || (lba + blocks) > scsi_sectors) {
        scsi_fail(SENSE_ILLEGAL_REQ, 0x21);   // LBA out of range
        return;
    }
    scsi_rewind_write();
    scsi_buf_seek(0);
    for (uint32_t i = 0; i < blocks; i++) {
        if (!scsi_push_sector(lba + i)) {
            scsi_fail(SENSE_NOT_READY, 0x11); // unrecovered read error
            return;
        }
    }
    scsi_rewind_read();
    scsi_ok();
}

static void scsi_do_write(uint32_t lba, uint32_t blocks)
{
    if (!scsi_sectors) { scsi_fail(SENSE_NOT_READY, 0x3A); return; }
    if (blocks == 0) { scsi_ok(); return; }
    if (blocks > SCSI_MAX_BLOCKS) blocks = SCSI_MAX_BLOCKS;
    if (lba >= scsi_sectors || (lba + blocks) > scsi_sectors) {
        scsi_fail(SENSE_ILLEGAL_REQ, 0x21);
        return;
    }
    scsi_buf_seek(0);
    for (uint32_t i = 0; i < blocks; i++) {
        if (!scsi_drain_sector(lba + i)) {
            scsi_fail(SENSE_NOT_READY, 0x0C); // write error
            return;
        }
    }
    scsi_rewind_write();
    scsi_ok();
}

static void scsi_do_inquiry(uint32_t alloc)
{
    static const char vendor[8]  = {'N','E','C',' ',' ',' ',' ',' '};
    static const char product[16] = {'P','C','-','9','8',' ','H','D',
                                     'D',' ',' ',' ',' ',' ',' ',' '};
    static const char rev[4] = {'1','.','0','0'};
    uint8_t d[36];
    for (int i = 0; i < 36; i++) d[i] = 0;
    d[0] = 0x00;            // direct access device
    d[1] = 0x00;            // not removable
    d[2] = 0x01;            // SCSI-1
    d[3] = 0x01;            // response format
    d[4] = 31;              // additional length
    for (int i = 0; i < 8;  i++) d[8 + i]  = (uint8_t) vendor[i];
    for (int i = 0; i < 16; i++) d[16 + i] = (uint8_t) product[i];
    for (int i = 0; i < 4;  i++) d[32 + i] = (uint8_t) rev[i];

    if (alloc == 0 || alloc > 36) alloc = 36;
    scsi_rewind_write();
    scsi_buf_seek(0);
    for (uint32_t i = 0; i < alloc; i++) scsi_put(d[i]);
    scsi_rewind_read();
    scsi_ok();
}

static void scsi_do_read_capacity(void)
{
    if (!scsi_sectors) { scsi_fail(SENSE_NOT_READY, 0x3A); return; }
    // The returned LBA is the LAST one, not the count.
    uint32_t last = scsi_sectors - 1;
    scsi_rewind_write();
    scsi_buf_seek(0);
    scsi_put((uint8_t) (last >> 24));
    scsi_put((uint8_t) (last >> 16));
    scsi_put((uint8_t) (last >> 8));
    scsi_put((uint8_t) last);
    scsi_put(0); scsi_put(0); scsi_put(2); scsi_put(0);   // 512-byte blocks
    scsi_rewind_read();
    scsi_ok();
}

static void scsi_do_request_sense(uint32_t alloc)
{
    uint8_t d[18];
    for (int i = 0; i < 18; i++) d[i] = 0;
    d[0] = 0x70;                // current error, fixed format
    d[2] = scsi_sense_key;
    d[7] = 10;                  // additional length
    d[12] = scsi_asc;
    if (alloc == 0 || alloc > 18) alloc = 18;
    scsi_rewind_write();
    scsi_buf_seek(0);
    for (uint32_t i = 0; i < alloc; i++) scsi_put(d[i]);
    scsi_rewind_read();
    // REQUEST SENSE itself succeeds and clears the pending sense.
    scsi_sense_key = SENSE_NO_SENSE;
    scsi_asc = 0x00;
    scsi_complete(SCSI_GOOD);
}

static void scsi_do_mode_sense(uint32_t alloc)
{
    // A four-byte header with no block descriptor and no pages: enough for the
    // BIOS to see a writable, present device without inventing geometry the
    // image does not have.
    uint8_t d[4];
    d[0] = 3;       // length after this byte
    d[1] = 0;       // medium type
    d[2] = 0;       // not write protected
    d[3] = 0;       // block descriptor length
    if (alloc == 0 || alloc > 4) alloc = 4;
    scsi_rewind_write();
    scsi_buf_seek(0);
    for (uint32_t i = 0; i < alloc; i++) scsi_put(d[i]);
    scsi_rewind_read();
    scsi_ok();
}

static void scsi_execute(const uint8_t *cdb)
{
    uint32_t lba, blocks;

    switch (cdb[0]) {
    case SCSI_TEST_UNIT_READY:
        if (scsi_sectors) scsi_ok();
        else              scsi_fail(SENSE_NOT_READY, 0x3A);
        break;

    case SCSI_REZERO:
    case SCSI_SEEK6:
    case SCSI_SEEK10:
    case SCSI_START_STOP:
    case SCSI_MODE_SELECT6:
    case SCSI_FORMAT_UNIT:
        // Accepted and ignored. The image is already formatted and there is
        // nothing to spin up; failing these makes the BIOS give up on a disk
        // that is perfectly readable.
        scsi_ok();
        break;

    case SCSI_REQUEST_SENSE:
        scsi_do_request_sense(cdb[4]);
        break;

    case SCSI_INQUIRY:
        scsi_do_inquiry(cdb[4]);
        break;

    case SCSI_MODE_SENSE6:
        scsi_do_mode_sense(cdb[4]);
        break;

    case SCSI_READ_CAPACITY:
        scsi_do_read_capacity();
        break;

    case SCSI_READ6:
        // Group 0: 21-bit LBA, the low five bits of byte 1 plus bytes 2-3.
        lba = ((uint32_t) (cdb[1] & 0x1F) << 16)
            | ((uint32_t) cdb[2] << 8) | cdb[3];
        blocks = cdb[4] ? cdb[4] : 256;
        scsi_do_read(lba, blocks);
        break;

    case SCSI_WRITE6:
        lba = ((uint32_t) (cdb[1] & 0x1F) << 16)
            | ((uint32_t) cdb[2] << 8) | cdb[3];
        blocks = cdb[4] ? cdb[4] : 256;
        scsi_do_write(lba, blocks);
        break;

    case SCSI_READ10:
        lba = ((uint32_t) cdb[2] << 24) | ((uint32_t) cdb[3] << 16)
            | ((uint32_t) cdb[4] << 8)  | cdb[5];
        blocks = ((uint32_t) cdb[7] << 8) | cdb[8];
        scsi_do_read(lba, blocks);
        break;

    case SCSI_WRITE10:
        lba = ((uint32_t) cdb[2] << 24) | ((uint32_t) cdb[3] << 16)
            | ((uint32_t) cdb[4] << 8)  | cdb[5];
        blocks = ((uint32_t) cdb[7] << 8) | cdb[8];
        scsi_do_write(lba, blocks);
        break;

    default:
        scsi_fail(SENSE_ILLEGAL_REQ, 0x20);   // invalid command operation code
        break;
    }
}

void scsi_mount(uint32_t sectors)
{
    scsi_sectors = sectors;
    scsi_sense_key = SENSE_NO_SENSE;
    scsi_asc = 0x00;
}

void scsi_init(void)
{
    scsi_sectors = 0;
    scsi_sense_key = SENSE_NO_SENSE;
    scsi_asc = 0x00;
    scsi_ack = 0;
    scsi_mgmt_write(SMGMT_AUXSTAT, 0x00);
    scsi_mgmt_write(SMGMT_STATUS, SCSI_GOOD);
}

// Called from the main loop. Register 0 bit 0 is (cmd_req != our ack), so a
// command is a level we can poll and clear rather than a pulse we can miss.
void scsi_poll(void)
{
    uint32_t ctrl = scsi_mgmt_read(SMGMT_CTRL);
    if (!(ctrl & 1))
        return;

    // Acknowledge first. A second command cannot arrive until the guest has
    // read the status, and clearing late would re-run this one.
    scsi_mgmt_write(SMGMT_CTRL, 1);
    scsi_ack = !scsi_ack;

    uint8_t cdb[CDB_MAX];
    scsi_get_cdb(cdb);
    scsi_execute(cdb);
}
