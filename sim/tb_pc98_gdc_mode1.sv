//
// tb_pc98_gdc_mode1 -- the mode flip-flops behind port 0x68, pinned to the
// bytes this machine's ROM actually writes.
//
// What is checked:
//
//   * reset: mode1 = 0x98 (np2 gdc_biosreset, 24 kHz CRT), bitac = FF
//   * the bit set/reset form: dat < 0x10, bit = 1 << ((dat >> 1) & 7), value
//     in dat[0] -- and only that form; a byte with the top nibble set is not
//     a mode write at all (np2 gdc_o68's `if (!(dat & 0xf0))`)
//   * bit 5 is the only bit bitac looks at: 0x0B sets it (bitac -> 00, every
//     cell ANK), 0x0A clears it (bitac -> FF) -- and the other bits moving
//     must not disturb it
//   * the ROM's measured bytes: the ITF writes 0x0F, 0x01, 0x08, 0x07, 0x09,
//     then 0x0B around its CG-window test and 0x0A on the way out; the POST's
//     CRT-init walker writes 00/01, 04/05, 06/07, 0A/0B from its table. The
//     register's 0x98 reset pattern makes those worth replaying bit for bit:
//     bit 4 and bit 3 are SET at reset, so a "set" can be a no-op and a
//     "clear" is the one that shows.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_gdc_mode1;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic       wr  = 1'b0;
    logic [7:0] d   = 8'h00;
    logic [7:0] mode1;
    wire  [7:0] bitac;

    pc98_gdc_mode1 dut (
        .clk(clk), .rst(rst),
        .wr(wr), .d(d),
        .mode1(mode1), .bitac(bitac)
    );

    int errors = 0;

    task automatic out68(input logic [7:0] byte_, input logic [7:0] want_mode1);
        begin
            @(negedge clk);
            wr = 1'b1; d = byte_;
            @(negedge clk);
            wr = 1'b0;
            @(negedge clk);
            $display("  OUT 68h,%02h  mode1=%02h bitac=%02h", byte_, mode1, bitac);
            if (mode1 !== want_mode1) begin
                $display("  FAIL mode1 %02h want %02h", mode1, want_mode1);
                errors++;
            end
        end
    endtask

    task automatic chk(input logic [7:0] want_bitac, input string why);
        begin
            if (bitac !== want_bitac) begin
                $display("  FAIL bitac %02h want %02h (%s)", bitac, want_bitac, why);
                errors++;
            end else begin
                $display("  bitac %02h -- %s", bitac, why);
            end
        end
    endtask

    initial begin
        $display("=== GDC mode flip-flops (port 0x68) ===");

        repeat (2) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        $display("  reset: mode1=%02h bitac=%02h", mode1, bitac);
        if (mode1 !== 8'h98) begin $display("  FAIL reset mode1"); errors++; end
        chk(8'hFF, "reset is kanji mode, like np2's 0x98");

        // The ITF's own opening writes (itf.rom file 0x080: 0F, 0x13C: 01,
        // 0x1C3: 08, 0x201: 07, 0x207: 09). 0x98 resets with bits 3 and 4 set,
        // so the clear of bit 4 is the visible one.
        out68(8'h0F, 8'h98);                          // set bit 7 (already set)
        out68(8'h01, 8'h99);                          // set bit 0
        out68(8'h08, 8'h89);                          // clear bit 4
        out68(8'h07, 8'h89);                          // set bit 3 (already set)
        out68(8'h09, 8'h99);                          // set bit 4 back
        chk(8'hFF, "bits 0/3/4/7 moved, bit 5 untouched");

        // The CG-window pair the ITF runs (file 0x751 in, 0x7D5 out) and the
        // BIOS runs (FE272/FEB96/FEC6A in, FE267/FEC12/FECA1 out).
        out68(8'h0B, 8'hB9);
        chk(8'h00, "OUT 0Bh forces every cell ANK");
        out68(8'h0A, 8'h99);
        chk(8'hFF, "OUT 0Ah gives the high byte back its say");

        // Bits that are NOT bit 5, on a dirty base.
        out68(8'h03, 8'h9B);                          // set bit 1
        out68(8'h02, 8'h99);                          // clear bit 1
        out68(8'h0D, 8'hD9);                          // set bit 6
        chk(8'hFF, "bit 6 (msw accessible) is not the ANK force");
        out68(8'h0C, 8'h99);                          // clear bit 6

        // A byte with the top nibble set is not a bit write: np2's gdc_o68
        // ignores it outright.
        out68(8'hAB, 8'h99);
        out68(8'h10, 8'h99);
        chk(8'hFF, "dat >= 0x10 changes nothing");

        // And bit 5 can be set again after all of that.
        out68(8'h0B, 8'hB9);
        chk(8'h00, "re-set after a cycle of other writes");

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #100_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
