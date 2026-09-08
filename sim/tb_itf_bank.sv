//
// tb_itf_bank -- the ROM window at F8000-FFFFF, and who switches it.
//
// A PC-98 shows the ITF there at power-on and the system BIOS afterwards. The
// ITF does the switch itself, through port 0x043D: 0x10 selects the ITF, 0x12
// selects the BIOS. The real instructions are in the ROM (BA 3D 04 B0 12 EE at
// F8A98), and the hand-over at F988D jumps to a stub in RAM to do it, because
// the ROM changes under the instruction that switches it.
//
// Two things have to hold and neither is obvious:
//
//   * the window is EXACTLY F8000-FFFFF. One bit too few in the compare and
//     E8000 moves with it, taking the BIOS's lower 64 KB out from under the
//     guest.
//   * a transient must not switch it. Address and command lines do not change
//     together, so an I/O write to another port sweeps through 0x043D for a
//     cycle on its way -- the same transient that logged POST codes the BIOS
//     never wrote. Switching the ROM out from under the CPU on a glitch is
//     considerably worse than a bad readout.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_itf_bank;

    logic clk = 0, rst = 1;
    always #11.64 clk = ~clk;

    logic [19:0] address    = 20'h0;
    logic  [7:0] cpu_data   = 8'h00;
    logic        io_write_n = 1'b1;
    logic        aen        = 1'b0;   // address_enable_n

    // ---- the logic under test, written as core_top writes it ----------------
    reg  itf_bank = 1'b1;
    reg  itf_io_q, itf_io_qq;
    reg  [7:0] itf_io_data;
    wire itf_port_write = ~io_write_n & ~aen & (address[15:0] == 16'h043D);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            itf_bank    <= 1'b1;
            itf_io_q    <= 1'b0;
            itf_io_qq   <= 1'b0;
            itf_io_data <= 8'h00;
        end else begin
            itf_io_q  <= itf_port_write;
            itf_io_qq <= itf_io_q;
            if (itf_port_write) itf_io_data <= cpu_data;
            if (itf_io_q && itf_io_qq && ~itf_port_write) begin
                if      (itf_io_data == 8'h10) itf_bank <= 1'b1;
                else if (itf_io_data == 8'h12) itf_bank <= 1'b0;
            end
        end
    end

    // RAM.sv's window select, likewise.
    wire [19:0] probe_addr;
    wire shadow_sel = itf_bank & (probe_addr[19:15] == 5'b11111);

    logic [19:0] probe_q = 20'h0;
    assign probe_addr = probe_q;

    int errors = 0;

    // out 0x043D,al the way the bus does it: command and address up first, data
    // settling partway through.
    task automatic out43d(input logic [7:0] v);
        address = 20'h0043D;
        cpu_data = 8'hC3;             // stale bus content
        io_write_n = 1'b0;
        repeat (2) @(posedge clk);
        cpu_data = v;
        repeat (3) @(posedge clk);
        io_write_n = 1'b1;
        address = 20'h0;
        repeat (4) @(posedge clk);
    endtask

    // An I/O write to a different port whose address sweeps through 0x043D for
    // one cycle on the way.
    task automatic out_glitch(input logic [7:0] v);
        io_write_n = 1'b0;
        address = 20'h0043D;
        cpu_data = v;
        @(posedge clk);
        address = 20'h0043F;          // settles on the real port
        repeat (4) @(posedge clk);
        io_write_n = 1'b1;
        address = 20'h0;
        repeat (4) @(posedge clk);
    endtask

    task automatic check_window(input string what);
        // Every address that must be in the window, and the ones just outside.
        probe_q = 20'hF8000; @(posedge clk);
        if (shadow_sel !== itf_bank) begin
            $display("  FAIL %s: F8000 not in window", what); errors++; end
        probe_q = 20'hFFFFF; @(posedge clk);
        if (shadow_sel !== itf_bank) begin
            $display("  FAIL %s: FFFFF not in window", what); errors++; end
        probe_q = 20'hF7FFF; @(posedge clk);
        if (shadow_sel !== 1'b0) begin
            $display("  FAIL %s: F7FFF IS in window (one bit too few)", what);
            errors++; end
        probe_q = 20'hE8000; @(posedge clk);
        if (shadow_sel !== 1'b0) begin
            $display("  FAIL %s: E8000 IS in window -- BIOS low 64K shadowed",
                     what); errors++; end
        probe_q = 20'h00000; @(posedge clk);
        if (shadow_sel !== 1'b0) begin
            $display("  FAIL %s: low memory in window", what); errors++; end
    endtask

    initial begin
        $display("=== ITF bank ===");
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        // Power-on: the ITF must be what is mapped, or the reset vector at
        // FFFF0 is the BIOS's (EA 00 00 80 FD) and the ITF never runs.
        $display("  reset: itf_bank=%0d (want 1)", itf_bank);
        if (itf_bank !== 1'b1) begin $display("  FAIL reset default"); errors++; end
        check_window("at reset");

        // The hand-over.
        out43d(8'h12);
        $display("  after 0x12: itf_bank=%0d (want 0)", itf_bank);
        if (itf_bank !== 1'b0) begin $display("  FAIL 0x12 did not switch"); errors++; end
        check_window("after 0x12");

        // And back.
        out43d(8'h10);
        if (itf_bank !== 1'b1) begin $display("  FAIL 0x10 did not switch back"); errors++; end

        // A value that is neither must do nothing.
        out43d(8'h00);
        if (itf_bank !== 1'b1) begin
            $display("  FAIL an unrelated value moved the bank"); errors++; end

        // A one-cycle sweep through the port must do nothing, whatever it
        // carries.
        out43d(8'h12);                 // park it at BIOS first
        out_glitch(8'h10);
        $display("  after glitch carrying 0x10: itf_bank=%0d (want 0)", itf_bank);
        if (itf_bank !== 1'b0) begin
            $display("  FAIL a transient switched the ROM"); errors++; end

        // A DMA cycle with a memory address whose low bits look like the port.
        aen = 1'b1;
        address = 20'h3043D;
        cpu_data = 8'h10;
        io_write_n = 1'b0;
        repeat (6) @(posedge clk);
        io_write_n = 1'b1;
        address = 20'h0;
        aen = 1'b0;
        repeat (4) @(posedge clk);
        if (itf_bank !== 1'b0) begin
            $display("  FAIL a DMA cycle switched the ROM"); errors++; end
        $display("  DMA cycle ignored: itf_bank=%0d", itf_bank);

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
