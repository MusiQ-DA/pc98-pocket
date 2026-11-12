// tb_pc98_text_gate -- a stopped master GDC shows no text.
//
// The real master pc98_gdc, driven through its command port with the bytes
// the BIOS sends, feeding pc98_text_gate across an incommensurate dot clock
// with the renderer's pixel held lit. np21w io/gdc.c (gdc_work) is the
// reference: STOP 0x0C / 0x05 and SYNC-off 0x0E clear the text plane's
// GDCSCRN_ENABLE; START 0x0D / 0x6B and SYNC-on 0x0F set it.
//
// The case that failed on hardware: Dynamo (MARKA PROJECT, 1991) calls
// INT 18h AH=0Dh -- the ROM's `mov al,0Ch / out 62h,al` at FE938 -- to take
// its DOS banner off the graphics title; np2kai hides the plane at that
// call, the core kept drawing it.
//
// Also pinned: before the first START since reset the pixel passes (the
// core's unprogrammed-GDC fallback picture is unchanged), and a reset
// returns to that state.
`timescale 1ns/1ps
`default_nettype none

module tb_pc98_text_gate;
    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;
    logic clk_dot = 1'b0;                    // 21.05 MHz dot clock
    always #(23.75) clk_dot = ~clk_dot;

    logic       reset = 1'b1;
    logic       cs = 1'b0, a1 = 1'b0;
    logic       io_write_n = 1'b1;
    logic [7:0] data_in = 8'h00;
    wire  [7:0] data_out;

    wire        disp_on;
    wire [7:0]  pitch;
    wire [15:0] part_sad [0:3];
    wire [9:0]  part_len [0:3];
    wire [5:0]  part_bend [0:2];
    wire [4:0]  line_rep;
    wire [15:0] cursor_addr;
    wire [3:0]  cursor_dot;
    wire        cursor_en, cursor_blink_en;
    wire [4:0]  cursor_top, cursor_bottom;
    wire [5:0]  cursor_rate;
    wire        draw_req, draw_busy;
    wire [7:0]  draw_op;
    wire [31:0] draw_snap [0:5];
    wire [1:0]  zoom_disp;
    wire [9:0]  vlines;

    pc98_gdc #(.MASTER(1'b1)) gdc (
        .clk(clk), .reset(reset),
        .cs(cs), .a1(a1), .io_read_n(1'b1), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(data_out),
        .hblank(1'b0), .vblank(1'b0),
        .disp_on(disp_on), .pitch(pitch),
        .part_sad(part_sad), .part_len(part_len), .part_pbyte(),
        .part_bend(part_bend),
        .cursor_addr(cursor_addr), .cursor_dot(cursor_dot),
        .cursor_en(cursor_en), .cursor_blink_en(cursor_blink_en),
        .cursor_top(cursor_top), .cursor_bottom(cursor_bottom),
        .cursor_rate(cursor_rate), .zoom_disp(zoom_disp), .vlines(vlines),
        .vbp(), .line_rep(line_rep),
        .draw_req(draw_req), .draw_op(draw_op), .draw_busy(draw_busy),
        .draw_timeout(), .srv_done_stb(1'b0), .draw_snap(draw_snap)
    );

    // Peripherals' own carry of disp_on into the dot clock (gdc_on_px).
    logic on_s1 = 1'b0, on_px = 1'b0;
    always_ff @(posedge clk_dot) begin
        on_s1 <= disp_on;  on_px <= on_s1;
    end

    logic pixel_in = 1'b1;                   // every renderer dot lit
    wire  pixel_out, text_off;
    pc98_text_gate dut (
        .clk(clk), .reset(reset), .disp_on(disp_on),
        .clk_dot(clk_dot), .disp_on_dot(on_px), .pixel_in(pixel_in),
        .pixel_out(pixel_out), .text_off(text_off)
    );

    // One port write, held like the real bus (~11 chipset clocks).
    task automatic wr(input logic odd, input logic [7:0] d);
        @(posedge clk);
        cs = 1'b1; a1 = odd; data_in = d; io_write_n = 1'b0;
        repeat (11) @(posedge clk);
        io_write_n = 1'b1; cs = 1'b0;
        @(posedge clk);
    endtask
    task automatic cmd(input logic [7:0] c);  wr(1'b1, c); endtask
    task automatic par(input logic [7:0] p);  wr(1'b0, p); endtask

    // The BIOS's 24 kHz master SYNC parameters (np21w gdcmastersync).
    task automatic sync_params;
        par(8'h10); par(8'h4E); par(8'h07); par(8'h25);
        par(8'h07); par(8'h07); par(8'h90); par(8'h65);
    endtask

    int errors = 0;

    // Settle through the dot-clock synchroniser, then sample a few dots: the
    // plane must be uniformly shown or uniformly blank.
    task automatic expect_text(input string what, input logic shown);
        int lit;
        repeat (8) @(posedge clk_dot);
        lit = 0;
        for (int i = 0; i < 16; i++) begin
            @(posedge clk_dot); #1;
            if (pixel_out) lit++;
        end
        if (shown ? (lit != 16) : (lit != 0)) begin
            $display("FAIL %s: text %s expected, %0d/16 dots lit (disp_on=%0d)",
                     what, shown ? "shown" : "blank", lit, disp_on);
            errors++;
        end else
            $display("ok   %s: text %s (disp_on=%0d)", what,
                     shown ? "shown" : "blank", disp_on);
    endtask

    initial begin
        repeat (20) @(posedge clk);
        reset = 1'b0;
        repeat (4) @(posedge clk);

        // Power-up: no START yet -- the fallback picture passes untouched.
        expect_text("before any START", 1'b1);

        // The ITF/BIOS CRT bring-up: SYNC (display off) + params, START.
        cmd(8'h0E); sync_params();
        expect_text("SYNC-off before the first START", 1'b1);
        cmd(8'h0D);
        expect_text("START 0x0D", 1'b1);

        // Dynamo's INT 18h AH=0Dh: the ROM writes 0Ch to port 62h.
        cmd(8'h0C);
        expect_text("STOP 0x0C (INT 18h AH=0Dh)", 1'b0);
        // ...and the graphics side it programs next must not bring the
        // text back (the master sees none of those writes).
        repeat (200) @(posedge clk);
        expect_text("still stopped", 1'b0);

        // INT 18h AH=0Ch: START again.
        cmd(8'h0D);
        expect_text("START 0x0D after STOP", 1'b1);

        // The other spellings np21w honours.
        cmd(8'h05);
        expect_text("STOP 0x05", 1'b0);
        cmd(8'h6B);
        expect_text("START 0x6B", 1'b1);
        cmd(8'h0E); sync_params();
        expect_text("SYNC-off 0x0E", 1'b0);
        cmd(8'h0F); sync_params();
        expect_text("SYNC-on 0x0F", 1'b1);

        // Stopped, then reset: back to the unprogrammed fallback.
        cmd(8'h0C);
        expect_text("STOP before reset", 1'b0);
        reset = 1'b1;
        repeat (20) @(posedge clk);
        reset = 1'b0;
        expect_text("after reset (no START yet)", 1'b1);

        if (errors == 0) $display("RESULT: PASS tb_pc98_text_gate");
        else             $display("RESULT: FAIL tb_pc98_text_gate (%0d)", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("RESULT: FAIL tb_pc98_text_gate (timeout)");
        $finish;
    end
endmodule

`default_nettype wire
