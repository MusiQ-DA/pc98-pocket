// tb_fdd_ramimg -- the RAM-disk floppy server's own bench.
//
// Covers, in order:
//   1. upload  -- TCK-side words packed by the bench's own SLD stub land as
//                 four consecutive carve-out bytes each, at the right offset.
//   2. mount   -- enable pulses the fdd_mount() write sequence onto the
//                 management bus, eject-to-insert.
//   3. serve   -- a read request reads the LBA out of register 0, bursts 16
//                 words x 64 out of SDRAM, and pushes 1024 bytes at 0xF20F.
//   4. drain   -- a write request pops the FIFO until the request drops.
//   5. probe   -- slot-0x88 readback reads one carve-out byte back.
//   6. unmount -- disable ejects drive A and hands the bus back.
//
// The bench drives the SLD node itself: fdd_ramimg is the only instantiation
// of this stub in this file list, so its outputs are just wires the bench
// toggles through a package. Push a word by raising sdr for exactly 32 TCK
// edges -- the same way the real hub shifts TDI, only slower and by hand.
//
// Build (in the pc98-sim image):
//   run: verilator --binary --timing -Wno-fatal --top-module tb_fdd_ramimg \
//        fpga/core/fdd_ramimg.sv sim/stub_dcfifo.sv sim/tb_fdd_ramimg.sv \
//        -o tb_fdd_ramimg --Mdir /tmp/obj_fddramimg && ./tb_fdd_ramimg

`default_nettype none

package fddramimg_jtag_pkg;
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
    assign tck                = fddramimg_jtag_pkg::tck;
    assign tdi                = fddramimg_jtag_pkg::tdi;
    assign ir_in              = {sld_ir_width{1'b0}};
    assign virtual_state_cdr  = fddramimg_jtag_pkg::cdr;
    assign virtual_state_sdr  = fddramimg_jtag_pkg::sdr;
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

module tb_fdd_ramimg;
    import fddramimg_jtag_pkg::*;

    localparam logic [23:0] BASE = 24'h620000;
    localparam int          IMG  = 32'd1261568;

    logic clk = 0, reset = 1, power_reset = 1;
    always #10 clk = ~clk;          // 50 MHz

    logic [1:0]  fdd_request = 2'b00;
    logic [15:0] mgmt_addr, mgmt_dout, mgmt_din;
    logic        mgmt_wr, mgmt_rd;
    logic        sd_req, sd_we, sd_ack, sd_rvalid, sd_done;
    logic [23:0] sd_addr;
    logic  [3:0] sd_len;
    logic [15:0] sd_wdata, sd_rdata;
    logic        ctl_pulse = 0;
    logic  [6:0] ctl_addr  = 0;
    logic [31:0] ctl_data  = 0;
    wire         own, greset;
    wire [31:0]  dbg0, dbg1, dbg2;

    fdd_ramimg #(.CARVE_BASE(BASE), .IMG_BYTES(IMG)) dut (
        .clk(clk), .reset(reset), .power_reset(power_reset),
        .fdd_request(fdd_request),
        .mgmt_addr(mgmt_addr), .mgmt_dout(mgmt_dout),
        .mgmt_wr(mgmt_wr), .mgmt_rd(mgmt_rd), .mgmt_din(mgmt_din),
        .sd_req(sd_req), .sd_we(sd_we), .sd_addr(sd_addr),
        .sd_len(sd_len), .sd_wdata(sd_wdata), .sd_ack(sd_ack),
        .sd_rvalid(sd_rvalid), .sd_rdata(sd_rdata), .sd_done(sd_done),
        .ctl_pulse(ctl_pulse), .ctl_addr(ctl_addr), .ctl_data(ctl_data),
        .own(own), .guest_reset_req(greset),
        .dbg0(dbg0), .dbg1(dbg1), .dbg2(dbg2)
    );

    int errors = 0;

    // ---------------------------------------------------------------
    // A fake SDRAM port. Writes: ack one cycle after the request, done a
    // few later -- like sdram_mp, where p_done always trails p_ack (the
    // WRITE beat commits after grant, never with it). Reads: ack, then one
    // rvalid beat every other clock for len+1 words.
    // ---------------------------------------------------------------
    logic [7:0]  carve_mem [0:IMG-1];
    int          burst_left = 0;
    logic [23:0] rd_base = 0;
    logic  [3:0] rd_len  = 0;
    logic  [3:0] wr_pend = 0;

    always_ff @(posedge clk) begin
        sd_ack    <= 1'b0;
        sd_rvalid <= 1'b0;
        sd_done   <= 1'b0;
        if (wr_pend != 0) begin
            wr_pend <= wr_pend - 4'd1;
            if (wr_pend == 4'd1) sd_done <= 1'b1;
        end
        if (sd_req && !sd_ack && wr_pend == 0 && burst_left == 0) begin
            sd_ack <= 1'b1;
            if (sd_we) begin
                carve_mem[sd_addr - BASE] <= sd_wdata[7:0];
                wr_pend <= 4'd3;
            end else begin
                rd_base    <= sd_addr - BASE;   // carve_mem is offset-indexed
                rd_len     <= sd_len;
                burst_left <= int'(sd_len) + 1;
            end
        end else if (burst_left > 0 && !sd_rvalid) begin
            // one beat per two clocks -- slower than real bursts on purpose
            sd_rvalid <= 1'b1;
            sd_rdata  <= {8'h00, carve_mem[rd_base + rd_len + 1 - burst_left]};
            burst_left <= burst_left - 1;
            if (burst_left == 1) sd_done <= 1'b1;
        end
    end

    // ---------------------------------------------------------------
    // mgmt_din model: register 0 answers {drive=0, lba=LAST_LBA}; anything
    // else reads 0.
    // ---------------------------------------------------------------
    logic [14:0] last_lba = 15'd0;
    always_comb begin
        if (mgmt_rd && mgmt_addr == 16'hF200)
            mgmt_din = {1'b0, last_lba};
        else
            mgmt_din = 16'h0000;
    end

    // ---------------------------------------------------------------
    // Witnesses: every mount-table write and every FIFO push/pop.
    // ---------------------------------------------------------------
    logic [15:0] mnt_log [0:15];
    int          mnt_n    = 0;
    int          fifo_pushes = 0;
    int          fifo_pops   = 0;
    logic [7:0]  push_bytes [0:2047];

    always @(posedge clk) begin
        if (mgmt_wr && mgmt_addr == 16'hF20F) begin
            if (fifo_pushes < 2048)
                push_bytes[fifo_pushes] = mgmt_dout[7:0];
            fifo_pushes = fifo_pushes + 1;
        end
        if (mgmt_wr && mgmt_addr != 16'hF20F) begin
            if (mnt_n < 16) mnt_log[mnt_n] = mgmt_addr;
            mnt_n = mnt_n + 1;
        end
        if (mgmt_rd && mgmt_addr == 16'hF20F) fifo_pops = fifo_pops + 1;
    end

    // ---------------------------------------------------------------
    // TCK driver: one capture then 32 shift edges, LSB first -- the same
    // order the real hub delivers a drscan value.
    // ---------------------------------------------------------------
    task push_word(input logic [31:0] w);
        @(negedge clk);
        tck = 1'b0;
        cdr = 1'b1;
        #1 tck = 1'b1; #1 tck = 1'b0;
        cdr = 1'b0; sdr = 1'b1;
        for (int i = 0; i < 32; i++) begin
            tdi = w[i];
            #1 tck = 1'b1; #1 tck = 1'b0;
        end
        sdr = 1'b0;
    endtask

    task ctl_write(input logic [31:0] v);
        @(negedge clk);
        ctl_addr <= 7'h07; ctl_data <= v; ctl_pulse <= 1'b1;
        @(negedge clk);
        ctl_pulse <= 1'b0;
    endtask

    task rba_write(input logic [31:0] v);
        @(negedge clk);
        ctl_addr <= 7'h08; ctl_data <= v; ctl_pulse <= 1'b1;
        @(negedge clk);
        ctl_pulse <= 1'b0;
    endtask

    function void check(input bit cond, input string name);
        if (!cond) begin
            errors++;
            $display("FAIL: %s", name);
        end
    endfunction

    initial begin
        repeat (5) @(negedge clk);
        power_reset = 0; reset = 0;
        repeat (4) @(negedge clk);

        // ---------- upload: eight words land as 32 bytes ----------
        ctl_write(32'h0000_0010);        // arm the stream sink
        for (int i = 0; i < 8; i++) begin
            // word i = {i*4+3, i*4+2, i*4+1, i*4+0} -- byte order probe
            push_word({8'(i*4+3), 8'(i*4+2), 8'(i*4+1), 8'(i*4)});
            repeat (30) @(negedge clk);  // let the drain keep up
        end
        repeat (200) @(negedge clk);
        for (int i = 0; i < 32; i++)
            check(carve_mem[i] == 8'(i),
                  $sformatf("upload byte %d landed (got %02h)", i, carve_mem[i]));
        check(dbg1[20:0] == 21'd32, "up_off tracks 8 words");

        // ---------- mount: the fdd_mount() row sequence -------------
        ctl_write(32'h0000_0001);        // enable -> mount
        repeat (400) @(negedge clk);
        check(dbg0[22] == 1'b1, "mounted flag set after mount pass");
        check(own == 1'b1, "own held while enabled");
        check(mnt_n == 9, "nine management writes (B eject + A seq)");
        if (mnt_n >= 9) begin
            check(mnt_log[0] == 16'hF280, "row0: B present=0");
            check(mnt_log[1] == 16'hF200, "row1: A present=0");
            check(mnt_log[2] == 16'hF202, "row2: cylinders");
            check(mnt_log[3] == 16'hF203, "row3: sectors/track");
            check(mnt_log[4] == 16'hF204, "row4: total sectors");
            check(mnt_log[5] == 16'hF205, "row5: heads");
            check(mnt_log[6] == 16'hF206, "row6: 1024 flag");
            check(mnt_log[7] == 16'hF201, "row7: write-protect");
            check(mnt_log[8] == 16'hF200, "row8: A present=1");
        end

        // ---------- serve: one sector read --------------------------
        // Prime a second fake-image region: sector lba=1 -> bytes 1024..2047.
        for (int i = 1024; i < 2048; i++) carve_mem[i] = 8'(i ^ 8'hA5);
        fifo_pushes = 0;
        last_lba    = 15'd1;
        @(negedge clk);
        fdd_request = 2'b01;
        // hold the request until the whole sector has been pushed (or die)
        for (int t = 0; t < 20000 && fifo_pushes < 1024; t++) @(negedge clk);
        fdd_request = 2'b00;
        check(fifo_pushes == 1024, "1024 bytes pushed for one 1024B sector");
        check(push_bytes[0] == 8'hA5, "serve byte 0 = sector's first byte");
        check(push_bytes[1023] == (8'd255 ^ 8'hA5), "serve byte 1023");
        if (push_bytes[0] != 8'hA5 || push_bytes[1023] != (8'd255 ^ 8'hA5))
            $display("  dbg: push0=%02h push1=%02h push1023=%02h dbg0=%08h",
                     push_bytes[0], push_bytes[1], push_bytes[1023], dbg0);
        repeat (50) @(negedge clk);

        // ---------- drain: a write request is drained, not served ---
        fifo_pops = 0;
        @(negedge clk);
        fdd_request = 2'b10;
        repeat (600) @(negedge clk);
        check(fifo_pops > 0, "write request pops the FIFO");
        fdd_request = 2'b00;
        repeat (50) @(negedge clk);

        // ---------- readback probe ----------------------------------
        carve_mem[12345] = 8'h77;
        rba_write(32'd12345);
        repeat (100) @(negedge clk);
        check(dbg2[7:0] == 8'h77, "readback probe returns the carved byte");
        if (dbg2[7:0] != 8'h77)
            $display("  dbg: dbg2=%08h mem[12345]=%02h", dbg2, carve_mem[12345]);

        // ---------- unmount -----------------------------------------
        mnt_n = 0;
        ctl_write(32'h0000_0000);        // disable -> eject A, bus released
        repeat (100) @(negedge clk);
        check(own == 1'b0, "own released after disable");
        check(dbg0[22] == 1'b0, "mounted cleared on unmount");
        check(mnt_n >= 1 && mnt_log[0] == 16'hF200, "unmount ejects drive A");

        // ---------- guest reset pulse -------------------------------
        // ctl_write returns on the negedge inside the one-clock greset
        // pulse: the bit landed on the posedge just past and clears on the
        // next one -- check it before waiting any further.
        ctl_write(32'h0000_0005);        // enable + greset
        check(greset == 1'b1, "greset pulses on the control write");
        @(negedge clk);
        check(greset == 1'b0, "greset is a one-clock pulse");

        if (errors == 0) $display("tb_fdd_ramimg: ALL PASS");
        else             $display("tb_fdd_ramimg: %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
