//============================================================================
// tb_zet_retf -- bare zet + zet_cpu_bridge on flat memory.
// The program loops `call far`/`retf`, `call far [mem]`, `int`/`iret`,
// `pusha`/`popa`, and a push-frame `retf`, writing an iteration marker to
// port 0x20 each pass and 0xAC to port 0x30 on success (0xEE on a CS bug).
// Meanwhile the bench raises INTR at randomized intervals (vector 40h) so
// the INT-entry/IRET path runs constantly over the stack ops -- a stack or
// far-transfer imbalance diverges the stream and the markers stall.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_zet_retf;

    logic clk = 1'b0;
    always #9.25 clk = ~clk;

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
        $readmemh("reft_test.hex", ram);
    end

    wire [2:0]  processor_status;
    wire [19:0] ad_out;
    logic [19:0] cpu_address = 20'h0;
    wire [7:0]  cpu_data_bus;
    wire        word_access;
    wire [7:0]  cpu_data_bus_hi;
    wire        mem_rd_n, mem_wr_n, io_rd_n, io_wr_n, ale, inta_n;

    i8288 u_8288 (
        .clock (clk), .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(~cpu_ce_posedge), .reset(reset),
        .address_enable_n(1'b0), .command_enable(1'b1), .io_bus_mode(1'b0),
        .processor_status(processor_status),
        .enable_io_command(), .advanced_io_write_command_n(),
        .io_write_command_n(io_wr_n), .io_read_command_n(io_rd_n),
        .interrupt_acknowledge_n(inta_n),
        .enable_memory_command(), .advanced_memory_write_command_n(),
        .memory_write_command_n(mem_wr_n), .memory_read_command_n(mem_rd_n),
        .direction_transmit_or_receive_n(), .data_enable(),
        .master_cascade_enable(), .peripheral_data_enable_n(),
        .address_latch_enable(ale)
    );
    always_ff @(posedge clk) if (ale) cpu_address <= ad_out;

    int         inta_cnt = 0;
    wire  [7:0] pic_dout = (inta_cnt >= 1) ? 8'h40 : 8'hFF;
    wire [7:0] din    = ~inta_n   ? pic_dout
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
        .clk(clk), .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(~cpu_ce_posedge), .fast_pace(1'b0), .reset(reset),
        .zet_clk(zet_clk), .wb_dat_o(zwb_dat_o), .wb_dat_i(zwb_dat_i),
        .wb_adr_o(zwb_adr), .wb_we_o(zwb_we), .wb_tga_o(zwb_tga),
        .wb_sel_o(zwb_sel), .wb_stb_o(zwb_stb), .wb_cyc_o(zwb_cyc),
        .wb_ack_i(zwb_ack), .wb_tgc_o(zwb_inta), .nmia(zwb_nmia),
        .processor_status(processor_status), .ad_out(ad_out),
        .cpu_data_bus(cpu_data_bus), .lock_n(), .analog_mode(1'b0),
        .pf_req_len(), .pf_beat_v(1'b0), .pf_beat_dat(8'h00),
        .word_access(word_access), .cpu_data_bus_hi(cpu_data_bus_hi),
        .data_bus_hi(din_hi), .data_bus(din), .processor_ready(1'b1),
        .address_enable_n(1'b0), .pause_core(1'b0), .biu_done(), .pf_disable(1'b0), .dbg()
    );

    zet u_cpu (
        .wb_clk_i(zet_clk), .wb_rst_i(reset),
        .wb_dat_i(zwb_dat_i), .wb_dat_o(zwb_dat_o), .wb_adr_o(zwb_adr),
        .wb_we_o(zwb_we), .wb_tga_o(zwb_tga), .wb_sel_o(zwb_sel),
        .wb_stb_o(zwb_stb), .wb_cyc_o(zwb_cyc), .wb_ack_i(zwb_ack),
        .wb_tgc_i(intr), .wb_tgc_o(zwb_inta), .nmi(nmi_r), .nmia(zwb_nmia),
        .pc(zet_pc)
    );

    // ---- random INTR stimulus: assert intr for a few zet edges, then release
    // gap between interrupts; $test$plusargs("noint") disables entirely
    localparam int GAP_LO = 300, GAP_HI = 1200;
    logic noint = 1'b0;
    initial noint = $test$plusargs("noint");
    int seed = 32'hC0FFEE;
    int intr_hold = 0, intr_wait = 0;
    always_ff @(posedge clk) begin
        if (reset) begin intr <= 1'b0; intr_hold <= 0; intr_wait <= 0; end
        else if (noint) intr <= 1'b0;
        else if (intr) begin
            if (zwb_inta || intr_hold > 6) begin
                intr <= 1'b0;
                intr_wait <= ($dist_uniform(seed, GAP_LO, GAP_HI));
            end else intr_hold <= intr_hold + 1;
        end else begin
            intr_hold <= 0;
            if (intr_wait > 0) intr_wait <= intr_wait - 1;
            else intr <= 1'b1;
        end
    end

    // ---- monitors ----
    logic mem_rd_d = 1, mem_wr_d = 1, io_wr_d = 1, inta_d = 1;
    int   mark20 = 0, int_count = 0;
    logic saw_ac = 0, saw_ee = 0;
    always_ff @(posedge clk) begin
        mem_rd_d <= mem_rd_n;  mem_wr_d <= mem_wr_n;
        io_wr_d  <= io_wr_n;   inta_d   <= inta_n;
        if (mem_wr_d & ~mem_wr_n) begin
            ram[cpu_address] <= cpu_data_bus;
            if (word_access) ram[cpu_address | 20'h1] <= cpu_data_bus_hi;
        end
        if (io_wr_d & ~io_wr_n) begin
            if (cpu_address[15:0] == 16'h20) mark20 <= mark20 + 1;
            else if (cpu_address[15:0] == 16'h30) begin
                if (cpu_data_bus == 8'hAC) saw_ac <= 1;
                if (cpu_data_bus == 8'hEE) saw_ee <= 1;
                $display("  %8t  PORT30 <- %02X", $time, cpu_data_bus);
            end
        end
        if (inta_d & ~inta_n) inta_cnt <= inta_cnt + 1;
    end

    // last-64 fetch-PC ring + first-divergence detector
    logic [19:0] pcr [0:63];
    logic [5:0]  pcw = 0;
    logic [19:0] pcprev = 0;
    logic        div_seen = 0;
    always_ff @(posedge clk) begin
        if (zet_pc != pcprev) begin
            // edge: was in code (>=0x9000), now dropped into low RAM
            if (!div_seen && (zet_pc < 20'h09000)
                && (pcprev >= 20'h09000) && (mark20 > 0)) begin
                div_seen <= 1;
                $display("  %8t  DIVERGE pc=%05X from %05X trail:", $time, zet_pc, pcprev);
                begin : dump
                    for (int i = 0; i < 32; i++)
                        $write(" %05x", pcr[(pcw + 64 - 32 + i) % 64]);
                    $display("");
                end
            end
            pcr[pcw] <= zet_pc; pcw <= pcw + 1; pcprev <= zet_pc;
        end
    end

    initial begin
        repeat (20) @(posedge clk);
        reset <= 1'b0;
        repeat (3200000) @(posedge clk);
        $display("DONE. pc=%05X mark20=%0d saw_ac=%b saw_ee=%b",
                 zet_pc, mark20, saw_ac, saw_ee);
        $write("trail:");
        for (int i = 0; i < 40; i++)
            $write(" %05x", pcr[(pcw + 64 - 40 + i) % 64]);
        $display("");
        if (saw_ac && !saw_ee && mark20 >= 300)
            $display("RETF PASS");
        else
            $display("RETF FAIL (diverged or CS corrupted)");
        $finish;
    end

endmodule

`default_nettype wire
