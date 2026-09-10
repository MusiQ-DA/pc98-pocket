//
// pc98_glyph_rowbuf -- a text row's worth of glyphs, fetched once per row.
//
// The font cannot live in BRAM: FONT.ROM is 282 KB against about 202 KB free on
// this device, so it is SDRAM-resident (GOAL.md R2) and the glyphs have to be
// read while the picture is being drawn.
//
// Fetching per SCANLINE would be the obvious thing and it is the wrong one.
// Each col's glyph byte for a given line sits at its own address, so eighty
// cells is eighty RANDOM accesses, and at the measured ~7 clocks each that is
// 560 of the 1730 clocks in a line -- a third of it, for a job that has to
// happen every line.
//
// Fetching per TEXT ROW costs the same bytes and almost no scheduling. A col's
// sixteen glyph bytes are CONTIGUOUS, so each col is one sixteen-byte burst,
// and the same eighty glyphs serve all sixteen scanlines of the row. Eighty
// bursts spread over sixteen line times is five cells per line, against a
// budget of 1730 clocks each.
//
// Double-buffered: the row being displayed is read while the next one is
// filled. 128 cells by 16 lines by two banks is 4 KB -- more than the eighty
// cells need, but it makes the addressing a concatenation instead of a
// multiplier.
//
// Kanji occupy two cells. The first carries the code and draws the left half;
// the second is its right half and its own contents are not a character. That
// pairing is tracked here, while filling, because the renderer sees only
// bytes.
//
// (`cell` is a Verilog-2001 config reserved word, hence `col`.)
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_glyph_rowbuf #(
    parameter int COLS = 80
) (
    input  wire        clk,
    input  wire        rst,

    // Start filling the row whose first col index is `row_base`. Assert for
    // one cycle; `busy` falls when the row is complete.
    input  wire        fill_start,
    input  wire [11:0] row_base,
    input  wire  [7:0] bitac,          // GDC mode mask; 00 means every col is ANK
    output logic       busy,

    // TVRAM video port, one cycle of latency.
    output logic [11:0] tv_cell,
    input  wire  [7:0]  tv_char_lo,
    input  wire  [7:0]  tv_char_hi,

    // Font fetch: request a sixteen-byte burst at f_addr, take f_data on each
    // f_valid. Sixteen beats, then the provider drops f_busy.
    //
    // KANJI cells only. An ANK cell's sixteen bytes come from the local
    // pc98_font_ank BRAM instead: the 4 KB 8x16 set the loader writes directly,
    // so plain text never depends on FONT.ROM reaching 0x400000 or on the
    // video SDRAM port being free. On the first hardware run that drew at all,
    // the SDRAM path read a region nobody had filled and every cell came out
    // solid -- attributes with no glyph. ANK out of BRAM is the fix and the
    // regression bench for it is tb_pc98_rowbuf.
    output logic        f_req,
    output logic [19:0] f_addr,
    input  wire         f_busy,
    input  wire         f_valid,
    input  wire  [7:0]  f_data,

    // ANK BRAM side, same clock as this FSM. Present (code, line); ank_row
    // answers the following cycle, one byte at a time -- two clocks per byte,
    // thirty-two per cell, against a budget of 1730 x 16 per row.
    output logic [7:0]  ank_code,
    output logic [3:0]  ank_line,
    input  wire  [7:0]  ank_row,

    // Renderer side: the row NOT being filled.
    //
    // On its OWN clock. The fill runs on the chipset clock, because that is
    // where the TVRAM and the SDRAM port are; the renderer runs on the dot
    // clock. The store is a dual-port BRAM, so the two sides need share nothing
    // but the bank bit -- and that only changes between rows, which is why the
    // buffer is double-buffered in the first place.
    input  wire         rd_clk,
    input  wire  [6:0]  rd_cell,
    input  wire  [3:0]  rd_line,
    output logic [7:0]  rd_byte,

    // Sticky: a kanji cell has been seen. The renderer cannot tell -- it is
    // handed bytes -- and this is where the pairing is decided, so it is here.
    output logic        kanji_seen
);

    (* ramstyle = "M10K" *) logic [7:0] store [0:4095];

    logic       bank;              // which half is being filled
    logic [6:0] col;
    logic [3:0] beat;
    logic       pair_second;       // this col is a kanji's right half
    logic [7:0] hold_lo, hold_hi;

    typedef enum logic [3:0] {
        S_IDLE, S_TV_REQ, S_TV_W1, S_TV_W2, S_FETCH, S_STREAM, S_NEXT,
        S_ANK, S_ANK_W
    } state_t;
    state_t state;

    wire        ga_is_kanji;
    wire [19:0] ga_addr;

    pc98_glyph_addr u_addr (
        .char_lo    (hold_lo),
        .char_hi    (hold_hi),
        .bitac      (bitac),
        .right_half (pair_second),
        .line       (4'd0),          // the burst starts at line 0 of the col
        .is_kanji   (ga_is_kanji),
        .addr       (ga_addr)
    );

    // Registered, so it infers a BRAM port rather than a wide mux. One cycle of
    // latency, which the renderer's cell pipeline already allows for.
    // The renderer reads the bank NOT being filled. bank flips on the row
    // boundary, so this is the row on screen for the whole of that row.
    always_ff @(posedge rd_clk)
        rd_byte <= store[{~bank, rd_cell, rd_line}];

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            bank        <= 1'b0;
            col        <= 7'd0;
            beat        <= 4'd0;
            busy        <= 1'b0;
            f_req       <= 1'b0;
            pair_second <= 1'b0;
            kanji_seen  <= 1'b0;
            tv_cell     <= 12'd0;
            ank_code    <= 8'h00;
            ank_line    <= 4'd0;
        end else begin
            f_req <= 1'b0;

            case (state)
            S_IDLE: if (fill_start) begin
                col         <= 7'd0;
                pair_second <= 1'b0;
                busy        <= 1'b1;
                // Flip HERE, at the start of a row, not when the fill finishes.
                //
                // The fill completes early in the row -- eighty cells against
                // sixteen scanlines -- so flipping on completion switches the
                // renderer to the NEXT row's glyphs partway down the row it is
                // still drawing. Flipping on the row boundary keeps the two
                // banks meaning "the row on screen" and "the row being fetched"
                // for the whole of every row.
                bank        <= ~bank;
                state       <= S_TV_REQ;
            end

            S_TV_REQ: begin
                tv_cell <= row_base + {5'd0, col};
                state   <= S_TV_W1;
            end

            // TWO cycles, not one. tv_cell is registered, so it only settles at
            // the end of S_TV_REQ; the TVRAM then registers its own output, so
            // the answer is not on tv_char_* until the cycle after that.
            // Sampling one cycle early takes the PREVIOUS column's character,
            // which shifts every glyph on the line by one -- and that looks
            // like a font or a TVRAM fault rather than a timing one.
            S_TV_W1: state <= S_TV_W2;

            S_TV_W2: begin
                hold_lo <= tv_char_lo;
                hold_hi <= tv_char_hi;
                state   <= S_FETCH;
            end

            // An ANK cell never touches the SDRAM port: the bytes come out of
            // the local BRAM, two clocks apiece. ga_is_kanji is the same
            // decision the address path makes, so the two paths cannot
            // disagree about what a cell is.
            S_FETCH: if (!f_busy) begin
                if (ga_is_kanji) begin
                    f_req  <= 1'b1;
                    f_addr <= ga_addr;
                    beat   <= 4'd0;
                    state  <= S_STREAM;
                end else begin
                    ank_code <= hold_lo;
                    ank_line <= 4'd0;
                    beat     <= 4'd0;
                    state    <= S_ANK;
                end
            end

            // One dead cycle. ank_code/ank_line were registered on the way in,
            // so the BRAM's answer for the current line only exists a cycle
            // after the request -- and the same is true of every line after
            // the first, so S_ANK_W comes back here between bytes.
            S_ANK: state <= S_ANK_W;

            // Store the byte the BRAM registered last cycle, then ask for the
            // next line. One byte every two clocks: request, wait, store.
            S_ANK_W: begin
                store[{bank, col, beat}] <= ank_row;
                if (beat == 4'd15) begin
                    state <= S_NEXT;
                end else begin
                    ank_line <= beat + 4'd1;
                    beat     <= beat + 4'd1;
                    state    <= S_ANK;
                end
            end

            S_STREAM: begin
                if (f_valid) begin
                    store[{bank, col, beat}] <= f_data;
                    beat <= beat + 4'd1;
                    if (beat == 4'd15) state <= S_NEXT;
                end
            end

            S_NEXT: begin
                if (ga_is_kanji) kanji_seen <= 1'b1;
                // A kanji's first col is followed by its right half, which
                // reuses the same code with right_half set. The col after that
                // starts fresh.
                if (ga_is_kanji && !pair_second) pair_second <= 1'b1;
                else                             pair_second <= 1'b0;

                if (col == 7'(COLS - 1)) begin
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end else begin
                    col  <= col + 7'd1;
                    // The right half does not re-read TVRAM: its own col holds
                    // no character, and reading it would replace the code the
                    // pair needs.
                    state <= (ga_is_kanji && !pair_second) ? S_FETCH : S_TV_REQ;
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
