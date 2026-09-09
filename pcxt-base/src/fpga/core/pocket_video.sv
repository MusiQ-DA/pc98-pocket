//
// Pocket video output: composite the machine's CGA/HGC raster and the softcore's OSD
// framebuffer into the Analogue APF scaler stream. The CGA raster is the pass-through
// default; the stages below special-case only what differs from it: the monochrome
// palette tint, the fixed Hercules canvas, the credits and sync-guard overlays, and the
// final pack of RGB + single-cycle HS/VS + DE with the scaler-slot word held through
// blanking. Runs on clk_pix, the CGA dot clock's half-rate sibling (one pixel per edge).
//

module pocket_video (
    input             clk_pix,
    input             clk_pix_90,
    input             RESET,
    // Machine raster (from CHIPSET, clk_pix-sampled)
    input      [5:0]  r,
    input      [5:0]  g,
    input      [5:0]  b,
    input             HSync,
    input             VSync,
    input             HBlank,
    input             VBlank,
    // Config / clock-mux state
    input      [2:0]  palette_cfg,
    input             credits_mode_pix,
    input             pix_sel,
    input             vid_blank,
    // OSD framebuffer handshake (softcore)
    input             osd_active,
    input     [15:0]  dbg_bits,
    input      [3:0]  osd_palette_idx,
    input             osd_in_area,
    output     [9:0]  osd_hcnt,
    output     [9:0]  osd_vcnt,
    output     [9:0]  osd_raster_w,
    output     [9:0]  osd_raster_h,
    // Analogue APF scaler
    output     [23:0] video_rgb,
    output            video_de,
    output            video_hs,
    output            video_vs,
    output            video_skip,
    output            video_rgb_clock,
    output            video_rgb_clock_90
);

    //
    // Palette tint
    //
    // Monochrome-monitor palette (Display setting): palette_cfg 0 = full colour, 1-7
    // tint by weighted luma. Combinational (no extra clock/latency); r/g/b widened to 8.
    wire [7:0]  pr = {r, 2'b00};
    wire [7:0]  pg = {g, 2'b00};
    wire [7:0]  pb = {b, 2'b00};
    wire [15:0] luma16 = pr * 16'd54 + pg * 16'd183 + pb * 16'd18;  // Rec.709 weights <<8
    wire [7:0]  mono   = luma16[15:8];
    wire [7:0]  hmono  = {1'b0, luma16[15:9]};   // mono >> 1
    reg  [7:0]  tr, tg, tb;
    always @(*) begin
        case (palette_cfg)
            3'd1: begin tr = 8'h00;                         tg = (mono < 8'h0F) ? 8'h0F : mono; tb = 8'h01; end
            3'd2: begin tr = (mono < 8'h08) ? 8'h08 : mono; tg = hmono;                         tb = 8'h01; end
            3'd3: begin tr = mono;                          tg = mono;                          tb = mono;  end
            3'd4: begin tr = (mono < 8'h08) ? 8'h08 : mono; tg = 8'h00;                         tb = 8'h01; end
            3'd5: begin tr = 8'h00;                         tg = hmono;                         tb = (mono < 8'h08) ? 8'h08 : mono; end
            3'd6: begin tr = (mono < 8'h08) ? 8'h08 : mono; tg = 8'h00;                         tb = hmono; end
            3'd7: begin tr = hmono;                         tg = 8'h00;                         tb = (mono < 8'h08) ? 8'h08 : mono; end
            default: begin tr = pr; tg = pg; tb = pb; end   // full colour
        endcase
    end

    //
    // Hercules canvas
    //
    // The guest programs arbitrary 6845 rasters, so present one fixed 720x350 window
    // (720 dots from the guest active start each line, 350 lines opening CANVAS_VSKIP
    // lines after the vsync fall) and pad the rest black. CANVAS_VSKIP must equal the
    // scaler's frame anchor, or the window's top lines wrap to the bottom.
    localparam CANVAS_W = 10'd720;
    localparam CANVAS_H = 10'd350;
    localparam CANVAS_VSKIP = 5'd16; // lines from the vsync fall to the window top
`ifdef MACHINE_PC98
    // No Hercules canvas on this machine, so nothing downstream may ever take
    // that path: it owns the OSD's line counter, the presented blanking and the
    // scaler slot.
    wire hgc_shown_pix = 1'b0;
`else
    wire hgc_shown_pix;
    synch_3 s_hgc_shown_pix (pix_sel, hgc_shown_pix, clk_pix);
`endif
    reg       src_hb_d = 1'b0;
    reg       src_vs_d = 1'b0;
    reg       v_arm    = 1'b0;   // vsync fell; window opens after the skip
    reg [4:0] v_skip   = 5'd0;
    reg [9:0] h_run    = 10'd0;  // dots left in this line's window
    reg [9:0] v_run    = 10'd0;  // lines left in this frame's window
    wire      line_open = src_hb_d & ~HBlank & (h_run == 10'd0);   // guest active start
    always @(posedge clk_pix) begin
        src_hb_d <= HBlank;
        src_vs_d <= VSync;
        if (~VSync & src_vs_d) begin
            v_arm  <= 1'b1;
            v_skip <= 5'd0;
        end
        if (line_open) begin
            h_run <= CANVAS_W - 10'd1;   // this cycle is the window's first dot
        end else if (h_run != 10'd0) begin
            h_run <= h_run - 10'd1;
            if (h_run == 10'd1) begin    // line end: settle v_run for the next line
                if (v_arm) begin
                    if (v_skip == CANVAS_VSKIP - 5'd1) begin
                        v_run <= CANVAS_H;
                        v_arm <= 1'b0;
                    end else begin
                        v_run  <= 10'd0;   // skip lines stay blank
                        v_skip <= v_skip + 5'd1;
                    end
                end else if (v_run != 10'd0) begin
                    v_run <= v_run - 10'd1;
                end
            end
        end
    end
    wire canvas_hb = ~(line_open | (h_run != 10'd0));
    wire canvas_vb = (v_run == 10'd0);

    //
    // Card blanking
    //
    // The Hercules canvas when that card is shown, the CGA HBlank/VBlank otherwise
    // (cga.v already normalizes every CGA mode to 640x200).
`ifdef MACHINE_PC98
    // -------------------------------------------------- rebuilt PC-98 blanking
    //
    // Not CHIPSET's HBlank/VBlank. Everything indexed by the counters derived
    // from those -- the overlay, the RTL status bands, a sixteen-pixel square at
    // their own origin -- has never appeared on hardware, while everything
    // driven from a free-running raster has: colour bars, and the softcore's
    // panel with its text readable. Simulating this exact path
    // (tb_pc98_osdwin) says it is correct, so what reaches pocket_video on the
    // hardware is not what the renderer's timing generator puts out.
    //
    // So rebuild the presented blanking here, from the two signals the hardware
    // has confirmed alive: the HSync and VSync edges. The PC-98 raster is fixed
    // -- 848 x 440 with sync at 680 and 412 -- so counting from those edges
    // reproduces the guest's own blanking exactly, and in phase with it, which
    // is what keeps the picture aligned.
    localparam [9:0] PC98_H_TOTAL  = 10'd848, PC98_H_ACTIVE = 10'd640;
    localparam [9:0] PC98_V_TOTAL  = 10'd440, PC98_V_ACTIVE = 10'd400;
    localparam [9:0] PC98_H_SYNC   = 10'd680;   // H_ACTIVE + H_FRONT
    localparam [9:0] PC98_V_SYNC   = 10'd412;   // V_ACTIVE + V_FRONT

    reg  [9:0] rb_h = 10'd0, rb_v = 10'd0;
    reg        rb_hs_d = 1'b0, rb_vs_d = 1'b0;
    wire       rb_hs_edge = HSync & ~rb_hs_d;
    wire       rb_vs_edge = VSync & ~rb_vs_d;
    always @(posedge clk_pix) begin
        rb_hs_d <= HSync;
        rb_vs_d <= VSync;
        if (rb_hs_edge)                     rb_h <= PC98_H_SYNC;
        else if (rb_h == PC98_H_TOTAL - 1)  rb_h <= 10'd0;
        else                                rb_h <= rb_h + 10'd1;

        if (rb_vs_edge)                     rb_v <= PC98_V_SYNC;
        else if (rb_hs_edge) begin
            if (rb_v == PC98_V_TOTAL - 1)   rb_v <= 10'd0;
            else                            rb_v <= rb_v + 10'd1;
        end
    end
    wire pc98_hb = (rb_h >= PC98_H_ACTIVE);
    wire pc98_vb = (rb_v >= PC98_V_ACTIVE);

    wire vid_hb  = pc98_hb;
    wire vid_vb  = pc98_vb;
`else
    wire vid_hb  = hgc_shown_pix ? canvas_hb : HBlank;
    wire vid_vb  = hgc_shown_pix ? canvas_vb : VBlank;
`endif
    // Canvas padding (inside the window, outside the guest raster). The window's first
    // line is sacrificial/black: the scaler captures the first DE line unreliably.
    wire vid_pad = hgc_shown_pix & (HBlank | VBlank | (v_run == CANVAS_H));

    //
    // Credits overlay
    //
    wire [23:0] credits_rgb;
    wire        credits_rst;
    synch_3 s_credits_rst (RESET, credits_rst, clk_pix);

    jtframe_credits #(
        .PAGES  (4),
        .COLW   (8),
        .BLKPOL (1)
    ) u_credits(
        .rst        ( credits_rst ),
        .clk        ( clk_pix ),
        .pxl_cen    ( 1'b1 ),

        // input image
        .HB         ( vid_hb  ),
        .VB         ( vid_vb ),
        .rgb_in     ( vid_pad ? 24'd0 : {tr, tg, tb} ),   // live picture; the credits dim it behind the scrolling text
        .rotate     ( 2'd0  ),
        .toggle     ( 1'b0  ),
        .fast_scroll( 1'b0  ),
        .border     ( 1'b0 ),

        .vram_din   ( 8'h0  ),
        .vram_dout  (       ),
        .vram_addr  ( 8'h0  ),
        .vram_we    ( 1'b0  ),
        .vram_ctrl  ( 3'b0  ),
        .enable     ( credits_mode_pix ),

        // output image
        .HB_out     (             ),
        .VB_out     (             ),
        .rgb_out    ( credits_rgb )
    );

    //
    // Overlay sync guard
    //
    // When the guest video timing leaves spec (a guest can program the CRTC to stall HSYNC
    // or suppress VSYNC), supply a stable frame for an open OSD/VKB to ride on so it stays
    // framed. `guard_run` engages only on the CGA path with an overlay open.
    wire osd_enable;
    synch_3 s_osd_enable_pix (osd_active, osd_enable, clk_pix);

`ifdef MACHINE_PC98
    // No guard on this machine.
    //
    // The guard exists because a PC/AT guest can program the CRTC to stall
    // HSYNC or suppress VSYNC, and an open overlay then has no stable frame to
    // ride on. This machine has one raster, fixed at 640x400 by
    // pc98_video_timing, and no way to leave spec.
    //
    // Left in, it does not merely idle: tb_pc98_osdwin measures it engaged for
    // 1119361 cycles out of 1119360 -- permanently -- because it is calibrated
    // for CGA's 640x200 and reads a 400-line frame as out of spec. It then
    // substitutes its own 200-line raster, so osd_vcnt reaches 199 instead of
    // 399 while osd_raster_h still reports 400, and the softcore places its
    // panel across lines the presented frame never has. It also forces the
    // picture black for as long as it runs.
    wire guard_run = 1'b0;
    wire gen_hs = 1'b0, gen_vs = 1'b0, gen_hb = 1'b0, gen_vb = 1'b0;
`else
    wire guard_run, gen_hs, gen_vs, gen_hb, gen_vb;
    video_sync_guard u_sync_guard (
        .clk_pix      (clk_pix),
        .overlay_open (osd_enable & ~hgc_shown_pix & ~credits_mode_pix),
        .hsync_in     (HSync),
        .vsync_in     (VSync),
        .hblank_in    (HBlank),
        .vblank_in    (VBlank),
        .run          (guard_run),
        .gen_hs       (gen_hs),
        .gen_vs       (gen_vs),
        .gen_hb       (gen_hb),
        .gen_vb       (gen_vb)
    );
`endif

    //
    // Presented raster
    //
    // The guest's raster, or the sync guard's generated frame once it has taken over.
    // Everything downstream (OSD counters, output sync, DE) rides on these four.
    wire sel_hs = guard_run ? gen_hs : HSync;
    wire sel_vs = guard_run ? gen_vs : VSync;
    wire sel_hb = guard_run ? gen_hb : vid_hb;
    wire sel_vb = guard_run ? gen_vb : vid_vb;

    // The credits overlay delays its picture one clk_pix; stage the presented sync/blanking
    // to match, so both align with the composited RGB at the final register. sel_hb_d1 also
    // gives the OSD line counter its hblank-fall edge.
    reg sel_hs_d1 = 1'b0, sel_vs_d1 = 1'b0;
    reg sel_hb_d1 = 1'b0, sel_vb_d1 = 1'b0;
    always @(posedge clk_pix) begin
        sel_hs_d1 <= sel_hs;
        sel_vs_d1 <= sel_vs;
        sel_hb_d1 <= sel_hb;
        sel_vb_d1 <= sel_vb;
    end

    //
    // OSD framebuffer readout
    //
    // OSD raster counters: osd_hcnt = pixel in the active line; the line index is the
    // canvas countdown on Hercules, else an hblank-fall counter parked at -1 so the
    // first fall (after VBlank) is line 0.
    reg [9:0] osd_hcnt_g   = 10'd0;
    reg [9:0] osd_vcnt_raw = 10'd0;
    always @(posedge clk_pix) begin
        if (sel_hb)                   osd_hcnt_g <= 10'd0;
        else                          osd_hcnt_g <= osd_hcnt_g + 10'd1;
        if (sel_vb)                   osd_vcnt_raw <= 10'd1023;
        else if (sel_hb_d1 & ~sel_hb) osd_vcnt_raw <= osd_vcnt_raw + 10'd1;
    end
    wire [9:0] osd_vcnt_g = hgc_shown_pix ? (CANVAS_H - 10'd1 - v_run) : osd_vcnt_raw;

    // Presented raster size, read by the softcore to place the overlay window;
    // the canvas reports its 349 usable lines, excluding the sacrificial one.
`ifdef MACHINE_PC98
    // One raster, 640x400. The PC/AT pair below is CGA and the Hercules canvas,
    // neither of which exists here -- and reporting 200 lines put the softcore's
    // panel in the top half of a 400-line picture.
    assign osd_raster_w = 10'd640;
    assign osd_raster_h = 10'd400;
`else
    assign osd_raster_w = pix_sel ? CANVAS_W : 10'd640;
    assign osd_raster_h = pix_sel ? (CANVAS_H - 10'd1) : 10'd200;
`endif

    // Framebuffer palette index -> opaque colour; index 0 is transparent and
    // falls through to the picture.
    wire vid_blank_pix;
    synch_3 s_vid_blank_pix (vid_blank, vid_blank_pix, clk_pix);
    wire osd_show = osd_enable & osd_in_area & (osd_palette_idx != 4'd0);
    reg [23:0] osd_color;
    always @(*) begin
        case (osd_palette_idx)
            4'd1:    osd_color = 24'hF1E5D5;   // body
            4'd2:    osd_color = 24'hD5C9B9;   // key face
            4'd3:    osd_color = 24'hB0A58F;   // accent key face
            4'd4:    osd_color = 24'h212421;   // key edge
            4'd5:    osd_color = 24'h101010;   // label
            4'd6:    osd_color = 24'hFFFFFF;   // cursor
            4'd7:    osd_color = 24'h30C030;   // latched
            4'd8:    osd_color = 24'h90FF90;   // latched under cursor
            4'd9:    osd_color = 24'h8C8578;   // disabled (dimmed label)
            default: osd_color = 24'h000000;
        endcase
    end

    //
    // Scaler output
    //
    // Scaler slot (video.json): 0 = CGA 640x200, 1 = Hercules canvas; follows only the
    // displayed card.
    wire [2:0] vid_slot = hgc_shown_pix ? 3'd1 : 3'd0;

    // Final pack: DE from the staged presented blanking, the overlay layered over the
    // picture (black behind it under the sync guard), sync staged to match. While DE is low
    // the bus carries the scaler-slot word ([23:13]), held through all of blanking: a zero
    // bus is itself slot 0 and the last word wins.
    reg  [23:0] vid_rgb = 24'd0;
    reg         vid_de  = 1'b0;
    reg         vid_hs  = 1'b0;
    reg         vid_vs  = 1'b0;
    wire        vid_de_now = ~(sel_hb_d1 | sel_vb_d1) & ~vid_blank_pix;
    // Debug bands: 64px-wide stripes down the left edge, 32 lines tall each,
    // lit white when the bit is high and dark grey when it is low, so a dark
    // band is still distinguishable from the picture behind it. Compiled in
    // only under PC98_DEBUG_BANDS.
`ifdef PC98_DEBUG_BANDS
    // ---------------------------------------------------- free-running probe
    //
    // The first version of this drew its bands inside the normal picture, which
    // was useless: the bands rode on vid_de_now, and vid_de_now rides on the
    // blanking CHIPSET produces. CHIPSET is held by the guest reset, and the
    // guest reset shares a term (load_active) with the softcore's -- so in the
    // one situation worth debugging, the raster is stopped, DE never asserts,
    // and the bands are as invisible as the OSD they were meant to explain.
    // What reaches the screen then is the scaler's own uninitialised memory: a
    // fine checkerboard that changes with video.json and with nothing else,
    // which is exactly what the hardware has been showing.
    //
    // So this generates its own 640x400 raster from clk_pix alone -- no reset,
    // no CHIPSET, no softcore, no guest -- and drives the APF output directly.
    // It answers a question the picture path cannot: is the bitstream running
    // and is the scaler accepting our frames at all?
    //
    //   left 64 px   eight status bands, 32 lines each, white = 1
    //   the rest     eight vertical colour bars, so the frame is unmistakable
    //
    // If the screen shows bars, clock, PLL, bitstream and scaler are all fine
    // and the bands say why nothing else runs. If it still shows the
    // checkerboard, the fault is upstream of every one of them.
    reg [15:0] dbg_bits_s1 = 16'd0, dbg_bits_pix = 16'd0;
    always @(posedge clk_pix) begin
        dbg_bits_s1  <= dbg_bits;
        dbg_bits_pix <= dbg_bits_s1;
    end

    // Bit 7: does CHIPSET's raster run at all? HSync arrives on clk_pix already,
    // so this needs no crossing -- just an edge and a timeout. About 50 ms of
    // stillness (a PC-98 line is 848 dots) counts as stopped.
    reg        hs_seen = 1'b0;
    reg [19:0] hs_idle = 20'd0;
    reg        raster_alive = 1'b0;
    always @(posedge clk_pix) begin
        hs_seen <= HSync;
        if (HSync != hs_seen) begin
            raster_alive <= 1'b1;
            hs_idle      <= 20'd0;
        end else if (hs_idle == 20'hFFFFF)
            raster_alive <= 1'b0;
        else
            hs_idle <= hs_idle + 20'd1;
    end
    // VSync liveness, same shape as HSync's.
    reg        vs_seen = 1'b0;
    reg [21:0] vs_idle = 22'd0;
    reg        vsync_alive = 1'b0;
    always @(posedge clk_pix) begin
        vs_seen <= VSync;
        if (VSync != vs_seen) begin
            vsync_alive <= 1'b1;
            vs_idle     <= 22'd0;
        end else if (vs_idle == 22'h3FFFFF)
            vsync_alive <= 1'b0;
        else
            vs_idle <= vs_idle + 22'd1;
    end

    // Per-frame "did this ever happen" flags, published at the probe's own frame
    // boundary so each reads as the state of the frame just gone.
    reg pb_vs_d = 1'b0;
    reg de_acc = 1'b0, ia_acc = 1'b0, px_acc = 1'b0, hb_acc = 1'b0, vb_acc = 1'b0;
    reg de_any = 1'b0, ia_any = 1'b0, px_any = 1'b0, hb_any = 1'b0, vb_any = 1'b0;
    always @(posedge clk_pix) begin
        pb_vs_d <= pb_vs;
        if (pb_vs & ~pb_vs_d) begin
            de_any <= de_acc; ia_any <= ia_acc; px_any <= px_acc;
            hb_any <= hb_acc; vb_any <= vb_acc;
            de_acc <= 1'b0; ia_acc <= 1'b0; px_acc <= 1'b0;
            hb_acc <= 1'b0; vb_acc <= 1'b0;
        end else begin
            if (vid_de_now)                                  de_acc <= 1'b1;
            if (osd_in_area)                                 ia_acc <= 1'b1;
            if (osd_in_area && (osd_palette_idx != 4'd0))    px_acc <= 1'b1;
            if (~sel_hb)                                     hb_acc <= 1'b1;
            if (~sel_vb)                                     vb_acc <= 1'b1;
        end
    end

    // Left column is core_top's; the right column is measured here.
    //
    //   9  raster_alive   HSync moves
    //   10 vsync_alive    VSync moves
    //   11 de_any         the picture path asserted DE this frame
    //   12 hb_any         the presented hblank ever cleared
    //   13 vb_any         the presented vblank ever cleared
    //   14 osd_enable     osd_active, synced to clk_pix
    //   15 ia_any         the softcore returned in-area for some probe pixel
    //   16 px_any         and returned a non-zero palette index there
    // What the guest-derived counters actually reach over the DE-active pixels
    // of a frame. The panel window is a range test on exactly these two, so
    // their span is the whole remaining question.
    reg [9:0] vg_min_acc = 10'h3FF, vg_max_acc = 10'd0, hg_max_acc = 10'd0;
    reg [9:0] vg_min = 10'h3FF, vg_max = 10'd0, hg_max = 10'd0;
    always @(posedge clk_pix) begin
        if (pb_vs & ~pb_vs_d) begin
            vg_min <= vg_min_acc; vg_max <= vg_max_acc; hg_max <= hg_max_acc;
            vg_min_acc <= 10'h3FF; vg_max_acc <= 10'd0; hg_max_acc <= 10'd0;
        end else if (vid_de_now) begin
            if (osd_vcnt_g < vg_min_acc) vg_min_acc <= osd_vcnt_g;
            if (osd_vcnt_g > vg_max_acc) vg_max_acc <= osd_vcnt_g;
            if (osd_hcnt_g > hg_max_acc) hg_max_acc <= osd_hcnt_g;
        end
    end

    //   A  core_top's eight, as before, then two dark
    //   B  raster_alive, vsync_alive, vb_any, hb_any, de_any,
    //      ia_any, px_any, osd_enable, guard_run, then one dark
    //   C  osd_vcnt_g minimum over the frame, ten bits, MSB at the top
    //   D  osd_vcnt_g maximum
    //   E  osd_hcnt_g maximum
    wire [9:0] dbg_colA = {2'b00, dbg_bits_pix[7:0]};
    wire [9:0] dbg_colB = {1'b0, guard_run, osd_enable, px_any, ia_any,
                           de_any, hb_any, vb_any, vsync_alive, raster_alive};
    wire [9:0] dbg_colC = vg_min;
    wire [9:0] dbg_colD = vg_max;
    wire [9:0] dbg_colE = hg_max;

    wire [9:0] pb_h, pb_v;
    wire       pb_hs, pb_vs, pb_hb, pb_vb, pb_de;
    pc98_video_timing u_probe_timing (
        .clk         (clk_pix),
        .ce          (1'b1),
        .rst         (1'b0),
        .hcount      (pb_h),
        .vcount      (pb_v),
        .hsync       (pb_hs),
        .vsync       (pb_vs),
        .hblank      (pb_hb),
        .vblank      (pb_vb),
        .de          (pb_de),
        .frame_start ()
    );

    // The probe reads the softcore's framebuffer with its OWN raster, so the
    // whole OSD chain can be tested with CHIPSET out of the picture entirely.
    // Keep feeding the softcore the probe's raster: that is the configuration
    // that renders a readable panel, and the panel carries the guest readouts
    // this whole exercise was for. The guest counters do not have to be routed
    // through the softcore to be measured -- vg_min/vg_max/hg_max below watch
    // them directly.
    assign osd_hcnt = pb_h;
    assign osd_vcnt = pb_v;

    // Two columns of eight: 0-63 is bits 0-7, 64-127 is bits 8-15.
    // Five columns of ten bands, in a strip along the BOTTOM of the frame:
    // 64 px wide, 8 lines tall, red rules between. The bottom is where the
    // softcore's 640x200 panel is not, so the readouts stay legible.
    wire       pb_band_area = (pb_h < 10'd320) && (pb_v >= 10'd320);
    wire [2:0] pb_col       = pb_h[8:6];
    wire [3:0] pb_row       = (pb_v - 10'd320) >> 3;
    reg  [9:0] pb_colsel;
    always @(*) begin
        case (pb_col)
            3'd0:    pb_colsel = dbg_colA;
            3'd1:    pb_colsel = dbg_colB;
            3'd2:    pb_colsel = dbg_colC;
            3'd3:    pb_colsel = dbg_colD;
            default: pb_colsel = dbg_colE;
        endcase
    end
    // MSB first in the numeric columns, so they read top to bottom as binary.
    wire pb_lit = (pb_col >= 3'd2) ? pb_colsel[4'd9 - pb_row]
                                   : pb_colsel[pb_row];
    // 128 px per bar, offset by one so no bar is black -- a black bar next to
    // the bands would read as "nothing here" and defeat the point.
    wire [2:0] pb_bar       = pb_h[9:7] + 3'd1;
    // A one-pixel rule between the two band columns, so they cannot be misread
    // as one column of sixteen.
    wire       pb_rule      = (pb_v >= 10'd320) && (pb_h >= 10'd64)
                              && (pb_h < 10'd320) && (pb_h[5:0] < 6'd2);
    wire [23:0] pb_bar_rgb  = {{8{pb_bar[2]}}, {8{pb_bar[1]}}, {8{pb_bar[0]}}};
    // The overlay, on a flat backdrop. Colour bars showing through the panel's
    // transparent pixels made the text unreadable, and the text is the point.
    //
    // Mid grey, not black: the label colour is 0x101010, so anywhere the panel
    // body did not get filled a black backdrop would hide the very text this is
    // for. Grey keeps both the light body (0xF1E5D5) and the near-black label
    // legible against it.
    wire [23:0] pb_rgb      = pb_rule       ? 24'hFF0000
                            : pb_band_area ? (pb_lit ? 24'hFFFFFF : 24'h202020)
                            : osd_show     ? osd_color
                            : osd_in_area  ? 24'h606060
                            :                pb_bar_rgb;

    reg [23:0] pb_vid_rgb = 24'd0;
    reg        pb_vid_de  = 1'b0;
    reg        pb_vid_hs  = 1'b0;
    reg        pb_vid_vs  = 1'b0;
    always @(posedge clk_pix) begin
        pb_vid_de  <= pb_de;
        pb_vid_rgb <= pb_de ? pb_rgb : 24'd0;   // slot 0 through blanking
        pb_vid_hs  <= pb_hs;
        pb_vid_vs  <= pb_vs;
    end

    wire        dbg_in    = 1'b0;
    wire [23:0] dbg_color = 24'd0;
`else
    wire        dbg_in    = 1'b0;
    wire [23:0] dbg_color = 24'd0;
`endif

    // A 16x16 white square at the origin of the OSD's own coordinate system,
    // drawn from osd_hcnt/osd_vcnt -- the two counters the overlay is indexed
    // by. It costs one corner of the picture and makes the next hardware round
    // trip decisive either way: square but no panel means the counters are fine
    // and the fault is in the framebuffer read; neither means the counters
    // still never reach the window. Remove it once the OSD is up.
`ifdef PC98_OSD_MARK
    wire        mark_in  = (osd_hcnt < 10'd16) && (osd_vcnt < 10'd16);
    wire [23:0] mark_rgb = 24'hFFFFFF;
`else
    wire        mark_in  = 1'b0;
    wire [23:0] mark_rgb = 24'd0;
`endif

    wire [23:0] overlay    = mark_in   ? mark_rgb
                           : dbg_in    ? dbg_color
                           : osd_show  ? osd_color
                           : guard_run ? 24'd0
                           :             credits_rgb;
    always @(posedge clk_pix) begin
        vid_de  <= vid_de_now;
        vid_rgb <= vid_de_now ? overlay : {8'd0, vid_slot, 13'd0};
        vid_hs  <= sel_hs_d1;
        vid_vs  <= sel_vs_d1;
    end

`ifdef PC98_DEBUG_BANDS
    assign video_rgb          = pb_vid_rgb;
    assign video_de           = pb_vid_de;
    assign video_hs           = pb_vid_hs;
    assign video_vs           = pb_vid_vs;
`else
    assign video_rgb          = vid_rgb;
    assign video_de           = vid_de;
    assign video_hs           = vid_hs;
    assign video_vs           = vid_vs;
`endif
`ifndef PC98_DEBUG_BANDS
    assign osd_hcnt = osd_hcnt_g;
    assign osd_vcnt = osd_vcnt_g;
`endif

    assign video_skip         = 1'b0;
    assign video_rgb_clock    = clk_pix;
    assign video_rgb_clock_90 = clk_pix_90;

endmodule
