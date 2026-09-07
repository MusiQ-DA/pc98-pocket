#ifndef POSTMON_H
#define POSTMON_H

// Guest POST-code overlay. The BIOS reports progress on I/O port 0x80;
// post_monitor.sv latches it and this puts it on screen, so a hardware run says
// how far the BIOS got instead of leaving it to be inferred from boot sounds.
// See docs/HANDOVER.md 1.5 for the POST map of the shipped image.
//
// Call from the service loop. Cheap: it redraws only when the code changes.
void post_mon_tick(void);

#endif
