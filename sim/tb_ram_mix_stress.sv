//
// tb_ram_mix_stress -- randomized DMA/CPU write mix through RAM.sv.
//
// SuperDepth at turbo lost single bytes of floppy DMA fills on the metal:
// a DOS buffer byte stayed at its previous contents while its neighbours
// landed. tb_ram_dma_wr covers a DMA-only stream; here the uPD71071's
// early-released strobes interleave with CPU byte/word reads and writes
// (strobes held to ready) at random gaps and random addresses in a small
// window, with port-D display bursts stealing the SDRAM. Every read checks
// a shadow model, so a lost write shows at the access that misses it.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ram_mix_stress;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    logic        word_access = 1'b0;
    logic [7:0]  data_hi = 8'h00;
    logic [7:0]  data_bus_out_hi;
    logic        gv_req = 1'b0;
    logic  [3:0] gv_len = 4'd8;
    int          gv_rate = 64;
    wire         gv_ack, gv_done;

    logic [19:0] address = '0;
    logic [7:0]  internal_data_bus = '0;
    logic [7:0]  data_bus_out;
    logic        memory_read_n = 1, memory_write_n = 1;
    logic        no_command_state = 1;
    logic        memory_access_ready, access_complete, ram_address_select_n;
    logic        initilized_sdram;

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;

    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};

    RAM dut (
        .clock(clock), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(address), .internal_data_bus(internal_data_bus),
        .data_bus_out(data_bus_out),
        .analog_mode(1'b0), .prefetch_len   (4'd0),
        .pf_beat_v      (),
        .pf_beat_dat    (),
        .word_access(word_access),
        .internal_data_bus_hi(data_hi), .data_bus_out_hi(data_bus_out_hi),
        .gvram_page1_flag(1'b0),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .no_command_state(no_command_state),
        .memory_access_ready(memory_access_ready),
        .access_complete(access_complete),
        .ram_address_select_n(ram_address_select_n),
        .write_taken(),
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
        .gv_rd_req(gv_req), .gv_rd_addr(24'h300000), .gv_rd_len(gv_len),
        .gv_rd_ack(gv_ack), .gv_rd_valid(), .gv_rd_data(), .gv_rd_done(gv_done),
        .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0), .vram_rd_wait_cycle(4'h0), .vram_wr_wait_cycle(4'h0),
        .ramimg_req(1'b0), .ramimg_we(1'b0), .ramimg_addr(24'h0),
        .ramimg_len(4'h0), .ramimg_wdata(16'h0000),
        .ramimg_ack(), .ramimg_rvalid(), .ramimg_rdata(), .ramimg_done(),
        .cachef_req(1'b0), .cachef_we(1'b0), .cachef_addr(24'h0),
        .cachef_len(4'd0), .cachef_wdata0(16'h0), .cachef_wdata1(16'h0),
        .cachef_ack(), .cachef_rvalid(), .cachef_rdata(), .cachef_done(),
        .ram_wr_snoop_v(), .ram_wr_snoop_addr(), .ram_wr_snoop_len()
    );

    sdram_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                  .T_RAS(2), .T_RC(3), .T_REF(335)
                  ,.PHYSICAL_DQ(1'b1)
                  ) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );


    int cl_from = -1, cl_to = -1;
    always @(posedge clock) if (nops >= cl_from && nops <= cl_to && cl_from >= 0)
        $display("    op%0d st=%0d wc=%b la=%05h d=%02h%02h w=%b | p1=%b %05h:%02h%02h/%b p2=%b %05h:%02h p3=%b %05h:%02h cap=%b %05h:%02h | acc=%05h:%02h%02h/%b dup=%b cov=%b/%b rdy=%b",
          nops, dut.state, dut.write_command, dut.latch_address[19:0], dut.internal_data_bus_hi, dut.internal_data_bus, dut.word_now,
          dut.wc_pend, dut.pend_address[19:0], dut.pend_data_hi, dut.pend_data, dut.pend_word,
          dut.wc_pend2, dut.pend2_address[19:0], dut.pend2_data, dut.wc_pend3, dut.pend3_address[19:0], dut.pend3_data,
          dut.cap_valid, dut.cap_address[19:0], dut.cap_data,
          dut.accept_address[19:0], dut.accept_data_hi, dut.accept_data, dut.accept_word, dut.dup_covered, dut.wr_covered, dut.cov_same, memory_access_ready);

    // port-D pressure: a display burst every so often, as the GVRAM fetch
    always @(posedge clock) begin
        if (reset) gv_req <= 1'b0;
        else if (gv_ack) gv_req <= 1'b0;
        else if (!gv_req && ($urandom % gv_rate == 0)) gv_req <= 1'b1;
    end

    localparam int BASE = 32'h07300;
    localparam int SPAN = 64;
    logic [7:0] shadow [0:SPAN-1];
    int errors = 0, nops = 0, ndma = 0;
    int tr_off = -1, tr_from = 0;

    task automatic idle_gap(input int n);
        memory_write_n = 1; memory_read_n = 1; no_command_state = 1;
        word_access = 0;
        repeat (n) @(posedge clock);
    endtask

    task automatic dma_write(input int off, input logic [7:0] d, input int hold);
        int guard;
        address = 20'(BASE + off);
        internal_data_bus = d;
        word_access = 0;
        no_command_state = 0;
        memory_write_n = 0;
        repeat (hold) @(posedge clock);
        guard = 0;
        while (!memory_access_ready && guard < 2000) begin
            @(posedge clock); guard++;
        end
        memory_write_n = 1;
        no_command_state = 1;
        if (off == tr_off && nops >= tr_from) $display("  t=%0t op %0d DMA  wr %02h hold=%0d", $time, nops, d, hold);
        shadow[off] = d;
        ndma++;
    endtask

    task automatic cpu_write(input int off, input logic [7:0] d,
                             input logic [7:0] dh, input bit w);
        int guard;
        address = 20'(BASE + off);
        internal_data_bus = d;
        data_hi = dh;
        word_access = w;
        no_command_state = 0;
        memory_write_n = 0;
        repeat (2) @(posedge clock);
        guard = 0;
        while (!memory_access_ready && guard < 4000) begin
            @(posedge clock); guard++;
        end
        if (guard >= 4000) begin errors++; $display("  WRITE TIMEOUT"); end
        memory_write_n = 1;
        no_command_state = 1;
        word_access = 0;
        if ((off == tr_off || (w && off+1 == tr_off)) && nops >= tr_from) $display("  t=%0t op %0d CPU  wr %02h%02h w=%0d @+%0d", $time, nops, dh, d, w, off);
        shadow[off] = d;
        if (w) shadow[off+1] = dh;
    endtask

    task automatic cpu_read(input int off, input bit w);
        int guard;
        address = 20'(BASE + off);
        word_access = w;
        no_command_state = 0;
        memory_read_n = 0;
        repeat (2) @(posedge clock);
        guard = 0;
        while (!memory_access_ready && guard < 4000) begin
            @(posedge clock); guard++;
        end
        if (guard >= 4000) begin errors++; $display("  READ TIMEOUT"); end
        if ((off == tr_off || (w && off+1 == tr_off)) && nops >= tr_from) $display("  t=%0t op %0d CPU  rd %02h%02h w=%0d @+%0d", $time, nops, data_bus_out_hi, data_bus_out, w, off);
        if (data_bus_out !== shadow[off] || (w && data_bus_out_hi !== shadow[off+1])) begin
            errors++;
            if (errors < 20)
                $display("  MISMATCH op %0d @%05h w=%0d got %02h%02h want %02h%02h t=%0t",
                         nops, BASE+off, w, w ? data_bus_out_hi : 8'h00, data_bus_out,
                         w ? shadow[off+1] : 8'h00, shadow[off], $time);
            shadow[off] = data_bus_out;          // resync, keep counting
            if (w) shadow[off+1] = data_bus_out_hi;
        end
        memory_read_n = 1;
        no_command_state = 1;
        word_access = 0;
    endtask

    int seed, N, k, off;
    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        if (!$value$plusargs("n=%d", N)) N = 200000;
        if (!$value$plusargs("tr_off=%d", tr_off)) tr_off = -1;
        if (!$value$plusargs("tr_from=%d", tr_from)) tr_from = 0;
        if (!$value$plusargs("cl_from=%d", cl_from)) cl_from = -1;
        if (!$value$plusargs("gvrate=%d", gv_rate)) gv_rate = 64;
        begin int l; if ($value$plusargs("gvlen=%d", l)) gv_len = 4'(l); end
        if (!$value$plusargs("cl_to=%d", cl_to)) cl_to = -1;
        void'($urandom(seed));
        repeat (8) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);
        for (int i = 0; i < SPAN; i++) cpu_write(i, 8'(i * 7 + 3), 8'h00, 0);
        for (nops = 0; nops < N; nops++) begin
            k = $urandom % 16;
            off = $urandom % SPAN;
            if (k < 7) begin
                // a DMA run: several consecutive bytes, the FDC fill
                int run = 1 + $urandom % 6;
                for (int j = 0; j < run && off + j < SPAN; j++) begin
                    dma_write(off + j, 8'($urandom), 1 + $urandom % 6);
                    idle_gap($urandom % 5);
                end
            end else if (k < 10) begin
                cpu_read(off & ~(($urandom % 2) ? 1 : 0) & (SPAN-2) | (off & 1) & 0, 0);
            end else if (k < 12) begin
                off = off & (SPAN - 2);
                cpu_read(off, 1);
            end else if (k < 14) begin
                cpu_write(off, 8'($urandom), 8'h00, 0);
            end else begin
                off = off & (SPAN - 2);
                cpu_write(off, 8'($urandom), 8'($urandom), 1);
            end
            idle_gap($urandom % 4);
        end
        repeat (64) @(posedge clock);
        for (int i = 0; i < SPAN; i++) cpu_read(i, 0);
        $display("ops=%0d dma=%0d errors=%0d", N, ndma, errors);
        if (errors == 0) $display("=== PASS tb_ram_mix_stress ===");
        else $display("=== FAIL tb_ram_mix_stress ===");
        $finish;
    end

endmodule
