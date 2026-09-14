//
// tb_v30_bridge -- the bridge between the nuV30 and the 8288 world, alone.
//
// What this bench proves, by running a real V30 program through the real
// KF8288 and the real READY module:
//
//   * a word write at an even address lands as TWO byte cycles, even
//     address first, with the low lane's data on the even byte and the high
//     lane's on the odd one (the adjacency assertions);
//   * a word read at an even address returns {odd, even} to the core and
//     the program reads back what it wrote (the marker bytes);
//   * odd byte reads and writes take the upper lane and come back right;
//   * the V30's own odd-address word split (two byte cycles the CPU issues
//     itself) passes through unharmed;
//   * INTA runs the two-pulse sequence through the 8288 into a real
//     KF8259, the vector reaches the core, and the handler runs;
//   * HLT runs through without the bridge parking on it, and the wake
//     continues after the HLT byte;
//   * with +slow=N the "memory" takes N extra chipset clocks per access:
//     the byte cycles stretch (the READY wait path) and every answer above
//     still holds;
//   * the core's CE is really gated while parked (no v30_ce pulse while
//     u_bridge.parked), which is what keeps the read capture edge after
//     the data is assembled.
//
// SPDX-License-Identifier: GPL-2.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_v30_bridge;

    // clk_chipset is 42.954545 MHz.
    logic clk = 1'b0;
    always #11.641 clk = ~clk;

    logic reset = 1'b1;

    // ---- the CE train, as core_top makes it -------------------------------
    wire  clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire  cycle_accrate, shift_read_timing;
    wire  [7:0] ccc_div, ccc_dec;
    wire  [1:0] ram_rd_wait, ram_wr_wait;
    logic biu_done;

    XT_CE_Generator u_ce (
        .clock                              (clk),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (2'b10),      // 9.54 MHz
        .cpu_clk_pin                        (clk_cpu),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .cycle_accrate                      (cycle_accrate),
        .clock_cycle_counter_division_ratio  (ccc_div),
        .clock_cycle_counter_decrement_value (ccc_dec),
        .shift_read_timing                  (shift_read_timing),
        .ram_read_wait_cycle                (ram_rd_wait),
        .ram_write_wait_cycle               (ram_wr_wait)
    );

    // ---- the CPU: nuV30, de-muxed, exactly as core_top will wire it -------
    wire  [2:0]  v30_bs;
    wire  [19:0] v30_addr;
    wire  [15:0] v30_data_o, v30_data_i;
    wire         v30_ube_n, v30_ce, v30_ready;

    v30_core u_cpu (
        .CLK        (clk),
        .CE         (v30_ce),
        .RESET      (reset),
        .READY      (v30_ready),
        .INT        (pic_int),
        .NMI        (1'b0),
        .POLL_N     (1'b1),
        .DATA_I     (v30_data_i),
        .ADDR_O     (v30_addr),
        .DATA_O     (v30_data_o),
        .STATUS_O   (),
        .QS         (),
        .BS         (v30_bs),
        .RD_N       (),
        .UBE_N      (v30_ube_n),
        .BUSLOCK_N  (),
        .SS_ADDR    ('0),
        .SS_WDATA   ('0),
        .SS_WE      (1'b0),
        .SS_RDATA   (),
        .SS_ERR     (),
        .SS_BUS_QUIET ()
    );

    // ---- the bridge under test --------------------------------------------
    wire [2:0] processor_status;
    wire [19:0] ad_out;
    wire [7:0]  cpu_data_bus;
    wire        lock_n;

    v30_cpu_bridge u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .reset             (reset),
        .v30_bs            (v30_bs),
        .v30_addr          (v30_addr),
        .v30_ube_n         (v30_ube_n),
        .v30_data_o        (v30_data_o),
        .v30_data_i        (v30_data_i),
        .v30_ready         (v30_ready),
        .v30_ce            (v30_ce),
        .processor_status  (processor_status),
        .ad_out            (ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (lock_n),
        .data_bus          (din),
        .processor_ready   (processor_ready),
        .address_enable_n  (1'b0),     // no other master in this bench
        .pause_core        (1'b0),
        .biu_done          (biu_done)
    );

    // ---- the bus controller, as the chipset wires it ----------------------
    wire mem_rd_n, mem_wr_n, adv_mem_wr_n;
    wire io_rd_n,  io_wr_n,  adv_io_wr_n;
    wire inta_n, ale, en_io, en_mem, dt_r_n, den, mce, pden;

    KF8288 u_8288 (
        .clock                           (clk),
        .cpu_ce_posedge                  (cpu_ce_posedge),
        .cpu_ce_negedge                  (cpu_ce_negedge),
        .reset                           (reset),
        .address_enable_n                (1'b0),
        .command_enable                  (1'b1),
        .io_bus_mode                     (1'b0),
        .processor_status                (processor_status),
        .enable_io_command               (en_io),
        .advanced_io_write_command_n     (adv_io_wr_n),
        .io_write_command_n              (io_wr_n),
        .io_read_command_n               (io_rd_n),
        .interrupt_acknowledge_n         (inta_n),
        .enable_memory_command           (en_mem),
        .advanced_memory_write_command_n (adv_mem_wr_n),
        .memory_write_command_n          (mem_wr_n),
        .memory_read_command_n           (mem_rd_n),
        .direction_transmit_or_receive_n (dt_r_n),
        .data_enable                     (den),
        .master_cascade_enable           (mce),
        .peripheral_data_enable_n        (pden),
        .address_latch_enable            (ale)
    );

    // core_top's address latch
    logic [19:0] cpu_address = 20'h0;
    always_ff @(posedge clk)
        if (ale) cpu_address <= ad_out;

    // ---- the READY module, the real one (this is the wait path) -----------
    wire processor_ready;
    READY u_ready (
        .clock               (clk),
        .cpu_ce_posedge      (cpu_ce_posedge),
        .cpu_ce_negedge      (cpu_ce_negedge),
        .reset               (reset),
        .processor_ready     (processor_ready),
        .dma_ready           (),
        .dma_wait_n          (1'b1),
        .io_channel_ready    (io_channel_ready),
        .io_read_n           (io_rd_n),
        .io_write_n          (io_wr_n),
        .memory_read_n       (mem_rd_n),
        .dma0_acknowledge_n  (1'b1),
        .address_enable_n    (1'b0)
    );

    // +slow=N: hold io_channel_ready low for N chipset clocks after each
    // command starts -- the "SDRAM is busy" stand-in. The bench then proves
    // the bridge's byte cycles stretch instead of losing data.
    int           slow_n = 0;
    logic [15:0]  slow_cnt = 16'd0;
    logic         command_q = 1'b0;
    initial if (!$value$plusargs("slow=%d", slow_n)) slow_n = 0;
    wire command_live = (~mem_rd_n) | (~mem_wr_n) | (~io_rd_n) | (~io_wr_n);
    always_ff @(posedge clk) begin
        if (reset) begin
            slow_cnt  <= 16'd0;
            command_q <= 1'b0;
        end else begin
            command_q <= command_live;
            if (command_live & ~command_q)
                slow_cnt <= 16'(slow_n);      // armed once, per command
            else if (slow_cnt != 16'd0)
                slow_cnt <= slow_cnt - 16'd1;
        end
    end
    wire io_channel_ready = (slow_cnt == 16'd0);

    // ---- the memory: one flat byte-wide megabyte --------------------------
    logic [7:0] mem [0:1048575];

    wire [7:0] pic_dout;
    wire       pic_data_bus_io;
    wire       pic_int;

    // The 8259 the INTA test talks to: master at 0x00/0x02, single, vectors
    // at 0x48.
    wire pic_iocs = (~io_rd_n | ~io_wr_n) & (~cpu_address[0])
                    & (cpu_address[7:3] == 5'b00000) & ~cpu_address[9]
                    & ~cpu_address[8];
    KF8259 u_pic (
        .clock            (clk),
        .reset            (reset),
        .chip_select_n    (~pic_iocs),
        .read_enable_n    (io_rd_n),
        .write_enable_n   (io_wr_n),
        .address          (cpu_address[1]),
        .data_bus_in      (cpu_data_bus),
        .data_bus_out     (pic_dout),
        .data_bus_io      (pic_data_bus_io),
        .cascade_in       (3'b000),
        .cascade_out      (),
        .cascade_io       (),
        .slave_program_n  (1'b1),
        .buffer_enable    (),
        .slave_program_or_enable_buffer (),
        .interrupt_acknowledge_n (inta_n),
        .interrupt_to_cpu (pic_int),
        .external_irr_clear (8'h00),
        .interrupt_request({7'b0, irq0})
    );

    // The stimulus for the interrupt test: a rising edge on IRQ0, issued
    // once the program has parked on HLT with interrupts armed. Held a few
    // clocks so the edge-triggered request cannot be missed.
    logic irq0 = 1'b0;
    logic [3:0] irq0_hold = 4'd0;
    logic hlt_seen = 1'b0;
    always_ff @(posedge clk) begin
        if (!hlt_seen && v30_bs == 3'b011) begin
            hlt_seen <= 1'b1;
            irq0_hold <= 4'd8;
        end else if (irq0_hold != 4'd0) begin
            irq0_hold <= irq0_hold - 4'd1;
        end
        irq0 <= (irq0_hold != 4'd0);
    end

    // The read data: memory answers byte-wide, the PIC answers INTA and its
    // own ports. Everything is combinational, as the chipset's is.
    wire [7:0] din = ~mem_rd_n ? mem[cpu_address]
                    : ~inta_n   ? pic_dout
                    : pic_iocs & ~io_rd_n ? pic_dout
                                : 8'hFF;

    // Memory writes commit on the command's trailing edge, the 8-bit bus
    // way: one byte per cycle, data from the lane the bridge selected.
    logic mem_wr_d = 1'b1;
    logic io_wr_d = 1'b1;
    always_ff @(posedge clk) begin
        mem_wr_d <= mem_wr_n;
        io_wr_d  <= io_wr_n;
        if (mem_wr_n & ~mem_wr_d) mem[cpu_address] <= cpu_data_bus;
    end

    // ---- the byte-cycle log (order assertions) -----------------------------
    //
    // One entry per completed 8288 command cycle: {addr, data, wr}. The
    // direction and data are latched WHILE the command is live (at the
    // trailing edge the command is already gone). The bridge serves a
    // word's two bytes back-to-back, so their adjacency in this log is
    // the assertion.
    typedef struct packed {
        logic [19:0] addr;
        logic [7:0]  data;
        logic        wr;
    } cyc_t;
    cyc_t cyclog [0:4095];
    int   cyc_n = 0;

    logic       cmd_wr_q = 1'b0;
    logic [7:0] cmd_data_q = 8'h00;
    always_ff @(posedge clk) begin
        if (reset) begin
            cmd_wr_q   <= 1'b0;
            cmd_data_q <= 8'h00;
        end else if (~mem_wr_n | ~io_wr_n) begin
            cmd_wr_q   <= 1'b1;
            cmd_data_q <= cpu_data_bus;
        end else if (~mem_rd_n | ~io_rd_n) begin
            cmd_wr_q   <= 1'b0;
            cmd_data_q <= din;
        end
    end

    logic mem_rd_d = 1'b1;
    logic io_rd_d = 1'b1;
    always_ff @(posedge clk) begin
        mem_wr_d <= mem_wr_n;
        io_wr_d  <= io_wr_n;
        mem_rd_d <= mem_rd_n;
        io_rd_d  <= io_rd_n;
        if ((mem_wr_n & ~mem_wr_d) || (io_wr_n & ~io_wr_d)
            || (mem_rd_n & ~mem_rd_d) || (io_rd_n & ~io_rd_d)) begin
            cyclog[cyc_n[11:0]] <= '{ cpu_address, cmd_data_q, cmd_wr_q };
            cyc_n <= cyc_n + 1;
        end
    end

    // The CE gate: while the bridge has the core parked, no CE may reach
    // it. Sampled on the gated CE itself.
    int ce_gates = 0;
    always_ff @(posedge clk)
        if (u_cpu.CE && u_bridge.parked) ce_gates = ce_gates + 1;

    // ---- the program -------------------------------------------------------
    //
    //   0000 B8 34 12          mov ax,1234
    //   0003 A3 00 02          mov [0200],ax          word W even
    //   0006 C7 06 04 02 78 56 mov word [0204],5678   word W even
    //   000D C6 06 06 02 AA    mov byte [0206],AA      byte W even
    //   0012 C6 06 07 02 BB    mov byte [0207],BB      byte W odd
    //   0017 A1 00 02          mov ax,[0200]           word R even
    //   001A A3 10 02          mov [0210],ax
    //   001D 8B 06 04 02       mov ax,[0204]           word R even
    //   0021 A3 12 02          mov [0212],ax
    //   0024 8A 26 06 02       mov ah,[0206]           byte R even
    //   0028 88 26 14 02       mov [0214],ah
    //   002C 8A 26 07 02       mov ah,[0207]           byte R odd
    //   0030 88 26 15 02       mov [0215],ah
    //   0034 B8 CD EF          mov ax,EFCD
    //   0037 A3 20 02          mov [0220],ax
    //   003A 8B 06 21 02       mov ax,[0221]           word R odd (V30 splits)
    //   003E A3 24 02          mov [0224],ax
    //   0041 C6 06 30 02 C3    mov byte [0230],C3      "data phase done"
    //   0046 B0 13 E6 00       ICW1: edge, single, ICW4   (A0=0)
    //   004A B0 48 E6 02       ICW2: vectors at 48h       (A0=1)
    //   004E B0 01 E6 02       ICW4: 8086 mode            (A0=1)
    //   0052 B0 FE E6 02       OCW1: unmask IRQ0 only     (A0=1)
    //   0056 FB                sti
    //   0057 F4                hlt
    //   0058 C6 06 32 02 66    mov byte [0232],66      "woke and continued"
    //   005D EB FE             jmp $
    //
    //  0100 C6 06 31 02 5A     the IRQ0 handler: mov byte [0231],5A
    //  0105 CF                 iret
    //  IVT[48h] = 0000:0100
    task automatic poke(input int a, input logic [7:0] d);
        mem[a] = d;
    endtask

    int errors = 0;

    task automatic expect8(input int a, input logic [7:0] d, input string what);
        if (mem[a] !== d) begin
            errors = errors + 1;
            $display("  FAIL %s: mem[%04X] = %02X, want %02X",
                     what, a, mem[a], d);
        end
    endtask

    // Assert that entry i is followed by entry i+1 of the given shape:
    // the two bytes of a word cycle must be adjacent in the log.
    task automatic expect_adjacent(input logic [19:0] a1, input logic [7:0] d1,
                                   input logic        w1,
                                   input logic [19:0] a2, input logic [7:0] d2,
                                   input logic        w2,
                                   input string what);
        int k;
        begin
            for (k = 0; k < cyc_n - 1; k++)
                if (cyclog[k].addr == a1 && cyclog[k].data == d1
                    && cyclog[k].wr == w1)
                    break;
            if (k >= cyc_n - 1
                || cyclog[k+1].addr != a2 || cyclog[k+1].data != d2
                || cyclog[k+1].wr != w2) begin
                errors = errors + 1;
                $display("  FAIL %s: no (%04X,%02X,%b)->(%04X,%02X,%b) pair in %0d cycles",
                         what, a1, d1, w1, a2, d2, w2, cyc_n);
            end
        end
    endtask

    initial begin : program_image
        int i;
        for (i = 0; i < 1048576; i = i + 1) mem[i] = 8'h00;

        // reset vector: jmp 0000:0000
        poke(20'hFFFF0, 8'hEA); poke(20'hFFFF1, 8'h00); poke(20'hFFFF2, 8'h00);
        poke(20'hFFFF3, 8'h00); poke(20'hFFFF4, 8'h00);

        i = 0;
        poke(16'h0000 + i, 8'hB8); i = i + 1;   // mov ax,1234
        poke(16'h0000 + i, 8'h34); i = i + 1;
        poke(16'h0000 + i, 8'h12); i = i + 1;
        poke(16'h0000 + i, 8'hA3); i = i + 1;   // mov [0200],ax
        poke(16'h0000 + i, 8'h00); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hC7); i = i + 1;   // mov word [0204],5678
        poke(16'h0000 + i, 8'h06); i = i + 1;
        poke(16'h0000 + i, 8'h04); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'h78); i = i + 1;
        poke(16'h0000 + i, 8'h56); i = i + 1;
        poke(16'h0000 + i, 8'hC6); i = i + 1;   // mov byte [0206],AA
        poke(16'h0000 + i, 8'h06); i = i + 1;
        poke(16'h0000 + i, 8'h06); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hAA); i = i + 1;
        poke(16'h0000 + i, 8'hC6); i = i + 1;   // mov byte [0207],BB
        poke(16'h0000 + i, 8'h06); i = i + 1;
        poke(16'h0000 + i, 8'h07); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hBB); i = i + 1;
        poke(16'h0000 + i, 8'hA1); i = i + 1;   // mov ax,[0200]
        poke(16'h0000 + i, 8'h00); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hA3); i = i + 1;   // mov [0210],ax
        poke(16'h0000 + i, 8'h10); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'h8B); i = i + 1;   // mov ax,[0204]
        poke(16'h0000 + i, 8'h06); i = i + 1;
        poke(16'h0000 + i, 8'h04); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hA3); i = i + 1;   // mov [0212],ax
        poke(16'h0000 + i, 8'h12); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'h8A); i = i + 1;   // mov ah,[0206]
        poke(16'h0000 + i, 8'h26); i = i + 1;
        poke(16'h0000 + i, 8'h06); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'h88); i = i + 1;   // mov [0214],ah
        poke(16'h0000 + i, 8'h26); i = i + 1;
        poke(16'h0000 + i, 8'h14); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'h8A); i = i + 1;   // mov ah,[0207]
        poke(16'h0000 + i, 8'h26); i = i + 1;
        poke(16'h0000 + i, 8'h07); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'h88); i = i + 1;   // mov [0215],ah
        poke(16'h0000 + i, 8'h26); i = i + 1;
        poke(16'h0000 + i, 8'h15); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hB8); i = i + 1;   // mov ax,EFCD
        poke(16'h0000 + i, 8'hCD); i = i + 1;
        poke(16'h0000 + i, 8'hEF); i = i + 1;
        poke(16'h0000 + i, 8'hA3); i = i + 1;   // mov [0220],ax
        poke(16'h0000 + i, 8'h20); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'h8B); i = i + 1;   // mov ax,[0221] -- odd word
        poke(16'h0000 + i, 8'h06); i = i + 1;
        poke(16'h0000 + i, 8'h21); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hA3); i = i + 1;   // mov [0224],ax
        poke(16'h0000 + i, 8'h24); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hC6); i = i + 1;   // mov byte [0230],C3
        poke(16'h0000 + i, 8'h06); i = i + 1;
        poke(16'h0000 + i, 8'h30); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hC3); i = i + 1;
        poke(16'h0000 + i, 8'hB0); i = i + 1;   // mov al,13 / out 00  (ICW1)
        poke(16'h0000 + i, 8'h13); i = i + 1;
        poke(16'h0000 + i, 8'hE6); i = i + 1;
        poke(16'h0000 + i, 8'h00); i = i + 1;
        poke(16'h0000 + i, 8'hB0); i = i + 1;   // mov al,48 / out 02  (ICW2)
        poke(16'h0000 + i, 8'h48); i = i + 1;
        poke(16'h0000 + i, 8'hE6); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hB0); i = i + 1;   // mov al,01 / out 02  (ICW4)
        poke(16'h0000 + i, 8'h01); i = i + 1;
        poke(16'h0000 + i, 8'hE6); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hB0); i = i + 1;   // mov al,FE / out 02  (OCW1)
        poke(16'h0000 + i, 8'hFE); i = i + 1;
        poke(16'h0000 + i, 8'hE6); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'hFB); i = i + 1;   // sti
        poke(16'h0000 + i, 8'hF4); i = i + 1;   // hlt
        poke(16'h0000 + i, 8'hC6); i = i + 1;   // mov byte [0232],66
        poke(16'h0000 + i, 8'h06); i = i + 1;
        poke(16'h0000 + i, 8'h32); i = i + 1;
        poke(16'h0000 + i, 8'h02); i = i + 1;
        poke(16'h0000 + i, 8'h66); i = i + 1;
        poke(16'h0000 + i, 8'hEB); i = i + 1;   // jmp $
        poke(16'h0000 + i, 8'hFE); i = i + 1;

        // IVT[0x48] (vector slot at 0x0120) -> the handler at 0000:0100.
        poke(16'h0120, 8'h00); poke(16'h0121, 8'h01);
        poke(16'h0122, 8'h00); poke(16'h0123, 8'h00);

        // the IRQ0 handler at 0x0100
        poke(16'h0100, 8'hC6); poke(16'h0101, 8'h06); poke(16'h0102, 8'h31);
        poke(16'h0103, 8'h02); poke(16'h0104, 8'h5A);
        poke(16'h0105, 8'hCF);
    end

    // ---- run ---------------------------------------------------------------
    initial begin
        repeat (40) @(posedge clk);
        reset = 1'b0;

        // Plenty of time: at +slow it just takes longer.
        wait (mem[20'h00232] == 8'h66);
        repeat (200) @(posedge clk);

        $display("byte cycles logged: %0d, CE-gated-while-parked violations: %0d",
                 cyc_n, ce_gates);

        // The writes landed, byte for byte, lane for lane.
        expect8(20'h00200, 8'h34, "word W even, low lane");
        expect8(20'h00201, 8'h12, "word W even, high lane");
        expect8(20'h00204, 8'h78, "second word W, low lane");
        expect8(20'h00205, 8'h56, "second word W, high lane");
        expect8(20'h00206, 8'hAA, "byte W even");
        expect8(20'h00207, 8'hBB, "byte W odd");

        // The reads came back through the 16-bit DATA_I correctly.
        expect8(20'h00210, 8'h34, "word R even readback, low");
        expect8(20'h00211, 8'h12, "word R even readback, high");
        expect8(20'h00212, 8'h78, "second word R readback, low");
        expect8(20'h00213, 8'h56, "second word R readback, high");
        expect8(20'h00214, 8'hAA, "byte R even readback");
        expect8(20'h00215, 8'hBB, "byte R odd readback");

        // The V30's own odd-word split: [0221]=EF, [0222]=00 -> AX=00EF.
        expect8(20'h00224, 8'hEF, "odd word R, first byte");
        expect8(20'h00225, 8'h00, "odd word R, second byte");

        // The markers: data phase, interrupt handler, post-HLT.
        expect8(20'h00230, 8'hC3, "data phase marker");
        expect8(20'h00231, 8'h5A, "INTA handler marker");
        expect8(20'h00232, 8'h66, "post-HLT marker");

        // The ORDER of a word's two bytes in the byte-cycle log.
        expect_adjacent(20'h00200, 8'h34, 1'b1,
                        20'h00201, 8'h12, 1'b1, "word W split order");
        expect_adjacent(20'h00200, 8'h34, 1'b0,
                        20'h00201, 8'h12, 1'b0, "word R split order");
        expect_adjacent(20'h00204, 8'h78, 1'b1,
                        20'h00205, 8'h56, 1'b1, "second word W split order");
        expect_adjacent(20'h00221, 8'hEF, 1'b0,
                        20'h00222, 8'h00, 1'b0, "V30 odd-word split order");

        if (ce_gates != 0) begin
            errors = errors + 1;
            $display("  FAIL the core took %0d CE pulses while parked", ce_gates);
        end
        if (lock_n !== 1'b1) begin
            errors = errors + 1;
            $display("  FAIL lock_n is not high");
        end
        if (biu_done_count == 0) begin
            errors = errors + 1;
            $display("  FAIL biu_done never pulsed");
        end

        if (errors == 0)
            $display("RESULT: PASS (%0d byte cycles, slow=%0d)", cyc_n, slow_n);
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    // biu_done counter
    int biu_done_count = 0;
    logic biu_done_d = 1'b0;
    always_ff @(posedge clk) begin
        biu_done_d <= biu_done;
        if (biu_done & ~biu_done_d) biu_done_count <= biu_done_count + 1;
    end

    // Watchdog
    initial begin
        #200_000_000;   // 200 ms of bench time
        $display("RESULT: FAIL (timeout; markers: 0230=%02X 0231=%02X 0232=%02X, %0d cycles)",
                 mem[20'h00230], mem[20'h00231], mem[20'h00232], cyc_n);
        $finish;
    end

endmodule

`default_nettype wire
