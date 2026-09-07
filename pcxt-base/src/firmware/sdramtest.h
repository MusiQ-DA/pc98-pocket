#ifndef SDRAMTEST_H
#define SDRAMTEST_H

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

#endif
