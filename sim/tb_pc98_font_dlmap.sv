//
// tb_pc98_font_dlmap -- does the loader put all 256 ANK glyphs where the
// renderer reads them?
//
// Streams a synthetic FONT.ROM head (each byte a function of its file offset)
// through pc98_font_dlmap into pc98_font_ank exactly as data_loader does:
// sixteen bits per write, low byte the even address, at bridge 0x10100000.
// Writes past 0x17FF and into a neighbouring slot must not land. Then reads
// every code, 0x00-0xFF, on both banks and compares with the file:
//
//   8x16: file 0x0800 + code*16 + line
//   8x8 : file 0x0000 + code*8  + line/2
//
// Codes 0x80-0xFF (half-width katakana) are the case this exists for: an
// address slice that dropped bit 12 sent them past the end of the store.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
`timescale 1ns/1ps
`default_nettype none

module tb_pc98_font_dlmap;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic        dl_wr = 1'b0;
    logic [27:0] dl_addr = '0;
    logic [15:0] dl_data = '0;
    wire         hit;
    wire  [11:0] word;

    pc98_font_dlmap u_map (.dl_wr(dl_wr), .dl_addr(dl_addr), .hit(hit), .word(word));

    logic [7:0] code = '0;
    logic [3:0] line = '0;
    logic       sel8 = 1'b0;
    wire  [7:0] row;

    pc98_font_ank u_ank (
        .wr_clk(clk), .wr_en(hit), .wr_addr(word), .wr_data(dl_data),
        .rd_clk(clk), .code(code), .line(line), .sel8(sel8), .row(row)
    );

    function automatic [7:0] fbyte(input int o);
        fbyte = 8'((o * 37) ^ (o >> 5) ^ 8'h5A);
    endfunction

    int errs = 0;
    int checks = 0;

    task automatic put(input logic [27:0] a, input logic [15:0] d);
        @(negedge clk);
        dl_wr = 1'b1; dl_addr = a; dl_data = d;
        @(negedge clk);
        dl_wr = 1'b0;
    endtask

    task automatic chk(input bit b8, input int c, input int l, input [7:0] want);
        @(negedge clk);
        sel8 = b8; code = 8'(c); line = 4'(l);
        @(posedge clk); @(negedge clk);
        checks++;
        if (row !== want) begin
            errs++;
            if (errs <= 12)
                $display("  MISMATCH %s code %02x line %0d: got %02x want %02x",
                         b8 ? "8x8 " : "8x16", c, l, row, want);
        end
    endtask

    initial begin
        // The file head, in order, as the loader streams it.
        for (int o = 0; o < 16'h1800; o += 2)
            put(28'h0100000 + 28'(o), {fbyte(o + 1), fbyte(o)});
        // Past the ANK window and in the neighbouring slots: must be ignored.
        for (int o = 16'h1800; o < 16'h2000; o += 2)
            put(28'h0100000 + 28'(o), 16'hDEAD);
        for (int o = 0; o < 16'h1800; o += 2) begin
            put(28'h0110000 + 28'(o), 16'hBEEF);
            put(28'h00F0000 + 28'(o), 16'hBEEF);
        end

        for (int c = 0; c < 256; c++)
            for (int l = 0; l < 16; l++) begin
                chk(1'b0, c, l, fbyte(16'h0800 + c * 16 + l));
                chk(1'b1, c, l, fbyte(c * 8 + l / 2));
            end

        $display("%0d checks, %0d mismatches", checks, errs);
        if (errs == 0) $display("RESULT: PASS");
        else           $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
