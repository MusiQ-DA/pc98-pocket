//============================================================================
//
//  zet_cpu_bridge -- put the Zet (16-bit Wishbone master) on the i8288
//  world (8-bit), the downstream contract the removed nuV30 bridge drove.
//
//  Zet is a plain 80186-class microcoded core: it knows
//  PUSHI/ENTER/LEAVE/PUSHA/IMUL-imm/INS/OUTS, so the ITF's
//  F9476 `push imm16` that killed the i8088 does not derail it. It is NOT
//  a V30: no NEC extensions (BRKEM/INS/EXT bitfield, the flag quirks), and
//  it makes no attempt at cycle accuracy. It is the shipping CPU -- nuV30
//  was removed when the swap landed.
//
//  THE UPSTREAM CONTRACT (zet_wb_master, measured, not assumed):
//   * wb_cyc_o == wb_stb_o, asserted in the master's stb states and held
//     until wb_ack_i; wb_adr_o[19:1] is the WORD address, wb_sel_o the
//     lanes: 01 = even byte, 10 = odd byte, 11 = word (always even --
//     the master itself splits an odd-addressed word into byte(odd) then
//     byte(even) across two Wishbone cycles).
//   * wb_tga_o = 1 means I/O; wb_we_o the direction. wb_dat_o is already
//     lane-placed (an odd byte's data sits in [15:8]).
//   * Interrupt acknowledge is NOT a bus cycle: wb_tgc_o pulses for one
//     Zet clock when the interrupt micro-routine starts, and the vector
//     must be on wb_dat_i DURING that pulse (iid_dat_i muxes it straight
//     through). The routine pushes F/CS/IP after -- tens of clocks -- but
//     the vector sample happens inside the pulse window.
//
//  THE BRIDGE'S ANSWER:
//
//   * Zet runs on a GATED clock (zet_clk = clk & (run_arm | reset)): the
//     gate is open unless an INTA service or pause_core has closed it, so
//     the core free-runs at clk_chipset and only the 8288 byte engine
//     below stays on the cpu_ce train. Bus cycles keep their PC-98
//     pacing (T-states, AEN stretch, SDRAM waits are all counted in CE
//     pulses); the CE setting now shapes the bus, not the core's issue
//     rate. (An FPGA clock gate, not a PLL -- skew vs clk is covered by
//     the explicit WB handshake.)
//   * A Wishbone cycle needs no parking trick: ack is simply withheld
//     while the byte engine below runs the access, exactly as the v30
//     bridge's byte engine works (T-state pacing, AEN stretch, word
//     bursts into SDRAM, I/O word termination -- same rules, same code).
//     Program order holds because Wishbone serializes for us: the next
//     cycle cannot announce until this one is acked, so the v30 bridge's
//     write queue is unnecessary here.
//   * INTA: when wb_tgc_o rises, the bridge FREEZES Zet's clock -- the
//     pulse is a register that cannot clear without an edge, so wb_tgc_o
//     stays high and iid_dat_i keeps selecting wb_dat_i. Two BS_INTA byte
//     cycles then run down the 8288 (the i8259 needs ACK1 to set ISR and
//     ACK2 to present the vector, same as the metal's double-INTA), the
//     second byte is captured, {8'h00, vector} is parked on wb_dat_i, and
//     the clock is released: the first edge Zet sees clears inta with the
//     vector already valid, which is when the microcode samples it.
//     NMI's acknowledge (nmia) gets the fixed vector 2 the same way --
//     kotku.v wires 16'h0002 for it, no bus cycle needed.
//
//  SPDX-License-Identifier: GPL-3.0-or-later  (Zet is GPLv3+; see
//  core/zet/LICENSE.Zet)
//
//============================================================================

`default_nettype none

module zet_cpu_bridge (

    // chipset domain
    input  wire         clk,                // clk_chipset
    input  wire         cpu_ce_posedge,     // the CE train the 8288 runs on
    input  wire         cpu_ce_negedge,     // its falling half: the fast-pair
                                            // gap ends on a PASV negedge
    input  wire         fast_pace,          // clk_select[1]: the fast settings
                                            // trade T-state fidelity for speed
    input  wire         reset,              // reset_cpu

    // the Zet's Wishbone pins
    output wire         zet_clk,            // gated clock for the core
    input  wire  [15:0] wb_dat_o,
    output wire  [15:0] wb_dat_i,
    input  wire  [19:1] wb_adr_o,
    input  wire         wb_we_o,
    input  wire         wb_tga_o,
    input  wire  [ 1:0] wb_sel_o,
    input  wire         wb_stb_o,
    input  wire         wb_cyc_o,
    output reg          wb_ack_i,
    input  wire         wb_tgc_o,           // inta pulse
    input  wire         nmia,

    // the CPU-side pins, as the chipset sees them
    output wire  [2:0]  processor_status,
    output reg   [19:0] ad_out,
    output reg   [7:0]  cpu_data_bus,
    output wire         lock_n,

    input  wire         analog_mode,
    output reg          word_access,
    // Prefetch burst side channel to RAM.sv, through Chipset: while a fill
    // owns the byte engine, pf_req_len is the burst's SDRAM word count;
    // pf_beat_* returns one beat per word in address order.
    output wire  [4:0]  pf_req_len,
    input  wire         pf_beat_v,
    input  wire  [7:0]  pf_beat_dat,
    output reg   [7:0]  cpu_data_bus_hi,
    input  wire  [7:0]  data_bus_hi,

    input  wire  [7:0]  data_bus,
    input  wire         processor_ready,
    input  wire         address_enable_n,
    input  wire         pause_core,

    output wire         biu_done,
    output wire  [15:0] dbg
);

    localparam [2:0] BS_INTA = 3'b000;
    localparam [2:0] BS_IOR  = 3'b001;
    localparam [2:0] BS_IOW  = 3'b010;
    localparam [2:0] BS_HALT = 3'b011;
    localparam [2:0] BS_CODE = 3'b100;
    localparam [2:0] BS_MEMR = 3'b101;
    localparam [2:0] BS_MEMW = 3'b110;
    localparam [2:0] BS_PASV = 3'b111;

    // ------------------------------------------------------------------------
    // the gated core clock: every clk edge reaches the core unless halted
    // ------------------------------------------------------------------------
    //
    // run_arm is latched on the FALLING edge, so it only changes while clk
    // is low -- `clk & run_arm` can then never glitch mid-high. The gate
    // stays open in normal operation, so zet_clk posedges come at every
    // clk posedge: the core's issue rate is clk_chipset, and the CE train
    // only paces the byte engine below. In this clk domain "Zet gets an
    // edge this cycle" is therefore just `run_arm` as seen at posedge
    // time.
    //
    // zet_halt starves the core from the very clk wb_tgc_o rises (the
    // level is sampled at the next negedge, closing the gate before the
    // following posedge -- the iid sample cannot land on a stale vector)
    // through the end of the INTA service; int_served re-opens the gate
    // so the release edge can clear the pulse. During reset the edges
    // must flow regardless (Zet's reset is synchronous -- no edges, no
    // reset), and pause_core is the OSD's freeze.
    wire zet_halt = ((wb_tgc_o || inta_active) && !int_served)
                 || (pause_core && !reset);
    reg  run_arm;
    always @(negedge clk) run_arm <= !zet_halt;
    // `| reset`: Zet's reset is SYNCHRONOUS -- no edges, no reset -- so the
    // gate is forced open while reset is held. (v30 gets away without this
    // because its reset is asynchronous.)
    //
    // zph removed: the Zet microcode loop is now two pipelined stages
    // (micro_o_r/bword_r in zet_core -- ROM fetch registered ahead of
    // execute), so the fetch-decode->seq_addr->micro_rom->exec->wb_master
    // round trip no longer has to close in one clk_chipset. zet_clk runs
    // at full rate: every ungated clk posedge reaches the core.
    assign zet_clk = clk & (run_arm | reset);

    // A zet edge lands at this posedge when the gate is open.
    wire zet_edge = run_arm | reset;

    // lock_n drives processor_lock_n on the bus arbiter -- see the posted
    // write queue section for its assignment.

    // ------------------------------------------------------------------------
    // upstream tracker: capture the Wishbone request, hold it until acked
    // ------------------------------------------------------------------------
    //
    // stb stays high through the wait, so capture once and remember.
    // Between the two byte cycles of an ODD word the master does NOT drop
    // stb (stb1_hi->stb2_hi keeps it up while adr/sel flip to the even
    // half), so "new request" cannot mean "stb re-rose". It means: a stb
    // is up while no request is in service and no ack is outstanding --
    // the parameters on the bus are already the next cycle's, because
    // they update on the same Zet edge that consumed the last ack.
    //
    // The parameters themselves are NEVER latched here: the master's
    // wb_adr_o/wb_sel_o/wb_dat_o re-track the core's cpu_*_o on every Zet
    // edge, so a capture made near stb's rise can hold the PREVIOUS
    // micro-op's operands (observed: OUT wrote AL one instruction back,
    // PUSH wrote 0000 instead of 1234). Instead req_age counts the Zet
    // edges since capture, arming is blocked until it reaches 2 (one full
    // track-lag edge plus margin), and the byte engine latches the LIVE
    // Wishbone outputs at arm time -- by then they have converged and
    // they stay stable for the rest of the cycle (cpu_block freezes the
    // exec stage until the ack edge).
    reg        req_busy;        // a WB cycle is being served
    reg  [1:0] req_age;         // Zet edges since capture, saturates at 2

    wire [2:0] wb_bs = wb_tga_o ? (wb_we_o ? BS_IOW : BS_IOR)
                                : (wb_we_o ? BS_MEMW : BS_MEMR);
    wire       wb_req = wb_cyc_o && wb_stb_o;

    // Ack timing: pulse ack once the byte pair is done, drop it on the clk
    // after the delivering Zet edge so the pulse spans exactly one edge.
    // (The core is a clk-rate master now: a two-edge-wide pulse would be
    // sampled twice and the odd-word's second byte would complete off the
    // stale read word without ever touching the 8288.) wb_dat_i stays
    // parked on the read result register -- valid through the ack edge
    // and beyond.
    reg [15:0] rd_word;         // last assembled read data
    reg        inta_active;     // serving a vector fetch for wb_tgc_o
    reg        int_served;      // the INTA pair ran -- keeps zet_halt open
    reg        tgc_q;           // wb_tgc_o last cycle, for rise detect
    reg [ 7:0] int_vector;

    always @(posedge clk) begin
        if (reset) begin
            req_busy      <= 1'b0;
            req_age       <= 2'd0;
            wb_ack_i      <= 1'b0;
            inta_active   <= 1'b0;
            int_served    <= 1'b0;
            tgc_q         <= 1'b0;
        end else begin
            // INTA pulse (a Zet-edge event): the rise starts service -- the
            // clock is already stopped by zet_halt. int_served is cleared
            // only while inta is low, so the release edge can pass and the
            // NEXT pulse still blocks the gate from its first clk.
            tgc_q <= wb_tgc_o;
            if (wb_tgc_o && !tgc_q) begin
                inta_active <= 1'b1;
            end
            if (!wb_tgc_o) int_served <= 1'b0;

            // New Wishbone request: mark it busy while stb is up and
            // nothing is in flight and no ack is outstanding. (The
            // odd-word second byte presents its new adr/sel while stb is
            // still high, on the very edge that consumed the previous
            // ack -- gated on !wb_ack_i, the earliest capture lands the
            // clk after it drops.) No parameters are captured -- see the
            // header note; the engine samples the live outputs at arm.
            if (wb_req && !req_busy && !wb_ack_i
                && !inta_active && !wb_tgc_o) begin
                req_busy <= 1'b1;
                req_age  <= 2'd0;
            end

            // Age the request: count delivered Zet edges, saturating at
            // 2. By the second edge the master's tracking registers have
            // converged to this cycle's operands (stb can rise while
            // wb_adr_o/wb_dat_o still show the previous micro-op's; each
            // Zet edge re-tracks cpu_*_o, so one edge of lag is inherent
            // and two gives margin).
            if (req_busy && zet_edge && (req_age != 2'd2))
                req_age <= req_age + 2'd1;

            // The engine finished the pair: pulse ack, drop it the clk
            // after the Zet edge that consumed it -- one edge wide, so a
            // clk-rate master cannot double-sample. If the core is halted
            // the pulse simply holds until an edge is delivered.
            // !cur_pf/!cur_dq: a prefetch fill's or a write-drain's
            // completion must never ack -- a request captured mid-pair
            // is served by the normal path once that pair retires.
            if (pair_done && req_busy && !cur_pf && !cur_dq) begin
                req_busy     <= 1'b0;
                wb_ack_i     <= 1'b1;
            end
            // A prefetch hit completes the same way but no bus cycle ever
            // ran for it; rd_word takes the window's bytes in the engine
            // block.
            if (hit_serve) begin
                req_busy     <= 1'b0;
                wb_ack_i     <= 1'b1;
            end
            // A forwarded read completes the same way; rd_word takes the
            // queue's bytes in the engine block.
            if (fwd_serve) begin
                req_busy     <= 1'b0;
                wb_ack_i     <= 1'b1;
            end
            // A posted write completes at capture: the operands queue
            // and the bus pair drains them behind the guest's back.
            if (wrq_push) begin
                req_busy     <= 1'b0;
                wb_ack_i     <= 1'b1;
            end
            if (wb_ack_i && zet_edge) wb_ack_i <= 1'b0;

            // INTA service complete: the vector is on wb_dat_i; release
            // the clock. inta clears at the first edge it gets, which is
            // also when the microcode samples iid.
            if (inta_done) begin
                inta_active <= 1'b0;
                int_served  <= 1'b1;
            end
        end
    end

    // wb_dat_i: the read result normally, the vector whenever inta or nmia
    // is asserting -- iid_dat_i selects this port only while wb_tgc_o is
    // high, which under the freeze means "through the release edge", so the
    // vector is what that edge's iid sample sees.
    assign wb_dat_i = nmia        ? 16'h0002
                    : wb_tgc_o    ? {8'h00, int_vector}
                    :               rd_word;

    // ------------------------------------------------------------------------
    // the byte engine: identical pacing to the removed v30_cpu_bridge's
    // ------------------------------------------------------------------------

    localparam [1:0] B_IDLE = 2'd0;   // nothing to do / waiting for the bus
    localparam [1:0] B_CMD  = 2'd1;   // status up: ALE, command, wait ready
    localparam [1:0] B_GAP  = 2'd2;   // status down, letting the 8288 re-arm

    reg  [1:0] bstate;
    reg  [1:0] byte_idx;      // 0 = the addressed byte, 1 = the odd half
    reg  [2:0] t_cnt;         // posedge-CE edges since this byte went up
    reg        saw_low;       // processor_ready fell on OUR bus during this byte
    reg        ready_d1;      // processor_ready, one clk back: edge detect
    reg  [1:0] gap_cnt;
    reg  [7:0] rd_lo;
    reg  [7:0] rd_hi;
    reg        biu_done_r;

    // The pair's parameters, latched at arm time.
    reg  [2:0]  cur_bs;
    reg  [19:0] cur_addr;
    reg         cur_ube_n;
    reg  [15:0] cur_data;
    reg  [2:0]  cur_term;     // the I/O word's termination class
    reg         cur_inta;     // this pair is an acknowledge byte

    wire cur_read = (cur_bs == BS_INTA) || (cur_bs == BS_IOR)
                 || (cur_bs == BS_CODE) || (cur_bs == BS_MEMR);
    wire cur_word = (cur_addr[0] == 1'b0) && (cur_ube_n == 1'b0)
                    && (cur_bs != BS_INTA);

`include "pc98_sdram_map.svh"

    function automatic logic word_1cyc(input logic [2:0] bs,
                                       input logic [19:0] a,
                                       input logic ube_n);
        word_1cyc = (a[0] == 1'b0) && (ube_n == 1'b0)
                 && ((bs == BS_CODE) || (bs == BS_MEMR) || (bs == BS_MEMW))
                 && pc98_sdram_hits(a, analog_mode);
    endfunction

    // Word-I/O termination -- same table the removed v30_cpu_bridge ran
    // (np21w io/iocore.c ioterminate[]/iocore16.tbl).
    localparam [2:0] TERM_NONE   = 3'd0;
    localparam [2:0] TERM_WORD   = 3'd1;
    localparam [2:0] TERM_ACTIVE = 3'd2;
    localparam [2:0] TERM_PLUS   = 3'd3;
    localparam [2:0] TERM_MINUS  = 3'd4;
    localparam [2:0] TERM_EXT08  = 3'd5;

    function automatic logic [2:0] io_term(input logic [2:0] bs,
                                           input logic [19:0] a,
                                           input logic ube_n);
        if (((bs == BS_IOR) || (bs == BS_IOW))
            && (a[0] == 1'b0) && (ube_n == 1'b0) && (a[11:10] == 2'b00))
        case (a[7:0])
          8'hf2, 8'hf6:              io_term = TERM_WORD;
          8'hd0, 8'hd2, 8'hd4, 8'hd6, 8'hd8, 8'hdc, 8'hde:
                                     io_term = TERM_ACTIVE;
          8'h30, 8'h32, 8'h34, 8'h36,
          8'h40, 8'h42, 8'h44, 8'h46:
                                     io_term = TERM_PLUS;
          8'h60, 8'h62, 8'h64, 8'h68, 8'h6a, 8'h6c,
          8'h70, 8'h72, 8'h74, 8'h76, 8'h7a, 8'h7c,
          8'ha0, 8'ha2, 8'ha4, 8'ha6, 8'ha8, 8'hac:
                                     io_term = TERM_MINUS;
          8'h20, 8'h22, 8'h24, 8'h26: io_term = TERM_EXT08;
          default:                   io_term = TERM_NONE;
        endcase
        else io_term = TERM_NONE;
    endfunction

    wire cur_1cyc  = word_1cyc(cur_bs, cur_addr, cur_ube_n);
    // INTA always runs its two bytes: byte 0 is ACK1 (sets the ISR), byte 1
    // is ACK2 (presents the vector). A terminated word I/O pair stops after
    // its one byte.
    wire last_byte = cur_inta ? (byte_idx == 2'd1)
                    : (cur_1cyc || (byte_idx == 2'd1) || !cur_word
                       || (cur_word && (cur_term != TERM_NONE)));

    wire bus_ours = (address_enable_n == 1'b0);

    // What the engine serves: an INTA service beats a pending WB request.
    // (Unreachable in practice -- inta can only pulse at an instruction
    // boundary, and the WB master blocks mid-op so no cycle is in flight --
    // but the mux order keeps it correct even so.)
    wire        srv_inta = inta_active && !int_served;
    wire        srv_req  = req_busy && (req_age == 2'd2) && !srv_inta;
    // Live Wishbone parameters, sampled at arm time (req_age==2 means the
    // tracking registers have settled).
    wire [2:0]  srv_bs   = srv_inta ? BS_INTA : wb_bs;
    wire [19:0] srv_addr = srv_inta ? 20'h00000
                                  : {wb_adr_o, (wb_sel_o == 2'b10)};
    wire        srv_ube  = srv_inta ? 1'b1 : (wb_sel_o != 2'b11);
    wire [15:0] srv_data = srv_inta ? 16'h0000 : wb_dat_o;
    wire [2:0]  srv_term = io_term(srv_bs, srv_addr, srv_ube);
    wire        srv_any  = srv_inta || srv_req;

    wire [19:0] srv_byte_addr = (byte_idx == 2'd0) ? srv_addr
                                                   : {srv_addr[19:1], 1'b1};
    wire [7:0]  srv_byte_data = (byte_idx == 2'd0)
                              ? (srv_addr[0] ? srv_data[15:8] : srv_data[7:0])
                              : srv_data[15:8];

    // fast_pace = clk_select[1], the beyond-real-hardware settings, where
    // the T-state model gives up fidelity it no longer needs. The shrink
    // is one posedge out of the command phase -- and only on a FRESH
    // ready: processor_ready can still be high from the previous byte's
    // completion when this byte's accept would fire (realmem E2E showed
    // byte data arriving one access stale, e.g. the reset vector reading
    // ea/00/00/80/fd as 00/ea/00/00), so the early count is qualified on
    // saw_low, a ready FALLING EDGE that marks THIS byte's access having
    // actually started. Level-testing "ready low while we own the bus" is
    // not enough: at the AEN release, bus_ours returns while the ready
    // chain is still draining dma_wait, and the falsely-armed byte then
    // accepts as the drain completes -- before the re-asserted strobe's
    // access could ever finish (realmem+freeze: f801d read as fe, the
    // same signature hardware showed at f95b3). Bytes whose access never
    // drops ready fall back to the faithful count. The gap ends at the
    // first
    // passive negedge -- pair_finish is the pair's ONLY terminator:
    // rd_word assembly, biu_done, the byte transition and the Wishbone
    // ack must all move on the same edge, or the ack lands before the
    // data (the stale-word signature returns).
    // INTA pairs keep the faithful count: for the 8259's two-acknowledge
    // sequence the pacing IS the contract.
    // Drains and fills take the fast profile regardless of the pace
    // dial: the guest never sees these pairs, so the faithful T-state
    // count would only delay data movement.
    wire fast_pair = (fast_pace || cur_dq || cur_pf || cur_fillm)
                  && !cur_inta;
    wire pair_finish = (bstate == B_GAP)
                     && (fast_pair ? cpu_ce_negedge : (gap_cnt == 2'd1));
    wire pair_done   = pair_finish && last_byte;
    wire inta_done   = pair_done && cur_inta;

    assign biu_done = biu_done_r;

    // ------------------------------------------------------------------
    // The prefetch window: the real BIU's prefetch, rebuilt on the SDRAM's
    // burst ability. A 32-byte ALIGNED sector chases the read stream;
    // fills run as ordinary byte-style bus cycles whose strobe carries
    // pf_req_len, so RAM turns each into ONE multi-word transaction
    // (~3 clk/byte instead of a whole bus cycle per byte). A guest read
    // landing inside the fetched span completes from it without any bus
    // cycle at all -- the same contract the metal's BIU gives the EU.
    //
    // A window covers offsets [pf_lo, pf_cnt) of its sector: fills append
    // at pf_cnt, and a fill-on-miss pair (see below) anchors both at the
    // miss offset -- bytes before the first miss are simply never there.
    //
    // Hits do NOT consume: the window is a sector, not a FIFO. A tight
    // code loop, or a status poll hammering one address, keeps hitting
    // on every iteration; a consume-on-hit queue would instead slide its
    // base past the loop head and miss the same bytes forever.
    //
    // Correctness hinges on invalidation, and all of it is local: every
    // guest write passes this engine, so an overlapping write's ARM drops
    // the window before the write ever reaches memory; any I/O write
    // flushes (bank/shadow/wait registers move the map); and !bus_ours --
    // the DMA grant -- flushes because the DMAC's writes bypass us. A fill
    // already in flight marks fill_ok; an invalidation clears it and the
    // rest of that fill's beats are dropped at append time.
    //
    // Only PLAIN sdram bytes are fetched: pc98_sdram_hits minus
    // pc98_gvram_hits -- never a graphics window (the sequencer's plane
    // walks), never an I/O or a memory-mapped hole, and never across the
    // 32K block containing the shadow boundary, because the burst is one
    // contiguous SDRAM run and the ITF remap would not follow it.
    // ------------------------------------------------------------------
    localparam int PF_N = 32;   // bytes per window

    // Two sector windows, each a 32-byte aligned region of SDRAM. A
    // single window can only hold one stream; two let a code fetch
    // stream and a data stream (REP MOVS sources, structure walks,
    // status polls) keep their own prefetchers instead of evicting each
    // other on every alternation. A byte lives at pf_buf[{win,addr[4:0]}]
    // outright because each base is 32-byte aligned.
    // MLAB storage: 512 FFs plus the two 64:1 hit muxes was ~50 LABs of
    // dead weight; a distributed MLAB serves the same async reads in one
    // LAB per replicated read port and keeps hit timing identical.
    // no_rw_check is safe: a fill only ever writes the frontier slot
    // (pf_cnt) while a hit only ever reads BEHIND it (off+span <= cnt),
    // so a read never collides with the same-byte write.
    (* ramstyle = "MLAB, no_rw_check" *) reg  [7:0]  pf_buf [0:2*PF_N-1];
    reg  [5:0]  pf_cnt0, pf_cnt1;   // one-past-last valid offset, 0..32
    reg  [4:0]  pf_lo0, pf_lo1;     // first valid offset -- a window is
                                    // [base, base+cnt) sector bytes that were
                                    // actually fetched: [lo, cnt)
    reg  [19:0] pf_base0, pf_base1;
    reg  [1:0]  pf_live;
    reg         pf_victim;          // which window a foreign miss claims
    reg         pf_want;            // preferred fill target (last rebase)
    reg         cur_pf;             // the pair in flight is a prefetch fill
    reg         cur_pf_w;           // which window it fills
    reg  [4:0]  cur_pf_len;         // its burst length
    reg         cur_fillm;          // the pair is a guest read whose burst
                                    // doubles as a fill (beat 0/1 serve the
                                    // guest, every beat also appends)
    reg         fill_ok;            // this fill's beats may still append
    reg  [4:0]  fill_beats;         // beats this fill appended
    reg  [6:0]  fill_wait;          // clks the pair has waited for its burst
    reg  [1:0]  pf_dead;            // zero-beat fills: dead man's switch
    reg         pf_miss1;           // a foreign miss since last hit/rebase

    // A fill or fill-on-miss pair must not take a ready that preceded its
    // own burst: READY.sv's one-shot still holds the PREVIOUS pair's pulse
    // when this pair enters B_CMD, and it survives ~2 ce edges past the new
    // strobe -- long enough for the fast accept to fire mid-burst and end
    // the pair with zero beats (measured: fill armed right behind a fillm
    // pair completed on the stale high ~6 clks in; pf_dead then killed the
    // whole engine). Beat 0 is also the fillm pair's guest byte, so waiting
    // for it is what returns correct data. The timeout is the never-ran
    // fallback: a request that somehow produced no beats ends the pair
    // anyway and the dead man's switch scores it.
    wire fill_early = (cur_pf || cur_fillm) && fill_ok
                   && (fill_beats == 5'd0) && (fill_wait != 7'd127);

    // ------------------------------------------------------------------
    // Posted write queue: a plain-SDRAM guest write is captured at
    // request time and acknowledged immediately -- the byte pair that
    // drains it to RAM runs in the engine's idle gaps, on the same fast
    // profile prefetch fills use. The guest's cost per write drops to
    // the tracker's settle (~4 clk) from a whole paced pair.
    //
    // Ordering, in three rules:
    //   - a guest read may bypass the queue only when no pending entry
    //     overlaps its span; an overlapping read blocks until the drain
    //     clears the byte, so it can never observe pre-write data;
    //   - another write to posted memory (and any prefetch fill) waits
    //     behind the queue;
    //   - while ANY entry is queued (or being drained, or pushed this
    //     clk), lock_n is asserted so the arbiter cannot start a HOLD
    //     grant -- a DMA grant can only land after every queued byte is
    //     inside RAM's own posted queue, which preserves guest-write ->
    //     DMA-read order without the queue ever needing the bus
    //     mid-grant. (processor_status itself is never overridden: it is
    //     the 8288's command input, so forcing MEMW there would turn an
    //     in-flight read pair into a phantom write on the read's
    //     address.)
    // Entries pop when their drain pair arms: the engine is serial, so
    // an armed write is committed ahead of whatever arms next, and
    // RAM's own posted-write ordering takes it from there. Each entry is
    // exactly one pair -- byte writes are single bytes, and the WB
    // master splits odd word writes into two sel'd byte requests, so no
    // drain ever needs a second byte phase.
    // ------------------------------------------------------------------
    localparam int WQ_N = 2;
    reg  [19:0] wrq_addr [0:WQ_N-1];
    reg  [15:0] wrq_data [0:WQ_N-1];
    reg         wrq_ube  [0:WQ_N-1];
    reg  [2:0]  wrq_cnt;            // live entries, 0..WQ_N
    reg         cur_dq;             // the pair in flight is a queue drain
    reg  [2:0]  ps_r;               // processor_status, minus queue holdoff

    wire [4:0]  srv_span  = srv_ube ? 5'd1 : 5'd2;
    wire [20:0] srv_beg   = {1'b0, srv_addr};
    wire [20:0] srv_end_a = srv_beg + {16'b0, srv_span};

    wire [20:0] pf_end0 = {1'b0, pf_base0} + {15'b0, pf_cnt0};
    wire [20:0] pf_end1 = {1'b0, pf_base1} + {15'b0, pf_cnt1};
    wire [20:0] pf_off0 = srv_beg - {1'b0, pf_base0};
    wire [20:0] pf_off1 = srv_beg - {1'b0, pf_base1};

    // A read is served when its whole span is fetched, in either window.
    // The base's low five bits are always zero (32B-aligned sectors), so
    // "inside the window" is a sector compare plus an in-sector span
    // check -- the full 21-bit subtract is only needed for the near/back
    // miss bookkeeping below, not for the hit itself.
    wire        inwin0 = pf_live[0] && (srv_beg[19:5] == pf_base0[19:5]);
    wire        inwin1 = pf_live[1] && (srv_beg[19:5] == pf_base1[19:5]);
    wire pf_hit0 = inwin0 && (srv_beg[4:0] >= pf_lo0)
                 && (({16'b0, srv_beg[4:0]} + {16'b0, srv_span})
                     <= {15'b0, pf_cnt0});
    wire pf_hit1 = inwin1 && (srv_beg[4:0] >= pf_lo1)
                 && (({16'b0, srv_beg[4:0]} + {16'b0, srv_span})
                     <= {15'b0, pf_cnt1});
    wire pf_hit  = srv_req && (srv_bs == BS_MEMR) && (pf_hit0 | pf_hit1);
    wire pf_hw   = pf_hit1;         // which window the hit is in
    // Hits need no bus cycle, so they may also complete while a request
    // is not yet armed -- but not while DMA owns the bus, when the
    // windows are being dropped anyway, and not over a queued write's
    // span, where the window's bytes predate the pending store.
    wire hit_serve = pf_hit && bus_ours && (bstate == B_IDLE) && !wrq_ovl;

    wire [4:0]  pf_idx0 = srv_beg[4:0];
    wire [7:0]  pf_b0   = pf_buf[{pf_hw, pf_idx0}];
    wire [7:0]  pf_b1   = pf_buf[{pf_hw, pf_idx0 + 5'd1}];
    wire [15:0] pf_hit_word = srv_ube ? {pf_b0, pf_b0} : {pf_b1, pf_b0};

    // Fill legality, per candidate byte: plain SDRAM, never a graphics
    // window or a hole, and never across the 32K block containing the
    // ITF/shadow boundary -- the burst is one contiguous SDRAM run and
    // the remap would not follow it.
    function automatic logic pf_ok(input logic [19:0] a,
                                   input logic [4:0]  blk);
        pf_ok = pc98_sdram_hits(a, analog_mode)
             && !pc98_gvram_hits(a, analog_mode)
             && (a[19:15] == blk);
    endfunction

    // Fill legality is uniform across a whole 32-byte sector: every term
    // in pc98_sdram_hits / pc98_gvram_hits (and the 32K-block fence) looks
    // at a[19:15] or coarser, and a 32B-aligned sector can never straddle
    // a boundary that wide. The old 16-deep consecutive-legal-bytes walk
    // therefore collapses to one check at the fill frontier -- the run is
    // either all sixteen candidate bytes or none. The length caps below
    // (room, column) keep the actual burst inside the window anyway.
    function automatic logic [4:0] pf_run_f(input logic [20:0] n);
        return pf_ok(n[19:0], n[19:15]) ? 5'd16 : 5'd0;
    endfunction

    wire [20:0] pf_next0 = pf_end0;         // each window's fill frontier
    wire [20:0] pf_next1 = pf_end1;
    wire [4:0]  pf_run0  = pf_run_f(pf_next0);
    wire [4:0]  pf_run1  = pf_run_f(pf_next1);
    wire [5:0]  pf_room0 = 6'd32 - {1'b0, pf_cnt0};
    wire [5:0]  pf_room1 = 6'd32 - {1'b0, pf_cnt1};
    wire [9:0]  pf_colr0 = 10'd512 - {1'b0, pf_next0[8:0]};
    wire [9:0]  pf_colr1 = 10'd512 - {1'b0, pf_next1[8:0]};

    // A window needs a fill while a legal byte remains inside it.
    function automatic logic [4:0] pf_len_f(input logic [4:0] run,
                                            input logic [5:0] room,
                                            input logic [9:0] colr);
        logic [4:0] l;
        l = (room > 6'd16) ? 5'd16 : room[4:0];
        l = (run < l) ? run : l;
        l = ({5'b0, colr} < {1'b0, l}) ? colr[4:0] : l;
        return l;
    endfunction

    wire [4:0]  pf_len0 = pf_len_f(pf_run0, pf_room0, pf_colr0);
    wire [4:0]  pf_len1 = pf_len_f(pf_run1, pf_room1, pf_colr1);
    wire        pf_need0 = pf_live[0] && (pf_len0 != 5'd0);
    wire        pf_need1 = pf_live[1] && (pf_len1 != 5'd0);
    // Both needy: the most recently rebased stream fills first -- it is
    // the one the guest is running on right now.
    wire        fill_w      = (pf_need0 && pf_need1) ? pf_want
                            : (pf_need1 ? 1'b1 : 1'b0);
    wire [20:0] pf_next     = fill_w ? pf_next1 : pf_next0;
    wire [4:0]  pf_fill_len = fill_w ? pf_len1 : pf_len0;

    wire srv_pf  = (pf_need0 | pf_need1) && (pf_dead != 2'd3)
                && !pause_core;

    // Write-queue capture: the request is postable when it targets plain
    // SDRAM and a slot is free. The push itself is in the tracker block
    // (it owns req_busy/wb_ack_i); wrq_tail lands the entry.
    wire srv_memw_plain = (srv_bs == BS_MEMW)
                       && pc98_sdram_hits(srv_addr, analog_mode)
                       && !pc98_gvram_hits(srv_addr, analog_mode);
    wire wrq_push = srv_req && srv_memw_plain && (wrq_cnt < WQ_N[2:0]);

    // Pending-write overlap vs the pending read's span. Entry span is
    // one byte for ube, two for a word; only live entries count.
    wire [20:0] wrq_end [0:WQ_N-1];
    wire [WQ_N-1:0] wrq_hit;
    genvar g;
    generate
    for (g = 0; g < WQ_N; g = g + 1) begin : g_wr_ovl
        assign wrq_end[g] = {1'b0, wrq_addr[g]}
                          + (wrq_ube[g] ? 21'd1 : 21'd2);
        assign wrq_hit[g] = (wrq_cnt > g)
                         && (srv_beg   <  wrq_end[g])
                         && (srv_end_a > {1'b0, wrq_addr[g]});
    end
    endgenerate
    wire wrq_ovl = |wrq_hit;

    // Store->load forwarding: a queued byte is still "newer than RAM"
    // until its drain lands, but the bridge is already holding the data.
    // A read whose whole span sits inside live entries takes the newest
    // covering byte straight from the queue -- no bus cycle, no drain
    // wait. This is the CALL/RET stack pattern: the RET's pop reads the
    // address the CALL just pushed, and without forwarding it stalls on
    // wrq_ovl for the whole drain (real-hw bench_ni NEARCALL +36%). The
    // FIFO is age-ordered (index 0 oldest), so the higher index wins.
    // Partial coverage still falls through to the drain wait -- the
    // uncovered byte has to come from RAM behind the queued writes.
    wire [20:0] fwd_a0 = srv_beg;
    wire [20:0] fwd_a1 = srv_beg + 21'd1;
    wire [WQ_N-1:0] fwd_cov0, fwd_cov1;
    generate
    for (g = 0; g < WQ_N; g = g + 1) begin : g_fwd
        assign fwd_cov0[g] = (wrq_cnt > g)
                         && (fwd_a0 >= {1'b0, wrq_addr[g]})
                         && (fwd_a0 <  wrq_end[g]);
        assign fwd_cov1[g] = (wrq_cnt > g)
                         && (fwd_a1 >= {1'b0, wrq_addr[g]})
                         && (fwd_a1 <  wrq_end[g]);
    end
    endgenerate
    wire       fwd_cov = (|fwd_cov0) && (srv_ube || (|fwd_cov1));
    wire [7:0] fwd_b0  = fwd_cov0[1]
                       ? (fwd_a0[0] ? wrq_data[1][15:8] : wrq_data[1][7:0])
                       : (fwd_a0[0] ? wrq_data[0][15:8] : wrq_data[0][7:0]);
    wire [7:0] fwd_b1  = fwd_cov1[1]
                       ? (fwd_a1[0] ? wrq_data[1][15:8] : wrq_data[1][7:0])
                       : (fwd_a1[0] ? wrq_data[0][15:8] : wrq_data[0][7:0]);
    wire [15:0] fwd_word = srv_ube ? {fwd_b0, fwd_b0} : {fwd_b1, fwd_b0};
    wire fwd_serve = srv_req && (srv_bs == BS_MEMR) && wrq_ovl && fwd_cov
                  && bus_ours && (bstate == B_IDLE);

    // What a pending request may NOT do while the queue holds data:
    // reads that overlap pending bytes wait for them to reach RAM;
    // plain-SDRAM writes never arm at all -- they push, or wait for a
    // slot. Everything that is not a plain-memory read (I/O, INTA, GVRAM
    // traffic) also waits behind the queue: an OUT that starts a DMA
    // must never pass the stores that filled the DMA buffer, and the
    // same strong order covers every other externally-visible cycle.
    // A plain non-overlapping MEMR is the only bypass left -- its data
    // cannot observe the queued bytes, so the bypass is unobservable.
    wire srv_blk = srv_memw_plain
                || ((wrq_cnt != 3'd0) && (srv_bs != BS_MEMR))
                || ((srv_bs == BS_MEMR) && wrq_ovl);

    // Shadow of the i8288's machine_cycle/machine_cycle_period
    // (i8288.sv:102-130). The controller only latches a bus address
    // while it sits in the wait-for-status phase -- ALE is
    // mcp & ~passive -- and a status asserted while it is still
    // unwinding the previous command (mcp still 0) issues a command
    // strobe with NO ALE: the bus keeps the stale address and the guest
    // reads or writes the wrong location. A fast drain ends its pair
    // one negedge before the next arm, racing exactly this window (the
    // pop-after-push fetch at f8550 came back with the drained byte).
    // ps_r is the status the 8288 itself sees and both sample it on the
    // same posedge, so tracking the two registers here on the same CE
    // train is exact; an arm is legal only once the controller is
    // waiting (mcp==1 implies mc==000, the cycle is pinned).
    reg  [2:0] sh_mc;
    reg        sh_mcp;
    wire       pasv_now = (ps_r == BS_PASV);

    always_ff @(posedge clk) begin
        if (reset) begin
            sh_mc  <= 3'b000;
            sh_mcp <= 1'b1;
        end else begin
            if (cpu_ce_negedge)
                sh_mc <= pasv_now ? 3'b000 :
                         sh_mcp   ? 3'b000 : {sh_mc[1:0], 1'b1};
            if (cpu_ce_posedge)
                sh_mcp <= (sh_mc == 3'b000) && pasv_now;
        end
    end

    // Engine arms, for the prefetch block's bookkeeping.
    wire arm_req   = (bstate == B_IDLE) && srv_any && bus_ours && !hit_serve
                  && !srv_blk && (wrq_cnt != WQ_N[2:0]) && sh_mcp;
    // The drain wins only when the engine is otherwise idle -- or when a
    // full queue is the thing standing between the guest and its arm.
    wire arm_drain = (bstate == B_IDLE) && bus_ours && (wrq_cnt != 3'd0)
                  && !arm_req && sh_mcp;
    wire arm_fill  = (bstate == B_IDLE) && srv_pf && bus_ours && !hit_serve
                  && !srv_any && (wrq_cnt == 3'd0) && !wrq_push && sh_mcp;
    wire arm_rd_ok = arm_req && (srv_bs == BS_MEMR)
                  && pc98_sdram_hits(srv_addr, analog_mode)
                  && !pc98_gvram_hits(srv_addr, analog_mode);
    wire arm_wr    = arm_req && (srv_bs == BS_MEMW);
    wire arm_iow   = arm_req && (srv_bs == BS_IOW);

    // While any queued write is outstanding -- or one is being posted
    // this very clk -- LOCK is asserted so the arbiter never starts a
    // HOLD grant: a grant can only land after every queued byte is inside
    // RAM's own posted queue, preserving guest-write -> DMA-read order.
    // (The grant latches on PASV && lock_n; pushing and grant-sampling
    // share the edge, so the assertion must be combinational on the push
    // condition, not on wrq_cnt alone. processor_status itself must NOT
    // be overridden: it is the 8288's command input, and forcing MEMW
    // there turns every in-flight read pair into a phantom write on the
    // read's own address.)
    assign processor_status = ps_r;
    assign lock_n = ~((wrq_cnt != 3'd0) || wrq_push || cur_dq);

    // Write overlap reaches into each window's PROMISED range, not just
    // its fetched one: a write landing where a fill is about to drop a
    // beat must still kill that window, or the stale beat lands after
    // the write it should have been behind.
    wire [20:0] pf_reach0 = pf_end0
                + (((cur_pf || cur_fillm) && !cur_pf_w) ? {16'b0, cur_pf_len}
                                                       : 21'd0);
    wire [20:0] pf_reach1 = pf_end1
                + (((cur_pf || cur_fillm) &&  cur_pf_w) ? {16'b0, cur_pf_len}
                                                       : 21'd0);
    wire wr_ovl0 = (srv_beg < pf_reach0) && (srv_end_a > {1'b0, pf_base0});
    wire wr_ovl1 = (srv_beg < pf_reach1) && (srv_end_a > {1'b0, pf_base1});
    wire pf_fill_done = pair_done && (cur_pf || cur_fillm);

    // What a miss may disturb. Inside either anchored sector it is the
    // guest merely outrunning that window's fill frontier: it rides the
    // bus while the fill pours the bytes behind it, and the window
    // stays. Just PAST a sector -- up to 64 ahead, or 32 behind on a
    // loop's back edge -- the miss is that window's own stream moving
    // on, so it rebases THAT window onto the new sector and its stream
    // keeps its prefetcher. Anything else is a foreign stream's read:
    // a lone one leaves both windows alone (single data accesses must
    // not kill a live fetch stream), only a second consecutive foreign
    // miss claims the victim window. The rebase anchor is the sector
    // containing the miss, so the byte just served -- and the loop head
    // behind it -- land inside the window.
    wire insec0 = pf_live[0] && !pf_off0[20]
                && (srv_beg < {1'b0, pf_base0} + 21'd32);
    wire insec1 = pf_live[1] && !pf_off1[20]
                && (srv_beg < {1'b0, pf_base1} + 21'd32);
    wire near0  = pf_live[0] && !pf_off0[20] && (pf_off0 < 21'd96);
    wire near1  = pf_live[1] && !pf_off1[20] && (pf_off1 < 21'd96);
    wire back0  = pf_live[0] && pf_off0[20] && (pf_off0 >= 21'h1FFFE0);
    wire back1  = pf_live[1] && pf_off1[20] && (pf_off1 >= 21'h1FFFE0);
    wire cont0  = near0 || back0;
    wire cont1  = near1 || back1;

    // ------------------------------------------------------------------
    // Fill-on-miss: an eligible guest read that misses but touches a
    // window decision carries pf_req_len itself -- the burst starts AT the
    // miss address, so beat 0/1 are the guest's own bytes (the shim pins
    // data_out/_hi on them) and every beat also appends to the window.
    // Pure fills need an idle engine slot to run in; at the fast pace
    // settings srv_any is up on nearly every B_IDLE, so that slot never
    // comes and the windows starve -- measured: speed3 fills=0/hits=0 in
    // tb_mem_perf, every sequential fetch paying full latency. With the
    // miss itself doing the fill the stream self-feeds at every speed.
    //
    // Eligibility mirrors the miss policy: any branch that claims,
    // rebases or extends a window turns the arming read into a fill;
    // a first foreign miss (pf_miss1==0) still rides the bus alone --
    // the two-strike rule keeps single random reads from paying for a
    // burst nobody consumes. Poisoned sectors (write-mixed) never fill.
    // A queued write overlapping the BURST range vetoes it: the window
    // would capture pre-drain bytes and serve them stale after the drain.
    // ------------------------------------------------------------------
    wire [4:0]  fillm_len  = pf_len_f(5'd16, 6'd32 - {1'b0, srv_beg[4:0]},
                                      10'd512 - {1'b0, srv_beg[8:0]});
    wire [20:0] fillm_end  = srv_beg + {16'b0, fillm_len};
    wire [WQ_N-1:0] wrq_hitm;
    generate
    for (g = 0; g < WQ_N; g = g + 1) begin : g_wrq_ovlm
        assign wrq_hitm[g] = (wrq_cnt > g)
                         && (srv_beg   <  wrq_end[g])
                         && (fillm_end > {1'b0, wrq_addr[g]});
    end
    endgenerate
    wire        fillm_ovl = |wrq_hitm;

    // Which window the miss touches, mirroring the policy chain below:
    // seed -> w0, in-sector -> its window, retn -> the OTHER one, cont ->
    // its own, claim -> the victim. insec_ext marks the case that keeps
    // the window's fetched prefix: the miss sits within [lo, cnt] -- the
    // rest re-anchor the window at the miss so no unfetched byte ever
    // lands inside [lo, cnt).
    wire        insec   = insec0 || insec1;
    wire        insec_w = insec1 && !insec0;
    wire [4:0]  insec_lo  = insec_w ? pf_lo1  : pf_lo0;
    wire [5:0]  insec_cnt = insec_w ? pf_cnt1 : pf_cnt0;
    wire        insec_ext = insec
                         && ({1'b0, srv_beg[4:0]} >= {1'b0, insec_lo})
                         && ({1'b0, srv_beg[4:0]} <= insec_cnt);
    wire        fillm_go = arm_rd_ok && !pf_poisoned && (pf_dead != 2'd3)
                        && !pause_core && !fillm_ovl
                        && (~|pf_live || insec || retn0 || retn1
                            || cont0 || cont1 || pf_miss1);
    wire        fillm_w  = (~|pf_live) ? 1'b0
                         : insec       ? insec_w
                         : retn0       ? 1'b1
                         : retn1       ? 1'b0
                         : cont0       ? 1'b0
                         : cont1       ? 1'b1
                         : (!pf_live[1] || (pf_live[0] && pf_victim));
    // For a re-anchor the append pointer starts at the miss offset; an
    // insec_ext keeps lo and just regrows cnt from the miss on.
    wire        fillm_new = ~|pf_live || !insec || !insec_ext;

    assign pf_req_len = ((cur_pf || cur_fillm) && (bstate == B_CMD))
                      ? cur_pf_len : 5'd0;

    // Anti-thrash poison: a window killed by an overlapping guest write
    // was almost certainly covering a data stream, not a code one --
    // the classic case is the CALL/RET stack loop, where the push kills
    // the stack window on every iteration and the pop refills it, so a
    // 16-beat fill burns bus time per iteration and is never consumed.
    // Remember the killed sector for a while; a miss inside it rides
    // the bus without claiming or rebasing, until enough armed reads
    // have passed to call the stream quiet again. (Real-hw bench_ni
    // NEARCALL regressed +36% on exactly this pattern.)
    reg  [14:0] pf_pois;        // poisoned sector tag, a[19:5]
    reg  [7:0]  pf_pcnt;        // armed reads left while it stays hot
    wire pf_poisoned = (pf_pcnt != 8'd0) && (srv_beg[19:5] == pf_pois);

    // Ghost tags: when a live window is redirected (rebase or claim-over)
    // its abandoned base is remembered. A miss back inside that sector is
    // the stream RETURNING, not continuing -- two code streams on adjacent
    // sectors otherwise make ONE window chase them forever: B is `near` of
    // A's window (rebase A->B), the next A read is `back` of the rebased
    // window (rebase B->A), and the second window never sees a foreign
    // miss to claim. bench_ni NEARCALL straddles exactly that boundary
    // (call@x2FD, loop@x300) and burned ~4 fills/iter on real hw and in
    // sim phase 8. A returning miss claims the OTHER window instead --
    // then both sectors settle, one window each.
    reg  [14:0] pf_ghost0, pf_ghost1;
    reg  [1:0]  pf_ghost_v;
    wire retn0 = pf_ghost_v[0] && (srv_beg[19:5] == pf_ghost0);
    wire retn1 = pf_ghost_v[1] && (srv_beg[19:5] == pf_ghost1);

    // Prefetch state -- one writer for every pf register.
    always @(posedge clk) begin
        if (reset) begin
            pf_cnt0    <= 6'd0;
            pf_cnt1    <= 6'd0;
            pf_lo0     <= 5'd0;
            pf_lo1     <= 5'd0;
            pf_base0   <= 20'h0;
            pf_base1   <= 20'h0;
            pf_live    <= 2'b00;
            pf_victim  <= 1'b1;
            pf_want    <= 1'b0;
            fill_ok    <= 1'b0;
            fill_beats <= 5'd0;
            pf_dead    <= 2'd0;
            pf_miss1   <= 1'b0;
            pf_pois    <= 15'h0;
            pf_pcnt    <= 8'd0;
            pf_ghost0  <= 15'h0;
            pf_ghost1  <= 15'h0;
            pf_ghost_v <= 2'b00;
        end else begin
            // A prefetch fill under way: beats append in address order
            // into ITS window, only while the fill still owns the
            // command phase and no invalidation has landed on it
            // (fill_ok covers the mid-fill case). A fill-on-miss pair
            // appends the same way -- its burst IS a fill.
            if (pf_beat_v && (cur_pf || cur_fillm) && fill_ok && bus_ours
                && (bstate == B_CMD)) begin
                // cnt saturates at the sector end -- a late beat from a
                // pair that already ended would otherwise wrap the index
                // back to 0 and overwrite fetched bytes.
                if (cur_pf_w) begin
                    if (!pf_cnt1[5]) begin
                        pf_buf[{1'b1, pf_cnt1[4:0]}] <= pf_beat_dat;
                        pf_cnt1 <= pf_cnt1 + 6'd1;
                    end
                end else begin
                    if (!pf_cnt0[5]) begin
                        pf_buf[{1'b0, pf_cnt0[4:0]}] <= pf_beat_dat;
                        pf_cnt0 <= pf_cnt0 + 6'd1;
                    end
                end
                fill_beats <= fill_beats + 5'd1;
            end

            // A guest read miss on eligible memory. In-sector misses
            // ride the bus; near misses rebase their own window's
            // stream; a second foreign miss claims the victim window.
            // Both windows dead simply seeds window 0.
            if (arm_rd_ok && (pf_pcnt != 8'd0))
                pf_pcnt <= pf_pcnt - 8'd1;

            if (arm_rd_ok) begin
                if (pf_poisoned)
                    // Poisoned sector: serve the miss off the bus and
                    // break the claim streak -- whatever stream lives
                    // here is write-mixed and a window would just die.
                    pf_miss1  <= 1'b0;
                else if (~|pf_live) begin
                    pf_base0   <= {srv_beg[19:5], 5'b0};
                    pf_cnt0    <= fillm_go ? {1'b0, srv_beg[4:0]} : 6'd0;
                    pf_lo0     <= fillm_go ? srv_beg[4:0] : 5'd0;
                    pf_live[0] <= 1'b1;
                    pf_victim  <= 1'b1;
                    pf_want    <= 1'b0;
                    pf_miss1   <= 1'b0;
                    pf_ghost_v <= 2'b00;
                end else if (insec0 || insec1) begin
                    pf_miss1  <= 1'b0;
                    // Fill-on-miss: the arming read's own burst appends
                    // from the miss offset. In-sector at or behind the
                    // fetched frontier it just regrows cnt (the loop head
                    // behind keeps its bytes); ahead of it or below lo
                    // the window re-anchors so no hole enters [lo, cnt).
                    if (fillm_go) begin
                        pf_want <= fillm_w;
                        if (fillm_w) begin
                            pf_cnt1 <= {1'b0, srv_beg[4:0]};
                            if (fillm_new) pf_lo1 <= srv_beg[4:0];
                        end else begin
                            pf_cnt0 <= {1'b0, srv_beg[4:0]};
                            if (fillm_new) pf_lo0 <= srv_beg[4:0];
                        end
                    end
                end
                else if (retn0) begin
                    // Miss back inside window0's abandoned sector: the
                    // stream returned -- give it window1 outright instead
                    // of letting `back` rebase window0 into a chase.
                    pf_ghost1  <= pf_base1[19:5];
                    pf_ghost_v[1] <= pf_live[1];
                    pf_base1   <= {srv_beg[19:5], 5'b0};
                    pf_cnt1    <= fillm_go ? {1'b0, srv_beg[4:0]} : 6'd0;
                    pf_lo1     <= fillm_go ? srv_beg[4:0] : 5'd0;
                    pf_live[1] <= 1'b1;
                    pf_victim  <= 1'b0;
                    pf_want    <= 1'b1;
                    pf_miss1   <= 1'b0;
                end else if (retn1) begin
                    pf_ghost0  <= pf_base0[19:5];
                    pf_ghost_v[0] <= pf_live[0];
                    pf_base0   <= {srv_beg[19:5], 5'b0};
                    pf_cnt0    <= fillm_go ? {1'b0, srv_beg[4:0]} : 6'd0;
                    pf_lo0     <= fillm_go ? srv_beg[4:0] : 5'd0;
                    pf_live[0] <= 1'b1;
                    pf_victim  <= 1'b1;
                    pf_want    <= 1'b0;
                    pf_miss1   <= 1'b0;
                end else if (cont0) begin
                    pf_ghost0  <= pf_base0[19:5];
                    pf_ghost_v[0] <= 1'b1;
                    pf_base0   <= {srv_beg[19:5], 5'b0};
                    pf_cnt0    <= fillm_go ? {1'b0, srv_beg[4:0]} : 6'd0;
                    pf_lo0     <= fillm_go ? srv_beg[4:0] : 5'd0;
                    pf_live[0] <= 1'b1;
                    pf_victim  <= 1'b1;
                    pf_want    <= 1'b0;
                    pf_miss1   <= 1'b0;
                end else if (cont1) begin
                    pf_ghost1  <= pf_base1[19:5];
                    pf_ghost_v[1] <= 1'b1;
                    pf_base1   <= {srv_beg[19:5], 5'b0};
                    pf_cnt1    <= fillm_go ? {1'b0, srv_beg[4:0]} : 6'd0;
                    pf_lo1     <= fillm_go ? srv_beg[4:0] : 5'd0;
                    pf_live[1] <= 1'b1;
                    pf_victim  <= 1'b0;
                    pf_want    <= 1'b1;
                    pf_miss1   <= 1'b0;
                end else if (pf_miss1) begin
                    // Second consecutive foreign miss: the victim takes
                    // the new stream's sector -- a dead window first,
                    // else the one not hitting lately.
                    if (!pf_live[1] || (pf_live[0] && pf_victim)) begin
                        pf_ghost1  <= pf_base1[19:5];
                        pf_ghost_v[1] <= pf_live[1];
                        pf_base1   <= {srv_beg[19:5], 5'b0};
                        pf_cnt1    <= fillm_go ? {1'b0, srv_beg[4:0]} : 6'd0;
                        pf_lo1     <= fillm_go ? srv_beg[4:0] : 5'd0;
                        pf_live[1] <= 1'b1;
                        pf_want    <= 1'b1;
                    end else begin
                        pf_ghost0  <= pf_base0[19:5];
                        pf_ghost_v[0] <= pf_live[0];
                        pf_base0   <= {srv_beg[19:5], 5'b0};
                        pf_cnt0    <= fillm_go ? {1'b0, srv_beg[4:0]} : 6'd0;
                        pf_lo0     <= fillm_go ? srv_beg[4:0] : 5'd0;
                        pf_live[0] <= 1'b1;
                        pf_want    <= 1'b0;
                    end
                    pf_victim <= ~pf_victim;
                    pf_miss1  <= 1'b0;
                end else
                    pf_miss1  <= 1'b1;
            end else if (hit_serve) begin
                // Hits belong to a different stream -- they must NOT
                // reset the foreign-miss streak, or a data read never
                // reaches two foreign misses between code hits and the
                // second window is never claimed at all. They only move
                // the victim off the just-hit window.
                pf_victim <= ~pf_hw;
            end

            // Invalidations: an overlapping guest write drops the
            // touched window before the write reaches memory; any I/O
            // write may move the map; a DMA grant means writes we
            // cannot see, so both windows die. Dropping pf_live too
            // keeps a dead window from refilling a sector nobody reads
            // -- the next miss re-seeds it where the stream actually is.
            if (!bus_ours || arm_iow) begin
                pf_cnt0 <= 6'd0;
                pf_cnt1 <= 6'd0;
                pf_lo0  <= 5'd0;
                pf_lo1  <= 5'd0;
                pf_live <= 2'b00;
                fill_ok <= 1'b0;
                pf_pcnt <= 8'd0;            // map changes lift the ban
                pf_ghost_v <= 2'b00;
            end else if (arm_wr || wrq_push) begin
                // ANY guest memory write poisons ITS OWN sector, not just
                // writes that overlap a live window: write-mixed sectors
                // (the CALL/RET stack, mailboxes, working data) are the
                // worst possible prefetch targets -- a window claimed on
                // the pop would be killed by the next push before a read
                // could ever use it. The earlier kill-only poison only
                // armed when a live window overlapped, and in the ghost-
                // claim rotation a code claim could evict the stack
                // window before the push ever landed, so the poison
                // never armed and the stack kept claiming (sim phase 8
                // fills rose to 2494). Tagging on the write closes that
                // race: the read that follows a write can never start a
                // doomed fill.
                pf_pois <= srv_addr[19:5];
                pf_pcnt <= 8'd255;
                if (wr_ovl0) begin
                    pf_cnt0    <= 6'd0;
                    pf_lo0     <= 5'd0;
                    pf_live[0] <= 1'b0;
                    pf_ghost_v[0] <= 1'b0;
                end
                if (wr_ovl1) begin
                    pf_cnt1    <= 6'd0;
                    pf_lo1     <= 5'd0;
                    pf_live[1] <= 1'b0;
                    pf_ghost_v[1] <= 1'b0;
                end
                if (cur_pf_w ? wr_ovl1 : wr_ovl0)
                    fill_ok <= 1'b0;
            end

            if (arm_fill || fillm_go) begin
                fill_ok    <= 1'b1;
                fill_beats <= 5'd0;
            end

            // Dead man's switch: a fill that completed with no
            // invalidation and appended zero beats means pf_beat_* is
            // not wired (legacy benches, a broken tap) -- stop spending
            // real bus cycles.
            if (pf_fill_done && fill_ok && (fill_beats == 5'd0)) begin
                if (pf_dead != 2'd3) pf_dead <= pf_dead + 2'd1;
                if (pf_dead == 2'd2) begin
                    pf_live    <= 2'b00;
                    pf_ghost_v <= 2'b00;
                end
            end
        end
    end

    // Posted write queue: push on the request's settle edge (the same
    // instant the tracker acks it), pop the head when its drain pair
    // arms -- the engine has latched the operands by then and serial
    // pair order carries the rest. Push and pop may share a clk; the
    // push then lands at the post-pop tail.
    wire        wrq_pop  = arm_drain;
    wire [2:0]  wrq_tail = wrq_cnt - (wrq_pop ? 3'd1 : 3'd0);

    always @(posedge clk) begin
        if (reset) begin
            wrq_cnt <= 3'd0;
        end else begin
            if (wrq_pop) begin
                for (int i = 0; i < WQ_N-1; i++) begin
                    wrq_addr[i] <= wrq_addr[i+1];
                    wrq_data[i] <= wrq_data[i+1];
                    wrq_ube[i]  <= wrq_ube[i+1];
                end
            end
            if (wrq_push) begin
                wrq_addr[wrq_tail] <= srv_addr;
                wrq_data[wrq_tail] <= srv_data;
                wrq_ube[wrq_tail]  <= srv_ube;
            end
            case ({wrq_push, wrq_pop})
                2'b10:   wrq_cnt <= wrq_cnt + 3'd1;
                2'b01:   wrq_cnt <= wrq_cnt - 3'd1;
                default: wrq_cnt <= wrq_cnt;
            endcase
        end
    end

`ifdef ZET_DBG_WQ
    reg rdy_seen;  // processor_ready dipped this pair
    reg [7:0] db_seen; // data_bus at accept
    always @(posedge clk) begin
        if (bstate == B_IDLE) rdy_seen <= 1'b0;
        else if (!processor_ready) rdy_seen <= 1'b1;
        if (bstate == B_CMD && cpu_ce_posedge && processor_ready && bus_ours
            && (t_cnt >= 3'd3 || (fast_pair && t_cnt >= 3'd2 && (saw_low || cur_dq))))
            db_seen <= data_bus;
        if (wb_req && !req_busy && !wb_ack_i && !inta_active && !wb_tgc_o)
            $display("  %8t  WBREQ %s a=%05x sel=%b d=%04x", $time, wb_we_o ? "WR" : "RD", {wb_adr_o, wb_sel_o == 2'b10}, wb_sel_o, wb_dat_o);
        if (bstate == B_IDLE && (arm_req || arm_drain || arm_fill || hit_serve))
            $display("  %8t  ARM %s a=%05x dq=%b pf=%b", $time,
                     arm_drain ? "DRN" : arm_fill ? "FIL" : hit_serve ? "HIT"
                               : fillm_go ? "FLM" : "REQ",
                     arm_drain ? wrq_addr[0] : srv_addr, cur_dq, cur_pf);
        if (bstate == B_CMD && cpu_ce_posedge && processor_ready && bus_ours
            && (t_cnt >= 3'd3 || (fast_pair && t_cnt >= 3'd2 && (saw_low || cur_dq))))
            $display("  %8t  ACC bs=%0d a=%05x db=%02x tc=%0d saw=%b dq=%b", $time, cur_bs, cur_addr, data_bus, t_cnt, saw_low, cur_dq);
        if (wrq_push)  $display("  %8t  WQ PUSH  a=%05x d=%04x ube=%b cnt=%0d", $time, srv_addr, srv_data, srv_ube, wrq_cnt);
        if (arm_drain) $display("  %8t  WQ DRAIN a=%05x d=%04x ube=%b cnt=%0d", $time, wrq_addr[0], wrq_data[0], wrq_ube[0], wrq_cnt);
        if (pair_done && req_busy && !cur_pf && !cur_dq && (cur_bs == BS_MEMR || cur_bs == BS_CODE))
            $display("  %8t  RDRET   a=%05x lo=%02x hi=%02x idx=%0d db=%02x rdy_dip=%b saw=%b", $time, cur_addr, rd_lo, rd_hi, byte_idx, db_seen, rdy_seen, saw_low);
        if (hit_serve) $display("  %8t  PFHIT    a=%05x w=%04x", $time, srv_addr, pf_hit_word);
        if (fwd_serve) $display("  %8t  FWDSRV   a=%05x w=%04x", $time, srv_addr, fwd_word);
        if (arm_fill)  $display("  %8t  PFFILL   a=%05x len=%0d w=%0d", $time, pf_next[19:0], pf_fill_len, fill_w);
        if (arm_rd_ok && bus_ours) begin
            if (pf_poisoned)      $display("  %8t  PFMISS a=%05x POIS", $time, srv_beg);
            else if (~|pf_live)   $display("  %8t  PFMISS a=%05x SEED", $time, srv_beg);
            else if (insec0||insec1) $display("  %8t  PFMISS a=%05x RIDE live=%b", $time, srv_beg, pf_live);
            else if (retn0)       $display("  %8t  PFMISS a=%05x RETN0->w1 g=%05x", $time, srv_beg, pf_ghost0);
            else if (retn1)       $display("  %8t  PFMISS a=%05x RETN1->w0 g=%05x", $time, srv_beg, pf_ghost1);
            else if (cont0)       $display("  %8t  PFMISS a=%05x CONT0", $time, srv_beg);
            else if (cont1)       $display("  %8t  PFMISS a=%05x CONT1", $time, srv_beg);
            else if (pf_miss1)    $display("  %8t  PFMISS a=%05x CLAIM", $time, srv_beg);
            else                  $display("  %8t  PFMISS a=%05x m1", $time, srv_beg);
        end
    end
`endif

    always @(posedge clk) begin
        if (reset) begin
            bstate           <= B_IDLE;
            byte_idx         <= 2'd0;
            t_cnt            <= 3'd0;
            saw_low          <= 1'b0;
            fill_wait        <= 7'd0;
            ready_d1         <= 1'b0;
            gap_cnt          <= 2'd0;
            rd_lo            <= 8'h00;
            rd_hi            <= 8'h00;
            int_vector       <= 8'h00;
            cur_bs           <= BS_PASV;
            cur_addr         <= 20'h0;
            cur_ube_n        <= 1'b1;
            cur_data         <= 16'h0;
            cur_term         <= TERM_NONE;
            cur_inta         <= 1'b0;
            cur_pf           <= 1'b0;
            cur_fillm        <= 1'b0;
            cur_pf_len       <= 5'd0;
            cur_pf_w         <= 1'b0;
            cur_dq           <= 1'b0;
            ps_r             <= BS_PASV;
            ad_out           <= 20'h0;
            cpu_data_bus     <= 8'h00;
            word_access      <= 1'b0;
            cpu_data_bus_hi  <= 8'h00;
            rd_word          <= 16'h0000;
            biu_done_r       <= 1'b0;
        end else begin
            biu_done_r <= 1'b0;
            ready_d1   <= processor_ready;
            // A prefetch-window hit retires a request with no bus cycle:
            // the queue's bytes go onto rd_word exactly where the normal
            // path leaves its assembled word, and the req block pulses
            // ack on the same edge.
            if (hit_serve) begin
                rd_word    <= pf_hit_word;
                biu_done_r <= 1'b1;
            end
            if (fwd_serve) begin
                rd_word    <= fwd_word;
                biu_done_r <= 1'b1;
            end
            case (bstate)
              B_IDLE: begin
                if (arm_req) begin
                    cur_bs           <= srv_bs;
                    cur_addr         <= srv_addr;
                    cur_ube_n        <= srv_ube;
                    cur_data         <= srv_data;
                    cur_term         <= srv_term;
                    cur_inta         <= srv_inta;
                    cur_pf           <= 1'b0;
                    cur_fillm        <= fillm_go;
                    cur_pf_w         <= fillm_w;
                    cur_pf_len       <= fillm_len;
                    cur_dq           <= 1'b0;
                    ps_r             <= (srv_term == TERM_WORD)
                                      ? BS_PASV : srv_bs;
                    ad_out           <= srv_byte_addr;
                    cpu_data_bus     <= srv_byte_data;
                    word_access      <= srv_inta ? 1'b0
                                      : word_1cyc(srv_bs, srv_addr, srv_ube);
                    cpu_data_bus_hi  <= srv_data[15:8];
                    t_cnt            <= 3'd0;
                    saw_low          <= 1'b0;
                    fill_wait        <= 7'd0;
                    bstate           <= B_CMD;
                end else if (arm_drain) begin
                    // Queued write head, replayed as an ordinary write
                    // pair. Its byte count/ube came with the entry; the
                    // pair engine treats it exactly like a guest write.
                    cur_bs           <= BS_MEMW;
                    cur_addr         <= wrq_addr[0];
                    cur_ube_n        <= wrq_ube[0];
                    cur_data         <= wrq_data[0];
                    cur_term         <= TERM_NONE;
                    cur_inta         <= 1'b0;
                    cur_pf           <= 1'b0;
                    cur_fillm        <= 1'b0;
                    cur_dq           <= 1'b1;
                    ps_r             <= BS_MEMW;
                    ad_out           <= wrq_addr[0];
                    cpu_data_bus     <= wrq_addr[0][0] ? wrq_data[0][15:8]
                                                       : wrq_data[0][7:0];
                    word_access      <= word_1cyc(BS_MEMW, wrq_addr[0],
                                                  wrq_ube[0]);
                    cpu_data_bus_hi  <= wrq_data[0][15:8];
                    t_cnt            <= 3'd0;
                    saw_low          <= 1'b0;
                    fill_wait        <= 7'd0;
                    bstate           <= B_CMD;
                end else if (arm_fill) begin
                    // Prefetch fill: a byte-style pair (ube_n=1, so the
                    // pair is one byte) whose read strobe carries
                    // pf_req_len -- RAM turns the one strobe into a
                    // cur_pf_len-word burst and the beats stream back on
                    // pf_beat_*. Nothing downstream can tell it apart
                    // from a guest's own read, and nothing consumes
                    // rd_word for it.
                    cur_bs           <= BS_MEMR;
                    cur_addr         <= pf_next[19:0];
                    cur_ube_n        <= 1'b1;
                    cur_data         <= 16'h0000;
                    cur_term         <= TERM_NONE;
                    cur_inta         <= 1'b0;
                    cur_pf           <= 1'b1;
                    cur_fillm        <= 1'b0;
                    cur_dq           <= 1'b0;
                    cur_pf_w         <= fill_w;
                    cur_pf_len       <= pf_fill_len;
                    ps_r             <= BS_MEMR;
                    ad_out           <= pf_next[19:0];
                    cpu_data_bus     <= 8'h00;
                    word_access      <= 1'b0;
                    cpu_data_bus_hi  <= 8'h00;
                    t_cnt            <= 3'd0;
                    saw_low          <= 1'b0;
                    fill_wait        <= 7'd0;
                    bstate           <= B_CMD;
                end
              end

              B_CMD: begin
                // The dip must be a falling edge while we own the bus. A
                // level test fails at the AEN release: bus_ours returns on
                // the combinational address_enable_n while the ready chain
                // is still draining dma_wait, so processor_ready sits low
                // for a couple of clks with the byte's access never having
                // run -- saw_low armed falsely, and the fast accept then
                // fired the moment the chain drained, far ahead of the
                // re-asserted strobe's real data (realmem+freeze repro:
                // fetch at f801d accepted 3 clks after release and came
                // back fe, the hardware signature). A genuine access dips
                // ready AFTER it was seen high -- the edge marks it.
                if (ready_d1 && !processor_ready && bus_ours)
                    saw_low <= 1'b1;
                if (cpu_ce_posedge)
                    t_cnt <= (t_cnt != 3'd7) ? (t_cnt + 3'd1) : 3'd7;
                if (fill_wait != 7'd127)
                    fill_wait <= fill_wait + 7'd1;

                // Fast accept (t_cnt>=2) only on a FRESH ready: the level can
                // still be the previous byte's residue, which would capture
                // stale bus data. A drain write is exempt from saw_low -- for
                // a write strobe, RAM's wr_strobe_open holds ready low until
                // the byte is durably captured, so a high ready already means
                // "taken" and cannot be the previous byte's residue.
                // The t_cnt>=3 fallback keeps never-dropping accesses
                // (instant I/O) on the faithful count.
                if ((t_cnt >= 3'd3
                     || (fast_pair && (t_cnt >= 3'd2) && (saw_low || cur_dq)))
                    && cpu_ce_posedge && processor_ready && bus_ours
                    && !fill_early) begin
                    if (cur_read && (byte_idx == 2'd0)) rd_lo <= data_bus;
                    if (cur_read && (byte_idx == 2'd1)) rd_hi <= data_bus;
                    if (cur_read && cur_1cyc)           rd_hi <= data_bus_hi;
                    ps_r             <= BS_PASV;
                    gap_cnt          <= 2'd0;
                    bstate           <= B_GAP;
                end
              end

              B_GAP: begin
                if (cpu_ce_posedge)
                    gap_cnt <= gap_cnt + 2'd1;

                if (pair_finish) begin
                    if (last_byte) begin
                        if (cur_inta) begin
                            int_vector  <= rd_hi;   // ACK2's byte
                            biu_done_r  <= 1'b1;
                        end else if (!cur_pf && !cur_dq) begin
                            if (cur_term == TERM_WORD)
                                rd_word <= 16'h2588;
                            else if (cur_term == TERM_ACTIVE)
                                rd_word <= {rd_word[15:8], rd_lo};
                            else if (cur_term == TERM_PLUS)
                                rd_word <= {8'hFF, rd_lo};
                            else if (cur_term == TERM_MINUS)
                                rd_word <= {8'h00, rd_lo};
                            else if (cur_term == TERM_EXT08)
                                rd_word <= {8'h08, rd_lo};
                            else if (cur_word)
                                rd_word <= {rd_hi, rd_lo};
                            else if (cur_addr[0])
                                rd_word <= {rd_lo, rd_lo};
                            else
                                rd_word <= {rd_lo, rd_lo};
                            biu_done_r <= 1'b1;
                        end
                        cur_pf      <= 1'b0;
                        cur_fillm   <= 1'b0;
                        cur_dq      <= 1'b0;
                        byte_idx    <= 2'd0;
                        word_access <= 1'b0;
                        bstate      <= B_IDLE;
                    end else begin
                        byte_idx <= 2'd1;
                        bstate   <= B_IDLE;
                    end
                end
              end

              default: bstate <= B_IDLE;
            endcase
        end
    end

    assign dbg = {zet_halt, inta_active, req_busy, wb_ack_i,
                  bstate, byte_idx, t_cnt, gap_cnt, cur_bs};

endmodule

`default_nettype wire
