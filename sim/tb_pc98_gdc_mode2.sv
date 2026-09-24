//
// tb_pc98_gdc_mode2 -- the flip-flops behind port 0x6A, pinned to np2kai's
// gdc_o6a: bytes below 0x08 are the bit set/reset form, bytes at and above
// it are extended commands, and of those only 0x82-0x85 touch the clock
// field.
//
// What is checked:
//
//   * reset: mode2 = 0x00 (digital, three planes), gdc_clk = 0 (2.5MHz)
//   * the bit form: dat < 0x08, bit = 1 << ((dat >> 1) & 3), value in dat[0]
//   * the clock commands: 0x82/0x83 move gdc_clk[0], 0x84/0x85 gdc_clk[1] --
//     3 is the "5MHz" field np2kai's renderers read as byte pitch, and the
//     BIOS's INT 18h high-res setup lands on it via `gdc.clock |= 3`
//   * the OTHER extended bytes (0x20 analog ext, 0x40/0x41 plasma, 0x68/0x69
//     the 256-colour pair, and the undefined 0x86) touch neither register
//   * a bit write must not disturb the clock field and vice versa
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_gdc_mode2;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic       wr  = 1'b0;
    logic [7:0] d   = 8'h00;
    logic [7:0] mode2;
    logic [1:0] gdc_clk;
    wire        analog;

    pc98_gdc_mode2 dut (
        .clk(clk), .rst(rst),
        .wr(wr), .d(d),
        .analog_capable(1'b1),
        .mode2(mode2), .gdc_clk(gdc_clk), .analog(analog)
    );

    int errors = 0;

    task automatic out6a(input logic [7:0] byte_,
                         input logic [7:0] want_mode2,
                         input logic [1:0] want_clk);
        begin
            @(negedge clk);
            wr = 1'b1; d = byte_;
            @(negedge clk);
            wr = 1'b0;
            @(negedge clk);
            $display("  OUT 6Ah,%02h  mode2=%02h clk=%b", byte_, mode2, gdc_clk);
            if (mode2 !== want_mode2 || gdc_clk !== want_clk) begin
                $display("  FAIL mode2 %02h want %02h, clk %b want %b",
                         mode2, want_mode2, gdc_clk, want_clk);
                errors++;
            end
        end
    endtask

    initial begin
        $display("=== GDC mode flip-flops 2 (port 0x6A) ===");

        repeat (2) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        $display("  reset: mode2=%02h clk=%b", mode2, gdc_clk);
        if (mode2 !== 8'h00 || gdc_clk !== 2'b00) begin
            $display("  FAIL reset"); errors++;
        end

        // The bit set/reset form first, so a dirty mode2 proves the clock
        // commands leave it alone.
        out6a(8'h01, 8'h01, 2'b00);                     // set bit 0 (analog)
        if (!analog) begin $display("  FAIL analog"); errors++; end
        out6a(8'h07, 8'h09, 2'b00);                     // set bit 3
        out6a(8'h05, 8'h0D, 2'b00);                     // set bit 2 -> EGC pair

        // The clock commands: d[2] picks the bit, d[0] the value.
        out6a(8'h83, 8'h0D, 2'b01);                     // set clock bit 0
        out6a(8'h85, 8'h0D, 2'b11);                     // set bit 1 -> 5MHz
        out6a(8'h82, 8'h0D, 2'b10);                     // clear bit 0
        out6a(8'h84, 8'h0D, 2'b00);                     // clear bit 1

        // The other extended bytes are not the clock field.
        out6a(8'h20, 8'h0D, 2'b00);                     // analog extension
        out6a(8'h40, 8'h0D, 2'b00);                     // plasma off
        out6a(8'h41, 8'h0D, 2'b00);                     // plasma on
        out6a(8'h68, 8'h0D, 2'b00);                     // 256-colour ext
        out6a(8'h86, 8'h0D, 2'b00);                     // undefined
        out6a(8'h80, 8'h0D, 2'b00);                     // plasma, high bit set

        // And the bit form still works -- and leaves the clock alone.
        out6a(8'h83, 8'h0D, 2'b01);
        out6a(8'h02, 8'h0D, 2'b01);                     // clear bit 1
        out6a(8'h85, 8'h0D, 2'b11);
        out6a(8'h06, 8'h05, 2'b11);                     // clear bit 3

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #100_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
