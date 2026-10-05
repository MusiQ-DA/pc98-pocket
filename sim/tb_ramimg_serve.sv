//
// tb_ramimg_serve — serve-path reproduction for fdd_ramimg against the REAL
// sdram_shim + sdram_mp + sdram_model chain.
//
// The JTAG-side upload is irrelevant here: the carve-out is preloaded into
// the model's memory, a read request is raised, and every F20F push is
// collected. Hardware showed the guest stream arriving as img[1..15],
// img[15], img[17..31], img[31] ... -- byte 0 of each 16-word burst missing
// and byte 15 pushed twice. This bench exists to see whether the real
// controller's ack/rvalid cadence makes the serve FSM produce exactly that.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ramimg_serve;

    localparam real HALF_NS = 11.64153;   // ~42.95 MHz chipset clock

    logic clk = 0, reset = 1, power_reset = 1;
    always #(HALF_NS) clk = ~clk;

    // ------------------------------------------------------------- fdd_ramimg
    logic  [1:0]  fdd_request;
    logic [15:0]  mgmt_addr, mgmt_dout, mgmt_din;
    logic         mgmt_wr, mgmt_rd;
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
        .mgmt_addr(mgmt_addr), .mgmt_dout(mgmt_dout),
        .mgmt_wr(mgmt_wr), .mgmt_rd(mgmt_rd), .mgmt_din(mgmt_din),
        .fw_busy(fw_busy),
        .sd_req(sd_req), .sd_we(sd_we), .sd_addr(sd_addr), .sd_len(sd_len),
        .sd_wdata(sd_wdata), .sd_ack(sd_ack), .sd_rvalid(sd_rvalid),
        .sd_rdata(sd_rdata), .sd_done(sd_done),
        .ctl_pulse(ctl_pulse), .ctl_addr(ctl_addr), .ctl_data(ctl_data),
        .own(own), .guest_reset_req(greset),
        .dbg0(dbg0), .dbg1(dbg1), .dbg2(dbg2)
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
        // port A: the guest's legacy single-word interface -- idle here
        .address(25'd0), .access_num(10'd0),
        .data_in(16'd0), .data_out(), .data_in_hi(16'd0), .data_out_hi(),
        .write_request(1'b0), .read_request(1'b0), .enable_refresh(1'b0),
        .write_flag(), .read_flag(), .idle(), .refresh_mode(),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(),
        .sdram_ras(s_ras_n), .sdram_cas(s_cas_n), .sdram_we(s_we_n),
        .sdram_ba(s_ba), .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out),
        .sdram_dq_io(s_dq_io),
        // B font fetch, C cg window, D display -- all idle
        .b_req(1'b0), .b_addr(24'd0), .b_len(4'd0),
        .b_ack(), .b_rvalid(), .b_rdata(), .b_done(),
        .c_req(1'b0), .c_addr(24'd0), .c_len(4'd0),
        .c_ack(), .c_rvalid(), .c_rdata(), .c_done(),
        .d_req(1'b0), .d_addr(24'd0), .d_len(4'd0),
        .d_ack(), .d_rvalid(), .d_rdata(), .d_done(),
        // E: the server under test
        .e_req(sd_req), .e_we(sd_we), .e_addr(sd_addr), .e_len(sd_len),
        .e_wdata(sd_wdata), .e_ack(sd_ack), .e_rvalid(sd_rvalid),
        .e_rdata(sd_rdata), .e_done(sd_done)
    );

    sdram_model #(
        .ROW_BITS(13), .COL_BITS(9), .BANK_BITS(2), .DQ_BITS(16),
        .PHYSICAL_DQ(1'b1)
    ) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // -------------------------------------------------- mgmt target stub
    // Register 0 (F200): read -> {drive0, lba}. FIFO (F20F): write -> collect.
    localparam int LBA     = 0;
    localparam int SERVED  = 1024;      // drop the request after this many
    logic [7:0] pushes [$];
    int         push_count = 0;

    always_comb begin
        if (mgmt_rd && mgmt_addr == 16'hF200)
            mgmt_din = {1'b0, 15'(LBA)};
        else
            mgmt_din = 16'h0001;
    end

    // FIFO write on every F20F strobe (floppy's fifo_write = wr && &addr).
    always_ff @(posedge clk) begin
        if (mgmt_wr && mgmt_addr[3:0] == 4'hF) begin
            pushes.push_back(mgmt_dout[7:0]);
            push_count <= push_count + 1;
        end
    end

    // fdd_request[0]: up while serving, drops when the stub FIFO has a full
    // sector -- the real controller's fifo_full edge.
    assign fdd_request = {1'b0, (push_count < SERVED) && req_armed};
    logic req_armed = 1'b0;

    // rvalid tracing: flag any beat that lands outside S_RD_BEAT and any
    // push whose byte isn't the expected stream value.
    // dut.st: S_RD_REQ=5, S_RD_BEAT=6 -- count rvalids that land elsewhere.
    int land_while_req = 0;
    always_ff @(posedge clk) begin
        if (sd_rvalid && dut.st != 5'd6)
            land_while_req <= land_while_req + 1;
    end

    // ------------------------------------------------------------- drive
    int errors = 0;
    localparam logic [23:0] CARVE = 24'h620000;

    task check(bit ok, string msg);
        if (!ok) begin errors++; $display("FAIL: %s", msg); end
    endtask

    initial begin
        int i;
        // carve: word N holds byte value (N*73+11) -- a run unique enough to
        // spot a dup/drop without matching neighbours.
        for (i = 0; i < 2048; i++)
            sdr.store[24'(CARVE) + 24'(i)] = {8'h00, 8'(i*73 + 11)};

        repeat (4) @(posedge clk);
        power_reset <= 0;
        repeat (4) @(posedge clk);
        reset <= 0;
        repeat (8) @(posedge clk);

        // enable + mount
        @(posedge clk); ctl_addr <= 7'h07; ctl_data <= 32'h1; ctl_pulse <= 1'b1;
        @(posedge clk); ctl_pulse <= 1'b0;
        repeat (300) @(posedge clk);          // let the mount pass run
        check(dbg0[23], "en set");

        // raise the read request
        req_armed = 1'b1;

        // wait for the serve to finish (push_count == 1024 or timeout)
        i = 0;
        while (push_count < SERVED && i < 400000) begin
            @(posedge clk); i++;
        end
        $display("pushes=%0d stray_rvalid=%0d dbg0=%h", pushes.size(),
                 land_while_req, dbg0);
        check(pushes.size() == SERVED, "serve pushes a full sector");

        for (i = 0; i < pushes.size() && i < SERVED; i++) begin
            if (pushes[i] !== 8'(i*73 + 11)) begin
                errors++;
                $display("MISMATCH push[%0d]=%02h expect=%02h",
                         i, pushes[i], 8'(i*73 + 11));
            end
        end
        if (errors == 0) $display("tb_ramimg_serve: ALL PASS");
        else             $display("tb_ramimg_serve: %0d error(s)", errors);
        $finish;
    end

endmodule
`default_nettype wire
