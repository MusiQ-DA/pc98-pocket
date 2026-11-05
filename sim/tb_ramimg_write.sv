//
// tb_ramimg_write -- fdd_ramimg's sector-WRITE path (S_WR_LBA .. S_WR_DONE)
// against the REAL sdram_shim + sdram_mp + sdram_model chain and a faithful
// slice of floppy.v's management side.
//
// The floppy slice is floppy.v's own write-drain plumbing, not a stub:
//   * the real simple_fifo (width 8, widthu 11, show-ahead q = mem[rd_index]),
//   * fifo_readdata as floppy.v registers it (fifo_readdata <= fifo_q),
//   * mgmt_readdata = !addr ? {drive, sd_sector} : &addr ? fifo_readdata : 1,
//   * fifo_read = mgmt_read && &mgmt_address,
//   * request[1] = (state == S_SD_WRITE_WAIT_FOR_EMPTY_FIFO), and the state
//     leaves on fifo_empty -- floppy.v's transition, registered.
// The bus between them is wired the way core_top/Peripherals wire it: the
// real mgmt_arb (firmware side optionally generating non-F2 traffic), then
// Peripherals' F2 chip-select gating the strobes and addr[3:0]/addr[7]
// reaching floppy.v. mgmt_din is the combinational answer, as on hardware.
//
// Scenario: a 1024-byte sector (byte i = i*7+3) is DMA-filled into the FIFO
// (state S_WAIT_FOR_FULL_WRITE_FIFO -- no mgmt traffic), the controller moves
// to the write wait with sd_sector = 37, fdd_ramimg drains it into the
// carve-out; then a second back-to-back sector (lba 38, byte i = i*13+5).
// Checks: every carve-out word of both sectors holds {8'h00, pattern}, every
// pre-existing word outside them is untouched, no word outside them was
// created, the FIFO was never popped while empty, and the controller left
// the wait state for each sector.
//
// Plusargs: +FW_PERIOD=n  firmware non-F2 (F4) mgmt read every n clocks.
//
// Build + run (from the repo root):
//   $ verilator --binary --timing -Wno-fatal --top-module tb_ramimg_write \
//     -Ifpga/core fpga/core/sdram_shim.sv fpga/core/sdram_mp.sv \
//     sim/sdram_model.sv fpga/core/fdd_ramimg.sv fpga/core/mgmt_arb.sv \
//     fpga/core/common/simple_fifo.v sim/stub_dcfifo.sv \
//     sim/stub_sld_virtual_jtag.sv sim/tb_ramimg_write.sv \
//     -o tb_ramimg_write --Mdir /tmp/obj_ramimg_write \
//     && /tmp/obj_ramimg_write/tb_ramimg_write
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ramimg_write;

    localparam real HALF_NS = 11.64153;   // ~42.95 MHz chipset clock

    logic clk = 0, reset = 1, power_reset = 1;
    always #(HALF_NS) clk = ~clk;

    // ------------------------------------------------------------- fdd_ramimg
    logic  [1:0]  fdd_request;
    logic [15:0]  ri_addr, ri_dout, mgmt_din;
    logic         ri_wr, ri_rd;
    logic         fw_busy = 1'b0;

    logic        sd_req, sd_we, sd_ack, sd_rvalid, sd_done;
    logic [23:0] sd_addr;
    logic  [3:0] sd_len;
    logic [15:0] sd_wdata, sd_rdata;

    logic        ctl_pulse = 1'b0;
    logic [6:0]  ctl_addr  = 7'd0;
    logic [31:0] ctl_data  = 32'd0;
    wire  [31:0] dbg0, dbg1, dbg2;
    wire         own, greset;

    fdd_ramimg dut (
        .clk(clk), .reset(reset), .power_reset(power_reset),
        .fdd_request(fdd_request),
        .mgmt_addr(ri_addr), .mgmt_dout(ri_dout),
        .mgmt_wr(ri_wr), .mgmt_rd(ri_rd), .mgmt_din(mgmt_din),
        .fw_busy(fw_busy),
        .sd_req(sd_req), .sd_we(sd_we), .sd_addr(sd_addr), .sd_len(sd_len),
        .sd_wdata(sd_wdata), .sd_ack(sd_ack), .sd_rvalid(sd_rvalid),
        .sd_rdata(sd_rdata), .sd_done(sd_done),
        .ctl_pulse(ctl_pulse), .ctl_addr(ctl_addr), .ctl_data(ctl_data),
        .own(own), .guest_reset_req(greset),
        .dbg0(dbg0), .dbg1(dbg1), .dbg2(dbg2)
    );

    // ------------------------------------------------------------- mgmt arb
    logic [15:0] fw_addr = 16'h0000;
    logic        fw_rd   = 1'b0;
    wire  [15:0] cs_addr, cs_dout;
    wire         cs_rd, cs_wr;

    mgmt_arb u_arb (
        .fw_addr(fw_addr), .fw_dout(16'h0000), .fw_rd(fw_rd), .fw_wr(1'b0),
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

    // ------------------------------------------- floppy.v management slice
    // Peripherals.sv: mgmt_fdd_cs = addr[15:8] == F2; floppy sees addr[3:0],
    // fddn = addr[7], strobes gated by the chip select.
    wire        fdd_cs     = cs_addr[15:8] == 8'hF2;
    wire  [3:0] f_addr     = cs_addr[3:0];
    wire        f_read     = cs_rd & fdd_cs;
    wire        f_write    = cs_wr & fdd_cs;
    wire        fifo_read  = f_read  && &f_addr;      // floppy.v:187
    wire        fifo_write = f_write && &f_addr;      // floppy.v:188

    localparam logic [3:0] FS_IDLE = 4'd0, FS_FILL = 4'd1,
                           FS_WAIT = 4'd11,           // S_SD_WRITE_WAIT_FOR_EMPTY_FIFO
                           FS_UPD  = 4'd12;
    logic [3:0]  fstate = FS_IDLE;
    logic [14:0] sd_sector = 15'd0;
    logic        sel_drive = 1'b0;

    logic        dma_wr = 1'b0;
    logic [7:0]  dma_data = 8'h00;
    wire         fifo_empty;
    wire  [7:0]  fifo_q;
    wire [10:0]  fifo_count;

    // floppy.v: wrreq = fifo_from_pc ? fifo_pc_wr : fifo_write;
    //           rdreq = fifo_to_pc   ? fifo_pc_rd : fifo_read  (never to_pc here)
    wire fifo_from_pc = (fstate == FS_FILL);
    simple_fifo #(.width(8), .widthu(11)) fifo (
        .clk(clk), .rst_n(~reset), .sclr(fstate == FS_IDLE),
        .data(fifo_from_pc ? dma_data : cs_dout[7:0]),
        .wrreq(fifo_from_pc ? dma_wr : fifo_write),
        .rdreq(fifo_read),
        .q(fifo_q), .empty(fifo_empty), .full(), .usedw(fifo_count)
    );

    logic [7:0] fifo_readdata;                       // floppy.v:1175
    always_ff @(posedge clk)
        if (reset) fifo_readdata <= 8'h00;
        else       fifo_readdata <= fifo_q;

    // floppy.v:152 -- combinational, routed straight back (Peripherals mux:
    // not SCSI/OPNA/sndev -> mgmt_fdd_readdata).
    always_comb
        mgmt_din = (f_addr == 4'd0) ? {sel_drive, sd_sector}
                 : (&f_addr)        ? {8'h00, fifo_readdata}
                 :                    16'd1;

    // floppy.v:153 -- request[1] while in the write wait, [0] never here.
    assign fdd_request = {fstate == FS_WAIT, 1'b0};

    // The controller's own exit: S_SD_WRITE_WAIT_FOR_EMPTY_FIFO && fifo_empty.
    int  waits_left = 0;
    always_ff @(posedge clk)
        if (fstate == FS_WAIT && fifo_empty) begin
            fstate     <= FS_UPD;
            waits_left <= waits_left + 1;
        end

    int pops = 0, underflow = 0, stray_writes = 0;
    always_ff @(posedge clk) begin
        if (fifo_read) begin
            pops <= pops + 1;
            if (fifo_empty) underflow <= underflow + 1;
        end
        if (fifo_write) stray_writes <= stray_writes + 1;
    end

    // Optional firmware traffic on a non-F2 window (scsi_poll-like).
    int fw_period = 0, fw_ctr = 0;
    initial if (!$value$plusargs("FW_PERIOD=%d", fw_period)) fw_period = 0;
    always_ff @(posedge clk) begin
        fw_rd <= 1'b0;
        if (fw_period != 0) begin
            fw_ctr <= (fw_ctr + 1 >= fw_period) ? 0 : fw_ctr + 1;
            if (fw_ctr == 0) begin fw_rd <= 1'b1; fw_addr <= 16'hF40F; end
        end
    end

    // +TRACE=1: per-clock trace around the tail of each sector.
    int trace = 0;
    initial if (!$value$plusargs("TRACE=%d", trace)) trace = 0;
    always @(posedge clk)
        if (trace != 0 && dut.beat_cnt >= 11'd1021 && dut.st != 5'd0)
            $display("[%0t] st=%0d beat=%0d req=%b rd=%b a=%h din=%h wr_byte=%h sd_req=%b ack=%b done=%b wdata=%h cnt=%0d",
                     $time, dut.st, dut.beat_cnt, fdd_request, cs_rd, cs_addr, mgmt_din,
                     dut.wr_byte, sd_req, sd_ack, sd_done, sd_wdata, fifo_count);

    // ------------------------------------------------------------- drive
    int errors = 0;
    localparam logic [23:0] CARVE = 24'h620000;

    task automatic check(bit ok, string msg);
        if (!ok) begin errors++; $display("FAIL: %s", msg); end
    endtask

    function automatic logic [7:0] pat(int sec, int i);
        return (sec == 0) ? 8'(i*7 + 3) : 8'(i*13 + 5);
    endfunction

    // One sector, the way floppy.v does it: DMA fill (no mgmt), then the
    // write wait with request[1] up until the FIFO is empty.
    task automatic write_sector(int lba, int sec);
        int i, t;
        int wl0 = waits_left;
        @(posedge clk); fstate <= FS_FILL;
        for (i = 0; i < 1024; i++) begin
            @(posedge clk); dma_wr <= 1'b1; dma_data <= pat(sec, i);
        end
        @(posedge clk); dma_wr <= 1'b0;
        @(posedge clk);
        check(fifo_count == 11'd1024, $sformatf("FIFO holds %0d after fill", fifo_count));
        sd_sector <= 15'(lba);
        fstate    <= FS_WAIT;
        t = 0;
        while (waits_left == wl0 && t < 400000) begin @(posedge clk); t++; end
        check(waits_left != wl0, $sformatf("lba %0d: controller left the write wait", lba));
        // Let the server finish its last SDRAM write and settle in S_IDLE.
        t = 0;
        while (dut.st != 5'd0 && t < 10000) begin @(posedge clk); t++; end
        repeat (50) @(posedge clk);
        check(dut.st == 5'd0, "server back in S_IDLE");
        $display("lba %0d: pops=%0d underflow=%0d st=%0d", lba, pops, underflow, dut.st);
        @(posedge clk); fstate <= FS_IDLE;           // S_UPDATE_SECTOR -> ... -> idle
        @(posedge clk);
    endtask

    logic [15:0] snap [int];

    initial begin
        int i, a, lo, hi, bad;
        // Background: four sectors around the target plus a far word, so a
        // stray or off-by-one write has something to clobber.
        for (i = 36*1024; i < 40*1024; i++)
            sdr.store[int'(CARVE) + i] = {8'hA5, 8'(i)};
        sdr.store[int'(CARVE) - 1] = 16'h1234;
        sdr.store[int'(CARVE)]     = 16'h5678;
        snap = sdr.store;

        repeat (4) @(posedge clk);
        power_reset <= 0;
        repeat (4) @(posedge clk);
        reset <= 0;
        repeat (8) @(posedge clk);

        @(posedge clk); ctl_addr <= 7'h07; ctl_data <= 32'h1; ctl_pulse <= 1'b1;
        @(posedge clk); ctl_pulse <= 1'b0;
        repeat (400) @(posedge clk);
        check(dbg0[22], "mounted");

        write_sector(37, 0);
        write_sector(38, 1);

        check(underflow == 0, $sformatf("%0d pops on an empty FIFO", underflow));
        check(pops == 2048, $sformatf("pops=%0d, want 2048", pops));
        check(stray_writes == 0, "no F20F writes during a write drain");

        lo = int'(CARVE) + 37*1024;
        hi = int'(CARVE) + 39*1024;
        bad = 0;
        for (i = 0; i < 2048; i++) begin
            a = lo + i;
            if (!sdr.store.exists(a) || sdr.store[a] !== {8'h00, pat(i/1024, i%1024)}) begin
                if (bad < 16)
                    $display("MISMATCH word %06h (sec %0d byte %0d) = %04h want %04h", a,
                             i/1024, i%1024, sdr.store.exists(a) ? sdr.store[a] : 16'hxxxx,
                             {8'h00, pat(i/1024, i%1024)});
                bad++;
            end
        end
        check(bad == 0, $sformatf("%0d carve-out word(s) wrong in lba 37/38", bad));

        bad = 0;
        foreach (sdr.store[k]) begin
            if (k >= lo && k < hi) continue;
            if (!snap.exists(k)) begin
                if (bad < 16) $display("STRAY word %06h created = %04h", k, sdr.store[k]);
                bad++;
            end else if (sdr.store[k] !== snap[k]) begin
                if (bad < 16) $display("CLOBBER word %06h = %04h was %04h", k,
                                       sdr.store[k], snap[k]);
                bad++;
            end
        end
        check(bad == 0, $sformatf("%0d word(s) outside the sectors changed", bad));

        if (errors == 0) $display("tb_ramimg_write: ALL PASS");
        else             $display("tb_ramimg_write: %0d error(s)", errors);
        $finish;
    end

endmodule
`default_nettype wire
