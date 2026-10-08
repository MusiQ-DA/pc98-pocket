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
// np21w cgwindowset's full low/high table, folded onto our win[] (win[0:15]
// is the fetched left half, win[16:31] the right; the even offset serves
// `low`, the odd `high`):
//
//   code (this machine is EGC-class, so grcg.chip >= 2 always holds)
//     hi == 0 (ANK)      low = dummy  high = ANK glyph -- 0x80000+code*16 in
//                        np21w's internal space = file 0x0800+code*16, the
//                        8x16 set; +0x2000 when !(gdc.mode1 & 8), which is
//                        the 8x8 bank = file code*8, read contiguously
//                        (np21w's slot tail is generated chargraph filler,
//                        a storage artifact -- linear ROM is the honest read)
//     lo7 0x56/0x57      low = dummy  high = gaiji RAM, a5-selected half
//     lo7 0x09-0x0B      low = dummy  high = lr ? dummy : left half
//     lo7 0x0C-0x0F,58-5F low = dummy high = a5-selected half
//     else               low = left   high = right
//
// For a gaiji code, then:
//
//   * window ODD offsets  -> gaiji[{idx, ku0, right_sel, line}] (read+write)
//   * window even offsets -> 0x00 (np21w's dummy region)
//   * 0xA9 writes         -> gaiji[{idx, ku0, right_sel, a5_line}]
//   * 0xA9 reads          -> same, or win[] for ROM codes
//
// Window writes land ONLY on odd offsets of a gaiji code -- memtram_wr8's
// `writable` gate. Every other write is discarded on real hardware, so win[]
// holds font bytes exclusively and needs no guest-write path at all.
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
    // (select & ~memory_write_n). Writes reach storage only on odd offsets of
    // a gaiji code (np21w's `writable` arm); the rest are discarded.
    input  wire        mem_wr,
    input  wire        mem_rd,
    input  wire [11:0] wr_addr,
    input  wire  [7:0] wr_data,

    // Guest read of A4000-A4FFF; offset within the window.
    input  wire [11:0] rd_addr,
    output wire  [7:0] rd_data,

    // Port 0x00A9 read data -- the {code, lr, line} the guest last selected.
    output wire  [7:0] a9_data,

    // GDC mode1 bit 3, inverted: the ANK 8x8 bank select (np21w's
    // `!(gdc.mode1 & 8)` in cgwindowset; pc98_ank8 in Peripherals).
    input  wire        ank8,

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
    logic [7:0] win [0:31];

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

    // The ANK fetch address isn't glyph_addr's -- cgwindowset picks the bank:
    // 8x16 at file 0x0800+code*16 normally, the 8x8 set at file code*8 when
    // mode1 bit 3 is clear. In 8x8 mode the left slot takes the 8x8 bank (the
    // window serves it on odd offsets) while the right slot still carries the
    // 8x16 set, because cgrom_ia9 has no mode1 branch and always reads the
    // 8x16 region.
    wire [19:0] fetch_addr = ga_kanji ? ga_addr
                          : (ank8 & ~fetch_half) ? {9'd0, code[7:0], 3'b000}
                          : 20'h00800 + {4'd0, code[7:0], 4'b0000};

    // ---- gaiji side --------------------------------------------------------
    //
    // np21w `(code & 0x007e) == 0x0056`: the low byte masked to 7 bits is
    // 0x56/0x57 -- code[7] falls out of the mask, so 0xD6/0xD7 qualify too.
    // code[15:8] is the glyph index, code[7:0] the ku.
    wire        gaiji_sel = (code[6:0] & 7'h7E) == 7'h56;
    wire        hi_nz     = (code[15:8] != 8'h00);

    // cgwindowset's range decode, on `code & 0x007f` exactly as np21w masks
    // it. All of these arms live inside the `code & 0xff00` else-branch, so
    // they apply only to kanji-class codes.
    wire  [6:0] ku7       = code[6:0];
    wire        ku_09_0b  = hi_nz & (ku7 >= 7'h09) & (ku7 < 7'h0C);
    wire        ku_fold   = hi_nz & (((ku7 >= 7'h0C) & (ku7 < 7'h10)) |
                                     ((ku7 >= 7'h58) & (ku7 < 7'h60)));
    wire        win_gaiji_c = hi_nz & gaiji_sel;
    wire        win_normal  = hi_nz & ~gaiji_sel & ~ku_09_0b & ~ku_fold;

    // The RAM index compresses np21w's `(code & 0x7f7f) << 4 + lr + line`:
    // {idx, ku0, half, line}. Window access exposes the a5-SELECTED half on
    // the odd offsets (cgwindowset folds lr into `high`), so rd_addr[0] only
    // says whether this access reaches the RAM at all; the half bit is
    // right_sel either way.
    wire        win_gaiji = win_gaiji_c & (mem_wr | mem_rd);
    wire  [3:0] g_rline  = win_gaiji ? rd_addr[4:1] : a5_line[3:0];
    wire [12:0] g_raddr  = {code[14:8], code[0], right_sel, g_rline};

    // Writes register address and data with the enable: g_we commits a cycle
    // after the guest's bus cycle, and by then the bus lines are already
    // carrying the next access. Latching late -- off the live bus -- wrote
    // the byte to the next slot over with the previous port's data.
    logic [12:0] g_waddr;
    logic  [7:0] g_wdata_q;
    assign g_addr  = g_we ? g_waddr : g_raddr;
    assign g_wdata = g_wdata_q;

    // win[] carries THREE read consumers but the guest bus performs one
    // access at a time -- a window read or a port read, never both -- so a
    // single read port serves them all and mem_rd picks the index. The
    // read is registered, which is what lets the array finally honour its
    // M10K attribute: an asynchronous read cannot live in block RAM and
    // was costing the array's 256 cells plus a 32:1 mux per consumer in
    // ALMs. One cycle is invisible here -- every consumer (the
    // data_bus_out capture, the testbench's two-clock sample) reads at
    // least a clock after the index, the same rhythm the gaiji RAM's
    // registered output already sets for a9_data.
    //
    // The index's half bit is not always rd_addr[0]: cgwindowset folds the
    // a5 selection into `high` for the fold ranges (0x0C-0x0F, 0x58-0x5F),
    // and the 09-0B arm's odd side is the left half at most.
    wire       rd_right   = rd_addr[0] & (win_normal | (ku_fold & right_sel));
    // cgrom_ia9: the 09-0B range is tested on the FULL low byte (0x89-0x8B
    // don't qualify -- the window masks with 0x7f instead). hi==0 codes take
    // the ANK arm; in ank8 mode the port still reads the 8x16 set, which the
    // fetch parked on win[16:31].
    wire       lo8_09_0b  = (code[7:0] >= 8'h09) & (code[7:0] < 8'h0C);
    wire       a9_right   = hi_nz ? (~lo8_09_0b & right_sel) : ank8;
    wire [4:0] win_ridx   = mem_rd ? {rd_right, rd_addr[4:1]}
                                   : {a9_right, a5_line[3:0]};
    logic [7:0] win_rdata;
    always_ff @(posedge clk) win_rdata <= win[win_ridx];

    // Window reads, np21w's low/high table: even offsets serve `low`, which
    // is the dummy region -- 0x00 -- for every code but a normal kanji cell.
    assign rd_data = ~rd_addr[0]      ? (win_normal ? win_rdata : 8'h00)
                   : win_gaiji_c      ? g_rdata
                   : ku_09_0b & right_sel ? 8'h00
                                      : win_rdata;

    // Port 0xA9 reads (cgrom_ia9): the 09-0B arm first -- full-byte range, so
    // it outranks the code-class check and also swallows hi==0 codes
    // 0x0009-0x000B (np21w reads fontrom[(code&0x7f7f)<<4+line] there, an
    // unmapped internal offset; win[left] standing in is closer than a zero
    // and the corner is unreachable in practice). Gaiji-class codes hit the
    // RAM; other kanji read the a5-selected half; ANK reads the 8x16 set
    // while line bit 4 stays clear.
    assign a9_data = lo8_09_0b ? (right_sel ? 8'h00 : win_rdata)
                   : ~hi_nz    ? (a5_line[4] ? 8'h00 : win_rdata)
                   : gaiji_sel ? g_rdata
                               : win_rdata;

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
                    // write is a no-op -- but port 0xA9 and the fold ranges
                    // need both fields, so they are latched here. It must not
                    // disturb stored gaiji data: the ITF's test (itf.rom
                    // F8743-F87D5) writes a half's pattern, flips the selector
                    // with a third OUT A5, then reads back -- a selector write
                    // that re-armed anything would report KANJI CG RAM ERROR.
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
                f_addr <= fetch_addr;
                beat   <= 4'd0;
                state  <= S_STREAM;
            end

            S_STREAM: if (f_valid) begin
                win[{fetch_half, beat}] <= f_data;
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

            // memtram_wr8's `writable` arm: the only window write that lands
            // is an odd offset on a gaiji code, into the a5-selected half.
            // Everything else is discarded -- the ROM codes' window bytes
            // have no RAM behind them.
            if (mem_wr & win_gaiji_c & wr_addr[0]) begin
                g_we      <= 1'b1;
                g_waddr   <= {code[14:8], code[0], right_sel,
                              wr_addr[4:1]};
                g_wdata_q <= wr_data;
            end
        end
    end

    wire _unused = &{1'b0, rd_addr[11:5], wr_addr[11:5], 1'b0};

endmodule

`default_nettype wire
