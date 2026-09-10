//
// pc98_cgwindow -- the character generator window at A4000-A4FFF.
//
// PC-98 lets software read glyphs itself, which is not decoration: the BIOS
// uses it, and a read that never answers hangs the guest rather than looking
// wrong. np2 io/cgrom.c and mem/memtram.c between them give the whole thing.
//
// Ports, exactly as np2 decodes them:
//
//   0x00A1  code[15:8]      cgrom_oa1: code = (dat << 8) | (code & 0xff)
//   0x00A3  code[7:0]       cgrom_oa3: code = (code & 0xff00) | dat
//   0x00A5  line and side   cgrom_oa5: line = dat & 0x1f,
//                                      lr   = ((~dat) & 0x20) << 6
//
// so bit 5 CLEAR selects the right half. The code is encoded the way a TVRAM
// cell is -- low byte the ku index, high byte the raw ten -- so the address
// arithmetic is pc98_glyph_addr's, unchanged.
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
// NOT YET: cgwindowset's special cases -- gaiji at ku 0x56/0x57, the 0x09-0x0C
// and 0x58-0x60 ranges, and the "grcg.chip >= 2" gate. Those change which
// halves map where for particular ku, and none of them is reachable until a
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

    // Guest writes to A4000-A4FFF, same qualification shape as the text VRAM's
    // (select & ~memory_write_n). The window is RAM on machines this BIOS
    // family knows: the ITF's own test writes a pattern through the window and
    // reads it back, and user-defined characters are loaded the same way. A
    // write lands in the same slot a read at that address would come from, so
    // what the guest wrote is what the guest reads.
    input  wire        mem_wr,
    input  wire [11:0] wr_addr,
    input  wire  [7:0] wr_data,

    // Guest read of A4000-A4FFF; offset within the window.
    input  wire [11:0] rd_addr,
    output wire  [7:0] rd_data,

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
        .bitac      (8'hFF),
        .right_half (fetch_half),
        .line       (4'd0),
        .is_kanji   (ga_kanji),
        .addr       (ga_addr)
    );

    // The address supplies the line and bit 0 picks the half, so the window
    // repeats every 32 bytes across the 4 KB.
    assign rd_data = win[{rd_addr[0], rd_addr[4:1]}];

    typedef enum logic [1:0] { S_IDLE, S_FETCH, S_STREAM, S_NEXT } state_t;
    state_t state;
    logic [3:0] beat;
    logic       reload;

    always_ff @(posedge clk) begin
        if (rst) begin
            code       <= 16'h0000;
            right_sel  <= 1'b0;
            state      <= S_IDLE;
            f_req      <= 1'b0;
            busy       <= 1'b0;
            reload     <= 1'b0;
            fetch_half <= 1'b0;
            dirty      <= 32'h0;
        end else begin
            f_req <= 1'b0;

            if (mem_wr) begin
                win[{wr_addr[0], wr_addr[4:1]}] <= wr_data;
                dirty[{wr_addr[0], wr_addr[4:1]}] <= 1'b1;
            end

            if (io_wr) begin
                case (io_port)
                    16'h00A1: begin code[15:8] <= io_data; reload <= 1'b1; end
                    16'h00A3: begin code[7:0]  <= io_data; reload <= 1'b1; end
                    16'h00A5: begin
                        // bit 5 clear selects the right half
                        right_sel <= ~io_data[5];
                        reload    <= 1'b1;
                    end
                    default: ;
                endcase
                // A code change hands the window back to the font store -- but
                // on the WRITE, not while `reload` is held: a refill can be in
                // flight when the guest starts storing, and clearing on the
                // level here would wipe the marks those stores leave and let
                // the refill stamp over them.
                if (io_port == 16'h00A1 || io_port == 16'h00A3
                 || io_port == 16'h00A5)
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
        end
    end

    wire _unused = &{1'b0, ga_kanji, right_sel, rd_addr[11:5], 1'b0};

endmodule

`default_nettype wire
