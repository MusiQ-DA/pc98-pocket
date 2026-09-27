//
// pc98_font_ank -- the 8x16 and 8x8 ANK fonts, 256 glyphs each, 6 KB.
//
// FONT.ROM is 0x46800 bytes (288,768, which matches the file exactly) and np21w's
// font/fontv98.c says what is where:
//
//   0x0000   8x8 ANK, 256 glyphs            <- sel8 reads this bank
//   0x0800   8x16 ANK, codes 0x00-0x7F      <- sel8=0 reads these two
//   0x1000   8x16 ANK, codes 0x80-0xFF
//   0x1800   kanji, 0x60 * 32 * (ku - 1) per ku, left and right halves
//            interleaved 16 bytes at a time
//
// The GDC mode1 register bit 3 picks the bank: set is the 8x16 set, clear is
// the 8x8 set with each glyph row serving two cell lines (line[3:1]), the
// hardware's vertical double -- np21w maketext.c's `fntline >>= 1`. The 8x8
// bank is what WIDTH 40's 16-dot cells are supposed to be drawn from.
// 284 KB of kanji stays on the SDRAM-resident path (GOAL.md R2).
//
// Written straight from the loader's dl_wr rather than through the guest bus:
// it is a small ROM with no handshake, and routing it through the ext port
// would put it behind the BIOS load it does not depend on.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_font_ank (
    // Load side, on the loader's clock. data_loader hands over sixteen bits at
    // a time -- the low byte belongs to the even address -- so the store is
    // sixteen bits wide and the read side picks a half. Writing one byte per
    // transfer would drop every second byte of the font.
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [11:0] wr_addr,        // word index, 0..3071
    input  wire [15:0] wr_data,

    // Render side.
    input  wire        rd_clk,
    input  wire  [7:0] code,           // character code
    input  wire  [3:0] line,           // scanline within the cell, 0..15
    input  wire        sel8,           // 1 = 8x8 bank (row = line >> 1)
    output wire  [7:0] row             // eight pixels, MSB leftmost
);

    // Words 0x000-0x7FF hold the 8x16 set (file 0x0800-0x17FF, as before) and
    // 0x800-0xBFF the 8x8 set (file 0x0000-0x07FF), so a bench that loads the
    // 8x16 bank where it always did needs no remap.
    (* ramstyle = "M10K" *) logic [15:0] glyphs [0:3071];

    always_ff @(posedge wr_clk)
        if (wr_en) glyphs[wr_addr] <= wr_data;

    // Byte address: 8x16 is code*16 + line; 8x8 is 0x1000 + code*8 + line/2.
    wire [12:0] rd_byte = sel8 ? (13'h1000 + {2'b00, code, line[3:1]})
                               : {1'b0, code, line};
    logic [15:0] rd_word;
    logic        rd_hi;

    always_ff @(posedge rd_clk) begin
        rd_word <= glyphs[rd_byte[12:1]];
        rd_hi   <= rd_byte[0];
    end

    assign row = rd_hi ? rd_word[15:8] : rd_word[7:0];

endmodule

`default_nettype wire
