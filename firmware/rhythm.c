// OPNA rhythm store -- instant baked kit, optional per-voice WAV override.
//
// The PC-9801-86's rhythm section is six ADPCM-A voices against a fixed ROM.
// This core keeps that sample data in pc98_opna.sv's rhy_mem, and as of the
// bake commit that store powers up already holding the YM2608's drum kit
// ($readmemh rhy_rom.hex -- see the git history for where those bytes came
// from and the licensing conversation around them). The board's pairs are
// injected below on the very first call, so rhythm sounds from power-on with
// no card traffic at all -- which also removed the deferred load whose
// data-slot reads used to tick the platform's audio chain.
//
// One override path remains, kept for licensing reasons: if any of the six
// per-voice WAV dataslots (ids 14-19, "Rhythm BD" ... "RIM") is bound, the
// bound voices are re-packed from user-supplied PCM. Each bound slot's file
// is parsed (RIFF, 8/16-bit PCM, mono/stereo, any sane rate), resampled to
// the ~18.5 kHz ADPCM-A rate and encoded on the fly by adpcma_enc.c into the
// store, overwriting the baked voice with its own start/end pair. Unbound
// voices keep the baked sample. The stream still waits for CAPS bit1
// (gw_seen -- the guest's first data-port write to the board): its card
// reads are audible, so they are parked under the program's own sound
// instead of a silent POST screen, and a program that only plays FM never
// pays for them.
//
// Slim builds (capability flag 0) have no store at all: the kit inject is
// skipped and this reports done immediately -- no retry loop, silent boot.
//
// The rhythm.bin container path (mode 1) is gone: the container, its packer
// (scripts/rhythm_pack.py) and its dataslot (id 13) were removed with the
// bake. WAV mode still packs bound voices sequentially from store offset 0,
// exactly as before; an unbound voice's baked bytes simply sit untouched.

#include "softcpu_regs.h"
#include "adpcma_enc.h"

// The drum kit owns pc98_opna's whole 32 KB rhythm store (RHY_BYTES).
#define RHY_STORE_BYTES 32768u

// The baked kit's layout, in the 256-byte units jt10_adpcm_cnt addresses.
// Voice order matches the original ROM: BD, SD, TOP, HH, TOM, RIM.
static const uint16_t baked_start[6] = { 0, 3, 6, 0x1e, 0x20, 0x26 };
static const uint16_t baked_end[6]   = { 2, 5, 0x1d, 0x1f, 0x25, 0x26 };

// The start/end each voice was last programmed with, in 256-byte units. A
// channel with no kit voice reads {0,0}, which plays silence.
static uint16_t rhythm_start[6], rhythm_end[6];

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

// --------------------------- per-voice WAV path -----------------------------
//
// Voices are processed strictly in channel order, at most one 512-byte chunk
// of source data per call, so the service loop keeps its latency. The state
// below is what survives between calls.

static uint32_t wav_voice;     // channel being attempted
static uint32_t wav_cursor;    // next free store byte (always 256-aligned)
static uint8_t  wav_done[6];   // channel resolved (loaded, skipped, failed)
static uint8_t  wav_active;    // a WAV voice is bound: the run is on

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
            wav_done[wav_voice] = 1;         // unbound or unusable: baked kit
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

    // Re-arm the auto-increment every call so the continuation address is
    // re-latched rather than assumed to have survived the call boundary.
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

// A retry that is still waiting for the guest's first OPNA write spaces
// itself by this much: the wait itself is one mg read, but the WAV-mode
// probe behind it is six datatable walks, and those reads are what the
// platform's audio chain hears. A load in progress is not spaced: each
// call is one chunk of real work.
#ifndef CHIPSET_HZ
#define CHIPSET_HZ 42954545u
#endif
#define RHYTHM_RETRY_CYCLES (CHIPSET_HZ / 6u / 4u)

static inline uint32_t rhythm_rdcycle(void)
{
    uint32_t c;
    __asm__ volatile("rdcycle %0" : "=r"(c));
    return c;
}

static uint32_t rhythm_retry_at;
static uint8_t  rhythm_backoff;

static int rhythm_later(void)
{
    rhythm_retry_at = rhythm_rdcycle() + RHYTHM_RETRY_CYCLES;
    rhythm_backoff = 1;
    return 0;
}

// Returns 1 once the kit is in place and every bound WAV voice is resolved;
// 0 while work remains -- the caller retries cheaply.
int rhythm_load(void)
{
    if (rhythm_backoff && (int32_t) (rhythm_rdcycle() - rhythm_retry_at) < 0)
        return 0;
    rhythm_backoff = 0;

    // Slim builds have no store and no drvA; OMGMT_CAPS bit0 tells us. There
    // is nothing to wait for in that case -- done, terminal, no retries.
    if (!(opna_mgmt_read(OMGMT_CAPS) & 1))
        return 1;

    // The baked kit: pairs land once, on the first call, from ROM contents
    // that powered up with the store. No card traffic, nothing to defer.
    static uint8_t kit_injected;
    if (!kit_injected) {
        for (uint32_t ch = 0; ch < 6; ch++) {
            rhythm_start[ch] = baked_start[ch];
            rhythm_end[ch]   = baked_end[ch];
            inject_pair(ch, baked_start[ch], baked_end[ch]);
        }
        kit_injected = 1;
    }

    // The WAV probe's data-slot traffic ticks the platform's audio chain,
    // and the boot ROMs never write 0x188-0x18F, so nothing sounds until a
    // program touches the board. CAPS bit1 (gw_seen) is that first touch:
    // hold the probe until then, and its reads land under the program's own
    // disk noise instead of a silent POST screen.
    if (!(opna_mgmt_read(OMGMT_CAPS) & 2))
        return rhythm_later();

    // One probe decides whether the override run happens at all; it is not
    // repeated later, matching the old bind-at-boot semantics.
    if (!wav_active) {
        for (uint32_t v = 0; v < 6; v++)
            if (slot_bytes(RHY_WAV_SLOT_BASE + v)) {
                wav_active = 1;
                break;
            }
        if (!wav_active)
            return 1;               // baked kit stands, no override
    }

    return wav_step();
}
