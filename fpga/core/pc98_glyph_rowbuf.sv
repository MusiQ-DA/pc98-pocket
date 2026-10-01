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

    // Start filling the row whose first cell index is `row_base`. Assert for
    // one cycle; `busy` falls when the row is complete.
    //
    // row_base lives in the LOW12 cell space np21w's maketext walks: the
    // GDC's scroll mapping is APPLIED BY WHOEVER COMPUTES IT -- today the
    // parent drives row*80; the SAD/PITCH-aware form is LOW12(SAD +
    // row*PITCH) as pc98_text_rowbase produces. The value is latched into
    // base_q at fill_start the way pc98_gvram_display latches its own SAD
    // walk at each line edge, so a register rewrite mid-fill cannot shear
    // the row being fetched.
    input  wire        fill_start,
    input  wire [11:0] row_base,
    input  wire  [7:0] bitac,          // GDC mode mask; 00 means every col is ANK
    input  wire        wide,           // mode1 bit 2: 40 columns
    input  wire        sel8,           // mode1 bit 3 clear: 8x8 halves lines
    output logic       busy,

    // TVRAM video port, one cycle of latency.
    output logic [11:0] tv_cell,
    input  wire  [7:0]  tv_char_lo,
    input  wire  [7:0]  tv_char_hi,

    // Font fetch: request a sixteen-byte burst at f_addr, take f_data on each
    // f_valid. Sixteen beats, then the provider drops f_busy.
    //
    // KANJI cells only. An ANK cell's sixteen bytes come from the local
    // pc98_font_ank BRAM instead: the 6 KB ANK set the loader writes directly,
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

    // Gaiji RAM side (pc98_gaiji_ram port B), same clock. Cells whose ku is
    // 0x56/0x57 are user-defined RAM, not FONT.ROM -- np21w draws them out of
    // the same array its cgrom_oa9 writes, so the read here must reach the
    // store the guest's 0xA9 and window writes fill. Two clocks per byte,
    // the same rhythm as the ANK path.
    output logic [12:0] gaiji_addr,
    input  wire  [7:0]  gaiji_data,

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
    logic [11:0] base_q;           // row_base, held for the whole fill
    logic [6:0] col;
    logic [3:0] beat;
    logic       pair_second;       // this col is a kanji's right half
    logic [7:0] hold_lo, hold_hi;
    logic [7:0] hold8 [0:7];

    // The column step: 40-column mode strides the cell space by two
    // (np21w maketext40's `edi = LOW12(edi + 2)`) -- odd cells are never
    // read, and a kanji's right half lands at the NEXT column's slot,
    // col+2, not col+1.
    wire [6:0] col_step = wide ? 7'd2 : 7'd1;

    typedef enum logic [3:0] {
        S_IDLE, S_TV_REQ, S_TV_W1, S_TV_W2, S_FETCH, S_STREAM, S_EXPAND,
        S_EXPAND_W, S_NEXT, S_ANK, S_ANK_W, S_GAIJI, S_GAIJI_W
    } state_t;
    state_t state;

    wire        ga_is_kanji;
    wire [19:0] ga_addr;

    // Gaiji: a kanji-class cell whose ku is 0x56/0x57 -- the same test
    // np21w's cgrom_oa9 applies, (code & 0x007e) == 0x0056. char_hi is the
    // glyph index the guest uploaded under port 0xA1.
    wire        ga_is_gaiji = ga_is_kanji & ((hold_lo[6:0] & 7'h7E) == 7'h56);
    logic [3:0] gaiji_line;

    pc98_glyph_addr u_addr (
        .char_lo    (hold_lo),
        .char_hi    (hold_hi),
        .bitac      (bitac),
        .right_half (pair_second),
        .line       (4'd0),          // the burst starts at line 0 of the col
        .is_kanji   (ga_is_kanji),
        .addr       (ga_addr)
    );

    // {index, ku0, half, line} -- pc98_gaiji_ram's port B. hold_* still carry
    // the cell's code during the second column's fetch, so pair_second is the
    // right-half select for a gaiji pair exactly as it is for the font burst.
    assign gaiji_addr = {hold_hi[6:0], hold_lo[0], pair_second, gaiji_line};

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
            gaiji_line  <= 4'd0;
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
                //
                // It is still one cell late for the renderer. pc98_text_render
                // fetches cell 0 of a line during the PREVIOUS line's blanking
                // -- sampled at hcount 843, five dot clocks before the line it
                // belongs to -- so at a text row boundary that read lands
                // before this flip and takes cell 0 line 0 out of the bank that
                // still holds the row above. One scanline of one cell per row,
                // and in FONT.ROM's 8x16 ANK set (0x0800-0x17FF) line 0 is
                // blank for every printable ASCII code but 0x60, so on text it
                // is invisible; the box-drawing codes 0x01-0x1F do carry ink
                // there. Flipping earlier needs the DISPLAY row boundary, and
                // fill_start is the only thing this side is handed.
                bank        <= ~bank;
                base_q      <= row_base;
                state       <= S_TV_REQ;
            end

            S_TV_REQ: begin
                // The 12-bit sum is LOW12(edi) itself: a line whose base plus
                // col runs past cell 4095 wraps onto the TVRAM ring the way
                // np21w's `edi = LOW12(edi + 1)` does.
                tv_cell <= base_q + {5'd0, col};
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
            // the local BRAM, two clocks apiece. Gaiji cells take the same
            // kind of path against pc98_gaiji_ram -- the SDRAM font region
            // has nothing where the guest-defined glyphs live. ga_is_kanji
            // is the same decision the address path makes, so the three
            // paths cannot disagree about what a cell is.
            S_FETCH: if (!f_busy) begin
                if (ga_is_gaiji) begin
                    gaiji_line <= 4'd0;
                    beat       <= 4'd0;
                    state      <= S_GAIJI;
                end else if (ga_is_kanji) begin
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

            // The gaiji cell's sixteen bytes, the same two-clock rhythm as
            // ANK -- the RAM's b_rdata is registered, so the byte asked for
            // in S_GAIJI lands in S_GAIJI_W. The address is the compressed
            // np21w fontrom offset: {index, ku0, half, line}, the half being
            // pair_second for the pair's second column.
            S_GAIJI: state <= S_GAIJI_W;

            S_GAIJI_W: begin
                gaiji_line <= beat + 4'd1;
                beat       <= beat + 4'd1;
                if (sel8) begin
                    // 8x8 halves gaiji the way it halves kanji: only lines
                    // 0-7 are ink, each drawn on two cell lines.
                    if (beat[3] == 1'b0) hold8[beat[2:0]] <= gaiji_data;
                    if (beat == 4'd15) begin
                        beat  <= 4'd0;
                        state <= S_EXPAND;
                    end else begin
                        state <= S_GAIJI;
                    end
                end else begin
                    store[{bank, col, beat}] <= gaiji_data;
                    if (beat == 4'd15) begin
                        state <= S_NEXT;
                    end else begin
                        state <= S_GAIJI;
                    end
                end
            end

            S_STREAM: begin
                if (f_valid) begin
                    if (sel8) begin
                        // 8x8 mode halves every glyph vertically, kanji
                        // included (maketext sets `curx[x] |= multiple` on
                        // kanji cells too, and its draw does fntline>>1):
                        // only the burst's first eight bytes are ink. The
                        // stream cannot pause and the store is one port,
                        // so the bytes land in hold8 first and S_EXPAND
                        // writes each to two cell lines afterwards.
                        if (beat[3] == 1'b0) hold8[beat[2:0]] <= f_data;
                        beat <= beat + 4'd1;
                        if (beat == 4'd15) begin
                            beat  <= 4'd0;
                            state <= S_EXPAND;
                        end
                    end else begin
                        store[{bank, col, beat}] <= f_data;
                        beat <= beat + 4'd1;
                        if (beat == 4'd15) state <= S_NEXT;
                    end
                end
            end

            // Two writes per captured byte, one port: even slot, odd slot.
            S_EXPAND: begin
                store[{bank, col, {beat[2:0], 1'b0}}] <= hold8[beat[2:0]];
                state <= S_EXPAND_W;
            end

            S_EXPAND_W: begin
                store[{bank, col, {beat[2:0], 1'b1}}] <= hold8[beat[2:0]];
                if (beat[2:0] == 3'd7) begin
                    beat  <= 4'd0;
                    state <= S_NEXT;
                end else begin
                    beat  <= beat + 4'd1;
                    state <= S_EXPAND;
                end
            end

            S_NEXT: begin
                if (ga_is_kanji) kanji_seen <= 1'b1;
                // A kanji's first col is followed by its right half, which
                // reuses the same code with right_half set. The col after that
                // starts fresh.
                if (ga_is_kanji && !pair_second) pair_second <= 1'b1;
                else                             pair_second <= 1'b0;

                if ({1'b0, col} + {1'b0, col_step} >= 8'(COLS)) begin
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end else begin
                    col  <= col + col_step;
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
