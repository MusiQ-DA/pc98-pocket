// altera_pll stub for scripts/lint_core.sh. The real PLL is a Quartus
// megafunction: linting needs its parameter and port names, nothing else --
// the clock behaviour is not modelled, so nothing here can time a design.
// A named connection to a parameter that does not exist is a hard lint error,
// so every parameter the three instances pass is spelled out below.
`default_nettype none
module altera_pll #(
    parameter number_of_clocks = 1,
    parameter output_clock_frequency0 = "0 MHz",
    parameter output_clock_frequency1 = "0 MHz",
    parameter output_clock_frequency2 = "0 MHz",
    parameter output_clock_frequency3 = "0 MHz",
    parameter output_clock_frequency4 = "0 MHz",
    parameter output_clock_frequency5 = "0 MHz",
    parameter phase_shift0 = "0 ps",
    parameter phase_shift1 = "0 ps",
    parameter phase_shift2 = "0 ps",
    parameter phase_shift3 = "0 ps",
    parameter phase_shift4 = "0 ps",
    parameter phase_shift5 = "0 ps",
    parameter duty_cycle0 = 50,
    parameter duty_cycle1 = 50,
    parameter duty_cycle2 = 50,
    parameter duty_cycle3 = 50,
    parameter duty_cycle4 = 50,
    parameter duty_cycle5 = 50,
    parameter fractional_vco_multiplier = "false",
    parameter reference_clock_frequency = "0 MHz",
    parameter operation_mode = "normal",
    parameter pll_type = "General",
    parameter pll_subtype = "General"
) (
    input  wire        rst,
    input  wire        refclk,
    input  wire        fbclk,
    output wire        fboutclk,
    output wire        locked,
    output wire [5:0]  outclk
);
    assign fboutclk = 1'b0;
    assign locked   = 1'b1;
    assign outclk   = 6'd0;
    wire _unused = &{1'b0, rst, refclk, fbclk, 1'b0};
endmodule
`default_nettype wire
