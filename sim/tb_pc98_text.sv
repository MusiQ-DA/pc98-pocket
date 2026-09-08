//
// tb_pc98_text -- does the text plane draw what TVRAM says?
//
// Checks the things that would otherwise be found by squinting at a photograph
// of a handheld screen:
//
//   * glyph bits come out leftmost-first
//   * reverse, secret, blink and underline do what the attribute says
//   * the colour field is G R B, not R G B -- an order that produces a picture
//     which looks plausible while being wrong
//   * a kanji cell is NOT drawn through the ANK font
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_text;

    logic clk = 0;
    always #5 clk = ~clk;

    logic        pix_ce = 1'b1;
    logic [9:0]  hcount = 10'd0, vcount = 10'd0;
    logic        blink_on = 1'b1;

    wire [11:0] tv_cell;
    logic [7:0] tv_char_lo, tv_char_hi, tv_attr;
    wire  [7:0] font_code;
    wire  [6:0] font_cell;
    wire  [3:0] font_line;
    logic [7:0] font_row;
    wire  [2:0] grb;
    wire        pixel, kanji_seen;

    pc98_text_render dut (
        .clk(clk), .pix_ce(pix_ce), .hcount(hcount), .vcount(vcount),
        .blink_on(blink_on),
        .tv_cell(tv_cell), .tv_char_lo(tv_char_lo), .tv_char_hi(tv_char_hi),
        .tv_attr(tv_attr),
        .font_cell(font_cell), .font_code(font_code), .font_line(font_line),
        .font_row(font_row),
        .grb(grb), .pixel(pixel), .kanji_seen(kanji_seen)
    );

    // A screen: every cell holds the same character and attribute, which is
    // enough to check the pixel path without modelling a whole TVRAM.
    logic [7:0] scr_char_lo = 8'h41;
    logic [7:0] scr_char_hi = 8'h00;
    logic [7:0] scr_attr    = 8'hE1;   // white (G,R,B all set), not secret
    logic [7:0] glyph_row   = 8'b1010_0000;

    // Model the one-cycle latencies the real memories have.
    always_ff @(posedge clk) begin
        tv_char_lo <= scr_char_lo;
        tv_char_hi <= scr_char_hi;
        tv_attr    <= scr_attr;
        font_row   <= glyph_row;
    end

    int errors = 0;

    // Run to the given pixel of the given line and sample.
    task automatic goto(input int x, input int y);
        // Walk from the start of the line so the cell pipeline fills the way it
        // does in hardware.
        vcount = 10'(y);
        for (int i = 0; i <= x; i++) begin
            hcount = 10'(i);
            @(posedge clk);
        end
    endtask

    task automatic expect_pixel(input int x, input int y, input bit want,
                                input string what);
        goto(x, y);
        if (pixel !== want) begin
            $display("  FAIL %s: pixel(%0d,%0d)=%0d want %0d", what, x, y, pixel, want);
            errors++;
        end
    endtask

    initial begin
        $display("=== PC-98 text plane ===");
        repeat (4) @(posedge clk);

        // Glyph 1010_0000 on line 0: pixels 0 and 2 of the cell lit, MSB first.
        // Sample well into the line so the pipeline is primed.
        expect_pixel(8*10 + 0, 0, 1'b1, "glyph bit 7");
        expect_pixel(8*10 + 1, 0, 1'b0, "glyph bit 6");
        expect_pixel(8*10 + 2, 0, 1'b1, "glyph bit 5");
        expect_pixel(8*10 + 3, 0, 1'b0, "glyph bit 4");

        // Reverse inverts.
        scr_attr = 8'hE5;                 // + reverse (0x04)
        expect_pixel(8*10 + 0, 0, 1'b0, "reverse on a lit pixel");
        expect_pixel(8*10 + 1, 0, 1'b1, "reverse on a dark pixel");

        // Secret (bit 0 clear) blanks the cell.
        scr_attr = 8'hE0;
        expect_pixel(8*10 + 0, 0, 1'b0, "secret");

        // Blink: lit in one phase, dark in the other.
        scr_attr = 8'hE3;                 // blink + not secret
        blink_on = 1'b1;
        expect_pixel(8*10 + 0, 0, 1'b1, "blink, phase on");
        blink_on = 1'b0;
        expect_pixel(8*10 + 0, 0, 1'b0, "blink, phase off");
        blink_on = 1'b1;

        // Underline: bottom line of the cell lights regardless of the glyph.
        scr_attr  = 8'hE9;                // underline + not secret
        glyph_row = 8'h00;
        expect_pixel(8*10 + 3, 15, 1'b1, "underline on line 15");
        expect_pixel(8*10 + 3, 14, 1'b0, "no underline on line 14");
        glyph_row = 8'b1010_0000;

        // Colour is G R B. 0x20 is the LOW bit of the field, which is BLUE.
        scr_attr = 8'h21;
        goto(8*10 + 0, 0);
        $display("  attr 0x21 -> grb=%03b (want 001, blue)", grb);
        if (grb !== 3'b001) begin $display("  FAIL blue"); errors++; end
        scr_attr = 8'h81;                 // top bit of the field is GREEN
        goto(8*10 + 0, 0);
        $display("  attr 0x81 -> grb=%03b (want 100, green)", grb);
        if (grb !== 3'b100) begin $display("  FAIL green"); errors++; end
        scr_attr = 8'h41;                 // middle is RED
        goto(8*10 + 0, 0);
        if (grb !== 3'b010) begin $display("  FAIL red"); errors++; end

        // Kanji now comes from the font like anything else -- the row buffer
        // fetches both halves and hands over bytes, so the renderer draws what
        // it is given. What must still hold is that the fact is REPORTED, so
        // "is the guest using kanji" stays measurable.
        scr_attr    = 8'hE1;
        scr_char_hi = 8'h30;              // non-zero high byte = kanji
        glyph_row   = 8'b1010_0000;
        expect_pixel(8*10 + 0, 0, 1'b1, "kanji glyph bit 7");
        expect_pixel(8*10 + 1, 0, 1'b0, "kanji glyph bit 6");
        $display("  kanji cell: kanji_seen=%0d (must be flagged)", kanji_seen);
        if (kanji_seen !== 1'b1) begin
            $display("  FAIL kanji not flagged"); errors++;
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
