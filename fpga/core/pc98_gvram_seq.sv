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
    parameter bit EGC = 1,
    // The RMW plane-line buffer (below). Needs a memory that answers a
    // prefetch_len read with pf_beat_* beats -- RAM.sv does; the benches'
    // behavioural memories do not, and leave it off.
    parameter bit RMWBUF = 0,
    // Posted GRCG RMW writes (see "POSTED GRCG RMW WRITE"); needs RMWBUF's
    // core_top shape, and rmwbuf_off (slot 0x09 [27]) turns it off too.
    parameter bit PWPOST = 0,
    // Write-back RMW line buffer (see "WRITE-BACK"): RMW results stay in
    // the buffer and each dirty plane line leaves as ONE 16-word burst on
    // controller port G. Needs RMWBUF.
    parameter bit WBACK  = 0,
    // Clocks a dirty line may sit with the FSM idle before it is written
    // out anyway (the display reads SDRAM directly).
    parameter int WB_AGE = 64
) (
    input  wire        clk,
    input  wire        reset,

    // ---- the guest's access ---------------------------------------------
    input  wire        cpu_gvram,        // the address is a graphics window
    input  wire        cpu_rd,           // level, as the 8288's commands are
    input  wire        cpu_wr,
    input  wire        cpu_word,         // a 16-bit bus cycle (both halves)
    input  wire [4:0]  cpu_pf_len,       // prefetch burst length on a
                                        // pass-through read -- forwarded
                                        // with mem_rd, never on seq legs
    input  wire [19:0] cpu_addr,
    input  wire [7:0]  cpu_wdata,
    input  wire [7:0]  cpu_wdata_hi,     // the odd byte of a word cycle
    output wire [7:0]  cpu_rdata,
    output wire [7:0]  cpu_rdata_hi,     // the odd byte of a word read
    output wire        cpu_ready,
    // The guest's own write strobe is durably held in RAM -- the witness
    // the posted-write drain waits on before unwinding its bus cycle.
    // RAM's write_taken cannot serve alone: while a svc op or an expanded
    // write owns the walk, ITS mem_wr legs pulse the same line, and a
    // guest strobe parked behind them would read a foreign capture as its
    // own release. expand=0 means mem_wr is the cpu_wr pass-through --
    // the only strobe on the port is the guest's, so write_taken then
    // genuinely names the presented write.
    output wire        cpu_wr_taken,
    // The guest's own READ completion witness -- cpu_ready qualified to
    // the window where the presented strobe can actually be answered.
    // cpu_ready alone cannot serve: mem_rd trails cpu_rd by a clock (the
    // pass-through is registered), and while the port strobe is still
    // absent RAM's memory_access_ready sits on its "nothing in flight"
    // idle level -- one full clk where cpu_ready says a read that has
    // not reached RAM yet is done. A stale processor_ready accept armed
    // on exactly that level is how the +GRANT+svc wedge kept capturing
    // leg residue (the RET-reads-ADAD signature). For a plain read the
    // qualifier waits for mem_rd; for an expanded walk the guest strobe
    // is held while the answer is assembled, so cpu_rd itself is the
    // reach -- its ready is S_DONE, never a port completion.
    output wire        cpu_rd_own,

    // ---- the GRCG's registers -------------------------------------------
    input  wire        grcg_active,
    input  wire        grcg_rmw,
    input  wire [3:0]  grcg_mask,        // 1 = skip this plane
    input  wire [7:0]  grcg_tile [0:3],
    input  wire        analog_mode,

    // ---- RAM.sv's one-byte interface ------------------------------------
    output reg  [19:0] mem_addr,
    output reg  [7:0]  mem_wdata,
    output reg  [7:0]  mem_wdata_hi,
    output wire        mem_word,         // word burst: pass-through, and the
                                      // GRCG word batch below
    output wire [4:0]  mem_pf_len,       // prefetch burst: pass-through only
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
    // RAM.sv's write_taken: the write strobe on the memory pins is durably
    // captured (or can never become a command). See cpu_wr_taken below.
    input  wire        mem_wr_taken,
    // RAM.sv's burst-read beat stream (prefetch_len reads): the RMW line
    // buffer below fills from it.
    input  wire        pf_beat_v,
    input  wire [7:0]  pf_beat_dat,
    // The beat stream is this module's own line-buffer burst: whoever else
    // listens to pf_beat_* (the bridge's prefetch window) must not take
    // these beats as its fill. Under a posted RMW walk the guest runs on
    // and its prefetch fill can be armed while the burst streams.
    output wire        pf_beat_seq,
    // Port G (RAM.sv gvwb_*): the write-back burst. Data by word on wcnt.
    output reg         gvwb_req,
    output reg         gvwb_we,          // 0: the line fill
    input  wire        gvwb_rvalid,
    input  wire [7:0]  gvwb_rdata,
    input  wire        gv_a_quiet,       // RAM.sv: nothing of port A pending
    output reg  [23:0] gvwb_addr,
    output wire [7:0]  gvwb_wdata,
    input  wire        gvwb_ack,
    input  wire        gvwb_done,
    input  wire [4:0]  gvwb_wcnt,
    // Hardware bisect (core_top JTAG slot 0x09 [27]; 0 in release): the
    // RMW line buffer off at run time, its lines dropped while off.
    input  wire        rmwbuf_off,

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
    output wire [7:0]  dbg,
    // JTAG probe (PC98_JTAG): the wedge tap's sequencer view --
    //   [15] expand -- the access on the pins is being walked (or a svc op
    //         owns the FSM), so a guest pass-through strobe is parked
    //   [14] mem_rd [13] mem_wr -- the leg strobes into RAM.sv
    //   [12] svc_gap -- the one-cycle guest-ready cover after a svc op
    //   [11] is_read [10] is_word [9] half [8] grcg_wbatch
    //   [7:0] nonidle_age -- clk cycles outside S_IDLE, saturating. Walks
    //         top out around a hundred clocks; 0xFF is a wedged walk.
    // Registered at the core_top boundary into the frozen wedge snapshot
    // (probe slot 0xA5).
    output wire [15:0] dbg2
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

    localparam [3:0] S_IDLE = 4'd0,
                     S_RD   = 4'd1,   // read this plane (RMW, or a TCR read)
                     S_RDW  = 4'd2,   // wait for it
                     S_WR   = 4'd3,   // write this plane
                     S_WRW  = 4'd4,   // wait for it
                     S_DONE = 4'd5,
                     S_EVT2 = 4'd6,   // a word read's second lane event
                     S_RBH  = 4'd7;   // RMW line-buffer hit: its M10K word lands

    reg [3:0] st;
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
    reg [7:0] rd_hold_hi;     // ... and its word-burst second byte
    // Set at arm time: this guest word write is a GRCG (non-EGC) op, so
    // the walk runs once per plane with word-wide memory legs instead of
    // twice (even byte, then odd byte).
    reg       grcg_wbatch;
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

    // ------------------------------------------------------------------
    // POSTED GRCG RMW WRITE. A guest RMW write is answered as soon as its
    // operands are latched, and its plane walk runs on behind the guest --
    // the svc channel's own shape (latched operand, held FSM, the guest's
    // next strobe waits for ready). The walk is ~50 chipset clocks and the
    // guest's turnaround to its next store ~27; run serially (REP STOSW
    // under RMW) they cost 1.75x np21w's GRCG price at 286 10 MHz.
    // pw_hold: the walk is a posted one -- every operand below comes from
    // the pw_* latch, never the bus. pw_ack: the guest strobe that posted
    // it is still up; it has its ready and must not be walked again.
    // The GRCG registers, the access page and the EGC arm are latched too:
    // an OUT 7Eh straight after the store must not retile it mid-walk.
    // ------------------------------------------------------------------
    reg        pw_hold, pw_ack;
    reg [19:0] pw_addr;
    reg [7:0]  pw_wd, pw_wdhi;
    reg        pw_rmw, pw_active, pw_page;
    reg [3:0]  pw_mask;
    reg [7:0]  pw_tile [0:3];
    wire       g_rmw    = pw_hold ? pw_rmw    : grcg_rmw;
    wire       g_active = pw_hold ? pw_active : grcg_active;
    wire       g_page   = pw_hold ? pw_page   : access_page;
    wire [3:0] g_mask   = pw_hold ? pw_mask   : grcg_mask;
    wire [7:0] g_tile [0:3];
    assign g_tile[0] = pw_hold ? pw_tile[0] : grcg_tile[0];
    assign g_tile[1] = pw_hold ? pw_tile[1] : grcg_tile[1];
    assign g_tile[2] = pw_hold ? pw_tile[2] : grcg_tile[2];
    assign g_tile[3] = pw_hold ? pw_tile[3] : grcg_tile[3];
    wire [7:0] g_wd     = pw_hold ? pw_wd   : cpu_wdata;
    wire [7:0] g_wdhi   = pw_hold ? pw_wdhi : cpu_wdata_hi;

    // svc_req crosses in from clk_pico: give it one sdram-clock sync stage
    // before the grant so a metastable edge cannot reach the S_IDLE arm and
    // launch a memory access that nobody asked for. The request is a level
    // held until svc_done, so one clock of sync latency is free.
    reg         svc_req_s;
    wire        svc_eval = (st == S_IDLE) & !(cpu_rd | cpu_wr) &
                           svc_req_s & !svc_done & !svc_hold;
    wire        in_svc   = svc_hold | svc_eval;
    wire [19:0] cur_addr = svc_hold ? svc_addr_r
                         : pw_hold  ? pw_addr
                         : svc_eval ? svc_addr : cpu_addr;
    // legpar is the leg's address parity. A dn-direction EGC word WRITE
    // walks the odd byte first: the pipeline's lane 1 product is the high
    // half (egcsftw_dn*'s sub(EGCADDR_H) runs first), so the leg that needs
    // it has to come first. legpar is assigned once egc_here/egc_dn exist.
    wire        legpar;
    wire [19:0] op_addr  = cur_addr | {19'd0, legpar};
    wire        op_ext   = op_addr[0];
    wire [7:0]  cur_wdata = svc_hold ? svc_wdata_r
                         : legpar ? g_wdhi : g_wd;

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
    wire egc_arm   = EGC & egc_active & ~pw_hold;
    // np21w i286c/cpumem.c vacctbl: the EGC rows (0x0a/0x0b/0x0e/0x0f) need
    // the GRCG arm -- operate bit3, modereg[7]. The EGC-enable bit alone
    // (rows 0x02/0x03, and 0x06/0x07 under a stale RMW flag) still answers
    // with plain VRAM; the engine is genuinely blind until the charger is
    // switched in. The service channel is exempt -- io/gdc_pset.c consults
    // VOPBIT_EGC alone, so an svc op runs the EGC whenever it is armed.
    wire egc_on    = egc_arm & (in_svc | g_active);
    wire egc_here  = egc_on & window & ~svc_raw_wr;
    // np21w i286c/cpumem.c vacctbl[0x0c/0x0d]: with the GRCG's RMW bit set a
    // guest READ is plain VRAM -- the modify half applies to writes only,
    // and the TCR answer exists only in TDW mode (rows 0x08/0x09). The read
    // still expands for page-1 banking through plain_pg1 below. ~in_svc
    // keeps a guest strobe that is merely WAITING from de-expanding the
    // service channel's own op.
    wire grcg_rd_raw = ~in_svc & ~pw_hold & cpu_rd & ~cpu_wr & grcg_rmw;
    wire grcg_here = ~egc_on & g_active & window & ~svc_raw_wr
                   & ~grcg_rd_raw;
    wire plain_pg1 = ~egc_on & window & g_page
                   & (~g_active | grcg_rd_raw);
    wire expand    = in_svc | pw_hold | egc_here | grcg_here | plain_pg1;
    wire [1:0] own = own_plane(cur_addr);

    // Pass-through keeps the CPU's word flag for RAM's two-word burst; an
    // expanded access must always reach memory as byte-wide SDRAM words --
    // except the GRCG word batch, which walks each plane once per WORD
    // (mem_wdata/mem_wdata_hi carry both computed bytes).
    assign mem_word = (expand ? is_word : cpu_word) & (~expand | grcg_wbatch);
    // Same rule as mem_word: the prefetch length belongs to the guest's own
    // pass-through strobe. A sequencer leg (svc or expanded) must never run
    // as a multi-word burst -- its reads expect one byte at a time.
    // (mem_pf_len is assigned below the RMW line buffer, which also uses it)

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
            rd_live_f = ~g_mask[p] & ((p != 2'd3) | analog_mode);
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
            wr_live_f = ~g_mask[p] & ((p != 2'd3) | analog_mode);
        else
            wr_live_f = (p == own);
    endfunction

    // Which planes the CURRENT PHASE touches: the read phase of an EGC write
    // still walks all four (the pattern load and the raster's dst each want
    // every byte); the write phase is where the access register and the mask
    // bite.
    wire       cur_live = (st == S_WR) ? wr_live_f(gp) : rd_live_f(gp);
    // Plane E only exists in analog mode, so in digital mode plane G is the
    // last one any walk can touch -- ending the walk there skips the S_WR
    // dead-cycle the plane-E skip used to cost (the leg chains below end on
    // this term). Same shape as egc_rd_last above, for the generic walk.
    wire       last_gp  = (gp == 2'd3) | ((gp == 2'd2) & ~analog_mode);
    wire [7:0] cur_tile = g_tile[gp];

    // Where this plane's byte lives, page banked when 0xA6 says so.
    function automatic logic [19:0] plane_addr(input logic [19:0] a,
                                               input logic [1:0] p);
        plane_addr = g_page ? {3'b000, pc98_gvram_plane1(a, p)}
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
            ? (g_rmw
                ? ((rd_hold & ~cur_wdata) | (cur_wdata & cur_tile))
                : cur_tile)
        : cur_wdata;

    // The odd byte's transform -- same GRCG formulas with the hi operands.
    // Only the GRCG word batch issues it (EGC keeps byte legs, plain mirrors
    // cpu_wdata_hi through the pass-through latch).
    wire [7:0] wr_byte_hi = grcg_here
        ? (g_rmw
            ? ((rd_hold_hi & ~g_wdhi) | (g_wdhi & g_tile[gp]))
            : g_tile[gp])
        : g_wdhi;

    // ------------------------------------------------------------------
    // LEG CHAINING -- issue the next plane's leg on the retire edge.
    //
    // RAM.sv treats a held write strobe whose OPERANDS changed as a new
    // transfer: while its FSM is busy the strobe parks in the pending
    // queue (new_write_strobe/2/3, idle_park, cap), the capture snapshots
    // the bus at that edge, and the executing access keeps running on its
    // accept_* snapshot -- so this module may drop S_WR's one-clock setup
    // between planes and simply move the address/data under a held
    // mem_wr. Each park registers wr_covered one clock later, which is
    // exactly the S_WRW wait the next plane needed anyway: the steady
    // state is one plane leg per clock.
    //
    // Only writes chain out of S_WRW. A read leg cannot chain: its
    // completion IS RAM.sv's COMPLETE_RAM_RW, and the next read has to
    // wait out the strobe-match drop and the IDLE re-accept anyway --
    // chaining there just moves the same latency around. The RMW chain
    // switches to the next plane's READ on the write's covered edge,
    // which is one clock ahead of the S_RD setup path.
    //
    // EGC walks never chain: the shift queue's push/event strobes are
    // timed against the S_RD/S_RDW ladder, and byte-lane order is the
    // pipeline's contract there. Plain page-1 walks are single-plane and
    // have nothing to chain.
    // ------------------------------------------------------------------
    wire chain_ok = grcg_here & ~svc_raw_rd;
    // The next plane's leg address, valid on a retire edge (gp+1).
    wire [1:0]  gp_nx   = gp + 2'd1;
    wire [19:0] nx_addr = plane_addr(op_addr, gp_nx);

    // ------------------------------------------------------------------
    // RMW PLANE-LINE BUFFER. A GRCG RMW write must read every live plane
    // before writing it, and each read leg was a full RAM.sv round trip
    // (~29 chipset clocks, half of it waiting out the display port) --
    // three of them serially per word, ~2.8x np21w's MEMWAIT_GRCG price.
    // Runs of RMW writes walk along a line (REP STOSW, a sprite row), so a
    // read miss now fetches the plane's whole 16-byte line as ONE burst
    // (RAM.sv's prefetch_len read, beats on pf_beat_*), and the next words'
    // reads of that plane come out of the buffer with no leg at all.
    //
    // Coherence is kept by keeping the buffer's life short: it is only
    // ever filled and consulted by guest GRCG RMW writes, every one of
    // which also writes its result back into the buffered byte, and any
    // OTHER write that can reach graphics memory through this module -- a
    // TDW or EGC walk, a service-channel op, a plain or page-one write, a
    // pass-through write into a window -- drops all of it. Reads change
    // nothing and leave it. The tag carries the access page. Not covered:
    // a DMA or loader write into graphics VRAM between two RMW writes to
    // the same line (no PC-98 software path does that).
    // ------------------------------------------------------------------
    // The bytes live in two M10K banks, even and odd (a GRCG word batch's
    // pair is one word of each), 32 x 8 apiece: {plane, word-in-line}. In
    // flip-flops the 512 bits and their any-plane/any-offset ports cost the
    // fit ~1.5k ALMs over the device. The read is registered, so a hit
    // spends one clock in S_RBH; a burst's operand bytes are taken off the
    // beat stream as they pass instead.
    // TWO lines (slots) of four planes: {slot, plane, word-in-line}. The
    // walk uses the slot holding its line (ws); a new line takes the slot
    // used less recently (~mru). With WBACK that lets the older line's
    // write-back run on port G while the walk carries on in the newer one.
    (* ramstyle = "M10K" *) reg [7:0] rbE [0:63];
    (* ramstyle = "M10K" *) reg [7:0] rbO [0:63];
    reg  [7:0]  rbq_e, rbq_o;
    reg  [3:0]  rb_v   [0:1];
    reg  [16:0] rb_tag [0:1];
    reg  [3:0]  rb_d   [0:1];            // dirty planes (WBACK)
    reg         mru;                     // the slot the last buffered write used
    reg         rb_leg;                  // the read leg in flight is a burst
    reg  [3:0]  rb_bi;
    wire        rmw_guest = RMWBUF & ~rmwbuf_off & grcg_here & g_rmw & ~egc_here & ~in_svc
                          & ~is_read;
    wire [16:0] rb_line   = {g_page, op_addr[19:4]};
    wire [3:0]  rb_off    = op_addr[3:0];
    // a batch word must be even: its two bytes are then one word of each bank
    wire        rb_fits   = ~grcg_wbatch | ~op_addr[0];
    wire        m0        = (rb_tag[0] == rb_line) & (rb_v[0] != 4'h0);
    wire        m1        = (rb_tag[1] == rb_line) & (rb_v[1] != 4'h0) & ~m0;
    wire        ws        = m0 ? 1'b0 : m1 ? 1'b1 : ~mru;
    wire        ws_m      = m0 | m1;
    wire [3:0]  ws_v      = rb_v[ws];
    wire        rb_hit_c  = rmw_guest & rb_fits & ws_m & ws_v[gp];
    wire        rb_hit_n  = rmw_guest & rb_fits & ws_m & ws_v[gp_nx];
    wire [19:0] rb_base_c = plane_addr({op_addr[19:4], 4'h0}, gp);
    wire [19:0] rb_base_n = plane_addr({op_addr[19:4], 4'h0}, gp_nx);
    // Bank ports. Writes: the burst's beats in line order, or an RMW write's
    // result bytes (lo to its own bank, a batch's hi to the odd one) -- the
    // two never share a clock (S_RDW vs S_WR). Reads: the plane the hit is
    // about to use (gp_nx on the chain edge in S_WRW, gp otherwise), or the
    // write-back's copy while the FSM leaves the port alone.
    // With WBACK the fill is a port-G read too (rb_g): no RAM.sv round
    // trip, and it waits for gv_a_quiet so it cannot pass a parked write.
    reg         rb_g, gf_sent;
    reg  [23:0] gf_addr;
    wire        rb_bv     = rb_g ? gvwb_rvalid : pf_beat_v;
    wire [7:0]  rb_bd     = rb_g ? gvwb_rdata  : pf_beat_dat;
    function automatic logic [23:0] g_sdram(input logic pg, input logic [19:0] pa);
        g_sdram = pg ? (24'h600000 + {7'h00, pa[16:0]}) : {4'h0, pa};
    endfunction
    wire        rb_beat_w = rb_leg & rb_bv;
    wire        rb_upd_w  = (st == S_WR) & cur_live & rmw_guest & rb_fits
                          & ws_m & ws_v[gp];
    wire [5:0]  rb_wa     = rb_beat_w ? {ws, gp, rb_bi[3:1]} : {ws, gp, rb_off[3:1]};
    wire        rb_we_e   = rb_beat_w ? ~rb_bi[0] : (rb_upd_w & ~rb_off[0]);
    wire        rb_we_o   = rb_beat_w ?  rb_bi[0] : (rb_upd_w & (rb_off[0] | grcg_wbatch));
    wire [7:0]  rb_wd_e   = rb_beat_w ? rb_bd : wr_byte;
    wire [7:0]  rb_wd_o   = rb_beat_w ? rb_bd : (rb_off[0] ? wr_byte : wr_byte_hi);
    // ------------------------------------------------------------------
    // WRITE-BACK (WBACK). A buffered RMW write no longer writes its plane
    // byte through RAM.sv at all: the result is already in the bank (the
    // rb_upd_w write above), so the plane is only marked dirty and the walk
    // moves on. A dirty plane line leaves as one sixteen-word burst on
    // port G -- three plane writes per word through RAM.sv (each its own
    // SDRAM transaction, ~8 clocks) become three bursts per eight words.
    //
    // The engine writes back the OLDER slot as soon as it is dirty (the walk
    // has moved to a new line), in the background: its copy out of the
    // banks takes the read port only on clocks the FSM leaves it, and its
    // burst needs nothing of the FSM at all. The newer slot goes when it
    // sits idle WB_AGE clocks, or when an access needs everything out.
    //
    // Coherence, the buffer being the newest copy of its lines:
    //   * every access the FSM or the pass-through would make to a
    //     graphics window, other than a posted-shape RMW write, waits for
    //     every dirty line (fl_all); so does a svc op touching a buffered
    //     line, and turning the buffer off (slot 0x09 [27]);
    //   * an RMW write waits while its slot is being written back (the
    //     engine would clear a dirty bit the write just set), and a new
    //     line waits for its victim slot to be clean;
    //   * the display (port D, straight from SDRAM) is behind by at most
    //     one line change or WB_AGE clocks;
    //   * the burst's data is copied out into stg first (the M10K read is
    //     registered; the controller wants each word on its p_wcnt).
    // Port A writes into a line cannot be in flight behind it: the fill
    // that buffered it waited for gv_a_quiet (or read through RAM.sv's
    // rd_conflicts), and every later write to it was either buffered or
    // waited for this write-back.
    // ------------------------------------------------------------------
    reg         fl_busy, fl_hold_q, fl_s, cp_q;
    reg  [1:0]  fl_ph;                   // 0 copy, 1 request, 2 burst
    reg  [1:0]  fl_p;
    reg  [3:0]  fl_i, fl_c;              // copy: words issued, words landed
    reg  [2:0]  cp_w;                    // the word the landing read was for
    reg  [7:0]  stg [0:15];
    reg  [6:0]  wb_age;
    wire        wb_on    = RMWBUF & WBACK;
    wire [3:0]  rd0      = wb_on ? rb_d[0] : 4'h0;
    wire [3:0]  rd1      = wb_on ? rb_d[1] : 4'h0;
    wire        rb_dirty = (rd0 != 4'h0) | (rd1 != 4'h0);
    // The live strobe, judged in S_IDLE: a posted-shape RMW write, and the
    // slot its line is (or would go) in.
    wire        lv_fits  = ~(cpu_word & ~cpu_rd) | ~cpu_addr[0];
    wire        lv_shape = cpu_wr & ~cpu_rd & RMWBUF & ~rmwbuf_off & grcg_here
                         & grcg_rmw & ~egc_here & ~in_svc & lv_fits;
    wire [16:0] lv_line  = {access_page, cpu_addr[19:4]};
    wire        lm0      = (rb_tag[0] == lv_line) & (rb_v[0] != 4'h0);
    wire        lm1      = (rb_tag[1] == lv_line) & (rb_v[1] != 4'h0) & ~lm0;
    wire        lslot    = lm0 ? 1'b0 : lm1 ? 1'b1 : ~mru;
    wire [3:0]  lslot_d  = lslot ? rd1 : rd0;
    // its slot is being written back, or it is a new line whose victim is
    // still dirty: wait (the engine is on it)
    wire        lv_wait  = lv_shape & ((fl_busy & (fl_s == lslot))
                                     | (~(lm0 | lm1) & (lslot_d != 4'h0)));
    wire        strobe_new = (cpu_rd | cpu_wr) & ~pw_ack;
    // A svc op only has to wait when it touches a buffered line in some
    // plane: every plane window is 32 KB, so that is the line's offset in
    // the window (and the page). Ops elsewhere walk through RAM.sv beside
    // the dirty lines, and their writes leave the buffer alone (below).
    wire        svc_l0   = (svc_addr[14:4] == rb_tag[0][10:0]) & (access_page == rb_tag[0][16]);
    wire        svc_l1   = (svc_addr[14:4] == rb_tag[1][10:0]) & (access_page == rb_tag[1][16]);
    wire        fl_want_all = (strobe_new & window & ~lv_shape)
                         | (svc_req_s & ~svc_done & ~svc_hold
                            & ((svc_l0 & (rd0 != 4'h0)) | (svc_l1 & (rd1 != 4'h0))))
                         | rmwbuf_off;
    // everything out first: no window access while any line is dirty or
    // a burst is still on its way
    wire        fl_all   = fl_want_all & (rb_dirty | fl_busy);
    wire [3:0]  rdo      = mru ? rd0 : rd1;       // the older slot
    wire [3:0]  rdn      = mru ? rd1 : rd0;       // the newer one
    wire        fl_start = rb_dirty & ~fl_busy & ~rb_leg
                         & ((st == S_IDLE) | (st == S_RDW & rb_g & ~gf_sent))
                         & ((rdo != 4'h0) | fl_all | (wb_age >= 7'(WB_AGE)));
    wire        fl_sel   = (rdo != 4'h0) ? ~mru : mru;
    wire [3:0]  fl_sd    = fl_sel ? rd1 : rd0;
    wire        fl_hold  = fl_all | lv_wait;
    // the pass-through's ready waits one clock longer than its strobes, so
    // the access released from the hold is on the pins before ready counts
    wire        pt_blk   = (fl_hold | fl_hold_q) & window;
    wire        wb_skip  = wb_on & rb_upd_w & ~rmwbuf_off;
    wire [3:0]  fl_cur   = fl_s ? rd1 : rd0;
    wire [1:0]  fl_first = fl_sd[0] ? 2'd0 : fl_sd[1] ? 2'd1 : fl_sd[2] ? 2'd2 : 2'd3;
    wire [3:0]  fl_rest  = fl_cur & ~(4'b0001 << fl_p);
    wire [1:0]  fl_next  = fl_rest[0] ? 2'd0 : fl_rest[1] ? 2'd1 : fl_rest[2] ? 2'd2 : 2'd3;
    wire [16:0] fl_tag   = rb_tag[fl_s];
    wire [19:0] fl_pa    = fl_tag[16] ? {3'b000, pc98_gvram_plane1({fl_tag[15:0], 4'h0}, fl_p)}
                                      : pc98_gvram_plane({fl_tag[15:0], 4'h0}, fl_p);
    assign gvwb_wdata = stg[gvwb_wcnt[3:0]];
    // the copy owns the read port on clocks the FSM does not read the banks
    wire        cp_own   = fl_busy & (fl_ph == 2'd0) & (fl_i != 4'd8)
                         & ((st == S_IDLE) | (st == S_RDW & rb_g & ~gf_sent));
    wire [5:0]  rb_ra     = cp_own ? {fl_s, fl_p, fl_i[2:0]}
                          : {ws, ((st == S_WRW) || (WBACK && st == S_WR)) ? gp_nx : gp,
                             rb_off[3:1]};
    always @(posedge clk) begin
        if (rb_we_e) rbE[rb_wa] <= rb_wd_e;
        if (rb_we_o) rbO[rb_wa] <= rb_wd_o;
        rbq_e <= rbE[rb_ra];
        rbq_o <= rbO[rb_ra];
    end

    // A buffer burst leg asks RAM.sv for the plane's 16-byte line.
    assign mem_pf_len = rb_leg ? 5'd16 : (cpu_pf_len & {5{~expand}});
    assign pf_beat_seq = rb_leg & ~rb_g;

    // Ready lands on the FINAL byte's walk: a word access's first S_DONE
    // only starts the odd half. svc_hold forces expand high, which parks
    // ready low -- a guest access arriving mid-svc-op waits politely.
    // The ~svc_hold matters at S_DONE: without it a guest whose strobe is
    // up when a svc op completes would see this cycle's ready and take
    // rdata_pass -- a stale byte -- for an access that never ran.
    // NOTE: the ready is deliberately NOT pulled earlier onto the final
    // S_WRW's retire edge, even though that edge is the walk's true
    // completion. S_DONE is a HELD level until the strobe drops, and a
    // back-to-back master (rep stosw) raises its next strobe one clock
    // after the release -- exactly when the FSM still sits in S_DONE.
    // The held ready would then answer the NEW strobe without running it
    // (tb chained-fill: every other word skipped). The one clock stays.
    assign cpu_ready = pw_ack ? 1'b1
                     : expand ? (st == S_DONE) & (~is_word | half
                                                   | grcg_wbatch)
                               & ~svc_hold & ~pw_hold
                               : mem_ready & ~svc_gap & ~pt_blk;

    // ~expand also proves ownership: mem_wr is then the registered
    // pass-through of cpu_wr and nothing else -- a sequencer leg only
    // exists while expand holds, so write_taken can only be answering a
    // foreign strobe when expand is set. A held guest write arriving
    // while a svc op runs sees expand=1 and mem_wr_taken=1 legs go by
    // untouched; its own strobe reaches the port only once the walk
    // hands the FSM back.
    //
    // The expand half is the walk's own done: a guest write the
    // sequencer claims never reaches RAM as itself, so its "taken" is
    // the walk completing -- S_DONE is a held level (the FSM parks
    // there until the guest drops its strobe), and ~svc_hold keeps a
    // service op's done from ever satisfying a guest write, the same
    // ownership term cpu_ready carries. ~is_word|half mirrors
    // cpu_ready: a word access's first S_DONE only starts the odd
    // half -- the walk is not done until the second pass lands.
    assign cpu_wr_taken = pw_ack ? 1'b1
                        : ~expand ? mem_wr_taken
                                : ((st == S_DONE)
                                   & (~is_word | half | grcg_wbatch)
                                   & ~svc_hold & ~pw_hold);

    // cpu_ready qualified to the guest's own reach -- see the port comment.
    assign cpu_rd_own = cpu_ready & cpu_rd & (mem_rd | expand);

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
            rd_hold_hi<= 8'h00;
            grcg_wbatch <= 1'b0;
            rdata_pass<= 8'h00;
            egc_rd_q  <= 8'h00;
            egc_own_q <= 8'h00;
            mem_addr  <= 20'h0;
            mem_wdata <= 8'h00;
            mem_wdata_hi <= 8'h00;
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
            rb_v[0]   <= 4'h0;
            rb_v[1]   <= 4'h0;
            mru       <= 1'b0;
            rb_leg    <= 1'b0;
            pw_hold   <= 1'b0;
            pw_ack    <= 1'b0;
            rb_d[0]   <= 4'h0;
            rb_d[1]   <= 4'h0;
            fl_busy   <= 1'b0;
            cp_q      <= 1'b0;
            fl_hold_q <= 1'b0;
            gvwb_req  <= 1'b0;
            gvwb_we   <= 1'b0;
            wb_age    <= 7'd0;
            rb_g      <= 1'b0;
        end else begin
            // ---- write-back engine (WBACK) ------------------------------
            fl_hold_q <= fl_hold;
            if (!rb_dirty || st != S_IDLE || fl_busy) wb_age <= 7'd0;
            else if (wb_age != 7'h7F) wb_age <= wb_age + 7'd1;
            if (gvwb_req && gvwb_ack) gvwb_req <= 1'b0;
            cp_q <= cp_own;
            cp_w <= fl_i[2:0];
            if (fl_start) begin
                fl_busy <= 1'b1;
                fl_s    <= fl_sel;
                fl_p    <= fl_first;
                fl_i    <= 4'd0;
                fl_c    <= 4'd0;
                fl_ph   <= 2'd0;
            end
            if (fl_busy) case (fl_ph)
              2'd0: begin                      // copy the plane line out
                if (cp_own) fl_i <= fl_i + 4'd1;
                if (cp_q) begin
                    stg[{cp_w, 1'b0}] <= rbq_e;
                    stg[{cp_w, 1'b1}] <= rbq_o;
                    fl_c <= fl_c + 4'd1;
                    if (fl_c == 4'd7) begin
                        gvwb_req  <= 1'b1;
                        gvwb_we   <= 1'b1;
                        gvwb_addr <= g_sdram(fl_tag[16], fl_pa);
                        fl_ph     <= 2'd1;
                    end
                end
              end
              2'd1: if (gvwb_ack) fl_ph <= 2'd2;
              default: if (gvwb_done) begin
                rb_d[fl_s][fl_p] <= 1'b0;
                if (fl_rest != 4'h0) begin
                    fl_p  <= fl_next;
                    fl_i  <= 4'd0;
                    fl_c  <= 4'd0;
                    fl_ph <= 2'd0;
                end else
                    fl_busy <= 1'b0;
              end
            endcase
            // The posting strobe has its ready; it is gone once it drops --
            // or once the pins carry another cycle's operands: a master
            // that runs write after write without a strobe gap (the bridge
            // with the cache off) would otherwise have its NEXT write
            // answered by this ack and never performed. An identical
            // re-write is idempotent, for RMW and plain alike.
            if (!cpu_wr || cpu_addr != pw_addr || cpu_wdata != pw_wd
                || (cpu_word && cpu_wdata_hi != pw_wdhi) || cpu_word != is_word)
                pw_ack <= 1'b0;
            if (rmwbuf_off && !rb_leg && !rb_dirty) begin rb_v[0] <= 4'h0; rb_v[1] <= 4'h0; end
            // the line buffer's burst beats, in order from the line head
            if (rb_leg && rb_bv) begin
                // the operand bytes, off the stream as they pass
                if (rb_bi == rb_off) rd_hold <= rb_bd;
                if (grcg_wbatch && rb_bi == (rb_off | 4'd1)) rd_hold_hi <= rb_bd;
                rb_bi <= rb_bi + 4'd1;
            end
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
            svc_gap <= (st == S_DONE) & (svc_hold | pw_hold);

            if (!expand) begin
                // Pass-through: the guest's own access, unchanged.
                mem_addr  <= cpu_addr;
                mem_wdata <= cpu_wdata;
                mem_wdata_hi <= cpu_wdata_hi;
                mem_rd    <= cpu_rd & ~(fl_hold & window);
                mem_wr    <= cpu_wr & ~pw_ack & ~(fl_hold & window);
                mem_page1 <= 1'b0;
                // ONLY WHILE A READ IS LIVE. Assigning this unconditionally
                // clobbered a TCR answer the moment the guest's strobes dropped
                // and `expand` went false -- the answer has to survive until the
                // guest has taken it, and the guest takes it while its own read
                // command is still up.
                if (cpu_rd) rdata_pass <= mem_rdata;
                if (cpu_wr & window & ~fl_hold) begin rb_v[0] <= 4'h0; rb_v[1] <= 4'h0; end
                st        <= S_IDLE;
                gp        <= 2'd0;
            end else begin
            case (st)
              S_IDLE: begin
                mem_rd <= 1'b0;
                mem_wr <= 1'b0;
                if ((cpu_rd | cpu_wr) && !pw_ack && !fl_hold) begin
                    // An RMW word the buffer cannot hold (odd: its bytes
                    // are not one word of each bank) walks through RAM.sv;
                    // the buffered copy of its line would go stale.
                    if (cpu_wr && grcg_here && grcg_rmw && !egc_here
                        && cpu_word && cpu_addr[0]) begin
                        rb_v[0] <= 4'h0; rb_v[1] <= 4'h0;
                    end
                    is_read <= cpu_rd;
                    // Post it: a GRCG RMW write (byte, or the word batch)
                    // is answered now and walked from the latch.
                    if (PWPOST && cpu_wr && !cpu_rd && grcg_here && grcg_rmw
                        && !egc_here && !rmwbuf_off) begin
                        pw_hold   <= 1'b1;
                        pw_ack    <= 1'b1;
                        pw_addr   <= cpu_addr;
                        pw_wd     <= cpu_wdata;
                        pw_wdhi   <= cpu_wdata_hi;
                        pw_rmw    <= grcg_rmw;
                        pw_active <= grcg_active;
                        pw_page   <= access_page;
                        pw_mask   <= grcg_mask;
                        for (int t = 0; t < 4; t++) pw_tile[t] <= grcg_tile[t];
                    end
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
                    // RMW short-circuits, so a walk only pays the read
                    // phase when the operand actually mixes bits: with a
                    // 0xFF operand every plane's byte lands as its tile
                    // (the TDW shape, wr_byte self-collapses to it), and
                    // with a 0x00 operand every plane keeps its byte, so
                    // there is nothing to touch in memory at all.
                    // GRCG word batch: both bytes walk the planes in
                    // one word-wide pass. EGC words keep byte legs (the
                    // shift queue needs them); reads never batch.
                    grcg_wbatch <= cpu_word & grcg_here & ~egc_here
                                   & ~cpu_rd;
                    if (cpu_wr & ~(grcg_here & grcg_rmw & ~egc_here)) begin
                        rb_v[0] <= 4'h0; rb_v[1] <= 4'h0;
                    end
                    if (cpu_rd | egc_here)
                        st <= S_RD;
                    else if (grcg_rmw && cur_wdata == 8'hFF
                             && (!cpu_word || cpu_wdata_hi == 8'hFF))
                        st <= S_WR;
                    else if (grcg_rmw && cur_wdata == 8'h00
                             && (!cpu_word || cpu_wdata_hi == 8'h00))
                        st <= S_DONE;
                    else
                        st <= grcg_rmw ? S_RD : S_WR;
                end else if (svc_req_s && !svc_done && !fl_hold) begin
                    // The softcore's byte op: same walk, through the same
                    // charger. A svc write under TDW lays the tiles; under
                    // RMW the read-modify-write runs; under the EGC the
                    // raster op does. This is what makes firmware-served
                    // WDAT/drawing land on real VRAM the way hardware does.
                    svc_hold   <= 1'b1;
                    grcg_wbatch <= 1'b0;   // svc ops are byte-wide
                    // a svc write drops the slot whose line it touches (a
                    // dirty one was written back first: fl_want_all)
                    if (svc_we && svc_l0) rb_v[0] <= 4'h0;
                    if (svc_we && svc_l1) rb_v[1] <= 4'h0;
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
                        // The same RMW short-circuits as the guest arm:
                        // 0xFF collapses to the TDW shape, 0x00 retires
                        // through S_DONE with no memory op (svc acks there).
                        if (~svc_we | egc_here)
                            st <= S_RD;
                        else if (grcg_rmw && ~svc_raw_wr
                                 && svc_wdata == 8'hFF)
                            st <= S_WR;
                        else if (grcg_rmw && ~svc_raw_wr
                                 && svc_wdata == 8'h00)
                            st <= S_DONE;
                        else
                            st <= (grcg_rmw & ~svc_raw_wr)
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
                end else if (rb_hit_c) begin
                    // the line buffer has this plane's bytes: no leg
                    st         <= S_RBH;
                end else begin
                    if (rmw_guest & rb_fits) begin
                        // miss: fetch the plane's whole line in one burst
                        mem_addr <= rb_base_c;
                        rb_leg   <= 1'b1;
                        rb_bi    <= 4'd0;
                        rb_g     <= WBACK;
                        gf_sent  <= 1'b0;
                        gf_addr  <= g_sdram(g_page, rb_base_c);
                    end else
                        mem_addr <= plane_addr(op_addr, gp);
                    mem_page1 <= g_page;
                    mem_rd    <= ~(WBACK & rmw_guest & rb_fits);
                    st        <= S_RDW;
                end
              end

              S_RDW: begin
                if (rb_g && !gf_sent && gv_a_quiet && !fl_busy && !fl_start) begin
                    gvwb_req  <= 1'b1;
                    gvwb_we   <= 1'b0;
                    gvwb_addr <= gf_addr;
                    gf_sent   <= 1'b1;
                end
                if (rb_g ? (gf_sent & gvwb_done) : leg_done) begin
                rb_g    <= 1'b0;
                mem_rd  <= 1'b0;
                if (!rb_leg) begin
                    rd_hold    <= mem_rdata;
                    rd_hold_hi <= mem_rdata_hi;
                end
                if (rb_leg) begin
                    // the burst landed: the plane's line is buffered, and
                    // this leg's operand bytes come out of it
                    rb_leg     <= 1'b0;
                    rb_v[ws]   <= ((rb_tag[ws] == rb_line) ? rb_v[ws] : 4'h0)
                                | (4'b0001 << gp);
                    rb_tag[ws] <= rb_line;
                    mru        <= ws;
                end
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
              end

              // ---- a word read's second lane ----------------------------
              // The head event ran on the last plane's byte landing; the
              // queue shifted under it. One dead cycle lets the tail event
              // produce lane 2 before S_DONE assembles the answer.
              S_EVT2: st <= S_DONE;

              // ---- RMW line-buffer hit: the bank word has landed ---------
              S_RBH: begin
                rd_hold    <= rb_off[0] ? rbq_o : rbq_e;
                rd_hold_hi <= rbq_o;
                st         <= S_WR;
              end

              // ---- write this plane -----------------------------------
              S_WR: begin
                if (!cur_live) begin
                    if (last_gp) st <= S_DONE;
                    else begin
                        gp <= gp + 2'd1;
                        st <= g_rmw | egc_here ? S_RD : S_WR;
                    end
                end else if (wb_skip) begin
                    // Write-back: the result is in the bank (rb_upd_w);
                    // only mark it dirty. rb_ra has the next plane's word.
                    rb_d[ws][gp] <= 1'b1;
                    mru          <= ws;
                    if (last_gp) st <= S_DONE;
                    else if (chain_ok & rd_live_f(gp_nx) & rb_hit_n) begin
                        gp <= gp_nx;
                        st <= S_RBH;
                    end else begin
                        gp <= gp + 2'd1;
                        st <= S_RD;
                    end
                end else begin
                    mem_addr  <= plane_addr(op_addr, gp);
                    mem_page1 <= g_page;
                    mem_wdata <= wr_byte;
                    mem_wdata_hi <= wr_byte_hi;
                    mem_wr    <= 1'b1;
                    st        <= S_WRW;
                    // (a buffered line is kept equal to memory: rb_upd_w)
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
              //
              // The CHAIN arms below ride that release straight into the
              // next plane's leg (see the chaining block above the FSM):
              // the TDW chain keeps mem_wr up and moves the operands (RAM
              // parks the new strobe while the old access drains), the RMW
              // chain drops the write and puts the next plane's read on the
              // bus one clock before the S_RD setup path would.
              S_WRW: if (leg_done | mem_ready) begin
                if (last_gp) begin
                    mem_wr <= 1'b0;
                    st <= S_DONE;
                end
                // RMW chain: the next live plane's READ, now.
                else if (chain_ok & g_rmw & rd_live_f(gp_nx) & rb_hit_n) begin
                    // next plane's bytes are buffered: straight to its write
                    mem_wr     <= 1'b0;
                    gp         <= gp_nx;
                    st         <= S_RBH;
                end
                else if (chain_ok & g_rmw & rd_live_f(gp_nx)) begin
                    mem_wr    <= 1'b0;
                    mem_rd    <= ~(WBACK & rmw_guest & rb_fits);
                    gp        <= gp_nx;
                    if (rmw_guest & rb_fits) begin
                        mem_addr <= rb_base_n;
                        rb_leg   <= 1'b1;
                        rb_bi    <= 4'd0;
                        rb_g     <= WBACK;
                        gf_sent  <= 1'b0;
                        gf_addr  <= g_sdram(g_page, rb_base_n);
                    end else
                        mem_addr <= nx_addr;
                    mem_page1 <= g_page;
                    st        <= S_RDW;
                end
                // TDW chain: mem_wr stays UP, operands move.
                else if (chain_ok & ~g_rmw & ~egc_here
                         & wr_live_f(gp_nx)) begin
                    mem_wr       <= 1'b1;
                    gp           <= gp_nx;
                    mem_addr     <= nx_addr;
                    mem_page1    <= g_page;
                    mem_wdata    <= g_tile[gp_nx];
                    mem_wdata_hi <= g_tile[gp_nx];
                    st           <= S_WRW;
                end else begin
                    mem_wr <= 1'b0;
                    gp <= gp + 2'd1;
                    st <= g_rmw | egc_here ? S_RD : S_WR;
                end
              end

              // ---- the answer -----------------------------------------
              S_DONE: begin
                // The answer itself is the mux above -- TCR returns the
                // INVERSE, a bit set where every unmasked plane matched, and
                // with every plane masked nothing differs and it is 0xFF,
                // which is np21w's behaviour too.
                if (pw_hold) begin
                    // A posted walk is done: hand the FSM back (the guest
                    // was answered when it posted; svc_gap covers a strobe
                    // that has been waiting since).
                    pw_hold <= 1'b0;
                    st      <= S_IDLE;
                end else if (svc_hold) begin
                    // The byte op is complete; ack the requester with the
                    // answer (a write's svc_rdata is don't-care).
                    svc_rdata <= ans_byte;
                    svc_done  <= 1'b1;
                    svc_hold  <= 1'b0;
                    st        <= S_IDLE;
                end else if (is_word & ~half & ~grcg_wbatch) begin
                    // A word access: the even byte's walk is done -- run it
                    // all again for the odd byte. Ready stays low until the
                    // second walk reaches S_DONE (cpu_ready above).
                    lo_ans <= ans_byte;
                    half   <= 1'b1;
                    gp     <= plain_pg1 ? own : 2'd0;
                    tcr    <= 8'h00;
                    // The odd byte's arm re-runs the RMW short-circuits,
                    // lane by lane (see the S_IDLE arm).
                    if (is_read | egc_here)
                        st <= S_RD;
                    else if (g_rmw && cur_wdata == 8'hFF)
                        st <= S_WR;
                    else if (g_rmw && cur_wdata == 8'h00)
                        st <= S_DONE;
                    else
                        st <= g_rmw ? S_RD : S_WR;
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

    // The wedge tap's age: how long the walk (or a parked svc op) has held
    // the FSM. Saturates like RAM.sv's nonidle_age.
    reg [7:0] nonidle_age;
    always_ff @(posedge clk) begin
        if (reset)
            nonidle_age <= 8'd0;
        else if (st == S_IDLE)
            nonidle_age <= 8'd0;
        else if (nonidle_age != 8'hFF)
            nonidle_age <= nonidle_age + 8'd1;
    end

    assign dbg2 = {expand, mem_rd, mem_wr, svc_gap, is_read, is_word,
                   half, grcg_wbatch, nonidle_age};

    // cpu_gvram was the window qualifier until `window` moved onto the
    // address alone (see above); it stays on the port list because Chipset
    // still produces it and a future build may want the select again.
    wire _unused = &{1'b0, cpu_gvram, 1'b0};

endmodule

`default_nettype wire
