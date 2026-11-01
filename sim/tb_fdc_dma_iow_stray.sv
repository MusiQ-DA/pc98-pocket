//
// tb_fdc_dma_iow_stray -- the floppy-WRITE single-byte 0x20 corruption.
//
// Hardware: a SuperDepth high-score save (FreeDOS, 2HD 1 KB sectors) now
// and then wrote ONE wrong byte, always 0x20, into a FAT sector -- one copy
// of the FAT only, a different offset each time, wherever the firmware's
// staging buffer sat. 0x20 is the PIC EOI the game's IRQ0 handler writes
// (`out 00h,20h`) at ~1.1-1.5 kHz.
//
// The mechanism this bench pins, real RTL only:
//
//   cpu_bus_bridge (real byte engine) -> BUS_ARBITER (real 8288, real
//   hold chain, real 92/201-clocked uPD71071, real strobe/data merge)
//   <- READY (real), with Peripherals' FDC DMA equations verbatim: the
//   write_to_fdd latch (`if (~io_write_n) write_to_fdd <= internal_data_bus`)
//   and floppy.v's dma_readdata sampled on fdd_dma_rw_ack, the clock
//   AFTER DACK falls.
//
//   1. The bridge arms an I/O write in the half-CE window between the
//      arbiter's passive-status sample (hold_request_ff_1) and the AEN
//      rise. The 8288 strobes the status; its machine cycle runs on with
//      command_enable gated off for the whole grant.
//   2. The 71071 moves a byte memory -> FDC (its own IOW latches the
//      memory byte into write_to_fdd) and, at the S4 posedge, drops IOW
//      and HRQ together. DACK only falls at the NEXT 71071 negedge.
//   3. AEN drops on the next cpu_ce_posedge -- which can come first --
//      and the parked 8288 command fires the instant command_enable
//      returns: IOW low with DEN, internal_data_bus = cpu_data_bus = 0x20.
//      write_to_fdd re-latches 0x20 while DACK is still low, and the FDC
//      takes it as the DMA byte.
//
// Stimulus: the bench CPU programs the 71071 through the bridge (mode 0x4A:
// single, memory->I/O, ch2) and then hammers OUT 00h,20h with random gaps
// while the FDC pulls a 1 KB sector by DMA. The source pattern never
// contains 0x20, so any 0x20 in the FDC's sink is the CPU's byte.
//
// Plusargs: +SPEED=0..3 (ce_generator clk_select)  +ITERS=n sectors
//           +SEED=n  +TRACE=1
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_fdc_dma_iow_stray;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic reset = 1'b1;

    int speed_sel = 3;
    int iters     = 4;
    int trace     = 0;
    int seed      = 1;
    initial begin
        int v;
        if ($value$plusargs("SPEED=%d", v)) speed_sel = v;
        if ($value$plusargs("ITERS=%d", v)) iters = v;
        if ($value$plusargs("TRACE=%d", v)) trace = v;
        if ($value$plusargs("SEED=%d", v))  seed = v;
        void'($urandom(seed));
    end

    // ---- CE train -----------------------------------------------------------
    wire  clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire  cycle_accrate, shift_read_timing;
    wire  [7:0] ccc_div, ccc_dec;
    wire  [1:0] ram_rd_wait, ram_wr_wait;
    logic [1:0] clk_sel;
    always_comb clk_sel = 2'(speed_sel);

    ce_generator u_ce (
        .clock                              (clk),
        .reset                              (reset),
        .clk_select_load                    (1'b1),
        .clk_select                         (clk_sel),
        .cpu_clk_pin                        (clk_cpu),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .cycle_accrate                      (cycle_accrate),
        .clock_cycle_counter_division_ratio (ccc_div),
        .clock_cycle_counter_decrement_value(ccc_dec),
        .shift_read_timing                  (shift_read_timing),
        .ram_read_wait_cycle                (ram_rd_wait),
        .ram_write_wait_cycle               (ram_wr_wait),
        .vram_wait_en                       ()
    );

    // ---- the real bridge, driven by a synthetic Wishbone master -------------
    logic [15:0] wb_dat_o_m = 16'h0;
    wire  [15:0] wb_dat_i;
    logic [19:1] wb_adr_m = 19'h0;
    logic        wb_we_m  = 1'b0;
    logic        wb_tga_m = 1'b0;
    logic [1:0]  wb_sel_m = 2'b11;
    logic        wb_stb_m = 1'b0;
    logic        wb_cyc_m = 1'b0;
    wire         wb_ack_i;
    wire         zet_clk, zet_edge;
    wire  [4:0]  pf_req_len;

    wire [2:0]   processor_status;
    wire [19:0]  ad_out;
    wire [7:0]   cpu_data_bus, cpu_data_bus_hi;
    wire         word_access, lock_n;
    wire         processor_ready;
    wire         address_enable_n;
    wire  [7:0]  internal_data_bus;
    wire         memory_write_n;

    cpu_bus_bridge #(.REQ_SETTLE(0)) u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .pace_286          (1'b1),
        .reset             (reset),
        .zet_clk           (zet_clk),
        .wb_dat_o          (wb_dat_o_m),
        .wb_dat_i          (wb_dat_i),
        .wb_adr_o          (wb_adr_m),
        .wb_we_o           (wb_we_m),
        .wb_tga_o          (wb_tga_m),
        .wb_sel_o          (wb_sel_m),
        .wb_stb_o          (wb_stb_m),
        .wb_cyc_o          (wb_cyc_m),
        .wb_ack_i          (wb_ack_i),
        .wb_tgc_o          (1'b0),
        .nmia              (1'b0),
        .processor_status  (processor_status),
        .ad_out            (ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (lock_n),
        .analog_mode       (1'b0),
        .word_access       (word_access),
        .pf_req_len        (pf_req_len),
        .pf_beat_v         (1'b0),
        .pf_beat_dat       (8'h00),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (8'hFF),
        .data_bus          (internal_data_bus),
        .processor_ready   (processor_ready),
        .address_enable_n  (address_enable_n),
        .sdram_wr_taken    (1'b0),
        .sdram_rd_ready    (1'b1),
        .pause_core        (1'b0),
        .throttle          (1'b0),
        .pf_disable        (1'b1),
        .pf_nofill         (1'b0),
        .pf_nofillm        (1'b0),
        .pf_nohit          (1'b0),
        .pf_wkill          (1'b0),
        .pf_bkill          (1'b0),
        .bus_mem_write_n   (memory_write_n),
        .sn_v              (1'b0),
        .sn_addr           (24'd0),
        .sn_len            (4'd0),
        .bios_shadow_flag  (1'b0),
        .biu_done          (),
        .zet_edge_o        (zet_edge),
        .dbg               (),
        .dbg_inta          (),
        .dbg_w             ()
    );

    // core_top's ALE latch
    logic [19:0] cpu_address = 20'h0;
    always_ff @(posedge clk)
        if (address_latch_enable) cpu_address <= ad_out;

    // ---- the real BUS_ARBITER ----------------------------------------------
    wire  [19:0] address;
    wire         address_direction, address_latch_enable;
    wire         data_bus_direction;
    wire         io_read_n, io_read_n_direction;
    wire         io_write_n, io_write_n_direction;
    wire         memory_read_n, memory_read_n_direction;
    wire         memory_write_n_direction;
    wire         no_command_state, interrupt_acknowledge_n;
    wire         processor_transmit_or_receive_n;
    wire         dma_wait_n, dma_ready;
    wire  [7:0]  dbg_hold;
    wire [127:0] dbg_dma_w, dbg_dma3_w;
    wire [15:0]  dbg_w_w;
    wire [31:0]  dbg_w2_w;

    logic        fdd_dma_req = 1'b0;
    wire  [3:0]  dma_request_in = {~fdd_dma_req, ~fdd_dma_req, 1'b1, 1'b1};
    wire  [3:0]  dma_acknowledge_n;
    wire         terminal_count_n;

    // Peripherals' chip selects, verbatim.
    wire pc98_io = (~io_read_n | ~io_write_n) & ~address_enable_n
                 & ~address[9] & ~address[8];
    wire dma_chip_select_n      = ~(pc98_io & address[0] & ~address[7]
                                    & ~address[6] & ~address[5]);
    wire dma_page_chip_select_n = ~(pc98_io & address[0]
                                    & (address[7:4] == 4'h2));

    // The external bus: guest memory answers the DMAC's memory read.
    logic [7:0] mem [0:65535];
    wire  [7:0] data_bus_ext = (~memory_read_n & address_enable_n)
                             ? mem[address[15:0]] : 8'hFF;

    BUS_ARBITER u_arb (
        .clock                              (clk),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .cpu_address                        (cpu_address),
        .cpu_data_bus                       (cpu_data_bus),
        .processor_status                   (processor_status),
        .processor_lock_n                   (lock_n),
        .processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .address                            (address),
        .address_ext                        (20'h0),
        .address_direction                  (address_direction),
        .data_bus_ext                       (data_bus_ext),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_direction                 (data_bus_direction),
        .address_latch_enable               (address_latch_enable),
        .io_read_n                          (io_read_n),
        .io_read_n_ext                      (1'b1),
        .io_read_n_direction                (io_read_n_direction),
        .io_write_n                         (io_write_n),
        .io_write_n_ext                     (1'b1),
        .io_write_n_direction               (io_write_n_direction),
        .memory_read_n                      (memory_read_n),
        .memory_read_n_ext                  (1'b1),
        .memory_read_n_direction            (memory_read_n_direction),
        .memory_write_n                     (memory_write_n),
        .memory_write_n_ext                 (1'b1),
        .memory_write_n_direction           (memory_write_n_direction),
        .no_command_state                   (no_command_state),
        .ext_access_request                 (1'b0),
        .dma_request                        (dma_request_in),
        .dma_acknowledge_n                  (dma_acknowledge_n),
        .address_enable_n                   (address_enable_n),
        .terminal_count_n                   (terminal_count_n),
        .dbg                                (dbg_hold),
        .dbg_dma                            (dbg_dma_w),
        .watch_addr                         (20'h0),
        .dbg_dma3                           (dbg_dma3_w),
        .dbg_w                              (dbg_w_w),
        .dbg_w2                             (dbg_w2_w)
    );

    READY u_ready (
        .clock                              (clk),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .processor_ready                    (processor_ready),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .io_channel_ready                   (1'b1),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .dma0_acknowledge_n                 (dma_acknowledge_n[0]),
        .address_enable_n                   (address_enable_n),
        .dbg                                ()
    );

    // ---- the FDC side: Peripherals' equations verbatim ----------------------
    localparam int SEC = 1024;
    logic [7:0] write_to_fdd = 8'h00;
    always_ff @(posedge clk)
        if (~io_write_n) write_to_fdd <= internal_data_bus;

    wire  fdd_dma_ack = ~dma_acknowledge_n[2] | ~dma_acknowledge_n[3];
    logic prev_fdd_dma_ack = 1'b0;
    always_ff @(posedge clk) prev_fdd_dma_ack <= fdd_dma_ack;
    wire  fdd_dma_rw_ack = prev_fdd_dma_ack & ~fdd_dma_ack;

    logic fdd_dma_tc = 1'b0;
    always_ff @(posedge clk)
        if (fdd_dma_ack) begin
            if (!fdd_dma_tc) fdd_dma_tc <= terminal_count_n;
        end else
            fdd_dma_tc <= 1'b0;

    // floppy.v (write command, DMA mode): dma_req is a level while the
    // sector buffer still wants bytes, dips on the ack pulse, ends at TC.
    int   want = 0;
    logic dma_has_terminated = 1'b1;
    wire  fdd_dma_req_wire = ~dma_has_terminated & ~fdd_dma_rw_ack
                           & (want != 0);
    always_ff @(posedge clk)
        if (fdd_dma_ack)          fdd_dma_req <= 1'b0;
        else if (cpu_ce_negedge)  fdd_dma_req <= fdd_dma_req_wire;

    logic [7:0] sink [0:SEC-1];
    int   got = 0;
    logic start_cmd = 1'b0;          // the FDC accepts a WRITE DATA command
    always_ff @(posedge clk) begin
        if (start_cmd) begin
            got  <= 0;
            want <= SEC;
            dma_has_terminated <= 1'b0;
        end else if (fdd_dma_rw_ack && want != 0) begin
            sink[got] <= write_to_fdd;   // floppy.v: fifo data = dma_readdata
            got  <= got + 1;
            want <= want - 1;
            if (trace)
                $display("[%0t] FDC <= %02x (#%0d)", $time, write_to_fdd, got);
            if (fdd_dma_tc) dma_has_terminated <= 1'b1;
        end
    end

    // Witness: a CPU-owned I/O write strobe while a DACK is still out.
    int cpu_iow_in_dack = 0;
    // Coverage: grants that landed on an armed CPU byte (AEN rising with
    // the bridge in B_CMD) -- the parked-command shape this bench needs.
    int   parked = 0;
    logic aen_q = 1'b0;
    always_ff @(posedge clk) begin
        aen_q <= address_enable_n;
        if (!reset && address_enable_n && !aen_q && u_bridge.bstate == 2'd1)
            parked <= parked + 1;
    end
    always_ff @(posedge clk)
        if (trace > 2 && cpu_ce_posedge)
            $display("[%0t] bst=%0d ps=%03b rdy=%b aen=%b iow=%b t=%0d req=%b", $time,
                     u_bridge.bstate, processor_status, processor_ready,
                     address_enable_n, io_write_n, u_bridge.t_cnt, u_bridge.req_busy);
    always_ff @(posedge clk)
        if (!reset && ~io_write_n && ~address_enable_n && fdd_dma_ack) begin
            cpu_iow_in_dack <= cpu_iow_in_dack + 1;
            if (cpu_iow_in_dack < 3)
                $display("[%0t] CPU IOW under DACK: port %04x data %02x (bridge bstate=%0d status=%03b, dmac state=%0d)",
                         $time, address[15:0], internal_data_bus,
                         u_bridge.bstate, processor_status, dbg_w_w[7:5]);
        end

    // ---- the bench CPU ------------------------------------------------------
    task automatic wb_out(input [15:0] port, input [7:0] val);
        int g;
        begin
            @(posedge clk);
            wb_adr_m   <= {3'b0, port[15:1]};
            wb_sel_m   <= port[0] ? 2'b10 : 2'b01;
            wb_dat_o_m <= {val, val};
            wb_we_m    <= 1'b1;
            wb_tga_m   <= 1'b1;
            wb_cyc_m   <= 1'b1;
            wb_stb_m   <= 1'b1;
            // Drop the request on the very edge the ack is seen -- a
            // master that holds stb one clk past the ack re-captures it.
            g = 0;
            do begin
                @(posedge clk);
                g++;
                if (g > 200000) begin
                    $display("RESULT: FAIL tb_fdc_dma_iow_stray (WB timeout port %04x)", port);
                    $fatal;
                end
            end while (!wb_ack_i);
            if (trace > 1) $display("[%0t] OUT %04x,%02x done", $time, port, val);
            wb_cyc_m <= 1'b0;
            wb_stb_m <= 1'b0;
            wb_we_m  <= 1'b0;
            wb_tga_m <= 1'b0;
        end
    endtask

    localparam logic [19:0] SRC = 20'h04000;

    task automatic arm_dma(input [15:0] a, input [15:0] cnt_m1);
        begin
            wb_out(16'h11, 8'h40);          // DREQ sense active-low
            wb_out(16'h19, 8'h00);          // byte pointer clear
            wb_out(16'h17, 8'h4A);          // single, memory->I/O, ch2
            wb_out(16'h09, a[7:0]);
            wb_out(16'h09, a[15:8]);
            wb_out(16'h23, 8'(SRC[19:16]));
            wb_out(16'h0B, cnt_m1[7:0]);
            wb_out(16'h0B, cnt_m1[15:8]);
            wb_out(16'h15, 8'h02);          // unmask ch2
        end
    endtask

    int i, k, bad20, badx, total20, totalx;
    initial begin
        for (i = 0; i < 65536; i++)
            mem[i] = 8'h80 | 8'(i * 7 + (i >> 7));   // never 0x20
        repeat (20) @(posedge clk);
        reset = 1'b0;
        repeat (100) @(posedge clk);
        wb_out(16'h1B, 8'h00);              // master clear

        total20 = 0; totalx = 0;
        for (k = 0; k < iters; k++) begin
            arm_dma(SRC[15:0], 16'(SEC - 1));
            @(posedge clk) start_cmd <= 1'b1;
            @(posedge clk) start_cmd <= 1'b0;
            @(posedge clk);
            // the game: the IRQ0 handler's EOI, over and over
            while (!dma_has_terminated) begin
                wb_out(16'h00, 8'h20);
                repeat ($urandom_range(0, 24)) @(posedge clk);
            end
            repeat (50) @(posedge clk);
            wb_out(16'h15, 8'h06);          // mask ch2
            bad20 = 0; badx = 0;
            for (i = 0; i < SEC; i++)
                if (sink[i] !== mem[SRC[15:0] + 16'(i)]) begin
                    if (sink[i] == 8'h20) bad20++; else badx++;
                    if (bad20 + badx <= 6)
                        $display("  sector %0d +%03x: got %02x want %02x",
                                 k, i, sink[i], mem[SRC[15:0] + 16'(i)]);
                end
            if (got != SEC) badx++;
            total20 += bad20; totalx += badx;
        end

        $display("speed=%0d iters=%0d bytes/sector=%0d: parked-grants=%0d 0x20-strays=%0d other=%0d cpu-IOW-under-DACK=%0d",
                 speed_sel, iters, SEC, parked, total20, totalx, cpu_iow_in_dack);
        // (At SPEED=3 the bench master never lands a grant on an armed
        // byte; the run still scoreboards the stream.)
        if (parked == 0 && speed_sel != 3) begin
            $display("RESULT: FAIL tb_fdc_dma_iow_stray (no grant landed on a parked command -- bench lost its teeth)");
            $fatal;
        end
        if (total20 + totalx + cpu_iow_in_dack != 0) begin
            $display("RESULT: FAIL tb_fdc_dma_iow_stray");
            $fatal;
        end
        $display("RESULT: PASS tb_fdc_dma_iow_stray");
        $finish;
    end

    initial begin
        #(200_000_000.0 * 1ns);
        $display("  at timeout: got=%0d want=%0d term=%b dmac=%08b drq=%b dack=%b aen=%b bst=%0d mask=%b",
                 got, want, dma_has_terminated, dbg_w_w[7:0], fdd_dma_req,
                 dma_acknowledge_n, address_enable_n, u_bridge.bstate,
                 u_arb.u_upd71071.u_Priority_Encoder.mask_register);
        $display("RESULT: FAIL tb_fdc_dma_iow_stray (global timeout)");
        $fatal;
    end

endmodule

`default_nettype wire
