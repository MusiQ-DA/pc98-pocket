// PC-98 video PLL.
//
// Pixel-domain clocks from the Analogue Pocket 74.25 MHz reference (clk_74b):
//   outclk_0  21.052600 MHz            PC-98 dot clock (640x400, 24.83 kHz)
//   outclk_1  21.052600 MHz  @90 deg   same clock for DDR (video_rgb_clock_90)
//
// 21.0526 MHz is np2's own figure for this mode -- io/gdc.c carries the table
//
//     {21052600 / 8, 106 - 6, 106 + 6, 400, 575}
//
// where the first field is the CHARACTER clock, so the dot clock is 21.0526 MHz
// and the line is 106 characters of 8 dots. 2631575 / 106 = 24,826 Hz, and 440
// lines gives 56.4 Hz.
//
// A separate PLL for the same reason the Hercules one is separate: the main
// PLL's VCO is 687.2727 MHz and 21.0526 does not divide out of it (687.2727 /
// 21.0526 = 32.64), so it cannot come from there whatever the output count.
//
// 90 degrees at 21.0526 MHz is a quarter of 47500 ps.
`timescale 1ns/10ps
module pll_video_pc98 (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire locked
);

    altera_pll #(
        .fractional_vco_multiplier ("true"),
        .reference_clock_frequency ("74.25 MHz"),
        .operation_mode            ("normal"),
        .number_of_clocks          (2),
        .output_clock_frequency0   ("21.052600 MHz"),
        .phase_shift0              ("0 ps"),
        .duty_cycle0               (50),
        .output_clock_frequency1   ("21.052600 MHz"),
        .phase_shift1              ("11875 ps"),
        .duty_cycle1               (50),
        .pll_type                  ("General"),
        .pll_subtype               ("General")
    ) altera_pll_i (
        .rst      (rst),
        .outclk   ({outclk_1, outclk_0}),
        .locked   (locked),
        .fboutclk (),
        .fbclk    (1'b0),
        .refclk   (refclk)
    );

endmodule
