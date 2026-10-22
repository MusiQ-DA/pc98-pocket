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
    logic        wild_en     = 1'b0;
    logic [3:0]  wild_static = '0;
    logic        wild_latch  = 1'b0;
    logic        z86_halted  = 1'b0;
    logic        z86_if      = 1'b1;
    logic        f0_port_write = 1'b0;

    wire wedge_run = ~reset_cpu & ~pause_core & ~z86_dbg_stopped
                   & ~jtag_dbg_stop;
    wire wedge_moving = (retired_cnt != wedge_ret_prev)
                      | (pc_now != wedge_pc_prev);
    wire poll_in_win = poll_en & (pc_now[19:5] == poll_pc[19:5]);
    // core_top's zone list (pc_wild), f0 term stripped: the port write is
    // legitimate even from a wild cursor, so it must not arm the trigger.
    wire wild_zone = wild_en & wedge_run
                   & (((pc_now < 20'h00400)
                       || (pc_now >= 20'hA0000 && pc_now < 20'hD0000)
                       || (pc_now >= 20'hE0000 && pc_now < 20'hE8000)
                       || (z86_halted && !z86_if))
                      & ~f0_port_write);
    wire tap_latch   = poll_latch | fdq_latch | wild_latch;

    always_ff @(posedge clk) begin
        if (probe_wr_pulse && probe_waddr_c == 7'h08
            && probe_wdata_c[0]) begin
            wedge_latch   <= 1'b0;
            wedge_static  <= '0;
            poll_static   <= '0;
            poll_latch    <= 1'b0;
            fdq_static    <= '0;
            fdq_latch     <= 1'b0;
            wild_static   <= '0;
            wild_latch    <= 1'b0;
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
            // wild debounce: core_top uses a full 10-bit counter; the
            // shape (count while present, reset on leaving) is what
            // matters here, so 4 bits keep the bench short.
            if (!wild_latch && wedge_run) begin
                if (wild_zone) begin
                    wild_static <= wild_static + 1'd1;
                    if (&wild_static)
                        wild_latch <= 1'b1;
                end else
                    wild_static <= '0;
            end
            if (tap_latch && !wedge_latch)
                wedge_latch <= 1'b1;
        end
    end

    initial begin
        probe_wr_pulse = 1'b0; probe_waddr_c = 7'h0; probe_wdata_c = 32'd0;
    end

    // core_top's slot-0x07 decode, same shape:
    //   {poll_en[31], wild_en[30], pc[19:0]} arms the poll window and the
    //   wild-fetch watch.
    always_ff @(posedge clk) begin
        if (probe_wr_pulse && probe_waddr_c == 7'h07) begin
            poll_en <= probe_wdata_c[31];
            wild_en <= probe_wdata_c[30];
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

        wr08(32'h1);

        // (7) the run#977 shape: the cursor BOUNCES inside the IVT
        // (0:0000 <-> 0:000F) -- moving the whole time, so the wedge
        // detector can never fire -- while armed wild (slot 0x87 bit30)
        // watches. The wild trigger must latch despite the movement.
        wr07({1'b1, 1'b1, 10'd0, 20'h317A8});    // poll + wild armed
        pc_now = 20'h00000;
        repeat (24) begin
            @(posedge clk);
            pc_now <= pc_now ^ 20'h0000F;        // 0 <-> F, always moving
        end
        if (!wild_latch || !wedge_latch) begin
            errors++;
            $display("FAIL (7): wild bounce did not latch (w=%b wld=%b)",
                     wedge_latch, wild_latch);
        end else
            $display("pass (7): IVT bounce latched wild (and wedge freeze)");

        // (8) same bounce with wild DISARMED (bit30=0): nothing latches.
        wr08(32'h1);
        wr07({1'b1, 1'b0, 10'd0, 20'h317A8});    // poll only
        pc_now = 20'h00000;
        repeat (24) begin
            @(posedge clk);
            pc_now <= pc_now ^ 20'h0000F;
        end
        if (wild_latch) begin
            errors++;
            $display("FAIL (8): wild latched while disarmed");
        end else
            $display("pass (8): wild disarmed, bounce ignored");

        // (9) the f0 term is stripped: a port-0xF0 write from a wild
        // cursor is a reset request, not a wild-fetch catch.
        pc_now = 20'h00000;
        f0_port_write = 1'b1;
        wr07({1'b1, 1'b1, 10'd0, 20'h317A8});    // wild armed again
        repeat (24) @(posedge clk);
        f0_port_write = 1'b0;
        if (wild_latch) begin
            errors++;
            $display("FAIL (9): wild latched on the f0 window");
        end else
            $display("pass (9): f0 write stripped from the wild zone");

        // (10) legal addresses (low RAM game code) never latch; a brief
        // one-cycle transient through the IVT window must also not latch
        // (the debounce).
        pc_now = 20'h10000;
        repeat (8) begin
            @(posedge clk);
            pc_now <= pc_now + 20'd11;
        end
        if (wild_latch) begin
            errors++;
            $display("FAIL (10a): wild latched on legal low RAM");
        end else
            $display("pass (10a): legal low RAM, no wild latch");
        pc_now = 20'h00005;                      // a 1-cycle transient
        @(posedge clk); pc_now <= 20'h10000;
        repeat (4) @(posedge clk);
        if (wild_latch) begin
            errors++;
            $display("FAIL (10b): wild latched on a transient");
        end else
            $display("pass (10b): transient through the wild zone ignored");

        // (11) HLT with IF clear is wild (nothing can wake it); HLT with
        // IF set is a legal VBLANK wait and must not latch.
        z86_halted = 1'b1; z86_if = 1'b0;
        repeat (24) @(posedge clk);
        if (!wild_latch) begin
            errors++;
            $display("FAIL (11a): HLT/IF=0 did not latch wild");
        end else
            $display("pass (11a): unwakeable HLT latched wild");
        wr08(32'h1);
        z86_halted = 1'b1; z86_if = 1'b1;
        repeat (24) @(posedge clk);
        if (wild_latch) begin
            errors++;
            $display("FAIL (11b): HLT/IF=1 (legal VBLANK wait) latched");
        end else
            $display("pass (11b): wakeable HLT ignored");

        if (errors == 0)
            $display("=== PASS tb_wedge_trig ===");
        else
            $display("=== FAIL tb_wedge_trig ===");
        $finish;
    end

endmodule

`default_nettype wire
