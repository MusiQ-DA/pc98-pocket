//============================================================================
// tb_zet_kernexp -- run the FreeDOS kernel.sys self-extractor on bare
// zet + zet_cpu_bridge over a flat byte memory. kernel.sys is loaded at
// 0060:0000 (the boot sector's convention); the trampoline at the reset
// vector seeds SS=1E80/SP=0100 then jumps 0060:0000, exactly like the
// real boot sector's EA 00 00 60 00.
//
//   +cycles=N   chipset clocks to run before the dump (default 200M)
//   +dump=FILE  writememh target for the whole 1 MiB (default kernexp.mem)
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_zet_kernexp;

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
        $readmemh("kernexp.hex", ram);
        $display("reset vec: %02x %02x %02x %02x %02x  khead: %02x %02x %02x",
                 ram[20'hfff0], ram[20'hfff1], ram[20'hfff2], ram[20'hfff3],
                 ram[20'hfff4], ram[20'h600], ram[20'h601], ram[20'h602]);
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
        .address_latch_enable            (ale)
    );
    always_ff @(posedge clk)
        if (ale) cpu_address <= ad_out;

    // fake 8259: vector 40h presented on the second INTA byte
    int         inta_cnt = 0;
    wire  [7:0] pic_dout = (inta_cnt >= 1) ? 8'h40 : 8'hFF;

    // SDRAM-latency model: RAM.sv holds the data bus on the PREVIOUS access's
    // byte while a command is in flight (data_bus_out_reg), and ready only
    // rises in COMPLETE_RAM_RW. Here every memory command parks ready for
    // `acc_wait` chipset clocks; while parked the bus shows the last
    // completed read's bytes -- the stale window the bridge must not sample.
    // +accwait=0 restores the old always-ready behaviour.
    int         acc_wait = 0;
    int         acc_timer = -1;
    logic [7:0] last_lo = 8'hFF, last_hi = 8'hFF;
    logic       mem_cmd_d = 1'b1;

    wire        mem_cmd_n = mem_rd_n & mem_wr_n;
    wire        acc_pend  = (acc_timer >= 0);
    wire        cpu_ready = ~acc_pend;

    always_ff @(posedge clk) begin
        mem_cmd_d <= mem_cmd_n;
        if (mem_cmd_d & ~mem_cmd_n)          // memory command asserts
            acc_timer <= acc_wait;
        else if (acc_pend) begin
            acc_timer <= acc_timer - 1;
            if (acc_timer == 0) begin
                if (~mem_rd_n) begin
                    last_lo <= ram[cpu_address];
                    last_hi <= ram[cpu_address | 20'h1];
                end
                acc_timer <= -1;
            end
        end
    end

    wire [7:0] din    = ~inta_n   ? pic_dout
                      : ~mem_rd_n ? (acc_pend ? last_lo : ram[cpu_address])
                                  : 8'hFF;
    wire [7:0] din_hi = ~mem_rd_n ? (acc_pend ? last_hi : ram[cpu_address | 20'h1])
                                  : 8'hFF;

    // periodic INTR stimulus: vector 40h -> F000:0200, handler is a bare
    // IRET. irq_period==0 disables it. The point is to run the extractor
    // under the same interrupt load the hardware sees (the 74 Hz keyboard
    // storm observed via io_wr_count).
    logic intr  = 1'b0;
    logic nmi_r = 1'b0;
    int   irq_period = 0;                    // chipset clocks between IRQs
    int   irq_hold   = 200;                  // how long INTR stays up
    longint irq_timer = 0;
    int   irq_on = 0;
    int   inta_n_seen = 0;
    always_ff @(posedge clk) begin
        if (irq_period > 0 && !reset) begin
            irq_timer <= irq_timer + 1;
            if (irq_timer >= irq_period) begin
                irq_timer <= 0;
                intr <= 1'b1;
                irq_on <= 1;
            end
            // drop INTR once the bridge has acked (inta pulse seen) or the
            // hold window elapsed -- mirrors a level IRQ that stays up
            // until serviced.
            if (intr && (zwb_inta || irq_timer >= irq_hold)) begin
                intr <= 1'b0;
                irq_on <= 0;
            end
        end
    end

    // INTR bookkeeping: count 8288 INTA pulses; byte1 carries the vector
    logic inta_d = 1'b1;
    always_ff @(posedge clk) begin
        inta_d <= inta_n;
        if (inta_d & ~inta_n) inta_cnt <= inta_cnt + 1;
        if (reset) inta_cnt <= 0;
    end

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
        .processor_ready   (cpu_ready),
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

    logic mem_wr_d = 1;
    logic mem_rd_d = 1;
    int   rd_n = 0, rd_max = 60;
    int   wr_lo = 20'hFFFFF, wr_hi = 0, wr_n = 0;
    always_ff @(posedge clk) begin
        mem_wr_d <= mem_wr_n;
        mem_rd_d <= mem_rd_n;
        if (mem_rd_d & ~mem_rd_n && rd_n < rd_max) begin
            $display("  %8t  RD %05X -> %02X%02X", $time, cpu_address,
                     din_hi, din);
            rd_n <= rd_n + 1;
        end
        if (mem_wr_d & ~mem_wr_n) begin
            if (wr_n < rd_max)
                $display("  %8t  WR %05X <- %02X%s", $time, cpu_address,
                         cpu_data_bus, word_access ? " word" : "");
            ram[cpu_address] <= cpu_data_bus;
            if (word_access) ram[cpu_address | 20'h1] <= cpu_data_bus_hi;
            if (cpu_address < wr_lo) wr_lo <= cpu_address;
            if (cpu_address > wr_hi) wr_hi <= cpu_address;
            wr_n <= wr_n + 1;
        end
    end

    // PC ring so the dump can say where the extractor ended up
    logic [19:0] pc_ring [0:15];
    int pc_ring_w = 0;
    always_ff @(posedge clk)
        if (cpu_ce_posedge && zwb_stb && zwb_cyc && !zwb_we) begin
            pc_ring[pc_ring_w] <= {zwb_adr, 1'b0};
            pc_ring_w <= (pc_ring_w + 1) & 15;
        end

    // instruction-boundary trace: zet_pc is the fetch pin; print the first
    // TRN distinct values so an early derail shows its true path.
    int tr_n = 0;
    int tr_max = 400;
    logic [19:0] last_pc = 20'hFFFFF;
    always_ff @(posedge clk)
        if (!reset && cpu_ce_posedge && zet_pc != last_pc && tr_n < tr_max) begin
            $display("  %8t  PC %05X", $time, zet_pc);
            last_pc <= zet_pc;
            tr_n    <= tr_n + 1;
        end

    longint cycles = 200_000_000;
    string  dumpf = "kernexp.mem";
    initial begin
        int v; string p;
        if ($value$plusargs("cycles=%d", v)) cycles = v;
        if ($value$plusargs("dump=%s", p))   dumpf  = p;
        if ($value$plusargs("trn=%d", v))    tr_max = v;
        if ($value$plusargs("rdn=%d", v))    rd_max = v;
        if ($value$plusargs("irqp=%d", v))   irq_period = v;
        if ($value$plusargs("irqhold=%d", v)) irq_hold = v;
        if ($value$plusargs("accwait=%d", v)) acc_wait = v;
        repeat (20) @(posedge clk);
        reset = 1'b0;
        repeat (cycles) @(posedge clk);
        $display("--- done after %0d clks ---", cycles);
        $display("writes %0d  range %05X..%05X  pc %05X", wr_n, wr_lo, wr_hi, zet_pc);
        $write("pc ring:");
        for (int j = 0; j < 16; j = j + 1)
            $write(" %05X", pc_ring[(pc_ring_w + j) & 15]);
        $display("");
        $writememh(dumpf, ram);
        $finish;
    end

endmodule

`default_nettype wire
