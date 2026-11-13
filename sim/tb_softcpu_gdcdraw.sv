// tb_softcpu_gdcdraw -- the REAL firmware.vh on the real picorv32 inside the
// real softcpu_subsystem (and with it pc98_gdc_draw), fed random slave-GDC
// LINE commands through the gdc_draw_* handshake. A GVRAM model answers the
// service channel the way pc98_gvram_seq does (own-plane raw reads; plain,
// GRCG RMW and GRCG TDW writes) after a clk_sys latency per op kind, and
// np21w's gdcsub_vectl + gdcpset (io/gdc_sub.c, io/gdc_pset.c), written out
// below on a second VRAM copy, is the reference: after every line the four
// planes must match byte for byte.
//
// It also times each command from the request to the retire pulse -- the
// whole firmware + engine path the guest's DRAWING bit waits on -- and
// prints the per-line / per-dot means.
//
//   +n=<lines> (default 300)  +seed=<n>  +sane (D1 <= 2*DC, for timing)
`timescale 1ns/1ps

module tb_softcpu_gdcdraw;

    reg clk_sys = 0;
    reg reset   = 1;
    always #10 clk_sys = ~clk_sys;   // timed as 42.95 MHz below

    reg        fw_wr_en   = 0;
    reg [13:0] fw_wr_addr = 0;
    reg [31:0] fw_wr_data = 0;

    reg        st_done_r  = 0;
    reg  [7:0] st_rdata_r = 8'h00;
    reg  [7:0] accel      = 8'h00;

    reg  [1:0]   draw_req  = 2'b00;
    reg  [1:0]   draw_busy = 2'b00;
    reg  [15:0]  draw_ops  = 16'h0000;
    reg  [383:0] draw_snap = 384'd0;

    // Boot-time dataslot model: the firmware polls TDS_STATUS for
    // done/ack around every transfer (font load, mounts). Answer every
    // request with ack then a one-cycle done so boot reaches the poll
    // loop.
    wire tds_rd, tds_wr;
    reg  tds_ack = 0, tds_done = 0;
    reg  [7:0] tds_cnt = 0;
    always @(posedge clk_sys) begin
        tds_ack <= tds_rd | tds_wr;
        if (tds_cnt != 0) begin
            tds_cnt  <= tds_cnt - 1;
            tds_done <= (tds_cnt == 8'd2);
        end else begin
            tds_done <= 1'b0;
            if (tds_ack && (tds_rd | tds_wr))
                tds_cnt <= 8'd20;
        end
    end

    wire clk_pico;
    wire        st_req, st_we, st_raw;
    wire [19:0] st_addr;
    wire  [7:0] st_wdata;
    wire  [1:0] done_lv;

    softcpu_subsystem dut (
        .clk_sys (clk_sys),
        .clk_74a (clk_sys),
        .reset   (reset),
        .fw_wr_clk  (clk_sys),
        .fw_wr_en   (fw_wr_en),
        .fw_wr_addr (fw_wr_addr),
        .fw_wr_data (fw_wr_data),
        .clk_pico (clk_pico),
        .fdd_request   (2'b00),
        .fdd0_disk_size(32'd0),
        .fdd1_disk_size(32'd0),
        .hdd0_disk_bytes(32'd0),
        .datatable_addr (),
        .datatable_data (),
        .datatable_wren (),
        .datatable_q    (32'd0),
        .fdd0_rebind (1'b0),
        .fdd1_rebind (1'b0),
        .hdd0_rebind (1'b0),
        .mgmt_addr (), .mgmt_dout (), .mgmt_wr (), .mgmt_rd (),
        .mgmt_din  (16'd0),
        .bridge_wr      (1'b0),
        .bridge_addr    (32'd0),
        .bridge_wr_data (32'd0),
        .target_dataslot_read  (tds_rd),
        .target_dataslot_write (tds_wr),
        .target_dataslot_id    (),
        .target_dataslot_slotoffset (),
        .target_dataslot_bridgeaddr (),
        .target_dataslot_length (),
        .target_dataslot_ack  (tds_ack),
        .target_dataslot_done (tds_done),
        .target_dataslot_err  (3'd0),
        .bridge_rd_data_out (),
        .clk_pix   (clk_sys),
        .osd_hcnt  (10'd0),
        .osd_vcnt  (10'd0),
        .osd_palette_idx (),
        .osd_in_area     (),
        .cont1_key    (16'd0),
        .dock_key_code(8'd0),
        .dock_key_ext (1'b0),
        .dock_key_stb (1'b0),
        .osd_open_req (1'b0),
        .raster_w     (10'd640),
        .raster_h     (10'd400),
        .dataslots_ready (1'b1),
        .soft_guest_hold (),
        .soft_vid_blank  (),
        .scsi_media      (),
        .gdc_draw_req   (draw_req),
        .gdc_draw_busy  (draw_busy),
        .gdc_draw_ops   (draw_ops),
        .gdc_draw_snaps (draw_snap),
        .gdc_srv_done_levels (done_lv),
        .st_req   (st_req),
        .st_we    (st_we),
        .st_raw   (st_raw),
        .st_addr  (st_addr),
        .st_wdata (st_wdata),
        .st_done  (st_done_r),
        .st_rdata (st_rdata_r),
        .accel_status (accel),
        .osd_active   (),
        .osd_disk_led (),
        .osd_extmem   (),
        .osd_dbl_skip (),
        .osd_fdd_turbo (),
        .osd_dipsw2 (), .osd_a3fea (), .osd_a3fee (), .osd_a3ff2 (),
        .vkb_key (), .vkb_stb (),
        .osd_palette  (), .osd_cpu_speed (), .osd_bios_wr (),
        .osd_boost    (), .osd_spk_vol   (), .osd_stereo (),
        .osd_gamepad  (),
        .key_cfg_idx (4'd0), .key_cfg_q (), .key_cfg_diag ()
    );

    // ---- VRAM: planes by np21w's select index {E, B, R, G} --------------
    reg [7:0] vram [0:4*32768-1];
    reg [7:0] rvram[0:4*32768-1];
    reg [7:0] tile [0:3];

    function automatic integer plane_of(input [19:0] a);
        case (a[19:15])
            5'h1C: plane_of = 0;
            5'h15: plane_of = 1;
            5'h16: plane_of = 2;
            5'h17: plane_of = 3;
            default: plane_of = -1;
        endcase
    endfunction

    integer errors = 0;
    integer lat_plain = 12, lat_rmw = 80, lat_tdw = 40;
    integer sv_cnt = 0;
    reg     sv_busy = 0;
    reg     req_s = 0;
    longint n_ops = 0;
    // The sequencer's svc port: one sync stage, the walk, done held until
    // the requester drops its level.
    always @(posedge clk_sys) begin
        integer p, q, o, lat;
        req_s <= st_req;
        if (!req_s) begin
            st_done_r <= 1'b0;
            sv_busy   <= 1'b0;
        end else if (!sv_busy && !st_done_r) begin
            sv_busy <= 1'b1;
            lat = (!st_we || !(accel[0] | accel[2])) ? lat_plain
                : (accel[1] && !accel[2]) ? lat_rmw : lat_tdw;
            sv_cnt  <= lat;
        end else if (sv_busy) begin
            if (sv_cnt == 0) begin
                sv_busy   <= 1'b0;
                st_done_r <= 1'b1;
                n_ops     <= n_ops + 1;
                p = plane_of(st_addr);
                o = st_addr[14:0];
                if (p < 0) begin
                    errors = errors + 1;
                    $display("%0t svc op outside GVRAM: %05x", $time, st_addr);
                end else if (st_raw) begin
                    errors = errors + 1;
                    $display("%0t raw svc op from a LINE", $time);
                end else if (!st_we) begin
                    st_rdata_r <= vram[p*32768 + o];
                end else if (!(accel[0] | accel[2])) begin
                    vram[p*32768 + o] = st_wdata;
                end else if (accel[1] && !accel[2]) begin
                    for (q = 0; q < 4; q = q + 1)
                        vram[q*32768 + o] = (vram[q*32768 + o] & ~st_wdata) | (tile[q] & st_wdata);
                end else begin
                    for (q = 0; q < 4; q = q + 1)
                        vram[q*32768 + o] = tile[q];
                end
            end else
                sv_cnt <= sv_cnt - 1;
        end
    end

    // ---- np21w io/gdc_sub.c gdcsub_vectl / io/gdc_pset.c gdcpset ----------
    reg [15:0] r_pat;
    integer    r_mode, r_plane, r_op;
    integer    r_drawn;
    task automatic r_pset(input [15:0] x, input [15:0] y);
        reg dot;
        integer addr, q;
        reg [7:0] m;
        dot   = r_pat[0];
        r_pat = {r_pat[0], r_pat[15:1]};
        if (y > 409) return;
        if (y == 409) begin if (x >= 384) return; end
        else if (x >= 640) return;
        r_drawn = r_drawn + 1;
        addr = y * 80 + (x >> 3);
        m = 8'h80 >> x[2:0];
        if (r_mode == 0) begin
            case (r_op)
                0: rvram[r_plane*32768 + addr] = dot ? (rvram[r_plane*32768 + addr] | m)
                                                     : (rvram[r_plane*32768 + addr] & ~m);
                1: if (dot) rvram[r_plane*32768 + addr] = rvram[r_plane*32768 + addr] ^ m;
                2: if (dot) rvram[r_plane*32768 + addr] = rvram[r_plane*32768 + addr] & ~m;
                default: if (dot) rvram[r_plane*32768 + addr] = rvram[r_plane*32768 + addr] | m;
            endcase
        end else if (dot) begin
            if (r_mode == 1) begin
                for (q = 0; q < 4; q = q + 1)
                    rvram[q*32768 + addr] = (rvram[q*32768 + addr] & ~m) | (tile[q] & m);
            end else begin
                for (q = 0; q < 4; q = q + 1) begin
                    rvram[q*32768 + (addr & ~1)] = tile[q];
                    rvram[q*32768 + (addr | 1)]  = tile[q];
                end
            end
        end
    endtask

    task automatic r_vectl(input [31:0] csrw, input [15:0] DC, input [15:0] D1,
                           input [2:0] oct, input [15:0] pat);
        reg [15:0] x, y, step;
        integer dc, i;
        r_pat = pat;
        x = 16'((((csrw & 32'h3fff) % 40) << 4) + ((csrw >> 20) & 32'h0f));
        y = 16'((csrw & 32'h3fff) / 40);
        dc = DC & 16'h3fff;
        if (dc == 0) begin
            r_pset(x, y);
            return;
        end
        for (i = 0; i <= dc; i = i + 1) begin
            step = 16'((((D1 * i) / dc) + 1) >> 1);
            case (oct)
                0: begin r_pset(x + step, y); y = y + 1; end
                1: begin r_pset(x, y + step); x = x + 1; end
                2: begin r_pset(x, y - step); x = x + 1; end
                3: begin r_pset(x + step, y); y = y - 1; end
                4: begin r_pset(x - step, y); y = y - 1; end
                5: begin r_pset(x, y - step); x = x - 1; end
                6: begin r_pset(x, y + step); x = x - 1; end
                default: begin r_pset(x - step, y); y = y + 1; end
            endcase
        end
    endtask

    task set_snap(input integer i, input [7:0] b);
        draw_snap[192 + i*8 +: 8] = b;
    endtask

    integer seed = 1, n = 300, verbose = 0, sane = 0;
    // where the time goes: request -> engine launch -> engine idle -> retire
    longint t_req = 0, t_go = 0, t_eng = 0, a_pre = 0, a_eng = 0;
`ifndef NO_LN  // the pre-engine firmware (timing baseline) has no engine to watch
    reg     lnb_q = 0;
    always @(posedge clk_sys) begin
        lnb_q <= dut.ln_busy;
        if (dut.ln_busy && !lnb_q) begin
            t_go = $time; a_pre = a_pre + (t_go - t_req);
            if (verbose) $display("  pre %0d ns", (t_go - t_req) * 50 / 43);
        end
        if (verbose && 0 && dut.cpu_mem_valid && dut.cpu_mem_ready && !dut.cpu_mem_instr && dut.cpu_mem_addr[31:28] == 4'h5)
            $display("  cpu %s %08x at %0d ns", |dut.cpu_mem_wstrb ? "W" : "R", dut.cpu_mem_addr, ($time - t_req) * 50 / 43);
        if (verbose && dut.u_gdc_draw.wr && 0) $display("  wr%0d at %0d ns", dut.u_gdc_draw.wr_sel, ($time - t_req) * 50 / 43);
        if (!dut.ln_busy && lnb_q) a_eng = a_eng + ($time - t_go);
    end
`endif
    longint t_sum = 0, d_sum = 0, t_long = 0, d_long = 0;
    initial begin
        integer i, k, l, dc, d1, oct, wm, mode, dots, mism;
        reg [31:0] csrw;
        reg [15:0] pat;
        longint t0;
        void'($value$plusargs("seed=%d", seed));
        void'($value$plusargs("n=%d", n));
        verbose = $test$plusargs("v");
        sane    = $test$plusargs("sane");   // real lines only: D1 <= 2 * DC
        for (i = 0; i < 4*32768; i = i + 1) begin
            vram[i]  = 8'($urandom(seed + i));
            rvram[i] = vram[i];
        end
        k = $urandom(seed);
        repeat (8) @(posedge clk_sys);
        reset <= 0;
        repeat (4000000) @(posedge clk_sys);
        $display("%0t boot runway done, pc=%08x", $time, dut.pico.reg_pc);

        for (l = 0; l < n; l = l + 1) begin
            k = $urandom % 10;
            dc = (k < 6) ? $urandom % 48 : (k < 9) ? $urandom % 400 : $urandom % 2000;
            d1 = ((sane || ($urandom % 8) != 0) && dc != 0) ? $urandom % (2 * dc + 1) : $urandom % 65536;
            oct = $urandom % 8;
            wm = $urandom % 4;
            k = $urandom % 10;
            mode = (k < 4) ? 0 : (k < 8) ? 1 : 2;
            accel = (mode == 0) ? 8'h00 : (mode == 1) ? 8'h03 : 8'h01;
            for (i = 0; i < 4; i = i + 1) tile[i] = 8'($urandom);
            pat = (($urandom % 4) != 0) ? 16'($urandom) : 16'hFFFF;
            csrw = ($urandom % 16000) | (($urandom % 4) << 14) | (($urandom % 16) << 20);
            for (i = 0; i < 24; i = i + 1) set_snap(i, 8'($urandom));
            set_snap(0, 8'(8'h08 | oct | (($urandom % 2) << 7)));
            set_snap(1, 8'(dc)); set_snap(2, 8'((dc >> 8) | (($urandom % 4) << 6)));
            set_snap(7, 8'(d1)); set_snap(8, 8'(d1 >> 8));
            for (i = 0; i < 4; i = i + 1) set_snap(11 + i, 8'(csrw >> (8 * i)));
            set_snap(15, pat[7:0]); set_snap(16, pat[15:8]);
            set_snap(18, 8'(wm));

            t0 = $time; t_req = $time;
            draw_ops <= 16'h6C00;
            draw_req <= 2'b10;
            for (i = 0; i < 50000000 && !done_lv[1]; i = i + 1) @(posedge clk_sys);
            if (!done_lv[1]) begin
                errors = errors + 1;
                $display("line %0d: never retired", l);
            end
            draw_req <= 2'b00;
            // time in ns at 42.95 MHz: the bench clock is 50 MHz
            t0 = ($time - t0) * 50 / 43;
            while (done_lv[1]) @(posedge clk_sys);

            r_mode = mode; r_plane = (csrw >> 14) & 3; r_op = wm; r_drawn = 0;
            r_vectl(csrw, {draw_snap[192+16 +: 8], draw_snap[192+8 +: 8]}, d1[15:0], oct[2:0], pat);
            dots = dc + 1;
            t_sum = t_sum + t0; d_sum = d_sum + dots;
            if (dots >= 100) begin t_long = t_long + t0; d_long = d_long + dots; end
            mism = 0;
            for (i = 0; i < 4*32768; i = i + 1)
                if (vram[i] !== rvram[i]) begin
                    if (mism < 4)
                        $display("  line %0d MISMATCH plane %0d +%04x: np21w %02x got %02x", l,
                                 i / 32768, i % 32768, rvram[i], vram[i]);
                    mism = mism + 1;
                    rvram[i] = vram[i];
                end
            if (mism) begin
                errors = errors + 1;
                $display("line %0d: csrw=%07x dc=%0d d1=%0d oct=%0d wm=%0d mode=%0d pat=%04x: %0d bytes differ",
                         l, csrw, dc, d1, oct, wm, mode, pat, mism);
            end
            repeat (200) @(posedge clk_sys);
        end
        $display("TIMING: %0d lines, %0d dots, %0d us total; %0.2f us/line, %0.3f us/dot (lines >= 100 dots: %0.3f us/dot)",
                 n, d_sum, t_sum / 1000, real'(t_sum) / 1000.0 / n, real'(t_sum) / 1000.0 / d_sum,
                 d_long ? real'(t_long) / 1000.0 / d_long : 0.0);
        $display("SPLIT: request->engine start %0.2f us/line, engine %0.2f us/line",
                 real'(a_pre) * 50 / 43 / 1000.0 / n, real'(a_eng) * 50 / 43 / 1000.0 / n);
        $display("DONE: %0d svc ops, %0d errors", n_ops, errors);
        if (errors) $display("RESULT: FAIL"); else $display("RESULT: PASS");
        $finish;
    end
endmodule
