//
// tb_mem_perf -- where do the cycles in a guest write burst actually go?
//
// The whole memory-write path, wired the way core_top wires it:
// Zet -> zet_cpu_bridge -> i8288 -> READY -> pc98_gvram_seq(+GRCG,+EGC)
// -> RAM.sv -> sdram_shim -> sdram_mp -> sdram_board_model, with the real
// ce_generator pacing the bus and the real display fetch contending on
// port D.
//
// The program is synthetic: phases of REP STOSB/STOSW/MOVSW against main
// RAM, then the same against the GRCG window with the charger armed (TDW,
// RMW) and with the EGC armed. OUT 88FEh brackets each phase (n / n|80h);
// the bench snapshots its counters at each bracket and prints a per-phase
// cycle attribution.
//
//   scripts/sim_mem_perf.sh [+speed=N] [+disp=0] [+analog4=1]
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_mem_perf;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic reset = 1'b1;
    logic sdram_up = 1'b0;
    wire  cpu_reset_w;

    // ---- CE -------------------------------------------------------------
    wire       ce_pos, ce_neg;
    wire [1:0] ram_rd_wait, ram_wr_wait;
    wire       vram_wait_en;
    logic [1:0] clk_select_r = 2'b00;
    initial if ($value$plusargs("speed=%d", clk_select_r))
        $display("clk_select %0d", clk_select_r);

    // Load the speed once the bench starts; the generator ignores
    // clk_select until a clk_select_load edge.
    logic sel_load = 1'b0;

    ce_generator u_ce (
        .clock                (clk), .reset(reset),
        .clk_select_load      (sel_load),
        .clk_select           (clk_select_r),
        .cpu_clk_pin          (),
        .cpu_ce_posedge       (ce_pos),
        .cpu_ce_negedge       (ce_neg),
        .peripheral_ce        (),
        .cycle_accrate        (),
        .clock_cycle_counter_division_ratio (),
        .clock_cycle_counter_decrement_value (),
        .shift_read_timing    (),
        .ram_read_wait_cycle  (ram_rd_wait),
        .ram_write_wait_cycle (ram_wr_wait),
        .vram_wait_en         (vram_wait_en)
    );

    // ---- CPU + bridge -----------------------------------------------------
    wire        zet_clk;
    wire [15:0] zwb_dat_i, zwb_dat_o;
    wire [19:1] zwb_adr;
    wire        zwb_we, zwb_tga, zwb_stb, zwb_cyc, zwb_ack;
    wire [ 1:0] zwb_sel;
    wire        zwb_inta, zwb_nmia;
    wire [19:0] zet_pc;
    wire [2:0]  processor_status;
    wire [19:0] ad_out;
    wire [7:0]  cpu_data_bus, cpu_data_bus_hi;
    wire        cpu_word_access;
    wire        biu_done;

    wire        guest_ready;   // the seq's cpu_ready -- Chipset's memory_access_ready
    wire        proc_ready;
    wire        pc98_analog_w;

    zet_cpu_bridge u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (ce_pos),
        .cpu_ce_negedge    (ce_neg),
        .fast_pace         (clk_select_r[1]),
        .reset             (cpu_reset_w),
        .zet_clk           (zet_clk),
        .wb_dat_o          (zwb_dat_o),
        .wb_dat_i          (zwb_dat_i),
        .wb_adr_o          (zwb_adr),
        .wb_we_o           (zwb_we),
        .wb_tga_o          (zwb_tga),
        .wb_sel_o          (zwb_sel),
        .wb_stb_o          (zwb_stb),
        .wb_cyc_o          (zwb_cyc),
        .wb_ack_i          (zwb_ack),
        .wb_tgc_o          (zwb_inta),
        .nmia              (zwb_nmia),
        .processor_status  (processor_status),
        .ad_out            (ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (),
        .analog_mode       (pc98_analog_w),
        .word_access       (cpu_word_access),
        .pf_req_len        (cpu_pf_len_w),
        .pf_beat_v         (pf_beat_v_w),
        .pf_beat_dat       (pf_beat_dat_w),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (din_hi),
        .data_bus          (din),
        .processor_ready   (proc_ready),
        .address_enable_n  (aen),
        .sdram_wr_taken    (seq_wr_taken_w),
        .pause_core        (1'b0),
        .biu_done          (biu_done),
        .pf_disable        (1'b0),
        .dbg               ()
    );

    zet u_cpu (
        .wb_clk_i  (zet_clk),
        .wb_rst_i  (cpu_reset_w),
        .wb_dat_i  (zwb_dat_i),
        .wb_dat_o  (zwb_dat_o),
        .wb_adr_o  (zwb_adr),
        .wb_we_o   (zwb_we),
        .wb_tga_o  (zwb_tga),
        .wb_sel_o  (zwb_sel),
        .wb_stb_o  (zwb_stb),
        .wb_cyc_o  (zwb_cyc),
        .wb_ack_i  (zwb_ack),
        .wb_tgc_i  (1'b0),
        .wb_tgc_o  (zwb_inta),
        .nmi       (1'b0),
        .nmia      (zwb_nmia),
        .pc        (zet_pc),
        .dbg_fault (),
        .dbg_opc   ()
    );

    // ---- 8288 + address latch --------------------------------------------
    wire mem_rd_n, mem_wr_n, io_rd_n, io_wr_n, inta_n, ale;

    i8288 u_8288 (
        .clock                           (clk),
        .cpu_ce_posedge                  (ce_pos),
        .cpu_ce_negedge                  (ce_neg),
        .reset                           (reset),
        .address_enable_n                (aen),
        .command_enable                  (~aen),
        .io_bus_mode                     (1'b0),
        .processor_status                (processor_status),
        .enable_io_command               (),
        .advanced_io_write_command_n     (),
        .io_write_command_n              (io_wr_n),
        .io_read_command_n               (io_rd_n),
        .interrupt_acknowledge_n         (inta_n),
        .enable_memory_command           (),
        .advanced_memory_write_command_n (),
        .memory_write_command_n          (mem_wr_n),
        .memory_read_command_n           (mem_rd_n),
        .direction_transmit_or_receive_n (),
        .data_enable                     (),
        .master_cascade_enable           (),
        .peripheral_data_enable_n        (),
        .address_latch_enable            (ale)
    );

    logic [19:0] cpu_address = 20'h0;
    always_ff @(posedge clk)
        if (ale) cpu_address <= ad_out;

    // ---- I/O decode: GRCG + mode2(0x6A) + access page(0xA6) + EGC --------
    logic       grcg_active, grcg_rmw;
    logic [3:0] grcg_mask;
    logic [7:0] grcg_tile [0:3];

    // The same latch-on-strobe, commit-on-release shape Peripherals uses.
    logic       io_wr_d = 1'b1;
    logic [7:0] io_wr_data = 8'h00;
    always_ff @(posedge clk) begin
        io_wr_d <= io_wr_n;
        if (~io_wr_n) io_wr_data <= cpu_data_bus;
    end
    wire io_wr_commit = io_wr_n & ~io_wr_d & (cpu_address[15:8] == 8'h00);
    // pc98_io_exact & ~io_write_n level selects, like Peripherals drives them:
    // the module latches the byte during the strobe and commits on its rise.
    wire io_sel_wr = ~io_wr_n & (cpu_address[15:8] == 8'h00);

    pc98_grcg u_grcg (
        .clk(clk), .reset(reset),
        .cs_mode(io_sel_wr & (cpu_address[7:0] == 8'h7C)),
        .cs_tile(io_sel_wr & (cpu_address[7:0] == 8'h7E)),
        .io_read_n(io_rd_n), .io_write_n(io_wr_n),
        .io_data_in(cpu_data_bus), .io_data_out(),
        .active(grcg_active), .rmw(grcg_rmw), .plane_mask(grcg_mask),
        .tile_o(grcg_tile),
        .cpu_wdata(8'h00),
        .plane_rdata('{8'h00, 8'h00, 8'h00, 8'h00}),
        .plane_wdata(), .plane_we(), .cpu_rdata()
    );

    // mode2 (port 0x6A) + access page (0xA6), decoded as Peripherals does.
    logic [7:0] mode2_w;
    wire        mode6a_wr = io_wr_commit & (cpu_address[7:0] == 8'h6A);
    logic       page_a6 = 1'b0;
    always_ff @(posedge clk)
        if (io_wr_commit & (cpu_address[7:0] == 8'hA6))
            page_a6 <= io_wr_data[0];

    pc98_gdc_mode2 u_mode2 (
        .clk(clk), .rst(reset),
        .wr(mode6a_wr), .d(io_wr_data),
        .analog_capable(1'b1),
        .mode2(mode2_w), .gdc_clk(), .analog(pc98_analog_w)
    );
    wire egc_active_w = mode2_w[3] & mode2_w[2];

    // 0x4A0-0x4AF, release-edge strobe exactly like Peripherals.
    wire egc_cs   = (cpu_address[15:4] == 12'h04A);
    wire egc_wr_w = io_wr_n & ~io_wr_d & egc_cs;
    wire [3:0] egc_rg_w = cpu_address[3:0];

    // ---- DMA grant injection (+GRANT): Bus_Arbiter's hold chain, flattened --
    // Reproduces the real grant timing: hold_request_ff_1 samples a passive
    // processor status on cpu_ce posedge, ff_2 propagates on the negedge,
    // hold_acknowledge -> address_enable_n -> dma_wait, one cpu_ce apart each.
    // address_enable_n high gates the i8288 (command_enable=~aen) and tells the
    // bridge to defer; while the bus is DMA-owned a synthetic DMAC writes an
    // FDC-style burst through the SAME seq/RAM path the CPU uses.
    logic        grant_en = 1'b0;
    logic        hreq     = 1'b0;
    logic        hrff1 = 1'b0, hrff2 = 1'b0;
    logic        aen = 1'b0, dma_wait = 1'b0;

    localparam int DMA_BASE  = 20'h30000;
    localparam int DMA_MASK  = 20'h00FFF;   // bounded 4 KB fill buffer
    localparam int DMA_BURST = 8;
    int          dma_period = 397;          // odd period -> hits all phases
    logic [19:0] dma_addr  = DMA_BASE;   // next byte the DMAC will write
    logic [19:0] bus_addr  = DMA_BASE;   // operand on the pins: follows
                                        // dma_addr only while bytes
                                        // remain, so a strobe fall always
                                        // shows the byte just taken
    logic        dma_wr    = 1'b0;
    logic        dma_rd    = 1'b0;
    int          burst_left    = 0;
    int          dma_per_cnt   = 0;
    int          grants        = 0;
    int          grants_midcmd = 0;
    int          diverged      = 0;
    int          stray         = 0;

    initial begin
        void'($value$plusargs("dmaperiod=%d", dma_period));
        grant_en = $test$plusargs("GRANT");
        if (grant_en)
            $display("GRANT injection on, dma_period=%0d", dma_period);
    end

    // hold_request_ff_1: passive status + hreq, on cpu_ce posedge
    always_ff @(posedge clk) begin
        if (reset) hrff1 <= 1'b0;
        else if (ce_pos)
            hrff1 <= processor_status[0] & processor_status[1] & hreq;
    end
    // hold_request_ff_2: propagates on cpu_ce negedge while hreq held
    always_ff @(posedge clk) begin
        if (reset) hrff2 <= 1'b0;
        else if (ce_neg)
            hrff2 <= ~hreq ? 1'b0 : (hrff2 | hrff1);
    end
    // address_enable_n follows hold_acknowledge; dma_wait one ce behind
    wire hlda_w = hreq ? hrff2 : 1'b0;
    always_ff @(posedge clk) begin
        if (reset) begin
            aen <= 1'b0; dma_wait <= 1'b0;
        end else if (ce_pos) begin
            aen      <= hlda_w & grant_en;
            dma_wait <= aen;
        end
    end
    wire dma_enable_n = ~(dma_wait & aen);
    wire dma_active   = ~dma_enable_n;

    // synthetic DMAC: request a burst every dma_period clks, then stream
    // bytes into the fill buffer while the bus is DMA-owned. Each byte's
    // strobe is HELD until RAM's write_taken says the operands were
    // durably captured -- the wait a real 8237's MEMW takes through the
    // ready chain. A free-running 1-byte/clk stream simply outruns RAM's
    // park depth: those "lost" bytes are a bench artifact, not RTL bugs.
    always_ff @(posedge clk) begin
        if (reset || !grant_en) begin
            hreq <= 1'b0; burst_left <= 0; dma_addr <= DMA_BASE;
            bus_addr <= DMA_BASE;
            dma_wr <= 1'b0; dma_per_cnt <= 0;
        end else begin
            if (!hreq) begin
                dma_per_cnt <= dma_per_cnt + 1;
                if (dma_per_cnt == dma_period) begin
                    dma_per_cnt <= 0;
                    hreq        <= 1'b1;
                    burst_left  <= DMA_BURST;
                    bus_addr    <= dma_addr;   // first byte's operand
                end
            end
            if (dma_active && burst_left > 0) begin
                dma_wr     <= 1'b1;
                // cpu_wr_taken, not mem_wr_taken: while the sequencer is
                // expanding a guest graphics op, mem_wr_taken fires for
                // ITS legs -- our byte was never even presented. And
                // write_taken answers for the operand the RAM sees NOW
                // (seq_mem_addr, a clock behind bus_addr): the previous
                // byte's coverage keeps it high while the new operand is
                // still in flight, so an unqualified sample advances the
                // stream one byte ahead of coverage -- the last byte then
                // falls presented-but-uncovered (the +GRANT uncov). The
                // seq_mem_addr==bus_addr qualifier is exactly "the 8237's
                // IOCHRDY wait released for THIS byte".
                if (dma_wr && seq_wr_taken_w && seq_mem_addr == bus_addr) begin
                    dma_addr   <= (dma_addr >= DMA_BASE + DMA_MASK)
                                  ? DMA_BASE : dma_addr + 20'd1;
                    burst_left <= burst_left - 1;
                    if (burst_left == 1)
                        dma_wr <= 1'b0;      // burst done: strobe ends on
                    else                     // the taken byte's operands
                        bus_addr <= (dma_addr >= DMA_BASE + DMA_MASK)
                                    ? DMA_BASE : dma_addr + 20'd1;
                end
            end else begin
                dma_wr <= 1'b0;
            end
            if (hreq && burst_left == 0)
                hreq <= 1'b0;
        end
    end
    // count grants that land while the bridge has a byte armed in B_CMD --
    // the exact mid-access preemption suspected of corrupting the CPU.
    // grant_start is a LEVEL that holds for a whole ce window, so count
    // its rising edge -- a level count just measures the grant's width.
    logic grant_start_d = 1'b0;
    wire  grant_start   = grant_en & aen & !dma_wait;
    always_ff @(posedge clk) begin
        grant_start_d <= grant_start;
        if (grant_start && !grant_start_d) begin
            grants <= grants + 1;
            if (u_bridge.bstate == u_bridge.B_CMD)
                grants_midcmd <= grants_midcmd + 1;
        end
    end

    // merged bus view for the seq + RAM: DMA owns it during dma_active,
    // otherwise the i8288's (grant-gated) CPU commands.
    wire        seq_rd    = dma_active ? dma_rd    : ~mem_rd_n;
    wire        seq_wr    = dma_active ? dma_wr    : ~mem_wr_n;
    wire [19:0] seq_addr  = dma_active ? bus_addr : cpu_address;
    wire [7:0]  seq_wdata = dma_active ? (8'hA5 ^ bus_addr[7:0])
                                       : cpu_data_bus;
    wire        bus_mrd_n = dma_active ? ~dma_rd   : mem_rd_n;
    wire        bus_mwr_n = dma_active ? ~dma_wr   : mem_wr_n;

    // ---- the graphics sequencer, ahead of RAM ----------------------------
    wire        ram_sel_n;
    wire [19:0] seq_mem_addr;
    wire [7:0]  seq_mem_wdata, seq_cpu_rdata, seq_cpu_rdata_hi;
    wire        seq_mem_word, seq_mem_rd, seq_mem_wr, seq_mem_page1;
    wire        ram_ready_w, access_complete_w, access_own_w;
    wire        ram_wt_w;           // u_ram's write_taken
    wire        seq_wr_taken_w;     // -> u_bridge.sdram_wr_taken
    wire [4:0]  seq_mem_pf_len;
    wire        pf_beat_v_w;
    wire [7:0]  pf_beat_dat_w;
    wire [4:0]  cpu_pf_len_w;

    pc98_gvram_seq #(.EGC(1'b1)) u_seq (
        .clk(clk), .reset(reset),
        .cpu_gvram(~ram_sel_n),
        .cpu_rd(seq_rd), .cpu_wr(seq_wr),
        // The aen qualifications mirror Chipset.sv: a stale word/prefetch
        // flag must never turn a DMA-owned byte write into a burst.
        .cpu_pf_len(cpu_pf_len_w & {5{~aen}}),
        .cpu_word(cpu_word_access & ~aen),
        .cpu_addr(seq_addr), .cpu_wdata(seq_wdata),
        .cpu_wdata_hi(cpu_data_bus_hi),
        .cpu_rdata(seq_cpu_rdata), .cpu_rdata_hi(seq_cpu_rdata_hi),
        .cpu_ready(guest_ready),
        .grcg_active(grcg_active), .grcg_rmw(grcg_rmw),
        .grcg_mask(grcg_mask), .grcg_tile(grcg_tile),
        .analog_mode(pc98_analog_w),
        .access_page(page_a6), .mem_page1(seq_mem_page1),
        .egc_active(egc_active_w), .egc_wr(egc_wr_w),
        .egc_rg(egc_rg_w), .egc_d(io_wr_data),
        .svc_req(1'b0), .svc_we(1'b0), .svc_raw(1'b0),
        .svc_addr(20'h0), .svc_wdata(8'h0),
        .svc_done(), .svc_rdata(), .dbg(),
        .mem_addr(seq_mem_addr), .mem_wdata(seq_mem_wdata),
        .mem_word(seq_mem_word), .mem_pf_len(seq_mem_pf_len),
        .mem_rd(seq_mem_rd), .mem_wr(seq_mem_wr),
        .mem_rdata(ram_dout), .mem_rdata_hi(ram_dout_hi),
        .mem_done(access_complete_w), .mem_own(access_own_w),
        .mem_ready(ram_ready_w),
        .mem_wr_taken(ram_wt_w),
        .cpu_wr_taken(seq_wr_taken_w)
    );

    // ---- RAM + SDRAM -------------------------------------------------------
    wire [7:0]  ram_dout, ram_dout_hi;
    wire        initilized_sdram_w;
    wire [12:0] s_a;  wire [1:0] s_ba;
    wire        s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};

    RAM u_ram (
        .clock(clk), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram_w),
        .gvram_page1_flag(seq_mem_page1),
        .address(seq_mem_addr), .internal_data_bus(seq_mem_wdata),
        .data_bus_out(ram_dout),
        .analog_mode(pc98_analog_w),
        .word_access(seq_mem_word),
        .prefetch_len(seq_mem_pf_len),
        .pf_beat_v(pf_beat_v_w), .pf_beat_dat(pf_beat_dat_w),
        .internal_data_bus_hi(cpu_data_bus_hi),
        .data_bus_out_hi(ram_dout_hi),
        .memory_read_n(~seq_mem_rd), .memory_write_n(~seq_mem_wr),
        .no_command_state(bus_mrd_n & bus_mwr_n & io_rd_n & io_wr_n),
        .memory_access_ready(ram_ready_w),
        .access_complete(access_complete_w),
        .access_own(access_own_w),
        .ram_address_select_n(ram_sel_n),
        .write_taken(ram_wt_w),
        .dbg(), .dbg2(), .dbg3(), .dbg4(), .dbg5(), .dbg6(), .dbg7(),
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
        .gv_rd_req(gv_req), .gv_rd_addr(gv_addr), .gv_rd_len(gv_len),
        .gv_rd_ack(gv_ack), .gv_rd_valid(gv_rvalid),
        .gv_rd_data(gv_rdata), .gv_rd_done(gv_done),
        .wait_count_clk_en(ce_neg),
        .ram_read_wait_cycle(ram_rd_wait), .ram_write_wait_cycle(ram_wr_wait),
        .vram_rd_wait_cycle(4'h0), .vram_wr_wait_cycle(4'h0),
        .ramimg_req(1'b0), .ramimg_we(1'b0), .ramimg_addr(24'h0),
        .ramimg_len(4'h0), .ramimg_wdata(16'h0000),
        .ramimg_ack(), .ramimg_rvalid(), .ramimg_rdata(), .ramimg_done()
    );

    sdram_board_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                        .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    assign cpu_reset_w = reset | ~sdram_up;
    always_ff @(posedge clk)
        if (initilized_sdram_w) sdram_up <= 1'b1;

    // ---- port D: the real display fetch ------------------------------------
    logic        disp_on_r = 1'b1;
    logic        analog4_r = 1'b0;
    initial begin
        int v;
        if ($value$plusargs("disp=%d", v))    disp_on_r  = (v != 0);
        if ($value$plusargs("analog4=%d", v)) analog4_r  = (v != 0);
    end

    logic dot_clk = 1'b0;
    always_ff @(posedge clk) dot_clk <= ~dot_clk;
    wire [9:0] vid_h, vid_v;
    wire       vid_hs, vid_vs, vid_hb, vid_vb, vid_de, vid_fs;
    pc98_video_timing u_vtiming (
        .clk(dot_clk), .ce(1'b1), .rst(1'b0),
        .hcount(vid_h), .vcount(vid_v), .hsync(vid_hs), .vsync(vid_vs),
        .hblank(vid_hb), .vblank(vid_vb), .de(vid_de), .frame_start(vid_fs)
    );

    wire        gv_req, gv_ack, gv_rvalid, gv_done;
    wire [23:0] gv_addr;
    wire  [3:0] gv_len;
    wire [15:0] gv_rdata;
    logic [15:0] disp_sad [0:3] = '{16'd0, 16'd0, 16'd0, 16'd0};
    logic [9:0]  disp_len [0:3] = '{10'd400, 10'd0, 10'd0, 10'd0};
    pc98_gvram_display u_gvram_disp (
        .clk(clk), .rst(reset),
        .rd_clk(dot_clk), .hcount(vid_h), .vcount(vid_v),
        .disp_on(disp_on_r), .disp_page(1'b0),
        .analog_mode(analog4_r), .dbl(1'b0),
        .pitch(8'd40), .mhz5(1'b0), .lrep(5'd0),
        .part_sad(disp_sad), .part_len(disp_len),
        .part_pbyte(4'h0), .vshift(6'd0),
        .p_req(gv_req), .p_addr(gv_addr), .p_len(gv_len),
        .p_ack(gv_ack), .p_rvalid(gv_rvalid), .p_rdata(gv_rdata),
        .p_done(gv_done), .gfx_dot(), .dbg()
    );

    // ---- READY -------------------------------------------------------------
    READY u_ready (
        .clock               (clk),
        .cpu_ce_posedge      (ce_pos),
        .cpu_ce_negedge      (ce_neg),
        .reset               (reset),
        .processor_ready     (proc_ready),
        .dma_ready           (),
        .dma_wait_n          (~dma_wait),
        .io_channel_ready    (guest_ready),
        .io_read_n           (io_rd_n),
        .io_write_n          (io_wr_n),
        .memory_read_n       (bus_mrd_n),
        .dma0_acknowledge_n  (1'b1),
        .address_enable_n    (aen)
    );

    // ---- the data bus back to the CPU --------------------------------------
    wire [7:0] din    = ~mem_rd_n ? (~ram_sel_n ? seq_cpu_rdata : 8'hFF)
                      :             8'hFF;
    wire [7:0] din_hi = ~mem_rd_n ? (~ram_sel_n ? seq_cpu_rdata_hi : 8'hFF)
                      :             8'hFF;

    // ========================================================================
    // the program, poked into the SDRAM image
    // ========================================================================
    //
    // Reset vector FFFF0 -> JMP F000:0000. The phases, bracketed by
    // OUT 88FEh,n / OUT 88FEh,n|80h:
    //
    //   01  REP STOSB  2048 B  @ ES:2000   (main RAM)
    //   02  REP STOSW  1024 W  @ ES:4000
    //   03  REP MOVSW  1024 W  DS:2000 -> ES:8000
    //   04  REP STOSB  2048 B  @ A800:0000 with GRCG TDW
    //   05  REP STOSB  2048 B  @ A800:2000 with GRCG RMW
    //   06  REP STOSB   512 B  @ A800:4000 with the EGC armed
    //   07  REP STOSB  2048 B  @ A800:6000 plain (window, no charger)
    //   08  byte-writes loop   @ A000 (TVRAM is not RAM -- open bus, skipped)
    //
    logic [7:0] prog [0:8191];
    int prog_len = 0;
    task emit(input logic [7:0] b);
        prog[prog_len] = b; prog_len++;
    endtask
    task emitw(input logic [15:0] w);
        emit(w[7:0]); emit(w[15:8]);
    endtask
    // OUT 88FEh, n
    task marker(input logic [7:0] n);
        emit(8'hB0); emit(n);          // MOV AL,n
        emit(8'hBA); emitw(16'h88FE);  // MOV DX,88FE
        emit(8'hEE);                   // OUT DX,AL
    endtask
    // MOV DX,imm16 ; OUT DX,AL -- port writes used for charger registers
    task outport(input logic [15:0] p, input logic [7:0] v);
        emit(8'hB0); emit(v); emit(8'hBA); emitw(p); emit(8'hEE);
    endtask

    initial begin
        prog_len = 0;
        // prologue
        emit(8'hFA);                        // CLI
        emit(8'hB8); emitw(16'h0000);       // MOV AX,0
        emit(8'h8E); emit(8'hD8);           // MOV DS,AX
        emit(8'h8E); emit(8'hC0);           // MOV ES,AX
        emit(8'h8E); emit(8'hD0);           // MOV SS,AX
        emit(8'hBC); emitw(16'h0400);       // MOV SP,0400

        // ---- phase 1: REP STOSB, 2048 bytes at 0x2000 ----
        marker(8'h01);
        emit(8'hBF); emitw(16'h2000);       // MOV DI,2000
        emit(8'hB9); emitw(16'h0800);       // MOV CX,0800
        emit(8'hB0); emit(8'h5A);           // MOV AL,5A
        emit(8'hF3); emit(8'hAA);           // REP STOSB
        marker(8'h81);

        // ---- phase 2: REP STOSW, 1024 words at 0x4000 ----
        marker(8'h02);
        emit(8'hBF); emitw(16'h4000);       // MOV DI,4000
        emit(8'hB9); emitw(16'h0400);       // MOV CX,0400
        emit(8'hB8); emitw(16'h5A5A);       // MOV AX,5A5A
        emit(8'hF3); emit(8'hAB);           // REP STOSW
        marker(8'h82);

        // ---- phase 3: REP MOVSW 0x2000 -> 0x8000, 1024 words ----
        marker(8'h03);
        emit(8'hBE); emitw(16'h2000);       // MOV SI,2000
        emit(8'hBF); emitw(16'h8000);       // MOV DI,8000
        emit(8'hB9); emitw(16'h0400);       // MOV CX,0400
        emit(8'hF3); emit(8'hA5);           // REP MOVSW
        marker(8'h83);

        // ---- phase 4: GRCG TDW rep stosb at A800:0000 ----
        marker(8'h04);
        outport(16'h007C, 8'h80);           // GRCG on, TDW, no mask
        outport(16'h007E, 8'hAA);           // tile 0
        outport(16'h007E, 8'hBB);           // tile 1
        outport(16'h007E, 8'hCC);           // tile 2
        outport(16'h007E, 8'hDD);           // tile 3
        emit(8'hB8); emitw(16'hA800);       // MOV AX,A800
        emit(8'h8E); emit(8'hC0);           // MOV ES,AX
        emit(8'hBF); emitw(16'h0000);       // MOV DI,0
        emit(8'hB9); emitw(16'h0800);       // MOV CX,0800
        emit(8'hB0); emit(8'h00);           // AL (TDW discards it)
        emit(8'hF3); emit(8'hAA);           // REP STOSB -> 4 plane writes each
        marker(8'h84);

        // ---- phase 5: GRCG RMW rep stosb at A800:2000 ----
        marker(8'h05);
        outport(16'h007C, 8'hC0);           // GRCG on, RMW
        emit(8'hBF); emitw(16'h2000);       // MOV DI,2000
        emit(8'hB9); emitw(16'h0800);       // MOV CX,0800
        emit(8'hB0); emit(8'hFF);           // AL=FF: all bits take tile
        emit(8'hF3); emit(8'hAA);           // REP STOSB -> rd+wr per plane
        marker(8'h85);
        // GRCG stays armed: egc_on = egc_arm & grcg_active in the seq.

        // ---- phase 6: EGC write rep stosb at A800:4000 ----
        marker(8'h06);
        outport(16'h007C, 8'h80);           // GRCG mode keeps the engine on
        outport(16'h006A, 8'h05);           // mode2 bit2 <- 1
        outport(16'h006A, 8'h07);           // mode2 bit3 <- 1 (EGC on)
        outport(16'h006A, 8'h01);           // mode2 bit0 <- 1 (analog)
        outport(16'h04A8, 8'hFF);           // egc mask lo
        outport(16'h04A9, 8'hFF);           // egc mask hi
        emit(8'hBF); emitw(16'h4000);       // MOV DI,4000
        emit(8'hB9); emitw(16'h0200);       // MOV CX,0200 (512B -- 8 legs each)
        emit(8'hB0); emit(8'h3C);           // AL
        emit(8'hF3); emit(8'hAA);           // REP STOSB
        marker(8'h86);

        // ---- phase 7: plain rep stosb on the window (charger off) ----
        marker(8'h07);
        outport(16'h007C, 8'h00);           // GRCG off
        outport(16'h006A, 8'h04);           // mode2 bit2 <- 0
        outport(16'h006A, 8'h06);           // mode2 bit3 <- 0 (EGC off)
        outport(16'h006A, 8'h00);           // mode2 bit0 <- 0 (analog off)
        emit(8'hBF); emitw(16'h6000);       // MOV DI,6000 (still ES=A800)
        emit(8'hB9); emitw(16'h0800);       // MOV CX,0800
        emit(8'hB0); emit(8'h77);           // AL
        emit(8'hF3); emit(8'hAA);           // REP STOSB
        marker(8'h87);

        // ---- phase 8: CALL/RET loop x500 -- push->pop store-load pattern ----
        // Real-hardware bench_ni NEARCALL regressed +36% when the posted
        // write queue was introduced: the CALL's push is queued, the RET's
        // pop reads the same address and stalls on wrq_ovl until the drain
        // retires. This phase reproduces that shape in sim.
        //
        // v2: pad so the CALL's bytes sit at sector offset 0x1D..0x1F and
        // LOOP+sub land in the next sector -- the exact bench_ni layout
        // (call@x2FD, loop@x300, sub@x303). With the stack sector that's
        // three live regions against two pf windows, the real-hardware
        // thrash case; the earlier single-sector version was the aligned
        // control (NEAR2ALGN) and did NOT reproduce the 407-clk/iter cost.
        marker(8'h08);
        while ((prog_len & 31) != 5'h1A) emit(8'h90);  // pad: MOV CX -> 0x1A
        emit(8'hB9); emitw(16'h01F4);       // MOV CX,500          @+0x1A
        emit(8'hE8); emitw(16'h0004);       // CALL +4 -> near_sub  @+0x1D..0x1F
        emit(8'hE2); emit(8'hFB);           // LOOP -5 -> CALL      @+0x20
        emit(8'hEB); emit(8'h01);           // JMP +1 -> done       @+0x22
        emit(8'hC3);                        // near_sub: RET        @+0x24
        marker(8'h88);

        // done: spin
        marker(8'hFF);
        emit(8'hEB); emit(8'hFE);           // JMP $
    end

    // poke the program + reset vector into the SDRAM image (1 guest byte per
    // word, flat-addressed the way poke() indexes).
    initial begin
        for (int i = 0; i < prog_len; i++)
            sdr.u_part.poke(24'h0F0000 + i, {8'h00, prog[i]});
        // FFFF0: EA 00 00 00 F0 = JMP FAR F000:0000 (ip, then seg, LE each)
        sdr.u_part.poke(24'h0FFFF0, 16'h00EA);
        sdr.u_part.poke(24'h0FFFF1, 16'h0000);
        sdr.u_part.poke(24'h0FFFF2, 16'h0000);
        sdr.u_part.poke(24'h0FFFF3, 16'h0000);
        sdr.u_part.poke(24'h0FFFF4, 16'h00F0);
    end

    // ========================================================================
    // cycle attribution
    // ========================================================================
    longint unsigned c_total = 0;
    longint unsigned c_ce    = 0;      // guest CPU clocks (ce posedges)
    longint unsigned c_bst   [0:3];    // bridge byte-engine state occupancy
    longint unsigned c_rfsm  [0:6];    // RAM FSM state occupancy
    longint unsigned c_sseq  [0:7];    // gvram_seq state occupancy
    longint unsigned c_qdep  = 0;      // sum of parked-queue depth
    int            c_qmax    = 0;
    longint unsigned c_qfull = 0;      // all four slots taken
    longint unsigned c_pa_wait = 0;    // port A req-up-not-acked
    longint unsigned c_pa_own  = 0;    // port A owns the device
    longint unsigned c_pa_ack  = 0;
    longint unsigned c_pd_own  = 0;    // port D owns the device
    longint unsigned c_ref     = 0;    // refresh cycles
    longint unsigned c_wrbeats = 0;    // SDRAM write beats on port A
    longint unsigned c_rdbeats = 0;
    longint unsigned c_gwr     = 0;    // guest write strobes (mem_wr_n asserts)
    longint unsigned c_grd     = 0;    // guest read strobes
    longint unsigned c_wbpend  = 0;    // zwb stb&~ack cycles
    longint unsigned c_gstall  = 0;    // cmd up, guest_ready down
    longint unsigned c_done    = 0;    // access_complete pulses
    // write strobe release latency: mem_wr_n low until guest_ready
    int              rel_lat   = 0;
    longint unsigned c_rel_sum = 0;
    longint unsigned c_rel_max = 0;
    longint unsigned c_rel_n   = 0;
    logic            rel_fly   = 1'b0;
    // drain latency: RAM leave IDLE -> next IDLE, i.e. one access's cost
    int              drain_lat = 0;
    longint unsigned c_drn_sum = 0;
    longint unsigned c_drn_n   = 0;
    logic            drain_fly = 1'b0;
    longint unsigned c_phit   = 0;     // window hits served with no bus cycle
    longint unsigned c_pfill  = 0;     // fill pairs armed
    longint unsigned c_pbeats = 0;     // beats appended to the window
    longint unsigned c_pkill  = 0;     // invalidations (write/io/DMA)

    localparam int MP_S_IDLE = 4, MP_S_RW = 6;
    wire mp_busy    = (u_ram.u_sdram.u_mp.state > MP_S_IDLE)
                  & (u_ram.u_sdram.u_mp.state != 4'd9)
                  & (u_ram.u_sdram.u_mp.state != 4'd10);
    wire [2:0] mp_grant = u_ram.u_sdram.u_mp.grant;
    wire [4:0] mp_reqs  = u_ram.u_sdram.u_mp.p_req;
    wire [4:0] mp_acks  = u_ram.u_sdram.u_mp.p_ack;
    wire       mp_wr    = mp_busy & u_ram.u_sdram.u_mp.cur_we
                      & (u_ram.u_sdram.u_mp.state == MP_S_RW);

    logic mem_wr_d = 1'b1, mem_rd_d = 1'b1;

    always_ff @(posedge clk) begin
        int qd;
        if (reset) begin
            mem_wr_d <= 1'b1; mem_rd_d <= 1'b1;
            rel_fly <= 1'b0; drain_fly <= 1'b0;
        end else if (sdram_up) begin
            mem_wr_d <= mem_wr_n;
            mem_rd_d <= mem_rd_n;
            c_total <= c_total + 1;
            if (ce_pos) c_ce <= c_ce + 1;
            c_bst[u_bridge.bstate] <= c_bst[u_bridge.bstate] + 1;
            c_rfsm[u_ram.state]    <= c_rfsm[u_ram.state] + 1;
            c_sseq[u_seq.st]       <= c_sseq[u_seq.st] + 1;
            qd = u_ram.wc_pend + u_ram.wc_pend2 + u_ram.wc_pend3
               + u_ram.cap_valid;
            c_qdep <= c_qdep + qd;
            if (qd > c_qmax) c_qmax <= qd;
            if (qd == 4) c_qfull <= c_qfull + 1;
            if (mp_reqs[0] & ~mp_acks[0]) c_pa_wait <= c_pa_wait + 1;
            if (mp_acks[0])               c_pa_ack  <= c_pa_ack + 1;
            if (mp_busy & (mp_grant == 3'd0)) c_pa_own <= c_pa_own + 1;
            if (mp_busy & (mp_grant == 3'd3)) c_pd_own <= c_pd_own + 1;
            if (u_ram.u_sdram.u_mp.stat_refresh) c_ref <= c_ref + 1;
            if (mp_wr & (mp_grant == 3'd0)) c_wrbeats <= c_wrbeats + 1;
            if (u_ram.u_sdram.u_mp.p_rvalid & (mp_grant == 3'd0))
                c_rdbeats <= c_rdbeats + 1;
            if (mem_wr_d & ~mem_wr_n) c_gwr <= c_gwr + 1;
            if (mem_rd_d & ~mem_rd_n) c_grd <= c_grd + 1;
            if (zwb_stb & ~zwb_ack)   c_wbpend <= c_wbpend + 1;
            if ((~mem_rd_n | ~mem_wr_n) & ~guest_ready)
                c_gstall <= c_gstall + 1;
            if (u_ram.state == u_ram.COMPLETE_RAM_RW) c_done <= c_done + 1;
            if (u_bridge.hit_serve) c_phit  <= c_phit + 1;
            if (u_bridge.arm_fill || u_bridge.fillm_go)
                                    c_pfill <= c_pfill + 1;
            if (u_bridge.pf_beat_v && (u_bridge.cur_pf || u_bridge.cur_fillm)
                && u_bridge.fill_ok
                && (u_bridge.bstate == u_bridge.B_CMD))
                c_pbeats <= c_pbeats + 1;
            if ((!u_bridge.bus_ours
                 || (u_bridge.arm_wr && (u_bridge.wr_ovl0 || u_bridge.wr_ovl1))
                 || u_bridge.arm_iow)
                && ((u_bridge.pf_cnt0 | u_bridge.pf_cnt1) != 6'd0))
                c_pkill <= c_pkill + 1;
            // release latency on each guest write strobe
            if (mem_wr_d & ~mem_wr_n) begin
                rel_fly <= 1'b1; rel_lat <= 0;
            end else if (rel_fly) begin
                rel_lat <= rel_lat + 1;
                if (guest_ready) begin
                    rel_fly <= 1'b0;
                    c_rel_sum <= c_rel_sum + rel_lat;
                    c_rel_n   <= c_rel_n + 1;
                    if (rel_lat > c_rel_max) c_rel_max <= rel_lat;
                end
            end
            // drain latency: cycles the RAM FSM spends non-IDLE per access
            if (!drain_fly && (u_ram.state != u_ram.IDLE)) begin
                drain_fly <= 1'b1; drain_lat <= 1;
            end else if (drain_fly) begin
                drain_lat <= drain_lat + 1;
                if (u_ram.state == u_ram.IDLE) begin
                    drain_fly <= 1'b0;
                    c_drn_sum <= c_drn_sum + drain_lat;
                    c_drn_n   <= c_drn_n + 1;
                end
            end
        end
    end

    // ---- write-beat hit map -------------------------------------------------
    // Each SDRAM write beat the mp issues for port A lands at cur_addr+p_wcnt
    // (the burst is column-contiguous). Mark which guest bytes actually got a
    // beat; a captured-but-never-beaten write shows as a hole here.
    logic        wr_hit [0:2047];
    initial for (int i = 0; i < 2048; i++) wr_hit[i] = 1'b0;
    always_ff @(posedge clk) begin
        if (u_ram.u_sdram.u_mp.state == 4'd6    // S_RW
            && u_ram.u_sdram.u_mp.cur_we && mp_grant == 3'd0) begin
            automatic longint g = u_ram.u_sdram.u_mp.cur_addr
                                + u_ram.u_sdram.u_mp.p_wcnt;
            if (g >= 20'h4000 && g < 20'h4800)
                wr_hit[g - 20'h4000] <= 1'b1;
        end
    end

    // log RAM write-accepts + the shim burst they launch, in a narrow window
    // (+accaddr=N sets the base, default near a previously-seen hole).
    logic [19:0] acc_lo = 20'h4500, acc_hi = 20'h4560;
    initial begin
        int v;
        if ($value$plusargs("accaddr=%h", v)) begin
            acc_lo = v; acc_hi = v + 20'h0300;
        end
    end
    // Per-cycle traces are the bulk of the output; gate them so correctness
    // runs (and CI) stay readable. +vtrace restores them all.
    logic trace = 1'b0;
    initial trace = $test$plusargs("vtrace");

    // The whole capture/strobe trace is phase-1-window diagnostics -- gated
    // on +vtrace so correctness runs (and CI) stay readable. The dq_*
    // histogram below stays live: it feeds the verify summary.
    always_ff @(posedge clk) if (trace) begin
        if (u_ram.state == u_ram.IDLE
            && u_ram.next_state == u_ram.RAM_WRITE_1
            && u_ram.accept_live_wr
            && u_ram.accept_address[19:0] >= acc_lo
            && u_ram.accept_address[19:0] < acc_hi)
            $display("  ACCW t=%0t ad=%05x w=%0d d=%02x/%02x",
                     $time, u_ram.accept_address[19:0], u_ram.accept_word,
                     u_ram.accept_data, u_ram.accept_data_hi);
        // shim captures the burst on the !busy && write_request edge; the
        // operands live on access_* that same cycle.
        if (!u_ram.u_sdram.busy && u_ram.u_sdram.write_request
            && u_ram.access_address[19:0] >= acc_lo
            && u_ram.access_address[19:0] < acc_hi)
            $display("  SHIM t=%0t ad=%05x num=%0d din=%02x/%02x",
                     $time, u_ram.access_address[19:0], u_ram.access_num,
                     u_ram.access_data_in[7:0], u_ram.access_data_in_hi[7:0]);
        // what the bus actually presents: every write strobe rise + its live
        // operands. Distinguishes a word access mis-captured from the bridge
        // splitting a word write into byte accesses.
        if (u_ram.write_strobe_rose
            && u_ram.latch_address[19:0] >= acc_lo
            && u_ram.latch_address[19:0] < acc_hi)
            $display("  WSTB t=%0t ad=%05x wn=%0d d=%02x/%02x",
                     $time, u_ram.latch_address[19:0], u_ram.word_now,
                     u_ram.internal_data_bus, u_ram.internal_data_bus_hi);
        // every durable capture (park slot / cap / live accept) -- the word
        // flag that actually latches vs the live word_now, and the bridge's
        // word_access line. A word write captured while word_access is low
        // drains as a single byte -> the odd half is lost.
        if (u_ram.write_command
            && (u_ram.new_write_strobe | u_ram.new_write_strobe2
                | u_ram.new_write_strobe3 | u_ram.idle_park | u_ram.new_cap
                | u_ram.wr_accept_live)
            && u_ram.latch_address[19:0] >= acc_lo
            && u_ram.latch_address[19:0] < acc_hi)
            $display("  CAP t=%0t ad=%05x wn=%0d cwa=%0d smw=%0d dq=%0d pend=%0d%0d%0d cap=%0d",
                     $time, u_ram.latch_address[19:0], u_ram.word_now,
                     cpu_word_access, seq_mem_word, u_bridge.cur_dq,
                     u_ram.wc_pend, u_ram.wc_pend2, u_ram.wc_pend3,
                     u_ram.cap_valid);
        // bridge-side: what the write queue accepted and what each drain
        // presents, for the same window.
        if (u_bridge.wrq_push
            && u_bridge.srv_addr >= acc_lo && u_bridge.srv_addr < acc_hi)
            $display("  WQP t=%0t a=%05x d=%04x ube=%b cnt=%0d",
                     $time, u_bridge.srv_addr, u_bridge.srv_data,
                     u_bridge.srv_ube, u_bridge.wrq_cnt);
        if (u_bridge.arm_drain
            && u_bridge.wrq_addr[0] >= acc_lo && u_bridge.wrq_addr[0] < acc_hi)
            $display("  WQD t=%0t a=%05x d=%04x ube=%b",
                     $time, u_bridge.wrq_addr[0], u_bridge.wrq_data[0],
                     u_bridge.wrq_ube[0]);
        // per-cycle view of any write strobe the bridge presents for the
        // window: the pair engine's presented address/word flag vs what the
        // RAM sees. Reveals a drain re-arm, a byte-pair split, or a stale
        // residual strobe.
        if (u_ram.write_command
            && (u_bridge.ad_out >= acc_lo && u_bridge.ad_out < acc_hi))
            $display("  STB t=%0t ad=%05x lad=%05x wa=%0d bs=%0d ps=%0d bi=%0d dq=%0d tc=%0d sw=%0d pr=%0d",
                     $time, u_bridge.ad_out, u_ram.latch_address[19:0],
                     u_bridge.word_access, u_bridge.bstate, u_bridge.ps_r,
                     u_bridge.byte_idx, u_bridge.cur_dq, u_bridge.t_cnt,
                     u_bridge.saw_low, u_bridge.processor_ready);
        // catch saw_low arming: log the dip, whether OUR write strobe is on
        // the bus yet, and whether the RAM even decodes a command right now.
        if (u_bridge.bstate == u_bridge.B_CMD && u_bridge.cur_dq
            && !u_bridge.saw_low && u_bridge.ready_d1
            && !u_bridge.processor_ready
            && u_bridge.ad_out >= acc_lo && u_bridge.ad_out < acc_hi)
            $display("  SWARM t=%0t ad=%05x wcmd=%0d rsn=%0d sel=%0d bo=%0d smw=%0d mrdy=%0d icr=%0d",
                     $time, u_bridge.ad_out, u_ram.write_command,
                     u_ram.memory_write_n, u_ram.ram_address_select_n,
                     u_bridge.bus_ours, seq_mem_wr, ram_ready_w, guest_ready);
    end

    // histogram of t_cnt when a drain's write command first reaches seq_mem_wr.
    // Unconditional: it feeds the verify summary. Keyed on cur_addr (stable
    // for the whole B_CMD), armed on arm_drain.
    bit dq_seen_cmd [0:8191];
    int dq_present  [0:7];
    int dq_max_pres = 0;
    always_ff @(posedge clk) begin
        if (u_bridge.cur_dq && u_bridge.bstate == u_bridge.B_CMD
            && seq_mem_wr && !dq_seen_cmd[u_bridge.cur_addr[12:0]]) begin
            dq_seen_cmd[u_bridge.cur_addr[12:0]] <= 1'b1;
            dq_present[u_bridge.t_cnt] <= dq_present[u_bridge.t_cnt] + 1;
            if (u_bridge.t_cnt > dq_max_pres) dq_max_pres <= u_bridge.t_cnt;
        end
        if (u_bridge.arm_drain)
            dq_seen_cmd[u_bridge.wrq_addr[0][12:0]] <= 1'b0;
        if (u_bridge.bstate == u_bridge.B_IDLE)
            dq_seen_cmd <= '{default:0};
    end

    // ========================================================================
    // phase brackets: OUT 88FEh,n marks start (n) and end (n|80h)
    // ========================================================================
    string phase_name [0:255];
    initial begin
        phase_name[8'h01] = "REP STOSB 2048B main RAM";
        phase_name[8'h02] = "REP STOSW 1024W main RAM";
        phase_name[8'h03] = "REP MOVSW 1024W main RAM";
        phase_name[8'h04] = "REP STOSB 2048B GRCG TDW";
        phase_name[8'h05] = "REP STOSB 2048B GRCG RMW";
        phase_name[8'h06] = "REP STOSB  512B EGC";
        phase_name[8'h07] = "REP STOSB 2048B window plain";
        phase_name[8'h08] = "CALL/RET x500 stack";
        phase_name[8'hFF] = "done";
    end
    int phase_bytes [0:255];
    initial begin
        phase_bytes[8'h01] = 2048;
        phase_bytes[8'h02] = 2048;
        phase_bytes[8'h03] = 2048;
        phase_bytes[8'h04] = 2048;
        phase_bytes[8'h05] = 2048;
        phase_bytes[8'h06] = 512;
        phase_bytes[8'h07] = 2048;
        phase_bytes[8'h08] = 500;
    end

    // snapshot record
    typedef struct {
        longint unsigned total, ce, wbpend, gstall, done;
        longint unsigned bst[0:3], rfsm[0:6], sseq[0:7];
        longint unsigned qdep, qfull, pa_wait, pa_own, pa_ack, pd_own, refr;
        longint unsigned wrbeats, rdbeats, gwr, grd;
        longint unsigned rel_sum, rel_max, rel_n, drn_sum, drn_n;
        longint unsigned phit, pfill, pbeats, pkill;
        int qmax;
    } snap_t;
    snap_t s0;

    task snap;
        s0.total=c_total; s0.ce=c_ce; s0.wbpend=c_wbpend; s0.gstall=c_gstall;
        s0.done=c_done;
        for (int i = 0; i < 4; i++) s0.bst[i]  = c_bst[i];
        for (int i = 0; i < 7; i++) s0.rfsm[i] = c_rfsm[i];
        for (int i = 0; i < 8; i++) s0.sseq[i] = c_sseq[i];
        s0.qdep=c_qdep; s0.qfull=c_qfull; s0.pa_wait=c_pa_wait;
        s0.pa_own=c_pa_own; s0.pa_ack=c_pa_ack; s0.pd_own=c_pd_own;
        s0.refr=c_ref; s0.wrbeats=c_wrbeats; s0.rdbeats=c_rdbeats;
        s0.gwr=c_gwr; s0.grd=c_grd;
        s0.rel_sum=c_rel_sum; s0.rel_max=c_rel_max; s0.rel_n=c_rel_n;
        s0.drn_sum=c_drn_sum; s0.drn_n=c_drn_n; s0.qmax=c_qmax;
        s0.phit=c_phit; s0.pfill=c_pfill; s0.pbeats=c_pbeats; s0.pkill=c_pkill;
    endtask

    int cur_phase = -1;
    task phase_start(input int n);
        cur_phase = n;
        snap;
    endtask

    task phase_end(input int n);
        longint unsigned dt;
        int byt;
        dt  = c_total - s0.total;
        byt = (n < 256) ? phase_bytes[n] : 0;
        $display("");
        $display("== phase %02X  %s ==", n, phase_name[n]);
        $display("   clks=%0d  bytes=%0d  -> %0d.%02d clk/B = %.0f ns/B",
                 dt, byt, byt ? dt/byt : 0,
                 byt ? int'(((dt*100)/byt) % 100) : 0,
                 byt ? real'(dt)*23.279/real'(byt) : 0.0);
        $display("   ce_pos=%0d (%.2f cpu-clk/B)   zwb_pend=%0d  gstall=%0d",
                 c_ce-s0.ce, byt ? real'(c_ce-s0.ce)/real'(byt) : 0.0,
                 c_wbpend-s0.wbpend, c_gstall-s0.gstall);
        $display("   bridge bstate: IDLE=%0d CMD=%0d GAP=%0d",
                 c_bst[0]-s0.bst[0], c_bst[1]-s0.bst[1], c_bst[2]-s0.bst[2]);
        $display("   ram fsm: IDLE=%0d W1=%0d W2=%0d R1=%0d R2=%0d CMP=%0d WAIT=%0d",
                 c_rfsm[0]-s0.rfsm[0], c_rfsm[1]-s0.rfsm[1],
                 c_rfsm[2]-s0.rfsm[2], c_rfsm[3]-s0.rfsm[3],
                 c_rfsm[4]-s0.rfsm[4], c_rfsm[5]-s0.rfsm[5],
                 c_rfsm[6]-s0.rfsm[6]);
        $display("   seq st: IDLE=%0d RD=%0d RDW=%0d WR=%0d WRW=%0d DONE=%0d EVT2=%0d",
                 c_sseq[0]-s0.sseq[0], c_sseq[1]-s0.sseq[1],
                 c_sseq[2]-s0.sseq[2], c_sseq[3]-s0.sseq[3],
                 c_sseq[4]-s0.sseq[4], c_sseq[5]-s0.sseq[5],
                 c_sseq[6]-s0.sseq[6]);
        $display("   queue: avg-depth=%.2f max=%0d full4=%0d cyc",
                 real'(c_qdep-s0.qdep)/real'(dt), c_qmax, c_qfull-s0.qfull);
        $display("   portA: acks=%0d wait=%0d own=%0d | portD own=%0d | refresh=%0d",
                 c_pa_ack-s0.pa_ack, c_pa_wait-s0.pa_wait, c_pa_own-s0.pa_own,
                 c_pd_own-s0.pd_own, c_ref-s0.refr);
        $display("   beats: wr=%0d rd=%0d | guest wr-strobes=%0d rd=%0d | fsm dones=%0d",
                 c_wrbeats-s0.wrbeats, c_rdbeats-s0.rdbeats,
                 c_gwr-s0.gwr, c_grd-s0.grd, c_done-s0.done);
        $display("   prefetch: hits=%0d fills=%0d fillbeats=%0d kills=%0d",
                 c_phit-s0.phit, c_pfill-s0.pfill,
                 c_pbeats-s0.pbeats, c_pkill-s0.pkill);
        $display("   wr release: n=%0d avg=%0d max=%0d | drain: n=%0d avg=%0d cyc",
                 c_rel_n-s0.rel_n,
                 (c_rel_n-s0.rel_n) ? int'((c_rel_sum-s0.rel_sum)/(c_rel_n-s0.rel_n)) : 0,
                 c_rel_max,
                 c_drn_n-s0.drn_n,
                 (c_drn_n-s0.drn_n) ? int'((c_drn_sum-s0.drn_sum)/(c_drn_n-s0.drn_n)) : 0);
        $fflush;
    endtask

    // ---- end-of-run verification -------------------------------------------
    // After the program finishes: the data regions must hold their REP-op
    // patterns, the code image must be intact, and under +GRANT the run must
    // have survived every grant without a wild transfer or a stray write.
    task automatic verify_run;
        int bad = 0;
        int dma_seen = 0;
        logic [15:0] w;
        begin
            for (int a = 20'h2000; a < 20'h2800; a++) begin
                w = sdr.u_part.peek(a);
                if (w[7:0] !== 8'h5A) begin
                    if (bad < 12) $display("  BAD stosb %05x=%02x", a, w[7:0]);
                    bad++;
                end
            end
            for (int a = 20'h4000; a < 20'h4800; a++) begin
                w = sdr.u_part.peek(a);
                if (w[7:0] !== 8'h5A) begin
                    if (bad < 12) $display("  BAD stosw %05x=%04x", a, w);
                    bad++;
                end
            end
            // bytes the mp never issued a write beat to (captured-but-dropped)
            begin
                int nh = 0;
                for (int a = 0; a < 2048; a++)
                    if (!wr_hit[a]) begin
                        if (nh < 12) $display("  NOBEAT %05x", 20'h4000 + a);
                        nh++;
                    end
                $display("  wr_hit holes=%0d", nh);
            end
            for (int a = 20'h8000; a < 20'h8800; a++) begin
                w = sdr.u_part.peek(a);
                if (w[7:0] !== 8'h5A) begin
                    if (bad < 12) $display("  BAD movsw %05x=%02x", a, w[7:0]);
                    bad++;
                end
            end
            for (int i = 0; i < 16; i++) begin
                w = sdr.u_part.peek(20'hF0000 + i);
                if (w[7:0] !== prog[i]) begin
                    $display("  BAD code %05x=%02x want %02x",
                             20'hF0000 + i, w[7:0], prog[i]);
                    bad++;
                end
            end
            // Under +GRANT the synthetic DMAC streams A5^addr over the
            // whole 4 KB fill buffer, so every byte of the probed
            // 256-byte window must hold the pattern -- anything less is
            // a DMA write that never landed. Without +GRANT the region
            // is whatever the phases left; dma_seen is noise then.
            for (int a = 20'h30000; a < 20'h30100; a++) begin
                w = sdr.u_part.peek(a);
                if (w[7:0] == (8'hA5 ^ a[7:0])) dma_seen++;
            end
            $display("VERIFY: bad=%0d diverged=%0d stray=%0d grants=%0d midcmd=%0d dma_bytes=%0d",
                     bad, diverged, stray, grants, grants_midcmd, dma_seen);
            $display("  RAM drop-witness: uncov=%0d parks=%0d first=%05x/%02x st=%0d last=%05x/%02x",
                     u_ram.dbg_uncov, u_ram.dbg_parks,
                     u_ram.dbg_uncov_addr, u_ram.dbg_uncov_data, u_ram.dbg_uncov_st,
                     u_ram.dbg_uncov_addr2, u_ram.dbg_uncov_data2);
            // queue occupancy at verify: if a bad write is still parked it is
            // wedged, not dropped. acc_ring = last 3 writes the FSM accepted.
            $display("  RAM queue @verify: st=%0d pend=%b%b%b cap=%b inflight(wr=%b rd=%b) acc_ring=%08x %08x %08x",
                     u_ram.state, u_ram.wc_pend, u_ram.wc_pend2, u_ram.wc_pend3,
                     u_ram.cap_valid, u_ram.accept_live_wr, u_ram.accept_live_rd,
                     u_ram.acc_ring[2], u_ram.acc_ring[1], u_ram.acc_ring[0]);
            $display("  drain cmd-present @t_cnt: [%0d %0d %0d %0d %0d %0d %0d %0d] max=%0d",
                     dq_present[0], dq_present[1], dq_present[2], dq_present[3],
                     dq_present[4], dq_present[5], dq_present[6], dq_present[7],
                     dq_max_pres);
            // bad/diverged/stray are direct loss checks; dbg_uncov is
            // RAM's own "a write strobe fell with its operands never
            // durably held" witness -- a true-loss counter, not a
            // heuristic; and under +GRANT the fill window must be whole.
            if (bad || diverged || stray || (u_ram.dbg_uncov != 16'd0)
                || (grant_en && (dma_seen != 256 || grants == 0)))
                $display("=== FAIL tb_mem_perf ===");
            else
                $display("=== PASS tb_mem_perf ===");
        end
    endtask

    // marker decode on the IO-write strobe
    logic io_marker_d = 1'b1;
    int   settle_ctr  = -1;
    wire  io_marker   = ~io_wr_n & (cpu_address == 16'h88FE);
    always_ff @(posedge clk) begin
        io_marker_d <= io_wr_n;
        if (settle_ctr >= 0) begin             // post-FF settle: let the
            if (settle_ctr == 0) begin         // posted-write queue drain
                verify_run;                    // before peeking the store
                cur_phase = 256;
                $fflush;
                $finish;
            end
            settle_ctr <= settle_ctr - 1;
        end else if (io_marker & io_marker_d) begin   // first strobe edge
            if (cpu_data_bus == 8'hFF) begin     // done marker: bit7 set too,
                $display("=== all phases done ===");   // so test it first
                settle_ctr <= 20000;             // long drain, then verify
            end else if (cpu_data_bus[7]) begin
                if (cur_phase >= 0) phase_end(cpu_data_bus[6:0]);
                cur_phase = -1;
            end else begin
                phase_start({25'd0, cpu_data_bus[6:0]});
                c_qmax    <= 0;           // per-phase maxima
                c_rel_max <= 0;
            end
        end
    end

    // ---- divergence + stray-write traps (the wild-jump witnesses) ----------
    // The program runs at F0000..+len and fetches the FFFF0 reset vector at
    // boot; it writes 0x2000/0x4000/0x8000 (data), the ~0x0400 stack and the
    // A8000 window, and the DMAC writes 0x30000-0x30FFF. A far-transfer that
    // sends CS:IP out of the code image is the SuperDepth symptom; a write to
    // the code/reset-vector region is a stray that could cause it.
    always_ff @(posedge clk) begin
        if (sdram_up && !reset) begin
            // CS:IP must stay in the code image (or the reset-vector fetch)
            if (!((zet_pc >= 20'hF0000 && zet_pc < 20'hF2000) ||
                  (zet_pc >= 20'hFFF00))) begin
                if (diverged < 16)
                    $display("*** DIVERGE pc=%05x aen=%b dma_act=%b bst=%0d ad=%05x t=%0t",
                             zet_pc, aen, dma_active, u_bridge.bstate,
                             cpu_address, $time);
                diverged <= diverged + 1;
            end
            // no write may touch the code image or the reset vector
            if (seq_mem_wr && seq_mem_addr >= 20'hF0000) begin
                if (stray < 16)
                    $display("*** STRAYWR->CODE addr=%05x d=%02x aen=%b dma_act=%b bst=%0d t=%0t",
                             seq_mem_addr, seq_mem_wdata, aen, dma_active,
                             u_bridge.bstate, $time);
                stray <= stray + 1;
            end
        end
    end

    // heartbeat so a piped stdout still shows the bench is alive
    int hb = 0;
    always_ff @(posedge clk) begin
        hb <= hb + 1;
        if (hb[21:0] == 22'h100000) begin
            $display("... hb pc=%05x ad=%05x bst=%0d rfsm=%0d sseq=%0d qd=%0d ph=%0d",
                     zet_pc, cpu_address, u_bridge.bstate, u_ram.state,
                     u_seq.st, u_ram.wc_pend + u_ram.wc_pend2 +
                     u_ram.wc_pend3 + u_ram.cap_valid, cur_phase);
            $display("      pf0=%05x/%0d..%0d pf1=%05x/%0d..%0d live=%0b dead=%0d ok=%0d cur_pf=%0d/%0d m1=%0d req_ad=%05x",
                     u_bridge.pf_base0, u_bridge.pf_lo0, u_bridge.pf_cnt0,
                     u_bridge.pf_base1, u_bridge.pf_lo1, u_bridge.pf_cnt1,
                     u_bridge.pf_live, u_bridge.pf_dead, u_bridge.fill_ok,
                     u_bridge.cur_pf,
                     u_bridge.cur_pf_w, u_bridge.pf_miss1,
                     u_bridge.srv_addr);
            $fflush;
        end
    end

    // Fills and fill-on-miss arms are rare enough to print unthrottled.
    reg [1:0] dead_d = 2'd0;
    always_ff @(posedge clk) if (trace) begin
        dead_d <= u_bridge.pf_dead;
        if (u_bridge.pf_dead != dead_d)
            $display("DEAD->%0d t=%0t cur_pf=%0d flm=%0d len=%0d beats=%0d ok=%0d ad=%05x w=%0d bst=%0d",
                     u_bridge.pf_dead, $time, u_bridge.cur_pf,
                     u_bridge.cur_fillm, u_bridge.cur_pf_len,
                     u_bridge.fill_beats, u_bridge.fill_ok,
                     u_bridge.cur_addr, u_bridge.cur_pf_w,
                     u_bridge.bstate);
        if (u_bridge.pf_beat_v && (u_bridge.cur_pf || u_bridge.cur_fillm))
            $display("BEAT t=%0t flm=%0d dat=%02x cnt=%0d/%0d bst=%0d ours=%0d ok=%0d",
                     $time, u_bridge.cur_fillm, u_bridge.pf_beat_dat,
                     u_bridge.pf_cnt0, u_bridge.pf_cnt1,
                     u_bridge.bstate, u_bridge.bus_ours, u_bridge.fill_ok);
        if (u_bridge.pf_fill_done)
            $display("FDONE t=%0t flm=%0d beats=%0d ok=%0d ad=%05x",
                     $time, u_bridge.cur_fillm, u_bridge.fill_beats,
                     u_bridge.fill_ok, u_bridge.cur_addr);
        if (u_bridge.arm_fill)
            $display("PFFILL t=%0t next=%05x len=%0d",
                     $time, u_bridge.pf_next[19:0], u_bridge.pf_fill_len);
        if (u_bridge.arm_req && u_bridge.fillm_go)
            $display("FLM t=%0t ad=%05x w=%0d len=%0d new=%0d ph=%0d",
                     $time, u_bridge.srv_addr, u_bridge.fillm_w,
                     u_bridge.fillm_len, u_bridge.fillm_new, cur_phase);
        // Cycle-accurate view while a fill/fillm pair owns the engine.
        if (u_bridge.cur_pf || u_bridge.cur_fillm)
            $display("CYC t=%0t bst=%0d pslen=%0d rdcmd=%0d rflag=%0d rfsm=%0d icr=%0d rnw=%0d qn=%0d prnw=%0d prdy=%0d t=%0d sawlow=%0d ours=%0d beat=%0d ad=%05x",
                     $time, u_bridge.bstate, u_bridge.pf_req_len,
                     u_ram.read_command, u_ram.read_flag, u_ram.state,
                     u_ready.io_channel_ready, u_ready.ready_n_or_wait,
                     u_ready.ready_n_or_wait_Qn, u_ready.prev_ready_n_or_wait,
                     u_bridge.processor_ready,
                     u_bridge.t_cnt, u_bridge.saw_low, u_bridge.bus_ours,
                     u_bridge.pf_beat_v, u_bridge.cur_addr);
    end

    // first events of the prefetch engine's life, for bring-up
    int pfdbg = 0;
    int pfdbg_max = 300;
    initial if ($value$plusargs("pfdbg=%d", pfdbg_max)) ;
    always_ff @(posedge clk) if (trace && pfdbg < pfdbg_max) begin
        if (u_bridge.hit_serve) begin
            // flat store is byte-indexed: one guest byte per word's low half
            automatic logic [15:0] w0  = sdr.u_part.peek(u_bridge.srv_addr);
            automatic logic [15:0] w1  = sdr.u_part.peek(u_bridge.srv_addr + 20'd1);
            automatic logic [7:0]  eb  = w0[7:0];
            automatic logic [7:0]  eb2 = w1[7:0];
            automatic logic [15:0] got = u_bridge.pf_hit_word;
            automatic logic [15:0] exp = u_bridge.srv_ube ? {eb, eb} : {eb2, eb};
            $display("PFHIT t=%0t ad=%05x w=%0d got=%04x exp=%04x %s",
                     $time, u_bridge.srv_addr, u_bridge.pf_hw, got, exp,
                     (got == exp) ? "OK" : "*** PF-DATA-MISMATCH ***");
            pfdbg++;
        end
        if (u_bridge.arm_rd_ok) begin
            $display("PFMISS t=%0t ad=%05x b0=%05x/%0d b1=%05x/%0d c0=%0d c1=%0d m1=%0d",
                     $time, u_bridge.srv_addr,
                     u_bridge.pf_base0, u_bridge.pf_cnt0,
                     u_bridge.pf_base1, u_bridge.pf_cnt1,
                     u_bridge.cont0, u_bridge.cont1,
                     u_bridge.pf_miss1);
            pfdbg++;
        end
    end

    // ---- dropped-write witness ----------------------------------------------
    // Per-signal shift registers (bit 0 = newest) so there is no packed-field
    // alignment to get wrong. On an uncovered strobe fall in the stosw range
    // dump the preceding 24 cycles to see exactly what released the write
    // before its operands were captured.
    localparam int RB = 32;
    int          losstr = 0;
    int          untr   = 0;
    logic [RB-1:0] h_ce, h_prdy, h_icr, h_mrdy, h_rnw, h_rqn, h_prnw;
    logic [RB-1:0] h_swr, h_wcmd, h_wcd, h_mwn, h_rsn;
    logic [RB-1:0] h_wcov, h_cs, h_wso, h_cap, h_wn, h_cw;
    logic [RB-1:0] h_nws1, h_nws2, h_nws3, h_idpk, h_ncap, h_wal;
    logic [RB-1:0] h_wr_fell, h_dupcov;
    logic [RB-1:0] h_aen, h_exp, h_iwn;
    logic [2:0]    h_sst [0:RB-1];
    logic [2:0]    h_mc  [0:RB-1];
    logic [2:0]    h_psr [0:RB-1];
    logic [2:0]    h_st  [0:RB-1];
    logic [2:0]    h_pend[0:RB-1];
    logic [19:0]   h_ad  [0:RB-1];
    int            hwptr = 0;
    always_ff @(posedge clk) begin
        h_ce    <= {h_ce[RB-2:0],    ce_pos};
        h_prdy  <= {h_prdy[RB-2:0],  proc_ready};
        h_icr   <= {h_icr[RB-2:0],   guest_ready};
        h_mrdy  <= {h_mrdy[RB-2:0],  ram_ready_w};
        h_rnw   <= {h_rnw[RB-2:0],   u_ready.ready_n_or_wait};
        h_rqn   <= {h_rqn[RB-2:0],   u_ready.ready_n_or_wait_Qn};
        h_prnw  <= {h_prnw[RB-2:0],  u_ready.prev_ready_n_or_wait};
        h_swr   <= {h_swr[RB-2:0],   seq_mem_wr};
        h_wcmd  <= {h_wcmd[RB-2:0],  u_ram.write_command};
        h_wcd   <= {h_wcd[RB-2:0],   u_ram.write_command_d};
        h_mwn   <= {h_mwn[RB-2:0],   u_ram.memory_write_n};
        h_rsn   <= {h_rsn[RB-2:0],   u_ram.ram_address_select_n};
        h_wcov  <= {h_wcov[RB-2:0],  u_ram.wr_covered};
        h_cs    <= {h_cs[RB-2:0],    u_ram.cov_same};
        h_wso   <= {h_wso[RB-2:0],   u_ram.wr_strobe_open};
        h_cap   <= {h_cap[RB-2:0],   u_ram.cap_valid};
        h_wn    <= {h_wn[RB-2:0],    u_ram.word_now};
        h_cw    <= {h_cw[RB-2:0],    cpu_word_access};
        h_nws1  <= {h_nws1[RB-2:0],  u_ram.new_write_strobe};
        h_nws2  <= {h_nws2[RB-2:0],  u_ram.new_write_strobe2};
        h_nws3  <= {h_nws3[RB-2:0],  u_ram.new_write_strobe3};
        h_idpk  <= {h_idpk[RB-2:0],  u_ram.idle_park};
        h_ncap  <= {h_ncap[RB-2:0],  u_ram.new_cap};
        h_wal   <= {h_wal[RB-2:0],   u_ram.wr_accept_live};
        h_wr_fell <= {h_wr_fell[RB-2:0], u_ram.write_strobe_fell};
        h_dupcov  <= {h_dupcov[RB-2:0], u_ram.dup_covered};
        h_aen     <= {h_aen[RB-2:0],     aen};
        h_sst[hwptr] <= u_seq.st;
        h_exp     <= {h_exp[RB-2:0],     u_seq.expand};
        h_iwn     <= {h_iwn[RB-2:0],     mem_wr_n};
        h_mc[hwptr] <= u_8288.machine_cycle;
        h_psr[hwptr] <= processor_status;
        h_st[hwptr]  <= u_ram.state;
        h_pend[hwptr] <= {u_ram.wc_pend, u_ram.wc_pend2, u_ram.wc_pend3};
        h_ad[hwptr]  <= u_ram.latch_address[19:0];
        hwptr <= (hwptr + 1) & (RB - 1);
        // any uncovered fall: log the DMA/grant context around it -- the
        // +GRANT run's 1-per-grant residue lives here
        if (u_ram.write_strobe_fell & ~(u_ram.wr_covered & u_ram.cov_same)) begin
            if (untr < 6) begin
                $display("UNCOV t=%0t ad=%05x d=%02x wn=%0d st=%0d pend=%03b cap=%0d | aen=%0d dw=%0d act=%0d dwr=%0d bl=%0d hr=%0d hlda=%0d daddr=%05x smw=%0d mwn=%0d | sst=%0d exp=%0d gp=%0d cwr=%0d",
                         $time, u_ram.latch_address, u_ram.internal_data_bus,
                         u_ram.word_now, u_ram.state,
                         {u_ram.wc_pend, u_ram.wc_pend2, u_ram.wc_pend3},
                         u_ram.cap_valid, aen, dma_wait, dma_active, dma_wr,
                         burst_left, hreq, hlda_w, dma_addr, seq_mem_wr,
                         u_ram.memory_write_n, u_seq.st, u_seq.expand,
                         u_seq.gp, seq_wr);
                $display("   i8288: mc=%03b swms=%0d psr=%0d bs=%0d dq=%0d ps=%0d mcp=%0d | hlda_d=%0d dma_wait=%0d",
                         u_8288.machine_cycle,
                         u_8288.strobed_write_memory_status,
                         processor_status, u_bridge.bstate, u_bridge.cur_dq,
                         u_bridge.ps_r, u_8288.machine_cycle_period,
                         hlda_w, dma_wait);
                for (int k = 16; k >= 1; k--)
                    $display("  t-%02d st=%0d wcmd=%0d swr=%0d wcov=%0d cs=%0d nws=%0d%0d%0d idpk=%0d ncap=%0d wal=%0d dup=%0d ad=%05x wn=%0d aen=%0d sst=%0d exp=%0d iwn=%0d mc=%0d psr=%0d",
                             k, h_st[(hwptr - k) & (RB - 1)],
                             h_wcmd[k-1], h_swr[k-1], h_wcov[k-1], h_cs[k-1],
                             h_nws1[k-1], h_nws2[k-1], h_nws3[k-1],
                             h_idpk[k-1], h_ncap[k-1], h_wal[k-1],
                             h_dupcov[k-1], h_ad[(hwptr - k) & (RB - 1)],
                             h_wn[k-1], h_aen[k-1],
                             h_sst[(hwptr - k) & (RB - 1)], h_exp[k-1],
                             h_iwn[k-1], h_mc[(hwptr - k) & (RB - 1)],
                             h_psr[(hwptr - k) & (RB - 1)]);
            end
            untr <= untr + 1;
        end
        // strict loss: write strobe fell and was NEVER covered
        if (u_ram.write_strobe_fell & ~u_ram.wr_covered & losstr < 4) begin
            losstr <= losstr + 1;
            $display("\n=== TRUE-LOSS #%0d t=%0t addr=%05x data=%02x word=%b ph=%0d ===",
                     losstr, $time, u_ram.latch_address,
                     u_ram.internal_data_bus, u_ram.word_now, cur_phase);
            // cycles T-24 .. T-1: 1-bit history lives in h_X[k-1], the
            // ring arrays in index (hwptr-k)&mask. Live signals are T itself.
            for (int k = 24; k >= 1; k--) begin
                automatic int r = (hwptr - k) & (RB - 1);
                $display("  t-%02d st=%0d pend=%03b cap=%0d wcmd=%0d wcd=%0d swr=%0d mwn=%0d rsn=%0d wcov=%0d cs=%0d wso=%0d nws=%0d%0d%0d idpk=%0d ncap=%0d wal=%0d dup=%0d mrdy=%0d icr=%0d prdy=%0d rnw=%0d ce=%0d ad=%05x wn=%0d",
                         k, h_st[r], h_pend[r], h_cap[k-1],
                         h_wcmd[k-1], h_wcd[k-1], h_swr[k-1], h_mwn[k-1],
                         h_rsn[k-1], h_wcov[k-1], h_cs[k-1], h_wso[k-1],
                         h_nws1[k-1], h_nws2[k-1], h_nws3[k-1],
                         h_idpk[k-1], h_ncap[k-1], h_wal[k-1], h_dupcov[k-1],
                         h_mrdy[k-1], h_icr[k-1], h_prdy[k-1], h_rnw[k-1],
                         h_ce[k-1], h_ad[r], h_wn[k-1]);
            end
            $display("  >>T  st=%0d pend=%03b cap=%0d wcmd=%0d wcd=%0d swr=%0d mwn=%0d rsn=%0d wcov=%0d cs=%0d wso=%0d nws=%0d%0d%0d idpk=%0d ncap=%0d wal=%0d dup=%0d mrdy=%0d icr=%0d prdy=%0d rnw=%0d ce=%0d ad=%05x wn=%0d",
                     u_ram.state, {u_ram.wc_pend, u_ram.wc_pend2, u_ram.wc_pend3},
                     u_ram.cap_valid, u_ram.write_command, u_ram.write_command_d,
                     seq_mem_wr, u_ram.memory_write_n, u_ram.ram_address_select_n,
                     u_ram.wr_covered, u_ram.cov_same, u_ram.wr_strobe_open,
                     u_ram.new_write_strobe, u_ram.new_write_strobe2,
                     u_ram.new_write_strobe3, u_ram.idle_park, u_ram.new_cap,
                     u_ram.wr_accept_live, u_ram.dup_covered,
                     ram_ready_w, guest_ready, proc_ready,
                     u_ready.ready_n_or_wait, ce_pos,
                     u_ram.latch_address[19:0], u_ram.word_now);
        end
    end

    initial begin
        repeat (20) @(posedge clk);
        reset = 0;
        // ce_generator samples clk_select_load outside reset only
        repeat (4) @(posedge clk);
        @(negedge clk) sel_load = 1;
        @(negedge clk) sel_load = 0;
        wait (sdram_up);
        $display("sdram up, CPU released");
        $fflush;
    end

    initial begin
        #400_000_000;                       // 400 ms of sim time ceiling
        $display("GLOBAL TIMEOUT  diverged=%0d stray=%0d grants=%0d midcmd=%0d ph=%0d pc=%05x",
                 diverged, stray, grants, grants_midcmd, cur_phase, zet_pc);
        $fflush;
        $finish;
    end

endmodule

`default_nettype wire
