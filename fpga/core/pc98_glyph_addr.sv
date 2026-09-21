//
// pc98_glyph_addr -- where a cell's glyph lives inside FONT.ROM.
//
// Derived from np2 and cross-checked two ways, because a wrong formula here
// draws a different real character rather than obvious rubbish.
//
// FONT.ROM's kanji region, from font/fontv98.c's v98knjcpy:
//
//     p = src + 0x1800 + (0x60 * 32 * (i - 1));     // i = ku, 1-based
//     for (j = 0x20; j < 0x80; j++) {               // j = ten
//         ... 16 bytes to the left half, then 16 to the right ...
//     }
//
// so 0x60 * 32 = 0xC00 bytes per ku, 32 per ten, left half first. That gives
//
//     0x1800 + (ku - 1) * 0xC00 + (ten - 0x20) * 0x20 + half * 0x10 + line
//
// Which byte of the cell is ku and which is ten comes from the renderer side.
// vram/maketext.c takes the cell as a 16-bit word and computes
//
//     bitmap[x] = (kc & 0x7f7f) << 4;               // left half
//     bitmap[x] = lastbitp + 0x800;                 // right half
//
// against an internal layout that v98knjcpy fills at
//
//     0x20000 + (ku << 4) + (ten - 0x20) * 0x1000
//
// Those agree only if the LOW byte is ku and the HIGH byte is ten: the
// (ku << 4) term matches ((kc & 0x7f) << 4), and (ten - 0x20) * 0x1000 matches
// (((kc >> 8) & 0x7f) << 12) with the 0x20 << 12 absorbed by the 0x20000 base.
//
// ANK is simpler: the 8x16 set is the contiguous 0x0800-0x17FF, so
//
//     0x0800 + code * 0x10 + line
//
// Whether a cell is kanji at all is the high byte masked with the GDC's bitac,
// which is 0x00 or 0xFF by mode -- so a machine in the wrong mode reads every
// cell as ANK, and that is the GDC's decision to make, not this module's.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_glyph_addr (
    input  wire  [7:0] char_lo,     // ku for kanji, character code for ANK
    input  wire  [7:0] char_hi,     // ten for kanji
    input  wire  [7:0] bitac,       // GDC mode mask: 00 forces ANK
    input  wire        right_half,  // second cell of a kanji pair
    input  wire  [3:0] line,        // scanline within the cell

    output wire        is_kanji,
    output wire [19:0] addr         // byte offset into FONT.ROM
);

    assign is_kanji = |(char_hi & bitac);

    wire [6:0] ku  = char_lo[6:0];
    wire [6:0] ten = char_hi[6:0];

    // (ku - 1) * 0xC00 = (ku - 1) * 0x800 + (ku - 1) * 0x400
    wire [6:0]  kum1  = ku - 7'd1;
    wire [19:0] ku_off  = {2'd0, kum1, 11'd0} + {3'd0, kum1, 10'd0};
    wire [19:0] ten_off = {8'd0, (ten - 7'h20), 5'd0};

    wire [19:0] kanji_addr = 20'h01800 + ku_off + ten_off
                           + (right_half ? 20'h10 : 20'h0) + {16'd0, line};
    wire [19:0] ank_addr   = 20'h00800 + {8'd0, char_lo, 4'd0} + {16'd0, line};

    assign addr = is_kanji ? kanji_addr : ank_addr;

endmodule

`default_nettype wire
