//============================================================================
// tb_zet_iplstress -- bare zet + zet_cpu_bridge on flat memory running the
// ipl_farstress image (same one loaded to hardware). Code sits at phys
// 0x1FC00 (CS=0x1FC0), the far-pointer table at 0x40100, seg2 copy at
// 0x30000, and the result mailbox at 0x50000.  Flat single-cycle RAM with NO
// prefetch -- if the stress passes here but diverges on hardware, the fault
// is in the SDRAM/prefetch path, not the CPU or the test.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_zet_iplstress;

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
        $readmemh("iplstress.hex", ram);
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
        .address_enable_n(1'b0), .sdram_wr_taken(~mem_wr_n), .sdram_rd_ready(1'b1),
        .pause_core(1'b0), .biu_done(), .pf_disable(1'b0),
        .pf_nofill(1'b0), .pf_nofillm(1'b0), .pf_nohit(1'b0),
        .bios_shadow_flag(1'b0), .dbg()
    );

    zet u_cpu (
        .wb_clk_i(zet_clk), .wb_rst_i(reset),
        .wb_dat_i(zwb_dat_i), .wb_dat_o(zwb_dat_o), .wb_adr_o(zwb_adr),
        .wb_we_o(zwb_we), .wb_tga_o(zwb_tga), .wb_sel_o(zwb_sel),
        .wb_stb_o(zwb_stb), .wb_cyc_o(zwb_cyc), .wb_ack_i(zwb_ack),
        .wb_tgc_i(intr), .wb_tgc_o(zwb_inta), .nmi(nmi_r), .nmia(zwb_nmia),
        .fwdis(1'b0), .nowrap(1'b0), .pc(zet_pc)
    );

    // ---- random INTR stimulus (matches hardware vsync pressure) ----
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

    // ---- mailbox write monitor: catch the status byte at phys 0x50004 ----
    logic mem_rd_d = 1, mem_wr_d = 1, io_wr_d = 1, inta_d = 1;
    int   iters = 0;
    logic saw_ac = 0, saw_ee = 0;
    logic [7:0] opfail = 0;
    logic [15:0] badcs = 0;
    always_ff @(posedge clk) begin
        mem_rd_d <= mem_rd_n;  mem_wr_d <= mem_wr_n;
        io_wr_d  <= io_wr_n;   inta_d   <= inta_n;
        if (mem_wr_d & ~mem_wr_n) begin
            ram[cpu_address] <= cpu_data_bus;
            if (word_access) ram[cpu_address | 20'h1] <= cpu_data_bus_hi;
            if (cpu_address == 20'h50004) begin
                if (cpu_data_bus == 8'hAC) saw_ac <= 1;
                if (cpu_data_bus == 8'hEE) saw_ee <= 1;
            end
            if (cpu_address == 20'h50008) opfail <= cpu_data_bus;
            if (cpu_address == 20'h5000A) badcs[7:0] <= cpu_data_bus;
            if (cpu_address == 20'h5000B) badcs[15:8] <= cpu_data_bus;
        end
        if (inta_d & ~inta_n) inta_cnt <= inta_cnt + 1;
    end

    // trace regfile writes (cs/ip) during the seg2 jmp-far sequence
    int trace_on = 0; int rd118 = 0;
    always_ff @(posedge clk) begin
        if (zwb_cyc && zwb_stb && zwb_ack && !zwb_we
            && ({zwb_adr,1'b0} == 20'h40118)) rd118 <= rd118 + 1;
        if (!trace_on && rd118 == 2) trace_on <= 1;
        if (trace_on && trace_on < 90) begin
            $display("  %8t pc=%05x cs=%04x ip=%04x | wr=%b ad=%h d=%04x | wb%s a=%05x stb=%b blk=%b",
                     $time, zet_pc,
                     u_cpu.core.exec.regfile.r[9],
                     u_cpu.core.exec.regfile.r[15],
                     u_cpu.core.exec.regfile.wr,
                     u_cpu.core.exec.regfile.addr_d,
                     u_cpu.core.exec.regfile.d[15:0],
                     (zwb_cyc&&zwb_stb)?(zwb_we?"W":"R"):"--",
                     {zwb_adr,1'b0}, zwb_stb, u_cpu.core.exec.block);
            trace_on <= trace_on + 1;
        end
    end

    // last-64 fetch-PC ring + first-divergence detector
    logic [19:0] pcr [0:63];
    logic [5:0]  pcw = 0;
    logic [19:0] pcprev = 0;
    logic        div_seen = 0;
    always_ff @(posedge clk) begin
        if (zet_pc != pcprev) begin
            if (!div_seen && (zet_pc < 20'h09000)
                && (pcprev >= 20'h09000)) begin
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
        repeat (15000000) @(posedge clk);
        iters = {ram[20'h50003], ram[20'h50002]};
        $display("DONE. pc=%05X iters=%0d saw_ac=%b saw_ee=%b opfail=%02x badcs=%04x",
                 zet_pc, iters, saw_ac, saw_ee, opfail, badcs);
        $display("  mbx cs=%04x ptr_off_rd=%04x ptr_seg_rd=%04x bc=%02x",
                 {ram[20'h50011],ram[20'h50010]},
                 {ram[20'h50013],ram[20'h50012]},
                 {ram[20'h50015],ram[20'h50014]}, ram[20'h50040]);
        $write("trail:");
        for (int i = 0; i < 40; i++)
            $write(" %05x", pcr[(pcw + 64 - 40 + i) % 64]);
        $display("");
        if (saw_ac && !saw_ee)
            $display("IPLSTRESS PASS");
        else if (saw_ee)
            $display("IPLSTRESS FAIL (bad CS at op %02x, saw %04x)", opfail, badcs);
        else
            $display("IPLSTRESS FAIL (diverged/hung, no result)");
        $finish;
    end

endmodule

`default_nettype wire
