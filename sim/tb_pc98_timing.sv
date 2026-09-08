//
// tb_pc98_timing -- is the raster the one PC-98 software expects?
//
// The rates are what matter, and they come from np2's GDC clock table
// (io/gdc.c): a 21.0526 MHz dot clock, 106 characters of 8 dots across, and a
// vertical total that puts the frame rate at 56.4 Hz. Getting the totals wrong
// gives a picture that is present but out of spec, which a scaler may well hide
// until something on the guest side counts scanlines.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_timing;

    localparam real DOT_HZ = 21052600.0;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire [9:0] hcount, vcount;
    wire hsync, vsync, hblank, vblank, de, frame_start;

    pc98_video_timing dut (
        .clk(clk), .ce(1'b1), .rst(rst),
        .hcount(hcount), .vcount(vcount),
        .hsync(hsync), .vsync(vsync),
        .hblank(hblank), .vblank(vblank), .de(de), .frame_start(frame_start)
    );

    int errors = 0;
    int de_dots, de_lines, line_dots, frame_lines;
    int seen_h, seen_v;

    initial begin
        $display("=== PC-98 raster ===");
        repeat (4) @(posedge clk);
        rst = 0;

        // Wait for the top of a frame, then measure one whole frame. Do NOT
        // step past frame_start before counting: dot 0 of line 0 is displayed,
        // and skipping it makes both totals come up exactly one short.
        while (!frame_start) @(posedge clk);

        de_dots = 0; de_lines = 0; line_dots = 0; frame_lines = 0;
        seen_h = 0; seen_v = 0;
        begin
            int prev_v; bit counted_line;
            prev_v = vcount; counted_line = 0;
            forever begin
                if (de) begin
                    de_dots++;
                    if (!counted_line) begin de_lines++; counted_line = 1; end
                end
                if (hsync) seen_h++;
                if (vsync) seen_v++;
                line_dots++;
                @(posedge clk);
                if (vcount != prev_v) begin
                    frame_lines++;
                    prev_v = vcount;
                    counted_line = 0;
                end
                if (frame_start) break;
            end
        end

        $display("  dots per frame   : %0d (want %0d)", line_dots, 848*440);
        $display("  lines per frame  : %0d (want 440)", frame_lines);
        $display("  displayed dots   : %0d (want %0d)", de_dots, 640*400);
        $display("  displayed lines  : %0d (want 400)", de_lines);
        $display("  hsync dots/frame : %0d", seen_h);
        $display("  vsync dots/frame : %0d", seen_v);

        if (line_dots   !== 848*440) begin $display("  FAIL frame length"); errors++; end
        if (frame_lines !== 440)     begin $display("  FAIL line count");   errors++; end
        if (de_dots     !== 640*400) begin $display("  FAIL active dots");  errors++; end
        if (de_lines    !== 400)     begin $display("  FAIL active lines"); errors++; end
        if (seen_h == 0)             begin $display("  FAIL no hsync");     errors++; end
        if (seen_v == 0)             begin $display("  FAIL no vsync");     errors++; end

        // The rates those totals imply, against np2's table.
        $display("  H rate           : %.1f Hz (want 24826)", DOT_HZ / (848.0));
        $display("  V rate           : %.2f Hz (want 56.4)",  DOT_HZ / (848.0 * 440.0));
        if (DOT_HZ / 848.0 < 24500.0 || DOT_HZ / 848.0 > 25200.0) begin
            $display("  FAIL H rate outside 24.83 kHz +- 300"); errors++;
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #40_000_000;
        $display("GLOBAL TIMEOUT"); $finish;
    end

endmodule

`default_nettype wire
