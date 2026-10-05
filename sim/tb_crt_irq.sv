//
// tb_crt_irq -- the GDC CRT interrupt's np21w cadence, exercised through
// the whole PERIPHERALS block: the real i8259 pair, the real raster from
// pc98_video_timing (pc98_vb is its vblank), the real port-0x64 arm decode
// and the real vector path during INTA.
//
// What np21w does (io/gdc.c gdc_o64, pccore.c screenvsync/screendisp,
// io/pic.c pic_setirq):
//
//   * any write to 0x64 arms the one-shot (gdc.vsyncint = 1);
//   * the start of vblank (screenvsync) consumes the arm and delivers
//     IRQ2 -- vector 0x0A (master PIC ICW2 base 0x08 + IR2);
//   * a serviced request is CONSUMED: no second interrupt until the next
//     0x64 write;
//   * a request still pending at the end of vblank (screendisp -- masked,
//     never acknowledged) is cancelled in the IRR and the arm restored,
//     so the next frame retries.
//
// The checks:
//   A. arm -> vblank -> INT, vector 0x0A.
//   B. no second IRQ on the following vblank (service consumed the arm).
//   C. re-arm -> IRQ again.
//   D. armed with IRQ2 masked: the latched request is cancelled at the
//      display edge, so unmasking mid-frame raises nothing; the retry
//      lands on the NEXT vblank.
//
`timescale 1ns/1ps
`default_nettype none

module tb_crt_irq;

    // clock: the chipset clock (~42.95 MHz; 24 ns here). clk_pc98_dot:
    // the raster's dot clock (~21.05 MHz; 48 ns). Deliberately incommensurate
    // so the two-flop vblank synchronisers see a real crossing.
    logic clock = 1'b0, dot = 1'b0;
    always #12 clock = ~clock;
    always #24 dot   = ~dot;

    logic        reset = 1'b1;
    logic [19:0] address = 20'h0;
    logic [7:0]  din = 8'h00;
    logic        io_rd = 1'b1, io_wr = 1'b1;
    logic        mem_rd = 1'b1, mem_wr = 1'b1;
    logic        aen_n = 1'b0;
    logic        inta_n = 1'b1;

    wire         int_to_cpu;
    wire [7:0]   dout;
    wire         dout_cs;
    wire         vid_vb, vid_vs, vid_hb, vid_hs, de_o;

    int errors = 0;

    task automatic want(input string name, input logic [7:0] got,
                        input logic [7:0] exp);
        if (got !== exp) begin
            errors = errors + 1;
            $display("*** FAIL: %s  got %02h want %02h", name, got, exp);
        end else
            $display("ok   %-44s %02h", name, got);
    endtask

    task automatic wantb(input string name, input logic got,
                         input logic exp);
        if (got !== exp) begin
            errors = errors + 1;
            $display("*** FAIL: %s  got %0d want %0d", name, got, exp);
        end else
            $display("ok   %-44s %0d", name, got);
    endtask

    // An I/O write on the chipset clock, long enough for every level
    // sensitive decode to see it (gdc_arm_w is a level while io_write_n is
    // low).
    task automatic iow(input logic [15:0] a, input logic [7:0] d);
        begin
            @(negedge clock);
            address = {4'h0, a}; din = d; io_wr = 1'b0;
            repeat (6) @(negedge clock);
            io_wr = 1'b1;
            din = 8'h00;
            repeat (8) @(negedge clock);
        end
    endtask

    // Two INTA pulses the way the 8288 sequences them; the vector lands on
    // the second. data_bus_out is registered, so it needs a couple of
    // clocks into the pulse.
    task automatic inta_cycle(output logic [7:0] vec);
        begin
            @(negedge clock);
            inta_n = 1'b0;
            repeat (6) @(negedge clock);
            inta_n = 1'b1;
            repeat (6) @(negedge clock);
            inta_n = 1'b0;
            repeat (4) @(negedge clock);
            vec = dout;
            repeat (2) @(negedge clock);
            inta_n = 1'b1;
            repeat (8) @(negedge clock);
        end
    endtask

    // Wait for interrupt_to_cpu, deadline in chipset clocks.
    task automatic wait_int(input int deadline, output bit ok);
        begin
            ok = 1'b0;
            repeat (deadline) begin
                @(posedge clock);
                if (int_to_cpu) ok = 1'b1;
            end
        end
    endtask

    // Confirm interrupt_to_cpu stays low for `span` chipset clocks.
    task automatic want_no_int(input string name, input int span);
        bit fired;
        begin
            fired = 1'b0;
            repeat (span) begin
                @(posedge clock);
                if (int_to_cpu) fired = 1'b1;
            end
            wantb(name, fired, 1'b0);
        end
    endtask

    PERIPHERALS u_periph (
        .clock                  (clock),
        .pc98_analog            (),
        .grcg_active            (),
        .grcg_rmw               (),
        .grcg_mask              (),
        .grcg_tile              (),
        .gvram_disp_page        (),
        .gvram_access_page      (),
        .egc_active             (),
        .egc_wr                 (),
        .egc_rg                 (),
        .egc_d                  (),
        .cpu_ce_negedge         (1'b1),
        .clk_select             (2'b00),
        .reset                  (reset),
        .interrupt_to_cpu       (int_to_cpu),
        .interrupt_acknowledge_n(inta_n),
        .dma_chip_select_n      (),
        .dma_page_chip_select_n (),
        .clk_pc98_dot           (dot),
        .de_o                   (de_o),
        .font_rd_req            (),
        .font_rd_addr           (),
        .font_rd_len            (),
        .font_rd_ack            (1'b0),
        .font_rd_valid          (1'b0),
        .font_rd_data           (16'h0),
        .font_rd_done           (1'b0),
        .cg_rd_req              (),
        .cg_rd_addr             (),
        .cg_rd_len              (),
        .cg_rd_ack              (1'b0),
        .cg_rd_valid            (1'b0),
        .cg_rd_data             (16'h0),
        .cg_rd_done             (1'b0),
        .gv_rd_req              (),
        .gv_rd_addr             (),
        .gv_rd_len              (),
        .gv_rd_ack              (1'b0),
        .gv_rd_valid            (1'b0),
        .gv_rd_data             (16'h0),
        .gv_rd_done             (1'b0),
        .font_wr_clk            (1'b0),
        .font_wr_en             (1'b0),
        .font_wr_addr           (12'h0),
        .font_wr_data           (16'h0),
        .VID_R                  (),
        .VID_G                  (),
        .VID_B                  (),
        .VID_HSYNC              (vid_hs),
        .VID_VSYNC              (vid_vs),
        .VID_HBlank             (vid_hb),
        .VID_VBlank             (vid_vb),
        .dbl200                 (),
        .mabiki                 (),
        .VID_TXT                (),
        .address                (address),
        .latch_address          (),
        .internal_data_bus      (din),
        .data_bus_out           (dout),
        .data_bus_out_from_chipset(dout_cs),
        .scsi_rom_hi            (),
        .interrupt_request      (8'h00),
        .io_read_n              (io_rd),
        .io_write_n             (io_wr),
        .memory_read_n          (mem_rd),
        .memory_write_n         (mem_wr),
        .address_enable_n       (aen_n),
        .timer_counter_out      (),
        .speaker_out            (),
        .kb_byte                (8'h00),
        .kb_valid               (1'b0),
        .kb_ready               (),
        .gdc_draw_req           (),
        .gdc_draw_busy          (),
        .gdc_draw_ops           (),
        .gdc_draw_snaps         (),
        .gdc_srv_done_levels    (2'b00),
        .gdc_draw_to            (),
        .dbg_egc_flag           (),
        .dbg_sysport            (),
        .tvram_dbg_cell         (12'h0),
        .tvram_dbg_word         (),
        .tvram_dbg_q            (),
        .opna_snd_l             (),
        .opna_snd_r             (),
        .mgmt_address           (16'h0),
        .mgmt_read              (1'b0),
        .mgmt_readdata          (),
        .mgmt_write             (1'b0),
        .mgmt_writedata         (16'h0),
        .floppy_wp              (2'b11),
        .fdd_turbo              (1'b0),
        .cfg_dipsw2             (8'h00),
        .cfg_a3fea              (8'h00),
        .cfg_a3fee              (8'h00),
        .cfg_a3ff2              (8'h00),
        .rtc_time               (48'h0),
        .fdd_present            (),
        .fdd_request            (),
        .fdd_media_req          (),
        .scsi_request           (),
        .dbg_scsi               (),
        .fdd_dma_req            (),
        .dbg_fdc                (),
        .dbg_fdc_cmd            (),
        .dbg_gdc_s              (),
        .fdd_dma_ack            (1'b0),
        .terminal_count         (1'b0),
        .pause_core             (),
        .pc98_key_stb           (1'b0),
        .pc98_key_byte          (8'h00),
        .mouse_dx               (16'sd0),
        .mouse_dy               (16'sd0),
        .mouse_ev               (1'b0),
        .mouse_btn              (2'b00),
        .opna_joy               (8'hFF)
    );

    logic [7:0] vec;
    bit  got;
    int  frames = 0;

    // Frame counter on the raster, for the diagnostics.
    always @(posedge vid_vb) frames = frames + 1;

    initial begin
        // Let the raster start while reset is still asserted, so the first
        // vblank after reset is a clean edge and not a startup transient.
        repeat (40) @(negedge clock);
        reset = 1'b0;
        repeat (20) @(negedge clock);

        // The VM BIOS's master ICWs (FDA2F-FDA3D): edge triggered, cascade,
        // ICW4; vectors 08-0F; slave on IRQ7; 8086 mode. Then mask all.
        iow(16'h0000, 8'h11);   // ICW1
        iow(16'h0002, 8'h08);   // ICW2
        iow(16'h0002, 8'h80);   // ICW3: slave on IR7
        iow(16'h0002, 8'h1D);   // ICW4
        iow(16'h0002, 8'hFF);   // IMR

        // The slave at 0x08/0x0A gets its own init (ITF F8060E): vectors
        // 10-17h, slave id 7, ICW4 09h -- NOT the master's 1Dh. With BUF=1
        // (1Dh bit 3) the chip ignores the slave_program_n pin and takes
        // its role from ICW4 bit 2, so a copied 1Dh makes it a buffered
        // MASTER that answers every INTA with its own reset vector.
        iow(16'h0008, 8'h11);   // ICW1
        iow(16'h000A, 8'h10);   // ICW2: vectors 10-17h
        iow(16'h000A, 8'h07);   // ICW3: slave id 7
        iow(16'h000A, 8'h09);   // ICW4: 8086, non-buffered -> pin says slave
        iow(16'h000A, 8'hFF);   // IMR

        // =========================================================
        // A. arm, unmask IRQ2, the next vblank must deliver INT 0x0A.
        // =========================================================
        iow(16'h0002, 8'hFB);   // IMR: unmask IRQ2 only
        iow(16'h0064, 8'h00);   // np21w gdc_o64: vsyncint = 1
        @(posedge vid_vb);      // screenvsync
        wait_int(4000, got);
        wantb("A: IRQ2 delivered at vblank", got, 1'b1);
        inta_cycle(vec);
        want ("A: vector is INT 0x0A", vec, 8'h0A);

        // =========================================================
        // B. The arm is consumed: the next vblank raises nothing.
        //    Sit through the whole rest of this frame plus the entire
        //    next vblank and a chunk of the frame after.
        // =========================================================
        @(negedge vid_vb);                 // display restarts
        want_no_int("B: quiet until next vblank", 4000);
        @(posedge vid_vb);                 // screenvsync again
        want_no_int("B: service consumed the arm", 20000);

        // =========================================================
        // C. Re-arm, the next vblank delivers again.
        // =========================================================
        iow(16'h0064, 8'h00);
        @(negedge vid_vb);
        @(posedge vid_vb);
        wait_int(4000, got);
        wantb("C: re-arm delivers next frame", got, 1'b1);
        inta_cycle(vec);
        want ("C: vector is INT 0x0A", vec, 8'h0A);

        // =========================================================
        // D. Masked at the vblank edge: the request latches, then the
        //    display edge cancels it and restores the arm (screendisp).
        //    Unmasking mid-display must NOT fire -- the latched IRR bit
        //    is gone -- and the retry lands on the NEXT vblank.
        // =========================================================
        iow(16'h0002, 8'hFF);   // mask everything
        iow(16'h0064, 8'h00);   // arm
        @(posedge vid_vb);      // the masked edge: crt_pend latches
        want_no_int("D: masked edge stays quiet", 4000);
        @(negedge vid_vb);      // screendisp: cancel + re-arm
        iow(16'h0002, 8'hFB);   // unmask mid-display
        want_no_int("D: unmask after cancel stays quiet", 20000);
        @(posedge vid_vb);      // the retry's screenvsync
        wait_int(4000, got);
        wantb("D: retry lands next vblank", got, 1'b1);
        inta_cycle(vec);
        want ("D: retry vector is INT 0x0A", vec, 8'h0A);

        if (errors == 0) $display("PASS tb_crt_irq (%0d frames)", frames);
        else             $display("FAIL tb_crt_irq errors=%0d", errors);
        $finish;
    end

    // Whole-run watchdog: ten frames is far more than the test needs.
    initial begin
        repeat (10 * 440) @(posedge vid_hb);
        $display("*** FAIL: watchdog -- %0d frames elapsed", frames);
        $finish;
    end

endmodule
`default_nettype wire
