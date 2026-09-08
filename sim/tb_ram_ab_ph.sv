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
    int bios_errors = 0;
    int load_errors = 0;
    int timeouts = 0;

    localparam int CPU_CYCLE = 36;  // 8088 at 4.77 MHz = ~9 chipset clocks per T-state, 4 T-states

    // `len` is how long the strobe is held before the ready handshake takes
    // over. The 8088 gives CPU_CYCLE; the BIOS loader in core_top drives the
    // SAME RAM.sv port through the chipset's ext mux, back to back with no idle
    // gap, and the BIOS image is written that way.
    task automatic bus_cycle_len(input bit is_write, input int addr,
                                 input logic [7:0] d, input int len,
                                 output logic [7:0] q);
        int guard;
        address = 20'(addr);
        internal_data_bus = d;
        no_command_state = 0;
        if (is_write) memory_write_n = 0; else memory_read_n = 0;
        repeat (len) @(posedge clock);
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

    task automatic bus_cycle(input bit is_write, input int addr,
                             input logic [7:0] d, output logic [7:0] q);
        bus_cycle_len(is_write, addr, d, CPU_CYCLE, q);
    endtask

    task automatic bus_write(input int addr, input logic [7:0] d);
        logic [7:0] ignore;
        bus_cycle(1'b1, addr, d, ignore);
    endtask

    // The BIOS loader's cadence, copied from core_top's bios_load_state 02-04:
    // hold the write strobe until ram_rw_complete, then a five-clock settle
    // before the next byte. Not a fixed short pulse -- an unconditional
    // back-to-back burst makes the KFSDRAM reference violate tRP, and KFSDRAM
    // boots the real board, so that stimulus would be wrong rather than
    // revealing.
    task automatic bus_write_loader(input int addr, input logic [7:0] d);
        int guard;
        address = 20'(addr);
        internal_data_bus = d;
        no_command_state = 0;
        memory_write_n = 0;
        guard = 0;
        while (!access_complete && guard < 4000) begin
            @(posedge clock); guard++;
        end
        if (guard >= 4000) begin
            $display("  LOADER TIMEOUT @%05h", addr); timeouts++;
        end
        memory_write_n = 1;
        no_command_state = 1;
        repeat (5) @(posedge clock);
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

        // ---------------------------------------------------------------
        // Bank crossing. The two passes above sit inside ONE 512-word column
        // block each, so with sdram_mp's {row, bank, col} mapping they land
        // entirely in bank 0 -- which is also the only bank KFSDRAM's mapping
        // ever uses. The testbench therefore never exercised sdram_mp's
        // multi-bank behaviour at all: bank switching, per-bank precharge, and
        // refresh while several banks have seen traffic.
        //
        // The BIOS's base 64 KB test -- the one that reports three beeps on
        // hardware -- covers 0x00000-0x0FFFF, which under that mapping spans
        // ALL FOUR banks and 32 rows. So this is exactly the gap between what
        // simulation covered and where the hardware fails.
        //
        // Two shapes, because they stress different things: a contiguous sweep
        // that walks bank 0,1,2,3 and rolls the row, and a strided pass that
        // changes bank on every single access.
        for (int i = 0; i < 2048; i++) bus_write(32'h00000 + i, pat(i + 3));
        for (int i = 0; i < 2048; i++) begin
            bus_read(32'h00000 + i, got);
            if (got !== pat(i + 3)) begin
                if (errors < 24)
                    $display("  BANK-SWEEP MISMATCH @%05h bank %0d row %0d: got %02h want %02h",
                             i, (i >> 9) & 3, i >> 11, got, pat(i + 3));
                errors++;
            end
        end

        for (int i = 0; i < 128; i++)
            for (int b = 0; b < 4; b++)
                bus_write(32'h04000 + (b << 9) + i, pat(i * 4 + b));
        for (int i = 0; i < 128; i++)
            for (int b = 0; b < 4; b++) begin
                bus_read(32'h04000 + (b << 9) + i, got);
                if (got !== pat(i * 4 + b)) begin
                    if (errors < 32)
                        $display("  BANK-STRIDE MISMATCH @%05h bank %0d: got %02h want %02h",
                                 32'h04000 + (b << 9) + i,
                                 ((32'h04000 + (b << 9) + i) >> 9) & 3,
                                 got, pat(i * 4 + b));
                    errors++;
                end
            end

        // The BIOS region itself, at board timing. testB27 read F8 2E 41 D6 at
        // F000:D880 where the image holds F8 2E E8 D2, and the sweeps above all
        // live in low memory: this covers the actual failing address, its row
        // and its bank, plus the row boundary at 0xFE000.
        for (int i = 0; i < 2048; i++)
            bus_write(32'hFD800 + i, pat(i + 11));
        for (int i = 0; i < 2048; i++) begin
            bus_read(32'hFD800 + i, got);
            if (got !== pat(i + 11)) begin
                if (bios_errors < 8)
                    $display("  BIOS MISMATCH @%05h (row %0d bank %0d col %0d): got %02h want %02h",
                             32'hFD800 + i, (32'hFD800 + i) >> 11,
                             ((32'hFD800 + i) >> 9) & 3, (32'hFD800 + i) & 511,
                             got, pat(i + 11));
                bios_errors++;
            end
        end
        $display("  BIOS region: %0d errors", bios_errors);

        // The loader's cadence, read back at CPU speed. A write lost to a
        // refresh collision would leave the image wrong in memory before the
        // guest ever reads it.
        //
        // sdram_mp only. At this cadence -- which is core_top's, not something
        // invented for the bench -- KFSDRAM racks up tRP violations against the
        // model (41 over 2048 writes) while its DATA still comes back correct.
        // KFSDRAM boots the real board, so that is either a part more forgiving
        // than the model's T_RP=2 or a corner the reference has always cut. It
        // is not a finding about sdram_mp and must not gate this bench.
`ifdef SDRAM_USE_MP
        for (int i = 0; i < 2048; i++)
            bus_write_loader(32'hFC000 + i, pat(i + 33));
        for (int i = 0; i < 2048; i++) begin
            bus_read(32'hFC000 + i, got);
            if (got !== pat(i + 33)) begin
                if (load_errors < 8)
                    $display("  LOAD MISMATCH @%05h (row %0d bank %0d col %0d): got %02h want %02h",
                             32'hFC000 + i, (32'hFC000 + i) >> 11,
                             ((32'hFC000 + i) >> 9) & 3, (32'hFC000 + i) & 511,
                             got, pat(i + 33));
                load_errors++;
            end
        end
        $display("  loader cadence: %0d errors", load_errors);
`else
        $display("  loader cadence: skipped (reference cuts tRP at this rate)");
`endif
        errors += bios_errors + load_errors;

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
