//
// sdram_kf_shim — KFSDRAM-compatible wrapper around sdram_mp.
//
// Exists to get sdram_mp onto real hardware underneath a system whose correct
// behaviour is already known. Our simulation coverage is good (0 protocol
// violations, verified read-back, even with the board's antiphase device
// clock modelled) but both testB2 builds failed on hardware while every
// simulation passed, so the gap is being closed by bisection on real hardware.
//
// The port list is KFSDRAM's, so this is a drop-in replacement in RAM.sv:
// select it with `SDRAM_USE_MP` (see config.tcl).
//
// KFSDRAM's callers use a level-request / pulse-flag protocol for one word at a
// time, which is a subset of what sdram_mp does. The mapping is:
//
//   write_request/read_request  ->  p_req + p_we, one word (p_len = 0)
//   write_flag / read_flag      ->  held while the transaction is in flight
//   idle                        ->  "a command can be accepted now", low
//                                   during refresh, like KFSDRAM's own idle
//   data_out                    ->  latched from p_rdata on p_rvalid
//
// `enable_refresh` is ignored: sdram_mp refreshes on its own interval counter
// rather than being told when the bus is quiet. `refresh_mode` still has to be
// reported, because RAM.sv drops access_ready when a command collides with a
// refresh.
//
// Clocking: this runs the controller at whatever `sdram_clock` the chipset
// supplies (clk_chipset, 42.95 MHz) rather than at clk_core. Raising the clock
// is a separate change with its own timing closure; keeping it here means the
// hardware A/B has exactly one variable, the controller itself.
//
// Bisection rung 1 (`SDRAM_MP_KF_REF`, 2026-09-07): define it and the far end
// becomes the STOCK KFSDRAM translated onto sdram_mp's request interface,
// with this file's glue otherwise unchanged. KFSDRAM boots the board, so:
//   boots   -> the failure is inside sdram_mp
//   fails   -> the failure is in this glue / the RAM.sv-facing handshake
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module sdram_kf_shim #(
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
    parameter int INIT_NOP         = 10000,  // 233 us: matches the KFSDRAM the board boots with
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
    output logic                              sdram_dq_io
);

    localparam int ADDR_BITS = sdram_col_width + sdram_row_width + sdram_bank_width;
    localparam int MASK_BITS = sdram_data_width/8;

    // KFSDRAM's callers only ever ask for one word, so BURST_MAX is 1 here and
    // the address never has to be checked against a column boundary.
    localparam int BURST_MAX = 1;

    // sdram_mp schedules its own refresh; the KF_REF far end is stock KFSDRAM
    // and consumes enable_refresh directly (see its instantiation below).
    wire _unused_refresh = enable_refresh;
`ifndef SDRAM_MP_KF_REF
    assign sdram_cs = 1'b0;      // stock KFSDRAM drives its own cs in the KF_REF build
`endif

    logic        req, we_r, busy;
    logic [ADDR_BITS-1:0] addr_r;
    logic        p_ack, p_done, p_rvalid, stat_idle, stat_refresh;
    logic [sdram_data_width-1:0] p_rdata;
    logic [0:0]  grant;

    // Request latch, shared by both far ends. A request is taken only when the
    // far end can actually accept a command this cycle (stat_idle), which for
    // both far ends also means "not before initialisation" and "not while
    // refreshing".
    always_ff @(posedge sdram_clock or posedge sdram_reset) begin
        if (sdram_reset) begin
            req      <= 1'b0;
            we_r     <= 1'b0;
            busy     <= 1'b0;
            addr_r   <= '0;
            data_out <= '0;
        end else begin
            if (p_rvalid) data_out <= p_rdata;

            if (!busy) begin
                if (stat_idle && (write_request || read_request)) begin
                    req    <= 1'b1;
                    we_r   <= write_request;
                    addr_r <= address[ADDR_BITS-1:0];
                    busy   <= 1'b1;
                end
            end else begin
                if (p_ack)  req  <= 1'b0;
                if (p_done) busy <= 1'b0;
            end
        end
    end

    // KFSDRAM raises the flag for the duration of the access and drops it when
    // the word has landed; RAM.sv's state machine edges on both transitions.
    assign write_flag   = busy &  we_r;
    assign read_flag    = busy & ~we_r;
    // KFSDRAM's idle is (state == IDLE), which is low during refresh. Matching
    // that matters: RAM.sv latches access_ready from it.
    //
    // ...and it matters far more than "matching" suggests. RAM.sv's CPU-facing
    // ready is OPEN LOOP:
    //
    //     else if (state == IDLE) access_ready <= idle;
    //
    // taken in the very cycle the command appears, and then held. Nothing waits
    // for the access to finish. What protects the 8088 is only the length of
    // its bus cycle: it asserts MEMR in T2 and latches at the end of T3, one CPU
    // clock later, which at 4.77 MHz is nine chipset cycles. KFSDRAM answers in
    // five, so it fits; sdram_mp answers in ten, so it does not, and the CPU
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
    // simulation). Holding it through the transaction makes the 8088 insert
    // wait states until COMPLETE_RAM_RW puts access_ready back up -- a real
    // handshake instead of a race against the bus-cycle length.
    //
    // It is a small lie -- we are busy, not refreshing -- but refresh_mode has
    // exactly one consumer in RAM.sv and this is what it is for.
    assign refresh_mode = stat_refresh;   // VARIANT D: the |busy hack removed

`ifdef SDRAM_MP_KF_REF
    // ---------------------------------------------------------------------
    // Bisection rung 1: stock KFSDRAM on sdram_mp's interface. Level protocol
    // translated 1:1; refresh via KFSDRAM's own force backstop (exactly what
    // boots the board as testB3).
    // ---------------------------------------------------------------------
    logic        kf_idle, kf_write_flag, kf_read_flag, kf_refresh_mode;
    logic        kf_idle_q;
    logic        kf_seen_idle;
    logic [sdram_data_width-1:0] kf_data_out;

    // stat_idle mirrors KFSDRAM's own idle, qualified by "initialisation has
    // finished" so requests are not taken during the init sequence.
    assign stat_idle    = kf_idle & kf_seen_idle;
    assign stat_refresh = kf_refresh_mode;
    // mp-interface view of KFSDRAM: a request is accepted in the cycle it is
    // seen while idle; the transaction is complete once the FSM parks in IDLE
    // again; read data is valid exactly while read_flag pulses.
    assign p_ack     = stat_idle & req;
    assign p_rvalid  = kf_read_flag;
    assign p_rdata   = kf_data_out;
    assign p_done    = kf_idle & ~kf_idle_q;
    assign grant     = 1'b0;

    always_ff @(posedge sdram_clock or posedge sdram_reset) begin
        if (sdram_reset) begin
            kf_idle_q    <= 1'b0;
            kf_seen_idle <= 1'b0;
        end else begin
            kf_idle_q <= kf_idle;
            if (kf_idle) kf_seen_idle <= 1'b1;
        end
    end

    KFSDRAM #(
        .sdram_col_width    (sdram_col_width),
        .sdram_row_width    (sdram_row_width),
        .sdram_bank_width   (sdram_bank_width),
        .sdram_data_width   (sdram_data_width)
    ) u_KFSDRAM (
        .sdram_clock        (sdram_clock),
        .sdram_reset        (sdram_reset),
        .address            (addr_r),
        .access_num         (sdram_col_width'(1)),
        .data_in            (data_in),
        .data_out           (kf_data_out),
        .write_request      (req &  we_r),
        .read_request       (req & ~we_r),
        .enable_refresh     (enable_refresh),
        .write_flag         (kf_write_flag),
        .read_flag          (kf_read_flag),
        .refresh_mode       (kf_refresh_mode),
        .idle               (kf_idle),
        .sdram_address      (sdram_address),
        .sdram_cke          (sdram_cke),
        .sdram_cs           (sdram_cs),
        .sdram_ras          (sdram_ras),
        .sdram_cas          (sdram_cas),
        .sdram_we           (sdram_we),
        .sdram_ba           (sdram_ba),
        .sdram_dq_in        (sdram_dq_in),
        .sdram_dq_out       (sdram_dq_out),
        .sdram_dq_io        (sdram_dq_io)
    );

    wire _unused_mp_if = &{1'b0, kf_write_flag, grant, 1'b0};

`else
    // ---------------------------------------------------------------------
    // Shipping far end: sdram_mp.
    // ---------------------------------------------------------------------
    logic init_done;
    logic [MASK_BITS-1:0] dqm_unused;

    sdram_mp #(
        .PORTS       (1),
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
        .p_req        (req),
        .p_we         (we_r),
        .p_addr       (addr_r),
        .p_len        (1'b0),
        .p_ack        (p_ack),
        .p_wcnt       (),
        .p_wdata      (data_in),
        .p_wmask      ({MASK_BITS{1'b1}}),
        .grant        (grant),
        .p_rvalid     (p_rvalid),
        .p_rdata      (p_rdata),
        .p_done       (p_done),
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
`endif

endmodule

`default_nettype wire
