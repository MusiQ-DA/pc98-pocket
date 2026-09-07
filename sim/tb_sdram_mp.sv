//
// tb_sdram_mp — protocol and bandwidth testbench for sdram_mp.
//
// This is the measurement that decides P0 option C (docs/P0_MEMORY.md §6). The
// requirement is roughly 7.7 MB/s of display fetch plus ~15 MB/s of EGC
// read-modify-write, on top of CPU traffic, so the number to beat is about
// 30 MB/s of sustained mixed traffic.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_sdram_mp;

    localparam int PORTS      = 3;
    localparam int ROW_BITS   = 13;
    localparam int COL_BITS   = 9;
    localparam int BANK_BITS  = 2;
    localparam int DQ_BITS    = 16;
    localparam int BURST_MAX  = 32;
    localparam int CAS_LAT    = 3;
    localparam int ADDR_BITS  = ROW_BITS + BANK_BITS + COL_BITS;
    localparam int LEN_BITS   = $clog2(BURST_MAX);
    localparam int GRANT_BITS = $clog2(PORTS);
    localparam int MASK_BITS  = DQ_BITS/8;

    // 85.909091 MHz
    localparam real CLK_MHZ = 85.909091;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clk = 0, rst = 1;
    always #(HALF_NS) clk = ~clk;

    logic [PORTS-1:0]                 p_req, p_we, p_ack, p_done;
    logic [PORTS-1:0][ADDR_BITS-1:0]  p_addr;
    logic [PORTS-1:0][LEN_BITS-1:0]   p_len;
    logic [PORTS-1:0][DQ_BITS-1:0]    p_wdata;
    logic [PORTS-1:0][MASK_BITS-1:0]  p_wmask;
    logic [LEN_BITS-1:0]              p_wcnt;
    logic [GRANT_BITS-1:0]            grant;
    logic                             p_rvalid, init_done;
    logic [DQ_BITS-1:0]               p_rdata;

    wire [ROW_BITS-1:0]  s_a;
    wire [BANK_BITS-1:0] s_ba;
    wire                 s_cke, s_ras_n, s_cas_n, s_we_n, s_dq_io;
    wire [MASK_BITS-1:0] s_dqm;
    wire [DQ_BITS-1:0]   s_dq_out;
    wire [DQ_BITS-1:0]   s_dq_in;

    sdram_mp #(
        .PORTS(PORTS), .ROW_BITS(ROW_BITS), .COL_BITS(COL_BITS),
        .BANK_BITS(BANK_BITS), .DQ_BITS(DQ_BITS), .BURST_MAX(BURST_MAX),
        .CAS_LATENCY(CAS_LAT),
        .INIT_NOP(64)          // shortened; the real part needs 100 us
    ) dut (
        .clk(clk), .rst(rst),
        .p_req(p_req), .p_we(p_we), .p_addr(p_addr), .p_len(p_len), .p_ack(p_ack),
        .p_wcnt(p_wcnt), .p_wdata(p_wdata), .p_wmask(p_wmask),
        .grant(grant), .p_rvalid(p_rvalid), .p_rdata(p_rdata), .p_done(p_done),
        .init_done(init_done),
        .sdram_a(s_a), .sdram_ba(s_ba), .sdram_cke(s_cke),
        .sdram_ras_n(s_ras_n), .sdram_cas_n(s_cas_n), .sdram_we_n(s_we_n),
        .sdram_dqm(s_dqm), .sdram_dq_in(s_dq_in),
        .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io)
    );

    sdram_model #(
        .ROW_BITS(ROW_BITS), .COL_BITS(COL_BITS), .BANK_BITS(BANK_BITS),
        .DQ_BITS(DQ_BITS)
    ) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ------------------------------------------------------------- bookkeeping

    int cycles;
    int words_moved;
    int errors;

    always_ff @(posedge clk) if (!rst) cycles <= cycles + 1;
    always_ff @(posedge clk) if (!rst && p_rvalid) words_moved <= words_moved + 1;

    // Write data: word i of a burst carries a value derived from its address so
    // the read-back check catches misplacement, not just corruption.
    function automatic logic [15:0] pattern(input int addr);
        pattern = 16'((addr * 32'h9E37) ^ 32'hA5A5);
    endfunction

    int wr_base [PORTS];
    always_comb begin
        for (int p = 0; p < PORTS; p++) begin
            p_wdata[p] = pattern(wr_base[p] + int'(p_wcnt));
            p_wmask[p] = '1;
        end
    end

    // ------------------------------------------------------------- transactions

    task automatic do_burst(input int port, input bit is_write,
                            input int addr, input int words);
        wr_base[port] = addr;
        p_addr[port]  = ADDR_BITS'(addr);
        p_len[port]   = LEN_BITS'(words - 1);
        p_we[port]    = is_write;
        p_req[port]   = 1'b1;
        @(posedge clk);
        while (!p_ack[port]) @(posedge clk);
        p_req[port] = 1'b0;
        while (!p_done[port]) @(posedge clk);
    endtask

    // Collects read data for the checker.
    logic [15:0] rd_buf [1024];
    int          rd_cnt;
    always_ff @(posedge clk) begin
        if (!rst && p_rvalid && rd_cnt < 1024) begin
            rd_buf[rd_cnt] <= p_rdata;
            rd_cnt         <= rd_cnt + 1;
        end
    end

    task automatic check_read(input int addr, input int words);
        for (int i = 0; i < words; i++) begin
            if (rd_buf[i] !== pattern(addr + i)) begin
                $display("  MISMATCH word %0d @%0h: got %h want %h",
                         i, addr + i, rd_buf[i], pattern(addr + i));
                errors++;
            end
        end
    endtask

    function automatic real mbytes_per_s(input int words, input int cyc);
        mbytes_per_s = (real'(words) * 2.0 * CLK_MHZ) / real'(cyc);
    endfunction

    // ------------------------------------------------------------------- main

    int t0, w0;
    real rate;

    initial begin
        p_req = '0; p_we = '0; p_addr = '0; p_len = '0;
        for (int p = 0; p < PORTS; p++) wr_base[p] = 0;
        cycles = 0; words_moved = 0; errors = 0; rd_cnt = 0;

        repeat (4) @(posedge clk);
        rst = 0;

        wait (init_done);
        $display("[%0t] init complete after %0d cycles", $time, cycles);

        // ---- 1. write a block, read it back, verify -----------------------
        $display("\n-- test 1: write/read-back integrity --");
        for (int b = 0; b < 8; b++)
            do_burst(0, 1'b1, 32'h001000 + b*BURST_MAX, BURST_MAX);
        rd_cnt = 0;
        do_burst(0, 1'b0, 32'h001000, BURST_MAX);
        repeat (CAS_LAT + 4) @(posedge clk);
        check_read(32'h001000, BURST_MAX);
        $display("   %0d words checked, %0d errors", BURST_MAX, errors);

        // ---- 2. sequential read throughput (display fetch shape) ----------
        $display("\n-- test 2: sequential read burst throughput --");
        t0 = cycles; w0 = words_moved;
        for (int b = 0; b < 64; b++)
            do_burst(0, 1'b0, 32'h001000 + b*BURST_MAX, BURST_MAX);
        rate = mbytes_per_s(words_moved - w0, cycles - t0);
        $display("   %0d words in %0d cycles -> %0.1f MB/s",
                 words_moved - w0, cycles - t0, rate);

        // Three-port contention lives in tb_sdram_load: Verilator 5.020's
        // --timing fork/join crashes when a fork branch calls a task that waits,
        // so the load generators there are always_ff blocks instead.

        // ---- verdict -------------------------------------------------------
        $display("\n=== summary ===");
        $display("  protocol violations : %0d", sdr.violations);
        $display("  data errors         : %0d", errors);
        $display("  reads served        : %0d", sdr.reads_served);
        $display("  writes served       : %0d", sdr.writes_served);
        if (sdr.violations == 0 && errors == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
