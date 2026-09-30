// drive_sound.c -- floppy mechanism noise played through the OPNA's own
// ADPCM-A voices.
//
// The dedicated fdd_sound sample player is gone from the RTL. What remains
// is the event picture: floppy.v's taps surface over the FDD mgmt register
// 0xE ({step_cnt, head, xfer, motor}), and the samples live in the rhythm
// store's upper half, encoded to ADPCM-A on load from the fddsnd.bin
// dataslot. The same jt12 rhythm voices then play them, keyed by injection
// through the management window.
//
// Channel policy: a mechanism sample borrows whichever voice is certainly
// free -- the ADPCM-A status bits are sticky end flags, so a set flag means
// a finished voice; cleared-flag channels come second. The borrow clears
// the flag fresh, programs that channel's start/end pair for the drive
// segment, keys it on, and on completion restores the drum pair rhythm.c
// recorded plus the guest's last-written LR+AL (mgmt regs 9-14). A guest
// key-on landing mid-borrow plays the drive sample: bounded, rare, and
// only on channels a kit uses.
//
// Loop voices (seek rattle, read hiss, motor hum) are one-shots in ADPCM-A,
// so looping is re-armed by the poll: a borrowed channel is re-keyed
// whenever its flag drops while its level still wants it. The level
// falling stops the re-key and lets the tail play out -- also what a real
// drive sounds like spinning down.

#include "softcpu_regs.h"
#include "adpcma_enc.h"
#include "settings_ui.h"

#define FDDSND_MAGIC   0x4446u   // 'FD' (word 0; word 1 is 'S1' = 0x3153)
#define FDDSND_MAGIC2  0x3153u   // 'S1'
#define FDDSND_RATE    24000u    // s8 sample rate inside fddsnd.bin
#define DRV_STORE_BASE 16384u    // upper half of the 32 KB rhythm store
#define DRV_STORE_END  32768u
#define DRV_SEGS       5

// Segment indices inside the file: tick, clunk, seek, read, motor -- the
// same order the old synth's VSEG table used.
#define SEG_TICK  0
#define SEG_CLUNK 1
#define SEG_SEEK  2
#define SEG_READ  3
#define SEG_MOTOR 4

// jt12 part-1 ADPCM-A registers, as the injection port addresses them:
// reg 0x00 = {dump,xx,mask[5:0]} key control, 0x08+ch = {l,r,al[4:0]},
// 0x10/0x18+ch and 0x20/0x28+ch = start/end in 256-byte units.
#define INJ_KEY     0x00u
#define INJ_LR_BASE 0x08u

static uint16_t drv_start[DRV_SEGS], drv_end[DRV_SEGS];
static uint8_t  drv_loaded;

// ------------------------------ loader ------------------------------------
// One bounded step per call, same discipline as rhythm.c's wav path: parse
// the header, then for each segment stream source bytes through adpcma_enc
// into the store's upper half.

static uint8_t   dl_hdr_done, dl_failed, dl_open;
static uint32_t  dl_seg;
static uint32_t  dl_cursor;             // absolute store byte, 256-aligned
static uint32_t  dl_seg_base;           // where this segment's stream began
static adpcm_enc dl_enc;
static uint32_t  dl_src_off, dl_src_left;
static uint16_t  seg_off[DRV_SEGS], seg_len[DRV_SEGS];

int drive_sound_load(void)
{
    // Slim builds have no store and no drvA; OMGMT_CAPS bit0 tells us.
    if (!(opna_mgmt_read(OMGMT_CAPS) & 1))
        return 1;

    if (!dl_hdr_done) {
        // fddsnd.bin: u16 'FD', u16 'S1', u16 version, u16 segment count,
        // then five {off,len} pairs in 16-bit word units; s8 payload
        // follows (24 kHz, two per word, low byte first).
        if (!slot_bytes(FDDSND_SLOT_ID) ||
            !tds_transfer(FDDSND_SLOT_ID, 0, FDD_TDS_READ, 28))
            return 0;
        *FDD_BRAM_ADDR = 0;
        if ((*FDD_BRAM_RDATA & 0xFFFF) != FDDSND_MAGIC ||
            (*FDD_BRAM_RDATA & 0xFFFF) != FDDSND_MAGIC2)
            return 1;                       // no kit: stay quiet forever
        (void)*FDD_BRAM_RDATA;              // version
        (void)*FDD_BRAM_RDATA;              // segment count
        for (uint32_t i = 0; i < DRV_SEGS; i++) {
            seg_off[i] = *FDD_BRAM_RDATA & 0xFFFF;
            seg_len[i] = *FDD_BRAM_RDATA & 0xFFFF;
        }
        dl_cursor = DRV_STORE_BASE;
        dl_seg    = 0;
        dl_hdr_done = 1;
        return 0;
    }

    if (!dl_open) {
        if (dl_seg >= DRV_SEGS) {
            drv_loaded = 1;
            return 1;
        }
        adpcm_enc_init(&dl_enc, FDDSND_RATE);
        // word units -> file bytes; s8 packs two per word.
        dl_src_off  = (uint32_t)seg_off[dl_seg] * 2;
        dl_src_left = (uint32_t)seg_len[dl_seg] * 2;
        dl_seg_base = dl_cursor;
        dl_failed   = 0;
        dl_open     = 1;
    }

    // Absolute re-arm every emit call: rhythm.c's loaders share the address
    // register between calls, so nothing may rely on the auto-increment
    // surviving a call boundary.
    opna_mgmt_write(OMGMT_RHYADDR, dl_cursor);

    // One 512-byte source chunk per call.
    uint32_t n = dl_src_left > SECTOR_BYTES ? SECTOR_BYTES : dl_src_left;
    if (n && !tds_transfer(FDDSND_SLOT_ID, dl_src_off, FDD_TDS_READ, n)) {
        dl_failed = 1;
    } else if (n) {
        dl_src_off  += n;
        dl_src_left -= n;
        *FDD_BRAM_ADDR = 0;
        for (uint32_t wi = 0; wi < (n + 3) / 4; wi++) {
            uint32_t w = *FDD_BRAM_RDATA;
            for (uint32_t b = 0; b < 4 && wi * 4 + b < n; b++) {
                int16_t s = (int16_t)((int8_t)(w >> (b * 8))) << 8;
                if (adpcm_enc_push(&dl_enc, s)) {
                    for (uint32_t i = 0; i < dl_enc.out_n; i++) {
                        if (dl_cursor < DRV_STORE_END) {
                            opna_mgmt_write(OMGMT_RHYDATA, dl_enc.out[i]);
                            dl_cursor++;
                        }
                    }
                }
            }
        }
    }

    if (dl_failed || dl_src_left == 0) {
        while (adpcm_enc_flush(&dl_enc)) {
            for (uint32_t i = 0; i < dl_enc.out_n; i++) {
                if (dl_cursor < DRV_STORE_END) {
                    opna_mgmt_write(OMGMT_RHYDATA, dl_enc.out[i]);
                    dl_cursor++;
                }
            }
        }
        if (!dl_failed && dl_cursor > dl_seg_base) {
            drv_start[dl_seg] = dl_seg_base >> 8;
            drv_end[dl_seg]   = (dl_cursor - 1) >> 8;
        } else {
            drv_start[dl_seg] = drv_end[dl_seg] = 0;
        }
        // The next segment starts on a fresh 256 boundary.
        dl_cursor = (dl_cursor + 255) & ~255u;
        dl_seg++;
        dl_open = 0;
    }
    return 0;
}

// ---------------------------- the service ---------------------------------

// Channels the drive kit has borrowed: -1 free, else the segment playing.
static int8_t  ch_seg[6] = { -1, -1, -1, -1, -1, -1 };
// Poll ticks since the borrow's key-on. A guest flag-control sweep could
// eat an end flag and strand a borrow; the age gives it a bounded life.
static uint16_t ch_age[6];
#define CH_AGE_MAX 4096u                 // ~seconds of polls, past any segment

static uint8_t  last_step_cnt, last_head;
static uint16_t seek_hold;               // rattle holdover, in poll ticks

static uint32_t mgmt_fdd_rd(uint32_t reg)
{
    *FDD_MGMT_ADDR = reg & 0xF;
    *FDD_MGMT_TRIG = FDD_MGMT_RD;
    return *FDD_MGMT_RDATA & 0xFFFF;
}

static void inj_p1(uint32_t reg, uint32_t data)
{
    uint32_t to = DISK_SPIN_LIMIT;
    while ((opna_mgmt_read(OMGMT_BUSY) & 1) && --to)
        ;
    opna_mgmt_write(OMGMT_INJ_P1, (reg << 8) | data);
}

static void inj_p0(uint32_t reg, uint32_t data)
{
    uint32_t to = DISK_SPIN_LIMIT;
    while ((opna_mgmt_read(OMGMT_BUSY) & 1) && --to)
        ;
    opna_mgmt_write(OMGMT_INJ_P0, (reg << 8) | data);
}

// The ADPCM-A status bits are sticky END flags, not playing bits: they set
// when a voice reaches its end address and stay until the flag-control
// register (jt12 part 0, 0x1C) clears them. Clear is a level -- the mask
// must be written and then released, or the flag can never set.
static void flag_clear(uint32_t ch)
{
    inj_p0(0x1C, 1u << ch);
    inj_p0(0x1C, 0u);
}

static void inj_pair(uint32_t ch, uint32_t start256, uint32_t end256)
{
    inj_p1(0x10u + ch, start256 & 0xFF);
    inj_p1(0x18u + ch, (start256 >> 8) & 0xF);
    inj_p1(0x20u + ch, end256 & 0xFF);
    inj_p1(0x28u + ch, (end256 >> 8) & 0xF);
}

// The kit's level per menu mode: 5.25" is the louder mechanism the pack was
// built around; 3.5" sits lower. Both speakers get the voice (l=r=1).
static uint32_t mode_al(void)
{
    return settings_drive_sound() == 2 ? 14u : 6u;
}

static void chan_restore(uint32_t ch)
{
    inj_pair(ch, rhythm_start[ch], rhythm_end[ch]);
    inj_p1(INJ_LR_BASE + ch, opna_mgmt_read(OMGMT_LR0 + ch) & 0xFF);
    ch_seg[ch] = -1;
    ch_age[ch] = 0;
}

// Borrow a channel for a segment and key it on. Preferred pick order:
// an ended flag means the voice is certainly idle; a clear flag might be a
// voice sounding, so those come second. Nothing happens when the pick is
// hopeless -- the event simply does not click, the same mercy the games'
// own key-ons get when the chip is full.
static void chan_play(uint32_t seg)
{
    uint32_t flags = opna_mgmt_read(OMGMT_STATUS1) & 0x3F;
    int ch = -1;
    for (int i = 5; i >= 0 && ch < 0; i--)
        if (ch_seg[i] < 0 && (flags & (1u << i)))
            ch = i;
    for (int i = 5; i >= 0 && ch < 0; i--)
        if (ch_seg[i] < 0 && !(flags & (1u << i)))
            ch = i;
    if (ch < 0)
        return;
    // Clear first so the end flag rises fresh for this sample, then the
    // pair, the level, and finally the key.
    flag_clear(ch);
    inj_pair(ch, drv_start[seg], drv_end[seg]);
    inj_p1(INJ_LR_BASE + ch, 0xC0 | mode_al());
    inj_p1(INJ_KEY, 1u << ch);
    ch_seg[ch] = seg;
    ch_age[ch] = 0;
}

static int seg_chan(uint32_t seg)
{
    for (uint32_t ch = 0; ch < 6; ch++)
        if (ch_seg[ch] == (int8_t)seg)
            return (int)ch;
    return -1;
}

void drive_sound_poll(void)
{
    if (!drv_loaded)
        return;

    uint32_t v = mgmt_fdd_rd(FMGMT_SNDEV);
    uint32_t cnt   = (v >> 8) & 0xFF;
    uint32_t head  = (v >> 2) & 1;
    uint32_t xfer  = (v >> 1) & 1;
    uint32_t motor =  v       & 1;
    uint32_t on    = settings_drive_sound();

    // Turning the option off must not strand a borrowed channel: the flag
    // sweep below still runs and hands the voice back to the drum kit the
    // moment its sample ends. It only gates new plays.
    if (on) {
        // One-shots are edge-triggered; a burst of steps still reads as a
        // counter delta, so no step is lost even under a slow poll.
        if (cnt != last_step_cnt) {
            chan_play(SEG_TICK);
            seek_hold = 60;          // ~60 polls of rattle after the step
        }
        if (head && !last_head)
            chan_play(SEG_CLUNK);

        // Loops are level-triggered and self-healing: a live level with no
        // channel playing it borrows one (covering the "channels were full
        // at the edge" case), a dead level just lets the tail play out.
        if (seek_hold && seg_chan(SEG_SEEK) < 0)
            chan_play(SEG_SEEK);
        if (xfer && seg_chan(SEG_READ) < 0)
            chan_play(SEG_READ);
        if (motor && seg_chan(SEG_MOTOR) < 0)
            chan_play(SEG_MOTOR);
    }
    last_step_cnt = cnt;
    last_head     = head;
    if (seek_hold)
        seek_hold--;

    // Flag pass: a set flag means the borrowed sample reached its end.
    // Loops that still want their level re-key (clearing the flag again
    // first); everything else gives the channel back to the drum kit with
    // its pair and guest LR+AL restored.
    uint32_t flags = opna_mgmt_read(OMGMT_STATUS1) & 0x3F;
    for (uint32_t ch = 0; ch < 6; ch++) {
        if (ch_seg[ch] < 0)
            continue;
        if (ch_age[ch] < CH_AGE_MAX)
            ch_age[ch]++;
        if (!(flags & (1u << ch)) && ch_age[ch] < CH_AGE_MAX)
            continue;
        int keep = on &&
            ((ch_seg[ch] == SEG_SEEK  && seek_hold) ||
             (ch_seg[ch] == SEG_READ  && xfer)      ||
             (ch_seg[ch] == SEG_MOTOR && motor));
        if (keep) {
            flag_clear(ch);
            inj_p1(INJ_KEY, 1u << ch);   // loop re-arm
            ch_age[ch] = 0;
        } else {
            chan_restore(ch);
        }
    }
}
