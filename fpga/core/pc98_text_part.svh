//
// pc98_text_part.svh -- which PRAM partition a text row lives in.
//
// The master GDC's SCROLL PRAM is four partitions of {SAD, LEN} and the
// display walks them in order (np21w vram/maketext.c): each partition
// contributes its LEN of lines, then the walk jumps to the next
// partition's SAD. A screen with one area sets partition 0 to the whole
// height and the walk never advances; a status-line split sets two.
//
// THE BOUNDARIES ARRIVE ALREADY IN ROWS. np21w counts LEN in emitted
// rasterlines, so the row where partition k+1 begins is
// floor((LEN[0]+..+LEN[k]) / (TEXT_LR+1)) -- pc98_gdc's part_bend does
// that divide (the rasterline count is not row-comparable on its own, and
// a boundary that lands mid-row opens the new partition AT that row --
// np21w's esi reload runs mid-row and the boundary row is its row 0).
// bend[k] here is the first row of partition k+1, 6 bits, 63 = beyond the
// deepest row: a zero LEN is absorbing in np21w (the UINT countdown wraps
// rather than firing) and arrives here as 63, which also swallows every
// later partition.
//
// Written once because two modules have to agree: pc98_text_rowbase (the
// glyph row buffer's fetch address) and pc98_text_render (the attribute
// fetch and the cursor's cell compare). The function returns
// {rel_row[4:0], sad[11:0]} -- the row's index INSIDE its partition and
// that partition's LOW12 SAD -- so each consumer adds its own pitch
// product; the callers keep the unprogrammed-GDC fallback (partition 0,
// rel = row) themselves.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// NO INCLUDE GUARD, deliberately -- see pc98_sdram_map.svh for why.

/* verilator lint_off UNUSEDSIGNAL */
function automatic logic [16:0] pc98_text_part(
        input logic [4:0]  row,
        input logic [15:0] sad [0:3],
        input logic [5:0]  bend [0:2]);
    logic [5:0] r;
    r = {1'b0, row};
    if (r < bend[0]) begin
        pc98_text_part = {row, sad[0][11:0]};
    end else if (r < bend[1]) begin
        pc98_text_part = {5'(r - bend[0]), sad[1][11:0]};
    end else if (r < bend[2]) begin
        pc98_text_part = {5'(r - bend[1]), sad[2][11:0]};
    end else begin
        pc98_text_part = {5'(r - bend[2]), sad[3][11:0]};
    end
endfunction
/* verilator lint_on UNUSEDSIGNAL */
