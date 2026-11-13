// svc.h -- cooperative yield between the main loop's services.
//
// The main loop runs fdd_poll, gdc_poll and scsi_poll in turn, and each one
// used to keep the loop until its request was finished: a 640-dot GDC line
// held a SCSI command off for 78 ms, a 16-block SCSI read held a GDC dot off
// for 70 ms. The long services now call svc_maybe_yield between their own
// natural units (a GDC dot or WDAT word, a SCSI block, a slice of an FDD
// sector), and once SVC_YIELD_CYCLES have passed since the main loop (or the
// last yield) ran the other polls, svc_yield runs them from there.
//
// One level only: a service entered from a yield runs to completion (its own
// yields return at once), so the stack holds at most two services and no
// service is ever re-entered. The caller passes its own SVC_* bit, which the
// yield skips. A yield point must sit between whole operations: nothing of
// the caller's may be half-written in a register the others share
// (FDD_MGMT_ADDR, FDD_BRAM_ADDR, the bridge RAM's words 0-127, the target
// dataslot engine) unless the caller re-latches it afterwards.
#ifndef SVC_H
#define SVC_H

#include <stdint.h>

#define SVC_FDD  1u
#define SVC_GDC  2u
#define SVC_SCSI 4u

#if defined(__riscv)
extern uint32_t svc_yield_due;
void svc_yield(uint32_t self);

static inline uint32_t svc_rdcycle(void)
{
    uint32_t c;
    __asm__ volatile("rdcycle %0" : "=r"(c));
    return c;
}

static inline void svc_maybe_yield(uint32_t self)
{
    if ((int32_t) (svc_rdcycle() - svc_yield_due) >= 0) {
        svc_yield(self);
    }
}
#else
// Host builds of a service file (sim/host/*) have no other services.
static inline void svc_maybe_yield(uint32_t self) { (void) self; }
#endif

#endif
