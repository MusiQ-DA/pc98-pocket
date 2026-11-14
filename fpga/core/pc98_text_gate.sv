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
// disp_on is pc98_gdc's level (START seen, STOP not), in the chipset clock;
// disp_on_dot is the same bit as Peripherals already carries it into the
// dot clock for the renderer (gdc_on_px), so the blank and the renderer's
// addressing fallback switch on the same dot. Only "started" crosses here:
// a chipset-clock flop (cleared by reset), then two flops into the dot clock.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_text_gate (
    input  wire clk,          // the GDC's clock
    input  wire reset,
    input  wire disp_on,      // master GDC: START seen, STOP not

    input  wire clk_dot,      // the renderer's dot clock
    input  wire disp_on_dot,  // disp_on, already synchronised to clk_dot
    input  wire pixel_in,     // the renderer's lit pixel
    output wire pixel_out,    // ...with a stopped plane blanked
    output wire text_off      // the dot-domain level, for the record
);

    logic started = 1'b0;
    always_ff @(posedge clk) begin
        if (reset)        started <= 1'b0;
        else if (disp_on) started <= 1'b1;
    end

    logic started_s1 = 1'b0, started_px = 1'b0;
    always_ff @(posedge clk_dot) begin
        started_s1 <= started;
        started_px <= started_s1;
    end

    assign text_off  = started_px & ~disp_on_dot;
    assign pixel_out = pixel_in & ~text_off;

endmodule

`default_nettype wire
