`default_nettype none
`timescale 1ns/1ps
// tb_wedge_hunt -- can the memory path wedge under the SuperDepth load?
//
// The hardware bug this hunts: 6-36 s into the title BGM the CPU's fetch
// never completes (probe slot 0x18 static, 0x17 static), and greset does
// NOT cure it -- the stuck state lives in the sdram_reset domain (RAM.sv,
// pc98_gvram_seq, sdram_shim/sdram_mp), which a guest reset never touches.
// This bench drives that exact chain, real RTL only, with the three
// masters the machine runs concurrently:
//
//   * the guest fetch -- a HELD pass-through read (the bridge's byte
//     engine holds MEMR until its own completion witness), rotating over
//     the observed wedge addresses: the DOS disk-buffer band (0x62xx-0x67xx
//     -- dma_last 0x66da/0x62c7), the sound-driver band (0x32exx) and the
//     BIOS F-page;
//   * the uPD71071's floppy fill -- write strobes into the SAME disk
//     buffer band, both shapes the 71071 produces: HELD-until-covered
//     (SW waiting for ready) and EARLY-RELEASED pulses that drop after a
//     fixed window whether or not RAM captured them (the park-slot
//     pressure: 3 slots + cap, pulses that land while all are full);
//   * the softcore's GDC draw service -- GRCG RMW byte writes into the
//     graphics windows, each a 4-plane read+write walk through the
//     sequencer, on the sequencer's own service channel.
//
// plus port-D display bursts inside RAM.sv and the controller's own
// auto-refresh. Every master runs under a watchdog: an op that never
// completes is the wedge, and the bench dumps the whole path's state --
// the same fields the new probe slots 0xA0-0xA7 freeze on hardware --
// then tries the unstick escape hatch (probe write slot 0x08 bit1's
// pulse) and reports whether the fetch master recovers.
//
// Plusargs:
//   +SEED=n    random seed (default 1)
//   +MS=n      sim milliseconds to run (default 4; ~43k clk/ms)
//   +PULSE=n   1-in-n DMA bytes are early-released pulses (default 3)
//   +SVCRATE=n average clk between svc attempts (default 200)
//   +TRACE=1   per-op line
//
// Directed wedge cases (run before/after the random hunt):
//   (a) served-park -- a held read completes, the master misses the ready
//       rise (the observed upstream sampling gap: READY.sv's CE-paired
//       edge, the bridge's command-phase witness, the 71071's dma_ready
//       pulse) and never drops its strobe. The FSM parks in
//       COMPLETE_RAM_RW with the transaction FINISHED and zero pending
//       work -- the exact frozen-tap shape. Layer 1 of the wedge
//       watchdog must dip memory_access_ready and re-assert it; the
//       master takes the second rise and the path continues.
//   (b) no-work watchdog -- the FSM is pushed into a non-IDLE park with
//       the port-A handshake jammed (the shim's busy forced high, as a
//       stuck read_flag would) and every strobe gone: parked with ZERO
//       pending work that no guest reset can ever clear. Layer 2 must
//       fire the auto-unstick (same clear as the probe's wr 0x88 0x02)
//       and hand the FSM back to IDLE.
//   (c) DMA-owned park (run#973 regression) -- a write strobe held far
//       past the layer-1 horizon with dma_hold=1 (the 71071 in SW waiting
//       for the FDC's byte off the slow SD card, 10-100 ms): the park is
//       LEGAL, so layer 1 must stay disarmed (no dip -- the 71071's
//       dma_ready is a one-shot pulse and a spurious one derails it) and
//       layer 2 must not fire either (a strobe is up = pending work).
//   (d) CPU-owned write park -- the same shape with dma_hold=0: layer 1
//       dips and re-asserts exactly as before the ownership gate, and
//       the path recovers (the write-side twin of (a)).
//
// Build (CI shape):
//   build: verilator --binary --timing -Wno-fatal --top-module tb_wedge_hunt
//     -Ifpga/core fpga/core/chipset/HDL/RAM.sv fpga/core/sdram_shim.sv
//     fpga/core/sdram_mp.sv fpga/core/pc98_gvram_seq.sv sim/sdram_model.sv
//     sim/tb_wedge_hunt.sv -o tb_wedge_hunt --Mdir /tmp/obj_wedgehunt

module tb_wedge_hunt;
    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    logic clk = 0, reset = 1;
    always #(HALF_NS) clk = ~clk;

    int seed = 1, ms_run = 4, pulse_one_in = 3, svc_rate = 200;

    // ---- guest side of the sequencer (the merged 8288 bus) ---------------
    logic        cpu_gvram = 0, cpu_rd = 0, cpu_wr = 0, cpu_word = 0;
    logic [19:0] cpu_addr = 20'h0;
    logic [7:0]  cpu_wdata = 8'h00, cpu_wdata_hi = 8'h00;
    wire  [7:0]  cpu_rdata, cpu_rdata_hi;
    wire         cpu_ready, cpu_wr_taken, cpu_rd_own;
    logic [4:0]  cpu_pf_len = 5'd0;

    logic        grcg_active = 0, grcg_rmw = 0;
    logic [3:0]  grcg_mask = 4'h0;
    logic [7:0]  grcg_tile [0:3] = '{8'h00, 8'h00, 8'h00, 8'h00};
    logic        analog_mode = 0, access_page = 0;

    // service channel (the softcore's GDC draw path)
    logic        svc_req = 0, svc_we = 0, svc_raw = 0;
    logic [19:0] svc_addr = 20'h0;
    logic [7:0]  svc_wdata = 8'h00;
    wire         svc_done;
    wire  [7:0]  svc_rdata;

    // ---- sequencer <-> RAM ----------------------------------------------
    wire [19:0] mem_addr;
    wire [7:0]  mem_wdata;
    wire        mem_word, mem_page1;
    wire        mem_rd, mem_wr;
    wire [7:0]  mem_rdata, mem_rdata_hi;
    wire        mem_done, mem_own, mem_ready;
    wire        ram_wt_w;

    pc98_gvram_seq #(.EGC(1'b0)) dut (
        .clk(clk), .reset(reset),
        .cpu_gvram(cpu_gvram), .cpu_rd(cpu_rd), .cpu_wr(cpu_wr),
        .cpu_pf_len(cpu_pf_len),
        .cpu_word(cpu_word),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_wdata_hi(cpu_wdata_hi),
        .cpu_rdata(cpu_rdata), .cpu_rdata_hi(cpu_rdata_hi),
        .cpu_ready(cpu_ready),
        .grcg_active(grcg_active), .grcg_rmw(grcg_rmw),
        .grcg_mask(grcg_mask), .grcg_tile(grcg_tile),
        .analog_mode(analog_mode),
        .access_page(access_page), .mem_page1(mem_page1),
        .svc_req(svc_req), .svc_we(svc_we), .svc_raw(svc_raw),
        .svc_addr(svc_addr), .svc_wdata(svc_wdata),
        .svc_done(svc_done), .svc_rdata(svc_rdata),
        .dbg(), .dbg2(),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_pf_len(),
        .mem_word(mem_word),
        .mem_rd(mem_rd), .mem_wr(mem_wr),
        .mem_rdata(mem_rdata), .mem_rdata_hi(mem_rdata_hi),
        .mem_done(mem_done), .mem_own(mem_own), .mem_ready(mem_ready),
        .mem_wr_taken(ram_wt_w), .cpu_wr_taken(cpu_wr_taken),
        .cpu_rd_own(cpu_rd_own)
    );

    // ---- the real memory -------------------------------------------------
    wire        initilized_sdram, ram_sel_n;
    wire [7:0]  ram_dbg;
    wire [23:0] ram_w_dbg;
    wire [39:0] sd_w_dbg;
    wire [12:0] s_a;  wire [1:0] s_ba;
    wire        s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};
    logic        unstick = 0;
    // AEN model for the directed cases: high while the (modelled) uPD71071
    // owns the bus. Zero everywhere else -- the fetch/DMA stream below all
    // runs CPU-side.
    logic        dma_hold = 0;

    // port-D pressure: the display fetch
    logic        gv_req = 1'b0;
    wire         gv_ack, gv_done;

    // Narrowed watchdog horizon for the bench: 2^16 clk ~= 1.5 ms -- the
    // directed case (b) completes inside the sim budget while staying
    // three orders above any legal non-IDLE streak (~100 clk). Layer 1's
    // park horizon keeps the shipping 2^13.
    RAM #(.WEDGE_WDOG_BITS(16)) u_ram (
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
        .unstick(unstick),
        .dma_hold(dma_hold),
        .dbg(ram_dbg), .dbg2(), .dbg3(), .dbg4(), .dbg5(), .dbg6(), .dbg7(),
        .dbg_w_ram(ram_w_dbg), .dbg_w_sdram(sd_w_dbg),
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
        .gv_rd_req(gv_req), .gv_rd_addr(24'h300000), .gv_rd_len(4'd15),
        .gv_rd_ack(gv_ack), .gv_rd_valid(), .gv_rd_data(), .gv_rd_done(gv_done),
        .ramimg_req(1'b0), .ramimg_we(1'b0), .ramimg_addr(24'h0),
        .ramimg_len(4'h0), .ramimg_wdata(16'h0000),
        .ramimg_ack(), .ramimg_rvalid(), .ramimg_rdata(), .ramimg_done(),
        .cachef_req(1'b0), .cachef_we(1'b0), .cachef_addr(24'h0),
        .cachef_len(4'd0), .cachef_wdata0(16'h0), .cachef_wdata1(16'h0),
        .cachef_ack(), .cachef_rvalid(), .cachef_rdata(), .cachef_done(),
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

    always @(posedge clk) begin
        if (reset)              gv_req <= 1'b0;
        else if (directed_on)    gv_req <= 1'b0;
        else if (gv_ack)        gv_req <= 1'b0;
        else if (!gv_req && (($urandom() % 64) == 0))
                                gv_req <= 1'b1;
    end

    // ---- the wedge dump: everything the hardware tap freezes --------------
    // sd_w_dbg packing (sdram_shim's dbg_w):
    //   [39:32] a_req_age  [31:24] a_busy_age  [23:18] mp_req {F,E,D,C,B,A}
    //   [17:14] mp state   [13:11] rr_ptr      [10] refresh_due
    //   [9] pre_guard  [8] stat_idle  [7] have_req  [6:4] grant
    //   [3] busy  [2] req  [1] we_r  [0] 0
    int errors = 0, wedge = 0, recovered = 0;
    int n_fetch = 0, n_dma = 0, n_svc = 0;

    task automatic dump_state(input string why);
        $display("---- WEDGE (%s) at %0t ----", why, $time);
        $display("  seq     : st=%0d gp=%0d svc_hold=%b svc_req=%b svc_done=%b expand=%b mem_rd=%b mem_wr=%b age=%0d",
                 dut.st, dut.gp, dut.svc_hold, svc_req, svc_done,
                 dut.expand, mem_rd, mem_wr, dut.nonidle_age);
        $display("  RAM     : state=%0d park={%b,%b,%b,%b} rd_conf=%b alr=%b alw=%b rwc=%0d wwc=%0d age=%0d",
                 u_ram.state, u_ram.wc_pend, u_ram.wc_pend2,
                 u_ram.wc_pend3, u_ram.cap_valid, u_ram.rd_conflicts,
                 u_ram.accept_live_rd, u_ram.accept_live_wr,
                 u_ram.read_wait_count, u_ram.write_wait_count,
                 u_ram.nonidle_age);
        $display("  RAM dbg_w_ram[23:0]  = %06h", ram_w_dbg);
        $display("  shim/mp dbg_w[39:0]  = %010h", sd_w_dbg);
        $display("    req_age=%0d busy_age=%0d p_req=%06b rr=%0d mp_state=%0d rfd=%b pg=%b idle=%b have_req=%b grant=%0d busy=%b req=%b we=%b",
                 sd_w_dbg[39:32], sd_w_dbg[31:24], sd_w_dbg[23:18],
                 sd_w_dbg[13:11], sd_w_dbg[17:14], sd_w_dbg[10],
                 sd_w_dbg[9], sd_w_dbg[8], sd_w_dbg[7], sd_w_dbg[6:4],
                 sd_w_dbg[3], sd_w_dbg[2], sd_w_dbg[1]);
        $display("  mp deep : state=%0d timer=%0d refresh_cnt=%0d pre_guard=%0d left=%0d cur_we=%b row_open=%b init_done=%b",
                 u_ram.u_sdram.u_mp.state, u_ram.u_sdram.u_mp.timer,
                 u_ram.u_sdram.u_mp.refresh_cnt, u_ram.u_sdram.u_mp.pre_guard,
                 u_ram.u_sdram.u_mp.left, u_ram.u_sdram.u_mp.cur_we,
                 u_ram.u_sdram.u_mp.row_open, u_ram.u_sdram.u_mp.init_done);
        $display("  mp cmd  : cmd=%03b sdram_a=%0h sdram_ba=%0d dq_io=%b",
                 u_ram.u_sdram.u_mp.cmd, u_ram.u_sdram.u_mp.sdram_a,
                 u_ram.u_sdram.u_mp.sdram_ba, u_ram.u_sdram.u_mp.sdram_dq_io);
    endtask

    // ---- guest-bus masters -------------------------------------------------
    // Beyond the layer-1 horizon (2^13): a fetch whose ready rise was
    // missed parks in COMPLETE and layer 1 heals it at ~8192 clk -- the
    // master here must still be waiting when that happens, exactly like
    // the hardware masters are.
    localparam int FETCH_WDT = (1 << 13) + 2000;
    localparam int SVC_WDT   = 4000;

    // A fetch through the sequencer's pass-through, held like the bridge
    // holds it: cpu_rd until the OWN completion witness, then a gap.
    // Returns 1 on completion, 0 on watchdog timeout.
    task automatic fetch_op(input logic [19:0] a, input int gap,
                            output logic ok);
        int w;
        begin
            @(negedge clk);
            cpu_addr = a; cpu_rd = 1'b1;
            w = 0; ok = 1;
            @(posedge clk);
            while (!cpu_rd_own && w < FETCH_WDT) begin
                @(posedge clk); w++;
            end
            if (!cpu_rd_own) begin
                ok = 0;
                dump_state("fetch never completed");
            end else
                n_fetch++;
            @(negedge clk);
            cpu_rd = 1'b0;
            repeat (gap) @(posedge clk);
        end
    endtask

    // One DMA byte into the disk band. shape=0: HELD until the write is
    // durably covered (the 71071 in SW, released by dma_ready); shape=1:
    // EARLY-RELEASED pulse, dropped after a short fixed window whether or
    // not RAM captured it -- the park pressure.
    task automatic dma_op(input logic [19:0] a, input logic [7:0] v,
                          input int shape, output logic ok);
        int w;
        begin
            @(negedge clk);
            cpu_addr = a; cpu_wdata = v; cpu_wr = 1'b1;
            w = 0; ok = 1;
            @(posedge clk);
            if (shape == 0) begin
                while (!cpu_wr_taken && w < FETCH_WDT) begin
                    @(posedge clk); w++;
                end
                if (!cpu_wr_taken) begin
                    ok = 0;
                    dump_state("DMA write never covered");
                end else
                    n_dma++;
                @(posedge clk);
            end else begin
                repeat (2 + ($urandom() % 3)) @(posedge clk);
                n_dma++;
            end
            @(negedge clk);
            cpu_wr = 1'b0;
        end
    endtask

    // A GDC draw byte through the service channel: GRCG RMW, 4-plane walk.
    // On timeout the request STAYS up -- the firmware holds svc_req until
    // svc_done -- so the wedged configuration is preserved exactly.
    task automatic svc_op(input logic [19:0] a, input logic [7:0] v);
        int w;
        begin
            @(negedge clk);
            svc_addr = a; svc_wdata = v; svc_we = 1'b1; svc_req = 1'b1;
            w = 0;
            @(posedge clk);
            while (!svc_done && w < SVC_WDT) begin
                @(posedge clk); w++;
            end
            if (!svc_done) begin
                wedge = 1;
                dump_state("svc op never done");
                forever @(posedge clk);   // hold the request, like firmware
            end else
                n_svc++;
            @(negedge clk);
            svc_req = 1'b0; svc_we = 1'b0;
            repeat (2 + ($urandom() % 8)) @(posedge clk);
        end
    endtask

    // svc stream: independent process, the softcore's draw rate. Waits for
    // the controller's power-up like everything else -- INIT_NOP alone is
    // 10000 clk, longer than any watchdog here.
    initial begin
        wait (!reset);
        wait (initilized_sdram);
        repeat (20) @(posedge clk);
        forever begin
            @(posedge clk);
            if (!wedge && !directed_on && (($urandom() % svc_rate) == 0)
                && !svc_req && !(cpu_rd | cpu_wr))
                svc_op(20'hA8000 + 20'($urandom() % 20'h1000),
                       8'($urandom()));
        end
    end

    // ---- directed wedge cases --------------------------------------------
    //
    // RAM.sv state codes for the hierarchical peeks below (the enum from
    // the DUT): IDLE=0 W1=1 W2=2 R1=3 R2=4 COMPLETE=5 WAIT=6.
    localparam int ST_IDLE     = 0;
    localparam int ST_R2       = 4;
    localparam int ST_COMPLETE = 5;
    localparam int ST_WAIT     = 6;

    bit directed_on = 0;    // quiesce the background masters for directed cases
    bit hunt_on    = 0;     // the random-hunt window (layer-1 dip monitor)
    int hunt_dips  = 0;     // dips layer 1 fired during the hunt -- each one
                            // is a missed ready rise it healed; the masters
                            // completing is the pass criterion, not dip count

    always @(posedge clk) begin
        if (hunt_on && u_ram.rdy_dip) hunt_dips++;
    end

    // Between directed cases: every case must start from a genuinely
    // quiescent path (IDLE, park FIFO empty), or its first wait can latch
    // onto the PREVIOUS case's completion instead of its own access.
    task automatic quiesce;
        int w;
        begin
            w = 0;
            @(posedge clk);
            while ((int'(u_ram.state) != ST_IDLE
                    || u_ram.wc_pend || u_ram.wc_pend2
                    || u_ram.wc_pend3 || u_ram.cap_valid)
                   && w < FETCH_WDT) begin
                @(posedge clk); w++;
            end
            if (int'(u_ram.state) != ST_IDLE)
                $display("FAIL: quiesce: path did not return to IDLE (state=%0d)",
                         int'(u_ram.state));
            repeat (2) @(posedge clk);
        end
    endtask

    // Case (a) -- the served park (layer 1). A held read completes; the
    // master then misses the ready rise and never drops its strobe. The
    // FSM parks in COMPLETE_RAM_RW with the transaction finished and zero
    // pending work -- the frozen-tap shape. Layer 1 must dip
    // memory_access_ready (cpu_ready here, pass-through) and re-assert
    // it, WITHOUT leaving COMPLETE and without re-running anything; the
    // master takes the second rise and the path keeps working.
    localparam int PARK_HORIZON = (1 << 13) + 3000;

    task automatic park_miss_case(output logic ok);
        int w, rises, park_len;
        logic rdy_q, ok_r;
        begin
            ok = 1; rises = 0; rdy_q = 1'b1; park_len = 0;
            directed_on = 1;
            quiesce;
            @(negedge clk);
            cpu_addr = 20'h6658; cpu_rd = 1'b1;
            // Wait for the access to be SERVED -- the FSM parked in
            // COMPLETE with the strobe still up. cpu_ready alone cannot
            // gate this: memory_access_ready idles HIGH with no command
            // on the pins, so it reads 1 before the access even starts.
            w = 0;
            @(posedge clk);
            while ((int'(u_ram.state) != ST_COMPLETE || !cpu_ready)
                   && w < FETCH_WDT) begin
                @(posedge clk); w++;
            end
            if (int'(u_ram.state) != ST_COMPLETE) begin
                ok = 0;
                dump_state("park case: access never served");
            end
            else begin
                // The miss: hold the strobe, consume nothing. Count
                // ready RE-assertions while the park holds.
                w = 0;
                while (rises < 1 && w < PARK_HORIZON && ok) begin
                    rdy_q = cpu_ready;
                    @(posedge clk);
                    if (!rdy_q && cpu_ready) rises++;
                    if (int'(u_ram.state) != ST_COMPLETE) begin
                        $display("FAIL: park case: FSM left COMPLETE (%0d) with the strobe still held",
                                 int'(u_ram.state));
                        ok = 0;
                    end
                    w++;
                end
                if (rises < 1 && ok) begin
                    ok = 0;
                    dump_state("park case: layer-1 re-assert never came");
                end
                else
                    park_len = w;
                if (ok) begin
                    // The recovered master: accept at the second rise.
                    @(negedge clk);
                    cpu_rd = 1'b0;
                    // The strobe's fall propagates (mem_rd lags a clock,
                    // then COMPLETE's exit evaluates) -- wait it out.
                    w = 0;
                    while (int'(u_ram.state) != ST_IDLE && w < 50) begin
                        @(posedge clk); w++;
                    end
                    fetch_op(20'h6658, 2, ok_r);
                    ok = ok_r;
                    w = 0;
                    while (int'(u_ram.state) != ST_IDLE && w < 50) begin
                        @(posedge clk); w++;
                    end
                    if (ok && int'(u_ram.state) != ST_IDLE) begin
                        $display("FAIL: park case: FSM did not return to IDLE (state=%0d)",
                                 int'(u_ram.state));
                        ok = 0;
                    end
                end
            end
            if (ok)
                $display("directed (a) served-park: dipped and re-asserted after %0d parked clk, path recovered",
                         park_len);
            directed_on = 0;
            @(negedge clk);
        end
    endtask

    // Case (b) -- the no-work watchdog (layer 2). Push the FSM into a
    // read's burst phase (R2), jam the shim's port-A busy flag -- the
    // stuck-read_flag class, a handshake level no guest reset can clear
    // -- then drop every strobe. The FSM abandons the request (R2->WAIT
    // on ~read_command) and parks with ZERO pending work: park FIFO
    // empty, no write strobe, no read request. Layer 2 must fire the
    // auto-unstick (the same clear the probe's wr 0x88 0x02 pulses) and
    // hand the FSM back to IDLE within the horizon.
    localparam int WDOG_HORIZON = (1 << 16) + 4000;

    task automatic wdog_case(output logic ok);
        int w;
        begin
            ok = 1;
            directed_on = 1;
            repeat (8) @(posedge clk);
            // Any park the killed hunt stream left behind drains on its
            // own from IDLE (one posted write per visit) -- wait it out so
            // the case below parks with the FIFO genuinely empty.
            w = 0;
            while ((u_ram.wc_pend | u_ram.wc_pend2 | u_ram.wc_pend3
                    | u_ram.cap_valid) && w < FETCH_WDT) begin
                @(posedge clk); w++;
            end
            if (u_ram.wc_pend | u_ram.wc_pend2 | u_ram.wc_pend3
                | u_ram.cap_valid) begin
                ok = 0;
                dump_state("wdog case: park never drained");
            end
            else begin
            @(negedge clk);
            cpu_addr = 20'h6650; cpu_rd = 1'b1;
            @(posedge clk);
            w = 0;
            while (int'(u_ram.state) != ST_R2 && w < FETCH_WDT) begin
                @(posedge clk); w++;
            end
            if (int'(u_ram.state) != ST_R2) begin
                ok = 0;
                dump_state("wdog case: never reached R2");
            end
            else begin
                // Jam the port-A handshake while the transaction is
                // genuinely in flight: read_flag can never fall again.
                force u_ram.u_sdram.busy = 1'b1;
                // Every master gives up; the FSM parks with no work.
                @(negedge clk);
                cpu_rd = 1'b0;
                repeat (4) @(posedge clk);
                if (int'(u_ram.state) != ST_WAIT)
                    $display("  wdog case: parked in state %0d (expected WAIT)",
                             int'(u_ram.state));
                // Layer 2: the auto-unstick must fire.
                w = 0;
                while (int'(u_ram.state) != ST_IDLE && w < WDOG_HORIZON) begin
                    @(posedge clk); w++;
                end
                release u_ram.u_sdram.busy;
                if (int'(u_ram.state) != ST_IDLE) begin
                    ok = 0;
                    dump_state("wdog case: auto-unstick never fired");
                end
                else
                    $display("directed (b) no-work watchdog: auto-unstick fired after %0d parked clk, FSM back at IDLE",
                             w);
            end
            end
            directed_on = 0;
        end
    endtask

    // Case (c) -- the DMA-owned park must NOT dip (the run#973 regression).
    // A write strobe held far beyond the layer-1 horizon with the bus
    // DMA-owned (dma_hold=1): exactly the 71071-in-SW shape of the SD cold
    // boot, where the FDC withholds its byte for 10-100 ms. The park is
    // LEGAL: layer 1 must stay disarmed (no ready dip), and layer 2 must
    // not fire either (a strobe is up, so there is pending work). The hold
    // spans the bench's full watchdog horizon (2^16 with the narrowed
    // parameter) so both layers' restraint is proven at once.
    localparam int DMA_HOLD_HORIZON = (1 << 16) + 5000;

    task automatic dma_park_case(output logic ok);
        int w, falls;
        logic rdy_q, ok_r;
        begin
            ok = 1; falls = 0; rdy_q = 1'b1;
            directed_on = 1;
            quiesce;
            @(negedge clk);
            cpu_addr = 20'h6300; cpu_wdata = 8'hA5; cpu_wr = 1'b1;
            dma_hold = 1'b1;
            // Wait until the write is covered and the FSM parks in
            // COMPLETE with the strobe still up.
            w = 0;
            @(posedge clk);
            while ((int'(u_ram.state) != ST_COMPLETE || !cpu_ready)
                   && w < FETCH_WDT) begin
                @(posedge clk); w++;
            end
            if (int'(u_ram.state) != ST_COMPLETE) begin
                ok = 0;
                dump_state("dma-park case: write never served");
            end
            else begin
                // The long legal park: nothing may move.
                w = 0;
                while (w < DMA_HOLD_HORIZON && ok) begin
                    rdy_q = cpu_ready;
                    @(posedge clk);
                    if (rdy_q && !cpu_ready) falls++;
                    if (u_ram.rdy_dip) begin
                        $display("FAIL: dma-park case: layer-1 dip fired under a DMA-held strobe (run#973 regression)");
                        ok = 0;
                    end
                    if (int'(u_ram.state) != ST_COMPLETE) begin
                        $display("FAIL: dma-park case: FSM left COMPLETE (%0d) mid-park -- watchdog fired?",
                                 int'(u_ram.state));
                        ok = 0;
                    end
                    w++;
                end
                if (ok && falls != 0) begin
                    $display("FAIL: dma-park case: cpu_ready dipped %0d times under dma_hold", falls);
                    ok = 0;
                end
                if (ok) begin
                    // The FDC finally delivers: the strobe drops, the bus
                    // returns, and the path keeps working.
                    dma_hold = 1'b0;
                    @(negedge clk);
                    cpu_wr = 1'b0;
                    w = 0;
                    while (int'(u_ram.state) != ST_IDLE && w < 100) begin
                        @(posedge clk); w++;
                    end
                    dma_op(20'h6301, 8'h3C, 0, ok_r);
                    ok = ok_r;
                end
            end
            if (ok)
                $display("directed (c) dma-owned park: %0d clk held, no dip, no watchdog, path healthy",
                         DMA_HOLD_HORIZON);
            directed_on = 0;
            @(negedge clk);
        end
    endtask

    // Case (d) -- the same held-write park CPU-owned (dma_hold=0): layer 1
    // must fire exactly as before the gate (dip, re-assert, recover). This
    // is the write-side twin of case (a), pinning that the ownership gate
    // disarmed ONLY the DMA window.
    task automatic cpu_wr_park_case(output logic ok);
        int w, rises;
        logic rdy_q, ok_r;
        begin
            ok = 1; rises = 0; rdy_q = 1'b1;
            directed_on = 1;
            quiesce;
            @(negedge clk);
            cpu_addr = 20'h6302; cpu_wdata = 8'h5A; cpu_wr = 1'b1;
            w = 0;
            @(posedge clk);
            while ((int'(u_ram.state) != ST_COMPLETE || !cpu_ready)
                   && w < FETCH_WDT) begin
                @(posedge clk); w++;
            end
            if (int'(u_ram.state) != ST_COMPLETE) begin
                ok = 0;
                dump_state("cpu-wr-park case: write never served");
            end
            else begin
                w = 0;
                while (rises < 1 && w < PARK_HORIZON && ok) begin
                    rdy_q = cpu_ready;
                    @(posedge clk);
                    if (!rdy_q && cpu_ready) rises++;
                    if (int'(u_ram.state) != ST_COMPLETE) begin
                        $display("FAIL: cpu-wr-park case: FSM left COMPLETE (%0d) with the strobe still held",
                                 int'(u_ram.state));
                        ok = 0;
                    end
                    w++;
                end
                if (rises < 1 && ok) begin
                    ok = 0;
                    dump_state("cpu-wr-park case: layer-1 re-assert never came");
                end
                if (ok) begin
                    @(negedge clk);
                    cpu_wr = 1'b0;
                    w = 0;
                    while (int'(u_ram.state) != ST_IDLE && w < 100) begin
                        @(posedge clk); w++;
                    end
                    fetch_op(20'h6658, 2, ok_r);
                    ok = ok_r;
                end
            end
            if (ok)
                $display("directed (d) cpu-owned write park: dipped and re-asserted, path recovered");
            directed_on = 0;
            @(negedge clk);
        end
    endtask

    // The fetch/DMA scheduler: what the merged bus carries, in order.
    logic [19:0] fetch_tab [0:5] = '{20'h6658, 20'h6650, 20'h62C7,
                                     20'h32E2A, 20'h32E94, 20'hF8620};
    int dma_run = 0;
    int timer_clks = 0;
    logic [19:0] dma_ptr = 20'h6200;
    logic ok;
    initial begin
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("MS=%d", ms_run))  ms_run = 4;
        if (!$value$plusargs("PULSE=%d", pulse_one_in)) pulse_one_in = 3;
        if (!$value$plusargs("SVCRATE=%d", svc_rate))   svc_rate = 200;
        void'($urandom(seed));

        repeat (8) @(posedge clk);
        reset = 0;
        wait (initilized_sdram);
        repeat (20) @(posedge clk);
        $display("init done; seed=%0d ms=%0d pulse=1-in-%0d svcrate=%0d",
                 seed, ms_run, pulse_one_in, svc_rate);

        // GRCG armed RMW from the start (the game's title screen).
        grcg_active = 1'b1; grcg_rmw = 1'b1; grcg_mask = 4'h0;
        grcg_tile[0] = 8'h3C; grcg_tile[1] = 8'hC3;
        grcg_tile[2] = 8'h5A; grcg_tile[3] = 8'hA5;

        // ---- directed case (a) first: the served park (layer 1) --------
        park_miss_case(ok);
        if (!ok) errors++;

        // ---- directed case (c): the DMA-owned park must never dip -------
        dma_park_case(ok);
        if (!ok) errors++;

        // ---- directed case (d): the CPU-owned write park still dips ----
        cpu_wr_park_case(ok);
        if (!ok) errors++;

        hunt_on = 1'b1;
        fork : run_all
            begin : timer
                timer_clks = ms_run * 42955;
                while (timer_clks > 0) begin
                    @(posedge clk);
                    timer_clks = timer_clks - 1;
                end
            end
            begin : bus_stream
                while (!wedge) begin
                    if (dma_run > 0) begin
                        dma_op(dma_ptr, 8'($urandom()),
                               (($urandom() % pulse_one_in) == 0) ? 1 : 0, ok);
                        if (!ok) begin wedge = 1; end
                        else begin
                            dma_ptr++;
                            if (($urandom() % 3) == 0) dma_run--;
                        end
                    end else begin
                        fetch_op(fetch_tab[$urandom() % 6],
                                 1 + ($urandom() % 4), ok);
                        if (!ok) wedge = 1;
                        // a fill starts every few fetches
                        else if (($urandom() % 5) == 0) begin
                            dma_run = 8 + ($urandom() % 24);
                            dma_ptr = 20'h6200
                                    + 20'(($urandom() % 16) * 20'h100);
                        end
                    end
                end
            end
        join_any
        // join_any leaves the losing branch RUNNING -- a mid-op task would
        // keep driving the bus into whatever runs next. Kill the fork and
        // quiesce the pins by hand (the killed task never reaches its own
        // trailing negedge drops).
        disable fork;
        hunt_on = 1'b0;
        @(negedge clk);
        cpu_rd = 1'b0; cpu_wr = 1'b0; svc_req = 1'b0; svc_we = 1'b0;
        // (join_any fell through: the timer expired or a master wedged --
        //  either way the bus stream below is done or parked)
        if (!wedge) begin
            $display("PASS: %0d fetch, %0d DMA bytes, %0d svc ops, no wedge",
                     n_fetch, n_dma, n_svc);
            // Dips during the hunt are layer 1 healing missed ready
            // rises (a random one landed in seed 5 of the first run of
            // this bench): the masters completing is what matters.
            if (hunt_dips != 0)
                $display("hunt: layer 1 healed %0d missed ready rise(s)", hunt_dips);
            // ---- directed case (b): the no-work watchdog (layer 2) ----
            wdog_case(ok);
            if (!ok) errors++;
        end
        else begin
            // The escape-hatch experiment: does the probe's unstick pulse
            // (RAM.sv's parked queue dropped, FSM to IDLE) free the fetch?
            repeat (50) @(posedge clk);
            unstick = 1'b1; @(posedge clk); unstick = 1'b0;
            repeat (20) @(posedge clk);
            fetch_op(20'h6658, 0, ok);
            recovered = ok;
            if (ok)
                $display("FAIL: wedged after %0d fetch, %0d DMA, %0d svc -- UNSTICK RECOVERED the fetch",
                         n_fetch, n_dma, n_svc);
            else begin
                dump_state("fetch still dead after unstick");
                $display("FAIL: wedged after %0d fetch, %0d DMA, %0d svc -- unstick did NOT recover",
                         n_fetch, n_dma, n_svc);
            end
            errors++;
        end
        if (errors == 0)
            $display("=== PASS tb_wedge_hunt ===");
        else
            $display("=== FAIL tb_wedge_hunt ===");
        $finish;
    end

    // A hard global backstop: nothing above may run away silently. The
    // directed cases add ~2 ms of sim over the hunt's own budget.
    initial begin
        #(60_000_000);   // 60 ms wall-of-sim
        $display("FAIL: global backstop");
        $finish;
    end

endmodule

`default_nettype wire
