//============================================================================
// tb_zet_smoke -- bare zet + zet_cpu_bridge on a flat byte memory.
// Builds in seconds, so the Wishbone->8288 contract can be debugged on
// programs of a dozen instructions instead of the full ITF bench.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_zet_movs;

    logic clk = 1'b0;
    always #9.25 clk = ~clk;               // ~54 MHz chipset clock

    logic reset = 1'b1;
    logic cpu_ce_posedge = 1'b0;
    int   ce_cnt = 0;
    always_ff @(posedge clk) begin
        // 42.95 MHz / 19.66 MHz -> a CE pulse roughly every 2.2 clocks:
        // pattern 1,0,1,0,0 repeats (5 pulses / 11 clks is close enough).
        ce_cnt <= (ce_cnt == 10) ? 0 : ce_cnt + 1;
        cpu_ce_posedge <= (ce_cnt == 0) || (ce_cnt == 2) || (ce_cnt == 5)
                       || (ce_cnt == 7) || (ce_cnt == 9);
    end

    // flat memory: 1 MiB
    logic [7:0] ram [0:20'hFFFFF];
    initial begin
        for (int i = 0; i < 32'h100000; i = i + 1) ram[i] = 8'h00;
        $readmemh("smoke.hex", ram);
        $display("vec: %02x %02x %02x %02x %02x  prog: %02x %02x",
                 ram[20'hfff0], ram[20'hfff1], ram[20'hfff2], ram[20'hfff3],
                 ram[20'hfff4], ram[20'hf8000], ram[20'hf8001]);
    end

    // processor-status driven strobes (the same fake the big bench runs)
    wire [2:0]  processor_status;
    wire [19:0] ad_out;
    logic [19:0] cpu_address = 20'h0;
    wire [7:0]  cpu_data_bus;
    wire        word_access;
    wire [7:0]  cpu_data_bus_hi;
    wire        mem_rd_n, mem_wr_n, io_rd_n, io_wr_n, ale, inta_n;

    i8288 u_8288 (
        .clock                           (clk),
        .cpu_ce_posedge                  (cpu_ce_posedge),
        .cpu_ce_negedge                  (~cpu_ce_posedge),
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
    // address latch, same as the big bench
    always_ff @(posedge clk)
        if (ale) cpu_address <= ad_out;

    // fake 8259: the 8288 pulses inta_n once per BS_INTA byte; a real PIC
    // presents the vector on the SECOND pulse (ACK2), so count the pulses
    // and drive 40h once ACK1 has ended. The bridge only samples byte 1.
    int         inta_cnt = 0;
    wire  [7:0] pic_dout = (inta_cnt >= 1) ? 8'h40 : 8'hFF;

    wire [7:0] din    = ~inta_n   ? pic_dout
                      : ~mem_rd_n ? ram[cpu_address]            : 8'hFF;
    wire [7:0] din_hi = ~mem_rd_n ? ram[cpu_address | 20'h1]    : 8'hFF;

    // interrupt stimulus, driven by the phase machine below
    logic intr  = 1'b0;
    logic nmi_r = 1'b0;

    wire        zet_clk;
    wire [15:0] zwb_dat_i, zwb_dat_o;
    wire [19:1] zwb_adr;
    wire        zwb_we, zwb_tga, zwb_stb, zwb_cyc, zwb_ack;
    wire [ 1:0] zwb_sel;
    wire        zwb_inta, zwb_nmia;
    wire [19:0] zet_pc;

    zet_cpu_bridge u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (~cpu_ce_posedge),
        .fast_pace         (1'b0),
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
        .nmia              (zwb_nmia),
        .processor_status  (processor_status),
        .ad_out            (ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (),
        .analog_mode       (1'b0),
        .pf_req_len        (),
        .pf_beat_v         (1'b0),
        .pf_beat_dat       (8'h00),
        .word_access       (word_access),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (din_hi),
        .data_bus          (din),
        .processor_ready   (1'b1),
        .address_enable_n  (1'b0),
        .pause_core        (1'b0),
        .biu_done          (),
        .dbg               ()
    );

    zet u_cpu (
        .wb_clk_i  (zet_clk),
        .wb_rst_i  (reset),
        .wb_dat_i  (zwb_dat_i),
        .wb_dat_o  (zwb_dat_o),
        .wb_adr_o  (zwb_adr),
        .wb_we_o   (zwb_we),
        .wb_tga_o  (zwb_tga),
        .wb_sel_o  (zwb_sel),
        .wb_stb_o  (zwb_stb),
        .wb_cyc_o  (zwb_cyc),
        .wb_ack_i  (zwb_ack),
        .wb_tgc_i  (intr),
        .wb_tgc_o  (zwb_inta),
        .nmi       (nmi_r),
        .nmia      (zwb_nmia),
        .pc        (zet_pc)
    );

    // ---------------------------------------------------------------------
    // monitor: every bus command, one line
    // ---------------------------------------------------------------------
    // request-capture watch: wb_dat_o at announce vs over the following clks
    logic [15:0] ann_data;  logic ann_valid = 0; int ann_clk = 0;
    always_ff @(posedge clk) begin
        if (!ann_valid && zwb_stb && zwb_cyc) begin
            ann_valid <= 1; ann_data <= zwb_dat_o; ann_clk <= 0;
            $display("  %8t  ANN adr %05x sel %b we %b dat_o %04x  exec_st %b we_o %b memop %b io %b pc %05x  ir %h aexec %05x",
                     $time, {zwb_adr,1'b0}, zwb_sel, zwb_we, zwb_dat_o,
                     u_cpu.core.exec_st, u_cpu.core.cpu_we_o, u_cpu.core.cpu_mem_op, u_cpu.core.cpu_m_io, zet_pc,
                     u_cpu.core.rom_ir, u_cpu.core.addr_exec);
        end else if (ann_valid) begin
            ann_clk <= ann_clk + 1;
            if (zwb_dat_o !== ann_data)
                $display("  %8t  ANN+ dat_o moved %04x -> %04x (+%0d clk)",
                         $time, ann_data, zwb_dat_o, ann_clk);
            if (!zwb_stb || ann_clk > 40) ann_valid <= 0;
        end
    end

    logic mem_rd_d = 1, mem_wr_d = 1, io_rd_d = 1, io_wr_d = 1;
    logic inta_d = 1, zwb_inta_d = 0;
    always_ff @(posedge clk) begin
        mem_rd_d <= mem_rd_n;  mem_wr_d <= mem_wr_n;
        io_rd_d  <= io_rd_n;   io_wr_d  <= io_wr_n;
        if (mem_rd_d & ~mem_rd_n)
            $display("  %8t  RD %05X -> %02X (sel %b) ram@ca=%02x ad=%05x",
                     $time, cpu_address, din, zwb_sel, ram[cpu_address], ad_out);
        if (mem_wr_d & ~mem_wr_n) begin
            $display("  %8t  WR %05X <- %02X%s", $time, cpu_address, cpu_data_bus,
                     word_access ? " word" : "");
            ram[cpu_address] <= cpu_data_bus;
            if (word_access) ram[cpu_address | 20'h1] <= cpu_data_bus_hi;
        end
        if (io_wr_d & ~io_wr_n)
            $display("  %8t  IOWR %04X <- %02X", $time, cpu_address[15:0], cpu_data_bus);
        if (io_rd_d & ~io_rd_n)
            $display("  %8t  IORD %04X", $time, cpu_address[15:0]);
        if (inta_d & ~inta_n) begin
            inta_cnt <= inta_cnt + 1;
            $display("  %8t  INTA#%0d", $time, inta_cnt + 1);
        end
        inta_d <= inta_n;
        if (zwb_inta & ~zwb_inta_d)
            $display("  %8t  ZINTA pulse -- clock frozen", $time);
        if (~zwb_inta & zwb_inta_d)
            $display("  %8t  ZINTA released (int_vector %02X)",
                     $time, u_bridge.int_vector);
        zwb_inta_d <= zwb_inta;
    end

    // stimulus: none -- the program does fill + rep movsw, then OUT 0101.
    int dumps = 0;
    always_ff @(posedge clk) begin
        if (io_wr_d & ~io_wr_n && cpu_address[15:0] == 16'h0101) begin
            $display("  %8t  DONE marker", $time);
            $display("  dst rows 0-3 after rep movsw (word values lo,hi):");
            for (int i = 0; i < 160; i = i + 2)
                $display("    a%04x: %02x %02x", 20'hA0000 + i, ram[20'hA0000+i], ram[20'hA0000+i+1]);
            $display("  src region a00a0-a00af: %02x %02x %02x %02x",
                     ram[20'hA00A0], ram[20'hA00A1], ram[20'hA00A2], ram[20'hA00A3]);
            $finish;
        end
    end

    initial begin
        repeat (20) @(posedge clk);
        reset <= 1'b0;
        #5000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
