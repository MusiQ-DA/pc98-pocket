//
// tb_pc98_firstcell -- is the first cell of a text line actually drawn?
//
// On hardware the ITF's "MEMORY SWITCH ERROR" came out as "EMORY SWITCH ERROR"
// and a line reading "KANJI" as "ANJI": one cell short at the left edge, with
// everything after it correct and in the right place. That is a DROPPED cell,
// not a shifted line, and the two have to be told apart -- the renderer runs
// its glyph fetch one character time ahead precisely to avoid the shift, and a
// naive fix for the dropped cell reintroduces it.
//
// So this bench renders a whole line whose every cell carries a different glyph
// byte and a different attribute and checks, cell by cell:
//
//   * character time N shows cell N's glyph      (cell 0 present, no shift)
//   * character time N shows cell N's attribute  (the TVRAM side of the same
//     one-ahead pipeline)
//   * the glyph byte is the one for THIS scanline, not the one above it -- the
//     cell-0 fetch happens during the previous line's blanking, so its line
//     index has to be the next line's
//
// It diagnoses the two failure modes by name, because "first cell missing" and
// "whole line shifted by one" produce the same error count and demand opposite
// fixes.
//
// The memories are modelled with the one cycle of latency the real ones have:
// pc98_tvram registers vid_attr, pc98_glyph_rowbuf registers rd_byte. That
// latency is the whole reason the fetch runs ahead.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_firstcell;

    // pc98_video_timing's defaults: 106 characters of 8 dots, 440 lines.
    localparam int H_TOTAL = 848;
    localparam int V_TOTAL = 440;
    localparam int COLS    = 80;

    logic clk = 0;
    always #5 clk = ~clk;

    wire [9:0] hcount, vcount;
    wire       hs, vs, hb, vb, de, fs;

    // The real timing generator, not a hand-rolled counter: the bug lives in
    // how the renderer reads hcount/vcount at the edge of a line, so the edge
    // has to be the real one.
    pc98_video_timing u_timing (
        .clk(clk), .ce(1'b1), .rst(1'b0),
        .hcount(hcount), .vcount(vcount),
        .hsync(hs), .vsync(vs), .hblank(hb), .vblank(vb),
        .de(de), .frame_start(fs)
    );

    wire [11:0] tv_cell;
    logic [7:0] tv_attr;
    wire  [6:0] font_cell;
    wire  [3:0] font_line;
    logic [7:0] font_row;
    wire  [2:0] grb;
    wire        pixel;

    pc98_text_render dut (
        .clk(clk), .pix_ce(1'b1),
        .hcount(hcount), .vcount(vcount), .blink_on(1'b1),
        .tv_cell(tv_cell), .tv_attr(tv_attr),
        .font_cell(font_cell), .font_line(font_line), .font_row(font_row),
        .grb(grb), .pixel(pixel)
    );

    // ------------------------------------------------------------ the screen
    //
    // Glyph byte per (cell, line). Unique and non-zero for every cell of the
    // lines under test, so a cell taken from the wrong column, the wrong line
    // or from beyond the 80 filled ones (which read back as zero, exactly like
    // the row buffer's untouched cells 80..127) is a distinguishable value and
    // not just "dark".
    function automatic [7:0] want_glyph(input int col, input int line);
        want_glyph = 8'((col + 1) + line * COLS);
    endfunction

    // Attribute per (cell, row): colour varies with both, bit 0 set so the cell
    // is not secret, bits 4:1 clear so no blink/reverse/underline/vertical rule
    // can light a pixel the glyph did not.
    function automatic [7:0] want_attr(input int col, input int row);
        want_attr = {3'((col + row) % 7 + 1), 5'b00001};
    endfunction

    logic [7:0] gmodel [0:127][0:15];    // the row buffer's bank, one text row
    logic [7:0] amodel [0:4095];         // TVRAM attributes, the whole plane

    always_ff @(posedge clk) begin
        tv_attr  <= amodel[tv_cell];
        font_row <= gmodel[font_cell][font_line];
    end

    // ------------------------------------------------------------ the capture
    //
    // Rebuild each character time's glyph byte from the pixels. dot 0 is bit 7:
    // the shifter walks the byte leftmost-first.
    logic [7:0] obs_row [0:COLS-1];
    logic [2:0] obs_grb [0:COLS-1];

    always_ff @(posedge clk) begin
        if (vcount < 10'd400 && hcount < 10'd640) begin
            obs_row[hcount[9:3]][3'd7 - hcount[2:0]] <= pixel;
            if (hcount[2:0] == 3'd0) obs_grb[hcount[9:3]] <= grb;
        end
    end

    int errors = 0;

    // Let scanline y pass, then compare what was shifted out against what the
    // models hold for it.
    task automatic check_line(input int y);
        int  row;
        int  bad_glyph, bad_attr;
        logic [7:0] want_a;
        bit  looks_shifted;

        row       = y / 16;
        bad_glyph = 0;
        bad_attr  = 0;

        @(posedge clk);
        while (!(vcount == 10'(y) && hcount == 10'd0))   @(posedge clk);
        while (!(vcount == 10'(y) && hcount == 10'd639)) @(posedge clk);
        @(posedge clk);   // the last cell's final pixel lands on this edge

        for (int c = 0; c < COLS; c++) begin
            if (obs_row[c] !== want_glyph(c, y % 16)) begin
                if (bad_glyph < 4)
                    $display("  FAIL line %0d cell %0d: glyph %02h, want %02h",
                             y, c, obs_row[c], want_glyph(c, y % 16));
                bad_glyph++;
            end
            want_a = want_attr(c, row);
            if (obs_grb[c] !== want_a[7:5]) begin
                if (bad_attr < 4)
                    $display("  FAIL line %0d cell %0d: grb %03b, want %03b",
                             y, c, obs_grb[c], want_a[7:5]);
                bad_attr++;
            end
        end

        // Name the failure mode. Both of these are one cell of error and they
        // are fixed in opposite directions, so the count alone is useless.
        looks_shifted = 1'b1;
        for (int c = 1; c < COLS; c++)
            if (obs_row[c] !== want_glyph(c - 1, y % 16)) looks_shifted = 1'b0;

        if (bad_glyph == 0 && bad_attr == 0)
            $display("  line %0d: 80 cells correct", y);
        else if (looks_shifted)
            $display("  line %0d: WHOLE LINE SHIFTED -- cell N-1 drawn at character time N", y);
        else if (bad_glyph == 1 && obs_row[0] !== want_glyph(0, y % 16))
            $display("  line %0d: FIRST CELL LOST -- character time 0 carried %02h (00 is a cell the row buffer never fills), cells 1..79 correct and in place",
                     y, obs_row[0]);

        errors += bad_glyph + bad_attr;
    endtask

    initial begin
        for (int c = 0; c < 128; c++)
            for (int l = 0; l < 16; l++)
                gmodel[c][l] = 8'h00;         // beyond COLS: what the row buffer never fills
        for (int c = 0; c < COLS; c++)
            for (int l = 0; l < 16; l++)
                gmodel[c][l] = want_glyph(c, l);

        for (int i = 0; i < 4096; i++) amodel[i] = 8'h00;
        for (int r = 0; r < 25; r++)
            for (int c = 0; c < COLS; c++)
                amodel[r*80 + c] = want_attr(c, r);

        $display("=== PC-98 text: the first cell of a line ===");

        // One whole frame first. Cell 0 of line 0 is fetched during the LAST
        // character time of the frame's last line, so out of reset there is
        // nothing for it to have fetched yet.
        @(posedge clk);
        while (!(vcount == 10'd439 && hcount == 10'd847)) @(posedge clk);

        check_line(0);     // line 0 of row 0: the fetch wraps the whole frame
        check_line(1);     // next scanline: the cell-0 fetch must advance the line
        check_line(16);    // line 0 of row 1: and the row, for the attribute

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
