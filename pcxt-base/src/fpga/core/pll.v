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
        // It was 11640 ps = 180 deg of the 23280 ps period. STA on run#101
        // measured the two directions:
        //
        //     write/command -> dram_*   setup  +4.395 ns
        //     read: dram_dq -> core     setup  -2.357 ns
        //
        // Moving this phase trades one against the other 1:1 -- earlier means
        // the part launches read data sooner (more setup for our capture) and
        // samples our commands sooner (less setup for them). The failing side
        // was the read, and 6.75 ns of total budget was sitting lopsided in the
        // write side. An even split would be 11640 - 3376 = 8264 ps, but the
        // phase is QUANTISED: this PLL runs a 687.2727 MHz VCO (85.909091 x 8),
        // so a VCO period is 1455.03 ps and only multiples of 1455 ps land on a
        // whole number of picoseconds. 8264 is rejected outright --
        //   Error: PLL Output Counter parameter 'phase_shift' is set to an
        //   illegal value of '8264 ps'
        // -- which is why the existing shifts are 11640 (8 VCO periods) and
        // 17460 (12). The nearest legal step down is 8730 ps, 6 VCO periods,
        // moving 2910 ps:
        //
        //     read           -2.357 + 2.910 = +0.553 ns
        //     write/command  +4.395 - 2.910 = +1.485 ns
        //
        // Both positive. Not the even split, but the finest the hardware
        // offers without going to 7275 ps, which would put the write side at
        // +0.030 and simply move the cliff.
        //
        // This is the same failure the hardware shows directly: the CPU reads
        // F8 2E 41 D6 at F000:D880 where the image holds F8 2E E8 D2, with the
        // low word correct and the next word wrong -- a marginal capture, not a
        // mapping or protocol fault (docs/HANDOVER.md §1).
        .output_clock_frequency2   ("42.954545 MHz"),
        .phase_shift2              ("8730 ps"),
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
