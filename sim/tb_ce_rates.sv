//
// tb_ce_rates -- what frequencies does ce_generator actually make?
//
// The speed table is four rational ratios against a 42.954545 MHz chipset
// clock, and "is index 1 really 9.8304 MHz?" is a measurement, not a reading.
// The PC-98 build's ratios exist because this machine is a 2.4576 MHz-family
// box (docs/HANDOVER.md 3.6: the ITF picks that class when [0x0501] bit 7 is
// clear, and the PIT is clocked for it), so its CPU speeds are 2.4576 x2 and
// x4 -- the "5 MHz" and "10 MHz" of a PC-9801VM/VX front panel -- and NOT the
// PC/XT's NTSC-derived 4.77/7.16/9.54.
//
// Counting edges over a window costs milliseconds. The first attempt at
// checking this change booted the whole ITF for two hours to watch a memory
// test count, which measured the ROM rather than the divider.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ce_rates;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic reset = 1'b1;
    logic [1:0] sel = 2'b00;
    logic       load = 1'b0;

    wire clk_cpu, ce_pos, ce_neg, per_ce;
    wire cycle_accrate, shift_read_timing;
    wire [7:0] ccc_div, ccc_dec;
    wire [1:0] rd_wait, wr_wait;

    ce_generator dut (
        .clock(clk), .reset(reset),
        .clk_select_load(load), .clk_select(sel),
        .cpu_clk_pin(clk_cpu),
        .cpu_ce_posedge(ce_pos), .cpu_ce_negedge(ce_neg),
        .peripheral_ce(per_ce),
        .cycle_accrate(cycle_accrate),
        .clock_cycle_counter_division_ratio(ccc_div),
        .clock_cycle_counter_decrement_value(ccc_dec),
        .shift_read_timing(shift_read_timing),
        .ram_read_wait_cycle(rd_wait), .ram_write_wait_cycle(wr_wait)
    );

    // What each index is meant to be. A posedge of the CPU pin clock per
    // measured posedge CE, so this is the CPU's clock rate.
    real want [4] = '{4.9152, 9.8304, 19.6608, 21.4773};
    localparam string WHICH = "PC-98 (2.4576 MHz family)";

    // 0.1 per cent: a phase accumulator cannot land exactly and does not need
    // to -- the PC-98 ratios are within 0.0001 per cent, and the tolerance is
    // here to catch a wrong table entry, not rounding.
    localparam real TOL = 0.001;

    int    errors = 0;
    int    count;
    time   t0, t1;
    real   got;

    initial begin
        repeat (20) @(posedge clk);
        reset = 1'b0;
        repeat (10) @(posedge clk);

        $display("ce_generator: %s, chipset %0.6f MHz", WHICH, CLK_MHZ);

        for (int i = 0; i < 4; i++) begin
            // Load the index the way core_top does, on biu_done.
            sel  = 2'(i);
            @(posedge clk); load = 1'b1;
            @(posedge clk); load = 1'b0;
            repeat (200) @(posedge clk);      // let the accumulator settle

            count = 0;
            t0 = $time;
            while (count < 20000) begin
                @(posedge clk);
                if (ce_pos) count++;
            end
            t1 = $time;
            // $time returns the TIMEUNIT (1 ns), not the precision -- %0t
            // prints picoseconds, the integer does not, and reading it as ps
            // put every measurement out by exactly 1000. 20000 edges over
            // dt ns is 2e7/dt MHz.
            got = (20000.0 * 1.0e3) / real'(t1 - t0);

            if (got < want[i] * (1.0 - TOL) || got > want[i] * (1.0 + TOL)) begin
                $display("FAIL index %0d: %0.6f MHz, want %0.6f", i, got, want[i]);
                errors++;
            end else begin
                $display("ok   index %0d: %0.6f MHz (want %0.6f, err %0.4f%%)",
                         i, got, want[i], 100.0 * (got - want[i]) / want[i]);
            end
        end

        if (errors == 0) $display("PASS tb_ce_rates");
        else             $display("FAILED tb_ce_rates: %0d", errors);
        $finish;
    end

endmodule

`default_nettype wire
