//
// pc98_text_rowbase -- where a text row's first cell sits in TVRAM.
//
// np21w vram/maketext.c is the authority for the TEXT side of the uPD7220:
//
//     pitch = gdc.m.para[GDC_PITCH] & 0xfe;      // the field is forced even
//     esi   = LOW12(LOADINTELWORD(gdc.m.para + GDC_SCROLL));
//     ...per text line... esi = LOW12(esi + pitch);
//     ...per cell........ edi = LOW12(edi + 1);   // +2 in the 40-column walk
//
// so the base of row R is LOW12(SAD + R*PITCH): a CELL index, twelve bits,
// NOT shifted -- the graphics GDC's LOW15(vad << 1) is a different reading
// of the same PRAM field (makegrex.c), which is why pc98_gdc hands both out
// raw and each consumer picks its own form.
//
// The wrap is the hardware's own ring: the text window is 4096 cells and
// LOW12 is the only arithmetic np21w ever applies, so scroll-by-SAD walks
// the visible window around the TVRAM ring instead of clipping it.
//
// AN UNPROGRAMMED GDC MUST GIVE TODAY'S PICTURE. gdc_on is the START
// command; a pitch of zero is a GDC that has been started but not told how
// wide a row is. Either way this falls back to eighty columns from cell 0,
// which is the expression the parent always drove before this module
// existed -- the same guard pc98_text_render applies to its own copy.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_text_rowbase (
    input  wire        gdc_on,      // master GDC START seen
    input  wire  [7:0] gdc_pitch,   // PITCH register, raw
    input  wire [15:0] gdc_sad,     // partition 0's SAD, raw
    input  wire  [4:0] row,         // the text row being addressed, 0-24
    output wire [11:0] base         // LOW12(SAD + row*PITCH), or row*80
);

    wire        live  = gdc_on & (gdc_pitch != 8'd0);
    // np21w masks with 0xfe -- an odd register value loses its low bit, it
    // does not round.
    wire  [7:0] pitch = live ? {gdc_pitch[7:1], 1'b0} : 8'd80;
    wire [11:0] sad   = live ? gdc_sad[11:0]           : 12'd0;

    // Both terms are cell counts; the 12-bit sum IS the LOW12 wrap. The
    // 5x8 product rides a DSP block (12 of 66 are in use) because the ALM
    // fabric is at 99 per cent -- a LUT multiplier is what pushed the fit
    // over the device edge.
    (* multstyle = "dsp" *) logic [12:0] row_pitch;
    always_comb row_pitch = row * pitch;
    assign base = sad + row_pitch[11:0];

endmodule

`default_nettype wire
