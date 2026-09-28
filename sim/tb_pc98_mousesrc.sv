// tb_pc98_mousesrc -- the shared mouse source feeding the bus mouse.
//
// The contract under test:
//
//   1. a dock report is consumed once its three words have sat stable for
//      the snapshot window, and arrives on ev_* scaled by 1/8 with the
//      remainder carried into the next report,
//   2. a held D-pad direction steps once per pad tick and pad A/B merge
//      into the button bits.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_mousesrc;

    localparam real CLK_MHZ = 42.954545;
    localparam HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0;
    always #(HALF_NS) clock = ~clock;

    // Small clk_rate: the pad tick shrinks.
    localparam int unsigned TEST_CLK = 48000;
    localparam int unsigned PAD_DIV  = TEST_CLK / 200;   // pad tick span

    logic [31:0] cont4_joy  = 32'd0;
    logic [15:0] cont4_key  = 16'd0;
    logic [15:0] cont4_trig = 16'd0;
    logic  [5:0] pad        = 6'd0;

    wire signed [15:0] ev_dx, ev_dy;
    wire               ev_v;
    wire        [1:0]  btn;

    pc98_mouse_src #(.clk_rate(TEST_CLK)) src (
        .clk       (clock),
        .cont4_joy (cont4_joy),
        .cont4_key (cont4_key),
        .cont4_trig(cont4_trig),
        .pad       (pad),
        .ev_dx     (ev_dx),
        .ev_dy     (ev_dy),
        .ev_v      (ev_v),
        .btn       (btn)
    );

    int errors = 0;

    task automatic expect_eq(input int got, input int want, input string what);
        begin
            if (got !== want) begin
                errors = errors + 1;
                $display("FAIL: %s: got %0d (0x%0x) want %0d (0x%0x)",
                         what, got, got, want, want);
            end
        end
    endtask

    // Drive a stable report: buttons + dx in joy, dy in trig, counter in key.
    // The dock's deltas are little-endian -- the source reads
    // {word[7:0], word[15:8]} -- so pack low byte into [15:8].
    task automatic report(input logic [1:0] btns, input signed [15:0] dx,
                          input signed [15:0] dy, input logic [15:0] cnt);
        begin
            cont4_joy  = {14'd0, btns, dx[7:0], dx[15:8]};
            cont4_trig = {dy[7:0], dy[15:8]};
            cont4_key  = cnt;
        end
    endtask

    // Wait through the snapshot window and capture the event's deltas; a
    // report produces exactly one ev_v, so also count to catch repeats.
    int rpt_events;
    logic signed [15:0] cap_dx, cap_dy;
    task automatic wait_rpt;
        int i;
        begin
            rpt_events = 0;
            for (i = 0; i < 8300; i++) begin
                @(negedge clock);
                if (ev_v) begin
                    cap_dx = ev_dx; cap_dy = ev_dy;
                    rpt_events = rpt_events + 1;
                end
            end
            if (rpt_events != 1) begin
                errors = errors + 1;
                $display("FAIL: %0d events for one report, want 1", rpt_events);
            end
        end
    endtask

    int ev_count, i;

    initial begin
        repeat (4) @(negedge clock);

        // ---- 1: a report becomes one scaled event -------------------------
        // The snapshot needs ~8191 quiet clocks; the counter change is then
        // consumed once and scaled by 1/8: +64 -> +8, -16 -> -2.
        report(2'b00, 16'sd64, -16'sd16, 16'd1);
        wait_rpt;
        expect_eq(cap_dx, 8, "report dx scaled /8");
        expect_eq(cap_dy, -2, "report dy scaled /8");

        // ---- 2: the residue carries ---------------------------------------
        // 5/8 rounds to 0 with remainder 5; the next +5 sees 5+5 -> 1.
        report(2'b00, 16'sd5, 16'sd0, 16'd2);
        wait_rpt;
        expect_eq(cap_dx, 0, "first sub-step report scales to 0");
        report(2'b00, 16'sd5, 16'sd0, 16'd3);
        wait_rpt;
        expect_eq(cap_dx, 1, "residue carries into the next report");

        // ---- 3: buttons merge ----------------------------------------------
        report(2'b01, 16'sd0, 16'sd0, 16'd4);  // dock left pressed
        wait_rpt;
        expect_eq({30'd0, btn}, 1, "dock left button");
        pad = 6'b100000;                       // pad B -> right
        repeat (4) @(negedge clock);
        expect_eq({30'd0, btn}, 3, "pad B merges as right");
        pad = 6'd0;

        // ---- 4: pad stepping ------------------------------------------------
        // D-pad right held: one +1 step per pad tick (~240 clks here).
        pad = 6'b001000;
        ev_count = 0;
        for (i = 0; i < PAD_DIV * 2 + PAD_DIV / 2; i++) begin
            @(negedge clock);
            if (ev_v && (ev_dx != 0)) ev_count++;
        end
        if (ev_count < 2 || ev_count > 3) begin
            errors = errors + 1;
            $display("FAIL: %0d pad steps in ~2.5 ticks, want 2", ev_count);
        end
        pad = 6'd0;

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
