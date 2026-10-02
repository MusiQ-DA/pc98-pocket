//
// np21w compat shim -- vram.h, the pieces the golden engine references:
// _VRAMOP (the operate nibble that picks the memory-map row), the dirty
// bitmaps, and the MEMWAIT macros (drained into a dummy cell).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

#ifndef NP21W_SHIM_VRAM_H
#define NP21W_SHIM_VRAM_H

typedef struct {
	UINT	operate;
	UINT	tramwait;
	UINT	vramwait;
	UINT	grcgwait;
} _VRAMOP, *VRAMOP;

// operate: bit0 access page, bit1 egc enable, bit2 grcg bit6 (RMW),
//          bit3 grcg bit7 (on), bit4 analog enable.
enum {
	VOPBIT_ACCESS	= 0,
	VOPBIT_EGC	= 1,
	VOPBIT_GRCG	= 2,
	VOPBIT_ANALOG	= 4,
	VOPBIT_VGA	= 5
};

#ifdef __cplusplus
extern "C" {
#endif

extern	_VRAMOP	vramop;
extern	UINT8	tramupdate[0x1000];
extern	UINT8	vramupdate[0x8000];

#ifdef __cplusplus
}
#endif

#define	MEMWAIT_TRAM	vramop.tramwait
#define	MEMWAIT_VRAM	vramop.vramwait
#define	MEMWAIT_GRCG	vramop.grcgwait

#endif	// NP21W_SHIM_VRAM_H
