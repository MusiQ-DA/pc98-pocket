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

// Capture the guest ROM bytes the panel shows.
//
// Must be called with the guest still held. The peek goes through the
// self-test master, which shares CHIPSET's external-access port with the guest;
// with the 8088 running it loses the arbitration and returns zeros, which reads
// as an empty ROM and is not. Called once from main() before the guest is
// released, the read happens in the conditions the master was built for.
void postmon_capture_rom(void);

#endif
