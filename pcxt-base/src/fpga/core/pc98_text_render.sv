//
// pc98_text_render -- the 80x25 text plane, 8x16 cells on 640x400.
//
// Attribute byte, from np2 vram/maketext.h:
//
//     bit 0  0x01  ~secret   (0 = the cell is not drawn)
//     bit 1  0x02  blink
//     bit 2  0x04  reverse
//     bit 3  0x08  underline
//     bit 4  0x10  vertical line / simple graphics
//     bits 7:5     colour, and the order is G R B, not R G B
//
// The colour order is the kind of thing that produces a picture which looks
// right until it does not, so it is spelled out here and checked in the bench.
//
// KANJI IS NOT DRAWN YET. A cell whose character high byte is non-zero is a
// kanji, occupying this cell and the next, and its glyph lives in the 284 KB of
// FONT.ROM that has to come from SDRAM (GOAL.md R2). Until that path exists
// this module marks such cells instead of rendering the low byte through the
// ANK font, because ANK-ing a kanji code produces plausible-looking letters --
// a screen that looks like it works and is silently wrong. `kanji_seen` is
// brought out so the fact is measurable rather than a matter of squinting.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_text_render (
    input  wire        clk,
    input  wire        pix_ce,          // one pixel per assertion
    input  wire [9:0]  hcount,          // pixel within the line
    input  wire [9:0]  vcount,          // line within the frame
    input  wire        blink_on,        // blink phase, ~2 Hz

    // TVRAM video port (one cycle of latency).
    output wire [11:0] tv_cell,
    input  wire  [7:0] tv_char_lo,
    input  wire  [7:0] tv_char_hi,
    input  wire  [7:0] tv_attr,

    // Glyph port (one cycle of latency). font_cell says WHICH cell is being
    // fetched, which is the one ahead of the one being drawn -- the row buffer
    // is indexed by it, and addressing that buffer with the current column
    // instead would shift the whole line by one cell.
    output wire  [6:0] font_cell,
    output wire  [7:0] font_code,
    output wire  [3:0] font_line,
    input  wire  [7:0] font_row,

    output logic [2:0] grb,             // G,R,B as the attribute orders them
    output logic       pixel,           // this pixel is lit
    output logic       kanji_seen       // sticky: a kanji cell was encountered
);

    wire visible = (hcount < 10'd640) && (vcount < 10'd400);

    wire [6:0] col  = hcount[9:3];
    wire [4:0] row  = vcount[8:4];
    wire [3:0] line = vcount[3:0];
    wire [2:0] dot  = hcount[2:0];

    // row * 80, as a shift pair rather than a multiplier.
    wire [11:0] rowbase = {1'b0, row, 6'd0} + {3'b000, row, 4'd0};   // row*64 + row*16
    wire [6:0]  next_col = (col == 7'd79) ? 7'd0 : col + 7'd1;
    wire [11:0] next_cell = rowbase + {5'd0, next_col};

    assign tv_cell = next_cell;

    // Latched at the point the TVRAM answer is valid, and used to ask the font.
    logic [7:0] q_char_lo, q_char_hi, q_attr;
    assign font_code = q_char_lo;
    assign font_line = line;
    assign font_cell = next_col;

    // The glyph and attribute in use for the cell being shifted out.
    logic [7:0] cur_row, cur_attr;
    logic       cur_kanji;
    logic [7:0] nxt_row, nxt_attr;
    logic       nxt_kanji;

    always_ff @(posedge clk) begin
        if (pix_ce) begin
            case (dot)
                3'd1: begin
                    q_char_lo <= tv_char_lo;
                    q_char_hi <= tv_char_hi;
                    q_attr    <= tv_attr;
                end
                3'd3: begin
                    nxt_row   <= font_row;
                    nxt_attr  <= q_attr;
                    nxt_kanji <= (q_char_hi != 8'h00);
                end
                3'd7: begin
                    cur_row   <= nxt_row;
                    cur_attr  <= nxt_attr;
                    cur_kanji <= nxt_kanji;
                end
                default: ;
            endcase
        end
    end

    // Sticky, so one kanji anywhere on the screen is visible in a register
    // rather than only to the eye.
    always_ff @(posedge clk)
        if (cur_kanji) kanji_seen <= 1'b1;

    wire [2:0] shift = ~dot;             // MSB is the leftmost pixel
    wire       glyph = cur_row[shift];

    wire secret    = ~cur_attr[0];
    wire blink     =  cur_attr[1];
    wire reverse   =  cur_attr[2];
    wire underline =  cur_attr[3];
    wire vertline  =  cur_attr[4];

    // Underline is the bottom line of the cell; the vertical line sits at the
    // left edge.
    wire deco = (underline && (line == 4'd15)) || (vertline && (dot == 3'd0));

    always_comb begin
        logic lit;
        lit = glyph | deco;
        if (secret)                lit = 1'b0;
        else if (blink & ~blink_on) lit = 1'b0;
        if (reverse)               lit = ~lit;

        // Kanji is drawn from the font now: the row buffer fetches both halves
        // of a pair and hands over the bytes, so there is nothing here to
        // special-case. cur_kanji stays only to drive kanji_seen, which says
        // whether the guest is using kanji at all.

        pixel = visible & lit;
        grb   = cur_attr[7:5];
    end

endmodule

`default_nettype wire
