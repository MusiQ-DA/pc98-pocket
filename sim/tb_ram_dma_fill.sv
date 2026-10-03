//
// tb_ram_dma_fill -- a REAL uPD71071 floppy-style write fill through the REAL
// memory path, hunting the byte drops the Pocket shows at every 512-word
// SDRAM column boundary during an FDC->DMAC->RAM transfer.
//
// On the metal the kernel.sys load loses bytes, systematically aligned to
// the column wrap: the byte at the boundary pays a row miss, and while it
// is being served a second strobe can arrive that the depth-one park in
// RAM.sv cannot hold -- it is dropped on the floor (dbg2/dbg3 count it).
//
// The path here is the metal's own:
//   upd71071 (programmed through its real register bus, byte-pointer clear,
//   mode 46h single-write ch2, base, count, unmask) -> the Bus_Arbiter
//   merge (address = {page, dma_address_out}, strobe = dma_memory_write_n)
//   -> RAM.sv -> sdram_shim -> sdram_mp -> sdram_model, with READY.sv
//   feeding dma_ready back to the DMAC exactly the way Chipset wires it.
//
// A periodic port-D read burst (the graphics display fetch) keeps the
// realistic SDRAM contention pressure that stretches port-A service, and
// RAM.sv's own refresh fires in the inter-byte gaps the way it does on the
// metal.
//
// What it answers: does the fill land clean, and does u_ram.dbg2/dbg3 name
// the drops (count, first address, colliding FSM state).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ram_dma_fill;

    // clk_chipset is 42.954545 MHz.
    logic clk = 1'b0;
    always #11.641 clk = ~clk;

    logic reset = 1'b1;

    // ---- the CE train, as core_top makes it -------------------------------
    // The DMA engine steps on cpu_ce_posedge; the metal default during the
    // boot fill is the 9.54 MHz pacing.
    wire  clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire  cycle_accrate, shift_read_timing;
    wire  [7:0] ccc_div, ccc_dec;
    wire  [1:0] ram_rd_wait, ram_wr_wait;
    logic biu_done = 1'b1;

    ce_generator u_ce (
        .clock                              (clk),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (2'b00),      // 4.9 MHz
        .cpu_clk_pin                        (clk_cpu),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .cycle_accrate                      (cycle_accrate),
        .clock_cycle_counter_division_ratio  (ccc_div),
        .clock_cycle_counter_decrement_value (ccc_dec),
        .shift_read_timing                  (shift_read_timing),
        .ram_read_wait_cycle                (ram_rd_wait),
        .ram_write_wait_cycle               (ram_wr_wait), .vram_wait_en()
    );

    // ---- the real uPD71071 --------------------------------------------------
    // Register setup is driven on its bus interface directly (cs + iow +
    // address_in + data_bus_in); the trailing edge of iow is the latch.
    logic       dmac_cs_n = 1'b1;
    logic       bench_iow_n = 1'b1;
    logic [3:0] bench_adr = 4'h0;
    logic [7:0] bench_dw  = 8'h00;

    // Bench-side CPU bus master for the verify pass: idle while the DMAC
    // owns the bus (aen_n), drives RAM reads after.
    logic        bench_memrd_n = 1'b1;
    logic        bench_memwr_n = 1'b1;
    logic [19:0] bench_addr    = 20'h0;
    logic [7:0]  bench_wdata   = 8'h00;

    wire        dmac_ior_out_n, dmac_iow_out_n;
    wire        dmac_memrd_n,   dmac_memwr_n;
    wire [15:0] dmac_addr_out;
    wire [7:0]  dmac_dout;
    wire [3:0]  dack_n;
    wire        hrq;

    // ab_* merges, exactly as Bus_Arbiter builds them: the 8288 side is the
    // bench master (gated by ~aen_n), the DMAC side its own strobes.
    wire        ab_io_write_n = ~(~bench_iow_n | ~dmac_iow_out_n);
    wire        ab_io_read_n  = dmac_ior_out_n;

    // +CLIPW=n clips every DMA write strobe to n clk at the RAM input,
    // modeling the metal's early-released ~1-CE-tick pulses (dma_ready is
    // still high from the previous byte when SW starts). The DMAC output
    // itself keeps its proper shape; only what RAM sees is shortened.
    int         clipw = 0;
    int         clip_cnt = 0;
    logic       clip_active = 1'b0;
    wire        dmac_memwr_vis = clip_active ? 1'b1 : dmac_memwr_n;
    always_ff @(posedge clk) begin
        if (reset || dmac_memwr_n) begin
            clip_cnt    <= 0;
            clip_active <= 1'b0;
        end else if (clipw != 0) begin
            if (clip_cnt == clipw - 1) clip_active <= 1'b1;
            else                       clip_cnt    <= clip_cnt + 1;
        end
    end

    wire        ab_mem_wr_n   = ~((~bench_memwr_n & ~aen_n) | ~dmac_memwr_vis);
    wire        ab_mem_rd_n   = ~((~bench_memrd_n & ~aen_n) | ~dmac_memrd_n);

    // The arbiter's hold handshake, flattened like tb_v30_dmac's: grant on
    // the cpu_ce edge, aen_n one tick behind, dma_wait one more.
    logic       hlda = 1'b0;
    logic       aen_n = 1'b1;
    logic       dma_wait = 1'b0;
    always_ff @(posedge clk) begin
        if (reset) begin
            hlda     <= 1'b0;
            aen_n    <= 1'b1;
            dma_wait <= 1'b0;
        end else if (cpu_ce_posedge) begin
            hlda     <= hrq;
            aen_n    <= hlda;
            dma_wait <= aen_n;
        end
    end
    wire        dma_wait_n = ~dma_wait;
    wire        dma_enable_n = ~(dma_wait & aen_n);

    // DRQ per byte, the way pc98_fdc_glue shapes it: the request drops for
    // the whole width of each ack, so every byte is a fresh request edge.
    logic       want_drq = 1'b0;
    logic [3:0] dreq = 4'b0000;
    always_ff @(posedge clk) begin
        if (reset)
            dreq <= 4'b0000;
        else if (!dack_n[2])
            dreq[2] <= 1'b0;
        else if (want_drq)
            dreq[2] <= 1'b1;
    end

    upd71071 u_dmac (
        .clock                              (clk),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .chip_select_n                      (dmac_cs_n),
        .ready                              (dma_ready),
        .hold_acknowledge                   (hlda),
        .dma_request                        (dreq),
        .data_bus_in                        (bench_dw),
        .data_bus_out                       (dmac_dout),
        .io_read_n_in                       (ab_io_read_n),
        .io_read_n_out                      (dmac_ior_out_n),
        .io_read_n_io                       (),
        .io_write_n_in                      (ab_io_write_n),
        .io_write_n_out                     (dmac_iow_out_n),
        .io_write_n_io                      (),
        .end_of_process_n_in                (1'b1),
        .end_of_process_n_out               (),
        .address_in                         (bench_adr),
        .address_out                        (dmac_addr_out),
        .output_highst_address              (),
        .hold_request                       (hrq),
        .dma_acknowledge                    (dack_n),
        .address_enable                     (),
        .address_strobe                     (),
        .memory_read_n                      (dmac_memrd_n),
        .memory_write_n                     (dmac_memwr_n)
    );

    // ---- the shared bus, Bus_Arbiter's address/data view -------------------
    // During the grant the address is {page_register[1], dma_address_out};
    // page 0 keeps the fill in low RAM where the kernel went on the metal.
    wire        dma_active = ~dma_enable_n && ~(&dack_n);
    wire [19:0] bus_addr = dma_active ? {4'h0, dmac_addr_out} : bench_addr;

    // The FDC's byte, on data_bus_ext for the whole io-read/write overlap.
    // Address-correlated: the FIFO head for the byte being transferred now,
    // so a shifted window shows up as a data mismatch, not an index slip.
    localparam int FILL_BASE = 20'h00400;   // first boundary at +0x200
    localparam int FILL_LEN  = 4096;
    wire [7:0]   fdc_byte = 8'hA5 ^ bus_addr[7:0];

    // internal_data_bus: Bus_Arbiter's default is the external bus; a bench
    // CPU-side write owns it during its own strobe.
    wire [7:0]  data_bus_ext = fdc_byte;
    wire [7:0]  internal_data_bus = (~bench_memwr_n & ~aen_n) ? bench_wdata
                                                            : data_bus_ext;

    // (no byte index needed -- the FDC byte is address-correlated)

    // ---- the real READY -----------------------------------------------------
    wire        dma_ready, bench_ready_unused;
    wire        memory_access_ready, ram_address_select_n;

    READY u_ready (
        .clock               (clk),
        .cpu_ce_posedge      (cpu_ce_posedge),
        .cpu_ce_negedge      (cpu_ce_negedge),
        .reset               (reset),
        .processor_ready     (bench_ready_unused),
        .dma_ready           (dma_ready),
        .dma_wait_n          (dma_wait_n),
        .io_channel_ready    (memory_access_ready),
        .io_read_n           (ab_io_read_n),
        .io_write_n          (ab_io_write_n),
        .memory_read_n       (ab_mem_rd_n),
        .dma0_acknowledge_n  (1'b1),
        .address_enable_n    (aen_n)
    );

    // ---- display-fetch pressure on sdram_mp port D --------------------------
    // The GDC's line fetch runs during the fill on the metal; a burst every
    // few hundred clocks is the same order of port contention. req holds
    // until ack, the burst drains on rvalid, done releases it.
    logic        gv_req = 1'b0;
    wire         gv_ack, gv_rvalid, gv_done;
    wire [15:0]  gv_rdata;
    int          gv_timer = 0;
    always_ff @(posedge clk) begin
        if (reset) begin
            gv_req <= 1'b0; gv_timer <= 0;
        end else if (gv_req) begin
            // req is a request, not a hold: it falls once the burst is
            // granted, like every other port master.
            if (gv_ack) gv_req <= 1'b0;
        end else begin
            gv_timer <= gv_timer + 1;
            if (gv_timer == 400) begin
                gv_timer <= 0;
                gv_req   <= 1'b1;
            end
        end
    end

    // ---- the carve-out server on sdram_mp port E ------------------------------
    // THE real contender: on the metal every byte the FDC pushes downstream
    // was fetched from the image carve-out by fdd_ramimg, one single-word
    // port-E read at a time, in a different row region. While the fill runs
    // this port streams reads continuously -- the per-byte arbitration that
    // stretches port-A write service on hardware.
    logic        ri_req = 1'b0;
    wire         ri_ack, ri_rvalid, ri_done;
    wire [15:0]  ri_rdata;
    logic [23:0] ri_addr = 24'h620000;   // carve-out region
    always_ff @(posedge clk) begin
        if (reset) begin
            ri_req <= 1'b0; ri_addr <= 24'h620000;
        end else if (ri_req) begin
            if (ri_ack) begin
                ri_req  <= 1'b0;
                ri_addr <= ri_addr + 24'd2;
            end
        end else if (want_drq) begin
            // a fresh single-word read every few clocks while the fill runs
            ri_req <= 1'b1;
        end
    end

    // ---- foreign FSM traffic (the svc-op stand-in) --------------------------
    // On the metal a softcpu svc op walks the RAM FSM for its whole access
    // while the fill runs; here a short read strobe injected straight at
    // RAM's read port does the same FSM occupancy. SVC_PERIOD sweeps the
    // cadence; set 0 to disable.
    `ifndef SVC_PERIOD
    `define SVC_PERIOD 96
    `endif
    logic        fgn_rd = 1'b0;
    int          fgn_timer = 0;
    wire         fgn_rd_n;
    always_ff @(posedge clk) begin
        if (reset) begin
            fgn_rd <= 1'b0; fgn_timer <= 0;
        end else if (want_drq) begin
            fgn_timer <= fgn_timer + 1;
            if (fgn_timer == `SVC_PERIOD) begin
                fgn_timer <= 0;
                fgn_rd    <= 1'b1;
            end else if (fgn_rd && fgn_timer == `SVC_PERIOD - 6)
                fgn_rd <= 1'b0;   // 6-clock read pulse
        end else begin
            fgn_rd <= 1'b0; fgn_timer <= 0;
        end
    end
    assign fgn_rd_n = ~fgn_rd;

    // ---- RAM + SDRAM ---------------------------------------------------------
    wire        ram_ready_w, access_complete_w, initilized_sdram_w;
    wire [7:0]  ram_dout, ram_dout_hi;
    wire [12:0] s_a;  wire [1:0] s_ba;
    wire        s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    wire [31:0] ram_dbg2, ram_dbg3;
    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};

    wire        all_mem_rd_n = ab_mem_rd_n & fgn_rd_n;
    wire no_command_state = ab_io_write_n & ab_io_read_n
                          & ab_mem_wr_n & all_mem_rd_n;

    RAM u_ram (
        .clock(clk), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram_w),
        .gvram_page1_flag(1'b0),
        .address(bus_addr), .internal_data_bus(internal_data_bus),
        .data_bus_out(ram_dout),
        .analog_mode(1'b0),
        .word_access(1'b0),
        .internal_data_bus_hi(8'h00),
        .data_bus_out_hi(ram_dout_hi),
        .memory_read_n(all_mem_rd_n), .memory_write_n(ab_mem_wr_n),
        .no_command_state(no_command_state),
        .memory_access_ready(ram_ready_w),
        .access_complete(access_complete_w),
        .ram_address_select_n(ram_address_select_n),
        .dbg(), .dbg2(ram_dbg2), .dbg3(ram_dbg3),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .ems98_map(ems98_unused),
        .bios_protect_flag(2'b00), .bios_shadow_flag(1'b0),
        .font_bank_flag(1'b0),
        .font_rd_req(1'b0), .font_rd_addr(24'h0), .font_rd_len(4'h0),
        .font_rd_ack(), .font_rd_valid(), .font_rd_data(), .font_rd_done(),
        .cg_rd_req(1'b0), .cg_rd_addr(24'h0), .cg_rd_len(4'h0),
        .cg_rd_ack(), .cg_rd_valid(), .cg_rd_data(), .cg_rd_done(),
        .gv_rd_req(gv_req), .gv_rd_addr(24'h0A000), .gv_rd_len(4'd8),
        .gv_rd_ack(gv_ack), .gv_rd_valid(gv_rvalid),
        .gv_rd_data(gv_rdata), .gv_rd_done(gv_done),
        .wait_count_clk_en(cpu_ce_negedge),
        .ram_read_wait_cycle(ram_rd_wait), .ram_write_wait_cycle(ram_wr_wait),
        .vram_rd_wait_cycle(4'h0), .vram_wr_wait_cycle(4'h0),
        .ramimg_req(ri_req), .ramimg_we(1'b0), .ramimg_addr(ri_addr),
        .ramimg_len(4'd0), .ramimg_wdata(16'h0000),
        .ramimg_ack(ri_ack), .ramimg_rvalid(ri_rvalid),
        .ramimg_rdata(ri_rdata), .ramimg_done(ri_done)
    );
    assign memory_access_ready = ram_ready_w;

    sdram_model #(.T_RCD(2), .T_RP(2), .T_WR(2), .T_RFC(7),
                  .T_RAS(4), .T_RC(6)) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ---- bookkeeping ----------------------------------------------------------
    int memw_pulses = 0;
    int wc_seen = 0, wr_accept = 0, sdr_writes = 0;
    int tail_trace = 0;
    logic [23:0] acc_prev = 24'h0;
    logic dmac_memwr_d = 1'b1;
    always_ff @(posedge clk) begin
        dmac_memwr_d <= ab_mem_wr_n;
        // Count only fill-phase strobes: a spurious assertion during reset
        // release otherwise eats one count and the fill ends a byte short.
        if (want_drq & ~ab_mem_wr_n & dmac_memwr_d) begin
            memw_pulses <= memw_pulses + 1;
            if (memw_pulses >= FILL_LEN - 8 || memw_pulses < 10)
                $display("    PLS #%0d ba=%06x t=%0t", memw_pulses + 1,
                         bus_addr, $time);
        end
        if (u_ram.write_command) wc_seen <= wc_seen + 1;
        if (u_ram.state == u_ram.IDLE && u_ram.next_state == u_ram.RAM_WRITE_1) begin
            wr_accept <= wr_accept + 1;
            if (wr_accept >= FILL_LEN - 10 || wr_accept < 12 ||
                (u_ram.wc_pend ? u_ram.pend_address : u_ram.latch_address)
                == acc_prev)
                $display("    ACC #%0d addr=%06x (pend=%b) t=%0t",
                         wr_accept + 1,
                         u_ram.wc_pend ? u_ram.pend_address
                                       : u_ram.latch_address,
                         u_ram.wc_pend, $time);
            acc_prev <= u_ram.wc_pend ? u_ram.pend_address
                                      : u_ram.latch_address;
        end
        if (~s_we & ~s_cas & s_ras & ~s_cs) sdr_writes <= sdr_writes + 1; // WR
        if (wr_accept < 4 && u_ram.state != u_ram.IDLE)
            $display("    t=%0t st=%0d wc=%b wrf=%b aadr=%06x adi=%04x | mpst=%0d init=%b hreq=%b gnt=%0d pack=%b pdone=%b",
                     $time, u_ram.state, u_ram.write_command,
                     u_ram.write_flag, u_ram.access_address,
                     u_ram.access_data_in,
                     u_ram.u_sdram.u_mp.state,
                     u_ram.u_sdram.u_mp.init_done,
                     u_ram.u_sdram.u_mp.have_req,
                     u_ram.u_sdram.u_mp.grant,
                     u_ram.u_sdram.u_mp.p_ack,
                     u_ram.u_sdram.u_mp.p_done);
        // The tail: last strobe's full lifecycle once the count is nearly out.
        if (memw_pulses >= FILL_LEN - 2 && tail_trace < 600) begin
            tail_trace++;
            $display("    T%03d mw=%b st=%0d nst=%0d wc=%b pend=%b wrf=%b wrq=%b rdy=%b mrdy=%b dst=%0d ba=%06x la=%06x pa=%06x aa=%06x adi=%04x",
                     tail_trace, ab_mem_wr_n, u_ram.state, u_ram.next_state,
                     u_ram.write_command, u_ram.wc_pend, u_ram.write_flag,
                     u_ram.write_request, dma_ready, memory_access_ready,
                     u_dmac.u_Timing_And_Control.state,
                     bus_addr, u_ram.latch_address, u_ram.pend_address,
                     u_ram.accept_address, u_ram.access_data_in);
        end
    end

    int errors = 0;
    task automatic check(input bit cond, input string name);
        if (!cond) begin
            errors++;
            $display("FAIL: %s", name);
        end
    endtask

    // Register write on the real iow interface: cs + iow low, hold a few
    // clocks, release -- the trailing edge latches (write_flag).
    task automatic dmac_wr(input logic [3:0] rega, input logic [7:0] v);
        begin
            @(posedge clk);
            dmac_cs_n   <= 1'b0;
            bench_adr   <= rega;
            bench_dw    <= v;
            bench_iow_n <= 1'b0;
            repeat (4) @(posedge clk);
            bench_iow_n <= 1'b1;
            @(posedge clk);
            dmac_cs_n   <= 1'b1;
        end
    endtask

    // Verify readback through the bus, the way a CPU master would: hold the
    // read strobe a few clocks first so the wait cannot slip out through the
    // not-yet-started ready window, then until memory_access_ready.
    task automatic cpu_read(input int addr, output logic [7:0] q);
        int guard;
        begin
            bench_addr    <= 20'(addr);
            bench_memrd_n <= 1'b0;
            repeat (4) @(posedge clk);
            guard = 0;
            while (!memory_access_ready && guard < 4000) begin
                @(posedge clk); guard++;
            end
            if (guard >= 4000) $display("  READ TIMEOUT @%05h", addr);
            q = ram_dout;
            bench_memrd_n <= 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    // ---- run ------------------------------------------------------------------
    initial begin
        int guard = 0;
        int miss = 0;
        logic [7:0] got;

        void'($value$plusargs("CLIPW=%d", clipw));
        repeat (40) @(posedge clk);
        reset = 1'b0;
        repeat (100) @(posedge clk);

        // BIOS ch2 setup verbatim: byte-pointer clear, mode 46h (single,
        // I/O->mem, ch2), base, count, unmask.
        dmac_wr(4'hC, 8'h00);                    // clear byte pointer
        dmac_wr(4'hB, 8'h46);                    // mode: single, write, ch2
        dmac_wr(4'h4, FILL_BASE[7:0]);           // base low
        dmac_wr(4'h4, FILL_BASE[15:8]);          // base high
        dmac_wr(4'h5, (FILL_LEN-1) & 8'hFF);     // count low
        dmac_wr(4'h5, 8'((FILL_LEN-1) >> 8));    // count high
        dmac_wr(4'hA, 8'h02);                    // unmask ch2
        repeat (8) @(posedge clk);               // let the mask write land
        if (u_dmac.u_Priority_Encoder.mask_register != 4'b1011)
            $display("  mask_register=%b after unmask (want 1011)",
                     u_dmac.u_Priority_Encoder.mask_register);
        check(u_dmac.u_Timing_And_Control.transfer_mode[2] == 2'b01,
              "mode set ch2 = single");

        // The fill: DRQ up, bytes stream until the count exhausts (TC).
        // Wait for SDRAM init first -- on the metal the FDC fill runs long
        // after the controller is up; losses inside the init stall are a
        // bench artifact, not the bug under test.
        while (!u_ram.u_sdram.u_mp.init_done) @(posedge clk);
        want_drq = 1'b1;
        guard = 0;
        while (memw_pulses < FILL_LEN && guard < 40_000_000) begin
            @(posedge clk); guard++;
        end
        $display("  fill done: pulses=%0d guard=%0d wc_seen=%0d wr_accept=%0d sdr_writes=%0d",
                 memw_pulses, guard, wc_seen, wr_accept, sdr_writes);
        check(memw_pulses == FILL_LEN, "all strobe pulses issued");

        // Let the tail drain, then read every byte back through the bus.
        want_drq = 1'b0;
        repeat (5000) @(posedge clk);

        for (int i = 0; i < FILL_LEN; i++) begin
            cpu_read(FILL_BASE + i, got);
            if (got !== (8'hA5 ^ 8'(FILL_BASE + i))) begin
                if (miss < 40)
                    $display("  MISS addr=%05x got=%02x want=%02x peek=%04x",
                             FILL_BASE + i, got, 8'hA5 ^ 8'(FILL_BASE + i),
                             sdr.peek(FILL_BASE + i));
                miss++;
            end
        end
        $display("  landed mismatches: %0d / %0d", miss, FILL_LEN);
        $display("  ram_dbg2=%08x (st=%0d wr=%0b addr=%05x lost=%0d)  ram_dbg3.blocked=%0d parks=%0d",
                 ram_dbg2, ram_dbg2[31:29], ram_dbg2[28],
                 ram_dbg2[27:8], ram_dbg2[7:0], ram_dbg3[23:16], ram_dbg3[15:0]);
        check(miss == 0, "every filled byte landed in SDRAM");

        if (errors == 0)
            $display("=== PASS tb_ram_dma_fill ===");
        else
            $display("=== FAIL tb_ram_dma_fill (%0d errors, %0d lost bytes) ===",
                     errors, miss);
        $finish;
    end

    // Watchdog
    initial begin
        #400_000_000;
        $display("FAIL tb_ram_dma_fill (timeout: pulses=%0d drops=%0d)",
                 memw_pulses, ram_dbg2[7:0]);
        $finish;
    end

endmodule
