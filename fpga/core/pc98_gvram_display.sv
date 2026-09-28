//
// pc98_gvram_display -- the graphics plane's display fetch.
//
// The text plane reaches the screen through TVRAM and the glyph row buffer;
// the graphics plane is 128 KB of guest SDRAM (four planes, B/R/G/E, 80 bytes
// per line each) and nothing read it. This module is the graphics half of the
// picture: four line buffers in BRAM hold a ring of display lines, the fill
// runs LOOKAHEAD lines ahead over the font's SDRAM port, and each line's own
// number selects the bank it is shifted out of at the dot clock.
//
// ADDRESSING. RAM.sv stores one guest byte per 16-bit word, so a line of
// eighty dots is eighty SDRAM words: five sixteen-word bursts per plane,
// twenty per line, plus the font's five -- inside the LOOKAHEAD-line window
// even when the round robin queues it behind the other masters. The plane
// bases are the hardware windows (A8000=B, B0000=R, B8000=G, and E
// at E0000, where pc98_gvram_seq keeps it). A line's byte offset inside its
// plane comes from the slave GDC's display registers the way the uPD7220
// walks them: the rasterline selects one of the four PRAM partitions by its
// LEN (lines past the last partition wrap back to the first), and the byte
// address is that partition's SAD plus the line-in-partition times PITCH --
// all word counts, shifted left one and wrapped inside the 32 KB plane.
// Latched at each line edge, so scroll-by-SAD and split screens behave the
// way software expects them to.
//
// DOMAINS. The fetch FSM runs on the chipset clock with the port-D
// handshake; the display shift runs on the dot clock the text renderer uses.
// The two meet in the line ring; the fetch side learns the scanline through
// a gray-coded vcount (multi-bit counters tear through a plain
// synchroniser), and the display side reads each line's own bank -- no
// completion handshake crosses the boundary at all.
//
// Remaining limit: the digital-mode packed palette at 0xA8-0xAE is not
// decoded (the digital path shows the fixed eight colours), and the dot is
// an index into the palette file owned by Peripherals.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_gvram_display #(
    parameter int DOT_BITS = 10,          // hcount/vcount width
    parameter int LINES    = 400
) (
    input  wire        clk,               // fetch side (chipset)
    input  wire        rst,

    // The dot-clock side: the raster counters the text renderer consumes.
    input  wire        rd_clk,
    input  wire [DOT_BITS-1:0] hcount,
    input  wire [DOT_BITS-1:0] vcount,
    input  wire        disp_on,           // the slave GDC's START seen
    input  wire        disp_page,         // port 0xA4 bit 0: show page one
    input  wire        analog_mode,       // port 0x6A bit 0: plane E exists

    // The slave GDC's display registers, live from pc98_gdc on this same
    // clock. They are latched at each line edge, so a mid-frame rewrite
    // takes effect from the next rasterline -- which is how the hardware's
    // scroll (SAD) and split-screen (partitions) actually behave.
    input  wire  [7:0]  pitch,            // PITCH register value
    input  wire         mhz5,             // port 0x6A clock field == 3
    input  wire  [15:0] part_sad [0:3],   // partition start, word address
    input  wire  [9:0]  part_len [0:3],   // partition length, lines

    // sdram_mp port side -- the controller's port D, a read-only master of
    // its own so the twenty bursts a line never queue behind the font's five.
    output logic       p_req,
    output logic [23:0] p_addr,
    output logic [3:0]  p_len,
    input  wire         p_ack,
    input  wire         p_rvalid,
    input  wire  [15:0] p_rdata,
    input  wire         p_done,

    // One dot of graphics, aligned with hcount delayed one rd_clk (the
    // buffer read is registered); zero when the plane is off.
    output logic [3:0] gfx_dot,           // {E, R, G, B}

    // Underrun telemetry for the wandering-band-edge hunt: a fill that is
    // still running when the next line edge arrives leaves that line's bank
    // stale, so the picture's horizontal boundaries sit a line low for one
    // rasterline. dbg packs {worst fill length in clk, skipped-line count,
    // launched-fill count}; the counters saturate at 0xFF so a runaway still
    // reads as nonzero.
    output logic [31:0] dbg
);

    // ---- the scanline, gray-coded across the domains ----------------------
    //
    // vcount changes many bits at once; a binary synchroniser can tear it
    // into a wrong line number and the fetch would fill garbage for a frame.
    // Gray changes one bit per step, so any torn sample is a valid neighbour.
    function automatic [8:0] bin2gray(input [8:0] b);
        bin2gray = b ^ (b >> 1);
    endfunction
    function automatic [8:0] gray2bin(input [8:0] g);
        logic [8:0] b;
        b[8] = g[8];
        for (int i = 7; i >= 0; i = i - 1)
            b[i] = b[i+1] ^ g[i];
        gray2bin = b;
    endfunction

    wire [8:0] vcount_gray = bin2gray(vcount[8:0]);
    logic [8:0] gray_s1 = 9'd0, gray_s2 = 9'd0;
    always_ff @(posedge clk) begin
        gray_s1 <= vcount_gray;
        gray_s2 <= gray_s1;
    end
    wire [8:0] line_now = gray2bin(gray_s2);

    logic [8:0] line_q = 9'd0;
    always_ff @(posedge clk) begin
        if (rst)
            line_q <= 9'd0;
        else if (line_now != line_q)
            line_q <= line_now;
    end
    wire line_edge = (line_now != line_q);

    // ---- the buffers -------------------------------------------------------
    //
    // Four banks of four planes of eighty bytes, four memories so the display
    // can read every plane's byte in the same cycle. A packed-3D array lands
    // in registers -- the LABs do not have it -- so each plane is its own
    // flat array marked for M10K, written from its own always block the way
    // the inference template wants. Index is {line[1:0], byte-in-line} with
    // the byte counting 0..79 of a 128-wide bank slot; the tail is unused and
    // 512 bytes still sit inside one M10K, so the two extra banks are free.
    (* ramstyle = "M10K" *) logic [7:0] buf_b [0:511];
    (* ramstyle = "M10K" *) logic [7:0] buf_r [0:511];
    (* ramstyle = "M10K" *) logic [7:0] buf_g [0:511];
    (* ramstyle = "M10K" *) logic [7:0] buf_e [0:511];

    // The bank a line lives in is its own number modulo four: the fill for
    // target T writes bank T[1:0] and the display reads bank vcount[1:0].
    // With a LOOKAHEAD-line fetch the fill and the display never touch the
    // same bank, so no done/use-bank handshake is needed at all -- a skipped
    // fill simply leaves line T-4's bytes in T's bank.
    localparam int LOOKAHEAD = 3;
    logic [1:0]  fill_bank = 2'd0;        // T[1:0] of the running fill

    // The plane bases, as SDRAM word addresses (one guest byte per word, so
    // the guest-linear windows are their own indices). Page one has no guest
    // address -- RAM.sv banks it at 0x600000 + plane*0x8000, where
    // pc98_gvram_seq's access-page writes land it.
    function automatic [23:0] plane_base(input [1:0] p);
        if (disp_page)
            plane_base = 24'h600000 + {7'd0, p, 15'd0};
        else case (p)
            2'd0:    plane_base = 24'hA8000;   // B
            2'd1:    plane_base = 24'hB0000;   // R
            2'd2:    plane_base = 24'hB8000;   // G
            default: plane_base = 24'hE0000;   // E
        endcase
    endfunction

    // ---- the fetch FSM -----------------------------------------------------
    localparam int BURST = 16;            // words per transaction
    localparam int CHUNKS = 80 / BURST;   // 5

    // The byte a line starts from: the uPD7220 never multiplies -- inside a
    // partition it just adds PITCH words a line to the running address, and
    // running off the partition's LEN restarts from the next entry's SAD.
    // Track it the same way: a 2-bit partition pointer, a line counter
    // inside it, and a base that steps by {pitch, 1'b0} bytes. A rasterline
    // past all four LENs keeps extending partition three -- the address
    // counter has nowhere else to go -- and the PRAM entries are meant to
    // cover the raster anyway. Replaces a multiply, four compares and three
    // subtracts with one adder and two small muxes. One corner is cheaper
    // than the absolute model: a zero-length partition is crossed one line
    // late instead of instantly (the walk advances once a line) -- an
    // underspecified-PRAM case the BIOS never writes.
    //
    // The walk leads the raster by LOOKAHEAD lines: when the edge for
    // line_now fires, run_base holds the byte offset of display line
    // (line_now + LOOKAHEAD) mod LINES -- the line the fill launched here
    // must bring in -- and the step moves it one line further. That gives a
    // fill roughly three line times to land (~5200 chipset clocks against a
    // ~1730-clock budget that the four-port round robin can occasionally
    // overrun), and a fill that still misses just leaves a bank stale rather
    // than corrupting the walk.
    logic [1:0]  cur_part  = 2'd0;
    logic [9:0]  part_rel  = 10'd0;     // line index inside the partition
    logic [14:0] run_base  = 15'd0;     // byte offset of the walked line

    // The line the next fill must bring in, wrapped into the display range.
    // line_now runs 0..439 but a fill only launches while line_now < LINES,
    // so the sum tops out at 402 and one subtract covers the wrap: at edges
    // 397..399 the targets are next frame's lines 0..2.
    wire [9:0] tgt_sum  = {1'b0, line_now} + 10'(LOOKAHEAD);
    wire [8:0] fill_tgt = (tgt_sum >= 10'(LINES)) ? 9'(tgt_sum - 10'(LINES))
                                                : 9'(tgt_sum);

    // The clock field changes what PITCH counts (np21w maketgrp: s_pitch is
    // doubled while the 5MHz flag is clear): at 2.5MHz the register is words
    // per line, at 5MHz it is bytes per line -- and forced even, np21w's
    // `s_pitch &= 0xfe`. SAD stays a word address in both modes.
    wire  [8:0]  pitch_b  = mhz5 ? {1'b0, pitch[7:1], 1'b0}
                                 : {pitch, 1'b0};
    wire  [9:0]  cur_len  = part_len[cur_part];
    wire  [15:0] sad_next = part_sad[cur_part + 2'd1];   // wraps to 0 at 3, unused there
    wire         w_wrap   = (line_now == 9'(LINES - 1 - LOOKAHEAD));
    wire         w_adv    = !w_wrap && (cur_part != 2'd3)
                       && (({1'b0, part_rel} + 11'd1) >= {1'b0, cur_len});
    wire  [14:0] base_next = w_wrap ? 15'(part_sad[0] << 1)
                          : w_adv  ? 15'(sad_next << 1)
                          :          run_base + 15'(pitch_b);

    always_ff @(posedge clk) begin
        if (rst) begin
            cur_part <= 2'd0;
            part_rel <= 10'd0;
            run_base <= 15'd0;
        end else if (line_edge && (line_now < 9'(LINES))) begin
            cur_part <= w_wrap ? 2'd0 : w_adv ? cur_part + 2'd1 : cur_part;
            part_rel <= (w_wrap || w_adv) ? 10'd0 : part_rel + 10'd1;
            run_base <= base_next;
        end
    end

    logic [2:0]  f_plane = 3'd0;
    logic [3:0]  f_chunk = 4'd0;
    logic [3:0]  f_word  = 4'd0;          // 0..15 within the burst
    logic        f_active = 1'b0;
    logic        req_q    = 1'b0;         // want a burst, dropped on ack
    logic [14:0] fill_base = 15'd0;       // byte offset of this line in-plane
    logic [8:0]  act_tgt   = 9'd0;        // display line the running fill serves

    // The buffer writes live in their own blocks, one per plane memory --
    // the M10K inference template. Byte index is {target[1:0], chunk, word}.
    wire  [8:0] w_addr = {fill_bank, f_chunk[2:0], f_word};
    wire        wr     = f_active & p_rvalid;
    always_ff @(posedge clk) if (wr && f_plane[1:0] == 2'd0) buf_b[w_addr] <= p_rdata[7:0];
    always_ff @(posedge clk) if (wr && f_plane[1:0] == 2'd1) buf_r[w_addr] <= p_rdata[7:0];
    always_ff @(posedge clk) if (wr && f_plane[1:0] == 2'd2) buf_g[w_addr] <= p_rdata[7:0];
    always_ff @(posedge clk) if (wr && f_plane[1:0] == 2'd3) buf_e[w_addr] <= p_rdata[7:0];

    // One request per burst, deasserted the cycle the arbiter acks -- the
    // font fetcher drives port B the same way, and holding req through the
    // burst lets the arbiter re-capture a stale address at p_done.
    assign p_req  = req_q;
    assign p_len  = 4'(BURST - 1);
    // The plane byte offset wraps inside the 32 KB plane the way the GDC's
    // own address counter does -- at chunk granularity here, which is exact
    // unless a line straddles the plane end between sixteen-byte marks.
    assign p_addr = plane_base(f_plane[1:0])
                 + {9'd0, (fill_base + 15'(f_chunk) * 15'(BURST)) & 15'h7FFF};

    always_ff @(posedge clk) begin
        if (rst) begin
            f_active <= 1'b0;
            f_plane  <= 3'd0;
            f_chunk  <= 4'd0;
            f_word   <= 4'd0;
            req_q    <= 1'b0;
            fill_bank <= 2'd0;
            act_tgt  <= 9'd0;
        end else begin
            if (p_ack) req_q <= 1'b0;
            if (!f_active) begin
                if (line_edge && (line_now < 9'(LINES))) begin
                    // A new line just began: fill the one LOOKAHEAD lines
                    // out into its own bank. The walk is already positioned
                    // at that target, so run_base is its byte offset --
                    // latching both freezes them for the whole fill against
                    // a mid-line SAD/PITCH rewrite.
                    fill_base <= run_base;
                    fill_bank <= fill_tgt[1:0];
                    act_tgt   <= fill_tgt;
                    f_plane   <= 3'd0;
                    f_chunk   <= 4'd0;
                    f_active  <= 1'b1;
                    req_q     <= 1'b1;
                end
            end else begin
                if (p_rvalid) f_word <= f_word + 4'd1;
                if (p_done) begin
                    f_word <= 4'd0;
                    if (f_chunk == 4'(CHUNKS - 1)) begin
                        f_chunk <= 4'd0;
                        // A digital machine has no plane E: stop at G and
                        // save the five bursts of bus time per line.
                        if (f_plane == (analog_mode ? 3'd3 : 3'd2)) begin
                            f_plane  <= 3'd0;
                            f_active <= 1'b0;
                        end else begin
                            f_plane <= f_plane + 3'd1;
                            req_q   <= 1'b1;
                        end
                    end else begin
                        f_chunk <= f_chunk + 4'd1;
                        req_q   <= 1'b1;
                    end
                end
            end
        end
    end

    // ---- the display side --------------------------------------------------
    //
    // Byte for the NEXT dot, registered once: the arrays are BRAM. One stage
    // of address, one stage of data -- the output aligns with hcount two
    // dots later, and the merger in Peripherals delays the text pixel to
    // match.
    //
    // The bank is the line's own number, so the read address needs no
    // handshake at all: line N's bytes sit in bank N[1:0], written LOOKAHEAD
    // lines earlier. The only failure left is a fill still running at its
    // target's boundary, which shows last cycle-of-four's line.
    wire visible    = (hcount < 10'd640) && (vcount < 10'd400);
    wire [6:0] n_byi = hcount[9:3];              // 0..79
    wire [2:0] n_bit = ~hcount[2:0];             // MSB is the leftmost dot

    logic [7:0] rd_b, rd_r, rd_g, rd_e;
    logic [2:0] bit_q = 3'd0;
    logic       vis_q = 1'b0;
    wire  [8:0] r_addr = {vcount[1:0], n_byi};
    always_ff @(posedge rd_clk) begin
        bit_q <= n_bit;
        vis_q <= visible;
        rd_b  <= buf_b[r_addr];
        rd_r  <= buf_r[r_addr];
        rd_g  <= buf_g[r_addr];
        rd_e  <= buf_e[r_addr];
    end

    // ---- underrun telemetry ------------------------------------------------
    //
    // skip counts a display-line edge a fill could not launch on because the
    // previous one still ran -- that edge's target keeps its cycle-of-four
    // data. late counts a fill still running when its OWN target's line edge
    // arrives -- the line reads its bank mid-write. Both put stale data on a
    // rasterline: the wandering band edge. max_fill is the worst launch->done
    // length in clk cycles; a line is ~1730 of them, so a number near 5200
    // says the deadline itself is the problem.
    logic [7:0]  dbg_skip      = 8'd0;
    logic [7:0]  dbg_late      = 8'd0;
    logic [15:0] dbg_fill_len  = 16'd0;
    logic [15:0] dbg_max_fill  = 16'd0;
    logic        f_act_d       = 1'b0;
    always_ff @(posedge clk) begin
        f_act_d <= f_active;
        if (rst) begin
            dbg_skip     <= 8'd0;
            dbg_late     <= 8'd0;
            dbg_fill_len <= 16'd0;
            dbg_max_fill <= 16'd0;
        end else begin
            if (line_edge && f_active) begin
                if (line_now == act_tgt && (dbg_late != 8'hFF))
                    dbg_late <= dbg_late + 8'd1;
                if (line_now < 9'(LINES) && (dbg_skip != 8'hFF))
                    dbg_skip <= dbg_skip + 8'd1;
            end
            if (f_active)
                dbg_fill_len <= (dbg_fill_len == 16'hFFFF) ? dbg_fill_len : dbg_fill_len + 16'd1;
            else
                dbg_fill_len <= 16'd0;
            if (f_act_d & ~f_active && (dbg_fill_len > dbg_max_fill))
                dbg_max_fill <= dbg_fill_len;
        end
    end
    assign dbg = {dbg_max_fill, dbg_skip, dbg_late};

    wire pb = rd_b[bit_q];
    wire pr = rd_r[bit_q];
    wire pg = rd_g[bit_q];
    wire pe = rd_e[bit_q] & analog_mode;
    // The four planes assemble into the palette index as {E,G,R,B}: the
    // windows in memory order are B,R,G,E and the BIOS's own palette table
    // (ITF trace F8042F) gives index 1 blue, 2 red, 4 green -- so the bit
    // the B0000 window produced is index bit 1, the B8000 window bit 2.
    assign gfx_dot = (disp_on & vis_q) ? {pe, pg, pr, pb} : 4'd0;

endmodule

`default_nettype wire
