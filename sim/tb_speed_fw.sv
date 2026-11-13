// tb_speed_fw -- how long the SHIPPED firmware takes to answer each request
// it services, measured on the real softcpu_subsystem (picorv32 + sprom with
// the committed firmware.vh) at the real clock: clk_sys = clk_chipset
// 42.954545 MHz, clk_pico = clk_sys / 6.
//
// Measurement only (docs/SPEED_VS_REAL.md, scripts/speed_vs_real.sh). Nothing
// here changes RTL or firmware. Every number printed is a "SPD" line:
//
//   SPD <key> claim_us=<t> done_us=<t> [extra]
//
//   claim = request edge -> the firmware's first visible move on it
//           (GDC: first service-channel op; FDD: first dataslot request or
//           FIFO push; SCSI: the request acknowledge)
//   done  = request edge -> the guest-visible completion
//           (GDC: the retire pulse that drops DRAWING; FDD: the sector's
//           last FIFO byte; SCSI: the STATUS write)
//
// The world around the softcore is modelled, and those models set what the
// numbers do NOT include:
//   * the GVRAM sequencer's service channel answers in +svclat clk_pico
//     (default 6; core_top's real round trip depends on guest traffic)
//   * the APF target-dataslot engine starts a transfer +tdslat clk_sys after
//     the request (default 43 = 1 us) and then lands one 32-bit word per
//     +tdsword clk_sys (default 2). The REAL Pocket round trip (ARM + SD) is
//     not modelled -- every "tds=N" in a line says how many transfers the
//     request needed, so the caller can add N x (APF latency) on top.
//   * floppy.v / pc98_scsi / pc98_gdc are register models: request levels,
//     FIFO/buffer counters, the CDB file. Their own RTL timing is NOT here.
//
// Plusargs: +svclat=N +tdslat=N +tdsword=N +quick (GDC rows only)
//   +d88 (drive A is a D88), +opnacaps (answer OPNA CAPS=1: a release
//   firmware built with ENABLE_OPNA then retries rhythm_load -- every pass
//   before fw-latency, every 250 ms since),
//   +pcprof (PC samples), +dbg.
//
`timescale 1ns/1ps

module tb_speed_fw;

    localparam real TCLK = 23.2804;            // 1 / 42.954545 MHz, ns
    reg clk_sys = 0;
    reg reset   = 1;
    always #(TCLK / 2.0) clk_sys = ~clk_sys;

    integer svclat = 6, tdslat = 43, tdsword = 2, quick = 0;
    integer d88 = 0, dbg = 0, opnacaps = 0;

    // ---- disk images: synthesised on the fly ------------------------------
    // Slot 3 (FDD0): a 2HD image, 154 tracks x 8 sectors x 1024 bytes, raw
    // (all-zero, so neither the D88 nor the FDI probe claims it) or D88
    // (0x2B0 header + 16-byte sector headers). Slot 5 (HDD0): flat, zero.
    localparam integer D88_TRK = 8 * (16 + 1024);
    localparam integer D88_SIZE = 688 + 154 * D88_TRK;
    function automatic [7:0] disk_byte(input [15:0] slot, input integer off);
        integer t, s, o, v;
        disk_byte = 8'h00;
        if (slot == 16'd3 && d88) begin
            if (off < 688) begin
                v = 0;
                if (off >= 16'h1C && off < 16'h20) v = D88_SIZE;
                else if (off >= 16'h20) begin
                    t = (off - 16'h20) / 4;
                    if (t < 154) v = 688 + t * D88_TRK;
                end
                disk_byte = 8'((v >> (8 * (off & 3))) & 255);
            end else begin
                o = off - 688;
                t = o / D88_TRK;
                s = (o % D88_TRK) / 1040;
                o = (o % D88_TRK) % 1040;
                if (t < 154)
                    case (o)
                        0:  disk_byte = 8'(t >> 1);
                        1:  disk_byte = 8'(t & 1);
                        2:  disk_byte = 8'(s + 1);
                        3:  disk_byte = 8'd3;
                        4:  disk_byte = 8'd8;
                        14: disk_byte = 8'h00;   // size 0x0400, little endian
                        15: disk_byte = 8'h04;
                        default: disk_byte = 8'h00;
                    endcase
            end
        end
    endfunction

    // ---- APF datatable: {id, size} pairs ----------------------------------
    wire        clk_pico;
    wire  [9:0] dt_addr;
    reg  [31:0] dt_q = 32'd0;
    reg  [31:0] hdd_bytes = 32'd0;
    reg  [31:0] fdd_sectors = 32'd0;
    always @(posedge clk_pico) begin
        case (dt_addr)
            10'd0:   dt_q <= 32'd3;
            10'd1:   dt_q <= fdd_sectors * 512;
            10'd2:   dt_q <= 32'd5;
            10'd3:   dt_q <= hdd_bytes;
            10'd4:   dt_q <= 32'd7;
            10'd5:   dt_q <= 32'd512;
            default: dt_q <= 32'd0;
        endcase
    end

    // ---- target-dataslot engine model -------------------------------------
    wire        tds_rd, tds_wr;
    wire [15:0] tds_id;
    wire [31:0] tds_off, tds_baddr, tds_len;
    reg         tds_ack = 0, tds_done = 0;
    reg         br_wr = 0;
    reg  [31:0] br_addr = 0, br_data = 0;
    integer     tds_n = 0;                // transfers started (all slots)
    integer     tds_busy = 0, tds_wait = 0, tds_w = 0, tds_words = 0;
    integer     tds_wgap = 0;
    reg  [15:0] tds_id_l;
    reg  [31:0] tds_off_l, tds_ba_l;
    reg         tds_is_rd;
    always @(posedge clk_sys) begin
        tds_ack  <= (tds_rd | tds_wr) & !tds_busy;
        br_wr    <= 1'b0;
        tds_done <= 1'b0;
        if (!tds_busy) begin
            if ((tds_rd | tds_wr) && !tds_ack) begin
                tds_busy  = 1;
                tds_n     <= tds_n + 1;
                if (dbg) $display("%0t DBG tds %s id=%0d off=%0d len=%0d", $time,
                                  tds_rd ? "rd" : "wr", tds_id, tds_off, tds_len);
                tds_id_l  <= tds_id;
                tds_off_l <= tds_off;
                tds_ba_l  <= tds_baddr;
                tds_is_rd <= tds_rd;
                tds_words = (tds_len + 3) / 4;
                tds_wait  = tdslat;
                tds_w     = 0;
                tds_wgap  = 0;
            end
        end else if (tds_wait > 0) begin
            tds_wait = tds_wait - 1;
        end else if (tds_w < tds_words) begin
            if (tds_wgap > 0) tds_wgap = tds_wgap - 1;
            else begin
                if (tds_is_rd) begin
                    br_wr   <= 1'b1;
                    br_addr <= tds_ba_l + tds_w * 4;
                    // APF lands file byte 0 in [31:24]; the bridge RAM
                    // reverses it to the word's low byte.
                    br_data <= {disk_byte(tds_id_l, tds_off_l + tds_w*4 + 0),
                                disk_byte(tds_id_l, tds_off_l + tds_w*4 + 1),
                                disk_byte(tds_id_l, tds_off_l + tds_w*4 + 2),
                                disk_byte(tds_id_l, tds_off_l + tds_w*4 + 3)};
                    // sim/stub_altsyncram honours byteena per byte, and the
                    // bridge ties it to 1'b1 (byte 0 only); the megafunction
                    // writes the whole word. Land bytes 1-3 directly.
                    for (int k = 1; k < 4; k++)
                        dut.fdd_bridge.bridgeram.mem[((tds_ba_l + tds_w*4) & 32'hFFC) + k]
                            <= disk_byte(tds_id_l, tds_off_l + tds_w*4 + k);
                end
                if (dbg && tds_w < 2 && tds_is_rd)
                    $display("%0t DBG bw a=%08x d=%02x%02x%02x%02x", $time, tds_ba_l + tds_w * 4,
                             disk_byte(tds_id_l, tds_off_l + tds_w*4 + 0),
                             disk_byte(tds_id_l, tds_off_l + tds_w*4 + 1),
                             disk_byte(tds_id_l, tds_off_l + tds_w*4 + 2),
                             disk_byte(tds_id_l, tds_off_l + tds_w*4 + 3));
                tds_w    = tds_w + 1;
                tds_wgap = tdsword - 1;
            end
        end else begin
            tds_done <= 1'b1;
            tds_busy  = 0;
            if (dbg) $display("%0t DBG mem0 %02x %02x %02x %02x %02x %02x %02x %02x", $time,
                dut.fdd_bridge.bridgeram.mem[0], dut.fdd_bridge.bridgeram.mem[1],
                dut.fdd_bridge.bridgeram.mem[2], dut.fdd_bridge.bridgeram.mem[3],
                dut.fdd_bridge.bridgeram.mem[4], dut.fdd_bridge.bridgeram.mem[5],
                dut.fdd_bridge.bridgeram.mem[6], dut.fdd_bridge.bridgeram.mem[7]);
        end
    end

    // ---- management bus: floppy.v (0xF2) and pc98_scsi (0xF4) models ------
    wire [15:0] mgmt_addr, mgmt_dout;
    wire        mgmt_wr, mgmt_rd;
    wire [7:0]  m_tgt = mgmt_addr[15:8];
    wire [3:0]  m_reg = mgmt_addr[3:0];

    reg  [1:0]  fdd_req = 2'b00;
    reg  [15:0] fdd_reg0 = 16'd0;
    integer     fifo_n = 0, fifo_full = 1024, fdd_present = 0;
    // Event stamps (ns), written ONLY by the always blocks below; the tasks
    // compare them against their own request time (Verilator drops a real
    // that two processes assign).
    real        ev_ack = 0, ev_push1 = 0, ev_full = 0;
    real        t_fdd_mount0 = 0;


    reg         sc_req = 0, sc_ack = 0;
    reg  [4:0]  sc_idx = 0;
    reg  [7:0]  sc_cdb [0:11];
    reg  [7:0]  sc_status = 8'hFF;
    integer     sc_done = 0, sc_put = 0;
    real        t_sc_status = 0;
    reg  [15:0] m_din;
    always @* begin
        m_din = 16'd0;
        if (m_tgt == 8'hF4) begin
            case (m_reg)
                4'd0: m_din = {8'h20, 7'd0, sc_req ^ sc_ack};
                4'd2: m_din = {8'd0, (sc_idx >= 5'd3 && sc_idx < 5'd15)
                                     ? sc_cdb[sc_idx - 5'd3] : 8'h00};
                default: ;
            endcase
        end else if (m_tgt == 8'hF2) begin
            if (m_reg == 4'd0) m_din = fdd_reg0;
        end else if (m_tgt == 8'hF5) begin
            // OPNA (release firmware only): CAPS bit0 = ADPCM-A store fitted
            if (m_reg == 4'd8) m_din = {15'd0, opnacaps[0]};
        end
    end
    always @(posedge clk_sys) begin
        if (m_tgt == 8'hF4 && mgmt_wr) begin
            case (m_reg)
                4'd0: if (mgmt_dout[0]) begin
                          if (dbg) $display("%0t DBG ack wr req=%0d ack=%0d", $time, sc_req, sc_ack);
                          if (sc_ack != sc_req) ev_ack = $realtime;
                          sc_ack <= sc_req;
                      end
                4'd1: sc_idx <= mgmt_dout[4:0];
                4'd2: sc_idx <= sc_idx + 5'd1;
                4'd4: sc_put <= sc_put + 1;
                4'd6: begin
                    sc_status <= mgmt_dout[7:0];
                    sc_done   <= sc_done + 1;
                    t_sc_status = $realtime;
                end
                default: ;
            endcase
        end
        if (m_tgt == 8'hF4 && mgmt_rd && m_reg == 4'd2)
            sc_idx <= sc_idx + 5'd1;
        if (m_tgt == 8'hF2 && mgmt_wr && m_reg == 4'h0)
            fdd_present = mgmt_dout[0];
        if (m_tgt == 8'hF2 && mgmt_wr && m_reg == 4'hF && fdd_req[0]) begin
            if (fifo_n == 0) ev_push1 = $realtime;
            fifo_n = fifo_n + 1;
            if (dbg && (fifo_n == 1 || fifo_n >= 1023)) $display("%0t DBG push %0d", $time, fifo_n);
            if (fifo_n == fifo_full) begin
                ev_full = $realtime;
                fdd_req <= 2'b00;          // floppy.v drops the request on full
            end
        end
    end

    // ---- GDC drawing channel ----------------------------------------------
    reg  [1:0]   draw_req  = 2'b00;
    reg  [15:0]  draw_ops  = 16'h0000;
    reg  [383:0] draw_snap = 384'd0;
    reg  [7:0]   accel     = 8'd0;
    wire  [1:0]  done_lv;
    wire         st_req, st_we, st_raw;
    wire [19:0]  st_addr;
    wire  [7:0]  st_wdata;
    reg          st_done = 0;
    integer      dcnt = 0;
    // st_total / ev_st1 are written only here; a task marks st_mark and
    // reads them (Verilator drops a variable two processes assign).
    integer      st_total = 0, st_mark = 0;
    real         ev_st1 = 0;
    reg          st_req_q = 0;
    always @(posedge clk_pico) begin
        st_req_q <= st_req;
        if (st_req && !st_req_q) begin
            if (st_total == st_mark) ev_st1 = $realtime;
            st_total = st_total + 1;
        end
        if (reset || !st_req) begin
            dcnt    = 0;
            st_done <= 0;
        end else begin
            st_done <= (dcnt == svclat - 1);
            if (dcnt != svclat - 1) dcnt = dcnt + 1;
        end
    end


    // ---- timer-IRQ occupancy: how much of the softcore the OSD tick eats --
    integer irq_cyc = 0, irq_n = 0, irq_max = 0, irq_cur = 0;
    reg     irq_q = 0;
    always @(posedge clk_sys) begin
        irq_q <= dut.pico.irq_active;
        if (dut.pico.irq_active) begin
            irq_cyc = irq_cyc + 1;
            irq_cur = irq_cur + 1;
        end
        if (dut.pico.irq_active && !irq_q) irq_n = irq_n + 1;
        if (!dut.pico.irq_active && irq_q) begin
            if (irq_cur > irq_max) irq_max = irq_cur;
            irq_cur = 0;
        end
    end
    // +pcprof: sample the softcore PC every 61 clk_sys (diagnostic)
    integer pcprof = 0, pcdiv = 0;
    always @(posedge clk_sys) if (pcprof) begin
        pcdiv = pcdiv + 1;
        if (pcdiv == 61) begin
            pcdiv = 0;
            $display("PCS %08x %0d", dut.pico.reg_pc, dut.pico.irq_active);
        end
    end
    real irq_t0;
    integer irq_c0, irq_n0;
    task irq_window_begin;
        irq_t0 = $realtime; irq_c0 = irq_cyc; irq_n0 = irq_n; irq_max = 0;
    endtask
    task irq_window_end(input string key);
        $display("SPD %s claim_us=0 done_us=%0.2f n=%0d busy_pct=%0.1f avg_us=%0.2f max_us=%0.2f",
                 key, ($realtime - irq_t0) / 1000.0, irq_n - irq_n0,
                 100.0 * (irq_cyc - irq_c0) * TCLK / ($realtime - irq_t0),
                 (irq_n > irq_n0 ? (irq_cyc - irq_c0) * TCLK / 1000.0 / (irq_n - irq_n0) : 0.0),
                 irq_max * TCLK / 1000.0);
    endtask

    reg osd_open = 0;
    wire guest_hold;

    softcpu_subsystem dut (
        .clk_sys (clk_sys), .clk_74a (clk_sys), .reset (reset),
        .fw_wr_clk (clk_sys), .fw_wr_en (1'b0), .fw_wr_addr (14'd0), .fw_wr_data (32'd0),
        .clk_pico (clk_pico),
        .fdd_request (fdd_req),
        .fdd0_disk_size (fdd_sectors), .fdd1_disk_size (32'd0),
        .hdd0_disk_bytes (hdd_bytes),
        .datatable_addr (dt_addr), .datatable_data (), .datatable_wren (),
        .datatable_q (dt_q),
        .fdd0_rebind (1'b0), .fdd1_rebind (1'b0), .hdd0_rebind (1'b0),
        .mgmt_addr (mgmt_addr), .mgmt_dout (mgmt_dout),
        .mgmt_wr (mgmt_wr), .mgmt_rd (mgmt_rd), .mgmt_din (m_din),
        .bridge_wr (br_wr), .bridge_addr (br_addr), .bridge_wr_data (br_data),
        .target_dataslot_read (tds_rd), .target_dataslot_write (tds_wr),
        .target_dataslot_id (tds_id), .target_dataslot_slotoffset (tds_off),
        .target_dataslot_bridgeaddr (tds_baddr), .target_dataslot_length (tds_len),
        .target_dataslot_ack (tds_ack), .target_dataslot_done (tds_done),
        .target_dataslot_err (3'd0),
        .bridge_rd_data_out (),
        .clk_pix (clk_sys), .osd_hcnt (10'd0), .osd_vcnt (10'd0),
        .osd_palette_idx (), .osd_in_area (),
        .cont1_key (16'd0), .dock_key_code (8'd0), .dock_key_ext (1'b0), .dock_key_stb (1'b0),
        .osd_open_req (osd_open),
        .raster_w (10'd640), .raster_h (10'd400),
        .dataslots_ready (1'b1),
        .soft_guest_hold (guest_hold), .soft_vid_blank (), .scsi_media (),
        .gdc_draw_req (draw_req), .gdc_draw_busy (2'b00),
        .gdc_draw_ops (draw_ops), .gdc_draw_snaps (draw_snap),
        .gdc_srv_done_levels (done_lv),
        .st_req (st_req), .st_we (st_we), .st_raw (st_raw),
        .st_addr (st_addr), .st_wdata (st_wdata),
        .st_done (st_done), .st_rdata (8'h00),
        .accel_status (accel),
        .osd_active (), .osd_disk_led (), .osd_extmem (), .osd_dbl_skip (),
        .osd_fdd_turbo (),
        .osd_dipsw2 (), .osd_a3fea (), .osd_a3fee (), .osd_a3ff2 (),
        .vkb_key (), .vkb_stb (),
        .osd_palette (), .osd_cpu_speed (), .osd_bios_wr (),
        .osd_boost (), .osd_spk_vol (), .osd_stereo (),
        .osd_gamepad (),
        .key_cfg_idx (4'd0), .key_cfg_q (), .key_cfg_diag ()
    );

    // ---- GDC request helpers ----------------------------------------------
    task set_snap(input integer i, input [7:0] b);
        draw_snap[192 + i*8 +: 8] = b;
    endtask
    task clear_snap;
        for (int i = 0; i < 24; i++) set_snap(i, 8'd0);
    endtask
    // VECTW/TEXTE snapshot: ope (dir | figure bits), dc, d, d2, d1, dm,
    // csrw EAD (plane B = 0x4000 | word), textw pattern, write mode.
    task snap_vect(input [7:0] ope, input [13:0] dc, input [13:0] d,
                   input [13:0] d2, input [13:0] d1, input [13:0] dm,
                   input [15:0] ead, input [15:0] pat, input [7:0] wmode);
        clear_snap;
        set_snap(0, ope);
        set_snap(1, dc[7:0]);  set_snap(2, {2'b00, dc[13:8]});
        set_snap(3, d[7:0]);   set_snap(4, {2'b00, d[13:8]});
        set_snap(5, d2[7:0]);  set_snap(6, {2'b00, d2[13:8]});
        set_snap(7, d1[7:0]);  set_snap(8, {2'b00, d1[13:8]});
        set_snap(9, dm[7:0]);  set_snap(10, {2'b00, dm[13:8]});
        set_snap(11, ead[7:0]); set_snap(12, ead[15:8]);
        set_snap(15, pat[7:0]); set_snap(16, pat[15:8]);
        set_snap(18, wmode);
    endtask
    task snap_wdat(input [15:0] words, input [15:0] ead);
        clear_snap;
        set_snap(1, 8'(words - 1)); set_snap(2, 8'((words - 1) >> 8));
        set_snap(11, ead[7:0]); set_snap(12, ead[15:8]);
        set_snap(18, 8'h20);
        set_snap(19, 8'hFF); set_snap(20, 8'hFF);
        set_snap(21, 8'hFF); set_snap(22, 8'hFF);
    endtask

    real t_req, t_done;
    integer ops0;
    // Raise the slave's request; wait for the retire level (bounded).
    task gdc_issue(input [7:0] opcode);
        st_mark = st_total;
        draw_ops <= {opcode, 8'h00};
        draw_req <= 2'b10;
        t_req = $realtime;
    endtask
    task gdc_wait(input integer limit_ms);
        real lim;
        lim = $realtime + limit_ms * 1.0e6;
        while (!done_lv[1] && $realtime < lim) @(posedge clk_sys);
        t_done = $realtime;
        draw_req <= 2'b00;
        while (done_lv[1]) @(posedge clk_sys);
        repeat (20) @(posedge clk_sys);
    endtask
    task gdc_report(input string key, input integer dots, input string ref_note);
        $display("SPD %s claim_us=%0.2f done_us=%0.2f ops=%0d dots=%0d %s", key,
                 (st_total > st_mark ? (ev_st1 - t_req) / 1000.0 : -1.0),
                 (t_done - t_req) / 1000.0, st_total - st_mark, dots, ref_note);
    endtask
    task gdc_run(input string key, input [7:0] opcode, input integer dots);
        gdc_issue(opcode);
        gdc_wait(400);
        gdc_report(key, dots, "");
    endtask

    // ---- FDD / SCSI request helpers ---------------------------------------
    integer tds0;
    task fdd_read(input string key, input integer lba);
        tds0 = tds_n;
        fifo_n = 0;
        fdd_reg0 <= 16'(lba);
        @(posedge clk_sys);
        fdd_req <= 2'b01;
        t_req = $realtime;
        while (fdd_req != 2'b00 && $realtime < t_req + 200.0e6) @(posedge clk_sys);
        $display("SPD %s claim_us=%0.2f done_us=%0.2f tds=%0d bytes=%0d", key,
                 (ev_push1 > t_req ? (ev_push1 - t_req) / 1000.0 : -1.0),
                 (ev_full > t_req ? (ev_full - t_req) / 1000.0 : -1.0),
                 tds_n - tds0, fifo_n);
        fdd_req <= 2'b00;
        // the prefetch of lba+1 runs after the push: let it land
        repeat (43 * 400) @(posedge clk_sys);
    endtask

    integer scd0;
    task scsi_post(input [7:0] op, input [31:0] lba, input [15:0] blocks);
        for (int i = 0; i < 12; i++) sc_cdb[i] = 8'h00;
        sc_cdb[0] = op;
        if (op == 8'h28 || op == 8'h2A) begin
            sc_cdb[2] = lba[31:24]; sc_cdb[3] = lba[23:16];
            sc_cdb[4] = lba[15:8];  sc_cdb[5] = lba[7:0];
            sc_cdb[7] = blocks[15:8]; sc_cdb[8] = blocks[7:0];
        end
        scd0 = sc_done;
        tds0 = tds_n;
        sc_put = 0;
        @(posedge clk_sys);
        sc_req <= ~sc_req;
        t_req = $realtime;
    endtask
    task scsi_wait(input string key);
        while (sc_done == scd0 && $realtime < t_req + 400.0e6) @(posedge clk_sys);
        $display("SPD %s claim_us=%0.2f done_us=%0.2f tds=%0d put=%0d status=%02x", key,
                 (ev_ack > t_req ? (ev_ack - t_req) / 1000.0 : -1.0),
                 (t_sc_status - t_req) / 1000.0, tds_n - tds0, sc_put, sc_status);
        repeat (200) @(posedge clk_sys);
    endtask
    task scsi_cmd(input string key, input [7:0] op, input [31:0] lba, input [15:0] blocks);
        scsi_post(op, lba, blocks);
        scsi_wait(key);
    endtask

    task wait_us(input real us);
        real t;
        t = $realtime + us * 1000.0;
        while ($realtime < t) @(posedge clk_sys);
    endtask

    // Pseudo-random start phases for the idle-latency rows.
    integer seed = 1234;
    reg [31:0] pc_at_req;
    real lat_min, lat_max, lat_sum;

    initial begin
        void'($value$plusargs("svclat=%d", svclat));
        void'($value$plusargs("tdslat=%d", tdslat));
        void'($value$plusargs("tdsword=%d", tdsword));
        if ($test$plusargs("quick")) quick = 1;
        if ($test$plusargs("d88")) d88 = 1;
        if ($test$plusargs("dbg")) dbg = 1;
        if ($test$plusargs("opnacaps")) opnacaps = 1;
        $display("CFG svclat=%0d tdslat=%0d tdsword=%0d quick=%0d d88=%0d",
                 svclat, tdslat, tdsword, quick, d88);

        repeat (8) @(posedge clk_sys);
        reset <= 0;

        // ---- boot: reset -> guest released (firmware share only) ----------
        while (guest_hold !== 1'b0 && $realtime < 2.0e9) @(posedge clk_sys);
        $display("SPD boot_release claim_us=0 done_us=%0.2f tds=%0d",
                 $realtime / 1000.0, tds_n);
        wait_us(3000);   // first main-loop passes, timer armed
        irq_window_begin;
        wait_us(30000);
        irq_window_end("irq_tick_osd_closed_boot");
        irq_window_begin;
        if ($test$plusargs("pcprof")) pcprof = 1;
        wait_us(20000);
        pcprof = 0;
        irq_window_end("irq_tick_osd_closed");

        // ---- GDC: idle-loop latency, nothing mounted ----------------------
        lat_min = 1e9; lat_max = 0; lat_sum = 0;
        for (int k = 0; k < 12; k++) begin
            wait_us(37.0 + ($urandom(seed + k) % 1500) / 1.0);
            snap_vect(8'h00, 0, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
            gdc_issue(8'h6C);
            pc_at_req = dut.pico.reg_pc;
            gdc_wait(50);
            $display("SMP gdc_claim k=%0d us=%0.2f pc=%08x", k,
                     (ev_st1 - t_req) / 1000.0, pc_at_req);
            if (ev_st1 - t_req < lat_min) lat_min = ev_st1 - t_req;
            if (ev_st1 - t_req > lat_max) lat_max = ev_st1 - t_req;
            lat_sum = lat_sum + (ev_st1 - t_req);
            if (k == 0) gdc_report("gdc_dot", 1, "");
        end
        $display("SPD gdc_idle_claim claim_us=%0.2f done_us=%0.2f min_us=%0.2f n=12",
                 lat_sum / 12000.0, lat_max / 1000.0, lat_min / 1000.0);

        // ---- GDC drawing rows ---------------------------------------------
        // line: octant 1 (x-major), dc = dots-1, d1 = 2*dy... a 45-ish slope
        snap_vect(8'h09, 99, 0, 0, 50, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_run("gdc_line100", 8'h6C, 100);
        snap_vect(8'h0A, 399, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_run("gdc_line400h", 8'h6C, 400);
        // GRCG TDW armed: each lit dot = two word-half writes, no read
        accel <= 8'h01;
        snap_vect(8'h09, 99, 0, 0, 50, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_run("gdc_line100_grcg", 8'h6C, 100);
        accel <= 8'h00;
        // dashed pattern: half the dots read-modify-write a zero
        snap_vect(8'h09, 99, 0, 0, 50, 0, 16'h4000, 16'h00FF, 8'h6C);
        gdc_run("gdc_line100_dash", 8'h6C, 100);
        // circle octant: r = 100 -> m = 71 dots (i = 0..t), np21w vectc
        snap_vect(8'h20, 71, 100, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_run("gdc_arc_r100", 8'h6C, 72);
        snap_vect(8'h20, 4, 7, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_run("gdc_arc_r7", 8'h6C, 5);
        // rectangle 100 x 50 = 300 dots
        snap_vect(8'h42, 0, 100, 50, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_run("gdc_rect100x50", 8'h6C, 300);
        // pattern fill line (VECTE + T bit, the 'graphic char' 16-dot run)
        snap_vect(8'h12, 0, 16, 0, 0, 0, 16'h4000, 16'hAAAA, 8'h6C);
        gdc_run("gdc_vectt16", 8'h6C, 8);
        // TEXTE: an 8 x 8 cell (64 dot slots, pattern 0x55/0xAA halves on)
        snap_vect(8'h12, 7, 8, 0, 0, 0, 16'h4000, 16'hAA55, 8'h68);
        gdc_run("gdc_texte8x8", 8'h68, 32);
        // WDAT word runs (area fills, the BIOS clear)
        snap_wdat(16'd1, 16'h4000);
        gdc_run("gdc_wdat1", 8'h20, 1);
        snap_wdat(16'd40, 16'h4000);
        gdc_run("gdc_wdat40", 8'h20, 40);
        if (!quick) begin
            snap_wdat(16'd1000, 16'h4000);
            gdc_run("gdc_wdat1000", 8'h20, 1000);
            snap_vect(8'h0A, 639, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
            gdc_run("gdc_line640h", 8'h6C, 640);
        end

        // ---- OSD open while a line draws (IRQ repaint steals the loop) ---
        snap_vect(8'h0A, 399, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_issue(8'h6C);
        osd_open <= 1'b1;
        gdc_wait(400);
        gdc_report("gdc_line400h_osdopen", 400, "");
        osd_open <= 1'b0;
        irq_window_begin;
        wait_us(20000);
        irq_window_end("irq_tick_osd_open");
        // close again (the open action toggles)
        osd_open <= 1'b1; wait_us(3000); osd_open <= 1'b0; wait_us(20000);

        if (quick) begin
            $display("RESULT: DONE (quick)");
            $finish;
        end

        // ---- SCSI: mount a 20 MB flat image -------------------------------
        hdd_bytes <= 32'd20 * 1024 * 1024;
        wait_us(20000);
        scsi_cmd("scsi_tur_first", 8'h00, 0, 0);     // re-probe rides it
        scsi_cmd("scsi_tur", 8'h00, 0, 0);
        scsi_cmd("scsi_read10_1", 8'h28, 100, 1);
        scsi_cmd("scsi_read10_8", 8'h28, 200, 8);
        scsi_cmd("scsi_read10_16", 8'h28, 300, 16);
        scsi_cmd("scsi_write10_1", 8'h2A, 400, 1);
        scsi_cmd("scsi_write10_8", 8'h2A, 500, 8);
        scsi_cmd("scsi_inquiry", 8'h12, 0, 0);

        // ---- FDD: mount drive A -------------------------------------------
        fdd_sectors <= d88 ? (D88_SIZE / 512) : 32'd2464;
        t_fdd_mount0 = $realtime;
        while (!fdd_present && $realtime < t_fdd_mount0 + 2.0e9) @(posedge clk_sys);
        tds0 = tds_n;
        $display("SPD fdd_mount claim_us=0 done_us=%0.2f", ($realtime - t_fdd_mount0) / 1000.0);
        wait_us(30000);   // the image hash reads that follow PRESENT
        fdd_read("fdd_rd_cold", 40);       // track 5, cold
        fdd_read("fdd_rd_seq", 41);        // prefetch hit
        fdd_read("fdd_rd_seq2", 42);
        fdd_read("fdd_rd_rand", 900);      // far track, cold
        fdd_read("fdd_rd_same_trk", 902);  // same track, not prefetched

        // ---- contention: one service holds the loop, another waits -------
        // (1) GDC dot posted just after a SCSI 16-block read
        scsi_post(8'h28, 1000, 16);
        while (!(ev_ack > t_req)) @(posedge clk_sys);   // the loop owns it
        wait_us(30);
        snap_vect(8'h00, 0, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        begin
            real tq;
            tq = $realtime;
            gdc_issue(8'h6C);
            gdc_wait(400);
            $display("SPD gdc_dot_behind_scsi16 claim_us=%0.2f done_us=%0.2f",
                     (ev_st1 - tq) / 1000.0, (t_done - tq) / 1000.0);
        end
        while (sc_done == scd0) @(posedge clk_sys);
        repeat (200) @(posedge clk_sys);
        // (2) SCSI TUR posted just after a 640-dot line starts
        snap_vect(8'h0A, 639, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_issue(8'h6C);
        while (st_total == st_mark) @(posedge clk_sys);          // the draw is running
        wait_us(50);
        scsi_post(8'h00, 0, 0);
        gdc_wait(400);
        scsi_wait("scsi_tur_behind_line640");
        // (3) FDD read posted just after a 640-dot line starts
        snap_vect(8'h0A, 639, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_issue(8'h6C);
        while (st_total == st_mark) @(posedge clk_sys);
        wait_us(50);
        begin
            real tg;
            tds0 = tds_n;
            fifo_n = 0;
            fdd_reg0 <= 16'd1100;
            fdd_req <= 2'b01;
            tg = $realtime;
            gdc_wait(400);
            while (fdd_req != 2'b00 && $realtime < tg + 200.0e6) @(posedge clk_sys);
            $display("SPD fdd_rd_behind_line640 claim_us=%0.2f done_us=%0.2f tds=%0d",
                     (ev_push1 - tg) / 1000.0, (ev_full - tg) / 1000.0, tds_n - tds0);
            repeat (43 * 400) @(posedge clk_sys);
        end
        // (4) GDC dot posted just after a cold-track FDD read
        begin
            real tq;
            tds0 = tds_n;
            fifo_n = 0;
            fdd_reg0 <= 16'd2000;
            fdd_req <= 2'b01;
            while (tds_n == tds0) @(posedge clk_sys);    // the loop owns it
            wait_us(10);
            snap_vect(8'h00, 0, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
            tq = $realtime;
            gdc_issue(8'h6C);
            gdc_wait(400);
            $display("SPD gdc_dot_behind_fdd_cold claim_us=%0.2f done_us=%0.2f",
                     (ev_st1 - tq) / 1000.0, (t_done - tq) / 1000.0);
            while (fdd_req != 2'b00) @(posedge clk_sys);
            repeat (43 * 400) @(posedge clk_sys);
        end
        // (4b) SCSI TUR posted right after a GDC dot retires: the loop
        // lingers on the GDC request line (GDC_LINGER polls) first
        snap_vect(8'h00, 0, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_issue(8'h6C);
        gdc_wait(50);
        scsi_cmd("scsi_tur_after_gdc_dot", 8'h00, 0, 0);
        snap_vect(8'h00, 0, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
        gdc_issue(8'h6C);
        gdc_wait(50);
        fdd_read("fdd_rd_after_gdc_dot", 1500);
        // (5) idle claim with both disks mounted (every poll runs)
        lat_min = 1e9; lat_max = 0; lat_sum = 0;
        for (int k = 0; k < 12; k++) begin
            wait_us(37.0 + ($urandom(seed + 77 + k) % 1500) / 1.0);
            snap_vect(8'h00, 0, 0, 0, 0, 0, 16'h4000, 16'hFFFF, 8'h6C);
            gdc_issue(8'h6C);
            pc_at_req = dut.pico.reg_pc;
            gdc_wait(50);
            $display("SMP gdc_claim k=%0d us=%0.2f pc=%08x", k,
                     (ev_st1 - t_req) / 1000.0, pc_at_req);
            if (ev_st1 - t_req < lat_min) lat_min = ev_st1 - t_req;
            if (ev_st1 - t_req > lat_max) lat_max = ev_st1 - t_req;
            lat_sum = lat_sum + (ev_st1 - t_req);
        end
        $display("SPD gdc_idle_claim_mounted claim_us=%0.2f done_us=%0.2f min_us=%0.2f n=12",
                 lat_sum / 12000.0, lat_max / 1000.0, lat_min / 1000.0);
        lat_min = 1e9; lat_max = 0; lat_sum = 0;
        for (int k = 0; k < 8; k++) begin
            wait_us(37.0 + ($urandom(seed + 177 + k) % 1500) / 1.0);
            scsi_post(8'h00, 0, 0);
            pc_at_req = dut.pico.reg_pc;
            while (sc_done == scd0) @(posedge clk_sys);
            $display("SMP scsi_claim k=%0d us=%0.2f pc=%08x", k,
                     (ev_ack - t_req) / 1000.0, pc_at_req);
            if (ev_ack - t_req < lat_min) lat_min = ev_ack - t_req;
            if (ev_ack - t_req > lat_max) lat_max = ev_ack - t_req;
            lat_sum = lat_sum + (ev_ack - t_req);
        end
        $display("SPD scsi_idle_claim_mounted claim_us=%0.2f done_us=%0.2f min_us=%0.2f n=8",
                 lat_sum / 8000.0, lat_max / 1000.0, lat_min / 1000.0);

        $display("RESULT: DONE");
        $finish;
    end

endmodule
