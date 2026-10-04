//
// tb_pc98_textscroll -- the text plane under a scrolled and re-pitched GDC.
//
// The uPD7220 does not keep a "screen": it walks TVRAM cells from SAD, one
// PITCH of cells per text line, both wrapped at twelve bits (np21w
// vram/maketext.c). Until now only pc98_text_render consumed that mapping --
// the glyph row buffer was fed a hardcoded row*80, so a scroll (SAD != 0) or
// a non-80 pitch drew the right ATTRIBUTES over the wrong CODES. This bench
// puts the real modules under a scrolled master GDC and checks the whole
// fetch contract:
//
//   * pc98_text_rowbase produces LOW12(SAD + row*PITCH) with the
//     unprogrammed-GDC fallback -- the value Peripherals will feed as
//     row_base once wired (the parent still sends row*80 today)
//   * the row buffer walks exactly those cells and wraps the 4K ring
//   * the renderer's attribute port is in the same space (it already was)
//   * the cursor, which lives in SAD space like np21w's `edi == csrw`,
//     lands on the mapped cell -- i.e. it scrolls WITH the content
//   * a non-0x50 PITCH moves every row base
//
// Plus the odd-byte attribute read: np21w's memtram_rd8 is a plain byte
// array read, so the odd lane answers 0x00 (never written), not the
// attribute it aliases in our cell-indexed bank.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_textscroll;

    // Chipset clock ~43 MHz, dot clock ~21 MHz -- same pair tb_pc98_pipeline
    // uses; the exact ratio is beside the point.
    logic clk = 0;      always #12 clk = ~clk;
    logic clk_dot = 0;  always #23 clk_dot = ~clk_dot;

    logic rst = 1'b1;
    int   errors = 0;

    // ------------------------------------------------------ guest bus model
    // cpu_addr is the byte offset inside A0000-A3FFF, exactly what
    // Peripherals drives into the TVRAM.
    logic [13:0] cpu_addr  = 14'd0;
    logic        cpu_wren  = 1'b0;
    logic  [7:0] cpu_wdata = 8'h00;
    wire   [7:0] cpu_q;

    // --------------------------------------------------- the master GDC
    // One register set feeds both consumers, the way a real GDC would: the
    // row-base mapper (row buffer side) and the renderer (attribute side).
    logic        gdc_on    = 1'b0;
    logic  [7:0] gdc_pitch = 8'd0;
    logic [15:0] gdc_sad [0:3] = '{default: 16'd0};
    logic [9:0]  gdc_len [0:3] = '{default: 10'd0};

    // ------------------------------------------------------------ TVRAM
    wire [11:0] fil_cell;
    wire  [7:0] fil_char_lo, fil_char_hi;
    wire [11:0] vid_cell;
    wire  [7:0] vid_attr;

    pc98_tvram u_tvram (
        .clk(clk), .rst(rst),
        .cpu_addr(cpu_addr), .cpu_wren(cpu_wren), .cpu_wdata(cpu_wdata),
        .cpu_rden(1'b1), .cpu_q(cpu_q),
        .dbg_cell(12'h000), .dbg_q(),
        .fil_clk(clk),   .fil_cell(fil_cell),
        .fil_char_lo(fil_char_lo), .fil_char_hi(fil_char_hi),
        .vid_clk(clk_dot), .vid_cell(vid_cell), .vid_attr(vid_attr),
        .cfg_a3fea(8'h04), .cfg_a3fee(8'h00), .cfg_a3ff2(8'h01)
    );

    // --------------------------------------------- the row-base mapper
    logic [4:0]  fill_row = 5'd0;
    wire  [11:0] row_base;

    pc98_text_rowbase u_map (
        .gdc_on(gdc_on), .gdc_pitch(gdc_pitch),
        .gdc_sad(gdc_sad), .gdc_len(gdc_len),
        .row(fill_row), .base(row_base)
    );

    // ------------------------------------------------------- row buffer
    // bitac = 0 forces every cell ANK, so the fill never touches the SDRAM
    // font port; glyphs come from the ANK model's two-clock BRAM pattern.
    logic        fill_start = 1'b0;
    wire         busy;
    wire         f_req;
    wire  [19:0] f_addr;
    wire   [7:0] ank_code;
    wire   [3:0] ank_line;
    logic  [7:0] ank_row = 8'h00;
    logic  [6:0] rd_col  = 7'd0;
    logic  [3:0] rd_line = 4'd0;
    wire   [7:0] rd_byte;
    wire         kanji_seen;

    pc98_glyph_rowbuf #(.COLS(80)) dut (
        .clk(clk), .rst(rst),
        .fill_start(fill_start), .row_base(row_base),
        .bitac(8'h00), .wide(1'b0), .sel8(1'b0), .busy(busy),
        .tv_cell(fil_cell), .tv_char_lo(fil_char_lo), .tv_char_hi(fil_char_hi),
        .f_req(f_req), .f_addr(f_addr),
        .f_busy(1'b0), .f_valid(1'b0), .f_data(8'h00),
        .ank_code(ank_code), .ank_line(ank_line), .ank_row(ank_row),
        .rd_clk(clk), .rd_cell(rd_col), .rd_line(rd_line),
        .rd_byte(rd_byte), .kanji_seen(kanji_seen)
    );

    // ANK model: one cycle of BRAM latency; the byte names its own
    // (code nibble, line) so a cell fetched from the wrong address reads
    // out as a wrong pattern, not a plausible glyph.
    always_ff @(posedge clk) ank_row <= {ank_code[3:0], ank_line};

    // ---------------------------------------------------------- renderer
    logic [9:0]  hcnt = 10'd0, vcnt = 10'd0;
    logic [15:0] cur_addr = 16'hFFFF;
    logic        cur_en   = 1'b0;
    wire   [2:0] grb;
    wire         pixel;
    wire   [6:0] font_cell;
    wire   [3:0] font_line;

    pc98_text_render #(.H_TOTAL(848), .V_TOTAL(440)) u_render (
        .clk(clk_dot), .pix_ce(1'b1),
        .hcount(hcnt), .vcount(vcnt), .blink_on(1'b1),
        .gdc_on(gdc_on), .gdc_pitch(gdc_pitch),
        .gdc_sad(gdc_sad), .gdc_len(gdc_len),
        .wide(1'b0),
        .cur_addr(cur_addr), .cur_en(cur_en), .cur_blink(1'b0),
        .cur_top(5'd0), .cur_bot(5'd15),
        .tv_cell(vid_cell), .tv_attr(vid_attr),
        .font_cell(font_cell), .font_line(font_line),
        .font_row(8'h00), .grb(grb), .pixel(pixel),
        .crtc_pl(5'd0), .crtc_bl(5'h0F), .crtc_cl(5'h10), .line_rep(5'h0F)
    );

    // The raster free-runs like pc98_video_timing's 848x440.
    always_ff @(posedge clk_dot) begin
        if (hcnt == 10'd847) begin
            hcnt <= 10'd0;
            vcnt <= (vcnt == 10'd439) ? 10'd0 : vcnt + 10'd1;
        end else begin
            hcnt <= hcnt + 10'd1;
        end
    end

    // ---------------------------------------------------- bus primitives
    task automatic bus_write(input [13:0] a, input [7:0] d);
        @(negedge clk);
        cpu_addr  = a;
        cpu_wdata = d;
        cpu_wren  = 1'b1;
        @(negedge clk);
        cpu_wren  = 1'b0;
        cpu_addr  = 14'd0;
    endtask

    task automatic bus_read(input [13:0] a, output [7:0] d);
        @(negedge clk);
        cpu_addr = a;
        repeat (3) @(negedge clk);
        d = cpu_q;
    endtask

    // Code plane at cc*2, attribute at 0x2000+cc*2 -- the real map. (`cell`
    // is a Verilog-2001 config reserved word.)
    task automatic put_cell(input int cc, input [15:0] code,
                            input [7:0] attr);
        bus_write(14'(cc*2),              code[7:0]);
        bus_write(14'(cc*2) + 14'd1,      code[15:8]);
        bus_write(14'h2000 + 14'(cc*2),   attr);
    endtask

    task automatic rd8_check(input [13:0] a, input [7:0] want,
                             input string what);
        automatic logic [7:0] got;
        bus_read(a, got);
        if (got !== want) begin
            $display("  FAIL %s: read %04h got %02h want %02h",
                     what, a, got, want);
            errors++;
        end
    endtask

    task automatic base_check(input [4:0] r, input [11:0] want,
                              input string what);
        #1;
        if (row_base !== want) begin
            $display("  FAIL %s: row %0d base %03h want %03h",
                     what, r, row_base, want);
            errors++;
        end
    endtask

    task automatic do_fill(input [4:0] r);
        @(negedge clk);
        fill_row   = r;
        fill_start = 1'b1;
        @(negedge clk);
        fill_start = 1'b0;
        wait (busy == 1'b1);
        wait (busy == 1'b0);
    endtask

    task automatic rd_glyph_check(input [6:0] c, input [3:0] l,
                                  input [7:0] want, input string what);
        rd_col  = c;
        rd_line = l;
        repeat (3) @(negedge clk);
        if (rd_byte !== want) begin
            $display("  FAIL %s: slot %0d line %0d got %02h want %02h",
                     what, c, l, rd_byte, want);
            errors++;
        end
    endtask

    // ------------------------------------------------- the fill's cell walk
    // Collapses the per-column holds into the sequence of distinct cells the
    // fill asked for; each must be LOW12(base + n). tv_cell keeps its stale
    // value for the first busy cycle, so the walk is baselined once busy is
    // up and only changes after that count.
    logic        f_watch = 1'b0;
    logic        f_armed = 1'b0;
    logic [12:0] f_prev  = 13'h1FFF;
    int          f_count = 0;
    logic [11:0] f_base  = 12'd0;
    int          walk_errors = 0;

    always_ff @(posedge clk) begin
        if (fill_start) begin
            f_watch <= 1'b1;
            f_armed <= 1'b0;
            f_prev  <= {1'b0, fil_cell};
            f_count <= 0;
            f_base  <= row_base;
        end else if (f_watch && busy && !f_armed) begin
            f_armed <= 1'b1;
            f_prev  <= {1'b0, fil_cell};
        end else if (f_watch && busy && ({1'b0, fil_cell} != f_prev)) begin
            if (fil_cell !== 12'((f_base + f_count) & 12'hFFF)) begin
                $display("  FAIL fill cell %0d: got %03h want %03h",
                         f_count, fil_cell,
                         12'((f_base + f_count) & 12'hFFF));
                walk_errors++;
            end
            f_prev  <= {1'b0, fil_cell};
            f_count <= f_count + 1;
        end else if (f_watch && !busy) begin
            f_watch <= 1'b0;
            if (f_count != 80) begin
                $display("  FAIL fill walked %0d cells, want 80", f_count);
                walk_errors++;
            end
        end
    end

    // -------------------------------------------------- renderer samplers
    // vid_cell is the renderer's one-cell-ahead fetch: during char time c it
    // points at cell c+1, and at the line's last character time at the next
    // line's cell 0 -- which, at a text row boundary, is the NEXT ROW's
    // base. That makes (v=15, h=845) the row-1 base and (v=0, h=845) the
    // row-0 base.
    logic [11:0] vc_row0_c1, vc_row0_base, vc_row1_base, vc_row1_c1;
    always_ff @(posedge clk_dot) begin
        if (vcnt == 10'd0  && hcnt == 10'd0)   vc_row0_c1   <= vid_cell;
        if (vcnt == 10'd0  && hcnt == 10'd845) vc_row0_base <= vid_cell;
        if (vcnt == 10'd15 && hcnt == 10'd845) vc_row1_base <= vid_cell;
        if (vcnt == 10'd16 && hcnt == 10'd0)   vc_row1_c1   <= vid_cell;
    end

    // Pixels at the cells under test: col 7 (h 56-63) carries the vertline
    // attribute, col 20 (h 160-167) carries the cursor.
    logic px_vl_d0, px_vl_d1, px_vl_next;
    logic px_cur_a, px_cur_b, px_cur_next;
    always_ff @(posedge clk_dot) begin
        if (vcnt == 10'd3 && hcnt == 10'd56)  px_vl_d0    <= pixel;
        if (vcnt == 10'd3 && hcnt == 10'd57)  px_vl_d1    <= pixel;
        if (vcnt == 10'd3 && hcnt == 10'd64)  px_vl_next  <= pixel;
        if (vcnt == 10'd5 && hcnt == 10'd160) px_cur_a    <= pixel;
        if (vcnt == 10'd5 && hcnt == 10'd165) px_cur_b    <= pixel;
        if (vcnt == 10'd5 && hcnt == 10'd168) px_cur_next <= pixel;
    end

    task automatic px_check(input logic got, input logic want,
                            input string what);
        if (got !== want) begin
            $display("  FAIL %s: pixel %0d want %0d", what, got, want);
            errors++;
        end
    endtask

    // ------------------------------------------------------------ the run
    initial begin
        $display("=== text plane under SAD/PITCH ===");

        // The reset sweep: the TVRAM clears itself one cell a clock.
        repeat (5000) @(posedge clk);
        rst = 1'b0;
        repeat (20) @(posedge clk);

        // ------------------------------------------------ 1. the mapper
        // Unprogrammed GDC: today's row*80 picture must survive.
        gdc_on = 1'b0; gdc_pitch = 8'd0; gdc_sad[0] = 16'd0;
        fill_row = 5'd7;  base_check(5'd7, 12'd560, "GDC off falls back");
        // START but no PITCH yet: same fallback.
        gdc_on = 1'b1; gdc_pitch = 8'd0;
        base_check(5'd7, 12'd560, "pitch 0 falls back");
        // Programmed but trivial: SAD 0, PITCH 80 -- the old expression.
        gdc_pitch = 8'h50; gdc_sad[0] = 16'h0000;
        base_check(5'd7, 12'd560, "SAD 0 pitch 80 parity");
        // Scrolled by one line: SAD = pitch.
        gdc_sad[0] = 16'h0080;
        fill_row = 5'd3; base_check(5'd3, 12'h170, "SAD 0x80 row 3");
        // A narrow pitch, and an odd register value losing its low bit.
        gdc_pitch = 8'h28;
        fill_row = 5'd4; base_check(5'd4, 12'h120, "pitch 40 row 4");
        gdc_pitch = 8'h29;
        base_check(5'd4, 12'h120, "pitch 0x29 reads as 0x28");
        // The ring: SAD near the top wraps LOW12.
        gdc_pitch = 8'h50; gdc_sad[0] = 16'h0FE0;
        fill_row = 5'd0;  base_check(5'd0,  12'hFE0, "wrap row 0");
        fill_row = 5'd1;  base_check(5'd1,  12'h030, "wrap row 1");
        fill_row = 5'd24; base_check(5'd24, 12'h760, "wrap row 24");

        // The four PRAM partitions tile rows (np21w maketext.c): ten rows
        // in partition 0, then partition 1 to the bottom -- a LEN of zero
        // never ends, so the "rest" partition needs no height of its own.
        gdc_len[0] = 10'd10; gdc_len[1] = 10'd0;
        gdc_sad[0] = 16'h0100; gdc_sad[1] = 16'h0300;
        fill_row = 5'd9;  base_check(5'd9,  12'h3D0, "part0 last row");
        fill_row = 5'd10; base_check(5'd10, 12'h300, "part1 first row");
        fill_row = 5'd24; base_check(5'd24, 12'h760, "part1 rel 14");
        gdc_len[0] = 10'd0; gdc_sad[1] = 16'd0;   // every row in part0 again

        // ----------------------------------- 2. the fill walks those cells
        // Codes name their position: cell (base + c) gets code c+1, so the
        // slot's ANK byte for line L is {c+1[3:0], L}.
        for (int c = 0; c < 80; c++)
            put_cell((16'hFE0 + c) & 16'hFFF, 16'(c + 1), 8'hE1);

        gdc_on = 1'b1; gdc_pitch = 8'h50; gdc_sad[0] = 16'h0FE0;
        do_fill(5'd0);           // fills cells FE0..FFF, 000..02F
        do_fill(5'd1);           // second fill flips the bank for reads

        // The ANK byte is {code[3:0], line}: code c+1 at mapped position c.
        rd_glyph_check(7'd0,  4'd0,  8'h10, "wrap row, slot 0");
        rd_glyph_check(7'd31, 4'd7,  8'h07, "wrap row, slot 31 (cell FFF)");
        rd_glyph_check(7'd32, 4'd15, 8'h1F, "wrap row, slot 32 (cell 000)");
        rd_glyph_check(7'd79, 4'd3,  8'h03, "wrap row, slot 79");

        // A non-0x50 pitch moves the same rows elsewhere: base 0x1A0.
        for (int c = 0; c < 80; c++)
            put_cell(16'h1A0 + c, 16'h60 + c, 8'hE1);
        gdc_sad[0] = 16'h0100; gdc_pitch = 8'h28;   // effective 40
        do_fill(5'd4);                            // base = 100 + 4*40 = 1A0
        do_fill(5'd5);
        rd_glyph_check(7'd0,  4'd0,  8'h00, "pitch40 row, slot 0");
        rd_glyph_check(7'd1,  4'd5,  8'h15, "pitch40 row, slot 1");
        rd_glyph_check(7'd63, 4'd9,  8'hF9, "pitch40 row, slot 63");

        // ----------------------------------- 3. odd-byte attribute reads
        // np21w memtram_rd8 is a plain byte array: even attr bytes answer the
        // attribute, odd ones answer the never-written default 0x00.
        put_cell(5, 16'h0000, 8'hE1);
        rd8_check(14'h200A, 8'hE1, "attr even byte");
        rd8_check(14'h200B, 8'h00, "attr odd byte is raw 00");
        bus_write(14'h200B, 8'h99);               // odd writes land nowhere
        rd8_check(14'h200A, 8'hE1, "odd write did not alias");
        rd8_check(14'h200B, 8'h00, "odd byte still 00");
        // The memory switch is an even-byte object too: A3FE2 reads the
        // register, A3FE3 reads the same unwritten 0x00.
        rd8_check(14'h3FE2, 8'h48, "memsw A3FE2");
        rd8_check(14'h3FE3, 8'h00, "memsw odd byte is raw 00");
        // The character region keeps its byte lanes.
        rd8_check(14'h000A, 8'h00, "char lo lane");
        put_cell(9, 16'h2204, 8'hE1);
        rd8_check(14'h0012, 8'h04, "char lo byte");
        rd8_check(14'h0013, 8'h22, "char hi byte");

        // --------------------------------- 4. the renderer's mapped space
        // SAD 0x100, pitch 80: screen row 0 draws cells 100+, row 1 180+.
        gdc_sad[0] = 16'h0100; gdc_pitch = 8'h50;
        // vertline attribute only at the MAPPED col 7 (cell 0x107); the
        // cursor at the MAPPED col 20 (cell 0x114) with a blank attribute.
        put_cell(16'h107, 16'h0000, 8'h11);
        put_cell(16'h114, 16'h0000, 8'h00);
        cur_addr = 16'h0114;
        cur_en   = 1'b1;

        wait (vcnt == 10'd0);        // a clean frame for the samplers
        wait (vcnt == 10'd20);       // one pass of the checks' lines
        if (vc_row0_c1   !== 12'h101) begin
            $display("  FAIL vid_cell row0 col fetch: got %03h want 101",
                     vc_row0_c1);
            errors++;
        end
        if (vc_row0_base !== 12'h100) begin
            $display("  FAIL vid_cell row0 base: got %03h want 100",
                     vc_row0_base);
            errors++;
        end
        if (vc_row1_base !== 12'h150) begin
            $display("  FAIL vid_cell row1 base: got %03h want 150",
                     vc_row1_base);
            errors++;
        end
        if (vc_row1_c1   !== 12'h151) begin
            $display("  FAIL vid_cell row1 col fetch: got %03h want 151",
                     vc_row1_c1);
            errors++;
        end
        px_check(px_vl_d0,    1'b1, "vertline dot at mapped col 7");
        px_check(px_vl_d1,    1'b0, "vertline only dot 0");
        px_check(px_vl_next,  1'b0, "unwritten attr stays dark");
        px_check(px_cur_a,    1'b1, "cursor on mapped col 20");
        px_check(px_cur_b,    1'b1, "cursor holds the cell");
        px_check(px_cur_next, 1'b0, "cursor stops at the cell edge");

        // A re-pitch mid-run moves the row base the NEXT frame uses.
        gdc_sad[0] = 16'h0200; gdc_pitch = 8'h28;
        wait (vcnt == 10'd439);
        wait (vcnt == 10'd20);
        if (vc_row1_base !== 12'h228) begin
            $display("  FAIL vid_cell row1 repitched base: got %03h want 228",
                     vc_row1_base);
            errors++;
        end

        $display("");
        $display("  errors: %0d", errors + walk_errors);
        $display("  RESULT: %s",
                 errors + walk_errors == 0 ? "PASS" : "FAIL");
        $finish;
    end

    // Bound the run at ~3 raster frames of dot clocks.
    initial begin
        repeat (1_200_000) @(posedge clk_dot);
        $display("  TIMEOUT");
        $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
