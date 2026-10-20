// tb_ramimg_fdc -- the RAM-image serve path, end to end, real RTL only.
//
//   fdd_ramimg --(mgmt bus)-->  floppy.v  --(DRQ/DACK)-->  tb_fdd_dma_model
//        |                                                     |
//   port-E on the REAL sdram_shim+sdram_mp+model          guest memory
//        |
//   port-D contender (display-fetch-shaped bursts)
//
// The point of the bench is byte-exactness of the delivered sector under the
// conditions the hardware loads the machine with. Two earlier hardware bugs
// live in this path and each left a check behind:
//
//   * the sector-local byte rotation -- while a serve pushed bytes at
//     0xF20F a firmware read of a NON-F2 window could land on the bus in
//     the same cycle and floppy.v decoded it as a nibble-F FIFO pop; the
//     fill ended short, the level-triggered re-serve appended the head
//     bytes and the guest received the sector rotated. mgmt_arb fences the
//     strobes now (sim/tb_ramimg_fdc was the reproduction).
//
//   * the wrong-value single byte -- the push used to present sd_rdata
//     combinationally on the rvalid cycle. sd_rdata is sdram_mp's SHARED
//     read-data register, negedge-captured, so the FIFO's capture sat half
//     a clock off the launch with the previous transaction's word (any
//     port's) as the failure value. The serve now latches the beat and
//     pushes from the register (fdd_ramimg S_RD_PUSH).
//
// What makes this bench able to see that class at all: the SDRAM is the
// REAL six-port controller and model -- not an instant-answer stub -- so
// port E's beats interleave with refresh and with a display-fetch-shaped
// contender on port D, exactly the arbitration the serve runs under on
// hardware, and the multi-sector read exercises the fill/drain alternation
// (the FIFO slot pattern and the request-drop windows between sectors).
//
// Plusargs:
//   +FW_PERIOD=n   firmware non-F2 read every n clocks (0 = silent)
//   +FW_ONPUSH=k   a read on every k-th push cycle -- the deterministic
//                  collision with the FIFO push
//   +D_PERIOD=n    port-D contender: one 16-word burst every n clocks
//                  (0 = contender off)
//   +TRACE=1       dump every push/pop/serve event
//
// Build (CI shape):
//   build: verilator --binary --timing -Wno-fatal --top-module tb_ramimg_fdc
//     fpga/core/common/floppy.v fpga/core/common/simple_fifo.v
//     fpga/core/mgmt_arb.sv fpga/core/fdd_ramimg.sv
//     fpga/core/sdram_shim.sv fpga/core/sdram_mp.sv sim/sdram_model.sv
//     sim/stub_dcfifo.sv sim/tb_fdd_dma_model.sv
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
    input tdo, input [sld_ir_width-1:0] ir_out,
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

    // The image the carve-out is loaded with and every check diffs against.
    logic [7:0] img [0:IMG-1];

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
        .fw_rd   (fw_rd),     .fw_wr   (fw_wr),
        .ri_addr (ri_addr),   .ri_dout (ri_dout),
        .ri_rd   (ri_rd),     .ri_wr   (ri_wr),   .ri_own (ri_own),
        .cs_addr (cs_mgmt_addr), .cs_dout (cs_mgmt_dout),
        .cs_rd   (cs_mgmt_rd),   .cs_wr   (cs_mgmt_wr)
    );

    // ------------------------------------------------------------------
    // The REAL SDRAM chain: sdram_shim (six ports) + sdram_mp + the
    // behavioural part. Port E is the server under test; port D runs the
    // display-fetch-shaped contender below; A/B/C/F idle.
    // ------------------------------------------------------------------
    logic        sd_req, sd_we, sd_ack, sd_rvalid, sd_done;
    logic [23:0] sd_addr;
    logic  [3:0] sd_len;
    logic [15:0] sd_wdata, sd_rdata;

    logic        d_req = 1'b0;
    logic [23:0] d_addr = 24'h400000;
    logic  [3:0] d_len  = 4'd15;
    wire         d_ack, d_rvalid, d_done;

    wire [12:0] s_a;
    wire [1:0]  s_ba;
    wire        s_cke, s_ras_n, s_cas_n, s_we_n, s_dq_io;
    wire [1:0]  s_dqm = 2'b00;
    wire [15:0] s_dq_out, s_dq_in;

    sdram_shim #(
        .INIT_NOP(64), .REFRESH_INT(320)
    ) u_shim (
        .sdram_clock(clk), .sdram_reset(power_rst),
        // port A: the guest's legacy single-word interface -- idle here
        .address(25'd0), .access_num(10'd0),
        .data_in(16'd0), .data_out(), .data_in_hi(16'd0), .data_out_hi(),
        .a_rvalid(), .a_beat(),
        .write_request(1'b0), .read_request(1'b0), .enable_refresh(1'b0),
        .write_flag(), .read_flag(), .idle(), .refresh_mode(),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(),
        .sdram_ras(s_ras_n), .sdram_cas(s_cas_n), .sdram_we(s_we_n),
        .sdram_ba(s_ba), .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out),
        .sdram_dq_io(s_dq_io),
        // B font fetch, C cg window -- idle
        .b_req(1'b0), .b_addr(24'd0), .b_len(4'd0),
        .b_ack(), .b_rvalid(), .b_rdata(), .b_done(),
        .c_req(1'b0), .c_addr(24'd0), .c_len(4'd0),
        .c_ack(), .c_rvalid(), .c_rdata(), .c_done(),
        // D: the contender
        .d_req(d_req), .d_addr(d_addr), .d_len(d_len),
        .d_ack(d_ack), .d_rvalid(d_rvalid), .d_rdata(), .d_done(d_done),
        // E: the server under test
        .e_req(sd_req), .e_we(sd_we), .e_addr(sd_addr), .e_len(sd_len),
        .e_wdata(sd_wdata), .e_ack(sd_ack), .e_rvalid(sd_rvalid),
        .e_rdata(sd_rdata), .e_done(sd_done),
        // F: the CPU cache -- idle
        .f_req(1'b0), .f_we(1'b0), .f_addr(24'd0), .f_len(4'd0),
        .f_wdata0(16'd0), .f_wdata1(16'd0),
        .f_ack(), .f_rvalid(), .f_rdata(), .f_done(),
        .a_wr_v(), .a_wr_addr(), .a_wr_len()
    );

    sdram_model #(
        .ROW_BITS(13), .COL_BITS(9), .BANK_BITS(2), .DQ_BITS(16),
        .T_RFC(4),                       // match the shim's tightened timing
        .PHYSICAL_DQ(1'b0)
    ) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ------------------------------------------------------------------
    // Port-D contender: display-fetch-shaped -- a sixteen-word burst every
    // D_PERIOD clocks at a walking address, data consumed and discarded.
    // This is the arbitration load the serve runs under on hardware: port
    // E's single-word reads queue behind these bursts and the refreshes
    // they collide with, so the shared read-data register changes hands
    // between port-E beats exactly the way it does in the machine.
    // ------------------------------------------------------------------
    int d_period = 34;
    int d_timer  = 0;
    int d_bursts = 0, d_beats = 0;
    always_ff @(posedge clk) begin
        if (power_rst) begin
            d_req <= 1'b0;
        end else if (!d_req) begin
            if (d_period > 0) begin
                if (d_timer >= d_period) begin
                    d_timer  <= 0;
                    d_req    <= 1'b1;
                    d_addr   <= 24'h400000 + ((d_bursts * 16) & 24'h0FFFFF);
                    d_len    <= 4'd15;
                end else
                    d_timer <= d_timer + 1;
            end
        end else if (d_ack) begin
            d_req <= 1'b0;
        end
        if (d_rvalid) d_beats <= d_beats + 1;
        if (d_done)   d_bursts <= d_bursts + 1;
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
    //   +FW_ONPUSH=k : a read on every k-th push cycle -- the
    //                  deterministic collision with the FIFO push
    // The firmware's target address never touches F2, so the current mux
    // lets every strobe through.
    // ------------------------------------------------------------------
    int  fw_period = 0, fw_onpush = 0;
    int  fw_timer  = 0, push_seen = 0;
    int  n_fw_rd   = 0;
    // onpush mode is combinational: the push fires from S_RD_PUSH the
    // clock after its rvalid, so the firmware strobe lands beside it.
    wire fw_rd_push = (fw_onpush > 0) && ri_wr && (ri_addr == 16'hF20F)
                      && (push_seen % fw_onpush == 0);
    wire fw_rd_any  = fw_rd | fw_rd_push;
    always @(posedge clk) begin
        fw_rd <= 1'b0;
        if (ri_wr && ri_addr == 16'hF20F) push_seen <= push_seen + 1;
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
    int n_push_drain = 0, n_fifo_over = 0, n_dropped_push = 0;
    int last_serve_lba = -1;
    bit trace = 0;

    wire fifo_rdreq = u_floppy.fifo_to_floppy_inst.rdreq;
    wire fifo_wrreq = u_floppy.fifo_to_floppy_inst.wrreq;
    int n_wr_pc = 0, n_wr_srv = 0;
    always @(posedge clk) begin
        if (u_floppy.fifo_from_pc && fifo_wrreq) begin
            n_wr_pc++;
            if (trace) $display("  WRPC  t=%0t fdcst=%0d fifocnt=%0d pcwr=%b ndmaw=%b ack=%b term=%b",
                                $time, u_floppy.state, u_floppy.fifo_count,
                                u_floppy.fifo_pc_wr, u_floppy.ndma_write,
                                fdc_ack_p, u_floppy.dma_has_terminated);
        end
        if (!u_floppy.fifo_from_pc && fifo_wrreq) n_wr_srv++;
    end

    always @(posedge clk) begin
        if (fifo_wrreq) begin
            n_push++;
            // The serve-side write must be in the fill state with room; the
            // fifo_srv_wr gate in floppy.v makes anything else a dropped
            // byte (visible as a short fill / re-serve), never an insert.
            if (u_floppy.state != 4'd5) begin
                n_push_drain++;
                $display("  !! PUSH OUTSIDE FILL t=%0t fdcst=%0d fifocnt=%0d d=%02h",
                         $time, u_floppy.state, u_floppy.fifo_count,
                         u_floppy.mgmt_writedata[7:0]);
            end
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
        if (u_floppy.fifo_count > 11'd2047) n_fifo_over++;
        // A serve-side strobe the floppy's gate refused: the server pushed
        // outside the fill window and the byte was dropped on the floor.
        if ((cs_mgmt_wr & cs_mgmt_f2 & &cs_mgmt_addr[3:0])
            && u_floppy.state != 4'd5)
            n_dropped_push++;
        if (dma_mem_wr) n_dma_wr++;
    end

    // A serve starts on the server's F200 management read.
    wire serve_lba_rd = ri_rd & (ri_addr == 16'hF200);

    // Debug: an aborted serve -- the server left the read loop with a
    // partial sector. Name the floppy state, fifo level and request bits
    // at the moment of the abort. (Trace-gated: a legal mid-serve request
    // drop -- a DOR reset landing inside a fill -- reports the same way.)
    always @(posedge clk) begin
        if ((u_ramimg.st == 5'd5 || u_ramimg.st == 5'd6 || u_ramimg.st == 5'd19)
            && u_ramimg.beat_cnt < 11'd1023
            && u_ramimg.beat_cnt > 0) begin
            if (!fdd_request[0] || &u_ramimg.wd)
                $display("  %s t=%0t beat=%0d req=%b wd=%h fdcst=%0d fifocnt=%0d",
                         trace ? "!! SERVE ABORT" : "    (serve abort)",
                         $time, u_ramimg.beat_cnt, fdd_request[0], u_ramimg.wd,
                         u_floppy.state, u_floppy.fifo_count);
        end
    end
    always @(posedge clk) begin
        if (serve_lba_rd) begin
            if (trace)
                $display("  SERVE lba=%0d t=%0t fdcst=%0d fifocnt=%0d sec=%0d eot=%0d pend=%h",
                         mgmt_rdata[14:0], $time, u_floppy.state, u_floppy.fifo_count,
                         u_floppy.sector[0], u_floppy.eot[0], u_floppy.pending_command);
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

    // Program ch2 for n bytes to 0x10000, then one READ DATA.
    task automatic read2hd_n(input [7:0] c, input [7:0] h, input [7:0] r,
                             input [7:0] eot, input int n,
                             output [7:0] st0, output [7:0] st1, output [7:0] st2);
        logic [7:0] msr;
        int guard;
        dma_wr(8'h19, 8'h00);                    // clear byte pointer
        dma_wr(8'h17, 8'h46);                    // single write-transfer, ch2
        dma_wr(8'h09, 8'h00); dma_wr(8'h09, 8'h00);  // base 0x0000
        dma_wr(8'h23, 8'h01);                    // page 1 -> 0x10000
        dma_wr(8'h0B, (n-1) & 8'hFF); dma_wr(8'h0B, ((n-1) >> 8) & 8'hFF);  // count n-1: n bytes
        dma_wr(8'h15, 8'h02);                    // unmask ch2
        wr(5, 8'h46); wr(5, (h & 8'h1) << 2); wr(5, c); wr(5, h);
        wr(5, r);     wr(5, 8'h03);              wr(5, eot); wr(5, 8'h1B);
        wr(5, 8'hFF);
        // The guard scales with the byte count: under the port-D contender
        // a serve runs ~50 clocks a byte, and a whole track is ~8x the wait
        // of a single sector.
        guard = 0;
        while (!fd_irq && guard < 100_000 + 80*n) begin @(negedge clk); guard++; end
        #1;
        rd(5, st0); rd(5, st1); rd(5, st2);
        for (int b = 0; b < 4; b++) rd(5, msr);
        rd(4, msr);
    endtask

    task automatic read2hd(input [7:0] c, input [7:0] h, input [7:0] r,
                           output [7:0] st0, output [7:0] st1, output [7:0] st2);
        read2hd_n(c, h, r, 8'd8, 1024, st0, st1, st2);
    endtask

    int errors = 0;
    task automatic want(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            errors++;
            $display("  FAIL %-46s got=%h want=%h", what, got, exp);
        end else
            $display("  ok   %-46s %h", what, got);
    endtask

    // Check landed sectors against the image; on mismatch, identify the
    // rotation amount.
    task automatic check_sector(input int lba, input int bufbase, input int n);
        int bad = 0; int first_bad = -1; int rot = -1;
        for (int i = 0; i < n; i++) begin
            if (dma_mem[bufbase+i] !== img[lba*1024 + i]) begin
                bad++;
                if (first_bad < 0) first_bad = i;
            end
        end
        for (int r = 0; r < n; r++)
            if (dma_mem[bufbase] === img[lba*1024 + r]) rot = r;
        if (bad == 0)
            $display("  ok   sector LBA%0d: %0d bytes identical", lba, n);
        else begin
            errors++;
            $display("  FAIL sector LBA%0d: %0d mismatches, head = img+%0d (rot %0d), first_bad=%0d got=%02h want=%02h",
                     lba, bad, rot, rot, first_bad,
                     dma_mem[bufbase+first_bad], img[lba*1024+first_bad]);
            $write("    buf[0..7]   = ");
            for (int i = 0; i < 8; i++) $write("%02h ", dma_mem[bufbase+i]);
            $write("\n    img[0..7]   = ");
            for (int i = 0; i < 8; i++) $write("%02h ", img[lba*1024 + i]);
            $write("\n    buf[end-7:] = ");
            for (int i = n-8; i < n; i++) $write("%02h ", dma_mem[bufbase+i]);
            $write("\n    img[end-7:] = ");
            for (int i = n-8; i < n; i++) $write("%02h ", img[lba*1024 + i]);
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
        if ($value$plusargs("D_PERIOD=%d", v)) d_period = v;
        if ($value$plusargs("TRACE=%d", v))    trace = v;

        // The image: byte i of sector L = L ^ i[7:0] -- every byte's value
        // names its position, so any reordering shows up immediately.
        for (longint a = 0; a < IMG; a++) begin
            img[a] = 8'((a >> 10) ^ a);
            sdr.store[BASE + 24'(a)] = {8'h00, img[a]};
        end

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
        $display("--- read LBA0 (fw_period=%0d onpush=%0d d_period=%0d) ---",
                 fw_period, fw_onpush, d_period);
        read2hd(8'd0, 8'd0, 8'd1, st0, st1, st2);
        want("st0 clean", st0 & 8'hC0, 8'h00);
        check_sector(0, 20'h10000, 1024);
        want("no same-LBA re-serve", n_reserve, 0);
        want("no fill-time pops", n_popfill, 0);
        want("no pushes outside the fill", n_push_drain, 0);
        want("no fifo overrun", n_fifo_over, 0);
        $display("  pushes=%0d (pc=%0d srv=%0d) pops=%0d dma_writes=%0d fw_rds=%0d d_bursts=%0d fillpops=%0d reserves=%0d",
                 n_push, n_wr_pc, n_wr_srv, n_pop, n_dma_wr, n_fw_rd, d_bursts,
                 n_popfill, n_reserve);

        // ---- a mid-disk sector: C4 H0 R5 -> LBA (4*2+0)*8 + 4 = 68 --------
        $display("--- read LBA68 ---");
        n_push = 0; n_pop = 0; n_dma_wr = 0; n_reserve = 0; n_popfill = 0;
        n_push_drain = 0; n_fifo_over = 0;
        read2hd(8'd4, 8'd0, 8'd5, st0, st1, st2);
        want("st0 clean", st0 & 8'hC0, 8'h00);
        check_sector(68, 20'h10000, 1024);
        want("no same-LBA re-serve", n_reserve, 0);
        want("no pushes outside the fill", n_push_drain, 0);
        $display("  pushes=%0d pops=%0d fillpops=%0d reserves=%0d",
                 n_push, n_pop, n_popfill, n_reserve);

        // ---- head 1: C0 H1 R3 -> LBA 10 -----------------------------------
        $display("--- read LBA10 (head1) ---");
        n_push = 0; n_pop = 0; n_dma_wr = 0; n_reserve = 0; n_popfill = 0;
        n_push_drain = 0; n_fifo_over = 0;
        read2hd(8'd0, 8'd1, 8'd3, st0, st1, st2);
        want("st0 clean", st0 & 8'hC0, 8'h00);
        check_sector(10, 20'h10000, 1024);
        want("no same-LBA re-serve", n_reserve, 0);
        want("no pushes outside the fill", n_push_drain, 0);
        $display("  pushes=%0d pops=%0d fillpops=%0d reserves=%0d",
                 n_push, n_pop, n_popfill, n_reserve);

        // ---- a whole track in one command: C1 H0 R1..R8 = LBA 16..23 -----
        // The multi-sector fill/drain alternation: the FIFO never clears
        // through S_IDLE inside the command, the request drops between
        // sectors and re-arms per fill, and the slot pattern alternates
        // 0..1023 / 1024..2047 -- the shape a sequential file load takes.
        $display("--- read track C1H0 (LBA16..23, 8 sectors) ---");
        n_push = 0; n_pop = 0; n_dma_wr = 0; n_reserve = 0; n_popfill = 0;
        n_push_drain = 0; n_fifo_over = 0;
        read2hd_n(8'd1, 8'd0, 8'd1, 8'd8, 8*1024, st0, st1, st2);
        want("st0 clean", st0 & 8'hC0, 8'h00);
        for (int s = 0; s < 8; s++)
            check_sector(16 + s, 20'h10000 + s*1024, 1024);
        want("no same-LBA re-serve", n_reserve, 0);
        want("no fill-time pops", n_popfill, 0);
        want("no pushes outside the fill", n_push_drain, 0);
        want("no fifo overrun", n_fifo_over, 0);
        $display("  pushes=%0d pops=%0d dma_writes=%0d fillpops=%0d reserves=%0d",
                 n_push, n_pop, n_dma_wr, n_popfill, n_reserve);

        if (errors == 0) $display("PASS tb_ramimg_fdc");
        else             $display("FAILED tb_ramimg_fdc: %0d", errors);
        $finish;
    end

    initial begin #600_000_000; $display("FAILED tb_ramimg_fdc: timeout"); $finish; end
endmodule

`default_nettype wire
