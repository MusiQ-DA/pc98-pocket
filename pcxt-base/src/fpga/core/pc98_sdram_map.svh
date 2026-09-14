//
// pc98_sdram_map.svh -- where the SDRAM answers, in one place.
//
// TWO modules have to agree on this and they decide at different moments.
// RAM.sv turns it into ram_address_select_n from the LATCHED address, after
// ALE. v30_cpu_bridge has to know it EARLIER -- at the moment it arms a byte
// cycle -- because the answer decides whether a V30 word access runs as one
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
// v30_cpu_bridge.sv ahead of RAM.sv in the file list, RAM.sv was left with
// "Can't find definition of task/function: pc98_sdram_hits".

// A function, not a macro: a macro that bit-selects its argument cannot
// parenthesise it, so it would silently depend on the caller passing a plain
// signal name. INCLUDE THIS INSIDE THE MODULE -- each one gets its own copy,
// which is what keeps Quartus happy about a function at compilation-unit
// scope.
function automatic logic pc98_sdram_hits(input logic [19:0] a);
    pc98_sdram_hits = ((a[19:16] < 4'hC)          // RAM + the GVRAM window
                    || (a[19:15] >= 5'b11101))    // E8000-FFFFF: the ROM image
                    && (a[19:15] != 5'b10100);    // not A0000-A7FFF
endfunction

