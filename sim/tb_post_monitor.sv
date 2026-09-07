//
// tb_post_monitor -- does the POST monitor record what the guest actually wrote?
//
// testB16 shipped without this and came back with SEQ FF 53 74 C3 6F, which are
// not POST codes at all -- the BIOS only ever writes 00-12, 21-25, 30-32,
// 40-43, 52, 54 and 55 -- and ADDR 00080, which is the port number rather than
// a memory address. Both were sampling bugs in the monitor, not findings about
// the guest.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_post_monitor;

    logic clk = 0, rst = 1;
    always #11.64 clk = ~clk;

    logic [19:0] address = 20'h0;
    logic  [7:0] cpu_data = 8'h00;
    logic        io_write_n = 1, memory_read_n = 1, memory_write_n = 1;

    wire  [7:0] post_code, post_prev, post_max;
    wire [63:0] post_hist;
    wire [19:0] last_mem_addr;
    wire [15:0] post_count, restart_count;

    post_monitor u_dut (
        .clk(clk), .rst(rst),
        .address(address), .cpu_data(cpu_data),
        .io_write_n(io_write_n),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .post_code(post_code), .post_prev(post_prev), .post_hist(post_hist),
        .last_mem_addr(last_mem_addr), .post_count(post_count),
        .post_max(post_max), .restart_count(restart_count)
    );

    int errors = 0;

    // A guest memory access, the thing ADDR is supposed to report.
    task automatic mem_read(input logic [19:0] a);
        address = a; memory_read_n = 0;
        repeat (4) @(posedge clk);
        memory_read_n = 1; address = 20'h0;
        repeat (2) @(posedge clk);
    endtask

    // out 0x80,al the way the bus does it: address and command up first, data
    // settling only partway through. A monitor that latches on the leading edge
    // captures the garbage that is on the bus beforehand.
    task automatic out80(input logic [7:0] v);
        address = 20'h00080;
        cpu_data = 8'hC3;          // stale bus content, deliberately wrong
        io_write_n = 0;
        repeat (2) @(posedge clk);
        cpu_data = v;              // real data settles mid-cycle
        repeat (3) @(posedge clk);
        io_write_n = 1;
        address = 20'h0;
        repeat (3) @(posedge clk);
    endtask

    // An I/O write to a DIFFERENT port whose address happens to sweep through
    // 0x0080 for one cycle on the way. testB17 recorded MAX 63, a value the
    // BIOS never writes to port 0x80, so a transient like this must not count.
    task automatic out_other_glitch(input logic [7:0] v);
        io_write_n = 0;
        address = 20'h00080;       // one cycle only, in transit
        cpu_data = v;
        @(posedge clk);
        address = 20'h00081;       // settles on the real port
        repeat (4) @(posedge clk);
        io_write_n = 1;
        address = 20'h0;
        repeat (3) @(posedge clk);
    endtask

    initial begin
        $display("=== post_monitor capture ===");
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        // A plausible POST run with memory work between the codes.
        mem_read(20'h00400);
        out80(8'h00);
        mem_read(20'h07FFE);
        out80(8'h01);
        out80(8'h02);
        mem_read(20'h12345);
        out80(8'h03);
        out80(8'h04);
        mem_read(20'h0ABCD);
        out80(8'h54);          // the memory-test failure code

        repeat (8) @(posedge clk);

        $display("  count    = %0d (want 6)", post_count);
        $display("  code     = %02h (want 54)", post_code);
        $display("  prev     = %02h (want 04)", post_prev);
        $display("  max      = %02h (want 54)", post_max);
        $display("  restarts = %0d (want 0)", restart_count);
        $display("  addr     = %05h (want 0ABCD, NOT 00080)", last_mem_addr);
        $display("  hist     = %02h %02h %02h %02h %02h %02h  (want 00 01 02 03 04 54)",
                 post_hist[47:40], post_hist[39:32], post_hist[31:24],
                 post_hist[23:16], post_hist[15:8], post_hist[7:0]);

        if (post_count !== 16'd6)      begin $display("  FAIL count");    errors++; end
        if (post_code  !== 8'h54)      begin $display("  FAIL code");     errors++; end
        if (post_prev  !== 8'h04)      begin $display("  FAIL prev");     errors++; end
        if (post_max   !== 8'h54)      begin $display("  FAIL max");      errors++; end
        if (last_mem_addr !== 20'h0ABCD) begin $display("  FAIL addr");   errors++; end
        if (post_hist[47:40] !== 8'h00 || post_hist[39:32] !== 8'h01 ||
            post_hist[31:24] !== 8'h02 || post_hist[23:16] !== 8'h03 ||
            post_hist[15:8]  !== 8'h04 || post_hist[7:0]   !== 8'h54)
            begin $display("  FAIL hist"); errors++; end

        // A one-cycle sweep through 0x0080 must be ignored entirely.
        out_other_glitch(8'h63);
        repeat (4) @(posedge clk);
        if (post_count !== 16'd6) begin
            $display("  FAIL glitch counted (count=%0d, want 6)", post_count); errors++;
        end
        if (post_max === 8'h63) begin $display("  FAIL glitch reached max"); errors++; end
        $display("  glitch ignored: count=%0d max=%02h", post_count, post_max);

        // A restart. The history holds DEPTH=8 entries, and six are used so far,
        // so these two fill it -- the freeze is only expected after that.
        out80(8'h00);          // restart #1
        out80(8'h01);          // history now full
        repeat (4) @(posedge clk);
        if (restart_count !== 16'd1) begin $display("  FAIL restart count"); errors++; end

        // From here the frozen fields must not move, while the counters do.
        out80(8'h02);
        out80(8'h00);          // restart #2
        repeat (8) @(posedge clk);
        $display("  after freeze: count=%0d restarts=%0d code=%02h (code must stay 01)",
                 post_count, restart_count, post_code);
        if (post_code !== 8'h01)      begin $display("  FAIL freeze");         errors++; end
        if (post_count !== 16'd10)    begin $display("  FAIL live count");     errors++; end
        if (restart_count !== 16'd2)  begin $display("  FAIL live restarts");  errors++; end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
