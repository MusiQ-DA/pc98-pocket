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

    // Prefetch A/B knobs (mirrors of the JTAG slot-0x09 bits) and the
    // F-bank remap flag -- driven by plusargs / phases below.
    reg         pf_dis_r    = 1'b0;
    reg         pf_nofill_r = 1'b0;
    reg         pf_nofillm_r = 1'b0;
    reg         pf_nohit_r  = 1'b0;
    reg         fwdis_r     = 1'b0;
    reg         shadow_flag_r = 1'b0;
    reg         irq_req     = 1'b0;
    reg         flipped10   = 1'b0;
    initial begin
        pf_dis_r    = $test$plusargs("pfdis");
        pf_nofill_r = $test$plusargs("pfnofill");
        pf_nofillm_r = $test$plusargs("pfnofillm");
        pf_nohit_r  = $test$plusargs("pfnohit");
        fwdis_r     = $test$plusargs("fwdis");
    end

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
        .sdram_rd_ready    (seq_rd_own_w),
        .pause_core        (1'b0),
        .biu_done          (biu_done),
        .pf_disable        (pf_dis_r),
        .pf_nofill         (pf_nofill_r),
        .pf_nofillm        (pf_nofillm_r),
        .pf_nohit          (pf_nohit_r),
        .bios_shadow_flag  (shadow_flag_r),
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
        .wb_tgc_i  (irq_req),
        .wb_tgc_o  (zwb_inta),
        .nmi       (1'b0),
        .nmia      (zwb_nmia),
        .fwdis     (fwdis_r),
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
    logic        beatlog       = 1'b0;

    initial begin
        void'($value$plusargs("dmaperiod=%d", dma_period));
        grant_en = $test$plusargs("GRANT");
        beatlog  = $test$plusargs("beatlog");
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
    wire        seq_rd_own_w;       // -> u_bridge.sdram_rd_ready
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
        .svc_req(svc_req_r), .svc_we(svc_we_r), .svc_raw(svc_raw_r),
        .svc_addr(svc_addr_r), .svc_wdata(svc_wdata_r),
        .svc_done(svc_done_w), .svc_rdata(svc_rdata_w), .dbg(),
        .mem_addr(seq_mem_addr), .mem_wdata(seq_mem_wdata),
        .mem_word(seq_mem_word), .mem_pf_len(seq_mem_pf_len),
        .mem_rd(seq_mem_rd), .mem_wr(seq_mem_wr),
        .mem_rdata(ram_dout), .mem_rdata_hi(ram_dout_hi),
        .mem_done(access_complete_w), .mem_own(access_own_w),
        .mem_ready(ram_ready_w),
        .mem_wr_taken(ram_wt_w),
        .cpu_wr_taken(seq_wr_taken_w),
        .cpu_rd_own(seq_rd_own_w)
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
        .bios_protect_flag(2'b00), .bios_shadow_flag(shadow_flag_r),
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

        // ---- phase 9: SMC trampoline loop -- the BIOS fd818 pattern --------
        // (bad_land is module-scope so the SDRAM poke can aim T at it)
        // Real-hardware POST dies executing a far-jump trampoline it had
        // JUST stored: mov word [T],imm x3; jmp far T -- the operand fetch
        // consumes stale/wrong bytes (prefetch-window suspect: pf_disable
        // boots clean 4/4 vs 4/4 wild with it on). Each iteration writes
        // "EE EA <ip> <cs=F000>" at 0x0600 through the posted-write queue
        // -- alternating cont_a/cont_b -- then jumps in. The flag byte at
        // 0x0700 records which target was written; a stale fetch lands on
        // the OTHER cont (flag mismatch) or on bad_land, both visible.
        // The cells are ALSO read back as data before the jump (the v15
        // -4-shift signature), and T+6.. is primed HLT so garbage bytes
        // hang instead of wandering. Sector 0x600 was write-killed+poisoned
        // every iteration, so any surviving stale hit is a true miss.
        begin
            int loop_head, cont_a, cont_b, tail, phase_done;
            int i_ca, i_cb, r_jzodd, r_jzok, r_jmpd, r_ja, r_jb;
            int r_badb, r_lp, r_jdone;
            marker(8'h09);
            // flag cell = 0 ; CX = 128 iterations
            emit(8'hC6); emit(8'h06); emitw(16'h0700); emit(8'h00);
            emit(8'hB9); emitw(16'h0080);                   // MOV CX,128
            loop_head = prog_len;
            // AX = (CL&1) ? cont_b : cont_a
            emit(8'hB8); i_ca = prog_len; emitw(16'h0000);  // MOV AX,cont_a
            emit(8'hF6); emit(8'hC1); emit(8'h01);          // TEST CL,1
            emit(8'h74); r_jzodd = prog_len; emit(8'h00);   // JZ +3 (keep A)
            emit(8'hB8); i_cb = prog_len; emitw(16'h0000);  // MOV AX,cont_b
            // write trampoline at 0600: EE EA <ax> <F000>
            emit(8'hC7); emit(8'h06); emitw(16'h0600);
            emit(8'hEE); emit(8'hEA);                       // MOV W[0600],EAEE
            emit(8'hA3); emitw(16'h0602);                   // MOV [0602],AX
            emit(8'hC7); emit(8'h06); emitw(16'h0604);
            emitw(16'hF000);                                // MOV W[0604],F000
            // data verify: BX=[0602]; CMP BX,AX; JE ok
            emit(8'h8B); emit(8'h1E); emitw(16'h0602);      // MOV BX,[0602]
            emit(8'h39); emit(8'hC3);                       // CMP BX,AX
            emit(8'h74); r_jzok = prog_len; emit(8'h00);    // JE +3 (skip JMP)
            emit(8'hE9); r_jmpd = prog_len; emitw(16'h0000);// JMP bad_land
            // ok: flag = CL&1 ; dx=043D ; al=0 ; jmp far 0000:0600
            emit(8'h88); emit(8'h0E); emitw(16'h0700);      // MOV [0700],CL
            emit(8'h80); emit(8'h26); emitw(16'h0700);
            emit(8'h01);                                    // AND B[0700],1
            emit(8'hBA); emitw(16'h043D);                   // MOV DX,043D
            emit(8'hB0); emit(8'h00);                       // MOV AL,0
            emit(8'hEA); emitw(16'h0600); emitw(16'h0000);  // JMPF 0000:0600
            cont_a = prog_len;
            emit(8'h80); emit(8'h3E); emitw(16'h0700);
            emit(8'h00);                                    // CMP B[0700],0
            emit(8'h75); r_ja = prog_len; emit(8'h00);      // JNZ bad
            emit(8'hEB); r_jb = prog_len; emit(8'h00);      // JMP tail
            cont_b = prog_len;
            emit(8'h80); emit(8'h3E); emitw(16'h0700);
            emit(8'h01);                                    // CMP B[0700],1
            emit(8'h75); r_badb = prog_len; emit(8'h00);    // JNZ bad
            tail = prog_len;
            emit(8'hE2); r_lp = prog_len; emit(8'h00);      // LOOP loop_head
            emit(8'hEB); r_jdone = prog_len; emit(8'h00);   // JMP phase_done
            bad_land = prog_len;
            emit(8'hB0); emit(8'hEE);                       // MOV AL,EE
            emit(8'hBA); emitw(16'h88FE); emit(8'hEE);      // OUT 88FE,AL
            emit(8'hEB); emit(8'hFE);                       // JMP $
            phase_done = prog_len;
            marker(8'h89);
            // fixups (rel8 targets are relative to the byte AFTER the imm)
            prog[i_ca  ] = cont_a[7:0];  prog[i_ca+1] = cont_a[15:8];
            prog[i_cb  ] = cont_b[7:0];  prog[i_cb+1] = cont_b[15:8];
            prog[r_jzodd] = 8'h03;                            // skip MOV AX,B
            prog[r_jzok ] = 8'h03;                            // skip JMP bad
            prog[r_jmpd  ] = 8'(bad_land - (r_jmpd + 2));
            prog[r_jmpd+1] = 8'((bad_land - (r_jmpd + 2)) >> 8);
            prog[r_ja   ] = 8'(bad_land - (r_ja + 1));
            prog[r_jb   ] = 8'(tail - (r_jb + 1));
            prog[r_badb ] = 8'(bad_land - (r_badb + 1));
            prog[r_lp   ] = 8'(loop_head - (r_lp + 1));
            prog[r_jdone] = 8'(phase_done - (r_jdone + 1));
            // T-sector prime: a trampoline aimed at bad_land for iter-0
            // staleness, then HLT filler so garbage bytes hang.
            sdr.u_part.poke(24'h000600, 16'h00EE);
            sdr.u_part.poke(24'h000601, 16'h00EA);
            sdr.u_part.poke(24'h000602, {8'h00, bad_land[7:0]});
            sdr.u_part.poke(24'h000603, {8'h00, bad_land[15:8]});
            sdr.u_part.poke(24'h000604, 16'h0000);
            sdr.u_part.poke(24'h000605, 16'h00F0);
            for (int i = 20'h00606; i < 20'h00620; i++)
                sdr.u_part.poke(24'(i), 16'h00F4);
        end

        // ---- phase 0A: F-bank remap kill ------------------------------
        // Guest F8000 is banked between phys 0F8000 ("bank A") and
        // 1F8000 ("bank B") by bios_shadow_flag. The bridge's windows
        // tag the guest address only, so a remap while a window is live
        // must drop it (bank_chg). The guest cannot flip the flag
        // without an OUT -- which would kill windows on the way through
        // anyway -- so the bench flips it loader-style when it sees the
        // 0x0702 signal write. Each pass through `resume` retries the
        // banked jump up to 3 times: bank A incs [0704]; bank B writes
        // BB. [0706] keeps the final mark for verify:
        //   flipped + kill works -> BB;  flipped + stale serve -> 3;
        //   never flipped          -> 3  (the control outcome)
        begin
            int resume10, r_ge10, wl10, giveup10, bdone10, done10, r_d10;
            marker(8'h0A);
            emit(8'hC6); emit(8'h06); emitw(16'h0704); emit(8'h00); // b[0704]=0
            emit(8'hEA); emitw(16'h0000); emitw(16'hF800);   // jmpf F800:0000
            resume10 = prog_len;
            emit(8'hFE); emit(8'h06); emitw(16'h0705);       // inc b[0705]
            emit(8'hC6); emit(8'h06); emitw(16'h0702); emit(8'h55);
                                                           // b[0702]=55 sig
            emit(8'h80); emit(8'h3E); emitw(16'h0705); emit(8'h03);
                                                           // cmp b[0705],3
            emit(8'h73); r_ge10 = prog_len; emit(8'h00);     // jae giveup
            emit(8'hB9); emitw(16'h0800);                    // mov cx,2048
            wl10 = prog_len;
            emit(8'hE2); emit(8'hFE);                        // loop $  (wait)
            emit(8'hEA); emitw(16'h0000); emitw(16'hF800);   // jmpf F800:0
            giveup10 = prog_len;
            emit(8'hA0); emitw(16'h0704);                    // mov al,[0704]
            emit(8'hA2); emitw(16'h0706);                    // mov [0706],al
            emit(8'hEB); r_d10 = prog_len; emit(8'h00);      // jmp done10
            bdone10 = prog_len;
            emit(8'hA0); emitw(16'h0704);                    // mov al,[0704]
            emit(8'hA2); emitw(16'h0706);                    // mov [0706],al
            done10 = prog_len;
            marker(8'h8A);
            prog[r_ge10] = 8'(giveup10 - (r_ge10 + 1));
            prog[r_d10]  = 8'(done10   - (r_d10 + 1));
            // bank A @ phys 0F8000: inc [0704]; mov cx,40; loop$; jmpf
            sdr.u_part.poke(24'h0F8000, 16'h00FE);
            sdr.u_part.poke(24'h0F8001, 16'h0006);
            sdr.u_part.poke(24'h0F8002, 16'h0004);
            sdr.u_part.poke(24'h0F8003, 16'h0007);
            sdr.u_part.poke(24'h0F8004, 16'h00B9);
            sdr.u_part.poke(24'h0F8005, 16'h0040);
            sdr.u_part.poke(24'h0F8006, 16'h0000);
            sdr.u_part.poke(24'h0F8007, 16'h00E2);
            sdr.u_part.poke(24'h0F8008, 16'h00FE);
            sdr.u_part.poke(24'h0F8009, 16'h00EA);
            sdr.u_part.poke(24'h0F800A, {8'h00, resume10[7:0]});
            sdr.u_part.poke(24'h0F800B, {8'h00, resume10[15:8]});
            sdr.u_part.poke(24'h0F800C, 16'h0000);
            sdr.u_part.poke(24'h0F800D, 16'h00F0);
            // bank B @ phys 1F8000: mov b[0704],BB ; jmpf bdone10
            sdr.u_part.poke(24'h1F8000, 16'h00C6);
            sdr.u_part.poke(24'h1F8001, 16'h0006);
            sdr.u_part.poke(24'h1F8002, 16'h0004);
            sdr.u_part.poke(24'h1F8003, 16'h0007);
            sdr.u_part.poke(24'h1F8004, 16'h00BB);
            sdr.u_part.poke(24'h1F8005, 16'h00EA);
            sdr.u_part.poke(24'h1F8006, {8'h00, bdone10[7:0]});
            sdr.u_part.poke(24'h1F8007, {8'h00, bdone10[15:8]});
            sdr.u_part.poke(24'h1F8008, 16'h0000);
            sdr.u_part.poke(24'h1F8009, 16'h00F0);
            // HLT filler past both entries
            for (int i = 20'h0F800E; i < 20'h0F8020; i++)
                sdr.u_part.poke(24'(i), 16'h00F4);
            for (int i = 24'h1F800A; i < 24'h1F8020; i++)
                sdr.u_part.poke(24'(i), 16'h00F4);
        end

        // ---- phase 0B: IRQ storm --------------------------------------
        // wb_tgc_i is the Zet's INTR line -- tied 0 in every other
        // phase. The bench fires it every ~2500 clks through this one;
        // the INTA pair reads vector FFh off the open bus and dispatch
        // lands on IVT[FFh] @ 0x3FC -> the stub below, which incs
        // [070A] and irets. SP moves to 0x500 first so the pushed
        // frames (3 words) clear the IVT -- the ITF's IRQ0 test walks
        // this same INTA/push/iret path through the pair engine.
        begin
            int isr11, loop11h, r_lp11;
            marker(8'h0B);
            emit(8'hC7); emit(8'h06); emitw(16'h03FC);
            isr11 = prog_len; emitw(16'h0000);               // IVT[FF].ip
            emit(8'hC7); emit(8'h06); emitw(16'h03FE);
            emitw(16'hF000);                                 // IVT[FF].cs
            emit(8'hBC); emitw(16'h0500);                    // mov sp,0500
            emit(8'hFB);                                     // sti
            emit(8'hB9); emitw(16'h1000);                    // mov cx,4096
            loop11h = prog_len;
            emit(8'hFE); emit(8'h06); emitw(16'h0708);       // inc b[0708]
            emit(8'hE2); r_lp11 = prog_len; emit(8'h00);    // loop loop11h
            emit(8'hFA);                                     // cli
            marker(8'h8B);
            emit(8'hEB); emit(8'h05);                        // jmp over isr (5B)
            isr11_addr = prog_len;
            emit(8'hFE); emit(8'h06); emitw(16'h070A);       // isr: inc [070A]
            emit(8'hCF);                                     // iret
            prog[isr11  ] = isr11_addr[7:0];
            prog[isr11+1] = isr11_addr[15:8];
            prog[r_lp11 ] = 8'(loop11h - (r_lp11 + 1));
        end

        // ---- phase 0C: frame-iret storm -----------------------------------
        // pushf; push cs; push ip; iret -- the BIOS mov ss/sp; retf shape:
        // the pops read cells the pushes wrote moments earlier through the
        // posted-write queue. Alternating cont targets make a shifted-pop
        // serve land on the OTHER cont (flag mismatch -> bad) or in dead
        // space (-> diverge). SP is still 0x500 from phase 0B, so the
        // frames land in the same 0x4FA-0x4FE cells the IRQ storm used.
        begin
            int lp12, cont12a, cont12b, tail12, bad12;
            int i_ca12, i_cb12, r_jz12, r_ja12, r_jb12, r_bb12, r_lp12, r_jd12;
            marker(8'h0C);
            emit(8'hC6); emit(8'h06); emitw(16'h070C); emit(8'h00); // flag=0
            emit(8'hB9); emitw(16'h0100);                  // mov cx,256
            lp12 = prog_len;
            // AX = (CL&1) ? cont_b : cont_a
            emit(8'hB8); i_ca12 = prog_len; emitw(16'h0000); // mov ax,cont_a
            emit(8'hF6); emit(8'hC1); emit(8'h01);         // test cl,1
            emit(8'h74); r_jz12 = prog_len; emit(8'h00);   // jz +3 (keep A)
            emit(8'hB8); i_cb12 = prog_len; emitw(16'h0000); // mov ax,cont_b
            // flag = CL&1 ; frame: pushf, push cs, push ax(ip) ; iret
            emit(8'h88); emit(8'h0E); emitw(16'h070C);     // mov [070C],cl
            emit(8'h80); emit(8'h26); emitw(16'h070C);
            emit(8'h01);                                   // and b[070C],1
            emit(8'h9C);                                   // pushf
            emit(8'h0E);                                   // push cs
            emit(8'h50);                                   // push ax (ip)
            emit(8'hCF);                                   // iret
            cont12a = prog_len;
            emit(8'h80); emit(8'h3E); emitw(16'h070C);
            emit(8'h00);                                   // cmp b[070C],0
            emit(8'h75); r_ja12 = prog_len; emit(8'h00);   // jnz bad
            emit(8'hEB); r_jb12 = prog_len; emit(8'h00);   // jmp tail
            cont12b = prog_len;
            emit(8'h80); emit(8'h3E); emitw(16'h070C);
            emit(8'h01);                                   // cmp b[070C],1
            emit(8'h75); r_bb12 = prog_len; emit(8'h00);   // jnz bad
            tail12 = prog_len;
            emit(8'hE2); r_lp12 = prog_len; emit(8'h00);   // loop lp12
            emit(8'hEB); r_jd12 = prog_len; emit(8'h00);   // jmp done12
            bad12 = prog_len;
            emit(8'hB0); emit(8'hEE);                      // mov al,EE
            emit(8'hBA); emitw(16'h88FE); emit(8'hEE);     // out 88FE,al
            emit(8'hEB); emit(8'hFE);                      // jmp $
            // done12:
            prog[i_ca12 ] = cont12a[7:0]; prog[i_ca12+1] = cont12a[15:8];
            prog[i_cb12 ] = cont12b[7:0]; prog[i_cb12+1] = cont12b[15:8];
            prog[r_jz12 ] = 8'h03;
            prog[r_ja12 ] = 8'(bad12  - (r_ja12 + 1));
            prog[r_jb12 ] = 8'(tail12 - (r_jb12 + 1));
            prog[r_bb12 ] = 8'(bad12  - (r_bb12 + 1));
            prog[r_lp12 ] = 8'(lp12   - (r_lp12 + 1));
            prog[r_jd12 ] = 8'(prog_len - (r_jd12 + 1));   // -> marker(8'h8C)
            marker(8'h8C);
        end

        // done: spin
        marker(8'hFF);
        emit(8'hEB); emit(8'hFE);           // JMP $
    end

    // module-scope so the T-sector prime can aim at it
    int bad_land = 0;
    int isr11_addr = 0;

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
        // phase-0A/0B mark cells: unwritten cells read X in the model
        for (int i = 20'h00700; i < 20'h00710; i++)
            sdr.u_part.poke(24'(i), 16'h0000);
        // Phase-9 prime is emitted by the program initial (bad_land is
        // only known there); see the poke inside the emit block.
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
    longint unsigned c_pbad   = 0;     // appended beats != SDRAM@base+cnt
    longint unsigned c_pforeign = 0;   // untagged returns inside a fill's cmd
    longint unsigned c_porphan = 0;    // tagged returns outside the fill's READ_2
    longint unsigned c_uncov  = 0;     // uncovered write falls outside expand
    logic swr_cov_seen = 0;            // write strobe saw coverage while held
    logic            tag_sim = 1'b0;   // bench mirror of RAM's prefetch tag

    // Physical address a guest access lands on: RAM.sv banks guest
    // F8000-FFFFF onto +0x100000 while bios_shadow_flag is up.
    function automatic logic [23:0] phys_of(input logic [19:0] g);
        return (shadow_flag_r && (g >= 20'hF8000)) ? {4'h1, g}
                                                 : {4'h0, g};
    endfunction

    // ---- service channel stimulus (+svc=N, default on) ---------------------
    // The firmware GDC service channel, driven the way the softcore uses
    // it: a level request held until svc_done. Each op is a raw read one
    // plane into the graphics window -- a port-A read return sharing the
    // shim with whatever guest fill is mid-flight. An untagged beat of
    // that kind landing inside a fill's B_CMD is the stray byte the
    // window must never append.
    int          svc_period = 157;
    logic        svc_req_r   = 1'b0;
    logic        svc_we_r    = 1'b0;
    logic        svc_raw_r   = 1'b1;
    logic [19:0] svc_addr_r  = 20'hA8000;
    logic [7:0]  svc_wdata_r = 8'h00;
    wire         svc_done_w;
    wire [7:0]   svc_rdata_w;
    int          svc_timer   = 0;
    longint      svc_ops     = 0;

    initial void'($value$plusargs("svc=%d", svc_period));

    always_ff @(posedge clk) begin
        if (reset || (svc_period == 0)) begin
            svc_req_r <= 1'b0;
            svc_timer <= 0;
        end else if (sdram_up) begin
            if (!svc_req_r) begin
                svc_timer <= svc_timer + 1;
                if (svc_timer >= svc_period) begin
                    svc_timer  <= 0;
                    svc_req_r  <= 1'b1;
                    svc_addr_r <= 20'hA8000 + 20'(svc_ops[12:0] * 20'h25);
                    svc_ops    <= svc_ops + 1;
                end
            end else if (svc_done_w) begin
                svc_req_r <= 1'b0;
            end
        end
    end

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
            if (u_ram.write_strobe_fell & ~(u_ram.wr_covered & u_ram.cov_same))
                $display("  UNCOV t=%0t ad=%05x d=%02x st=%0d seqst=%0d svch=%b exp=%b memwr=%b rdq=%0d dq=%b bs=%0d",
                         $time, u_ram.latch_address[19:0],
                         u_ram.internal_data_bus, u_ram.state, u_seq.st,
                         u_seq.svc_hold, u_seq.expand, u_seq.mem_wr,
                         u_bridge.wrq_cnt, u_bridge.cur_dq, u_bridge.cur_bs);
            // dbg_uncov counts every uncovered fall, but two release shapes
            // are benign: an expand takeover clips a strobe the seq already
            // captured and released (svc_eval only arms while the guest bus
            // is quiet), and a covered write's release lets the pins move on
            // to the next access BEFORE the fall clk -- cov_same then
            // compares the new operands against the parked slot and misses.
            // Either way the byte landed while the strobe was held, which is
            // exactly what swr_cov_seen tracks: coverage observed on any clk
            // the strobe was up. Only a fall whose held window never saw
            // coverage is a true drop.
            if (u_ram.write_strobe_fell)
                swr_cov_seen <= 1'b0;
            else if (u_ram.write_command
                     && ((u_ram.wr_covered & u_ram.cov_same)
                         | u_ram.dup_covered))
                swr_cov_seen <= 1'b1;
            if (u_ram.write_strobe_fell & ~(u_ram.wr_covered & u_ram.cov_same)
                & ~u_seq.expand & ~swr_cov_seen & ~u_ram.dup_covered)
                c_uncov <= c_uncov + 1;
            if (u_ram.state == u_ram.COMPLETE_RAM_RW) c_done <= c_done + 1;
            if (u_bridge.hit_serve) c_phit  <= c_phit + 1;
            if (u_bridge.arm_fill || u_bridge.fillm_go)
                                    c_pfill <= c_pfill + 1;
            if (u_bridge.pf_beat_v && (u_bridge.cur_pf || u_bridge.cur_fillm)
                && u_bridge.fill_ok && u_bridge.bus_ours
                && (u_bridge.bstate == u_bridge.B_CMD)) begin
                c_pbeats <= c_pbeats + 1;
                // Corruption witness: the appended byte must equal the
                // SDRAM word at base+offset. Anything else is a foreign
                // port-A return -- a sequencer or svc leg -- landing in
                // the fill's slot; a later hit would serve it as guest
                // code or data. Skip the clk a write lands: it kills the
                // window anyway, so the byte can never be served. Cells
                // never written read back as the model's DEAD poison --
                // anything is a correct answer there.
                if (!(u_bridge.arm_wr || u_bridge.wrq_push)
                    && !(u_bridge.cur_pf_w ? u_bridge.pf_cnt1[5]
                                           : u_bridge.pf_cnt0[5])) begin
                    automatic logic [19:0] app_addr =
                        (u_bridge.cur_pf_w ? u_bridge.pf_base1
                                           : u_bridge.pf_base0)
                        + 20'(u_bridge.cur_pf_w ? u_bridge.pf_cnt1[4:0]
                                                : u_bridge.pf_cnt0[4:0]);
                    automatic logic [23:0] app_phys = phys_of(app_addr);
                    if (sdr.u_part.store.exists(app_phys)
                        && (pf_beat_dat_w !== sdr.u_part.store[app_phys][7:0])) begin
                        if (c_pbad < 8)
                            $display("  PFBAD t=%0t w=%0d app=%05x beat=%02x exp=%02x len=%0d shim_a=%06x ramst=%0d seqst=%0d svch=%b aen=%b",
                                     $time, u_bridge.cur_pf_w, app_addr,
                                     pf_beat_dat_w,
                                     sdr.u_part.store[app_phys][7:0],
                                     u_bridge.cur_pf_len,
                                     u_ram.u_sdram.addr_r,
                                     u_ram.state, u_seq.st,
                                     u_seq.svc_hold, aen);
                        c_pbad <= c_pbad + 1;
                    end
                end
            end
            // Foreign-beat collision counter, computed the way RAM's tag
            // computes it: the last port-A read request's prefetch
            // qualifier. A return beat landing inside a fill's command
            // phase without that qualifier is foreign -- on an untagged
            // build it lands in the window (c_pbad flags it); on a tagged
            // build it proves the collision actually exercised.
            if (u_ram.read_request && !u_ram.read_flag && !u_ram.write_flag) begin
                tag_sim <= (u_ram.prefetch_len != 5'd0);
                if (beatlog)
                    $display("RQ t=%0t a=%06x len=%0d", $time,
                             u_ram.latch_address, u_ram.prefetch_len);
            end
            if (beatlog && u_ram.u_sdram.a_rvalid)
                $display("BEAT t=%0t rq=%06x rb=%0d d=%02x fill=%b/%b cnt=%0d",
                         $time, u_ram.u_sdram.addr_r, u_ram.u_sdram.rbeat,
                         u_ram.u_sdram.a_beat[7:0],
                         u_bridge.cur_pf, u_bridge.cur_fillm,
                         u_bridge.cur_pf_w ? u_bridge.pf_cnt1
                                           : u_bridge.pf_cnt0);
            if (u_ram.u_sdram.a_rvalid
                && (u_bridge.cur_pf || u_bridge.cur_fillm)
                && u_bridge.fill_ok && u_bridge.bus_ours
                && (u_bridge.bstate == u_bridge.B_CMD)
                && !tag_sim)
                c_pforeign <= c_pforeign + 1;
            // Orphan counter: a tagged return that lands inside a fill's
            // command phase while the RAM FSM is NOT streaming it (the
            // fill that owned the burst ended early -- grant dropped the
            // strobe, or a foreign ready ended the command phase). The
            // tag-only build let these through and shifted the window;
            // the READ_2 gate blocks them, so a nonzero count is the
            // collision being exercised, not a failure.
            if (u_ram.u_sdram.a_rvalid
                && (u_bridge.cur_pf || u_bridge.cur_fillm)
                && u_bridge.fill_ok && u_bridge.bus_ours
                && (u_bridge.bstate == u_bridge.B_CMD)
                && tag_sim
                && (u_ram.state != u_ram.RAM_READ_2))
                c_porphan <= c_porphan + 1;
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

    // read-answer witness: did the RAM complete THIS strobe's access at
    // any point during the pair's command phase? A read pair accepting
    // without it grabbed a foreign ready pulse (a svc leg, a DMA drain,
    // an AEN-release residue) and captured whatever data_bus happened to
    // hold -- the RET-reads-ADAD signature. Expanded walks (EGC/GRCG/svc)
    // answer through the sequencer's S_DONE instead, so exclude them.
    logic rd_seen_own;
    longint unsigned c_rd_foreign = 0;
    longint unsigned c_wit_foreign = 0;
    always_ff @(posedge clk) begin
        if (u_bridge.bstate == u_bridge.B_IDLE)
            rd_seen_own <= 1'b0;
        else if (u_ram.access_own || (u_seq.st == u_seq.S_DONE))
            rd_seen_own <= 1'b1;
        // The bridge's actual witness input rising without the own-access
        // model: whatever pulses here is what rd_own_seen latches. A legit
        // completion fires access_own/S_DONE on the same clk -- exclude it;
        // anything left is a genuinely foreign ready reaching the flag.
        if (u_bridge.bstate != u_bridge.B_IDLE
            && seq_rd_own_w && u_bridge.bus_ours
            && u_bridge.cur_read && !rd_seen_own
            && !u_ram.access_own && !(u_seq.st == u_seq.S_DONE)
            && !u_ram.ram_address_select_n) begin
            if (c_wit_foreign < 24)
                $display("  WITFOR t=%0t ad=%05x bst=%0d t_cnt=%0d aen=%b st=%0d seqst=%0d svch=%b svg=%b exp=%b mrn=%b mwn=%b sel=%b wopen=%b alr=%b rsm=%b",
                         $time, u_bridge.cur_addr, u_bridge.bstate,
                         u_bridge.t_cnt, aen, u_ram.state, u_seq.st,
                         u_seq.svc_hold, u_seq.svc_gap, u_seq.expand,
                         mem_rd_n, mem_wr_n, u_ram.ram_address_select_n,
                         u_ram.wr_strobe_open, u_ram.accept_live_rd,
                         u_ram.read_strobe_match);
            c_wit_foreign <= c_wit_foreign + 1;
        end
        if (u_bridge.bstate == u_bridge.B_CMD && u_bridge.pair_accept
            && u_bridge.cur_read && !u_bridge.cur_fillm && !u_bridge.cur_pf
            && !u_bridge.cur_inta
            && !rd_seen_own && u_bridge.bus_ours
            && !u_ram.ram_address_select_n) begin
            if (c_rd_foreign < 8)
                $display("  RDFOREIGN t=%0t ad=%05x t_cnt=%0d saw_low=%b aen=%b st=%0d seqst=%0d svch=%b bus=%02x icr=%b mrdy=%b",
                         $time, u_bridge.cur_addr, u_bridge.t_cnt,
                         u_bridge.saw_low, aen, u_ram.state, u_seq.st,
                         u_seq.svc_hold, u_bridge.data_bus,
                         guest_ready, ram_ready_w);
            c_rd_foreign <= c_rd_foreign + 1;
        end
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
        phase_name[8'h09] = "SMC trampoline x128";
        phase_name[8'h0A] = "F-bank remap kill";
        phase_name[8'h0B] = "IRQ storm x4096";
        phase_name[8'h0C] = "frame-iret x256";
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
        phase_bytes[8'h09] = 128;
        phase_bytes[8'h0A] = 48;
        phase_bytes[8'h0B] = 4096;
        phase_bytes[8'h0C] = 256;
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

    // ---- phase-0A remap poke ------------------------------------------------
    // The guest can't flip the F-bank flag without an OUT (which would
    // kill windows on the way through anyway), so the bench does it
    // loader-style: the signal write to 0x0702 flips shadow_flag_r while
    // the bank-A window is still live, before the guest's second jmpf.
    always @(posedge clk) begin
        if (reset) begin
            flipped10     <= 1'b0;
            shadow_flag_r <= 1'b0;
        end else if (cur_phase == 8'h0A && !flipped10
                     && zwb_stb && zwb_we && !zwb_tga
                     && ({zwb_adr, 1'b0} == 20'h00702)
                     && (zwb_dat_o[7:0] == 8'h55)) begin
            flipped10     <= 1'b1;
            shadow_flag_r <= 1'b1;
        end
    end

    // ---- phase-0B IRQ storm driver ------------------------------------------
    // INTR is a level input: hold it until the Zet's own INTA output
    // (zwb_inta = wb_tgc_o) pulses, then re-arm after a gap. Fires only
    // while phase 0B is current -- the guest's STI/CLI bracket it.
    reg [15:0] irq_gap = 16'd0;
    always @(posedge clk) begin
        if (reset || cur_phase != 8'h0B) begin
            irq_req <= 1'b0;
            irq_gap <= 16'd0;
        end else if (zwb_inta) begin
            irq_req <= 1'b0;
            irq_gap <= 16'd0;
        end else if (irq_gap == 16'd2500) begin
            irq_req <= 1'b1;
            irq_gap <= 16'd0;
        end else
            irq_gap <= irq_gap + 16'd1;
    end

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
            // phase-9 trampoline: did the written bytes actually land?
            for (int a = 20'h00600; a < 20'h00610; a++) begin
                w = sdr.u_part.peek(a);
                $display("  T[%05x]=%02x", a, w[7:0]);
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
            // phase-0A bank remap: flipped + kill works -> BB;
            // flipped + a stale window served bank A again -> 03 (the
            // same value the unflipped control produces).
            begin
                logic [7:0] exp10;
                exp10 = flipped10 ? 8'hBB : 8'h03;
                w = sdr.u_part.peek(20'h0706);
                $display("  bankmark 0706=%02x want %02x (flipped=%0d)",
                         w[7:0], exp10, flipped10);
                if (w[7:0] !== exp10) bad++;
            end
            // phase-0B irq storm: at least one INTA->ISR->iret round
            // trip must have landed
            begin
                w = sdr.u_part.peek(20'h070A);
                $display("  irqcount 070A=%02x", w[7:0]);
                if (w[7:0] == 8'h00) bad++;
            end
            $display("VERIFY: bad=%0d diverged=%0d stray=%0d grants=%0d midcmd=%0d dma_bytes=%0d pfbad=%0d pforeign=%0d porphan=%0d rdfor=%0d svc_ops=%0d",
                     bad, diverged, stray, grants, grants_midcmd, dma_seen,
                     c_pbad, c_pforeign, c_porphan, c_rd_foreign, svc_ops);
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
            // bad/diverged/stray are direct loss checks; c_uncov counts
            // uncovered write-strobe falls with expand down -- the only
            // falls that can be true losses (an expand takeover only clips
            // an already-captured, already-released strobe); and under
            // +GRANT the fill window must be whole.
            if (bad || diverged || stray || (c_uncov != 0)
                || (c_pbad != 0)
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

    // fetch-PC ring: the last 32 presented fetch addresses, dumped on the
    // first diverge so the escape entry is visible (the jump target or the
    // pop that delivered it)
    logic [19:0] pc_ring [0:31];
    int          pc_ptr = 0;
    int          dvg_dumped = 0;
    always_ff @(posedge clk) begin
        pc_ring[pc_ptr] <= zet_pc;
        pc_ptr <= (pc_ptr + 1) & 31;
    end

    // guest bus-op ring: the last 16 sequencer-level memory accesses
    // (addr, write?, data) -- the stack push that should hold the return
    // address and the pop that read it are both here when RET escapes
    logic [19:0] op_addr  [0:15];
    logic        op_wr    [0:15];
    logic [7:0]  op_data  [0:15];
    int          op_ptr = 0;
    always_ff @(posedge clk) begin
        if (seq_mem_rd || seq_mem_wr) begin
            op_addr[op_ptr] <= seq_mem_addr;
            op_wr[op_ptr]   <= seq_mem_wr;
            op_data[op_ptr] <= seq_mem_wdata;
            op_ptr <= (op_ptr + 1) & 15;
        end
    end

    // ---- divergence + stray-write traps (the wild-jump witnesses) ----------
    // The program runs at F0000..+len and fetches the FFFF0 reset vector at
    // boot; it writes 0x2000/0x4000/0x8000 (data), the ~0x0400 stack and the
    // A8000 window, and the DMAC writes 0x30000-0x30FFF. A far-transfer that
    // sends CS:IP out of the code image is the SuperDepth symptom; a write to
    // the code/reset-vector region is a stray that could cause it.
    // zet_pc is combinational (cs<<4)+ip -- during a far transfer it
    // flashes the ip-before-cs transient (0x00xx) for a clk or two even
    // though no fetch is ever issued there. Sample the real fetch address
    // on the Wishbone instead: an instruction cycle (tga) presenting stb.
    wire [19:0] fetch_a = {zwb_adr, 1'b0} | {19'b0, zwb_sel == 2'b10};
    always_ff @(posedge clk) begin
        if (sdram_up && !reset) begin
            // every issued instruction-fetch byte must be in legal space
            if (zwb_stb && zwb_cyc && !zwb_we && zwb_tga
                && !((fetch_a >= 20'hF0000 && fetch_a < 20'hF2000) ||
                     (fetch_a >= 20'hF8000 && fetch_a < 20'hF8020) ||
                     (fetch_a >= 20'h00600 && fetch_a < 20'h00620) ||
                     (fetch_a >= 20'hFFF00))) begin
                if (diverged < 16)
                    $display("*** DIVERGE pc=%05x aen=%b dma_act=%b bst=%0d ad=%05x t=%0t",
                             zet_pc, aen, dma_active, u_bridge.bstate,
                             cpu_address, $time);
                if (diverged == 0 && !dvg_dumped) begin
                    dvg_dumped <= 1;
                    for (int k = 31; k >= 1; k--)
                        $display("   pc-%02d %05x", k,
                                 pc_ring[(pc_ptr - k) & 31]);
                    $display("   w0 base=%05x cnt=%0d live=%b ok=%b",
                             u_bridge.pf_base0, u_bridge.pf_cnt0,
                             u_bridge.pf_live, u_bridge.fill_ok);
                    $display("   w1 base=%05x cnt=%0d",
                             u_bridge.pf_base1, u_bridge.pf_cnt1);
                    for (int k = 0; k < 32; k++)
                        $display("   buf0[%02x]=%02x/%02x buf1[%02x]=%02x/%02x",
                                 k, u_bridge.pf_buf[k],
                                 sdr.u_part.store.exists(phys_of(u_bridge.pf_base0+k))
                                    ? sdr.u_part.store[phys_of(u_bridge.pf_base0+k)][7:0] : 8'hxx,
                                 k, u_bridge.pf_buf[32+k],
                                 sdr.u_part.store.exists(phys_of(u_bridge.pf_base1+k))
                                    ? sdr.u_part.store[phys_of(u_bridge.pf_base1+k)][7:0] : 8'hxx);
                    // stack neighbourhood + last guest ops: the pop that
                    // delivered the escape read from here
                    $display("   stack@0x3f0:");
                    for (int k = 0; k < 32; k++)
                        $display("   stk[%03x]=%02x", 20'h003F0 + k,
                                 sdr.u_part.store.exists(20'h003F0 + k)
                                    ? sdr.u_part.store[20'h003F0 + k][7:0] : 8'hxx);
                    for (int k = 15; k >= 1; k--)
                        $display("   op-%02d %s %05x %02x", k,
                                 op_wr[(op_ptr - k) & 15] ? "WR" : "RD",
                                 op_addr[(op_ptr - k) & 15],
                                 op_data[(op_ptr - k) & 15]);
                end
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

    // ---- phase-9 trampoline watch: every bus access + queue event in T ----
    // The trampoline at 0x600 is the SMC target; log guest strobes, queue
    // pushes/drains, fills and hits touching 0x600-0x61F so a stale serve
    // or a lost byte shows its provenance.
    logic t_trace = 1'b0;
    initial t_trace = $test$plusargs("ttrace");
    always_ff @(posedge clk) if (t_trace && sdram_up) begin
        if (u_bridge.wrq_push
            && u_bridge.srv_addr >= 20'h00600
            && u_bridge.srv_addr < 20'h00620)
            $display("T WQP t=%0t a=%05x d=%04x ube=%b cnt=%0d",
                     $time, u_bridge.srv_addr, u_bridge.srv_data,
                     u_bridge.srv_ube, u_bridge.wrq_cnt);
        if (u_bridge.arm_drain
            && u_bridge.wrq_addr[0] >= 20'h00600
            && u_bridge.wrq_addr[0] < 20'h00620)
            $display("T WQD t=%0t a=%05x d=%04x ube=%b",
                     $time, u_bridge.wrq_addr[0], u_bridge.wrq_data[0],
                     u_bridge.wrq_ube[0]);
        if (u_bridge.hit_serve
            && u_bridge.srv_addr >= 20'h00600
            && u_bridge.srv_addr < 20'h00620)
            $display("T HIT t=%0t a=%05x w=%04x pfhw=%0d b0=%05x/%0d b1=%05x/%0d",
                     $time, u_bridge.srv_addr, u_bridge.pf_hit_word,
                     u_bridge.pf_hw, u_bridge.pf_base0, u_bridge.pf_cnt0,
                     u_bridge.pf_base1, u_bridge.pf_cnt1);
        if (u_bridge.fwd_serve
            && u_bridge.srv_addr >= 20'h00600
            && u_bridge.srv_addr < 20'h00620)
            $display("T FWD t=%0t a=%05x w=%04x",
                     $time, u_bridge.srv_addr, u_bridge.fwd_word);
        if (u_bridge.arm_rd_ok
            && u_bridge.srv_addr >= 20'h00600
            && u_bridge.srv_addr < 20'h00620)
            $display("T MISS t=%0t a=%05x len=%0d fillm=%b pois=%b fmovl=%b w0=%05x/%0d..%0d w1=%05x/%0d..%0d",
                     $time, u_bridge.srv_addr, u_bridge.fillm_len,
                     u_bridge.fillm_go, u_bridge.pf_poisoned,
                     u_bridge.fillm_ovl,
                     u_bridge.pf_base0, u_bridge.pf_lo0, u_bridge.pf_cnt0,
                     u_bridge.pf_base1, u_bridge.pf_lo1, u_bridge.pf_cnt1);
        if (u_bridge.arm_fill
            && u_bridge.pf_next >= 20'h00600
            && u_bridge.pf_next < 20'h00620)
            $display("T FILL t=%0t a=%05x len=%0d w=%0d",
                     $time, u_bridge.pf_next, u_bridge.pf_fill_len,
                     u_bridge.fill_w);
        // RAM-side: what the T-region bursts actually issued/returned
        if (u_ram.u_sdram.a_rvalid
            && u_ram.u_sdram.addr_r + u_ram.u_sdram.rbeat >= 20'h00600
            && u_ram.u_sdram.addr_r + u_ram.u_sdram.rbeat < 20'h00620)
            $display("T BEAT t=%0t a=%05x d=%02x tag=%b st=%0d",
                     $time, u_ram.u_sdram.addr_r + u_ram.u_sdram.rbeat,
                     u_ram.u_sdram.a_beat[7:0], u_ram.pf_tag,
                     u_ram.state);
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
        // Window-bookkeeping forensic: every write-visible event while a
        // fill pair is in flight -- who can move pf_cnt/pf_base/fill_ok.
        if (u_bridge.cur_pf || u_bridge.cur_fillm)
            $display("PFW t=%0t c0=%0d c1=%0d lo0=%0d lo1=%0d b0=%05x b1=%05x lv=%b ok=%0d fb=%0d w=%0d iow=%0d awr=%0d wqp=%0d bchg=%0d ours=%0d arok=%0d afl=%0d flm=%0d wov=%b/%b bst=%0d",
                     $time, u_bridge.pf_cnt0, u_bridge.pf_cnt1,
                     u_bridge.pf_lo0, u_bridge.pf_lo1,
                     u_bridge.pf_base0, u_bridge.pf_base1,
                     u_bridge.pf_live, u_bridge.fill_ok, u_bridge.fill_beats,
                     u_bridge.cur_pf_w, u_bridge.arm_iow, u_bridge.arm_wr,
                     u_bridge.wrq_push, u_bridge.bank_chg, u_bridge.bus_ours,
                     u_bridge.arm_rd_ok, u_bridge.arm_fill, u_bridge.fillm_go,
                     u_bridge.wr_ovl0, u_bridge.wr_ovl1, u_bridge.bstate);
    end

    // Catch the exact edge where a full window-kill fires: pf_live is still
    // nonzero (pre-edge) and one of the full-kill inputs is asserted.
    always @(posedge clk) if (trace) begin
        if (|u_bridge.pf_live &&
            (u_bridge.arm_iow || u_bridge.bank_chg || !u_bridge.bus_ours ||
             u_bridge.wrq_push || u_bridge.arm_wr || u_bridge.arm_fill || u_bridge.fillm_go))
            $display("PFKILL t=%0t live=%b c0=%0d c1=%0d iow=%0d bchg=%0d ours=%0d wqp=%0d awr=%0d afl=%0d flm=%0d arok=%0d shf=%0d sq=%0d wov=%b/%b bst=%0d",
                     $time, u_bridge.pf_live, u_bridge.pf_cnt0, u_bridge.pf_cnt1,
                     u_bridge.arm_iow, u_bridge.bank_chg, u_bridge.bus_ours,
                     u_bridge.wrq_push, u_bridge.arm_wr, u_bridge.arm_fill,
                     u_bridge.fillm_go, u_bridge.arm_rd_ok,
                     u_bridge.bios_shadow_flag, u_bridge.shadow_q,
                     u_bridge.wr_ovl0, u_bridge.wr_ovl1, u_bridge.bstate);
    end

    // first events of the prefetch engine's life, for bring-up
    int pfdbg = 0;
    int pfdbg_max = 300;
    initial if ($value$plusargs("pfdbg=%d", pfdbg_max)) ;
    always_ff @(posedge clk) if (trace && pfdbg < pfdbg_max) begin
        if (u_bridge.hit_serve) begin
            // flat store is byte-indexed: one guest byte per word's low half
            automatic logic [15:0] w0  = sdr.u_part.peek(phys_of(u_bridge.srv_addr));
            automatic logic [15:0] w1  = sdr.u_part.peek(phys_of(u_bridge.srv_addr + 20'd1));
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
        $display("GLOBAL TIMEOUT  diverged=%0d stray=%0d grants=%0d midcmd=%0d ph=%0d pc=%05x uncov=%0d pfbad=%0d rdfor=%0d witfor=%0d irq=%02x",
                 diverged, stray, grants, grants_midcmd, cur_phase, zet_pc,
                 c_uncov, c_pbad, c_rd_foreign, c_wit_foreign,
                 sdr.u_part.peek(20'h070A));
        for (int k = 31; k >= 1; k--)
            $display("   pc-%02d %05x", k, pc_ring[(pc_ptr - k) & 31]);
        for (int k = 15; k >= 1; k--)
            $display("   op-%02d %s %05x %02x", k,
                     op_wr[(op_ptr - k) & 15] ? "WR" : "RD",
                     op_addr[(op_ptr - k) & 15],
                     op_data[(op_ptr - k) & 15]);
        $fflush;
        $finish;
    end

endmodule

`default_nettype wire
