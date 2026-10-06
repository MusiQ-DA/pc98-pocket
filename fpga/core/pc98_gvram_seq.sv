//
// pc98_gvram_seq -- one CPU access to graphics VRAM, several to memory.
//
// The GRCG's arithmetic is pc98_grcg's. This is the part that costs time: a
// single guest write to A8000, B0000, B8000 or E0000 has to reach EVERY
// unmasked plane, and in RMW mode each plane must be READ before it is
// written. One CPU bus cycle becomes up to four memory accesses, or eight.
//
// WHY A SEQUENCER AND NOT A CHANGE TO RAM.sv. RAM.sv is the proven path --
// it is what boots the machine, and its ready handshake was the subject of a
// bug found only today. Wrapping it keeps the expansion out of it: this drives
// RAM.sv's own one-byte interface repeatedly and holds the guest off with
// cpu_ready until the last one lands, which is exactly what RAM.sv already
// does for a single access, one level up.
//
// PASS-THROUGH IS THE DEFAULT. With the GRCG off, or for an address that is
// not a graphics window, the request goes straight out and the answer straight
// back -- one access, no state. A machine that never turns the GRCG on behaves
// as if this module were not here, which is what makes it safe to add before
// anything uses it.
//
// THE THREE SHAPES (np21w mem/memvram.c):
//
//   write, TDW  one write per unmasked plane, of that plane's tile. The byte
//               the guest wrote is discarded.
//   write, RMW  one read and one write per unmasked plane:
//               plane = (plane & ~data) | (data & tile)
//   read        one read per unmasked plane, and the answer is the TCR mask:
//               a bit is 1 where EVERY unmasked plane matches its tile bit.
//
// THE EGC SHAPES (np21w mem/memegc.c, egc_writebyte/egc_readbyte). When the
// EGC is active it supersedes the GRCG's transform, and every access walks
// all four planes regardless of the GRCG's mask -- the EGC's own access
// register gates them:
//
//   write  read every plane (dst for the raster op, and the pattern
//          registers' load when ope 9:8 is 0b10), then write every plane
//          whose access bit is CLEAR: plane = (plane & ~mask) | (data & mask),
//          with data from pc98_egc's datapath.
//   read   read every plane (pushing each byte onto the shift pipeline's
//          queue, and on the last plane running one shift event), and
//          answer with the byte the pipeline produced for the plane fgbg
//          9:8 names, unless ope 0x400 (or 0x2000) asks for a raw byte.
//
// THE ACCESS PAGE (port 0xA6 bit 0, np21w's gdcs.access). Page one of the
// graphics RAM has no guest address -- the real machine rebanks the same
// windows -- so this module readdresses every plane access through
// pc98_gvram_plane1 and raises mem_page1, and RAM.sv banks the byte at
// 0x600000. Plain single-plane accesses take that path too when the page bit
// is set: a plain write with page one selected must NOT land in the page-zero
// window just because no charger is armed.
//
// PLANE E IS NOT WHERE THE OTHERS ARE. B, R and G are 0x8000 apart from
// A8000; E is at E0000, and it only exists in analog mode. Both facts live
// in pc98_sdram_map.svh so this module and RAM.sv cannot disagree about them.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_gvram_seq #(
    // EGC=0 drops the raster engine outright: the machine then answers like
    // a GRCG-only model -- mode2's VOPBIT_EGC bits still latch, but nothing
    // consumes them, ports 0x4A0-0x4AF decode nowhere, and every graphics
    // access is GRCG or plain. The engine stays in the tree (tb_pc98_egc and
    // this module's own bench still build with EGC=1).
    parameter bit EGC = 1
) (
    input  wire        clk,
    input  wire        reset,

    // ---- the guest's access ---------------------------------------------
    input  wire        cpu_gvram,        // the address is a graphics window
    input  wire        cpu_rd,           // level, as the 8288's commands are
    input  wire        cpu_wr,
    input  wire        cpu_word,         // a 16-bit bus cycle (both halves)
    input  wire [19:0] cpu_addr,
    input  wire [7:0]  cpu_wdata,
    input  wire [7:0]  cpu_wdata_hi,     // the odd byte of a word cycle
    output wire [7:0]  cpu_rdata,
    output wire [7:0]  cpu_rdata_hi,     // the odd byte of a word read
    output wire        cpu_ready,

    // ---- the GRCG's registers -------------------------------------------
    input  wire        grcg_active,
    input  wire        grcg_rmw,
    input  wire [3:0]  grcg_mask,        // 1 = skip this plane
    input  wire [7:0]  grcg_tile [0:3],
    input  wire        analog_mode,

    // ---- RAM.sv's one-byte interface ------------------------------------
    output reg  [19:0] mem_addr,
    output reg  [7:0]  mem_wdata,
    output wire        mem_word,         // word burst: pass-through only
    output reg         mem_rd,
    output reg         mem_wr,
    input  wire [7:0]  mem_rdata,
    input  wire [7:0]  mem_rdata_hi,     // the burst's second byte on reads
    input  wire        mem_done,         // RAM.sv's access_complete
    // RAM.sv's access_own: the completing access is the one this strobe is
    // holding for. mem_done alone also pulses when a POSTED write drains --
    // a leg parked in S_RDW behind rd_conflicts sees that pulse, drops
    // mem_rd, and walks on carrying whatever data_bus_out_reg happened to
    // hold (RAM never served the read at all). Every wait below is on
    // leg_done, the qualified edge. Benches whose model memory only ever
    // completes the seq's own access may tie this high.
    input  wire        mem_own,
    // RAM.sv's memory_access_ready, which is NOT access_complete: it is 1
    // whenever no selected access is in flight, which is the semantics the
    // guest's READY has always had. Pass-through must hand that through
    // unchanged or every non-graphics access in the machine changes shape.
    input  wire        mem_ready,

    // ---- the access page (port 0xA6 bit 0) -------------------------------
    // Rebanks every plane window between the two 640x400 pages, np21w's
    // gdcs.access. When set, this module addresses planes through
    // pc98_gvram_plane1 and asserts mem_page1 so RAM.sv banks the byte at
    // 0x600000, past the guest's map and EMS alike.
    input  wire        access_page,
    output reg         mem_page1,

    // ---- the EGC ---------------------------------------------------------
    // Register writes decoded upstream (Peripherals, ports 0x4A0-0x4AF) and
    // forwarded here, where the engine that consumes them lives. egc_active
    // is mode2 bits 3 and 2 together (np21w's VOPBIT_EGC gate, io/gdc.c
    // gdc_o6a: bit 3 arms the EGC-capable G-RCG, bit 2 switches the memory
    // layer onto the EGC path).
    input  wire        egc_active,
    input  wire        egc_wr,
    input  wire  [3:0] egc_rg,
    input  wire  [7:0] egc_d,

    // ---- the softcore's service channel ----------------------------------
    // The firmware GDC engine (firmware/gdc_service.c) reaches guest VRAM
    // one byte at a time through here -- the replacement for the removed
    // sdram_selftest_master, and a better one: a svc WRITE while a charger
    // is armed walks the same planes as a guest write, which is exactly
    // what np21w gdc_pset.c's withtdw/withrmw/withegc mean on hardware
    // (the GDC's accesses go through the one data path into video memory).
    // Level req/ack: the requester holds svc_req until svc_done, which
    // latches svc_rdata for a read.
    input  wire        svc_req,
    input  wire        svc_we,           // 1 = write, 0 = read
    input  wire        svc_raw,          // 1 = bypass the charger (WDAT)
    input  wire [19:0] svc_addr,
    input  wire [7:0]  svc_wdata,
    output reg         svc_done,
    output reg  [7:0]  svc_rdata,

    // ---- JTAG probe byte ------------------------------------------------
    // {req, done, hold} name a wedged service channel; {st, gp} name where
    // the plane walk is parked (a read stuck in S_RDW is RAM not answering;
    // S_DONE forever is the guest's strobe never dropping). Combined with
    // Chipset's dbg_chipset (arbiter hold, RAM FSM) a stall is localised.
    //
    // While the FSM sits IDLE the {st,gp} field carries the last svc-write
    // arm's charger witness instead of the dead state: dbg[4:0] =
    // {svc_raw_wr, egc_here, grcg_active, window, grcg_here}. grcg_here=0
    // there names which term denied the charger -- window, the mode bit,
    // a raw request, or the EGC stealing it -- and every-else-set-but-here
    // means egc_on fired on egc_active (slot 0x32's accel view).
    output wire [7:0]  dbg
);

`include "pc98_sdram_map.svh"

    // Which plane a plain access's own window names: A8000 B, B0000 R,
    // B8000 G, E0000 E. The three 0x8000-apart windows differ in address
    // bits 17:16 minus one; the E window is its own check.
    function automatic logic [1:0] own_plane(input logic [19:0] a);
        if (a[19:15] == 5'b11100)      own_plane = 2'd3;
        else if (a[19:15] == 5'b10101) own_plane = 2'd0;
        else if (a[15])                own_plane = 2'd2;
        else                           own_plane = 2'd1;
    endfunction

    localparam [2:0] S_IDLE = 3'd0,
                     S_RD   = 3'd1,   // read this plane (RMW, or a TCR read)
                     S_RDW  = 3'd2,   // wait for it
                     S_WR   = 3'd3,   // write this plane
                     S_WRW  = 3'd4,   // wait for it
                     S_DONE = 3'd5,
                     S_EVT2 = 3'd6;   // a word read's second lane event

    reg [2:0] st;
    reg [1:0] gp;             // which plane
    reg       is_read;        // this access is a read
    reg       is_word;        // this access is a 16-bit bus cycle
    // A completion that belongs to the leg in flight -- see the mem_own
    // port comment. RAM.sv's access_own already implies access_complete,
    // but keeping mem_done in the term documents (and benches) the contract.
    wire leg_done = mem_done & mem_own;
    reg       half;           // a word access's odd-byte walk
    reg [7:0] tcr;            // the match mask being accumulated
    reg [7:0] rd_hold;        // what the last plane read gave
    reg [7:0] lo_ans;         // a word read's even-byte answer
    reg [7:0] rdata_pass;     // the pass-through answer

    // ------------------------------------------------------------------
    // Who the sequencer is working for right now.
    //
    // The guest wins: a svc request is granted only while the guest is
    // quiet (svc_eval), and once it owns the walk svc_hold keeps cur_addr
    // pinned to its operand even if guest strobes arrive mid-run -- they
    // wait for ready, which the S_DONE arm below gates while svc is in.
    //
    // cur_addr is the word BASE: for a 16-bit guest cycle the odd byte is
    // the second walk, selected by half. op_addr is the byte the current
    // leg actually addresses; op_ext is its EGC byte lane (memegc.c's
    // ext = addr & 1).
    // ------------------------------------------------------------------
    reg        svc_hold;
    reg        svc_we_r;
    reg        svc_raw_r;
    reg [19:0] svc_addr_r;
    reg [7:0]  svc_wdata_r;

    // One quiet cycle after a svc op releases the FSM. A guest strobe the
    // V30 has been holding through the walk would otherwise see mem_ready's
    // idle-high level in the cycle before its own request reaches RAM --
    // a ready for an access nobody started, the same orphan class RAM.sv's
    // parked-write slot covers for the DMA. Blocking that one cycle is
    // invisible to a fresh access: the V30 never samples ready that early
    // in a bus cycle.
    reg        svc_gap;

    // svc_req crosses in from clk_pico: give it one sdram-clock sync stage
    // before the grant so a metastable edge cannot reach the S_IDLE arm and
    // launch a memory access that nobody asked for. The request is a level
    // held until svc_done, so one clock of sync latency is free.
    reg         svc_req_s;
    wire        svc_eval = (st == S_IDLE) & !(cpu_rd | cpu_wr) &
                           svc_req_s & !svc_done & !svc_hold;
    wire        in_svc   = svc_hold | svc_eval;
    wire [19:0] cur_addr = svc_hold ? svc_addr_r
                         : svc_eval ? svc_addr : cpu_addr;
    // legpar is the leg's address parity. A dn-direction EGC word WRITE
    // walks the odd byte first: the pipeline's lane 1 product is the high
    // half (egcsftw_dn*'s sub(EGCADDR_H) runs first), so the leg that needs
    // it has to come first. legpar is assigned once egc_here/egc_dn exist.
    wire        legpar;
    wire [19:0] op_addr  = cur_addr | {19'd0, legpar};
    wire        op_ext   = op_addr[0];
    wire [7:0]  cur_wdata = svc_hold ? svc_wdata_r
                         : legpar ? cpu_wdata_hi : cpu_wdata;

    // A svc READ is the GDC's own bus view: raw memory, the plane its window
    // names, never the TCR mask or the EGC read transform. On hardware the
    // charger sits on the WRITE path (and the CPU's read path): the GDC's
    // drawing engine reads the plane it is about to modify back verbatim.
    // svc_raw_rd turns the walk into a single own-plane read; the write
    // side is untouched, so a svc WRITE still goes through the charger
    // when one is armed.
    wire svc_raw_rd = svc_hold & ~svc_we_r;

    // A svc op marked raw is the drawing engine's own view of video memory
    // on the WRITE side too: np21w io/gdc_sub.c (gdcsub_write) scribbles on
    // `mem[]` directly -- no charger transform, no EGC raster op, no shift
    // input, not even a destination read. Excluding it from the here-flags
    // puts the walk back on the plain own-plane path with cur_wdata, and
    // the arm skips the read phase entirely.
    wire svc_raw_wr = in_svc & (svc_hold ? svc_raw_r : svc_raw)
                    & (svc_hold ? svc_we_r  : svc_we);

    // Claimed: a charger expands it, the page bit banks even a plain one,
    // or the softcore is being served (a svc op always goes through the
    // sequencer so the charger state applies to it too).
    //
    // window rides on pc98_gvram_hits alone, NOT on cpu_gvram: gvram_sel
    // follows the registered CPU address and so arrives (and clears) a
    // cycle later than the address itself. The old `cpu_gvram & hits`
    // expression let the access right after a pass-through window access
    // run its first leg unexpanded -- the stale-select hazard -- and a
    // parked write in RAM.sv could reorder behind it.
    wire window    = pc98_gvram_hits(cur_addr, analog_mode);
    wire egc_arm   = EGC & egc_active;
    // np21w i286c/cpumem.c vacctbl: the EGC rows (0x0a/0x0b/0x0e/0x0f) need
    // the GRCG arm -- operate bit3, modereg[7]. The EGC-enable bit alone
    // (rows 0x02/0x03, and 0x06/0x07 under a stale RMW flag) still answers
    // with plain VRAM; the engine is genuinely blind until the charger is
    // switched in. The service channel is exempt -- io/gdc_pset.c consults
    // VOPBIT_EGC alone, so an svc op runs the EGC whenever it is armed.
    wire egc_on    = egc_arm & (in_svc | grcg_active);
    wire egc_here  = egc_on & window & ~svc_raw_wr;
    // np21w i286c/cpumem.c vacctbl[0x0c/0x0d]: with the GRCG's RMW bit set a
    // guest READ is plain VRAM -- the modify half applies to writes only,
    // and the TCR answer exists only in TDW mode (rows 0x08/0x09). The read
    // still expands for page-1 banking through plain_pg1 below. ~in_svc
    // keeps a guest strobe that is merely WAITING from de-expanding the
    // service channel's own op.
    wire grcg_rd_raw = ~in_svc & cpu_rd & ~cpu_wr & grcg_rmw;
    wire grcg_here = ~egc_on & grcg_active & window & ~svc_raw_wr
                   & ~grcg_rd_raw;
    wire plain_pg1 = ~egc_on & window & access_page
                   & (~grcg_active | grcg_rd_raw);
    wire expand    = in_svc | egc_here | grcg_here | plain_pg1;
    wire [1:0] own = own_plane(cur_addr);

    // Pass-through keeps the CPU's word flag for RAM's two-word burst; an
    // expanded access must always reach memory as byte-wide SDRAM words.
    assign mem_word = cpu_word & ~expand;

    // The EGC engine's registers and datapath live one module down; the load
    // strobes and the plane walk are this FSM's business.
    wire [15:0] egc_access, egc_fgbg, egc_ope, egc_mask, egc_sft;
    wire [15:0] egc_fgc [0:3], egc_bgc [0:3], egc_patreg [0:3], egc_src [0:3];
    wire [7:0]  egc_op_data, egc_op_mask;

    // ---- the shift pipeline's strobes -----------------------------------
    // Reads feed the queue while ope 0x400 is clear (egc_readbyte's shift
    // input); writes push the CPU's byte where egc_opeb would consult the
    // pipeline -- the raster-op mode, or the 0x1000 pattern source in its
    // non-colour banks (EGCOPE_SHIFTB's call sites).
    wire egc_rd_shift = ~egc_ope[10];
    // memegc.c's write-side queue pushes are NOT symmetric by access size:
    // egc_opeb pushes (EGCOPE_SHIFTB) only where ope 12:11 consults the
    // pipeline AND ope 0x400 asks for it; egc_opew pushes on EVERY word
    // write -- the raster bank runs EGCOPE_SHIFTW (0x400-guarded) while the
    // pattern and replicate banks run EGCOPE_SHIFTW2 unconditionally, so a
    // word write always advances the pipeline even when it does not feed
    // the written byte.
    wire egc_wr_shift = is_word
                      ? ((egc_ope[12:11] == 2'b01) ? egc_ope[10] : 1'b1)
                      : (egc_ope[10]
                       & ((egc_ope[12:11] == 2'b01)
                        | ((egc_ope[12:11] == 2'b10)
                         & ~(egc_fgbg[14] ^ egc_fgbg[13]))));
    // The last live plane of an EGC read: plane E takes analog mode.
    wire egc_rd_last  = (gp == 2'd3) | ((gp == 2'd2) & ~analog_mode);
    // sf_push is one strobe per live plane byte landing (each S_RDW); sf_evt
    // runs once per access -- for a byte read on the last plane's byte
    // landing, for a byte write-push on the first plane's read beat (the
    // queue needs the produced byte before any plane's write goes out).
    // A WORD access is one event, not two: np21w's shiftinput_incw/decw
    // push the whole word then run egcsftw_* once, so a write's event fires
    // on the even leg (both bus bytes are live then) and a read's on the
    // odd leg's last plane (both legs' pushes are in the queue by then).
    wire egc_dn      = egc_sft[12];
    wire word_dnwr   = is_word & ~is_read & egc_here & egc_dn;
    assign legpar    = half ^ word_dnwr;
    wire egc_sf_push = egc_here & is_read  & egc_rd_shift
                     & (st == S_RDW) & leg_done & ~svc_raw_rd;
    // The push slot offset splits a word read's two legs into adjacent
    // queue slots; dn walks place the even byte behind the odd (inptr[-1]=L,
    // inptr[0]=H then inptr-=2 -- the pair is H-then-L in queue order).
    wire egc_sf_off  = is_word & (egc_dn ? ~half : half);
    // A word access is TWO events one walk apart, sharing the engine's
    // single lane datapath: the head event does the word's input
    // accounting and lane 1, the tail event runs lane 2. A write's tail
    // fires on the odd leg's first read beat, a read's in S_EVT2 -- the
    // dead cycle the FSM now takes between the last push and the answer.
    wire egc_sf_evt  = egc_here
                     & (is_read
                        ? (egc_rd_shift & (st == S_RDW) & leg_done
                         & egc_rd_last & ~svc_raw_rd & (~is_word | half))
                        : (egc_wr_shift & (st == S_RD) & (gp == 2'd0)
                         & (~is_word | ~half)));
    wire egc_sf_evt2 = egc_here & is_word
                     & (is_read
                        ? (egc_rd_shift & (st == S_EVT2) & ~svc_raw_rd)
                        : (egc_wr_shift & (st == S_RD) & (gp == 2'd0)
                         & half));

    generate
    if (EGC) begin : g_egc
        pc98_egc u_egc (
            .clk(clk), .rst(reset),
            // np21w egc_o4a0/egc_w16 drop register writes while the engine
            // is off -- the first line is `if (!VOPBIT_EGC) return`. Gate
            // the strobe the same way so pre-arm pokes cannot leave state.
            .wr(egc_wr & egc_active), .rg(egc_rg), .d(egc_d),
            .access_r(egc_access), .fgbg_r(egc_fgbg), .ope_r(egc_ope),
            .mask_r(egc_mask), .sft_r(egc_sft), .leng_r(),
            .fgc(egc_fgc), .bgc(egc_bgc),
            .pat_ld(egc_pat_ld), .pat_plane(gp),
            .pat_ext(op_ext), .pat_d(mem_rdata), .patreg(egc_patreg),
            .src_q(egc_src),
            .sf_push(egc_sf_push), .sf_push_plane(gp), .sf_push_d(mem_rdata),
            .sf_evt(egc_sf_evt | egc_sf_evt2), .sf_evt_tail(egc_sf_evt2),
            .sf_evt_wr(~is_read),
            .sf_evt_d(is_word ? cpu_wdata : cur_wdata),
            .sf_evt_d2(cpu_wdata_hi), .sf_evt_word(is_word),
            .sf_push_off(egc_sf_off),
            .sf_ext(op_ext),
            .op_plane(gp), .op_ext(op_ext), .op_word(is_word),
            .op_dst(rd_hold), .op_val(cur_wdata), .op_data(egc_op_data),
            .op_mask(egc_op_mask)
        );
    end else begin : g_no_egc
        assign egc_access  = '0;
        assign egc_fgbg    = '0;
        assign egc_ope     = '0;
        assign egc_mask    = '0;
        assign egc_op_data = 8'h00;
        assign egc_op_mask = 8'h00;
        genvar i;
        for (i = 0; i < 4; i++) begin : g_tie
            assign egc_fgc[i]    = '0;
            assign egc_bgc[i]    = '0;
            assign egc_patreg[i] = '0;
            assign egc_src[i]    = '0;
        end
    end
    endgenerate

    // Which plane an EGC read answers with, and the byte it gave.
    wire [1:0] egc_rd_plane = egc_fgbg[9:8];
    reg  [7:0] egc_rd_q, egc_own_q;
    // The pattern registers load on a read when ope 9:8 is 0b01 and on a
    // write when 0b10 (egc_readbyte / egc_writebyte's ope & 0x0300 tests).
    wire egc_pat_on_rd = (egc_ope[9:8] == 2'b01);
    wire egc_pat_on_wr = (egc_ope[9:8] == 2'b10);
    // The load strobe has to fire DURING the byte's landing cycle: RAM.sv
    // drops read_command as mem_rd falls, so the cycle after mem_done its
    // data output is already 0x00 -- a registered strobe saw every pattern
    // register fill with zero. plane/ext are the in-flight leg's values.
    wire egc_pat_ld = egc_here & ~svc_raw_rd
                    & (st == S_RDW) & leg_done
                    & (is_read ? egc_pat_on_rd : egc_pat_on_wr);

    // Plane liveness, split by phase:
    //   read  GRCG: the grcg mask (a TCR read skips masked planes); EGC: all
    //         of them, because the source latch and the pattern load want
    //         every byte; plane E needs analog either way.
    //   write GRCG: the mask; EGC: the access register's bit SET means the
    //         plane is not written, and a zero mask byte has nothing to
    //         write (egc_writebyte's `if`); plain: the window's own plane.
    function automatic logic rd_live_f(input logic [1:0] p);
        if (svc_raw_rd)
            rd_live_f = (p == own);
        else if (egc_here)
            rd_live_f = ((p != 2'd3) | analog_mode);
        else if (grcg_here)
            rd_live_f = ~grcg_mask[p] & ((p != 2'd3) | analog_mode);
        else
            rd_live_f = (p == own);
    endfunction

    // The access register's write gates are bits 3:0, one per plane
    // (np21w mem/memegc.c's `if (!(egc.access & 1))`); the register is
    // 16 bits, so name the nibble instead of widening the plane index.
    wire [3:0] egc_wr_gate = egc_access[3:0];
    function automatic logic wr_live_f(input logic [1:0] p);
        if (egc_here)
            wr_live_f = ((p != 2'd3) | analog_mode)
                       & ~egc_wr_gate[p] & (egc_op_mask != 8'h00);
        else if (grcg_here)
            wr_live_f = ~grcg_mask[p] & ((p != 2'd3) | analog_mode);
        else
            wr_live_f = (p == own);
    endfunction

    // Which planes the CURRENT PHASE touches: the read phase of an EGC write
    // still walks all four (the pattern load and the raster's dst each want
    // every byte); the write phase is where the access register and the mask
    // bite.
    wire       cur_live = (st == S_WR) ? wr_live_f(gp) : rd_live_f(gp);
    wire       last_gp  = (gp == 2'd3);
    wire [7:0] cur_tile = grcg_tile[gp];

    // Where this plane's byte lives, page banked when 0xA6 says so.
    function automatic logic [19:0] plane_addr(input logic [19:0] a,
                                               input logic [1:0] p);
        plane_addr = access_page ? {3'b000, pc98_gvram_plane1(a, p)}
                                 : pc98_gvram_plane(a, p);
    endfunction

    // The transform, per np21w: TDW lays the tile down and discards the
    // guest's byte; RMW uses it as a mask between the tile and what is there;
    // the EGC masks the engine's byte into what is there; a plain access
    // writes the guest's byte unchanged. cur_wdata is the current leg's
    // operand -- the guest's odd byte on a word's second walk, the svc
    // byte under the channel.
    wire [7:0] wr_byte = egc_here
        ? ((rd_hold & ~egc_op_mask) | (egc_op_data & egc_op_mask))
        : grcg_here
            ? (grcg_rmw
                ? ((rd_hold & ~cur_wdata) | (cur_wdata & cur_tile))
                : cur_tile)
        : cur_wdata;

    // Ready lands on the FINAL byte's walk: a word access's first S_DONE
    // only starts the odd half. svc_hold forces expand high, which parks
    // ready low -- a guest access arriving mid-svc-op waits politely.
    // The ~svc_hold matters at S_DONE: without it a guest whose strobe is
    // up when a svc op completes would see this cycle's ready and take
    // rdata_pass -- a stale byte -- for an access that never ran.
    assign cpu_ready = expand ? (st == S_DONE) & (~is_word | half)
                              & ~svc_hold
                              : mem_ready & ~svc_gap;

    // COMBINATIONAL, and it has to be. Assigning it inside the S_DONE arm did
    // not work: by the time S_DONE is the current state the guest has seen
    // cpu_ready and dropped its strobes, `expand` is false, and the arm never
    // runs. The guest samples while its own command is still up, which is
    // exactly when this mux is valid.
    // The EGC read's answer, egc_readbyte's tail: the shift pipeline's
    // produced byte when ope 0x2000 is clear and the read fed the queue;
    // the raw plane byte when 0x400 pushed from the write side instead;
    // and the window's own byte when 0x2000 asks for it raw.
    wire [7:0] egc_src_b = op_ext ? egc_src[egc_rd_plane][15:8]
                                : egc_src[egc_rd_plane][7:0];
    wire [7:0] ans_byte = svc_raw_rd ? rd_hold
                        : egc_here ? (egc_ope[13] ? egc_own_q
                                     : egc_ope[10] ? egc_rd_q
                                     : egc_src_b)
                        : grcg_here ? ~tcr : rd_hold;
    // fin_read: the cycle the guest can take an expanded read's answer. For
    // a word read that is the SECOND walk's S_DONE -- the even byte went
    // into lo_ans at the half boundary, the odd byte is live here.
    // One exception: an EGC word read's shift event runs on the ODD leg
    // (S_EVT2), so the even byte's answer only exists post-shift -- the
    // S_DONE-time re-latch of lo_ans lands a cycle after the guest already
    // sampled it. Drive that lane combinationally instead, exactly the
    // condition the re-latch below covers.
    wire egc_lo_post = is_read & egc_here & ~svc_raw_rd
                     & ~egc_ope[13] & ~egc_ope[10];
    wire fin_read = expand & is_read & (st == S_DONE) & (~is_word | half);
    assign cpu_rdata    = fin_read
                          ? (is_word ? (egc_lo_post ? egc_src[egc_rd_plane][7:0]
                                                    : lo_ans)
                                     : ans_byte)
                          : rdata_pass;
    assign cpu_rdata_hi = fin_read ? ans_byte : mem_rdata_hi;

    always_ff @(posedge clk) begin
        if (reset) begin
            st        <= S_IDLE;
            gp        <= 2'd0;
            is_read   <= 1'b0;
            is_word   <= 1'b0;
            half      <= 1'b0;
            lo_ans    <= 8'h00;
            tcr       <= 8'h00;
            rd_hold   <= 8'h00;
            rdata_pass<= 8'h00;
            egc_rd_q  <= 8'h00;
            egc_own_q <= 8'h00;
            mem_addr  <= 20'h0;
            mem_wdata <= 8'h00;
            mem_rd    <= 1'b0;
            mem_wr    <= 1'b0;
            mem_page1 <= 1'b0;
            svc_hold  <= 1'b0;
            svc_we_r  <= 1'b0;
            svc_addr_r<= 20'h0;
            svc_wdata_r<= 8'h00;
            svc_done  <= 1'b0;
            svc_rdata <= 8'h00;
            svc_gap   <= 1'b0;
            svc_req_s <= 1'b0;
            dbg_arm   <= 5'h00;
        end else begin
            // The EGC's pattern-load strobe is combinational now (see the
            // egc_pat_ld wire): it must fire while mem_rdata still carries
            // the landing byte, because RAM.sv's data output goes to 0x00
            // the cycle after mem_done.
            // The service channel's done is a level: it drops when the
            // requester does (one clock after, through the sync stage).
            svc_req_s <= svc_req;
            if (!svc_req_s) svc_done <= 1'b0;
            // One cycle of guest-ready cover after a svc op hands the FSM
            // back -- see the declaration.
            svc_gap <= (st == S_DONE) & svc_hold;

            if (!expand) begin
                // Pass-through: the guest's own access, unchanged.
                mem_addr  <= cpu_addr;
                mem_wdata <= cpu_wdata;
                mem_rd    <= cpu_rd;
                mem_wr    <= cpu_wr;
                mem_page1 <= 1'b0;
                // ONLY WHILE A READ IS LIVE. Assigning this unconditionally
                // clobbered a TCR answer the moment the guest's strobes dropped
                // and `expand` went false -- the answer has to survive until the
                // guest has taken it, and the guest takes it while its own read
                // command is still up.
                if (cpu_rd) rdata_pass <= mem_rdata;
                st        <= S_IDLE;
                gp        <= 2'd0;
            end else begin
            case (st)
              S_IDLE: begin
                mem_rd <= 1'b0;
                mem_wr <= 1'b0;
                if (cpu_rd | cpu_wr) begin
                    is_read <= cpu_rd;
                    is_word <= cpu_word;
                    half    <= 1'b0;
                    // A plain page-one access walks exactly one plane: the
                    // one its window names, and no other.
                    gp      <= plain_pg1 ? own : 2'd0;
                    // A TCR read starts from all-match and clears bits; a
                    // write starts by reading only if RMW needs it. The EGC
                    // always reads first -- the raster op needs dst, and the
                    // pattern registers may be loading.
                    tcr     <= 8'h00;
                    st      <= (cpu_rd | grcg_rmw | egc_here) ? S_RD : S_WR;
                end else if (svc_req_s && !svc_done) begin
                    // The softcore's byte op: same walk, through the same
                    // charger. A svc write under TDW lays the tiles; under
                    // RMW the read-modify-write runs; under the EGC the
                    // raster op does. This is what makes firmware-served
                    // WDAT/drawing land on real VRAM the way hardware does.
                    svc_hold   <= 1'b1;
                    svc_we_r   <= svc_we;
                    svc_raw_r  <= svc_raw;
                    svc_addr_r <= svc_addr;
                    svc_wdata_r<= svc_wdata;
                    is_read    <= ~svc_we;
                    is_word    <= 1'b0;
                    half       <= 1'b0;
                    tcr        <= 8'h00;
                    if (svc_we) begin
                        // The terms grcg_here is built from, at the moment
                        // the arm evaluated them -- the slot's arm nibble.
                        dbg_arm <= {svc_raw_wr, egc_here, grcg_active,
                                    window, grcg_here};
                    end
                    if (window) begin
                        // cur_addr is already svc_addr this cycle (svc_eval):
                        // window/here/own above are the svc operand's. A svc
                        // READ walks only the plane its window names -- the
                        // GDC's own bus view, no charger on reads. A RAW
                        // write (WDAT) skips the read phase as well:
                        // gdcsub_write computes the result in firmware and
                        // scribbles it back verbatim.
                        gp <= (svc_we & (egc_here | grcg_here)) ? 2'd0 : own;
                        st <= (~svc_we | ((grcg_rmw & ~svc_raw_wr) | egc_here))
                            ? S_RD : S_WR;
                    end else begin
                        // Outside the windows there is nothing to walk and
                        // nothing to transform: ack without a RAM access.
                        svc_rdata <= 8'hFF;
                        svc_done  <= 1'b1;
                        svc_hold  <= 1'b0;
                    end
                end
              end

              // ---- read this plane ------------------------------------
              S_RD: begin
                if (!cur_live) begin
                    // Masked, or plane E in digital mode: nothing to read and
                    // nothing to contribute to the match.
                    if (last_gp) st <= S_DONE;
                    else begin gp <= gp + 2'd1; st <= S_RD; end
                end else begin
                    mem_addr  <= plane_addr(op_addr, gp);
                    mem_page1 <= access_page;
                    mem_rd    <= 1'b1;
                    st        <= S_RDW;
                end
              end

              S_RDW: if (leg_done) begin
                mem_rd  <= 1'b0;
                rd_hold <= mem_rdata;
                if (egc_here && !svc_raw_rd) begin
                    // Each plane byte that lands goes into the shift
                    // pipeline's queue (egc_sf_push is combinational over
                    // this same cycle); the pattern registers take them when
                    // ope asks, on either direction -- egc_pat_ld is
                    // combinational for exactly this cycle too.
                    if (is_read & (gp == egc_rd_plane))
                        egc_rd_q <= mem_rdata;
                    if (is_read & (gp == own))
                        egc_own_q <= mem_rdata;
                end else if (is_read) begin
                    // A GRCG read accumulates the match mask.
                    tcr <= tcr | (mem_rdata ^ cur_tile);
                end
                if (is_read) begin
                    if (is_word & half & egc_here & egc_rd_shift
                      & ~svc_raw_rd & egc_rd_last)
                        st <= S_EVT2;
                    else if (last_gp) st <= S_DONE;
                    else begin gp <= gp + 2'd1; st <= S_RD; end
                end else
                    st <= S_WR;
              end

              // ---- a word read's second lane ----------------------------
              // The head event ran on the last plane's byte landing; the
              // queue shifted under it. One dead cycle lets the tail event
              // produce lane 2 before S_DONE assembles the answer.
              S_EVT2: st <= S_DONE;

              // ---- write this plane -----------------------------------
              S_WR: begin
                if (!cur_live) begin
                    if (last_gp) st <= S_DONE;
                    else begin
                        gp <= gp + 2'd1;
                        st <= grcg_rmw | egc_here ? S_RD : S_WR;
                    end
                end else begin
                    mem_addr  <= plane_addr(op_addr, gp);
                    mem_page1 <= access_page;
                    mem_wdata <= wr_byte;
                    mem_wr    <= 1'b1;
                    st        <= S_WRW;
                end
              end

              // mem_ready, not mem_done: RAM.sv's posted-write release means
              // "the operands are durably covered" -- parked in a queue slot,
              // accepted into the FSM, or matching the write completing now
              // (same address and data, which makes this leg's byte land
              // identically). The parked FIFO keeps the plane order and
              // rd_conflicts holds a conflicting read behind the drain, so a
              // write leg is free to retire at coverage -- the drain runs in
              // the background while the next leg walks in. Reads still wait
              // for leg_done: their data is not back until COMPLETE_RAM_RW,
              // and a parked drain's pulse is not theirs (mem_own).
              S_WRW: if (leg_done | mem_ready) begin
                mem_wr <= 1'b0;
                if (last_gp) st <= S_DONE;
                else begin
                    gp <= gp + 2'd1;
                    st <= grcg_rmw | egc_here ? S_RD : S_WR;
                end
              end

              // ---- the answer -----------------------------------------
              S_DONE: begin
                // The answer itself is the mux above -- TCR returns the
                // INVERSE, a bit set where every unmasked plane matched, and
                // with every plane masked nothing differs and it is 0xFF,
                // which is np21w's behaviour too.
                if (svc_hold) begin
                    // The byte op is complete; ack the requester with the
                    // answer (a write's svc_rdata is don't-care).
                    svc_rdata <= ans_byte;
                    svc_done  <= 1'b1;
                    svc_hold  <= 1'b0;
                    st        <= S_IDLE;
                end else if (is_word & ~half) begin
                    // A word access: the even byte's walk is done -- run it
                    // all again for the odd byte. Ready stays low until the
                    // second walk reaches S_DONE (cpu_ready above).
                    lo_ans <= ans_byte;
                    half   <= 1'b1;
                    gp     <= plain_pg1 ? own : 2'd0;
                    tcr    <= 8'h00;
                    st     <= (is_read | grcg_rmw | egc_here) ? S_RD : S_WR;
                end else if (is_word & half & is_read & egc_here
                           & ~svc_raw_rd & ~egc_ope[13] & ~egc_ope[10]) begin
                    // An EGC word READ runs its shift event on the odd
                    // leg's last plane (both pushed bytes must be queued
                    // before egcsftw_* sees them), so the even leg's answer
                    // -- latched above before the event existed -- is the
                    // produced low lane NOW.
                    lo_ans <= egc_src[egc_rd_plane][7:0];
                    if (!(cpu_rd | cpu_wr)) st <= S_IDLE;
                end else if (!(cpu_rd | cpu_wr)) st <= S_IDLE;
              end

              default: st <= S_IDLE;
            endcase
            end
        end
    end

    // {requester up, answered, in flight, FSM, plane}. svc_req is an input
    // here because "the softcore raised it and nobody moved" is itself the
    // diagnostic. While st is IDLE the {st,gp} field carries dbg_arm -- the
    // last svc-write arm's here-terms, see the port comment -- because an
    // idle FSM has no plane position worth reporting.
    reg [4:0] dbg_arm;
    assign dbg = {svc_req, svc_done, svc_hold,
                  (st == S_IDLE) ? dbg_arm : {st, gp}};

    // cpu_gvram was the window qualifier until `window` moved onto the
    // address alone (see above); it stays on the port list because Chipset
    // still produces it and a future build may want the select again.
    wire _unused = &{1'b0, cpu_gvram, 1'b0};

endmodule

`default_nettype wire
