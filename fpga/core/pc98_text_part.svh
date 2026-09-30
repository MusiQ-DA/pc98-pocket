//
// pc98_text_part.svh -- which PRAM partition a text row lives in.
//
// The master GDC's SCROLL PRAM is four partitions of {SAD, LEN} and the
// display walks them in order (np21w vram/maketext.c): each partition
// contributes LEN text rows, then the walk jumps to the next partition's
// SAD. A screen with one area sets partition 0 to the whole height and the
// walk never advances; a status-line split sets two.
//
// LEN means the PRAM field's low 14 bits >> 4 -- already decoded in
// pc98_gdc's part_len. A partition whose LEN is zero never ends: np21w's
// UINT countdown wraps to 0xFFFFFFFF rather than firing, so the row stays
// in that partition forever. Written as a bound check it is the same rule:
// a zero LEN compares true for every row.
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
        input logic [9:0]  len [0:3]);
    logic [9:0]  e0, e1, e2;
    logic [9:0]  r;
    e0 = len[0];
    e1 = len[0] + len[1];
    e2 = e1 + len[2];
    r  = {5'd0, row};
    if ((len[0] == 10'd0) || (r < e0)) begin
        pc98_text_part = {row, sad[0][11:0]};
    end else if ((len[1] == 10'd0) || (r < e1)) begin
        pc98_text_part = {5'(r - e0), sad[1][11:0]};
    end else if ((len[2] == 10'd0) || (r < e2)) begin
        pc98_text_part = {5'(r - e1), sad[2][11:0]};
    end else begin
        pc98_text_part = {5'(r - e2), sad[3][11:0]};
    end
endfunction
/* verilator lint_on UNUSEDSIGNAL */
