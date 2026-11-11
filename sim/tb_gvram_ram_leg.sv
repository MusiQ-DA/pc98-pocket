`default_nettype none
`timescale 1ns/1ps
// tb_gvram_ram_leg -- the sequencer's wait states against the REAL RAM.sv.
//
// The unit benches model memory idealistically: one access in flight, done
// is always yours. The posted-write queue makes that untrue -- a write the
// guest released long ago can still be draining when the sequencer's next
// leg arrives, and RAM.sv pulses access_complete for THAT access too. A leg
// parked in S_RDW that takes any done as its own drops mem_rd before the
// read ever ran and walks on with data_bus_out's stale byte -- the class
// EGCVIEW's write-then-RMW-read sprite passes hit on hardware.
//
// Access_own (seq's mem_own) is the qualifier this bench exercises on the
// real FSM: a GRCG TCR read issued while the pass-through write is still
// in flight must wait out the write's foreign completion and answer the
// data the write landed, not whatever the data pins last held.
//
// GV_IL stage 2: the seq runs with the full Chipset parameter set
// (RMWBUF/PWPOST/RB_PF on, WBACK obsolete), port G wired to u_ram exactly
// as Chipset wires it, so the line buffer's port-G fills, write-backs and
// lane-DQM are exercised against the real SDRAM FSM and pin-level model.
module tb_gvram_ram_leg;
    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    logic clk = 0, reset = 1;
    always #(HALF_NS) clk = ~clk;

    // ---- guest side of the sequencer ------------------------------------
    logic        cpu_gvram = 0, cpu_rd = 0, cpu_wr = 0, cpu_word = 0;
    logic [19:0] cpu_addr = 20'h0;
    logic [7:0]  cpu_wdata = 8'h00, cpu_wdata_hi = 8'h00;
    wire  [7:0]  cpu_rdata, cpu_rdata_hi;
    wire         cpu_ready;

    logic        grcg_active = 0, grcg_rmw = 0;
    logic [3:0]  grcg_mask = 4'h0;
    logic [7:0]  grcg_tile [0:3] = '{8'h00, 8'h00, 8'h00, 8'h00};
    logic        analog_mode = 0, access_page = 0;
    logic        egc_active = 0, egc_wr = 0;
    logic [3:0]  egc_rg = 4'h0;
    logic [7:0]  egc_d = 8'h00;

    // ---- sequencer <-> RAM ----------------------------------------------
    wire [19:0] mem_addr;
    wire [7:0]  mem_wdata;
    wire        mem_word, mem_page1;
    wire        mem_rd, mem_wr;
    wire [7:0]  mem_rdata, mem_rdata_hi;
    wire        mem_done, mem_own, mem_ready;
    wire        ram_wt_w;           // u_ram write_taken -> seq mem_wr_taken
    // ---- sequencer <-> RAM port G (the RMW line buffer's fills and -------
    // ---- write-backs), wired exactly like Chipset does -------------------
    wire         gvwb_req_w, gvwb_we_w, gvwb_ack_w, gvwb_done_w;
    wire         gvwb_rvalid_w, gv_a_quiet_w;
    wire [23:0]  gvwb_addr_w;
    wire [15:0]  gvwb_wdata_w, gvwb_rdata_w;
    wire [1:0]   gvwb_wmask_w;
    wire [3:0]   gvwb_len_w;
    wire [4:0]   cachef_wcnt_w;

    pc98_gvram_seq #(.EGC(1'b1), .RMWBUF(1'b1), .PWPOST(1'b1),
                     .WBACK(1'b1), .RB_PF(1'b1)) dut (
        .rmwbuf_off(1'b0),
        .dx_seq(2'b00),
        .disp_page(1'b0),
        .clk(clk), .reset(reset),
        .cpu_gvram(cpu_gvram), .cpu_rd(cpu_rd), .cpu_wr(cpu_wr),
        .cpu_pf_len(5'd0),
        .cpu_word(cpu_word),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_wdata_hi(cpu_wdata_hi),
        .cpu_rdata(cpu_rdata), .cpu_rdata_hi(cpu_rdata_hi),
        .cpu_ready(cpu_ready),
        .grcg_active(grcg_active), .grcg_rmw(grcg_rmw),
        .grcg_mask(grcg_mask), .grcg_tile(grcg_tile),
        .analog_mode(analog_mode),
        .access_page(access_page), .mem_page1(mem_page1),
        .egc_active(egc_active), .egc_wr(egc_wr), .egc_rg(egc_rg), .egc_d(egc_d),
        .svc_req(1'b0), .svc_we(1'b0), .svc_raw(1'b0),
        .svc_addr(20'h0), .svc_wdata(8'h0), .svc_done(), .svc_rdata(),
        .dbg(),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_pf_len(),
        .mem_word(mem_word),
        .mem_rd(mem_rd), .mem_wr(mem_wr),
        .mem_rdata(mem_rdata), .mem_rdata_hi(mem_rdata_hi),
        .mem_done(mem_done), .mem_own(mem_own), .mem_ready(mem_ready),
        .mem_wr_taken(ram_wt_w), .pf_beat_v(1'b0), .pf_beat_dat(8'h00),
        .cpu_wr_taken(), .cpu_rd_own(),
        .gvwb_req(gvwb_req_w), .gvwb_we(gvwb_we_w),
        .gvwb_addr(gvwb_addr_w), .gvwb_wdata(gvwb_wdata_w),
        .gvwb_wmask(gvwb_wmask_w), .gvwb_len(gvwb_len_w), .gv_word_ok(),
        .gvwb_ack(gvwb_ack_w), .gvwb_done(gvwb_done_w),
        .gvwb_rvalid(gvwb_rvalid_w), .gvwb_rdata(gvwb_rdata_w),
        .gvwb_wcnt(cachef_wcnt_w), .gv_a_quiet(gv_a_quiet_w)
    );

    // ---- the real memory -------------------------------------------------
    wire        initilized_sdram, ram_sel_n;
    wire [7:0]  ram_dbg;
    wire [12:0] s_a;  wire [1:0] s_ba;
    wire        s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};

    RAM u_ram (
        .dma_hold(1'b0),
        .clock(clk), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(mem_addr), .internal_data_bus(mem_wdata),
        .data_bus_out(mem_rdata),
        .analog_mode(analog_mode), .prefetch_len   (5'd0),
        .pf_beat_v      (),
        .pf_beat_dat    (),
        .word_access(mem_word),
        .internal_data_bus_hi(cpu_wdata_hi), .data_bus_out_hi(mem_rdata_hi),
        .gvram_page1_flag(mem_page1),
        .memory_read_n(~mem_rd), .memory_write_n(~mem_wr),
        .no_command_state(~(mem_rd | mem_wr)),
        .memory_access_ready(mem_ready),
        .access_complete(mem_done), .access_own(mem_own),
        .ram_address_select_n(ram_sel_n),
        .write_taken(ram_wt_w),
        .dbg(ram_dbg), .dbg2(), .dbg3(), .dbg4(), .dbg5(), .dbg6(), .dbg7(),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .ems98_map(ems98_unused),
        .bios_protect_flag(2'b00), .bios_shadow_flag(1'b0),
        .font_bank_flag(1'b0),
        .font_rd_req(1'b0), .font_rd_addr(24'd0), .font_rd_len(4'd0),
        .font_rd_ack(), .font_rd_valid(), .font_rd_data(), .font_rd_done(),
        .cg_rd_req(1'b0), .cg_rd_addr(24'd0), .cg_rd_len(4'd0),
        .cg_rd_ack(), .cg_rd_valid(), .cg_rd_data(), .cg_rd_done(),
        .gv_rd_req(1'b0), .gv_rd_addr(24'd0), .gv_rd_len(4'd0),
        .gv_rd_ack(), .gv_rd_valid(), .gv_rd_data(), .gv_rd_done(),
        .ramimg_req(1'b0), .ramimg_we(1'b0), .ramimg_addr(24'h0),
        .ramimg_len(4'h0), .ramimg_wdata(16'h0000),
        .ramimg_ack(), .ramimg_rvalid(), .ramimg_rdata(), .ramimg_done(),
        .cachef_req(1'b0), .cachef_we(1'b0), .cachef_addr(24'h0),
        .cachef_len(4'd0), .cachef_wdata0(16'h0), .cachef_wdata1(16'h0),
        .cachef_ack(), .cachef_rvalid(), .cachef_rdata(), .cachef_done(),
        .cachef_wcnt(cachef_wcnt_w),
        .gvwb_req(gvwb_req_w), .gvwb_we(gvwb_we_w),
        .gvwb_rvalid(gvwb_rvalid_w), .gvwb_rdata(gvwb_rdata_w),
        .gv_a_quiet(gv_a_quiet_w), .gvwb_addr(gvwb_addr_w),
        .gvwb_wdata(gvwb_wdata_w), .gvwb_wmask(gvwb_wmask_w), .gvwb_len(gvwb_len_w),
        .gvwb_ack(gvwb_ack_w), .gvwb_done(gvwb_done_w),
        .ram_wr_snoop_v(), .ram_wr_snoop_addr(), .ram_wr_snoop_len(),
        .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0),
        .vram_rd_wait_cycle(4'h0), .vram_wr_wait_cycle(4'h0)
    );

    sdram_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                  .T_RAS(2), .T_RC(3), .T_REF(335), .PHYSICAL_DQ(1'b1)) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    logic walk_dbg = 1'b0;
    logic buf_dbg  = 1'b0;
    bit   trace_on = $test$plusargs("trace");   // +trace: leg-by-leg RAM.sv parking trace
    always @(negedge clk) if (buf_dbg && trace_on)
        $display("%8t st=%0d exp=%1b strobe=%1b gp=%0d | leg=%1b sent=%1b h=%1b bi=%0d req=%1b ack=%1b done=%1b rv=%1b wcnt=%0d | fl=%1b/%0d h=%1b i=%0d c=%0d | pf=%1b/%0d h=%1b | rbv=%h tag=%h d=%b age=%0d mru=%1b | rdy=%1b crdy=%1b",
                 $time, dut.st, dut.expand, dut.strobe_new, dut.gp,
                 dut.rb_leg, dut.gf_sent, dut.gf_h, dut.rb_bi,
                 dut.gvwb_req, gvwb_ack_w, gvwb_done_w, gvwb_rvalid_w, cachef_wcnt_w,
                 dut.fl_busy, dut.fl_ph, dut.fl_h, dut.fl_i, dut.fl_c,
                 dut.pf_busy, dut.pf_ph, dut.pf_h,
                 dut.rb_v[0], dut.rb_tag[0], dut.rb_dirty, dut.wb_age, dut.mru,
                 mem_ready, cpu_ready);
    always @(negedge clk) if (walk_dbg && trace_on)
        $display("%8t seq.st=%0d gp=%0d wr=%1b addr=%05h | ram.st=%0d wc=%b%b%b cv=%b lat=%06h lane=%1b dbus=%02h | pend=%06h/%1b p2=%06h/%1b p3=%06h/%1b cap=%06h/%1b | acc=%06h/%1b alw=%b rdy=%1b",
                 $time, dut.st, dut.gp, mem_wr, mem_addr,
                 u_ram.state, u_ram.wc_pend, u_ram.wc_pend2, u_ram.wc_pend3,
                 u_ram.cap_valid, u_ram.latch_address, u_ram.gv_il_lane,
                 u_ram.internal_data_bus,
                 u_ram.pend_address, u_ram.pend_lane,
                 u_ram.pend2_address, u_ram.pend2_lane,
                 u_ram.pend3_address, u_ram.pend3_lane,
                 u_ram.cap_address, u_ram.cap_lane,
                 u_ram.accept_address, u_ram.accept_lane, u_ram.accept_live_wr,
                 mem_ready);

    int errors = 0;
    task automatic want(input string what, input int got, input int exp);
        if (got !== exp) begin
            $display("FAIL %-46s got %02x, want %02x", what, got, exp);
            errors++;
        end else
            $display("ok   %-46s %02x", what, got);
    endtask

    // A completion the seq's held strobe did NOT earn: witness it so the
    // test proves the race actually happened, not just that the answer is
    // right when the stars aligned differently.
    int foreign_in_rdw = 0;
    always @(posedge clk)
        if (mem_done & ~mem_own & (dut.st == 3'd2))
            foreign_in_rdw <= foreign_in_rdw + 1;

`ifdef TRACE
    int last_st = -1;
    always @(negedge clk)
        if (u_ram.state != last_st || mem_rd || mem_wr || mem_done) begin
            $display("%8t st=%0d nst=%0d rd=%b wr=%b rc=%b wc=%b pend=%b alr=%b alw=%b done=%b own=%b rdy=%b rdat=%02h",
                     $time, u_ram.state, u_ram.next_state, mem_rd, mem_wr,
                     u_ram.read_command, u_ram.write_command,
                     u_ram.wc_pend, u_ram.accept_live_rd, u_ram.accept_live_wr,
                     mem_done, mem_own, mem_ready, mem_rdata);
            last_st = u_ram.state;
        end
`endif

    // ---- helpers ----------------------------------------------------------
    // Guest accesses: a strobe must hold until the command has REGISTERED
    // (mem_rd/mem_wr visible, or the walk left S_IDLE) before ready is
    // meaningful -- pass-through's ready is high while the bus idles, and a
    // guest that polls it on the first edge drops its strobe before RAM
    // ever saw one (tb_pc98_egc_golden's tasks spell this out).
    //
    // hold=0 makes a write POSTED: memory_access_ready fires on wr_covered
    // -- the operands are durably captured (accept or a park slot) -- while
    // the SDRAM write is still in flight or queued. The strobe drops, the
    // guest moves on, and the write's COMPLETE arrives later, foreign to
    // whatever strobe is held then. This is the shape a real guest bus
    // produces: the V30 does not sit out the SDRAM write.
    task automatic pw(input logic [19:0] a, input logic [7:0] v,
                      input int hold);
        begin
            @(negedge clk);
            cpu_gvram = 1'b1; cpu_addr = a; cpu_wdata = v; cpu_wr = 1'b1;
            @(posedge clk);
            while (!(mem_rd | mem_wr) && (dut.st == 3'd0)) @(posedge clk);
            repeat (hold) @(posedge clk);
            while (!cpu_ready) @(posedge clk);
            @(negedge clk);
            cpu_wr = 1'b0; cpu_gvram = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic pr(input logic [19:0] a, output logic [7:0] v);
        begin
            @(negedge clk);
            cpu_gvram = 1'b1; cpu_addr = a; cpu_rd = 1'b1;
            @(posedge clk);
            while (!(mem_rd | mem_wr) && (dut.st == 3'd0)) @(posedge clk);
            while (!cpu_ready) @(posedge clk);
            v = cpu_rdata;
            @(negedge clk);
            cpu_rd = 1'b0; cpu_gvram = 1'b0;
            @(posedge clk);
        end
    endtask

    logic [7:0] rb;

    // Drain the RMW line buffer: a plain window write forces the engine to
    // write every dirty line back (fl_want_all -> fl_all; pt_blk holds the
    // write's ready until the banks are in SDRAM), and the write itself
    // drops the buffer. Then wait out any trailing fill/prefetch burst so
    // peek() sees settled memory.
    task automatic flush_buf(input logic [19:0] scratch);
        begin
            pw(scratch, 8'h11, 8);
            while (dut.fl_busy || dut.pf_busy || dut.rb_dirty
                   || dut.rb_leg || dut.gf_sent)
                @(posedge clk);
        end
    endtask

    initial begin
        repeat (8) @(posedge clk);
        reset = 0;
        wait (initilized_sdram);
        repeat (8) @(posedge clk);
        $display("init done");

        // ---- prime: 33h in B/R/G at offset 0x400, one window each --------
        // Pass-through writes (no charger) touch only the window's own
        // plane. Fully waited (hold=8) so nothing is left in the queue.
        // A last read of a DIFFERENT byte leaves 77h in RAM's
        // data_bus_out_reg -- what a foreign done would hand the leg.
        pw(20'hA8400, 8'h33, 8);
        pw(20'hB0400, 8'h33, 8);
        pw(20'hB8400, 8'h33, 8);
        pw(20'hA8500, 8'h77, 8);
        pr(20'hA8500, rb);
        want("primer read back 77h", rb, 8'h77);

        // ---- the race: two posted writes, TCR read right behind ----------
        // W1 @A8000 is accepted live and released by coverage while still in
        // flight. W2 @A8400 arrives during W1's WRITE_2 and PARKS in wc_pend;
        // its strobe releases on coverage while the byte is still queued.
        // The expanded read's plane-B leg then raises mem_rd while RAM is
        // draining W2: rd_conflicts blocks the read, W2's COMPLETE pulses
        // mem_done with mem_own low, and an unqualified S_RDW would eat it
        // and answer the stale 77h. Qualified, the leg waits and the write's
        // 55h is what the byte must be.
        //   correct:  B=55 R=33 G=33 -> tcr = 66 -> answer 99
        //   broken ordering (read first): B=33 -> tcr = 0 -> answer FF
        //   stale byte (old bug): B=77 -> tcr = 44 -> answer BB
        foreign_in_rdw = 0;
        pw(20'hA8000, 8'h11, 0);          // W1: fills the pipeline
        pw(20'hA8400, 8'h55, 0);          // W2: parks behind W1, drains later
        grcg_active = 1'b1; grcg_rmw = 1'b0; grcg_mask = 4'h0;
        grcg_tile[0] = 8'h33; grcg_tile[1] = 8'h33;
        grcg_tile[2] = 8'h33; grcg_tile[3] = 8'h33;
        pr(20'hA8400, rb);                // expanded TCR read, B leg races
        grcg_active = 1'b0;
        want("racy TCR read: B saw the posted write", rb, 8'h99);
        want("  foreign done witnessed in S_RDW",
             foreign_in_rdw > 0 ? 1 : 0, 1);

        // ---- a settled read still reads the byte back ---------------------
        pr(20'hA8400, rb);
        want("settled plain read of plane B", rb, 8'h55);

        // ---- same race, RMW write leg: the read phase feeds the write ----
        // GRCG RMW: each plane reads then writes (old & ~wdata) | (wdata &
        // tile). If the read leg eats a foreign done, the written byte is
        // computed from garbage -- check the landed value.
        pw(20'hA8600, 8'h55, 8);
        pw(20'hB0600, 8'h55, 8);
        pw(20'hB8600, 8'h55, 8);
        foreign_in_rdw = 0;
        pw(20'hA8700, 8'h99, 0);          // W1 keeps RAM busy
        pw(20'hA8600, 8'h11, 0);          // W2 posts 11h into plane B
        grcg_active = 1'b1; grcg_rmw = 1'b1;
        grcg_tile[0] = 8'h0F; grcg_tile[1] = 8'h0F;
        grcg_tile[2] = 8'h0F; grcg_tile[3] = 8'h0F;
        pw(20'hA8600, 8'hF0, 0);          // expanded RMW write, B leg races
        // wdata=F0, tile=0F: (old & ~F0) | (F0 & 0F) = old & 0F.
        // B read 11h -> lands 01h; R/G read 55h -> land 05h. The stale-byte
        // signature would be 77h & 0Fh = 07h on plane B.
        grcg_active = 1'b0; grcg_rmw = 1'b0;
        pr(20'hA8600, rb); want("RMW after race: plane B = 01h", rb, 8'h01);
        pr(20'hB0600, rb); want("RMW after race: plane R = 05h", rb, 8'h05);
        pr(20'hB8600, rb); want("RMW after race: plane G = 05h", rb, 8'h05);
        $display("  foreign completions seen in S_RDW this phase: %0d",
                 foreign_in_rdw);

        // ---- GV_IL cross-lane dedup: the posted-queue operand match must  --
        // include the byte lane. B and R of one guest offset translate to
        // the SAME SDRAM word (even word: {R,B}), differing only in the DQM
        // lane. Two posted writes with equal data (an erase: 00 to every
        // plane) used to operand-match across lanes -- the second write was
        // dup_covered by the first and never landed. On hardware that is
        // NEON's red ghost: blue (lower lane) erases, red (upper lane)
        // stays forever.
        pw(20'hA8900, 8'hAA, 8);           // prime B = AA
        pw(20'hB0900, 8'hAA, 8);           // prime R = AA
        pw(20'hA8F00, 8'h11, 0);           // W1 keeps the FSM busy
        pw(20'hA8900, 8'h00, 0);           // W2 parks: B-lane 00
        pw(20'hB0900, 8'h00, 0);           // W3 same word+data, upper lane:
                                          //    must ALSO land (not a dup)
        pr(20'hA8900, rb); want("cross-lane park: B erased", rb, 8'h00);
        pr(20'hB0900, rb); want("cross-lane park: R erased", rb, 8'h00);

        // ---- the same erase through the GRCG walk (NEON's actual shape) --
        // TDW with all-plane tiles 00: four legs write 00 to B,R,G,E of one
        // offset back-to-back. The legs park behind each other; without the
        // lane in the match, R (even word) and E (odd word) are eaten by
        // their lane-twin's parked write. E0000 needs analog to be GVRAM.
        analog_mode = 1'b1;
        pw(20'hA8A00, 8'hAA, 8); pw(20'hB0A00, 8'hAA, 8);
        pw(20'hB8A00, 8'hAA, 8); pw(20'hE0A00, 8'hAA, 8);
        grcg_active = 1'b1; grcg_rmw = 1'b0; grcg_mask = 4'h0;
        grcg_tile[0] = 8'h00; grcg_tile[1] = 8'h00;
        grcg_tile[2] = 8'h00; grcg_tile[3] = 8'h00;
        pw(20'hA8E00, 8'h11, 0);           // keep the FSM busy so legs park
        walk_dbg = 1'b1;
        pw(20'hA8A00, 8'h00, 0);           // expanded TDW: 4-plane erase
        grcg_active = 1'b0;
        pr(20'hA8A00, rb); want("walk erase: plane B", rb, 8'h00);
        pr(20'hB0A00, rb); want("walk erase: plane R", rb, 8'h00);
        pr(20'hB8A00, rb); want("walk erase: plane G", rb, 8'h00);
        pr(20'hE0A00, rb); want("walk erase: plane E", rb, 8'h00);
        walk_dbg = 1'b0;
        // Where did each lane actually land? {R,B} even word, {E,G} odd.
        $display("  peek 601200 (even {R,B}) = %04h", sdr.peek(24'h601200));
        $display("  peek 601401 (odd  {E,G}) = %04h", sdr.peek(24'h601401));
        analog_mode = 1'b0;

        // ---- GV_IL stage 2: the RMW line buffer through the real port G --
        // A run of posted RMW writes into a fresh line: the first arms the
        // two-burst port-G fill (all four planes of 16 guest bytes at once),
        // the rest hit the bank with no leg at all, each write merging its
        // plane byte and marking the line dirty. A later plain window write
        // forces the write-back -- lane DQM keeps the clean twin lane of
        // every word intact. The peeked SDRAM words must equal the np21w
        // RMW model (old & ~d) | (d & tile) applied per plane, in order.
        analog_mode = 1'b1;
        buf_dbg = 1'b1;
        for (int i = 0; i < 16; i++) begin        // prime line 0xC00: AA
            pw(20'hA8C00 + 16'(i), 8'hAA, 8);
            pw(20'hB0C00 + 16'(i), 8'hAA, 8);
            pw(20'hB8C00 + 16'(i), 8'hAA, 8);
            pw(20'hE0C00 + 16'(i), 8'hAA, 8);
        end
        begin
            logic [7:0] mdl [0:3][0:15];
            logic [7:0] d;
            for (int p = 0; p < 4; p++)
                for (int i = 0; i < 16; i++) mdl[p][i] = 8'hAA;
            grcg_active = 1'b1; grcg_rmw = 1'b1; grcg_mask = 4'h0;
            grcg_tile[0] = 8'h3C; grcg_tile[1] = 8'h5A;
            grcg_tile[2] = 8'hC3; grcg_tile[3] = 8'h96;
            for (int i = 0; i < 16; i++) begin
                d = 8'((i * 17 + 3) & 8'hFF);
                for (int p = 0; p < 4; p++)
                    mdl[p][i] = (mdl[p][i] & ~d) | (d & grcg_tile[p]);
                pw(20'hA8C00 + 16'(i), d, 0);     // posted: fill/hit behind
            end
            grcg_active = 1'b0; grcg_rmw = 1'b0;
            flush_buf(20'hA8D00);                 // everything back to SDRAM
            for (int i = 0; i < 16; i++) begin
                logic [15:0] weven, wodd;
                weven = sdr.peek(24'h601800 + 24'(2 * i));
                wodd  = sdr.peek(24'h601800 + 24'(2 * i + 1));
                want($sformatf("buf RMW line byte %02d: B lane", i),
                     weven[7:0],  mdl[0][i]);
                want($sformatf("buf RMW line byte %02d: R lane", i),
                     weven[15:8], mdl[1][i]);
                want($sformatf("buf RMW line byte %02d: G lane", i),
                     wodd[7:0],  mdl[2][i]);
                want($sformatf("buf RMW line byte %02d: E lane", i),
                     wodd[15:8], mdl[3][i]);
            end
            // and the same bytes back through port A reads, one per plane
            pr(20'hA8C00, rb);      want("buf RMW readback: plane B", rb, mdl[0][0]);
            pr(20'hB0C05, rb);      want("buf RMW readback: plane R", rb, mdl[1][5]);
            pr(20'hB8C0A, rb);      want("buf RMW readback: plane G", rb, mdl[2][10]);
            pr(20'hE0C0F, rb);      want("buf RMW readback: plane E", rb, mdl[3][15]);
        end
        analog_mode = 1'b0;
        buf_dbg  = 1'b0;

        if (errors == 0) $display("PASS tb_gvram_ram_leg");
        else             $display("FAILED tb_gvram_ram_leg: %0d", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAILED tb_gvram_ram_leg: timeout");
        $display("  seq: st=%0d expand=%1b strobe=%1b gp=%0d rb_leg=%1b gf_sent=%1b gf_h=%1b rb_bi=%0d",
                 dut.st, dut.expand, dut.strobe_new, dut.gp, dut.rb_leg,
                 dut.gf_sent, dut.gf_h, dut.rb_bi);
        $display("  seq: gvwb req=%1b we=%1b addr=%06h ack=%1b done=%1b rvalid=%1b wcnt=%0d quiet=%1b",
                 dut.gvwb_req, dut.gvwb_we, dut.gvwb_addr, gvwb_ack_w,
                 gvwb_done_w, gvwb_rvalid_w, cachef_wcnt_w, gv_a_quiet_w);
        $display("  seq: fl busy=%1b ph=%0d h=%1b i=%0d c=%0d | pf busy=%1b ph=%0d h=%1b | rbv=%h/%h tag=%h/%h dirty=%b age=%0d mru=%1b",
                 dut.fl_busy, dut.fl_ph, dut.fl_h, dut.fl_i, dut.fl_c,
                 dut.pf_busy, dut.pf_ph, dut.pf_h,
                 dut.rb_v[0], dut.rb_v[1], dut.rb_tag[0], dut.rb_tag[1],
                 dut.rb_dirty, dut.wb_age, dut.mru);
        $display("  ram: state=%0d latch=%06h | cpu rd=%1b wr=%1b rdy=%1b crdy=%1b",
                 u_ram.state, u_ram.latch_address, cpu_rd, cpu_wr,
                 mem_ready, cpu_ready);
        $finish;
    end
endmodule
