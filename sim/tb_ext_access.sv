//
// tb_ext_access -- does an access on CHIPSET's external-access port actually
// reach RAM.sv?
//
// This is the check that should have run before testB9/10/11 went to hardware.
// Three hardware round-trips came back with nothing on screen, including a
// write to CGA text VRAM that does not involve the SDRAM at all, which means
// the doubt is about the ext port itself rather than the memory behind it.
//
// The BIOS loader uses this port and works, so the port is not broken; what is
// unverified is the sequence core_top's new self-test master drives on it. So
// drive exactly that sequence here and see whether RAM.sv performs the access.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ext_access;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    // ---- ext port, driven exactly as core_top's self-test master drives it
    logic [19:0] ext_addr    = 20'd0;
    logic  [7:0] ext_wdata   = 8'd0;
    logic        ext_req     = 1'b0;
    logic        ext_wr_n    = 1'b1;
    logic        ext_rd_n    = 1'b1;

    wire  [7:0]  ext_rdata;
    wire         ram_rw_complete;

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;

    // RAM.sv on its own, fed the bus signals CHIPSET's arbiter would produce
    // for an ext access: this isolates "does the ext sequence make RAM.sv do
    // the access" from the arbiter's hold handshake, which is exercised
    // separately by the BIOS loader on real hardware.
    logic [6:0] unused_map [0:3] = '{7'd0, 7'd0, 7'd0, 7'd0};
    logic       initilized_sdram;
    wire        memory_access_ready, ram_address_select_n;

    RAM dut (
        .clock(clock), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(ext_addr), .internal_data_bus(ext_wdata),
        .data_bus_out(ext_rdata),
        .memory_read_n(ext_rd_n), .memory_write_n(ext_wr_n),
        .no_command_state(ext_rd_n & ext_wr_n),
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

    // The master's own sequence: raise the command, hold it until
    // ram_rw_complete or the 200-cycle guard, latch, drop.
    task automatic master_access(input bit is_write, input logic [19:0] a,
                                 input logic [7:0] d, output logic [7:0] q,
                                 output int took, output bit completed);
        int guard = 0;
        ext_addr  = a;
        ext_wdata = d;
        ext_wr_n  = ~is_write;
        ext_rd_n  =  is_write;
        completed = 1'b0;
        forever begin
            @(posedge clock);
            guard++;
            if (ram_rw_complete) begin completed = 1'b1; break; end
            if (guard == 200) break;
        end
        q = ext_rdata;
        took = guard;
        ext_wr_n = 1'b1;
        ext_rd_n = 1'b1;
        repeat (4) @(posedge clock);
    endtask

    logic [7:0] got;
    int took;
    bit done;

    initial begin
`ifdef SDRAM_USE_MP
        $display("=== ext-port access through sdram_kf_shim (sdram_mp) ===");
`else
        $display("=== ext-port access through KFSDRAM (reference) ===");
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

        // Bank 1 under sdram_mp's addr[10:9] mapping.
        master_access(1'b1, 20'h00240, 8'h5A, got, took, done);
        master_access(1'b0, 20'h00240, 8'h00, got, took, done);
        $display("  read  00240      : complete=%0d after %0d cycles, got %02h",
                 done, took, got);
        if (!done || got !== 8'h5A) errors++;

        // CGA text VRAM: RAM.sv must NOT claim this, so ram_rw_complete never
        // fires and the master falls through on its guard. That is the
        // behaviour the firmware's "SELFTEST START" write depends on.
        master_access(1'b1, 20'hB8000, 8'h53, got, took, done);
        $display("  write B8000      : complete=%0d after %0d cycles (expect 0)",
                 done, took);
        if (done) begin
            $display("  UNEXPECTED: RAM.sv claimed a CGA VRAM address");
            errors++;
        end
        if (ram_address_select_n !== 1'b1)
            $display("  note: ram_address_select_n=%0d at B8000", ram_address_select_n);

        $display("\n=== summary ===");
        $display("  errors : %0d", errors);
        $display(errors == 0 ? "  RESULT: PASS" : "  RESULT: FAIL");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
