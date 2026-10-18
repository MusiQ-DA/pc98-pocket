//
// tb_zet_inta_grant -- does a DMA/HOLD grant landing mid-INTA desync the
// i8259's acknowledge state machine so the bridge captures the WRONG vector?
//
// The suspected metal race (the leading explanation for the intermittent
// wild-jump crash): the arbiter samples a passive processor_status on
// cpu_ce_posedge, but the ACK2 byte can arm between that sample and the aen
// edge. When aen lands, the i8288's command_enable drops, which FORCES
// interrupt_acknowledge_n high even though the ACK2 byte is mid-strobe. The
// i8259 counts inta_n EDGES (CTL_READY -nedge-> ACK1 -pedge-> ACK2 -pedge->
// CTL_READY in 8086 mode), so the grant's forced pedge ends ACK2 early; the
// re-run's nedge then starts a phantom ACK1, out_control_logic_data is no
// longer asserted, and the bridge's ACK2 accept samples a byte that is NOT
// the vector -- a random IVT index, memory untouched.
//
// Faithful path under test:
//   zet_cpu_bridge (wb_tgc_o -> INTA pair) -> i8288 (inta_n, gated by
//   command_enable=~aen) -> i8259 (master, edge-triggered IRQ0) -> the
//   vector back onto the shared data bus during ~inta_n.
//   The HOLD grant is driven through the arbiter's own hold chain, exactly
//   as tb_zet_dma_grant does.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_zet_inta_grant;

    // clk_chipset is 42.954545 MHz.
    logic clk = 1'b0;
    always #11.641 clk = ~clk;

    logic reset = 1'b1;

    // ---- CE train -----------------------------------------------------------
    wire  clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire  cycle_accrate, shift_read_timing;
    wire  [7:0] ccc_div, ccc_dec;
    wire  [1:0] ram_rd_wait, ram_wr_wait;

    logic [1:0] clk_select_r = 2'b00;
    initial void'($value$plusargs("speed=%d", clk_select_r));

    ce_generator u_ce (
        .clock                              (clk),
        .reset                              (reset),
        .clk_select_load                    (1'b1),
        .clk_select                         (clk_select_r),
        .cpu_clk_pin                        (clk_cpu),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .cycle_accrate                      (cycle_accrate),
        .clock_cycle_counter_division_ratio  (ccc_div),
        .clock_cycle_counter_decrement_value (ccc_dec),
        .shift_read_timing                  (shift_read_timing),
        .ram_read_wait_cycle                (ram_rd_wait),
        .ram_write_wait_cycle               (ram_wr_wait),
        .vram_wait_en                       ()
    );

    // ---- the HOLD grant, through the arbiter's own chain -------------------
    // hreq has three stimulus sources OR'd together so there is a single
    // driver: the random background DMAC, the timed sweep grant, and the
    // ACK2-targeted grant.
    logic       dmac_hreq  = 1'b0;
    logic       sweep_hreq = 1'b0;
    logic       grant_on_ack2 = 1'b0;
    wire        pic_in_ack2;
    wire        hreq = dmac_hreq | sweep_hreq | (grant_on_ack2 & pic_in_ack2);
    logic       hold_ff1 = 1'b0;
    logic       hold_ff2 = 1'b0;
    logic       aen = 1'b0;
    logic       dma_wait = 1'b0;
    wire [2:0]  processor_status;

    always_ff @(posedge clk) begin
        if (reset)
            hold_ff1 <= 1'b0;
        else if (cpu_ce_posedge)
            // Bus_Arbiter.sv's sample: PASV && lock_n && request.
            hold_ff1 <= (processor_status[0] & processor_status[1]) & lock_n
                        & hreq;
    end
    always_ff @(posedge clk) begin
        if (reset)
            hold_ff2 <= 1'b0;
        else if (cpu_ce_negedge)
            hold_ff2 <= ~hreq ? 1'b0 : (hold_ff2 | hold_ff1);
    end
    wire    hold_ack = hreq ? hold_ff2 : 1'b0;
    always_ff @(posedge clk) begin
        if (reset) begin
            aen      <= 1'b0;
            dma_wait <= 1'b0;
        end else if (cpu_ce_posedge) begin
            aen      <= hold_ack;
            dma_wait <= aen;
        end
    end
    wire dma_wait_n = ~dma_wait;
    wire bus_ours   = ~aen;

    // ---- Zet's Wishbone, driven by a synthetic master ----------------------
    logic [15:0] wb_dat_o_m;
    wire  [15:0] wb_dat_i;
    logic [19:1] wb_adr_m;
    logic        wb_we_m;
    logic        wb_tga_m;
    logic [1:0]  wb_sel_m;
    logic        wb_stb_m;
    logic        wb_cyc_m;
    logic        wb_tgc_m;      // INTA request (the "CPU took the interrupt")
    wire         wb_ack_i;
    wire         zet_clk;
    wire  [4:0]  pf_req_len;
    wire         pf_beat_v;
    wire  [7:0]  pf_beat_dat;

    wire [19:0]  ad_out;
    wire [7:0]   cpu_data_bus, cpu_data_bus_hi;
    wire         word_access, lock_n;
    wire  [7:0]  ram_dout, ram_dout_hi;
    wire         inta_n;
    wire  [7:0]  pic_dout;

    // During INTA the shared bus carries the PIC's byte; otherwise RAM's.
    wire [7:0]   data_bus = ~inta_n ? pic_dout : ram_dout;

    zet_cpu_bridge u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .fast_pace         (clk_select_r[1]),
        .reset             (reset),
        .zet_clk           (zet_clk),
        .wb_dat_o          (wb_dat_o_m),
        .wb_dat_i          (wb_dat_i),
        .wb_adr_o          (wb_adr_m),
        .wb_we_o           (wb_we_m),
        .wb_tga_o          (wb_tga_m),
        .wb_sel_o          (wb_sel_m),
        .wb_stb_o          (wb_stb_m),
        .wb_cyc_o          (wb_cyc_m),
        .wb_ack_i          (wb_ack_i),
        .wb_tgc_o          (wb_tgc_m),
        .nmia              (1'b0),
        .processor_status  (processor_status),
        .ad_out            (ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (lock_n),
        .analog_mode       (1'b0),
        .word_access       (word_access),
        .pf_req_len        (pf_req_len),
        .pf_beat_v         (pf_beat_v),
        .pf_beat_dat       (pf_beat_dat),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (ram_dout_hi),
        .data_bus          (data_bus),
        .processor_ready   (proc_ready),
        .address_enable_n  (aen),
        .sdram_wr_taken    (wr_taken_w),
        .sdram_rd_ready    (1'b1),
        .pause_core        (1'b0),
        .throttle          (1'b0),
        .pf_disable        (1'b1),
        .pf_nofill         (1'b0),
        .pf_nofillm        (1'b0),
        .pf_nohit          (1'b0),
        .bios_shadow_flag  (1'b0),
        .biu_done          (),
        .dbg               ()
    );

    // ---- i8288: status -> command strobes, gated off the bus during aen -----
    wire mem_rd_n, mem_wr_n, io_rd_n, io_wr_n, ale;
    i8288 u_8288 (
        .clock                           (clk),
        .cpu_ce_posedge                  (cpu_ce_posedge),
        .cpu_ce_negedge                  (cpu_ce_negedge),
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

    logic [19:0] cpu_addr = 20'h0;
    always_ff @(posedge clk)
        if (ale) cpu_addr <= ad_out;

    // ---- the PIC: a single master i8259, timer IRQ0 edge-triggered ---------
    logic       pic_cs_n = 1'b1;
    logic       pic_we_n = 1'b1;
    logic       pic_rd_n = 1'b1;
    logic       pic_addr = 1'b0;
    logic [7:0] pic_din  = 8'h00;
    logic [7:0] pic_irq  = 8'h00;
    wire        pic_int;
    wire        pic_dio;

    i8259 #(.edge_requests(8'h01)) u_pic (
        .clock                      (clk),
        .reset                      (reset),
        .chip_select_n              (pic_cs_n),
        .read_enable_n              (pic_rd_n),
        .write_enable_n             (pic_we_n),
        .address                    (pic_addr),
        .data_bus_in                (pic_din),
        .data_bus_out               (pic_dout),
        .data_bus_io                (pic_dio),
        .cascade_in                 (3'b000),
        .cascade_out                (),
        .cascade_io                 (),
        .slave_program_n            (1'b1),
        .buffer_enable              (),
        .slave_program_or_enable_buffer (),
        .interrupt_acknowledge_n    (inta_n),
        .interrupt_to_cpu           (pic_int),
        .interrupt_request          (pic_irq),
        .external_irr_clear         (8'h00)
    );

    // ---- DMA side ----------------------------------------------------------
    logic        dma_en    = 1'b0;
    logic [19:0] dma_addr  = 20'h30000;
    logic [7:0]  dma_wdata = 8'hA5;
    wire        dma_memwr_n = ~(aen & dma_en);
    wire [19:0] bus_addr  = aen ? dma_addr : cpu_addr;
    wire [7:0]  bus_wdata = aen ? dma_wdata : cpu_data_bus;
    wire        mem_rd_to_ram = aen ? 1'b1 : mem_rd_n;
    wire        mem_wr_to_ram = ~((~mem_wr_n & ~aen) | ~dma_memwr_n);
    wire        no_command_state = mem_rd_to_ram & mem_wr_to_ram
                                 & io_rd_n & io_wr_n;

    // ---- READY --------------------------------------------------------------
    wire proc_ready, memory_access_ready;
    READY u_ready (
        .clock               (clk),
        .cpu_ce_posedge      (cpu_ce_posedge),
        .cpu_ce_negedge      (cpu_ce_negedge),
        .reset               (reset),
        .processor_ready     (proc_ready),
        .dma_ready           (),
        .dma_wait_n          (dma_wait_n),
        .io_channel_ready    (memory_access_ready),
        .io_read_n           (io_rd_n),
        .io_write_n          (io_wr_n),
        .memory_read_n       (mem_rd_to_ram),
        .dma0_acknowledge_n  (1'b1),
        .address_enable_n    (aen)
    );

    // ---- RAM + SDRAM ---------------------------------------------------------
    wire        initilized_sdram_w, access_complete_w, access_own_w, ram_sel_n;
    wire        wr_taken_w;   // u_ram write_taken -> u_bridge drain release
    wire [12:0] s_a;  wire [1:0] s_ba;
    wire        s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};

    RAM u_ram (
        .clock(clk), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram_w),
        .gvram_page1_flag(1'b0),
        .address(bus_addr), .internal_data_bus(bus_wdata),
        .data_bus_out(ram_dout),
        .analog_mode(1'b0),
        .word_access(word_access),
        .prefetch_len(pf_req_len),
        .pf_beat_v(pf_beat_v), .pf_beat_dat(pf_beat_dat),
        .internal_data_bus_hi(cpu_data_bus_hi),
        .data_bus_out_hi(ram_dout_hi),
        .memory_read_n(mem_rd_to_ram), .memory_write_n(mem_wr_to_ram),
        .no_command_state(no_command_state),
        .memory_access_ready(memory_access_ready),
        .access_complete(access_complete_w),
        .access_own(access_own_w),
        .ram_address_select_n(ram_sel_n),
        .write_taken(wr_taken_w),
        .dbg(), .dbg2(), .dbg3(), .dbg4(), .dbg5(), .dbg6(), .dbg7(),
        .dbg_watch_addr(20'hFFFFF),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .ems98_map(ems98_unused),
        .bios_protect_flag(2'b00), .bios_shadow_flag(1'b0),
        .font_bank_flag(1'b0),
        .font_rd_req(1'b0), .font_rd_addr(24'h0), .font_rd_len(4'd0),
        .font_rd_ack(), .font_rd_valid(), .font_rd_data(), .font_rd_done(),
        .cg_rd_req(1'b0), .cg_rd_addr(24'h0), .cg_rd_len(4'd0),
        .cg_rd_ack(), .cg_rd_valid(), .cg_rd_data(), .cg_rd_done(),
        .gv_rd_req(1'b0), .gv_rd_addr(24'h0), .gv_rd_len(4'd0),
        .gv_rd_ack(), .gv_rd_valid(), .gv_rd_data(), .gv_rd_done(),
        .wait_count_clk_en(cpu_ce_negedge),
        .ram_read_wait_cycle(ram_rd_wait), .ram_write_wait_cycle(ram_wr_wait),
        .vram_rd_wait_cycle(4'h0), .vram_wr_wait_cycle(4'h0),
        .ramimg_req(1'b0), .ramimg_we(1'b0), .ramimg_addr(24'h0),
        .ramimg_len(4'h0), .ramimg_wdata(16'h0000),
        .ramimg_ack(), .ramimg_rvalid(), .ramimg_rdata(), .ramimg_done(),
        .cachef_req(1'b0), .cachef_we(1'b0), .cachef_addr(24'h0),
        .cachef_len(4'd0), .cachef_wdata0(16'h0), .cachef_wdata1(16'h0),
        .cachef_ack(), .cachef_rvalid(), .cachef_rdata(), .cachef_done(),
        .ram_wr_snoop_v(), .ram_wr_snoop_addr(), .ram_wr_snoop_len()
    );

    sdram_model #(.T_RCD(2), .T_RP(2), .T_WR(2), .T_RFC(7),
                  .T_RAS(4), .T_RC(6)) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ---- background DMAC ---------------------------------------------------
    logic dma_on = 1'b0;
    int   dma_hold_clks = 6;

    initial begin : dmac_proc
        int hold;
        dmac_hreq = 1'b0;
        forever begin
            @(posedge clk);
            if (reset || !dma_on) begin
                dmac_hreq <= 1'b0;
            end else if (!dmac_hreq) begin
                if ($urandom_range(0, 31) < 3) dmac_hreq <= 1'b1;
            end else if (dmac_hreq && aen) begin
                hold++;
                if (hold >= dma_hold_clks) begin
                    dmac_hreq <= 1'b0;
                    hold  = 0;
                end
            end else begin
                hold = 0;
            end
        end
    end

    // ---- PIC register write (bypasses the bus; config only) ----------------
    task automatic pic_write(input logic a0, input logic [7:0] d);
        begin
            pic_addr = a0; pic_din = d; pic_cs_n = 1'b0; pic_we_n = 1'b0;
            repeat (4) @(posedge clk);
            pic_we_n = 1'b1;
            repeat (4) @(posedge clk);
            pic_cs_n = 1'b1;
            repeat (4) @(posedge clk);
        end
    endtask

    task automatic pic_init;
        begin
            pic_write(1'b0, 8'h13);   // ICW1: edge, single, ICW4 follows
            pic_write(1'b1, 8'h08);   // ICW2: vector base 0x08 -> IRQ0 = 0x08
            pic_write(1'b1, 8'h01);   // ICW4: 8086 mode, no auto-EOI
        end
    endtask

    task automatic pic_eoi;
        pic_write(1'b0, 8'h20);       // OCW2: non-specific EOI
    endtask

    // glitch witness: a grant that disconnects inta_n while it is low is the
    // hazard -- inta_n rising only because aen stole command_enable is the
    // spurious edge the PIC miscounts.
    int grant_inta_low = 0;   // aen rose while inta_n was low
    int inta_forced    = 0;   // inta_n rose while aen held the bus
    int aen_during_inta = 0;  // aen rose at all while an INTA pair was live
    int aen_in_gap     = 0;   // aen rose while a byte was armed (cur_inta B_CMD)
    int pasv_win_inta  = 0;   // passive-status cpu_ce edges during an INTA
    int pasv_win_inta_hreq = 0; // ...of those, with a request held high
    always_ff @(posedge clk) begin
        if (reset) begin
            grant_inta_low <= 0;
            inta_forced    <= 0;
            aen_during_inta <= 0;
            aen_in_gap      <= 0;
            pasv_win_inta   <= 0;
            pasv_win_inta_hreq <= 0;
        end else begin
            if ($rose(aen) && !inta_n)
                grant_inta_low <= grant_inta_low + 1;
            if ($rose(inta_n) && aen)
                inta_forced <= inta_forced + 1;
            if ($rose(aen) && u_bridge.inta_active)
                aen_during_inta <= aen_during_inta + 1;
            if ($rose(aen) && u_bridge.cur_inta && u_bridge.bstate == 2'd1)
                aen_in_gap <= aen_in_gap + 1;
            if (cpu_ce_posedge && u_bridge.inta_active
                && (processor_status == 3'b111)) begin
                pasv_win_inta <= pasv_win_inta + 1;
                if (hreq) pasv_win_inta_hreq <= pasv_win_inta_hreq + 1;
            end
        end
    end

    // PIC control_state == ACK2 (2). The window spans the passive B_GAP that
    // precedes the ACK2 byte plus the byte itself, so holding the request here
    // makes the grant land while inta_n is low mid-strobe.
    assign pic_in_ack2 = (u_pic.u_Control_Logic.control_state == 2);

    // ---- fire one INTA: pulse wb_tgc_o, capture the bridge's vector --------
    // grant_mode: -1 none, >=0 hold the request from that clk for grant_len,
    // 999 = hold it while the PIC is in ACK2 (grant lands inside the byte).
    task automatic fire_inta(input int grant_mode, input int grant_len,
                             output logic [7:0] vec);
        int g;
        int c;
        begin : fire_blk
            // raise the request edge so the PIC has IRQ0 pending
            pic_irq[0] <= 1'b0;
            repeat (4) @(posedge clk);
            pic_irq[0] <= 1'b1;

            if (grant_mode == 999) grant_on_ack2 <= 1'b1;
            wb_tgc_m <= 1'b1;
            g = 0;
            c = 0;
            while (1) begin
                @(posedge clk);
                g++;
                if (grant_mode >= 0 && grant_mode < 999 && c == grant_mode)
                    sweep_hreq <= 1'b1;
                if (grant_mode >= 0 && grant_mode < 999
                    && c == grant_mode + grant_len) sweep_hreq <= 1'b0;
                c++;
                // INTA pair finished when the bridge drops inta_active after
                // having raised it.
                if (g > 8 && !u_bridge.inta_active) begin
                    vec = u_bridge.int_vector;
                    sweep_hreq <= 1'b0;
                    grant_on_ack2 <= 1'b0;
                    disable fire_blk;
                end
                if (g > 200000) begin
                    $display("  INTA TIMEOUT (int_active=%b aen=%b cstate=%0d)",
                             u_bridge.inta_active, aen,
                             u_pic.u_Control_Logic.control_state);
                    vec = 8'hEE;
                    sweep_hreq <= 1'b0;
                    grant_on_ack2 <= 1'b0;
                    disable fire_blk;
                end
            end
        end
    endtask

    // trace the INTA handshake + grant against the PIC's state machine
    logic tracen = 1'b0;
    always_ff @(posedge clk) begin
        if (tracen)
            $display("    [%0t] tgc=%b inta_act=%b bst=%0d stat=%b aen=%b inta_n=%b pic_st=%0d dio=%b pdout=%02x vec=%02x", $time, wb_tgc_m, u_bridge.inta_active, u_bridge.bstate, processor_status, aen, inta_n, u_pic.u_Control_Logic.control_state, pic_dio, pic_dout, u_bridge.int_vector);
    end

    int errors = 0;
    int vec_bad = 0;
    initial begin
        int off;
        logic [7:0] vec;

        wb_cyc_m = 0; wb_stb_m = 0; wb_we_m = 0; wb_tga_m = 0;
        wb_sel_m = 2'b11; wb_adr_m = 0; wb_dat_o_m = 0; wb_tgc_m = 0;
        pic_cs_n = 1; pic_we_n = 1; pic_rd_n = 1; pic_addr = 0;
        pic_din = 0; pic_irq = 0;
        repeat (40) @(posedge clk);
        reset = 1'b0;
        wait (initilized_sdram_w);
        repeat (200) @(posedge clk);

        $display("=== INTA vector under DMA grant (speed=%0d) ===", clk_select_r);

        // ---- clean reference: an INTA with no grant -------------------------
        pic_init();
        dma_on = 1'b0;
        tracen = 1'b1;
        fire_inta(-1, 0, vec);
        tracen = 1'b0;
        $display("  clean INTA -> vector %02x (want 08)", vec);
        pic_eoi();
        repeat (20) @(posedge clk);

        // ---- targeted: hold the request while the PIC is in ACK2 ------------
        // The ACK2 state spans the passive B_GAP before the byte plus the byte
        // itself, so this lands a grant inside the ACK2 strobe -- the hazard.
        $display("--- grant pinned to PIC ACK2 state ---");
        vec_bad = 0;
        for (int i = 0; i < 200; i++) begin
            pic_init();
            tracen = (i < 3);
            fire_inta(999, 0, vec);
            tracen = 1'b0;
            if (vec !== 8'h08) begin
                vec_bad++;
                if (vec_bad < 40)
                    $display("  BADVEC #%0d -> vec %02x (want 08)", i, vec);
            end
            pic_eoi();
            repeat (8) @(posedge clk);
        end
        $display("  ack2-pinned: %0d bad /200 (aen-in-inta=%0d aen-in-INTA=%0d forced-hi=%0d pasvwin=%0d whreq=%0d)",
                 vec_bad, grant_inta_low, aen_during_inta, inta_forced,
                 pasv_win_inta, pasv_win_inta_hreq);

        // ---- sweep a single grant across the INTA window --------------------
        $display("--- single-grant sweep across ACK2 ---");
        vec_bad = 0;
        for (off = 0; off < 140; off++) begin
            pic_init();
            fire_inta(off, 8, vec);
            if (vec !== 8'h08) begin
                vec_bad++;
                if (vec_bad < 40)
                    $display("  BADVEC grant@%0d -> vec %02x (want 08)",
                             off, vec);
            end
            pic_eoi();
            repeat (10) @(posedge clk);
        end
        $display("  single-grant sweep: %0d bad vectors /140", vec_bad);

        // ---- dense background grants + repeated INTAs ------------------------
        $display("--- dense grants + repeated INTA ---");
        vec_bad = 0;
        dma_on = 1'b1;
        for (int i = 0; i < 400; i++) begin
            pic_init();
            fire_inta(-1, 0, vec);
            if (vec !== 8'h08) begin
                vec_bad++;
                if (vec_bad < 40)
                    $display("  BADVEC #%0d -> vec %02x (want 08)", i, vec);
            end
            pic_eoi();
            repeat (4) @(posedge clk);
        end
        dma_on = 1'b0;
        $display("  dense: %0d bad /400 aen-in-inta=%0d aen-in-INTA=%0d aen-in-gap=%0d forced-hi=%0d",
                 vec_bad, grant_inta_low, aen_during_inta, aen_in_gap, inta_forced);
        $display("  passive-win-in-INTA=%0d (with-hreq=%0d)",
                 pasv_win_inta, pasv_win_inta_hreq);

        if (vec_bad == 0)
            $display("=== PASS tb_zet_inta_grant ===");
        else
            $display("=== FAIL tb_zet_inta_grant (%0d wrong vectors) ===",
                     vec_bad);
        $finish;
    end

    // Watchdog
    initial begin
        #600_000_000;
        $display("FAIL tb_zet_inta_grant (timeout)");
        $finish;
    end

endmodule
