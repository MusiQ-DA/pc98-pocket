//
// pc98_cgwindow -- the character generator window at A4000-A4FFF, plus the
// CG data port 0x00A9.
//
// PC-98 lets software read glyphs itself, which is not decoration: the BIOS
// uses it, and a read that never answers hangs the guest rather than looking
// wrong. np21w io/cgrom.c and mem/memtram.c between them give the whole thing.
//
// Ports, exactly as np21w decodes them:
//
//   0x00A1  code[15:8]      cgrom_oa1: code = (dat << 8) | (code & 0xff)
//   0x00A3  code[7:0]       cgrom_oa3: code = (code & 0xff00) | dat
//   0x00A5  line and side   cgrom_oa5: line = dat & 0x1f,
//                                      lr   = ((~dat) & 0x20) << 6
//   0x00A9  pattern data    cgrom_oa9/cgrom_ia9: writes land only when
//                           (code & 0x007e) == 0x0056 -- the gaiji region --
//                           at fontrom[(code & 0x7f7f) << 4 + lr + line];
//                           reads return the same offset for any code with a
//                           nonzero high byte, and the ANK set for hi == 0.
//
// so bit 5 CLEAR on 0xA5 selects the right half. The code is encoded the way a
// TVRAM cell is -- low byte the ku index, high byte the raw ten -- so the
// address arithmetic is pc98_glyph_addr's, unchanged.
//
// The window itself, from memtram_rd8:
//
//   else if (address < 0xa5000) {
//       if (address & 1) return fontrom[cgwindow.high + ((address >> 1) & 0x0f)];
//       else             return fontrom[cgwindow.low  + ((address >> 1) & 0x0f)];
//   }
//
// -- so the address supplies the line, bit 0 picks the half, and 32 bytes are
// mirrored across the 4 KB.
//
// Prefetched rather than fetched per read. Thirty-two bytes are two bursts and
// the guest changes the code far less often than it reads the window, so this
// costs one fetch per character instead of one per byte, and a read never has
// to wait on SDRAM.
//
// GAIJI -- ku 0x56/0x57 -- are user RAM, not ROM. np21w's cgwindowset leaves
// `low` pointing at a dummy region for those codes and sets `high` to the
// a5-selected half of the glyph, so the window's ODD addresses reach the RAM
// while even ones see scratch; the port path (0xA9) reads/writes
// {code, lr, line} directly. Here the backing store is pc98_gaiji_ram, shared
// with the text row buffer, so a glyph the guest uploads is both read back
// and drawn -- which is what software like SuperDepth's DEPTH.FNT loader
// needs: it stores glyphs through 0xA9 and then displays them on the text
// layer.
//
// For a gaiji code, then:
//
//   * window ODD offsets  -> gaiji[{idx, ku0, right_sel, line}] (read+write)
//   * window even offsets -> the prefetch window, as a harmless dummy stand-in
//   * 0xA9 writes         -> gaiji[{idx, ku0, right_sel, a5_line}]
//   * 0xA9 reads          -> same, or win[] for ROM codes
//
// NOT YET: cgwindowset's other special cases -- the 0x09-0x0C and 0x58-0x60
// ranges and the "grcg.chip >= 2" gate. None of them is reachable until a
// guest asks for those characters. Left explicit rather than approximated.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_cgwindow (
    input  wire        clk,
    input  wire        rst,

    // Port writes, already decoded and qualified.
    input  wire        io_wr,          // one cycle
    input  wire [15:0] io_port,
    input  wire  [7:0] io_data,

    // Guest access to A4000-A4FFF, same qualification shape as the text VRAM's
    // (select & ~memory_write_n). The window is RAM on machines this BIOS
    // family knows: the ITF's own test writes a pattern through the window and
    // reads it back, and user-defined characters are loaded the same way. A
    // write lands in the same slot a read at that address would come from, so
    // what the guest wrote is what the guest reads.
    input  wire        mem_wr,
    input  wire        mem_rd,
    input  wire [11:0] wr_addr,
    input  wire  [7:0] wr_data,

    // Guest read of A4000-A4FFF; offset within the window.
    input  wire [11:0] rd_addr,
    output wire  [7:0] rd_data,

    // Port 0x00A9 read data -- the {code, lr, line} the guest last selected.
    output wire  [7:0] a9_data,

    // Gaiji RAM port A (the guest side); the renderer owns port B.
    output logic        g_we,
    output wire  [12:0] g_addr,
    output wire   [7:0] g_wdata,
    input  wire   [7:0] g_rdata,

    // Font fetch, same shape as the row buffer's.
    output logic        f_req,
    output logic [19:0] f_addr,
    input  wire         f_busy,
    input  wire         f_valid,
    input  wire  [7:0]  f_data,

    output logic        busy
);

    logic [15:0] code;
    logic        right_sel;     // the half port 0x00A5 last selected
    logic  [4:0] a5_line;       // and the line it named

    // Two halves of sixteen lines.
    (* ramstyle = "M10K" *) logic [7:0] win [0:31];

    // Which slots the guest has written since the last code change. The code
    // write kicks off a refill from the font store, and the CPU can reach its
    // first stosb before that burst lands -- without the mask the refill would
    // stamp ROM bytes over the guest's pattern and the write would look like
    // it never happened.
    logic [31:0] dirty;

    wire        ga_kanji;
    wire [19:0] ga_addr;
    logic       fetch_half;     // which half is being fetched

    pc98_glyph_addr u_addr (
        .char_lo    (code[7:0]),
        .char_hi    (code[15:8]),
        // NOT the GDC mode mask. np21w's cgwindowset decides this window by the
        // code alone -- `!(cr->code & 0xff00)` takes the ANK path whatever
        // mode1 bit 5 says -- so 8'hFF (high byte decides) is the faithful
        // wiring here, and the BIOS's OUT 68h,0Bh around window access is
        // about the rest of the machine, not the window. The ROW BUFFER is
        // the consumer that has to honour bitac (Peripherals.sv).
        .bitac      (8'hFF),
        .right_half (fetch_half),
        .line       (4'd0),
        .is_kanji   (ga_kanji),
        .addr       (ga_addr)
    );

    // ---- gaiji side --------------------------------------------------------
    //
    // np21w `(code & 0x007e) == 0x0056`: the low byte masked to 7 bits is
    // 0x56/0x57. code[15:8] is the glyph index, code[7:0] the ku.
    wire gaiji_sel = (code[7:0] & 8'h7E) == 8'h56;

    // The RAM index compresses np21w's `(code & 0x7f7f) << 4 + lr + line`:
    // {idx, ku0, half, line}. Window access exposes the a5-SELECTED half on
    // the odd offsets (cgwindowset folds lr into `high`), so rd_addr[0] only
    // says whether this access reaches the RAM at all; the half bit is
    // right_sel either way.
    wire        win_gaiji = gaiji_sel & (mem_wr | mem_rd);
    wire [12:0] g_raddr  = win_gaiji ? {code[14:8], code[0], right_sel,
                                        rd_addr[4:1]}
                                     : {code[14:8], code[0], right_sel,
                                        a5_line[3:0]};

    // Writes register address and data with the enable: g_we commits a cycle
    // after the guest's bus cycle, and by then the bus lines are already
    // carrying the next access. Latching late -- off the live bus -- wrote
    // the byte to the next slot over with the previous port's data.
    logic [12:0] g_waddr;
    logic  [7:0] g_wdata_q;
    assign g_addr  = g_we ? g_waddr : g_raddr;
    assign g_wdata = g_wdata_q;

    // Window reads of a gaiji code: odd offsets answer from the RAM, even
    // from the prefetch window (np21w's `low` dummy region stands there).
    assign rd_data = (gaiji_sel & rd_addr[0]) ? g_rdata
                                              : win[{rd_addr[0], rd_addr[4:1]}];

    // Port 0xA9 reads: gaiji codes hit the RAM; other kanji-class codes read
    // the prefetched half/line (np21w returns fontrom at the same offsets);
    // ANK codes come from the window's left half while line bit 4 stays clear,
    // the `!(cr->line & 0x10)` gate in cgrom_ia9.
    assign a9_data = gaiji_sel            ? g_rdata
                   : (code[15:8] != 8'h00) ? win[{right_sel, a5_line[3:0]}]
                   : a5_line[4]            ? 8'h00
                                           : win[{1'b0, a5_line[3:0]}];

    typedef enum logic [1:0] { S_IDLE, S_FETCH, S_STREAM, S_NEXT } state_t;
    state_t state;
    logic [3:0] beat;
    logic       reload;

    always_ff @(posedge clk) begin
        if (rst) begin
            code       <= 16'h0000;
            right_sel  <= 1'b0;
            a5_line    <= 5'd0;
            state      <= S_IDLE;
            f_req      <= 1'b0;
            busy       <= 1'b0;
            reload     <= 1'b0;
            fetch_half <= 1'b0;
            dirty      <= 32'h0;
            g_we       <= 1'b0;
        end else begin
            f_req <= 1'b0;
            g_we  <= 1'b0;

            if (io_wr) begin
                case (io_port)
                    16'h00A1: begin code[15:8] <= io_data; reload <= 1'b1; end
                    16'h00A3: begin code[7:0]  <= io_data; reload <= 1'b1; end
                    // 0x00A5 carries the line and the half. The window holds
                    // both halves' sixteen lines at once, indexed out of the
                    // address (see rd_data above), so for window access the
                    // write is a no-op -- but port 0xA9 needs both fields, so
                    // they are latched here.
                    //
                    // It must not touch `dirty`, and that is the whole KANJI
                    // CG RAM ERROR story. The ITF's test is itf.rom
                    // F8743-F87D5:
                    //
                    //   OUT A1/A3          ku 0x56, the gaiji region
                    //   OUT A5,00 + 16 x STOSB      write the pattern
                    //   OUT A5,20 + 16 x STOSB      write it again
                    //   OUT A5,00 + 16 x SCASB      read it back
                    //   OUT A5,20 + 16 x SCASB      and again
                    //   JNZ -> MOV SI,17DEh, "KANJI CG RAM ERROR"
                    //
                    // The third OUT A5 sits between the writing and the
                    // reading. Clearing `dirty` there re-armed the refill over
                    // all thirty-two slots, and at 4.77 MHz the burst lands
                    // long before the first SCASB's bus cycle, so every one of
                    // the 128 read-backs returned a font byte (measured:
                    // 128/128 in tb_pc98_cgwindow before this change, 0/128
                    // after). The test cannot pass while a selector write
                    // discards what the guest stored.
                    16'h00A5: begin right_sel <= ~io_data[5];
                                    a5_line   <= io_data[4:0]; end
                    // cgrom_oa9: writes land only in the gaiji RAM. The M10K
                    // register stage means the store commits next clock, which
                    // is long before a 4.77 MHz guest's next bus cycle.
                    16'h00A9: if (gaiji_sel) begin
                        g_we      <= 1'b1;
                        g_waddr   <= {code[14:8], code[0], right_sel,
                                      a5_line[3:0]};
                        g_wdata_q <= io_data;
                    end
                    default: ;
                endcase
                // A code change hands the window back to the font store -- but
                // on the WRITE, not while `reload` is held: a refill can be in
                // flight when the guest starts storing, and clearing on the
                // level here would wipe the marks those stores leave and let
                // the refill stamp over them.
                if (io_port == 16'h00A1 || io_port == 16'h00A3)
                    dirty <= 32'h0;
            end

            case (state)
            S_IDLE: if (reload) begin
                reload     <= 1'b0;
                fetch_half <= 1'b0;
                busy       <= 1'b1;
                state      <= S_FETCH;
            end

            S_FETCH: if (!f_busy) begin
                f_req  <= 1'b1;
                f_addr <= ga_addr;
                beat   <= 4'd0;
                state  <= S_STREAM;
            end

            S_STREAM: if (f_valid) begin
                if (!dirty[{fetch_half, beat}]) win[{fetch_half, beat}] <= f_data;
                beat <= beat + 4'd1;
                if (beat == 4'd15) state <= S_NEXT;
            end

            S_NEXT: begin
                if (!fetch_half) begin
                    fetch_half <= 1'b1;
                    state      <= S_FETCH;
                end else begin
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
            end

            default: state <= S_IDLE;
            endcase

            // LAST, so the guest wins a same-cycle collision with a refill
            // beat. `dirty` is read a cycle too late to cover the beat that
            // coincides with the store: the S_STREAM branch above sees the old
            // zero and would assign f_data after this block if this block came
            // first. One cycle in thirty-two per glyph is not a risk worth
            // leaving in a path whose failure mode is a wrong character.
            if (mem_wr) begin
                if (gaiji_sel & wr_addr[0]) begin
                    // Odd offsets on a gaiji code reach the RAM -- the
                    // a5-selected half, the window offset's line.
                    g_we      <= 1'b1;
                    g_waddr   <= {code[14:8], code[0], right_sel,
                                  wr_addr[4:1]};
                    g_wdata_q <= wr_data;
                end else begin
                    win[{wr_addr[0], wr_addr[4:1]}] <= wr_data;
                    dirty[{wr_addr[0], wr_addr[4:1]}] <= 1'b1;
                end
            end
        end
    end

    wire _unused = &{1'b0, ga_kanji, rd_addr[11:5], wr_addr[11:5], 1'b0};

endmodule

`default_nettype wire
