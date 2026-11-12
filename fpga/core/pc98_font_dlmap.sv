//
// pc98_font_dlmap -- which data_loader writes land in pc98_font_ank, and where.
//
// data.json puts font.rom at bridge 0x10100000. The ANK BRAM keeps the file's
// two ANK sets (np21w font/fontv98.c):
//
//   file 0x0000-0x07FF  8x8 ANK, 256 glyphs     -> words 0x800-0xBFF
//   file 0x0800-0x17FF  8x16 ANK, 256 glyphs    -> words 0x000-0x7FF
//
// so the window is dl_addr 0x100000-0x1017FF, sixteen bits per transfer.
//
// The 8x16 word is file byte offset / 2 - 0x400, and file offset 0x1000-0x17FF
// (codes 0x80-0xFF: half-width katakana and the graphic set) needs address
// bit 12 for that. The original 11-bit form, dl_addr[11:1] - 11'h400, dropped
// bit 12 and only worked because the subtraction wrapped modulo 2048; widening
// it to twelve bits for the 8x8 bank kept the [11:1] slice, so codes 0x80-0xFF
// landed at words 0xC00-0xFFF -- past the end of the store -- and never
// reached the screen. Kept in its own module so a bench can drive it with the
// real file layout.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_font_dlmap (
    input  wire        dl_wr,
    input  wire [27:0] dl_addr,
    output wire        hit,
    output wire [11:0] word          // pc98_font_ank wr_addr
);

    assign hit  = dl_wr && (dl_addr[27:16] == 12'h010)
                        && (dl_addr[15:0] <  16'h1800);
    assign word = (dl_addr[15:0] >= 16'h0800)
                ? (dl_addr[12:1] - 12'h400)              // 8x16 bank
                : ({1'b0, dl_addr[11:1]} + 12'h800);     // 8x8 bank

endmodule

`default_nettype wire
