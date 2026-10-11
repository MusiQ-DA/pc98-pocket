//
// np21w compat shim -- iocore.h, reduced to the three state structs the
// golden files touch. The union/struct bodies are VERBATIM copies from
// np21w rev106: io/egc.h (EGCWORD, EGCQUAD, _EGC), io/crtc.h (PAIR16,
// _GRCG) and io/gdc.h (_GDCS). Field order is load-bearing -- the copied
// sources index into them, so do not "tidy" them.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

#ifndef NP21W_SHIM_IOCORE_H
#define NP21W_SHIM_IOCORE_H

// ---------------------------------------------------------------------------
// np21w io/egc.h
// ---------------------------------------------------------------------------
typedef union {
	UINT8	_b[2];
	UINT16	w;
} EGCWORD;

typedef union {
	UINT8	_b[4][2];
	UINT16	w[4];
	UINT32	d[2];
	UINT64	q;
} EGCQUAD;

typedef struct {
	UINT16	access;
	UINT16	fgbg;
	UINT16	ope;
	UINT16	fg;
	EGCWORD	mask;
	UINT16	bg;
	UINT16	sft;
	UINT16	leng;
	EGCQUAD	lastvram;
	EGCQUAD	patreg;
	EGCQUAD	fgc;
	EGCQUAD	bgc;

	int		func;
	UINT	remain;
	UINT	stack;
	UINT8	*inptr;
	UINT8	*outptr;
	EGCWORD	mask2;
	EGCWORD	srcmask;
	UINT8	srcbit;
	UINT8	dstbit;
	UINT8	sft8bitl;
	UINT8	sft8bitr;

	UINT	padding_b[4];
	UINT8	buf[4096/8 + 4*4];
	UINT	padding_a[4];
} _EGC, *EGC;

// ---------------------------------------------------------------------------
// np21w io/crtc.h
// ---------------------------------------------------------------------------
typedef union {
	UINT8	b[2];
	UINT16	w;
} PAIR16;

typedef struct {
	UINT32	counter;
	UINT16	mode;
	UINT8	modereg;
	UINT8	padding;
	PAIR16	tile[4];
	UINT32	gdcwithgrcg;
	UINT8	chip;
} _GRCG, *GRCG;

// ---------------------------------------------------------------------------
// np21w io/gdc.h -- the _GDCS slice; only `access` (page bit, port 0xA6) and
// `grphdisp` (dirty flags) are consumed by the golden engine.
// ---------------------------------------------------------------------------
typedef struct {
	UINT8	access;
	UINT8	disp;
	UINT8	textdisp;
	UINT8	msw_accessable;
	UINT8	grphdisp;
	UINT8	palchange;
	UINT8	mode2;
} _GDCS, *GDCS;

#ifdef __cplusplus
extern "C" {
#endif

extern	_EGC		egc;
extern	_GRCG		grcg;
extern	_GDCS		gdcs;

// np21w's I/O bind table. egc.c's egc_bind() attaches egc_o4a0 to ports
// 0x4A0-0x4AF; the shim captures the attachment so the harness can poke
// register writes through np21w's own decoder instead of duplicating it.
typedef void (IOOUTCALL *IOOUT)(UINT port, REG8 val);
void iocore_attachout(UINT port, IOOUT func);

// io/egc.c's public entry points.
void egc_reset(const NP2CFG *pConfig);
void egc_bind(void);

#ifdef __cplusplus
}
#endif

#endif	// NP21W_SHIM_IOCORE_H
