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
        .address_enable_n  (1'b0),
        .pause_core        (1'b0),
        .biu_done          (biu_done),
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
        .address_enable_n                (1'b0),
        .command_enable                  (1'b1),
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

    // ---- the graphics sequencer, ahead of RAM ----------------------------
    wire        ram_sel_n;
    wire [19:0] seq_mem_addr;
    wire [7:0]  seq_mem_wdata, seq_cpu_rdata, seq_cpu_rdata_hi;
    wire        seq_mem_word, seq_mem_rd, seq_mem_wr, seq_mem_page1;
    wire        ram_ready_w, access_complete_w, access_own_w;
    wire [4:0]  seq_mem_pf_len;
    wire        pf_beat_v_w;
    wire [7:0]  pf_beat_dat_w;
    wire [4:0]  cpu_pf_len_w;

    pc98_gvram_seq #(.EGC(1'b1)) u_seq (
        .clk(clk), .reset(reset),
        .cpu_gvram(~ram_sel_n),
        .cpu_rd(~mem_rd_n), .cpu_wr(~mem_wr_n),
        .cpu_pf_len(cpu_pf_len_w),
        .cpu_word(cpu_word_access),
        .cpu_addr(cpu_address), .cpu_wdata(cpu_data_bus),
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
        .mem_ready(ram_ready_w)
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
        .no_command_state(mem_rd_n & mem_wr_n & io_rd_n & io_wr_n),
        .memory_access_ready(ram_ready_w),
        .access_complete(access_complete_w),
        .access_own(access_own_w),
        .ram_address_select_n(ram_sel_n),
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
        .dma_wait_n          (1'b1),
        .io_channel_ready    (guest_ready),
        .io_read_n           (io_rd_n),
        .io_write_n          (io_wr_n),
        .memory_read_n       (mem_rd_n),
        .dma0_acknowledge_n  (1'b1),
        .address_enable_n    (1'b0)
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
            if (u_bridge.arm_fill)  c_pfill <= c_pfill + 1;
            if (u_bridge.pf_beat_v && u_bridge.cur_pf && u_bridge.fill_ok
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

    // marker decode on the IO-write strobe
    logic io_marker_d = 1'b1;
    wire  io_marker   = ~io_wr_n & (cpu_address == 16'h88FE);
    always_ff @(posedge clk) begin
        io_marker_d <= io_wr_n;
        if (io_marker & io_marker_d) begin     // first cycle of this strobe
            if (cpu_data_bus[7]) begin
                if (cur_phase >= 0) phase_end(cpu_data_bus[6:0]);
                cur_phase = -1;
            end else if (cpu_data_bus == 8'hFF) begin
                $display("=== all phases done ===");
                cur_phase = 256;
                $fflush;
                $finish;
            end else begin
                phase_start({25'd0, cpu_data_bus[6:0]});
                c_qmax    <= 0;           // per-phase maxima
                c_rel_max <= 0;
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
            $display("      pf0=%05x/%0d pf1=%05x/%0d live=%0b cur_pf=%0d/%0d m1=%0d req_ad=%05x",
                     u_bridge.pf_base0, u_bridge.pf_cnt0,
                     u_bridge.pf_base1, u_bridge.pf_cnt1,
                     u_bridge.pf_live, u_bridge.cur_pf,
                     u_bridge.cur_pf_w, u_bridge.pf_miss1,
                     u_bridge.srv_addr);
            $fflush;
        end
    end

    // first events of the prefetch engine's life, for bring-up
    int pfdbg = 0;
    always_ff @(posedge clk) if (pfdbg < 300) begin
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
        if (u_bridge.arm_fill) begin
            $display("PFFILL t=%0t next=%05x len=%0d",
                     $time, u_bridge.pf_next[19:0], u_bridge.pf_fill_len);
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
        $display("GLOBAL TIMEOUT");
        $fflush;
        $finish;
    end

endmodule

`default_nettype wire
