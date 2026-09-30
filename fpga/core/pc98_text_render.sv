//
// pc98_text_render -- the 80x25 text plane, 8x16 cells on 640x400.
//
// Attribute byte, from np21w vram/maketext.h:
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
    input  wire [15:0] gdc_sad[0:3],    // the four partitions' starts, RAW
    input  wire [9:0]  gdc_len[0:3],    // and their line counts, decoded
    // 40 columns: mode1 bit 2 (the port 0x68 register) makes each cell
    // sixteen dots -- the glyph byte shifts at half rate so every bit lasts
    // two dots, and a column consumes TWO cells, the even one carrying the
    // character. np21w does the same split (pccore.c: gdc.mode1 & 4 ->
    // maketext40, which steps edi by 2 and doubles each byte through
    // text_tblx2).
    input  wire        wide,

    // The CRTC's text-cell geometry, np21w io/crtc.c ports 0x70-0x7A even.
    // The BIOS's 20-line mode writes bl=0x11, NOT 0x13 -- 0x13 is the GDC's
    // CSRFORM raster count and belongs to line_rep below. What the CRTC
    // supplies is the FONT WINDOW inside the row: pl is the topline offset
    // (np21w maketext.c's TEXT_PL: values >= 16 mean pl-32, so 0x1E shifts
    // the glyph two rasters down), cl is how many rasters the font occupies
    // (0x10, clamped to 16), and bl+1-past-topline is where the underline
    // rides (maketext.c's nowline+1 == lines).
    input  wire [4:0]  crtc_pl,
    input  wire [4:0]  crtc_bl,
    input  wire [4:0]  crtc_cl,

    // The master GDC's CSRFORM raster count minus one -- np21w's TEXT_LR,
    // the text-row pitch. 0x0F = 16-raster rows (25-line), 0x13 = 20-raster
    // rows (the 20-line mode dipsw2 bit 3 selects). Reset to 0x0F upstream,
    // so an unprogrammed GDC still draws the 25-line picture it always did.
    input  wire [4:0]  line_rep,

    // The cursor, as the master GDC's CSRW/CSRFORM leave it. The address is
    // a WORD index into the text plane -- the same space gdc_sad and the
    // cell counter below count in -- so the comparison is direct.
    input  wire [15:0] cur_addr,
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
    output logic       pixel,           // this pixel is lit

    // Row-boundary strobes for the glyph row buffer, which fills a row ahead
    // of the raster: tick at the first dot of each row's raster 0, and the
    // row index that fetch should target (wrapping to 0 when the next row
    // would start beyond the visible frame -- pitch does not always divide
    // 400, and the last partial row's fill is the next frame's row 0).
    output wire        txt_row_tick,
    output wire [4:0]  txt_next_row
);

    wire visible = (hcount < 10'd640) && (vcount < 10'd400);

    // `col` counts COLUMNS, not cells: a wide column is sixteen dots (two
    // cells' worth), a narrow one eight.
    wire [6:0] col  = wide ? {1'b0, hcount[9:4]} : hcount[9:3];
    wire [2:0] dot  = hcount[2:0];     // dot within a narrow cell
    wire [3:0] cdot = hcount[3:0];     // dot within a wide cell

    // Row geometry used to be three vcount mod/div sites against the CSRFORM
    // raster count; the /10 and /20 pitches synthesised as lpm_divide chains
    // (several hundred ALM across the module's instances). The beam only
    // steps one raster at a time, so a (row, raster) pair walking the frame
    // carries the same information: its combinational next-state IS this
    // line's decomposition, +1 raster is the fetch position, and
    // vcount+pitch always lands in row+1. The whole arithmetic collapses to
    // a counter and a wrap compare -- and unlike the old case it honours
    // EVERY line_rep, not just the BIOS table's {8,10,16,20}.
    wire [9:0] pitch_p1 = {5'd0, line_rep} + 10'd1;

    reg  [9:0] trk_v;
    reg  [4:0] trk_raster, trk_row;
    wire       new_line = (vcount != trk_v);
    wire       trk_full = ({5'd0, trk_raster} >= pitch_p1 - 10'd1);

    wire [4:0] raster_q = (vcount == 10'd0) ? 5'd0
                        : new_line ? (trk_full ? 5'd0 : trk_raster + 5'd1)
                        :            trk_raster;
    wire [4:0] row_q    = (vcount == 10'd0) ? 5'd0
                        : new_line ? (trk_full ? trk_row + 5'd1 : trk_row)
                        :            trk_row;

    always_ff @(posedge clk) begin
        if (new_line) begin
            trk_v      <= vcount;
            trk_raster <= raster_q;
            trk_row    <= row_q;
        end
    end

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
    wire        last_char = wide ? (hcount >= 10'(H_TOTAL - 16))
                                 : (hcount >= 10'(H_TOTAL - 8));
    wire [6:0]  next_col  = last_char ? 7'd0 : col + 7'd1;
    // The fetch's position in (row, raster) space is the next scanline's --
    // one tracked step further than raster_q/row_q; on the frame's last
    // line the next scanline is (0, 0).
    wire       pf_full   = ({5'd0, raster_q} >= pitch_p1 - 10'd1);
    wire       frame_end = last_char & (vcount == 10'(V_TOTAL - 1));
    wire [4:0] pf_raster = !last_char ? raster_q
                         : frame_end  ? 5'd0
                         : pf_full    ? 5'd0
                         :              raster_q + 5'd1;
    wire [4:0] next_row  = !last_char ? row_q
                         : frame_end  ? 5'd0
                         : pf_full    ? row_q + 5'd1
                         :              row_q;

    // ---- where the screen starts, and how wide a row is -------------------
    //
    // np21w vram/maketext.c, which is the authority for the TEXT side:
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

`include "pc98_text_part.svh"

    // The four PRAM partitions tile the screen's rows (np21w maketext.c):
    // each row's cell run starts at its own partition's SAD plus the
    // row's index WITHIN the partition times the pitch. A one-area screen
    // keeps every row in partition 0, which reduces to the old SAD+row*pitch.
    // (The calls are separate statements: Verilator 5.020's V3Gate trips
    // on a function call inlined inside a conditional -- internal error.)
    wire [16:0] n_partf = pc98_text_part(next_row, gdc_sad, gdc_len);
    wire [16:0] n_part  = gdc_live ? n_partf : {next_row, 12'd0};
    wire [11:0] n_start = n_part[11:0];
    wire [4:0]  n_rel   = n_part[16:12];
    // row * pitch. Kept as a multiplier only when the GDC is driving it; the
    // 80-column case is still the shift pair it always was.
    wire [11:0] n_relmul  = n_rel * eff_pitch;
    wire [11:0] n_rowoff  = {1'b0, next_row, 6'd0} + {3'b000, next_row, 4'd0};
    wire [11:0] next_rowbase = gdc_live ? n_relmul : n_rowoff;
    // In the cell index space a wide column occupies two slots (np21w's
    // edi += 2 per column), so the column term doubles.
    wire [11:0] next_coff    = wide ? {5'd0, next_col[5:0], 1'b0}
                                    : {5'd0, next_col};
    wire [11:0] next_cell    = n_start + next_rowbase + next_coff;

    // The cell being DRAWN: the current row and column against the same
    // start and pitch. next_* above is where the memories are pointed (one
    // character time ahead); this is where the shift register is emptying.
    // (Named draw_row because cur_row is the glyph register below.)
    wire [4:0]  draw_row  = row_q;
    wire [16:0] d_partf = pc98_text_part(draw_row, gdc_sad, gdc_len);
    wire [16:0] d_part  = gdc_live ? d_partf : {draw_row, 12'd0};
    wire [11:0] d_start = d_part[11:0];
    wire [4:0]  d_rel   = d_part[16:12];
    wire [11:0] d_relmul  = d_rel * eff_pitch;
    wire [11:0] d_rowoff  = {1'b0, draw_row, 6'd0} + {3'b000, draw_row, 4'd0};
    wire [11:0] draw_rowbase = gdc_live ? d_relmul : d_rowoff;
    wire [11:0] draw_coff  = wide ? {5'd0, col[5:0], 1'b0} : {5'd0, col};
    wire [11:0] drawn_cell = d_start + draw_rowbase + draw_coff;

    // The GDC's cursor: a blinking reverse block over cursor_top..cursor_bot
    // of the one cell CSRW names. Blink rides the attribute blink phase --
    // close enough to the machine's own ~2 Hz until someone needs the exact
    // CSRFORM rate.
    wire cursor_here = cur_en & (drawn_cell == cur_addr[11:0]);
    // CSRFORM's cursor top/bottom are font-window coordinates, not raw
    // cell rasters -- np21w compares them against nowline.
    wire cursor_line = cursor_here & (nowline_q >= 7'(cur_top))
                                   & (nowline_q <= 7'(cur_bot));
    wire cursor_show = cursor_line & (~cur_blink | blink_on);

    assign tv_cell = next_cell;

    // ---- topline: where inside the row the font sits -------------------
    //
    // np21w maketext.c: topline = TEXT_PL, except pl >= 16 wraps it to
    // pl-32 -- the BIOS's 20-line entry is pl=0x1E, a two-raster drop, so
    // the font window is raster 2..17 of the 20 and the underline rides
    // raster 19. nowline is the signed font-window coordinate; font is
    // drawn only while 0 <= nowline < cl. The prefetch position runs the
    // same shift on pf_raster so the fetch matches the pixel it feeds.
    wire signed [6:0] topline    = (crtc_pl >= 5'd16) ? 7'(crtc_pl) - 7'sd32
                                                    : 7'(crtc_pl);
    wire signed [6:0] nowline_q  = topline + 7'(raster_q);
    wire signed [6:0] nowline_pf = topline + 7'(pf_raster);
    // np21w's `lines`: pl >= 16 -> bl+1; otherwise bl+1 - topline.
    wire signed [6:0] lines_w    = (crtc_pl >= 5'd16) ? 7'(crtc_bl) + 7'sd1
                                                    : 7'(crtc_bl) + 7'sd1
                                                      - topline;
    wire [4:0] cl_eff    = (crtc_cl > 5'd16) ? 5'd16 : crtc_cl;
    wire       row_blank = (nowline_q < 0) || (nowline_q >= 7'(cl_eff));

    // Latched at the point the TVRAM answer is valid.
    logic [7:0] q_attr;
    assign font_line = ((nowline_pf >= 0) && (nowline_pf < 7'sd16))
                     ? nowline_pf[3:0] : 4'd0;
    // The row buffer's slot equals the cell's offset within the row: double
    // the column when wide.
    assign font_cell = wide ? {next_col[5:0], 1'b0} : next_col;

    // The glyph and attribute in use for the cell being shifted out.
    logic [7:0] cur_row, cur_attr;
    logic [7:0] nxt_row, nxt_attr;

    // The pipeline's three taps ride the character time: on a wide cell they
    // land at dots 2, 6 and 15 of sixteen; on a narrow one, 1, 3 and 7 of
    // eight. Either way the memories have had their cycle of latency -- and
    // the load has to be the LAST dot, not an early one: reloading cur_row
    // at dot 14 leaves dot 15 shifting the NEXT cell's bit 0, which is the
    // one-dot smear at every wide cell's right edge.
    wire ph_attr = wide ? (cdot == 4'd2 ) : (dot == 3'd1);
    wire ph_row  = wide ? (cdot == 4'd6 ) : (dot == 3'd3);
    wire ph_load = wide ? (cdot == 4'd15) : (dot == 3'd7);

    always_ff @(posedge clk) begin
        if (pix_ce) begin
            if (ph_attr) q_attr <= tv_attr;
            if (ph_row) begin
                nxt_row  <= font_row;
                nxt_attr <= q_attr;
            end
            if (ph_load) begin
                cur_row  <= nxt_row;
                cur_attr <= nxt_attr;
            end
        end
    end

    // MSB is the leftmost pixel; on a wide cell each bit lasts two dots.
    wire [2:0] shift = wide ? ~cdot[3:1] : ~dot;
    wire       glyph = cur_row[shift];

    wire secret    = ~cur_attr[0];
    wire blink     =  cur_attr[1];
    wire reverse   =  cur_attr[2];
    wire underline =  cur_attr[3];
    wire vertline  =  cur_attr[4];

    // Underline sits at nowline+1 == lines (np21w maketext.c): at the
    // 25-line geometry that is raster 15, and on the 20-line cell it rides
    // raster 19 -- the row's last raster either way. The vertical line sits
    // at the left edge.
    wire deco = (underline && (nowline_q + 7'sd1 == lines_w))
              || (vertline && (wide ? (cdot == 4'd0) : (dot == 3'd0)));

    // The row-buffer cadence the glyph prefetcher runs on: raster 0 of every
    // row, and the row that starts one pitch hence (row 0 once the next row
    // would begin past the visible frame).
    assign txt_row_tick = pix_ce & (hcount == 10'd0) & (raster_q == 5'd0)
                        & (vcount < 10'd400);
    // vcount+pitch is always the same raster of the next row, so its row is
    // row_q+1; past the visible frame the next fill is row 0.
    wire [9:0] next_row_v = vcount + pitch_p1;
    assign txt_next_row = (next_row_v >= 10'd400) ? 5'd0 : row_q + 5'd1;

    always_comb begin
        logic lit;
        lit = (glyph & ~row_blank) | deco;
        if (secret)                lit = 1'b0;
        else if (blink & ~blink_on) lit = 1'b0;
        if (reverse)               lit = ~lit;


        if (cursor_show)          lit = ~lit;   // the cursor is a reverse slice
        pixel = visible & lit;
        // The cursor must be seen: where the cell's attribute is a non-black
        // colour it lends it to the slice; where it is black -- every cell
        // the BIOS never wrote -- the slice falls back to white or the block
        // is a black square on a black screen, invisible.
        grb   = cursor_show && (cur_attr[7:5] == 3'b000)
              ? 3'b111 : cur_attr[7:5];
    end

endmodule

`default_nettype wire
