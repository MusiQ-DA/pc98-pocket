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

module pc98_text_render #(
    // The raster the fetch pointer wraps on. Defaults are pc98_video_timing's
    // own: 848 = 106 characters of 8 dots, 440 lines. The horizontal total must
    // stay a multiple of 8 or the "last character time of the line" test below
    // never lands on a cell boundary.
    parameter int H_TOTAL = 848,
    parameter int V_TOTAL = 440
) (
    input  wire        clk,
    input  wire        pix_ce,          // one pixel per assertion
    input  wire [9:0]  hcount,          // pixel within the line
    input  wire [9:0]  vcount,          // line within the frame
    input  wire        blink_on,        // blink phase, ~2 Hz

    // The master GDC's display registers. Tie gdc_on low and this module
    // behaves exactly as it did before they existed.
    input  wire        gdc_on,          // START seen
    input  wire [7:0]  gdc_pitch,       // words per row
    input  wire [15:0] gdc_sad,         // partition 0's start, RAW

    // The cursor, as the master GDC's CSRW/CSRFORM leave it. The address is
    // a WORD index into the text plane -- the same space gdc_sad and the
    // cell counter below count in -- so the comparison is direct.
    input  wire [13:0] cur_addr,
    input  wire        cur_en,
    input  wire        cur_blink,
    input  wire [4:0]  cur_top,
    input  wire [4:0]  cur_bot,

    // TVRAM attribute port (one cycle of latency). The character codes are the
    // row buffer's business, not this module's: it is handed glyph bytes.
    output wire [11:0] tv_cell,
    input  wire  [7:0] tv_attr,

    // Glyph port (one cycle of latency). font_cell/font_line say WHICH cell is
    // being fetched, which is the raster cell ahead of the one being drawn --
    // the row buffer is indexed by them, and addressing that buffer with the
    // current column instead would shift the whole line by one cell. At the end
    // of a line that next cell is cell 0 of the NEXT scanline, so font_line
    // leads vcount there too.
    output wire  [6:0] font_cell,
    output wire  [3:0] font_line,
    input  wire  [7:0] font_row,

    output logic [2:0] grb,             // G,R,B as the attribute orders them
    output logic       pixel            // this pixel is lit
);

    wire visible = (hcount < 10'd640) && (vcount < 10'd400);

    wire [6:0] col  = hcount[9:3];
    wire [3:0] line = vcount[3:0];     // the line being DRAWN; the fetch's is below
    wire [2:0] dot  = hcount[2:0];

    // The FETCH position: the raster cell one character time ahead of the one
    // being drawn, which is where the memories' one cycle of latency is paid
    // for. It has to be the next RASTER cell, not the next column of this line.
    //
    // Wrapping the column at 79 instead -- what this did until the hardware run
    // that printed "EMORY SWITCH ERROR" for "MEMORY SWITCH ERROR" -- wraps
    // twenty-six character times too early on a 106-character line, and two
    // things follow. Cell 0 IS fetched, during character time 79, and is
    // shifted out into the blanking at hcount 640-647, eighty character times
    // after the slot it belonged in. The pointer then runs 81,82,...,106
    // through the rest of the blanking, so the load at dot 7 of the last
    // character time (hcount 847) carries cell 106 -- an address the row buffer
    // never fills, which reads back as zero, and zero is what the first
    // character time of the next line shifted out. The attribute port runs the
    // same pointer, so that cell took its colour from cell 106 as well.
    // Cells 1..79 were never affected, which is why the rest of the line was
    // correct and in place: a dropped cell, not a shifted line.
    //
    // The vertical half matters for the same reason. The first cell of a line
    // is fetched during the line BEFORE it, so its line-within-cell -- and, at
    // a text row boundary, its row -- must be the next scanline's, or the top
    // cell of every line shows the slice above it.
    wire        last_char = (hcount >= 10'(H_TOTAL - 8));
    wire [9:0]  next_v    = last_char
                          ? ((vcount == 10'(V_TOTAL - 1)) ? 10'd0 : vcount + 10'd1)
                          : vcount;
    wire [6:0]  next_col  = last_char ? 7'd0 : col + 7'd1;
    wire [4:0]  next_row  = next_v[8:4];

    // ---- where the screen starts, and how wide a row is -------------------
    //
    // np2kai vram/maketext.c, which is the authority for the TEXT side:
    //
    //     pitch = gdc.m.para[GDC_PITCH] & 0xfe;
    //     esi   = LOW12(LOADINTELWORD(gdc.m.para + GDC_SCROLL));
    //     ...   mem[0xa0000 + edi*2]
    //
    // so the master GDC's SAD is a CELL INDEX, twelve bits, NOT shifted -- the
    // graphics GDC's LOW15(vad << 1) is a different reading of the same PRAM
    // field, and pc98_gdc hands both out raw for that reason.
    //
    // AN UNPROGRAMMED GDC MUST GIVE TODAY'S PICTURE. gdc_on is the START
    // command; a pitch of zero is a GDC that has been started but not told how
    // wide a row is. Either way this falls back to 80 columns from cell 0,
    // which is the expression that was here before, so the screen that works
    // now keeps working and is the regression test for this change.
    wire        gdc_live  = gdc_on & (gdc_pitch != 8'd0);
    wire [7:0]  eff_pitch = gdc_live ? {gdc_pitch[7:1], 1'b0} : 8'd80;
    wire [11:0] eff_start = gdc_live ? gdc_sad[11:0]          : 12'd0;

    // row * pitch. Kept as a multiplier only when the GDC is driving it; the
    // 80-column case is still the shift pair it always was.
    wire [11:0] next_rowbase = gdc_live
        ? 12'(next_row * eff_pitch)
        : ({1'b0, next_row, 6'd0} + {3'b000, next_row, 4'd0});
    wire [11:0] next_cell    = eff_start + next_rowbase + {5'd0, next_col};

    // The cell being DRAWN: the current row and column against the same
    // start and pitch. next_* above is where the memories are pointed (one
    // character time ahead); this is where the shift register is emptying.
    // (Named draw_row because cur_row is the glyph register below.)
    wire [4:0]  draw_row  = vcount[8:4];
    wire [11:0] draw_rowbase = gdc_live
        ? 12'(draw_row * eff_pitch)
        : ({1'b0, draw_row, 6'd0} + {3'b000, draw_row, 4'd0});
    wire [11:0] drawn_cell = eff_start + draw_rowbase + {5'd0, col};

    // The GDC's cursor: a blinking reverse block over cursor_top..cursor_bot
    // of the one cell CSRW names. Blink rides the attribute blink phase --
    // close enough to the machine's own ~2 Hz until someone needs the exact
    // CSRFORM rate.
    wire cursor_here = cur_en & (drawn_cell == {2'b00, cur_addr[11:0]});
    wire cursor_line = cursor_here & (line >= cur_top) & (line <= cur_bot);
    wire cursor_show = cursor_line & (~cur_blink | blink_on);

    assign tv_cell = next_cell;

    // Latched at the point the TVRAM answer is valid.
    logic [7:0] q_attr;
    assign font_line = next_v[3:0];
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


        if (cursor_show)          lit = ~lit;   // the cursor is a reverse slice
        pixel = visible & lit;
        grb   = cur_attr[7:5];
    end

endmodule

`default_nettype wire
