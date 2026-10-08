//
// pc98_video_timing -- the 640x400 raster, 24.83 kHz.
//
// Numbers from np21w's own GDC clock table (io/gdc.c), not from memory:
//
//     {14318180 / 8, 112 - 8, 112 + 8, 200, 300}   15.98 kHz
//     {21052600 / 8, 106 - 6, 106 + 6, 400, 575}   24.83 kHz   <- this one
//     {25260000 / 8, 100 - 8, 100 + 8, 400, 575}   31 kHz
//
// The first field is the CHARACTER clock, so the dot clock is 21.0526 MHz and
// the horizontal total is 106 characters of 8 dots = 848. np21w then computes
// hclock = clock / x = 2631575 / 106 = 24,826 Hz, and the vertical rate is
// hclock / y -- 440 lines gives 56.4 Hz, which is the mode PC-98 software
// expects.
//
// The blanking split inside the 208 non-displayed dots and the 40
// non-displayed lines is the uPD7220 SYNC decode of the BIOS's 24 kHz
// table, defsyncm24 {0x10,0x4e,0x07,0x25,0x07,0x07,0x90,0x65} (np21w
// io/gdc.c; same decode shape as every 7220 emulator):
//
//     HFP = (sync[3]>>2)+1 = 10 ch    VFP =  sync[5]&0x3f        = 7
//     HS  = (sync[2]&0x1f)+1 =  8 ch  VS  =  sync[2]>>5
//     HBP = (sync[4]&0x3f)+1 =  8 ch        + ((sync[3]&3)<<3)   = 8
//     CR  =  sync[1]+2       = 80 ch  VBP =  sync[7]>>2          = 25
//                                   AL  = (sync[7:6] word)
//                                        & 0x3ff, norm. to 1-1024 = 400
//
// Check: 10+8+8+80 = 106 characters and 7+8+25+400 = 440 lines -- the
// totals above. np21w itself never drives a raster off these (dispsync
// uses VBP only to offset the two planes against each other), so the
// pulse positions matter only for the VID_* outputs and where the
// frame-edge sampling lands inside the blank.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_video_timing #(
    parameter int H_ACTIVE = 640,
    parameter int H_FRONT  = 80,      // HFP 10 chars
    parameter int H_SYNC   = 64,      // HS   8 chars
    parameter int H_TOTAL  = 848,     // HBP  8 chars (implied by total)
    parameter int V_ACTIVE = 400,
    parameter int V_FRONT  = 7,
    parameter int V_SYNC   = 8,
    parameter int V_TOTAL  = 440      // VBP 25 implied; 24826/440 = 56.4 Hz
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
