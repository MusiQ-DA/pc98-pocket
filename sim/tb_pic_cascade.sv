//
// tb_pic_cascade -- the slave-PIC cascade, the one path the boot bench
// never exercised: no INTA ever came through it, and the machine is now
// parked in a loop waiting for a flag that only a slave interrupt raises.
//
// Two KF8259s, initialized exactly the way the VM BIOS initializes them
// (ICW1-4: master 0x11/0x08/0x80/0x1D, slave 0x11/0x10/0x07/0x09 -- the
// slave hangs off the master's IRQ7, slave ID 7). Then one pulse on the
// slave's IRQ2 (the 0xCC drive timer's line). What should happen:
//
//   slave IRR bit2 -> slave INT -> master IRQ7 -> master INT -> CPU INTA
//   master cascade_out = 7 -> slave sees its ID -> slave drives vector
//   0x12 (slave ICW2 0x10 + IRQ2) on the data bus during the second pulse
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
`default_nettype none
`timescale 1ns/1ps

module tb_pic_cascade;

    logic clk = 1'b0;
    always #10 clk = ~clk;          // 50 MHz, convenient and irrelevant
    logic reset = 1'b1;
    logic inta_n = 1'b1;

    // A fake CPU: sees INT, answers with TWO INTA pulses, latches the bus.
    wire         pic1_int = pic1_int_raw;
    logic [7:0]  bus_din;
    logic [7:0]  vector;
    int          inta_pulses = 0;

    logic [7:0] pic1_dout, pic2_dout;
    logic       pic1_int_raw, pic2_int;
    logic       pic1_dio, pic2_dio;
    logic [2:0] cascade_out;

    logic       irq2_pulse;          // the drive timer's line

    KF8259 u_master (
        .clock(clk), .reset(reset),
        .chip_select_n(pic1_cs),      // not selected: only INTA matters here
        .read_enable_n(1'b1), .write_enable_n(pic1_wr),
        .address(pic1_a0),
        .data_bus_in(pic1_din),
        .data_bus_out(pic1_dout),
        .data_bus_io(pic1_dio),
        .cascade_in(3'b000),
        .cascade_out(cascade_out),
        .cascade_io(),
        .slave_program_n(1'b1),
        .interrupt_acknowledge_n(inta_n),
        .interrupt_to_cpu(pic1_int_raw),
        .interrupt_request({pic2_int, 7'b0})   // slave on IRQ7, per ICW3
    );

    KF8259 u_slave (
        .clock(clk), .reset(reset),
        .chip_select_n(pic2_cs),
        .read_enable_n(1'b1), .write_enable_n(pic2_wr),
        .address(pic2_a0),
        .data_bus_in(pic2_din),
        .data_bus_out(pic2_dout),
        .data_bus_io(pic2_dio),
        .cascade_in(cascade_out),
        .cascade_out(),
        .cascade_io(),
        .slave_program_n(1'b0),
        .interrupt_acknowledge_n(inta_n),
        .interrupt_to_cpu(pic2_int),
        .interrupt_request({5'b0, irq2_pulse, 2'b0})  // IRQ2 = XTMASK
    );

    // The INTA mux exactly as PERIPHERALS wires it: whoever is driving
    // (data_bus_io low) puts the byte on the bus.
    assign bus_din = (~pic2_dio) ? pic2_dout : pic1_dout;

    // Fake CPU INTA generation: two pulses, 10 clocks apart, then done.
    logic started = 1'b0;
    int    pulse_cnt = 0;
    always_ff @(posedge clk) begin
        if (!reset && pic1_int && !started) started <= 1'b1;
        if (started && inta_pulses < 2) begin
            inta_n <= (pulse_cnt < 6) ? 1'b0 : 1'b1;
            if (pulse_cnt == 2) vector <= bus_din;  // second pulse's byte
            if (pulse_cnt == 9) begin
                inta_pulses <= inta_pulses + 1;
                pulse_cnt <= 0;
            end else
                pulse_cnt <= pulse_cnt + 1;
        end
    end

    // Program both chips the BIOS way: drives the (now logic) bus inputs.
    logic       pic1_cs = 1'b1, pic1_wr = 1'b1, pic1_a0 = 1'b0;
    logic [7:0] pic1_din = 8'h00;
    logic       pic2_cs = 1'b1, pic2_wr = 1'b1, pic2_a0 = 1'b0;
    logic [7:0] pic2_din = 8'h00;
    task pic_write(input logic slave, input logic a0, input logic [7:0] d);
    begin
        if (!slave) begin
            pic1_cs = 1'b0; pic1_a0 = a0; pic1_din = d; pic1_wr = 1'b0;
            @(posedge clk);
            pic1_wr = 1'b1; pic1_cs = 1'b1;
        end else begin
            pic2_cs = 1'b0; pic2_a0 = a0; pic2_din = d; pic2_wr = 1'b0;
            @(posedge clk);
            pic2_wr = 1'b1; pic2_cs = 1'b1;
        end
        repeat (2) @(posedge clk);
    end
    endtask

    int errors = 0;
    logic slave_int_seen = 1'b0, master_int_seen = 1'b0;
    initial begin
        $dumpfile("tb_pic_cascade.vcd");
        $dumpvars(0, tb_pic_cascade);
        repeat (5) @(posedge clk);
        reset = 1'b0;
        repeat (5) @(posedge clk);

        // ICWs, exactly as FDA2F-FDA4D writes them.
        pic_write(0, 0, 8'h11);      // master ICW1: edge, cascade, ICW4
        pic_write(0, 1, 8'h08);      // ICW2: vectors 08-0F
        pic_write(0, 1, 8'h80);      // ICW3: slave on IRQ7
        pic_write(0, 1, 8'h1D);      // ICW4
        pic_write(1, 0, 8'h11);      // slave ICW1
        pic_write(1, 1, 8'h10);      // ICW2: vectors 10-17
        pic_write(1, 1, 8'h07);      // ICW3: my ID is 7
        pic_write(1, 1, 8'h09);      // ICW4
        $display("[%0t] programmed; master int=%b slave int=%b",
                 $time, pic1_int_raw, pic2_int);

        // Fire the drive timer's line: one clean rising edge.
        irq2_pulse = 1'b0;
        repeat (3) @(posedge clk);
        irq2_pulse = 1'b1;
        @(posedge clk);
        irq2_pulse = 1'b0;
        repeat (5) @(posedge clk);
        slave_int_seen = pic2_int;
        master_int_seen = pic1_int_raw;
        $display("[%0t] IRQ2 pulsed; slave IRR=%02X slave int=%b master int=%b",
                 $time, u_slave.interrupt_request_register, slave_int_seen, master_int_seen);

        repeat (100) @(posedge clk);
        $display("[%0t] after 100 clk: inta_pulses=%0d vector=%02X",
                 $time, inta_pulses, vector);
        if (slave_int_seen !== 1'b1) begin
            $display("  FAIL: slave did not raise INT");
            errors++;
        end
        if (master_int_seen !== 1'b1) begin
            $display("  FAIL: master did not raise INT from the cascade line");
            errors++;
        end
        if (inta_pulses < 2) begin
            $display("  FAIL: fake CPU never completed two INTA pulses");
            errors++;
        end else if (vector !== 8'h12) begin
            $display("  FAIL: vector %02X, expected 12 (slave ICW2 0x10 + IRQ2)", vector);
            errors++;
        end else
            $display("  PASS: cascade delivered vector 12");

        $finish;
    end

endmodule

`default_nettype wire
