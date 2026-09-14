//
// tb_pc98_fdc_glue -- the PC-98 FDC ports really do land on floppy.v's file.
//
// The PERIPHERALS comment that has kept PC98_FDC_REAL switched off says what
// this is for: "Turning this on trades a known-good stub for an untested path;
// it wants a bench that gets there first." This is that bench for the mapping
// layer -- the part where a guess is silent and fatal, because floppy.v has no
// way to complain that its DOR never arrived.
//
// Checked against np2kai io/fdc.c (fdc_o94's three live bits) and floppy.v's
// own register decode.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_fdc_glue;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst = 1'b1;
    logic sel_stat = 1'b0, sel_data = 1'b0, sel_ctrl = 1'b0;
    logic wr_stb = 1'b0;
    logic [7:0] wr_data = 8'h00;

    wire [2:0] fd_addr;
    wire       fd_write;
    wire [7:0] fd_wdata;
    wire [7:0] ctrl_readback;

    pc98_fdc_glue dut (
        .clk(clk), .rst(rst),
        .sel_stat(sel_stat), .sel_data(sel_data), .sel_ctrl(sel_ctrl),
        .wr_stb(wr_stb), .wr_data(wr_data),
        .fd_addr(fd_addr), .fd_write(fd_write), .fd_wdata(fd_wdata),
        .ctrl_readback(ctrl_readback)
    );

    int errors = 0;
    task automatic want(input string what, input [7:0] got, input [7:0] exp);
        if (got !== exp) begin
            $display("  FAIL %-38s %02h (want %02h)", what, got, exp);
            errors++;
        end else
            $display("  ok   %-38s %02h", what, got);
    endtask
    task automatic want1(input string what, input logic got, input logic exp);
        if (got !== exp) begin
            $display("  FAIL %-38s %0d (want %0d)", what, got, exp);
            errors++;
        end else
            $display("  ok   %-38s %0d", what, got);
    endtask

    // A guest write: the port is selected, wr_stb is the single cycle at the
    // end with the data already settled.
    // Drive the strobe and STOP inside it, so the caller can look at what the
    // glue is presenting to floppy.v during the write. wr_end() finishes it.
    task automatic wr_begin(input int which, input [7:0] v);
        sel_stat = (which == 0); sel_data = (which == 1); sel_ctrl = (which == 2);
        wr_data = v;
        @(negedge clk);
        wr_stb = 1'b1;
        #1;
    endtask

    task automatic wr_end;
        @(negedge clk);
        wr_stb = 1'b0;
        sel_stat = 0; sel_data = 0; sel_ctrl = 0;
        #1;
    endtask

    task automatic wr(input int which, input [7:0] v);
        wr_begin(which, v);
        wr_end();
    endtask

    initial begin
        $display("=== PC-98 FDC port mapping ===");
        repeat (3) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // ---- 0x90 is the MSR: floppy.v register 4, and never a write -------
        sel_stat = 1'b1; sel_data = 1'b0; sel_ctrl = 1'b0;
        #1;
        want("0x90 selects reg 4 (MSR)", {5'd0, fd_addr}, 8'd4);
        want1("and does not write", fd_write, 1'b0);
        sel_stat = 1'b0;

        // ---- 0x92 is the FIFO: register 5, both directions -----------------
        sel_data = 1'b1;
        #1;
        want("0x92 selects reg 5 (FIFO)", {5'd0, fd_addr}, 8'd5);
        sel_data = 1'b0;

        wr_begin(1, 8'h03);   // a SPECIFY opcode going into the FIFO
        want("FIFO write carries the byte", fd_wdata, 8'h03);
        want("FIFO write addresses reg 5", {5'd0, fd_addr}, 8'd5);
        want1("and asserts a write", fd_write, 1'b1);
        wr_end();

        // ---- 0x94 becomes a DOR write at register 2 ------------------------
        // The bits floppy.v needs that a PC-98 does not supply are constants:
        // enable (2) and both motors (4,5). Interrupt enable comes from the
        // guest's bit 3. Drive select stays 0 -- the uPD765 command's unit
        // field is what really picks the drive.
        wr_begin(2, 8'h08);
        want("0x94 write addresses reg 2 (DOR)", {5'd0, fd_addr}, 8'd2);
        want1("and asserts a write", fd_write, 1'b1);
        want("DOR: enable+motors+irq", fd_wdata, 8'h3C);
        wr_end();
        want("control port reads back", ctrl_readback, 8'h08);

        // Interrupt enable off: the same constants, bit 3 clear.
        wr_begin(2, 8'h00);
        want("DOR with irq disabled", fd_wdata, 8'h34);
        wr_end();

        // ---- bit 7 going 0 -> 1 pulses a reset -----------------------------
        // np2's fdc_o94 resets on the EDGE, not the level, so a guest that
        // leaves the bit set does not hold the controller down. floppy.v takes
        // a reset at register 4 with bit 7 set. reset_pending is raised by the
        // edge that ends the write, so the pulse is the cycle AFTER it -- look
        // there, not at the write itself.
        wr(2, 8'h80);
        want("reset goes to reg 4", {5'd0, fd_addr}, 8'd4);
        want("reset writes bit 7", fd_wdata, 8'h80);
        want1("reset asserts a write", fd_write, 1'b1);

        // It lasts one cycle and then the mapping is normal again.
        @(negedge clk); #1;
        want1("reset is one cycle", fd_write, 1'b0);

        // Writing again with bit 7 already set must NOT reset.
        wr(2, 8'h88);
        want1("no second reset while bit 7 stays set", fd_write, 1'b0);
        want("control port reads back the new value", ctrl_readback, 8'h88);

        // Dropping it and raising it again does.
        wr(2, 8'h08);
        wr(2, 8'h88);
        want("a fresh 0 -> 1 resets again", fd_wdata, 8'h80);
        want1("and writes", fd_write, 1'b1);

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("PASS tb_pc98_fdc_glue");
        else             $display("FAILED tb_pc98_fdc_glue: %0d", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAILED tb_pc98_fdc_glue: timeout");
        $finish;
    end

endmodule

`default_nettype wire
