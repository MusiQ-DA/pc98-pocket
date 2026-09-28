// tb_strict_grant -- unit check for the strict grant-stability path.
// Models address_enable_n: a stale high with a queued drop, then a real
// sustained grant. The master must NOT strobe during the stale window and
// MUST strobe once the grant has been stable for >1 cpu_ce period.
`default_nettype none
`timescale 1ns/1ps

module tb_strict_grant;
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic        req = 0, we = 0, init = 1;
    logic [19:0] addr = 20'h12345;
    logic [7:0]  wdata = 8'h00;
    logic        granted = 0, loader_busy = 0;
    logic        rw_complete = 0;
    logic [7:0]  ext_rdata = 8'hA5;

    wire run, write_n, read_n, done;
    wire [7:0] rdata;

    sdram_selftest_master #(.GUARD(200)) dut (
        .clk(clk), .rst(rst), .req(req), .we(we), .addr(addr), .wdata(wdata),
        .initilized_sdram(init), .loader_busy(loader_busy),
        .strict(1'b1),
        .bus_granted(granted), .ram_rw_complete(rw_complete),
        .ext_rdata(ext_rdata),
        .run(run), .write_n(write_n), .read_n(read_n),
        .done(done), .rdata(rdata)
    );

    // consecutive-high count on granted; any strobe at <10 is a stale hit
    int high_cnt = 0, bad = 0;
    always @(posedge clk) high_cnt <= granted ? high_cnt + 1 : 0;
    always @(negedge read_n) if (high_cnt < 10) bad++;
    always @(negedge write_n) if (high_cnt < 10) bad++;

    initial begin
        repeat (4) @(posedge clk); rst <= 0;
        repeat (4) @(posedge clk);

        // -- phase 1: stale grant. granted=1 for 3 clk then the queued drop.
        req <= 1; @(posedge clk);
        granted <= 1;
        repeat (3) @(posedge clk);
        granted <= 0;
        repeat (12) @(posedge clk);

        // -- phase 2: real sustained grant.
        granted <= 1;
        wait (!read_n);
        repeat (6) @(posedge clk);
        rw_complete <= 1; @(posedge clk); rw_complete <= 0;
        wait (done);
        @(posedge clk);

        if (bad != 0) begin
            $display("RESULT: FAIL -- %0d strobe(s) on an unsettled grant", bad);
            $fatal;
        end
        if (rdata !== 8'hA5) begin
            $display("RESULT: FAIL -- rdata=%h", rdata);
            $fatal;
        end
        $display("RESULT: PASS -- no strobe during stale window, read completed");

        // -- phase 3: aen never drops across the req gap; must not deadlock.
        req <= 0; repeat (3) @(posedge clk);
        req <= 1;
        wait (!read_n);
        repeat (6) @(posedge clk);
        rw_complete <= 1; @(posedge clk); rw_complete <= 0;
        wait (done);
        if (bad != 0) begin
            $display("RESULT: FAIL -- strobe on short grant in phase 3");
            $fatal;
        end
        $display("RESULT: PASS -- continuous grant does not deadlock");
        $finish;
    end

    initial begin
        #20000;
        $display("RESULT: FAIL -- timeout (deadlock?)");
        $fatal;
    end
endmodule
