//
// sdram_board_model — sdram_model wrapped with the Pocket's board timing.
//
// The real board runs the SDRAM device clock (dram_clk) half a period OUT OF
// PHASE with the controller clock (pll.v outclk_2, phase_shift2 = 11640 ps on
// a 42.954545 MHz output = 180 degrees). Both testB2 builds passed every
// simulation yet failed on hardware, and the one structural thing every
// testbench got wrong is that the model sampled on the controller's edge.
//
// This wrapper feeds sdram_model a device clock that is the controller clock
// delayed by half a period, and adds realistic pin flight times:
//
//   * controller outputs (commands, address, write data, dq_io) reach the
//     device T_CO ns later (fabric FF to pin on Cyclone V, no IOE registers)
//   * the device's read data reaches the controller T_RET ns later (tAC plus
//     pin to fabric FF flight)
//
// A controller that only worked because the model shared its clock phase
// fails here the way it fails on the board.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module sdram_board_model #(
    parameter real CLK_MHZ   = 42.954545,
    parameter real T_CO_NS   = 7.0,    // controller FF -> device pin
    parameter real T_RET_NS  = 8.0,    // device pin -> controller FF (incl. tAC)
    parameter int  ROW_BITS  = 13,
    parameter int  COL_BITS  = 9,
    parameter int  BANK_BITS = 2,
    parameter int  DQ_BITS   = 16,
    parameter int  T_RCD     = 2,
    parameter int  T_RP      = 2,
    parameter int  T_WR      = 2,
    parameter int  T_RFC     = 7,
    parameter int  T_RAS     = 2,
    parameter int  T_RC      = 3,
    parameter int  T_REF     = 0,
    parameter bit  CHECK     = 1
) (
    input  wire                   clk,       // controller clock (reference)
    input  wire [ROW_BITS-1:0]    a,
    input  wire [BANK_BITS-1:0]   ba,
    input  wire                   cke,
    input  wire                   ras_n,
    input  wire                   cas_n,
    input  wire                   we_n,
    input  wire [DQ_BITS/8-1:0]   dqm,
    input  wire [DQ_BITS-1:0]     dq_out,
    input  wire                   dq_io,
    output wire [DQ_BITS-1:0]     dq_in
);

    localparam real HALF_NS = 500.0 / CLK_MHZ;   // half period (11.64 ns)

    // Device clock: controller clock delayed by half a period == 180 degrees,
    // which is what pll.v's phase_shift2 = "11640 ps" produces on the board.
    logic dev_clk = 1'b1;
    always #(HALF_NS) dev_clk = ~dev_clk;

    // Controller outputs reach the part after T_CO_NS.
    wire [ROW_BITS-1:0]  d_a    ; assign #(T_CO_NS) d_a     = a;
    wire [BANK_BITS-1:0] d_ba   ; assign #(T_CO_NS) d_ba    = ba;
    wire                 d_cke  ; assign #(T_CO_NS) d_cke   = cke;
    wire                 d_ras_n; assign #(T_CO_NS) d_ras_n = ras_n;
    wire                 d_cas_n; assign #(T_CO_NS) d_cas_n = cas_n;
    wire                 d_we_n ; assign #(T_CO_NS) d_we_n  = we_n;
    wire [DQ_BITS/8-1:0] d_dqm  ; assign #(T_CO_NS) d_dqm   = dqm;
    wire [DQ_BITS-1:0]   d_dqout; assign #(T_CO_NS) d_dqout = dq_out;
    wire                 d_dqio ; assign #(T_CO_NS) d_dqio  = dq_io;

    // Read data comes back after T_RET_NS.
    wire [DQ_BITS-1:0] m_dq_in;
    assign #(T_RET_NS) dq_in = m_dq_in;

    sdram_model #(
        .ROW_BITS  (ROW_BITS),
        .COL_BITS  (COL_BITS),
        .BANK_BITS (BANK_BITS),
        .DQ_BITS   (DQ_BITS),
        .T_RCD     (T_RCD),
        .T_RP      (T_RP),
        .T_WR      (T_WR),
        .T_RFC     (T_RFC),
        .T_RAS     (T_RAS),
        .T_RC      (T_RC),
        .T_REF     (T_REF),
        .CHECK     (CHECK),
        // This wrapper supplies the real launch/flight delays, so the part
        // inside it must present an honest one-period DQ window. Without this
        // the model's window is 3x too wide and the testbench cannot tell a
        // correct DQ sample point from one half a cycle early -- which is
        // exactly how testB6 passed here and went black on hardware.
        .PHYSICAL_DQ (1'b1)
    ) u_part (
        .clk   (dev_clk),
        .a     (d_a),
        .ba    (d_ba),
        .cke   (d_cke),
        .ras_n (d_ras_n),
        .cas_n (d_cas_n),
        .we_n  (d_we_n),
        .dqm   (d_dqm),
        .dq_out(d_dqout),
        .dq_io (d_dqio),
        .dq_in (m_dq_in)
    );

endmodule

`default_nettype wire
