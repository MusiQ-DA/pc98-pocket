#ifndef SDRAMTEST_H
#define SDRAMTEST_H

#include <stdint.h>

// In-core SDRAM self-test. See docs/P0_SELFTEST_SPEC.md.
//
// sdram_mp does not boot the board. Every logical hypothesis is spent and all
// simulation is green; the only thing hardware has told us is a POST beep
// count (three = base 64 KB RAM failure). This walks guest SDRAM from the
// softcore while the 8088 is held in reset and puts the first mismatching
// address on the OSD, so a hardware run reports where it broke instead of
// only that it broke.
//
// Call with the guest still held. Returns once the result is on screen; the
// caller decides whether to release the guest.
void sdram_selftest_run(void);

// Read one guest byte through the self-test master.
//
// The ROM the guest actually executes is the only thing the panel could not
// show. RD0 covers sixteen bytes at FFFF0 and nothing else, so a fault that
// spares the reset vector and corrupts the rest reads as "the ITF started and
// then went somewhere odd" -- which is exactly what happened. This makes any
// guest address readable from the firmware, so checking the ROM against the
// file costs a firmware copy instead of a Quartus compile.
uint8_t sdram_peek(uint32_t addr);

#endif
