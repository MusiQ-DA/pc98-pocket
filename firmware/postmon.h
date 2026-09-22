#ifndef POSTMON_H
#define POSTMON_H

// Guest POST-code overlay. The BIOS reports progress on I/O port 0x80;
// post_monitor.sv latches it and this puts it on screen, so a hardware run says
// how far the BIOS got instead of leaving it to be inferred from boot sounds.
// See docs/HANDOVER.md 1.5 for the POST map of the shipped image.
//
// Call from the service loop. Cheap: it redraws only when the code changes.
void post_mon_tick(void);

// Show or hide the overlay. Bound to a button through the settings menu
// (BTNFN_POSTMON), because the panel covers the top of the guest's screen and
// there was no way to look underneath it without rebuilding the firmware.
//
// The strip starts SHOWN: it is a diagnostic build's whole point, and a build
// that came up blank would read as the monitor being broken.
void postmon_toggle(void);

// Force the strip shown: the button binding uses this when it closes an open
// overlay, where a blind toggle could land on hidden.
void postmon_show(void);

// Capture the guest ROM bytes the panel shows.
//
// Must be called with the guest still held: the peek shares CHIPSET's
// external-access port with the guest, and taking the bus while the 8088 runs
// disturbs the very boot this panel exists to watch. Called once from main()
// before the guest is released, the read happens in the conditions the master
// was built for.
//
// What the peek returns is the image in the MAIN bank -- what the loader wrote
// at that guest address. That is a property of the RTL, not of the call site:
// RAM.sv overlays the ITF shadow on F8000-FFFFF for the guest's bank bit, and
// the master's accesses are routed around the overlay precisely because this
// compare is against the BIOS image (core_top's tandy_bios_flag). Before that,
// with PC98_BOOT_ITF powering up in the ITF bank, the peek read the ITF copy
// at physical 1FD800 -- zero padding past the ITF's code -- and the panel read
// BAD 0EC: all 256 bytes zero against a table that itself holds 20 zero bytes,
// 236 mismatches, GOT all 00. Not an empty ROM and not lost arbitration: the
// wrong bank of a working one.
void postmon_capture_rom(void);

#endif
