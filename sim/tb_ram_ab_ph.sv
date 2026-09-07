//
// tb_ram_ab_ph — tb_ram_ab with the Pocket's real board timing.
//
// Identical stimulus and checks to tb_ram_ab, but the SDRAM model runs on a
// device clock 180 degrees out of phase with the controller and sees pin
// flight delays (see sdram_board_model.sv). This is the configuration the
// hardware actually presents: dram_clk is pll outclk_2 at +11.64 ns while the
// controller runs on clk_chipset.
//
// Validity condition: the KFSDRAM reference must still PASS here, because
// KFSDRAM boots the real board. If the reference fails, the board model is
// wrong, not the DUT. The sdram_mp answer is only meaningful after that.
//
// Select the controller with +define+SDRAM_USE_MP (same as config.tcl).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ram_ab_ph;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    logic [19:0] address = '0;
    logic [7:0]  internal_data_bus = '0;
    logic [7:0]  data_bus_out;
    logic        memory_read_n = 1, memory_write_n = 1;
    logic        no_command_state = 1;
    logic        memory_access_ready, access_complete, ram_address_select_n;
    logic        initilized_sdram;

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;

    logic [6:0] map_ems [0:3] = '{7'd0, 7'd0, 7'd0, 7'd0};

    RAM dut (
        .clock(clock), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(address), .internal_data_bus(internal_data_bus),
        .data_bus_out(data_bus_out),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .no_command_state(no_command_state),
        .memory_access_ready(memory_access_ready),
        .access_complete(access_complete),
        .ram_address_select_n(ram_address_select_n),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .map_ems(map_ems),
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
    int timeouts = 0;

    localparam int CPU_CYCLE = 36;  // 8088 at 4.77 MHz = ~9 chipset clocks per T-state, 4 T-states

    task automatic bus_cycle(input bit is_write, input int addr,
                             input logic [7:0] d, output logic [7:0] q);
        int guard;
        address = 20'(addr);
        internal_data_bus = d;
        no_command_state = 0;
        if (is_write) memory_write_n = 0; else memory_read_n = 0;
        repeat (CPU_CYCLE) @(posedge clock);
        guard = 0;
        while (!memory_access_ready && guard < 4000) begin
            @(posedge clock); guard++;
        end
        if (guard >= 4000) begin
            $display("  TIMEOUT @%05h", addr); timeouts++;
        end
        q = data_bus_out;
        memory_write_n = 1;
        memory_read_n  = 1;
        no_command_state = 1;
        repeat (2) @(posedge clock);
    endtask

    task automatic bus_write(input int addr, input logic [7:0] d);
        logic [7:0] ignore;
        bus_cycle(1'b1, addr, d, ignore);
    endtask

    task automatic bus_read(input int addr, output logic [7:0] d);
        bus_cycle(1'b0, addr, 8'h00, d);
    endtask

    function automatic logic [7:0] pat(input int a);
        pat = 8'((a * 8'h9D) ^ 8'h5A);
    endfunction

    logic [7:0] got;

    initial begin
`ifdef SDRAM_USE_MP
        $display("=== [board timing] RAM.sv + sdram_kf_shim (sdram_mp) ===");
`else
        $display("=== [board timing] RAM.sv + KFSDRAM (reference) ===");
`endif
        repeat (8) @(posedge clock);
        reset = 0;

        wait (initilized_sdram);
        $display("init done");

        for (int i = 0; i < 512; i++)
            bus_write(32'h01000 + i, pat(i));
        for (int i = 0; i < 512; i++) begin
            bus_read(32'h01000 + i, got);
            if (got !== pat(i)) begin
                if (errors < 8)
                    $display("  MISMATCH @%05h: got %02h want %02h",
                             32'h01000 + i, got, pat(i));
                errors++;
            end
        end

        for (int i = 0; i < 256; i++) begin
            bus_write(32'h02000 + i, pat(i + 77));
            bus_read (32'h02000 + i, got);
            if (got !== pat(i + 77)) begin
                if (errors < 16)
                    $display("  RMW MISMATCH @%05h: got %02h want %02h",
                             32'h02000 + i, got, pat(i + 77));
                errors++;
            end
        end

        $display("\n=== summary ===");
        $display("  protocol violations : %0d", sdr.u_part.violations);
        $display("  data errors         : %0d", errors);
        $display("  bus timeouts        : %0d", timeouts);
        $display("  refreshes issued    : %0d", sdr.u_part.ref_count);
        $display("  writes/reads served : %0d / %0d",
                 sdr.u_part.writes_served, sdr.u_part.reads_served);
        if (sdr.u_part.violations == 0 && errors == 0 && timeouts == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
