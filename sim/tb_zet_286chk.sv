//============================================================================
// tb_zet_286chk -- bare zet + zet_cpu_bridge on flat memory.
// The program under test writes a result byte to I/O ports 110h..11Fh;
// the bench just logs every I/O write so the transcript can be compared
// against expected 80286 semantics.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_zet_286chk;

    logic clk = 1'b0;
    always #9.25 clk = ~clk;               // ~54 MHz chipset clock

    logic reset = 1'b1;
    logic cpu_ce_posedge = 1'b0;
    int   ce_cnt = 0;
    always_ff @(posedge clk) begin
        ce_cnt <= (ce_cnt == 10) ? 0 : ce_cnt + 1;
        cpu_ce_posedge <= (ce_cnt == 0) || (ce_cnt == 2) || (ce_cnt == 5)
                       || (ce_cnt == 7) || (ce_cnt == 9);
    end

    // flat memory: 1 MiB
    logic [7:0] ram [0:20'hFFFFF];
    initial begin
        for (int i = 0; i < 32'h100000; i = i + 1) ram[i] = 8'h00;
        $readmemh("chk.hex", ram);
    end

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
    always_ff @(posedge clk)
        if (ale) cpu_address <= ad_out;

    wire        zet_clk;
    wire [15:0] zwb_dat_o, zwb_dat_i;
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

    wire [7:0] din    = ~mem_rd_n ? ram[cpu_address]         : 8'hFF;
    wire [7:0] din_hi = ~mem_rd_n ? ram[cpu_address | 20'h1] : 8'hFF;

    logic intr = 1'b0, nmi_r = 1'b0;
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

    logic mem_rd_d = 1, mem_wr_d = 1, io_rd_d = 1, io_wr_d = 1;
    always_ff @(posedge clk) begin
        mem_rd_d <= mem_rd_n;  mem_wr_d <= mem_wr_n;
        io_rd_d  <= io_rd_n;   io_wr_d  <= io_wr_n;
        if (mem_wr_d & ~mem_wr_n) begin
            ram[cpu_address] <= cpu_data_bus;
            if (word_access) ram[cpu_address | 20'h1] <= cpu_data_bus_hi;
        end
        if (io_wr_d & ~io_wr_n)
            $display("  %8t  IOWR %04X <- %02X", $time, cpu_address[15:0], cpu_data_bus);
    end

    initial begin
        repeat (20) @(posedge clk);
        reset <= 1'b0;
        repeat (300000) @(posedge clk);
        $display("CHK DONE. pc=%05X", zet_pc);
        $finish;
    end

endmodule

`default_nettype wire
