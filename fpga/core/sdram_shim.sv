//
// sdram_shim — wraps sdram_mp in the request/flag handshake RAM.sv speaks.
//
// RAM.sv uses a level-request / pulse-flag protocol for one word at a time,
// which is a subset of what sdram_mp does. The mapping is:
//
//   write_request/read_request  ->  p_req + p_we, one word (p_len = 0)
//   write_flag / read_flag      ->  held while the transaction is in flight
//   idle                        ->  "a command can be accepted now", low
//                                   during refresh
//   data_out                    ->  latched from p_rdata on p_rvalid
//
// `enable_refresh` is ignored: sdram_mp refreshes on its own interval counter
// rather than being told when the bus is quiet. `refresh_mode` still has to be
// reported, because RAM.sv drops access_ready when a command collides with a
// refresh.
//
// Clocking: this runs the controller at whatever `sdram_clock` the chipset
// supplies (clk_chipset, 42.95 MHz) rather than at clk_core.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module sdram_shim #(
    // Published so the port list can use them; the internals below re-derive
    // the same values as localparams.
    parameter int ADDR_BITS_PUB    = 24,
    parameter int LEN_BITS_PUB     = 4,
    parameter int sdram_col_width  = 9,
    parameter int sdram_row_width  = 13,
    parameter int sdram_bank_width = 2,
    parameter int sdram_data_width = 16,
    // Timing in sdram_clock cycles. Defaults suit 42.95 MHz (23.3 ns); they are
    // deliberately loose, since one wait state costs nothing at one word per
    // transaction.
    parameter int T_RCD            = 2,
    parameter int T_RP             = 2,
    parameter int T_WR             = 2,
    parameter int T_RFC            = 4,
    // Back to CL=2. CL=3 was tried (testB22) on the theory that it would buy a
    // clock of read margin; STA did not move (-2.357 vs -2.408) and neither did
    // the hardware. It was the wrong lever: the constraint measures the pin-to-
    // pin relationship between the part launching data and the FPGA capturing
    // it, and CL changes when the data comes out, not how it is caught.
    parameter int CAS_LATENCY      = 2,
    parameter int INIT_NOP         = 10000,  // 233 us: the SDRAM's own init wait
    parameter int REFRESH_INT      = 320     // <= 7.8 us at 42.95 MHz
) (
    input  wire                               sdram_clock,
    input  wire                               sdram_reset,

    input  wire  [sdram_col_width
                  + sdram_row_width
                  + sdram_bank_width-1:0]     address,
    input  wire  [sdram_col_width-1:0]        access_num,
    input  wire  [sdram_data_width-1:0]       data_in,
    output logic [sdram_data_width-1:0]       data_out,
    // The second word of a two-word access on this port. RAM.sv stores ONE
    // GUEST BYTE PER 16-BIT SDRAM WORD (access_data_in is {8'h00, byte} and
    // the write mask is all-ones), so the guest's byte N and byte N+1 are
    // consecutive SDRAM WORDS. That makes a V30 word access one burst of two
    // rather than two transactions: one arbitration, one ACTIVATE, one extra
    // column clock. access_num picks the shape -- 1 or 2, nothing else -- and
    // these two carry the second word in each direction.
    //
    // A two-word read lands beat by beat: the first word is the addressed
    // byte, the second its odd half. RAM.sv only asks for two words when
    // word_access is up -- a guest word at an address the SDRAM serves.
    input  wire  [sdram_data_width-1:0]       data_in_hi,
    output logic [sdram_data_width-1:0]       data_out_hi,
    input  wire                               write_request,
    input  wire                               read_request,
    input  wire                               enable_refresh,
    output logic                              write_flag,
    output logic                              read_flag,
    output logic                              refresh_mode,
    output logic                              idle,

    output logic [sdram_row_width-1:0]        sdram_address,
    output logic                              sdram_cke,
    output logic                              sdram_cs,
    output logic                              sdram_ras,
    output logic                              sdram_cas,
    output logic                              sdram_we,
    output logic [sdram_bank_width-1:0]       sdram_ba,
    input  wire  [sdram_data_width-1:0]       sdram_dq_in,
    output logic [sdram_data_width-1:0]       sdram_dq_out,
    output logic                              sdram_dq_io,

    // ---------------------------------------------------------------- port B
    //
    // A second, read-only master, for the video side's font fetch. This is
    // what sdram_mp being multi-port was for: FONT.ROM is 282 KB against about
    // 202 KB of free M10K, so it lives in SDRAM and glyphs are read while the
    // picture is drawn.
    //
    // The controller is instanced with two ports on BOTH machines rather than
    // conditionally, because making the port count depend on a macro makes
    // every signal width depend on it too. Tie b_req low if unused: the
    // round-robin never grants it, and the guest path behaves as it did.
    input  wire                               b_req,      /* tie low if unused */
    input  wire  [ADDR_BITS_PUB-1:0]          b_addr,
    input  wire  [LEN_BITS_PUB-1:0]           b_len,
    output logic                              b_ack,
    output logic                              b_rvalid,
    output logic [sdram_data_width-1:0]       b_rdata,
    output logic                              b_done,

    // ---------------------------------------------------------------- port C
    //
    // The character generator window, which the guest reads glyphs through. It
    // is idle almost all the time -- one prefetch per character the guest asks
    // for -- so it gets a port of its own rather than a priority scheme against
    // the row buffer, which runs for the whole visible frame.
    input  wire                               c_req,
    input  wire  [ADDR_BITS_PUB-1:0]          c_addr,
    input  wire  [LEN_BITS_PUB-1:0]           c_len,
    output logic                              c_ack,
    output logic                              c_rvalid,
    output logic [sdram_data_width-1:0]       c_rdata,
    output logic                              c_done,

    // ---------------------------------------------------------------- port D
    //
    // The graphics plane's display fetch: twenty sixteen-word bursts per
    // scanline, four planes of eighty bytes each. Like C it is read-only; the
    // round robin inside sdram_mp shares the line time with the row buffer's
    // five bursts and the guest's traffic.
    input  wire                               d_req,
    input  wire  [ADDR_BITS_PUB-1:0]          d_addr,
    input  wire  [LEN_BITS_PUB-1:0]           d_len,
    output logic                              d_ack,
    output logic                              d_rvalid,
    output logic [sdram_data_width-1:0]       d_rdata,
    output logic                              d_done
);

    localparam int ADDR_BITS = sdram_col_width + sdram_row_width + sdram_bank_width;
    localparam int MASK_BITS = sdram_data_width/8;

    // Port A's caller only ever asks for one word at a time, so it never bursts and
    // its address never has to be checked against a column boundary. BURST_MAX
    // is 16 for port B: a glyph is sixteen bytes and RAM.sv stores one byte per
    // word, so that is one transaction instead of sixteen.
    localparam int BURST_MAX = 16;
    localparam int LEN_BITS  = (BURST_MAX > 1) ? $clog2(BURST_MAX) : 1;
    localparam int PORTS     = 4;

    // sdram_mp schedules its own refresh and has no cs pin: the SDRAM's chip
    // select is permanently asserted.
    wire _unused_refresh = enable_refresh;
    assign sdram_cs = 1'b0;

    logic        req, we_r, busy;
    logic [ADDR_BITS-1:0] addr_r;
    logic [LEN_BITS-1:0]  len_r;      // words - 1, latched with the request
    logic                 rbeat;      // which word of a two-word read is next
    logic [sdram_data_width-1:0] wdata_r, wdata_hi_r;
    logic        p_ack, p_done, p_rvalid, stat_idle, stat_refresh;
    logic [sdram_data_width-1:0] p_rdata;
    logic        mp_rvalid;
    logic [sdram_data_width-1:0] mp_rdata;

    // Request latch, shared by both far ends. Two different clocks apply here:
    // the request fields are captured the first cycle the requester is seen --
    // not when the far end can accept a command -- because req stays up until
    // p_ack and early capture costs nothing downstream. The write payload is
    // the opposite: data_in is RAM.sv's latch_data, a registered follower of
    // internal_data_bus, so on the request's first cycle it is still the
    // PREVIOUS byte. It is therefore resampled for the whole transaction and
    // frozen at p_done. The byte is guaranteed on the bus for the duration:
    // CPU and loader writes hold it until ready, and ready only rises from
    // COMPLETE_RAM_RW -- after p_done; a µPD71071 DMA write drops its strobe
    // at S4 but the FDC's byte stays driven on data_bus_out until the next
    // beat, dozens of clocks past any plausible commit. Sampled live at the
    // WRITE command instead -- which is what a single-port controller got away
    // with by never queueing behind other ports -- a delayed grant committed whatever
    // the bus had moved on to, and the sector image landed shifted.
    always_ff @(posedge sdram_clock or posedge sdram_reset) begin
        if (sdram_reset) begin
            req         <= 1'b0;
            we_r        <= 1'b0;
            busy        <= 1'b0;
            addr_r      <= '0;
            len_r       <= '0;
            rbeat       <= 1'b0;
            wdata_r     <= '0;
            wdata_hi_r  <= '0;
            data_out    <= '0;
            data_out_hi <= '0;
        end else begin
            if (busy && we_r) begin
                wdata_r    <= data_in;
                wdata_hi_r <= data_in_hi;
            end
            // Read beats arrive in address order, so the first belongs to the
            // addressed byte and the second to the odd half.
            if (p_rvalid) begin
                if (rbeat == 1'b0) data_out    <= p_rdata;
                else               data_out_hi <= p_rdata;
                rbeat <= ~rbeat;
            end

            if (!busy) begin
                if (write_request || read_request) begin
                    req        <= 1'b1;
                    we_r       <= write_request;
                    addr_r     <= address[ADDR_BITS-1:0];
                    // Exactly two shapes, tested rather than truncated: a
                    // wider access_num cannot silently become a long burst.
                    len_r  <= (access_num >= 'd2) ? LEN_BITS'(1) : LEN_BITS'(0);
                    rbeat  <= 1'b0;
                    busy   <= 1'b1;
                end
            end else begin
                if (p_ack)  req  <= 1'b0;
                if (p_done) busy <= 1'b0;
            end
        end
    end

    // The flag rises for the duration of the access and drops when the word
    // has landed; RAM.sv's state machine edges on both transitions.
    assign write_flag   = busy &  we_r;
    assign read_flag    = busy & ~we_r;
    // idle means "the controller can take a command now" and is low during
    // refresh. RAM.sv latches access_ready from it.
    //
    // ...and it matters far more than "matching" suggests. RAM.sv's CPU-facing
    // ready is OPEN LOOP:
    //
    //     else if (state == IDLE) access_ready <= idle;
    //
    // taken in the very cycle the command appears, and then held. Nothing waits
    // for the access to finish. What protects the CPU is only the length of
    // its bus cycle: it asserts MEMR in T2 and latches at the end of T3, one CPU
    // clock later, which at 4.77 MHz is nine chipset cycles. A controller that
    // answers in five fits; sdram_mp answers in ten, so it does not, and the CPU
    // latches the PREVIOUS access's byte every single time (tb_cpu_timing:
    // 64/64 wrong on CPU timing, 0/64 when the same reads wait for completion).
    // That is the whole bisection: every testbench passed because every
    // testbench waited.
    //
    // Dropping idle in the same cycle the request is seen turns that open loop
    // into a real handshake. access_ready latches 0 at the start of the access,
    // holds 0 through RAM_READ_1/2, and only returns in COMPLETE_RAM_RW, so the
    // CPU inserts wait states until the data is genuinely there. Correctness
    // then does not depend on the controller being fast enough -- which matters,
    // because bursts and extra ports will only make it slower.
    //
    // Safe against RAM.sv's other users of idle: initilized_sdram latches on the
    // first idle, long before any command, and the WAIT state is only entered
    // after the command has dropped.
    assign idle         = stat_idle & ~busy & ~(write_request | read_request);
    // RAM.sv's only mechanism for "the controller cannot serve you yet" is:
    //
    //     else if ((read_command) && (refresh_mode)) access_ready <= 1'b0;
    //
    // and unlike the IDLE-cycle latch above, that branch fires in ANY state, so
    // it does not depend on which value of RAM.sv's `state` the access_ready
    // block happens to see (RAM.sv assigns state with a BLOCKING assignment
    // inside always_ff, so that ordering is not even well defined in
    // simulation). Holding it through the transaction makes the CPU insert
    // wait states until COMPLETE_RAM_RW puts access_ready back up -- a real
    // handshake instead of a race against the bus-cycle length.
    //
    // It is a small lie -- we are busy, not refreshing -- but refresh_mode has
    // exactly one consumer in RAM.sv and this is what it is for.
    assign refresh_mode = stat_refresh | busy;

    // Far end: sdram_mp, the four-port controller.
    // ---------------------------------------------------------------------
    logic init_done;
    logic [MASK_BITS-1:0] dqm_unused;

    // Port A is the guest (the request/flag handshake, one word at a time),
    // port B the font fetch. Packed so the widths follow the controller's parameters.
    wire [PORTS-1:0] mp_req  = {d_req, c_req, b_req, req};
    wire [PORTS-1:0] mp_we   = {1'b0,  1'b0,  1'b0, we_r};
    wire [PORTS-1:0][ADDR_BITS-1:0] mp_addr  = {d_addr, c_addr, b_addr, addr_r};
    wire [PORTS-1:0][LEN_BITS-1:0]  mp_len   = {d_len,  c_len,  b_len,  len_r};
    // sdram_mp publishes the index of the word it wants in p_wcnt and consumes
    // p_wdata combinationally, so a two-word write is just this select. Ports
    // B, C and D are read-only.
    wire [LEN_BITS-1:0] mp_wcnt;
    wire [PORTS-1:0][sdram_data_width-1:0] mp_wdata =
        {{sdram_data_width{1'b0}}, {sdram_data_width{1'b0}},
         {sdram_data_width{1'b0}},
         (mp_wcnt == LEN_BITS'(0)) ? wdata_r : wdata_hi_r};
    wire [PORTS-1:0][MASK_BITS-1:0] mp_wmask =
        {{MASK_BITS{1'b1}}, {MASK_BITS{1'b1}}, {MASK_BITS{1'b1}},
         {MASK_BITS{1'b1}}};
    wire [PORTS-1:0] mp_ack, mp_done;
    wire [$clog2(PORTS)-1:0] mp_grant;

    assign p_ack    = mp_ack[0];
    assign p_done   = mp_done[0];
    assign b_ack    = mp_ack[1];
    assign b_done   = mp_done[1];
    assign c_ack    = mp_ack[2];
    assign c_done   = mp_done[2];
    assign d_ack    = mp_ack[3];
    assign d_done   = mp_done[3];
    // Read data is tagged with the owning port, so each master sees only its own.
    assign p_rvalid = mp_rvalid & (mp_grant == 2'd0);
    assign b_rvalid = mp_rvalid & (mp_grant == 2'd1);
    assign c_rvalid = mp_rvalid & (mp_grant == 2'd2);
    assign d_rvalid = mp_rvalid & (mp_grant == 2'd3);
    assign p_rdata  = mp_rdata;
    assign b_rdata  = mp_rdata;
    assign c_rdata  = mp_rdata;
    assign d_rdata  = mp_rdata;

    sdram_mp #(
        .PORTS       (PORTS),
        .ROW_BITS    (sdram_row_width),
        .COL_BITS    (sdram_col_width),
        .BANK_BITS   (sdram_bank_width),
        .DQ_BITS     (sdram_data_width),
        .BURST_MAX   (BURST_MAX),
        .CAS_LATENCY (CAS_LATENCY),
        .T_RCD       (T_RCD),
        .T_RP        (T_RP),
        .T_WR        (T_WR),
        .T_RFC       (T_RFC),
        .INIT_NOP    (INIT_NOP),
        .REFRESH_INT (REFRESH_INT)
    ) u_mp (
        .clk          (sdram_clock),
        .rst          (sdram_reset),
        .p_req        (mp_req),
        .p_we         (mp_we),
        .p_addr       (mp_addr),
        .p_len        (mp_len),
        .p_ack        (mp_ack),
        .p_wcnt       (mp_wcnt),
        .p_wdata      (mp_wdata),
        .p_wmask      (mp_wmask),
        .grant        (mp_grant),
        .p_rvalid     (mp_rvalid),
        .p_rdata      (mp_rdata),
        .p_done       (mp_done),
        .init_done    (init_done),
        .stat_idle    (stat_idle),
        .stat_refresh (stat_refresh),
        .sdram_a      (sdram_address),
        .sdram_ba     (sdram_ba),
        .sdram_cke    (sdram_cke),
        .sdram_ras_n  (sdram_ras),
        .sdram_cas_n  (sdram_cas),
        .sdram_we_n   (sdram_we),
        .sdram_dqm    (dqm_unused),
        .sdram_dq_in  (sdram_dq_in),
        .sdram_dq_out (sdram_dq_out),
        .sdram_dq_io  (sdram_dq_io)
    );

    wire _unused_init_done = init_done;

endmodule

`default_nettype wire
