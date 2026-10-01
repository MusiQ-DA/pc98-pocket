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
// THE REFERENCE IS np21w, AND ITS TWO FILES SPLIT THE SAME WAY THIS TREE
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
//     0x4A8  mask     the write mask, sixteen bits. np21w only accepts this
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
// minterms of those inputs. np21w implements a handful of the entries with
// dedicated two-input forms (ope_nd drops dst, ope_np drops pat, ope_00/0f/
// c0/f0/fc/ff are constants and single terms) and every other code through
// the general three-input form. The table here reproduces that mapping as a
// three-bit kind per code, and one combinational datapath covers all of it.
//
// THE SOURCE LATCH (egc_src) IS THE BLIT. The EGC's fastest trick is
// REP MOVSW through VRAM: every read shifts source bits in, every write
// consumes them, and the sft register's two bit-fields pick up the
// misalignment between source and destination. The full pipeline is
// memegc.c's byte queue (buf/inptr/outptr, egcshift and the egcsftb family),
// and it IS here: serialised to the sequencer's one-plane-at-a-time walk.
// Each guest access is one queue event -- sf_push fills a slot per plane as
// its byte lands, then sf_evt runs the state machine once: input accounting
// (shiftinput_byte), the mask bookkeeping (the bytemask tables as shifts),
// one produced byte per plane into src_q, and the pop. sft's srcbit/dstbit
// fields are four bits each so a run can start mid-byte on either side; the
// >= 8 halves skip whole bytes the way the x86 asm (the authoritative np21w
// reference -- the C port's unsigned guard masks dstbit>8 forever) does it.
// leng is the run's bit count: remain hits zero and the whole pipeline
// re-arms from sft/leng, which is how a 2-D blit restarts each line.
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

    // The source latch -- egc_src in np21w: per plane, the byte the shift
    // pipeline produced for each address parity. Written by the event below,
    // consumed by the raster ops and by shifted reads.
    output logic [15:0] src_q [0:3],

    // ---- the shift pipeline (memegc.c's buf/inptr/outptr + egcsftb) -----
    // sf_push: a plane's byte arrived for the queue (sequencer's read beat).
    // sf_evt: run one byte-position event. evt_wr set = the queued byte is
    // the CPU's write data (ope 0x400 pushes from the write side); ext is
    // the access's address parity, which picks the srcmask/src_q half.
    input  wire         sf_push,
    input  wire  [1:0]  sf_push_plane,
    input  wire  [7:0]  sf_push_d,
    input  wire         sf_evt,
    input  wire         sf_evt_wr,
    input  wire  [7:0]  sf_evt_d,
    input  wire  [7:0]  sf_evt_d2,   // a word write's odd byte (cpu_wdata_hi)
    input  wire         sf_evt_word, // this event is a whole 16-bit access
    input  wire         sf_evt_tail, // second lane of the word pair
    input  wire         sf_push_off, // read byte lands one slot past the tail
    input  wire         sf_ext,

    // ---- the write datapath, one plane and one byte at a time -----------
    //
    // egc_opeb for a single plane/ext: what the sequencer should WRITE,
    // before the mask and the access gate are applied (it applies those
    // itself, because they decide WHICH planes it talks to memory about).
    // dst is what the sequencer just read from this plane; val is the CPU's
    // byte. op_mask is mask2's byte for op_ext -- the mask register's half,
    // and-ed with srcmask where the op's mode calls for the shift mask.
    input  wire  [1:0]  op_plane,
    input  wire         op_ext,
    input  wire  [7:0]  op_dst,
    input  wire  [7:0]  op_val,
    output wire  [7:0]  op_data,
    output wire  [7:0]  op_mask
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

    // ------------------------------------------------------------------
    // the shift pipeline's state (memegc.c's egc.func/srcbit/dstbit/stack/
    // remain/srcmask/inptr/outptr, the queue itself per plane)
    // ------------------------------------------------------------------
    // np21w keeps one byte queue per plane, stride four inside egc.buf:
    // outptr[4p] is the next byte to consume, outptr[4p+1] the one after.
    // inptr and outptr never sit further apart than four bytes -- stack is
    // charged to at most 16+8 bits before pushes stall -- so five slots per
    // plane cover every reachable depth; sf_qd is the shared count.
    logic [2:0]  sf_func;                   // 0/1 aligned, 2/3 and 4/5 funnel
    logic [3:0]  sf_srcbit, sf_dstbit;
    logic [3:0]  sf_shl, sf_shr;            // sft8bitl / sft8bitr
    logic [5:0]  sf_stack;
    logic [12:0] sf_remain;
    logic [15:0] sf_srcmask;
    logic [2:0]  sf_qd;
    logic [7:0]  sf_q [0:3][0:6];           // seven: word push + pop window
    logic        sf_wpend;                  // a word's second lane still owed

    // A byte written to sft or leng re-arms everything (io/egc.c calls
    // egcshift on all four ports); the register byte itself is still on the
    // write data bus, so the merge is done on the incoming value.
    wire        sf_arm  = wr & rg[3] & rg[2];        // 0x4AC .. 0x4AF
    wire [15:0] sft_n   = (wr & (rg == 4'hC)) ? {sft_r[15:8], d}
                      : (wr & (rg == 4'hD)) ? {d, sft_r[7:0]} : sft_r;
    wire [15:0] leng_n  = (wr & (rg == 4'hE)) ? {leng_r[15:8], d}
                      : (wr & (rg == 4'hF)) ? {d, leng_r[7:0]} : leng_r;
    wire [3:0]  arm_s8  = {1'b0, sft_n[2:0]};
    wire [3:0]  arm_d8  = {1'b0, sft_n[6:4]};
    wire [2:0]  arm_func = {2'b00, sft_n[12]}
                         + ((arm_s8 < arm_d8) ? 3'd2 : 3'd0)
                         + ((arm_s8 > arm_d8) ? 3'd4 : 3'd0);
    wire [3:0]  arm_r   = (arm_s8 < arm_d8) ? (arm_d8 - arm_s8)
                        : (arm_s8 > arm_d8) ? (4'd8 - (arm_s8 - arm_d8))
                                          : 4'd0;
    wire [3:0]  arm_l   = (arm_s8 < arm_d8) ? (4'd8 - (arm_d8 - arm_s8))
                        : (arm_s8 > arm_d8) ? (arm_s8 - arm_d8)
                                          : 4'd0;

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
            sf_srcmask <= 16'hFFFF;
            sf_func    <= 3'd0;
            sf_srcbit  <= 4'd0;
            sf_dstbit  <= 4'd0;
            sf_shl     <= 4'd0;
            sf_shr     <= 4'd0;
            sf_stack   <= 6'd0;
            sf_qd      <= 3'd0;
            sf_wpend   <= 1'b0;
            sf_remain  <= 13'd16;          // leng resets to 0x000F
            for (int k = 0; k < 4; k++)
                for (int i = 0; i < 7; i++)
                    sf_q[k][i] <= 8'h00;
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
                    4'h7: ;                        // 0x4A7: np21w drops it
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

            // ---- the shift pipeline ------------------------------------
            // One plane byte landed for the queue: it goes to the shared
            // tail slot of that plane's half of buf. sf_push_off puts the
            // second byte of a word push one slot further (and a dn word's
            // even byte behind its odd one -- the decw layout in np21w
            // places the pair L-behind-H since the buffer fills downward).
            if (sf_push)
                sf_q[sf_push_plane][sf_qd + {2'b00, sf_push_off}] <= sf_push_d;

            // One access event. The combinational block below did the
            // arithmetic; here it all commits at once. A word event can
            // produce BOTH source-latch lanes and pop up to three queue
            // bytes (the srcbit>=8 pre-pop plus one per lane sub).
            if (sf_evt) begin
                if (ev_prod) begin
                    for (int p = 0; p < 4; p++)
                        if (ev_ext) src_q[p][15:8] <= ev_out[p];
                        else        src_q[p][7:0]  <= ev_out[p];
                end
                // outptr moved: the window slides left by the pop count,
                // the tail slots keep what was pushed (pv merged them).
                // With no pops the merged pushes still land via pv.
                for (int p = 0; p < 4; p++)
                    for (int i = 0; i < 7; i++)
                        sf_q[p][i] <= (i + ev_pops > 3'd6) ? pv[p][i]
                                      : pv[p][i + {1'b0, ev_pops}];
                // the mask byte updates on EVERY event, including the run's
                // last -- egcshift() does not touch srcmask, so the final
                // partial-byte mask still reaches the write that consumes it
                sf_srcmask <= nx_srcmask;
                sf_wpend   <= sf_evt_word & ~sf_evt_tail & ev_wpend;
                if (ev_last) begin
                    // remain hit zero: egcshift() re-arms the whole run from
                    // the registers.
                    sf_func   <= arm_func;
                    sf_srcbit <= sft_n[3:0];
                    sf_dstbit <= sft_n[7:4];
                    sf_shl    <= arm_l;
                    sf_shr    <= arm_r;
                    sf_stack  <= 6'd0;
                    sf_qd     <= 3'd0;
                    sf_remain <= {1'b0, leng_n[11:0]} + 13'd1;
                end else begin
                    sf_stack   <= nx_stack;
                    sf_remain  <= nx_remain;
                    sf_srcbit  <= nx_srcbit;
                    sf_dstbit  <= nx_dstbit;
                    sf_qd      <= nx_qd;
                end
            end

            // A byte written to sft or leng re-arms the pipeline itself:
            // io/egc.c calls egcshift() from every port 0x4AC-0x4AF write and
            // then sets srcmask to all-ones.
            if (sf_arm) begin
                sf_srcmask <= 16'hFFFF;
                sf_wpend   <= 1'b0;
                sf_func    <= arm_func;
                sf_srcbit  <= sft_n[3:0];
                sf_dstbit  <= sft_n[7:4];
                sf_shl     <= arm_l;
                sf_shr     <= arm_r;
                sf_stack   <= 6'd0;
                sf_qd      <= 3'd0;
                sf_remain  <= {1'b0, leng_n[11:0]} + 13'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // the shift event, combinationally (memegc.c's shiftinput_byte /
    // shiftinput_incw/decw feeding egcsftb_*_sub, with the x86 asm's
    // word-wide srcmask clear on the suppressed paths)
    // ------------------------------------------------------------------
    // pv[p][i] is plane p's queue AFTER this event's pushes. A word access
    // is TWO events sharing the one lane datapath: the head event does the
    // word's input accounting (both push credits, the srcbit>=8 pre-pop,
    // the 16-dstbit stack check) and runs lane 1; the tail event runs
    // lane 2 a clock later on the post-commit queue head.
    logic [7:0]  pv [0:3][0:6];
    logic [7:0]  ev_out [0:3];
    logic        ev_prod, ev_insub, ev_last, ev_ext, ev_wpend;
    logic [1:0]  ev_pops;
    logic [5:0]  nx_stack;
    logic [12:0] nx_remain;
    logic [3:0]  nx_srcbit, nx_dstbit;
    logic [15:0] nx_srcmask;
    logic [2:0]  nx_qd;
    // block temps, module scope: Quartus rejects automatic declarations
    // inside always blocks (the rtc notes the same)
    logic        v_acc, v_prepop, v_first;
    logic [7:0]  v_mask;
    logic        w_dn;
    // the shared _sub's call site: the event front-end fills these, the
    // lane body below reads them once.
    logic        sub_en, sub_ext, sub_pop;
    logic [7:0]  sub_t0 [0:3], sub_t1 [0:3];

    always_comb begin
        w_dn = sf_func[0];
        for (int p = 0; p < 4; p++) begin
            for (int i = 0; i < 7; i++)
                pv[p][i] = sf_q[p][i];
            if (sf_evt & sf_evt_wr & sf_evt_word & ~sf_evt_tail) begin
                // word write push: up queues {L,H}, dn queues {H,L}
                pv[p][sf_qd]        = w_dn ? sf_evt_d2 : sf_evt_d;
                pv[p][sf_qd + 3'd1] = w_dn ? sf_evt_d  : sf_evt_d2;
            end else if (sf_evt & sf_evt_wr & ~sf_evt_word) begin
                pv[p][sf_qd] = sf_evt_d;
            end else if (sf_push & (sf_push_plane == 2'(p))) begin
                pv[p][sf_qd + {2'b00, sf_push_off}] = sf_push_d;
            end
        end

        v_acc = 1'b0; v_prepop = 1'b0; v_first = 1'b0; v_mask = 8'hFF;
        nx_stack   = sf_stack;  nx_remain  = sf_remain;
        nx_srcbit  = sf_srcbit; nx_dstbit  = sf_dstbit;
        nx_srcmask = sf_srcmask; nx_qd     = sf_qd;
        ev_prod = 1'b0; ev_insub = 1'b0; ev_last = 1'b0; ev_wpend = 1'b0;
        ev_pops = 2'd0; ev_ext = sf_ext;
        sub_en = 1'b0; sub_ext = 1'b0; sub_pop = 1'b0;
        for (int p = 0; p < 4; p++) begin
            ev_out[p] = 8'h00;
            sub_t0[p] = pv[p][0];
            sub_t1[p] = pv[p][1];
        end

        // ---- front-ends: input accounting, the stack guard, the mask
        // preset, and the shared sub's tap/ext select -------------------
        if (sf_evt & ~sf_evt_word) begin
            // shiftinput_byte: the new byte sits at the tail (pv); it earns
            // stack credit only while stack <= 16. A srcbit >= 8 spends one
            // push as a whole byte with no credit.
            if (sf_stack <= 6'd16) begin
                v_acc = 1'b1;
                if (sf_srcbit >= 4'd8) nx_srcbit = sf_srcbit - 4'd8;
                else begin
                    nx_stack  = sf_stack + (6'd8 - {2'b00, sf_srcbit});
                    nx_srcbit = 4'd0;
                end
            end

            // egcsft_byte: the fresh mask byte first, then the guards, in
            // the asm's order.
            if (sf_ext) nx_srcmask[15:8] = 8'hFF;
            else        nx_srcmask[7:0]  = 8'hFF;
            if (nx_dstbit > 4'd8) begin
                // dstbit 9..15 skips one whole destination byte per event.
                nx_dstbit  = nx_dstbit - 4'd8;
                nx_srcmask = 16'h0000;
            end else if (nx_stack < (6'd8 - {2'b00, nx_dstbit})) begin
                // the input for this position has not arrived yet
                nx_srcmask = 16'h0000;
            end else begin
                nx_stack = nx_stack - (6'd8 - {2'b00, nx_dstbit});
                ev_insub = 1'b1;
                sub_en   = 1'b1;
                sub_ext  = sf_ext;
            end
        end else if (sf_evt & ~sf_evt_tail) begin
            // ---- shiftinput_incw/decw, head: the whole word's input side
            // plus lane 1. np21w's incw grants a two-byte credit, spends a
            // fully-consumed head byte on srcbit>=8 (the pre-pop), then the
            // egcsftw_* wrapper checks 16-dstbit once for the pair.
            ev_ext = w_dn;   // up: lane 1 is the low byte; dn: the high
            if (sf_stack <= 6'd16) begin
                v_acc    = 1'b1;
                v_prepop = (sf_srcbit >= 4'd8);
                nx_stack = sf_stack + (6'd16 - {2'b00, sf_srcbit});
                nx_srcbit = 4'd0;
            end
            // the sub reads through the pre-pop: its two taps slide down
            // one slot when a head byte was spent.
            for (int p = 0; p < 4; p++) begin
                sub_t0[p] = pv[p][{2'b00, v_prepop}];
                sub_t1[p] = pv[p][{2'b00, v_prepop} + 3'd1];
            end
            nx_srcmask = 16'hFFFF;
            if (nx_stack < (6'd16 - {2'b00, nx_dstbit})) begin
                nx_srcmask = 16'h0000;
            end else begin
                nx_stack = nx_stack - (6'd16 - {2'b00, nx_dstbit});
                ev_insub = 1'b1;
                sub_en   = 1'b1;
                sub_ext  = w_dn;
            end
        end else if (sf_evt) begin
            // ---- the tail event: lane 2, on the queue the head commit
            // left behind. Only runs while the run still has bits.
            ev_ext   = ~w_dn;
            sub_en   = sf_wpend;
            sub_ext  = ~w_dn;
            ev_insub = sf_wpend;
        end

        // ---- the shared lane sub (egcsftb_*_sub) -----------------------
        // dstbit >= 8 skips this byte position without producing; the
        // dstbit!=0 forms split the mask between this byte and the next;
        // the aligned case either spends a whole byte or closes the run.
        if (sub_en) begin
            if (nx_dstbit >= 4'd8) begin
                nx_dstbit = nx_dstbit - 4'd8;
                if (sub_ext) nx_srcmask[15:8] = 8'h00;
                else         nx_srcmask[7:0]  = 8'h00;
            end else begin
                if (nx_dstbit != 0) begin
                    v_first = 1'b1;
                    if (({9'd0, nx_dstbit} + nx_remain) >= 13'd8) begin
                        v_mask    = w_dn ? (8'hFF << nx_dstbit[2:0])
                                         : (8'hFF >> nx_dstbit[2:0]);
                        nx_remain = nx_remain - (13'd8 - {9'd0, nx_dstbit});
                    end else begin
                        v_mask    = w_dn
                                  ? ((8'hFF << nx_dstbit[2:0]) &
                                     (8'hFF >> (4'd8 - nx_dstbit
                                              - {1'b0, nx_remain[2:0]})))
                                  : ((8'hFF >> nx_dstbit[2:0]) &
                                     (8'hFF << (4'd8 - nx_dstbit
                                              - {1'b0, nx_remain[2:0]})));
                        nx_remain = 13'd0;
                    end
                    nx_dstbit = 4'd0;
                end else if (nx_remain >= 13'd8) begin
                    nx_remain = nx_remain - 13'd8;
                end else begin
                    v_mask    = w_dn
                              ? (8'hFF >> (4'd8 - {1'b0, nx_remain[2:0]}))
                              : (8'hFF << (4'd8 - {1'b0, nx_remain[2:0]}));
                    nx_remain = 13'd0;
                end
                if (sub_ext) nx_srcmask[15:8] = v_mask;
                else         nx_srcmask[7:0]  = v_mask;
                // one produced byte per plane: the funnel taps are the
                // head byte and the one after it.
                for (int p = 0; p < 4; p++) begin
                    case (sf_func)
                        3'd0, 3'd1:
                            ev_out[p] = sub_t0[p];
                        3'd2:
                            ev_out[p] = v_first ? (sub_t0[p] >> sf_shr)
                                      : ((sub_t0[p] << sf_shl)
                                       | (sub_t1[p] >> sf_shr));
                        3'd3:
                            ev_out[p] = v_first ? (sub_t0[p] << sf_shr)
                                      : ((sub_t0[p] >> sf_shl)
                                       | (sub_t1[p] << sf_shr));
                        3'd4:
                            ev_out[p] = (sub_t0[p] << sf_shl)
                                      | (sub_t1[p] >> sf_shr);
                        default:
                            ev_out[p] = (sub_t0[p] >> sf_shl)
                                      | (sub_t1[p] << sf_shr);
                    endcase
                end
                ev_prod = 1'b1;
                // the aligned and left forms consume the head always; the
                // right forms' first byte is a look, not a pop.
                sub_pop = ~v_first | ((sf_func != 3'd2)
                                    & (sf_func != 3'd3));
            end
        end

        // ---- closes: pops, queue depth, the mid-word suppress, rearm ----
        if (sf_evt & ~sf_evt_word) begin
            ev_pops = {1'b0, sub_pop};
            nx_qd   = sf_qd + {2'b00, v_acc} - {1'b0, ev_pops};
            ev_last = ev_insub & (nx_remain == 13'd0);
        end else if (sf_evt & ~sf_evt_tail) begin
            ev_pops  = {1'b0, v_prepop} + {1'b0, sub_pop};
            ev_wpend = ev_insub & (nx_remain != 13'd0);
            if (ev_insub & ~ev_wpend) begin
                if (~w_dn) nx_srcmask[15:8] = 8'h00;
                else       nx_srcmask[7:0]  = 8'h00;
            end
            nx_qd   = sf_qd + {v_acc, 1'b0} - {1'b0, ev_pops};
            ev_last = ev_insub & ~ev_wpend;
        end else if (sf_evt) begin
            ev_pops = {1'b0, sub_pop};
            nx_qd   = sf_qd - {1'b0, ev_pops};
            ev_last = ev_insub & (nx_remain == 13'd0);
        end
        if (sf_evt) begin
            if (nx_qd == 3'd7)      nx_qd = 3'd0;
            else if (nx_qd > 3'd6)  nx_qd = 3'd6;
        end
    end

    // ------------------------------------------------------------------
    // the write datapath
    // ------------------------------------------------------------------
    // The raster-op table, as np21w's opefn[256] maps it: which of the nine
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
    // (foreground) is 2'b10 -- np21w's switch cases, in bit positions.
    wire [15:0] fgbg_col = (fgbg_r[14:13] == 2'b01) ? bgc[op_plane]
                        : (fgbg_r[14:13] == 2'b10) ? fgc[op_plane]
                        : (fgbg_r[14:13] == 2'b11)
                            ? (op_plane[1] ? bgc[op_plane] : fgc[op_plane])
                        : 16'h0000;
    wire [7:0] patreg_b = op_ext ? patreg[op_plane][15:8]
                                 : patreg[op_plane][7:0];
    wire [7:0] pat_b = (fgbg_r[14:13] == 2'b00)
                     ? ((ope_r[9:8] == 2'b01) ? src_b : patreg_b)
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
    // table; 2'b10 is the pattern -- np21w returns the fg/bg colours only
    // for banks 0x2000/0x4000 and the SOURCE latch for banks 0 and 3
    // (memegc.c's `default:` also runs EGCOPE_SHIFTB, which sf_in_op covers
    // on the mask side). The word model disagrees on the colour banks'
    // little corners; they read the same for aligned runs.
    assign op_data = (ope_r[12:11] == 2'b01) ? opefn_result
                   : (ope_r[12:11] == 2'b10)
                       ? ((fgbg_r[14:13] == 2'b01 || fgbg_r[14:13] == 2'b10)
                                 ? (op_ext ? fgbg_col[15:8] : fgbg_col[7:0])
                                 : src_b)
                   :                                 op_val;

    // mask2's byte for this access's parity. egc_opeb ANDs srcmask in only
    // where the shift pipeline was consulted: the raster-op mode (0x0800)
    // and the non-colour 0x1000 pattern source; the colours and the
    // replicate modes mask with the mask register alone.
    wire       sf_in_op = (ope_r[12:11] == 2'b01)
                        | ((ope_r[12:11] == 2'b10)
                         & ~(fgbg_r[14] ^ fgbg_r[13]));
    wire [7:0] sm_b = op_ext ? sf_srcmask[15:8] : sf_srcmask[7:0];
    assign op_mask = (op_ext ? mask_r[15:8] : mask_r[7:0])
                   & (sf_in_op ? sm_b : 8'hFF);

endmodule

`default_nettype wire
