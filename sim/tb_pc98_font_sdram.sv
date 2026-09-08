//
// tb_pc98_font_sdram -- glyphs out of SDRAM, end to end.
//
// Row buffer -> font fetcher -> sdram_mp -> sdram_model, with real FONT.ROM
// bytes preloaded at the addresses the fetcher will compute. Checks that the
// glyph the renderer eventually reads is the one that is actually in the font,
// which is the whole chain the kanji path depends on.
//
// The font slice in font_slice.hex was cut from a real font.rom: ANK 'A' at
// 0x0C10 and hiragana A at 0x3C40, both halves. Its lines are
// "<byte offset> <value>" with one byte per SDRAM word, which is how RAM.sv
// stores everything and therefore how the loader will write it.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_font_sdram;

    localparam int ADDR_BITS = 24;
    localparam int LEN_BITS  = 5;
    localparam [ADDR_BITS-1:0] FONT_BASE = 24'h200000;

    logic clk = 0, rst = 1;
    always #11.64 clk = ~clk;

    // ---- row buffer --------------------------------------------------------
    logic        fill_start = 1'b0;
    logic [11:0] row_base = 12'd0;
    wire         busy;
    wire [11:0]  tv_cell;
    logic [7:0]  tv_char_lo, tv_char_hi;

    wire        f_req, f_busy, f_valid;
    wire [19:0] f_addr;
    wire  [7:0] f_data;

    logic [6:0] rd_col = 7'd0;
    logic [3:0] rd_line = 4'd0;
    wire  [7:0] rd_byte;
    wire        kanji_seen;

    pc98_glyph_rowbuf #(.COLS(4)) u_rowbuf (
        .clk(clk), .rst(rst),
        .fill_start(fill_start), .row_base(row_base), .bitac(8'hFF), .busy(busy),
        .tv_cell(tv_cell), .tv_char_lo(tv_char_lo), .tv_char_hi(tv_char_hi),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data),
        .rd_clk(clk), .rd_cell(rd_col), .rd_line(rd_line), .rd_byte(rd_byte), .kanji_seen(kanji_seen)
    );

    // Cell 0 is ANK 'A'; cells 1 and 2 are one kanji; cell 3 is ANK 'A' again.
    logic [7:0] scr_lo [0:7];
    logic [7:0] scr_hi [0:7];
    always_ff @(posedge clk) begin
        tv_char_lo <= scr_lo[tv_cell[2:0]];
        tv_char_hi <= scr_hi[tv_cell[2:0]];
    end

    // ---- fetcher and controller -------------------------------------------
    wire                 p_req;
    wire [ADDR_BITS-1:0] p_addr;
    wire [LEN_BITS-1:0]  p_len;
    wire                 p_ack, p_rvalid, p_done;
    wire [15:0]          p_rdata;

    pc98_font_fetch #(.ADDR_BITS(ADDR_BITS), .LEN_BITS(LEN_BITS),
                      .FONT_BASE(FONT_BASE)) u_fetch (
        .clk(clk), .rst(rst),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data),
        .p_req(p_req), .p_addr(p_addr), .p_len(p_len), .p_ack(p_ack),
        .p_rvalid(p_rvalid), .p_rdata(p_rdata), .p_done(p_done)
    );

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_ras_n, s_cas_n, s_we_n, s_dq_io;
    wire [1:0] s_dqm;
    wire [15:0] s_dq_out, s_dq_in;
    wire init_done, stat_idle, stat_refresh;
    wire [0:0] grant;

    sdram_mp #(.PORTS(1), .BURST_MAX(16), .CAS_LATENCY(2),
               .INIT_NOP(64), .REFRESH_INT(320)) u_sdram (
        .clk(clk), .rst(rst),
        .p_req(p_req), .p_we(1'b0), .p_addr(p_addr), .p_len(p_len),
        .p_ack(p_ack),
        .p_wcnt(), .p_wdata(16'd0), .p_wmask(2'b11),
        .grant(grant), .p_rvalid(p_rvalid), .p_rdata(p_rdata), .p_done(p_done),
        .init_done(init_done), .stat_idle(stat_idle), .stat_refresh(stat_refresh),
        .sdram_a(s_a), .sdram_ba(s_ba), .sdram_cke(s_cke),
        .sdram_ras_n(s_ras_n), .sdram_cas_n(s_cas_n), .sdram_we_n(s_we_n),
        .sdram_dqm(s_dqm), .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out),
        .sdram_dq_io(s_dq_io)
    );

    sdram_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                  .T_RAS(2), .T_RC(3), .T_REF(0)) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ---- the real font bytes ----------------------------------------------
    int fh, waddr, wval, n;
    logic [7:0] want [0:65535];        // byte offset -> expected value

    int errors = 0;
    logic [7:0] got;

    task automatic rd(input int c, input int l, output logic [7:0] d);
        rd_col = 7'(c); rd_line = 4'(l);
        @(posedge clk); @(posedge clk); @(posedge clk);
        d = rd_byte;
    endtask

    initial begin
        $display("=== glyphs out of SDRAM ===");

        // Load the slice into the model and remember what each byte should be.
        begin
            int lines;
            string ln;
            lines = 0;
            fh = $fopen("sim/font_slice.hex", "r");
            if (fh == 0) begin
                $display("  FAIL cannot open sim/font_slice.hex"); errors++;
            end
            while ($fscanf(fh, "%h %h\n", waddr, wval) == 2) begin
                // One byte per word: the file gives words, so split them.
                sdr.poke(FONT_BASE + waddr*2,     16'(wval & 8'hFF));
                sdr.poke(FONT_BASE + waddr*2 + 1, 16'((wval >> 8) & 8'hFF));
                want[waddr*2]     = 8'(wval & 8'hFF);
                want[waddr*2 + 1] = 8'((wval >> 8) & 8'hFF);
                lines++;
            end
            $fclose(fh);
            $display("  preloaded %0d words", lines);
            if (lines == 0) begin $display("  FAIL empty slice"); errors++; end
        end

        scr_lo[0] = 8'h41; scr_hi[0] = 8'h00;   // ANK 'A'  -> 0x0C10
        scr_lo[1] = 8'h04; scr_hi[1] = 8'h22;   // kanji    -> 0x3C40 / 0x3C50
        scr_lo[2] = 8'hFF; scr_hi[2] = 8'hFF;   // its right half
        scr_lo[3] = 8'h41; scr_hi[3] = 8'h00;   // ANK 'A' again

        repeat (8) @(posedge clk);
        rst = 0;
        wait (init_done);
        repeat (4) @(posedge clk);

        fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
        wait (busy == 1'b0);
        repeat (4) @(posedge clk);

        // Every byte of every cell must be the font's.
        for (int l = 0; l < 16; l++) begin
            rd(0, l, got);
            if (got !== want[20'h0C10 + l]) begin
                $display("  FAIL ANK line %0d: %02h want %02h",
                         l, got, want[20'h0C10 + l]); errors++;
            end
            rd(1, l, got);
            if (got !== want[20'h3C40 + l]) begin
                $display("  FAIL kanji left line %0d: %02h want %02h",
                         l, got, want[20'h3C40 + l]); errors++;
            end
            rd(2, l, got);
            if (got !== want[20'h3C50 + l]) begin
                $display("  FAIL kanji right line %0d: %02h want %02h",
                         l, got, want[20'h3C50 + l]); errors++;
            end
        end

        $display("  ANK   line 0-3: %02h %02h %02h %02h",
                 want[20'h0C10], want[20'h0C11], want[20'h0C12], want[20'h0C13]);
        $display("  kanji line 0-3: %02h %02h %02h %02h",
                 want[20'h3C40], want[20'h3C41], want[20'h3C42], want[20'h3C43]);
        $display("  protocol violations: %0d", sdr.violations);
        if (sdr.violations != 0) begin $display("  FAIL violations"); errors++; end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("GLOBAL TIMEOUT"); $finish;
    end

endmodule

`default_nettype wire
