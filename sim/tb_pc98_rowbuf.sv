//
// tb_pc98_rowbuf -- does a text row's glyphs end up in the buffer?
//
// Drives a model TVRAM and a model font, fills one row, and reads it back the
// way the renderer will. What is actually being checked:
//
//   * every cell of the row gets its sixteen bytes, from the right address
//   * a kanji occupies TWO cells -- the first draws the left half, the second
//     the right half of the SAME character, and the second cell's own contents
//     are not treated as a character
//   * the buffer is double-buffered, so what the renderer reads during a fill
//     is the previous row and not a half-written one
//
// The kanji pairing is the part worth a bench. Getting it wrong shifts every
// character after the first kanji on the line by one cell, which looks like a
// font or a TVRAM problem rather than a pairing one.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_rowbuf;

    localparam int COLS = 80;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic        fill_start = 1'b0;
    logic [11:0] row_base = 12'd0;
    logic  [7:0] bitac = 8'hFF;
    wire         busy;

    wire [11:0] tv_cell;
    logic [7:0] tv_char_lo, tv_char_hi;

    wire        f_req;
    wire [19:0] f_addr;
    logic       f_busy = 1'b0, f_valid = 1'b0;
    logic [7:0] f_data = 8'h00;

    // The ANK side: the REAL BRAM, loaded with a pattern that names the byte
    // -- {code[3:0], line[3:0]} -- so a wrong glyph address or a wrong line
    // order reads out as a wrong value rather than as a plausible font.
    wire  [7:0] ank_code;
    wire  [3:0] ank_line;
    wire  [7:0] ank_row;
    wire [12:0] gaiji_addr;
    wire  [7:0] gaiji_data;
    logic       gaiji_we = 1'b0;
    logic [12:0] gaiji_waddr = 13'd0;
    logic  [7:0] gaiji_wdata = 8'd0;
    logic       font_wr_en = 1'b0;
    logic [11:0] font_wr_addr = 12'd0;
    logic [15:0] font_wr_data = 16'd0;
    logic        sel8 = 1'b0;
    logic        wide = 1'b0;

    logic [6:0] rd_col = 7'd0;
    logic [3:0] rd_line = 4'd0;
    wire  [7:0] rd_byte;
    wire        kanji_seen;

    pc98_glyph_rowbuf #(.COLS(COLS)) dut (
        .clk(clk), .rst(rst),
        .fill_start(fill_start), .row_base(row_base), .bitac(bitac),
        .wide(wide), .sel8(sel8), .busy(busy),
        .tv_cell(tv_cell), .tv_char_lo(tv_char_lo), .tv_char_hi(tv_char_hi),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data),
        .ank_code(ank_code), .ank_line(ank_line), .ank_row(ank_row),
        .gaiji_addr(gaiji_addr), .gaiji_data(gaiji_data),
        .rd_clk(clk), .rd_cell(rd_col), .rd_line(rd_line), .rd_byte(rd_byte), .kanji_seen(kanji_seen)
    );

    pc98_font_ank u_ank (
        .wr_clk(clk), .wr_en(font_wr_en), .wr_addr(font_wr_addr),
        .wr_data(font_wr_data),
        .rd_clk(clk), .code(ank_code), .line(ank_line), .sel8(sel8), .row(ank_row)
    );

    // The real gaiji store: the bench plays the guest on port A, the row
    // buffer reads port B.
    pc98_gaiji_ram u_gaiji (
        .clk(clk),
        .a_we(gaiji_we), .a_addr(gaiji_waddr), .a_wdata(gaiji_wdata),
        .a_rdata(),
        .b_addr(gaiji_addr), .b_rdata(gaiji_data)
    );

    function automatic logic [7:0] ank_pat(input logic [7:0] code,
                                           input logic [3:0] line);
        ank_pat = {code[3:0], line};
    endfunction

    // 8x8-bank pattern: {1, code[3:0], row[2:0]} -- the top bit marks the
    // bank so an 8x16 byte can never alias as a passing 8x8 read.
    function automatic logic [7:0] ank8_pat(input logic [7:0] code,
                                            input logic [2:0] row);
        ank8_pat = {1'b1, code[3:0], row};
    endfunction

    // ---- model TVRAM: cell 3 and 4 are a kanji pair, the rest are ANK -------
    logic [7:0] scr_lo [0:127];
    logic [7:0] scr_hi [0:127];

    always_ff @(posedge clk) begin
        tv_char_lo <= scr_lo[tv_cell[6:0]];
        tv_char_hi <= scr_hi[tv_cell[6:0]];
    end

    // ---- model font: byte at address A is A's low eight bits ---------------
    // so a fetched byte says exactly which address it came from.
    logic [19:0] burst_addr;
    int          burst_n;
    logic [19:0] seen_addr [0:127];   // the address each column was fetched from
    int          fetches;

    initial begin
        f_busy = 1'b0; f_valid = 1'b0; fetches = 0;
    end

    always_ff @(posedge clk) begin
        f_valid <= 1'b0;
        if (f_req && !f_busy) begin
            burst_addr <= f_addr;
            // Only the FIRST fill's addresses: later fills reuse the indices
            // and would overwrite what the checks below are reading.
            if (fetches < COLS) seen_addr[fetches[6:0]] <= f_addr;
            fetches    <= fetches + 1;
            burst_n    <= 0;
            f_busy     <= 1'b1;
        end else if (f_busy) begin
            f_valid <= 1'b1;
            f_data  <= (burst_addr[7:0] + 8'(burst_n));
            burst_n <= burst_n + 1;
            if (burst_n == 15) f_busy <= 1'b0;
        end
    end

    int errors = 0;

    task automatic rd(input int c, input int l, output logic [7:0] d);
        rd_col = 7'(c); rd_line = 4'(l);
        @(posedge clk); @(posedge clk); @(posedge clk);
        d = rd_byte;
    endtask

    logic [7:0] got;

    initial begin
        $display("=== glyph row buffer ===");
        for (int i = 0; i < 128; i++) begin
            scr_lo[i] = 8'(8'h41 + i[7:0]);   // ANK
            scr_hi[i] = 8'h00;
        end
        // Columns 3 and 4 are one kanji: hiragana A, ku index 4 ten 0x22.
        scr_lo[3] = 8'h04; scr_hi[3] = 8'h22;
        scr_lo[4] = 8'hFF; scr_hi[4] = 8'hFF;   // deliberately not a character
        // Columns 5 and 6 are a gaiji pair: ku 0x56, index 0x21 -- the bytes
        // must come out of the gaiji RAM, not the SDRAM burst and not the
        // ANK BRAM.
        scr_lo[5] = 8'h56; scr_hi[5] = 8'h21;
        scr_lo[6] = 8'hFF; scr_hi[6] = 8'hFF;

        repeat (2) @(posedge clk);
        // Preload the gaiji RAM the way a guest's 0xA9 stores would: left
        // half 0xE0+line, right half 0xF0+line.
        for (int l = 0; l < 16; l++) begin
            gaiji_we = 1'b1;
            gaiji_waddr = {7'h21, 1'b0, 1'b0, 4'(l)}; gaiji_wdata = 8'hE0 + 8'(l);
            @(posedge clk);
            gaiji_waddr = {7'h21, 1'b0, 1'b1, 4'(l)}; gaiji_wdata = 8'hF0 + 8'(l);
            @(posedge clk);
        end
        gaiji_we = 1'b0;
        // Load the ANK BRAM the way the loader does: sixteen bits at a time,
        // low byte at the even offset.
        for (int w = 0; w < 2048; w++) begin
            font_wr_en   = 1'b1;
            font_wr_addr = 12'(w);
            font_wr_data = {ank_pat(8'((2*w+1) >> 4), 4'((2*w+1) & 15)),
                            ank_pat(8'((2*w)   >> 4), 4'((2*w)   & 15))};
            @(posedge clk);
        end
        font_wr_en = 1'b0;
        repeat (2) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // TWICE, with the same content. The renderer reads the bank NOT being
        // filled, so after a single fill it is looking at the other one -- which
        // is right, and is why the buffer is double-buffered. Two fills is the
        // steady state a running display is always in.
        fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
        wait (busy == 1'b0);
        repeat (4) @(posedge clk);
        fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
        wait (busy == 1'b0);
        repeat (4) @(posedge clk);

        // ANK cells must NOT reach for the SDRAM: only the two kanji halves
        // burst, so two fills of this screen make four fetches, not 320.
        $display("  fetches: %0d (want 4: two kanji halves x two fills)", fetches);
        if (fetches !== 4) begin $display("  FAIL fetch count"); errors++; end

        // First fill: col 3 is the kanji left half at 0x3C40, col 4 its RIGHT
        // half at 0x3C50 -- not whatever FF FF would decode to.
        $display("  kanji left addr %05h (want 03C40)", seen_addr[0]);
        if (seen_addr[0] !== 20'h03C40) begin $display("  FAIL kanji left"); errors++; end
        $display("  kanji right addr %05h (want 03C50, the right half)", seen_addr[1]);
        if (seen_addr[1] !== 20'h03C50) begin
            $display("  FAIL kanji right half not paired"); errors++;
        end

        // The ANK cells came out of the BRAM: every byte names its own
        // (code, line), so the wrong glyph, the wrong line order, or the
        // column-shifted-by-one failure mode all read as a wrong value.
        // Columns 0, 7, 14 ... cover the cells before, between and after the
        // kanji pair; 3 and 4 are the pair itself and must hold the BURST
        // model's bytes, 0x40+l and 0x50+l.
        for (int c = 0; c < COLS; c += 7) begin
            for (int l = 0; l < 16; l += 5) begin
                rd(c, l, got);
                if (got !== ank_pat(8'(8'h41 + c), 4'(l))) begin
                    $display("  FAIL col %0d line %0d: %02h want %02h",
                             c, l, got, ank_pat(8'(8'h41 + c), 4'(l)));
                    errors++;
                end
            end
        end
        for (int l = 0; l < 16; l += 5) begin
            rd(3, l, got);
            if (got !== 8'(8'h40 + l)) begin
                $display("  FAIL kanji col 3 line %0d: %02h want %02h", l, got, 8'(8'h40 + l));
                errors++;
            end
            rd(4, l, got);
            if (got !== 8'(8'h50 + l)) begin
                $display("  FAIL kanji col 4 line %0d: %02h want %02h", l, got, 8'(8'h50 + l));
                errors++;
            end
        end
        $display("  ANK bytes from BRAM, kanji bytes from the burst");

        // The gaiji pair read the RAM: col 5 the left half, col 6 the right.
        for (int l = 0; l < 16; l++) begin
            rd(5, l, got);
            if (got !== 8'hE0 + 8'(l)) begin
                $display("  FAIL gaiji col 5 line %0d: %02h want %02h",
                         l, got, 8'hE0 + 8'(l));
                errors++;
            end
            rd(6, l, got);
            if (got !== 8'hF0 + 8'(l)) begin
                $display("  FAIL gaiji col 6 line %0d: %02h want %02h",
                         l, got, 8'hF0 + 8'(l));
                errors++;
            end
        end
        $display("  gaiji cells drew their glyph from the user CG RAM");

        // The bank must flip on the ROW BOUNDARY, not on fill completion.
        //
        // The fill finishes early in a row -- eighty cells against sixteen
        // scanlines -- so flipping at completion would switch what the renderer
        // reads partway down the row it is still drawing. Flipping on the
        // boundary means the renderer always shows the row filled by the
        // PREVIOUS fill, for the whole of that row.
        //
        // So: fill with X, then Y, then Z, and the renderer should show X after
        // the Y fill and Y after the Z fill -- always one behind.
        begin
            logic [7:0] after_y, after_z;
            logic [7:0] want_x, want_y;

            // col 9's line-0 byte is the ANK pattern {code[3:0], 0}, so pick
            // contents whose code&0x0F differ or the check proves nothing.
            want_x = 8'((8'h4A & 8'h0F) << 4);      // 0x41 + 9
            want_y = 8'((8'h89 & 8'h0F) << 4);      // 0x80 + 9

            for (int i = 0; i < 128; i++) scr_lo[i] = 8'(8'h80 + i[7:0]);
            fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
            wait (busy == 1'b0); repeat (4) @(posedge clk);
            rd(9, 0, after_y);

            for (int i = 0; i < 128; i++) scr_lo[i] = 8'(8'hC3 + i[7:0]);
            fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
            wait (busy == 1'b0); repeat (4) @(posedge clk);
            rd(9, 0, after_z);

            $display("  after the Y fill %02h (want %02h, still X)", after_y, want_x);
            $display("  after the Z fill %02h (want %02h, now Y)",  after_z, want_y);
            if (after_y !== want_x) begin
                $display("  FAIL the renderer saw the row being filled"); errors++;
            end
            if (after_z !== want_y) begin
                $display("  FAIL the renderer did not advance a row"); errors++;
            end
        end

        // ---- the 8x8 bank (mode1 bit 3 clear, the WIDTH 40 font) -----------
        //
        // sel8 moves u_ank's reads to words 0x800-0xBFF, each glyph row
        // answering two cell lines (line[3:1]). Load it with the ank8_pat
        // pattern, re-fill so the buffer's active bank holds the new bytes,
        // then every line pair of a cell must read the same 8x8 row.
        for (int w = 0; w < 1024; w++) begin
            font_wr_en   = 1'b1;
            font_wr_addr = 12'h800 + 12'(w);
            font_wr_data = {ank8_pat(8'((2*w+1) >> 3), 3'((2*w+1) & 7)),
                            ank8_pat(8'((2*w)   >> 3), 3'((2*w)   & 7))};
            @(posedge clk);
        end
        font_wr_en = 1'b0;
        sel8 = 1'b1;
        repeat (2) @(posedge clk);
        fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
        wait (busy == 1'b0); repeat (4) @(posedge clk);
        fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
        wait (busy == 1'b0); repeat (4) @(posedge clk);
        for (int l = 0; l < 16; l++) begin
            rd(1, l, got);
            if (got !== ank8_pat(scr_lo[1], 3'(l >> 1))) begin
                $display("  FAIL 8x8 col 1 line %0d: %02h want %02h",
                         l, got, ank8_pat(scr_lo[1], 3'(l >> 1)));
                errors++;
            end
        end
        $display("  8x8 bank: every line pair reads row line>>1");
        sel8 = 1'b0;

        // ---- 40-column mode (mode1 bit 2): cells stride by two -------------
        //
        // np21w maketext40 walks edi += 2 per column: the BIOS writes a
        // character to every EVEN cell, odd cells are never consulted, and a
        // kanji pair spans two COLUMNS -- cells 2c and 2c+2 -- the second
        // cell's own contents counting for nothing. The fill must match that
        // or a kanji's right half lands in a slot the renderer never reads,
        // and the cell after the pair fills with whatever the second cell
        // decoded to on its own.
        begin
            int ff;
            ff = fetches;
            wide = 1'b1;
            for (int i = 0; i < 128; i++) begin
                scr_lo[i] = 8'(8'h41 + i[7:0]);
                scr_hi[i] = 8'h00;
            end
            // Columns 3 and 4 (cells 6 and 8) are one kanji; the second
            // cell deliberately carries ANOTHER kanji code, which a
            // sequential fill would happily decode as a fresh character.
            scr_lo[6] = 8'h04; scr_hi[6] = 8'h22;
            scr_lo[8] = 8'h09; scr_hi[8] = 8'h30;
            // Odd cells hold an inviting kanji code: reading one must not
            // happen and must not disturb the pairing.
            scr_lo[7] = 8'h04; scr_hi[7] = 8'h22;

            fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
            wait (busy == 1'b0); repeat (4) @(posedge clk);
            fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
            wait (busy == 1'b0); repeat (4) @(posedge clk);

            // Two kanji halves per fill, two fills: four fetches more.
            $display("  wide: fetches +%0d (want +4)", fetches - ff);
            if (fetches - ff !== 4) begin
                $display("  FAIL wide fetch count"); errors++;
            end

            // Slot = cell index. Column 3's kanji left half at slot 6,
            // the right half at slot 8 -- NOT cell 8's own kanji code.
            for (int l = 0; l < 16; l += 5) begin
                rd(6, l, got);
                if (got !== 8'(8'h40 + l)) begin
                    $display("  FAIL wide kanji left line %0d: %02h", l, got);
                    errors++;
                end
                rd(8, l, got);
                if (got !== 8'(8'h50 + l)) begin
                    $display("  FAIL wide kanji right line %0d: %02h", l, got);
                    errors++;
                end
                rd(10, l, got);
                if (got !== ank_pat(8'(8'h41 + 10), 4'(l))) begin
                    $display("  FAIL wide col 10 line %0d: %02h want %02h",
                             l, got, ank_pat(8'h4B, 4'(l)));
                    errors++;
                end
            end
            $display("  wide: kanji pair spans cells 2c and 2c+2");

            // 8x8 mode halves kanji too: burst bytes 0..7 each serve two
            // cell lines (np21w's `curx[x] |= multiple` on kanji cells).
            sel8 = 1'b1;
            fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
            wait (busy == 1'b0); repeat (4) @(posedge clk);
            fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
            wait (busy == 1'b0); repeat (4) @(posedge clk);
            for (int l = 0; l < 16; l++) begin
                rd(6, l, got);
                if (got !== 8'(8'h40 + (l >> 1))) begin
                    $display("  FAIL sel8 kanji left line %0d: %02h", l, got);
                    errors++;
                end
                rd(8, l, got);
                if (got !== 8'(8'h50 + (l >> 1))) begin
                    $display("  FAIL sel8 kanji right line %0d: %02h", l, got);
                    errors++;
                end
            end
            $display("  sel8: kanji lines read burst byte l>>1");
            sel8 = 1'b0;
            wide = 1'b0;
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("GLOBAL TIMEOUT (busy never cleared)"); $finish;
    end

endmodule

`default_nettype wire
