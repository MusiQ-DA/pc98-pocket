//
// golden_egc.c -- the np21w golden model's harness-facing half.
//
// WHAT THIS FILE IS. The three np21w sources under np21w/ (io/egc.c,
// mem/memegc.c, mem/memvram.c) are the reference for the EGC and GRCG. They
// expect a machine around them: mem[], the egc/grcg/gdcs/vramop globals, and
// an I/O bind table so egc_o4a0 can be reached. This file provides that
// machine -- nothing more. Everything an op stream does lands on the real
// np21w code paths; the dispatch in golden_rd8/wr8/rd16/wr16 reproduces
// i286c/cpumem.c's vacctbl (memm_vram) row-for-row.
//
// THE OPERATE NIBBLE. np21w selects the VRAM access path on
// vramop.operate & 0x0f:
//     bit0  gdcs.access   -- page 1 (port 0xA6 bit 0)
//     bit1  EGC enable    -- mode2 bit 2, and only while mode2 bit 3 arms it
//     bit2  GRCG RMW      -- GRCG modereg bit 6
//     bit3  GRCG on       -- GRCG modereg bit 7
// The harness's M op is the test-side engine select; it maps onto operate
// the way the real wiring can reach: M 2 raises the EGC bit, M 0/1 lower it,
// and the GRCG bits always follow grcg.modereg -- but see the M note in
// FORMAT.md: np21w's EGC rows (0x0a/0x0b/0x0e/0x0f) require bit 3 TOO, so an
// M 2 stream must set GM bit7 first (real software has to anyway).
//
// Address convention: every <a> in the op stream is the guest CPU address --
// 0xA8000/0xB0000/0xB8000/0xE0000 windows, 0x1A8000+ for F ops on page 1.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

#include "compiler.h"
#include "cpucore.h"
#include "pccore.h"
#include "iocore.h"
#include "memegc.h"
#include "memvram.h"
#include "vram.h"


// ---------------------------------------------------------------------------
// the machine the np21w sources expect
// ---------------------------------------------------------------------------

UINT8		mem[0x200000];
UINT8		vramupdate[0x8000];
UINT8		tramupdate[0x1000];
_VRAMOP		vramop;
_EGC		egc;
_GRCG		grcg;
_GDCS		gdcs;
SINT32		np21w_remclock;

// The np21w register decoder reaches us through its own bind call: egc_bind
// attaches egc_o4a0 to ports 0x4A0-0x4AF, which this table records verbatim.
static IOOUT	out_handlers[0x10000];

void iocore_attachout(UINT port, IOOUT func) {
	out_handlers[port & 0xffff] = func;
}


// ---------------------------------------------------------------------------
// harness state: the M op's engine select, kept off np21w's own state so the
// stream controls which charger is in the path the same way the RTL bench's
// egc_active/grcg_active inputs do.
// ---------------------------------------------------------------------------
static int	g_engine = 0;		// 0 normal, 1 GRCG, 2 EGC

// operate nibble, exactly the bits np21w's real code paths can produce:
// access from gdcs, analog always on (the bench runs the 16-colour machine),
// the GRCG field from grcg.modereg ALWAYS (modereg is wired into operate
// unconditionally on the real machine -- an "M 0"-tagged access while the
// GRCG is armed still lands on the vacctbl[0x08-0x0d] rows), and the EGC
// bit while the engine select says so. Note what that means: an M 2 stream
// without GM bit7 leaves operate's bit3 clear and np21w answers PLAIN.
static void sync_operate(void) {

	UINT	f;

	f = (1 << VOPBIT_ANALOG);
	if (gdcs.access)
		f |= (1 << VOPBIT_ACCESS);
	f |= ((grcg.modereg & 0xc0) >> (6 - VOPBIT_GRCG));
	if (g_engine == 2)
		f |= (1 << VOPBIT_EGC);
	vramop.operate = f;
}


// ---------------------------------------------------------------------------
// the access dispatch -- i286c/cpumem.c's vacctbl, row for row:
//
//   0x00-0x07  plain VRAM (bit0 picks the page) -- EGC or RMW bits alone do
//              nothing without the GRCG-on bit.
//   0x08/0x09  GRCG TDW: TCR read / tile write.
//   0x0c/0x0d  GRCG RMW: PLAIN read / read-modify-write.
//   0x0a-0x0f  EGC: memegc_* (the engine handles the page bit itself).
//
// The table only covers the graphics windows; anywhere else is plain RAM
// (np21w's cpumem vacctbl never routes e.g. 0xC0000 or 0xE8000 through
// vramop). The RTL agrees: !window -> expand=0 -> raw passthrough.
// ---------------------------------------------------------------------------
static int in_window(UINT32 a) {

	return(((a >= 0xA8000) && (a <= 0xAFFFF))
	    || ((a >= 0xB0000) && (a <= 0xBFFFF))
	    || ((a >= 0xE0000) && (a <= 0xE7FFF)));
}

static REG8 dispatch_rd8(UINT32 a) {

	if (!in_window(a))
		return(mem[a]);
	switch (vramop.operate & 0x0f) {
		case 0x08:	return(memtcr0_rd8(a));
		case 0x09:	return(memtcr1_rd8(a));
		case 0x0a: case 0x0b:
		case 0x0e: case 0x0f:
			return(memegc_rd8(a));
		case 0x0c:	return(memvram0_rd8(a));
		case 0x0d:	return(memvram1_rd8(a));
		default:
			return((vramop.operate & 1) ? memvram1_rd8(a)
						   : memvram0_rd8(a));
	}
}

static void dispatch_wr8(UINT32 a, REG8 v) {

	if (!in_window(a)) {
		mem[a] = v;
		return;
	}
	switch (vramop.operate & 0x0f) {
		case 0x08:	memtdw0_wr8(a, v); return;
		case 0x09:	memtdw1_wr8(a, v); return;
		case 0x0a: case 0x0b:
		case 0x0e: case 0x0f:
			memegc_wr8(a, v); return;
		case 0x0c:	memrmw0_wr8(a, v); return;
		case 0x0d:	memrmw1_wr8(a, v); return;
		default:
			if (vramop.operate & 1) memvram1_wr8(a, v);
			else			  memvram0_wr8(a, v);
			return;
	}
}

static REG16 dispatch_rd16(UINT32 a) {

	if (!in_window(a))
		return(LOADINTELWORD(mem + a));
	switch (vramop.operate & 0x0f) {
		case 0x08:	return(memtcr0_rd16(a));
		case 0x09:	return(memtcr1_rd16(a));
		case 0x0a: case 0x0b:
		case 0x0e: case 0x0f:
			return(memegc_rd16(a));
		case 0x0c:	return(memvram0_rd16(a));
		case 0x0d:	return(memvram1_rd16(a));
		default:
			return((vramop.operate & 1) ? memvram1_rd16(a)
						   : memvram0_rd16(a));
	}
}

static void dispatch_wr16(UINT32 a, REG16 v) {

	if (!in_window(a)) {
		STOREINTELWORD(mem + a, v);
		return;
	}
	switch (vramop.operate & 0x0f) {
		case 0x08:	memtdw0_wr16(a, v); return;
		case 0x09:	memtdw1_wr16(a, v); return;
		case 0x0a: case 0x0b:
		case 0x0e: case 0x0f:
			memegc_wr16(a, v); return;
		case 0x0c:	memrmw0_wr16(a, v); return;
		case 0x0d:	memrmw1_wr16(a, v); return;
		default:
			if (vramop.operate & 1) memvram1_wr16(a, v);
			else			  memvram0_wr16(a, v);
			return;
	}
}


// ---------------------------------------------------------------------------
// DPI-visible API -- the testbench calls one of these per op, in stream
// order. Plain C linkage is what Verilator's DPI import binds -- and this
// file needs the guard spelled out, because Verilator's make rules compile
// user .c files with g++ and the imported names are emitted unmangled.
// ---------------------------------------------------------------------------
#ifdef __cplusplus
extern "C" {
#endif

// Reset everything the harness owns: the RAM image, the EGC (np21w's own
// egc_reset), the GRCG registers, the access page, and the bind table.
void golden_reset(void) {

	ZeroMemory(mem, sizeof(mem));
	ZeroMemory(vramupdate, sizeof(vramupdate));
	ZeroMemory(tramupdate, sizeof(tramupdate));
	ZeroMemory(&vramop, sizeof(vramop));
	ZeroMemory(&grcg, sizeof(grcg));
	ZeroMemory(&gdcs, sizeof(gdcs));
	grcg.chip = 3;					// this machine's charger is the EGC one
	np21w_remclock = 0;
	g_engine = 0;
	egc_reset(NULL);
	egc_bind();
	sync_operate();
}

// M <n>: engine select for the accesses that follow.
void golden_mode(int m) {
	g_engine = m & 3;
	sync_operate();
}

// E <rg> <vv>: a byte write to EGC port 0x4A0+rg, through np21w's decoder.
// egc_o4a0 drops it itself when operate's EGC bit is clear.
void golden_egc_write(int rg, int val) {
	IOOUT	f;

	f = out_handlers[0x04a0 + (rg & 0xf)];
	if (f != NULL)
		f(0x04a0 + (rg & 0xf), (REG8)val);
}

// GM <vv>: GRCG mode register (port 0x7C). np21w io/crtc.c crtc_o7c:
// latches the byte, resets the tile counter, remaps the GRCG operate bits.
void golden_grcg_mode(int val) {
	grcg.modereg = (UINT8)val;
	grcg.counter = 0;
	sync_operate();
}

// GT <p> <vvvv>: plane p's tile register, 16 bits. On the real port every
// 0x7E write sets both tile bytes to the same value (crtc.c); the wide form
// exists so recorded streams can carry a full word -- keep the halves equal
// for hardware-faithful runs (see FORMAT.md).
void golden_grcg_tile(int p, int val) {
	grcg.tile[p & 3].w = (UINT16)val;
}

// P <v>: access page (port 0xA6 bit 0) -- gdcs.access.
void golden_access_page(int v) {
	gdcs.access = (UINT8)(v & 1);
	sync_operate();
}

int golden_rd8(int addr) {
	return(dispatch_rd8((UINT32)addr));
}

void golden_wr8(int addr, int val) {
	dispatch_wr8((UINT32)addr, (REG8)val);
}

int golden_rd16(int addr) {
	return(dispatch_rd16((UINT32)addr));
}

// egc.sft as np21w keeps it -- bit 12 (0x1000) is the direction flag the
// odd-word paths in memegc_rd16/memegc_wr16 consult for byte order.
int golden_egc_sft(void) {
	return(egc.sft);
}

// Shift-pipeline internals for divergence hunting: the write gate is
// `if (egc.mask2.x)`, and mask2 = mask & srcmask -- when the queue runs dry
// (remain hits zero mid-access) srcmask suppresses lanes.
int golden_egc_mask2(void)   { return(egc.mask2.w); }
// Trace inside the np21w shift functions (EGCT in memegc.c).
extern int np21w_egc_dbg;
void golden_egc_dbgev(int v) { np21w_egc_dbg = v; }
int golden_egc_srcmask(void) { return(egc.srcmask.w); }
int golden_egc_remain(void)  { return(egc.remain); }
int golden_egc_stack(void)   { return(egc.stack); }
int golden_egc_ope(void)     { return(egc.ope); }
// The pattern registers, one 16-bit lane each -- same layout as the
// RTL's patreg[plane].
int golden_egc_patreg(int p) { return(egc.patreg.w[p & 3]); }
int golden_egc_fgbg(void)    { return(egc.fgbg); }
// The funnel output latch (egc_src): four planes, a 16-bit lane each.
extern REG16 np21w_egc_src_plane(UINT p);
int golden_egc_src(int p)    { return(np21w_egc_src_plane((UINT)p)); }
// The in-flight queue byte head positions -- shiftpipeline internals.
int golden_egc_srcbit(void)  { return(egc.srcbit); }
int golden_egc_dstbit(void)  { return(egc.dstbit); }
int golden_egc_func(void)    { return(egc.func); }
extern int np21w_egc_inptr(void);
extern int np21w_egc_outptr(void);
extern int np21w_egc_buf(int i);
int golden_egc_inptr(void)   { return(np21w_egc_inptr()); }
int golden_egc_outptr(void)  { return(np21w_egc_outptr()); }
int golden_egc_buf(int i)    { return(np21w_egc_buf(i)); }

void golden_wr16(int addr, int val) {
	dispatch_wr16((UINT32)addr, (REG16)val);
}

// The canonical VRAM byte at a mem[] offset: page 0 at 0xA8000/0xB0000/
// 0xB8000/0xE0000, page 1 at 0x1A8000/0x1B0000/0x1B8000/0x1E0000. Used for
// the X compare and for F seed writes.
int golden_vram_byte(int addr) {

	if ((addr < 0) || (addr >= 0x200000))
		return(0);
	return(mem[addr]);
}

void golden_vram_poke(int addr, int val) {

	if ((addr < 0) || (addr >= 0x200000))
		return;
	mem[addr] = (UINT8)val;
}

// np21w's dirty bits: every graphics write ORs the plane/page flag into
// vramupdate[LOW15(addr)] -- a superset of "which offsets were touched",
// which lets the bench compare only cells either side could have written.
int golden_vramupdate(int off) {

	if ((off < 0) || (off >= 0x8000))
		return(0);
	return(vramupdate[off]);
}

#ifdef __cplusplus
}
#endif
