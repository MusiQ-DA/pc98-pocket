//============================================================================
// tb_zet_ios -- bare zet + zet_cpu_bridge on a flat byte memory.
// Exercises the 80186 string-I/O opcodes (6C-6F) added to the microcode:
//   outsb/outsw (incl. rep outsw), insb/insw, DF=1 direction, ES: override
//   on outs, and rep insb/insw -> single INVOP fault (rep not implemented
//   for ins; rep outsb would loop INVOP and is not covered here).
// Self-checking: records the io write byte stream and the ES:DI image.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_zet_ios;

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
        $readmemh("ios.hex", ram);
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

    // io read data: each read returns the next byte of a fixed stream so the
    // memory image makes ordering obvious.
    int   io_rd_cnt = 0;
    wire  [7:0] io_din = 8'h60 + io_rd_cnt[7:0];

    wire [7:0] din    = ~io_rd_n  ? io_din
                      : ~mem_rd_n ? ram[cpu_address]            : 8'hFF;
    wire [7:0] din_hi = ~mem_rd_n ? ram[cpu_address | 20'h1]    : 8'hFF;

    logic intr = 1'b0, nmi_r = 1'b0;

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
    // monitors: record io-write bytes and io-read count; capture memory image
    // ---------------------------------------------------------------------
    logic mem_rd_d = 1, mem_wr_d = 1, io_rd_d = 1, io_wr_d = 1;
    logic inta_d = 1;

    logic [7:0] iowr_log [0:63];
    int    iowr_cnt = 0;
    logic [7:0] iowr_adr [0:63];
    bit    done_seen = 0;

    always_ff @(posedge clk) begin
        mem_rd_d <= mem_rd_n;  mem_wr_d <= mem_wr_n;
        io_rd_d  <= io_rd_n;   io_wr_d  <= io_wr_n;
        if (mem_wr_d & ~mem_wr_n) begin
            ram[cpu_address] <= cpu_data_bus;
            if (word_access) ram[cpu_address | 20'h1] <= cpu_data_bus_hi;
        end
        if (io_wr_d & ~io_wr_n) begin
            iowr_log[iowr_cnt] <= cpu_data_bus;
            iowr_adr[iowr_cnt] <= cpu_address[7:0];
            iowr_cnt <= iowr_cnt + 1;
            $display("  %8t  IOWR %04X <- %02X", $time, cpu_address[15:0], cpu_data_bus);
            if (cpu_address[15:0] == 16'h05A1 && cpu_data_bus == 8'h42)
                done_seen <= 1;
        end
        if (io_rd_d & ~io_rd_n)
            $display("  %8t  IORD %04X -> %02X", $time, cpu_address[15:0], io_din);
        if (~io_rd_d & io_rd_n)
            io_rd_cnt <= io_rd_cnt + 1;
        inta_d <= inta_n;
    end

    // expected io-write data stream (port byte order):
    //   outsb   -> A0
    //   outsw   -> A1 A2        (lo,hi of word at 20001)
    //   rep outsw x3 -> A3 A4 A5 A6 A7 A8
    //   DF outsb -> A8          (si=8 reads [20008])
    //   es:outsb -> 77          ([50002])
    //   out 05A1,42 -> 42       (completion)
    localparam logic [7:0] EXP [0:11] =
        '{8'hA0, 8'hA1, 8'hA2, 8'hA3, 8'hA4, 8'hA5,
          8'hA6, 8'hA7, 8'hA8, 8'hA8, 8'h77, 8'h42};
    // ES:3000 image: insb+insw reads 3 bytes (60..62). rep insb/insw fault
    // once via INVOP; the int6 handler bumps the return IP past the rep
    // prefix so the bare opcode runs once as a plain ins - landing at
    // ES:5000 (es was reloaded for the es:outsb check), reads 63..65.
    localparam logic [7:0] EXPIMG [0:5] =
        '{8'h60, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65};

    int errors = 0;
    initial begin
        repeat (20) @(posedge clk);
        reset <= 1'b0;
        repeat (300000) @(posedge clk);
        $display("DONE. pc=%05X iowr=%0d iord=%0d marker=%02x done=%0d",
                 zet_pc, iowr_cnt, io_rd_cnt, ram[20'h20310], done_seen);
        $display("frame bp+0..8: %02x%02x %02x%02x %02x%02x %02x%02x %02x%02x",
                 ram[20'h20301], ram[20'h20300], ram[20'h20303], ram[20'h20302],
                 ram[20'h20305], ram[20'h20304], ram[20'h20307], ram[20'h20306],
                 ram[20'h20309], ram[20'h20308]);
        $display("stack FFF0-FFFF: %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
                 ram[20'hFFF0], ram[20'hFFF1], ram[20'hFFF2], ram[20'hFFF3],
                 ram[20'hFFF4], ram[20'hFFF5], ram[20'hFFF6], ram[20'hFFF7],
                 ram[20'hFFF8], ram[20'hFFF9], ram[20'hFFFA], ram[20'hFFFB],
                 ram[20'hFFFC], ram[20'hFFFD], ram[20'hFFFE], ram[20'hFFFF]);
        if (iowr_cnt != 12) begin
            errors++; $display("FAIL: iowr_cnt=%0d != 12", iowr_cnt);
        end else for (int i = 0; i < 12; i++)
            if (iowr_log[i] !== EXP[i]) begin
                errors++;
                $display("FAIL: iowr[%0d]=%02x exp %02x (adr %04x)",
                         i, iowr_log[i], EXP[i], iowr_adr[i]);
            end
        if (io_rd_cnt != 3 && io_rd_cnt != 6) begin
            errors++; $display("FAIL: iord_cnt=%0d (exp 3 or 6)", io_rd_cnt);
        end
        for (int i = 0; i < 3; i++)
            if (ram[20'h30000+i] !== EXPIMG[i]) begin
                errors++;
                $display("FAIL: [300%02x]=%02x exp %02x", i, ram[20'h30000+i], EXPIMG[i]);
            end
        for (int i = 0; i < io_rd_cnt-3 && i < 3; i++)
            if (ram[20'h50003+i] !== EXPIMG[3+i]) begin
                errors++;
                $display("FAIL: [500%02x]=%02x exp %02x", i+3, ram[20'h50003+i], EXPIMG[3+i]);
            end
        if (ram[20'h20310] < 8'd2) begin
            errors++;
            $display("FAIL: int6 marker=%02x < 2 (rep insb/insw didn't fault)",
                     ram[20'h20310]);
        end
        if (!done_seen) begin
            errors++; $display("FAIL: completion out 05A1,42 not seen");
        end
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
