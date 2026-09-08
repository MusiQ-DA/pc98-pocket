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
    parameter int LEN_BITS    = (BURST_MAX > 1) ? $clog2(BURST_MAX) : 1,
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
    // FSM visibility for wrappers that must tell a caller "not ready now".
    // stat_idle is asserted only when a command can be accepted this cycle;
    // it is low during refresh, which a "no transaction in flight" signal
    // would miss.
    output logic                             stat_idle,
    output logic                             stat_refresh,

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
        S_IDLE, S_ACT, S_RW, S_TAIL, S_REF_PRE, S_REF, S_PRE_MISS
    } state_t;

    state_t state;

    logic [2:0] cmd;
    always_comb {sdram_ras_n, sdram_cas_n, sdram_we_n} = cmd;

    always_comb begin
        stat_idle    = init_done & (state == S_IDLE) & (timer == 0) & ~refresh_due;
        stat_refresh = (state == S_REF) | (state == S_REF_PRE);
    end

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
    // Timer constants below use width casts rather than parameter bit-selects
    // (T_RP[15:0] etc). Bit-selecting a parameter is legal SystemVerilog that
    // simulators honour, but it is a classic synthesis-hazard construct: if the
    // tool mangles one constant the FSM still fits and passes STA while timing
    // out on real hardware in a way no RTL simulation can reproduce. The casts
    // make the intent unambiguous for any tool.
    logic [15:0]          init_left;
    logic [15:0]          refresh_cnt;
    logic                 refresh_due;

    assign refresh_due = (refresh_cnt >= 16'(REFRESH_INT));

    // Read data timing, derived from KFSDRAM -- the controller that boots this
    // board -- rather than from first principles, because the device clock is
    // antiphase (pll.v outclk_2 = clk_chipset + 180 deg) and the intuition
    // about which edge is "mid-window" inverts with it.
    //
    // The part samples commands on ITS rising edge, which is our FALLING edge.
    // So a READ driven out at posedge P is captured by the part at P+1/2, and
    // with CL=2 the datum is launched at the device edge P+CL+1/2 = P+2.5 --
    // again our falling edge. It is valid from P+2.5+tAC until roughly the
    // next device edge, i.e. the window is about [P+2.7, P+3.6] in cycles.
    //
    // The MIDDLE of that window is our POSEDGE P+3. The falling edge P+2.5 is
    // the launch instant itself, before tAC has elapsed -- sampling there
    // returns the previous word. (That was testB6, and it failed on hardware.)
    //
    // KFSDRAM lands on exactly P+3: its READ reaches the bus one cycle after
    // the request, its read_flag/data_out register fires three cycles later
    // (state_counter > cas_latency), and that pairing is what boots the board.
    // So: sample DQ on the posedge, RD_DELAY = CAS_LATENCY + 1, and rd_pipe[0]
    // is set in the same cycle the READ is driven -- p_rvalid then gates on
    // rd_pipe[RD_DELAY-1] and presents alongside the P+3 capture.
    localparam int RD_DELAY = CAS_LATENCY + 1;
    logic [RD_DELAY:0] rd_pipe;

    wire [ROW_BITS-1:0]  act_row  = p_addr[winner][ADDR_BITS-1 -: ROW_BITS];
    wire [BANK_BITS-1:0] act_bank = p_addr[winner][COL_BITS +: BANK_BITS];
    wire [COL_BITS-1:0]  act_col  = p_addr[winner][COL_BITS-1:0];
    wire [BANK_BITS-1:0] cur_bank = cur_addr[COL_BITS +: BANK_BITS];

    // ------------------------------------------------------- open-row policy
    //
    // Every transaction used to be ACTIVATE / access / PRECHARGE, which costs
    // four clocks before the access (ACT plus T_RCD) and four after (T_WR is
    // owed anyway, then PRE plus T_RP) whether or not the row was already
    // there. Measured against RAM.sv on the BIOS loader's cadence that made a
    // byte cost 19.11 clocks where KFSDRAM costs 8.08.
    //
    // That is not a performance nicety, it is the bug. data_loader cannot be
    // backpressured -- APF delivers a 32-bit word roughly every 75 clk_74a
    // cycles, about 21.7 chipset clocks per 16-bit word or 10.9 per byte, and
    // core_top's load FIFO drops silently when it fills. At 19.11 the consumer
    // loses by 1.75x and the BIOS image arrives full of holes: run#107
    // measured 4682 words thrown away, and run#106 caught two of them as
    // F000:D882-D883 and D88E-D88F never being written at all.
    //
    // So leave the row open. A hit skips both halves; a miss on the same bank
    // pays one PRECHARGE it would have paid anyway. The loader writes
    // consecutive addresses, and with {row,bank,col} = addr[23:11],
    // addr[10:9], addr[8:0] that is 511 hits in every 512.
    //
    // Correctness rests on three things:
    //   * a row that is open must be PRECHARGEd before a different row in the
    //     same bank is ACTIVATEd (S_PRE_MISS),
    //   * AUTO REFRESH is illegal with any bank open, so the refresh path
    //     still does PRECHARGE ALL and clears every flag (S_REF_PRE), and
    //   * tWR is still owed after the last write before any precharge, which
    //     S_TAIL continues to pay before returning to S_IDLE.
    // tWR is owed between the last write and a PRECHARGE of that bank -- and
    // with the row left open, that precharge no longer happens on the way out.
    // So the write transaction does not have to sit through it: report done
    // immediately and let this guard hold off the only two things that can
    // precharge (a row miss, and the refresh path's PRECHARGE ALL).
    logic [15:0]                pre_guard;
    logic [(1<<BANK_BITS)-1:0]  row_open;
    logic [ROW_BITS-1:0]        open_row [(1<<BANK_BITS)];
    wire row_hit  = row_open[act_bank] && (open_row[act_bank] == act_row);
    wire row_miss = row_open[act_bank] && (open_row[act_bank] != act_row);

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
            init_left    <= 16'(INIT_NOP);
            refresh_cnt  <= '0;
            rd_pipe      <= '0;
            left         <= '0;
            cur_we       <= 1'b0;
            cur_addr     <= '0;
            cur_col      <= '0;
            row_open     <= '0;
            pre_guard    <= '0;
        end else begin
            // Defaults; the states below override what they need.
            //
            // sdram_a and sdram_ba are deliberately NOT cleared here. They used
            // to be, which drove the address bus row -> 0 -> col -> 0 on every
            // access: thirteen address lines plus two bank lines switching
            // together, twice per transaction, for no reason. KFSDRAM holds its
            // address across a state instead, and KFSDRAM is the one that runs
            // reliably on this board.
            //
            // The hardware fault is intermittent (testB19/20 pass the BIOS
            // memory test, testB21/22 fail it) and no simulation reproduces it,
            // so it is physical. Simultaneous switching on the address bus is
            // exactly the kind of thing that corrupts a marginal data capture
            // and that no RTL simulation can see. Holding the address costs
            // nothing: the part latches it with the command, and NOP cycles do
            // not care what is on those pins.
            cmd         <= CMD_NOP;
            sdram_dqm   <= '0;
            sdram_dq_io <= 1'b1;
            p_ack       <= '0;
            p_done      <= '0;

            rd_pipe <= {rd_pipe[RD_DELAY-1:0], 1'b0};
            if (refresh_cnt != 16'hFFFF) refresh_cnt <= refresh_cnt + 16'd1;
            if (timer != 0)              timer       <= timer - 16'd1;
            if (pre_guard != 0)          pre_guard   <= pre_guard - 16'd1;

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
                timer     <= 16'(T_RP);
                init_left <= 16'd8;                // eight refreshes before MRS
                state     <= S_INIT_REF;
            end

            S_INIT_REF: if (timer == 0) begin
                if (init_left != 0) begin
                    cmd       <= CMD_REF;
                    timer     <= 16'(T_RFC);
                    init_left <= init_left - 16'd1;
                end else begin
                    cmd     <= CMD_MRS;
                    sdram_a <= MODE_REG;
                    timer   <= 16'(T_MRD);
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
                if (refresh_due && pre_guard == 0) begin
                    // PRECHARGE ALL first, then AUTO REFRESH -- exactly what
                    // KFSDRAM does (REFRESH_PALL -> REFRESH).
                    //
                    // This controller used to issue AUTO REFRESH on its own,
                    // reasoning that every transaction ends with a PRECHARGE of
                    // its bank so nothing can be open. That invariant does look
                    // sound on paper, but AUTO REFRESH with any bank still open
                    // is illegal and corrupts memory, and the cost of not
                    // relying on the argument is one state and a few cycles on
                    // an event that happens every 7.45 us. PRECHARGE ALL when
                    // everything is already precharged is a legal no-op.
                    //
                    // It matters more here than the invariant suggests: this
                    // controller puts addr[10:9] in the bank field, so the
                    // BIOS's base 64 KB test -- the one reporting three beeps
                    // on hardware -- spans all four banks, where KFSDRAM's
                    // mapping keeps that region entirely in bank 0.
                    cmd         <= CMD_PRE;
                    sdram_a     <= ROW_BITS'(1) << 10;   // A10 = all banks
                    timer       <= 16'(T_RP);
                    refresh_cnt <= '0;
                    row_open    <= '0;                   // nothing is open now
                    state       <= S_REF_PRE;
                end else if (have_req && !(row_miss && pre_guard != 0)) begin
                    cur_addr      <= p_addr[winner];
                    cur_col       <= act_col;
                    cur_we        <= p_we[winner];
                    left          <= {1'b0, p_len[winner]} + 1'b1;
                    grant         <= winner;
                    p_ack[winner] <= 1'b1;
                    p_wcnt        <= '0;
                    rr_ptr        <= (winner == GRANT_BITS'(PORTS-1)) ? '0
                                                                     : winner + 1'b1;
                    if (row_hit) begin
                        // Already there: straight to the access, no command
                        // and no T_RCD.
                        state <= S_RW;
                    end else if (row_miss && pre_guard == 0) begin
                        // Wrong row in this bank -- close it, then activate.
                        cmd      <= CMD_PRE;
                        sdram_ba <= act_bank;
                        sdram_a  <= '0;              // A10 low: this bank only
                        timer    <= 16'(T_RP);
                        row_open[act_bank] <= 1'b0;
                        state    <= S_PRE_MISS;
                    end else begin
                        cmd      <= CMD_ACT;
                        sdram_a  <= act_row;
                        sdram_ba <= act_bank;
                        row_open[act_bank] <= 1'b1;
                        open_row[act_bank] <= act_row;
                        timer    <= 16'(T_RCD);
                        state    <= S_ACT;
                    end
                end
            end

            S_REF_PRE: if (timer == 0) begin
                cmd   <= CMD_REF;
                timer <= 16'(T_RFC);
                state <= S_REF;
            end

            S_REF: if (timer == 0) state <= S_IDLE;

            // The bank was open on the wrong row; T_RP has been paid, so
            // activate the one that was asked for.
            S_PRE_MISS: if (timer == 0) begin
                cmd      <= CMD_ACT;
                sdram_a  <= cur_addr[ADDR_BITS-1 -: ROW_BITS];
                sdram_ba <= cur_bank;
                row_open[cur_bank] <= 1'b1;
                open_row[cur_bank] <= cur_addr[ADDR_BITS-1 -: ROW_BITS];
                timer    <= 16'(T_RCD);
                state    <= S_ACT;
            end

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
                    if (cur_we) begin
                        // The write is committed the moment the command is on
                        // the bus. Nothing downstream needs tWR -- only a
                        // later PRECHARGE does -- so finish here and let
                        // pre_guard carry the obligation.
                        p_done[grant] <= 1'b1;
                        pre_guard     <= 16'(T_WR);
                        state         <= S_IDLE;
                    end else begin
                        timer <= 16'(RD_DELAY);
                        state <= S_TAIL;
                    end
                end
            end

            // Reads only: drain the pipeline so p_rvalid has presented before
            // the transaction is declared done. Writes never come here.
            S_TAIL: if (timer == 0) begin
                p_done[grant] <= 1'b1;
                state         <= S_IDLE;
            end

            default: state <= S_INIT_NOP;

            endcase
        end
    end

    // Read data is registered straight off the bus at the posedge that sits in
    // the middle of the part's data window (see RD_DELAY above), one cycle
    // behind the pipeline tag so p_rdata and p_rvalid present together.
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
