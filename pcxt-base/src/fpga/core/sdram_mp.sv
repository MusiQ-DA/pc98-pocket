//
// sdram_mp — multi-port burst SDRAM controller for the Analogue Pocket.
//
// Replaces KFSDRAM for the PC-98 machine layer. KFSDRAM serves a single
// requester and precharges after every access, which leaves it far short of
// what a graphics VRAM needs (docs/P0_MEMORY.md §3). This controller keeps the
// same command sequencing but adds the two things that actually buy bandwidth:
//
//   * it runs at clk_core (85.909 MHz, exactly 2x clk_chipset) instead of
//     42.95 MHz, reusing a PLL output the design already generates
//   * it moves up to BURST_MAX words per granted transaction, so the ~8 cycles
//     of ACTIVATE/CAS/PRECHARGE overhead amortise across the burst
//
// Sustained rate is DQ_BITS * f * BURST/(BURST + overhead). At the defaults
// that is roughly 16 * 85.909e6 * 32/40 = 137 MB/s, against a requirement of
// about 7.7 MB/s of display fetch plus ~15 MB/s of EGC read-modify-write plus
// CPU traffic. The number that decides option C is the one the testbench
// measures, not this comment -- see docs/P0_SDRAM_DESIGN.md.
//
// Ports are arbitrated round-robin so no requester is starved by a neighbour
// that always has work queued. One transaction is in flight at a time, so the
// read data path is shared and tagged with `grant`.
//
// A burst must not cross a column boundary (COL_BITS words). Callers are cache
// line fills using aligned power-of-two bursts, which satisfies this by
// construction; the controller does not split a crossing burst.
//
// The Pocket brings no dram_cs pin out, so CS is effectively always asserted
// and commands are decoded from RAS/CAS/WE alone. dq_io follows the KFSDRAM
// convention and is an ACTIVE-LOW output enable, matching core_top's
//   assign dram_dq = ~SDRAM_DQ_IO ? SDRAM_DQ_OUT : 16'hZZZZ;
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module sdram_mp #(
    parameter int PORTS       = 3,
    parameter int ROW_BITS    = 13,
    parameter int COL_BITS    = 9,
    parameter int BANK_BITS   = 2,
    parameter int DQ_BITS     = 16,
    parameter int BURST_MAX   = 32,
    parameter int CAS_LATENCY = 3,

    // Timing, in controller clocks. Defaults are for 85.909 MHz (11.64 ns) and
    // are deliberately conservative; the testbench sweeps them.
    parameter int T_RCD       = 2,      // ACTIVATE -> READ/WRITE
    parameter int T_RP        = 2,      // PRECHARGE -> ACTIVATE
    parameter int T_WR        = 2,      // last write datum -> PRECHARGE
    parameter int T_RFC       = 7,      // AUTO REFRESH cycle
    parameter int T_MRD       = 2,      // MODE REGISTER SET -> any command
    parameter int INIT_NOP    = 8600,   // >= 100 us of NOP after power-up
    parameter int REFRESH_INT = 640,    // <= 7.8 us between AUTO REFRESH

    // Derived. Do not override.
    parameter int ADDR_BITS   = ROW_BITS + BANK_BITS + COL_BITS,
    parameter int LEN_BITS    = $clog2(BURST_MAX),
    parameter int GRANT_BITS  = (PORTS > 1) ? $clog2(PORTS) : 1,
    parameter int MASK_BITS   = DQ_BITS/8
) (
    input  wire                              clk,
    input  wire                              rst,

    // Request interface. Hold req until ack. addr is a word address laid out as
    // {row, bank, col} so consecutive column blocks land in different banks,
    // leaving room to add bank interleaving later without moving data.
    input  wire  [PORTS-1:0]                 p_req,
    input  wire  [PORTS-1:0]                 p_we,
    input  wire  [PORTS-1:0][ADDR_BITS-1:0]  p_addr,
    input  wire  [PORTS-1:0][LEN_BITS-1:0]   p_len,     // words to move, minus 1
    output logic [PORTS-1:0]                 p_ack,     // one cycle, request taken

    // Write data. The controller publishes the index of the word it wants in
    // p_wcnt and consumes p_wdata[grant] combinationally. p_wcnt is valid from
    // the ACTIVATE onward, so a caller sourcing from BRAM gets T_RCD cycles of
    // head start on the first word and one cycle per word thereafter.
    output logic [LEN_BITS-1:0]              p_wcnt,
    input  wire  [PORTS-1:0][DQ_BITS-1:0]    p_wdata,
    input  wire  [PORTS-1:0][MASK_BITS-1:0]  p_wmask,   // active high byte enables

    // Read data, tagged with the owning port.
    output logic [GRANT_BITS-1:0]            grant,
    output logic                             p_rvalid,
    output logic [DQ_BITS-1:0]               p_rdata,
    output logic [PORTS-1:0]                 p_done,    // one cycle, burst complete

    output logic                             init_done,

    // SDRAM device
    output logic [ROW_BITS-1:0]              sdram_a,
    output logic [BANK_BITS-1:0]             sdram_ba,
    output logic                             sdram_cke,
    output logic                             sdram_ras_n,
    output logic                             sdram_cas_n,
    output logic                             sdram_we_n,
    output logic [MASK_BITS-1:0]             sdram_dqm,
    input  wire  [DQ_BITS-1:0]               sdram_dq_in,
    output logic [DQ_BITS-1:0]               sdram_dq_out,
    output logic                             sdram_dq_io   // active low output enable
);

    // Command encodings, {ras_n, cas_n, we_n}. CS is tied asserted on this board.
    localparam logic [2:0] CMD_NOP   = 3'b111;
    localparam logic [2:0] CMD_ACT   = 3'b011;
    localparam logic [2:0] CMD_READ  = 3'b101;
    localparam logic [2:0] CMD_WRITE = 3'b100;
    localparam logic [2:0] CMD_PRE   = 3'b010;
    localparam logic [2:0] CMD_REF   = 3'b001;
    localparam logic [2:0] CMD_MRS   = 3'b000;

    // Mode register: A[2:0] burst length 1, A[3] sequential, A[6:4] CAS latency,
    // A[8:7] standard operation, A[9] burst read / burst write.
    localparam logic [ROW_BITS-1:0] MODE_REG = {
        {(ROW_BITS-10){1'b0}}, 1'b0, 2'b00, CAS_LATENCY[2:0], 1'b0, 3'b000
    };

    typedef enum logic [3:0] {
        S_INIT_NOP, S_INIT_PRE, S_INIT_REF, S_INIT_MRS,
        S_IDLE, S_ACT, S_RW, S_TAIL, S_PRE, S_REF
    } state_t;

    state_t state;

    logic [2:0] cmd;
    always_comb {sdram_ras_n, sdram_cas_n, sdram_we_n} = cmd;

    // ---------------------------------------------------------------- arbiter

    logic [GRANT_BITS-1:0] rr_ptr;    // where the next scan starts
    logic [GRANT_BITS-1:0] winner;
    logic                  have_req;
    integer                i, idx;

    always_comb begin
        winner   = '0;
        have_req = 1'b0;
        // Scan from rr_ptr downward so the lowest i (nearest rr_ptr) wins.
        for (i = PORTS-1; i >= 0; i = i - 1) begin
            idx = (rr_ptr + i) % PORTS;
            if (p_req[idx]) begin
                winner   = GRANT_BITS'(idx);
                have_req = 1'b1;
            end
        end
    end

    // ------------------------------------------------------- transaction regs

    logic [ADDR_BITS-1:0] cur_addr;
    logic [COL_BITS-1:0]  cur_col;
    logic [LEN_BITS:0]    left;        // words still to command
    logic                 cur_we;
    logic [15:0]          timer;
    logic [15:0]          init_left;
    logic [15:0]          refresh_cnt;
    logic                 refresh_due;

    assign refresh_due = (refresh_cnt >= REFRESH_INT[15:0]);

    // Read data returns CAS_LATENCY cycles after the READ command reaches the
    // part, plus one cycle because cmd is registered on the way out and one
    // more because sdram_dq_in is registered on the way in. Track which pipeline
    // slots carry real data so p_rvalid lines up with p_rdata.
    localparam int RD_DELAY = CAS_LATENCY + 2;
    logic [RD_DELAY:0] rd_pipe;

    wire [ROW_BITS-1:0]  act_row  = p_addr[winner][ADDR_BITS-1 -: ROW_BITS];
    wire [BANK_BITS-1:0] act_bank = p_addr[winner][COL_BITS +: BANK_BITS];
    wire [COL_BITS-1:0]  act_col  = p_addr[winner][COL_BITS-1:0];
    wire [BANK_BITS-1:0] cur_bank = cur_addr[COL_BITS +: BANK_BITS];

    // ------------------------------------------------------------- sequencer

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= S_INIT_NOP;
            cmd          <= CMD_NOP;
            sdram_a      <= '0;
            sdram_ba     <= '0;
            sdram_cke    <= 1'b1;
            sdram_dqm    <= '1;
            sdram_dq_out <= '0;
            sdram_dq_io  <= 1'b1;
            p_ack        <= '0;
            p_done       <= '0;
            p_wcnt       <= '0;
            grant        <= '0;
            rr_ptr       <= '0;
            init_done    <= 1'b0;
            timer        <= '0;
            init_left    <= INIT_NOP[15:0];
            refresh_cnt  <= '0;
            rd_pipe      <= '0;
            left         <= '0;
            cur_we       <= 1'b0;
            cur_addr     <= '0;
            cur_col      <= '0;
        end else begin
            // Defaults; the states below override what they need.
            cmd         <= CMD_NOP;
            sdram_a     <= '0;
            sdram_ba    <= '0;
            sdram_dqm   <= '0;
            sdram_dq_io <= 1'b1;
            p_ack       <= '0;
            p_done      <= '0;

            rd_pipe <= {rd_pipe[RD_DELAY-1:0], 1'b0};
            if (refresh_cnt != 16'hFFFF) refresh_cnt <= refresh_cnt + 16'd1;
            if (timer != 0)              timer       <= timer - 16'd1;

            case (state)

            // ---- power-up ------------------------------------------------
            S_INIT_NOP: begin
                sdram_dqm <= '1;
                if (init_left != 0) init_left <= init_left - 16'd1;
                else                state     <= S_INIT_PRE;
            end

            S_INIT_PRE: begin
                cmd       <= CMD_PRE;
                sdram_a   <= ROW_BITS'(1) << 10;   // A10 = precharge all banks
                timer     <= T_RP[15:0];
                init_left <= 16'd8;                // eight refreshes before MRS
                state     <= S_INIT_REF;
            end

            S_INIT_REF: if (timer == 0) begin
                if (init_left != 0) begin
                    cmd       <= CMD_REF;
                    timer     <= T_RFC[15:0];
                    init_left <= init_left - 16'd1;
                end else begin
                    cmd     <= CMD_MRS;
                    sdram_a <= MODE_REG;
                    timer   <= T_MRD[15:0];
                    state   <= S_INIT_MRS;
                end
            end

            S_INIT_MRS: if (timer == 0) begin
                init_done   <= 1'b1;
                refresh_cnt <= '0;
                state       <= S_IDLE;
            end

            // ---- steady state --------------------------------------------
            S_IDLE: if (timer == 0) begin
                if (refresh_due) begin
                    // Every transaction ends precharged, so AUTO REFRESH is
                    // safe to issue without a preceding PRECHARGE ALL.
                    cmd         <= CMD_REF;
                    timer       <= T_RFC[15:0];
                    refresh_cnt <= '0;
                    state       <= S_REF;
                end else if (have_req) begin
                    cmd           <= CMD_ACT;
                    sdram_a       <= act_row;
                    sdram_ba      <= act_bank;
                    cur_addr      <= p_addr[winner];
                    cur_col       <= act_col;
                    cur_we        <= p_we[winner];
                    left          <= {1'b0, p_len[winner]} + 1'b1;
                    grant         <= winner;
                    p_ack[winner] <= 1'b1;
                    p_wcnt        <= '0;
                    rr_ptr        <= (winner == GRANT_BITS'(PORTS-1)) ? '0
                                                                     : winner + 1'b1;
                    timer         <= T_RCD[15:0];
                    state         <= S_ACT;
                end
            end

            S_REF: if (timer == 0) state <= S_IDLE;

            S_ACT: if (timer == 0) state <= S_RW;

            S_RW: begin
                sdram_ba <= cur_bank;
                sdram_a  <= ROW_BITS'(cur_col);   // A10 low: no auto precharge
                if (cur_we) begin
                    cmd          <= CMD_WRITE;
                    sdram_dq_out <= p_wdata[grant];
                    sdram_dq_io  <= 1'b0;
                    sdram_dqm    <= ~p_wmask[grant];
                    p_wcnt       <= p_wcnt + 1'b1;
                end else begin
                    cmd        <= CMD_READ;
                    rd_pipe[0] <= 1'b1;
                end
                cur_col <= cur_col + 1'b1;
                left    <= left - 1'b1;
                if (left == 1) begin
                    timer <= cur_we ? T_WR[15:0] : RD_DELAY[15:0];
                    state <= S_TAIL;
                end
            end

            // Drain the read pipeline, or honour tWR, before precharging.
            S_TAIL: if (timer == 0) begin
                cmd      <= CMD_PRE;
                sdram_ba <= cur_bank;
                sdram_a  <= '0;                   // A10 low: this bank only
                timer    <= T_RP[15:0];
                state    <= S_PRE;
            end

            S_PRE: if (timer == 0) begin
                p_done[grant] <= 1'b1;
                state         <= S_IDLE;
            end

            default: state <= S_INIT_NOP;

            endcase
        end
    end

    // Read data is registered off the bus one cycle behind the pipeline tag so
    // p_rdata and p_rvalid present together.
    always_ff @(posedge clk) begin
        if (rst) begin
            p_rvalid <= 1'b0;
            p_rdata  <= '0;
        end else begin
            p_rvalid <= rd_pipe[RD_DELAY-1];
            p_rdata  <= sdram_dq_in;
        end
    end

endmodule

`default_nettype wire
