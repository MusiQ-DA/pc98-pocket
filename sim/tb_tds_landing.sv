// tb_tds_landing -- the disk bridge must not report a dataslot READ done
// before the read's bytes are in the bridge RAM.
//
// Hardware (SD-booted SuperDepth, z86 Turbo + cache): DEPTH.EXE's file
// sectors 63-69 (LBA 298-304 of superdepth.hdm) all arrived as file sector
// 62 (LBA 297). fdd_service serves sequential reads from the prefetch half
// of the bridge RAM (words 256-511), staged while the guest drains the
// previous sector; the prefetch of LBA 298 was reported done by the APF
// while the half still held LBA 297, and so on for seven sectors. The
// game's data segment was sector 62 seven times over, its "FM board
// present" byte read 0x89, and it hung polling a YM2203 that is not there.
//
// The bridge now gates the APF's done on the landing of every word of the
// window (softcpu_fdd_bridge, "Landing gate"). This bench drives the
// bridge's firmware registers the way disk_tds.c does and plays the APF:
//
//   T1  in-order completion (data, then done): status done, data present.
//   T2  the hardware failure: the prefetch window at 0x60000400 already
//       holds "sector A"; a read of "sector B" is answered done at once and
//       its data lands 3000 clk_74a later. STATUS must stay not-done until
//       the last word is in, and must read done afterwards; the RAM then
//       holds B, never A. The early-completion witness counts it.
//   T3  partial landing: only half the words ever arrive -- never done.
//   T4  an error completion carries no data and passes straight through.
//   T5  a WRITE command (host reads the RAM) is not gated.
//   T6  an odd length (drive_sound's tail chunk): ceil(len/4) words.
//
`timescale 1ns/1ps
`default_nettype none

module tb_tds_landing;

    // clk_sys 50 MHz; clk_pico a one-in-six gated pulse of it, as in
    // softcpu_subsystem; clk_74a free-running and unrelated.
    reg clk_sys = 0;
    always #10 clk_sys = ~clk_sys;
    reg clk_74a = 0;
    always #6.734 clk_74a = ~clk_74a;
    reg [2:0] pdiv = 0;
    reg clk_pico = 0;
    always @(posedge clk_sys) begin
        pdiv     <= (pdiv == 3'd5) ? 3'd0 : pdiv + 3'd1;
        clk_pico <= (pdiv == 3'd5);
    end

    reg reset = 1;

    // ---- firmware bus ---------------------------------------------------
    reg         cpu_valid = 0;
    reg  [31:0] cpu_addr  = 0;
    reg  [31:0] cpu_wdata = 0;
    reg   [3:0] cpu_wstrb = 0;
    wire [31:0] cpu_rdata;

    // ---- APF model --------------------------------------------------------
    reg         bridge_wr = 0;
    reg  [31:0] bridge_addr = 0;
    reg  [31:0] bridge_wr_data = 0;
    wire        tds_rd, tds_wr;
    wire [15:0] tds_id;
    wire [31:0] tds_off, tds_baddr, tds_len;
    reg         tds_ack = 0;
    reg         tds_done = 0;
    reg   [2:0] tds_err = 0;
    wire [31:0] tds_dbg;

    softcpu_fdd_bridge #(.BRIDGE_ADDR(32'h60000000)) dut (
        .clk_pico (clk_pico), .clk_sys (clk_sys), .clk_74a (clk_74a),
        .reset    (reset),
        .cpu_valid (cpu_valid), .cpu_addr (cpu_addr), .cpu_wdata (cpu_wdata),
        .cpu_wstrb (cpu_wstrb), .cpu_rdata (cpu_rdata),
        .fdd_request (2'b00),
        .fdd0_disk_size (32'd0), .fdd1_disk_size (32'd0),
        .datatable_addr (), .datatable_data (), .datatable_wren (),
        .datatable_q (32'd0),
        .fdd0_rebind (1'b0), .fdd1_rebind (1'b0),
        .mgmt_addr (), .mgmt_dout (), .mgmt_wr (), .mgmt_rd (),
        .mgmt_din (16'd0),
        .bridge_wr (bridge_wr), .bridge_addr (bridge_addr),
        .bridge_wr_data (bridge_wr_data),
        .target_dataslot_read (tds_rd), .target_dataslot_write (tds_wr),
        .target_dataslot_id (tds_id), .target_dataslot_slotoffset (tds_off),
        .target_dataslot_bridgeaddr (tds_baddr),
        .target_dataslot_length (tds_len),
        .target_dataslot_ack (tds_ack), .target_dataslot_done (tds_done),
        .target_dataslot_err (tds_err),
        .bridge_rd_data_out (),
        .tds_dbg (tds_dbg)
    );

    integer errors = 0;

    // One firmware store / load: valid for two pico periods, then a gap,
    // like a picorv32 access through softcpu_subsystem's ready logic.
    task automatic fw_wr(input [7:0] a, input [31:0] d);
        @(posedge clk_pico);
        cpu_addr <= {24'h300000, a}; cpu_wdata <= d; cpu_wstrb <= 4'hF;
        cpu_valid <= 1;
        @(posedge clk_pico); @(posedge clk_pico);
        cpu_valid <= 0; cpu_wstrb <= 0;
    endtask
    task automatic fw_rd(input [7:0] a, output [31:0] d);
        @(posedge clk_pico);
        cpu_addr <= {24'h300000, a}; cpu_wstrb <= 0; cpu_valid <= 1;
        @(posedge clk_pico);
        d = cpu_rdata;
        @(posedge clk_pico);
        cpu_valid <= 0;
    endtask

    // disk_tds.c's tds_transfer_to, minus the wait.
    task automatic fw_issue(input [31:0] baddr, input [31:0] len, input [1:0] dir);
        while (apf_busy || cmd_edges != cmd_handled) @(posedge clk_74a);
        fw_wr(8'h20, 32'd3);
        fw_wr(8'h24, 32'h0004A800);
        fw_wr(8'h28, baddr);
        fw_wr(8'h2C, len);
        fw_wr(8'h38, 32'd1);
        fw_wr(8'h30, {30'd0, dir});
    endtask

    // Poll STATUS for up to `n` pico polls; returns the last status.
    task automatic fw_wait(input integer n, output [31:0] st);
        integer i;
        st = 0;
        for (i = 0; i < n; i++) begin
            fw_rd(8'h34, st);
            if (st[0]) break;
        end
    endtask

    // Byte lane 0 of bridge word w (the stub altsyncram honours the
    // bridge's 1-bit byteena_a as lane 0 only -- that lane is the probe).
    function automatic [7:0] ram_b0(input integer w);
        ram_b0 = dut.bridgeram.mem[w*4];
    endfunction

    // ---- APF behaviour knobs, read by the host process below -------------
    integer apf_mode   = 0;   // 0 data-then-done, 1 done-then-data (late)
    integer apf_late   = 0;   // clk_74a between done and the first word
    integer apf_words  = -1;  // -1: the whole window; else this many
    reg [7:0] apf_tag  = 8'h00;
    reg [2:0] apf_err  = 3'd0;

    task automatic apf_put_words(input integer nw);
        integer k;
        for (k = 0; k < nw; k++) begin
            @(posedge clk_74a);
            bridge_wr      <= 1;
            bridge_addr    <= tds_baddr + k * 4;
            bridge_wr_data <= {apf_tag ^ k[7:0], 24'h000000};
            @(posedge clk_74a);
            bridge_wr <= 0;
            repeat (3) @(posedge clk_74a);
        end
    endtask

    // The APF: on a command edge go busy (ack), then complete per apf_mode.
    // done stays high until the next command, as core_bridge_cmd holds it.
    // Command edges are caught by a plain always block and handed to the
    // host process as a sticky flag (Verilator 5.020's --timing scheduler
    // mis-orders an NBA edge detector inside an initial/forever loop).
    reg rd_d = 0, wr_d = 0;
    integer cmd_edges = 0, cmd_handled = 0;
    always @(posedge clk_74a) begin
        rd_d <= tds_rd;
        wr_d <= tds_wr;
        if ((tds_rd && !rd_d) || (tds_wr && !wr_d)) cmd_edges <= cmd_edges + 1;
    end
    reg apf_busy = 0;
    integer apf_cmds = 0;
    initial begin
        forever begin
            @(posedge clk_74a);
            if (cmd_edges != cmd_handled) begin : cmd
                integer nw;
                reg is_rd;
                is_rd = tds_rd;
                cmd_handled = cmd_handled + 1;
                apf_busy = 1;
                apf_cmds = apf_cmds + 1;
                nw = (apf_words >= 0) ? apf_words : (tds_len + 3) / 4;
                repeat (4) @(posedge clk_74a);
                tds_done <= 0;
                tds_ack  <= 1;
                repeat (40) @(posedge clk_74a);
                if (!is_rd || apf_err != 0) begin
                    tds_err  <= apf_err;
                    tds_done <= 1;
                end else if (apf_mode == 0) begin
                    apf_put_words(nw);
                    tds_err  <= 0;
                    tds_done <= 1;
                end else begin
                    tds_err  <= 0;
                    tds_done <= 1;
                    tds_ack  <= 0;
                    repeat (apf_late) @(posedge clk_74a);
                    apf_put_words(nw);
                end
                tds_ack <= 0;
                apf_busy = 0;
            end
        end
    end

    reg [31:0] st;
    integer w, bad;

    initial begin
        repeat (20) @(posedge clk_sys);
        reset = 0;
        repeat (20) @(posedge clk_sys);

        // ---- T1: in order ------------------------------------------------
        apf_mode = 0; apf_tag = 8'h10; apf_err = 0; apf_words = -1;
        fw_issue(32'h60000000, 32'd1024, 2'b01);
        fw_wait(20000, st);
        if (!st[0] || st[3:1] != 0) begin
            $display("FAIL T1: in-order read never completed (st=%h)", st); errors++;
        end
        bad = 0;
        for (w = 0; w < 256; w++) if (ram_b0(w) != (8'h10 ^ w[7:0])) bad++;
        if (bad) begin $display("FAIL T1: %0d words wrong", bad); errors++; end
        else $display("ok   T1 in-order read: done with all 256 words in");

        // ---- T2: the hardware failure ------------------------------------
        // Prefetch half holds "sector A" (tag 0x97, LBA 297's stand-in).
        apf_mode = 0; apf_tag = 8'h97;
        fw_issue(32'h60000400, 32'd1024, 2'b01);
        fw_wait(20000, st);
        if (!st[0]) begin $display("FAIL T2: staging read A never completed"); errors++; end
        // Now "sector B" (tag 0x98): done at once, data 3000 clk_74a later.
        apf_mode = 1; apf_late = 3000; apf_tag = 8'h98;
        fw_issue(32'h60000400, 32'd1024, 2'b01);
        // Wait until the APF has raised its done, then well past it: the
        // firmware's poll must still say not-done while A is in the RAM.
        wait (tds_done === 1'b1);
        repeat (400) @(posedge clk_sys);
        fw_rd(8'h34, st);
        if (st[0]) begin
            $display("FAIL T2: STATUS done while the window still held the previous sector (b0=%h)",
                     ram_b0(256));
            errors++;
        end else
            $display("ok   T2 early APF done held back (window still stale, STATUS not done)");
        fw_wait(100000, st);
        bad = 0;
        for (w = 0; w < 256; w++) if (ram_b0(256 + w) != (8'h98 ^ w[7:0])) bad++;
        if (!st[0]) begin $display("FAIL T2: late data landed but STATUS never done"); errors++; end
        else if (bad) begin
            $display("FAIL T2: STATUS done with %0d prefetch words still stale", bad); errors++;
        end else
            $display("ok   T2 done once all 256 late words landed; window holds the new sector");
        if (tds_dbg[31:16] == 16'd0) begin
            $display("FAIL T2: early-completion witness did not count (dbg=%h)", tds_dbg); errors++;
        end

        // ---- T3: partial landing never completes -----------------------
        apf_mode = 1; apf_late = 10; apf_tag = 8'h33; apf_words = 128;
        fw_issue(32'h60000000, 32'd1024, 2'b01);
        w = apf_cmds;
        fw_wait(6000, st);
        if (apf_cmds == w - 1 || !tds_done) begin
            $display("FAIL T3: the APF model never completed the command"); errors++;
        end
        if (st[0]) begin $display("FAIL T3: done with half the window missing"); errors++; end
        else $display("ok   T3 half-landed read never reports done");
        apf_words = -1;

        // ---- T4: error completion passes ---------------------------------
        apf_mode = 0; apf_err = 3'd2;
        fw_issue(32'h60000000, 32'd1024, 2'b01);
        fw_wait(20000, st);
        if (!st[0] || st[3:1] != 3'd2) begin
            $display("FAIL T4: error completion not passed through (st=%h)", st); errors++;
        end else $display("ok   T4 error completion passes with its code");
        apf_err = 0;

        // ---- T5: writes are not gated ------------------------------------
        fw_issue(32'h60000000, 32'd1024, 2'b10);
        fw_wait(20000, st);
        if (!st[0]) begin $display("FAIL T5: write command never completed"); errors++; end
        else $display("ok   T5 write completes without landing");

        // ---- T6: odd length rounds up to whole words ---------------------
        apf_mode = 0; apf_tag = 8'h55;
        fw_issue(32'h60000000, 32'd29, 2'b01);   // 8 words
        fw_wait(20000, st);
        if (!st[0]) begin $display("FAIL T6: 29-byte read never completed"); errors++; end
        else $display("ok   T6 29-byte read completes on its 8 words");

        if (errors == 0) $display("PASS tb_tds_landing");
        else             $display("FAIL tb_tds_landing (%0d)", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("FAIL tb_tds_landing: timeout");
        $finish;
    end
endmodule
`default_nettype wire
