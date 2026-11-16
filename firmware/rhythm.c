// OPNA rhythm store -- the samples are baked into the bitstream.
//
// The PC-9801-86's rhythm section is six ADPCM-A voices against a fixed ROM,
// and the real YM2608 carries that ROM inside the chip. This core now does
// the same: pc98_opna.sv preloads its 32 KB store (rhy_mem) from
// fpga/core/rhy_rom.hex at synthesis -- the payload of the retired card-side
// rhythm.bin -- so there is nothing to stream and nothing to wait for. The
// old deferred load (rhythm.bin plus the per-voice 2608_*.wav dataslots,
// held back until the guest's first board write) is gone with it: its
// data-slot traffic ticked the platform's analog audio chain mid-music,
// which is what crackled over FM playback.
//
// What the guest can never program remains this file's one job: the six
// YM2610-style start/end pairs that match the baked layout, injected once
// at boot through the management window. The pairs are in 256-byte units,
// copied from the 'RYA1' header they used to be parsed out of.

#include "softcpu_regs.h"

// Voice i = {start256, end256}, inclusive end, against rhy_rom.hex's
// sequential six-voice packing.
static const uint16_t rhy_start[6] = { 0x00, 0x03, 0x06, 0x1e, 0x20, 0x26 };
static const uint16_t rhy_end[6]   = { 0x02, 0x05, 0x1d, 0x1f, 0x25, 0x26 };

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

// The store is in the image and the pairs are constants, so this resolves on
// its first call and returns 1 forever after; the main loop's retry never
// fires. Slim builds (no store, no drvA) have nothing to inject: CAPS bit0
// says so, and done is still done.
int rhythm_load(void)
{
    if (!(opna_mgmt_read(OMGMT_CAPS) & 1))
        return 1;
    for (uint32_t ch = 0; ch < 6; ch++)
        inject_pair(ch, rhy_start[ch], rhy_end[ch]);
    return 1;
}
