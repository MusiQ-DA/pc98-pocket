//
// tb_ram_ab — drives the real RAM.sv and checks a byte round trip.
//
// Built after the hardware A/B failed: the PCXT base reached BIOS through
// KFSDRAM but not through sdram_kf_shim, so something in the integration
// differs in a way the controller-level testbenches could not see. This runs
// the actual RAM.sv so the two controllers can be compared directly.
//
// Select the controller with +define+SDRAM_USE_MP (the same macro config.tcl
// sets for the FPGA build).
//
// The test deliberately runs long enough to collide with refreshes, since
// refresh handling is the most visible behavioural difference between the two.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ram_ab;

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

    sdram_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                  .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    int errors = 0;
    int timeouts = 0;
    // How many clocks one loader byte costs, start of strobe to ready for the
    // next. APF delivers a 32-bit word about every 75 clk_74a cycles, which at
    // 42.95 MHz is ~43 chipset clocks for TWO 16-bit words -- so the budget is
    // ~21.7 clocks per word, ~10.9 per byte. Anything slower overflows the load
    // FIFO, and run#107 measured 4682 words dropped.
    int ld_clocks = 0;
    int ld_bytes  = 0;
    bit ld_timing = 0;
    int bios_errors = 0;
    int load_errors = 0;

    // A CPU bus cycle: assert the strobe for a fixed number of clocks and then
    // extend it only while memory_access_ready is low. This is the path that
    // matters -- RAM.sv's only wait state comes from refresh_mode, so a
    // controller that fails to report "busy refreshing" lets the cycle end
    // before the data has moved. Waiting on access_complete instead hides that
    // entirely, which is how the first version of this testbench passed a
    // controller that does not work on hardware.
    localparam int CPU_CYCLE = 36;  // 8088 at 4.77 MHz = ~9 chipset clocks per T-state, 4 T-states

    // `len` is how many clocks the strobe is held before the ready handshake
    // takes over. The 8088 gives CPU_CYCLE; the BIOS loader in core_top drives
    // the SAME RAM.sv port through the chipset's ext mux, back to back with no
    // idle gap between accesses, which is a different refresh interaction
    // entirely -- and the BIOS image is written that way.
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

    task automatic bus_read(input int addr, output logic [7:0] d);
        bus_cycle(1'b0, addr, 8'h00, d);
    endtask

    // The BIOS loader's cadence, copied from core_top's bios_load_state 02-04:
    // hold the write strobe until ram_rw_complete, then a five-clock settle
    // before the next byte. Not a fixed short pulse -- an unconditional
    // back-to-back burst makes the KFSDRAM reference violate tRP, and KFSDRAM
    // boots the real board, so that stimulus would be wrong rather than
    // revealing.
    task automatic bus_write_loader(input int addr, input logic [7:0] d);
        int guard;
        int t0;
        t0 = ld_clocks;
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
        repeat (2) @(posedge clock);
        if (ld_timing) ld_bytes++;
    endtask

    function automatic logic [7:0] pat(input int a);
        pat = 8'((a * 8'h9D) ^ 8'h5A);
    endfunction

    logic [7:0] got;

    always @(posedge clock) if (ld_timing) ld_clocks++;

    initial begin
`ifdef SDRAM_USE_MP
        $display("=== RAM.sv + sdram_kf_shim (sdram_mp) ===");
`else
        $display("=== RAM.sv + KFSDRAM (reference) ===");
`endif
        repeat (8) @(posedge clock);
        reset = 0;

        wait (initilized_sdram);
        $display("init done");

        // 512 bytes, written then read back. At ~1 us per pair this spans many
        // refresh intervals, so refresh collisions are exercised.
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

        // Interleaved write/read, which is closer to how a CPU actually behaves.
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

        // The BIOS region, which is where hardware actually fails.
        //
        // Everything above stays inside ONE row of ONE bank: 0x01000 and
        // 0x02000 are 512 and 256 bytes long, and with {row,bank,col} =
        // addr[23:11], addr[10:9], addr[8:0] both fit entirely in bank 0. So
        // the passing result says nothing about bank switching or row
        // crossing, and the BIOS at 0xF0000-0xFFFFF does 128 rows across all
        // four banks.
        //
        // 0xFD800-0xFDFFF crosses four bank boundaries and a row boundary, and
        // contains 0xFD880-0xFD883 -- the four bytes the CPU read as
        // F8 2E 41 D6 on hardware where the image holds F8 2E E8 D2.
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
        $display("  BIOS region (bank/row crossing): %0d errors", bios_errors);

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
        ld_timing = 1;
        for (int i = 0; i < 2048; i++)
            bus_write_loader(32'hFC000 + i, pat(i + 33));
        ld_timing = 0;
        // The number this whole change exists to move. KFSDRAM, measured the
        // same way before any of it, costs 8.08 clocks/byte; sdram_mp cost
        // 19.11, and APF's delivery rate allows about 10.9.
        $display("  loader cost: %0d clocks for %0d bytes = %0d.%02d clocks/byte (budget 10.9)",
                 ld_clocks, ld_bytes, ld_clocks / ld_bytes,
                 ((ld_clocks * 100) / ld_bytes) % 100);
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
        $display("  protocol violations : %0d", sdr.violations);
        $display("  data errors         : %0d", errors);
        $display("  bus timeouts        : %0d", timeouts);
        $display("  refreshes issued    : %0d", sdr.ref_count);
        $display("  writes/reads served : %0d / %0d", sdr.writes_served, sdr.reads_served);
        if (sdr.violations == 0 && errors == 0 && timeouts == 0)
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
