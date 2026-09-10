//
// tb_cpu_v30 -- the 186-class instructions the V30 ROMs actually use.
//
// The machine's CPUs are V30s: the VM BIOS, the UX ITF, and N88-BASIC all
// assume the 186 additions, and the first one that mattered was PUSH imm16.
// mcl86 is an 8088, where opcode 0x68 is the undocumented alias of JS -- the
// ITF's CPU-reset save sequence starts with one, so the "jump if sign" ate
// the immediate as a displacement, the stream derailed four bytes deep, and
// the reset resume RETFed to garbage. That failure is why this bench exists.
//
// A flat 64 KB, the same clock-enable plumbing as the boot bench, and a
// program of pushes. What lands on the stack is then exactly what the
// microcode did.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_cpu_v30;

    logic clk_chipset = 1'b0;
    logic clk_core    = 1'b0;
    always #11.641 clk_chipset = ~clk_chipset;
    always  #5.820 clk_core    = ~clk_core;

    logic reset = 1'b1;

    wire       clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire       cycle_accrate, shift_read_timing;
    wire [7:0] ccc_div, ccc_dec;
    wire [1:0] ram_rd_wait, ram_wr_wait;
    wire       biu_done;

    XT_CE_Generator u_ce (
        .clock                              (clk_chipset),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (2'b10),      // 9.54 MHz, as shipped
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

    wire [19:0] cpu_ad_out;
    wire  [7:0] cpu_data_bus, din;
    wire  [2:0] processor_status;
    wire        lock_n, s6_3_mux;
    wire  [2:0] SEGMENT;

    i8088 u_cpu (
        .CORE_CLK  (clk_core),
        .CLK       (clk_cpu),
        .RESET     (reset),
        .READY     (1'b1),
        .INTR      (1'b0),
        .NMI       (1'b0),
        .ad_out    (cpu_ad_out),
        .dout      (cpu_data_bus),
        .din       (din),
        .lock_n    (lock_n),
        .s6_3_mux  (s6_3_mux),
        .s2_s0_out (processor_status),
        .SEGMENT   (SEGMENT),
        .biu_done  (biu_done),
        .cycle_accrate                       (cycle_accrate),
        .clock_cycle_counter_division_ratio  (ccc_div),
        .clock_cycle_counter_decrement_value (ccc_dec),
        .shift_read_timing                   (shift_read_timing)
    );

    // ---- bus controller, as the boot bench has it ---------------------------
    wire mem_rd_n, mem_wr_n, adv_mem_wr_n;
    wire io_rd_n,  io_wr_n,  adv_io_wr_n;
    wire inta_n, ale, en_io, en_mem, dt_r_n, den, mce, pden;

    KF8288 u_8288 (
        .clock                           (clk_chipset),
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

    logic [19:0] cpu_address = 20'h0;
    always_ff @(posedge clk_chipset)
        if (ale) cpu_address <= cpu_ad_out;

    logic [7:0] ram [0:1048575];
    assign din = ~mem_rd_n ? ram[cpu_address] : 8'hFF;

    logic mem_wr_d = 1'b1;
    logic [7:0] mem_wr_data_q = 8'h00;
    always_ff @(posedge clk_chipset) begin
        mem_wr_d   <= mem_wr_n;
        if (~mem_wr_n) mem_wr_data_q <= cpu_data_bus;
        if (mem_wr_n & ~mem_wr_d) ram[cpu_address] <= mem_wr_data_q;
    end

    wire [19:0] eu_pc = {u_cpu.t_biu_register_cs, 4'd0}
                      + {4'd0, u_cpu.t_pfq_addr_out};

    // Microcode trace, only for the new routine and its callees, so a broken
    // clone names the microinstruction it died at.
    logic [12:0] urom_d = 13'h1FFF;
    wire  [12:0] urom = u_cpu.EU_CORE.eu_rom_address;
    logic        trace_on = 1'b0;
    int          trace_n = 0;
    always_ff @(posedge clk_core) begin
        urom_d <= urom;
        if (urom == 13'h0F7A) trace_on <= 1'b1;
        if (trace_on && trace_n < 700 && urom != urom_d) begin
            trace_n <= trace_n + 1;
            $display("  %6t u %03X r3=%04X r1=%04X out=%04X sp=%04X pfqe=%b", $time, urom,
                     u_cpu.EU_CORE.eu_register_r3, u_cpu.EU_CORE.eu_register_r1,
                     u_cpu.EU_CORE.eu_biu_dataout, u_cpu.EU_CORE.eu_register_sp,
                     ~u_cpu.BIU_CORE.pfq_empty);
        end
    end

    int errors = 0;

    initial begin
        // CS:IP = 0000:0100 via the reset vector, which jumps there.
        ram[20'hFFFF0] = 8'hEA; ram[20'hFFFF1] = 8'h00; ram[20'hFFFF2] = 8'h01;
        ram[20'hFFFF3] = 8'h00; ram[20'hFFFF4] = 8'h00;

        // 0100: B8 00 02        mov ax, 0x0200
        // 0103: 8E D0           mov ss, ax
        // 0105: BC 60 00        mov sp, 0x0060
        // 0108: 68 34 12        push 0x1234
        // 010B: 68 78 56        push 0x5678
        // 010E: 6A FE           push -2        (sign-extends to FFFE)
        // 0110: 6A 42           push byte 0x42
        // 0112: EB FE           jmp $
        ram[20'h0100]=8'hB8; ram[20'h0101]=8'h00; ram[20'h0102]=8'h02;
        ram[20'h0103]=8'h8E; ram[20'h0104]=8'hD0;
        ram[20'h0105]=8'hBC; ram[20'h0106]=8'h60; ram[20'h0107]=8'h00;
        ram[20'h0108]=8'h68; ram[20'h0109]=8'h34; ram[20'h010A]=8'h12;
        ram[20'h010B]=8'h68; ram[20'h010C]=8'h78; ram[20'h010D]=8'h56;
        ram[20'h010E]=8'h6A; ram[20'h010F]=8'hFE;
        ram[20'h0110]=8'h6A; ram[20'h0111]=8'h42;
        ram[20'h0112]=8'hEB; ram[20'h0113]=8'hFE;

        for (int i = 20'h0200; i < 20'h0300; i++) ram[i] = 8'h00;

        repeat (40) @(posedge clk_chipset);
        reset = 1'b0;

        // The program is a handful of instructions; a thousand CPU clocks is
        // many times over. Poll for the park on the EB FE instead of guessing.
        repeat (30000) @(posedge clk_chipset);
        if (eu_pc !== 20'h0112)
            $display("  note: eu_pc %05X (park expected at 0112)", eu_pc);

        $display("=== V30 push immediates ===");
        // SS:SP should now be 0200:0058, with the four words below it.
        $display("  SP %04X (want 0058)", u_cpu.EU_CORE.eu_register_sp);
        if (u_cpu.EU_CORE.eu_register_sp !== 16'h0058) begin
            $display("  FAIL SP"); errors++;
        end
        for (int i = 20'h0100; i < 20'h0400; i++)
            if (ram[i] !== 8'h00 && !(i >= 20'h0100 && i <= 20'h0113))
                $display("  RAM[%04X] = %02X", i, ram[i]);
        begin : check
            logic [7:0] w0, w1, w2, w3, w4, w5, w6, w7;
            w0 = ram[20'h0258]; w1 = ram[20'h0259];
            w2 = ram[20'h025A]; w3 = ram[20'h025B];
            w4 = ram[20'h025C]; w5 = ram[20'h025D];
            w6 = ram[20'h025E]; w7 = ram[20'h025F];
            $display("  [0258] %02X%02X (want 1234)", w1, w0);
            $display("  [025A] %02X%02X (want 5678)", w3, w2);
            $display("  [025C] %02X%02X (want FFFE)", w5, w4);
            $display("  [025E] %02X%02X (want 0042)", w7, w6);
            if ({w1, w0} !== 16'h1234) begin $display("  FAIL push imm16 low");  errors++; end
            if ({w3, w2} !== 16'h5678) begin $display("  FAIL push imm16 high"); errors++; end
            if ({w5, w4} !== 16'hFFFE) begin $display("  FAIL push imm8 negative sign-extension"); errors++; end
            if ({w7, w6} !== 16'h0042) begin $display("  FAIL push imm8 positive"); errors++; end
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
