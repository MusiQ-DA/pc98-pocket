// tb_softcpu_gdcdraw -- the REAL firmware.vh on the real picorv32 inside the
// real softcpu_subsystem (and with it pc98_gdc_draw), fed random slave-GDC
// drawing commands (LINE / dot / RECT / VECTT / TEXTE) through the
// gdc_draw_* handshake. A GVRAM model answers the service channel the way
// pc98_gvram_seq does (own-plane raw reads; plain, GRCG RMW and GRCG TDW
// writes) after a clk_sys latency per op kind, and np21w's vectdraw /
// textdraw (io/gdc_sub.c, io/gdc_pset.c), written out below on a second
// VRAM copy, is the reference: after every draw the four planes must match
// byte for byte. TEXTE's snapshot carries the full 8-byte TEXTW area
// (bytes 15-16 and 24-29); np21w's textdraw doubles para[27] for its
// vectp/vectl/vectr figures.
//
// It also times each command from the request to the retire pulse -- the
// whole firmware + engine path the guest's DRAWING bit waits on -- and
// prints the per-draw / per-dot means.
//
//   +n=<draws> (default 300)  +seed=<n>  +sane (D1 <= 2*DC, for timing)
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
    reg  [511:0] draw_snap = 512'd0;

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
    integer dbg_trace = 0;
    initial void'($value$plusargs("trace=%d", dbg_trace));
    reg trace_en = 0;   // high while the draw indexed by dbg_trace runs
    reg fixmode = 0;    // +fix: replay docker's failing draw 39 verbatim
    initial fixmode = $test$plusargs("fix");
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
                if (trace_en)
                    $display("SVC %0t we=%0d raw=%0d addr=%05x data=%02x accel=%02x",
                             $time, st_we, st_raw, st_addr, st_wdata, accel);
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

    // np21w's vectdir[16]: {x, y} walks the column, {x2, y2} the row
    task automatic r_dir(input integer sel, output integer dx, output integer dy,
                         output integer dx2, output integer dy2);
        case (sel & 15)
            0: begin dx = 0; dy = 1; dx2 = 1; dy2 = 0; end
            1: begin dx = 1; dy = 1; dx2 = 1; dy2 = -1; end
            2: begin dx = 1; dy = 0; dx2 = 0; dy2 = -1; end
            3: begin dx = 1; dy = -1; dx2 = -1; dy2 = -1; end
            4: begin dx = 0; dy = -1; dx2 = -1; dy2 = 0; end
            5: begin dx = -1; dy = -1; dx2 = -1; dy2 = 1; end
            6: begin dx = -1; dy = 0; dx2 = 0; dy2 = 1; end
            7: begin dx = -1; dy = 1; dx2 = 1; dy2 = 1; end
            8: begin dx = 0; dy = 1; dx2 = 1; dy2 = 1; end
            9: begin dx = 1; dy = 1; dx2 = 1; dy2 = 0; end
            10: begin dx = 1; dy = 0; dx2 = 1; dy2 = -1; end
            11: begin dx = 1; dy = -1; dx2 = 0; dy2 = -1; end
            12: begin dx = 0; dy = -1; dx2 = -1; dy2 = -1; end
            13: begin dx = -1; dy = -1; dx2 = -1; dy2 = 0; end
            14: begin dx = -1; dy = 0; dx2 = -1; dy2 = 1; end
            default: begin dx = -1; dy = 1; dx2 = 0; dy2 = 1; end
        endcase
    endtask

    function automatic [7:0] bitrev8(input [7:0] v);
        reg [7:0] r;
        integer i;
        for (i = 0; i < 8; i = i + 1) r[i] = v[7 - i];
        bitrev8 = r;
    endfunction

    reg [15:0] r_px0, r_py0;
    task automatic r_prepare(input [31:0] csrw, input [15:0] pat);
        begin
            r_pat  = pat;
            r_px0 = 16'((((csrw & 32'h3fff) % 40) << 4) + ((csrw >> 20) & 32'h0f));
            r_py0 = 16'((csrw & 32'h3fff) / 40);
        end
    endtask

    // gdcsub_vectr: RECT walks dir, dir2, -dir, -dir2 with D / D2 dots
    task automatic r_vectr(input [31:0] csrw, input [15:0] D, input [15:0] D2,
                           input [2:0] oct, input [15:0] pat);
        integer d, d2, i, dx, dy, dx2, dy2;
        reg [15:0] x, y;
        begin
            r_prepare(csrw, pat);
            r_dir(oct, dx, dy, dx2, dy2);
            d = D & 16'h3fff; d2 = D2 & 16'h3fff;
            x = r_px0; y = r_py0;
            for (i = 0; i < d; i = i + 1)  begin r_pset(x, y); x = x + dx;  y = y + dy; end
            for (i = 0; i < d2; i = i + 1) begin r_pset(x, y); x = x + dx2; y = y + dy2; end
            for (i = 0; i < d; i = i + 1)  begin r_pset(x, y); x = x - dx;  y = y - dy; end
            for (i = 0; i < d2; i = i + 1) begin r_pset(x, y); x = x - dx2; y = y - dy2; end
        end
    endtask

    // gdcsub_vectt: SL reverses the pattern bytewise (GDCPATREVERSE),
    // pattern FFFF, dir = vectdir[ope & 7]; the pattern runs continuously
    // across rows. Rows = multiple (ZOOM & 15 + 1), columns = sx.
    task automatic r_vectt(input [31:0] csrw, input [15:0] D,
                           input [2:0] oct, input integer sl, input [7:0] zoom,
                           input [15:0] patin);
        integer multiple, muly, xrem, mulx, dx, dy, dx2, dy2;
        integer sx;
        reg [15:0] lpat;
        reg [15:0] cx, cy;
        begin
            lpat = sl ? {bitrev8(patin[7:0]), bitrev8(patin[15:8])} : patin;
            r_prepare(csrw, 16'hFFFF);
            r_dir(oct, dx, dy, dx2, dy2);
            multiple = (zoom & 15) + 1;
            sx = (D - 1) & 16'h3fff;
            sx = sx + 1;
            if (sx >= 768) sx = 768;
            muly = multiple;
            while (muly > 0) begin
                muly = muly - 1;
                cx = r_px0; cy = r_py0;
                xrem = sx;
                while (xrem > 0) begin
                    xrem = xrem - 1;
                    mulx = multiple;
                    if (lpat[0]) begin
                        lpat = {lpat[0], lpat[15:1]};
                        while (mulx > 0) begin
                            mulx = mulx - 1;
                            r_pset(cx, cy); cx = cx + dx; cy = cy + dy;
                        end
                    end else begin
                        lpat = {lpat[0], lpat[15:1]};
                        while (mulx > 0) begin
                            mulx = mulx - 1;
                            cx = cx + dx; cy = cy + dy;
                        end
                    end
                end
                r_px0 = r_px0 + dx2; r_py0 = r_py0 + dy2;
            end
        end
    endtask

    // gdcsub_text: the 8-byte TEXTW pattern (snapshot bytes 15-16 and
    // 24-29), rows pat[7] down to pat[0] wrapping (patnum-- from 0),
    // sy rows (DC + 1, clamp 768) of muly repeats each, dir with the
    // SL offset: vectdir[((ope & 0x80) >> 4) + (ope & 7)].
    task automatic r_text(input [31:0] csrw, input [15:0] DC, input [15:0] D,
                          input [7:0] ope, input [7:0] zoom, input [7:0] pat8[0:7]);
        integer multiple, sy, sx, muly, xrem, mulx, dx, dy, dx2, dy2;
        integer patnum;
        reg [7:0] pbit;  // not "bit": that is a SystemVerilog keyword
        reg [15:0] cx, cy;
        begin
            r_prepare(csrw, 16'hFFFF);
            r_dir(((ope & 8'h80) >> 4) + (ope & 7), dx, dy, dx2, dy2);
            multiple = (zoom & 15) + 1;
            sy = (DC & 16'h3fff) + 1;
            if (sy >= 768) sy = 768;
            sx = (D - 1) & 16'h3fff;
            sx = sx + 1;
            if (sx >= 768) sx = 768;
            patnum = 0;
            while (sy > 0) begin
                sy = sy - 1;
                muly = multiple;
                patnum = patnum - 1;
                while (muly > 0) begin
                    muly = muly - 1;
                    cx = r_px0; cy = r_py0;
                    pbit = pat8[patnum & 7];
                    xrem = sx;
                    while (xrem > 0) begin
                        xrem = xrem - 1;
                        mulx = multiple;
                        if (pbit[0]) begin
                            pbit = {pbit[0], pbit[7:1]};
                            while (mulx > 0) begin
                                mulx = mulx - 1;
                                r_pset(cx, cy); cx = cx + dx; cy = cy + dy;
                            end
                        end else begin
                            pbit = {pbit[0], pbit[7:1]};
                            while (mulx > 0) begin
                                mulx = mulx - 1;
                                cx = cx + dx; cy = cy + dy;
                            end
                        end
                    end
                    r_px0 = r_px0 + dx2; r_py0 = r_py0 + dy2;
                end
            end
        end
    endtask

    task set_snap(input integer i, input [7:0] b);
        draw_snap[256 + i*8 +: 8] = b;
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
        if (trace_en && dut.u_gdc_draw.wr)
            $display("ENGWR %0t sel=%0d data=%08x", $time, dut.u_gdc_draw.wr_sel, dut.u_gdc_draw.wr_data);
        if (trace_en && dut.u_gdc_draw.wr && dut.u_gdc_draw.wr_sel == 2'd3 && !dut.u_gdc_draw.busy)
            $display("ENGSX %0t D=%04x DC=%04x tw=%04x oct=%0d zm=%0d fig=%0d b29=%02x p8hi=%02x",
                     $time, dut.u_gdc_draw.snap[37:24], dut.u_gdc_draw.snap[21:8],
                     dut.u_gdc_draw.tw, dut.u_gdc_draw.snap[2:0],
                     dut.u_gdc_draw.snap[139:136], dut.u_gdc_draw.wr_data[12:10],
                     dut.u_gdc_draw.snap[239:232], dut.u_gdc_draw.pat8[63:56]);
        if (trace_en && dut.u_gdc_draw.adv && dut.u_gdc_draw.f_char && dut.u_gdc_draw.mcnt == 4'd0)
            $display("PAT %0t pat=%04x tb=%02x cnt=%0d rcnt=%0d x=%0d y=%0d pn=%0d",
                     $time, dut.u_gdc_draw.pat, dut.u_gdc_draw.tb, dut.u_gdc_draw.cnt,
                     dut.u_gdc_draw.rcnt, dut.u_gdc_draw.x, dut.u_gdc_draw.y, dut.u_gdc_draw.pn);
        if (!dut.ln_busy && lnb_q) a_eng = a_eng + ($time - t_go);
    end
`endif
    longint t_sum = 0, d_sum = 0, t_long = 0, d_long = 0;
    initial begin
        integer i, k, l, dc, d1, d, d2, oct, wm, mode, dots, mism;
        integer zoom, texte, kind, sl, m, sx, sy;
        reg [31:0] csrw;
        reg [15:0] pat;
        reg [15:0] fpat;
        reg [7:0]  pat8[0:7];
        reg [7:0]  zoomb;
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
            // the kinds: l line, p lone dot, r rect, t VECTT, x TEXTE
            k = $urandom % 20;
            kind = (k < 8) ? "l" : (k < 11) ? "p" : (k < 15) ? "r" : (k < 18) ? "t" : "x";
            texte = (kind == "x");
            sl = $urandom % 2;
            oct = $urandom % 8;
            wm = $urandom % 4;
            k = $urandom % 10;
            mode = (k < 4) ? 0 : (k < 8) ? 1 : 2;
            accel = (mode == 0) ? 8'h00 : (mode == 1) ? 8'h03 : 8'h01;
            for (i = 0; i < 4; i = i + 1) tile[i] = 8'($urandom);
            pat = (($urandom % 4) != 0) ? 16'($urandom) : 16'hFFFF;
            csrw = ($urandom % 16000) | (($urandom % 4) << 14) | (($urandom % 16) << 20);
            // the parameter spreads, np21w-style: mostly small, sometimes
            // the 14-bit clamps
            k = $urandom % 10;
            d  = (k < 6) ? $urandom % 48 : (k < 9) ? $urandom % 400 : $urandom % 2000;
            k = $urandom % 10;
            d2 = (k < 6) ? $urandom % 48 : (k < 9) ? $urandom % 400 : $urandom % 2000;
            k = $urandom % 10;
            dc = (k < 6) ? $urandom % 48 : (k < 9) ? $urandom % 400 : $urandom % 2000;
            d1 = ((sane || ($urandom % 8) != 0) && dc != 0) ? $urandom % (2 * dc + 1) : $urandom % 65536;
            zoomb = 8'(($urandom & 8'hF0) | (($urandom % 4) ? $urandom % 3 : $urandom % 16));
            case (kind)
                "p": ;
                "t", "x": begin
                    d  = ($urandom % 10) ? $urandom % 33 : $urandom % 16384;  // sx
                    dc = ($urandom % 10) ? $urandom % 24 : $urandom % 16384;  // sy
                    d1 = $urandom % (2 * dc + 1);
                end
                default: ;   // 'l'/'r' keep the line/rect spreads
            endcase
            // keep a walk inside the firmware's poll bound: shrink ZOOM
            if (kind == "t" || kind == "x") begin
                sx = ((d - 1) & 16'h3fff) + 1; if (sx > 768) sx = 768;
                sy = (dc & 16'h3fff) + 1;      if (sy > 768) sy = 768;
                if (kind == "t") sy = 1;
                m = (zoomb & 15) + 1;
                while (sx * sy * m * m > 600000 && (zoomb & 15) != 0) begin
                    zoomb = zoomb - 1;
                    m = (zoomb & 15) + 1;
                end
            end

            for (i = 0; i < 30; i = i + 1) set_snap(i, 8'($urandom));
            set_snap(23, 8'h00);
            k = (kind == "l") ? 8'h08 :
                (kind == "p") ? 8'h00 :
                (kind == "r") ? (8'h40 | ((($urandom % 8) == 0) ? 8'h08 : 8'h00)) :
                (8'h10 | ((($urandom % 10) == 0) ? 8'h48 : 8'h00));
            set_snap(0, 8'(k | oct | (sl << 7)));
            set_snap(1, 8'(dc)); set_snap(2, 8'((dc >> 8) | (($urandom % 4) << 6)));
            set_snap(3, 8'(d));  set_snap(4, 8'((d >> 8) | (($urandom % 4) << 6)));
            set_snap(5, 8'(d2)); set_snap(6, 8'((d2 >> 8) | (($urandom % 4) << 6)));
            set_snap(7, 8'(d1)); set_snap(8, 8'(d1 >> 8));
            for (i = 0; i < 4; i = i + 1) set_snap(11 + i, 8'(csrw >> (8 * i)));
            set_snap(15, pat[7:0]); set_snap(16, pat[15:8]);
            set_snap(17, zoomb);
            set_snap(18, 8'(wm));

            if (fixmode) begin : fix_params
                // docker 5.020's failing draw 39, verbatim: kind=t (VECTT)
                kind = "t"; texte = 0; sl = 0; oct = 2; wm = 1;
                mode = 1; accel = 8'h03; pat = 16'h8054;
                csrw = 32'h050427f; d = 17; d2 = 131; dc = 4; d1 = 0; zoomb = 8'h11;
                set_snap(0,  8'h12); set_snap(1,  8'h04); set_snap(2,  8'h00); set_snap(3,  8'h11);
                set_snap(4,  8'h80); set_snap(5,  8'h83); set_snap(6,  8'h40); set_snap(7,  8'h00);
                set_snap(8,  8'h00); set_snap(9,  8'h64); set_snap(10, 8'h2d); set_snap(11, 8'h7f);
                set_snap(12, 8'h42); set_snap(13, 8'h50); set_snap(14, 8'h00); set_snap(15, 8'h54);
                set_snap(16, 8'h80); set_snap(17, 8'h11); set_snap(18, 8'h01); set_snap(19, 8'he0);
                set_snap(20, 8'hba); set_snap(21, 8'h2b); set_snap(22, 8'h3f); set_snap(23, 8'h00);
                set_snap(24, 8'he7); set_snap(25, 8'hd6); set_snap(26, 8'h2f); set_snap(27, 8'h07);
                set_snap(28, 8'he6); set_snap(29, 8'h6c);
            end

            t0 = $time; t_req = $time;
            trace_en <= (dbg_trace == l + 1);
            draw_ops <= texte ? 16'h6800 : 16'h6C00;
            draw_req <= 2'b10;
            for (i = 0; i < 50000000 && !done_lv[1]; i = i + 1) @(posedge clk_sys);
            if (!done_lv[1]) begin
                errors = errors + 1;
                $display("draw %0d: never retired", l);
            end
            draw_req <= 2'b00;
            trace_en <= 0;
            // time in ns at 42.95 MHz: the bench clock is 50 MHz
            t0 = ($time - t0) * 50 / 43;
            while (done_lv[1]) @(posedge clk_sys);

            // ---- np21w's vectdraw / textdraw over the same snapshot ----
            r_mode = mode; r_plane = (csrw >> 14) & 3; r_op = wm; r_drawn = 0;
            // textdraw hands its figures para[27] doubled; vectdraw the
            // TEXTW word
            fpat = texte ? {2{draw_snap[256 + 29*8 +: 8]}} : pat;
            k = draw_snap[256 +: 8];   // VECTW's ope
            if ((k & 8'h78) == 0) begin
                r_prepare(csrw, fpat);
                r_pset(r_px0, r_py0);   // vectp
            end
            if (k & 8'h08) r_vectl(csrw, {draw_snap[256+16 +: 8], draw_snap[256+8 +: 8]},
                                   d1[15:0], oct[2:0], fpat);
            if (k & 8'h10) begin
                if (texte) begin
                    for (i = 0; i < 8; i = i + 1)
                        pat8[i] = (i < 2) ? draw_snap[256 + (15+i)*8 +: 8]
                                          : draw_snap[256 + (22+i)*8 +: 8];
                    r_text(csrw, {draw_snap[256+16 +: 8], draw_snap[256+8 +: 8]},
                           {draw_snap[256+32 +: 8], draw_snap[256+24 +: 8]},
                           draw_snap[256 +: 8], zoomb, pat8);
                end else begin
                    r_vectt(csrw, {draw_snap[256+32 +: 8], draw_snap[256+24 +: 8]},
                            oct[2:0], sl, zoomb, pat);
                end
            end
            if (k & 8'h40) r_vectr(csrw, {draw_snap[256+32 +: 8], draw_snap[256+24 +: 8]},
                                   {draw_snap[256+48 +: 8], draw_snap[256+40 +: 8]},
                                   oct[2:0], fpat);
            dots = r_drawn;
            t_sum = t_sum + t0; d_sum = d_sum + dots;
            if (dots >= 100) begin t_long = t_long + t0; d_long = d_long + dots; end
            mism = 0;
            for (i = 0; i < 4*32768; i = i + 1)
                if (vram[i] !== rvram[i]) begin
                    if (mism < 4)
                        $display("  draw %0d MISMATCH plane %0d +%04x: np21w %02x got %02x", l,
                                 i / 32768, i % 32768, rvram[i], vram[i]);
                    mism = mism + 1;
                    rvram[i] = vram[i];
                end
            if (mism) begin
                errors = errors + 1;
                $display("draw %0d: kind=%c csrw=%07x dc=%0d d=%0d d2=%0d d1=%0d oct=%0d wm=%0d mode=%0d pat=%04x: %0d bytes differ",
                         l, kind, csrw, dc, d, d2, d1, oct, wm, mode, pat, mism);
                $write("  snap:");
                for (i = 0; i < 30; i = i + 1) $write(" %02x", draw_snap[256 + i*8 +: 8]);
                $write(" sl=%0d zoom=%02x\n", sl, zoomb);
            end
            repeat (200) @(posedge clk_sys);
        end
        $display("TIMING: %0d draws, %0d dots, %0d us total; %0.2f us/draw, %0.3f us/dot (draws >= 100 dots: %0.3f us/dot)",
                 n, d_sum, t_sum / 1000, real'(t_sum) / 1000.0 / n, real'(t_sum) / 1000.0 / d_sum,
                 d_long ? real'(t_long) / 1000.0 / d_long : 0.0);
        $display("SPLIT: request->engine start %0.2f us/draw, engine %0.2f us/draw",
                 real'(a_pre) * 50 / 43 / 1000.0 / n, real'(a_eng) * 50 / 43 / 1000.0 / n);
        $display("DONE: %0d svc ops, %0d errors", n_ops, errors);
        if (errors) $display("RESULT: FAIL"); else $display("RESULT: PASS");
        $finish;
    end
endmodule
