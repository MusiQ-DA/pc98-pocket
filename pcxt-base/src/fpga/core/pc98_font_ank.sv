//
// pc98_font_ank -- the 8x16 ANK font, 256 glyphs, 4 KB.
//
// FONT.ROM is 0x46800 bytes (288,768, which matches the file exactly) and np2's
// font/fontv98.c says what is where:
//
//   0x0000   8x8 ANK, 256 glyphs
//   0x0800   8x16 ANK, codes 0x00-0x7F      <- this module
//   0x1000   8x16 ANK, codes 0x80-0xFF      <- and this
//   0x1800   kanji, 0x60 * 32 * (ku - 1) per ku, left and right halves
//            interleaved 16 bytes at a time
//
// So the two ANK halves are contiguous: 0x0800-0x17FF is the whole 256-glyph
// 8x16 set, 4096 bytes, one M10K block. That is all a text screen needs, and
// the 284 KB of kanji can wait for the SDRAM-resident path (GOAL.md R2).
//
// Written straight from the loader's dl_wr rather than through the guest bus:
// it is a small ROM with no handshake, and routing it through the ext port
// would put it behind the BIOS load it does not depend on.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_font_ank (
    // Load side, on the loader's clock.
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [11:0] wr_addr,        // 0..4095, already offset from 0x0800
    input  wire  [7:0] wr_data,

    // Render side.
    input  wire        rd_clk,
    input  wire  [7:0] code,           // character code
    input  wire  [3:0] line,           // scanline within the cell, 0..15
    output logic [7:0] row             // eight pixels, MSB leftmost
);

    (* ramstyle = "M10K" *) logic [7:0] glyphs [0:4095];

    always_ff @(posedge wr_clk)
        if (wr_en) glyphs[wr_addr] <= wr_data;

    always_ff @(posedge rd_clk)
        row <= glyphs[{code, line}];

endmodule

`default_nettype wire
