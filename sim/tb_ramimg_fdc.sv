// tb_ramimg_fdc -- the RAM-image serve path, end to end, real RTL only.
//
//   fdd_ramimg  --(mgmt bus)-->  floppy.v  --(DRQ/DACK)-->  tb_fdd_dma_model
//        |                                                     |
//   port-E SDRAM stub                                    guest memory
//
// The point of the bench is the sector-local byte rotation seen on
// hardware: occasionally the guest's copy of a 1024-byte sector comes out
// as [byte N..1023, byte 0..N-1] for small N.
//
// The mechanism, reconstructed from the guest dump + RTL: while a serve
// pushes bytes at 0xF20F, core_top's management mux switches the bus
// address to the server's, but the read strobe is OR'd:
//     cs_mgmt_addr = ri_stb ? ri_mgmt_addr : mgmt_addr;
//     cs_mgmt_rd   = ri_mgmt_rd | (mgmt_rd & ~(ri_own & fw_fdd_hit));
// A firmware management read at a NON-F2 window (fw_fdd_hit=0 -- the
// scsi_poll/opna polls run F4/F5) during a push cycle therefore lands on
// the bus as a read of 0xF2xF -- floppy.v decodes nibble F as a FIFO pop.
// The coincident read+write stores the push but consumes the head byte:
// the fill ends 1 short, request stays high, the server re-serves the
// same LBA and appends f0..f_{n-1} -- the exact wraparound rotation.
//
// This bench reproduces it: a firmware-traffic generator raises mgmt_rd
// pulses at F4/F5 addresses at a configurable rate, the bench wires the
// real core_top mux equations, and the guest buffer is diffed against
// the image.
//
// Plusargs:
//   +FW_PERIOD=n   firmware non-F2 read every n clocks (0 = silent)
//   +FIX=n         apply the fix (mask fw strobes while ri_stb)
//   +TRACE=1       dump every push/pop/serve event
//
// Build:
//   build: verilator --binary --timing -Wno-fatal --top-module tb_ramimg_fdc \
//     fpga/core/common/floppy.v fpga/core/common/simple_fifo.v \
//     fpga/core/fdd_ramimg.sv sim/stub_dcfifo.sv sim/tb_fdd_dma_model.sv \
//     sim/tb_ramimg_fdc.sv -o tb_ramimg_fdc --Mdir /tmp/obj_ramimgfdc

`timescale 1ns/1ps
`default_nettype none

package ramimg_jtag_pkg;
    logic tck = 1'b0, tdi = 1'b0, cdr = 1'b0, sdr = 1'b0;
endpackage

module sld_virtual_jtag_basic #(
    parameter sld_mfg_id = 0, parameter sld_type_id = 0,
    parameter sld_version = 0, parameter sld_instance_index = 0,
    parameter sld_auto_instance_index = "NO", parameter sld_ir_width = 1,
    parameter sld_sim_n_scan = 0, parameter sld_sim_action = "UNUSED",
    parameter sld_sim_total_length = 0, parameter lpm_type = "",
    parameter lpm_hint = "UNUSED"
) (
    output tck, output tdi, output [sld_ir_width-1:0] ir_in,
    input  tdo, input [sld_ir_width-1:0] ir_out,
    output virtual_state_cdr, output virtual_state_sdr,
    output virtual_state_e1dr, output virtual_state_pdr,
    output virtual_state_e2dr, output virtual_state_udr,
    output virtual_state_cir, output virtual_state_uir,
    output tms, output jtag_state_tlr, output jtag_state_rti,
    output jtag_state_sdrs, output jtag_state_cdr, output jtag_state_sdr,
    output jtag_state_e1dr, output jtag_state_pdr, output jtag_state_e2dr,
    output jtag_state_udr, output jtag_state_sirs, output jtag_state_cir,
    output jtag_state_sir, output jtag_state_e1ir, output jtag_state_pir,
    output jtag_state_e2ir, output jtag_state_uir
);
    assign tck                = ramimg_jtag_pkg::tck;
    assign tdi                = ramimg_jtag_pkg::tdi;
    assign ir_in              = {sld_ir_width{1'b0}};
    assign virtual_state_cdr  = ramimg_jtag_pkg::cdr;
    assign virtual_state_sdr  = ramimg_jtag_pkg::sdr;
    assign virtual_state_e1dr = 1'b0;
    assign virtual_state_pdr  = 1'b0;
    assign virtual_state_e2dr = 1'b0;
    assign virtual_state_udr  = 1'b0;
    assign virtual_state_cir  = 1'b0;
    assign virtual_state_uir  = 1'b0;
    assign tms                = 1'b0;
    assign jtag_state_tlr     = 1'b0;
    assign jtag_state_rti     = 1'b0;
    assign jtag_state_sdrs    = 1'b0;
    assign jtag_state_cdr     = 1'b0;
    assign jtag_state_sdr     = 1'b0;
    assign jtag_state_e1dr    = 1'b0;
    assign jtag_state_pdr     = 1'b0;
    assign jtag_state_e2dr    = 1'b0;
    assign jtag_state_udr     = 1'b0;
    assign jtag_state_sirs    = 1'b0;
    assign jtag_state_cir     = 1'b0;
    assign jtag_state_sir     = 1'b0;
    assign jtag_state_e1ir    = 1'b0;
    assign jtag_state_pir     = 1'b0;
    assign jtag_state_e2ir    = 1'b0;
    assign jtag_state_uir     = 1'b0;
endmodule

module tb_ramimg_fdc;
    import ramimg_jtag_pkg::*;

    localparam logic [23:0] BASE = 24'h620000;
    localparam int          IMG  = 32'd1261568;   // 77*8*2*1024

    logic clk = 0, rst = 1, power_rst = 1;
    always #10 clk = ~clk;                        // 50 MHz chipset clock

    // ------------------------------------------------------------------
    // The real management arbiter (fpga/core/mgmt_arb.sv) between the
    // bench's firmware-traffic generator and fdd_ramimg -- the bench
    // exercises the shipped gate, not a copy of it.
    // ------------------------------------------------------------------
    wire [15:0] ri_addr, ri_dout;
    wire        ri_wr, ri_rd;
    wire [15:0] mgmt_rdata;
    wire        ri_own;

    logic        fw_rd = 1'b0, fw_wr = 1'b0;
    logic [15:0] fw_addr = 16'hF400;             // SCSI_TARGET window
    logic [15:0] fw_dout = 16'h0000;

    wire [15:0] cs_mgmt_addr, cs_mgmt_dout;
    wire        cs_mgmt_rd, cs_mgmt_wr;
    wire        cs_mgmt_f2 = (cs_mgmt_addr[15:8] == 8'hF2);

    mgmt_arb u_mgmt_arb (
        .fw_addr (fw_addr),   .fw_dout (fw_dout),
        .fw_rd   (fw_rd_any), .fw_wr   (fw_wr),
        .ri_addr (ri_addr),   .ri_dout (ri_dout),
        .ri_rd   (ri_rd),     .ri_wr   (ri_wr),   .ri_own (ri_own),
        .cs_addr (cs_mgmt_addr), .cs_dout (cs_mgmt_dout),
        .cs_rd   (cs_mgmt_rd),   .cs_wr   (cs_mgmt_wr)
    );

    // ------------------------------------------------------------------
    // SDRAM port-E model. One word per image byte, low byte live.
    // ------------------------------------------------------------------
    logic [7:0]  sdram [0:(BASE + IMG + 4095)];
    logic        sd_req, sd_we, sd_ack, sd_rvalid, sd_done;
    logic [23:0] sd_addr;
    logic  [3:0] sd_len;
    logic [15:0] sd_wdata, sd_rdata;
    int          rd_delay = -1;
    logic [23:0] rd_addr_q = 0;
    int          ack_wait = 0;
    int          sd_stall = 0;

    always_ff @(posedge clk) begin
        sd_ack    <= 1'b0;
        sd_rvalid <= 1'b0;
        sd_done   <= 1'b0;
        if (rd_delay > 0) begin
            rd_delay <= rd_delay - 1;
            if (rd_delay == 1) begin
                sd_rvalid <= 1'b1;
                sd_rdata  <= {8'h00, sdram[rd_addr_q]};
                sd_done   <= 1'b1;
                rd_delay  <= -1;
            end
        end
        if (sd_req && !sd_ack && rd_delay < 0) begin
            if (ack_wait < sd_stall) begin
                ack_wait <= ack_wait + 1;
            end else begin
                ack_wait <= 0;
                sd_ack   <= 1'b1;
                if (sd_we) begin
                    sdram[sd_addr] <= sd_wdata[7:0];
                    sd_done        <= 1'b1;
                end else begin
                    rd_addr_q <= sd_addr;
                    rd_delay  <= 4;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // fdd_ramimg: request bits come straight off floppy.request, exactly
    // like core_top's mgmt_req[7:6].
    // ------------------------------------------------------------------
    wire  [1:0] fdd_request;
    logic       ctl_pulse = 0;
    logic [6:0] ctl_addr  = 0;
    logic [31:0] ctl_data = 0;
    wire        greset;
    wire [31:0] dbg0, dbg1, dbg2;

    fdd_ramimg #(.CARVE_BASE(BASE), .IMG_BYTES(IMG)) u_ramimg (
        .clk(clk), .reset(rst), .power_reset(power_rst),
        .fdd_request(fdd_request),
        .mgmt_addr(ri_addr), .mgmt_dout(ri_dout),
        .mgmt_wr(ri_wr), .mgmt_rd(ri_rd), .mgmt_din(mgmt_rdata),
        .fw_busy(1'b0),
        .sd_req(sd_req), .sd_we(sd_we), .sd_addr(sd_addr),
        .sd_len(sd_len), .sd_wdata(sd_wdata), .sd_ack(sd_ack),
        .sd_rvalid(sd_rvalid), .sd_rdata(sd_rdata), .sd_done(sd_done),
        .ctl_pulse(ctl_pulse), .ctl_addr(ctl_addr), .ctl_data(ctl_data),
        .own(ri_own), .guest_reset_req(greset),
        .dbg0(dbg0), .dbg1(dbg1), .dbg2(dbg2)
    );

    // ------------------------------------------------------------------
    // floppy.v -- the real 765A core with the real FIFO.
    // ------------------------------------------------------------------
    logic [2:0]  fd_addr;
    logic        fd_write = 0, fd_read = 0;
    logic [7:0]  fd_wdata = 8'h00;
    wire  [7:0]  fd_rdata;
    wire         fd_irq, fd_busy;
    wire         fdc_dreq, fdc_ack_p, fdc_tc_p;
    wire  [7:0]  fdc_dma_w, fdc_dma_r;

    floppy #(.NOT_READY_ENDS_COMMAND(1)) u_floppy (
        .clk            (clk),
        .rst_n          (~rst),
        .dma_req        (fdc_dreq),
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
        .mgmt_address   (cs_mgmt_addr[3:0]),
        .mgmt_fddn      (cs_mgmt_addr[7]),
        .mgmt_write     (cs_mgmt_wr & cs_mgmt_f2),
        .mgmt_writedata (cs_mgmt_dout),
        .mgmt_read      (cs_mgmt_rd & cs_mgmt_f2),
        .mgmt_readdata  (mgmt_rdata),
        .wp             (2'b00),
        .clock_rate     (28'd2000),
        .turbo          (1'b0),
        .request        (fdd_request),
        .snd_step(), .snd_head(), .snd_xfer(), .snd_motor()
    );

    // ------------------------------------------------------------------
    // DMAC: the bench model, feed side off -- fdd_ramimg feeds the FIFO.
    // ------------------------------------------------------------------
    wire        dma_mem_wr;
    wire [19:0] dma_mem_addr;
    wire  [7:0] dma_mem_wd;
    logic [7:0] dma_mem [0:262143];
    logic       dma_wr_p = 0;
    logic [7:0] dma_port = 0, dma_wd = 0;

    always_ff @(posedge clk)
        if (dma_mem_wr) dma_mem[dma_mem_addr] <= dma_mem_wd;

    tb_fdd_dma_model u_dma (
        .clk        (clk),
        .io_wr      (dma_wr_p), .io_rd(1'b0),
        .io_addr    (dma_port), .io_wdata(dma_wd), .io_rdata(),
        .drq        (fdc_dreq), .dack(fdc_ack_p), .tc(fdc_tc_p),
        .ddata_i    (fdc_dma_w), .ddata_o(fdc_dma_r),
        .mem_wr     (dma_mem_wr), .mem_addr(dma_mem_addr),
        .mem_wdata  (dma_mem_wd), .mem_rdata(dma_mem[dma_mem_addr]),
        .feed_en    (1'b0), .sec_req(2'b00),
        .mgmt_wr(), .mgmt_addr(), .mgmt_wdata(), .mgmt_rd(),
        .mgmt_rdata (16'h0000),
        .media_1024 (1'b1),
        .feed_lba(), .feed_idx(), .feed_byte(8'h00)
    );

    // ------------------------------------------------------------------
    // Firmware-traffic generator: non-F2-window management reads -- the
    // scsi_poll / opna poll shape. Two modes:
    //   +FW_PERIOD=n : one read every n clocks
    //   +FW_ONPUSH=k : a read on every k-th sd_rvalid cycle -- the
    //                  deterministic collision with the FIFO push
    // The firmware's target address never touches F2, so the current mux
    // lets every strobe through.
    // ------------------------------------------------------------------
    int  fw_period = 0, fw_onpush = 0;
    int  fw_timer  = 0, push_seen = 0;
    int  n_fw_rd   = 0;
    // onpush mode is combinational: the push itself is a same-cycle
    // response to sd_rvalid, so the firmware strobe has to land on it.
    wire fw_rd_push = (fw_onpush > 0) && sd_rvalid && (push_seen % fw_onpush == 0);
    wire fw_rd_any  = fw_rd | fw_rd_push;
    always @(posedge clk) begin
        fw_rd <= 1'b0;
        if (sd_rvalid) push_seen <= push_seen + 1;
        if (fw_rd_push) begin
            fw_addr <= (fw_addr == 16'hF400) ? 16'hF500 : 16'hF400;
            n_fw_rd <= n_fw_rd + 1;
        end else if (fw_period > 0) begin
            fw_timer <= fw_timer + 1;
            if (fw_timer >= fw_period) begin
                fw_timer <= 0;
                fw_rd    <= 1'b1;
                fw_addr  <= (fw_addr == 16'hF400) ? 16'hF500 : 16'hF400;
                n_fw_rd  <= n_fw_rd + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Witnesses.
    // ------------------------------------------------------------------
    int n_push = 0, n_pop = 0, n_dma_wr = 0, n_reserve = 0, n_popfill = 0;
    int last_serve_lba = -1;
    bit trace = 0;

    wire fifo_rdreq = u_floppy.fifo_to_floppy_inst.rdreq;
    wire fifo_wrreq = u_floppy.fifo_to_floppy_inst.wrreq;
    always @(posedge clk) begin
        if (fifo_wrreq) begin
            n_push++;
            if (trace) $display("  PUSH  t=%0t fifocnt=%0d beat=%0d d=%02h",
                                $time, u_floppy.fifo_count,
                                u_ramimg.beat_cnt, cs_mgmt_dout[7:0]);
        end
        if (fifo_rdreq && !u_floppy.fifo_empty) begin
            n_pop++;
            if (u_floppy.state != 4'd6) begin
                n_popfill++;
                $display("  !! FILL-TIME POP t=%0t fdcst=%0d fifocnt=%0d pcrd=%b mgmtrd=%b fwrd=%b fwaddr=%04h",
                         $time, u_floppy.state, u_floppy.fifo_count,
                         u_floppy.fifo_pc_rd, u_floppy.fifo_read, fw_rd_any, fw_addr);
            end else if (trace)
                $display("  POP   t=%0t q=%02h fifocnt=%0d",
                         $time, u_floppy.fifo_q, u_floppy.fifo_count);
        end
        if (dma_mem_wr) n_dma_wr++;
    end

    // A serve starts on the server's F200 management read.
    wire serve_lba_rd = ri_rd & (ri_addr == 16'hF200);
    always @(posedge clk) begin
        if (serve_lba_rd) begin
            if (last_serve_lba == int'(mgmt_rdata[14:0]) &&
                u_floppy.fifo_count < 11'd1024) begin
                n_reserve++;
                $display("  !! RESERVE lba=%0d t=%0t fifocnt=%0d",
                         mgmt_rdata[14:0], $time, u_floppy.fifo_count);
            end
            last_serve_lba <= int'(mgmt_rdata[14:0]);
            if (trace) $display("  SERVE lba=%0d t=%0t", mgmt_rdata[14:0], $time);
        end
    end

    // ------------------------------------------------------------------
    // io tasks (same shape as tb_fdd_144).
    // ------------------------------------------------------------------
    task automatic wr(input int which, input [7:0] v);
        fd_addr = which[2:0]; fd_wdata = v;
        @(negedge clk); fd_write = 1'b1;
        @(negedge clk); fd_write = 1'b0; #1;
    endtask
    task automatic rd(input int which, output logic [7:0] v);
        fd_addr = which[2:0];
        @(negedge clk); fd_read = 1'b1;
        @(negedge clk); fd_read = 1'b0; #1; v = fd_rdata; #1;
    endtask
    task automatic dma_wr(input [7:0] port, input [7:0] v);
        @(negedge clk); dma_port = port; dma_wd = v; dma_wr_p = 1'b1;
        @(negedge clk); dma_wr_p = 1'b0; #1;
    endtask
    task automatic ctl_write(input logic [31:0] v);
        @(negedge clk); ctl_addr = 7'h07; ctl_data = v; ctl_pulse = 1'b1;
        @(negedge clk); ctl_pulse = 1'b0;
    endtask

    // PC-98 2HD read: 1024-byte sectors, spt=8, N=3, EOT=8.
    // DMA buffer at 0x10000 (page 1, base 0), count = 1024.
    task automatic read2hd(input [7:0] c, input [7:0] h, input [7:0] r,
                           output [7:0] st0, output [7:0] st1, output [7:0] st2);
        logic [7:0] msr;
        int guard;
        dma_wr(8'h19, 8'h00);                    // clear byte pointer
        dma_wr(8'h17, 8'h46);                    // single write-transfer, ch2
        dma_wr(8'h09, 8'h00); dma_wr(8'h09, 8'h00);  // base 0x0000
        dma_wr(8'h23, 8'h01);                    // page 1 -> 0x10000
        dma_wr(8'h0B, 8'hFF); dma_wr(8'h0B, 8'h03);  // count 0x03FF = 1024
        dma_wr(8'h15, 8'h02);                    // unmask ch2
        wr(5, 8'h46); wr(5, (h & 8'h1) << 2); wr(5, c); wr(5, h);
        wr(5, r);     wr(5, 8'h03);              wr(5, 8'd8); wr(5, 8'h1B);
        wr(5, 8'hFF);
        guard = 0;
        while (!fd_irq && guard < 400_000) begin @(negedge clk); guard++; end
        #1;
        rd(5, st0); rd(5, st1); rd(5, st2);
        for (int b = 0; b < 4; b++) rd(5, msr);
        rd(4, msr);
    endtask

    int errors = 0;
    task automatic want(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            errors++;
            $display("  FAIL %-46s got=%h want=%h", what, got, exp);
        end else
            $display("  ok   %-46s %h", what, got);
    endtask

    // Check one landed sector against the carve-out image; on mismatch,
    // identify the rotation amount.
    task automatic check_sector(input int lba, input int bufbase, input int n);
        int bad = 0; int first_bad = -1; int rot = -1;
        for (int i = 0; i < n; i++) begin
            if (dma_mem[bufbase+i] !== sdram[BASE + lba*1024 + i]) begin
                bad++;
                if (first_bad < 0) first_bad = i;
            end
        end
        for (int r = 0; r < n; r++)
            if (dma_mem[bufbase] === sdram[BASE + lba*1024 + r]) rot = r;
        if (bad == 0)
            $display("  ok   sector LBA%0d: %0d bytes identical", lba, n);
        else begin
            errors++;
            $display("  FAIL sector LBA%0d: %0d mismatches, head = img+%0d (rot %0d)",
                     lba, bad, rot, rot);
            $write("    buf[0..7]   = ");
            for (int i = 0; i < 8; i++) $write("%02h ", dma_mem[bufbase+i]);
            $write("\n    img[0..7]   = ");
            for (int i = 0; i < 8; i++) $write("%02h ", sdram[BASE + lba*1024 + i]);
            $write("\n    buf[end-7:] = ");
            for (int i = n-8; i < n; i++) $write("%02h ", dma_mem[bufbase+i]);
            $write("\n    img[end-7:] = ");
            for (int i = n-8; i < n; i++) $write("%02h ", sdram[BASE + lba*1024 + i]);
            $display("");
        end
    endtask

    initial begin
        logic [7:0] st0, st1, st2;
        int v;
        int got_fw;
        got_fw = $value$plusargs("FW_PERIOD=%d", fw_period)
               | $value$plusargs("FW_ONPUSH=%d", fw_onpush);
        // Default: a firmware non-F2 read on ~every tenth push -- the
        // collision the arbiter exists for. 0 disables the traffic.
        if (!got_fw) fw_onpush = 97;
        if ($value$plusargs("SD_STALL=%d", v)) sd_stall = v;
        if ($value$plusargs("TRACE=%d", v))    trace = v;

        // The image: byte i of sector L = L ^ i[7:0] -- every byte's value
        // names its position, so any reordering shows up immediately.
        for (longint a = 0; a < IMG; a++)
            sdram[BASE + a] = 8'((a >> 10) ^ a);

        repeat (4) @(posedge clk);
        power_rst = 0; rst = 0;
        repeat (4) @(negedge clk);

        // Mount through the server's own control path.
        ctl_write(32'h0000_0001);
        repeat (600) @(negedge clk);
        want("mounted", dbg0[22], 1);
        want("media present A", u_floppy.media_present[0], 1);
        want("1024-byte flag", u_floppy.media_is_1024[0], 1);
        want("spt=8", u_floppy.media_sectors_per_track[0], 8);

        wr(2, 8'h3C);                            // DOR: enable, irq, motor

        // ---- sector 0 read: C0 H0 R1 = LBA 0 ------------------------------
        $display("--- read LBA0 (fw_period=%0d onpush=%0d stall=%0d) ---",
                 fw_period, fw_onpush, sd_stall);
        read2hd(8'd0, 8'd0, 8'd1, st0, st1, st2);
        want("st0 clean", st0 & 8'hC0, 8'h00);
        check_sector(0, 20'h10000, 1024);
        want("no same-LBA re-serve", n_reserve, 0);
        want("no fill-time pops", n_popfill, 0);
        $display("  pushes=%0d pops=%0d dma_writes=%0d fw_rds=%0d fillpops=%0d reserves=%0d",
                 n_push, n_pop, n_dma_wr, n_fw_rd, n_popfill, n_reserve);

        // ---- a mid-disk sector: C4 H0 R5 -> LBA (4*2+0)*8 + 4 = 68 --------
        $display("--- read LBA68 ---");
        n_push = 0; n_pop = 0; n_dma_wr = 0; n_reserve = 0; n_popfill = 0;
        read2hd(8'd4, 8'd0, 8'd5, st0, st1, st2);
        want("st0 clean", st0 & 8'hC0, 8'h00);
        check_sector(68, 20'h10000, 1024);
        $display("  pushes=%0d pops=%0d fillpops=%0d reserves=%0d",
                 n_push, n_pop, n_popfill, n_reserve);

        // ---- head 1: C0 H1 R3 -> LBA 10 -----------------------------------
        $display("--- read LBA10 (head1) ---");
        n_push = 0; n_pop = 0; n_dma_wr = 0; n_reserve = 0; n_popfill = 0;
        read2hd(8'd0, 8'd1, 8'd3, st0, st1, st2);
        want("st0 clean", st0 & 8'hC0, 8'h00);
        check_sector(10, 20'h10000, 1024);
        $display("  pushes=%0d pops=%0d fillpops=%0d reserves=%0d",
                 n_push, n_pop, n_popfill, n_reserve);

        if (errors == 0) $display("PASS tb_ramimg_fdc");
        else             $display("FAILED tb_ramimg_fdc: %0d", errors);
        $finish;
    end

    initial begin #400_000_000; $display("FAILED tb_ramimg_fdc: timeout"); $finish; end
endmodule

`default_nettype wire
