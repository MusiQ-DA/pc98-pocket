// OPNA rhythm store loader -- fills pc98_opna's ADPCM-A sample store at boot.
//
// The PC-9801-86's rhythm section is six ADPCM-A voices against a fixed ROM.
// This core keeps that sample data in a small firmware-filled store
// (pc98_opna.sv's rhy_mem): the guest's 0x10/0x11/0x18-0x1D writes already
// drive the real jt12 ADPCM-A engine, so what the guest can never reach --
// the sample bytes and the YM2610-style start/end pairs -- arrives here
// through the management window instead.
//
// Two source paths, mutually exclusive:
//
//  * Any of the six per-voice WAV dataslots (ids 14-19, "Rhythm BD" ... "RIM")
//    bound -> WAV mode. Each bound slot's file is parsed (RIFF, 8/16-bit PCM,
//    mono/stereo, any sane rate), resampled to the ~18.5 kHz ADPCM-A rate and
//    encoded on the fly by adpcma_enc.c into the store. Voices pack
//    sequentially from store offset 0; an unbound voice is skipped and its
//    channel just never gets a start/end pair, so it decodes silence.
//
//  * Otherwise the deferload "Rhythm PCM" dataslot (rhythm.bin on the card),
//    produced by scripts/rhythm_pack.py from the six 2608_*.wav files:
//
//      word 0    u32 magic 'RYA1'
//      word 1    u32 payload offset in the file (the voice table sits at +8)
//      word 2..7 six u16 pairs packed little-endian: voice i = {start256,
//                end256}, already in the 256-byte units jt10_adpcm_cnt works in
//      payload   ADPCM-A nibbles, two samples per byte, high nibble first,
//                each voice 256-byte aligned
//
// WAV mode wins whenever a WAV slot is bound: mixing the two would corrupt
// region offsets, since each path packs its own sequential layout.
//
// Nothing is required to be present: no bound slots, a slim-OPNA build (the
// capability flag reads 0) or unreadable files all just leave the store
// empty, and rhythm key-on writes then decode silence -- the same as before.
// A slot bound after the first complete pass is ignored, matching the bin
// path's semantics.

#include "softcpu_regs.h"
#include "adpcma_enc.h"

#define RHYTHM_MAGIC 0x31415952u // 'RYA1' little-endian
#define RHYTHM_HDR_WORDS 8
// Drums pack under the drive-noise kit: the hardware store is 32 KB, the
// upper half belongs to drive_sound.c's mechanism samples, so a voice's own
// data may not run past 16 KB.
#define RHY_STORE_BYTES 16384u

#define RIFF_RIFF 0x46464952u // 'RIFF'
#define RIFF_WAVE 0x45564157u // 'WAVE'
#define RIFF_FMT  0x20746D66u // 'fmt '
#define RIFF_DATA 0x61746164u // 'data'

void opna_mgmt_write(uint32_t reg, uint32_t data)
{
    *FDD_MGMT_ADDR = OPNA_TARGET | (reg & 0xF);
    *FDD_MGMT_WDATA = data & 0xFFFF;
    *FDD_MGMT_TRIG = FDD_MGMT_WR;
}

uint32_t opna_mgmt_read(uint32_t reg)
{
    *FDD_MGMT_ADDR = OPNA_TARGET | (reg & 0xF);
    *FDD_MGMT_TRIG = FDD_MGMT_RD;
    return *FDD_MGMT_RDATA & 0xFFFF;
}

// One start/end pair on jt12 part 1: start = regs 0x10/0x18 + ch (low/high
// byte of the 12-bit 256-unit address), end = regs 0x20/0x28 + ch. Each
// injection is two bus beats; rtr_busy (OMGMT_BUSY) clears when it lands.
static void inject_pair(uint32_t ch, uint32_t start256, uint32_t end256)
{
    uint32_t pair[4] = {
        (0x10u + ch) << 8 | (start256 & 0xFF),
        (0x18u + ch) << 8 | ((start256 >> 8) & 0xF),
        (0x20u + ch) << 8 | (end256 & 0xFF),
        (0x28u + ch) << 8 | ((end256 >> 8) & 0xF),
    };
    for (uint32_t i = 0; i < 4; i++) {
        uint32_t to = DISK_SPIN_LIMIT;
        while ((opna_mgmt_read(OMGMT_BUSY) & 1) && --to)
            ;
        opna_mgmt_write(OMGMT_INJ_P1, pair[i]);
    }
}

// ------------------------- rhythm.bin path ---------------------------------

static int bin_load(void)
{
    uint32_t total = slot_bytes(RHYTHM_SLOT_ID);
    if (total < RHYTHM_HDR_WORDS * 4 + 256)
        return 0;

    // Header: magic, payload offset, six {start256,end256} pairs.
    if (!tds_transfer(RHYTHM_SLOT_ID, 0, FDD_TDS_READ, RHYTHM_HDR_WORDS * 4))
        return 0;
    *FDD_BRAM_ADDR = 0;
    if (*FDD_BRAM_RDATA != RHYTHM_MAGIC)
        return 0;
    uint32_t payload = *FDD_BRAM_RDATA;
    if (payload < RHYTHM_HDR_WORDS * 4 || payload >= total)
        return 0;
    for (uint32_t i = 0; i < 6; i++) {
        uint32_t w = *FDD_BRAM_RDATA;
        rhythm_start[i] = w & 0xFFFF;
        rhythm_end[i]   = w >> 16;
        // Pairs naming bytes at or past the drum region's top would point a
        // voice into the drive-noise half; clamp them inside.
        if (rhythm_start[i] >= (RHY_STORE_BYTES >> 8))
            rhythm_start[i] = 0;
        if (rhythm_end[i] >= (RHY_STORE_BYTES >> 8))
            rhythm_end[i] = (RHY_STORE_BYTES >> 8) - 1;
    }

    // Payload lands at store offset 0; cap it at the drum region so an
    // oversized pack can never bleed into the drive-noise half.
    uint32_t payload_bytes = total - payload;
    if (payload_bytes > RHY_STORE_BYTES)
        payload_bytes = RHY_STORE_BYTES;

    // Stream the payload into the store. The BRAM window is 1 KB but the low
    // 512 bytes are the disk sector buffer and word 128 up is the settings
    // blob, so chunks stay inside the first 128 words.
    opna_mgmt_write(OMGMT_RHYADDR, 0);
    for (uint32_t off = 0; off < payload_bytes; off += SECTOR_BYTES) {
        uint32_t n = payload_bytes - off;
        if (n > SECTOR_BYTES)
            n = SECTOR_BYTES;
        if (!tds_transfer(RHYTHM_SLOT_ID, payload + off, FDD_TDS_READ, n))
            return 0;
        *FDD_BRAM_ADDR = 0;
        for (uint32_t w_i = 0; w_i < (n + 3) / 4; w_i++) {
            uint32_t w = *FDD_BRAM_RDATA;
            for (uint32_t b = 0; b < 4 && w_i * 4 + b < n; b++)
                opna_mgmt_write(OMGMT_RHYDATA, (w >> (b * 8)) & 0xFF);
        }
    }

    for (uint32_t ch = 0; ch < 6; ch++)
        inject_pair(ch, rhythm_start[ch], rhythm_end[ch]);
    return 1;
}

// --------------------------- per-voice WAV path -----------------------------
//
// Voices are processed strictly in channel order, at most one 512-byte chunk
// of source data per call, so the service loop keeps its latency. The state
// below is what survives between calls.

static uint32_t wav_voice;     // channel being attempted
static uint32_t wav_cursor;    // next free store byte (always 256-aligned)
static uint8_t  wav_done[6];   // channel resolved (loaded, skipped, failed)

// The start/end each voice was last programmed with, in 256-byte units --
// drive_sound.c restores these after borrowing a channel for a mechanism
// sample. A channel with no kit voice reads {0,0}, which plays silence.
uint16_t rhythm_start[6], rhythm_end[6];

// In-flight voice state.
static adpcm_enc wav_enc;
static uint32_t  wav_slot;
static uint32_t  wav_pos;      // next source byte offset inside the WAV
static uint32_t  wav_left;     // source bytes left in the data chunk
static uint32_t  wav_written;  // store bytes emitted for this voice
static uint16_t  wav_ch;
static uint16_t  wav_bits;
static uint8_t   wav_open;     // a voice stream is in progress
static uint8_t   wav_failed;

// Reads `n` bytes of slot data into the BRAM window and returns the word
// count the caller may consume (n rounded up to whole words).
static uint32_t wav_read(uint32_t slot, uint32_t off, uint32_t n)
{
    if (!tds_transfer(slot, off, FDD_TDS_READ, n))
        return 0;
    *FDD_BRAM_ADDR = 0;
    return (n + 3) / 4;
}

// Walk the RIFF chunk list for fmt + data; returns 0 on success.
static int wav_probe(uint32_t slot, uint32_t *data_off, uint32_t *data_len,
                     uint32_t *rate)
{
    if (!wav_read(slot, 0, 12))
        return -1;
    if (*FDD_BRAM_RDATA != RIFF_RIFF)
        return -1;
    *FDD_BRAM_ADDR = 2;         // word address: bytes 8-11 hold 'WAVE'
    if (*FDD_BRAM_RDATA != RIFF_WAVE)
        return -1;

    uint32_t off = 12, end = slot_bytes(slot);
    int got_fmt = 0;
    while (off + 8 <= end && off < 4096) {
        if (!wav_read(slot, off, 8))
            return -1;
        uint32_t id = *FDD_BRAM_RDATA;
        uint32_t sz = *FDD_BRAM_RDATA;
        if (id == RIFF_FMT && sz >= 16) {
            if (!wav_read(slot, off + 8, 16))
                return -1;
            uint32_t w0 = *FDD_BRAM_RDATA;   // tag[15:0] | channels[31:16]
            *rate = *FDD_BRAM_RDATA;
            (void)*FDD_BRAM_RDATA;           // byte rate
            uint32_t w3 = *FDD_BRAM_RDATA;   // blockalign | bits<<16
            if ((w0 & 0xFFFF) != 1)          // integer PCM only
                return -1;
            wav_ch = (uint16_t)(w0 >> 16);
            wav_bits = (uint16_t)(w3 >> 16);
            got_fmt = 1;
        } else if (id == RIFF_DATA) {
            *data_off = off + 8;
            *data_len = (sz <= end - off - 8) ? sz : end - off - 8;
            return got_fmt ? 0 : -1;
        }
        off += 8 + sz + (sz & 1);            // RIFF chunks are word-padded
    }
    return -1;
}

// Emit encoded bytes to the store, respecting both the store size and the
// current write cursor.
static void wav_emit_bytes(void)
{
    for (uint32_t i = 0; i < wav_enc.out_n; i++) {
        if (wav_cursor + wav_written < RHY_STORE_BYTES) {
            opna_mgmt_write(OMGMT_RHYDATA, wav_enc.out[i]);
            wav_written++;
        }
    }
}

static int wav_step(void)
{
    while (wav_voice < 6 && wav_done[wav_voice])
        wav_voice++;
    if (wav_voice >= 6)
        return 1;

    if (!wav_open) {
        wav_slot = RHY_WAV_SLOT_BASE + wav_voice;
        uint32_t rate = 0, data_off = 0, data_len = 0;
        if (!slot_bytes(wav_slot) ||
            wav_probe(wav_slot, &data_off, &data_len, &rate) ||
            (wav_ch != 1 && wav_ch != 2) ||
            (wav_bits != 16 && wav_bits != 8) ||
            rate < 4000 || rate > 192000 || data_len == 0) {
            wav_done[wav_voice] = 1;         // unbound or unusable: silent
            wav_voice++;
            return 0;
        }
        adpcm_enc_init(&wav_enc, rate);
        opna_mgmt_write(OMGMT_RHYADDR, wav_cursor);
        wav_pos = data_off;
        // Whole frames only: a tail shorter than a frame is dropped here so
        // the chunk loop below never hits a zero-length iteration. A frame
        // is 1, 2 or 4 bytes (the probe above rejects any other channel/bit
        // mix), so a mask stands in for % -- the softcore has no divider.
        wav_left = data_len & ~(((uint32_t)wav_ch *
                                 (wav_bits == 16 ? 2u : 1u)) - 1u);
        wav_written = 0;
        wav_failed = 0;
        wav_open = 1;
    }

    // A file longer than the store's remaining room is truncated at the wall;
    // stop pulling source bytes once no more output can land.
    if (wav_cursor + wav_written >= RHY_STORE_BYTES)
        wav_left = 0;

    // Re-arm the auto-increment every call: drive_sound.c writes its own
    // region through the same address register between calls, so the
    // continuation address has to be re-latched rather than assumed.
    opna_mgmt_write(OMGMT_RHYADDR, wav_cursor + wav_written);

    // One 512-byte source chunk per call.
    uint32_t n = wav_left > SECTOR_BYTES ? SECTOR_BYTES : wav_left;
    uint32_t frame = (uint32_t)wav_ch * (wav_bits == 16 ? 2u : 1u);
    n -= n & (frame - 1);
    if (n && !wav_read(wav_slot, wav_pos, n)) {
        wav_failed = 1;
    } else if (n) {
        wav_pos += n;
        wav_left -= n;
        uint32_t words = (n + 3) / 4;
        for (uint32_t wi = 0; wi < words; wi++) {
            uint32_t w = *FDD_BRAM_RDATA;
            for (uint32_t b = 0; b < 4; b++) {
                uint32_t byte_i = wi * 4 + b;
                if ((byte_i & (frame - 1)) || byte_i >= n)
                    continue;               // keep only frame-leading bytes
                int32_t s;
                // Stereo pairs average with a shift: >>1 floors exactly like
                // the Python packer's //2, where /2 truncates -- and the
                // softcore has no divider for it anyway.
                if (wav_bits == 16) {
                    s = (int16_t)((w >> (b * 8)) & 0xFFFF);
                    if (wav_ch == 2)
                        s = (s + (int16_t)((w >> (b * 8 + 16)) & 0xFFFF)) >> 1;
                } else {
                    s = (int32_t)((w >> (b * 8)) & 0xFF);
                    if (wav_ch == 2)
                        s = (s + (int32_t)((w >> (b * 8 + 8)) & 0xFF)) >> 1;
                    s = (s - 128) << 8;
                }
                if (adpcm_enc_push(&wav_enc, (int16_t)s))
                    wav_emit_bytes();
            }
        }
    }

    if (wav_failed || wav_left == 0) {
        while (adpcm_enc_flush(&wav_enc))
            wav_emit_bytes();
        if (!wav_failed && wav_written) {
            uint32_t start256 = wav_cursor >> 8;
            uint32_t end256 = (wav_cursor + wav_written - 1) >> 8;
            inject_pair(wav_voice, start256, end256);
            rhythm_start[wav_voice] = start256;
            rhythm_end[wav_voice]   = end256;
            wav_cursor += wav_written;
        }
        wav_done[wav_voice] = 1;
        wav_open = 0;
        wav_voice++;
    }
    return 0;
}

// Returns 1 once every bound source is resolved; 0 while work remains --
// the caller retries cheaply.
int rhythm_load(void)
{
    // Slim builds have no store and no drvA; OMGMT_CAPS bit0 tells us.
    if (!(opna_mgmt_read(OMGMT_CAPS) & 1))
        return 0;

    // WAV mode wins when any per-voice slot is bound.
    static uint32_t mode;
    if (!mode) {
        for (uint32_t v = 0; v < 6; v++)
            if (slot_bytes(RHY_WAV_SLOT_BASE + v))
                mode = 2;
        if (!mode)
            mode = slot_bytes(RHYTHM_SLOT_ID) ? 1 : 0;
        if (!mode)
            return 0;
    }
    return mode == 1 ? bin_load() : wav_step();
}
