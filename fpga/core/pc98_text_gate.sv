//
// pc98_text_gate -- a STOPPED master GDC shows no text.
//
// np21w io/gdc.c (gdc_work): STOP (0x0C / 0x05) and SYNC with display off
// (0x0E) clear gdcs.textdisp's GDCSCRN_ENABLE, and vram/scrndraw.c then
// composites no text plane at all until START (0x0D / 0x6B) or SYNC-on
// (0x0F) sets it again. That is all INT 18h AH=0Dh ("text display off") is
// on the machine -- the ROM's `mov al,0Ch / out 62h,al` at FE938 -- and
// games use it to take the DOS banner off a graphics title: Dynamo
// (MARKA PROJECT, 1991) calls int86(0x18) with AH=0Dh just before its
// AH=42h/40h graphics setup, and on the core its "Dynamo Ver.0.77 ... BGM
// Library ..." banner stayed over the title.
//
// pc98_text_render's gdc_on only picks the SAD/pitch addressing -- a stopped
// GDC falls back to 80 columns from cell 0 and KEEPS drawing -- so the blank
// is applied to the renderer's pixel here, in the dot-clock domain.
//
// Only once the GDC has been STARTed since reset: np21w hides text before
// the first START too, but the core's pre-START picture (the unprogrammed-
// GDC fallback the renderer documents) stays exactly as it was.
//
// disp_on is pc98_gdc's level (START seen, STOP not), in the chipset clock.
// The stopped level is a flop there, then two flops into the dot clock,
// like the other single-bit GDC controls Peripherals carries across.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_text_gate (
    input  wire clk,          // the GDC's clock
    input  wire reset,
    input  wire disp_on,      // master GDC: START seen, STOP not

    input  wire clk_dot,      // the renderer's dot clock
    input  wire pixel_in,     // the renderer's lit pixel
    output wire pixel_out,    // ...with a stopped plane blanked
    output wire text_off      // the dot-domain level, for the record
);

    logic started = 1'b0, stopped = 1'b0;
    always_ff @(posedge clk) begin
        if (reset) begin
            started <= 1'b0;
            stopped <= 1'b0;
        end else begin
            if (disp_on) started <= 1'b1;
            stopped <= started & ~disp_on;
        end
    end

    logic off_s1 = 1'b0, off_px = 1'b0;
    always_ff @(posedge clk_dot) begin
        off_s1 <= stopped;
        off_px <= off_s1;
    end

    assign pixel_out = pixel_in & ~off_px;
    assign text_off  = off_px;

endmodule

`default_nettype wire
