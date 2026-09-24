//
// pc98_gdc_mode2 -- the mode flip-flops behind I/O port 0x006A.
//
// Same shape as pc98_gdc_mode1 (port 0x68): a "bit set/reset" byte whose bits
// 3:1 pick a flip-flop and whose bit 0 is the new value, and which is only a
// mode write at all when the top nibble is clear. np2kai io/gdc.c, gdc_o6a:
//
//     if (!(dat & 0xf8)) {
//         bit = (dat >> 1) & 3;
//         dat &= 1;
//         ... gdc.mode2 ^= (1 << bit);
//
// Note the mask is 0xF8, not 0xF0, and the selector is TWO bits, not three:
// this port has four flip-flops, not eight.
//
// BIT 0 IS THE ONE THAT MOVES MEMORY. It selects analog (sixteen-colour) mode,
// and in np2kai that is not a palette switch -- it RE-MAPS VRAM
// (i386c/cpumem.c, memm_vram):
//
//     memfn0.rd8[0xa8000 >> 15] = vacc->rd8;   // B
//     memfn0.rd8[0xb0000 >> 15] = vacc->rd8;   // R
//     memfn0.rd8[0xb8000 >> 15] = vacc->rd8;   // G
//     memfn0.rd8[0xe0000 >> 15] = vacc->rd8;   // E
//     if (!(func & (1 << VOPBIT_ANALOG))) {       // digital: take E back
//         memfn0.rd8[0xe0000 >> 15] = memnc_rd8;
//     }
//
// So in DIGITAL mode the machine has three graphics planes and E0000-E7FFF
// answers to nothing; in ANALOG mode it has four and E0000 is the fourth.
// That is why a core with three planes works: it is in digital mode, where
// three is right.
//
// AND IT IS GATED. np2kai only acts on bit 0 while gdc.display's analog bit
// is set (`if (gdc.display & (1 << GDCDISP_ANALOG))`), which is a machine
// capability rather than a mode -- a machine without the sixteen-colour board
// ignores the write. This core has the planes, so `analog_capable` is tied
// true by its caller; the input exists so that is a decision someone made
// rather than one nobody noticed.
//
// Bytes 0x82-0x85 are a different shape entirely -- the extended commands of
// gdc_o6a's `else` arm, and of those the four that touch gdc.clock:
//
//     case 0x82: gdc.clock &= ~1;      case 0x84: gdc.clock &= ~2;
//     case 0x83: gdc.clock |=  1;      case 0x85: gdc.clock |=  2;
//
// d[2] picks the bit, d[0] the value -- the same set/reset idea in a wider
// encoding. The field is the machine's GDC clock switch: np2kai shows it as
// "2.5MHz"/"5MHz" (np2info, bit 7 is a shadow flag it toggles when the field
// hits 3, pccore.c), and in its renderers it changes what the slave GDC's
// PITCH means -- maketgrp doubles s_pitch while the flag is clear, so a
// 640-dot line is PITCH=40 words at 2.5MHz but PITCH=80 bytes at 5MHz. The
// BIOS writes the pair together in INT 18h's graphics setup (bios18.c:
// `gdc.clock |= 3` beside `PITCH = 80`).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_gdc_mode2 (
    input  wire        clk,
    input  wire        rst,

    // One cycle per port 0x6A write, with the written byte on `d`.
    input  wire        wr,
    input  wire  [7:0] d,

    // Whether this machine has the sixteen-colour hardware at all.
    input  wire        analog_capable,

    output logic [7:0] mode2,
    output logic [1:0] gdc_clk,        // clock field -- 3 selects 5MHz mode
    output wire        analog          // 1 = sixteen colours, E0000 is plane 3
);

    wire [1:0] sel = d[2:1];
    wire [3:0] msk = 4'h1 << sel;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            mode2    <= 8'h00;         // digital, three planes
            gdc_clk  <= 2'b00;         // the 2.5MHz clock this machine boots in
        end else if (wr) begin
            if ((d & 8'hF8) == 8'h00) begin
                // Bit 0 only moves while the machine admits to having the
                // hardware; the others are unconditional.
                if (!(sel == 2'd0) || analog_capable) begin
                    if (d[0]) mode2 <= mode2 |  {4'h0, msk};
                    else      mode2 <= mode2 & ~{4'h0, msk};
                end
            end else if ((d == 8'h82) || (d == 8'h83)
                      || (d == 8'h84) || (d == 8'h85)) begin
                gdc_clk[d[2]] <= d[0];
            end
        end
    end

    assign analog = mode2[0];

endmodule

`default_nettype wire
