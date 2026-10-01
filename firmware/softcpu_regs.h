#ifndef SOFTCPU_REGS_H
#define SOFTCPU_REGS_H

#include <stdint.h>

// Disk-bridge registers (softcpu_fdd_bridge), mapped in the 0x3 region.
#define FDD_REQUEST    ((volatile uint32_t *) 0x30000000) // R: {write, read} pending
#define FDD_MGMT_ADDR  ((volatile uint32_t *) 0x30000004) // W: {drive << 4, reg[3:0]}
#define FDD_MGMT_WDATA ((volatile uint32_t *) 0x30000008) // W: mgmt write data [15:0]
#define FDD_MGMT_TRIG  ((volatile uint32_t *) 0x3000000C) // W: bit0 write, bit1 read
#define FDD_MGMT_PUSH  ((volatile uint32_t *) 0x3000005C) // W: fused WDATA+write-trigger
#define FDD_MGMT_RDATA ((volatile uint32_t *) 0x30000010) // R: captured mgmt read data
#define FDD_BRAM_ADDR  ((volatile uint32_t *) 0x30000014) // W: bridge-RAM word address
#define FDD_BRAM_RDATA ((volatile uint32_t *) 0x30000018) // R: bridge-RAM word (auto-inc)
#define FDD_BRAM_WDATA ((volatile uint32_t *) 0x3000001C) // W: bridge-RAM word (auto-inc)
#define FDD_TDS_ID     ((volatile uint32_t *) 0x30000020) // W: dataslot id
#define FDD_TDS_OFFSET ((volatile uint32_t *) 0x30000024) // W: dataslot byte offset
#define FDD_TDS_BRIDGE ((volatile uint32_t *) 0x30000028) // W: bridge address
#define FDD_TDS_LENGTH ((volatile uint32_t *) 0x3000002C) // W: transfer length in bytes
#define FDD_TDS_TRIG   ((volatile uint32_t *) 0x30000030) // W: bit0 read, bit1 write
#define FDD_TDS_STATUS ((volatile uint32_t *) 0x30000034) // R: bit0 done, bits[3:1] err
#define FDD_TDS_CLR    ((volatile uint32_t *) 0x30000038) // W: bit0 clear done
#define FDD0_DISK_SIZE ((volatile uint32_t *) 0x3000003C) // R: floppy-0 image size in sectors
#define FDD1_DISK_SIZE ((volatile uint32_t *) 0x30000040) // R: floppy-1 image size in sectors
#define FDD_REBIND     ((volatile uint32_t *) 0x30000050) // R: per-floppy image-rebind toggles
#define DTBL_ADDR      ((volatile uint32_t *) 0x30000054) // W: datatable word index
#define DTBL_DATA      ((volatile uint32_t *) 0x30000058) // R: datatable word at the index; W: write it

// OSD GPU command registers (softcpu_subsystem), mapped in the 0x4 region. Set XY (and WH for
// FILL/OUTLINE) then write the op; poll STATUS between commands.
#define GPU_XY      ((volatile uint32_t *) 0x40000000) // W: {y[15:0], x[15:0]}
#define GPU_WH      ((volatile uint32_t *) 0x40000004) // W: {h[15:0], w[15:0]}
#define GPU_FILL    ((volatile uint32_t *) 0x40000008) // W: color[3:0] -> fill XY/WH rectangle
#define GPU_STATUS  ((volatile uint32_t *) 0x40000010) // R: bit0 = busy
#define GPU_OUTLINE ((volatile uint32_t *) 0x40000014) // W: {round[4], color[3:0]} -> outline rect
#define GPU_CHAR    ((volatile uint32_t *) 0x40000018) // W: {tall,transp,bg[15:12],fg[11:8],char[7:0]}

// OSD font window (softcpu_subsystem region 0x7): the GPU's glyph RAM,
// word-addressed with byte enables (any store width lands; the loader copies
// in words). The window holds font.rom's two ANK banks at the file's own
// offsets: bytes 0x000-0x7FF the 8x8 bank (256 glyphs x 8 bytes), bytes
// 0x800-0x17FF the 8x16 bank (256 x 16). Powers up blank; osd_font.c fills it
// from font.rom at boot and patches in this core's own glyphs (the old
// baked-in image was CP437/NEC-derived and cannot ship in the repository or
// the bitstream).
#define FONT_WIN ((volatile uint8_t *) 0x70000000u)

// GPU_OUTLINE flag: omit the four corner pixels (1px-rounded look).
#define GPU_OUTLINE_ROUND (1u << 4)
// GPU_CHAR flag: draw only the glyph's lit pixels, leaving the background untouched.
#define GPU_CHAR_TRANSP (1u << 16)
// GPU_CHAR flag: draw an 8x16 cell from the 8x16 ANK bank (the window's 0x800+
// region) instead of the default 8x8 cell from the 8x8 bank.
#define GPU_CHAR_TALL (1u << 17)

// Status / control (0x2 region).
#define CONT1_KEY       ((volatile uint32_t *) 0x20000000) // R: pocket controller-1 buttons
#define VKB_CTRL        ((volatile uint32_t *) 0x20000004) // W: bit0 = OSD overlay shown
#define VKB_KEY         ((volatile uint32_t *) 0x20000008) // W: bit8 = make, bits[7:0] Set-2 code
#define SETTINGS_REG    ((volatile uint32_t *) 0x2000000C) // W: {index[12:8], value[7:0]}
#define OSD_ACTION      ((volatile uint32_t *) 0x20000010) // W: bit2 video
#define OSD_ORIGIN      ((volatile uint32_t *) 0x20000014) // W: {y[25:16], x[9:0]} framebuffer origin
#define OSD_RASTER      ((volatile uint32_t *) 0x20000018) // R: {h[25:16], w[9:0]} presented raster size
#define SOFT_GUEST_HOLD ((volatile uint32_t *) 0x2000001C) // W: bit0 = hold guest in reset, bit1 = blank video
#define KEYCFG_REG      ((volatile uint32_t *) 0x20000020) // W: {id[12:9], ext[8], code[7:0]}
#define SOFT_SCSI_MEDIA ((volatile uint32_t *) 0x20000030) // W: bit0 = HDD image mounted (gates the disk lamp)

// OSD_ACTION command bits.
#define OSD_ACT_VIDEO   4u

// cont1_key button bits (Analogue Pocket layout).
#define BTN_UP     (1 << 0)
#define BTN_DOWN   (1 << 1)
#define BTN_LEFT   (1 << 2)
#define BTN_RIGHT  (1 << 3)
#define BTN_A      (1 << 4)
#define BTN_B      (1 << 5)
#define BTN_X      (1 << 6)
#define BTN_Y      (1 << 7)
#define BTN_L1     (1 << 8)
#define BTN_R1     (1 << 9)
#define BTN_SELECT (1 << 14)
#define BTN_START  (1 << 15)

// CONT1_KEY carries status flags in its upper bits (the low 16 are the buttons): the last
// docked-keyboard make in code[23:16] + ext[27] with a change toggle[28] for the key picker,
// osd_open[25], dataslots_ready[26].
#define CONT1_OSD_OPEN(raw)  ((raw) & (1u << 25))    // interact "Extra Options" requests the OSD
#define DATASLOTS_READY(raw) ((raw) & (1u << 26))    // APF finished the initial dataslot load
#define CONT1_DOCK_CODE(raw) (((raw) >> 16) & 0xFFu) // last docked-keyboard make: Set-2 code
#define CONT1_DOCK_EXT(raw)  (((raw) >> 27) & 1u)    // its E0 flag
#define CONT1_DOCK_STB(raw)  (((raw) >> 28) & 1u)    // toggles per docked make

// OSD_RASTER field extractors.
#define RASTER_W(raw) ((raw) & 0x3FFu)
#define RASTER_H(raw) (((raw) >> 16) & 0x3FFu)

// Button function ids the softcore routes (from the binding table in key_bind.c; keyboard-key
// bindings are typed by pocket_keyboard, not here).
#define BTNFN_NONE     0u
#define BTNFN_SETTINGS 1u
// 2 (the retired credits overlay) stays reserved: a save blob can still carry a 0xF2 binding,
// which decodes to it and dispatches to nothing.
#define BTNFN_VIDEO    3u

// FDD_REQUEST bits
#define FDD_REQ_READ  (1 << 0)
#define FDD_REQ_WRITE (1 << 1)

// FDD_REBIND bits: one toggle per floppy drive, flipping on each image (re)bind.
#define FDD0_REBIND_BIT (1 << 0)
#define FDD1_REBIND_BIT (1 << 1)

// FDD_MGMT_TRIG bits
#define FDD_MGMT_WR (1 << 0)
#define FDD_MGMT_RD (1 << 1)

// FDD_TDS_TRIG bits
#define FDD_TDS_READ  (1 << 0)
#define FDD_TDS_WRITE (1 << 1)

// FDD_TDS_STATUS bits
#define FDD_TDS_DONE (1 << 0)
#define FDD_TDS_ERR  (7 << 1) // bits[3:1]: non-zero = transfer error

// floppy.v management registers (mgmt_address[3:0]). Register 0 reads back the
// requested LBA ({drive, lba[14:0]}) and is written to set media-present.
#define FMGMT_PRESENT 0x0
#define FMGMT_WRPROT  0x1
#define FMGMT_CYLS    0x2
#define FMGMT_SPT     0x3
#define FMGMT_TOTAL   0x4
#define FMGMT_HEADS   0x5
#define FMGMT_SECSIZE 0x6   // bit0: sectors are 1024 bytes (PC-98 2HD), not 512
#define FMGMT_SNDEV   0xE   // R: drive-noise events {step_cnt[15:8], 5'd0, head, xfer, motor}
#define FMGMT_FIFO    0xF

// LBA read from register 0: 15-bit block, bit 15 selects drive B.
#define FDD_LBA_MASK  0x7FFF
#define FDD_LBA_DRIVE 0x8000

// Management-bus target selects (FDD_MGMT_ADDR bits): the byte routes the
// transaction to a service target instead of floppy.v (0xF2).
#define SCSI_TARGET   (1 << 9) // FDD_MGMT_ADDR bit: select pc98_scsi (mgmt 0xF4)
#define OPNA_TARGET   (1 << 10) // FDD_MGMT_ADDR bit: select pc98_opna (mgmt 0xF5)

// pc98_opna management registers (mgmt_address[3:0]). See pc98_opna.sv.
#define OMGMT_RHYADDR  0x0     // W: rhythm-store byte address (reg1 writes auto-increment)
#define OMGMT_RHYDATA  0x1     // W: rhythm-store byte
#define OMGMT_INJ_P0   0x2     // W: {reg[15:8], data[7:0]} raw write, jt12 part 0
#define OMGMT_INJ_P1   0x3     // W: same, part 1 (ADPCM-A start/end live here)
#define OMGMT_BUSY     0x4     // R: bit0 = injected register still landing
#define OMGMT_STATUS0  0x5     // R: jt12 status0 {busy,5'd0,flag_B,flag_A}
#define OMGMT_STATUS1  0x6     // R: jt12 status1 {adpcmb_flag,1'b0,adpcma_flags[5:0]}
#define OMGMT_CAPS     0x8     // R: bit0 = ADPCM-A store present (USE_ADPCM build)
#define OMGMT_LR0      0x9     // R: guest's last LR+AL per voice (9..14 = ch0..5)

// pc98_scsi management registers (mgmt_address[3:0]). See PERIPHERALS.
#define SMGMT_CTRL    0x0      // R: {cmd_byte, req != ack}  W: bit0 acknowledges
#define SMGMT_REGIDX  0x1      // W: control-register index
#define SMGMT_REGDATA 0x2      // R/W: that register, index post-increments
#define SMGMT_BUFPTR  0x3      // W: data-buffer pointer
#define SMGMT_BUFDATA 0x4      // R/W: buffer byte, pointer post-increments
#define SMGMT_AUXSTAT 0x5      // W: the byte 0xCC0 hands the guest
#define SMGMT_STATUS  0x6      // W: the byte index 0x17 hands the guest
#define SMGMT_PTRCLR  0x7      // W: bit0 rewinds read ptr, bit1 write ptr
// APF bridge-RAM base and the sector geometry the transfers use.
#define FDD_BRIDGE_BASE 0x60000000
#define SECTOR_BYTES    512
#define SECTOR_WORDS    128

// Bounded spin for disk waits (dataslot transfers and SCSI data-phase handshakes) so a
// stalled transfer or a guest that abandons one cannot hang the softcore, which serves
// both disks and draws the OSD. A real wait resolves in well under a millisecond; this
// is a few seconds of margin, never a false trip.
#define DISK_SPIN_LIMIT 4000000u

// Dataslot ids, matching data.json. Floppy sizes arrive via the dataslot event
// (FDD*_DISK_SIZE); HDD and Settings sizes are read from the datatable by id (slot_bytes).
#define FDD0_SLOT_ID     3
#define FDD1_SLOT_ID     4
#define HDD0_SLOT_ID     5
#define HDD1_SLOT_ID     6
#define SETTINGS_SLOT_ID 7
#define RHYTHM_SLOT_ID   13   // deferload: rhythm.bin, packed ADPCM-A voices
#define RHY_WAV_SLOT_BASE 14  // deferload ids 14-19: per-voice *.wav sources
#define FDDSND_SLOT_ID   20   // deferload, filename-bound: fddsnd.bin mechanism samples (s8/24k)
// Bytes to declare for the nonvolatile Settings slot so it flushes on first boot.
// The whole upper half of the 1 KB bridge RAM: the global settings blob plus
// the per-disk profile table (settings_ui.c).
#define SETTINGS_SLOT_BYTES 512

// Shared disk-bridge sector transfer (disk_tds.c). The length is the media's
// sector width, because the image file is laid out in that width.
// tds_transfer_to lands the bytes at an explicit bridge-RAM byte address --
// the read path's prefetch buffer lives at FDD_BRIDGE_BASE + 1024.
int tds_transfer(uint32_t slot, uint32_t offset, uint32_t dir, uint32_t bytes);
int tds_transfer_to(uint32_t slot, uint32_t offset, uint32_t dir, uint32_t bytes,
                    uint32_t bridge_addr);

// APF datatable access by slot id (disk_tds.c).
uint32_t slot_bytes(uint16_t id);

// OPNA management window (rhythm.c): store writes and jt12 register
// injection. drive_sound.c shares both.
void     opna_mgmt_write(uint32_t reg, uint32_t data);
uint32_t opna_mgmt_read(uint32_t reg);
// The six ADPCM-A start/end pairs the drum kit last programmed (256-byte
// units). drive_sound.c restores them after borrowing a voice.
extern uint16_t rhythm_start[6], rhythm_end[6];
// Chunked loaders / services; both return nonzero when finished.
// drive_sound_present reads OMGMT_CAPS bit0 -- 0 on a slim (USE_ADPCM=0)
// OPNA build, where the voices and the store do not exist.
int  rhythm_load(void);
int  drive_sound_present(void);
int  drive_sound_load(void);
void drive_sound_poll(void);

int slot_declare_size(uint16_t id, uint32_t bytes);

// Service entry points (fdd_service.c).
void fdd_mount(uint32_t drive, uint32_t sectors);
void fdd_eject(uint32_t drive);
void fdd_insert(uint32_t drive);
void fdd_unbind(uint32_t drive);
int  fdd_is_inserted(uint32_t drive);
uint32_t fdd_mounted_sectors(uint32_t drive);

// Service entry points (fdd_service.c, scsi_service.c). PC-98 only -- the
// board is a PC-9801-55.
void scsi_init(void);
void scsi_mount(uint32_t sectors);
void scsi_poll(void);
void fdd_poll(void);

#endif
