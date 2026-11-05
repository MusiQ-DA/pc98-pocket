//
// tb_ce_rates -- what frequencies does ce_generator actually make?
//
// The speed table is four rational ratios against a 42.954545 MHz chipset
// clock, and "is index 1 really 9.8304 MHz?" is a measurement, not a
// reading. The build prices one CE as one CPU clock of a 286-class machine
// -- the bus engine (cpu_bus_bridge) runs the 286 Ts/Tc profile, so the CE
// train is the CPU clock itself, not a multiple of it. 92/201 is the
// 2.4576 MHz-family value the "286 10MHz" step targets; the 8 and 12 MHz
// steps have no exact ratio against this clock and take the nearest fits
// (75/201, 112/201), which is why their wants carry four decimals too.
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
        .ram_read_wait_cycle(rd_wait), .ram_write_wait_cycle(wr_wait), .vram_wait_en()
    );

    // What each index is meant to be. A posedge of the CPU pin clock per
    // measured posedge CE, so this is the CPU's clock rate.
    real want [4] = '{8.0139, 9.8304, 11.9674, 21.4773};
    localparam string WHICH = "PC-98 286-class, 1x CPU clocks";

    // 0.1 per cent: a phase accumulator cannot land exactly and does not need
    // to -- each want is the rate its ratio is built to land on (how far that
    // sits from the menu's nominal 8/10/12 MHz is a design choice, not an
    // error), and the tolerance is here to catch a wrong table entry.
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
