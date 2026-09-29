// tb_fdc_4be -- the 0x4BE 3-mode density register.
//
// np21w io/fdc.c's fdc_o4be / fdc_i4be: a write names a drive in bits[6:5]
// and a density in bit0 under the bit4 strobe; a read returns the stored
// density for whichever drive the register last named, | 0xFE. This is the
// hardware a "3-mode" (1.44 MB-capable) drive adapter adds to a PC-98.
`timescale 1ns/1ps
`default_nettype none

module tb_fdc_4be;
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic       sel_mode144 = 1'b0;
    logic       wr_stb = 1'b0;
    logic [7:0] wr_data = 8'h00;
    wire  [7:0] reg144;

    pc98_fdc_glue dut (
        .clk(clk), .rst(rst),
        .sel_stat(1'b0), .sel_data(1'b0), .sel_ctrl(1'b0), .sel_mode(1'b0),
        .sel_mode144(sel_mode144), .port_2dd(1'b0),
        .wr_stb(wr_stb), .wr_data(wr_data), .rd_stb(1'b0),
        .fd_addr(), .fd_write(), .fd_read(), .fd_wdata(),
        .fd_irq(1'b0), .fd_busy(1'b0),
        .ctrl_readback(), .mode_readback(), .reg144_readback(reg144),
        .group_live(), .irq_2hd(), .irq_2dd(), .dma_enable()
    );

    int errors = 0;
    task automatic want(input string what, input [7:0] got, input [7:0] exp);
        if (got !== exp) begin
            errors++;
            $display("  FAIL %-44s got=%h want=%h", what, got, exp);
        end else
            $display("  ok   %-44s %h", what, got);
    endtask

    task automatic wr4be(input [7:0] v);
        sel_mode144 = 1'b1; wr_data = v;
        @(negedge clk); wr_stb = 1'b1;
        @(negedge clk); wr_stb = 1'b0; sel_mode144 = 1'b0;
        #1;
    endtask

    initial begin
        $display("=== 0x4BE 3-mode density register ===");
        repeat (3) @(posedge clk); rst = 1'b0;
        repeat (2) @(negedge clk);

        want("reset: drive 0 density reads 0", reg144, 8'hFE);

        // Select drive 0, mode 1: 0x10 strobe | drv 0<<5 | 1.
        wr4be(8'h11);
        want("drive 0 density latched to 1", reg144, 8'hFF);

        // Re-select drive 0 (no strobe) -- just names it for the read.
        wr4be(8'h00);
        want("drive 0 density still 1", reg144, 8'hFF);

        // Drive 1, mode 0: strobe | drv 1<<5 | 0 = 0x10|0x20 = 0x30.
        wr4be(8'h30);
        want("drive 1 density 0 (read names drv1)", reg144, 8'hFE);

        // Drive 1, mode 1: 0x10|0x20|0x01 = 0x31.
        wr4be(8'h31);
        want("drive 1 density 1", reg144, 8'hFF);

        // A write with no strobe bit (bit4=0) updates the read pointer only.
        wr4be(8'h00);   // reg144=0 -> reads drive 0 again
        want("drive 0 still 1 after reselect", reg144, 8'hFF);

        // Drive 2: never written -> 0.
        wr4be(8'h40);   // reg144=0x40 -> sel = (0x40>>5)&3 = 2
        want("drive 2 density untouched 0", reg144, 8'hFE);

        if (errors == 0) $display("PASS tb_fdc_4be");
        else             $display("FAILED tb_fdc_4be: %0d", errors);
        $finish;
    end
    initial begin #20_000_000; $display("FAILED tb_fdc_4be: timeout"); $finish; end
endmodule
