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

    logic [6:0] rd_col = 7'd0;
    logic [3:0] rd_line = 4'd0;
    wire  [7:0] rd_byte;
    wire        kanji_seen;

    pc98_glyph_rowbuf #(.COLS(COLS)) dut (
        .clk(clk), .rst(rst),
        .fill_start(fill_start), .row_base(row_base), .bitac(bitac), .busy(busy),
        .tv_cell(tv_cell), .tv_char_lo(tv_char_lo), .tv_char_hi(tv_char_hi),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data),
        .rd_clk(clk), .rd_cell(rd_col), .rd_line(rd_line), .rd_byte(rd_byte), .kanji_seen(kanji_seen)
    );

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

        repeat (4) @(posedge clk);
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

        $display("  fetches: %0d (want %0d, two fills)", fetches, 2*COLS);
        if (fetches !== 2*COLS) begin $display("  FAIL fetch count"); errors++; end

        // Column 0: ANK 0x41 -> 0x0800 + 0x41*16 = 0x0C10.
        $display("  col 0 addr %05h (want 00C10)", seen_addr[0]);
        if (seen_addr[0] !== 20'h00C10) begin $display("  FAIL ANK addr"); errors++; end

        // Column 3: kanji left half at 0x3C40. Column 4: its RIGHT half, 0x3C50
        // -- not whatever FF FF would decode to.
        $display("  col 3 addr %05h (want 03C40)", seen_addr[3]);
        if (seen_addr[3] !== 20'h03C40) begin $display("  FAIL kanji left"); errors++; end
        $display("  col 4 addr %05h (want 03C50, the right half)", seen_addr[4]);
        if (seen_addr[4] !== 20'h03C50) begin
            $display("  FAIL kanji right half not paired"); errors++;
        end

        // Column 5 must be back to ANK, from its own code.
        $display("  col 5 addr %05h (want %05h)", seen_addr[5], 20'h0800 + 20'((8'h41 + 5) * 16));
        if (seen_addr[5] !== 20'h0800 + 20'((8'h41 + 5) * 16)) begin
            $display("  FAIL cell after a kanji pair"); errors++;
        end

        // And the bytes landed in the right places: the model font returns the
        // address's low byte plus the beat.
        for (int c = 0; c < COLS; c += 7) begin
            for (int l = 0; l < 16; l += 5) begin
                rd(c, l, got);
                if (got !== 8'(seen_addr[c][7:0] + 8'(l))) begin
                    $display("  FAIL col %0d line %0d: %02h want %02h",
                             c, l, got, 8'(seen_addr[c][7:0] + 8'(l)));
                    errors++;
                end
            end
        end
        $display("  buffer contents match the fetched addresses");

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

            // col 9's line-0 byte is the low byte of 0x0800 + code*16, so pick
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
