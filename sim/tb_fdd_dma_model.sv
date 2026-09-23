//
// tb_fdd_dma_model -- the uPD71071 + sector-feed pair the FDC benches need.
//
// The benches that boot the real BIOS cannot use the real BUS_ARBITER (it
// owns the whole bus), so this model carries just the guest-visible surface:
// the odd 0x01-0x1F register window, the odd 0x21-0x2F page window, and a
// per-byte transfer engine. dma_ack is the one-clock pulse PERIPHERALS hands
// the FDC on the DACK falling edge; dma_tc rides the last byte's edge. The
// floppy's DRQ is self-gating (it drops while ack is high), so one byte
// moves every other clock once a channel is unmasked -- same pacing the
// real single-transfer mode produces.
//
// The feeder half is fdd_poll()/push_sector() in miniature: request[0] asks
// for a sector, the wanted LBA comes back on mgmt address 0, and one
// sector's bytes go in through mgmt address 15.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module tb_fdd_dma_model (
    input  logic        clk,

    // Guest writes: the caller decodes the windows, this module keeps the
    // registers. io_wr pulses once per byte written; io_addr is the port.
    input  logic        io_wr,
    input  logic        io_rd,
    input  logic [7:0]  io_addr,
    input  logic [7:0]  io_wdata,
    output logic [7:0]  io_rdata,

    // FDC side of the transfer
    input  logic        drq,
    output logic        dack,
    output logic        tc,
    input  logic [7:0]  ddata_i,
    output logic [7:0]  ddata_o,

    // Byte store -- the caller's memory array
    output logic        mem_wr,
    output logic [19:0] mem_addr,
    output logic [7:0]  mem_wdata,
    input  logic [7:0]  mem_rdata,

    // Sector feed -- the floppy's mgmt port. feed_en gates the whole side:
    // low and the port is never touched, so benches that drive mgmt by hand
    // keep exact control until they want the feeder.
    input  logic        feed_en,
    input  logic [1:0]  sec_req,
    output logic        mgmt_wr,
    output logic [3:0]  mgmt_addr,
    output logic [15:0] mgmt_wdata,
    output logic        mgmt_rd,
    input  logic [15:0] mgmt_rdata,
    input  logic        media_1024,
    output logic [14:0] feed_lba,
    output int          feed_idx,
    input  logic [7:0]  feed_byte
);
    // Register file -- index = port[4:1] on the odd window. Channel address
    // registers live at even indices, counts at odd, ch = index[2:1].
    logic [15:0] cur_addr [0:3];
    logic [15:0] cur_cnt  [0:3];
    logic  [7:0] mode_reg [0:3];
    logic  [3:0] mask_reg = 4'hF;
    logic  [3:0] page_reg [0:3];
    logic        hi_byte  = 1'b0;
    logic  [7:0] rb_lsb [0:7] = '{default: 8'h00};
    logic  [7:0] rb_msb [0:7] = '{default: 8'h00};

    wire  [3:0]  ridx     = io_addr[4:1];
    wire         is_dmac  = io_addr[0] & (io_addr[7:5] == 3'h0);
    wire         is_page  = io_addr[0] & (io_addr[7:4] == 4'h2) & ~io_addr[3];

    // io_wr/io_rd are level strobes: a real bus cycle holds them for two or
    // three clks. Apply each access once, on the leading edge, or hi_byte
    // toggles once per clk and the count/address bytes scramble.
    logic io_wr_q = 1'b0, io_rd_q = 1'b0;
    always_ff @(posedge clk) begin
        io_wr_q <= io_wr;
        io_rd_q <= io_rd;
    end
    wire wr_p = io_wr & ~io_wr_q;
    wire rd_done = io_rd_q & ~io_rd;
    // The byte pointer flips when a channel-register read completes; ridx must
    // be captured while the read is still live.
    logic rd_was_chan = 1'b0;
    always_ff @(posedge clk) if (io_rd) rd_was_chan <= is_dmac & (ridx < 8);
    wire rd_is_chan = rd_was_chan;

    always_ff @(posedge clk) begin
        if (wr_p && is_dmac) begin
            if (ridx < 8) begin
                if (~hi_byte) begin
                    rb_lsb[ridx[2:0]] <= io_wdata;
                    if (ridx[0]) cur_cnt [ridx[2:1]][7:0]  <= io_wdata;
                    else         cur_addr[ridx[2:1]][7:0]  <= io_wdata;
                end else begin
                    rb_msb[ridx[2:0]] <= io_wdata;
                    if (ridx[0]) cur_cnt [ridx[2:1]][15:8] <= io_wdata;
                    else         cur_addr[ridx[2:1]][15:8] <= io_wdata;
                end
                hi_byte <= ~hi_byte;
            end else case (ridx)
                4'd10: mask_reg[io_wdata[1:0]] <= io_wdata[2];
                4'd11: mode_reg[io_wdata[1:0]] <= io_wdata;
                4'd12: hi_byte <= 1'b0;
                4'd13: begin mask_reg <= 4'hF; hi_byte <= 1'b0; end
                4'd14: mask_reg <= 4'h0;
                4'd15: mask_reg <= io_wdata[3:0];
                default: ;
            endcase
        end else if (wr_p && is_page) begin
            page_reg[io_addr[2:1]] <= io_wdata[3:0];
        end else if (rd_done && rd_is_chan) begin
            hi_byte <= ~hi_byte;
        end
    end
    assign io_rdata = hi_byte ? rb_msb[ridx[2:0]] : rb_lsb[ridx[2:0]];

    // The FDC's DRQ lands on ch2 and ch3 alike; whichever is unmasked serves
    // it, ch2 first -- the BIOS masks the sibling anyway (FFC36).
    wire [1:0] serve_ch = ~mask_reg[2] ? 2'd2 : 2'd3;
    wire       serve_v  = ~mask_reg[2] | ~mask_reg[3];
    wire [1:0] serve_t  = mode_reg[serve_ch][3:2];

    always_ff @(posedge clk) begin
        dack   <= 1'b0;
        tc     <= 1'b0;
        mem_wr <= 1'b0;
        if (drq && serve_v && !dack) begin
            dack     <= 1'b1;
            mem_wr   <= (serve_t == 2'b01);  // write transfer: FDC -> mem
            mem_addr <= {page_reg[serve_ch - 2'd1], cur_addr[serve_ch]};
            mem_wdata<= ddata_i;
            cur_addr[serve_ch] <= cur_addr[serve_ch] + 16'd1;
            if (cur_cnt[serve_ch] == 16'd0) begin
                cur_cnt[serve_ch] <= 16'hFFFF;
                tc <= 1'b1;
            end else
                cur_cnt[serve_ch] <= cur_cnt[serve_ch] - 16'd1;
        end
    end
    assign ddata_o = mem_rdata;

    // Sector feed. request[] is level: it stays up for a clock or two after
    // the last byte lands (fifo_full is registered behind it), so a feed is
    // armed once per request and only re-arms when the request drops --
    // the same one-sector-per-request rule fdd_poll() lives by.
    logic feed_act = 1'b0, feed_wait_lba = 1'b0, feed_done = 1'b0;
    always_ff @(posedge clk) begin
        mgmt_wr <= 1'b0;
        mgmt_rd <= 1'b0;
        if (!sec_req[0])
            feed_done <= 1'b0;
        if (feed_en && sec_req[0] && !feed_act && !feed_done) begin
            feed_act      <= 1'b1;
            feed_wait_lba <= 1'b1;
            feed_idx      <= 0;
            mgmt_addr     <= 4'd0;
            mgmt_rd       <= 1'b1;
        end else if (feed_wait_lba) begin
            feed_wait_lba <= 1'b0;
            feed_lba      <= mgmt_rdata[14:0];
        end else if (feed_act) begin
            mgmt_wr    <= 1'b1;
            mgmt_addr  <= 4'hF;
            mgmt_wdata <= {8'h00, feed_byte};
            feed_idx   <= feed_idx + 1;
            if (feed_idx == (media_1024 ? 1024 : 512) - 1) begin
                feed_act  <= 1'b0;
                feed_done <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
