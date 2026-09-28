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
        //    Strict also holds `run` through the gap so the bus never returns
        //    to the CPU mid-walk -- check run stayed high the whole time.
        req <= 0;
        repeat (4) @(posedge clk) if (!run) bad++;
        if (bad != 0) begin
            $display("RESULT: FAIL -- run released across the req gap");
            $fatal;
        end
        req <= 1;
        wait (!read_n);
        repeat (6) @(posedge clk);
        rw_complete <= 1; @(posedge clk); rw_complete <= 0;
        wait (done);
        if (bad != 0) begin
            $display("RESULT: FAIL -- strobe on short grant in phase 3");
            $fatal;
        end
        $display("RESULT: PASS -- continuous grant does not deadlock, run held");

        // -- phase 4: a guest access drains while we hold the grant. The
        //    strobe must wait for the pending complete to clear.
        req <= 0; repeat (3) @(posedge clk);
        rw_complete <= 1;                    // foreign access still draining
        req <= 1;
        repeat (10) @(posedge clk);
        if (!read_n) begin
            $display("RESULT: FAIL -- strobed while a complete was pending");
            $fatal;
        end
        rw_complete <= 0;                    // foreigner finished
        wait (!read_n);
        repeat (6) @(posedge clk);
        rw_complete <= 1; @(posedge clk); rw_complete <= 0;
        wait (done);
        $display("RESULT: PASS -- pending complete drained before strobe");

        // -- phase 5: a foreign complete is already up the instant our strobe
        //    fires (in-flight guest access finishing as we enter). The line
        //    was never low while our strobe was up, so it must not be
        //    accepted; only the later genuine pulse may finish the access.
        //    (A complete arriving 2+ clk into the access is indistinguishable
        //    from our own on a shared line -- the held `run` grant is what
        //    keeps that case from ever happening on the real bus.)
        req <= 0; repeat (3) @(posedge clk);
        req <= 1;
        wait (!read_n);
        rw_complete <= 1;                    // lands with/at the strobe
        repeat (3) @(posedge clk);
        if (done) begin
            $display("RESULT: FAIL -- accepted a stale complete");
            $fatal;
        end
        rw_complete <= 0;
        if (done) begin
            $display("RESULT: FAIL -- accepted a stale complete");
            $fatal;
        end
        repeat (4) @(posedge clk);
        ext_rdata <= 8'h5A;
        rw_complete <= 1; @(posedge clk); rw_complete <= 0;
        wait (done);
        if (rdata !== 8'h5A) begin
            $display("RESULT: FAIL -- rdata=%h, wanted 5A", rdata);
            $fatal;
        end
        $display("RESULT: PASS -- foreign complete in window not accepted");
        $finish;
    end

    initial begin
        #20000;
        $display("RESULT: FAIL -- timeout (deadlock?)");
        $fatal;
    end
endmodule
