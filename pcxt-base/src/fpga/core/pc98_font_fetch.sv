//
// pc98_font_fetch -- turns a glyph request into an SDRAM burst.
//
// pc98_glyph_rowbuf asks for sixteen contiguous bytes at a FONT.ROM offset;
// sdram_mp wants a word address, a length and a held request. This is the
// adapter between them.
//
// One byte per 16-bit word, which is how RAM.sv stores everything -- the PC/AT
// machine layer needs byte addressing and cannot get it any other way. Packing
// the font two-to-a-word would halve the space and the burst, but then the
// loader could not write it through the path that already exists, and a second
// write path is a worse trade than sixteen words instead of eight.
//
// So a glyph is SIXTEEN words, p_len = 15, and still ONE transaction: roughly
// ACT + tRCD + sixteen, against sixteen separate transactions of about seven
// clocks each. That is the whole reason to burst.
//
// FONT_BASE is where the image was loaded, as a WORD address. It sits above the
// guest's megabyte so nothing the guest does can reach it -- the font is a ROM
// as far as the machine is concerned, and the CG window will read it through
// this same path rather than by mapping it into the address space.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_font_fetch #(
    parameter int ADDR_BITS = 24,
    parameter int LEN_BITS  = 5,
    parameter [ADDR_BITS-1:0] FONT_BASE = 24'h200000
) (
    input  wire        clk,
    input  wire        rst,

    // Row-buffer side.
    input  wire        f_req,          // one cycle
    input  wire [19:0] f_addr,         // byte offset into FONT.ROM
    output logic       f_busy,
    output logic       f_valid,
    output logic [7:0] f_data,

    // sdram_mp port side.
    output logic                 p_req,
    output logic [ADDR_BITS-1:0] p_addr,
    output logic [LEN_BITS-1:0]  p_len,
    input  wire                  p_ack,
    input  wire                  p_rvalid,
    input  wire  [15:0]          p_rdata,
    input  wire                  p_done
);

    // Sixteen bytes, one per word.
    localparam int WORDS = 16;

    // Collect the burst, then hand it over.
    //
    // The obvious streaming form -- emit the low byte on p_rvalid and the high
    // byte the cycle after -- silently drops every second WORD, because the
    // controller delivers one word per cycle back to back and the cycle spent
    // on the high byte ignores the next p_rvalid. It looks like it works until
    // a burst is longer than two words.
    //
    // Sixteen bytes is one glyph and the row buffer wants them one per cycle
    // anyway, so take the whole burst into a register file and play it out.
    logic  [7:0] bytes_q [0:WORDS-1];
    logic  [3:0] wr_idx;
    logic  [4:0] rd_idx;
    logic        draining;

    always_ff @(posedge clk) begin
        if (rst) begin
            p_req    <= 1'b0;
            f_busy   <= 1'b0;
            f_valid  <= 1'b0;
            draining <= 1'b0;
            wr_idx   <= 4'd0;
            rd_idx   <= 5'd0;
            p_len    <= LEN_BITS'(WORDS - 1);
        end else begin
            f_valid <= 1'b0;

            if (f_req && !f_busy) begin
                p_addr   <= FONT_BASE + {4'd0, f_addr};
                p_len    <= LEN_BITS'(WORDS - 1);
                p_req    <= 1'b1;
                f_busy   <= 1'b1;
                wr_idx   <= 4'd0;
                rd_idx   <= 5'd0;
                draining <= 1'b0;
            end

            if (p_ack) p_req <= 1'b0;

            if (p_rvalid) begin
                bytes_q[wr_idx] <= p_rdata[7:0];
                wr_idx          <= wr_idx + 4'd1;
            end

            // p_done is one cycle and can share it with the last p_rvalid, so
            // start draining from the flag rather than from the pulse.
            if (p_done) draining <= 1'b1;

            if (draining) begin
                f_valid <= 1'b1;
                f_data  <= bytes_q[rd_idx[3:0]];
                rd_idx  <= rd_idx + 5'd1;
                if (rd_idx == 5'(WORDS - 1)) begin
                    draining <= 1'b0;
                    f_busy   <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire
