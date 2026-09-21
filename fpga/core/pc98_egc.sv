//
// pc98_egc -- the Extended Graphic Charger's registers and op datapath.
//
// WHAT THE EGC IS. A second plane-expansion engine that supersedes the GRCG
// when enabled: one CPU write to a graphics window becomes a raster operation
// over all four planes, with the pattern data coming from a foreground or
// background colour, from the four sixteen-bit pattern registers, or from the
// source latch, and every term masked by the mask register and gated per
// plane by the access register. Games drive it directly for sprites, tiles
// and transparent blits; DOS extender-era engines drive it through REP MOVSW,
// which is why the source latch exists (see egc_src, below).
//
// THE REFERENCE IS np2kai, AND ITS TWO FILES SPLIT THE SAME WAY THIS TREE
// DOES: io/egc.c is the register file (the ports), mem/memegc.c is the
// engine (what a write does). Everything below cites one or the other.
//
// THE PORTS (io/egc.c, egc_o4a0 -- byte model; the V30 bus this core runs is
// byte cycles, which is that model exactly):
//
//     0x4A0  access   reset 0xFFF0. bits 3:0 gate a plane's WRITE: a SET bit
//                     means the plane is NOT written (egc_writebyte's
//                     `if (!(egc.access & 1))`). bits 7:4 gate reads the
//                     same way (the TCR expansion).
//     0x4A2  fgbg     reset 0x00FF. bits 13:14 (0x6000) select the pattern
//                     source for a raster op: 0x2000 = background colour,
//                     0x4000 = foreground colour, 0x6000 = fg in the low
//                     dwords and bg in the high ones (ope_nd/ope_np's split),
//                     0 = the pattern registers. bits 9:8 pick the plane a
//                     READ returns. The port also carries the low byte's
//                     colour defaults at reset.
//     0x4A4  ope      the raster op select. bits 11:10 (0x1800) pick the
//                     data source: 0x0000 = the written value itself,
//                     replicated to every plane; 0x0800 = the raster-op
//                     table, indexed by ope 7:0; 0x1000 = the pattern
//                     source outright (fgc/bgc/patreg). bits 9:8 (0x0300)
//                     load the pattern registers from VRAM: 0x0100 on a
//                     read, 0x0200 on a write. bit 0x2000 on a read selects
//                     between the source latch and the raw plane.
//     0x4A6  fg       the foreground COLOUR, four bits; it expands to four
//                     planes of all-ones masks through maskword (io/egc.c
//                     builds egc.fgc exactly this way).
//     0x4A8  mask     the write mask, sixteen bits. np2kai only accepts this
//                     write while the pattern-source field is zero
//                     (`if (!(egc.fgbg & 0x6000))`), and this follows it:
//                     the register file shares silicon with the pattern
//                     pointer on the real chip.
//     0x4AA  bg       the background colour, expanded like fg.
//     0x4AC  sft      the shift control for the source pipeline.
//     0x4AE  leng     the run length for the source pipeline.
//
// THE ENGINE (mem/memegc.c, egc_opeb/opefn): a write's data per plane is
// picked by ope 11:10, and the raster-op table is a 256-entry function table
// over three inputs -- pat (the pattern source), src (the source latch), and
// dst (what is in VRAM now) -- where the ope byte's eight bits are the eight
// minterms of those inputs. np2kai implements a handful of the entries with
// dedicated two-input forms (ope_nd drops dst, ope_np drops pat, ope_00/0f/
// c0/f0/fc/ff are constants and single terms) and every other code through
// the general three-input form. The table here reproduces that mapping as a
// three-bit kind per code, and one combinational datapath covers all of it.
//
// THE SOURCE LATCH (egc_src) IS THE BLIT. The EGC's fastest trick is
// REP MOVSW through VRAM: every read shifts source bits in, every write
// consumes them, and the sft register's two bit-fields pick up the
// misalignment between source and destination. The full pipeline is a
// byte-queue (memegc.c's buf/inptr/outptr machinery, egcshift and the
// egcsftb family) and is NOT here yet; what is here is the aligned case the
// queue degenerates to: a four-by-sixteen-bit latch, loaded by every EGC
// read, consumed by every raster write. Aligned copies work; misaligned ones
// (sft != 0) are stage two and are recorded in SOFTCORE_RTL_SPLIT.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_egc (
    input  wire         clk,
    input  wire         rst,

    // One cycle per byte written to 0x4A0-0x4AF, with the register number in
    // rg (address bits 3:0) -- the house style, as the mode registers take it.
    input  wire         wr,
    input  wire  [3:0]  rg,
    input  wire  [7:0]  d,

    // ---- the engine's view of the registers ---------------------------
    output logic [15:0] access_r,     // 0x4A0
    output logic [15:0] fgbg_r,       // 0x4A2
    output logic [15:0] ope_r,        // 0x4A4
    output logic [15:0] mask_r,       // 0x4A8
    output logic [15:0] sft_r,        // 0x4AC
    output logic [15:0] leng_r,       // 0x4AE

    // The fg/bg colours, expanded to four planes of sixteen-bit masks:
    // maskword[c][p] = c bit p set ? 0xFFFF : 0x0000 (io/egc.c).
    output wire  [15:0] fgc [0:3],
    output wire  [15:0] bgc [0:3],

    // The pattern registers: four planes of sixteen bits, loaded from VRAM
    // by the sequencer when ope 0x100/0x200 says so. ext picks the byte.
    input  wire         pat_ld,       // strobe: a plane byte is on pat_d
    input  wire  [1:0]  pat_plane,
    input  wire         pat_ext,      // 0 = low byte of the word, 1 = high
    input  wire  [7:0]  pat_d,
    output logic [15:0] patreg [0:3],

    // The source latch: loaded on every EGC read of a plane word, consumed
    // by raster writes. Aligned blits only, until the shift pipeline lands.
    input  wire         src_ld,
    input  wire  [1:0]  src_plane,
    input  wire         src_ext,
    input  wire  [7:0]  src_d,
    output logic [15:0] src_q [0:3],

    // ---- the write datapath, one plane and one byte at a time -----------
    //
    // egc_opeb for a single plane/ext: what the sequencer should WRITE,
    // before the mask and the access gate are applied (it applies those
    // itself, because they decide WHICH planes it talks to memory about).
    // dst is what the sequencer just read from this plane; val is the CPU's
    // byte.
    input  wire  [1:0]  op_plane,
    input  wire         op_ext,
    input  wire  [7:0]  op_dst,
    input  wire  [7:0]  op_val,
    output wire  [7:0]  op_data
);

    // maskword: colour bit c, plane p -> all-ones or all-zeros.
    function automatic logic [15:0] maskword(input logic [3:0] c,
                                             input int p);
        maskword = c[p] ? 16'hFFFF : 16'h0000;
    endfunction

    logic [3:0] fg_color, bg_color;

    genvar gp;
    generate
        for (gp = 0; gp < 4; gp = gp + 1) begin : g_exp
            assign fgc[gp] = maskword(fg_color, gp);
            assign bgc[gp] = maskword(bg_color, gp);
        end
    endgenerate

    // Reset values: io/egc.c egc_reset -- access FFF0, fgbg 00FF, mask FFFF,
    // leng 000F; fg 0, bg 0.
    always_ff @(posedge clk) begin
        if (rst) begin
            access_r <= 16'hFFF0;
            fgbg_r   <= 16'h00FF;
            ope_r    <= 16'h0000;
            mask_r   <= 16'hFFFF;
            sft_r    <= 16'h0000;
            leng_r   <= 16'h000F;
            fg_color <= 4'h0;
            bg_color <= 4'h0;
            for (int k = 0; k < 4; k++) begin
                patreg[k] <= 16'h0000;
                src_q[k]  <= 16'h0000;
            end
        end else begin
            // The register write, byte model: the low byte of a register at
            // an even port, the high byte at the odd one above it, exactly
            // egc_o4a0's switch on (port & 0x0f).
            if (wr) begin
                case (rg)
                    4'h0: access_r[7:0]  <= d;    // 0x4A0 low
                    4'h1: access_r[15:8] <= d;    // 0x4A1 high
                    4'h2: fgbg_r[7:0]    <= d;    // 0x4A2
                    4'h3: fgbg_r[15:8]   <= d;
                    4'h4: ope_r[7:0]     <= d;    // 0x4A4
                    4'h5: ope_r[15:8]    <= d;
                    4'h6: fg_color       <= d[3:0]; // 0x4A6: colour, four bits
                    4'h7: ;                        // 0x4A7: np2kai drops it
                    4'h8: if (fgbg_r[14:13] == 2'b00) mask_r[7:0]  <= d;
                    4'h9: if (fgbg_r[14:13] == 2'b00) mask_r[15:8] <= d;
                    4'hA: bg_color       <= d[3:0]; // 0x4AA
                    4'hB: ;
                    4'hC: sft_r[7:0]     <= d;    // 0x4AC
                    4'hD: sft_r[15:8]    <= d;
                    4'hE: leng_r[7:0]    <= d;    // 0x4AE
                    4'hF: leng_r[15:8]   <= d;
                    default: ;
                endcase
            end

            // The pattern registers, loaded from VRAM by the sequencer.
            if (pat_ld) begin
                if (pat_ext) patreg[pat_plane][15:8] <= pat_d;
                else         patreg[pat_plane][7:0]  <= pat_d;
            end

            // The source latch, loaded on every EGC read.
            if (src_ld) begin
                if (src_ext) src_q[src_plane][15:8] <= src_d;
                else         src_q[src_plane][7:0]  <= src_d;
            end
        end
    end

    wire _unused = &{1'b0, 1'b0};

    // ------------------------------------------------------------------
    // the write datapath
    // ------------------------------------------------------------------
    // The raster-op table, as np2kai's opefn[256] maps it: which of the nine
    // forms a code takes. Everything not listed is the general three-input
    // form (ope_xx).
    localparam [3:0] K_Z = 4'd0,   // 0x00: all zeros
                     K_NS = 4'd1,  // 0x0F: ~src
                     K_SD = 4'd2,  // 0xC0: src & dst
                     K_S  = 4'd3,  // 0xF0: src
                     K_SO = 4'd4,  // 0xFC: src | dst
                     K_ONE= 4'd5,  // 0xFF: all ones
                     K_ND = 4'd6,  // pat x src, minterms 7,6,3,2
                     K_NP = 4'd7,  // src x dst, minterms 7,5,3,1
                     K_XX = 4'd8;  // pat x src x dst, all eight

    function automatic logic [3:0] opkind(input logic [7:0] c);
        case (c)
            8'h00: opkind = K_Z;
            8'h0F: opkind = K_NS;
            8'hC0: opkind = K_SD;
            8'hF0: opkind = K_S;
            8'hFC: opkind = K_SO;
            8'hFF: opkind = K_ONE;
            8'h03, 8'h0C, 8'h30, 8'h33, 8'h3C, 8'h3F,
            8'hC3, 8'hCC, 8'hCF, 8'hF3:          opkind = K_NP;
            8'h05, 8'h0A, 8'h50, 8'h55, 8'h5A, 8'h5F,
            8'hA0, 8'hA5, 8'hAA, 8'hAF, 8'hF5, 8'hFA: opkind = K_ND;
            default:                              opkind = K_XX;
        endcase
    endfunction

    // Byte of a word by ext -- a plain indexed select would be ONE BIT, not
// the byte; both slices spelled out, as the mask byte in the sequencer is.
wire [7:0] src_b = op_ext ? src_q[op_plane][15:8] : src_q[op_plane][7:0];

    // The pattern source, as ope_nd/ope_np/ope_xx select it. The bank field
    // is fgbg bits 14:13, so 0x2000 (background) is 2'b01 and 0x4000
    // (foreground) is 2'b10 -- np2kai's switch cases, in bit positions.
    wire [15:0] fgbg_col = (fgbg_r[14:13] == 2'b01) ? bgc[op_plane]
                        : (fgbg_r[14:13] == 2'b10) ? fgc[op_plane]
                        : (fgbg_r[14:13] == 2'b11)
                            ? (op_plane[1] ? bgc[op_plane] : fgc[op_plane])
                        : 16'h0000;
    wire [7:0] patreg_b = op_ext ? patreg[op_plane][15:8]
                                 : patreg[op_plane][7:0];
    wire [7:0] pat_b = (fgbg_r[14:13] == 2'b00)
                     ? (ope_r[8] ? src_b : patreg_b)
                     : (op_ext ? fgbg_col[15:8] : fgbg_col[7:0]);

    // The general three-input form, ope_xx: eight minterms, MSB first --
    // bit7 P·S·D, bit6 ~P·S·D, bit5 P·S·~D, bit4 ~P·S·~D, bit3 P·~S·D,
    // bit2 ~P·~S·D, bit1 P·~S·~D, bit0 ~P·~S·~D.
    wire [7:0] minterms =
          (ope_r[7] ? (pat_b & src_b & op_dst) : 8'h00)
        | (ope_r[6] ? (~pat_b & src_b & op_dst) : 8'h00)
        | (ope_r[5] ? (pat_b & src_b & ~op_dst) : 8'h00)
        | (ope_r[4] ? (~pat_b & src_b & ~op_dst) : 8'h00)
        | (ope_r[3] ? (pat_b & ~src_b & op_dst) : 8'h00)
        | (ope_r[2] ? (~pat_b & ~src_b & op_dst) : 8'h00)
        | (ope_r[1] ? (pat_b & ~src_b & ~op_dst) : 8'h00)
        | (ope_r[0] ? (~pat_b & ~src_b & ~op_dst) : 8'h00);

    wire [7:0] nd_terms =
          (ope_r[7] ? (pat_b & src_b) : 8'h00)
        | (ope_r[6] ? (~pat_b & src_b) : 8'h00)
        | (ope_r[3] ? (pat_b & ~src_b) : 8'h00)
        | (ope_r[2] ? (~pat_b & ~src_b) : 8'h00);

    wire [7:0] np_terms =
          (ope_r[7] ? (src_b & op_dst) : 8'h00)
        | (ope_r[5] ? (src_b & ~op_dst) : 8'h00)
        | (ope_r[3] ? (~src_b & op_dst) : 8'h00)
        | (ope_r[1] ? (~src_b & ~op_dst) : 8'h00);

    wire [3:0] kind = opkind(ope_r[7:0]);
    wire [7:0] opefn_result = (kind == K_Z)  ? 8'h00
                             : (kind == K_NS) ? ~src_b
                             : (kind == K_SD) ? (src_b & op_dst)
                             : (kind == K_S)  ? src_b
                             : (kind == K_SO) ? (src_b | op_dst)
                             : (kind == K_ONE)? ~8'h00
                             : (kind == K_ND) ? nd_terms
                             : (kind == K_NP) ? np_terms
                             :                 minterms;

    // egc_opeb's source select, by ope 11:10. This follows the BYTE model
    // (egc_opeb), because the sequencer below this is a byte engine: 2'b00
    // and 2'b11 fall to the written byte itself; 2'b01 is the raster-op
    // table; 2'b10 is the pattern -- the fg/bg colours by bank, and the
    // SOURCE latch for bank zero, which is where the byte and word models
    // disagree (egc_opew returns patreg there). They read the same for any
    // aligned run, which is every run until the shift pipeline exists.
    assign op_data = (ope_r[12:11] == 2'b01) ? opefn_result
                   : (ope_r[12:11] == 2'b10)
                       ? ((fgbg_r[14:13] == 2'b00) ? src_b
                                 : (op_ext ? fgbg_col[15:8] : fgbg_col[7:0]))
                   :                                 op_val;

endmodule

`default_nettype wire
