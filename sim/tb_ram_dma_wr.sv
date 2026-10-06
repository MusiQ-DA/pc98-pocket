//
// tb_ram_dma_wr — uPD71071-style fixed-width memory_write_n pulses into RAM.sv.
//
// The CPU holds its write strobe until memory_access_ready stretches the
// cycle; the DMA controller does not -- memory_write_n is a fixed pulse and
// the byte moves on whether the RAM accepted it or not. On hardware this
// dropped ~1 in 9 bytes of a floppy-sector DMA fill, leaving pre-existing
// memory untouched (proved by pre-dirtying with 0xFF: mismatches were all
// stale 0xFF, never injected data).
//
// This bench issues fixed-width write strobes at a configurable period with
// no ready handshake and checks every byte lands. SW defines the launch
// command itself; the queue in RAM.sv has to carry it past the collision.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_ram_dma_wr;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

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
        .analog_mode(1'b0), .word_access(1'b0),
        .internal_data_bus_hi(8'h00), .data_bus_out_hi(),
        .gvram_page1_flag(1'b0),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .no_command_state(no_command_state),
        .memory_access_ready(memory_access_ready),
        .access_complete(access_complete),
        .ram_address_select_n(ram_address_select_n),
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
        .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0), .vram_rd_wait_cycle(4'h0), .vram_wr_wait_cycle(4'h0),
        .ramimg_req(1'b0), .ramimg_we(1'b0), .ramimg_addr(24'h0),
        .ramimg_len(4'h0), .ramimg_wdata(16'h0000),
        .ramimg_ack(), .ramimg_rvalid(), .ramimg_rdata(), .ramimg_done()
    );

    sdram_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                  .T_RAS(2), .T_RC(3), .T_REF(335)
                  ,.PHYSICAL_DQ(1'b1)
                  ) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    int errors = 0;
    int dropped = 0;
    int parks = 0, parks_full = 0, served = 0;
    always @(posedge clock) begin
        if (!reset && dut.new_write_strobe)
            parks++;
        if (!reset && dut.write_command && dut.state != 0 && dut.wc_pend)
            parks_full++;
        if (!reset && dut.state == 0 && dut.next_state == 1)
            served++;
        if (!reset && dut.write_strobe_fell && !dut.wr_covered)
            $display("  UNCOV fall @%05h st=%0d data=%02h pend=%b/%b acc_a=%05h acc_d=%02h t=%0t",
                     dut.latch_address, dut.state, dut.internal_data_bus,
                     dut.wc_pend, dut.wc_pend2, dut.accept_address,
                     dut.accept_data, $time);
    end

    // 71071-style write: the strobe is asserted and released when the READY
    // chain drops dma_ready -- which is any COMPLETE_RAM_RW, including one
    // belonging to a previous byte. That premature release is exactly what
    // orphaned the write on hardware; the parking slot has to catch it.
    // `gap` is the dead time before the next byte (the S1-S3 preamble).
    task automatic dma_write(input int addr, input logic [7:0] d,
                             input int hold, input int gap);
        int guard;
        address = 20'(addr);
        internal_data_bus = d;
        no_command_state = 0;
        memory_write_n = 0;
        repeat (hold) @(posedge clock);
        guard = 0;
        while (!memory_access_ready && guard < 2000) begin
            @(posedge clock); guard++;
        end
        memory_write_n = 1;
        no_command_state = 1;
        repeat (gap) @(posedge clock);
    endtask

    // CPU readback: strobe held until memory_access_ready, like a real bus
    // master that waits. The strobe is held for a few clocks first so the
    // wait below can't slip out through the not-yet-started ready window.
    task automatic cpu_read(input int addr, output logic [7:0] q);
        int guard;
        address = 20'(addr);
        internal_data_bus = 8'h00;
        no_command_state = 0;
        memory_read_n = 0;
        repeat (4) @(posedge clock);
        guard = 0;
        while (!memory_access_ready && guard < 4000) begin
            @(posedge clock); guard++;
        end
        if (guard >= 4000) $display("  READ TIMEOUT @%05h", addr);
        q = data_bus_out;
        memory_read_n = 1;
        no_command_state = 1;
        repeat (2) @(posedge clock);
    endtask

    task automatic cpu_write(input int addr, input logic [7:0] d);
        int guard;
        address = 20'(addr);
        internal_data_bus = d;
        no_command_state = 0;
        memory_write_n = 0;
        repeat (4) @(posedge clock);
        guard = 0;
        while (!memory_access_ready && guard < 4000) begin
            @(posedge clock); guard++;
        end
        if (guard >= 4000) $display("  WRITE TIMEOUT @%05h", addr);
        memory_write_n = 1;
        no_command_state = 1;
        repeat (2) @(posedge clock);
    endtask

    // Deadlock regression: a write strobe asserted inside a read's
    // COMPLETE window parks, and its twin is held on the bus while the
    // parked copy runs. The served strobe is the slot's, so flag-only
    // ready never answers the twin -- on hardware this wedged the guest
    // in POST. Ready must come from the operand match.
    task automatic read_then_held_write(input int raddr, input int waddr,
                                        input logic [7:0] d);
        int guard;
        address = raddr;
        internal_data_bus = 8'h00;
        no_command_state = 0;
        memory_read_n = 0;
        repeat (4) @(posedge clock);
        guard = 0;
        while (!memory_access_ready && guard < 4000) begin
            @(posedge clock); guard++;
        end
        // The FSM sits in the read's COMPLETE while the strobe is up;
        // swapping strobes lands the write inside that window -> park.
        address = waddr;
        internal_data_bus = d;
        memory_read_n = 1;
        memory_write_n = 0;
        repeat (4) @(posedge clock);
        guard = 0;
        while (!memory_access_ready && guard < 4000) begin
            @(posedge clock); guard++;
        end
        if (guard >= 4000) begin
            errors++;
            $display("  HELD-TWIN DEADLOCK @%05h", waddr);
        end
        memory_write_n = 1;
        no_command_state = 1;
        repeat (2) @(posedge clock);
    endtask

    function automatic logic [7:0] pat(input int a);
        pat = 8'((a * 8'h9D) ^ 8'h5A);
    endfunction

    logic [7:0] got;
    int n;

    initial begin
        $display("=== DMA fixed-strobe write test (sdram_shim/mp) ===");
        repeat (8) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);
        $display("init done");

        // Pre-dirty the range with 0xFF -- a dropped write must show up as
        // stale fill, identical to the hardware experiment.
        for (int i = 0; i < 512; i++)
            cpu_write(32'h1FE00 + i, 8'hFF);
        $display("pre-dirty done");

        // Fixed-pulse burst at a DMA-like cadence. The gap sweeps phases so
        // strobes land in every FSM window, including the one-cycle
        // COMPLETE-release gap that orphaned writes on hardware.
        for (int i = 0; i < 512; i++)
            dma_write(32'h1FE00 + i, pat(i), 4, i % 4);
        $display("burst done");

        // Give any parked write time to drain, then read back.
        repeat (64) @(posedge clock);
        n = 0;
        for (int i = 0; i < 512; i++) begin
            cpu_read(32'h1FE00 + i, got);
            if (got !== pat(i)) begin
                dropped++;
                if (n < 16) begin
                    $display("  @%05h: got %02h want %02h%s",
                             32'h1FE00 + i, got, pat(i),
                             (got === 8'hFF) ? "  (stale FF)" : "");
                    n++;
                end
            end
        end
        $display("burst: %0d/512 dropped (parks=%0d full-strobes=%0d served=%0d)",
                 dropped, parks, parks_full, served);

        // A slower cadence must be lossless even without the queue.
        for (int i = 0; i < 64; i++)
            cpu_write(32'h20000 + i, 8'hFF);
        for (int i = 0; i < 64; i++)
            dma_write(32'h20000 + i, pat(i + 128), 4, 24);
        repeat (64) @(posedge clock);
        for (int i = 0; i < 64; i++) begin
            cpu_read(32'h20000 + i, got);
            if (got !== pat(i + 128)) begin
                errors++;
                if (errors < 8)
                    $display("  slow MISMATCH @%05h: got %02h want %02h",
                             32'h20000 + i, got, pat(i + 128));
            end
        end
        $display("slow burst: %0d/64 dropped", errors);

        // CPU-held writes must still work (regression check).
        for (int i = 0; i < 32; i++)
            cpu_write(32'h20400 + i, pat(i + 200));
        for (int i = 0; i < 32; i++) begin
            cpu_read(32'h20400 + i, got);
            if (got !== pat(i + 200)) begin
                errors++;
                $display("  cpu MISMATCH @%05h: got %02h want %02h",
                         32'h20400 + i, got, pat(i + 200));
            end
        end

        // Held-twin: each write parks behind a read's COMPLETE and its
        // strobe is held on the bus until ready -- the slot's copy must
        // release it via the operand match, not a live flag.
        for (int i = 0; i < 16; i++)
            cpu_write(32'h20600 + i, 8'hFF);
        for (int i = 0; i < 16; i++)
            read_then_held_write(32'h1FE00 + (i & 7), 32'h20600 + i, pat(i + 64));
        repeat (32) @(posedge clock);
        for (int i = 0; i < 16; i++) begin
            cpu_read(32'h20600 + i, got);
            if (got !== pat(i + 64)) begin
                errors++;
                $display("  twin MISMATCH @%05h: got %02h want %02h",
                         32'h20600 + i, got, pat(i + 64));
            end
        end

        if (dropped == 0 && errors == 0)
            $display("=== PASS ===");
        else
            $display("=== FAIL: %0d dropped + %0d errors ===", dropped, errors);
        $finish;
    end

endmodule
