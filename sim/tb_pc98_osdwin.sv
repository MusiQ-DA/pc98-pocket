//
// tb_pc98_osdwin -- does the OSD's coordinate system ever reach its window?
//
// The overlay is placed by a range test on osd_hcnt/osd_vcnt, which pocket_video
// derives from the presented blanking. On hardware nothing indexed by those two
// has ever appeared -- not the overlay, not the RTL status bands, not even a
// sixteen-pixel square at their origin -- while everything driven from a
// free-running raster did. So the question is exactly this: fed the PC-98
// raster the way PERIPHERALS feeds it, do those counters sweep 0..639 and
// 0..399, or do they sit somewhere unreachable?
//
// This is the real connection, not a model of it: pc98_video_timing's outputs
// go to pocket_video's HSync/VSync/HBlank/VBlank exactly as PERIPHERALS assigns
// them.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_osdwin;

    logic clk_pix = 1'b0;
    always #23.75 clk_pix = ~clk_pix;      // 21.0526 MHz

    logic [9:0] h, v;
    wire  hs, vs, hb, vb, de, fs;

    pc98_video_timing u_t (
        .clk(clk_pix), .ce(1'b1), .rst(1'b0),
        .hcount(h), .vcount(v),
        .hsync(hs), .vsync(vs), .hblank(hb), .vblank(vb),
        .de(de), .frame_start(fs)
    );

    wire [9:0] osd_hcnt, osd_vcnt, osd_raster_w, osd_raster_h;
    wire [23:0] video_rgb;
    wire        video_de, video_hs, video_vs, video_skip;
    wire        video_rgb_clock, video_rgb_clock_90;

    pocket_video u_pv (
        .clk_pix         (clk_pix),
        .clk_pix_90      (clk_pix),
        .RESET           (1'b0),
        .r               (6'h3F),
        .g               (6'h00),
        .b               (6'h00),
        .HSync           (hs),
        .VSync           (vs),
        .HBlank          (hb),
        .VBlank          (vb),
        .palette_cfg     (3'd0),
        .credits_mode_pix(1'b0),
        .pix_sel         (1'b0),
        .vid_blank       (1'b0),
        .osd_active      (1'b1),
        .dbg_bits        (16'd0),
        .osd_palette_idx (4'd0),
        .osd_in_area     (1'b0),
        .osd_hcnt        (osd_hcnt),
        .osd_vcnt        (osd_vcnt),
        .osd_raster_w    (osd_raster_w),
        .osd_raster_h    (osd_raster_h),
        .video_rgb       (video_rgb),
        .video_de        (video_de),
        .video_hs        (video_hs),
        .video_vs        (video_vs),
        .video_skip      (video_skip),
        .video_rgb_clock (video_rgb_clock),
        .video_rgb_clock_90 (video_rgb_clock_90)
    );

    // Measure in steady state: the first frames are the counters settling, and
    // a settling transient reported as a result is how a healthy path gets
    // called broken.
    logic       run = 1'b0;
    wire        guard = u_pv.guard_run;
    int         guard_cyc = 0;
    logic [9:0] hmin = 10'h3FF, hmax = 10'd0, vmin = 10'h3FF, vmax = 10'd0;
    int de_on = 0, de_off = 0, hb_hi = 0, vb_hi = 0;
    int mark_hits = 0, win_hits = 0;

    always @(posedge clk_pix) begin
        if (!run) begin
            hb_hi = 0; vb_hi = 0; de_on = 0; de_off = 0;
            mark_hits = 0; win_hits = 0; guard_cyc = 0;
            hmin = 10'h3FF; hmax = 10'd0; vmin = 10'h3FF; vmax = 10'd0;
        end
        if (guard) guard_cyc++;
        if (hb) hb_hi++;
        if (vb) vb_hi++;
        if (video_de) de_on++; else de_off++;
        if (video_de) begin
            if (osd_hcnt < hmin) hmin = osd_hcnt;
            if (osd_hcnt > hmax) hmax = osd_hcnt;
            if (osd_vcnt < vmin) vmin = osd_vcnt;
            if (osd_vcnt > vmax) vmax = osd_vcnt;
            // The marker's test, and the overlay's own 640x200 window with the
            // origin the firmware would pick for a centred panel.
            if (osd_hcnt < 10'd16 && osd_vcnt < 10'd16) mark_hits++;
            if (osd_hcnt < 10'd640 && osd_vcnt >= 10'd100 && osd_vcnt < 10'd300)
                win_hits++;
        end
    end

    initial begin
        repeat (3 * 848 * 440) @(posedge clk_pix);   // settle
        run = 1'b1;
        repeat (3 * 848 * 440) @(posedge clk_pix);   // measure
        $display("raster reported to the softcore: %0d x %0d",
                 osd_raster_w, osd_raster_h);
        $display("hblank high %0d cycles, vblank high %0d", hb_hi, vb_hi);
        $display("sync guard engaged %0d cycles of %0d", guard_cyc, 3*848*440);
        $display("DE high %0d, low %0d  (expect 640*400*3 = %0d high)",
                 de_on, de_off, 640*400*3);
        $display("osd_hcnt over DE: %0d .. %0d   (want 0 .. 639)", hmin, hmax);
        $display("osd_vcnt over DE: %0d .. %0d   (want 0 .. 399)", vmin, vmax);
        $display("origin marker hit %0d times (want 16*16*3 = %0d)",
                 mark_hits, 16*16*3);
        $display("panel window hit %0d times (want 640*200*3 = %0d)",
                 win_hits, 640*200*3);
        // Strict, because every one of these has been wrong on hardware at
        // least once: the guard must stay out, DE must cover the whole active
        // area, and the counters must span it.
        if (guard_cyc != 0)
            $display("FAIL: the sync guard engaged (%0d cycles)", guard_cyc);
        else if (de_on != 640*400*3)
            $display("FAIL: DE covered %0d of %0d active dots", de_on, 640*400*3);
        else if (vmax != 10'd399)
            $display("FAIL: osd_vcnt reached %0d, not 399", vmax);
        else if (mark_hits == 0 || win_hits == 0)
            $display("FAIL: the OSD's coordinates never reach their window");
        else
            $display("PASS");
        $finish;
    end

endmodule

`default_nettype wire
