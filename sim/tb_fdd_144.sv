// tb_fdd_144 -- does a 1.44 MB image actually reach the uPD765?
//
// The mount in fdd_service.c keys geometry off the image size: a 2880-sector
// file lands on the { 80 cyls, 18 spt, 2 heads, 512-byte } row, which is the
// PC-9821 1.44 MB layout (512*18*80*2). This bench mounts exactly that and
// then reads a sector that cannot exist on any other media the core serves:
// C=5, H=1, R=15 is LBA (5*2+1)*18 + 14 = 212, and needs spt=18 / cyls=80 to
// be in range. It also reads the last sector (C79,H1,R18 -> LBA 2879) and
// pokes R=19, which must be rejected as over spt=18 -- the bounds prove the
// geometry really is the 1.44 one and not a 2DD/2HD row it happens to share.
`timescale 1ns/1ps
`default_nettype none

module tb_fdd_144;
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    // ---- floppy.v's io register file, driven straight on -------------------
    logic [2:0]  fd_addr;
    logic        fd_write = 1'b0, fd_read = 1'b0;
    logic [7:0]  fd_wdata = 8'h00;
    wire  [7:0]  fd_rdata;
    wire         fd_irq, fd_busy;
    wire  [1:0]  fdd_request;

    // ---- the mgmt port the mount writes, shared with the feeder ------------
    logic        mgmt_write = 1'b0;
    logic [3:0]  mgmt_address = 4'd0;
    logic [15:0] mgmt_writedata = 16'd0;
    wire  [15:0] mgmt_rdata;

    // ---- the DMAC + sector feeder ------------------------------------------
    wire        feed_wr_m, feed_rd_m;
    wire  [3:0] feed_addr_m;
    wire [15:0] feed_wdata_m;
    wire [14:0] feed_lba;
    int         feed_idx;
    logic       feed_en = 1'b1;
    wire        dma_mem_wr;
    wire [19:0] dma_mem_addr;
    wire  [7:0] dma_mem_wd;
    logic [7:0] dma_mem [0:262143];
    logic       dma_wr_p = 1'b0;
    logic [7:0] dma_port = 8'd0, dma_wd = 8'd0;
    wire  [7:0] feed_byte = feed_idx[7:0];
    wire        fdc_dreq_w, fdc_ack_p, fdc_tc_p;
    wire  [7:0] fdc_dma_w, fdc_dma_r;
    logic       media_1024 = 1'b0;   // 512-byte sectors: the 1.44/2DD width

    always_ff @(posedge clk)
        if (dma_mem_wr) dma_mem[dma_mem_addr] <= dma_mem_wd;

    // Feeder wins the mgmt port while it owns it, the test owns it otherwise.
    wire        mgmt_wr_m    = feed_wr_m | mgmt_write;
    wire  [3:0] mgmt_addr_m  = (feed_wr_m | feed_rd_m) ? feed_addr_m
                                                       : mgmt_address;
    wire [15:0] mgmt_wdata_m = feed_wr_m ? feed_wdata_m : mgmt_writedata;

    floppy #(.NOT_READY_ENDS_COMMAND(1)) u_floppy (
        .clk            (clk),
        .rst_n          (~rst),
        .dma_req        (fdc_dreq_w),
        .dma_ack        (fdc_ack_p),
        .dma_tc         (fdc_tc_p),
        .dma_readdata   (fdc_dma_r),
        .dma_writedata  (fdc_dma_w),
        .irq            (fd_irq),
        .busy           (fd_busy),
        .io_address     (fd_addr),
        .io_read        (fd_read),
        .io_readdata    (fd_rdata),
        .io_write       (fd_write),
        .io_writedata   (fd_wdata),
        .fdd0_inserted  (),
        .mgmt_address   (mgmt_addr_m),
        .mgmt_fddn      (1'b0),
        .mgmt_write     (mgmt_wr_m),
        .mgmt_writedata (mgmt_wdata_m),
        .mgmt_read      (feed_rd_m),
        .mgmt_readdata  (mgmt_rdata),
        .wp             (2'b00),
        .clock_rate     (28'd2000),
        .request        (fdd_request)
    );

    tb_fdd_dma_model u_dma (
        .clk        (clk),
        .io_wr      (dma_wr_p),
        .io_rd      (1'b0),
        .io_addr    (dma_port),
        .io_wdata   (dma_wd),
        .io_rdata   (),
        .drq        (fdc_dreq_w),
        .dack       (fdc_ack_p),
        .tc         (fdc_tc_p),
        .ddata_i    (fdc_dma_w),
        .ddata_o    (fdc_dma_r),
        .mem_wr     (dma_mem_wr),
        .mem_addr   (dma_mem_addr),
        .mem_wdata  (dma_mem_wd),
        .mem_rdata  (dma_mem[dma_mem_addr]),
        .feed_en    (feed_en),
        .sec_req    (fdd_request),
        .mgmt_wr    (feed_wr_m),
        .mgmt_addr  (feed_addr_m),
        .mgmt_wdata (feed_wdata_m),
        .mgmt_rd    (feed_rd_m),
        .mgmt_rdata (mgmt_rdata),
        .media_1024 (media_1024),
        .feed_lba   (feed_lba),
        .feed_idx   (feed_idx),
        .feed_byte  (feed_byte)
    );

    int errors = 0;
    task automatic want(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            errors++;
            $display("  FAIL %-42s got=%h want=%h", what, got, exp);
        end else
            $display("  ok   %-42s %h", what, got);
    endtask

    // One byte into an io register: address set for a cycle, write pulses high.
    task automatic wr(input int which, input [7:0] v);
        fd_addr  = which[2:0];
        fd_wdata = v;
        @(negedge clk);
        fd_write = 1'b1;
        @(negedge clk);
        fd_write = 1'b0;
        #1;
    endtask
    task automatic rd(input int which, output logic [7:0] v);
        fd_addr = which[2:0];
        @(negedge clk);
        fd_read = 1'b1;
        @(negedge clk);
        fd_read = 1'b0;
        #1;
        v = fd_rdata;
        #1;
    endtask

    // The uPD71071 registers the BIOS's INT 1Bh programs before each sector.
    task automatic dma_wr(input [7:0] port, input [7:0] v);
        @(negedge clk);
        dma_port = port; dma_wd = v; dma_wr_p = 1'b1;
        @(negedge clk);
        dma_wr_p = 1'b0;
        #1;
    endtask

    // Mount 80 cyls / 18 spt / 2 heads of 512 bytes -- the 1.44 MB row.
    task automatic mount_144;
        @(negedge clk); mgmt_address=4'd2; mgmt_writedata=16'd80;   mgmt_write=1'b1;
        @(negedge clk); mgmt_address=4'd3; mgmt_writedata=16'd18;
        @(negedge clk); mgmt_address=4'd4; mgmt_writedata=16'd2880; // total sectors
        @(negedge clk); mgmt_address=4'd5; mgmt_writedata=16'd2;
        @(negedge clk); mgmt_address=4'd6; mgmt_writedata=16'd0;
        @(negedge clk); mgmt_address=4'd0; mgmt_writedata=16'h0001; // present
        @(negedge clk); mgmt_write=1'b0;
        #1;
    endtask

    // A single-sector DMA read of C/H/R, into page-1 memory; returns the
    // status bytes. ST0's low bits are HD|US (the head+drive used), so a
    // clean read on head 1 answers 0x04 -- success is the interrupt code in
    // bits [7:6] being 0 and ST1/ST2 clear.
    task automatic read144(input [7:0] c, input [7:0] h, input [7:0] r,
                           output [7:0] st0, output [7:0] st1, output [7:0] st2);
        logic [7:0] msr;
        int guard;
        dma_wr(8'h19, 8'h00);                    // clear the byte pointer
        dma_wr(8'h17, 8'h46);                    // single write-transfer, ch2
        dma_wr(8'h09, 8'h00); dma_wr(8'h09, 8'h00);  // base addr 0x0000
        dma_wr(8'h23, 8'h01);                    // page 1 -> 0x10000
        dma_wr(8'h0B, 8'hFF); dma_wr(8'h0B, 8'h01);  // count 0x01FF = 512
        dma_wr(8'h15, 8'h02);                    // unmask ch2
        // READ DATA (0x46 = MT|MFM|READ). The unit byte's HD bit must match the
        // H field (floppy.v's incorrect-head check): unit = (head<<2)|drive.
        wr(5, 8'h46); wr(5, (h & 8'h1) << 2); wr(5, c); wr(5, h);
        wr(5, r);     wr(5, 8'h02);           wr(5, 8'd18); wr(5, 8'h1B);
        wr(5, 8'hFF);
        guard = 0;
        while (!fd_irq && guard < 60_000) begin @(negedge clk); guard++; end
        #1;
        rd(5, st0); rd(5, st1); rd(5, st2);
        for (int b = 0; b < 4; b++) rd(5, msr);  // drain C H R N
        rd(4, msr);
    endtask

    initial begin
        logic [7:0] st0, st1, st2;
        $display("=== 1.44 MB mount + read ===");
        repeat (4) @(posedge clk); rst = 1'b0;
        repeat (2) @(negedge clk);
        mount_144;
        // floppy.v won't run a media command until its DOR says the controller
        // is enabled and the motor's on -- the glue's constant DOR, done here
        // by hand. enable|irq|motor0|motor1, drive 0 selected.
        wr(2, 8'h3C);
        $display("  mount: cyl=%0d spt=%0d heads=%0d is1024=%0d present=%0d",
                 u_floppy.media_cylinders[0], u_floppy.media_sectors_per_track[0],
                 u_floppy.media_heads[0], u_floppy.media_is_1024[0],
                 u_floppy.media_present[0]);

        // C5 H1 R15 -> LBA (5*2+1)*18 + 14 = 212. Needs spt=18, cyls>5, N=2.
        // Head 1, so a clean answer is ST0=0x04 (HD) with ST1/ST2 clear.
        read144(8'd5, 8'd1, 8'd15, st0, st1, st2);
        want("mid-disk read normal (IC=00)", st0 & 8'hC0, 8'h00);
        want("  ST1 clear", st1, 8'h00);
        want("  ST2 clear", st2, 8'h00);
        want("feeder asked LBA 212", feed_lba, 15'd212);
        want("first byte landed",  dma_mem[20'h10000],       8'h00);
        want("last byte landed",   dma_mem[20'h10000 + 511], 8'hFF);

        // Last sector on the media: C79 H1 R18 -> LBA (79*2+1)*18 + 17 = 2879.
        read144(8'd79, 8'd1, 8'd18, st0, st1, st2);
        want("last-sector read normal (IC=00)", st0 & 8'hC0, 8'h00);
        want("feeder asked LBA 2879", feed_lba, 15'd2879);

        // R=19 is past spt=18 -> incorrect-sector error: ST0 abnormal (0x40),
        // ST1 no-data (0x04).
        read144(8'd0, 8'd0, 8'd19, st0, st1, st2);
        want("R=19 rejected (spt is really 18)", st0 & 8'hC0, 8'h40);
        want("  ST1 = ND", st1, 8'h04);

        if (errors == 0) $display("PASS tb_fdd_144");
        else             $display("FAILED tb_fdd_144: %0d", errors);
        $finish;
    end
    initial begin #200_000_000; $display("FAILED tb_fdd_144: timeout"); $finish; end
endmodule
