// PCXT Pocket system PLL.
//
// One fractional-N VCO from the Analogue Pocket 74.25 MHz reference (clk_74a) feeds all
// core clocks, so the CPU, chipset and CGA video are mutually phase-locked (as on the
// real machine, where all derive from one 14.31818 MHz crystal). Each output is an
// integer division of the VCO; Quartus solves the M/N/C counters from these strings.
//   outclk_0   42.954545 MHz            chipset + SDRAM controller + XT_CE_Generator
//   outclk_1   85.909091 MHz            i8088 (MCL86) CORE_CLK (2:1 to chipset)
//   outclk_2   42.954545 MHz  @180 deg  SDRAM device clock (dram_clk), edge-centered
//   outclk_3   28.636360 MHz            CGA dot clock
//   outclk_4   14.318180 MHz            scaler pixel clock (video_rgb_clock)
//   outclk_5   14.318180 MHz  @90 deg   scaler pixel clock, DDR sibling
`timescale 1ns/10ps
module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire outclk_2,
    output wire outclk_3,
    output wire outclk_4,
    output wire outclk_5,
    output wire locked
);

    altera_pll #(
        .fractional_vco_multiplier ("true"),
        .reference_clock_frequency ("74.25 MHz"),
        .operation_mode            ("normal"),
        .number_of_clocks          (6),
        .output_clock_frequency0   ("42.954545 MHz"),
        .phase_shift0              ("0 ps"),
        .duty_cycle0               (50),
        .output_clock_frequency1   ("85.909091 MHz"),
        .phase_shift1              ("0 ps"),
        .duty_cycle1               (50),
        // outclk_2 leaves the chip as dram_clk and is used nowhere else, so its
        // phase is purely an interface knob: it sets both when the SDRAM
        // samples our commands and when it launches read data at us.
        //
        // 11640 ps is 180 deg of the 23280 ps period, and it STAYS, because the
        // one experiment that moved it says every other value tried so far is
        // worse. Measured, run#101 vs run#104:
        //
        //                        11640 ps      8730 ps
        //     setup write/cmd     +4.395       +2.018
        //     setup read          -2.357       -4.585
        //     hold  write/cmd        --       +11.429
        //     hold  read             --       +16.021
        //
        // The move was made on the theory that the two directions trade 1:1 --
        // earlier means the part launches read data sooner (more setup for our
        // capture) and samples our commands sooner (less for them) -- so 2910
        // ps of the write side's surplus should have bought the read side out
        // of its 2.357 ns hole. BOTH got worse by about 2.3 ns instead. The
        // trade model is wrong, and nothing here should move again until a
        // third data point in the OTHER direction says what the real trend is.
        //
        // Whatever that trend turns out to be, note the read path is genuinely
        // failing timing at -2.357 ns and the hold side has 11-16 ns of room,
        // so the margin exists somewhere; this knob just is not how to reach
        // it. Phase values are also quantised: the VCO is 687.2727 MHz
        // (85.909091 x 8), a VCO period is 1455.03 ps, and only multiples of
        // 1455 land on a whole picosecond. 8264 was rejected outright --
        //   Error: PLL Output Counter parameter 'phase_shift' is set to an
        //   illegal value of '8264 ps'
        // -- which is why the shifts in this file are 11640 (8 VCO periods)
        // and 17460 (12).
        .output_clock_frequency2   ("42.954545 MHz"),
        .phase_shift2              ("11640 ps"),
        .duty_cycle2               (50),
        .output_clock_frequency3   ("28.636360 MHz"),
        .phase_shift3              ("0 ps"),
        .duty_cycle3               (50),
        .output_clock_frequency4   ("14.318180 MHz"),
        .phase_shift4              ("0 ps"),
        .duty_cycle4               (50),
        .output_clock_frequency5   ("14.318180 MHz"),
        .phase_shift5              ("17460 ps"),
        .duty_cycle5               (50),
        .pll_type                  ("General"),
        .pll_subtype               ("General")
    ) altera_pll_i (
        .rst      (rst),
        .outclk   ({outclk_5, outclk_4, outclk_3, outclk_2, outclk_1, outclk_0}),
        .locked   (locked),
        .fboutclk (),
        .fbclk    (1'b0),
        .refclk   (refclk)
    );

endmodule
