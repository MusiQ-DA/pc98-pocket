//
// pc98_gaiji_ram -- the user-defined character RAM behind ku 0x56/0x57.
//
// On a real PC-98 the character generator holds a RAM region for codes whose
// low byte is 0x56 or 0x57: 128 indices x 2 ku x 2 halves x 16 lines = 8 KB of
// glyphs the guest can rewrite. np21w keeps it inside its fontrom array --
// io/cgrom.c cgrom_oa9/cgrom_ia9 address it as
//
//     fontrom[((code & 0x7f7f) << 4) + lr + (line & 0x0f)]
//
// and vram/maketext.c renders a cell with the same (kc & 0x7f7f) << 4 formula,
// which is why a glyph written through the port lands on screen. Here the RAM
// stands alone because the renderer's kanji bytes come out of SDRAM, not out
// of an array this port can reach.
//
// The 13-bit index compresses np21w's offset:
//
//     {idx[6:0], ku[0], half, line[3:0]}
//
// where idx is code[15:8] (or the cell's high byte) ANDed with 0x7F, ku[0]
// picks 0x56/0x57, half is the a5-selected side (1 = right, np21w's lr=0x800)
// or the renderer's pair_second, and line is the scanline. Write and read
// paths share the formula, so what port 0xA9 (or the A4000 window) stores is
// what the row buffer fetches.
//
// Two ports, both on the chipset clock: A is the guest side (read AND write),
// B is a read port the glyph row buffer uses. An M10K pair gives true
// dual-port semantics, so a guest store mid-frame cannot disturb a fetch.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_gaiji_ram (
    input  wire        clk,

    // Port A: guest side -- 0xA9 I/O and the A4000 window.
    input  wire        a_we,
    input  wire [12:0] a_addr,
    input  wire  [7:0] a_wdata,
    output logic [7:0] a_rdata,

    // Port B: the row buffer's glyph source for gaiji cells.
    input  wire [12:0] b_addr,
    output logic [7:0] b_rdata
);

    (* ramstyle = "M10K" *) logic [7:0] ram [0:8191];

    always_ff @(posedge clk) begin
        if (a_we) ram[a_addr] <= a_wdata;
        a_rdata <= ram[a_addr];
        b_rdata <= ram[b_addr];
    end

endmodule

`default_nettype wire
