//
// tb_pc98_glyph_addr -- the address a cell's glyph lives at, pinned to a real
// font image.
//
// The subtle part is not the arithmetic, it is what a TVRAM cell actually
// HOLDS. It is not the raw JIS code. np2's renderer takes the cell as a word
// and computes (kc & 0x7f7f) << 4 against an internal layout that fontv98.c
// fills at 0x20000 + (ku_index << 4) + (ten - 0x20) * 0x1000, and those agree
// only if
//
//     low byte  = ku index = (JIS first byte) - 0x20      1-based
//     high byte = ten      = (JIS second byte)            raw, 0x21..0x7E
//
// Feeding the raw JIS bytes instead produces an address that is still inside
// the font and still returns structured data -- it draws a DIFFERENT REAL
// CHARACTER, with the halves taken from two different glyphs. Nothing about
// that looks like a bug from across the room, which is why it is nailed down
// here against known offsets in the actual FONT.ROM.
//
// The expected values were read out of a real font.rom: hiragana A is JIS
// 0x2422, so ku index 4 and ten 0x22, and its glyph is at 0x3C40 -- verified by
// rendering the sixteen rows and looking at them.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_glyph_addr;

    logic [7:0] char_lo, char_hi, bitac;
    logic       right_half;
    logic [3:0] line;
    wire        is_kanji;
    wire [19:0] addr;

    pc98_glyph_addr dut (
        .char_lo(char_lo), .char_hi(char_hi), .bitac(bitac),
        .right_half(right_half), .line(line),
        .is_kanji(is_kanji), .addr(addr)
    );

    int errors = 0;

    task automatic chk(input [7:0] lo, input [7:0] hi, input [7:0] ba,
                       input bit rh, input [3:0] ln,
                       input bit want_kanji, input [19:0] want_addr,
                       input string what);
        char_lo = lo; char_hi = hi; bitac = ba; right_half = rh; line = ln;
        #1;
        if (is_kanji !== want_kanji) begin
            $display("  FAIL %s: is_kanji=%0d want %0d", what, is_kanji, want_kanji);
            errors++;
        end
        if (addr !== want_addr) begin
            $display("  FAIL %s: addr=%05h want %05h", what, addr, want_addr);
            errors++;
        end
    endtask

    initial begin
        $display("=== glyph addresses ===");

        // ANK: the 8x16 set is the contiguous 0x0800-0x17FF.
        chk(8'h00, 8'h00, 8'hFF, 1'b0, 4'd0,  1'b0, 20'h00800, "ANK 00 line 0");
        chk(8'h41, 8'h00, 8'hFF, 1'b0, 4'd0,  1'b0, 20'h00C10, "ANK 41 line 0");
        chk(8'h41, 8'h00, 8'hFF, 1'b0, 4'd15, 1'b0, 20'h00C1F, "ANK 41 line 15");
        chk(8'hFF, 8'h00, 8'hFF, 1'b0, 4'd0,  1'b0, 20'h017F0, "ANK FF line 0");
        // The last ANK byte must be the last byte of the 4 KB set.
        chk(8'hFF, 8'h00, 8'hFF, 1'b0, 4'd15, 1'b0, 20'h017FF, "ANK FF line 15");

        // Kanji: hiragana A, JIS 0x2422 -> ku index 4, ten 0x22 -> 0x3C40.
        chk(8'h04, 8'h22, 8'hFF, 1'b0, 4'd0,  1'b1, 20'h03C40, "hiragana A left");
        chk(8'h04, 8'h22, 8'hFF, 1'b1, 4'd0,  1'b1, 20'h03C50, "hiragana A right");
        chk(8'h04, 8'h22, 8'hFF, 1'b0, 4'd15, 1'b1, 20'h03C4F, "hiragana A left, line 15");
        chk(8'h04, 8'h22, 8'hFF, 1'b1, 4'd15, 1'b1, 20'h03C5F, "hiragana A right, line 15");

        // First cell of the kanji region: ku 1, ten 0x21.
        chk(8'h01, 8'h21, 8'hFF, 1'b0, 4'd0,  1'b1, 20'h01820, "ku 1 ten 21");
        // Stepping ten by one steps the address by 32.
        chk(8'h01, 8'h22, 8'hFF, 1'b0, 4'd0,  1'b1, 20'h01840, "ku 1 ten 22");
        // Stepping ku by one steps it by 0xC00.
        chk(8'h02, 8'h21, 8'hFF, 1'b0, 4'd0,  1'b1, 20'h02420, "ku 2 ten 21");

        // bitac is the GDC's decision. With it clear, every cell is ANK no
        // matter what the high byte says.
        chk(8'h41, 8'h22, 8'h00, 1'b0, 4'd0,  1'b0, 20'h00C10, "bitac 00 forces ANK");

        // And the trap: feeding raw JIS bytes must NOT give the same answer as
        // the TVRAM encoding, or this bench is not testing anything.
        begin
            logic [19:0] raw_addr;
            char_lo = 8'h24; char_hi = 8'h22; bitac = 8'hFF;
            right_half = 1'b0; line = 4'd0; #1;
            raw_addr = addr;
            $display("  raw JIS 0x2422 -> %05h, TVRAM encoding -> 03C40", raw_addr);
            if (raw_addr === 20'h03C40) begin
                $display("  FAIL raw JIS and the TVRAM encoding agree -- one of them is wrong");
                errors++;
            end
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
