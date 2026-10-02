//
// np21w compat shim -- cpucore.h + i286c/cpumem.h, reduced to what
// mem/memegc.c and mem/memvram.c actually touch: the linear mem[] image, the
// VRAM plane bases, the access-page step, and the clock-drain macro (a dummy
// drain here -- waits are not guest-visible to this harness).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

#ifndef NP21W_SHIM_CPUCORE_H
#define NP21W_SHIM_CPUCORE_H

#ifdef __cplusplus
extern "C" {
#endif

// np21w i286c/cpumem.c: the whole machine's RAM, 2 MB. The graphics planes
// live at the VRAM_* offsets; the access page adds VRAM_STEP.
extern	UINT8	mem[0x200000];

// cpumem.h
enum {
	VRAM_STEP	= 0x100000,
	VRAM_B		= 0x0a8000,
	VRAM_R		= 0x0b0000,
	VRAM_G		= 0x0b8000,
	VRAM_E		= 0x0e0000
};

#define	VRAMADDRMASKEX(a)	((a) & (VRAM_STEP | 0x7fff))

// cpucore.h's CPU_REMCLOCK is i286core.s.remainclock; one dummy cell stands
// in for it (the MEMWAIT_* charges land here).
extern	SINT32	np21w_remclock;
#define	CPU_REMCLOCK	np21w_remclock

#ifdef __cplusplus
}
#endif

#endif	// NP21W_SHIM_CPUCORE_H
