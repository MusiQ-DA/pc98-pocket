//
// tb_pc98_cgwindow -- can the guest read a glyph out of the window?
//
// The window is what lets PC-98 software draw characters itself, and a read
// that never answers hangs the guest rather than looking wrong, so this checks
// the whole path: the port writes that set the code, the prefetch they trigger,
// and what a read at A4000+k returns.
//
// The model font returns each byte's own address, so a returned byte says
// exactly where it was fetched from.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_cgwindow;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic        io_wr = 0;
    logic [15:0] io_port = 0;
    logic  [7:0] io_data = 0;
    logic [11:0] rd_addr = 0;
    wire   [7:0] rd_data;
    wire         f_req, busy;
    wire  [19:0] f_addr;
    logic        f_busy = 0, f_valid = 0;
    logic  [7:0] f_data = 0;

    pc98_cgwindow dut (
        .clk(clk), .rst(rst),
        .io_wr(io_wr), .io_port(io_port), .io_data(io_data),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data), .busy(busy)
    );

    // Model font: byte at A is A's low eight bits.
    logic [19:0] burst_addr;
    int          n;
    // Keep the LAST two, not the first two: np2 recomputes the window on every
    // port write, so writing the code in two halves legitimately fetches once
    // with the code half-written. What matters is where it ends up.
    logic [19:0] last_a, last_b;
    int          fetches = 0;

    always_ff @(posedge clk) begin
        f_valid <= 1'b0;
        if (f_req && !f_busy) begin
            burst_addr <= f_addr;
            last_a     <= last_b;
            last_b     <= f_addr;
            fetches    <= fetches + 1;
            n          <= 0;
            f_busy     <= 1'b1;
        end else if (f_busy) begin
            f_valid <= 1'b1;
            f_data  <= 8'(burst_addr[7:0] + 8'(n));
            n       <= n + 1;
            if (n == 15) f_busy <= 1'b0;
        end
    end

    int errors = 0;
    logic [7:0] got;

    task automatic port(input [15:0] p, input [7:0] d);
        io_port = p; io_data = d; io_wr = 1'b1;
        @(posedge clk);
        io_wr = 1'b0;
        @(posedge clk);
    endtask

    task automatic rd(input int k, output logic [7:0] v);
        rd_addr = 12'(k);
        @(posedge clk);
        v = rd_data;
    endtask

    initial begin
        $display("=== CG window ===");
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // Hiragana A: ku index 4, ten 0x22. np2 puts the HIGH byte on 0x00A1
        // and the LOW byte on 0x00A3, so ten goes to A1 and ku to A3.
        fetches = 0;
        port(16'h00A1, 8'h22);
        port(16'h00A3, 8'h04);
        // Both halves settled: busy must be low and STAY low.
        repeat (4) @(posedge clk);
        wait (busy == 1'b0);
        repeat (40) @(posedge clk);

        $display("  fetches %0d (a write to either code port refetches)", fetches);
        $display("  left  %05h (want 03C40)", last_a);
        $display("  right %05h (want 03C50)", last_b);
        if (last_a !== 20'h03C40) begin $display("  FAIL left addr"); errors++; end
        if (last_b !== 20'h03C50) begin $display("  FAIL right addr"); errors++; end

        // Even addresses give the left half's lines, odd the right half's.
        for (int l = 0; l < 16; l++) begin
            rd(l * 2, got);
            if (got !== 8'(20'h03C40 + l)) begin
                $display("  FAIL left line %0d: %02h want %02h",
                         l, got, 8'(20'h03C40 + l)); errors++;
            end
            rd(l * 2 + 1, got);
            if (got !== 8'(20'h03C50 + l)) begin
                $display("  FAIL right line %0d: %02h want %02h",
                         l, got, 8'(20'h03C50 + l)); errors++;
            end
        end
        $display("  sixteen lines of both halves read back correctly");

        // The window repeats every 32 bytes across the 4 KB.
        rd(0, got);
        begin
            logic [7:0] mirrored;
            rd(32, mirrored);
            if (mirrored !== got) begin
                $display("  FAIL window does not repeat every 32 bytes"); errors++;
            end
            rd(4064, mirrored);
            if (mirrored !== got) begin
                $display("  FAIL no mirror at the top of the window"); errors++;
            end
        end
        $display("  mirrors every 32 bytes");

        // An ANK code: high byte zero -> 0x0800 + code*16.
        fetches = 0;
        port(16'h00A1, 8'h00);
        port(16'h00A3, 8'h41);
        repeat (4) @(posedge clk);
        wait (busy == 1'b0);
        repeat (40) @(posedge clk);
        $display("  ANK 'A' left %05h (want 00C10)", last_a);
        if (last_a !== 20'h00C10) begin $display("  FAIL ANK addr"); errors++; end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("GLOBAL TIMEOUT"); $finish;
    end

endmodule

`default_nettype wire
