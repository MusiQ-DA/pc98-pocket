//
// tb_pc98_egc_iow -- the guest's write strobe on the EGC register file,
// delivered end to end through the real BUS_ARBITER and PERIPHERALS.
//
// The bug this guards: PERIPHERALS qualified the EGC chip select with iorq
// (egc_cs = iorq & ~aen & (address[15:4]==12'h04A)) but produced the write
// strobe on the release edge (egc_wr = io_write_n & ~prev & egc_cs). iorq
// falls the same cycle io_write_n rises, so egc_wr was unreachable and
// EVERY guest write to 0x4A0-0x4AF evaporated on hardware -- the engine
// armed through 0x6A but ran with all-zero registers (EGCVIEW rendered
// garbage while every sequencer-level bench, which drives egc_wr directly,
// passed). The fix decodes the raw address like mode6a_addr/mode68_addr,
// which hold the same edge convention.
//
// The bench drives guest-visible io cycles exactly the way the arbiter
// passes them while the CPU owns the bus -- the port on cpu_address, the
// byte on data_bus_ext, the strobe on io_write_n_ext -- the same harness
// tb_pc98_dma_decode uses.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_egc_iow;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    logic cpu_ce_posedge = 0, cpu_ce_negedge = 0;
    int   ce_div = 0;
    always @(posedge clock) begin
        ce_div <= (ce_div == 8) ? 0 : ce_div + 1;
        cpu_ce_posedge <= (ce_div == 0);
        cpu_ce_negedge <= (ce_div == 4);
    end

    // ---- guest bus, driven the way a parked-CPU arbiter sees it -----------
    logic [19:0] cpu_address  = 20'd0;
    logic  [7:0] cpu_data_bus = 8'd0;
    logic  [2:0] processor_status = 3'b111;   // passive -- no 8288 cycle
    logic        io_rd_ext = 1'b1, io_wr_ext = 1'b1;
    logic [19:0] ext_addr  = 20'd0;
    logic  [7:0] ext_wdata = 8'd0;
    logic        ext_req   = 1'b0;

    wire [19:0] address;
    wire  [7:0] internal_data_bus;
    wire        io_read_n, io_write_n;
    wire        memory_read_n, memory_write_n, no_command_state;
    wire        address_enable_n, terminal_count_n;
    wire  [3:0] dma_acknowledge_n;
    wire        dma_cs_n, dma_page_cs_n;
    wire        address_direction, data_bus_direction;
    wire        io_read_n_direction, io_write_n_direction;
    wire        memory_read_n_direction, memory_write_n_direction;
    wire        address_latch_enable, interrupt_acknowledge_n;
    wire        processor_transmit_or_receive_n, dma_wait_n;

    // The EGC register-file outputs under test, plus the arming witness.
    wire        egc_wr, egc_active;
    wire  [3:0] egc_rg;
    wire  [7:0] egc_d;

    /* verilator lint_off PINMISSING */
    /* verilator lint_off PINCONNECTEMPTY */
    PERIPHERALS u_per (
        .clock                  (clock),
        .cpu_ce_negedge         (cpu_ce_negedge),
        .clk_select             (2'b00),
        .reset                  (reset),
        .interrupt_acknowledge_n(interrupt_acknowledge_n),
        .clk_pc98_dot           (1'b0),
        .font_rd_ack            (1'b0),
        .font_rd_valid          (1'b0),
        .font_rd_data           (16'd0),
        .font_rd_done           (1'b0),
        .cg_rd_ack              (1'b0),
        .cg_rd_valid            (1'b0),
        .cg_rd_data             (16'd0),
        .cg_rd_done             (1'b0),
        .font_wr_clk            (1'b0),
        .font_wr_en             (1'b0),
        .font_wr_addr           (11'd0),
        .font_wr_data           (16'd0),
        .address                (address),
        .internal_data_bus      (internal_data_bus),
        .interrupt_request      (8'd0),
        .io_read_n              (io_read_n),
        .io_write_n             (io_write_n),
        .memory_read_n          (memory_read_n),
        .memory_write_n         (memory_write_n),
        .address_enable_n       (address_enable_n),
        .kb_byte                (8'd0),
        .kb_valid               (1'b0),
        .gdc_srv_done_levels    (2'b00),
        .mgmt_address           (16'd0),
        .mgmt_read              (1'b0),
        .mgmt_write             (1'b0),
        .mgmt_writedata         (16'd0),
        .floppy_wp              (2'b00),
        .fdd_turbo              (1'b0),
        .rtc_time               (48'd0),
        .fdd_dma_ack            (1'b0),
        .terminal_count         (terminal_count_n),
        .pc98_key_stb           (1'b0),
        .pc98_key_byte          (8'd0),
        .mouse_dx               (16'sd0),
        .mouse_dy               (16'sd0),
        .mouse_ev               (1'b0),
        .mouse_btn              (2'b00),
        .opna_joy               (8'hFF),
        .dma_chip_select_n      (dma_cs_n),
        .dma_page_chip_select_n (dma_page_cs_n),
        .egc_active             (egc_active),
        .egc_wr                 (egc_wr),
        .egc_rg                 (egc_rg),
        .egc_d                  (egc_d)
    );
    /* verilator lint_on PINCONNECTEMPTY */
    /* verilator lint_on PINMISSING */

    BUS_ARBITER u_arb (
        .clock(clock),
        .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(cpu_ce_negedge),
        .reset(reset),
        .cpu_address(cpu_address),
        .cpu_data_bus(cpu_data_bus),
        .processor_status(processor_status),
        .processor_lock_n(1'b1),
        .processor_transmit_or_receive_n(processor_transmit_or_receive_n),
        .dma_ready(1'b1),
        .dma_wait_n(dma_wait_n),
        .interrupt_acknowledge_n(interrupt_acknowledge_n),
        .dma_chip_select_n(dma_cs_n),
        .dma_page_chip_select_n(dma_page_cs_n),
        .address(address),
        .address_ext(ext_addr),
        .address_direction(address_direction),
        .data_bus_ext(ext_wdata),
        .internal_data_bus(internal_data_bus),
        .data_bus_direction(data_bus_direction),
        .address_latch_enable(address_latch_enable),
        .io_read_n(io_read_n),
        .io_read_n_ext(io_rd_ext),
        .io_read_n_direction(io_read_n_direction),
        .io_write_n(io_write_n),
        .io_write_n_ext(io_wr_ext),
        .io_write_n_direction(io_write_n_direction),
        .memory_read_n(memory_read_n),
        .memory_read_n_ext(1'b1),
        .memory_read_n_direction(memory_read_n_direction),
        .memory_write_n(memory_write_n),
        .memory_write_n_ext(1'b1),
        .memory_write_n_direction(memory_write_n_direction),
        .no_command_state(no_command_state),
        .ext_access_request(ext_req),
        .dma_request(4'hF),
        .dma_acknowledge_n(dma_acknowledge_n),
        .address_enable_n(address_enable_n),
        .terminal_count_n(terminal_count_n)
    );

    int errors = 0;
    task automatic check(input bit cond, input string name);
        if (!cond) begin
            errors++;
            $display("FAIL: %s", name);
        end
    endtask

    // ---- the strobe witness -------------------------------------------
    // egc_wr is a release-edge pulse: every pulse should carry the port's
    // own register number and the byte latched while the strobe was low.
    int        wr_count = 0;
    logic [3:0] wr_rg  [0:15];
    logic [7:0] wr_dat [0:15];

    always @(posedge clock) begin
        if (egc_wr) begin
            if (wr_count < 16) begin
                wr_rg[wr_count]  <= egc_rg;
                wr_dat[wr_count] <= egc_d;
            end
            wr_count <= wr_count + 1;
        end
    end

    // One guest io write, the dma_decode shape: port parked, byte on the ext
    // side, strobe on io_write_n_ext.
    task automatic io_write(input logic [19:0] port, input logic [7:0] data);
        @(negedge clock);
        cpu_address = port;
        ext_wdata   = data;
        @(negedge clock);
        io_wr_ext = 1'b0;
        repeat (4) @(negedge clock);
        io_wr_ext = 1'b1;
        repeat (4) @(negedge clock);
        cpu_address = 20'd0;
        repeat (2) @(negedge clock);
    endtask

    task automatic io_read(input logic [19:0] port);
        @(negedge clock);
        cpu_address = port;
        @(negedge clock);
        io_rd_ext = 1'b0;
        repeat (4) @(negedge clock);
        io_rd_ext = 1'b1;
        repeat (4) @(negedge clock);
        cpu_address = 20'd0;
        repeat (2) @(negedge clock);
    endtask

    int prev_count;

    initial begin
        repeat (40) @(posedge clock);
        reset = 0;
        repeat (40) @(posedge clock);

        $display("=== mode2 arm (0x6A is bit-addressed: 0x05 sets bit2, 0x07 bit3) ===");
        check(!egc_active, "EGC starts disarmed");
        io_write(20'h0006A, 8'h05);
        check(!egc_active, "bit2 alone does not arm");
        io_write(20'h0006A, 8'h07);
        check(egc_active, "bit3+bit2 armed -> egc_active");
        check(wr_count == 0, "mode2 writes do not touch the EGC file");

        $display("=== EGCVIEW's ope write: out 0x4A4,ax with ax=0x2CAC ===");
        // Two byte strobes, low then high, exactly what the bridge emits.
        io_write(20'h004A4, 8'hAC);
        check(wr_count == 1, "one pulse for the low byte");
        check(wr_rg[0] == 4'h4 && wr_dat[0] == 8'hAC, "rg4 <- 0xAC");
        io_write(20'h004A5, 8'h2C);
        check(wr_count == 2, "one pulse for the high byte");
        check(wr_rg[1] == 4'h5 && wr_dat[1] == 8'h2C, "rg5 <- 0x2C");

        $display("=== the rest of the register file ===");
        io_write(20'h004AE, 8'h0F);          // leng lo
        check(wr_count == 3 && wr_rg[2] == 4'hE && wr_dat[2] == 8'h0F,
              "rgE <- 0x0F");
        io_write(20'h004AF, 8'h00);          // leng hi
        check(wr_count == 4 && wr_rg[3] == 4'hF && wr_dat[3] == 8'h00,
              "rgF <- 0x00");
        io_write(20'h004A0, 8'hF0);          // access lo
        check(wr_count == 5 && wr_rg[4] == 4'h0 && wr_dat[4] == 8'hF0,
              "rg0 <- 0xF0");

        $display("=== negatives ===");
        prev_count = wr_count;
        io_read(20'h004A4);                  // a read cycle must not write
        check(wr_count == prev_count, "read of 0x4A4 does not strobe");
        io_write(20'h004B0, 8'hFF);          // next page: not the EGC
        check(wr_count == prev_count, "0x4B0 does not strobe");
        io_write(20'h000A0, 8'hFF);          // 0x00 page lookalike
        check(wr_count == prev_count, "0x00A0 does not strobe");
        io_write(20'h004BE, 8'h00);          // the FDC's 144 port on the page
        check(wr_count == prev_count, "0x4BE does not strobe");

        if (errors == 0)
            $display("PASS tb_pc98_egc_iow");
        else
            $display("FAIL tb_pc98_egc_iow (%0d errors)", errors);
        $finish;
    end

endmodule
