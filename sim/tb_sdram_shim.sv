//
// tb_sdram_shim — drives sdram_kf_shim the way RAM.sv drives KFSDRAM.
//
// RAM.sv holds write_request/read_request high and edges its state machine on
// the flag rising and falling, one word per access. This checks that the shim
// reproduces that handshake and that data survives a write/read round trip.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
`default_nettype none
`timescale 1ns/1ps

module tb_sdram_shim;
    localparam int AW = 24, DW = 16;
    localparam real HALF_NS = 500.0 / 42.954545;

    logic clk = 0, rst = 1;
    always #(HALF_NS) clk = ~clk;

    logic [AW-1:0] address = '0;
    logic [8:0]    access_num = 9'd1;
    logic [DW-1:0] data_in = '0;
    logic [DW-1:0] data_out;
    logic write_request = 0, read_request = 0;
    logic write_flag, read_flag, refresh_mode, idle;

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io;
    wire [DW-1:0] s_dq_out, s_dq_in;

    sdram_kf_shim #(.INIT_NOP(64), .REFRESH_INT(320), .CAS_LATENCY(2)) dut (
        .sdram_clock(clk), .sdram_reset(rst),
        .address(address), .access_num(access_num),
        .data_in(data_in), .data_out(data_out),
        .write_request(write_request), .read_request(read_request),
        .enable_refresh(1'b1),
        .write_flag(write_flag), .read_flag(read_flag),
        .refresh_mode(refresh_mode), .idle(idle),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io));

    sdram_model #(.T_RCD(2), .T_RP(2), .T_WR(2), .T_RFC(4)) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm(2'b00),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in));

    int errors = 0;

    // Mirrors RAM.sv: raise the request, wait for the flag to rise then fall.
    task automatic access(input bit is_write, input int addr, input logic [15:0] d);
        address = AW'(addr);
        data_in = d;
        if (is_write) write_request = 1; else read_request = 1;
        @(posedge clk);
        while (!(is_write ? write_flag : read_flag)) @(posedge clk);
        while ( (is_write ? write_flag : read_flag)) @(posedge clk);
        write_request = 0; read_request = 0;
        @(posedge clk);
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        wait (idle);
        $display("shim: init done");

        for (int i = 0; i < 32; i++)
            access(1'b1, 32'h001000 + i, 16'(i * 16'h1234 ^ 16'h5A5A));
        for (int i = 0; i < 32; i++) begin
            access(1'b0, 32'h001000 + i, 16'h0);
            if (data_out !== 16'(i * 16'h1234 ^ 16'h5A5A)) begin
                $display("  MISMATCH @%0d: got %h want %h",
                         i, data_out, 16'(i * 16'h1234 ^ 16'h5A5A));
                errors++;
            end
        end

        $display("\n=== shim summary ===");
        $display("  protocol violations : %0d", sdr.violations);
        $display("  data errors         : %0d", errors);
        if (sdr.violations == 0 && errors == 0) $display("  RESULT: PASS");
        else                                    $display("  RESULT: FAIL");
        $finish;
    end

    initial begin #5_000_000; $display("TIMEOUT"); $finish; end
endmodule

`default_nettype wire
