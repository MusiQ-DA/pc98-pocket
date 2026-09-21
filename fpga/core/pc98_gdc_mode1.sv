//
// pc98_gdc_mode1 -- the GDC mode flip-flops behind I/O port 0x0068.
//
// The real PC-98 has a bank of mode flip-flops the BIOS drives with "bit
// set/reset" bytes: a write below 0x10 carries a bit number in bits 3:1 and
// the new value in bit 0. np2 keeps them as gdc.mode1 (io/gdc.c, gdc_o68):
//
//     bit = 1 << ((dat >> 1) & 7);
//     dat & 1 ? (mode1 |= bit) : (mode1 &= ~bit);
//
// One of them matters to every letter on the screen. Bit 5 is the KAC/ANK
// force: while it is set, the text renderer treats EVERY cell as single-width
// ANK and ignores the cell's high byte outright (io/gdc.c,
// gdc_restorekacmode):
//
//     bitac = ((!uPD72020) && (mode1 & 0x20)) ? 0x00 : 0xff;
//
// This machine's text GDC is a uPD7220, so bit 5 set means bitac 0x00.
//
// That is not decoration, and this ROM depends on it:
//
//   * the FD80 POST's message printer (bios.rom FE0F0, disassembled) stores
//     ONLY the even byte of each cell -- STOSB for the code, then a byte at
//     +0x2000 for the attribute. It never writes the cell's high byte, which
//     is only safe in a mode where the high byte cannot make the cell a
//     kanji.
//   * the same ROM toggles the bit for real: OUT 68h,0Bh (set) at FE272,
//     FEB96 and FEC6A, OUT 68h,0Ah (clear) at FE267, FEC12 and FECA1, and
//     the CRT-init table walker at FE8B8-FE8E9 writes table[3] = 0x0A or
//     0x0B picked by bit 3 of the INT 18h mode byte -- the same bit np2's
//     bios0x18_0a maps to gdc.mode1 |= 0x20. The ITF does the same dance
//     around its CG-window test (itf.rom file 0751: OUT 68h,0Bh on the way
//     in, file 07D5: OUT 68h,0Ah on the way out).
//
// The core used to hardcode bitac = 8'hFF at both glyph consumers, which
// reads every cell with a nonzero high byte as a kanji half -- run#191 on the
// Pocket drew every letter double-width exactly that way, the high bytes
// holding the ITF VRAM test's 0x55 that a mode-5 machine never looks at.
//
// Reset value 0x98 is np2's gdc_biosreset for a 24 kHz CRT (dipsw1-1 clear):
// bit 5 clear, so a freshly reset machine renders kanji normally.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_gdc_mode1 (
    input  wire        clk,
    input  wire        rst,

    // One cycle per port 0x68 write, with the written byte on `d`.
    input  wire        wr,
    input  wire  [7:0] d,

    output logic [7:0] mode1,
    output wire  [7:0] bitac          // 00 = every cell ANK, FF = high byte decides
);

    // (`bit` is a SystemVerilog type keyword, hence `msk` -- the rowbuf's
    // `cell` lesson over again.)
    wire [2:0] sel = d[3:1];
    wire [7:0] msk = 8'h01 << sel;

    always_ff @(posedge clk, posedge rst) begin
        if (rst)
            mode1 <= 8'h98;
        else if (wr && (d & 8'hF0) == 8'h00) begin
            if (d[0]) mode1 <= mode1 | msk;
            else      mode1 <= mode1 & ~msk;
        end
    end

    assign bitac = mode1[5] ? 8'h00 : 8'hFF;

endmodule

`default_nettype wire
