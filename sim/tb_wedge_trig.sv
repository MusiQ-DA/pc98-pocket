//
// tb_wedge_trig -- the run#976 transition triggers, unit-level.
//
// core_top's wedge detector latched only on FULL retirement silence, but
// z86 has no retire tap (v30_first_pop is tied 0 -- slot 0x17 reads 0
// forever) and the run#976 freeze signature is a CPU parked in a poll
// loop: the fetch cursor stops LEAVING its window, not necessarily
// stopping outright. This bench pins the three detectors added beside
// it, copied shape-for-shape from core_top with only the horizon
// narrowed (TICKS=64 instead of 2^24):
//
//   * liveness  -- zet_pc movement counts as alive (the OR with the
//     retired counter keeps any future retire feed useful);
//   * poll-trap -- probe write slot 0x87 {en[31], pc[19:0]} arms a
//     32-byte window (pc[19:5] match); dwelling inside it for the
//     horizon latches (and would freeze the wedge tap + pc_hist/tlog);
//   * fdq-stall -- the FDC's dma_req LEVEL held up for the horizon
//     latches (a healthy byte train re-dips it every few hundred clocks);
//   * wr 0x88 0x01 clears every latch and re-arms.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_wedge_trig;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    localparam int  TICKS   = 64;   // narrowed from core_top's 2^24 (~390 ms)

    logic clk = 0;
    always #(HALF_NS) clk = ~clk;

    logic reset_cpu = 1'b0, z86_dbg_stopped = 1'b0, jtag_dbg_stop = 1'b0,
          pause_core = 1'b0;
    logic [23:0] retired_cnt = 24'd0;      // z86: never moves (the point)
    logic [19:0] pc_now;
    logic        fdq_up;                   // the live cs_fdc2[7] wire
    logic        probe_wr_pulse;
    logic [6:0]  probe_waddr_c;
    logic [31:0] probe_wdata_c;

    // ---- copied from core_top, horizon narrowed ---------------------------
    localparam int CNT_W = $clog2(TICKS + 1);
    typedef logic [CNT_W-1:0] cnt_t;
    localparam cnt_t TICKS_MAX = cnt_t'(TICKS - 1);

    logic        wedge_latch = 1'b0;
    cnt_t        wedge_static = '0;
    logic [23:0] wedge_ret_prev = 24'd0;
    logic [19:0] wedge_pc_prev  = 20'd0;
    logic        poll_en   = 1'b0;
    logic [19:0] poll_pc   = 20'd0;
    cnt_t        poll_static = '0;
    logic        poll_latch = 1'b0;
    cnt_t        fdq_static  = '0;
    logic        fdq_latch   = 1'b0;

    wire wedge_run = ~reset_cpu & ~pause_core & ~z86_dbg_stopped
                   & ~jtag_dbg_stop;
    wire wedge_moving = (retired_cnt != wedge_ret_prev)
                      | (pc_now != wedge_pc_prev);
    wire poll_in_win = poll_en & (pc_now[19:5] == poll_pc[19:5]);
    wire tap_latch   = poll_latch | fdq_latch;

    always_ff @(posedge clk) begin
        if (probe_wr_pulse && probe_waddr_c == 7'h08
            && probe_wdata_c[0]) begin
            wedge_latch   <= 1'b0;
            wedge_static  <= '0;
            poll_static   <= '0;
            poll_latch    <= 1'b0;
            fdq_static    <= '0;
            fdq_latch     <= 1'b0;
        end else begin
            if (!wedge_latch && wedge_run) begin
                wedge_ret_prev <= retired_cnt;
                wedge_pc_prev  <= pc_now;
                if (!wedge_moving) begin
                    wedge_static <= wedge_static + 1'd1;
                    if (wedge_static == TICKS_MAX)
                        wedge_latch <= 1'b1;
                end else
                    wedge_static <= '0;
            end
            if (!poll_latch && wedge_run) begin
                if (poll_in_win) begin
                    poll_static <= poll_static + 1'd1;
                    if (poll_static == TICKS_MAX)
                        poll_latch <= 1'b1;
                end else
                    poll_static <= '0;
            end
            if (!fdq_latch && wedge_run) begin
                if (fdq_up) begin
                    fdq_static <= fdq_static + 1'd1;
                    if (fdq_static == TICKS_MAX)
                        fdq_latch <= 1'b1;
                end else
                    fdq_static <= '0;
            end
            if (tap_latch && !wedge_latch)
                wedge_latch <= 1'b1;
        end
    end

    initial begin
        probe_wr_pulse = 1'b0; probe_waddr_c = 7'h0; probe_wdata_c = 32'd0;
    end

    // core_top's slot-0x07 decode, same shape:
    //   {en[31], pc[19:0]} arms the poll-trap window.
    always_ff @(posedge clk) begin
        if (probe_wr_pulse && probe_waddr_c == 7'h07) begin
            poll_en <= probe_wdata_c[31];
            poll_pc <= probe_wdata_c[19:0];
        end
    end

    task automatic wr07(input logic [31:0] d);
        begin
            @(negedge clk);
            probe_waddr_c = 7'h07; probe_wdata_c = d; probe_wr_pulse = 1'b1;
            @(negedge clk);
            probe_wr_pulse = 1'b0;
        end
    endtask

    task automatic wr08(input logic [31:0] d);
        begin
            @(negedge clk);
            probe_waddr_c = 7'h08; probe_wdata_c = d; probe_wr_pulse = 1'b1;
            @(negedge clk);
            probe_wr_pulse = 1'b0;
        end
    endtask

    int errors = 0;

    initial begin
        pc_now  = 20'h00000;
        fdq_up  = 1'b0;

        // (1) a healthy machine: the cursor walks, nothing ever latches.
        repeat (4 * TICKS) begin
            @(posedge clk);
            pc_now <= pc_now + 20'd7;            // jumps windows every step
        end
        if (wedge_latch || poll_latch || fdq_latch) begin
            errors++;
            $display("FAIL (1): latched on a walking CPU (w=%b p=%b f=%b)",
                     wedge_latch, poll_latch, fdq_latch);
        end else
            $display("pass (1): walking CPU, no latch");

        // (2) arm the poll-trap on 0x317A8's window, then leave it alone:
        // the cursor walking OUTSIDE the window must not latch (the old
        // full-silence detector is what this is not).
        wr07({1'b1, 11'd0, 20'h317A8});
        repeat (4 * TICKS) begin
            @(posedge clk);
            pc_now <= 20'h62000 + ((pc_now + 20'd17) & 20'hFFF);
        end
        if (poll_latch || wedge_latch) begin
            errors++;
            $display("FAIL (2): poll-trap latched on a CPU outside the window");
        end else
            $display("pass (2): outside-window walk, no latch");

        // (3) the run#976 shape: the cursor parks INSIDE the window (it
        // may still jiggle inside -- a poll loop is a handful of
        // instructions) with retired_cnt eternally 0. The trap must fire.
        pc_now = 20'h317A4;                       // same 32-byte window
        repeat (3 * TICKS / 2) begin
            @(posedge clk);
            pc_now <= 20'h317A8 ^ (pc_now[0]);    // jiggles A8<->A9
        end
        if (!poll_latch || !wedge_latch) begin
            errors++;
            $display("FAIL (3): poll-trap did not fire on an in-window park");
        end else
            $display("pass (3): in-window park fired poll_latch (+wedge freeze)");

        // (4) wr 0x88 0x01 clears everything and re-arms.
        wr08(32'h1);
        if (wedge_latch || poll_latch || fdq_latch) begin
            errors++;
            $display("FAIL (4): re-arm write left a latch set");
        end else
            $display("pass (4): re-arm cleared the latches");

        // (5) FDC DRQ stall: dma_req held level for the horizon latches;
        // the intermittent shape (dipping well inside the horizon) does
        // not.
        fdq_up = 1'b1;
        repeat (TICKS / 2) @(posedge clk);
        if (fdq_latch) begin
            errors++;
            $display("FAIL (5a): fdq fired before the horizon");
        end else
            $display("pass (5a): below horizon, no fdq latch");
        repeat (TICKS) @(posedge clk);
        if (!fdq_latch) begin
            errors++;
            $display("FAIL (5b): held dma_req did not latch fdq");
        end else
            $display("pass (5b): held dma_req latched fdq (and wedge freeze)");

        wr08(32'h1);
        for (int i = 0; i < 8 * TICKS; i++) begin
            @(posedge clk);
            if ((i % 4) == 3) fdq_up = ~fdq_up;   // a healthy byte train
        end
        if (fdq_latch) begin
            errors++;
            $display("FAIL (5c): dipping dma_req latched fdq");
        end else
            $display("pass (5c): dipping dma_req, no fdq latch");

        // (6) full CPU silence still latches the wedge detector on pc
        // movement alone (the z86 reality: retired_cnt never moves).
        pc_now = 20'h10000;
        wedge_pc_prev = 20'h0DEAD;               // force "not moving" start
        repeat (TICKS + 4) @(posedge clk);       // pc never changes now
        if (!wedge_latch) begin
            errors++;
            $display("FAIL (6): pc-static silence did not latch wedge");
        end else
            $display("pass (6): pc-static silence latched wedge");

        if (errors == 0)
            $display("=== PASS tb_wedge_trig ===");
        else
            $display("=== FAIL tb_wedge_trig ===");
        $finish;
    end

endmodule

`default_nettype wire
