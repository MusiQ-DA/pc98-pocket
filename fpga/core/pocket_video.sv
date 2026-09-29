//
// Pocket video output: composite the machine's raster and the softcore's OSD
// framebuffer into the Analogue APF scaler stream. The machine raster is the
// pass-through default; the stages below special-case only what differs from
// it: the palette tint, the sync-guard overlay, and the final
// pack of RGB + single-cycle HS/VS + DE with the scaler-slot word held
// through blanking. Runs on clk_pix, the dot clock's half-rate sibling (one
// pixel per edge).
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
    input             disk_led,   // on-screen disk-access lamp (stretched level)
    input             vid_blank,
    // OSD framebuffer handshake (softcore)
    input             osd_active,
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
    // Card blanking
    //
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
    // No padding: the machine raster is the picture, edge to edge.

    //
    // Overlay sync guard
    //
    // When the guest video timing leaves spec (a guest can program the CRTC to stall HSYNC
    // or suppress VSYNC), supply a stable frame for an open OSD/VKB to ride on so it stays
    // framed. `guard_run` engages only with an overlay open.
    wire osd_enable;
    synch_3 s_osd_enable_pix (osd_active, osd_enable, clk_pix);

    // No guard on this machine.
    //
    // The guard exists because a guest can program the CRTC to stall
    // HSYNC or suppress VSYNC, and an open overlay then has no stable frame to
    // ride on. This machine has one raster, fixed at 640x400 by
    // pc98_video_timing, and no way to leave spec.
    //
    // Left in, it does not merely idle: tb_pc98_osdwin measures it engaged for
    // 1119361 cycles out of 1119360 -- permanently -- because it is calibrated
    // for a 640x200 frame and reads this 400-line one as out of spec. It then
    // substitutes its own 200-line raster, so osd_vcnt reaches 199 instead of
    // 399 while osd_raster_h still reports 400, and the softcore places its
    // panel across lines the presented frame never has. It also forces the
    // picture black for as long as it runs.
    wire guard_run = 1'b0;
    wire gen_hs = 1'b0, gen_vs = 1'b0, gen_hb = 1'b0, gen_vb = 1'b0;

    //
    // Presented raster
    //
    // The guest's raster, or the sync guard's generated frame once it has taken over.
    // Everything downstream (OSD counters, output sync, DE) rides on these four.
    wire sel_hs = guard_run ? gen_hs : HSync;
    wire sel_vs = guard_run ? gen_vs : VSync;
    wire sel_hb = guard_run ? gen_hb : vid_hb;
    wire sel_vb = guard_run ? gen_vb : vid_vb;

    // The output register delays the composited RGB one clk_pix; stage the presented
    // sync/blanking to match, so both align at the final register. sel_hb_d1 also
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
    // window countdown, else an hblank-fall counter parked at -1 so the
    // first fall (after VBlank) is line 0.
    reg [9:0] osd_hcnt_g   = 10'd0;
    reg [9:0] osd_vcnt_raw = 10'd0;
    always @(posedge clk_pix) begin
        if (sel_hb)                   osd_hcnt_g <= 10'd0;
        else                          osd_hcnt_g <= osd_hcnt_g + 10'd1;
        if (sel_vb)                   osd_vcnt_raw <= 10'd1023;
        else if (sel_hb_d1 & ~sel_hb) osd_vcnt_raw <= osd_vcnt_raw + 10'd1;
    end
    wire [9:0] osd_vcnt_g = osd_vcnt_raw;

    // Presented raster size, read by the softcore to place the overlay window;
    // the canvas reports its 349 usable lines, excluding the sacrificial one.
    // One raster, 640x400. Reporting 200 lines
    // put the softcore's panel in the top half of a 400-line picture.
    assign osd_raster_w = 10'd640;
    assign osd_raster_h = 10'd400;

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
    // Scaler slot: video.json declares exactly one mode (640x400), so slot 0
    // is the only word the scaler can be handed.
    wire [2:0] vid_slot = 3'd0;

    // Final pack: DE from the staged presented blanking, the overlay layered over the
    // picture (black behind it under the sync guard), sync staged to match. While DE is low
    // the bus carries the scaler-slot word ([23:13]), held through all of blanking: a zero
    // bus is itself slot 0 and the last word wins.
    reg  [23:0] vid_rgb = 24'd0;
    reg         vid_de  = 1'b0;
    reg         vid_hs  = 1'b0;
    reg         vid_vs  = 1'b0;
    // DE keeps running under vid_blank: the blank forces the PIXELS dark
    // (in the overlay mux below) rather than starving DE, so the scaler sees
    // an ordinary all-black frame and cannot treat the input as lost.
    wire        vid_de_now = ~(sel_hb_d1 | sel_vb_d1);


    // Disk-access lamp: a 12x12 amber square tucked just inside the top-right
    // corner of the raster, over the picture and under the OSD.
    wire lamp_in = disk_led && (rb_h >= PC98_H_ACTIVE - 10'd20) && (rb_h < PC98_H_ACTIVE - 10'd8)
                            && (rb_v >= 10'd8) && (rb_v < 10'd20);

    wire [23:0] overlay    = vid_blank_pix ? 24'd0
                           : osd_show      ? osd_color
                           : guard_run     ? 24'd0
                           : lamp_in       ? 24'hE0A020
                           :                 {tr, tg, tb};
    always @(posedge clk_pix) begin
        vid_de  <= vid_de_now;
        vid_rgb <= vid_de_now ? overlay : {8'd0, vid_slot, 13'd0};
        vid_hs  <= sel_hs_d1;
        vid_vs  <= sel_vs_d1;
    end

    assign video_rgb          = vid_rgb;
    assign video_de           = vid_de;
    assign video_hs           = vid_hs;
    assign video_vs           = vid_vs;
    assign osd_hcnt = osd_hcnt_g;
    assign osd_vcnt = osd_vcnt_g;

    assign video_skip         = 1'b0;
    assign video_rgb_clock    = clk_pix;
    assign video_rgb_clock_90 = clk_pix_90;

endmodule
