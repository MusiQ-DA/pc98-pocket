//============================================================================
//  z86_cache -- z86's memory port with a real cache in front of the SDRAM.
//
//  Same z86-side ports as z86_wbif (ld_*, rd_*, wr_*), two ways out:
//
//   * CACHED: guest RAM 00000-9FFFF and the ROM image E8000-FFFFF. 16 KB,
//     direct mapped, 16-byte lines, tagged by the PHYSICAL address
//     {bios_shadow, addr} -- so the ITF bank at F8000 and the BIOS behind
//     it are different lines and the bank switch needs no flush. Misses
//     fill a whole line as ONE sixteen-beat burst on a dedicated sdram_mp
//     port (F); RAM.sv keeps one guest byte per SDRAM word, so a line is
//     exactly sixteen words. Writes are write-through, no allocate: the
//     line is updated on a hit and the store goes out on port F through a
//     one-entry write buffer, acknowledged to the core as soon as it is
//     buffered.
//   * UNCACHED: I/O, VRAM, the CG window, option ROMs, EMS -- everything
//     else -- runs as Wishbone cycles through cpu_bus_bridge. The write
//     buffer is drained before any
//     of them starts, so an OUT that starts a DMA never passes the store
//     that set up its buffer.
//
//  Coherency. The only other writers of the cached ranges reach the SDRAM
//  through port A (CPU-bus DMA, the ROM loader, the JTAG/firmware masters
//  on the chipset bus). Each port A write COMMIT (sdram_shim's a_wr_*) clears
//  the line it lands in. sdram_mp runs one transaction at a time, so a fill
//  either reads after the commit or its line is cleared by it -- there is
//  no window in between. The CPU's own stores update the line in place, and
//  the fetch unit already snoops them for its buffer.
//
//  The lookup itself races the snoop on two edges, and both must lose to
//  the snoop: the invalidating tag write is registered, so a commit
//  accepted on the lookup's read edge only reaches the tag RAM the edge
//  after (the kill register), and one accepted on the compare edge is in
//  the SDRAM already (the sn_hit term on hit). Either window left the
//  stale line serving -- the SuperDepth 0xA1-vs-0x38 failure, where the
//  FDC's DMA byte landed in a line the ITF memory test had cached
//  (tb_z86_cache_snoop T6). A commit accepted while a fill is installing
//  suppresses the install's valid bit the same way (sn_ours in S_FILL,
//  plus the in-flight guard for one accepted on f_done's own edge).
//
//  The tag-write SLOT is guarded as well: the install and a kill share
//  t_we/t_wa/t_wd, and the FSM's assignment is the later one in the block,
//  so a kill racing the install of ANOTHER line was silently overwritten
//  -- the kill "fired" (the snoop feed, and the witness counter, saw it)
//  but never reached the tag RAM, and the commit's line went on serving
//  its pre-commit data (T9). Installs now defer their valid bit to any
//  kill on their edge; a second-line kill that loses the slot to a new
//  commit stays armed and retries (T7).
//
//  And the eviction itself clears the tag at the MISS edge, before the
//  fill ever runs: a DEFERRED install leaves the tag untouched, which
//  used to mean the index's previous occupant kept its VALID tag over
//  the new line's just-installed data -- the evicted address "hit" and
//  served the filler's bytes, and no commit ever killed it, because
//  nothing writes a 16 KB alias the filler displaced (T10). With the
//  victim cleared at the miss, a deferred install just leaves the index
//  invalid -- one refill, never a lie. The eviction write shares t_we
//  with the snoop, so on a busy edge it parks (park_v) and retries, one
//  step behind the snoop's own pending kill: a commit's kill always
//  outranks it.
//
//  Clocking. This runs on the FREE clk_chipset, not the bridge's gated CPU
//  clock, because port F and the snoop are pulses on the free clock. `ce`
//  is the bridge's zet_edge: high on the clk posedges where the gated clock
//  also ticks. Everything the core or the bridge samples is qualified by it,
//  which makes those paths behave exactly as if they ran on the gated clock:
//  a pulse from the core (rd) is taken only on a ce edge, a pulse to the
//  core (wr_ready) is held until a ce edge has seen it, and the Wishbone
//  master only moves on ce edges. Levels (rd_ready, ld_ack, the data) may
//  change on any edge; the core reads them on its next one.
//
//  I/O pacing. No blanket gap any more: the only consumer of z86_wbif's
//  IO_GAP was the ITF's PIT check (load counter 0, two JMP $+2, latch, and
//  expect the count to have moved), so the gap now applies only in front of
//  a PIT access (71/73/75/77h, 3FD9-3FDFh). OUT 5Fh is PC-98 software's own
//  I/O delay -- about 0.6 us on the machines that have it (np21w io/artic.c)
//  -- so the store is held that long before the core sees it complete.
//
//  SPDX-License-Identifier: Apache-2.0  (z86 is Apache-2.0)
//============================================================================

`default_nettype none

module z86_cache #(
    // Minimum gap, in clk, from the end of one I/O cycle to the start of a
    // PIT access (see above). 64 clk_chipset is ~1.5 us.
    parameter int PIT_GAP  = 64,
    // OUT 5Fh: ~0.6 us at 42.95 MHz.
    parameter int WAIT_5F  = 26,
    parameter int IDX_BITS = 10,        // 1024 lines x 16 B = 16 KB
    // Write combining (see "Store combining"): 1 in core_top. Benches whose
    // port-F model cannot take a burst keep the single-store path.
    parameter bit WCOMB    = 0,
    // Clocks an idle combine buffer waits before it writes itself out.
    parameter int CB_AGE   = 32,
    // Paced stores answered before their bus time is paid (see wr_owed).
    parameter bit STORE_POST = 1,
    // PC-98 port: 24-bit linear addresses from z86's 80286 protected mode,
    // and EXT_MB megabytes of extended memory at 100000h (see "Extended
    // memory" below). 0: the 20-bit cache, unchanged.
    parameter bit PM286    = 0,
    parameter int EXT_MB   = 3
) (
    input  wire         clk,            // free clk_chipset
    input  wire         ce,             // the gated CPU clock ticks this edge
    input  wire         reset,          // CPU reset (synchronous)
    input  wire         cache_en,       // 0: everything takes the bus
    // Paced settings (286 8/10/12 MHz): a cached access completes no
    // sooner than the 286 bus cycles it stands for -- see "Paced hits".
    input  wire         pace,
    input  wire         pace_ce,        // one pulse per 286 CPU clock
    input  wire [1:0]   pace_rd_wait,   // wait states per read cycle
    input  wire [1:0]   pace_wr_wait,   // ... per write cycle
    // np21w's graphics-VRAM wait for an access starting now ({analog,
    // clocks}: 6 with the beam out, 8 with the GRCG/EGC armed, 1 in
    // vblank -- Chipset.sv). Added once per uncached VRAM access.
    input  wire [4:0]   pace_vwait,
    // execute's per-iteration REP surcharge (rep_x), paced settings only
    input  wire [2:0]   rep_x,
    input  wire         rep_on,         // execute: a REP string loop is running
    // Hardware bisect (core_top JTAG slot 0x09 [21]-[24]; 0 in release):
    // [0] line loads priced whole before the hand-off (no critical word
    // first), [1] no store combining, [2] no whole-line install from a
    // combine bank, [3] no graphics-VRAM pricing.
    input  wire [3:0]   dx,

    // ---- PC-98 map state ------------------------------------------------
    input  wire         bios_shadow,    // RAM.sv bios_shadow_flag
    input  wire         bios_protect,   // RAM.sv bios_protect_flag[1]

    // ---- z86 side: the `cache` module's ports ---------------------------
    input  wire [23:0]  ld_addr,
    input  wire         ld_req,         // toggle
    output reg          ld_ack,         // toggle, follows ld_req when done
    output reg [127:0]  ld_data,
    // The fetch buffer has dropped the line load in flight (a branch or a
    // store snoop retargeted it): an uncached load stops at the word on
    // the bus instead of fetching the rest of a line nobody will use.
    input  wire         ld_drop,

    input  wire [23:0]  rd_addr,
    input  wire         rd,             // pulse
    output reg          rd_ready,       // idle or data ready
    output reg [15:0]   rd_data,
    input  wire         rd_io,
    input  wire         rd_word,

    input  wire [23:0]  wr_addr,
    input  wire         wr_valid,       // held until wr_ready
    output reg          wr_ready,       // pulse (held until a ce edge)
    input  wire [15:0]  wr_data,
    input  wire         wr_word,
    input  wire         wr_io,

    // ---- Wishbone master (the bridge's contract) ------------------------
    output reg  [19:1]  wb_adr_o,
    output reg  [ 1:0]  wb_sel_o,
    output reg          wb_we_o,
    output reg          wb_tga_o,
    output reg  [15:0]  wb_dat_o,
    output reg          wb_stb_o,
    output wire         wb_cyc_o,
    input  wire         wb_ack_i,
    input  wire [15:0]  wb_dat_i,

    // ---- sdram_mp port F (word address, one guest byte per word) -------
    output reg          f_req,
    output reg          f_we,
    output reg  [23:0]  f_addr,
    output reg  [ 3:0]  f_len,
    output wire [15:0]  f_wdata0,
    output wire [15:0]  f_wdata1,
    input  wire         f_ack,
    input  wire         f_rvalid,
    input  wire [15:0]  f_rdata,
    input  wire         f_done,
    input  wire [4:0]   f_wcnt,         // sdram_mp's p_wcnt: the word it wants

    // ---- port A write commits (sdram_shim a_wr_*) ----------------------
    input  wire         sn_v,
    input  wire [23:0]  sn_addr,
    input  wire [ 3:0]  sn_len,

    // ---- probe: the watched line's snoop-kill witness -------------------
    // dbg_watch_a is a guest byte address (core_top's slot-0x06 trig_addr).
    // Every tag write the kill path issues for that address's LINE counts
    // in dbg_sn_kills (16-bit free-running, read as deltas) -- so a moving
    // count while an FDC fill streams the watched buffer proves the port-A
    // commits are reaching the cache's invalidator at all. A frozen count
    // beside a moving slot-0x6c total says the feed lives but never lands
    // on the watched line. The witness is staged into its own always block
    // below -- it observes the kill, never loads it.
    input  wire [19:0]  dbg_watch_a,
    output reg  [15:0]  dbg_sn_kills,

    output wire         busy,           // something is buffered or in flight

    // ---- JTAG write watchpoint ----------------------------------------
    // The store the port-F write buffer just took. Cached stores bypass
    // the chipset bus entirely (no bus cycle ever runs), so core_top's
    // bus-side write watchpoint cannot see them; this pulse is the only
    // witness that side has. Fires when the buffer accepts the store --
    // the F engine below drains the buffer unconditionally, so buffer-take
    // equals an SDRAM write. clk (free clk_chipset) domain, guest byte
    // address, word flag (a0 and a0+1 both land).
    output reg          dbg_wr_v,
    output reg   [19:0] dbg_wr_a0,
    output reg          dbg_wr_two
);

    assign wb_cyc_o = wb_stb_o;

    localparam int LINES = 1 << IDX_BITS;
    // Physical (SDRAM word) address width the cache tags: 21 bits cover
    // the guest megabyte and the ITF shadow, 24 the extended memory.
    localparam int PW = PM286 ? 24 : 21;
    localparam int TAG_BITS = PW - 4 - IDX_BITS;

    // ------------------------------------------------------------------
    // Map
    // ------------------------------------------------------------------
    // Extended memory (PM286). Linear 100000h up is the 80286's memory
    // above the first megabyte, EXT_MB megabytes of it (at most 3), in
    // SDRAM words nothing else in the map uses -- 1 MB pages at 0x200000,
    // 0x300000 and 0x500000 (0x400000 is the font bank, 0x600000 GVRAM page
    // one and the FDD carve-out, 0x800000 the EMS pool; RAM.sv and
    // fdd_ramimg.sv draw the same map). It is only ever the CPU's, so it is
    // always cached -- cache_en, which the ITF bank drops, covers only the
    // chipset-visible megabyte. Above EXT_MB is a hole: reads FF, writes
    // vanish, nothing aliases into the low megabyte (the ITF and HIMEM size
    // memory by exactly that miscompare).
    function automatic logic ext_a(input logic [23:0] a);
        ext_a = PM286 && (a[23:20] != 4'h0);
    endfunction
    function automatic logic hole_a(input logic [23:0] a);
        hole_a = ext_a(a) && (a[23:20] > 4'(EXT_MB));
    endfunction
    function automatic logic cacheable_a(input logic [23:0] a);
        cacheable_a = ext_a(a) ? !hole_a(a)
                    : cache_en && ((a[19:16] < 4'hA) || (a[19:15] >= 5'b11101));
    endfunction
    function automatic logic rom_a(input logic [23:0] a);
        rom_a = !ext_a(a) && ((a[19:16] == 4'hF) || (a[19:15] == 5'b11101));
    endfunction
    // RAM.sv's latch_address for the cached ranges: the shadow bit only
    // ever applies to F8000-FFFFF. Extended memory's pages per the map above.
    function automatic logic [PW-1:0] phys_of(input logic [23:0] a, input logic sh);
        logic [23:0] p;
        p = {3'b000, sh & (a[19:15] == 5'b11111), a[19:0]};
        if (ext_a(a))
            p[23:20] = (a[23:20] == 4'h1) ? 4'h2 : (a[23:20] == 4'h2) ? 4'h3 : 4'h5;
        phys_of = p[PW-1:0];
    endfunction
    function automatic logic [IDX_BITS-1:0] idx_of(input logic [PW-1:0] p);
        idx_of = p[4 +: IDX_BITS];
    endfunction
    function automatic logic [TAG_BITS-1:0] tag_of(input logic [PW-1:0] p);
        tag_of = p[PW-1 -: TAG_BITS];
    endfunction
    function automatic logic pit_port(input logic [15:0] a);
        pit_port = ((a & 16'hFFF9) == 16'h0071)
                || (a[15:3] == 13'h07FB && a[0]);   // 3FD9-3FDF odd
    endfunction

    // An access is cached when every byte of it is.
    wire [23:0] wr_a1 = wr_addr + 24'd1;
    // The second byte's MAP class without the 24-bit carry chain: every
    // map boundary is 32 KB aligned, so a+1 is in a's region unless
    // a[14:0] = 7FFF, and then in the region starting at a[23:15] + 1.
    // (The full a+1 sat on the CPU clock's critical path, microcode ->
    // execute's address add -> this -> the combine-buffer enables.)
    function automatic logic [23:0] reg1_of(input logic [23:0] a);
        reg1_of = (a[14:0] == 15'h7FFF) ? {a[23:15] + 9'd1, 15'h0000} : a;
    endfunction
    wire [23:0] rd_a1 = rd_addr + 24'd1;
    wire [23:0] ld_a1 = ld_addr;
    wire wr_cached = !wr_io && cacheable_a(wr_addr)
                  && (!wr_word || cacheable_a(reg1_of(wr_addr)));
    // A store that touches the hole goes nowhere (a word straddling into it
    // is dropped whole: its low byte would land in another page's SDRAM).
    wire wr_hole   = !wr_io && (hole_a(wr_addr) || (wr_word && hole_a(reg1_of(wr_addr))));

    // ------------------------------------------------------------------
    // Tag and data RAM (M10K): one read port each for the lookup, one write
    // port each. Tags are {valid, tag}.
    // ------------------------------------------------------------------
    wire [TAG_BITS:0]    t_q;
    wire [127:0]         d_q;

    reg                  t_we;
    reg  [IDX_BITS-1:0]  t_wa;
    reg  [TAG_BITS:0]    t_wd;
    reg                  d_we;
    reg  [IDX_BITS-1:0]  d_wa;
    reg  [15:0]          d_be;
    reg  [127:0]         d_wd;
    reg  [IDX_BITS-1:0]  look_idx;      // combinational: what to read this edge

    // The tag RAM's byte lanes are 8 bits (altsyncram's byte_size takes 8
    // or 9 here, and the 21-bit map's {valid, tag} is exactly 8). The 24-bit
    // PM286 map's 11-bit {valid, tag} rides two lanes, zero-padded to 16.
    localparam int TLANES = (TAG_BITS + 1 > 8) ? 2 : 1;
    wire [8*TLANES-1:0] t_q_w;
    z86_cache_ram #(.AW(IDX_BITS), .BYTES(TLANES), .BW(8)) u_tags (
        .clk(clk), .we(t_we), .waddr(t_wa), .be({TLANES{1'b1}}),
        .wdata((8*TLANES)'(t_wd)),
        .raddr(look_idx), .q(t_q_w));
    assign t_q = t_q_w[TAG_BITS:0];
    z86_cache_ram #(.AW(IDX_BITS), .BYTES(16), .BW(8)) u_data (
        .clk(clk), .we(d_we), .waddr(d_wa), .be(d_be), .wdata(d_wd),
        .raddr(look_idx), .q(d_q));

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    localparam [3:0] S_FLUSH = 4'd0,
                     S_IDLE  = 4'd1,
                     S_CMP   = 4'd2,    // lookup result on t_q/d_q
                     S_FILL  = 4'd3,    // waiting for a line fill
                     S_SERVE = 4'd4,    // serve from the filled line
                     S_WLD   = 4'd5,    // Wishbone line load
                     S_WRD1  = 4'd6,
                     S_WRD2  = 4'd7,
                     S_WWR1  = 4'd8,
                     S_WWR2  = 4'd9,
                     S_W5F   = 4'd10,   // OUT 5Fh delay
                     S_PACE  = 4'd11;   // paced hit: result held, bus time owed
    reg  [3:0]  st;

    // ---- Paced hits -----------------------------------------------------
    // At the 286 settings the cache is a latency hider, not a speedup: a
    // VX21's memory answers within its 2-clock bus cycle (Ts+Tc, plus the
    // configured waits), and the SDRAM behind the bridge cannot -- a
    // Wishbone pair measured ~7.7 CPU clocks of port arbitration and
    // CAS round trip. A hit answers in a clk, so the access is priced
    // instead: pdebt is loaded with the bus time the access stands for
    // when it is accepted, counts down one per 286 clock, and the
    // handshake (ld_ack, rd_ready, wr_ready) is held in S_PACE until it
    // runs out. A miss's fill usually outlasts the debt and costs its
    // own time -- max(real, 286), never less than the metal. Nothing new
    // is accepted while debt is owed: the 286 BIU runs one cycle at a
    // time, and a line load is the words from the requested one to the
    // line's end (what the uncached S_WLD fetches), each a full cycle.
    reg  [5:0]  pdebt;
    reg         wr_owed;                // paced store buffered, wr_ready owed
    reg  [1:0]  pk;                     // what S_PACE completes (K_LD/K_RD)
    // Line loads deliver critical word first: the fetch gets the line once
    // its FIRST word's cycle is paid, and the rest of the line's words are
    // owed afterwards as a prefetch tail (ld_tail) -- the bus stays busy
    // for them, so the next sequential line still waits, exactly as a
    // 286's BIU streams one word per cycle. The tail yields, as the BIU's
    // prefetch does, to an EU access or a branch's out-of-line load: it
    // is cut to the word in flight. (Without this a taken branch waited
    // for the whole line tail before its first instruction could issue.)
    reg  [5:0]  ptail;
    reg         ld_tail;
    reg  [15:0] ld_next;                // the line a sequential load asks for
    wire [2:0]  p_rcyc = 3'd2 + {1'b0, pace_rd_wait};
    wire [2:0]  p_wcyc = 3'd2 + {1'b0, pace_wr_wait};
    reg  [3:0]  xdebt;                  // REP iteration clocks beyond the bus (rep_x)
    wire        p_busy = pace && (pdebt != 6'd0 || xdebt != 4'd0);
    // p_rcyc - 1, registered (it only moves with the speed setting): the
    // subtract inside S_IDLE's decision is the cone shape Quartus' S2T died
    // on (CI 42049924286).
    reg  [5:0]  p_yld;
    always @(posedge clk) p_yld <= {3'd0, p_rcyc} - 6'd1;
    function automatic logic vram_a(input logic [23:0] a);
        vram_a = !dx[3] && !ext_a(a) && ((a[19:15] == 5'b10101) || (a[19:16] == 4'hB)
                            || (pace_vwait[4] && a[19:15] == 5'b11100));
    endfunction
    wire [5:0]  p_vw = {2'd0, pace_vwait[3:0]};

    localparam [1:0] K_LD = 2'd0, K_RD = 2'd1, K_WR = 2'd2;
    reg  [1:0]  k;                      // what the lookup is for
    reg         part;                   // 0: byte at a, 1: byte at a+1 (straddle)
    reg  [23:0] c_a;                    // the access's address
    reg         c_word;
    reg  [15:0] c_wd;                   // write data
    reg  [7:0]  lo_byte;                // first half of a straddled read
    reg  [IDX_BITS-1:0] flush_i;

    // A read pulse is captured: rd may land while something else runs.
    reg         rd_pend;
    reg  [23:0] rd_a;
    reg         rd_isio, rd_isw;

    reg  [2:0]  ld_i;
    reg  [19:0] ld_base;
    reg  [7:0]  io_rec;                 // clk since the last I/O cycle, saturating
    reg  [4:0]  w5f;

    // Lookups the snoop raced: a tag write at the edge the lookup read, or
    // during the compare, of the same index makes it a miss. Two edges
    // matter because the tag write is registered: sn_ours's edge only
    // LOADS t_we/t_wa (the RAM write lands the edge after), so a lookup
    // that read the tags on sn_ours's own edge sampled the pre-invalidate
    // contents and would otherwise hit stale -- the FDC-DMA window
    // (tb_z86_cache_snoop T6). The t_we term covers the next edge, where
    // the write lands in the same edge the lookup read (old data on a
    // read-during-write); sn2_v re-queues its write the same way.
    reg         kill;

    // A parked EVICTION. The fill path now clears the victim's tag at the
    // MISS edge, not at the install: 2aff963's install defers its valid
    // bit whenever a kill shares its edge, and the deferred install left
    // the index's OLD tag -- still valid -- over the NEW line's installed
    // data. The evicted line's address then "hit" and served the filler's
    // bytes, and no commit ever killed it (nothing writes the victim):
    // tb_z86_cache_snoop T10, and on metal every deferred install under a
    // streaming DMA corrupts whatever 16 KB alias lives at the index.
    // Clearing at the miss edge means the tag never lies: it is invalid
    // from the eviction decision until the fresh install lands (or defers,
    // which now just leaves it invalid). The write has to share t_we with
    // the snoop, so a busy edge parks it here and retries -- like sn2_v,
    // ahead of the snoop's assignments so a kill never loses its slot.
    reg         park_v;
    reg  [IDX_BITS-1:0] park_i;

    // ---- write buffer and port F --------------------------------------
    reg         wb_full;                // a store waits for port F
    reg  [PW-1:0] wb_p0, wb_p1;         // physical address of each byte
    reg  [7:0]  wb_b0, wb_b1;
    reg         wb_two;                 // a word (two bytes)
    localparam [1:0] F_IDLE = 2'd0, F_REQ = 2'd1, F_RUN = 2'd2;
    reg  [1:0]  fs;
    reg         f_isfill;
    reg         f_wpart;                // second single-byte write of a split word
    reg  [3:0]  f_beat;
    reg  [127:0] lb;                    // the line being filled
    reg         fill_req;               // the FSM wants a fill of fill_p
    reg  [PW-1:0] fill_p;
    reg         fill_live;              // its result is still wanted
    reg         fill_done;              // lb holds fill_p's line

    // ---- store combining --------------------------------------------
    // Every store used to be its own port-F transaction -- ACTIVATE, two
    // beats, PRECHARGE, ~18 clk -- so a run of stores (REP STOSW, a stack
    // frame, a struct fill) went at port F's rate, 1.4-1.6x a 286's. With
    // WCOMB the stores gather in a one-line buffer as long as they extend
    // one contiguous byte range [cb_lo, cb_hi] of the same line, and the
    // range leaves as ONE burst: the data is served by byte, combinational
    // on sdram_mp's p_wcnt (f_wcnt), like every other burst writer here.
    // The buffer goes out when a store will not merge, after CB_AGE idle
    // clocks, ahead of any fill (port F's order: the store, then the fill),
    // and ahead of any uncached access (busy covers it -- an OUT that
    // starts a DMA never passes a store). Reads stay coherent the way they
    // always were: a store patches its cached line on the way in.
    // TWO such buffers, so a run of stores never waits out a burst: while
    // one is going out on port F, the other takes the next line (REP STOSW
    // and MOVSW paid ~22 chipset clocks at every line change). cb_act is
    // the one stores merge into; the other is draining or empty. A store
    // into the other's line waits for it to leave, so no byte is ever held
    // in both (an older copy can never land after a newer one).
    reg  [1:0]  cb_v;                   // the buffer holds a range
    reg  [1:0]  cb_fl;                  // ... and is being written out
    reg  [1:0]  cb_want;                // it should leave now
    reg  [PW-5:0] cb_ln [0:1];          // physical line, phys[PW-1:4]
    reg  [127:0] cb_d  [0:1];
    reg  [3:0]  cb_lo  [0:1];
    reg  [3:0]  cb_hi  [0:1];
    reg  [5:0]  cb_age [0:1];
    reg         cb_act;                 // the merging buffer
    reg         cb_fli;                 // the buffer port F is writing out
    // A WHOLE line leaving a bank is installed in the cache when its burst
    // is done -- every byte is known and now equals memory -- so reading
    // freshly written data (REP MOVSW out of a buffer REP STOSW just
    // filled) hits instead of missing through a fill: stores are otherwise
    // no-allocate. cb_kill: a port-A commit touched the line's index while
    // the bank held it, so memory may be newer -- no install. The install
    // only takes an edge where nothing else uses the tag/data write ports.
    reg  [1:0]  cb_kill;
    wire [IDX_BITS-1:0] cb_fidx = idx_of({cb_ln[cb_fli], 4'h0});
    wire [TAG_BITS-1:0] cb_ftag = tag_of({cb_ln[cb_fli], 4'h0});
    reg  [15:0] f_wdata0_r, f_wdata1_r;
    wire [3:0]  cb_ix   = cb_lo[cb_fli] + f_wcnt[3:0];
    wire [127:0] cb_fd  = cb_d[cb_fli];
    wire [7:0]  cb_byte = cb_fd[{cb_ix, 3'b000} +: 8];
    wire        cb_flng = WCOMB && (cb_fl != 2'b00);
    assign f_wdata0 = cb_flng ? {8'h00, cb_byte} : f_wdata0_r;
    assign f_wdata1 = cb_flng ? {8'h00, cb_byte} : f_wdata1_r;

    assign busy = wb_full || (WCOMB && cb_v != 2'b00) || (fs != F_IDLE) || wb_stb_o;

    // Current lookup's address (the byte this part touches) and line.
    wire [23:0] c_ab  = part ? c_a + 24'd1 : c_a;
    wire [PW-1:0] c_p = phys_of(c_ab, bios_shadow);
    wire [3:0]  c_off = c_ab[3:0];
    // A word whose second byte is in the next line.
    wire        c_straddle = c_word && (c_a[3:0] == 4'hF);

    // ---- what the next edge's RAM read should address ------------------
    // IDLE picks the request (same priority as below), CMP a straddle's
    // second half. Anything else reads the current line again; harmless.
    // wr_ready is held until the ce edge the core takes it on; by the edge
    // after, wr_valid is already the core's next store (or low).
    wire wr_pend   = wr_valid && !wr_ready && !wr_owed;
    wire ld_pend   = (ld_req ^ ld_ack);
    wire rd_now    = rd && ce;
    wire rd_any    = rd_pend || rd_now;
    wire [23:0] rd_cur_a  = rd_now ? rd_addr : rd_a;
    wire        rd_cur_io = rd_now ? rd_io   : rd_isio;
    wire        rd_cur_w  = rd_now ? rd_word : rd_isw;
    wire rd_cached = !rd_cur_io && cacheable_a(rd_cur_a)
                  && (!rd_cur_w || cacheable_a(reg1_of(rd_cur_a)));
    wire rd_hole   = !rd_cur_io && (hole_a(rd_cur_a)
                  || (rd_cur_w && hole_a(reg1_of(rd_cur_a))));
    wire ld_cached = cacheable_a(ld_addr);
    wire ld_hole   = hole_a(ld_addr);

    always @* begin
        look_idx = idx_of(c_p);
        if (st == S_IDLE) begin
            if (wr_pend)       look_idx = idx_of(phys_of(wr_addr, bios_shadow));
            // same order as S_IDLE below: a pending read ahead of a load
            else if (rd_any)   look_idx = idx_of(phys_of(rd_cur_a, bios_shadow));
            else if (ld_pend)  look_idx = idx_of(phys_of(ld_addr, bios_shadow));
        end else if ((st == S_CMP || st == S_SERVE) && c_straddle && !part)
            look_idx = idx_of(phys_of(c_a + 24'd1, bios_shadow));
    end

    // ---- snoop: clear the line(s) a port A write lands in ---------------
    // A two-word write can end in the next line; that one is cleared on the
    // following edge.
    reg         sn2_v;
    reg  [IDX_BITS-1:0] sn2_i;
    wire        sn_ours  = sn_v && (sn_addr[23:21] == 3'b000);
    wire [20:0] sn_end   = sn_addr[20:0] + {17'd0, sn_len};
    wire [IDX_BITS-1:0] sn_i0 = idx_of(PW'(sn_addr[20:0]));
    wire [IDX_BITS-1:0] sn_i1 = idx_of(PW'(sn_end));
    // The watched line, in the same physical terms the kill uses. phys_of
    // only ever touches bit 20 and idx_of reads [13:4], so this is a pure
    // bit-slice of dbg_watch_a -- but kept as the functions so the two
    // cannot drift apart.
    wire [IDX_BITS-1:0] sn_wp_i = idx_of(phys_of({4'h0, dbg_watch_a}, bios_shadow));

    // Probe witness, STAGED and fully isolated from the coherence cone:
    // stage 1 registers the facts of each tag write the kill path issues
    // (valid + index -- sn_ours wins a collision, exactly the priority the
    // assignments in the main block give the write port); stage 2 is a
    // plain register-to-register compare against the REGISTERED watched
    // index and a free-running 16-bit count. Nothing here loads sn_ours/
    // sn2_v/t_we or shares a comparator with the lookup -- the shape CI's
    // Quartus died on (S2T internal error, runs 39543865833/39546532071)
    // had the compare live in the main block; this is deliberately dull.
    // The count is one clk behind the kill it counts -- meaningless for a
    // counter. Deltas mod 65536, like core_top's sn_v_cnt.
    reg                  snq_v;
    reg  [IDX_BITS-1:0]  snq_i;
    reg  [IDX_BITS-1:0]  snq_wi;
    always @(posedge clk) begin
        snq_v <= sn_ours | sn2_v;
        if (sn_ours)      snq_i <= sn_i0;
        else if (sn2_v)   snq_i <= sn2_i;
        snq_wi <= sn_wp_i;
        if (snq_v && snq_i == snq_wi)
            dbg_sn_kills <= dbg_sn_kills + 16'd1;
    end

    // The snoop also guards the compare combinationally: a commit arriving
    // on the very edge the hit is judged is already in the SDRAM (sn_v is
    // sdram_shim's a_wr_* completion pulse), but the registered kill only
    // lands the edge after -- without this term that edge hit stale
    // (tb_z86_cache_snoop T6 off=0). look_idx equals idx_of(c_p) in CMP.
    wire        sn_hit = (sn_ours && (sn_i0 == look_idx))
                      || (sn2_v  && (sn2_i == look_idx));
    wire        hit = t_q[TAG_BITS] && (t_q[TAG_BITS-1:0] == tag_of(c_p))
                   && !kill && !sn_hit;
    wire [127:0] line = (st == S_SERVE) ? lb : d_q;

    // Byte enables and data for a write hit at c_off (one or two bytes).
    wire        wr_both = c_word && !c_straddle && !part;
    wire [15:0] w_be   = wr_both ? (16'b11 << c_off) : (16'b1 << c_off);
    wire [7:0]  w_byte = part ? c_wd[15:8] : c_wd[7:0];
    // The byte enables pick the lanes, so the data only has to be right in
    // them: replicate instead of shifting (a 128-bit barrel shifter was
    // a good part of this module's ALMs). A word's low byte sits at c_off,
    // so the pair is laid lo-in-even or lo-in-odd lanes by c_off[0].
    wire [127:0] w_wd  = !wr_both ? {16{w_byte}}
                       : c_off[0] ? {8{c_wd[7:0], c_wd[15:8]}}
                                  : {8{c_wd[15:8], c_wd[7:0]}};

    function automatic [1:0] sel_of(input logic a0, input logic word);
        sel_of = word ? 2'b11 : (a0 ? 2'b10 : 2'b01);
    endfunction

    wire [PW-1:0] wp0 = phys_of(wr_addr, bios_shadow);
    wire [PW-1:0] wp1 = phys_of(wr_a1, bios_shadow);
    wire        cb_shape = WCOMB && !dx[1] && (!wr_word || (wp1 == wp0 + PW'(1) && wp0[3:0] != 4'hF));
    wire [4:0]  w_lo = {1'b0, wp0[3:0]};
    wire [4:0]  w_hi = w_lo + (wr_word ? 5'd1 : 5'd0);
    // An uncached access waiting in S_IDLE: busy holds it until the
    // combine buffer has gone out, and this makes the buffer go now.
    wire        unc_want = (st == S_IDLE)
                        && ((wr_pend && !wr_cached) || (rd_any && !rd_cached)
                            || (ld_pend && !ld_cached));
    // The flush launch, as F_IDLE below decides it. A merge on the launch
    // edge would widen the range after f_addr/f_len latched the old one,
    // and the done that follows clears the buffer: the merged bytes were
    // lost (irq_rep under +pace: REP MOVS copies with holes).
    wire        cb_a = cb_act, cb_b = ~cb_act;
    // flush launch per buffer; the idle one (b) first, then the active one
    wire        cb_due_b = WCOMB && cb_v[cb_b] && !cb_fl[cb_b] && (fs == F_IDLE)
                        && (cb_want[cb_b] || cb_age[cb_b] >= 6'(CB_AGE) || fill_req || unc_want);
    wire        cb_due_a = WCOMB && cb_v[cb_a] && !cb_fl[cb_a] && (fs == F_IDLE)
                        && (cb_want[cb_a] || cb_age[cb_a] >= 6'(CB_AGE) || fill_req || unc_want);
    wire        cb_go    = cb_due_b || cb_due_a;
    wire        cb_gi    = cb_due_b ? cb_b : cb_a;
    // the other buffer still holds this store's line: wait for it to leave
    wire        cb_clash = cb_v[cb_b] && (cb_ln[cb_b] == wp0[PW-1:4]);
    // a merge on the active buffer's flush-launch edge would widen the
    // range after f_len latched (the merged bytes were lost)
    wire        cb_merge = cb_v[cb_a] && !cb_fl[cb_a] && !(cb_go && cb_gi == cb_a)
                        && !cb_clash && (cb_ln[cb_a] == wp0[PW-1:4])
                        && (w_lo <= {1'b0, cb_hi[cb_a]} + 5'd1)
                        && (w_hi + 5'd1 >= {1'b0, cb_lo[cb_a]});
    wire        cb_new_a = !cb_v[cb_a] && !cb_clash;
    wire        cb_swap  = cb_v[cb_a] && !cb_merge && !cb_v[cb_b];
    wire        acc_cb = cb_shape && !wb_full && (cb_new_a || cb_merge || cb_swap);
    // The whole-line install of a bank whose burst ends this edge (F_RUN
    // below). Its tag/data writes land on the NEXT edge, after any lookup
    // S_IDLE starts on this one has already read the old occupant -- and
    // the kill term only covers lookups whose read shares the landing
    // edge. A store that hit the old occupant (another line at the same
    // index) then patched its bytes into the freshly installed line, under
    // the installed line's valid tag. So S_IDLE starts nothing on an
    // install edge; the lookup on the next edge is caught by kill.
    // S_IDLE's guard is the superset "a combine burst ends this edge" --
    // one clock per burst, and a small cone (the full cb_inst term in the
    // S_IDLE decision is the shape Quartus' S2T died on).
    wire        cb_endf = cb_flng && f_done && (fs == F_RUN);
    wire        cb_inst = WCOMB && (fs == F_RUN) && f_done && !f_isfill && cb_flng
                       && cb_lo[cb_fli] == 4'h0 && cb_hi[cb_fli] == 4'hF
                       && !cb_kill[cb_fli] && cache_en && !dx[2]
                       && st == S_IDLE && !sn_ours && !sn2_v && !park_v;
    wire        acc_wb = !cb_shape && !wb_full && !(WCOMB && cb_v != 2'b00);

    always @(posedge clk) begin
        for (int i = 0; i < 2; i++) begin
            if (WCOMB && cb_v[i] && !cb_fl[i] && cb_age[i] != 6'h3F)
                cb_age[i] <= cb_age[i] + 6'd1;
            if (WCOMB && cb_v[i] && sn_ours
                && (sn_i0 == idx_of({cb_ln[i], 4'h0}) || sn_i1 == idx_of({cb_ln[i], 4'h0})))
                cb_kill[i] <= 1'b1;
        end
        t_we <= 1'b0;
        d_we <= 1'b0;
        dbg_wr_v <= 1'b0;
        if (ce) wr_ready <= 1'b0;
        if (io_rec != 8'hFF) io_rec <= io_rec + 8'd1;
        if (pace_ce && pdebt != 6'd0) pdebt <= pdebt - 6'd1;
        if (!pace) xdebt <= 4'd0;
        // after the bus debt, not beside it: the two add up
        else xdebt <= xdebt + {1'b0, rep_x} - {3'd0, pace_ce && xdebt != 4'd0 && pdebt == 6'd0};
        if (!pace) pdebt <= 6'd0;
        if (!p_busy) ld_tail <= 1'b0;
        // A paced store inside a REP string loop is answered at once: the
        // bus cycle runs on while the microcode goes round, and only the
        // NEXT access waits its debt out (S_IDLE's p_busy). Holding the
        // ready for the debt put the core's own turnaround after it (REP
        // MOVSW: read 9 + write 8 + 5 clocks of turnaround per word, 1.26x
        // the data sheet); each iteration's non-bus clocks come from
        // execute's rep_x instead. Other stores keep the held ready: posted,
        // the next instruction's line load got in ahead of the next store
        // (mov [m16],ax x8 went 1.05 -> 1.17).
        if (wr_owed && ((STORE_POST && rep_on) || !p_busy)) begin
            wr_ready <= 1'b1;
            wr_owed  <= 1'b0;
        end

        // ---------------- snoop (every edge, highest priority) ----------
        // t_we/d_we are registered: the write they carry lands on THIS edge,
        // and a read of the same index on this edge still sees the old
        // contents. A tag write racing the lookup makes it a miss; a data
        // write is never raced -- IDLE waits it out (below).
        kill <= (t_we    && (t_wa  == look_idx))
              | (sn_ours && (sn_i0 == look_idx))
              | (sn2_v   && (sn2_i == look_idx));
        // A second-line kill that loses the single tag-write slot to a new
        // sn_ours stays armed and retries the next edge instead of being
        // dropped (back-to-back pulses, T7): sn_ours keeps the slot, sn2_v
        // keeps its address. Two straddles arriving within one edge would
        // still be more than the one pending slot holds; the serialized
        // shim spaces port-A commits at least two edges apart, so that
        // never arises. The parked eviction retries the same way, one step
        // further back: the snoop's kills outrank it, so it can never
        // steal the slot -- it only waits for a kill-free edge, and a fill
        // gives it thirty-odd.
        if (park_v && !sn2_v && !sn_ours) begin
            t_we   <= 1'b1;
            t_wa   <= park_i;
            t_wd   <= '0;
            park_v <= 1'b0;
        end
        if (sn2_v && !sn_ours) begin
            t_we <= 1'b1; t_wa <= sn2_i; t_wd <= '0;
            sn2_v <= 1'b0;
        end
        if (sn_ours) begin
            t_we <= 1'b1; t_wa <= sn_i0; t_wd <= '0;
            sn2_v <= sn2_v | (sn_i1 != sn_i0);
            if (!sn2_v) sn2_i <= sn_i1;
        end

        // ---------------- port F engine (not reset by the CPU) ----------
        // A transaction already granted has to run to its done pulse, so
        // a CPU reset only drops the fill's result (fill_live).
        case (fs)
          F_IDLE:
            if (cb_go) begin
                f_req    <= 1'b1;
                f_we     <= 1'b1;
                f_isfill <= 1'b0;
                f_addr   <= 24'({cb_ln[cb_gi], cb_lo[cb_gi]});
                f_len    <= cb_hi[cb_gi] - cb_lo[cb_gi];
                cb_fl[cb_gi] <= 1'b1;
                cb_fli   <= cb_gi;
                fs <= F_REQ;
            end else if (wb_full) begin
                f_req    <= 1'b1;
                f_we     <= 1'b1;
                f_isfill <= 1'b0;
                // A word goes as one two-word burst unless its halves are
                // not adjacent words in the same SDRAM column.
                if (!f_wpart) begin
                    f_addr   <= 24'(wb_p0);
                    f_wdata0_r <= {8'h00, wb_b0};
                    f_wdata1_r <= {8'h00, wb_b1};
                    f_len    <= (wb_two && wb_p1 == wb_p0 + PW'(1) && wb_p0[8:0] != 9'h1FF)
                              ? 4'd1 : 4'd0;
                end else begin
                    f_addr   <= 24'(wb_p1);
                    f_wdata0_r <= {8'h00, wb_b1};
                    f_len    <= 4'd0;
                end
                fs <= F_REQ;
            end else if (fill_req) begin
                f_req    <= 1'b1;
                f_we     <= 1'b0;
                f_isfill <= 1'b1;
                f_addr   <= 24'({fill_p[PW-1:4], 4'h0});
                f_len    <= 4'd15;
                f_beat   <= 4'd0;
                fill_req <= 1'b0;
                fs <= F_REQ;
            end
          F_REQ: if (f_ack) begin f_req <= 1'b0; fs <= F_RUN; end
          F_RUN: begin
            if (f_rvalid && f_isfill) begin
                lb[8*f_beat +: 8] <= f_rdata[7:0];
                f_beat <= f_beat + 4'd1;
            end
            if (f_done) begin
                fs <= F_IDLE;
                if (f_isfill) begin
                    if (fill_live) fill_done <= 1'b1;
                end else if (cb_flng) begin
                    cb_fl[cb_fli]   <= 1'b0;
                    cb_v[cb_fli]    <= 1'b0;
                    cb_want[cb_fli] <= 1'b0;
                    if (cb_inst) begin
                        d_we <= 1'b1; d_wa <= cb_fidx; d_be <= 16'hFFFF; d_wd <= cb_fd;
                        t_we <= 1'b1; t_wa <= cb_fidx; t_wd <= {1'b1, cb_ftag};
                    end
                end else if (wb_two && !f_wpart && f_len == 4'd0) begin
                    f_wpart <= 1'b1;            // second byte next
                end else begin
                    f_wpart <= 1'b0;
                    wb_full <= 1'b0;
                end
            end
          end
          default: fs <= F_IDLE;
        endcase

        // ---------------- the request FSM -------------------------------
        if (rd_now) begin
            rd_pend  <= 1'b1;
            rd_a     <= rd_addr;
            rd_isio  <= rd_io;
            rd_isw   <= rd_word;
            rd_ready <= 1'b0;
        end

        if (reset) begin
            st        <= S_FLUSH;
            flush_i   <= '0;
            ld_ack    <= 1'b0;          // see fetch.sv's reset: both toggles to 0
            rd_ready  <= 1'b1;
            rd_pend   <= 1'b0;
            wr_ready  <= 1'b0;
            wb_stb_o  <= 1'b0;
            wb_we_o   <= 1'b0;
            wb_tga_o  <= 1'b0;
            wb_sel_o  <= 2'b00;
            wb_adr_o  <= 19'h0;
            wb_dat_o  <= 16'h0;
            fill_req  <= 1'b0;
            fill_live <= 1'b0;
            fill_done <= 1'b0;
            io_rec    <= 8'hFF;
            park_v    <= 1'b0;          // S_FLUSH clears every tag anyway
            pdebt     <= 6'd0;
            xdebt     <= 4'd0;
            wr_owed   <= 1'b0;
            ld_tail   <= 1'b0;
        end else case (st)
          S_FLUSH: begin
            // Clear every tag. The snoop keeps the cache coherent on its
            // own; this only makes a reset a clean slate (and covers the
            // power-up contents in simulation).
            if (!sn_ours && !sn2_v) begin
                t_we <= 1'b1; t_wa <= flush_i; t_wd <= '0;
                flush_i <= flush_i + 1'b1;
                if (flush_i == IDX_BITS'(LINES - 1)) st <= S_IDLE;
            end
          end

          S_IDLE: begin
            part <= 1'b0;
            if (d_we || p_busy || cb_endf) begin
                // a line patch lands this edge, or the last paced access
                // still owes bus time -- a prefetch tail yields to an EU
                // access or an out-of-line (branch) load after its word
                // (the yield waits out the prefetch cycle in flight, which
                // is half done on average: p_rcyc - 1)
                if (ld_tail && pdebt > p_yld
                    && (wr_pend || rd_any
                        || (ld_pend && ld_addr[19:4] != ld_next)))
                    pdebt <= p_yld;
                // a line patch lands this edge: look it up on the next
            end else if (wr_pend) begin
                if (wr_hole) begin
                    // above extended memory: the store vanishes
                    wr_ready <= 1'b1;
                end else if (wr_cached) begin
                    if (bios_protect && rom_a(wr_addr)) begin
                        // A protected ROM write goes nowhere -- but its
                        // bus cycle still runs.
                        if (pace) begin
                            wr_owed <= 1'b1;
                            pdebt   <= {3'd0, p_wcyc};
                        end else
                            wr_ready <= 1'b1;
                    end else if (acc_cb || acc_wb) begin
                        if (acc_cb) begin
                            // the buffer this store lands in: the active one,
                            // or the idle one on a swap (the active one then
                            // leaves at once)
                            automatic logic t = cb_swap ? cb_b : cb_a;
                            cb_v[t]   <= 1'b1;
                            cb_ln[t]  <= wp0[PW-1:4];
                            if (!cb_merge) cb_kill[t] <= 1'b0;
                            cb_lo[t]  <= cb_merge ? ((w_lo[3:0] < cb_lo[t]) ? w_lo[3:0] : cb_lo[t])
                                                  : w_lo[3:0];
                            cb_hi[t]  <= cb_merge ? ((w_hi[3:0] > cb_hi[t]) ? w_hi[3:0] : cb_hi[t])
                                                  : w_hi[3:0];
                            cb_d[t][{wp0[3:0], 3'b000} +: 8] <= wr_data[7:0];
                            if (wr_word)
                                cb_d[t][{wp0[3:0] + 4'd1, 3'b000} +: 8] <= wr_data[15:8];
                            cb_age[t] <= 6'd0;
                            if (cb_swap) begin
                                cb_act <= cb_b;
                                // A store into the line the leaving bank
                                // holds (it is flushing, or launches on
                                // this edge, so it cannot merge): the store
                                // patches the cached line below, and the
                                // leaving bank's install would put its
                                // older bytes back over it under a valid
                                // tag. Memory ends right (this bank goes
                                // out after it); the cache must not.
                                if (cb_ln[cb_a] == wp0[PW-1:4]) cb_kill[cb_a] <= 1'b1;
                                if (!cb_fl[cb_a]) cb_want[cb_a] <= 1'b1;
                            end
                        end else begin
                            wb_full  <= 1'b1;
                            wb_p0    <= wp0;
                            wb_p1    <= wp1;
                            wb_b0    <= wr_data[7:0];
                            wb_b1    <= wr_data[15:8];
                            wb_two   <= wr_word;
                            f_wpart  <= 1'b0;
                        end
                        if (pace) begin
                            wr_owed <= 1'b1;
                            pdebt   <= (wr_word && wr_addr[0])
                                     ? {2'd0, p_wcyc, 1'b0}
                                     : {3'd0, p_wcyc};
                        end else
                            wr_ready <= 1'b1;
                        // Watchpoint witness: this store now owns the
                        // port-F buffer and will reach the SDRAM.
                        dbg_wr_v   <= 1'b1;
                        dbg_wr_a0  <= wr_addr[19:0];
                        dbg_wr_two <= wr_word;
                        // ...and update the line if it is cached.
                        k      <= K_WR;
                        c_a    <= wr_addr;
                        c_word <= wr_word;
                        c_wd   <= wr_data;
                        st     <= S_CMP;
                    end else if (WCOMB) begin
                        // a store that cannot land yet: move things along
                        if (cb_v[cb_a] && !cb_fl[cb_a]) cb_want[cb_a] <= 1'b1;
                        if (cb_v[cb_b] && !cb_fl[cb_b]) cb_want[cb_b] <= 1'b1;
                    end
                end else if (ce && !busy
                             && !(wr_io && pit_port(wr_addr[15:0]) && io_rec < PIT_GAP[7:0])) begin
                    // Word at an odd address: the odd byte first, its data
                    // (the low byte of the word) in lane [15:8].
                    wb_adr_o <= wr_addr[19:1];
                    wb_sel_o <= sel_of(wr_addr[0], wr_word && !wr_addr[0]);
                    wb_dat_o <= wr_addr[0] ? {wr_data[7:0], 8'h00}
                              : (wr_word ? wr_data : {8'h00, wr_data[7:0]});
                    wb_we_o  <= 1'b1;
                    wb_tga_o <= wr_io;
                    wb_stb_o <= 1'b1;
                    st       <= S_WWR1;
                    // A graphics-VRAM store occupies the bus for its cycles
                    // plus the np21w wait: the store itself completes when
                    // the pair does, and the NEXT access waits out the rest
                    // (S_IDLE's p_busy) -- the CPU-side gap between stores
                    // overlaps the wait, as the 286's next-cycle setup does.
                    // (Holding the store's own ready instead added that gap
                    // on top: a GRCG TDW word went from 1.12x to 1.42x.)
                    if (pace && !wr_io && vram_a(wr_addr))
                        pdebt <= ((wr_word && wr_addr[0]) ? {2'd0, p_wcyc, 1'b0}
                                                          : {3'd0, p_wcyc}) + p_vw;
                end
            // Data reads before line loads: a 286's EU cycles take the
            // bus ahead of the BIU's prefetch, so a pop or operand read
            // never queues behind a code line. With uncached fetch at the
            // paced settings that wait was a whole line load per access.
            end else if (ld_pend && !rd_any) begin
                if (ld_hole) begin
                    ld_data <= '1;
                    ld_ack  <= ~ld_ack;
                end else if (ld_cached) begin
                    k    <= K_LD;
                    c_a  <= {ld_addr[19:4], 4'h0};
                    c_word <= 1'b0;
                    st   <= S_CMP;
                    // the requested word now, the rest of the line as a
                    // tail after the hand-off (see ld_tail)
                    pdebt <= !pace ? 6'd0
                           : dx[0] ? (6'd8 - {3'd0, ld_addr[3:1]}) * {3'd0, p_rcyc}
                           : {3'd0, p_rcyc};
                    // The tail is what the 286's BIU would fetch on behind
                    // the word asked for -- but its queue holds six bytes,
                    // so at most three words, not the rest of our line
                    // (a CALL/RET target paid up to seven words of tail
                    // the 286 never fetches before the next transfer).
                    // (min(7 - w, 3) is ~w[1:0] for w >= 4, else 3)
                    ptail <= (pace && !dx[0])
                           ? {4'd0, ld_addr[3] ? ~ld_addr[2:1] : 2'd3} * {3'd0, p_rcyc}
                           : 6'd0;
                end else if (ce && !busy) begin
                    // Uncached: start at the word the fetch asked for. A
                    // 286's BIU fetches from the branch target on, never
                    // the bytes below it; z86's fetch buffer records the
                    // half's first valid byte (buf_lo) and reloads a
                    // branch that lands under it. Paced settings price
                    // every word as a full bus pair, so the line head
                    // was pure overcharge on every redirect.
                    ld_base  <= {ld_addr[19:4], 4'b0};
                    ld_i     <= ld_addr[3:1];
                    wb_adr_o <= ld_addr[19:1];
                    wb_sel_o <= 2'b11;
                    wb_we_o  <= 1'b0;
                    wb_tga_o <= 1'b0;
                    wb_stb_o <= 1'b1;
                    st       <= S_WLD;
                end
            end else if (rd_any) begin
                if (rd_hole) begin
                    // above extended memory: open bus
                    rd_data  <= 16'hFFFF;
                    rd_pend  <= 1'b0;
                    rd_ready <= 1'b1;
                end else if (rd_cached) begin
                    k      <= K_RD;
                    pdebt  <= !pace ? 6'd0
                            : (rd_cur_w && rd_cur_a[0]) ? {2'd0, p_rcyc, 1'b0}
                            : {3'd0, p_rcyc};
                    c_a    <= rd_cur_a;
                    c_word <= rd_cur_w;
                    rd_a   <= rd_cur_a;
                    rd_isw <= rd_cur_w;
                    rd_isio <= 1'b0;
                    st     <= S_CMP;
                end else if (ce && !busy
                             && !(rd_cur_io && pit_port(rd_cur_a[15:0]) && io_rec < PIT_GAP[7:0])) begin
                    // rd may be this very edge's pulse: take its operands
                    // live, the capture above lands at the same edge.
                    wb_adr_o <= rd_cur_a[19:1];
                    wb_sel_o <= sel_of(rd_cur_a[0], rd_cur_w && !rd_cur_a[0]);
                    wb_we_o  <= 1'b0;
                    wb_tga_o <= rd_cur_io;
                    wb_stb_o <= 1'b1;
                    st       <= S_WRD1;
                    if (pace && !rd_cur_io && vram_a(rd_cur_a))
                        pdebt <= ((rd_cur_w && rd_cur_a[0]) ? {2'd0, p_rcyc, 1'b0}
                                                            : {3'd0, p_rcyc}) + p_vw;
                end
            end
          end

          // ---------------- cached paths -------------------------------
          S_CMP, S_SERVE: begin
            if (st == S_CMP && !hit) begin
                if (k == K_WR) begin
                    // No allocate: the store is in the write buffer.
                    if (c_straddle && !part) begin part <= 1'b1; st <= S_CMP; end
                    else st <= S_IDLE;
                end else begin
                    fill_req  <= 1'b1;
                    fill_p    <= c_p;
                    fill_live <= 1'b1;
                    fill_done <= 1'b0;
                    st        <= S_FILL;
                    // Evict the index's occupant NOW, not at the install.
                    // The install defers its tag write whenever a kill
                    // shares its edge (T9), and a deferred install used to
                    // leave the OLD tag valid over the NEW data -- the
                    // evicted line served the filler's bytes and nothing
                    // ever killed it (T10). Clearing here means a deferred
                    // install just leaves the tag invalid: one refill, no
                    // lie. The t_we slot belongs to the snoop first, so a
                    // busy edge parks the clear and the retry above lands
                    // it long before any fill completes. Writing '0 can
                    // never undo a kill (both invalidate), so unlike the
                    // install there is no in-flight term to owe.
                    if (!sn_ours && !sn2_v) begin
                        t_we <= 1'b1; t_wa <= idx_of(c_p); t_wd <= '0;
                    end else begin
                        park_v <= 1'b1; park_i <= idx_of(c_p);
                    end
                end
            end else begin
                // A hit, or the line just filled (line = lb).
                case (k)
                  K_LD: begin
                    ld_data <= line;
                    if (p_busy) begin
                        pk <= K_LD;
                        st <= S_PACE;
                    end else begin
                        ld_ack  <= ~ld_ack;
                        pdebt   <= ptail;
                        ld_tail <= (ptail != 6'd0);
                        ld_next <= c_a[19:4] + 16'd1;
                        st      <= S_IDLE;
                    end
                  end
                  K_RD: begin
                    if (!part) begin
                        if (c_straddle) begin
                            lo_byte <= line[8*c_off +: 8];
                            part    <= 1'b1;
                            st      <= S_CMP;
                        end else begin
                            rd_data  <= c_word ? {line[8*(c_off+4'd1) +: 8], line[8*c_off +: 8]}
                                               : {8'h00, line[8*c_off +: 8]};
                            if (p_busy) begin
                                pk <= K_RD;
                                st <= S_PACE;
                            end else begin
                                rd_pend  <= 1'b0;
                                rd_ready <= 1'b1;
                                st       <= S_IDLE;
                            end
                        end
                    end else begin
                        rd_data  <= {line[8*c_off +: 8], lo_byte};
                        if (p_busy) begin
                            pk <= K_RD;
                            st <= S_PACE;
                        end else begin
                            rd_pend  <= 1'b0;
                            rd_ready <= 1'b1;
                            st       <= S_IDLE;
                        end
                    end
                  end
                  default: begin    // K_WR hit: patch the line
                    d_we <= 1'b1;
                    d_wa <= idx_of(c_p);
                    d_be <= w_be;
                    d_wd <= w_wd;
                    if (c_straddle && !part) begin part <= 1'b1; st <= S_CMP; end
                    else st <= S_IDLE;
                  end
                endcase
            end
          end

          S_FILL: if (fill_done) begin
            fill_done <= 1'b0;
            fill_live <= 1'b0;
            // Install the line's DATA always, but its valid bit only when
            // the snoop is issuing NO kill this edge -- any index, not just
            // this line's. t_we/t_wa/t_wd hold one write, and this FSM's
            // assignment sits LATER in the block than the snoop's, so an
            // install that raced a kill for another line used to overwrite
            // it: the commit's line kept its VALID tag over pre-commit data
            // while the snoop feed -- and the witness counter, which counts
            // the feed -- showed the kill as fired. That dropped-kill
            // window is the metal 0xA1-vs-0x38 (tb_z86_cache_snoop T9):
            // the tag was believed invalidated, yet stale data served.
            // Deferring this line's valid bit costs one refill, nothing
            // else. The in-flight term keeps covering a kill loaded on
            // f_done's own edge (sdram_mp cannot land a port-A write and a
            // fill together today; insurance against future scheduling).
            d_we <= 1'b1; d_wa <= idx_of(fill_p); d_be <= 16'hFFFF; d_wd <= lb;
            if (!sn_ours && !sn2_v
                && !(t_we && !t_wd[TAG_BITS] && t_wa == idx_of(fill_p))) begin
                t_we <= 1'b1; t_wa <= idx_of(fill_p); t_wd <= {1'b1, tag_of(fill_p)};
            end
            st <= S_SERVE;
          end

          // ---------------- paced: the result waits out its bus time -----
          // A line load the fetch abandoned (a branch) stops at the cycle
          // in flight, as S_WLD's ld_drop does.
          S_PACE: begin
            if (pk == K_LD && ld_drop && pdebt > {3'd0, p_rcyc})
                pdebt <= {3'd0, p_rcyc};
            if (!p_busy) begin
                if (pk == K_LD) begin
                    ld_ack  <= ~ld_ack;
                    pdebt   <= ptail;
                    ld_tail <= (ptail != 6'd0);
                    ld_next <= c_a[19:4] + 16'd1;
                end else begin
                    rd_pend  <= 1'b0;
                    rd_ready <= 1'b1;
                end
                st <= S_IDLE;
            end
          end

          // ---------------- uncached: Wishbone, ce edges only ------------
          S_WLD: if (ce && wb_ack_i) begin
            ld_data[16*ld_i +: 16] <= wb_dat_i;
            if (ld_i == 3'd7 || ld_drop) begin
                wb_stb_o <= 1'b0;
                ld_ack   <= ~ld_ack;
                st       <= S_IDLE;
            end else begin
                ld_i     <= ld_i + 3'd1;
                wb_adr_o <= {ld_base[19:4], ld_i + 3'd1};
            end
          end

          S_WRD1: if (ce && wb_ack_i) begin
            rd_pend <= 1'b0;
            if (wb_tga_o) io_rec <= 8'd0;
            if (rd_a[0]) begin
                rd_data[7:0] <= wb_dat_i[15:8];
                if (rd_isw) begin
                    wb_adr_o <= rd_a[19:1] + 19'd1;
                    wb_sel_o <= 2'b01;
                    st       <= S_WRD2;
                end else begin
                    rd_data[15:8] <= 8'h00;
                    wb_stb_o <= 1'b0;
                    if (p_busy) begin pk <= K_RD; st <= S_PACE; end
                    else begin rd_ready <= 1'b1; st <= S_IDLE; end
                end
            end else begin
                rd_data  <= rd_isw ? wb_dat_i : {8'h00, wb_dat_i[7:0]};
                wb_stb_o <= 1'b0;
                if (p_busy) begin pk <= K_RD; st <= S_PACE; end
                else begin rd_ready <= 1'b1; st <= S_IDLE; end
            end
          end

          S_WRD2: if (ce && wb_ack_i) begin
            if (wb_tga_o) io_rec <= 8'd0;
            rd_data[15:8] <= wb_dat_i[7:0];
            wb_stb_o <= 1'b0;
            if (p_busy) begin pk <= K_RD; st <= S_PACE; end
            else begin rd_ready <= 1'b1; st <= S_IDLE; end
          end

          S_WWR1: if (ce && wb_ack_i) begin
            if (wb_tga_o) io_rec <= 8'd0;
            if (wr_addr[0] && wr_word) begin
                wb_adr_o <= wr_addr[19:1] + 19'd1;
                wb_sel_o <= 2'b01;
                wb_dat_o <= {8'h00, wr_data[15:8]};
                st       <= S_WWR2;
            end else if (wb_tga_o && wr_addr[15:0] == 16'h005F) begin
                wb_stb_o <= 1'b0;
                w5f      <= 5'd0;
                st       <= S_W5F;
            end else begin
                wb_stb_o <= 1'b0;
                wr_ready <= 1'b1;
                st       <= S_IDLE;
            end
          end

          S_WWR2: if (ce && wb_ack_i) begin
            if (wb_tga_o) io_rec <= 8'd0;
            wb_stb_o <= 1'b0;
            wr_ready <= 1'b1;
            st       <= S_IDLE;
          end

          S_W5F: begin
            w5f <= w5f + 5'd1;
            if (w5f == 5'(WAIT_5F - 1)) begin
                wr_ready <= 1'b1;
                st       <= S_IDLE;
            end
          end

          default: st <= S_IDLE;
        endcase
    end

    // Power-up state for what the CPU reset does not touch.
    initial begin
        fs = F_IDLE; f_req = 1'b0; f_we = 1'b0; wb_full = 1'b0; f_wpart = 1'b0;
        cb_v = 2'b00; cb_fl = 2'b00; cb_want = 2'b00; cb_act = 1'b0; cb_fli = 1'b0;
        cb_kill = 2'b00;
        cb_age[0] = 6'd0; cb_age[1] = 6'd0;
        sn2_v = 1'b0; st = S_FLUSH; flush_i = '0; wr_ready = 1'b0;
        dbg_sn_kills = 16'd0;
        snq_v = 1'b0; snq_i = '0; snq_wi = '0;
        park_v = 1'b0; park_i = '0;
    end

    wire _unused = &{1'b0, ld_a1, rd_a1};

endmodule

// Simple dual-port M10K: one write port with byte enables, one read port
// whose address is registered (data the cycle after). Quartus gets the
// megafunction itself -- written behaviourally, the 16 KB array was not
// inferred and the fit ran out of logic -- and simulation the same thing
// as a plain array. Both start all-zero (the tags' valid bits).
module z86_cache_ram #(
    parameter int AW = 10,
    parameter int BYTES = 16,
    parameter int BW = 8
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [AW-1:0]         waddr,
    input  wire [BYTES-1:0]      be,
    input  wire [BYTES*BW-1:0]   wdata,
    input  wire [AW-1:0]         raddr,
    output wire [BYTES*BW-1:0]   q
);
`ifdef VERILATOR
    reg [BYTES-1:0][BW-1:0] ram [0:(1<<AW)-1];
    reg [BYTES*BW-1:0] q_r;
    integer i;
    initial for (i = 0; i < (1 << AW); i = i + 1) ram[i] = '0;
    always @(posedge clk) begin
        if (we)
            for (int b = 0; b < BYTES; b++)
                if (be[b]) ram[waddr][b] <= wdata[b*BW +: BW];
        q_r <= ram[raddr];
    end
    assign q = q_r;
`else
    altsyncram #(
        .operation_mode                     ("DUAL_PORT"),
        .intended_device_family             ("Cyclone V"),
        .ram_block_type                     ("M10K"),
        .width_a                            (BYTES * BW),
        .widthad_a                          (AW),
        .numwords_a                         (1 << AW),
        .width_byteena_a                    (BYTES),
        .byte_size                          (BW),
        .width_b                            (BYTES * BW),
        .widthad_b                          (AW),
        .numwords_b                         (1 << AW),
        .address_reg_b                      ("CLOCK0"),
        .outdata_reg_b                      ("UNREGISTERED"),
        .outdata_aclr_b                     ("NONE"),
        .read_during_write_mode_mixed_ports ("DONT_CARE"),
        .power_up_uninitialized             ("FALSE"),
        .lpm_type                           ("altsyncram")
    ) u_ram (
        .clock0     (clk),
        .wren_a     (we),
        .address_a  (waddr),
        .data_a     (wdata),
        .byteena_a  (be),
        .address_b  (raddr),
        .q_b        (q),
        .aclr0 (1'b0), .aclr1 (1'b0), .addressstall_a (1'b0),
        .addressstall_b (1'b0), .byteena_b (1'b1), .clock1 (1'b1),
        .clocken0 (1'b1), .clocken1 (1'b1), .clocken2 (1'b1),
        .clocken3 (1'b1), .data_b ({(BYTES*BW){1'b1}}), .eccstatus (),
        .q_a (), .rden_a (1'b1), .rden_b (1'b1), .wren_b (1'b0)
    );
`endif
endmodule

`default_nettype wire
