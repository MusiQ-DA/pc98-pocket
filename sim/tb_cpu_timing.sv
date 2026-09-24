//
// tb_cpu_timing -- does the V30 get its data in time, at the real CE rates?
//
// The in-core self-test passes the whole base 64 KB through sdram_mp (hardware,
// testB14: PILOT A5/A5, PILOT2 5A/5A, PASS 64K), while the BIOS running on the
// CPU reports three beeps for the same region. The self-test waits for
// ram_rw_complete before moving on. The CPU does not.
//
// RAM.sv's ready is open loop: nothing holds the CPU. What protects the read
// is the bus-cycle protocol -- and on this machine that protocol is paced by
// ce_generator's cpu_ce_* strobes, not by a fixed chipset-cycle window. The
// V30's speeds are the PC-98 family's 2.4576 MHz x2/x4 ("5 MHz"/"10 MHz") plus
// two faster cycle-paced steps -- none of them anywhere near the 8088's 4.77
// MHz this bench used to model.
//
// The contract the bridge actually runs (v30_cpu_bridge.sv):
//   * the 8288 strobes processor_status on cpu_ce_negedge -- commands assert
//     on a negedge
//   * READY is sampled at every cpu_ce_posedge from the third T state on;
//     each posedge with READY low is one wait state (one CPU clock)
//   * data is latched at the posedge where READY is high
//   * RAM's wait counter ticks on cpu_ce_negedge and must reach zero, which
//     is how clk_select 2/3 force at least one Tw
//
// So this bench instantiates the real ce_generator and speaks that protocol:
// command on a negedge, sample at posedges, latch where ready. It runs the
// whole pass at all four clk_select speeds, because "ready in time" means
// something different at 4.9 MHz and at 21.5 MHz.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_cpu_timing;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    // The real CE source, driven exactly as core_top drives it: clk_select is
    // latched once per speed phase (biu_done in the machine; a bench pulse
    // here between phases).
    logic [1:0] clk_select = 2'b00;
    logic       sel_load   = 1'b0;
    wire        ce_pos, ce_neg;
    wire [1:0]  rd_wait, wr_wait;

    ce_generator ce (
        .clock(clock), .reset(reset),
        .clk_select_load(sel_load), .clk_select(clk_select),
        .cpu_clk_pin(),
        .cpu_ce_posedge(ce_pos), .cpu_ce_negedge(ce_neg),
        .peripheral_ce(),
        .cycle_accrate(),
        .clock_cycle_counter_division_ratio(),
        .clock_cycle_counter_decrement_value(),
        .shift_read_timing(),
        .ram_read_wait_cycle(rd_wait), .ram_write_wait_cycle(wr_wait)
    );

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

    // RAM is wired as Chipset.sv wires it: the wait counter ticks on
    // cpu_ce_negedge and reloads from the generator's own wait-cycle outputs.
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
        .wait_count_clk_en(ce_neg),
        .ram_read_wait_cycle(rd_wait), .ram_write_wait_cycle(wr_wait)
    );

    sdram_board_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                        .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    int errors = 0, waited_errors = 0;

    // CE helpers. The strobes are single chipset-clock pulses produced on
    // posedge clock, so they are waited on negedge for a clean mid-cycle read.
    task automatic ce_posedge_wait;
        do @(negedge clock); while (!ce_pos);
    endtask
    task automatic ce_negedge_wait;
        do @(negedge clock); while (!ce_neg);
    endtask

    // A write the way the bridge does it: status strobed on a negedge, the
    // byte completes at a posedge where READY is high, passive through the
    // next negedge, two posedges of gap.
    task automatic cpu_write(input int a, input logic [7:0] d);
        int guard = 0;
        ce_negedge_wait();
        address = 20'(a);
        internal_data_bus = d;
        no_command_state = 0;
        memory_write_n = 0;
        ce_posedge_wait(); ce_posedge_wait();
        forever begin
            ce_posedge_wait();
            if (memory_access_ready) break;
            if (++guard > 80) begin
                $display("  WRITE ready timeout @%05h", a);
                break;
            end
        end
        ce_negedge_wait();
        memory_write_n = 1;
        no_command_state = 1;
        ce_posedge_wait(); ce_posedge_wait();
    endtask

    // A read the way the bridge does it: command at a negedge, READY sampled
    // at every posedge from the third on, each low sample one wait state.
    task automatic cpu_read(input int a, output logic [7:0] q, output int waits);
        ce_negedge_wait();
        address = 20'(a);
        no_command_state = 0;
        memory_read_n = 0;
        waits = 0;
        ce_posedge_wait(); ce_posedge_wait();
        forever begin
            ce_posedge_wait();
            if (memory_access_ready) break;
            if (++waits > 80) begin
                $display("  READ ready timeout @%05h", a);
                break;
            end
        end
        q = data_bus_out;                       // latched at the ready posedge
        ce_negedge_wait();
        memory_read_n = 1;
        no_command_state = 1;
        ce_posedge_wait(); ce_posedge_wait();   // B_GAP
    endtask

    // The same read, but waiting for completion -- what the self-test does.
    task automatic waited_read(input int a, output logic [7:0] q);
        int guard = 0;
        address = 20'(a);
        no_command_state = 0;
        memory_read_n = 0;
        while (!access_complete && guard < 400) begin @(posedge clock); guard++; end
        q = data_bus_out;
        memory_read_n = 1;
        no_command_state = 1;
        repeat (4) @(posedge clock);
    endtask

    function automatic logic [7:0] pat(input int a);
        pat = 8'((a * 8'h9D) ^ 8'h5A);
    endfunction

    logic [7:0] got;
    int waits, total_waits;

    // One pass at one clk_select: write, CE-paced read-back, waited read-back.
    task automatic run_speed(input int s, input string name);
        int spd_err = 0;
        clk_select = 2'(s);
        @(negedge clock) sel_load = 1;
        @(negedge clock) sel_load = 0;
        repeat (8) ce_posedge_wait();   // let the new edge ratio settle

        for (int i = 0; i < 64; i++) cpu_write(32'h01000 + i, pat(i));

        total_waits = 0;
        for (int i = 0; i < 64; i++) begin
            cpu_read(32'h01000 + i, got, waits);
            total_waits += waits;
            if (got !== pat(i)) begin
                if (spd_err < 4)
                    $display("  CPU-TIMED MISMATCH @%05h: got %02h want %02h",
                             32'h01000 + i, got, pat(i));
                spd_err++;
            end
        end
        errors += spd_err;
        $display("  %-28s errors %0d/64, wait states %0d, rd_wait %0d",
                 name, spd_err, total_waits, rd_wait);
    endtask

    initial begin
`ifdef SDRAM_USE_MP
        $display("=== V30 read timing through sdram_mp (CE-paced) ===");
`else
        $display("=== V30 read timing through sdram_single (reference, CE-paced) ===");
`endif
        repeat (8) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);

        run_speed(0, "4.9152 MHz (5 MHz, PC-98)");
        run_speed(1, "9.8304 MHz (10 MHz, PC-98)");
        run_speed(2, "19.6608 MHz (2x fast)");
        run_speed(3, "21.4773 MHz (chipset)");

        // How the self-test reads, for contrast -- speed-independent.
        for (int i = 0; i < 64; i++) begin
            waited_read(32'h01000 + i, got);
            if (got !== pat(i)) waited_errors++;
        end

        $display("\n=== summary ===");
        $display("  errors, CPU timing  : %0d / 256", errors);
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
