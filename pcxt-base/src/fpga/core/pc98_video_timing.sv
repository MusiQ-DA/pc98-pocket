//
// pc98_video_timing -- the 640x400 raster, 24.83 kHz.
//
// Numbers from np2's own GDC clock table (io/gdc.c), not from memory:
//
//     {14318180 / 8, 112 - 8, 112 + 8, 200, 300}   15.98 kHz
//     {21052600 / 8, 106 - 6, 106 + 6, 400, 575}   24.83 kHz   <- this one
//     {25260000 / 8, 100 - 8, 100 + 8, 400, 575}   31 kHz
//
// The first field is the CHARACTER clock, so the dot clock is 21.0526 MHz and
// the horizontal total is 106 characters of 8 dots = 848. np2 then computes
// hclock = clock / x = 2631575 / 106 = 24,826 Hz, and the vertical rate is
// hclock / y -- 440 lines gives 56.4 Hz, which is the mode PC-98 software
// expects.
//
// The blanking split inside the 208 non-displayed dots and the 40 non-displayed
// lines is not fixed by that table -- a real GDC is programmed with it, and the
// BIOS does the programming. These defaults are a sane centred raster to bring
// the path up; when the GDC's sync parameters are implemented they replace
// them, which is why they are parameters rather than literals.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_video_timing #(
    parameter int H_ACTIVE = 640,
    parameter int H_FRONT  = 40,
    parameter int H_SYNC   = 64,
    parameter int H_TOTAL  = 848,     // 106 characters
    parameter int V_ACTIVE = 400,
    parameter int V_FRONT  = 12,
    parameter int V_SYNC   = 8,
    parameter int V_TOTAL  = 440      // 24826 / 440 = 56.4 Hz
) (
    input  wire        clk,
    input  wire        ce,            // one dot per assertion
    input  wire        rst,

    output logic [9:0] hcount,
    output logic [9:0] vcount,
    output logic       hsync,
    output logic       vsync,
    output logic       hblank,
    output logic       vblank,
    output logic       de,            // in the displayed area
    output logic       frame_start    // one dot at the top-left of the frame
);

    localparam int H_SYNC_BEG = H_ACTIVE + H_FRONT;
    localparam int H_SYNC_END = H_SYNC_BEG + H_SYNC;
    localparam int V_SYNC_BEG = V_ACTIVE + V_FRONT;
    localparam int V_SYNC_END = V_SYNC_BEG + V_SYNC;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            hcount <= 10'd0;
            vcount <= 10'd0;
        end else if (ce) begin
            if (hcount == 10'(H_TOTAL - 1)) begin
                hcount <= 10'd0;
                vcount <= (vcount == 10'(V_TOTAL - 1)) ? 10'd0 : vcount + 10'd1;
            end else begin
                hcount <= hcount + 10'd1;
            end
        end
    end

    always_comb begin
        hblank      = (hcount >= 10'(H_ACTIVE));
        vblank      = (vcount >= 10'(V_ACTIVE));
        de          = ~hblank & ~vblank;
        hsync       = (hcount >= 10'(H_SYNC_BEG)) && (hcount < 10'(H_SYNC_END));
        vsync       = (vcount >= 10'(V_SYNC_BEG)) && (vcount < 10'(V_SYNC_END));
        frame_start = (hcount == 10'd0) && (vcount == 10'd0);
    end

endmodule

`default_nettype wire
