//
// tb_cpu_timing -- does the 8088 get its data in time?
//
// The in-core self-test passes the whole base 64 KB through sdram_mp (hardware,
// testB14: PILOT A5/A5, PILOT2 5A/5A, PASS 64K), while the BIOS running on the
// 8088 reports three beeps for the same region. The self-test waits for
// ram_rw_complete before moving on. The 8088 does not.
//
// RAM.sv's ready is open loop: access_ready is taken from the controller's idle
// while the state machine is in IDLE, so it is already high when the access
// starts and nothing holds the CPU. What actually protects the read is the bus
// cycle length -- the 8088 asserts MEMR in T2 and latches at the end of T3, one
// CPU clock later, which at 4.77 MHz is nine chipset cycles.
//
// Measured latency from read command to data: KFSDRAM 5, sdram_mp 10. So this
// bench samples at a fixed offset like the CPU does, instead of waiting.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_cpu_timing;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    // Chipset cycles from the read command to the 8088's latch point.
    // 4.77 MHz: one CPU clock is nine chipset cycles.
    localparam int CPU_SAMPLE = 9;
    localparam int CPU_CLK    = 9;   // chipset cycles per 8088 clock at 4.77 MHz

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    logic [19:0] address = '0;
    logic  [7:0] internal_data_bus = '0;
    logic        memory_read_n = 1, memory_write_n = 1, no_command_state = 1;
    wire   [7:0] data_bus_out;
    wire         memory_access_ready, access_complete, ram_address_select_n;
    logic        initilized_sdram;

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [6:0] map [0:3] = '{7'd0, 7'd0, 7'd0, 7'd0};

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
        .map_ems(map), .ems_b1(1'b0), .ems_b2(1'b0), .ems_b3(1'b0), .ems_b4(1'b0),
        .bios_protect_flag(2'b00), .tandy_bios_flag(1'b0),
        .enable_a000h(1'b1), .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0)
    );

    sdram_board_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                        .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    int errors = 0, waited_errors = 0;

    // A write the way the CPU does it: assert, hold a bus cycle, drop.
    task automatic cpu_write(input int a, input logic [7:0] d);
        address = 20'(a);
        internal_data_bus = d;
        no_command_state = 0;
        memory_write_n = 0;
        repeat (36) @(posedge clock);          // a full 4-T bus cycle
        memory_write_n = 1;
        no_command_state = 1;
        repeat (4) @(posedge clock);
    endtask

    // A read the way the 8088 really does it. MEMR goes out in T2 and the data
    // is latched at the end of T3 -- but only if READY is high there. If it is
    // low the CPU inserts wait states, a whole CPU clock each, and re-checks.
    //
    // Modelling the CPU as never waiting was wrong and made even KFSDRAM's
    // shimmed reference fail; the point of the exercise is whether READY is
    // asserted HONESTLY, not whether the controller is fast.
    task automatic cpu_read(input int a, output logic [7:0] q, output int waits);
        address = 20'(a);
        no_command_state = 0;
        memory_read_n = 0;
        waits = 0;
        repeat (CPU_SAMPLE) @(posedge clock);   // T2 -> end of T3
        while (!memory_access_ready && waits < 40) begin
            repeat (CPU_CLK) @(posedge clock);  // one wait state
            waits++;
        end
        q = data_bus_out;                       // the 8088's latch point
        repeat (CPU_CLK) @(posedge clock);      // T4
        memory_read_n = 1;
        no_command_state = 1;
        repeat (4) @(posedge clock);
    endtask

    // The same read, but waiting for completion -- what the self-test does.
    task automatic waited_read(input int a, output logic [7:0] q);
        int guard = 0;
        address = 20'(a);
        no_command_state = 0;
        memory_read_n = 0;
        while (!access_complete && guard < 200) begin @(posedge clock); guard++; end
        q = data_bus_out;
        memory_read_n = 1;
        no_command_state = 1;
        repeat (4) @(posedge clock);
    endtask

    function automatic logic [7:0] pat(input int a);
        pat = 8'((a * 8'h9D) ^ 8'h5A);
    endfunction

    logic [7:0] got;
    int waits, total_waits = 0;

    initial begin
`ifdef SDRAM_USE_MP
        $display("=== 8088 read timing through sdram_mp ===");
`else
        $display("=== 8088 read timing through KFSDRAM (reference) ===");
`endif
        $display("    CPU latches %0d chipset cycles after MEMR", CPU_SAMPLE);
        repeat (8) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);

        for (int i = 0; i < 64; i++) cpu_write(32'h01000 + i, pat(i));

        // How the CPU reads.
        for (int i = 0; i < 64; i++) begin
            cpu_read(32'h01000 + i, got, waits);
            total_waits += waits;
            if (got !== pat(i)) begin
                if (errors < 4)
                    $display("  CPU-TIMED MISMATCH @%05h: got %02h want %02h",
                             32'h01000 + i, got, pat(i));
                errors++;
            end
        end

        // How the self-test reads, for contrast.
        for (int i = 0; i < 64; i++) begin
            waited_read(32'h01000 + i, got);
            if (got !== pat(i)) waited_errors++;
        end

        $display("\n=== summary ===");
        $display("  errors, CPU timing  : %0d / 64", errors);
        $display("  wait states inserted: %0d total", total_waits);
        $display("  errors, waiting     : %0d / 64", waited_errors);
        if (errors == 0) $display("  RESULT: PASS");
        else             $display("  RESULT: FAIL -- the CPU samples before the data arrives");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
