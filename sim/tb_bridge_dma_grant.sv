//
// tb_bridge_dma_grant -- does a DMA/HOLD grant that lands while a CPU read byte
// is armed in B_CMD corrupt the byte the bridge returns?
//
// The suspected metal race: the arbiter samples a passive processor_status on
// a cpu_ce_posedge (hold_request_ff_1), but the byte engine can ARM the next
// byte on that very edge, so address_enable_n lands ~1.5 edges later while the
// byte is mid-B_CMD -- its memory read strobe is disconnected for the grant,
// then re-runs on release. The faithful accept (t_cnt>=3) has no saw_low gate,
// and t_cnt saturates during the grant, so on bus return the accept can fire
// on a processor_ready that rose for bus-availability, not data-validity.
//
// Faithful path under test:
//   cpu_bus_bridge -> i8288 (command_enable=~aen) -> bus merge -> RAM ->
//   sdram_shim -> sdram_mp -> sdram_model, with READY feeding processor_ready.
//   The HOLD grant is driven through the arbiter's own hold chain (passive
//   status sample -> hold_acknowledge -> aen -> dma_wait), exactly the metal's.
//
// A word read's odd byte is the sharpest probe: between byte0 and byte1 there
// is a passive-status window where a pending grant lands, preempting byte1.
// A stale high byte on a far pointer = a wild segment. We sweep the grant
// request offset across the read and flag any word whose bytes come back
// wrong.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_bridge_dma_grant;

    // clk_chipset is 42.954545 MHz.
    logic clk = 1'b0;
    always #11.641 clk = ~clk;

    logic reset = 1'b1;

    // ---- CE train -----------------------------------------------------------
    wire  clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire  cycle_accrate, shift_read_timing;
    wire  [7:0] ccc_div, ccc_dec;
    wire  [1:0] ram_rd_wait, ram_wr_wait;
    logic biu_done_gate = 1'b1;

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
    // hold_request_ff_1 samples a passive status on cpu_ce_posedge; ff_2 on the
    // negedge; aen on the following posedge; dma_wait one behind. This is
    // Bus_Arbiter's hold chain verbatim so the grant lands exactly where the
    // metal's can -- including preempting a byte armed between the passive
    // sample and the aen edge.
    logic       hreq = 1'b0;          // stimulus: "the DMAC wants the bus"
    logic       hold_ff1 = 1'b0;
    logic       hold_ff2 = 1'b0;
    logic       aen = 1'b0;
    logic       dma_wait = 1'b0;
    wire [2:0]  processor_status;

    always_ff @(posedge clk) begin
        if (reset)
            hold_ff1 <= 1'b0;
        else if (cpu_ce_posedge)
            hold_ff1 <= (processor_status[0] & processor_status[1]) & hreq;
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
    wire         wb_ack_i;
    wire         zet_clk;
    wire  [4:0]  pf_req_len;
    wire         pf_beat_v;
    wire  [7:0]  pf_beat_dat;

    // bridge CPU-facing outputs
    wire [19:0]  ad_out;
    wire [7:0]   cpu_data_bus, cpu_data_bus_hi;
    wire         word_access, lock_n;
    wire [7:0]   ram_dout, ram_dout_hi;

    cpu_bus_bridge u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .pace_286          (1'b1),
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
        .wb_tgc_o          (1'b0),
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
        .data_bus          (ram_dout),
        .processor_ready   (proc_ready),
        .address_enable_n  (aen),
        .sdram_wr_taken    (wr_taken_w),
        .sdram_rd_ready    (1'b1),
        .pause_core        (1'b0),
        .throttle          (1'b0),
        .pf_disable        (1'b1),      // isolate the byte-engine accept path
        .pf_nofill         (1'b0),
        .pf_nofillm        (1'b0),
        .pf_nohit          (1'b0),
        .sn_v              (1'b0),      // no memory model in this bench
        .sn_addr           (24'd0),
        .sn_len            (4'd0),
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
        .interrupt_acknowledge_n         (),
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

    // CPU address latch on ALE, as the chipset does.
    logic [19:0] cpu_addr = 20'h0;
    always_ff @(posedge clk)
        if (ale) cpu_addr <= ad_out;

    // ---- the DMA side: during the grant an "FDC" byte writes to RAM --------
    // A grant that only parks the bus still defers the CPU read; driving a
    // real write keeps RAM busy so the re-run contention is faithful and a
    // stray-address write is on the bus exactly as FDC DMA does. dma_en is the
    // stimulus flag: while set, each aen window writes dma_wdata to dma_addr.
    logic        dma_en    = 1'b0;
    logic [19:0] dma_addr  = 20'h30000;
    logic [7:0]  dma_wdata = 8'hA5;
    wire        dma_memwr_n = ~(aen & dma_en);

    // Bus merge (Bus_Arbiter's ab_* shape): the CPU's command only reaches the
    // bus while ~aen; the DMA's write only while aen.
    wire ab_mem_rd_n = ~((~mem_rd_n & ~aen) | 1'b0) & (aen ? 1'b1 : 1'b1);
    wire ab_mem_wr_n = ~((~mem_wr_n & ~aen) | ~dma_memwr_n);
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

    // ---- synthetic Wishbone read master ------------------------------------
    // One read at a time: hold cyc/stb/adr stable until ack, then release.
    // Tracks a shadow so the grant injector knows when a read is mid-flight.
    int   reads_done = 0;
    int   stale_hits = 0;
    logic [15:0] last_rd;

    // ---- DRQ/DACK grant driver ---------------------------------------------
    // A real DMAC asserts DRQ and holds it until the arbiter grants the bus
    // (aen), then holds the bus for a transfer and releases. Running this as a
    // free background process -- not coupled to any Wishbone access -- makes
    // grants land at arbitrary points in the byte stream, including mid-B_CMD
    // on whichever byte is armed when aen drops in.
    logic dma_on = 1'b0;         // master enable for the background DMAC
    int   dma_hold_clks = 6;     // how long aen stays high per grant
    int   dma_gap_lo = 2;        // idle clks between requests (randomised)
    int   dma_gap_hi = 30;

    initial begin : dmac_proc
        int hold;
        hreq = 1'b0;
        forever begin
            @(posedge clk);
            if (reset || !dma_on) begin
                hreq <= 1'b0;
            end else if (!hreq) begin
                // wait a random gap, then raise DRQ
                if ($urandom_range(0, 31) < 3) hreq <= 1'b1;
            end else if (hreq && aen) begin
                // granted: hold the bus for the transfer, then release
                hold++;
                if (hold >= dma_hold_clks) begin
                    hreq <= 1'b0;
                    hold  = 0;
                end
            end else begin
                hold = 0;   // still waiting for the grant
            end
        end
    end

    task automatic wb_read_word(input logic [19:0] addr, output logic [15:0] d);
        int g;
        begin : wb_read_word_blk
            @(posedge clk);
            wb_adr_m <= addr[19:1];
            wb_sel_m <= 2'b11;      // word
            wb_we_m  <= 1'b0;
            wb_tga_m <= 1'b0;
            wb_cyc_m <= 1'b1;
            wb_stb_m <= 1'b1;
            g = 0;
            while (!wb_ack_i) begin
                @(posedge clk);
                g++;
                if (g > 60000) begin
                    $display("  WB RD TIMEOUT @%05x (hreq=%b aen=%b)", addr, hreq, aen);
                    wb_cyc_m <= 1'b0; wb_stb_m <= 1'b0;
                    d = 16'hDEAD;
                    disable wb_read_word_blk;
                end
            end
            d = wb_dat_i;
            @(posedge clk);
            wb_cyc_m <= 1'b0;
            wb_stb_m <= 1'b0;
        end
    endtask

    task automatic wb_write_word(input logic [19:0] addr, input logic [15:0] d);
        int g;
        begin : wb_write_word_blk
            @(posedge clk);
            wb_adr_m   <= addr[19:1];
            wb_sel_m   <= 2'b11;
            wb_we_m    <= 1'b1;
            wb_tga_m   <= 1'b0;
            wb_dat_o_m <= d;
            wb_cyc_m   <= 1'b1;
            wb_stb_m   <= 1'b1;
            g = 0;
            while (!wb_ack_i) begin
                @(posedge clk);
                g++;
                if (g > 60000) begin
                    $display("  WB WR TIMEOUT @%05x", addr);
                    wb_cyc_m <= 1'b0; wb_stb_m <= 1'b0;
                    disable wb_write_word_blk;
                end
            end
            @(posedge clk);
            wb_cyc_m <= 1'b0;
            wb_stb_m <= 1'b0;
            wb_we_m  <= 1'b0;
        end
    endtask

    // ---- trace: watch the byte engine + grant chain during one read --------
    logic tracen = 1'b0;
    always_ff @(posedge clk) begin
        if (tracen && cpu_ce_posedge)
            $display("    [%0t] bst=%0d stat=%b t=%0d saw=%b aen=%b hreq=%b rdy=%b mrd=%b",
                     $time, bst, processor_status, tcnt, sawl, aen, hreq,
                     proc_ready, mem_rd_to_ram);
    end

    // ---- run -----------------------------------------------------------------
    // ---- witness: did aen actually preempt an armed read byte? ------------
    // If aen ever rises while the byte engine is mid-B_CMD, the grant
    // preempted a live access -- the exact hazard window.
    int   grant_total   = 0;   // aen rising edges
    int   grant_midcmd  = 0;   // of those, aen rose while bstate==B_CMD
    int   reads_preempt = 0;   // reads that overlapped an aen window
    logic aen_seen_this_read = 1'b0;

    // internal byte-engine state via hierarchical refs into the DUT
    wire [1:0] bst  = u_bridge.bstate;
    wire [2:0] tcnt = u_bridge.t_cnt;
    wire       sawl = u_bridge.saw_low;

    always_ff @(posedge clk) begin
        if (reset) begin
            grant_total <= 0; grant_midcmd <= 0; reads_preempt <= 0;
            aen_seen_this_read <= 1'b0;
        end else begin
            if ($rose(aen)) begin
                grant_total <= grant_total + 1;
                if (bst == 2'd1)               // B_CMD: a byte was armed
                    grant_midcmd <= grant_midcmd + 1;
            end
            if (wb_cyc_m && wb_stb_m && aen)
                aen_seen_this_read <= 1'b1;
            if (!wb_cyc_m && aen_seen_this_read) begin
                reads_preempt <= reads_preempt + 1;
                aen_seen_this_read <= 1'b0;
            end
        end
    end

    int errors = 0;
    initial begin
        logic [15:0] got;
        int off;
        int nbad;
        int wnbad;
        int stray;

        // init
        wb_cyc_m = 0; wb_stb_m = 0; wb_we_m = 0; wb_tga_m = 0;
        wb_sel_m = 2'b11; wb_adr_m = 0; wb_dat_o_m = 0;
        repeat (40) @(posedge clk);
        reset = 1'b0;
        wait (initilized_sdram_w);
        repeat (200) @(posedge clk);

        // Fill the probe region with a known pattern: byte = low byte of addr
        // XOR 0x5A. Word reads then expect {pat(a+1), pat(a)}.
        for (int i = 0; i < 256; i++)
            sdr.poke(24'h20000 + i, {8'h00, 8'(8'h5A ^ (i & 8'hFF))});
        // Write-target region + guard band, all zeroed.
        for (int i = 0; i < 256; i++)
            sdr.poke(24'h21000 + i, 16'h0000);

        $display("=== grant-preempts-read sweep (speed=%0d) ===", clk_select_r);

        // Baseline: a clean word read with no grant, traced.
        tracen = 1'b1;
        wb_read_word(20'h20000, got);
        tracen = 1'b0;
        $display("  clean read @20000 -> %04x (want %04x)",
                 got, {8'h5A ^ 8'h01, 8'h5A ^ 8'h00});

        // Traced read with the background DMAC enabled -- does aen rise
        // mid-byte?
        $display("  --- traced reads with background DMAC ---");
        dma_on = 1'b1;
        tracen = 1'b1;
        for (int k = 0; k < 6; k++)
            wb_read_word(20'h20000, got);
        tracen = 1'b0;
        dma_on = 1'b0;
        $display("    last got=%04x", got);

        // ---- push/pop hazard: write A then immediately read A, grant between --
        // A call/int pushes a return address (posted write parked in RAM's
        // queue); ret/iret pops it. If a grant interleaves between the park
        // and the read, a rd_conflicts hole would serve the PRE-write value.
        // Hammer the exact pattern: write then same-address read, grants on.
        $display("--- push/pop RAW: write-then-read same addr, grants on ---");
        begin : rawloop
            int rawbad;
            rawbad = 0;
            dma_on = 1'b1; dma_en = 1'b1;
            for (int i = 0; i < 400; i++) begin
                logic [19:0] a;
                logic [15:0] wv, rv;
                a  = 20'h23000 + ($urandom_range(0, 15) * 2); // small window
                wv = 16'h4000 + i;
                wb_write_word(a, wv);
                wb_read_word (a, rv);          // immediate same-address read
                if (rv !== wv) begin
                    rawbad++;
                    if (rawbad < 30)
                        $display("  RAW miss %05x wrote %04x read %04x",
                                 a, wv, rv);
                end
            end
            dma_on = 1'b0; dma_en = 1'b0;
            repeat (300) @(posedge clk);
            $display("  RAW same-addr: %0d stale /400 (grants=%0d midcmd=%0d)",
                     rawbad, grant_total, grant_midcmd);
            stale_hits += rawbad;
        end

        // ---- dense soak: grants fly against a continuous r/w stream ---------
        // The metal's byte stream is dense: prefetch + operand + write cycles
        // back-to-back, so a HOLD grant lands while some byte is armed in
        // B_CMD. dma_on runs the background DMAC (writes to 0x30000); dma_en
        // puts a real DMA write on the bus during each grant.
        $display("--- dense soak: background grants vs r/w stream ---");
        dma_on = 1'b1;
        dma_en = 1'b1;
        // Write a counting pattern across 0x22000..0x220FF (128 words) while
        // grants fire -- this is the write path under preemption.
        for (int i = 0; i < 128; i++)
            wb_write_word(20'h22000 + i*2, 16'h7000 + i);
        // Reread the whole block repeatedly while grants keep firing.
        for (int rep = 0; rep < 4; rep++)
            for (int i = 0; i < 128; i++) begin
                wb_read_word(20'h22000 + i*2, got);
                if (got !== 16'h7000 + i) begin
                    stale_hits++;
                    if (stale_hits < 40)
                        $display("  STALE rd %05x got %04x want %04x",
                                 20'h22000 + i*2, got, 16'h7000 + i);
                end
            end
        dma_on = 1'b0;
        dma_en = 1'b0;
        repeat (400) @(posedge clk);   // let parked writes drain

        // Authoritative verify in the SDRAM model: every byte of the block.
        nbad = 0;
        for (int i = 0; i < 256; i++) begin
            int gotb  = sdr.peek(24'h22000 + i) & 8'hFF;
            int wantb = (i % 2 == 0) ? (16'h7000 + (i/2)) & 8'hFF
                                     : ((16'h7000 + (i/2)) >> 8) & 8'hFF;
            if (gotb !== wantb) begin
                nbad++;
                if (nbad < 40)
                    $display("  MEM %05x = %02x want %02x",
                             24'h22000 + i, gotb, wantb);
            end
        end
        // And the read/guard regions must be untouched by stray writes.
        for (int i = 0; i < 256; i++) begin
            int gotb = sdr.peek(24'h20000 + i) & 8'hFF;
            int wantb = 8'h5A ^ (i & 8'hFF);
            if (gotb !== wantb) begin
                stray++;
                if (stray < 40)
                    $display("  STRAY %05x = %02x want %02x",
                             24'h20000 + i, gotb, wantb);
            end
        end
        wnbad += nbad;   // block-write errors fold into the write count

        $display("  grants=%0d midcmd=%0d reads-overlap=%0d",
                 grant_total, grant_midcmd, reads_preempt);
        $display("  stale-reads=%0d bad-writes=%0d stray-writes=%0d",
                 stale_hits, wnbad, stray);
        if (stale_hits + wnbad + stray == 0)
            $display("=== PASS tb_zet_dma_grant ===");
        else
            $display("=== FAIL tb_zet_dma_grant (%0d corruptions) ===",
                     stale_hits + wnbad + stray);
        $finish;
    end

    // Watchdog
    initial begin
        #400_000_000;
        $display("FAIL tb_zet_dma_grant (timeout)");
        $finish;
    end

endmodule
