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

    pc98_gvram_seq #(.EGC(1'b1)) dut (
        .clk(clk), .reset(reset),
        .cpu_gvram(cpu_gvram), .cpu_rd(cpu_rd), .cpu_wr(cpu_wr),
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
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_word(mem_word),
        .mem_rd(mem_rd), .mem_wr(mem_wr),
        .mem_rdata(mem_rdata), .mem_rdata_hi(mem_rdata_hi),
        .mem_done(mem_done), .mem_own(mem_own), .mem_ready(mem_ready)
    );

    // ---- the real memory -------------------------------------------------
    wire        initilized_sdram, ram_sel_n;
    wire [7:0]  ram_dbg;
    wire [12:0] s_a;  wire [1:0] s_ba;
    wire        s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};

    RAM u_ram (
        .clock(clk), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(mem_addr), .internal_data_bus(mem_wdata),
        .data_bus_out(mem_rdata),
        .analog_mode(analog_mode), .word_access(mem_word),
        .internal_data_bus_hi(cpu_wdata_hi), .data_bus_out_hi(mem_rdata_hi),
        .gvram_page1_flag(mem_page1),
        .memory_read_n(~mem_rd), .memory_write_n(~mem_wr),
        .no_command_state(~(mem_rd | mem_wr)),
        .memory_access_ready(mem_ready),
        .access_complete(mem_done), .access_own(mem_own),
        .ram_address_select_n(ram_sel_n),
        .dbg(ram_dbg), .dbg2(), .dbg3(), .dbg4(), .dbg5(), .dbg6(), .dbg7(),
        .dbg_watch_addr(20'hFFFFF),
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

        if (errors == 0) $display("PASS tb_gvram_ram_leg");
        else             $display("FAILED tb_gvram_ram_leg: %0d", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAILED tb_gvram_ram_leg: timeout");
        $finish;
    end
endmodule
