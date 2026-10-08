//============================================================================
// tb_zet_resume -- directed replay of the ITF's shutdown/resume handshake on
// zet + zet_cpu_bridge. The real ITF does:
//
//     mov sp,0x30 / mov ss,sp / mov sp,0xFE          SS:SP = 0030:00FE
//     out 37h,0Eh                                   clear PC7 ("resume")
//     push cs / push 1497h                          return address
//     mov [0406],ss / mov [0404],sp                 save the stack pointer
//     out 0F0h,al                                   CPU-only reset
//   -- after reset, ITF entry --
//     in al,35h / test al,80h / jnz cold_boot
//     mov ss,[0406] / mov sp,[0404] / retf          -> CS:1497
//
// On hardware (zet build) this loops cold-boot forever: the test replays the
// exact instruction shapes and checks that RETF lands at CS:1497 (marker
// BEEFh in [0200h], DEADh if the 35h read says "cold boot").
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_zet_resume;

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

    logic [7:0] ram [0:20'hFFFFF];
    initial begin
        for (int i = 0; i < 32'h100000; i = i + 1) ram[i] = 8'h00;
        $readmemh("resume.hex", ram);
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

`ifdef ZET_DBG_WQ
    // Per-clk view of the 8288 machine-cycle vs the bridge's pair engine,
    // triggered by queue-drain completion and held open for 40 clocks.
    int st_watch = 0;
    always_ff @(posedge clk) begin
        if (u_bridge.cur_dq) st_watch <= 40;
        else if (st_watch > 0) st_watch <= st_watch - 1;
        if (st_watch > 0)
            $display("  %8t  ST=%03b mc=%b mcp=%b ale=%b ca=%05X rd_n=%b wr_n=%b db=%02x",
                     $time, processor_status, u_8288.machine_cycle,
                     u_8288.machine_cycle_period, ale, cpu_address,
                     mem_rd_n, mem_wr_n, din);
    end
`endif

    // port 35h answers 79h (bit7 clear: "this is a resume"); port 42h
    // answers 02h -- the real RTL's value (Peripherals.sv sysport_data);
    // bit1=1 is the "V30 machine" answer that makes the ITF SKIP the
    // 286-only FNINIT/FSTSW/SMSW/LMSW block at F94D2.
    wire [7:0] din    = ~mem_rd_n ? ram[cpu_address]
                      : ~io_rd_n  ? ((cpu_address[15:0] == 16'h35) ? 8'h79
                                   : (cpu_address[15:0] == 16'h42) ? 8'h84
                                                                 : 8'hFF)
                      : 8'hFF;
    wire [7:0] din_hi = ~mem_rd_n ? ram[cpu_address | 20'h1] : 8'hFF;

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
        .pf_disable        (1'b0),
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
        .wb_tgc_i  (1'b0),
        .wb_tgc_o  (zwb_inta),
        .nmi       (1'b0),
        .nmia      (zwb_nmia),
        .pc        (zet_pc)
    );

    logic mem_rd_d = 1, mem_wr_d = 1, io_rd_d = 1, io_wr_d = 1;
    always_ff @(posedge clk) begin
        mem_rd_d <= mem_rd_n;  mem_wr_d <= mem_wr_n;
        io_rd_d  <= io_rd_n;   io_wr_d  <= io_wr_n;
        if (mem_wr_d & ~mem_wr_n) begin
            $display("  %8t  WR %05X <- %02X%s", $time, cpu_address, cpu_data_bus,
                     word_access ? " word" : "");
            ram[cpu_address] <= cpu_data_bus;
            if (word_access) ram[cpu_address | 20'h1] <= cpu_data_bus_hi;
        end
        if (io_wr_d & ~io_wr_n)
            $display("  %8t  IOWR %04X <- %02X  (pc %05x)", $time,
                     cpu_address[15:0], cpu_data_bus, zet_pc);
        if (io_rd_d & ~io_rd_n)
            $display("  %8t  IORD %04X -> %02X  (pc %05x)", $time,
                     cpu_address[15:0], din, zet_pc);
        // stack-window reads: watch every byte the retf pops
        if (mem_rd_d & ~mem_rd_n && cpu_address >= 20'h3F0 && cpu_address < 20'h410)
            $display("  %8t  RD %05X -> %02X%s  (pc %05x)", $time, cpu_address,
                     din, word_access ? " word" : "", zet_pc);
    end

    // Wishbone trace while PC is near the retf (f8020..f8040) -- every bus
    // beat of the resume pop sequence.
    logic zwb_ack_d = 0;
    logic [15:0] imm_l_d = 0;
    always_ff @(posedge clk) begin
        zwb_ack_d <= zwb_ack;
        if (zwb_ack & ~zwb_ack_d &&
            ((zet_pc >= 20'hf8009 && zet_pc <= 20'hf8040)
             || ({zwb_adr, 1'b0} >= 20'h3F0 && {zwb_adr, 1'b0} < 20'h410)))
            $display("  %8t  WB %s adr=%05X sel=%b di=%04X do=%04X  (pc %05x)",
                     $time, zwb_we ? "WR" : "RD", {zwb_adr, 1'b0}, zwb_sel,
                     zwb_dat_i, zwb_dat_o, zet_pc);
        // fetch internals: watch imm_l capture around the push imm16
        if (u_cpu.core.fetch.imm_l != 16'h0000
            && u_cpu.core.fetch.imm_l != imm_l_d
            && zet_pc >= 20'hf8009 && zet_pc <= 20'hf8020)
            $display("  %8t  FETCH st=%0d nst=%0d data=%04X imm_l=%04X cdi=%04X (pc %05x)",
                     $time, u_cpu.core.fetch.state, u_cpu.core.fetch.next_state,
                     u_cpu.core.fetch.data, u_cpu.core.fetch.imm_l,
                     u_cpu.wb_master.cpu_dat_i, zet_pc);
        imm_l_d <= u_cpu.core.fetch.imm_l;
    end

    // CS trace: the retf landing shows up here
    logic [15:0] cs_d = 16'hFFFF;
    always_ff @(posedge clk) begin
        cs_d <= zet_pc[19:4];
        if (zet_pc[19:4] != cs_d)
            $display("  %8t  CS %04X -> %04X  (pc %05X)", $time, cs_d,
                     zet_pc[19:4], zet_pc);
    end

    initial begin
        repeat (20) @(posedge clk);
        reset <= 1'b0;
        repeat (300000) @(posedge clk);
        $display("DONE. pc=%05X  [0200]=%04X [0202]=%04X [0204]=%04X  [0404]=%04X [0406]=%04X  stack 30F8: %02X %02X %02X %02X %02X %02X",
                 zet_pc,
                 {ram[20'h201], ram[20'h200]},
                 {ram[20'h203], ram[20'h202]},
                 {ram[20'h205], ram[20'h204]},
                 {ram[20'h405], ram[20'h404]},
                 {ram[20'h407], ram[20'h406]},
                 ram[20'h003F8], ram[20'h003F9], ram[20'h003FA],
                 ram[20'h003FB], ram[20'h003FC], ram[20'h003FD]);
        if ({ram[20'h201], ram[20'h200]} == 16'hBEEF) begin
            if ({ram[20'h203], ram[20'h202]} == 16'hFF97
                && {ram[20'h205], ram[20'h204]} == 16'h1234)
                $display("RESUME PASS: retf+post-resume block landed at F854E, push imm8 sign-extends, 0F01 stubs consumed");
            else if ({ram[20'h205], ram[20'h204]} != 16'h1234)
                $display("RESUME PASS+MIXED: landed but 0F01 stub path lost sync ([0204]=%04X, want 1234)",
                         {ram[20'h205], ram[20'h204]});
            else
                $display("RESUME PASS+MIXED: landed but push imm8 gave [0202]=%04X (want FF97)",
                         {ram[20'h203], ram[20'h202]});
        end
        else if ({ram[20'h201], ram[20'h200]} == 16'hDEAD)
            $display("RESUME FAIL: in 35h read bit7 set (took cold-boot path)");
        else
            $display("RESUME FAIL: [0200]=%04X never written (pc=%05X)", {ram[20'h201], ram[20'h200]}, zet_pc);
        $finish;
    end

endmodule

`default_nettype wire
