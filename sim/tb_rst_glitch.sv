//
// tb_rst_glitch -- the spontaneous-reboot fix, unit-level.
//
// The machine rebooted itself mid-game (SuperDepth: dark screen, cold
// POST, ROM BASIC) with the reset-source witness dark -- seen=0x00, no
// reset source rose.  The hole: RESET is the RAW analog 'locked' output
// of two PLLs, asynchronous to clk_chipset, and every guest stretch flop
// (reset / reset_cpu / reset_chipset / reset_sdram / reset_soft) took its
// term on an ASYNC SET.  A nanosecond-scale unlock blip that rises and
// falls between clk_chipset posedges cold-booted the whole machine while
// the posedge-sampled witness never saw a level to latch.
//
// core_top now runs every guest reset term through synch_3 into
// clk_chipset (RESET_sync / soft_guest_hold_sync), so only an unlock that
// survives three edges can restart the guest; the raw pulses the filter
// ate are counted on the slot-0x9D witness (rst_raw_cnt / rst_real_cnt,
// blips = raw - real).  This bench pins the copied shapes:
//
//   * power-on -- the raw level, its filtered copy and the episode
//     counters agree (one real episode); the witness names the PLL and
//     the operator's 0x8A clear works;
//   * THE FIX -- a sub-period raw blip (shorter than one clk period,
//     placed between posedges) is caught by the async latch (the very
//     pulse a stretch flop used to take) yet the guest's reset NEVER
//     asserts, the witness stays dark, and 0x9D counts raw++ real+0;
//   * a sustained unlock still resets the guest, lights witness bit 0
//     and counts real++ (a real PLL loss must keep working);
//   * the softcore's cross-domain hold reaches reset_wire only through
//     its synchronized copy -- witness bit 5, guest reset, no raw-reset
//     episode;
//   * no double-count: each episode moves its counter exactly once.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_rst_glitch;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clk = 0;
    always #(HALF_NS) clk = ~clk;

    // ---- the inputs core_top sees ----------------------------------------
    logic RESET = 1'b1;              // raw ~locked of two PLLs, async
    logic soft_guest_hold = 1'b0;    // softcore-domain register
    // the remaining reset_wire terms, in their "machine is up" state
    logic soft_reset_cpu = 1'b0, ri_greset = 1'b0;
    logic guest_hold_sync2 = 1'b0, interact_reset = 1'b0;
    logic bios_ever_loaded = 1'b1, load_active = 1'b0;
    // probe write channel (the witness clear)
    logic        probe_wr_pulse;
    logic [6:0]  probe_waddr_c;
    logic [31:0] probe_wdata_c;

    // ---- synch_3's shape (fpga/apf/common.v), copied ----------------------
    logic RESET_sync, rst_sync_rise, rst_sync_fall;
    sync3 i_sync3 (RESET, RESET_sync, clk, rst_sync_rise, rst_sync_fall);

    logic soft_guest_hold_sync, soft_unused_rise, soft_unused_fall;
    sync3 i_sync3_soft (soft_guest_hold, soft_guest_hold_sync, clk,
                        soft_unused_rise, soft_unused_fall);

    // ---- the guest reset, core_top's shape (stretch shortened to 8) -------
    wire reset_wire = RESET_sync | load_active | ~bios_ever_loaded
                    | interact_reset | guest_hold_sync2 | soft_guest_hold_sync
                    | ri_greset;
    localparam [15:0] STRETCH = 16'd8;   // core_top: 16'hffff -- shape, not scale
    logic reset = 1'b1;
    logic [15:0] reset_count = 16'h0000;
    always @(posedge clk, posedge reset_wire) begin
        if (reset_wire) begin
            reset       <= 1'b1;
            reset_count <= 16'h0000;
        end else if (reset) begin
            if (reset_count != STRETCH) begin
                reset       <= 1'b1;
                reset_count <= reset_count + 16'd1;
            end else begin
                reset       <= 1'b0;
                reset_count <= reset_count;
            end
        end else begin
            reset       <= 1'b0;
            reset_count <= reset_count;
        end
    end

    // ---- the reset-source witness, copied (bit5/bit0 are the live ones) ---
    wire [7:0] rst_src_now = {soft_reset_cpu,   ri_greset,
                              soft_guest_hold_sync, guest_hold_sync2,
                              interact_reset,  ~bios_ever_loaded,
                              load_active,      RESET_sync};
    reg  [7:0]  rst_seen = 8'h00;
    reg  [7:0]  rst_src_q = 8'h00;
    wire [7:0]  rst_rise = rst_src_now & ~rst_src_q;
    always_ff @(posedge clk) begin
        rst_src_q <= rst_src_now;
        if (probe_wr_pulse && probe_waddr_c == 7'h0a && probe_wdata_c[0])
            rst_seen <= 8'h00;
        else if (|rst_rise)
            rst_seen <= rst_seen | rst_rise;
    end

    // ---- the raw-reset blip witness, copied (slot 0x9D) -------------------
    reg        rst_raw_l = 1'b0;
    reg [1:0]  rst_raw_q = 2'b00;
    reg        rst_raw_clear_q = 1'b0;
    reg [15:0] rst_raw_cnt  = 16'd0;
    reg [15:0] rst_real_cnt = 16'd0;
    wire       rst_raw_seen = rst_raw_q[1];
    wire       rst_raw_clear = rst_raw_seen & ~RESET & ~RESET_sync;
    wire       rst_raw_pulse = rst_raw_clear & ~rst_raw_clear_q;
    always @(posedge clk or posedge RESET) begin
        if (RESET)
            rst_raw_l <= 1'b1;
        else if (rst_raw_clear)
            rst_raw_l <= 1'b0;
    end
    always_ff @(posedge clk) begin
        rst_raw_q       <= {rst_raw_q[0], rst_raw_l};
        rst_raw_clear_q <= rst_raw_clear;
        if (rst_raw_pulse)
            rst_raw_cnt <= rst_raw_cnt + 16'd1;
        if (rst_sync_rise)
            rst_real_cnt <= rst_real_cnt + 16'd1;
    end

    // tb monitor: did the guest reset EVER assert since a mark?
    reg reset_ever = 1'b0;
    always @(posedge clk) if (reset) reset_ever <= 1'b1;

    task automatic pwr(input logic [6:0] a, input logic [31:0] d);
        begin
            @(negedge clk);
            probe_waddr_c = a; probe_wdata_c = d; probe_wr_pulse = 1'b1;
            @(negedge clk);
            probe_wr_pulse = 1'b0;
        end
    endtask

    int errors = 0;

    initial begin
        probe_wr_pulse = 1'b0; probe_waddr_c = 7'h0; probe_wdata_c = 32'd0;

        // (1) power-on: the raw level holds, the filtered copy follows,
        // the stretch keeps the guest down, one real episode counts.
        repeat (10) @(posedge clk);
        if (RESET_sync !== 1'b1 || reset !== 1'b1) begin
            errors++;
            $display("FAIL (1): power-on sync=%b reset=%b", RESET_sync, reset);
        end else
            $display("pass (1): power-on holds the guest through the filter");
        if (rst_seen[0] !== 1'b1) begin
            errors++;
            $display("FAIL (1a): witness did not name the PLL: %08b", rst_seen);
        end else
            $display("pass (1a): witness bit0 lit at power-on");
        // boot: unlock ends, the stretch runs out, the episode completes
        @(negedge clk); RESET = 1'b0;
        repeat (STRETCH + 16'd8) @(posedge clk);
        if (reset !== 1'b0) begin
            errors++;
            $display("FAIL (1b): guest never released: reset=%b", reset);
        end else
            $display("pass (1b): boot releases the guest");
        if (rst_raw_cnt !== 16'd1 || rst_real_cnt !== 16'd1) begin
            errors++;
            $display("FAIL (1c): episode counts raw=%0d real=%0d",
                     rst_raw_cnt, rst_real_cnt);
        end else
            $display("pass (1c): one real episode, blips=0");
        // operator clears the witness
        pwr(7'h0a, 32'd1);
        if (rst_seen !== 8'd0) begin
            errors++;
            $display("FAIL (1d): witness clear left seen=%08b", rst_seen);
        end else
            $display("pass (1d): wr 0x8A 0x01 clears the witness");
        reset_ever = 1'b0;

        // (2) THE FIX: a sub-period raw blip between posedges.  The async
        // latch catches it (the very pulse the old stretch flops took on
        // their async set), yet the guest must NOT reset and the witness
        // must stay dark; only 0x9D's raw count moves.
        @(posedge clk);
        #(HALF_NS * 0.4) RESET = 1'b1;     // mid-cycle, no posedge inside
        #4 RESET = 1'b0;                   // 4 ns << 23.3 ns period
        @(posedge clk);
        if (rst_raw_l !== 1'b1) begin
            errors++;
            $display("FAIL (2): async latch missed the blip");
        end else
            $display("pass (2): the async latch caught the blip");
        repeat (12) @(posedge clk);
        if (reset_ever !== 1'b0 || reset !== 1'b0) begin
            errors++;
            $display("FAIL (2a): a filtered blip reset the guest");
        end else
            $display("pass (2a): blip filtered -- the guest never reset");
        if (rst_seen !== 8'd0) begin
            errors++;
            $display("FAIL (2b): witness lit on a filtered blip: %08b", rst_seen);
        end else
            $display("pass (2b): witness dark through the blip");
        if (rst_raw_cnt !== 16'd2 || rst_real_cnt !== 16'd1) begin
            errors++;
            $display("FAIL (2c): blip counts raw=%0d real=%0d",
                     rst_raw_cnt, rst_real_cnt);
        end else
            $display("pass (2c): 0x9D raw=2 real=1 -- one blip on record");

        // (3) a sustained unlock still resets the guest.
        @(negedge clk); RESET = 1'b1;
        repeat (6) @(posedge clk);
        if (RESET_sync !== 1'b1 || reset !== 1'b1 || rst_seen[0] !== 1'b1) begin
            errors++;
            $display("FAIL (3): sustained unlock lost: sync=%b reset=%b seen=%08b",
                     RESET_sync, reset, rst_seen);
        end else
            $display("pass (3): sustained unlock resets guest, bit0 lit");
        @(negedge clk); RESET = 1'b0;
        repeat (STRETCH + 16'd8) @(posedge clk);
        if (reset !== 1'b0) begin
            errors++;
            $display("FAIL (3a): guest stuck in reset after a real unlock");
        end else
            $display("pass (3a): guest released after the real unlock");
        if (rst_raw_cnt !== 16'd3 || rst_real_cnt !== 16'd2) begin
            errors++;
            $display("FAIL (3b): counts raw=%0d real=%0d (double count?)",
                     rst_raw_cnt, rst_real_cnt);
        end else
            $display("pass (3b): one episode each -- no double count");
        pwr(7'h0a, 32'd1);
        reset_ever = 1'b0;

        // (4) the softcore's hold crosses domains only through the sync.
        @(posedge clk);
        #(HALF_NS * 0.6) soft_guest_hold = 1'b1;   // mid-edge transition
        repeat (6) @(posedge clk);
        if (soft_guest_hold_sync !== 1'b1 || reset !== 1'b1
            || rst_seen[5] !== 1'b1) begin
            errors++;
            $display("FAIL (4): soft hold: sync=%b reset=%b seen=%08b",
                     soft_guest_hold_sync, reset, rst_seen);
        end else
            $display("pass (4): soft hold resets via its synced copy, bit5 lit");
        @(negedge clk); soft_guest_hold = 1'b0;
        repeat (STRETCH + 16'd8) @(posedge clk);
        if (reset !== 1'b0 || rst_raw_cnt !== 16'd3) begin
            errors++;
            $display("FAIL (4a): soft hold aftermath: reset=%b raw=%0d",
                     reset, rst_raw_cnt);
        end else
            $display("pass (4a): guest released; the raw-RESET witness unmoved");

        if (errors == 0)
            $display("PASS tb_rst_glitch");
        else begin
            $display("FAIL tb_rst_glitch (%0d errors)", errors);
            $fatal(1);
        end
        $finish;
    end

    // synch_3 (fpga/apf/common.v), shape copied so the bench stands alone
    // (see the sync3 module below tb_rst_glitch)

endmodule

module sync3 (
    input  wire i,
    output reg  o,
    input  wire clk,
    output wire rise,
    output wire fall
);
    reg stage_1, stage_2, stage_3;
    assign rise = o & ~stage_3;
    assign fall = ~o & stage_3;
    always @(posedge clk)
        {stage_3, o, stage_2, stage_1} <= {o, stage_2, stage_1, i};
    initial begin
        stage_1 = 1'b0; stage_2 = 1'b0; stage_3 = 1'b0; o = 1'b0;
    end
endmodule

`default_nettype wire
