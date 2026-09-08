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
// Kanji is drawn like anything else: the row buffer fetches both halves of a
// pair from the SDRAM-resident font and hands over bytes, so this module has no
// idea whether a cell is kanji and does not need one. Whether the guest is
// USING kanji is reported by the row buffer, which does know.
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

    // TVRAM attribute port (one cycle of latency). The character codes are the
    // row buffer's business, not this module's: it is handed glyph bytes.
    output wire [11:0] tv_cell,
    input  wire  [7:0] tv_attr,

    // Glyph port (one cycle of latency). font_cell says WHICH cell is being
    // fetched, which is the one ahead of the one being drawn -- the row buffer
    // is indexed by it, and addressing that buffer with the current column
    // instead would shift the whole line by one cell.
    output wire  [6:0] font_cell,
    output wire  [3:0] font_line,
    input  wire  [7:0] font_row,

    output logic [2:0] grb,             // G,R,B as the attribute orders them
    output logic       pixel            // this pixel is lit
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

    // Latched at the point the TVRAM answer is valid.
    logic [7:0] q_attr;
    assign font_line = line;
    assign font_cell = next_col;

    // The glyph and attribute in use for the cell being shifted out.
    logic [7:0] cur_row, cur_attr;
    logic [7:0] nxt_row, nxt_attr;

    always_ff @(posedge clk) begin
        if (pix_ce) begin
            case (dot)
                3'd1: q_attr <= tv_attr;
                3'd3: begin
                    nxt_row  <= font_row;
                    nxt_attr <= q_attr;
                end
                3'd7: begin
                    cur_row  <= nxt_row;
                    cur_attr <= nxt_attr;
                end
                default: ;
            endcase
        end
    end

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


        pixel = visible & lit;
        grb   = cur_attr[7:5];
    end

endmodule

`default_nettype wire
