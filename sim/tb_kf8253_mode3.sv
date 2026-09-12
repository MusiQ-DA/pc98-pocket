//
// tb_kf8253_mode3 -- does counter 0 in mode 3 toggle forever?
//
// The boot bench watched the KF8253's mode-3 output stop after a handful of
// edges.  This bench replays the exact programming sequences the machine
// issues, against the real chip model, and counts output transitions:
//
//   A. the bench's power-on state: counter 0 wakes in mode 3 (RESET_MODE),
//      RL=MSB, and the "reload" is two MSB writes of 0x80 -> 0x8000.
//   B. the UX BIOS's real program sequence (FDE20): control word 0x36
//      (counter 0, LSB+MSB, mode 3), then LSB 0x00, MSB 0x60 -> 0x6000.
//   C. B applied on top of a counter that is already running (reprogram in
//      flight, the state the boot leaves the chip in).
//
// Each phase runs long enough for many half-periods; a healthy mode-3
// counter toggles every N/2 counter clocks and never stops.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_kf8253_mode3;

    // system clock for the chip model (42.954545 MHz like the bench)
    logic clk = 1'b0;
    always #11.641 clk = ~clk;

    // the PIT input clock: 42.954545/18/2 = 1.193 MHz, exactly the bench's
    // timer_clock (peripheral_ce toggling a flip-flop)
    logic timer_clock = 1'b0;
    int    ce_div = 0;
    always_ff @(posedge clk) begin
        ce_div <= ce_div + 1;
        if (ce_div >= 17) begin
            ce_div <= 0;
            timer_clock <= ~timer_clock;
        end
    end

    logic reset = 1'b1;

    // bus, driven the way the boot bench's 8288 does
    logic        chip_select_n = 1'b1;
    logic        read_enable_n = 1'b1;
    logic        write_enable_n = 1'b1;
    logic [1:0]  address = 2'b00;
    logic [7:0]  data_bus_in = 8'h00;
    wire  [7:0]  data_bus_out;

    wire out0, out1, out2;

    KF8253 u_pit (
        .clock            (clk),
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

    task automatic pit_write(input logic [1:0] a, input logic [7:0] d);
        begin
            @(negedge clk);
            address       = a;
            data_bus_in   = d;
            chip_select_n = 1'b0;
            write_enable_n = 1'b0;
            repeat (4) @(negedge clk);
            write_enable_n = 1'b1;      // write latches on WE rising edge
            @(negedge clk);
            chip_select_n = 1'b1;
            repeat (4) @(negedge clk);
        end
    endtask

    // output edge census
    int      edges = 0;
    logic    out0_d = 1'b0;
    realtime last_edge_t = 0.0;
    realtime gap;
    always_ff @(posedge clk) begin
        out0_d <= out0;
        if (out0 != out0_d) begin
            gap = $realtime - last_edge_t;
            last_edge_t = $realtime;
            edges = edges + 1;
            $display("%t  EDGE #%0d  out=%b  gap=%0t ns  count=%05X  mode=%0d rl=%b start=%b",
                     $realtime, edges, out0, gap,
                     u_pit.u_KF8253_Counter_0.count[15:0],
                     u_pit.u_KF8253_Counter_0.select_mode,
                     u_pit.u_KF8253_Counter_0.select_read_write,
                     u_pit.u_KF8253_Counter_0.start_counting);
        end
    end

    int expect_edges;

    task automatic run_and_check(input int ms, input string name);
        begin
            edges = 0;
            repeat (ms * 50000) @(posedge clk);   // 1 ms = 42955 clocks
            $display("--- %s: %0d edges in %0d ms (last count %05X, mode %0d)\n",
                     name, edges, ms,
                     u_pit.u_KF8253_Counter_0.count[15:0],
                     u_pit.u_KF8253_Counter_0.select_mode);
            if (edges == 0)
                $display("*** FAIL: %s produced no output edges", name);
        end
    endtask

    initial begin
        repeat (20) @(negedge clk);
        reset = 1'b0;
        repeat (20) @(negedge clk);

        $display("\n=== A: power-on mode 3, RL=MSB, writes 0x80,0x80 -> 0x8000 ===");
        pit_write(2'b00, 8'h80);
        pit_write(2'b00, 8'h80);
        run_and_check(300, "A");        // 0x8000/2 = 16384 clk = 13.72 ms/half

        $display("=== B: UX BIOS sequence: ctrl 0x36, LSB 0x00, MSB 0x60 ===");
        pit_write(2'b11, 8'h36);
        pit_write(2'b00, 8'h00);
        pit_write(2'b00, 8'h60);
        run_and_check(300, "B");        // 0x6000/2 = 12288 clk = 10.29 ms/half

        $display("=== C: same again while already counting ===");
        pit_write(2'b11, 8'h36);
        pit_write(2'b00, 8'h33);
        pit_write(2'b00, 8'h0D);        // 0x0D33: odd value, 1.72 ms/half
        run_and_check(60,  "C");

        $display("=== D: odd reload sanity, full LSB+MSB path ===");
        pit_write(2'b11, 8'h36);
        pit_write(2'b00, 8'hFF);
        pit_write(2'b00, 8'h01);        // 0x01FF odd
        run_and_check(20,  "D");        // 0x1FF/2 = 255 clk = 213 us/half

        $display("=== done ===");
        $finish;
    end

endmodule

`default_nettype wire
