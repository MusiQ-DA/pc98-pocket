//============================================================================
//
//  v30_cpu_bridge -- put the nuV30 (16-bit bus) on the KF8288 world (8-bit).
//
//  WHY THIS EXISTS. The machine's ROMs are V30 ROMs (the ITF's F9476 pushes
//  an immediate word -- a 186-class instruction the 8088 dispatched to its
//  undocumented JS alias), so the hardware CPU is the vendored nuV30. That
//  core has a 16-bit bus and no 8-bit mode, and everything on the other side
//  of it here -- KF8288, Peripherals, RAM, the DMA controller -- is the
//  PC/XT's 8-bit world. On a real PC-98 the V30 talks to 16-bit memory and
//  the byte-lane steering happens in glue; here the glue is this module.
//
//  THE V30 SIDE'S CONTRACT (measured on the vendored core, not assumed):
//
//   * A cycle announces itself by BS leaving passive. ADDR_O is valid from
//     that announcement through T4; UBE_N is valid from T1 (M2: it changes
//     one clock after the status does). The announcement is sometimes a
//     one-clock "preview" (inta_preview / vector_follow_preview /
//     flush_fast in v30u_biu.sv) -- and every preview is a READ, which
//     matters below.
//   * The completion eval fires at the end of the T3 clock when the
//     REGISTERED ready (sampled at the end of T2) was high
//     (`eval_inst = ... dage >= 3 && ready_prev`, v30u_biu.sv M2r): a
//     cycle with READY high through its T2 clock is a zero-wait cycle
//     that retires three core-CE edges after the announcement.
//   * On a read, DATA_I is captured at the T2->T3 edge -- v30u_biu.sv's
//     `TS_T2: cur_data = ad_i` -- which is one edge BEFORE that ready
//     registration. WAIT STATES THEREFORE DO NOT EXTEND THE DATA WINDOW
//     (the upstream rig spells it out, nec_bus.sv: "rdata must be valid
//     ... before T2 ends"). A bridge that splits a word read into two byte
//     cycles and holds READY low until they finish would still hand the
//     core whatever was on DATA_I at the un-postponable capture edge.
//   * On a write, DATA_O is final only after the edge that ends T2: the
//     EU's write pairing loads r_cur_data at T1/T2-edge evals and "a
//     pairing that lands after that clock never holds" (v30u_biu.sv M5b).
//
//  THE BRIDGE'S ANSWER, per direction:
//
//   READS park the CPU. The core's only clock is CE (a de-muxed build has
//   no ce/ce_half contract -- v30_core.sv spells that out), so gating CE
//   freezes the core with ADDR_O, UBE_N and BS stable. Parking at the
//   second core-CE edge after the announcement sits inside the T2 clock:
//   the completion eval (which wanted the T2-clock READY) cannot fire
//   because that edge never comes, and the read's capture edge is still
//   ahead of it. The bridge then runs the byte cycles, assembles DATA_I,
//   and releases: the core takes its capture edge, and the eval fires
//   there with the ready that was registered before the park -- the cycle
//   retires with ZERO perceived waits, the park being pure calendar time.
//   A preview announcement consumes one of the two edges (previews are
//   reads), parking inside T1 instead -- equally safe for a read.
//
//   WRITES QUEUE. A write cannot be parked mid-cycle for servicing: its
//   word may still be pairing at the T2-end edge, so the pins are not
//   trustworthy until the cycle completes. So writes run through un-parked
//   (READY is high, they retire in three edges), and at completion --
//   with r_cur_data certainly final -- the bridge latches {status, address,
//   UBE, word} into a two-deep queue. The queue is drained by the same
//   byte engine, before any parked cycle is serviced, so program order
//   holds: the store lands before the fetch that follows it can read it
//   (and before the OUT 043D bank switch can move the ROM under a fetch).
//   Backpressure: if the queue is full when a write announces, THAT write
//   parks (stretched like a read) and is released once the engine has made
//   room; it then completes, queues, and is serviced in order. No store is
//   ever dropped or reordered.
//
//  THE BYTE ENGINE, for whichever access it is serving, impersonates the
//  8088 the KF8288 was built for:
//
//   * processor_status carries the cycle code per byte and passive between
//     bytes, so the 8288 re-arms its ALE/command machinery per byte
//     exactly as it does per 8088 cycle;
//   * ad_out carries the BYTE address (even lane first, then odd for a
//     word), latched by core_top's ALE-follower into cpu_address;
//   * cpu_data_bus carries the addressed lane of the write word -- A0=0
//     takes DATA_O[7:0], A0=1 takes DATA_O[15:8] (the core publishes the
//     write word "in bus byte order (swapped on an odd address)");
//   * a word cycle (A0=0, UBE_N=0) becomes byte(even) then byte(odd);
//     everything else is one byte cycle;
//   * each byte runs >= 3 posedge-CE "T states" and completes only when
//     processor_ready is high at a posedge-CE with the bus not granted
//     away (address_enable_n == 0), which is what paces the SDRAM and the
//     peripherals -- the same handshake the 8088's READY ran;
//   * read bytes are latched from data_bus at the completing edge, and
//     DATA_I is assembled at release: {odd, even} for a word read, {b, b}
//     for a byte read, {8'h00, vector} for INTA (the forms the working
//     tb_pc98_v30 bench measured on this core).
//
//  THE AEN RACE, AND WHY NO RETRY. A DMA hold request that latches on the
//  last passive posedge before a byte's status rises will drop
//  address_enable_n ~1.5 CE later; the 8288's commands are then born
//  disabled and nothing executes. The READY module holds processor_ready
//  low for as long as the bus is granted away (dma_wait_n), so the byte
//  simply STRETCHES: when the master releases, the 8288 re-asserts the
//  command (the strobes never saw passive) and the byte completes exactly
//  once. One hole -- processor_ready can read high for the first posedge
//  after AEN falls, before dma_wait_n catches up -- is closed by also
//  requiring address_enable_n == 0 at the completing sample. No byte is
//  ever gapped or doubled, which matters because a gapped I/O write would
//  double-edge the PIT's LSB/MSB byte pointer.
//
//  HALT cycles (BS=011) are not accesses: the core runs them through
//  un-parked with READY high, the bridge stays passive, and the arbiter
//  can grant DMA holds meanwhile exactly as it did against the 8088's TI.
//
//  SPDX-License-Identifier: GPL-2.0-or-later  (the nuV30 it serves is
//  GPL-2.0; see core/v30/LICENSE.nuV30)
//
//============================================================================

`default_nettype none

module v30_cpu_bridge (

    // chipset domain
    input  wire         clk,                // clk_chipset
    input  wire         cpu_ce_posedge,     // the CE train the 8288 runs on
    input  wire         cpu_ce_negedge,
    input  wire         reset,              // reset_cpu (negedge-clock domain:
                                            // stable across posedge samples)

    // the V30's pins (ADDR_O/UBE_N/DATA_O/BS are stable while parked)
    input  wire  [2:0]  v30_bs,
    input  wire  [19:0] v30_addr,
    input  wire         v30_ube_n,
    input  wire  [15:0] v30_data_o,
    output reg  [15:0] v30_data_i,
    output wire         v30_ready,
    output wire         v30_ce,             // gated posedge CE to the core

    // the 8088's pins, as the chipset sees them
    output reg   [2:0]  processor_status,   // S2-S0 to the KF8288 / arbiter
    output reg   [19:0] ad_out,             // to core_top's ALE address latch
    output reg   [7:0]  cpu_data_bus,       // the addressed write lane
    output wire         lock_n,             // the core ties BUSLOCK_N high

    // chipset status
    input  wire  [7:0]  data_bus,           // the read byte, during commands
    input  wire         processor_ready,    // the READY module's output
    input  wire         address_enable_n,   // 0 = the 8288 world is ours
    input  wire         pause_core,         // freeze the CPU when set

    output wire         biu_done            // one clk pulse per finished
                                            // V30 cycle, for the CE
                                            // generator's speed reload
);

    localparam [2:0] BS_INTA = 3'b000;
    localparam [2:0] BS_IOR  = 3'b001;
    localparam [2:0] BS_IOW  = 3'b010;
    localparam [2:0] BS_HALT = 3'b011;
    localparam [2:0] BS_CODE = 3'b100;
    localparam [2:0] BS_MEMR = 3'b101;
    localparam [2:0] BS_MEMW = 3'b110;
    localparam [2:0] BS_PASV = 3'b111;

    // BS values that are real bus accesses. HALT runs through un-parked
    // (presenting passive to the 8288 -- for the arbiter's hold granting
    // halt and passive are equivalent: both have S1=S0=1).
    wire bs_access = (v30_bs != BS_PASV) && (v30_bs != BS_HALT);
    wire bs_write  = (v30_bs == BS_IOW) || (v30_bs == BS_MEMW);

    // A read's pins, latched at park time (frozen by then).
    reg  [2:0]  cyc_bs;
    reg  [19:0] cyc_addr;
    reg         cyc_ube_n;

    // The completed-write queue: two deep, FIFO by shifting. The push and
    // the pop are decided in different processes, so both are brought to
    // this one as wires and applied atomically -- a retirement landing on
    // the same clk as a pop must not vanish behind the shift.
    reg  [2:0]  wr_q_bs   [0:1];
    reg  [19:0] wr_q_addr [0:1];
    reg         wr_q_ube  [0:1];
    reg  [15:0] wr_q_data [0:1];
    reg  [1:0]  wr_count;
    wire        q_pop;
    reg         q_push;
    reg  [2:0]  q_push_bs;
    reg  [19:0] q_push_addr;
    reg         q_push_ube;
    reg  [15:0] q_push_data;

    always @(posedge clk) begin
        if (reset) begin
            wr_count <= 2'd0;
        end else if (q_pop) begin
            if (q_push) begin
                // the head leaves, the new arrival takes its place
                wr_q_bs  [0] <= q_push_bs;
                wr_q_addr[0] <= q_push_addr;
                wr_q_ube [0] <= q_push_ube;
                wr_q_data[0] <= q_push_data;
                wr_count     <= 2'd1;
            end else begin
                wr_q_bs  [0] <= wr_q_bs  [1];
                wr_q_addr[0] <= wr_q_addr[1];
                wr_q_ube [0] <= wr_q_ube [1];
                wr_q_data[0] <= wr_q_data[1];
                wr_count     <= wr_count - 2'd1;
            end
        end else if (q_push) begin
            wr_q_bs  [wr_count] <= q_push_bs;
            wr_q_addr[wr_count] <= q_push_addr;
            wr_q_ube [wr_count] <= q_push_ube;
            wr_q_data[wr_count] <= q_push_data;
            wr_count            <= wr_count + 2'd1;
        end
    end

    // ------------------------------------------------------------------------
    // the cycle tracker: watch BS, park reads, retire writes into the queue
    // ------------------------------------------------------------------------

    reg         cyc_active;         // a cycle is out (announcement seen)
    reg  [2:0]  run_edges;          // core CE edges served since (saturates)
    reg         parked;             // the core's CE is gated off
    reg         bs_active_q;        // edge detect on the (access-only) view
    reg         cyc_was_write;      // the retiring cycle's direction
    reg  [2:0]  cyc_type;           // and its exact status code

    assign v30_ce = cpu_ce_posedge && !parked;
    assign v30_ready = !parked && !pause_core;

    // Release wires, so `parked` has a single driver:
    //   engine_release -- the byte engine finished a parked READ;
    //   write_release  -- a parked WRITE may now retire (the queue has room).
    wire engine_release, write_release;
    wire cyc_is_write = (cyc_bs == BS_IOW) || (cyc_bs == BS_MEMW);

    // biu_done: the CE generator reloads clk_select at cycle boundaries;
    // the boundary here is BS returning to passive after an access cycle.
    assign biu_done = bs_active_q && !bs_access && !reset;

    // The core's lock pin is tied high inside v30_core (the LOCK prefix is
    // U2 scope there), so the arbiter's hold gating sees it never locked.
    assign lock_n = 1'b1;

    // A write parks only under backpressure (queue full); a read always
    // parks. Evaluated at the edge that makes the park decision.
    wire park_now = !bs_write || (wr_count == 2'd2);
    localparam [2:0] PARK_AT = 3'd2;   // the T2 clock, see the header

    always @(posedge clk) begin
        if (reset) begin
            cyc_active    <= 1'b0;
            run_edges     <= 3'd0;
            parked        <= 1'b0;
            bs_active_q   <= 1'b0;
            cyc_was_write <= 1'b0;
            cyc_type      <= BS_PASV;
            cyc_bs        <= BS_PASV;
            cyc_addr      <= 20'h0;
            cyc_ube_n     <= 1'b1;
            q_push        <= 1'b0;
            q_push_bs     <= BS_PASV;
            q_push_addr   <= 20'h0;
            q_push_ube    <= 1'b1;
            q_push_data   <= 16'h0;
        end else begin
            bs_active_q <= bs_access;
            q_push      <= 1'b0;

            if (!cyc_active) begin
                if (bs_access) begin
                    cyc_active    <= 1'b1;
                    run_edges     <= 3'd0;
                    cyc_was_write <= bs_write;
                    cyc_type      <= v30_bs;
                end
            end else begin
                if (bs_access) cyc_type <= v30_bs;

                // Count the core CE edges this cycle has consumed. The
                // announcement edge itself is not counted (it happened
                // before the detection registered).
                if (!parked && cpu_ce_posedge && (run_edges != 3'd7)) begin
                    run_edges <= run_edges + 3'd1;
                    if ((run_edges == PARK_AT - 3'd1) && park_now) begin
                        parked   <= 1'b1;
                        // Latch the read's pins while they are frozen.
                        cyc_bs   <= v30_bs;
                        cyc_addr <= v30_addr;
                        cyc_ube_n<= v30_ube_n;
                    end
                end
                // The two release paths.
                if (engine_release) parked <= 1'b0;
                if (write_release)  parked <= 1'b0;

                if (!bs_access) begin
                    // The cycle retired. A write goes into the queue HERE:
                    // r_cur_data committed at its T2/T3-edge pairing and
                    // the pins hold by retention past the eval, so the
                    // word is final. (A write that had parked was released
                    // by write_release first and retires through this same
                    // path.)
                    if (cyc_was_write && wr_count != 2'd2) begin
                        q_push      <= 1'b1;
                        q_push_bs   <= cyc_type;
                        q_push_addr <= v30_addr;
                        q_push_ube  <= v30_ube_n;
                        q_push_data <= v30_data_o;
                    end
                    cyc_active    <= 1'b0;
                    run_edges     <= 3'd0;
                    cyc_was_write <= 1'b0;
                end
            end
        end
    end

    // A parked write may retire once the engine has drained a slot.
    assign write_release = parked && cyc_is_write && (wr_count <= 2'd1);

    // ------------------------------------------------------------------------
    // the byte engine: the queue first, then the parked read
    // ------------------------------------------------------------------------

    localparam [1:0] B_IDLE = 2'd0;   // nothing to do / waiting for the bus
    localparam [1:0] B_CMD  = 2'd1;   // status up: ALE, command, wait ready
    localparam [1:0] B_GAP  = 2'd2;   // status down, letting the 8288 re-arm

    reg  [1:0] bstate;
    reg  [1:0] byte_idx;      // 0 = the addressed byte, 1 = the odd half
    reg        from_queue;    // this pair serves wr_q[0], pop on finish
    reg  [2:0] t_cnt;         // posedge-CE edges since this byte went up
    reg  [1:0] gap_cnt;
    reg  [7:0] rd_lo;         // byte read at the even address
    reg  [7:0] rd_hi;         // byte read at the odd address

    // The pair's parameters, latched at arm time so a queue push or a
    // parked-cycle change mid-pair cannot re-point the byte in flight.
    reg  [2:0]  cur_bs;
    reg  [19:0] cur_addr;
    reg         cur_ube_n;
    reg  [15:0] cur_data;

    wire cur_read = (cur_bs == BS_INTA) || (cur_bs == BS_IOR)
                 || (cur_bs == BS_CODE) || (cur_bs == BS_MEMR);
    wire cur_word = (cur_addr[0] == 1'b0) && (cur_ube_n == 1'b0)
                    && (cur_bs != BS_INTA);
    wire last_byte = (byte_idx == 2'd1) || !cur_word;

    wire bus_ours = (address_enable_n == 1'b0);

    // The access the engine would serve next: the queue head if any, else
    // the parked read. (A parked write is never served -- it is released
    // and queued at its retirement instead.)
    wire        srv_queue = (wr_count != 2'd0);
    wire [2:0]  srv_bs    = srv_queue ? wr_q_bs  [0] : cyc_bs;
    wire [19:0] srv_addr  = srv_queue ? wr_q_addr[0] : cyc_addr;
    wire        srv_ube   = srv_queue ? wr_q_ube [0] : cyc_ube_n;
    wire [15:0] srv_data  = srv_queue ? wr_q_data[0] : 16'h0000;

    // The engine may drive the 8288 world while the core is parked, or
    // while no cycle is out at all (between cycles, or halted).
    wire eng_avail = (parked || !cyc_active) && bus_ours;

    wire [19:0] srv_byte_addr = (byte_idx == 2'd0) ? srv_addr
                                                   : {srv_addr[19:1], 1'b1};
    wire [7:0]  srv_byte_data = (byte_idx == 2'd0)
                              ? (srv_addr[0] ? srv_data[15:8] : srv_data[7:0])
                              : srv_data[15:8];

    // The pair's finish instant, as wires: the tracker releases the core
    // here (a parked read), the queue pops here (a queued write).
    wire pair_finish = (bstate == B_GAP) && (gap_cnt == 2'd1);
    assign q_pop     = pair_finish && last_byte && from_queue;
    assign engine_release = pair_finish && last_byte && !from_queue;

    always @(posedge clk) begin
        if (reset) begin
            bstate           <= B_IDLE;
            byte_idx         <= 2'd0;
            from_queue       <= 1'b0;
            t_cnt            <= 3'd0;
            gap_cnt          <= 2'd0;
            rd_lo            <= 8'h00;
            rd_hi            <= 8'h00;
            cur_bs           <= BS_PASV;
            cur_addr         <= 20'h0;
            cur_ube_n        <= 1'b1;
            cur_data         <= 16'h0;
            processor_status <= BS_PASV;
            ad_out           <= 20'h0;
            cpu_data_bus     <= 8'h00;
            v30_data_i       <= 16'h0000;
        end else begin
            case (bstate)
              B_IDLE: begin
                // Queue entries first (program order), then a parked read.
                // A parked WRITE is released, never served from its pins.
                if (eng_avail && (srv_queue || (parked && !cyc_is_write))) begin
                    cur_bs           <= srv_bs;
                    cur_addr         <= srv_addr;
                    cur_ube_n        <= srv_ube;
                    cur_data         <= srv_data;
                    processor_status <= srv_bs;
                    ad_out           <= srv_byte_addr;
                    cpu_data_bus     <= srv_byte_data;
                    from_queue       <= srv_queue;
                    t_cnt            <= 3'd0;
                    bstate           <= B_CMD;
                end
              end

              B_CMD: begin
                if (cpu_ce_posedge)
                    t_cnt <= (t_cnt != 3'd7) ? (t_cnt + 3'd1) : 3'd7;

                // End the byte at its T3 sample or later, once the chipset
                // says ready AND the bus is still ours (the AEN race: see
                // the header). Waiting here is the wait-state path -- the
                // SDRAM's access stretches this state, exactly as it
                // stretched the 8088's T3/Tw.
                if ((t_cnt >= 3'd3) && cpu_ce_posedge
                    && processor_ready && bus_ours) begin
                    if (cur_read && (byte_idx == 2'd0)) rd_lo <= data_bus;
                    if (cur_read && (byte_idx == 2'd1)) rd_hi <= data_bus;
                    processor_status <= BS_PASV;
                    gap_cnt          <= 2'd0;
                    bstate           <= B_GAP;
                end
              end

              B_GAP: begin
                // One posedge of passive clears the 8288's strobes (the
                // negedge in between resets machine_cycle) and re-arms
                // machine_cycle_period; a second one makes the re-arm a
                // certainty rather than a derivation.
                if (cpu_ce_posedge)
                    gap_cnt <= gap_cnt + 2'd1;

                if (gap_cnt == 2'd1) begin
                    if (last_byte) begin
                        if (!from_queue) begin
                            // The parked READ is done: assemble what the
                            // core will capture at its next CE edge.
                            if (cur_bs == BS_INTA)
                                v30_data_i <= {8'h00, rd_lo};
                            else if (cur_word)
                                v30_data_i <= {rd_hi, rd_lo};
                            else
                                v30_data_i <= {rd_lo, rd_lo};
                        end
                        // (from_queue: the pop is q_pop's own doing.)
                        byte_idx <= 2'd0;
                        bstate   <= B_IDLE;
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

endmodule

`default_nettype wire
