//
// tb_pc98_tvram -- the guest's view of A0000-A3FFF, and the renderer's.
//
// The layout is the whole point of this bench. PC-98 keeps character codes and
// attributes in SEPARATE regions:
//
//   A0000 + idx*2   character low     A0001 + idx*2   character high
//   A2000 + idx*2   attribute
//
// The pre-pivot tvram.sv assumed char at even and attribute at odd addresses
// inside one window. Under that assumption every attribute write lands in the
// character high byte and every character high byte lands in the attribute --
// which renders as garbage that still looks like text, so it would not have
// announced itself.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_tvram;

    logic clk = 0;
    always #5 clk = ~clk;

    logic [13:0] cpu_addr = 14'h0;
    logic        cpu_wren = 1'b0;
    logic  [7:0] cpu_wdata = 8'h00;
    wire   [7:0] cpu_q;

    logic [11:0] vid_cell = 12'h0;
    wire   [7:0] vid_char_lo, vid_char_hi, vid_attr;
    logic [11:0] fil_cell = 12'h0;

    pc98_tvram dut (
        .clk(clk),
        .cpu_addr(cpu_addr), .cpu_wren(cpu_wren), .cpu_wdata(cpu_wdata),
        .cpu_q(cpu_q),
        .fil_clk(clk), .fil_cell(fil_cell),
        .fil_char_lo(vid_char_lo), .fil_char_hi(vid_char_hi),
        .vid_clk(clk), .vid_cell(vid_cell), .vid_attr(vid_attr)
    );

    int errors = 0;

    task automatic wr(input [13:0] a, input [7:0] d);
        cpu_addr = a; cpu_wdata = d; cpu_wren = 1'b1;
        @(posedge clk);
        cpu_wren = 1'b0;
        @(posedge clk);
    endtask

    task automatic rd(input [13:0] a, output [7:0] d);
        cpu_addr = a;
        @(posedge clk);
        @(posedge clk);
        d = cpu_q;
    endtask

    logic [7:0] got;

    initial begin
        $display("=== PC-98 TVRAM ===");
        @(posedge clk);

        // A whole 80x25 screen, written the way the BIOS writes it.
        for (int i = 0; i < 2000; i++) begin
            wr(14'(i*2),          8'(i & 8'hFF));          // char low
            wr(14'(i*2 + 1),      8'((i >> 8) & 8'hFF));   // char high
            wr(14'('h2000 + i*2), 8'((i * 3) & 8'hFF));    // attribute
        end

        // Read it all back through the guest port.
        for (int i = 0; i < 2000; i++) begin
            rd(14'(i*2), got);
            if (got !== 8'(i & 8'hFF)) begin
                if (errors < 4) $display("  FAIL char lo cell %0d: %02h", i, got);
                errors++;
            end
            rd(14'(i*2 + 1), got);
            if (got !== 8'((i >> 8) & 8'hFF)) begin
                if (errors < 4) $display("  FAIL char hi cell %0d: %02h", i, got);
                errors++;
            end
            rd(14'('h2000 + i*2), got);
            if (got !== 8'((i * 3) & 8'hFF)) begin
                if (errors < 4) $display("  FAIL attr cell %0d: %02h", i, got);
                errors++;
            end
        end
        $display("  guest read-back: %0d errors", errors);

        // The renderer's view: one cell index must give all three bytes at once.
        for (int i = 0; i < 2000; i += 37) begin
            vid_cell = 12'(i); fil_cell = 12'(i);
            @(posedge clk); @(posedge clk);
            if (vid_char_lo !== 8'(i & 8'hFF) ||
                vid_char_hi !== 8'((i >> 8) & 8'hFF) ||
                vid_attr    !== 8'((i * 3) & 8'hFF)) begin
                $display("  FAIL video cell %0d: %02h %02h %02h",
                         i, vid_char_hi, vid_char_lo, vid_attr);
                errors++;
            end
        end

        // The regions must not alias. Writing an attribute must not disturb the
        // character bytes of the same cell -- the exact failure the old layout
        // would have produced.
        wr(14'h0000, 8'hAA);
        wr(14'h0001, 8'hBB);
        wr(14'h2000, 8'hCC);
        rd(14'h0000, got);
        if (got !== 8'hAA) begin
            $display("  FAIL attribute write clobbered char lo (%02h)", got); errors++;
        end
        rd(14'h0001, got);
        if (got !== 8'hBB) begin
            $display("  FAIL attribute write clobbered char hi (%02h)", got); errors++;
        end
        rd(14'h2000, got);
        if (got !== 8'hCC) begin
            $display("  FAIL attribute did not stick (%02h)", got); errors++;
        end
        $display("  regions independent: char %02h %02h, attr %02h",
                 8'hAA, 8'hBB, 8'hCC);

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
