//
// pc98_gvram_display -- the graphics plane's display fetch.
//
// The text plane reaches the screen through TVRAM and the glyph row buffer;
// the graphics plane is 128 KB of guest SDRAM (four planes, B/R/G/E, 80 bytes
// per line each) and nothing read it. This module is the graphics half of the
// picture: it keeps two line buffers in BRAM, fills the back one a line ahead
// over the font's SDRAM port (whose kanji load is five bursts per line against
// a forty-burst budget), and shifts the front one out at the dot clock.
//
// ADDRESSING. RAM.sv stores one guest byte per 16-bit word, so a line of
// eighty dots is eighty SDRAM words: five sixteen-word bursts per plane,
// twenty per line, plus the font's five -- comfortably inside a line time.
// The plane bases are the hardware windows (A8000=B, B0000=R, B8000=G, and E
// at E0000, where pc98_gvram_seq keeps it); the line stride is eighty bytes
// inside each plane.
//
// DOMAINS. The fetch FSM runs on the chipset clock with the port-B
// handshake; the display shift runs on the dot clock the text renderer uses.
// The two meet in a byte-wide dual-port buffer pair; the fetch side learns
// the scanline through a gray-coded vcount (multi-bit counters tear through
// a plain synchroniser), and the display side picks the freshest completed
// bank off a toggled flag.
//
// First-cut limits, all noted in docs/SOFTCORE_RTL_SPLIT.md: the slave GDC's
// SAD/PITCH are not consumed (games that scroll by moving SAD will not move),
// and the palette is the fixed sixteen-colour mapping rather than ports
// 0x4A0-0x4AF. Each is one register file away when a title needs it.
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
    output logic [3:0] gfx_dot            // {E, R, G, B}
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

    wire [8:0] vga_gray = bin2gray(vcount[8:0]);
    logic [8:0] gray_s1 = 9'd0, gray_s2 = 9'd0;
    always_ff @(posedge clk) begin
        gray_s1 <= vga_gray;
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
    // Two banks of four planes of eighty bytes. The fetch side writes one
    // byte per completed word (RAM.sv's packing); the display side reads all
    // four planes' byte for a dot in one cycle. Simple arrays; Quartus will
    // put them in M10K and the registered read below is the BRAM's own.
    logic [7:0] linebuf [0:1][0:3][0:79];

    logic        fill_bank = 1'b0;        // the bank being written
    logic        done_bank = 1'b0;        // the bank the last completed fill wrote
    logic [8:0]  fill_line = 9'd0;

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

    logic [2:0]  f_plane = 3'd0;
    logic [3:0]  f_chunk = 4'd0;
    logic [6:0]  f_word  = 7'd0;          // 0..15 within the burst
    logic        f_active = 1'b0;
    logic        req_q    = 1'b0;         // want a burst, dropped on ack

    // One request per burst, deasserted the cycle the arbiter acks -- the
    // font fetcher drives port B the same way, and holding req through the
    // burst lets the arbiter re-capture a stale address at p_done.
    assign p_req  = req_q;
    assign p_len  = 4'(BURST - 1);
    assign p_addr = plane_base(f_plane[1:0])
                 + {15'd0, fill_line} * 24'd80
                 + {20'd0, f_chunk} * 24'(BURST);

    always_ff @(posedge clk) begin
        if (rst) begin
            f_active <= 1'b0;
            f_plane  <= 3'd0;
            f_chunk  <= 4'd0;
            f_word   <= 7'd0;
            req_q    <= 1'b0;
            fill_bank <= 1'b0;
            done_bank <= 1'b0;
            fill_line <= 9'd0;
        end else begin
            if (p_ack) req_q <= 1'b0;
            if (!f_active) begin
                if (line_edge && (line_now < 9'(LINES))) begin
                    // A new line just began: fill the NEXT one into the other
                    // bank. Wrap at the raster's line count; lines past the
                    // active window are not fetched at all -- they have no
                    // plane storage and nothing displays them.
                    fill_line <= (line_now == 9'(LINES - 1)) ? 9'd0
                                                             : line_now + 9'd1;
                    fill_bank <= ~fill_bank;
                    f_plane   <= 3'd0;
                    f_chunk   <= 4'd0;
                    f_active  <= 1'b1;
                    req_q     <= 1'b1;
                end
            end else begin
                if (p_rvalid) begin
                    linebuf[fill_bank][f_plane[1:0]][32'(f_chunk) * BURST + {28'd0, f_word[3:0]}]
                        <= p_rdata[7:0];
                    f_word <= f_word + 7'd1;
                end
                if (p_done) begin
                    f_word <= 7'd0;
                    if (f_chunk == 4'(CHUNKS - 1)) begin
                        f_chunk <= 4'd0;
                        // A digital machine has no plane E: stop at G and
                        // save the five bursts of bus time per line.
                        if (f_plane == (analog_mode ? 3'd3 : 3'd2)) begin
                            f_plane  <= 3'd0;
                            f_active <= 1'b0;
                            done_bank <= fill_bank;    // the bank is ready
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
    // The displayed bank changes ONLY at a line boundary: a fill completes
    // well inside its line, and adopting it the moment p_done lands would
    // shear the tail of the line still being drawn onto the next line's
    // bytes. done_bank crosses as a plain bit -- it changes once a line --
    // and use_bank follows it when vcount steps.
    logic        done_bank_s1 = 1'b0, done_bank_s2 = 1'b0;
    logic [8:0]  v_q = 9'd0;
    logic        use_bank = 1'b0;
    always_ff @(posedge rd_clk) begin
        done_bank_s1 <= done_bank;
        done_bank_s2 <= done_bank_s1;
        v_q          <= vcount[8:0];
        if (rst)
            use_bank <= 1'b0;
        else if (vcount[8:0] != v_q)
            use_bank <= done_bank_s2;
    end

    // Which dot the NEXT cycle will need.
    wire visible    = (hcount < 10'd640) && (vcount < 10'd400);
    wire [6:0] n_byi = hcount[9:3];              // 0..79
    wire [2:0] n_bit = 7 - hcount[2:0];          // MSB is the leftmost dot

    logic [7:0] rd_b, rd_r, rd_g, rd_e;
    logic [6:0] byi_q = 7'd0;
    logic [2:0] bit_q = 3'd0;
    logic       vis_q = 1'b0;
    always_ff @(posedge rd_clk) begin
        byi_q <= n_byi;
        bit_q <= n_bit;
        vis_q <= visible;
        rd_b  <= linebuf[use_bank][0][n_byi];
        rd_r  <= linebuf[use_bank][1][n_byi];
        rd_g  <= linebuf[use_bank][2][n_byi];
        rd_e  <= linebuf[use_bank][3][n_byi];
    end

    wire pb = rd_b[bit_q];
    wire pr = rd_r[bit_q];
    wire pg = rd_g[bit_q];
    wire pe = rd_e[bit_q] & analog_mode;
    assign gfx_dot = (disp_on & vis_q) ? {pe, pr, pg, pb} : 4'd0;

endmodule

`default_nettype wire
