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
    output reg   [2:0]  processor_status,
    output reg   [19:0] ad_out,
    output reg   [7:0]  cpu_data_bus,
    output wire         lock_n,

    input  wire         analog_mode,
    output reg          word_access,
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
    // zph halves the delivered rate: the fetch FSM's state->next_state->
    // latch cones don't close single-cycle at 42.95 MHz (slow-corner STA
    // showed ~41 ns on a 23.3 ns budget into modrm_l/f0f_l), and on the
    // real chip that marginal path corrupts instruction decode
    // intermittently -- the tvram "starfield" symptom. With zph in the
    // gate, delivered posedges are at least two clk apart, so every
    // core-internal path honestly has two cycles (the SDC says the same
    // via a setup-2 multicycle on the zet:u_cpu keepers); bus pacing is
    // untouched -- the byte engine below still runs on the CE train.
    // zph is latched on the FALLING edge, same as run_arm, so the
    // three-input AND can never glitch mid-high.
    reg  zph = 1'b0;
    always @(negedge clk) zph <= !zph;
    assign zet_clk = clk & (run_arm | reset) & zph;

    // A zet edge lands at this posedge when the gate was open AND zph
    // is the passing half.
    wire zet_edge = (run_arm | reset) & zph;

    assign lock_n   = 1'b1;

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
            if (pair_done && req_busy) begin
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
    wire fast_pair = fast_pace && !cur_inta;
    wire pair_finish = (bstate == B_GAP)
                     && (fast_pair ? cpu_ce_negedge : (gap_cnt == 2'd1));
    wire pair_done   = pair_finish && last_byte;
    wire inta_done   = pair_done && cur_inta;

    assign biu_done = biu_done_r;

    always @(posedge clk) begin
        if (reset) begin
            bstate           <= B_IDLE;
            byte_idx         <= 2'd0;
            t_cnt            <= 3'd0;
            saw_low          <= 1'b0;
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
            processor_status <= BS_PASV;
            ad_out           <= 20'h0;
            cpu_data_bus     <= 8'h00;
            word_access      <= 1'b0;
            cpu_data_bus_hi  <= 8'h00;
            rd_word          <= 16'h0000;
            biu_done_r       <= 1'b0;
        end else begin
            biu_done_r <= 1'b0;
            ready_d1   <= processor_ready;
            case (bstate)
              B_IDLE: begin
                if (srv_any && bus_ours) begin
                    cur_bs           <= srv_bs;
                    cur_addr         <= srv_addr;
                    cur_ube_n        <= srv_ube;
                    cur_data         <= srv_data;
                    cur_term         <= srv_term;
                    cur_inta         <= srv_inta;
                    processor_status <= (srv_term == TERM_WORD)
                                      ? BS_PASV : srv_bs;
                    ad_out           <= srv_byte_addr;
                    cpu_data_bus     <= srv_byte_data;
                    word_access      <= srv_inta ? 1'b0
                                      : word_1cyc(srv_bs, srv_addr, srv_ube);
                    cpu_data_bus_hi  <= srv_data[15:8];
                    t_cnt            <= 3'd0;
                    saw_low          <= 1'b0;
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

                // Fast accept (t_cnt>=2) only on a FRESH ready: the level can
                // still be the previous byte's residue, which would capture
                // stale bus data. The t_cnt>=3 fallback keeps never-dropping
                // accesses (instant I/O) on the faithful count.
                if ((t_cnt >= 3'd3
                     || (fast_pair && (t_cnt >= 3'd2) && saw_low))
                    && cpu_ce_posedge && processor_ready && bus_ours) begin
                    if (cur_read && (byte_idx == 2'd0)) rd_lo <= data_bus;
                    if (cur_read && (byte_idx == 2'd1)) rd_hi <= data_bus;
                    if (cur_read && cur_1cyc)           rd_hi <= data_bus_hi;
                    processor_status <= BS_PASV;
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
                        end else begin
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
