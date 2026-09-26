// tb_cursor_cdc -- pc98_gdc (master) + the REAL Peripherals CDC + renderer.
//
// The standalone test wired gdc_m_cur_* straight into the renderer. The metal
// does not: en/blink cross as two flops, but addr/top/bot are captured only on
// the rising edge of the synchronised vsync (Peripherals.sv:1243-1257). This
// reproduces that exactly and asks whether the cursor still lands where the
// BIOS put it -- including after the cursor is enabled and moved mid-frame.
`timescale 1ns/1ps
`default_nettype none

module tb_cursor_cdc;
    localparam HALF_NS = 5;
    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;              // the chipset clock (GDC side)

    // A separate, slightly-incommensurate pixel clock for the dot-clock domain.
    logic clk_dot = 1'b0;
    always #(7) clk_dot = ~clk_dot;

    logic reset = 1'b1;

    // ---- GDC port side ---------------------------------------------------
    logic       cs = 1'b0, a1 = 1'b0;
    logic       io_write_n = 1'b1;
    logic [7:0] data_in = 8'h00;
    wire  [7:0] data_out;
    logic       hblank = 1'b0, vsync_in = 1'b0;

    wire        disp_on;
    wire [7:0]  pitch;
    wire [15:0] part_sad [0:3];
    wire [9:0]  part_len [0:3];
    wire [15:0] cursor_addr;
    wire [3:0]  cursor_dot;
    wire        cursor_en, cursor_blink_en;
    wire [4:0]  cursor_top, cursor_bottom;
    wire [5:0]  cursor_rate;
    wire [7:0]  csr_wr_count;
    wire [31:0] csr_trace;
    wire [1:0]  zoom_disp;
    wire        draw_req, draw_busy;
    wire [7:0]  draw_op;
    wire [31:0] draw_snap [0:4];
    wire [7:0]  unk_cmd, unk_count;

    pc98_gdc #(.MASTER(1'b1)) gdc (
        .clk(clk), .reset(reset),
        .cs(cs), .a1(a1), .io_read_n(1'b1), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(data_out),
        .hblank(hblank), .vsync(vsync_in),
        .disp_on(disp_on), .pitch(pitch),
        .part_sad(part_sad), .part_len(part_len),
        .cursor_addr(cursor_addr), .cursor_dot(cursor_dot),
        .cursor_en(cursor_en), .cursor_blink_en(cursor_blink_en),
        .cursor_top(cursor_top), .cursor_bottom(cursor_bottom),
        .cursor_rate(cursor_rate), .zoom_disp(zoom_disp),
        .csr_wr_count(csr_wr_count), .csr_trace(csr_trace),
        .draw_req(draw_req), .draw_op(draw_op), .draw_busy(draw_busy),
        .srv_done_stb(1'b0), .draw_snap(draw_snap),
        .unk_cmd(unk_cmd), .unk_count(unk_count)
    );

    // ---- the raster, in the dot-clock domain -----------------------------------
    // pc98_video_timing makes vsync; here a simple counter frame: 848x440.
    logic [9:0] hcount = 10'd0, vcount = 10'd0;
    wire pc98_vs = (vcount >= 10'd400);        // vblank flag as the vsync source
    logic blink_on = 1'b1;                     // test-controlled blink phase

    // ---- the REAL Peripherals CDC, copied verbatim ------------------------
    logic gdc_on_s1, gdc_on_px;
    logic pc98_vs_s1, pc98_vs_px, pc98_vs_px_d;
    logic [7:0]  gdc_pitch_px;
    logic [15:0] gdc_sad_px;
    logic [15:0] gdc_cur_addr_px;
    logic [4:0]  gdc_cur_top_px, gdc_cur_bot_px;
    logic gdc_cur_en_s1, gdc_cur_en_px;
    logic gdc_cur_bl_s1, gdc_cur_bl_px;

    always_ff @(posedge clk_dot) begin
        gdc_on_s1  <= disp_on;  gdc_on_px  <= gdc_on_s1;
        pc98_vs_s1 <= pc98_vs;  pc98_vs_px <= pc98_vs_s1;
        pc98_vs_px_d <= pc98_vs_px;
        gdc_cur_en_s1 <= cursor_en;  gdc_cur_en_px <= gdc_cur_en_s1;
        gdc_cur_bl_s1 <= cursor_blink_en; gdc_cur_bl_px <= gdc_cur_bl_s1;
        if (pc98_vs_px & ~pc98_vs_px_d) begin
            gdc_pitch_px    <= pitch;
            gdc_sad_px      <= part_sad[0];
            gdc_cur_addr_px <= cursor_addr;
            gdc_cur_top_px  <= cursor_top;
            gdc_cur_bot_px  <= cursor_bottom;
        end
    end



    // ---- renderer ---------------------------------------------------------
    wire  [11:0] tv_cell;
    wire  [6:0]  font_cell;
    wire  [3:0]  font_line;
    wire  [2:0]  grb;
    wire         pixel;
    wire         t_vis;

    logic [7:0] attr_mem [0:4095];
    logic [7:0] tv_attr;
    always_ff @(posedge clk_dot) tv_attr <= attr_mem[tv_cell];
    logic [7:0] font_row;
    always_ff @(posedge clk_dot) font_row <= 8'b1010_0000;

    pc98_text_render #(.H_TOTAL(848), .V_TOTAL(440)) rnd (
        .clk(clk_dot), .pix_ce(1'b1),
        .hcount(hcount), .vcount(vcount), .blink_on(blink_on),
        .gdc_on(gdc_on_px), .gdc_pitch(gdc_pitch_px), .gdc_sad(gdc_sad_px),
        .cur_addr(gdc_cur_addr_px), .cur_en(gdc_cur_en_px),
        .cur_blink(gdc_cur_bl_px),
        .cur_top(gdc_cur_top_px), .cur_bot(gdc_cur_bot_px),
        .tv_cell(tv_cell), .tv_attr(tv_attr),
        .font_cell(font_cell), .font_line(font_line), .font_row(font_row),
        .grb(grb), .pixel(pixel)
    );

    int errors = 0;

    task automatic wr(input logic odd, input logic [7:0] d);
        @(posedge clk);
        cs = 1'b1; a1 = odd; data_in = d; io_write_n = 1'b0;
        // Hold the strobe low for many clk edges -- the real bus keeps it low
        // ~11 clk of the 42.95 MHz chipset clock, not one. A level-sensitive
        // write would re-take the byte into every parameter slot the strobe
        // spans (the cursor-corruption this test guards); the GDC dedups it
        // to a single commit on the strobe's rising edge.
        repeat (11) @(posedge clk);
        io_write_n = 1'b1; cs = 1'b0;
        @(posedge clk);
    endtask
    task automatic cmd(input logic [7:0] c); wr(1'b1, c); endtask
    task automatic par(input logic [7:0] p); wr(1'b0, p); endtask

    // Advance the dot-clock raster one dot per call. The counters step on the
    // posedge; everything downstream (drawn_cell, cursor_show, cur_row, pixel)
    // is combinational and needs the rest of the cycle to settle, so each dot
    // ends with a #2 settle delay and samplers then read a stable pixel.
    task automatic vtick;
        @(posedge clk_dot);
        if (hcount == 10'd847) begin
            hcount <= 10'd0;
            vcount <= (vcount == 10'd439) ? 10'd0 : vcount + 10'd1;
        end else
            hcount <= hcount + 10'd1;
        #2;
    endtask

    task automatic count_cell(input int col, input int row, output int lit);
        int seen, guard;
        lit = 0; seen = 0; guard = 0;
        while (seen < 128) begin
            if (vcount >= 10'(16*row) && vcount < 10'(16*row+16) &&
                hcount >= 10'(8*col) && hcount < 10'(8*col+8)) begin
                seen++;
                if (pixel) lit++;
            end
            vtick;
            if (++guard > 848*440*2) begin
                $display("  (count_cell %0d,%0d timeout)", col, row);
                return;
            end
        end
    endtask

    int lit;
    initial begin
        for (int i = 0; i < 4096; i++) attr_mem[i] = 8'hE1;
        repeat (8) @(posedge clk);
        reset = 1'b0;
        repeat (4) @(posedge clk);

        // The real boot sequence captured from the V30 bench:
        //   RESET, VSYNC-on, SYNC{10 4e 07 25 0d 0f c8 94}, PITCH 50,
        //   ZOOM 00, PRAM part0{SAD0 LEN1ff0} part1{SAD0 LEN0010} ...
        cmd(8'h00);                                              // RESET
        cmd(8'h6F);                                              // VSYNC on
        cmd(8'h0E);
        par(8'h10); par(8'h4e); par(8'h07); par(8'h25);
        par(8'h0d); par(8'h0f); par(8'hc8); par(8'h94);          // SYNC
        cmd(8'h47); par(8'h50);                                  // PITCH 80
        cmd(8'h46); par(8'h00);                                  // ZOOM
        cmd(8'h70);                                              // PRAM, 16 bytes
        par(8'h00); par(8'h00); par(8'hf0); par(8'h1f);          // part0 SAD0 LEN1ff0
        par(8'h00); par(8'h00); par(8'h10); par(8'h00);          // part1
        par(8'h00); par(8'h00); par(8'h00); par(8'h00);          // part2
        par(8'h00); par(8'h00); par(8'h00); par(8'h00);          // part3
        cmd(8'h0D);                                              // START

        // Cursor on (the BIOS's one-byte form), CSRW to cell 82 = (col2,row1).
        cmd(8'h4B); par(8'h8F);
        cmd(8'h49); par(8'd82); par(8'h00);

        $display("csr: en=%0d blink=%0d top=%0d bot=%0d addr=%0d cnt=%0d",
                 cursor_en, cursor_blink_en, cursor_top, cursor_bottom,
                 cursor_addr, csr_wr_count);
        if (cursor_top !== 0 || cursor_bottom !== 15) begin
            $display("FAIL span %0d-%0d want 0-15", cursor_top, cursor_bottom);
            errors++;
        end
        // CSRW {82, 00} must land as the byte pair 0x0052, not 82 repeated --
        // a level-sensitive write would have doubled the low byte into the
        // high slot (0x5252 & 0x3FF). Single commit keeps it 82.
        if (cursor_addr !== 16'd82) begin
            $display("FAIL addr %0d want 82", cursor_addr); errors++;
        end
        // One CSRFORM + one CSRW command total. Multi-cycle io_write_n
        // against the old level-sensitive port counted ~11 arrivals each.
        if (csr_wr_count !== 8'd2) begin
            $display("FAIL cnt %0d want 2", csr_wr_count); errors++;
        end

        // Let two full frames elapse so the vsync latch picks the values up,
        // with blink_on held high so the block is visible.
        blink_on = 1'b1;
        repeat (2) begin
            while (!(vcount == 0 && hcount == 0)) vtick;
            while (!(vcount == 439)) vtick;   // run to near the frame end
            while (!(vcount == 0 && hcount == 0)) vtick;
        end

        $display("px: en=%0d top=%0d bot=%0d addr=%0d  sad=%0d pitch=%0d",
                 gdc_cur_en_px, gdc_cur_top_px, gdc_cur_bot_px,
                 gdc_cur_addr_px, gdc_sad_px, gdc_pitch_px);

        // Per-dot trace across the cursor cell on its first line (vcount=16):
        // col, drawn_cell, cursor_show, glyph bit, lit, pixel.
        begin : tr
            while (!(vcount == 10'd16 && hcount == 10'd8)) vtick;
            $display("  h  col dot drawn_cell cshow glyph lit pix");
            repeat (40) begin
                $display("  %3d c%0d d%0d  cell=%0d  sh=%b gl=%b px=%b",
                         hcount, rnd.col, rnd.dot, rnd.drawn_cell,
                         rnd.cursor_show, rnd.glyph, pixel);
                vtick;
            end
        end

        // Dump a dot map of rows 0..2, cols 0..6 to see the real shape.
        begin : map
            int litmap[0:47][0:55];
            int guard = 0;
            for (int r=0;r<48;r++) for(int c=0;c<56;c++) litmap[r][c]=-1;
            while (vcount != 0 || hcount != 0) vtick;   // align to frame start
            while (guard++ < 848*50) begin
                if (vcount < 48 && hcount < 56)
                    litmap[vcount][hcount] = pixel;
                if (vcount >= 48) break;
                vtick;
            end
            for (int r=0;r<48;r++) begin
                string s = "";
                for (int c=0;c<56;c++) s = {s, litmap[r][c]? "#":"."};
                $display("  r%02d %s", r, s);
            end
        end

        count_cell(2, 1, lit);
        $display("cell (2,1) lit: %0d / 128  (want 96 = inverted block)", lit);
        if (lit !== 96) begin
            $display("FAIL cursor block not at (2,1)"); errors++;
        end
        count_cell(3, 1, lit);
        if (lit !== 32) begin
            $display("FAIL neighbour (3,1) lit %0d want 32", lit); errors++;
        end

        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d)", errors);
        $finish;
    end
endmodule
`default_nettype wire
