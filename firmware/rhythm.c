// OPNA rhythm store -- user-supplied WAV kit or nothing.
//
// The PC-9801-86's rhythm section is six ADPCM-A voices against a fixed ROM.
// This core does not ship that ROM: the sample bytes are a Yamaha dump, and
// the licensing call (2026-11-16) was to keep them out of the repo and the
// bitstream. The store powers up empty, so with no WAV dataslot bound a
// program that keys rhythm voices gets silence -- the FM and SSG sections
// are unaffected.
//
// The one path that fills the store is the per-voice WAV dataslots (ids
// 14-19, "Rhythm BD" ... "RIM"): each bound slot's file is parsed (RIFF,
// 8/16-bit PCM, mono/stereo, any sane rate), resampled to the ~18.5 kHz
// ADPCM-A rate and encoded on the fly by adpcma_enc.c into the store, and
// the voice gets its own start/end pair. Unbound voices stay at their reset
// pair {0,0}, which plays silence. The stream runs at firmware start (the
// normal load timing): its card reads are audible as quiet ticks during
// boot, the price of streaming a user kit off the card.
//
// Slim builds (capability flag 0) have no store at all and report done
// immediately -- no retry loop, silent boot. The rhythm.bin container path
// (mode 1) is gone for good: container, packer (scripts/rhythm_pack.py)
// and dataslot (id 13) were removed; if none of slots 14-19 is bound the
// load is terminal, not retried.

#include "softcpu_regs.h"
#include "adpcma_enc.h"

// The drum kit owns pc98_opna's whole 32 KB rhythm store (RHY_BYTES).
#define RHY_STORE_BYTES 32768u

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
            wav_done[wav_voice] = 1;         // unbound or unusable: silence
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

// The work starts on the FIRST SERVICE-LOOP call, not the boot call: the
// boot call happens before scsi_init(), and an OPNA mg read that early
// destabilized the hdd re-bind bench (tb_softcpu_hdd section C -- the
// re-bind edge missed its window). One no-op boot pass costs a few loop
// iterations, far below anything audible, so "load at firmware start"
// keeps its meaning: the stream begins right after the guest is released,
// long before any music. A load in progress is simply one chunk of real
// work per call.

// Returns 1 once the kit is in place and every bound WAV voice is resolved;
// 0 while work remains -- the caller retries cheaply.
int rhythm_load(void)
{
    // The boot call (before scsi_init) must touch no bus: just arm the
    // real start and let the service loop's first call do the work.
    static uint8_t booted;
    if (!booted) {
        booted = 1;
        return 0;
    }

    // Slim builds have no store and no drvA; OMGMT_CAPS bit0 tells us. There
    // is nothing to wait for in that case -- done, terminal, no retries.
    if (!(opna_mgmt_read(OMGMT_CAPS) & 1))
        return 1;

    // One probe decides whether a kit exists at all; it is not repeated
    // later, matching the old bind-at-boot semantics.
    if (!wav_active) {
        for (uint32_t v = 0; v < 6; v++)
            if (slot_bytes(RHY_WAV_SLOT_BASE + v)) {
                wav_active = 1;
                break;
            }
        if (!wav_active)
            return 1;               // no kit bound: rhythm stays silent
    }

    return wav_step();
}
