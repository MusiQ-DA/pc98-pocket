//
// tb_rst_witness -- the spontaneous-reboot catch, unit-level.
//
// The machine reboots itself mid-game and every witness reads the POST
// tail: the ITF POST refills the tlog ring before its own OUT 0F0h
// (F9A2A) freezes it, and pc_hist was WIPE-armed on reset/soft_reset_cpu
// anyway -- the F0 freeze fired, then the clear branch erased it two
// cycles later.  core_top now catches the reboot at its earliest
// symptom, the fetch cursor snapping to the reset vector (z86 holds
// CS:IP=F000:FFF0 through the whole reset stretch), and names the reset
// SOURCE with a sticky rise-map over reset_wire's eight terms.  This
// bench pins the copied shapes:
//
//   * the source witness -- a rise lights its sticky bit, names the
//     last source and latches the tick; a simultaneous rise resolves
//     to the PLL (index 0); wr 0x8A 0x01 clears;
//   * the reboot freeze -- the cycle the cursor reads FFF0 the entry
//     LANDS (last record = the seam) and both rings freeze: the POST
//     walk that follows records nothing;
//   * trail survival -- pc_hist keeps its pre-reboot entries through
//     the reset AND through the POST's own OUT 0F0h (the old wipe-race
//     is the bug this regression pins); only wr 0x85 re-arms it;
//   * the walk case -- a cursor that WALKS to FFF0 with no source rise
//     still freezes the rings (the trail catch) while the witness
//     stays dark: "no reset, the guest jumped there";
//   * the re-arm guard -- a slot-0x06 write with the cursor parked at
//     FFF0 leaves the log armed instead of re-freezing it.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_rst_witness;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clk = 0;
    always #(HALF_NS) clk = ~clk;

    // ---- the inputs core_top sees ----------------------------------------
    logic [19:0] pc_now = 20'h80000;
    logic        itf_bank = 1'b1;
    // the eight reset_wire/CPU-reset terms (rst_src_now's order)
    logic        soft_reset_cpu = 1'b0, ri_greset = 1'b0;
    logic        soft_guest_hold = 1'b0, guest_hold_sync2 = 1'b0;
    logic        interact_reset = 1'b0, bios_ever_loaded = 1'b1;
    logic        load_active = 1'b0, RESET = 1'b0;
    // the OUT 0F0h port-write strobe (f0_port_write in core_top)
    logic        f0_port_write = 1'b0;
    // probe write channel
    logic        probe_wr_pulse;
    logic [6:0]  probe_waddr_c;
    logic [31:0] probe_wdata_c;

    // ---- the reset-source witness, copied from core_top -------------------
    wire [7:0] rst_src_now = {soft_reset_cpu,   ri_greset,
                              soft_guest_hold,  guest_hold_sync2,
                              interact_reset,  ~bios_ever_loaded,
                              load_active,      RESET};
    reg  [31:0] rst_tick      = 32'd0;
    reg  [7:0]  rst_src_q     = 8'h00;
    reg  [7:0]  rst_seen      = 8'h00;
    reg  [3:0]  rst_last      = 4'h0;
    reg  [31:0] rst_last_tick = 32'd0;
    wire [7:0]  rst_rise = rst_src_now & ~rst_src_q;
    wire [2:0]  rst_rise_idx = rst_rise[0] ? 3'd0
                            : rst_rise[1] ? 3'd1
                            : rst_rise[2] ? 3'd2
                            : rst_rise[3] ? 3'd3
                            : rst_rise[4] ? 3'd4
                            : rst_rise[5] ? 3'd5
                            : rst_rise[6] ? 3'd6 : 3'd7;
    always_ff @(posedge clk) begin
        rst_tick  <= rst_tick + 32'd1;
        rst_src_q <= rst_src_now;
        if (probe_wr_pulse && probe_waddr_c == 7'h0a && probe_wdata_c[0]) begin
            rst_seen      <= 8'h00;
            rst_last      <= 4'h0;
            rst_last_tick <= 32'd0;
        end else if (|rst_rise) begin
            rst_seen      <= rst_seen | rst_rise;
            rst_last      <= {1'b1, rst_rise_idx};
            rst_last_tick <= rst_tick;
        end
    end

    // ---- the reboot catch, copied from core_top ---------------------------
    wire pc_reset_vec = (pc_now == 20'hFFFF0);
    reg  rst_boot_latch = 1'b0;
    reg  rst_boot_itf   = 1'b0;
    always_ff @(posedge clk) begin
        if (probe_wr_pulse && probe_waddr_c == 7'h08 && probe_wdata_c[0]) begin
            rst_boot_latch <= 1'b0;
            rst_boot_itf   <= 1'b0;
        end else if (pc_reset_vec && !rst_boot_latch) begin
            rst_boot_latch <= 1'b1;
            rst_boot_itf   <= itf_bank;
        end
    end
    wire tap_latch = rst_boot_latch;   // poll/fdq latches tied off

    // ---- the tlog ring, shape copied (entry narrowed to the PC) -----------
    // tlog_all mode: a record per fetch-cursor change. trig_* terms tied
    // off; tlog_trap on so the F0 term of pc_wild is live (pc_wild narrowed
    // to its f0_port_write term, the only one this bench exercises).
    logic        tlog_all = 1'b1, tlog_trap = 1'b1, tlog_frozen = 1'b0;
    logic [15:0] tlog_n = 16'd0;
    logic [19:0] tlog_pc_d = 20'd0;
    reg  [19:0]  tlog [0:63];
    wire         pc_wild = f0_port_write;
    wire         tlog_ev = tlog_all ? (pc_now != tlog_pc_d) : 1'b0;
    always_ff @(posedge clk) begin
        tlog_pc_d <= pc_now;
        if (probe_wr_pulse && probe_waddr_c == 7'h06) begin
            tlog_n      <= 16'd0;
            tlog_frozen <= 1'b0;
        end else if (tlog_ev && !tlog_frozen) begin
            tlog[tlog_n[5:0]] <= pc_now;
            tlog_n            <= tlog_n + 16'd1;
        end
        if (!(probe_wr_pulse && probe_waddr_c == 7'h06) &&
            (((tlog_trap && pc_wild) ||
              pc_reset_vec ||
              tap_latch) && !tlog_frozen))
            tlog_frozen <= 1'b1;
    end
    function automatic [19:0] tlog_at(input int idx);
        tlog_at = tlog[idx[5:0]];
    endfunction

    // ---- the pc_hist ring, shape copied (32 deep, as shipped) -------------
    reg  [19:0] pc_hist [0:31];
    reg  [4:0]  pc_hist_w = 5'd0;
    reg  [19:0] pc_hist_prev = 20'h0;
    reg         pc_hist_frozen = 1'b0;
    wire        pc_rearm_c = probe_wr_pulse && (probe_waddr_c == 7'h05);
    reg         pc_rearm = 1'b0;
    always_ff @(posedge clk) pc_rearm <= pc_rearm_c;
    wire [19:0] hist_src = pc_now;
    always_ff @(posedge clk) begin
        if (pc_rearm) begin
            pc_hist_frozen <= 1'b0;
            pc_hist_w      <= 5'd0;
        end else if (!pc_hist_frozen) begin
            if (hist_src != pc_hist_prev) begin
                pc_hist_prev       <= hist_src;
                pc_hist[pc_hist_w] <= hist_src;
                pc_hist_w          <= pc_hist_w + 5'd1;
            end
            if (f0_port_write || pc_reset_vec || (tlog_trap && pc_wild) ||
                tap_latch)
                pc_hist_frozen <= 1'b1;
        end
    end

    // ---- probe-write tasks (tb_wedge_trig's shape) ------------------------
    task automatic pwr(input logic [6:0] a, input logic [31:0] d);
        begin
            @(negedge clk);
            probe_waddr_c = a; probe_wdata_c = d; probe_wr_pulse = 1'b1;
            @(negedge clk);
            probe_wr_pulse = 1'b0;
        end
    endtask

    // walk the cursor the way a running machine does: drive between
    // edges (negedge), one recorded value per posedge
    task automatic walk(input int n, input logic [19:0] base, input int step);
        for (int i = 0; i < n; i++) begin
            @(negedge clk);
            pc_now = base + i * step;
            @(posedge clk);
        end
    endtask

    int errors = 0;
    int n_pre, w_pre;

    initial begin
        probe_wr_pulse = 1'b0; probe_waddr_c = 7'h0; probe_wdata_c = 32'd0;

        // (1) power-on: PLL + streaming + BIOS gate rise together; the
        // priority names the PLL, and all three bits go sticky.
        RESET = 1'b1; load_active = 1'b1; bios_ever_loaded = 1'b0;
        repeat (3) @(posedge clk);
        if (rst_seen !== 8'b0000_0111 || rst_last !== 4'h8 /* {1,idx0}=PLL */) begin
            errors++;
            $display("FAIL (1): power-on rise map seen=%08b last=%0d",
                     rst_seen, rst_last);
        end else
            $display("pass (1): simultaneous power-on rise -> PLL named");
        // boot finishes, operator clears the witness
        RESET = 1'b0; load_active = 1'b0; bios_ever_loaded = 1'b1;
        repeat (2) @(posedge clk);
        pwr(7'h0a, 32'd1);
        if (rst_seen !== 8'd0 || rst_last !== 4'd0) begin
            errors++;
            $display("FAIL (1b): witness clear left seen=%08b last=%0d",
                     rst_seen, rst_last);
        end else
            $display("pass (1b): wr 0x8A 0x01 clears the witness");

        // (2) the game runs: some branches land in both rings, nothing
        // freezes, no source rises.
        @(negedge clk);
        pc_now = 20'h62A00;
        @(posedge clk);
        walk(24, 20'h62A04, 20'd23);
        if (tlog_frozen || pc_hist_frozen || rst_seen !== 8'd0) begin
            errors++;
            $display("FAIL (2): running game froze (t=%0b p=%0b) or rose (%08b)",
                     tlog_frozen, pc_hist_frozen, rst_seen);
        end else if (tlog_n < 24'd20 || pc_hist_w < 5'd20) begin
            errors++;
            $display("FAIL (2): rings not filling (n=%0d w=%0d)", tlog_n, pc_hist_w);
        end else
            $display("pass (2): game run fills both rings, no freeze");
        @(negedge clk);              // settled read of the ring counters
        n_pre = tlog_n;
        w_pre = pc_hist_w;

        // (3) the spontaneous reboot: a full guest reset -- the cursor
        // snaps to FFF0 (z86's held reset state) and soft_guest_hold (say)
        // had risen the cycle before.  The FFF0 entry LANDS as the last
        // tlog record, both rings freeze, the boot latch names the bank.
        @(negedge clk); soft_guest_hold = 1'b1;
        @(posedge clk);
        @(negedge clk); pc_now = 20'hFFFF0;   // reset asserts: CS:IP <- F000:FFF0
        @(posedge clk);                        // the seam entry lands + freeze
        @(posedge clk);                        // let the NBAs settle, then read
        soft_guest_hold = 1'b0;                // the orchestrated reset releases
        if (!tlog_frozen || !pc_hist_frozen || !rst_boot_latch) begin
            errors++;
            $display("FAIL (3): no freeze (t=%0b p=%0b boot=%0b)",
                     tlog_frozen, pc_hist_frozen, rst_boot_latch);
        end else if (tlog_n !== n_pre + 1 || tlog_at(int'(tlog_n - 1)) !== 20'hFFFF0) begin
            errors++;
            $display("FAIL (3): seam entry lost (n=%0d want %0d last=%06x)",
                     tlog_n, n_pre + 1, tlog_at(int'(tlog_n - 1)));
        end else
            $display("pass (3): frozen at the seam, last entry FFF0");
        if (rst_seen[5] !== 1'b1 || rst_last !== 4'hd /* {1,idx5} */) begin
            errors++;
            $display("FAIL (3b): witness missed the culprit (%08b last=%0d)",
                     rst_seen, rst_last);
        end else
            $display("pass (3b): witness names soft_guest_hold, tick %0d",
                     rst_last_tick);

        // (4) the ITF POST runs: entries must NOT land in either ring,
        // and its own OUT 0F0h (the old wipe-race trigger) must leave
        // the pre-reboot trail intact.
        @(negedge clk); pc_now = 20'hF8000; @(posedge clk);
        walk(12, 20'hF8004, 20'd37);
        @(negedge clk); f0_port_write = 1'b1; @(posedge clk);
        @(negedge clk); f0_port_write = 1'b0;
        walk(8, 20'hF9A00, 20'd11);
        if (tlog_n !== n_pre + 1) begin
            errors++;
            $display("FAIL (4): POST refilled tlog (n=%0d want %0d)",
                     tlog_n, n_pre + 1);
        end else if (pc_hist_w < w_pre || pc_hist_w > w_pre + 1) begin
            errors++;
            $display("FAIL (4): pc_hist trail clobbered (w=%0d, pre %0d)",
                     pc_hist_w, w_pre);
        end else
            $display("pass (4): POST + its F0 wrote nothing; trail intact");

        // (5) re-arm: the wedge clear drops the boot latch, slot 5 rolls
        // pc_hist, slot 6 re-arms tlog -- and recording resumes.
        pwr(7'h08, 32'd1);
        pwr(7'h05, 32'd1);
        pwr(7'h06, 32'h800FFFF0);
        if (rst_boot_latch || pc_hist_frozen || tlog_frozen) begin
            errors++;
            $display("FAIL (5): re-arm left latches (b=%0b p=%0b t=%0b)",
                     rst_boot_latch, pc_hist_frozen, tlog_frozen);
        end else begin
            walk(6, 20'h10000, 20'd9);
            if (tlog_n < 6'd5) begin
                errors++;
                $display("FAIL (5): tlog did not resume (n=%0d)", tlog_n);
            end else
                $display("pass (5): re-arm restores recording");
        end

        // (6) the walk case: no source rises, the cursor WALKS to the
        // reset vector -- rings freeze (the trail catch) while the
        // witness stays dark: the guest jumped, no reset fired.
        pwr(7'h0a, 32'd1);           // fresh witness: the game was clean
        pwr(7'h08, 32'd1); pwr(7'h05, 32'd1); pwr(7'h06, 32'h800FFFF0);
        walk(10, 20'h20000, 20'd4097);
        @(negedge clk); pc_now = 20'hFFFF0;
        @(posedge clk); @(posedge clk);
        if (!tlog_frozen || !rst_boot_latch) begin
            errors++;
            $display("FAIL (6): walk-to-FFF0 did not freeze (t=%0b b=%0b)",
                     tlog_frozen, rst_boot_latch);
        end else if (rst_seen !== 8'd0) begin
            errors++;
            $display("FAIL (6): witness lit on a walk (%08b)", rst_seen);
        end else
            $display("pass (6): walk freezes the rings, witness stays dark");

        // (7) the re-arm guard: cursor parked at FFF0, slot 0x06 written
        // -- the log must come back armed that cycle, not re-freeze.
        // (A cycle later it freezes again, correctly: a cursor PARKED on
        // the reset vector means the machine is held in reset.)
        pwr(7'h08, 32'd1);           // boot latch down so only tlog matters
        pwr(7'h06, 32'h800FFFF0);    // the guarded re-arm, pc still FFF0
        if (tlog_frozen) begin
            errors++;
            $display("FAIL (7): slot-0x06 re-arm under FFF0 stayed frozen");
        end else begin
            @(posedge clk); @(negedge clk);    // settled read of the re-freeze
            if (!tlog_frozen) begin
                errors++;
                $display("FAIL (7b): parked FFF0 did not re-freeze after re-arm");
            end else
                $display("pass (7): re-arm under a parked FFF0 clears, then re-freezes");
        end

        if (errors == 0)
            $display("=== PASS tb_rst_witness ===");
        else begin
            $display("=== FAIL tb_rst_witness: %0d errors ===", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule

`default_nettype wire
