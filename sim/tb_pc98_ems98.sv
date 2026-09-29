//
// tb_pc98_ems98 -- the NEC-style EMS board (pc98_ems98) against real RAM.sv.
//
// Proves the whole path, not just the register file:
//
//   * an unmapped window leaves C0000-CFFFF in the hole (no SDRAM select);
//   * OUT 08E9h/08E1h..08E7h bank a window into the SDRAM pool, and a byte
//     written through the window lands at the pool word np21w's formula
//     predicts: word 0x800000 + (target-1)*0x100000 + (page&0xFC)*0x400 +
//     offset;
//   * IN 08E9h answers 00h/FFh by fitted megabyte, which is how software
//     sizes the board;
//   * target 0 maps the window's own base frame, and t > 8 drops the write
//     (np21w io/emsio.c semantics);
//   * the Lo-tech windows (ems_b*) now claim the SDRAM too -- they never
//     did, the select OR was missing them -- and keep priority if both
//     boards land on the same window.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_ems98;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    logic [19:0] address = '0;
    logic [7:0]  internal_data_bus = '0;
    logic [7:0]  data_bus_out;
    logic        memory_read_n = 1, memory_write_n = 1;
    logic        io_write_n = 1;
    logic        no_command_state = 1;
    logic        memory_access_ready, access_complete, ram_address_select_n;
    logic        initilized_sdram;

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;

    logic [6:0]  map_ems [0:3] = '{7'd0, 7'd0, 7'd0, 7'd0};
    // The Lo-tech window-enable Peripherals would make for a programmed page:
    // ena_ems AND the frame address. b1_on plays ena_ems[0], frame C0000.
    logic        b1_on = 1'b0;
    wire         ems_b1 = b1_on && (address[19:14] == 6'h30);

    logic [10:0] ems98_map [0:3];
    logic [7:0]  ems98_status;

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
        .ems_b1(ems_b1), .ems_b2(1'b0), .ems_b3(1'b0), .ems_b4(1'b0),
        .ems98_map(ems98_map),
        .bios_protect_flag(2'b00), .bios_shadow_flag(1'b0),
        .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0)
    );

    pc98_ems98 u_ems98 (
        .clock(clock), .reset(reset),
        .address(address), .internal_data_bus(internal_data_bus),
        .io_write_n(io_write_n), .address_enable_n(1'b0),
        .maxmem(4'd8),                       // the full pool
        .map(ems98_map), .status(ems98_status)
    );

    sdram_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                  .T_RAS(2), .T_RC(3), .T_REF(335)
`ifdef SDRAM_USE_MP
                  ,.PHYSICAL_DQ(1'b1)
`endif
                  ) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    int errors = 0;
    int timeouts = 0;
    localparam int CPU_CYCLE = 36;

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

    // An I/O write: the port rides the same 20-bit address bus.
    task automatic io_write(input int port, input logic [7:0] d);
        address = 20'(port);
        internal_data_bus = d;
        no_command_state = 0;
        io_write_n = 0;
        repeat (4) @(posedge clock);
        io_write_n = 1;
        no_command_state = 1;
        repeat (2) @(posedge clock);
    endtask

    task automatic check(input string what, input int addr,
                         input logic [7:0] want);
        logic [7:0] got;
        bus_read(addr, got);
        if (got !== want) begin
            $display("  FAIL %s: read @%05h = %02h, want %02h", what, addr, got, want);
            errors++;
        end
        else
            $display("  ok   %s: @%05h = %02h", what, addr, got);
    endtask

    // The model keys its store by the flat word reconstructed from the PINS
    // -- {row, bank, col}. sdram_mp's address bus is already {row,bank,col},
    // so the pool's word index IS the key. sdram_single puts the bank on top
    // ({bank,row,col}), so under it the same pool word keys differently.
    // Either way the window readback is the functional proof; this helper
    // only asks "which key does this controller produce for pool word w".
    function automatic int mkey(input int w);
`ifdef SDRAM_USE_MP
        mkey = w;
`else
        mkey = ((w & 32'h3FFE00) << 2) | (((w >> 22) & 3) << 9) | (w & 32'h1FF);
`endif
    endfunction

    task automatic check_store(input string what, input int word,
                               input logic [15:0] want);
        logic [15:0] got;
        automatic int key = mkey(word);
        got = sdr.store.exists(key) ? sdr.store[key] : 16'hDEAD;
        if (got !== want) begin
            $display("  FAIL %s: sdram word %06h = %04h, want %04h",
                     what, word, got, want);
            errors++;
        end
        else
            $display("  ok   %s: word %06h = %04h", what, word, got);
    endtask

    // A C0000 access while no window claims it must not select the SDRAM.
    task automatic check_hole(input int addr);
        address = 20'(addr);
        no_command_state = 0;
        memory_read_n = 0;
        @(posedge clock);
        if (ram_address_select_n !== 1'b1) begin
            $display("  FAIL hole @%05h: SDRAM selected an unmapped window", addr);
            errors++;
        end
        else
            $display("  ok   hole @%05h stays unselected", addr);
        memory_read_n = 1;
        no_command_state = 1;
        repeat (2) @(posedge clock);
    endtask

    logic [7:0] got;

    initial begin
        $display("=== pc98_ems98 + RAM.sv ===");
        repeat (8) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);
        $display("init done");

        // Power-on: nothing mapped, the C0000 frame is a hole, and IN 08E9h
        // says "no megabyte selected".
        check_hole(32'hC0000);
        check_hole(32'hCFFFF);
        if (ems98_status !== 8'hFF) begin
            $display("  FAIL IN 08E9h at reset: %02h, want FF", ems98_status);
            errors++;
        end

        // Target 1, window 0, page 2 -> SDRAM word 0x808000.
        io_write(16'h08E9, 8'h01);
        if (ems98_status !== 8'h00) begin
            $display("  FAIL IN 08E9h t=1: %02h, want 00", ems98_status);
            errors++;
        end
        io_write(16'h08E1, 8'h08);
        bus_write(32'hC0123, 8'hA5);
        check_store("t1 win0 pg2 -> 0x808123", 24'h808123, 16'h00A5);
        check    ("t1 win0 readback",          32'hC0123, 8'hA5);
        // The rest of the frame is still a hole.
        check_hole(32'hC4000);

        // Target 1, window 2, page 1 -> 0x804000; writes land, reads return.
        io_write(16'h08E5, 8'h04);
        bus_write(32'hC8000, 8'h5A);
        check_store("t1 win2 pg1 -> 0x804000", 24'h804000, 16'h005A);
        check    ("t1 win2 readback",          32'hC8000, 8'h5A);

        // Target 2, window 3, page 63 -> 0x900000 + 0xFC000 = 0x9FC000.
        io_write(16'h08E9, 8'h02);
        io_write(16'h08E7, 8'hFC);
        bus_write(32'hCC456, 8'hC3);
        check_store("t2 win3 pg63 -> 0x9FC456", 24'h9FC456, 16'h00C3);
        check    ("t2 win3 readback",           32'hCC456, 8'hC3);

        // The size probe: last fitted megabyte answers 00h, first absent FFh.
        io_write(16'h08E9, 8'h08);
        if (ems98_status !== 8'h00) begin
            $display("  FAIL IN 08E9h t=8: %02h, want 00", ems98_status);
            errors++;
        end
        io_write(16'h08E9, 8'h09);
        if (ems98_status !== 8'hFF) begin
            $display("  FAIL IN 08E9h t=9: %02h, want FF", ems98_status);
            errors++;
        end
        else
            $display("  ok   IN 08E9h scan: 8 MB fitted");

        // t > MAXMEM drops the page write: window 0 must still point at
        // t1 pg2 (0x808000), not at a bank 8 that does not exist.
        io_write(16'h08E1, 8'h20);
        bus_write(32'hC0010, 8'h11);
        check_store("t9 write dropped, win0 -> 0x808010", 24'h808010, 16'h0011);

        // Target 0 maps the window's own base frame (np21w's unbanked state):
        // window 1 -> SDRAM word 0xC4000.
        io_write(16'h08E9, 8'h00);
        io_write(16'h08E3, 8'h00);
        bus_write(32'hC4789, 8'h66);
        check_store("t0 win1 base alias -> 0xC4789", 24'h0C4789, 16'h0066);
        check    ("t0 win1 readback",                  32'hC4789, 8'h66);

        // The Lo-tech board: ems_b1 with map_ems[0]=0x10 banks C0000-C3FFF at
        // 0x200000 + 0x10*0x4000 = 0x240000 -- and wins over the NEC window.
        map_ems[0] = 7'h10;
        b1_on = 1;
        bus_write(32'hC0777, 8'h77);
        check_store("lotech win0 -> 0x240777", 24'h240777, 16'h0077);
        check    ("lotech wins over ems98",    32'hC0777, 8'h77);
        b1_on = 0;

        $display("\n=== summary ===");
        $display("  protocol violations : %0d", sdr.violations);
        $display("  data errors         : %0d", errors);
        $display("  bus timeouts        : %0d", timeouts);
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
