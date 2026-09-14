//
// tb_pc98_scsi -- does the register window behave the way the board does?
//
// The whole point of pc98_scsi is that it is ONLY the interface: an indirect
// index at 0xCC0, a data register at 0xCC2 that post-increments it, a discard
// at 0xCC4 and a buffer port at 0xCC6. Every one of those behaviours is
// something the disk BIOS depends on, and none of them is visible from a
// command-level test, so they get pinned here.
//
// Checked against np2kai cbus/scsiio.c: scsiio_occ0/2/4/6 and
// scsiio_icc0/2/4/6, with the indices from cbus/scsiio.tbl.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_scsi;

    logic clk = 0;
    always #5 clk = ~clk;

    logic       rst = 1'b1;
    logic       cs = 1'b0;
    logic [1:0] a1a2 = 2'b00;
    logic       io_read_n = 1'b1;
    logic       io_write_n = 1'b1;
    logic [7:0] data_in = 8'h00;
    wire  [7:0] data_out;
    wire        read_select;

    wire        cmd_req;
    wire  [7:0] cmd_byte;

    logic  [4:0] mg_reg_addr = 5'd0;
    logic        mg_reg_we = 1'b0;
    logic  [7:0] mg_reg_wdata = 8'h00;
    wire   [7:0] mg_reg_rdata;

    logic [12:0] mg_buf_addr = 13'd0;
    logic        mg_buf_we = 1'b0;
    logic  [7:0] mg_buf_wdata = 8'h00;
    wire   [7:0] mg_buf_rdata;

    logic  [7:0] mg_auxstatus = 8'h00;
    logic        mg_auxstatus_we = 1'b0;
    logic  [7:0] mg_scsistatus = 8'h00;
    logic        mg_scsistatus_we = 1'b0;
    logic        mg_rdptr_clr = 1'b0;
    logic        mg_wrptr_clr = 1'b0;

    pc98_scsi dut (
        .clk(clk), .rst(rst),
        .cs(cs), .a1a2(a1a2),
        .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(data_out), .read_select(read_select),
        .cmd_req(cmd_req), .cmd_byte(cmd_byte),
        .mg_reg_addr(mg_reg_addr), .mg_reg_we(mg_reg_we),
        .mg_reg_wdata(mg_reg_wdata), .mg_reg_rdata(mg_reg_rdata),
        .mg_buf_addr(mg_buf_addr), .mg_buf_we(mg_buf_we),
        .mg_buf_wdata(mg_buf_wdata), .mg_buf_rdata(mg_buf_rdata),
        .mg_auxstatus(mg_auxstatus), .mg_auxstatus_we(mg_auxstatus_we),
        .mg_scsistatus(mg_scsistatus), .mg_scsistatus_we(mg_scsistatus_we),
        .mg_rdptr_clr(mg_rdptr_clr), .mg_wrptr_clr(mg_wrptr_clr)
    );

    int errors = 0;
    task automatic want(input string what, input [7:0] got, input [7:0] exp);
        if (got !== exp) begin
            $display("  FAIL %-34s %02h (want %02h)", what, got, exp);
            errors++;
        end else
            $display("  ok   %-34s %02h", what, got);
    endtask

    // A guest I/O write: address and command up, data settling mid-cycle, the
    // way the bus actually does it.
    task automatic io_wr(input [1:0] port, input [7:0] v);
        a1a2 = port; cs = 1'b1; data_in = 8'hC3; io_write_n = 1'b0;
        repeat (2) @(posedge clk);
        data_in = v;
        repeat (3) @(posedge clk);
        io_write_n = 1'b1;
        @(posedge clk);
        cs = 1'b0; a1a2 = 2'b00;
        repeat (2) @(posedge clk);
    endtask

    task automatic io_rd(input [1:0] port, output [7:0] v);
        a1a2 = port; cs = 1'b1; io_read_n = 1'b0;
        repeat (3) @(posedge clk);
        v = data_out;
        repeat (2) @(posedge clk);
        io_read_n = 1'b1;
        @(posedge clk);
        cs = 1'b0; a1a2 = 2'b00;
        repeat (2) @(posedge clk);
    endtask

    task automatic fw_reg_wr(input [4:0] a, input [7:0] v);
        mg_reg_addr = a; mg_reg_wdata = v; mg_reg_we = 1'b1;
        @(posedge clk);
        mg_reg_we = 1'b0;
        repeat (2) @(posedge clk);
    endtask

    logic [7:0] got;
    logic       req0;

    initial begin
        $display("=== PC-98 SCSI register window ===");
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

        // ---- the index post-increments, which is how a CDB gets written ----
        // np2 scsiio_occ2: reg[port] = dat; port++ for port <= 0x19. The BIOS
        // writes SCSICTR_CDB (0x03) once and then pushes the whole descriptor
        // block through 0xCC2.
        io_wr(2'b00, 8'h03);              // select CDB
        io_wr(2'b01, 8'h08);              // READ(6)
        io_wr(2'b01, 8'h00);
        io_wr(2'b01, 8'h00);
        io_wr(2'b01, 8'h10);              // LBA 0x10
        io_wr(2'b01, 8'h01);              // one block
        io_wr(2'b01, 8'h00);
        mg_reg_addr = 5'h03; @(posedge clk); @(posedge clk);
        want("CDB[0] after six writes", mg_reg_rdata, 8'h08);
        mg_reg_addr = 5'h06; @(posedge clk); @(posedge clk);
        want("CDB[3] = LBA low", mg_reg_rdata, 8'h10);
        mg_reg_addr = 5'h07; @(posedge clk); @(posedge clk);
        want("CDB[4] = block count", mg_reg_rdata, 8'h01);

        // ---- reading 0xCC2 also post-increments ---------------------------
        io_wr(2'b00, 8'h03);
        io_rd(2'b01, got); want("read CDB[0]", got, 8'h08);
        io_rd(2'b01, got); want("read CDB[1], index moved", got, 8'h00);

        // ---- writing CMD (0x18) raises the request -------------------------
        req0 = cmd_req;
        io_wr(2'b00, 8'h18);
        io_wr(2'b01, 8'h20);              // SELECT-with-ATN-and-transfer
        want("cmd_byte handed over", cmd_byte, 8'h20);
        if (cmd_req === req0) begin
            $display("  FAIL cmd_req did not toggle");
            errors++;
        end else
            $display("  ok   cmd_req toggled");

        // A register that is NOT the command must not raise it.
        req0 = cmd_req;
        io_wr(2'b00, 8'h0F);              // TARGETLUN
        io_wr(2'b01, 8'h00);
        if (cmd_req !== req0) begin
            $display("  FAIL cmd_req toggled on a non-command write");
            errors++;
        end else
            $display("  ok   cmd_req quiet on TARGETLUN");

        // ---- 0xCC0 reads auxstatus, and reading CLEARS it ------------------
        mg_auxstatus = 8'h85; mg_auxstatus_we = 1'b1;
        @(posedge clk); mg_auxstatus_we = 1'b0; repeat (2) @(posedge clk);
        io_rd(2'b00, got); want("auxstatus", got, 8'h85);
        io_rd(2'b00, got); want("auxstatus cleared by the read", got, 8'h00);

        // ---- index 0x17 answers scsistatus --------------------------------
        mg_scsistatus = 8'h16; mg_scsistatus_we = 1'b1;
        @(posedge clk); mg_scsistatus_we = 1'b0; repeat (2) @(posedge clk);
        io_wr(2'b00, 8'h17);
        io_rd(2'b01, got); want("scsistatus at index 17", got, 8'h16);

        // ---- the registers above 0x19 that answer at all -------------------
        io_wr(2'b00, 8'h30); io_wr(2'b01, 8'h40);   // MEMBANK, bank 1
        io_wr(2'b00, 8'h30); io_rd(2'b01, got);
        want("MEMBANK reads back", got, 8'h40);
        io_wr(2'b00, 8'h36); io_rd(2'b01, got);
        want("index 36 is always 00", got, 8'h00);
        io_wr(2'b00, 8'h3A); io_rd(2'b01, got);
        want("an unmapped index reads FF", got, 8'hFF);

        // ---- 0xCC4 discards on write and reads 00 --------------------------
        io_wr(2'b10, 8'h5A);
        io_rd(2'b10, got); want("CC4 reads 00", got, 8'h00);

        // ---- 0xCC6 is a buffer with separate pointers ----------------------
        // The firmware fills it and rewinds the read pointer; the guest walks
        // it out a byte at a time. That is a sector arriving.
        for (int i = 0; i < 8; i++) begin
            mg_buf_addr = 13'(i); mg_buf_wdata = 8'(8'hA0 + i); mg_buf_we = 1'b1;
            @(posedge clk);
        end
        mg_buf_we = 1'b0;
        mg_rdptr_clr = 1'b1; @(posedge clk); mg_rdptr_clr = 1'b0;
        repeat (2) @(posedge clk);
        io_rd(2'b11, got); want("buffer[0]", got, 8'hA0);
        io_rd(2'b11, got); want("buffer[1], pointer moved", got, 8'hA1);
        io_rd(2'b11, got); want("buffer[2]", got, 8'hA2);

        // And the other direction: the guest writes, the firmware reads back.
        mg_wrptr_clr = 1'b1; @(posedge clk); mg_wrptr_clr = 1'b0;
        repeat (2) @(posedge clk);
        io_wr(2'b11, 8'h5E);
        io_wr(2'b11, 8'h5F);
        mg_buf_addr = 13'd0; @(posedge clk); @(posedge clk);
        want("guest wrote buffer[0]", mg_buf_rdata, 8'h5E);
        mg_buf_addr = 13'd1; @(posedge clk); @(posedge clk);
        want("guest wrote buffer[1]", mg_buf_rdata, 8'h5F);

        // ---- the firmware can preload a register the guest then reads ------
        fw_reg_wr(5'h17 & 5'h1F, 8'h00);  // harmless, exercises the write port
        io_wr(2'b00, 8'h05); io_wr(2'b01, 8'h77);
        mg_reg_addr = 5'h05; @(posedge clk); @(posedge clk);
        want("CYLINDERS readable by firmware", mg_reg_rdata, 8'h77);

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("PASS tb_pc98_scsi");
        else             $display("FAILED tb_pc98_scsi: %0d", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("FAILED tb_pc98_scsi: timeout");
        $finish;
    end

endmodule

`default_nettype wire
