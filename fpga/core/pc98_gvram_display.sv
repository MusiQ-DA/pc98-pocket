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
// the palette is the fixed sixteen-colour mapping rather than ports
// 0x4A0-0x4AF, and the E plane is always taken at E0000. Each is one register
// file away when a title needs it.
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

    // sdram_mp port side, ARBITRATED OUTSIDE against the font fetch.
    output logic       p_req,
    output logic [23:0] p_addr,
    output logic [4:0]  p_len,
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
        b = g;
        for (int i = 1; i < 9; i = i + 1)
            b[i] = b[i-1] ^ g[i];
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
    logic [7:0] buf [0:1][0:3][0:79];

    logic        fill_bank = 1'b0;        // the bank being written
    logic        bank_done = 1'b0;        // toggles when a fill completes
    logic [8:0]  fill_line = 9'd0;

    // The plane bases, as byte addresses into guest memory.
    function automatic [23:0] plane_base(input [1:0] p);
        case (p)
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

    assign p_req  = f_active;
    assign p_len  = 5'(BURST - 1);
    assign p_addr = plane_base(f_plane[1:0]) + {14'd0, fill_line} * 80
                 + {18'd0, f_chunk} * BURST;

    always_ff @(posedge clk) begin
        if (rst) begin
            f_active <= 1'b0;
            f_plane  <= 3'd0;
            f_chunk  <= 4'd0;
            f_word   <= 7'd0;
            fill_bank <= 1'b0;
            bank_done <= 1'b0;
            fill_line <= 9'd0;
        end else begin
            if (!f_active) begin
                if (line_edge) begin
                    // A new line just began: fill the NEXT one into the other
                    // bank. Wrap at the raster's line count.
                    fill_line <= (line_now == 9'(LINES - 1)) ? 9'd0
                                                             : line_now + 9'd1;
                    fill_bank <= ~fill_bank;
                    f_plane   <= 3'd0;
                    f_chunk   <= 4'd0;
                    f_active  <= 1'b1;
                end
            end else begin
                if (p_ack) begin
                    // one word per rvalid from here to p_done
                end
                if (p_rvalid) begin
                    buf[fill_bank][f_plane[1:0]][f_chunk * BURST + f_word[3:0]]
                        <= p_rdata[7:0];
                    f_word <= f_word + 7'd1;
                end
                if (p_done) begin
                    f_word <= 7'd0;
                    if (f_chunk == CHUNKS - 1) begin
                        f_chunk <= 4'd0;
                        if (f_plane == 3) begin
                            f_plane  <= 3'd0;
                            f_active <= 1'b0;
                            bank_done <= ~bank_done;   // the bank is ready
                        end else begin
                            f_plane <= f_plane + 3'd1;
                        end
                    end else begin
                        f_chunk <= f_chunk + 4'd1;
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
    logic        bank_done_s1 = 1'b0, bank_done_s2 = 1'b0;
    always_ff @(posedge rd_clk) begin
        bank_done_s1 <= bank_done;
        bank_done_s2 <= bank_done_s1;
    end
    // The freshest completed bank: follow the toggle, and at reset show the
    // bank that the first fill produced.
    logic use_bank = 1'b0;
    always_ff @(posedge rd_clk) begin
        if (rst)
            use_bank <= 1'b1;
        else if (bank_done_s2 != bank_done_s1)
            use_bank <= ~use_bank;
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
        rd_b  <= buf[use_bank][0][n_byi];
        rd_r  <= buf[use_bank][1][n_byi];
        rd_g  <= buf[use_bank][2][n_byi];
        rd_e  <= buf[use_bank][3][n_byi];
    end

    wire pb = rd_b[bit_q];
    wire pr = rd_r[bit_q];
    wire pg = rd_g[bit_q];
    wire pe = rd_e[bit_q];
    assign gfx_dot = (disp_on & vis_q) ? {pe, pr, pg, pb} : 4'd0;

endmodule

`default_nettype wire
