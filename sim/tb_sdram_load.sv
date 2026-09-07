//
// tb_sdram_load — three-port contention and bandwidth measurement for sdram_mp.
//
// This is the number that decides P0 option C (docs/P0_MEMORY.md §6): can one
// SDRAM carry the display fetch, EGC read-modify-write and CPU traffic at once?
// Requirement is roughly 7.7 MB/s display + ~15 MB/s EGC + CPU, so ~30 MB/s of
// sustained mixed traffic with no port starved.
//
// The load generators are always_ff state machines rather than forked threads,
// because fork/join under --timing in Verilator 5.020 segfaults when a branch
// calls a task that waits on a clock edge.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_sdram_load;

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

    localparam real CLK_MHZ = 85.909091;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    localparam int  WINDOW  = 20000;   // measurement window in clocks

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
    wire [DQ_BITS-1:0]   s_dq_out, s_dq_in;

    sdram_mp #(
        .PORTS(PORTS), .ROW_BITS(ROW_BITS), .COL_BITS(COL_BITS),
        .BANK_BITS(BANK_BITS), .DQ_BITS(DQ_BITS), .BURST_MAX(BURST_MAX),
        .CAS_LATENCY(CAS_LAT), .INIT_NOP(64)
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

    // ------------------------------------------------------------- generators
    //
    // port 0  display : long sequential reads, always hungry
    // port 1  EGC     : 32-word read then 32-word write over the same span
    // port 2  CPU     : short 2-word accesses at scattered addresses

    logic run;
    typedef enum logic [1:0] {G_REQ, G_WAIT_ACK, G_WAIT_DONE} gstate_t;
    gstate_t gs [PORTS];

    int      bursts   [PORTS];   // completed transactions per port
    int      words    [PORTS];   // words moved per port
    int      wait_cyc [PORTS];   // cycles spent waiting for a grant
    int      worst    [PORTS];   // worst-case grant latency
    int      pending  [PORTS];
    int      step     [PORTS];

    localparam int BASE0 = 32'h004000;
    localparam int BASE1 = 32'h010000;
    localparam int BASE2 = 32'h020000;

    always_ff @(posedge clk) begin
        if (rst) begin
            p_req <= '0; p_we <= '0; p_addr <= '0; p_len <= '0;
            for (int p = 0; p < PORTS; p++) begin
                gs[p]       = G_REQ;
                bursts[p]   = 0;
                words[p]    = 0;
                wait_cyc[p] = 0;
                worst[p]    = 0;
                pending[p]  = 0;
                step[p]     = 0;
            end
        end else if (run) begin
            for (int p = 0; p < PORTS; p++) begin
                case (gs[p])
                G_REQ: begin
                    case (p)
                    0: begin
                        p_addr[p] <= ADDR_BITS'(BASE0 + (step[p] % 256) * BURST_MAX);
                        p_len[p]  <= LEN_BITS'(BURST_MAX - 1);
                        p_we[p]   <= 1'b0;
                        pending[p] = BURST_MAX;
                    end
                    1: begin
                        p_addr[p] <= ADDR_BITS'(BASE1 + ((step[p] / 2) % 128) * BURST_MAX);
                        p_len[p]  <= LEN_BITS'(BURST_MAX - 1);
                        p_we[p]   <= step[p][0];      // read, then write back
                        pending[p] = BURST_MAX;
                    end
                    default: begin
                        p_addr[p] <= ADDR_BITS'(BASE2 + (step[p] % 512) * 64);
                        p_len[p]  <= LEN_BITS'(1);    // 2 words
                        p_we[p]   <= step[p][0];
                        pending[p] = 2;
                    end
                    endcase
                    p_req[p] <= 1'b1;
                    gs[p]     = G_WAIT_ACK;
                end
                G_WAIT_ACK: begin
                    wait_cyc[p] = wait_cyc[p] + 1;
                    pending[p]  = pending[p];
                    if (p_ack[p]) begin
                        p_req[p] <= 1'b0;
                        if (wait_cyc[p] > worst[p]) worst[p] = wait_cyc[p];
                        wait_cyc[p] = 0;
                        gs[p]       = G_WAIT_DONE;
                    end
                end
                G_WAIT_DONE: if (p_done[p]) begin
                    bursts[p] = bursts[p] + 1;
                    words[p]  = words[p] + pending[p];
                    step[p]   = step[p] + 1;
                    gs[p]     = G_REQ;
                end
                endcase
            end
        end
    end

    // Write data is not checked here; tb_sdram_mp covers integrity.
    always_comb begin
        for (int p = 0; p < PORTS; p++) begin
            p_wdata[p] = 16'(p_wcnt) ^ 16'hC3C3;
            p_wmask[p] = '1;
        end
    end

    // ------------------------------------------------------------------- main

    int cyc;
    always_ff @(posedge clk) if (run) cyc <= cyc + 1;

    function automatic real rate(input int w, input int c);
        rate = (real'(w) * 2.0 * CLK_MHZ) / real'(c);
    endfunction

    string names [PORTS];

    initial begin
        names[0] = "display (32w seq reads) ";
        names[1] = "EGC     (32w read+write)";
        names[2] = "CPU     (2w scattered)  ";
        run = 0; cyc = 0;
        repeat (4) @(posedge clk);
        rst = 0;
        wait (init_done);
        repeat (4) @(posedge clk);
        run = 1;

        repeat (WINDOW) @(posedge clk);
        run = 0;
        @(posedge clk);

        $display("\n=== three-port contention over %0d cycles @ %0.3f MHz ===",
                 cyc, CLK_MHZ);
        begin
            automatic int total = 0;
            for (int p = 0; p < PORTS; p++) begin
                $display("  port %0d %s : %5d bursts, %6d words, %6.1f MB/s, worst grant wait %0d cycles",
                         p, names[p], bursts[p], words[p], rate(words[p], cyc),
                         worst[p]);
                total += words[p];
            end
            $display("  ---");
            $display("  aggregate: %0d words -> %0.1f MB/s", total, rate(total, cyc));
            $display("  protocol violations: %0d", sdr.violations);
            if (sdr.violations == 0 && rate(total, cyc) >= 30.0)
                $display("  RESULT: PASS (>= 30 MB/s requirement)");
            else
                $display("  RESULT: FAIL");
        end
        $finish;
    end

    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
