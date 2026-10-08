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
    logic cpu_ce_negedge = 1'b0;      // pulse, like ce_generator's (not ~posedge)
    int   ce_cnt = 0;
    int   ce_gap = 0;                 // 0 = stock 5/11 pattern; N = 1 CE/N clks
    always_ff @(posedge clk) begin
        if (ce_gap > 0) begin
            ce_cnt <= (ce_cnt >= ce_gap - 1) ? 0 : ce_cnt + 1;
            cpu_ce_posedge <= (ce_cnt == 0);
            cpu_ce_negedge <= (ce_cnt == (ce_gap >> 1));
        end else begin
            ce_cnt <= (ce_cnt == 10) ? 0 : ce_cnt + 1;
            cpu_ce_posedge <= (ce_cnt == 0) || (ce_cnt == 2) || (ce_cnt == 5)
                           || (ce_cnt == 7) || (ce_cnt == 9);
            cpu_ce_negedge <= (ce_cnt == 1) || (ce_cnt == 3) || (ce_cnt == 6)
                           || (ce_cnt == 8) || (ce_cnt == 10);
        end
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
        .cpu_ce_negedge                  (cpu_ce_negedge),
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

    // Faithful memory model (RAM.sv semantics):
    //   * a memory command parks the FSM for acc_wait clks (accept->latency),
    //   * the read data lands in a HOLD REGISTER only at completion --
    //     data_bus keeps showing the previous access's bytes meanwhile
    //     (RAM.sv data_bus_out_reg's stale window),
    //   * memory_access_ready is 0 while the access is in flight and rises
    //     for one clk at completion,
    //   * writes commit at completion too.
    // +accwait=N sets the access latency (0 = instant, near the old model).
    int         acc_wait = 0;
    int         acc_timer = -1;
    logic       acc_busy  = 1'b0;
    logic [19:0] acc_addr = 20'h0;
    logic        acc_we   = 1'b0;
    logic        acc_word = 1'b0;
    logic [7:0]  acc_wlo = 8'h00, acc_whi = 8'h00;
    logic [7:0]  hold_lo = 8'hFF, hold_hi = 8'hFF;
    logic        mem_cmd_d = 1'b1;
    logic        mem_done = 1'b0;

    wire        mem_cmd_n = mem_rd_n & mem_wr_n;
    wire        mem_acc_rdy = acc_busy ? mem_done : 1'b1;

    always_ff @(posedge clk) begin
        mem_cmd_d <= mem_cmd_n;
        mem_done  <= 1'b0;
        if (mem_cmd_d & ~mem_cmd_n & ~acc_busy) begin  // command accepts
            acc_addr  <= cpu_address;
            acc_we    <= ~mem_wr_n;
            acc_word  <= word_access;
            acc_wlo   <= cpu_data_bus;
            acc_whi   <= cpu_data_bus_hi;
            acc_timer <= acc_wait;
            acc_busy  <= 1'b1;
        end else if (acc_busy) begin
            if (acc_timer <= 0) begin
                if (acc_we) begin
                    ram[acc_addr]              <= acc_wlo;
                    if (acc_word) ram[acc_addr | 20'h1] <= acc_whi;
                end else begin
                    hold_lo <= ram[acc_addr];
                    hold_hi <= ram[acc_addr | 20'h1];
                end
                acc_busy <= 1'b0;
                mem_done <= 1'b1;
            end else
                acc_timer <= acc_timer - 1;
        end
    end

    // data_bus semantics: the held bytes are what the bus shows during a
    // read (stale until THIS access completes); off the mem window it floats FF.
    wire [7:0] din    = ~inta_n   ? pic_dout
                      : ~mem_rd_n ? hold_lo
                                  : 8'hFF;
    wire [7:0] din_hi = ~mem_rd_n ? hold_hi
                                  : 8'hFF;

    // The real CE-synced READY chain -- processor_ready can only change on
    // cpu_ce edges, exactly as hardware paces it.
    wire cpu_ready;
    READY u_ready (
        .clock              (clk),
        .cpu_ce_posedge     (cpu_ce_posedge),
        .cpu_ce_negedge     (cpu_ce_negedge),
        .reset              (reset),
        .processor_ready    (cpu_ready),
        .dma_ready          (),
        .dma_wait_n         (1'b1),
        .io_channel_ready   (mem_acc_rdy),   // Chipset ANDs its own io_ch term;
                                            // none here: 1 while no mem busy
        .io_read_n          (io_rd_n),
        .io_write_n         (io_wr_n),
        .memory_read_n      (mem_rd_n),
        .dma0_acknowledge_n (1'b1),
        .address_enable_n   (aen_r)
    );

    // DMA/AEN injection: +aen=K parks the CPU bus every 2048 clks for K clks,
    // modelling the FDC DMA steal the flat bench never sees.
    int     aen_len = 0;
    int     aen_cnt = 0;
    logic   aen_r   = 1'b0;
    always_ff @(posedge clk) begin
        if (aen_len > 0 && !reset) begin
            aen_cnt <= aen_cnt + 1;
            aen_r   <= (aen_cnt > 2048 && aen_cnt <= 2048 + aen_len);
            if (aen_cnt > 2048 + aen_len) aen_cnt <= 0;
        end
    end

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
        .cpu_ce_negedge    (cpu_ce_negedge),
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
        .processor_ready   (cpu_ready),
        .address_enable_n  (aen_r),
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
    // Handshake integrity: each engine arm queues the byte0/byte1 addresses it
    // must put on the bus; every memory command must then match the queued
    // address (ALE latched cpu_address). A mismatch means the 8288 cycle ran
    // on a stale address -- the class of corruption the slow-CE wedge implies.
    logic [19:0] exp_addr [0:15];
    logic [ 1:0] exp_cnt = 0;
    int          exp_w = 0, exp_r = 0, mismatch = 0;
    wire  [1:0]  eng_bstate = u_bridge.bstate;
    logic [1:0]  eng_bstate_d = 0;
    always_ff @(posedge clk) begin
        eng_bstate_d <= eng_bstate;
        // B_IDLE->B_CMD transition = arm for a byte of the pair
        if (eng_bstate_d == 2'd0 && eng_bstate == 2'd1 && !u_bridge.cur_inta) begin
            exp_addr[exp_w & 15] <= ad_out;
            exp_w <= exp_w + 1;
        end
        if ((mem_rd_d & ~mem_rd_n) | (mem_wr_d & ~mem_wr_n)) begin
            if (exp_r < exp_w) begin
                if (cpu_address !== exp_addr[exp_r & 15]) begin
                    $display("  %8t  !! ADDR MISMATCH cmd@%05X expected %05X",
                             $time, cpu_address, exp_addr[exp_r & 15]);
                    mismatch <= mismatch + 1;
                end
                exp_r <= exp_r + 1;
            end
        end
        // stale-data check: the byte the bridge is about to latch must equal
        // the memory's true content -- a completion on the stale window or a
        // re-issued access would diverge here.
        if (u_bridge.bstate == 2'd1 && u_bridge.t_cnt >= 3'd3
            && cpu_ce_posedge && cpu_ready && !aen_r
            && u_bridge.cur_read && !u_bridge.cur_inta) begin
            if (din !== ram[cpu_address]) begin
                $display("  %8t  !! RDSTALE @%05X bus=%02X mem=%02X",
                         $time, cpu_address, din, ram[cpu_address]);
                stale <= stale + 1;
            end
            if (u_bridge.cur_1cyc && din_hi !== ram[cpu_address | 20'h1]) begin
                $display("  %8t  !! RDSTALE_HI @%05X bus=%02X mem=%02X",
                         $time, cpu_address, din_hi, ram[cpu_address | 20'h1]);
                stale <= stale + 1;
            end
            // a completion that never saw ready fall sampled the stale
            // window by definition -- count them even when the value
            // coincidentally matches.
            if (!rdy_fell) nofall <= nofall + 1;
        end
        // ready-fell bookkeeping per byte: set once proc_ready has been
        // low during this command -- the RAM actually took the access.
        if (eng_bstate_d == 2'd0 && eng_bstate == 2'd1)
            rdy_fell <= 1'b0;
        else if (eng_bstate == 2'd1 && !cpu_ready)
            rdy_fell <= 1'b1;
        else if (eng_bstate != 2'd1)
            rdy_fell <= 1'b0;
    end
    int stale = 0;
    int nofall = 0;
    logic rdy_fell = 1'b0;
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
        if ($value$plusargs("aen=%d", v))     aen_len  = v;
        if ($value$plusargs("cegap=%d", v))   ce_gap = v;
        repeat (20) @(posedge clk);
        reset = 1'b0;
        repeat (cycles) @(posedge clk);
        $display("--- done after %0d clks ---", cycles);
        $display("armed %0d cmds %0d mismatches %0d stale %0d nofall %0d", exp_w, exp_r, mismatch, stale, nofall);
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
