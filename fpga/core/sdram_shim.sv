//
// sdram_shim — wraps sdram_mp in the request/flag handshake RAM.sv speaks.
//
// RAM.sv uses a level-request / pulse-flag protocol for one word at a time,
// which is a subset of what sdram_mp does. The mapping is:
//
//   write_request                ->  latched into a small posted-write FIFO
//                                    (see the port-A block below); the flag
//                                    is a one-cycle accept pulse
//   read_request                 ->  p_req + p_we, issued once the FIFO has
//                                    drained so reads never pass writes
//   write_flag / read_flag      ->  held while the access is owned: the
//                                    write's accept pulse; the read's whole
//                                    latch-to-done span
//   idle                        ->  "a command can be accepted now", low
//                                   during refresh and while the FIFO drains
//   data_out                    ->  latched from p_rdata on p_rvalid
//
// `enable_refresh` is ignored: sdram_mp refreshes on its own interval counter
// rather than being told when the bus is quiet. `refresh_mode` still has to be
// reported, because RAM.sv drops access_ready when a command collides with a
// refresh.
//
// Clocking: this runs the controller at whatever `sdram_clock` the chipset
// supplies (clk_chipset, 42.95 MHz) rather than at clk_core.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module sdram_shim #(
    // Published so the port list can use them; the internals below re-derive
    // the same values as localparams.
    parameter int ADDR_BITS_PUB    = 24,
    parameter int LEN_BITS_PUB     = 4,
    parameter int sdram_col_width  = 9,
    parameter int sdram_row_width  = 13,
    parameter int sdram_bank_width = 2,
    parameter int sdram_data_width = 16,
    // Timing in sdram_clock cycles. Defaults suit 42.95 MHz (23.3 ns); they are
    // deliberately loose, since one wait state costs nothing at one word per
    // transaction.
    parameter int T_RCD            = 2,
    parameter int T_RP             = 2,
    parameter int T_WR             = 2,
    parameter int T_RFC            = 4,
    // Back to CL=2. CL=3 was tried (testB22) on the theory that it would buy a
    // clock of read margin; STA did not move (-2.357 vs -2.408) and neither did
    // the hardware. It was the wrong lever: the constraint measures the pin-to-
    // pin relationship between the part launching data and the FPGA capturing
    // it, and CL changes when the data comes out, not how it is caught.
    parameter int CAS_LATENCY      = 2,
    parameter int INIT_NOP         = 10000,  // 233 us: the SDRAM's own init wait
    parameter int REFRESH_INT      = 288     // <= 7.8 us at 42.95 MHz, with
                                             // headroom for a 16-beat burst
                                             // in flight when the timer dues
                                             // (wait ~36 -> 324 < 335 spec)
) (
    input  wire                               sdram_clock,
    input  wire                               sdram_reset,

    input  wire  [sdram_col_width
                  + sdram_row_width
                  + sdram_bank_width-1:0]     address,
    input  wire  [sdram_col_width-1:0]        access_num,
    input  wire  [sdram_data_width-1:0]       data_in,
    output logic [sdram_data_width-1:0]       data_out,
    // The second word of a two-word access on this port. RAM.sv stores ONE
    // GUEST BYTE PER 16-BIT SDRAM WORD (access_data_in is {8'h00, byte} and
    // the write mask is all-ones), so the guest's byte N and byte N+1 are
    // consecutive SDRAM WORDS. That makes a V30 word access one burst of two
    // rather than two transactions: one arbitration, one ACTIVATE, one extra
    // column clock. access_num picks the shape -- 1 or 2, nothing else -- and
    // these two carry the second word in each direction.
    //
    // A two-word read lands beat by beat: the first word is the addressed
    // byte, the second its odd half. RAM.sv only asks for two words when
    // word_access is up -- a guest word at an address the SDRAM serves.
    input  wire  [sdram_data_width-1:0]       data_in_hi,
    output logic [sdram_data_width-1:0]       data_out_hi,
    // Per-beat read taps for the prefetch engine: a_rvalid pulses the cycle
    // AFTER each p_rvalid, so a_beat already holds that beat's word. Only
    // port A produces them; a burst's beats arrive in address order.
    output logic                              a_rvalid,
    output logic [sdram_data_width-1:0]       a_beat,
    input  wire                               write_request,
    input  wire                               read_request,
    input  wire                               enable_refresh,
    output logic                              write_flag,
    output logic                              read_flag,
    output logic                              refresh_mode,
    output logic                              idle,

    output logic [sdram_row_width-1:0]        sdram_address,
    output logic                              sdram_cke,
    output logic                              sdram_cs,
    output logic                              sdram_ras,
    output logic                              sdram_cas,
    output logic                              sdram_we,
    output logic [sdram_bank_width-1:0]       sdram_ba,
    input  wire  [sdram_data_width-1:0]       sdram_dq_in,
    output logic [sdram_data_width-1:0]       sdram_dq_out,
    output logic                              sdram_dq_io,

    // ---------------------------------------------------------------- port B
    //
    // A second, read-only master, for the video side's font fetch. This is
    // what sdram_mp being multi-port was for: FONT.ROM is 282 KB against about
    // 202 KB of free M10K, so it lives in SDRAM and glyphs are read while the
    // picture is drawn.
    //
    // The controller is instanced with two ports on BOTH machines rather than
    // conditionally, because making the port count depend on a macro makes
    // every signal width depend on it too. Tie b_req low if unused: the
    // round-robin never grants it, and the guest path behaves as it did.
    input  wire                               b_req,      /* tie low if unused */
    input  wire  [ADDR_BITS_PUB-1:0]          b_addr,
    input  wire  [LEN_BITS_PUB-1:0]           b_len,
    output logic                              b_ack,
    output logic                              b_rvalid,
    output logic [sdram_data_width-1:0]       b_rdata,
    output logic                              b_done,

    // ---------------------------------------------------------------- port C
    //
    // The character generator window, which the guest reads glyphs through. It
    // is idle almost all the time -- one prefetch per character the guest asks
    // for -- so it gets a port of its own rather than a priority scheme against
    // the row buffer, which runs for the whole visible frame.
    input  wire                               c_req,
    input  wire  [ADDR_BITS_PUB-1:0]          c_addr,
    input  wire  [LEN_BITS_PUB-1:0]           c_len,
    output logic                              c_ack,
    output logic                              c_rvalid,
    output logic [sdram_data_width-1:0]       c_rdata,
    output logic                              c_done,

    // ---------------------------------------------------------------- port D
    //
    // The graphics plane's display fetch: twenty sixteen-word bursts per
    // scanline, four planes of eighty bytes each. Like C it is read-only; the
    // round robin inside sdram_mp shares the line time with the row buffer's
    // five bursts and the guest's traffic.
    input  wire                               d_req,
    input  wire  [ADDR_BITS_PUB-1:0]          d_addr,
    input  wire  [LEN_BITS_PUB-1:0]           d_len,
    output logic                              d_ack,
    output logic                              d_rvalid,
    output logic [sdram_data_width-1:0]       d_rdata,
    output logic                              d_done,

    // ---------------------------------------------------------------- port E
    //
    // fdd_ramimg's carve-out access: single-word writes while a JTAG upload
    // fills the image, sixteen-word read bursts while it serves sectors.
    // Unlike B/C/D this port writes, so it carries wdata -- held stable for
    // the whole transaction, because sdram_mp samples p_wdata at each WRITE
    // beat rather than at grant time.
    input  wire                               e_req,      /* tie low if unused */
    input  wire                               e_we,
    input  wire  [ADDR_BITS_PUB-1:0]          e_addr,
    input  wire  [LEN_BITS_PUB-1:0]           e_len,
    input  wire  [sdram_data_width-1:0]       e_wdata,
    output logic                              e_ack,
    output logic                              e_rvalid,
    output logic [sdram_data_width-1:0]       e_rdata,
    output logic                              e_done,

    // ---------------------------------------------------------------- port F
    //
    // The CPU's line cache (z86_cache): line fills as bursts of up to sixteen
    // words, and write-through stores of one or two words. Like E it writes,
    // and its payload is held for the whole transaction; f_wdata1 is the
    // second word of a two-word store -- nothing longer is ever written, so
    // the p_wcnt select below needs only the two. The caller keeps a burst
    // inside one 512-word column.
    input  wire                               f_req,      /* tie low if unused */
    input  wire                               f_we,
    input  wire  [ADDR_BITS_PUB-1:0]          f_addr,
    input  wire  [LEN_BITS_PUB-1:0]           f_len,
    input  wire  [sdram_data_width-1:0]       f_wdata0,
    input  wire  [sdram_data_width-1:0]       f_wdata1,
    output logic                              f_ack,
    output logic                              f_rvalid,
    output logic [sdram_data_width-1:0]       f_rdata,
    output logic                              f_done,

    // Port A write-commit snoop, for the cache to invalidate against: a_wr_v
    // pulses for the one cycle in which a guest/DMA/loader write on port A
    // has completed in the SDRAM, with that write's word address and length
    // (words - 1: 0 or 1, port A writes a byte or a V30 word). addr_r/len_r
    // are frozen while busy, so the pair is valid alongside the pulse. Port
    // E (the floppy carve-out, never cached) is not snooped.
    output logic                              a_wr_v,
    output logic [ADDR_BITS_PUB-1:0]          a_wr_addr,
    output logic [LEN_BITS_PUB-1:0]           a_wr_len,
    // JTAG probe (PC98_JTAG): the wedge tap's port-A / controller view.
    //   [39:32] a_req_age  -- clk cycles req has waited for a grant
    //                         (saturates 0xFF; the round-robin grants port A
    //                         within ~a refresh + one 16-beat burst, so a
    //                         pegged counter means starvation or a lost req)
    //   [31:24] a_busy_age -- clk cycles the taken transaction has run
    //                         without p_done (saturates; a normal word is
    //                         ~10-40 clk incl. refresh)
    //   [23:18] mp_req     -- the six live p_req lines, {F,E,D,C,B,A}
    //   [17:4]  mp dbg     -- sdram_mp's {state[3:0], rr_ptr[2:0],
    //                         refresh_due, pre_guard!=0, stat_idle, have_req,
    //                         grant[2:0]}
    //   [3] busy [2] req [1] we_r -- the port-A handshake registers
    //   [0] 0
    // Registered at the core_top boundary into the frozen wedge snapshot
    // (probe slots 0xA2/0xA3).
    output logic [39:0]                       dbg_w
);

    localparam int ADDR_BITS = sdram_col_width + sdram_row_width + sdram_bank_width;
    localparam int MASK_BITS = sdram_data_width/8;

    // Port A's caller only ever asks for one word at a time, so it never bursts and
    // its address never has to be checked against a column boundary. BURST_MAX
    // is 16 for port B: a glyph is sixteen bytes and RAM.sv stores one byte per
    // word, so that is one transaction instead of sixteen.
    localparam int BURST_MAX = 16;
    localparam int LEN_BITS  = (BURST_MAX > 1) ? $clog2(BURST_MAX) : 1;
    localparam int PORTS     = 6;

    // Port-A posted-write FIFO depth (the block comment below). Three
    // entries behind the engine's one in flight matches RAM.sv's own
    // four-deep park queue: the drain never starves the device while the
    // master above still has somewhere to park.
    localparam int AQ_DEPTH = 3;

    // sdram_mp schedules its own refresh and has no cs pin: the SDRAM's chip
    // select is permanently asserted.
    wire _unused_refresh = enable_refresh;
    assign sdram_cs = 1'b0;

    // ------------------------------------------------------------------
    // Port A -- a posted-write queue in front of a serial engine.
    //
    // RAM.sv used to drain its parked writes one transaction per FSM lap:
    // IDLE accepts, WRITE_1 presents, the shim latched, sdram_mp granted,
    // the beats ran, p_done, WRITE_2, COMPLETE, IDLE -- around nine clocks
    // of which only two were SDRAM beats. A GRCG walk parks four plane
    // legs per guest word, so the park FIFO filled faster than that and
    // the CPU stalled on queue-full instead of on the SDRAM itself
    // (tb_mem_perf ph11 measured ~38% of cycles with all four park slots
    // taken). The turnaround, not the device, was the wall.
    //
    // Writes therefore decouple here. The flag handshake answers "durably
    // taken" the cycle the request latches into a three-deep FIFO, and one
    // engine drains that FIFO to sdram_mp port A with back-to-back
    // transactions. Ordering is the whole safety argument, and it is the
    // old serial contract moved one level down:
    //
    //   * the engine works strictly in arrival order. FIFO entries go
    //     first, and a read is only latched once RAM.sv's own serial FSM
    //     can no longer have a write ahead of it; a push while a read is
    //     pending is refused (defensively impossible from RAM.sv, whose
    //     outputs drive exactly one request at a time, but refused all
    //     the same);
    //   * a latched read is issued only after the FIFO drains, so a read
    //     behind posted writes still sees them (tb_gvram_ram_leg's racy
    //     TCR read behind a posted-write train);
    //   * a full FIFO withholds the flag rise, which parks RAM.sv in
    //     WRITE_1 -- exactly the backpressure a busy shim always applied.
    //
    // The one behavioural change above the port: write_flag is now a
    // one-cycle ACCEPT pulse instead of the transaction's full length.
    // RAM.sv edges on the rise (WRITE_1 -> WRITE_2) and on the fall
    // (WRITE_2 -> COMPLETE), so a pulse drives it one lap per write with
    // the handshake it always saw. COMPLETE arrives earlier -- that is
    // the point: the write is durably held here, drains in order behind
    // whatever the device is doing, and nothing above reads write_flag as
    // a level. Reads keep the old semantics: read_flag spans latch to
    // p_done, because a read's data is not back until the device returns
    // it.
    //
    // The engine also chains: at a write's p_done it loads the next FIFO
    // head in the same edge, so consecutive port-A transactions reach the
    // controller with one grant gap instead of a whole shim+RAM lap.
    // ------------------------------------------------------------------

    // FIFO slots, head first (the RAM.sv park-queue idiom: shift on pop).
    // Full SDRAM words: RAM.sv only ever drives {8'h00, byte} into them,
    // but the shim's own contract (tb_sdram_shim) is the whole word.
    logic                  aq0_v, aq1_v, aq2_v;
    logic [ADDR_BITS-1:0]  aq0_addr, aq1_addr, aq2_addr;
    logic                  aq0_word, aq1_word, aq2_word;  // 1 = two-word write
    logic [sdram_data_width-1:0] aq0_d0, aq1_d0, aq2_d0;
    logic [sdram_data_width-1:0] aq0_d1, aq1_d1, aq2_d1;
    // The entry pushed by the request still on the pins. data_in can be
    // RAM.sv's registered follower one clock behind the bus on a live
    // accept, so the pushed entry keeps resampling while write_request
    // holds (the old `busy && we_r` resample, narrowed to the window
    // where the operand is still the caller's). The bit travels with the
    // entry because older heads can pop and shift it mid-window.
    logic                  aq0_open, aq1_open, aq2_open;

    // The latched read: one slot, no queueing -- a second read cannot
    // arrive until read_flag falls, which is this read's p_done.
    logic                  rd_busy;
    logic [ADDR_BITS-1:0]  rd_addr;
    logic [LEN_BITS-1:0]   rd_len;

    // The engine: one port-A transaction at a time, exactly the req/we/
    // addr/len presentation the controller always saw.
    logic        req, we_r, eng_busy;
    logic [ADDR_BITS-1:0] addr_r;
    logic [LEN_BITS-1:0]  len_r;
    logic [LEN_BITS-1:0]  rbeat;      // which word of the burst is next
    logic        wflag_q;             // the accept pulse
    logic        p_ack, p_done, p_rvalid, stat_idle, stat_refresh;
    logic [sdram_data_width-1:0] p_rdata;
    logic        mp_rvalid;
    logic [sdram_data_width-1:0] mp_rdata;

    wire [sdram_data_width-1:0] din_lo = data_in;
    wire [sdram_data_width-1:0] din_hi = data_in_hi;
    // An open entry presents the live operand, not its stale snapshot --
    // the engine may already be consuming it as the head (this is the old
    // resample-through-the-transaction behaviour, kept for the window).
    wire [sdram_data_width-1:0] aq0_d0e = aq0_open ? din_lo : aq0_d0;
    wire [sdram_data_width-1:0] aq0_d1e = aq0_open ? din_hi : aq0_d1;
    wire [sdram_data_width-1:0] aq1_d0e = aq1_open ? din_lo : aq1_d0;
    wire [sdram_data_width-1:0] aq1_d1e = aq1_open ? din_hi : aq1_d1;
    wire [sdram_data_width-1:0] aq2_d0e = aq2_open ? din_lo : aq2_d0;
    wire [sdram_data_width-1:0] aq2_d1e = aq2_open ? din_hi : aq2_d1;

    wire [1:0] q_count = 2'(aq0_v + aq1_v + aq2_v);
    wire       pop_now = eng_busy & we_r & p_done;
    wire [1:0] push_idx = q_count - pop_now;
    // One push per request window: RAM.sv holds write_request for the
    // whole handshake, and a held strobe whose OPERANDS changed is a new
    // transfer that RAM.sv itself parks separately -- re-pushing the same
    // request every cycle would duplicate every write. The window's push
    // may still come late (a full FIFO holds it until a slot frees),
    // which is exactly the old "!busy" gate one level down.
    logic      wreq_done;
    wire       push_now = write_request & ~rd_busy & ~wreq_done
                        & ((q_count - pop_now) < 2'(AQ_DEPTH));
    // The next head AFTER this edge's pop -- what a chaining engine loads.
    wire       nx_wr_v    = pop_now ? aq1_v    : aq0_v;
    wire [ADDR_BITS-1:0] nx_wr_addr  = pop_now ? aq1_addr  : aq0_addr;
    wire       nx_wr_word = pop_now ? aq1_word : aq0_word;

    // ------------------------------------------------------------------
    // Read reordering: a latched read may be issued AHEAD of queued writes
    // it provably cannot overlap -- RAM.sv's own rd_conflicts rule,
    // extended across this queue (RAM.sv can only check writes still in
    // ITS park FIFO; once dequeued here they are invisible to it, and
    // strict FIFO here was making every RMW/EGC read leg wait out the
    // whole write backlog of its own walk -- writes that target OTHER
    // planes and can never collide). The disjointness test is 1K-word
    // block granularity (a 14-bit address prefix compare, not a 24-bit
    // range adder): same block => assume conflict; a read whose range
    // CROSSES a block boundary (rd_cross) is always conflicting, so
    // "different block" really does mean disjoint. Plane legs are 0x8000
    // words apart, so the granularity loses nothing on the walk that
    // motivated this.
    //
    // Ordering stays sound: the read only passes writes it provably cannot
    // read behind; and a write can never push while a read waits on a
    // conflict, because RAM.sv cannot present a write_request until the
    // read's flag falls (its FSM is serial) -- so "younger write passes an
    // older waiting read" has no producer.
    // ------------------------------------------------------------------
    wire       rd_cross = ({1'b0, rd_addr[9:0]} + {7'd0, rd_len}) >= 11'd1024;
    wire [13:0] rd_blk  = rd_addr[23:10];
    wire rd_conflict_q = rd_cross
                       | (aq0_v & (aq0_addr[23:10] == rd_blk))
                       | (aq1_v & (aq1_addr[23:10] == rd_blk))
                       | (aq2_v & (aq2_addr[23:10] == rd_blk));
    // What the engine takes when it frees: the read if one waits and the
    // queue holds nothing it conflicts with (or nothing at all); else the
    // head write. nx_* below is the write head after this edge's pop.
    //
    // MITIGATION 2026-10-26 (hardware freeze, CI 1000 build): two cold
    // boots froze in BIOS POST with RAM.sv parked in R2 and the latched
    // read never completing -- different addresses each boot, i.e. a race,
    // not a stuck bit. The read-side reorder and the controller's fused
    // grant-issue are the only two read-path timing changes in a2f0d62, so
    // both are switched off here pending a root cause; strict arrival
    // order (read only when the queue is empty) is the pre-a2f0d62
    // contract. The posted-write queue itself -- where the measured win
    // lives -- stays on.
    localparam bit READ_REORDER = 1'b0;
    wire       eng_rd_next = rd_busy
                          & ~(nx_wr_v & (READ_REORDER ? rd_conflict_q : 1'b1));

    always_ff @(posedge sdram_clock or posedge sdram_reset) begin
        if (sdram_reset) begin
            req         <= 1'b0;
            we_r        <= 1'b0;
            eng_busy    <= 1'b0;
            wflag_q     <= 1'b0;
            addr_r      <= '0;
            len_r       <= '0;
            rbeat       <= 1'b0;
            aq0_v       <= 1'b0;
            aq1_v       <= 1'b0;
            aq2_v       <= 1'b0;
            aq0_addr    <= '0;
            aq1_addr    <= '0;
            aq2_addr    <= '0;
            aq0_word    <= 1'b0;
            aq1_word    <= 1'b0;
            aq2_word    <= 1'b0;
            aq0_d0      <= '0;
            aq1_d0      <= '0;
            aq2_d0      <= '0;
            aq0_d1      <= '0;
            aq1_d1      <= '0;
            aq2_d1      <= '0;
            aq0_open    <= 1'b0;
            aq1_open    <= 1'b0;
            aq2_open    <= 1'b0;
            wreq_done   <= 1'b0;
            rd_busy     <= 1'b0;
            rd_addr     <= '0;
            rd_len      <= '0;
            data_out    <= '0;
            data_out_hi <= '0;
            a_rvalid    <= 1'b0;
            a_beat      <= '0;
        end else begin
            // Read beats arrive in address order: the first belongs to the
            // addressed byte and the second to the odd half. rbeat saturates
            // at the burst's last index instead of toggling, so on a longer
            // burst (a bridge fill-on-miss read) data_out/data_out_hi stay
            // pinned on beats 0/1 -- the guest's own bytes -- while the
            // a_beat stream carries every word for the window append.
            if (p_rvalid) begin
                if (rbeat == LEN_BITS'(0))      data_out    <= p_rdata;
                else if (rbeat == LEN_BITS'(1)) data_out_hi <= p_rdata;
                if (rbeat != len_r)             rbeat       <= rbeat + 1'b1;
            end
            // One-beat-delayed view for prefetch captures: at a_rvalid's
            // cycle, a_beat and data_out/data_out_hi are all settled.
            a_rvalid <= p_rvalid;
            if (p_rvalid) a_beat <= p_rdata;

            // ---- the open entry's resample (see aq*_open) ---------------
            if (aq0_open) begin aq0_d0 <= din_lo; aq0_d1 <= din_hi; end
            if (aq1_open) begin aq1_d0 <= din_lo; aq1_d1 <= din_hi; end
            if (aq2_open) begin aq2_d0 <= din_lo; aq2_d1 <= din_hi; end

            // ---- pop: the engine committed the head write ---------------
            // Shift uses the eff values so an open entry carries its latest
            // sample down with it; the open bits close when the request
            // window ends, whenever they travel.
            if (pop_now) begin
                aq0_v    <= aq1_v;
                aq0_addr <= aq1_addr;
                aq0_word <= aq1_word;
                aq0_d0   <= aq1_d0e;
                aq0_d1   <= aq1_d1e;
                aq0_open <= aq1_open & write_request;
                aq1_v    <= aq2_v;
                aq1_addr <= aq2_addr;
                aq1_word <= aq2_word;
                aq1_d0   <= aq2_d0e;
                aq1_d1   <= aq2_d1e;
                aq1_open <= aq2_open & write_request;
                aq2_v    <= 1'b0;
                aq2_open <= 1'b0;
            end else if (!write_request) begin
                aq0_open <= 1'b0;
                aq1_open <= 1'b0;
                aq2_open <= 1'b0;
            end

            // ---- push: the flag pulse, and the entry --------------------
            if (!write_request)
                wreq_done <= 1'b0;
            if (push_now) begin
                wflag_q  <= 1'b1;
                wreq_done<= 1'b1;
                case (push_idx)
                    2'd0: begin
                        aq0_v <= 1'b1; aq0_addr <= address[ADDR_BITS-1:0];
                        aq0_word <= access_num[1];
                        aq0_d0 <= din_lo; aq0_d1 <= din_hi; aq0_open <= 1'b1;
                    end
                    2'd1: begin
                        aq1_v <= 1'b1; aq1_addr <= address[ADDR_BITS-1:0];
                        aq1_word <= access_num[1];
                        aq1_d0 <= din_lo; aq1_d1 <= din_hi; aq1_open <= 1'b1;
                    end
                    default: begin
                        aq2_v <= 1'b1; aq2_addr <= address[ADDR_BITS-1:0];
                        aq2_word <= access_num[1];
                        aq2_d0 <= din_lo; aq2_d1 <= din_hi; aq2_open <= 1'b1;
                    end
                endcase
            end else begin
                wflag_q <= 1'b0;
            end

            // ---- the read latch -----------------------------------------
            // One to BURST_MAX words: prefetch reads ask for the whole run
            // and clamp at the port's ceiling. The burst must still fit
            // inside one column -- the caller keeps it below the 512-word
            // boundary by construction.
            if (~rd_busy & read_request) begin
                rd_busy <= 1'b1;
                rd_addr <= address[ADDR_BITS-1:0];
                rd_len  <= (access_num > sdram_col_width'(BURST_MAX))
                         ? LEN_BITS'(BURST_MAX - 1)
                         : (access_num == '0) ? '0
                         : LEN_BITS'(access_num - 1'b1);
                rbeat   <= 1'b0;
            end

            // ---- the engine ----------------------------------------------
            // Loads the FIFO head, or a latched read that cannot overlap
            // any queued write (eng_rd_next -- see the reordering block
            // above), and at a write's p_done chains straight into
            // whatever comes next -- the same edge that pops it.
            if (eng_busy) begin
                if (p_ack) req <= 1'b0;
                if (p_done) begin
                    if (we_r) begin
                        if (eng_rd_next) begin
                            // the read jumps the remaining writes
                            req <= 1'b1; we_r <= 1'b0;
                            addr_r <= rd_addr; len_r <= rd_len;
                        end else if (nx_wr_v) begin
                            req <= 1'b1; we_r <= 1'b1;
                            addr_r <= nx_wr_addr;
                            len_r  <= nx_wr_word ? LEN_BITS'(1) : LEN_BITS'(0);
                        end else begin
                            req <= 1'b0; eng_busy <= 1'b0;
                        end
                    end else begin
                        // The read has landed; its flag may fall. Writes it
                        // jumped are waiting: chain straight into the head.
                        rd_busy <= 1'b0;
                        if (nx_wr_v) begin
                            req <= 1'b1; we_r <= 1'b1;
                            addr_r <= nx_wr_addr;
                            len_r  <= nx_wr_word ? LEN_BITS'(1) : LEN_BITS'(0);
                        end else begin
                            req <= 1'b0; eng_busy <= 1'b0;
                        end
                    end
                end
            end else if (eng_rd_next) begin
                req <= 1'b1; we_r <= 1'b0; eng_busy <= 1'b1;
                addr_r <= rd_addr; len_r <= rd_len;
            end else if (aq0_v) begin
                req <= 1'b1; we_r <= 1'b1; eng_busy <= 1'b1;
                addr_r <= aq0_addr;
                len_r  <= aq0_word ? LEN_BITS'(1) : LEN_BITS'(0);
            end
        end
    end

    // Port A is occupied from the first latched write until the last
    // transaction retires: idle and refresh_mode must stay low across the
    // whole drain, or RAM.sv would tell a caller "ready" while the access
    // it owes is still queued here (the open-loop read race the idle line
    // exists to close). A wire so a diagnostic force stays legal.
    wire busy = eng_busy | aq0_v | aq1_v | aq2_v | rd_busy;

    // The flag rises for the duration of the access and drops when the word
    // has landed; RAM.sv's state machine edges on both transitions. For a
    // write the "duration" is now the accept pulse (see the queue block
    // above); a read still spans its whole transaction.
    assign write_flag   = wflag_q;
    assign read_flag    = rd_busy;
    // idle means "the controller can take a command now" and is low during
    // refresh. RAM.sv latches access_ready from it.
    //
    // ...and it matters far more than "matching" suggests. RAM.sv's CPU-facing
    // ready is OPEN LOOP:
    //
    //     else if (state == IDLE) access_ready <= idle;
    //
    // taken in the very cycle the command appears, and then held. Nothing waits
    // for the access to finish. What protects the CPU is only the length of
    // its bus cycle: it asserts MEMR in T2 and latches at the end of T3, one CPU
    // clock later, which at 4.77 MHz is nine chipset cycles. A controller that
    // answers in five fits; sdram_mp answers in ten, so it does not, and the CPU
    // latches the PREVIOUS access's byte every single time (tb_cpu_timing:
    // 64/64 wrong on CPU timing, 0/64 when the same reads wait for completion).
    // That is the whole bisection: every testbench passed because every
    // testbench waited.
    //
    // Dropping idle in the same cycle the request is seen turns that open loop
    // into a real handshake. access_ready latches 0 at the start of the access,
    // holds 0 through RAM_READ_1/2, and only returns in COMPLETE_RAM_RW, so the
    // CPU inserts wait states until the data is genuinely there. Correctness
    // then does not depend on the controller being fast enough -- which matters,
    // because bursts and extra ports will only make it slower.
    //
    // Safe against RAM.sv's other users of idle: initilized_sdram latches on the
    // first idle, long before any command, and the WAIT state is only entered
    // after the command has dropped.
    assign idle         = stat_idle & ~busy & ~(write_request | read_request);
    // RAM.sv's only mechanism for "the controller cannot serve you yet" is:
    //
    //     else if ((read_command) && (refresh_mode)) access_ready <= 1'b0;
    //
    // and unlike the IDLE-cycle latch above, that branch fires in ANY state, so
    // it does not depend on which value of RAM.sv's `state` the access_ready
    // block happens to see (RAM.sv assigns state with a BLOCKING assignment
    // inside always_ff, so that ordering is not even well defined in
    // simulation). Holding it through the transaction makes the CPU insert
    // wait states until COMPLETE_RAM_RW puts access_ready back up -- a real
    // handshake instead of a race against the bus-cycle length.
    //
    // It is a small lie -- we are busy, not refreshing -- but refresh_mode has
    // exactly one consumer in RAM.sv and this is what it is for.
    assign refresh_mode = stat_refresh | busy;

    // Far end: sdram_mp, the six-port controller.
    // ---------------------------------------------------------------------
    logic init_done;
    logic [MASK_BITS-1:0] dqm_unused;

    // Port A is the guest (the request/flag handshake, one word at a time),
    // port B the font fetch, C the CG window, D the display fetch, E the
    // RAM-image floppy server, and F the CPU cache. Packed so the widths
    // follow the controller's parameters.
    wire [PORTS-1:0] mp_req  = {f_req,  e_req,  d_req, c_req, b_req, req};
    wire [PORTS-1:0] mp_we   = {f_we,   e_we,   1'b0,  1'b0,  1'b0, we_r};
    wire [PORTS-1:0][ADDR_BITS-1:0] mp_addr  = {f_addr, e_addr, d_addr, c_addr,
                                                b_addr, addr_r};
    wire [PORTS-1:0][LEN_BITS-1:0]  mp_len   = {f_len,  e_len,  d_len,  c_len,
                                                b_len,  len_r};
    // sdram_mp publishes the index of the word it wants in p_wcnt and consumes
    // p_wdata combinationally, so a two-word write is just this select. Ports
    // B, C and D are read-only; port E's write data is held by fdd_ramimg for
    // the whole transaction, which is what the combinational consume needs,
    // and port F's two words are held by the cache the same way. Port A's
    // words come from the FIFO head -- held for the whole transaction, and
    // live-resampled only while that entry's request is still on the pins
    // (aq0_open above), which is the window the old whole-transaction
    // resample existed for.
    wire [LEN_BITS-1:0] mp_wcnt;
    wire [PORTS-1:0][sdram_data_width-1:0] mp_wdata =
        {(mp_wcnt == LEN_BITS'(0)) ? f_wdata0 : f_wdata1,
         e_wdata, {sdram_data_width{1'b0}}, {sdram_data_width{1'b0}},
         {sdram_data_width{1'b0}},
         (mp_wcnt == LEN_BITS'(0)) ? aq0_d0e : aq0_d1e};
    wire [PORTS-1:0][MASK_BITS-1:0] mp_wmask =
        {{MASK_BITS{1'b1}}, {MASK_BITS{1'b1}}, {MASK_BITS{1'b1}},
         {MASK_BITS{1'b1}}, {MASK_BITS{1'b1}}, {MASK_BITS{1'b1}}};
    wire [PORTS-1:0] mp_ack, mp_done;
    wire [$clog2(PORTS)-1:0] mp_grant;

    assign p_ack    = mp_ack[0];
    assign p_done   = mp_done[0];
    assign b_ack    = mp_ack[1];
    assign b_done   = mp_done[1];
    assign c_ack    = mp_ack[2];
    assign c_done   = mp_done[2];
    assign d_ack    = mp_ack[3];
    assign d_done   = mp_done[3];
    assign e_ack    = mp_ack[4];
    assign e_done   = mp_done[4];
    assign f_ack    = mp_ack[5];
    assign f_done   = mp_done[5];
    // Read data is tagged with the owning port, so each master sees only its own.
    assign p_rvalid = mp_rvalid & (mp_grant == 3'd0);
    assign b_rvalid = mp_rvalid & (mp_grant == 3'd1);
    assign c_rvalid = mp_rvalid & (mp_grant == 3'd2);
    assign d_rvalid = mp_rvalid & (mp_grant == 3'd3);
    assign e_rvalid = mp_rvalid & (mp_grant == 3'd4);
    assign f_rvalid = mp_rvalid & (mp_grant == 3'd5);
    assign p_rdata  = mp_rdata;
    assign b_rdata  = mp_rdata;
    assign c_rdata  = mp_rdata;
    assign d_rdata  = mp_rdata;
    assign e_rdata  = mp_rdata;
    assign f_rdata  = mp_rdata;

    // Port A write commits (guest, DMA, loader), for the cache to snoop:
    // one-cycle pulse, SDRAM word address, words - 1. The engine can chain
    // into the next FIFO head on the very edge its p_done is set, so the
    // identity of the completing write is snapshotted there -- addr_r by
    // the pulse's cycle already names the NEXT transaction.
    logic                  a_wr_q;
    logic [ADDR_BITS-1:0]  a_wr_addr_q;
    logic [LEN_BITS-1:0]   a_wr_len_q;
    always_ff @(posedge sdram_clock or posedge sdram_reset) begin
        if (sdram_reset) begin
            a_wr_q      <= 1'b0;
            a_wr_addr_q <= '0;
            a_wr_len_q  <= '0;
        end else begin
            a_wr_q <= eng_busy & we_r & p_done;
            if (eng_busy & we_r & p_done) begin
                a_wr_addr_q <= addr_r;
                a_wr_len_q  <= len_r;
            end
        end
    end
    assign a_wr_v    = a_wr_q;
    assign a_wr_addr = ADDR_BITS_PUB'(a_wr_addr_q);
    assign a_wr_len  = LEN_BITS_PUB'(a_wr_len_q);

    // Port-A stall ages for the wedge tap: a_req_age counts an un-granted
    // request's wait, a_busy_age an in-flight transaction without p_done.
    // Both saturate rather than wrap, so a wedged read shows 0xFF forever
    // while a healthy machine never leaves single digits.
    logic [7:0] a_req_age, a_busy_age;
    always_ff @(posedge sdram_clock or posedge sdram_reset) begin
        if (sdram_reset) begin
            a_req_age  <= 8'd0;
            a_busy_age <= 8'd0;
        end else begin
            if (!req | p_ack)
                a_req_age <= 8'd0;
            else if (a_req_age != 8'hFF)
                a_req_age <= a_req_age + 8'd1;
            if (!busy | p_done)
                a_busy_age <= 8'd0;
            else if (a_busy_age != 8'hFF)
                a_busy_age <= a_busy_age + 8'd1;
        end
    end

    logic [13:0] mp_dbg;
    assign dbg_w = {a_req_age, a_busy_age, mp_req, mp_dbg,
                    busy, req, we_r, 1'b0};

    sdram_mp #(
        .PORTS       (PORTS),
        .ROW_BITS    (sdram_row_width),
        .COL_BITS    (sdram_col_width),
        .BANK_BITS   (sdram_bank_width),
        .DQ_BITS     (sdram_data_width),
        .BURST_MAX   (BURST_MAX),
        .CAS_LATENCY (CAS_LATENCY),
        .T_RCD       (T_RCD),
        .T_RP        (T_RP),
        .T_WR        (T_WR),
        .T_RFC       (T_RFC),
        .INIT_NOP    (INIT_NOP),
        .REFRESH_INT (REFRESH_INT)
    ) u_mp (
        .clk          (sdram_clock),
        .rst          (sdram_reset),
        .p_req        (mp_req),
        .p_we         (mp_we),
        .p_addr       (mp_addr),
        .p_len        (mp_len),
        .p_ack        (mp_ack),
        .p_wcnt       (mp_wcnt),
        .p_wdata      (mp_wdata),
        .p_wmask      (mp_wmask),
        .grant        (mp_grant),
        .p_rvalid     (mp_rvalid),
        .p_rdata      (mp_rdata),
        .p_done       (mp_done),
        .init_done    (init_done),
        .stat_idle    (stat_idle),
        .stat_refresh (stat_refresh),
        .dbg          (mp_dbg),
        .sdram_a      (sdram_address),
        .sdram_ba     (sdram_ba),
        .sdram_cke    (sdram_cke),
        .sdram_ras_n  (sdram_ras),
        .sdram_cas_n  (sdram_cas),
        .sdram_we_n   (sdram_we),
        .sdram_dqm    (dqm_unused),
        .sdram_dq_in  (sdram_dq_in),
        .sdram_dq_out (sdram_dq_out),
        .sdram_dq_io  (sdram_dq_io)
    );

    wire _unused_init_done = init_done;

endmodule

`default_nettype wire
