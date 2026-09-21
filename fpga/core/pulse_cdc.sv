//
// pulse_cdc -- carry a one-cycle pulse from one clock domain to another.
//
// The PC-98 text path needs this in one place and it is not optional there: the
// start of a text row happens on the dot clock (21.05 MHz) and starts a fill on
// the chipset clock (42.95 MHz), where the TVRAM and the SDRAM port live.
//
// A three-flop synchroniser on the pulse itself is the wrong tool and fails in
// two directions. Going to a SLOWER clock it drops pulses that are narrower
// than the destination period. Going to a faster one it can stretch a pulse
// into two. Neither is visible in a functional simulation that happens to use
// convenient clock ratios, and both produce a display that is intermittently
// wrong on hardware -- the most expensive class of fault this project has hit.
//
// So: the source TOGGLES a level on each pulse, the level crosses through two
// flops, and the destination edge-detects it. A level cannot be missed, only
// delayed. The cost is that pulses closer together than a few destination
// clocks are merged, which is fine here -- a text row is 16 scanlines apart.
//
// `busy` tells the source when a previous crossing is still in flight, so it
// can decide whether merging matters. For the row fill it does not: the fill
// takes far less than a row.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pulse_cdc (
    input  wire  src_clk,
    input  wire  src_rst,
    input  wire  src_pulse,
    output logic src_busy,

    input  wire  dst_clk,
    input  wire  dst_rst,
    output logic dst_pulse
);

    logic tog;
    always_ff @(posedge src_clk or posedge src_rst) begin
        if (src_rst) tog <= 1'b0;
        else if (src_pulse) tog <= ~tog;
    end

    // Two flops to resolve, a third to edge-detect against.
    logic s1, s2, s3;
    always_ff @(posedge dst_clk or posedge dst_rst) begin
        if (dst_rst) begin
            s1 <= 1'b0; s2 <= 1'b0; s3 <= 1'b0;
        end else begin
            s1 <= tog;
            s2 <= s1;
            s3 <= s2;
        end
    end

    assign dst_pulse = s2 ^ s3;

    // The toggle as the source last saw it come back, so it can tell whether
    // the far side has caught up.
    logic b1, b2;
    always_ff @(posedge src_clk or posedge src_rst) begin
        if (src_rst) begin
            b1 <= 1'b0; b2 <= 1'b0;
        end else begin
            b1 <= s3;
            b2 <= b1;
        end
    end
    assign src_busy = tog ^ b2;

endmodule

`default_nettype wire
