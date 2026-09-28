// OPNA rhythm store loader -- fills pc98_opna's ADPCM-A sample store at boot.
//
// The PC-9801-86's rhythm section is six ADPCM-A voices against a fixed ROM.
// This core keeps that sample data in a small firmware-filled store
// (pc98_opna.sv's rhy_mem): the guest's 0x10/0x11/0x18-0x1D writes already
// drive the real jt12 ADPCM-A engine, so what the guest can never reach --
// the sample bytes and the YM2610-style start/end pairs -- arrives here
// through the management window instead.
//
// The bytes come from the deferload "Rhythm PCM" dataslot (rhythm.bin on the
// card), produced by scripts/rhythm_pack.py from the six 2608_*.wav files:
//
//   word 0    u32 magic 'RYA1'
//   word 1    u32 payload offset in the file (the voice table sits at +8)
//   word 2..7 six u16 pairs packed little-endian: voice i = {start256,
//             end256}, already in the 256-byte units jt10_adpcm_cnt works in
//   payload   ADPCM-A nibbles, two samples per byte, high nibble first,
//             each voice 256-byte aligned
//
// Nothing is required to be present: no dataslot, a slim-OPNA build (the
// capability flag reads 0) or a bad magic all just leave the store empty,
// and rhythm key-on writes then decode silence -- the same as before.

#include "softcpu_regs.h"

#define RHYTHM_MAGIC 0x31415952u // 'RYA1' little-endian
#define RHYTHM_HDR_WORDS 8

static void opna_mgmt_write(uint32_t reg, uint32_t data)
{
    *FDD_MGMT_ADDR = OPNA_TARGET | (reg & 0xF);
    *FDD_MGMT_WDATA = data & 0xFFFF;
    *FDD_MGMT_TRIG = FDD_MGMT_WR;
}

static uint32_t opna_mgmt_read(uint32_t reg)
{
    *FDD_MGMT_ADDR = OPNA_TARGET | (reg & 0xF);
    *FDD_MGMT_TRIG = FDD_MGMT_RD;
    return *FDD_MGMT_RDATA & 0xFFFF;
}

// Returns 1 once the store is loaded; 0 while the slot is absent, still
// unbound, or the build is slim -- the caller retries cheaply.
int rhythm_load(void)
{
    // Slim builds have no store and no drvA; OMGMT_CAPS bit0 tells us.
    if (!(opna_mgmt_read(OMGMT_CAPS) & 1))
        return 0;

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
    uint16_t start[6], end[6];
    for (uint32_t i = 0; i < 6; i++) {
        uint32_t w = *FDD_BRAM_RDATA;
        start[i] = w & 0xFFFF;
        end[i]   = w >> 16;
    }

    uint32_t payload_bytes = total - payload;

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

    // Start/end pairs on jt12 part 1: start = regs 0x10/0x18 + ch (low/high
    // byte of the 12-bit 256-unit address), end = regs 0x20/0x28 + ch. Each
    // injection is two bus beats; rtr_busy (OMGMT_BUSY) clears when it lands.
    for (uint32_t ch = 0; ch < 6; ch++) {
        uint32_t pair[4] = {
            (0x10u + ch) << 8 | (start[ch] & 0xFF),
            (0x18u + ch) << 8 | ((start[ch] >> 8) & 0xF),
            (0x20u + ch) << 8 | (end[ch] & 0xFF),
            (0x28u + ch) << 8 | ((end[ch] >> 8) & 0xF),
        };
        for (uint32_t i = 0; i < 4; i++) {
            uint32_t to = DISK_SPIN_LIMIT;
            while ((opna_mgmt_read(OMGMT_BUSY) & 1) && --to)
                ;
            opna_mgmt_write(OMGMT_INJ_P1, pair[i]);
        }
    }
    return 1;
}
