//
// tb_floppy_format -- FORMAT TRACK (0Dh) against the REAL floppy.v, end to
// end: a guest-side driver on the I/O port, and on the management side either
// the real fdd_ramimg write path (sdram_shim + sdram_mp + sdram_model, through
// the real mgmt_arb, as tb_ramimg_write wires it) or a firmware-shaped server
// on mgmt_arb's firmware port that pops the controller FIFO while request[1]
// stays up and counts what it got.
//
// The guest side is the 765 protocol as a driver speaks it: DOR (port 2)
// motor/enable, MSR (port 4) RQM/DIO polled before every data-port (port 5)
// byte, SPECIFY with ND set (non-DMA) or clear (DMA), FORMAT 4Dh HD/US N SC
// GPL D, the C/H/R/N IDs per sector -- by PIO or by a DMA channel model that
// raises TC on the last ID byte -- and the seven result bytes.
//
// Scenarios:
//   A. 2DD (512-byte sectors, N=2), firmware-shaped server, PIO: every sector
//      is exactly 512 pops of D at its own LBA; sector count, result normal.
//   B. 2DD write-protected (mgmt 0x01): ST0=40h|hd|us, ST1=02h, ST2=00h.
//   C. 2HD through fdd_ramimg (it mounts 77/8/2, N=3), PIO: every carve-out
//      word of the 8 sectors is {00,D} -- including bytes 512..1023, which
//      were pre-filled with something else -- neighbours untouched.
//   D. 2HD again, DMA with TC on the last ID byte, other cylinder/head/D.
//   E. 2HD write-protected through the wp pin: ST0=40h|hd|us, ST1=02h.
//
// Build + run (from the repo root):
//   $ verilator --binary --timing -Wno-fatal --top-module tb_floppy_format \
//     -Ifpga/core fpga/core/common/floppy.v fpga/core/common/simple_fifo.v \
//     fpga/core/sdram_shim.sv fpga/core/sdram_mp.sv sim/sdram_model.sv \
//     fpga/core/fdd_ramimg.sv fpga/core/mgmt_arb.sv sim/stub_dcfifo.sv \
//     sim/stub_sld_virtual_jtag.sv sim/tb_floppy_format.sv \
//     -o tb_floppy_format --Mdir /tmp/obj_floppy_format \
//     && /tmp/obj_floppy_format/tb_floppy_format
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_floppy_format;

    localparam real HALF_NS = 11.64153;   // ~42.95 MHz chipset clock
    logic clk = 0, reset = 1, power_reset = 1;
    always #(HALF_NS) clk = ~clk;

    // ------------------------------------------------------------- fdd_ramimg
    wire  [1:0]  fdd_request;
    logic [15:0] ri_addr, ri_dout;
    wire  [15:0] mgmt_din;
    logic        ri_wr, ri_rd;

    logic        sd_req, sd_we, sd_ack, sd_rvalid, sd_done;
    logic [23:0] sd_addr;
    logic  [3:0] sd_len;
    logic [15:0] sd_wdata, sd_rdata;

    logic        ctl_pulse = 1'b0;
    logic [6:0]  ctl_addr  = 7'd0;
    logic [31:0] ctl_data  = 32'd0;
    wire  [31:0] dbg0, dbg1, dbg2;
    wire         own, greset;

    fdd_ramimg ri (
        .clk(clk), .reset(reset), .power_reset(power_reset),
        .fdd_request(fdd_request),
        .mgmt_addr(ri_addr), .mgmt_dout(ri_dout),
        .mgmt_wr(ri_wr), .mgmt_rd(ri_rd), .mgmt_din(mgmt_din),
        .fw_busy(1'b0),
        .sd_req(sd_req), .sd_we(sd_we), .sd_addr(sd_addr), .sd_len(sd_len),
        .sd_wdata(sd_wdata), .sd_ack(sd_ack), .sd_rvalid(sd_rvalid),
        .sd_rdata(sd_rdata), .sd_done(sd_done),
        .ctl_pulse(ctl_pulse), .ctl_addr(ctl_addr), .ctl_data(ctl_data),
        .own(own), .guest_reset_req(greset),
        .dbg0(dbg0), .dbg1(dbg1), .dbg2(dbg2)
    );

    // ------------------------------------------------------------- mgmt arb
    logic [15:0] fw_addr = 16'h0000, fw_dout = 16'h0000;
    logic        fw_rd = 1'b0, fw_wr = 1'b0;
    wire  [15:0] cs_addr, cs_dout;
    wire         cs_rd, cs_wr;

    mgmt_arb u_arb (
        .fw_addr(fw_addr), .fw_dout(fw_dout), .fw_rd(fw_rd), .fw_wr(fw_wr),
        .ri_addr(ri_addr), .ri_dout(ri_dout), .ri_rd(ri_rd), .ri_wr(ri_wr),
        .ri_own(own),
        .cs_addr(cs_addr), .cs_dout(cs_dout), .cs_rd(cs_rd), .cs_wr(cs_wr)
    );

    // ------------------------------------------------------------- shim + mp
    wire [12:0] s_a;
    wire [1:0]  s_ba;
    wire        s_cke, s_ras_n, s_cas_n, s_we_n, s_dq_io;
    wire [1:0]  s_dqm = 2'b00;
    wire [15:0] s_dq_out, s_dq_in;

    sdram_shim #(
        .INIT_NOP(64), .REFRESH_INT(320)
    ) shim (
        .sdram_clock(clk), .sdram_reset(power_reset),
        .address(25'd0), .access_num(10'd0),
        .data_in(16'd0), .data_out(), .data_in_hi(16'd0), .a_rvalid(),
        .a_beat(),
        .data_out_hi(),
        .write_request(1'b0), .read_request(1'b0), .enable_refresh(1'b0),
        .write_flag(), .read_flag(), .idle(), .refresh_mode(),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(),
        .sdram_ras(s_ras_n), .sdram_cas(s_cas_n), .sdram_we(s_we_n),
        .sdram_ba(s_ba), .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out),
        .sdram_dq_io(s_dq_io),
        .b_req(1'b0), .b_addr(24'd0), .b_len(4'd0),
        .b_ack(), .b_rvalid(), .b_rdata(), .b_done(),
        .c_req(1'b0), .c_addr(24'd0), .c_len(4'd0),
        .c_ack(), .c_rvalid(), .c_rdata(), .c_done(),
        .d_req(1'b0), .d_addr(24'd0), .d_len(4'd0),
        .d_ack(), .d_rvalid(), .d_rdata(), .d_done(),
        .e_req(sd_req), .e_we(sd_we), .e_addr(sd_addr), .e_len(sd_len),
        .e_wdata(sd_wdata), .e_ack(sd_ack), .e_rvalid(sd_rvalid),
        .e_rdata(sd_rdata), .e_done(sd_done),
        .f_req(1'b0), .f_we(1'b0), .f_addr(24'd0), .f_len(4'd0),
        .f_wdata0(16'd0), .f_wdata1(16'd0),
        .f_ack(), .f_rvalid(), .f_rdata(), .f_done(),
        .a_wr_v(), .a_wr_addr(), .a_wr_len()
    );

    sdram_model #(
        .ROW_BITS(13), .COL_BITS(9), .BANK_BITS(2), .DQ_BITS(16),
        .PHYSICAL_DQ(1'b1)
    ) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ------------------------------------------------------------- floppy.v
    // Peripherals.sv: chip select F2, addr[3:0], fddn = addr[7], strobes
    // gated by the select, the readback routed straight to the bus.
    wire        fdd_cs  = cs_addr[15:8] == 8'hF2;
    wire [15:0] f_rdata;
    assign mgmt_din = fdd_cs ? f_rdata : 16'h0000;

    logic  [2:0] io_address = 3'd0;
    logic        io_read = 1'b0, io_write = 1'b0;
    logic  [7:0] io_writedata = 8'h00;
    wire   [7:0] io_readdata;
    logic  [1:0] wp_pin = 2'b00;

    wire        dma_req;
    logic       dma_ack = 1'b0, dma_tc_r = 1'b0;
    logic [7:0] dma_rd = 8'h00;
    wire  [7:0] dma_wr_unused;
    wire        f_irq, f_busy;

    floppy #(.NOT_READY_ENDS_COMMAND(1)) fdc (
        .clk(clk), .rst_n(~reset),
        .dma_req(dma_req), .dma_ack(dma_ack), .dma_tc(dma_tc_r & dma_ack),
        .dma_readdata(dma_rd), .dma_writedata(dma_wr_unused),
        .irq(f_irq), .busy(f_busy),
        .io_address(io_address), .io_read(io_read), .io_readdata(io_readdata),
        .io_write(io_write), .io_writedata(io_writedata),
        .fdd0_inserted(),
        .mgmt_address(cs_addr[3:0]), .mgmt_fddn(cs_addr[7]),
        .mgmt_write(cs_wr & fdd_cs), .mgmt_writedata(cs_dout),
        .mgmt_read(cs_rd & fdd_cs), .mgmt_readdata(f_rdata),
        .wp(wp_pin),
        .clock_rate(28'd42954545),
        .turbo(1'b1),
        .request(fdd_request),
        .dbg_cmd_accepts(), .dbg_cmd_drops(), .dbg_reply_left(),
        .dbg_xfer(), .dbg_command(), .dbg_sector_info(),
        .snd_step(), .snd_head(), .snd_xfer(), .snd_motor()
    );

    // ------------------------------------------------------------- checks
    int errors = 0;
    localparam logic [23:0] CARVE = 24'h620000;

    task automatic check(bit ok, string msg);
        if (!ok) begin errors++; $display("FAIL: %s", msg); end
        else           $display("  ok: %s", msg);
    endtask

    // FIFO pops on an empty FIFO are expected for FORMAT (the filler byte is
    // a register); what must hold is that no pop lands outside the fill wait.
    int stray_pops = 0;
    always @(posedge clk)
        if (cs_rd && fdd_cs && &cs_addr[3:0] && fdc.state != 4'd13 && fdc.cmd_format_in_progress)
            stray_pops <= stray_pops + 1;

    // ------------------------------------------------------------- DMA model
    // A 8237 channel in single mode: one ack per request, TC on the last byte
    // of the programmed count.
    logic [7:0] dma_buf [0:255];
    int         dma_n = 0, dma_i = 0;
    always @(posedge clk) begin
        dma_ack  <= 1'b0;
        dma_tc_r <= 1'b0;
        if (dma_req && !dma_ack && dma_i < dma_n) begin
            dma_ack  <= 1'b1;
            dma_rd   <= dma_buf[dma_i];
            dma_tc_r <= (dma_i == dma_n - 1);
            dma_i    <= dma_i + 1;
        end
    end

    // ------------------------------------------------------------- guest I/O
    // Strobes change on the falling edge, one clock wide; a read samples the
    // registered io_readdata one clock after its strobe.
    task automatic io_wr(input logic [2:0] a, input logic [7:0] d);
        @(negedge clk); io_address = a; io_writedata = d; io_write = 1'b1;
        @(negedge clk); io_write = 1'b0;
    endtask

    task automatic io_rd(input logic [2:0] a, output logic [7:0] d);
        @(negedge clk); io_address = a; io_read = 1'b1;
        @(negedge clk); io_read = 1'b0; d = io_readdata;
    endtask

    task automatic msr_wait(output logic [7:0] m);
        int t = 0;
        do begin
            io_rd(3'd4, m);
            t++;
        end while (!m[7] && t < 2000000);
        if (!m[7]) begin errors++; $display("FAIL: MSR never showed RQM (MSR=%02h state=%0d)", m, fdc.state); end
    endtask

    task automatic fdc_out(input logic [7:0] d);
        logic [7:0] m;
        msr_wait(m);
        if (m[6]) begin errors++; $display("FAIL: DIO set while sending %02h (MSR=%02h)", d, m); end
        io_wr(3'd5, d);
    endtask

    task automatic fdc_specify(input bit nd);
        fdc_out(8'h03); fdc_out(8'hDF); fdc_out({7'h02, nd});
    endtask

    // FORMAT: issue the command, feed SC IDs by PIO (or let the DMA model
    // feed them), then read the seven result bytes.
    task automatic format_track(input bit use_dma, input bit hd, input logic [7:0] cyl,
                                input logic [7:0] n, input logic [7:0] sc,
                                input logic [7:0] d, input bit expect_data,
                                output logic [7:0] res [0:6]);
        logic [7:0] m;
        int s, b, t;
        if (use_dma) begin
            for (s = 0; s < sc; s++) begin
                dma_buf[s*4+0] = cyl; dma_buf[s*4+1] = 8'(hd);
                dma_buf[s*4+2] = 8'(s + 1); dma_buf[s*4+3] = n;
            end
            dma_i = 0; dma_n = int'(sc) * 4;
        end
        fdc_out(8'h4D); fdc_out({5'd0, hd, 2'd0}); fdc_out(n);
        fdc_out(sc); fdc_out(8'h54); fdc_out(d);
        if (expect_data && !use_dma) begin
            for (s = 0; s < sc; s++)
                for (b = 0; b < 4; b++) begin
                    msr_wait(m);
                    if (m[6]) begin
                        errors++;
                        $display("FAIL: result phase early, sector %0d byte %0d", s, b);
                        s = sc; break;
                    end
                    io_wr(3'd5, (b == 0) ? cyl : (b == 1) ? 8'(hd) : (b == 2) ? 8'(s + 1) : n);
                end
        end
        // Result phase: RQM and DIO.
        t = 0;
        do begin io_rd(3'd4, m); t++; end while (!(m[7] && m[6]) && t < 4000000);
        if (!(m[7] && m[6])) begin
            errors++;
            $display("FAIL: no result phase (MSR=%02h state=%0d)", m, fdc.state);
        end
        for (b = 0; b < 7; b++) begin
            msr_wait(m);
            io_rd(3'd5, res[b]);
        end
        io_rd(3'd4, m);
        check(m == 8'h80, $sformatf("MSR back to 80h after the result (got %02h)", m));
        if (use_dma) check(dma_i == dma_n, $sformatf("DMA moved all %0d ID bytes (%0d)", dma_n, dma_i));
        $display("  result: %02h %02h %02h %02h %02h %02h %02h",
                 res[0], res[1], res[2], res[3], res[4], res[5], res[6]);
    endtask

    // ------------------------------------------------------------- firmware-
    // shaped server on the fw port: register 0 for {drive,lba}, then pop F20F
    // while request[1] is up -- one pop, two idle clocks (pull_fifo's
    // registered-head gap) -- and record what each sector got.
    bit          fw_serve = 1'b0;
    int          fw_pops [int];      // lba -> pops
    logic  [7:0] fw_bad  [int];      // lba -> 0 if every byte was D
    logic  [7:0] fw_expect_d = 8'h00;

    task automatic fw_write(input logic [15:0] a, input logic [15:0] d);
        @(negedge clk); fw_addr = a; fw_dout = d; fw_wr = 1'b1;
        @(negedge clk); fw_wr = 1'b0;
    endtask

    initial begin : fw_server
        int lba, n;
        logic [15:0] v;
        forever begin
            @(negedge clk);
            if (fw_serve && fdd_request[1]) begin
                fw_addr = 16'hF200; fw_rd = 1'b1; #1 v = mgmt_din;
                @(negedge clk); fw_rd = 1'b0;
                lba = int'(v[14:0]);
                n = 0;
                fw_bad[lba] = 8'h00;
                while (fdd_request[1] && n < 4096) begin
                    fw_addr = 16'hF20F; fw_rd = 1'b1; #1 v = mgmt_din;
                    if (v[7:0] !== fw_expect_d) fw_bad[lba] = 8'h01;
                    @(negedge clk); fw_rd = 1'b0;
                    n++;
                    @(negedge clk); @(negedge clk);
                end
                fw_pops[lba] = fw_pops.exists(lba) ? fw_pops[lba] + n : n;
            end
        end
    end

    task automatic fw_mount_2dd(input bit wprot);
        fw_write(16'hF200, 16'd0);
        repeat (20) @(posedge clk);
        fw_write(16'hF202, 16'd80);
        fw_write(16'hF203, 16'd3);       // 3 sectors/track keeps the run short
        fw_write(16'hF204, 16'd480);
        fw_write(16'hF205, 16'd2);
        fw_write(16'hF206, 16'd0);       // 512-byte sectors
        fw_write(16'hF201, 16'(wprot));
        fw_write(16'hF200, 16'd1);
    endtask

    // ------------------------------------------------------------- 2HD image
    function automatic int lba_2hd(int c, int h, int r);
        return (c * 2 + h) * 8 + r - 1;
    endfunction

    task automatic prefill(int lba0, int nsec);
        int i;
        for (i = (lba0 - 1) * 1024; i < (lba0 + nsec + 1) * 1024; i++)
            sdr.store[int'(CARVE) + i] = {8'hA5, 8'(i * 3 + 1)};
    endtask

    task automatic check_2hd(int lba0, int nsec, logic [7:0] d);
        int i, a, bad = 0, tailbad = 0, nb = 0;
        for (i = 0; i < nsec * 1024; i++) begin
            a = int'(CARVE) + lba0 * 1024 + i;
            if (!sdr.store.exists(a) || sdr.store[a] !== {8'h00, d}) begin
                if (bad < 8) $display("  MISMATCH lba %0d byte %0d = %04h", lba0 + i / 1024, i % 1024,
                                      sdr.store.exists(a) ? sdr.store[a] : 16'hxxxx);
                bad++;
                if (i % 1024 >= 512) tailbad++;
            end
        end
        check(bad == 0, $sformatf("2HD lba %0d..%0d: all %0d bytes == %02h (%0d wrong, %0d in tails 512..1023)",
                                  lba0, lba0 + nsec - 1, nsec * 1024, d, bad, tailbad));
        for (i = 0; i < 1024; i++) begin
            a = int'(CARVE) + (lba0 - 1) * 1024 + i;
            if (sdr.store[a] !== {8'hA5, 8'(((lba0 - 1) * 1024 + i) * 3 + 1)}) nb++;
            a = int'(CARVE) + (lba0 + nsec) * 1024 + i;
            if (sdr.store[a] !== {8'hA5, 8'(((lba0 + nsec) * 1024 + i) * 3 + 1)}) nb++;
        end
        check(nb == 0, $sformatf("neighbour sectors %0d and %0d untouched (%0d changed)", lba0 - 1, lba0 + nsec, nb));
    endtask

    // ------------------------------------------------------------- run
    initial begin
        logic [7:0] res [0:6];
        int s, lba, d0;

        repeat (4) @(posedge clk);
        power_reset <= 0;
        repeat (4) @(posedge clk);
        reset <= 0;
        repeat (8) @(posedge clk);

        io_wr(3'd2, 8'h1C);              // DOR: motor 0, DMA/IRQ enable, !reset, drive 0
        repeat (8) @(posedge clk);

        // ---------------- A: 2DD, PIO, firmware-shaped server
        $display("A: 2DD (N=2, SC=3), PIO");
        fw_serve = 1'b1;
        fw_mount_2dd(1'b0);
        fdc_specify(1'b1);
        fw_expect_d = 8'hE5;
        fw_pops.delete();
        format_track(1'b0, 1'b1, 8'd4, 8'd2, 8'd3, 8'hE5, 1'b1, res);
        check(res[0] == 8'h04 && res[1] == 8'h00 && res[2] == 8'h00,
              $sformatf("2DD ST0/ST1/ST2 normal = 04/00/00 (got %02h/%02h/%02h)", res[0], res[1], res[2]));
        check(res[6] == 8'h02, $sformatf("2DD result N=2 (got %02h)", res[6]));
        check(fw_pops.size() == 3, $sformatf("2DD: 3 sectors served (%0d)", fw_pops.size()));
        for (s = 1; s <= 3; s++) begin
            lba = (4 * 2 + 1) * 3 + s - 1;
            check(fw_pops.exists(lba) && fw_pops[lba] == 512 && fw_bad[lba] == 0,
                  $sformatf("2DD lba %0d: %0d pops of E5 (want 512)", lba,
                            fw_pops.exists(lba) ? fw_pops[lba] : -1));
        end
        check(fdc.format_sector_count == 8'd0, "format_sector_count counted down to 0");

        // ---------------- B: 2DD write-protected
        $display("B: 2DD write-protected");
        fw_write(16'hF201, 16'd1);
        fw_pops.delete();
        format_track(1'b0, 1'b0, 8'd0, 8'd2, 8'd3, 8'hE5, 1'b0, res);
        check(res[0] == 8'h40 && res[1] == 8'h02 && res[2] == 8'h00,
              $sformatf("WP: ST0/ST1/ST2 = 40/02/00 (got %02h/%02h/%02h)", res[0], res[1], res[2]));
        check(fw_pops.size() == 0, "WP: nothing written");
        fw_write(16'hF201, 16'd0);
        fw_serve = 1'b0;

        // ---------------- C: 2HD through fdd_ramimg, PIO
        $display("C: 2HD via fdd_ramimg (N=3, SC=8), PIO");
        prefill(lba_2hd(10, 1, 1), 8);
        prefill(lba_2hd(20, 0, 1), 8);
        @(posedge clk); ctl_addr <= 7'h07; ctl_data <= 32'h1; ctl_pulse <= 1'b1;
        @(posedge clk); ctl_pulse <= 1'b0;
        repeat (600) @(posedge clk);
        check(dbg0[22], "fdd_ramimg mounted");
        check(fdc.media_is_1024[0] == 1'b1, "media_is_1024[0] set by the mount");
        format_track(1'b0, 1'b1, 8'd10, 8'd3, 8'd8, 8'h6B, 1'b1, res);
        check(res[0] == 8'h04 && res[1] == 8'h00 && res[2] == 8'h00,
              $sformatf("2HD ST0/ST1/ST2 normal = 04/00/00 (got %02h/%02h/%02h)", res[0], res[1], res[2]));
        check(res[3] == 8'd10 && res[4] == 8'd1 && res[6] == 8'h03,
              $sformatf("2HD result C=10 H=1 N=3 (got %02h %02h %02h)", res[3], res[4], res[6]));
        repeat (200) @(posedge clk);
        check_2hd(lba_2hd(10, 1, 1), 8, 8'h6B);

        // ---------------- D: 2HD, DMA with TC on the last ID byte
        $display("D: 2HD via fdd_ramimg, DMA + TC");
        fdc_specify(1'b0);
        format_track(1'b1, 1'b0, 8'd20, 8'd3, 8'd8, 8'hF6, 1'b1, res);
        check(res[0] == 8'h00 && res[1] == 8'h00 && res[2] == 8'h00,
              $sformatf("2HD DMA ST0/ST1/ST2 normal = 00/00/00 (got %02h/%02h/%02h)", res[0], res[1], res[2]));
        repeat (200) @(posedge clk);
        check_2hd(lba_2hd(20, 0, 1), 8, 8'hF6);

        // ---------------- E: 2HD write-protected (wp pin)
        $display("E: 2HD write-protected");
        wp_pin = 2'b01;
        format_track(1'b0, 1'b1, 8'd30, 8'd3, 8'd8, 8'h00, 1'b0, res);
        check(res[0] == 8'h44 && res[1] == 8'h02 && res[2] == 8'h00,
              $sformatf("WP: ST0/ST1/ST2 = 44/02/00 (got %02h/%02h/%02h)", res[0], res[1], res[2]));
        wp_pin = 2'b00;

        check(stray_pops == 0, $sformatf("no FIFO pop outside the fill wait during FORMAT (%0d)", stray_pops));

        if (errors == 0) $display("tb_floppy_format: ALL PASS");
        else             $display("tb_floppy_format: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #(400ms);
        $display("tb_floppy_format: TIMEOUT");
        $finish;
    end

endmodule
`default_nettype wire
