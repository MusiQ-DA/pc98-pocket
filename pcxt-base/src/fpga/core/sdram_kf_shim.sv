//
// sdram_kf_shim — KFSDRAM-compatible wrapper around sdram_mp.
//
// Exists to get sdram_mp onto real hardware underneath a system whose correct
// behaviour is already known. Our simulation coverage is good (0 protocol
// violations, verified read-back) but both the controller and the SDRAM model
// it is checked against are ours, so a shared misreading of the part would pass
// simulation and fail on the board. Booting the unmodified PCXT through
// sdram_mp is the independent check.
//
// The port list is KFSDRAM's, so this is a drop-in replacement in RAM.sv:
// select it with `SDRAM_USE_MP` (see config.tcl).
//
// KFSDRAM's callers use a level-request / pulse-flag protocol for one word at a
// time, which is a subset of what sdram_mp does. The mapping is:
//
//   write_request/read_request  ->  p_req + p_we, one word (p_len = 0)
//   write_flag / read_flag      ->  held while the transaction is in flight
//   idle                        ->  init_done and nothing in flight
//   data_out                    ->  latched from p_rdata on p_rvalid
//
// `enable_refresh` is ignored: sdram_mp refreshes on its own interval counter
// rather than being told when the bus is quiet. `refresh_mode` still has to be
// reported, because RAM.sv drops access_ready when a command collides with a
// refresh -- and `idle` has to mean "a command can be accepted now", not merely
// "no transaction in flight", or RAM.sv will tell the CPU an access completed
// while the controller is still refreshing.
//
// Clocking: this runs sdram_mp at whatever `sdram_clock` the chipset supplies
// (clk_chipset, 42.95 MHz) rather than at clk_core. Raising the clock is a
// separate change with its own timing closure; keeping it here means the
// hardware A/B has exactly one variable, the controller itself.
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
    parameter int CAS_LATENCY      = 2,
    parameter int INIT_NOP         = 4300,   // >= 100 us at 42.95 MHz
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

    // Unused: sdram_mp schedules its own refresh.
    wire _unused_refresh = enable_refresh;
    // The Pocket has no CS pin; KFSDRAM drove this and core_top left it open.
    assign sdram_cs = 1'b0;

    logic        req, we_r, busy;
    logic [ADDR_BITS-1:0] addr_r;
    logic        p_ack, p_done, p_rvalid, init_done, stat_idle, stat_refresh;
    logic [sdram_data_width-1:0] p_rdata;
    logic [0:0]  grant;

    // sdram_mp's request side is a one-entry command; hold it until acked.
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
                if (init_done && (write_request || read_request)) begin
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
    assign idle         = stat_idle & ~busy;
    assign refresh_mode = stat_refresh;

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

endmodule

`default_nettype wire
