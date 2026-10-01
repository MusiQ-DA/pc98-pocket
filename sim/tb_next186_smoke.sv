//============================================================================
// tb_next186_smoke -- bare next186_cpu_bridge (the Next186 CPU + BIU inside)
// on a flat byte memory. Builds in seconds, so the no-handshake CE-stall
// contract -- including the double-INTA path -- is debuggable on programs of
// a dozen instructions instead of the full ITF bench.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_next186_smoke;

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

    wire [15:0] bridge_dbg;
    wire [19:0] dbg_pc;
    wire [15:0] dbg_din;

    next186_cpu_bridge u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .reset             (reset),
        .intr              (intr),
        .nmi               (nmi_r),
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
        .dbg_pc            (dbg_pc),
        .dbg_din           (dbg_din),
        .dbg               (bridge_dbg)
    );

    // ---------------------------------------------------------------------
    // monitor: every bus command, one line
    // ---------------------------------------------------------------------
    logic mem_rd_d = 1, mem_wr_d = 1, io_rd_d = 1, io_wr_d = 1;
    logic inta_d = 1, u_inta_d = 0;
    always_ff @(posedge clk) begin
        mem_rd_d <= mem_rd_n;  mem_wr_d <= mem_wr_n;
        io_rd_d  <= io_rd_n;   io_wr_d  <= io_wr_n;
        if (mem_rd_d & ~mem_rd_n)
            $display("  %8t  RD %05X -> %02X (ram@ca=%02x ad=%05x mreq %b rd %b wr %b ce186 %b)",
                     $time, cpu_address, din, ram[cpu_address], ad_out,
                     u_bridge.u_ram_mreq, u_bridge.u_ram_rd, u_bridge.u_ram_wr,
                     u_bridge.ce186);
        if (mem_wr_d & ~mem_wr_n) begin
            $display("  %8t  WR %05X <- %02X%s", $time, cpu_address, cpu_data_bus,
                     word_access ? " word" : "");
            ram[cpu_address] <= cpu_data_bus;
            if (word_access) ram[cpu_address | 20'h1] <= cpu_data_bus_hi;
        end
        if (io_wr_d & ~io_wr_n)
            $display("  %8t  IOWR %04X <- %02X", $time, cpu_address[15:0], cpu_data_bus);
        if (io_rd_d & ~io_rd_n)
            $display("  %8t  IORD %04X -> %02X", $time, cpu_address[15:0], din);
        if (inta_d & ~inta_n) begin
            inta_cnt <= inta_cnt + 1;
            $display("  %8t  INTA#%0d", $time, inta_cnt + 1);
        end
        inta_d <= inta_n;
        if (u_bridge.u_inta & ~u_inta_d)
            $display("  %8t  N186INTA pulse -- unit frozen", $time);
        if (~u_bridge.u_inta & u_inta_d)
            $display("  %8t  N186INTA released (int_vector %02X)",
                     $time, u_bridge.int_vector);
        u_inta_d <= u_bridge.u_inta;
        // every unit tick: BIU state + CPU stage + request flags
        if (u_bridge.unit_ce && !reset && $time < 32_000_000)
            $display("  %8t  UTK bstate=%0d ce186=%b qs=%0d%s%s%s%s icode=%0d stage=%0d iaddr=%05x",
                     $time, u_bridge.u_biu.STATE, u_bridge.ce186,
                     u_bridge.u_biu.qsize,
                     u_bridge.u_ram_mreq ? " MREQ" : "",
                     u_bridge.u_ram_rd ? " RD" : "",
                     u_bridge.u_ram_wr ? " WR" : "",
                     u_bridge.u_inta ? " INTA" : (u_bridge.u_iorq ? " IORQ" : ""),
                     u_bridge.u_cpu.ICODE1, u_bridge.u_cpu.STAGE,
                     u_bridge.u_iaddr);
        // per-tick microcode trace: every CE186&CE tick retires a stage
        if (u_bridge.unit_ce && u_bridge.ce186 && !reset && $time < 30_000_000)
            $display("  %8t  TICK icode=%0d stage=%0d%s%s%s iaddr=%05x addr=%05x din=%04x",
                     $time, u_bridge.u_cpu.ICODE1, u_bridge.u_cpu.STAGE,
                     u_bridge.u_iorq ? " IORQ" : "",
                     u_bridge.u_inta ? " INTA" : "",
                     u_bridge.u_cpu.HALT ? " HALT" : "",
                     u_bridge.u_iaddr, u_bridge.u_addr,
                     u_bridge.cpu_din);
    end

    // ---------------------------------------------------------------------
    // stimulus: the program arms vectors 40h/02h, STIs, then spins on
    // `inc word [0202h]`. Once the loop is live, raise INTR; the handler
    // writes BEEFh to [0200] and IRETs -- a moving [0202] afterwards proves
    // the resume. Then a short NMI pulse must land CAFEh in [0204] the
    // same way (vector 2, no bus cycle). Expected: exactly 2 INTA pulses.
    // ---------------------------------------------------------------------
    int   phase   = 0;
    int   nmi_cnt = 0;
    int   wr202   = 0;         // WR strobes to 0x202 since the phase reset it

    wire wr202_pulse = mem_wr_d & ~mem_wr_n && (cpu_address == 20'h202);

    always_ff @(posedge clk) begin
        if (wr202_pulse) wr202 <= wr202 + 1;
        if (phase == 4) nmi_cnt <= nmi_cnt + 1;
        case (phase)
          0: if (wr202 >= 1) begin                        // STI ran, loop up
                 intr  <= 1'b1;
                 phase <= 1;
                 $display("  %8t  STIM intr high", $time);
             end
          1: if (inta_cnt >= 1) begin                     // ACK1: committed
                 intr  <= 1'b0;
                 phase <= 2;
                 $display("  %8t  STIM intr low", $time);
             end
          2: if ({ram[20'h201], ram[20'h200]} == 16'hBEEF) begin
                 wr202 <= 0;
                 phase <= 3;
                 $display("  %8t  STIM marker BEEF -- handler ran", $time);
             end
          3: if (wr202 >= 2) begin                        // IRET resumed
                 nmi_r   <= 1'b1;
                 nmi_cnt <= 0;
                 phase   <= 4;
                 $display("  %8t  STIM nmi pulse", $time);
             end
          4: if (nmi_cnt == 500) begin             // span plenty of unit ticks
                 nmi_r <= 1'b0;
                 phase <= 5;
             end
          5: if ({ram[20'h205], ram[20'h204]} == 16'hCAFE) begin
                 wr202 <= 0;
                 phase <= 6;
                 $display("  %8t  STIM marker CAFE -- nmi handler ran", $time);
             end
          6: if (wr202 >= 2) phase <= 7;
          default: ;
        endcase
    end

    initial begin
        repeat (20) @(posedge clk);
        reset <= 1'b0;
        repeat (2000000) @(posedge clk);
        $display("DONE. dbg_pc=%05X phase=%0d inta_cnt=%0d  [0200]=%04X [0204]=%04X [0202]=%04X",
                 dbg_pc, phase, inta_cnt,
                 {ram[20'h201], ram[20'h200]},
                 {ram[20'h205], ram[20'h204]},
                 {ram[20'h203], ram[20'h202]});
        if (phase == 7 && inta_cnt == 2
            && {ram[20'h201], ram[20'h200]} == 16'hBEEF
            && {ram[20'h205], ram[20'h204]} == 16'hCAFE)
            $display("SMOKE PASS: INTR took vector 40h, NMI vector 2, IRET resumed");
        else
            $display("SMOKE FAIL");
        $finish;
    end

endmodule

`default_nettype wire
