//
// pc98_sdram_map.svh -- where the SDRAM answers, in one place.
//
// TWO modules have to agree on this and they decide at different moments.
// RAM.sv turns it into ram_address_select_n from the LATCHED address, after
// ALE. cpu_bus_bridge has to know it EARLIER -- at the moment it arms a byte
// cycle -- because the answer decides whether a word access runs as one
// cycle (the SDRAM can burst two words) or as two (everything else on this
// bus is eight bits wide and cannot).
//
// Written out twice they would drift, and the failure would be silent: a word
// cycle issued at an address the SDRAM does not serve puts one byte where two
// belong. So it is written once, here, and both include it.
//
// The map itself is PC-98's, and RAM.sv's comment is the authority on why:
// the SDRAM answers 00000-BFFFF (640 KB plus the A8000-BFFFF window the GVRAM
// probe writes through) and E8000-FFFFF (the ROM image the loader writes
// there), with A0000-A7FFF cut out because text VRAM and the CG window answer
// from elsewhere. C0000-E7FFF is deliberately empty: with SDRAM answering
// there the POST saw an expansion that does not exist.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// NO INCLUDE GUARD, deliberately. The body is a function that each module
// needs its own copy of, and a guard makes the SECOND include a no-op: with
// cpu_bus_bridge.sv ahead of RAM.sv in the file list, RAM.sv was left with
// "Can't find definition of task/function: pc98_sdram_hits".

// A function, not a macro: a macro that bit-selects its argument cannot
// parenthesise it, so it would silently depend on the caller passing a plain
// signal name. INCLUDE THIS INSIDE THE MODULE -- each one gets its own copy,
// which is what keeps Quartus happy about a function at compilation-unit
// scope.
// `analog` is the sixteen-colour mode bit (port 0x6A bit 0). It has to be an
// ARGUMENT rather than a constant because it MOVES THE MEMORY MAP: the fourth
// graphics plane lives at E0000-E7FFF and exists only in analog mode. np21w
// maps all four windows and then takes the fourth back in digital mode
// (i386c/cpumem.c, memm_vram), so three planes is CORRECT for a digital
// machine, not a gap. Opening E0000 unconditionally is the failure RAM.sv
// records: the POST swept into a phantom expansion and stopped at D0000.
// Each of these looks at only part of the address -- the window functions at
// the top bits, the plane function at the bottom -- and a full-width argument
// is what keeps the callers from having to know which. Verilator's
// UNUSEDSIGNAL on a function argument is noise here, not a finding.
/* verilator lint_off UNUSEDSIGNAL */
function automatic logic pc98_sdram_hits(input logic [19:0] a,
                                         input logic analog);
    pc98_sdram_hits = (((a[19:16] < 4'hC)         // RAM + planes B, R, G
                     || (a[19:15] >= 5'b11101))   // E8000-FFFFF: the ROM image
                     && (a[19:15] != 5'b10100))   // not A0000-A7FFF
                    || (analog && (a[19:15] == 5'b11100)); // E0000: plane E
endfunction

// The three graphics windows that always exist, plus the fourth when analog.
// A GRCG access to ANY of them touches all four planes, so the memory path
// needs to recognise the window rather than the plane.
function automatic logic pc98_gvram_hits(input logic [19:0] a,
                                         input logic analog);
    pc98_gvram_hits = (a[19:15] == 5'b10101)      // A8000-AFFFF  plane B
                   || (a[19:16] == 4'hB)          // B0000-BFFFF  planes R, G
                   || (analog && (a[19:15] == 5'b11100)); // E0000  plane E
endfunction

// Where plane p of the byte at `a` lives. Planes B/R/G are 0x8000 apart from
// A8000; plane E is not -- it is at E0000, four windows further on.
function automatic logic [19:0] pc98_gvram_plane(input logic [19:0] a,
                                                 input logic [1:0] p);
    pc98_gvram_plane = (p == 2'd3) ? {5'b11100, a[14:0]}
                                   : {5'b10101 + 5'(p), a[14:0]};
endfunction

// THE ACCESS PAGE (np21w io/gdc.c, gdc_oa6: port 0xA6 bit 0 is gdcs.access,
// and mem/memvram.c banks every plane window by it -- the window offset is
// fifteen bits of ONE 640x400 page, and bit 14 of it is lines 256-399, NOT a
// second page). Page zero is the guest-linear window above, unchanged. Page
// one has no guest address at all -- the real machine rebanks the same
// window -- so it lives behind RAM.sv's gvram_page1_flag at 0x600000, where
// the guest cannot see it and extended memory cannot reach it. The sequencer returns
// these seventeen bits (plane number and offset) and asserts the flag.
function automatic logic [16:0] pc98_gvram_plane1(input logic [19:0] a,
                                                  input logic [1:0] p);
    pc98_gvram_plane1 = {2'b00, p, a[14:0]};
endfunction

// Which of the four planes a window address selects. Written once here
// because the interleave needs it in THREE places: RAM.sv (turn a window
// address into the interleaved word), pc98_gvram_seq (the walk order and
// its own address math), and anything else that has to classify a guest
// address without going through the sequencer. Same decode as
// pc98_gvram_plane: E0000 is plane 3, A8000 plane 0, bit 15 of the window
// separates G (B8000) from R (B0000).
function automatic logic [1:0] pc98_gvram_own_plane(input logic [19:0] a);
    pc98_gvram_own_plane = (a[19:15] == 5'b11100) ? 2'd3   // E0000-E7FFF
                         : (a[19:15] == 5'b10101) ? 2'd0   // A8000-AFFFF
                         : a[15]                  ? 2'd2   // B8000-BFFFF: G
                                                  : 2'd1; // B0000-B7FFF: R
endfunction

// THE INTERLEAVE (docs/GVRAM_PLANE_INTERLEAVE.md). The four planes stop
// living in four separate 0x8000 windows and share one dense region, so a
// GRCG read-modify-write of one pixel dot reads the four planes it needs
// from CONSECUTIVE SDRAM words instead of four windows 0x8000 apart:
//
//   byte offset off (15 bits, within the plane) and plane p (B=0 R=1 G=2 E=3)
//     word = base + {off, p[1]}   -- offset doubled, plane bit 1 selects the
//                                    odd word, so:
//       even word {R[off] hi : B[off] lo}
//       odd  word {E[off] hi : G[off] lo}
//     lane = p[0]                 -- B/G take the low byte, R/E the high.
//
// One guest byte touches exactly one word on one lane, a GRCG byte access
// is one two-word read plus one masked two-word write, and a word access
// (offsets off, off+1) four consecutive words either way. The price is
// that every byte write must be masked -- the neighbour lane holds the
// partner plane's byte -- which is why the DQM path is wired up.
// Page zero lives at 0x600000 and page one at 0x610000, each 64K words
// (32 K offsets x 2 words), clear of the font bank (0x400000) and the
// 286's extended memory (0x800000-0xFFFFFF, z86_cache's port F).
function automatic logic [23:0] pc98_gvram_il(input logic pg,
                                              input logic [14:0] off,
                                              input logic [1:0] p);
    pc98_gvram_il = {7'h30, pg, off, p[1]};
endfunction
/* verilator lint_on UNUSEDSIGNAL */

