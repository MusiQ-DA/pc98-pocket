//============================================================================
//  z86_wbif -- z86's memory/I/O port, as the Zet Wishbone master the PC-98
//  bridge already serves.
//
//  Drop-in for z86's own `cache` module (same CPU-side ports): the line
//  loads, data reads and writes the pipeline issues become 16-bit Wishbone
//  cycles in exactly the shape zet_wb_master produces, so zet_cpu_bridge
//  (posted writes, 8288 pacing, INTA service, AEN/DMA handling) carries
//  them to the PC-98 bus unchanged:
//
//   * wb_adr_o[19:1] is the WORD address, wb_sel_o the lanes (01 even
//     byte, 10 odd byte, 11 word). An odd-addressed word is two byte
//     cycles, odd byte first, then the even byte of the next word --
//     zet_wb_master's order.
//   * wb_dat_o is lane-placed: an odd byte's data rides in [15:8].
//   * wb_tga_o = 1 marks I/O.
//   * cyc == stb, raised with stable operands and held until wb_ack_i,
//     which the bridge presents for exactly one edge of this (gated) clock.
//
//  Writes go first, then line loads, then reads. (z86's own cache put the
//  line load ahead of a pending write; on this bus that let a far jump into
//  just-patched code -- the ITF's 0000:04F8 hand-over stub -- fetch the
//  bytes from before the patch.) A line load is eight word reads (16 bytes,
//  16-byte aligned by the fetch unit) and always runs to completion: the
//  fetch unit drops a stale line itself (loading_drop).
//
//  SPDX-License-Identifier: Apache-2.0  (z86 is Apache-2.0)
//============================================================================

`default_nettype none

module z86_wbif #(
    // I/O recovery: the minimum gap, in clk, from the end of one I/O cycle
    // to the start of the next. PC-98 software times its port sequences in
    // V30 instructions -- the ITF's PIT check loads counter 0, waits two
    // JMP $+2, latches and expects the count to have moved -- and z86 runs
    // a JMP $+2 out of its fetch buffer in a few clocks. 64 clk_chipset is
    // ~1.5 us, about an 8 MHz 8086's OUT plus JMP $+2.
    parameter int IO_GAP = 64
) (
    input  wire         clk,
    input  wire         reset,

    // ---- z86 side: the `cache` module's ports -------------------------
    input  wire [19:0]  ld_addr,
    input  wire         ld_req,         // toggle
    output reg          ld_ack,         // toggle, follows ld_req when done
    output reg [127:0]  ld_data,

    input  wire [19:0]  rd_addr,
    input  wire         rd,             // pulse
    output reg          rd_ready,       // idle or data ready
    output reg [15:0]   rd_data,
    input  wire         rd_io,
    input  wire         rd_word,

    input  wire [19:0]  wr_addr,
    input  wire         wr_valid,       // held until wr_ready
    output reg          wr_ready,       // one-cycle pulse
    input  wire [15:0]  wr_data,
    input  wire         wr_word,
    input  wire         wr_io,

    // ---- Wishbone master (zet_wb_master's shape) -----------------------
    output reg  [19:1]  wb_adr_o,
    output reg  [ 1:0]  wb_sel_o,
    output reg          wb_we_o,
    output reg          wb_tga_o,
    output reg  [15:0]  wb_dat_o,
    output reg          wb_stb_o,
    output wire         wb_cyc_o,
    input  wire         wb_ack_i,
    input  wire [15:0]  wb_dat_i
);

    assign wb_cyc_o = wb_stb_o;

    localparam [2:0] S_IDLE = 3'd0,
                     S_LD   = 3'd1,     // line load, eight word reads
                     S_RD1  = 3'd2,     // read, first (or only) cycle
                     S_RD2  = 3'd3,     // odd word read, even byte of addr+1
                     S_WR1  = 3'd4,
                     S_WR2  = 3'd5;
    reg  [2:0]  st;

    // A read pulse is captured: rd may land while a load or write runs.
    reg         rd_pend;
    reg  [19:0] rd_a;
    reg         rd_isio, rd_isw;

    reg  [2:0]  ld_i;                   // word index inside the line

    // I/O recovery counter: loaded when an I/O cycle completes, an I/O
    // cycle may only start once it has run out.
    reg  [7:0]  io_rec;
    wire        io_ok = (io_rec == 8'd0);
    reg  [19:0] ld_base;

    // Byte/word shapes for one access at `a`.
    function automatic [1:0] sel_of(input logic a0, input logic word);
        sel_of = word ? 2'b11 : (a0 ? 2'b10 : 2'b01);
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            st       <= S_IDLE;
            io_rec   <= 8'd0;
            ld_ack   <= 1'b0;          // see fetch.sv's reset: both toggles to 0
            rd_ready <= 1'b1;
            rd_pend  <= 1'b0;
            wr_ready <= 1'b0;
            wb_stb_o <= 1'b0;
            wb_we_o  <= 1'b0;
            wb_tga_o <= 1'b0;
            wb_sel_o <= 2'b00;
            wb_adr_o <= 19'h0;
            wb_dat_o <= 16'h0;
        end else begin
            wr_ready <= 1'b0;
            if (io_rec != 8'd0) io_rec <= io_rec - 8'd1;
            if (wb_stb_o && wb_ack_i && wb_tga_o) io_rec <= IO_GAP[7:0];
            if (rd) begin
                rd_pend  <= 1'b1;
                rd_a     <= rd_addr;
                rd_isio  <= rd_io;
                rd_isw   <= rd_word;
                rd_ready <= 1'b0;
            end

            case (st)
              S_IDLE: begin
                if (wr_valid && !wr_ready && wr_io && !io_ok) begin
                    // An OUT waiting out its recovery gap holds everything
                    // behind it: nothing may pass a pending write.
                end else if (wr_valid && !wr_ready) begin
                    // Word at an odd address: the odd byte first, its data
                    // (the low byte of the word) in lane [15:8].
                    wb_adr_o <= wr_addr[19:1];
                    wb_sel_o <= sel_of(wr_addr[0], wr_word && !wr_addr[0]);
                    wb_dat_o <= wr_addr[0] ? {wr_data[7:0], 8'h00}
                              : (wr_word ? wr_data : {8'h00, wr_data[7:0]});
                    wb_we_o  <= 1'b1;
                    wb_tga_o <= wr_io;
                    wb_stb_o <= 1'b1;
                    st       <= S_WR1;
                end else if (ld_req ^ ld_ack) begin
                    ld_base  <= {ld_addr[19:4], 4'b0};
                    ld_i     <= 3'd0;
                    wb_adr_o <= {ld_addr[19:4], 3'd0};
                    wb_sel_o <= 2'b11;
                    wb_we_o  <= 1'b0;
                    wb_tga_o <= 1'b0;
                    wb_stb_o <= 1'b1;
                    st       <= S_LD;
                end else if ((rd_pend || rd) && (io_ok || !(rd ? rd_io : rd_isio))) begin
                    // rd may be this very cycle's pulse: take its operands
                    // live, the capture above lands at the same edge.
                    wb_adr_o <= (rd ? rd_addr : rd_a) >> 1;
                    wb_sel_o <= rd ? sel_of(rd_addr[0], rd_word && !rd_addr[0])
                                   : sel_of(rd_a[0], rd_isw && !rd_a[0]);
                    wb_we_o  <= 1'b0;
                    wb_tga_o <= rd ? rd_io : rd_isio;
                    wb_stb_o <= 1'b1;
                    st       <= S_RD1;
                end
              end

              S_LD: if (wb_ack_i) begin
                ld_data[16*ld_i +: 16] <= wb_dat_i;
                if (ld_i == 3'd7) begin
                    wb_stb_o <= 1'b0;
                    ld_ack   <= ~ld_ack;
                    st       <= S_IDLE;
                end else begin
                    ld_i     <= ld_i + 3'd1;
                    wb_adr_o <= {ld_base[19:4], ld_i + 3'd1};
                end
              end

              S_RD1: if (wb_ack_i) begin
                rd_pend <= 1'b0;
                if (rd_a[0]) begin
                    rd_data[7:0] <= wb_dat_i[15:8];
                    if (rd_isw) begin
                        wb_adr_o <= rd_a[19:1] + 19'd1;
                        wb_sel_o <= 2'b01;
                        st       <= S_RD2;
                    end else begin
                        rd_data[15:8] <= 8'h00;
                        wb_stb_o <= 1'b0;
                        rd_ready <= 1'b1;
                        st       <= S_IDLE;
                    end
                end else begin
                    rd_data  <= rd_isw ? wb_dat_i : {8'h00, wb_dat_i[7:0]};
                    wb_stb_o <= 1'b0;
                    rd_ready <= 1'b1;
                    st       <= S_IDLE;
                end
              end

              S_RD2: if (wb_ack_i) begin
                rd_data[15:8] <= wb_dat_i[7:0];
                wb_stb_o <= 1'b0;
                rd_ready <= 1'b1;
                st       <= S_IDLE;
              end

              S_WR1: if (wb_ack_i) begin
                if (wr_addr[0] && wr_word) begin
                    wb_adr_o <= wr_addr[19:1] + 19'd1;
                    wb_sel_o <= 2'b01;
                    wb_dat_o <= {8'h00, wr_data[15:8]};
                    st       <= S_WR2;
                end else begin
                    wb_stb_o <= 1'b0;
                    wr_ready <= 1'b1;
                    st       <= S_IDLE;
                end
              end

              S_WR2: if (wb_ack_i) begin
                wb_stb_o <= 1'b0;
                wr_ready <= 1'b1;
                st       <= S_IDLE;
              end

              default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
