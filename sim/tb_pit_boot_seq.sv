//
// tb_pit_boot_seq -- the PC-98 interval timer, end to end, at the machine's
// own clocking.
//
// What this proves, phase by phase:
//   A. The KF8253's mode-3 logic toggles forever at exactly N/2 counts --
//      the "mode 3 stops after ~5 edges" diagnosis was mode 0 doing its
//      one-shot job, not a counter bug (sim/tb_kf8253_mode3.sv measures the
//      same thing standalone).
//   B. The ITF's own programming (F854E: ctrl 0x30, LSB/MSB 0x00 -- mode 0,
//      count 65536) gives exactly one terminal-count edge 26.7 ms later at
//      the PC-98 2.4576 MHz PIT clock, then silence: correct one-shot mode 0.
//   C. The FD80 POST's programming (FDE20: ctrl 0x36, LSB 0x00, MSB 0x60 --
//      mode 3, count 0x6000 = 100 Hz) toggles continuously, one rising edge
//      per 10 ms period, which is one IRQ0 per period on an edge-triggered
//      PIC -- np2's NEVENT_ITIMER cadence.
//   D. np2's quirk (io/pit.c pit_o71/pit_o77): a completed channel-0 write
//      clears the master PIC's IRR bit 0, so a request latched before a
//      reprogram cannot be delivered after it.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pit_boot_seq;

    logic clk_chipset = 1'b0;
    always #11.641 clk_chipset = ~clk_chipset;     // 42.954545 MHz

    logic reset = 1'b1;

    // The PC-98 PIT input clock, generated the way Peripherals.sv now does:
    // phase-accumulate 4.9152 MHz toggles against 42.954545 MHz, so the
    // falling edges the chip counts land at exactly 2.4576 MHz on average.
    logic timer_clock = 1'b0;
    logic [31:0] pit_clk_phase = 32'd0;
    localparam logic [31:0] PIT_CLK_TOGGLE_HZ = 32'd4_915_200;
    localparam logic [31:0] CHIPSET_HZ        = 32'd42_954_545;
    always_ff @(posedge clk_chipset) begin
        if ({1'b0, pit_clk_phase} + PIT_CLK_TOGGLE_HZ >= CHIPSET_HZ) begin
            pit_clk_phase <= pit_clk_phase + PIT_CLK_TOGGLE_HZ - CHIPSET_HZ;
            timer_clock   <= ~timer_clock;
        end
        else
            pit_clk_phase <= pit_clk_phase + PIT_CLK_TOGGLE_HZ;
    end

    // clock sanity: 2000 falling edges must span 2000/2457600 s +- 0.5%
    int   fall_n = 0;
    realtime t_fall0 = 0.0, t_fall_last = 0.0;
    logic timer_clock_q = 1'b0;
    always_ff @(posedge clk_chipset) begin
        timer_clock_q <= timer_clock;
        if (timer_clock_q & ~timer_clock) begin
            if (fall_n == 0) t_fall0 = $realtime;
            fall_n = fall_n + 1;
            t_fall_last = $realtime;
        end
    end

    // bus, driven the way the boot bench's 8288 does
    logic        chip_select_n = 1'b1;
    logic        read_enable_n = 1'b1;
    logic        write_enable_n = 1'b1;
    logic [1:0]  address = 2'b00;
    logic [7:0]  data_bus_in = 8'h00;
    wire  [7:0]  data_bus_out;
    wire out0, out1, out2;

    KF8253 u_pit (
        .clock            (clk_chipset),
        .reset            (reset),
        .chip_select_n    (chip_select_n),
        .read_enable_n    (read_enable_n),
        .write_enable_n   (write_enable_n),
        .address          (address),
        .data_bus_in      (data_bus_in),
        .data_bus_out     (data_bus_out),
        .counter_0_clock  (timer_clock), .counter_0_gate (1'b1),
        .counter_0_out    (out0),
        .counter_1_clock  (timer_clock), .counter_1_gate (1'b1),
        .counter_1_out    (out1),
        .counter_2_clock  (timer_clock), .counter_2_gate (1'b1),
        .counter_2_out    (out2)
    );

    // A master PIC watching the timer pin, for the IRR0-quirk phase
    logic inta_n = 1'b1;
    wire  pic_int;
    KF8259 u_pic (
        .clock            (clk_chipset),
        .reset            (reset),
        .chip_select_n    (1'b1),          // never bus-selected: IRR only
        .read_enable_n    (1'b1),
        .write_enable_n   (1'b1),
        .address          (1'b0),
        .data_bus_in      (8'h00),
        .data_bus_out     (),
        .cascade_in       (3'b000),
        .cascade_out      (),
        .cascade_io       (),
        .slave_program_n  (1'b1),
        .interrupt_acknowledge_n (inta_n),
        .interrupt_to_cpu (pic_int),
        .external_irr_clear ({7'b0, pit0_write_clears_irr0}),
        .interrupt_request({7'b0, out0})
    );

    // The np2 quirk decode, same as Peripherals.sv / the boot bench
    logic pit_write_cycle_q = 1'b0;
    wire  pit_write_cycle   = ~chip_select_n & ~write_enable_n;
    wire  pit_write_done    = pit_write_cycle_q & ~pit_write_cycle;
    wire  pit0_write_clears_irr0 = pit_write_done &
           (  (address == 2'b00)
            | ((address == 2'b11) & (data_bus_in[7:6] == 2'b00)
                                  & (data_bus_in[5:4] != 2'b00)));
    always_ff @(posedge clk_chipset)
        pit_write_cycle_q <= pit_write_cycle;

    task automatic pit_write(input logic [1:0] a, input logic [7:0] d);
        begin
            @(negedge clk_chipset);
            address        = a;
            data_bus_in    = d;
            chip_select_n  = 1'b0;
            write_enable_n = 1'b0;
            repeat (4) @(negedge clk_chipset);
            write_enable_n = 1'b1;
            @(negedge clk_chipset);
            chip_select_n  = 1'b1;
            repeat (8) @(negedge clk_chipset);
        end
    endtask

    // output edge census, with half-period measurement
    int      edges = 0;
    logic    out0_d = 1'b0;
    realtime t_edge = 0.0, half_ns;
    int      errors = 0;
    always_ff @(posedge clk_chipset) begin
        out0_d <= out0;
        if (out0 != out0_d) begin
            half_ns = $realtime - t_edge;   // ns
            edges = edges + 1;
            if (edges <= 12)
                $display("%12t  EDGE #%0d out=%b  half=%.3f us  count=%04X",
                         $realtime, edges, out0, half_ns / 1000.0,
                         u_pit.u_KF8253_Counter_0.count[15:0]);
            t_edge = $realtime;
        end
    end


    initial begin
        repeat (40) @(negedge clk_chipset);
        reset = 1'b0;

        // clock sanity first
        repeat (2000) @(posedge clk_chipset);
        begin : clkcheck
            // $realtime differences are in ns (timescale 1ns); 2000 chipset
            // clocks is ~46.6 us, in which ~114 PIT falling edges fit.
            real span_ns = t_fall_last - t_fall0;
            real rate = (fall_n - 1) * 1e9 / span_ns;
            $display("PIT clock measured: %0d falls in %.1f us -> %.0f Hz",
                     fall_n - 1, span_ns / 1000.0, rate);
            if (rate < 2457600.0 * 0.995 || rate > 2457600.0 * 1.005) begin
                $display("*** FAIL: PIT clock off rate");
                errors = errors + 1;
            end
        end

        // ---- B: the ITF's programming: mode 0, count 65536 ----------------
        $display("\n=== B: ITF F854E sequence: ctrl 0x30, 0x00, 0x00 (mode 0, 65536) ===");
        edges = 0;
        pit_write(2'b11, 8'h30);
        pit_write(2'b00, 8'h00);
        pit_write(2'b00, 8'h00);
        $display("... mode 0 terminal count due in %.1f ms (65536 @ 2.4576 MHz)",
                 65536.0 / 2457600.0 * 1000.0);
        repeat (5000000) @(posedge clk_chipset);      // ~116 ms
        // expect: the OUT drop at the control write, one TC rise at ~26.7 ms,
        // then nothing (mode 0 latches high)
        if (!(edges == 2)) begin
            $display("*** FAIL: B expected exactly 2 edges (drop + one TC), got %0d", edges);
            errors = errors + 1;
        end else
            $display("--- B: mode 0 one-shot correct: %0d edges in 116 ms", edges);

        // ---- C: the FD80 POST's programming: mode 3, count 0x6000 ----------
        $display("\n=== C: FD80 FDE20 sequence: ctrl 0x36, 0x00, 0x60 (mode 3, 0x6000 = 100 Hz) ===");
        edges = 0;
        pit_write(2'b11, 8'h36);
        pit_write(2'b00, 8'h00);
        pit_write(2'b00, 8'h60);
        repeat (15000000) @(posedge clk_chipset);     // ~350 ms -> ~35 edges
        // every half-period must be 0x3000 counts = 5.000 ms (+-0.2 ms)
        if (edges < 30) begin
            $display("*** FAIL: C expected a continuous square wave (>=30 edges), got %0d", edges);
            errors = errors + 1;
        end else
            $display("--- C: mode 3 continuous: %0d edges in 350 ms (100 Hz period)", edges);

        // ---- D: the np2 IRR0 quirk ------------------------------------------
        $display("\n=== D: IRR0 set on the rising edge, cleared by a ch0 write ===");
        wait (u_pic.interrupt_request_register[0] == 1'b1);
        $display("%10t  IRR0 set while the square wave runs (out=%b)", $realtime, out0);
        pit_write(2'b00, 8'h60);                      // ch0 count write
        repeat (10) @(posedge clk_chipset);
        if (u_pic.interrupt_request_register[0] == 1'b0)
            $display("--- D: ch0 write cleared IRR0, as np2 does");
        else begin
            $display("*** FAIL: D IRR0 survived a channel-0 write");
            errors = errors + 1;
        end

        // and a control-word write for ch0 clears it too (np2 pit_o77)
        wait (u_pic.interrupt_request_register[0] == 1'b1);
        pit_write(2'b11, 8'h36);
        repeat (10) @(posedge clk_chipset);
        if (u_pic.interrupt_request_register[0] == 1'b0)
            $display("--- D: ch0 control word cleared IRR0 too");
        else begin
            $display("*** FAIL: D IRR0 survived a ch0 control write");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("\n*** ALL PHASES PASS ***");
        else
            $display("\n*** %0d FAILURES ***", errors);
        $finish;
    end

endmodule

`default_nettype wire
