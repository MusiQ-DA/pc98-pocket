//
// tb_ext_arbiter -- does an ext-port access survive BUS_ARBITER's hold
// handshake and reach RAM.sv?
//
// This is the piece that was never simulated before testB9/10/11 went to
// hardware and came back with nothing on screen three times running --
// including a write to CGA text VRAM, which does not involve the SDRAM at all.
// tb_ext_access already proved the sequence works when driven straight at
// RAM.sv, so the arbiter in between is what is left.
//
// BUS_ARBITER only grants the bus when the CPU is parked:
//     processor_status[0] & processor_status[1] & processor_lock_n & hold_request
// sampled on cpu_ce_posedge. The self-test runs with the 8088 held in reset,
// where biu_max drives S2_S0_OUT = 3'b111, so that should hold -- "should" being
// the word that has cost three hardware runs.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ext_arbiter;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    // 8088 at 4.77 MHz: one CPU period every nine chipset clocks.
    logic cpu_ce_posedge = 0, cpu_ce_negedge = 0;
    int   ce_div = 0;
    always @(posedge clock) begin
        ce_div <= (ce_div == 8) ? 0 : ce_div + 1;
        cpu_ce_posedge <= (ce_div == 0);
        cpu_ce_negedge <= (ce_div == 4);
    end

    // The CPU is held in reset, so biu_max parks the status lines passive.
    localparam logic [2:0] STATUS_PASSIVE = 3'b111;

    // ---- ext port, driven exactly as core_top's self-test master drives it
    logic [19:0] ext_addr  = 20'd0;
    logic  [7:0] ext_wdata = 8'd0;
    logic        ext_req   = 1'b0;
    logic        ext_wr_n  = 1'b1;
    logic        ext_rd_n  = 1'b1;

    wire [19:0] address;
    wire  [7:0] internal_data_bus;
    wire        memory_read_n, memory_write_n, no_command_state;
    wire        address_direction, data_bus_direction;
    wire        io_read_n, io_write_n;
    wire        io_read_n_direction, io_write_n_direction;
    wire        memory_read_n_direction, memory_write_n_direction;
    wire        address_latch_enable, interrupt_acknowledge_n;
    wire        processor_transmit_or_receive_n, dma_wait_n;
    wire  [3:0] dma_acknowledge_n;
    wire        address_enable_n, terminal_count_n;

    wire  [7:0] ram_data_out;
    wire        ram_rw_complete, memory_access_ready, ram_address_select_n;

    // CHIPSET feeds the arbiter's data_bus_ext from its own mux; for an ext
    // write that mux selects data_bus_ext, which is what is modelled here.
    BUS_ARBITER u_arb (
        .clock(clock),
        .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(cpu_ce_negedge),
        .reset(reset),
        .cpu_address(20'd0),
        .cpu_data_bus(8'd0),
        .processor_status(STATUS_PASSIVE),
        .processor_lock_n(1'b1),
        .processor_transmit_or_receive_n(processor_transmit_or_receive_n),
        .dma_ready(1'b1),
        .dma_wait_n(dma_wait_n),
        .interrupt_acknowledge_n(interrupt_acknowledge_n),
        .dma_chip_select_n(1'b1),
        .dma_page_chip_select_n(1'b1),
        .address(address),
        .address_ext(ext_addr),
        .address_direction(address_direction),
        .data_bus_ext(ext_wdata),
        .internal_data_bus(internal_data_bus),
        .data_bus_direction(data_bus_direction),
        .address_latch_enable(address_latch_enable),
        .io_read_n(io_read_n),
        .io_read_n_ext(1'b1),
        .io_read_n_direction(io_read_n_direction),
        .io_write_n(io_write_n),
        .io_write_n_ext(1'b1),
        .io_write_n_direction(io_write_n_direction),
        .memory_read_n(memory_read_n),
        .memory_read_n_ext(ext_rd_n),
        .memory_read_n_direction(memory_read_n_direction),
        .memory_write_n(memory_write_n),
        .memory_write_n_ext(ext_wr_n),
        .memory_write_n_direction(memory_write_n_direction),
        .no_command_state(no_command_state),
        .ext_access_request(ext_req),
        .dma_request(4'd0),
        .dma_acknowledge_n(dma_acknowledge_n),
        .address_enable_n(address_enable_n),
        .terminal_count_n(terminal_count_n)
    );

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [6:0] unused_map [0:3] = '{7'd0, 7'd0, 7'd0, 7'd0};
    logic       initilized_sdram;

    RAM u_ram (
        .clock(clock), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(address), .internal_data_bus(internal_data_bus),
        .data_bus_out(ram_data_out),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .no_command_state(no_command_state),
        .memory_access_ready(memory_access_ready),
        .access_complete(ram_rw_complete),
        .ram_address_select_n(ram_address_select_n),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .map_ems(unused_map),
        .ems_b1(1'b0), .ems_b2(1'b0), .ems_b3(1'b0), .ems_b4(1'b0),
        .bios_protect_flag(2'b00), .tandy_bios_flag(1'b0),
        .enable_a000h(1'b1),
        .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0)
    );

    sdram_board_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                        .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    int errors = 0;

    // core_top's master, exactly: raise ext_access_request with the command,
    // hold until ram_rw_complete or the 200-cycle guard, latch, drop.
    task automatic master_access(input bit is_write, input logic [19:0] a,
                                 input logic [7:0] d, output logic [7:0] q,
                                 output int took, output bit completed);
        int guard = 0;
        ext_addr  = a;
        ext_wdata = d;
        ext_req   = 1'b1;
        ext_wr_n  = ~is_write;
        ext_rd_n  =  is_write;
        completed = 1'b0;
        forever begin
            @(posedge clock);
            guard++;
            if (ram_rw_complete) begin completed = 1'b1; break; end
            if (guard == 200) break;
        end
        q = ram_data_out;
        took = guard;
        ext_wr_n = 1'b1;
        ext_rd_n = 1'b1;
        ext_req  = 1'b0;
        repeat (8) @(posedge clock);
    endtask

    logic [7:0] got;
    int took;
    bit done;

    initial begin
`ifdef SDRAM_USE_MP
        $display("=== ext access through BUS_ARBITER, sdram_mp ===");
`else
        $display("=== ext access through BUS_ARBITER, KFSDRAM reference ===");
`endif
        repeat (8) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);
        $display("sdram initialised");

        master_access(1'b1, 20'h00040, 8'hA5, got, took, done);
        $display("  write 00040 = A5 : complete=%0d after %0d cycles", done, took);
        if (!done) errors++;

        master_access(1'b0, 20'h00040, 8'h00, got, took, done);
        $display("  read  00040      : complete=%0d after %0d cycles, got %02h",
                 done, took, got);
        if (!done || got !== 8'hA5) errors++;

        master_access(1'b1, 20'h00240, 8'h5A, got, took, done);
        master_access(1'b0, 20'h00240, 8'h00, got, took, done);
        $display("  read  00240      : complete=%0d after %0d cycles, got %02h",
                 done, took, got);
        if (!done || got !== 8'h5A) errors++;

        $display("\n=== summary ===");
        $display("  errors : %0d", errors);
        if (errors == 0) $display("  RESULT: PASS");
        else             $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("GLOBAL TIMEOUT -- the arbiter never granted the ext access");
        $finish;
    end

endmodule

`default_nettype wire
