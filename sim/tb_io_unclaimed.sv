//
// tb_io_unclaimed -- an IN from a port nobody claims must read 0xFF, even
// right after an OUT to it.
//
// SuperDepth's OPN probe (DEPTH.EXE module E384): OUT 188h,0 / OUT 18Ah,7Bh /
// NOP x4 / IN AL,18Ah / STI / CMP AL,7Bh. With no OPNA on the bus the IN
// must come back 0xFF (np21w io/iocore.c definp8). On metal (run #1028,
// Turbo + cache) the probe passed: the IN echoed the OUT's data and the
// game then spun on the OPN busy flag forever.
//
// The path is the shipping one end to end: z86 (+ its cache on port F) ->
// cpu_bus_bridge -> BUS_ARBITER (i8288 + its data mux) -> READY, with the
// Chipset's data branches in front of the arbiter's data_bus_ext: a memory
// read answers from the flat memory below, an INTA with the vector, and
// anything else -- the unclaimed port -- falls through to core_top's
// external lane, which idles at 0xFF (bios_write_data outside a ROM load).
//
// The program is sim/z86_tests/raw_opn_probe.hex: 400 rounds of the probe
// under a periodic interrupt whose handler is the PC-98 EOI shape. It
// counts every IN that did not read 0xFF at 0602h. Run at each CE rate
// (+speed=0..3, cache on at 3 like core_top) and a few IRQ periods.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_io_unclaimed;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic reset = 1'b1;

    // ---- CE train -----------------------------------------------------------
    wire  clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire  cycle_accrate, shift_read_timing, vram_wait_en;
    wire  [7:0] ccc_div, ccc_dec;
    wire  [1:0] ram_rd_wait, ram_wr_wait;
    logic [1:0] clk_select_r = 2'b11;
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
        .vram_wait_en                       (vram_wait_en)
    );

    // ---- flat memory + port F (the cache's SDRAM port) ----------------------
    logic [7:0] mem [0:1048575];
    wire        f_req, f_we;
    wire [23:0] f_addr;
    wire [3:0]  f_len;
    wire [15:0] f_wd0, f_wd1;
    logic       f_ack = 1'b0, f_rvalid = 1'b0, f_done = 1'b0;
    logic [15:0] f_rdata = 16'h0;
    // +flat=N: port-F grant latency in clocks (+flatrand: 1..N at random).
    int flat = 4, flat_rand = 0;
    initial begin
        void'($value$plusargs("flat=%d", flat));
        flat_rand = $test$plusargs("flatrand");
    end
    always @(posedge clk) begin : port_f
        f_ack <= 1'b0; f_rvalid <= 1'b0; f_done <= 1'b0;
        if (f_req && !f_ack) begin
            repeat (flat_rand ? $urandom_range(1, flat) : flat) @(posedge clk);
            f_ack <= 1'b1;
            @(posedge clk); f_ack <= 1'b0;
            repeat (2) @(posedge clk);
            if (f_we) begin
                mem[f_addr[19:0]] <= f_wd0[7:0];
                if (f_len == 4'd1) mem[f_addr[19:0] + 20'd1] <= f_wd1[7:0];
                @(posedge clk);
            end else begin
                for (int i = 0; i <= f_len; i++) begin
                    f_rvalid <= 1'b1; f_rdata <= {8'h00, mem[f_addr[19:0] + 20'(i)]};
                    @(posedge clk);
                end
                f_rvalid <= 1'b0;
            end
            f_done <= 1'b1;
        end
    end

    // ---- z86 ----------------------------------------------------------------
    wire        zet_clk, z86_ce;
    wire [19:1] zwb_adr;
    wire [1:0]  zwb_sel;
    wire        zwb_we, zwb_tga, zwb_stb, zwb_cyc, zwb_ack, zwb_inta;
    wire [15:0] zwb_dat_o, zwb_dat_i;
    wire [19:0] zet_pc;
    wire        z86_halted;
    logic       intr = 1'b0;
    logic       sn_v = 1'b0;
    logic [23:0] sn_addr = 24'h0;
    logic [3:0]  sn_len = 4'h0;

    z86 u_cpu (
        .clk(zet_clk), .reset(reset), .clk_free(clk), .ce(z86_ce),
        .cache_en(clk_select_r == 2'b11),
        .bios_shadow(1'b0), .bios_protect(1'b0),
        .f_req(f_req), .f_we(f_we), .f_addr(f_addr), .f_len(f_len),
        .f_wdata0(f_wd0), .f_wdata1(f_wd1), .f_ack(f_ack),
        .f_rvalid(f_rvalid), .f_rdata(f_rdata), .f_done(f_done),
        .sn_v(sn_v), .sn_addr(sn_addr), .sn_len(sn_len),
        .dbg_watch_a(20'h0), .dbg_sn_kills(),
        .wb_adr_o(zwb_adr), .wb_sel_o(zwb_sel), .wb_we_o(zwb_we),
        .wb_tga_o(zwb_tga), .wb_dat_o(zwb_dat_o), .wb_stb_o(zwb_stb),
        .wb_cyc_o(zwb_cyc), .wb_ack_i(zwb_ack), .wb_dat_i(zwb_dat_i),
        .wb_tgc_i(intr), .wb_tgc_o(zwb_inta),
        .pc(zet_pc), .dbg_ds(), .dbg_regs(), .dbg_halted(z86_halted),
        .dbg_stop(1'b0), .dbg_stopped(), .dbg_next_ip(),
        .dbg_wr_v(), .dbg_wr_a0(), .dbg_wr_two()
    );

    // ---- the bridge -------------------------------------------------------
    wire [2:0]   processor_status;
    wire [19:0]  ad_out;
    wire [7:0]   cpu_data_bus, cpu_data_bus_hi;
    wire         word_access, lock_n;
    wire [7:0]   data_bus, data_bus_hi;
    wire         processor_ready;
    wire         address_enable_n;
    wire         memory_write_n;

    cpu_bus_bridge #(.REQ_SETTLE(0)) u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .pace_286          (1'b1),
        .reset             (reset),
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
        .nmia              (1'b0),
        .processor_status  (processor_status),
        .ad_out            (ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (lock_n),
        .analog_mode       (1'b0),
        .word_access       (word_access),
        .pf_req_len        (),
        .pf_beat_v         (1'b0),
        .pf_beat_dat       (8'h00),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (data_bus_hi),
        .data_bus          (data_bus),
        .processor_ready   (processor_ready),
        .address_enable_n  (address_enable_n),
        .sdram_wr_taken    (~memory_write_n),
        .sdram_rd_ready    (1'b1),
        .pause_core        (1'b0),
        .throttle          (1'b0),
        .pf_disable        (1'b1),
        .pf_nofill         (1'b0),
        .pf_nofillm        (1'b0),
        .pf_nohit          (1'b0),
        .pf_wkill          (1'b0),
        .pf_bkill          (1'b0),
        .bus_mem_write_n   (memory_write_n),
        .sn_v              (1'b0),
        .sn_addr           (24'd0),
        .sn_len            (4'd0),
        .bios_shadow_flag  (1'b0),
        .biu_done          (),
        .zet_edge_o        (z86_ce),
        .dbg               (),
        .dbg_inta          (),
        .dbg_w             ()
    );

    // +grant=<N>: an external bus master (core_top's loader, which asks for
    // the bus whenever an APF data-slot transfer runs) requests the bus at
    // random, ~1 in N clocks, and holds it for a random stretch.
    int   grant_n = 0;
    logic ext_req = 1'b0;
    int   ext_hold = 0;
    initial void'($value$plusargs("grant=%d", grant_n));
    always @(posedge clk) begin
        if (reset || grant_n == 0) ext_req <= 1'b0;
        else if (!ext_req) begin
            if ($urandom_range(0, grant_n - 1) == 0) begin
                ext_req  <= 1'b1;
                ext_hold <= $urandom_range(1, 40);
            end
        end else if (ext_hold > 0) ext_hold <= ext_hold - 1;
        else ext_req <= 1'b0;
    end

    // ---- arbiter + ready, as Chipset wires them ---------------------------
    wire [19:0] address;
    wire        address_direction, address_latch_enable;
    wire [7:0]  internal_data_bus;
    wire        data_bus_direction;
    wire        io_read_n, io_write_n, memory_read_n;
    wire        no_command_state, dma_ready, dma_wait_n, inta_n;
    wire [3:0]  dma_ack_n;
    wire        tc_n, ptr_n;
    logic [7:0] data_bus_ext;

    READY u_ready (
        .clock               (clk),
        .cpu_ce_posedge      (cpu_ce_posedge),
        .cpu_ce_negedge      (cpu_ce_negedge),
        .reset               (reset),
        .processor_ready     (processor_ready),
        .dma_ready           (dma_ready),
        .dma_wait_n          (dma_wait_n),
        .io_channel_ready    (1'b1),
        .io_read_n           (io_read_n),
        .io_write_n          (io_write_n),
        .memory_read_n       (memory_read_n),
        .dma0_acknowledge_n  (dma_ack_n[0]),
        .address_enable_n    (address_enable_n),
        .dbg                 ()
    );

    BUS_ARBITER u_arb (
        .clock                           (clk),
        .cpu_ce_posedge                  (cpu_ce_posedge),
        .cpu_ce_negedge                  (cpu_ce_negedge),
        .reset                           (reset),
        .cpu_address                     (ad_out),
        .cpu_data_bus                    (cpu_data_bus),
        .processor_status                (processor_status),
        .processor_lock_n                (lock_n),
        .processor_transmit_or_receive_n (ptr_n),
        .dma_ready                       (dma_ready),
        .dma_wait_n                      (dma_wait_n),
        .interrupt_acknowledge_n         (inta_n),
        .dma_chip_select_n               (1'b1),
        .dma_page_chip_select_n          (1'b1),
        .address                         (address),
        .address_ext                     (20'h0),
        .address_direction               (address_direction),
        .data_bus_ext                    (data_bus_ext),
        .internal_data_bus               (internal_data_bus),
        .data_bus_direction              (data_bus_direction),
        .address_latch_enable            (address_latch_enable),
        .io_read_n                       (io_read_n),
        .io_read_n_ext                   (1'b1),
        .io_read_n_direction             (),
        .io_write_n                      (io_write_n),
        .io_write_n_ext                  (1'b1),
        .io_write_n_direction            (),
        .memory_read_n                   (memory_read_n),
        .memory_read_n_ext               (1'b1),
        .memory_read_n_direction         (),
        .memory_write_n                  (memory_write_n),
        .memory_write_n_ext              (1'b1),
        .memory_write_n_direction        (),
        .no_command_state                (no_command_state),
        .ext_access_request              (ext_req),
        .dma_request                     (4'hF),
        .dma_acknowledge_n               (dma_ack_n),
        .address_enable_n                (address_enable_n),
        .terminal_count_n                (tc_n),
        .dbg                             (),
        .dbg_dma                         (),
        .watch_addr                      (20'hFFFFF),
        .dbg_dma3                        (),
        .dbg_w                           (),
        .dbg_w2                          ()
    );

    // The Chipset's data branches in front of the arbiter: memory answers a
    // memory read, the PIC an acknowledge; an I/O read nobody claims falls
    // through to the external lane (Chipset's last else), which idles high.
    logic [7:0] ext_lane = 8'hFF;
    always_comb begin
        if (~inta_n)
            data_bus_ext = 8'h20;
        else if (~memory_read_n)
            data_bus_ext = mem[address];
        else if (data_bus_direction)
            data_bus_ext = ext_lane;
        else
            data_bus_ext = 8'hFF;
    end
    assign data_bus    = internal_data_bus;
    assign data_bus_hi = mem[{address[19:1], 1'b1}];

    // Memory writes through the bus (cache off, or uncached ranges).
    logic mw_d = 1'b1;
    always @(posedge clk) begin
        mw_d <= memory_write_n;
        sn_v <= 1'b0;
        if (~memory_write_n && mw_d) begin
            mem[address] <= internal_data_bus;
            if (word_access && ~address_enable_n)
                mem[address + 20'd1] <= cpu_data_bus_hi;
            sn_v    <= 1'b1;
            sn_addr <= {4'h0, address};
            sn_len  <= 4'd1;
        end
    end

    // Every I/O read the bus completes: what the bridge captured for it.
    int io_rd_n = 0, io_rd_bad = 0;
    always @(posedge clk)
        if (u_bridge.bstate == 2'd1 && u_bridge.cur_bs == 3'd1 /* BS_IOR */
            && u_bridge.pair_accept && cpu_ce_posedge && u_bridge.bus_ours) begin
            io_rd_n++;
            if (data_bus !== 8'hFF) begin
                io_rd_bad++;
                if (io_rd_bad <= 8)
                    $display("  %t IN %04x captured %02x (cpu_data_bus %02x, DT/R %b DEN %b)",
                             $time, ad_out[15:0], data_bus, cpu_data_bus,
                             u_arb.direction_transmit_or_receive_n, u_arb.data_enable);
            end
        end

    // The arbiter driving the CPU's write byte while a read strobe is out.
    int echo_clk = 0;
    always @(posedge clk)
        if ((~io_read_n | ~memory_read_n) && u_arb.data_enable
            && u_arb.direction_transmit_or_receive_n) begin
            echo_clk++;
            if (echo_clk <= 4)
                $display("  %t read strobe with DT/R=1 DEN=1: bus %02x (ior %b mr %b)",
                         $time, internal_data_bus, io_read_n, memory_read_n);
        end

    // +irq=<clocks>: INTR every that many clocks, held until the acknowledge.
    int irq_period = 0, irq_cnt = 0;
    initial void'($value$plusargs("irq=%d", irq_period));
    always @(posedge clk) begin
        if (zwb_inta) intr <= 1'b0;
        else if (!reset && irq_period != 0) begin
            irq_cnt <= irq_cnt + 1;
            if (irq_cnt + 1 >= irq_period) begin irq_cnt <= 0; intr <= 1'b1; end
        end
    end

    logic [7:0] pbuf [0:4095];
    string prog;
    initial begin
        for (int i = 0; i < 1048576; i++) mem[i] = 8'h90;
        for (int i = 0; i < 4096; i++) pbuf[i] = 8'hF4;
        if (!$value$plusargs("prog=%s", prog)) prog = "sim/z86_tests/raw_opn_probe.hex";
        $readmemh(prog, pbuf);
        for (int i = 0; i < 4096; i++) mem[20'h00400 + i] = pbuf[i];
        mem[20'hFFFF0] = 8'hEA; mem[20'hFFFF1] = 8'h00; mem[20'hFFFF2] = 8'h04;
        mem[20'hFFFF3] = 8'h00; mem[20'hFFFF4] = 8'h00;
        repeat (40) @(posedge clk);
        reset = 1'b0;
    end

    initial begin
        int rounds, bad;
        longint t;
        t = 0;
        while (!z86_halted && t < 64'd40_000_000) begin @(posedge clk); t++; end
        repeat (20) @(posedge clk);
        rounds = {mem[20'h601], mem[20'h600]};
        bad    = {mem[20'h603], mem[20'h602]};
        $display("echo window clocks: %0d", echo_clk);
        $display("speed=%0d irq=%0d: %0d rounds, %0d bad IN (last %02x); bus: %0d I/O reads, %0d not FF",
                 clk_select_r, irq_period, rounds, bad, mem[20'h604], io_rd_n, io_rd_bad);
        if (rounds == 400 && bad == 0 && io_rd_bad == 0)
            $display("=== PASS tb_io_unclaimed ===");
        else
            $display("=== FAIL tb_io_unclaimed ===");
        $finish;
    end

endmodule

`default_nettype wire
