// tb_z86_cache_snoop -- z86_cache's snoop port (sn_v/sn_addr/sn_len) against
// external-master writes to guest RAM, the FDC-DMA coherency contract:
//
//   (a) the CPU reads a line (it is filled and now cached),
//   (b) an external master commits a write into that line -- sn_v pulses
//       with the commit, as sdram_shim's a_wr_* does for port A,
//   (c) the CPU reads again and MUST see the new data.
//
// The port-F model carries a byte-per-word memory the bench and the DUT
// share: fills read it, write-through stores land in it, and the external
// write task updates it before pulsing sn_v -- so a stale line shows up as
// a data mismatch, exactly the SuperDepth 0xA1-vs-0x38 failure on metal.
//
// Cases beyond the basic one, each a window the snoop has to close:
//   * byte write into the same line at a different offset,
//   * two-word (sn_len=1) write split across a line boundary,
//   * external commit landing in the SAME edge window as the line's fill
//     completion (tag install race), at several cycle offsets,
//   * the fetch unit's line load (ld_req/ld_ack) path,
//   * sn_v racing the CPU's own lookup edge (the kill path),
//   * back-to-back sn_v pulses a cycle apart (DMA burst cadence is slower
//     than this on metal -- if THIS passes, everything slower passes).
//
// Build/run: scripts/sim_z86_cache_snoop.sh
`timescale 1ns/1ps
module tb_z86_cache_snoop;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;

    logic cache_en = 1'b1;

    // CPU side: execute's read pulse + write-back's store port
    logic [19:0] rd_addr = 20'h0;
    logic        rd = 0;
    wire         rd_ready;
    wire [15:0]  rd_data;
    logic        rd_io = 0, rd_word = 0;

    logic [19:0] wr_addr = 20'h0;
    logic        wr_valid = 0;
    wire         wr_ready;
    logic [15:0] wr_data = 16'h0;
    logic        wr_word = 0, wr_io = 0;

    // fetch unit's line load
    logic [19:0] ld_addr = 20'h0;
    logic        ld_req = 0;
    wire         ld_ack;
    wire [127:0] ld_data;
    logic [7:0]  ld_snap [0:15];

    // Wishbone: unused cached paths only, but tie it honest
    wire [19:1] wb_adr; wire [1:0] wb_sel; wire wb_we, wb_tga, wb_stb, wb_cyc;
    wire [15:0] wb_dat;
    logic wb_ack = 0;
    always @(posedge clk) wb_ack <= wb_stb && !wb_ack;

    // port F model with the shared byte-per-word memory
    logic [7:0] mem [0:20'hFFFFF];
    wire  f_req, f_we; wire [23:0] f_addr; wire [3:0] f_len;
    wire  [15:0] f_wd0, f_wd1;
    logic f_ack = 0, f_rvalid = 0, f_done = 0;
    logic [15:0] f_rdata = 0;

    logic sn_v = 0;
    logic [23:0] sn_addr = 0;
    logic [3:0] sn_len = 0;

    wire busy;

    z86_cache dut (
        .clk(clk), .ce(1'b1), .reset(reset), .cache_en(cache_en),
        .bios_shadow(1'b0), .bios_protect(1'b0),
        .f_req(f_req), .f_we(f_we), .f_addr(f_addr), .f_len(f_len),
        .f_wdata0(f_wd0), .f_wdata1(f_wd1),
        .f_ack(f_ack), .f_rvalid(f_rvalid), .f_rdata(f_rdata), .f_done(f_done),
        .sn_v(sn_v), .sn_addr(sn_addr), .sn_len(sn_len),
        .busy(busy),
        .ld_addr(ld_addr), .ld_req(ld_req), .ld_ack(ld_ack), .ld_data(ld_data),
        .rd_addr(rd_addr), .rd(rd), .rd_ready(rd_ready), .rd_data(rd_data),
        .rd_io(rd_io), .rd_word(rd_word),
        .wr_addr(wr_addr), .wr_valid(wr_valid), .wr_ready(wr_ready),
        .wr_data(wr_data), .wr_word(wr_word), .wr_io(wr_io),
        .wb_adr_o(wb_adr), .wb_sel_o(wb_sel), .wb_we_o(wb_we),
        .wb_tga_o(wb_tga), .wb_dat_o(wb_dat), .wb_stb_o(wb_stb),
        .wb_cyc_o(wb_cyc), .wb_ack_i(wb_ack), .wb_dat_i(16'h0),
        .dbg_wr_v(), .dbg_wr_a0(), .dbg_wr_two()
    );

    // ---- port F: fills read the model, stores commit to it -------------
    // Ordering is faithful to sdram_mp: one transaction at a time, and the
    // bench never runs ext_write inside a fill's beats (metal cannot: the
    // port-A write is its own transaction before or after the fill).
    always @(posedge clk) begin
        f_ack <= 0; f_rvalid <= 0; f_done <= 0;
        if (f_req && !f_ack) begin
            repeat (2) @(posedge clk);
            f_ack <= 1;
            @(posedge clk);
            f_ack <= 0;
            if (f_we) begin
                mem[f_addr[19:0]] <= f_wd0[7:0];
                if (f_len == 4'd1) mem[f_addr[19:0] + 20'd1] <= f_wd1[7:0];
                repeat (3) @(posedge clk);
            end else begin
                for (int b = 0; b <= f_len; b++) begin
                    repeat (2) @(posedge clk);
                    f_rvalid <= 1;
                    f_rdata  <= {8'h00, mem[f_addr[19:0] + b[19:0]]};
                    @(posedge clk);
                    f_rvalid <= 0;
                end
                repeat (2) @(posedge clk);
            end
            f_done <= 1;
            @(posedge clk);
            f_done <= 0;
        end
    end

    // ---- drivers --------------------------------------------------------
    // A strict read: pulse rd, then wait until rd_ready rises fresh
    task cpu_read2(input logic [19:0] a, output logic [7:0] d);
        begin
            @(posedge clk);
            rd_addr = a; rd = 1;
            @(posedge clk);
            rd = 0;
            @(posedge clk);          // the DUT drops rd_ready by now
            while (!rd_ready) @(posedge clk);
            d = rd_data[7:0];
        end
    endtask

    // External master commits a byte (port-A write commit + sn_v pulse)
    task ext_byte(input logic [19:0] a, input logic [7:0] v);
        begin
            mem[a] = v;
            @(posedge clk);
            sn_v <= 1; sn_addr <= a; sn_len <= 4'd0;
            @(posedge clk);
            sn_v <= 0;
            @(posedge clk);
        end
    endtask

    // External master commits a word (sn_len = 1, words-1 as on port A)
    task ext_word(input logic [19:0] a, input logic [7:0] lo, input logic [7:0] hi);
        begin
            mem[a] = lo; mem[a + 20'd1] = hi;
            @(posedge clk);
            sn_v <= 1; sn_addr <= a; sn_len <= 4'd1;
            @(posedge clk);
            sn_v <= 0;
            @(posedge clk);
        end
    endtask

    task drain;
        begin
            repeat (2) @(posedge clk);
            while (busy || f_req) @(posedge clk);
            repeat (2) @(posedge clk);
        end
    endtask

    int errors = 0;
    logic [7:0] got;

    task check(input logic [19:0] a, input logic [7:0] exp,
               input string what);
        begin
            cpu_read2(a, got);
            if (got !== exp) begin
                errors++;
                $display("FAIL: %s: read %05x got %02x expected %02x",
                         what, a, got, exp);
            end
        end
    endtask

    logic ld_ack_q;
    task cpu_ld(input logic [19:0] a);
        begin
            ld_ack_q = ld_ack;
            @(posedge clk);
            ld_addr = a; ld_req = ~ld_ack_q;
            @(posedge clk);
            while (ld_ack === ld_ack_q) @(posedge clk);
            for (int i = 0; i < 16; i++) ld_snap[i] = ld_data[8*i +: 8];
            @(posedge clk);
        end
    endtask

    initial begin
        for (int i = 0; i < 21'h100000; i++) mem[i] = 8'hA1;  // the ITF pattern
        repeat (5) @(posedge clk);
        reset = 0;
        repeat (1200) @(posedge clk);      // S_FLUSH walks 1024 lines

        // ---- T1: the SuperDepth case, byte-for-byte --------------------
        // line at 0x30000 carries the stale A1 pattern; the CPU reads it
        // (fill), DMA writes 0x38 into it, the CPU reads again.
        mem[20'h30010] = 8'hA1;
        check(20'h30010, 8'hA1, "T1 prime");
        ext_byte(20'h30010, 8'h38);
        check(20'h30010, 8'h38, "T1 dma byte");

        // ---- T2: byte into the same line, different offset -------------
        check(20'h30013, 8'hA1, "T2 line still hot");
        ext_byte(20'h30013, 8'h5A);
        check(20'h30013, 8'h5A, "T2 dma byte");

        // ---- T3: two-word write split across a line boundary -----------
        check(20'h3001E, 8'hA1, "T3 prime lo");
        check(20'h30020, 8'hA1, "T3 prime hi");
        ext_word(20'h3001F, 8'h11, 8'h22);
        check(20'h3001F, 8'h11, "T3 word lo");
        check(20'h30020, 8'h22, "T3 word hi (next line)");
        check(20'h3001E, 8'hA1, "T3 untouched byte of line 1");

        // ---- T4: commit racing the fill's completion -------------------
        // sdram_mp serialises transactions, so a port-A write cannot
        // finish INSIDE a fill's beats: the reachable orders are "the
        // write ran before the fill (the fill read the new bytes)" and
        // "the write finished after f_done" -- from f_done's own edge D
        // (k=2 here: the invalidating tag write is still in flight when
        // S_FILL installs) through the install edge (k=3) to well past
        // it (k>=4, the clear lands after the install). Whatever k, the
        // line must not survive the commit: the follow-up read sees the
        // committed byte.
        for (int k = 2; k <= 8; k++) begin
            automatic logic [19:0] a = 20'h31000 + 20'(20'h100 * k);
            automatic logic [7:0]  v = 8'h40 + 8'(k);
            automatic int beats = 0;
            mem[a] = 8'hEE;                       // the fill reads EE
            // start the read and let the fill run to its last visible beat
            @(posedge clk);
            rd_addr = a; rd = 1;
            @(posedge clk);
            rd = 0;
            while (beats < 16) begin
                @(posedge clk);
                if (f_rvalid) beats++;
            end
            // B was the last beat's edge; k edges later the commit fires
            repeat (k) @(posedge clk);
            mem[a] = v;                           // port-A write commits
            sn_v <= 1; sn_addr <= a; sn_len <= 4'd0;
            @(posedge clk);
            sn_v <= 0;
            while (!rd_ready) @(posedge clk);
            // The read was ISSUED before the commit completed, so the old
            // byte is a legal answer for it; what coherence demands is
            // that the line did not survive the commit -- the follow-up
            // read must see the committed byte.
            if (rd_data[7:0] !== v && rd_data[7:0] !== 8'hEE) begin
                errors++;
                $display("FAIL: T4 k=%0d: read %02x, neither old EE nor %02x",
                         k, rd_data[7:0], v);
            end
            check(a, v, "T4 follow-up");
        end

        // ---- T5: the fetch unit's line load path ------------------------
        cpu_ld(20'h32000);
        ext_byte(20'h32008, 8'h77);
        cpu_ld(20'h32000);
        if (ld_snap[8] !== 8'h77) begin
            errors++;
            $display("FAIL: T5: ld line byte 8 got %02x expected 77",
                     ld_snap[8]);
        end

        // ---- T5b: sn_v on the very edge the ld lookup is issued ---------
        cpu_ld(20'h32800);
        mem[20'h32804] = 8'h88;
        ld_ack_q = ld_ack;
        @(posedge clk);
        ld_addr = 20'h32800; ld_req = ~ld_ack_q;
        sn_v <= 1; sn_addr <= 20'h32804; sn_len <= 4'd0;
        @(posedge clk);
        sn_v <= 0;
        while (ld_ack === ld_ack_q) @(posedge clk);
        for (int i = 0; i < 16; i++) ld_snap[i] = ld_data[8*i +: 8];
        if (ld_snap[4] !== 8'h88) begin
            errors++;
            $display("FAIL: T5b: same-edge ld snoop lost: byte 4 got %02x expected 88",
                     ld_snap[4]);
        end

        // ---- T6: sn_v on the very edge the lookup is issued -------------
        // The kill path: the snoop's tag write must beat the lookup or the
        // lookup must miss. Sweep the commit across every relative edge
        // around the read -- any offset that hands back the OLD byte is an
        // open window (the fix closes the sn_ours-edge one).
        for (int off = -3; off <= 3; off++) begin
            automatic logic [19:0] a = 20'h33000 + 20'(20'h10 * (off + 4));
            automatic logic [7:0]  fresh = 8'h90 + 8'(off + 3);
            ext_byte(a, 8'h66);                    // prime: line cached, old 66
            check(a, 8'h66, "T6 prime");
            mem[a] = fresh;
            if (off < 0) begin
                // commit first, then the read |off| edges later
                @(posedge clk);
                sn_v <= 1; sn_addr <= a; sn_len <= 4'd0;
                @(posedge clk);
                sn_v <= 0;
                repeat (-off - 1) @(posedge clk);
                rd_addr = a; rd = 1;
                @(posedge clk);
                rd = 0;
            end else if (off == 0) begin
                @(posedge clk);
                rd_addr = a; rd = 1;
                sn_v <= 1; sn_addr <= a; sn_len <= 4'd0;
                @(posedge clk);
                rd = 0; sn_v <= 0;
            end else begin
                @(posedge clk);
                rd_addr = a; rd = 1;
                @(posedge clk);
                rd = 0;
                repeat (off - 1) @(posedge clk);
                sn_v <= 1; sn_addr <= a; sn_len <= 4'd0;
                @(posedge clk);
                sn_v <= 0;
            end
            // wait out this read (it may fill) and check. off<=0: the
            // commit finished no later than the hit is judged -- the read
            // MUST see the fresh byte. off>=+1: the read was issued before
            // the commit completed, so the stale byte is a legal answer;
            // the follow-up read below must be fresh either way.
            while (!rd_ready) @(posedge clk);
            if (off <= 0 && rd_data[7:0] !== fresh) begin
                errors++;
                $display("FAIL: T6 off=%0d: snoop lost: read %02x expected %02x",
                         off, rd_data[7:0], fresh);
            end
            check(a, fresh, "T6 follow-up");
        end

        // ---- T7: back-to-back commits one cycle apart --------------------
        // Two commits on consecutive edges, second one split across lines.
        ext_byte(20'h34000, 8'h01);
        ext_byte(20'h34010, 8'h02);
        // now a pair with no gap between the pulses
        mem[20'h3401F] = 8'h03; mem[20'h34020] = 8'h04;
        @(posedge clk);
        sn_v <= 1; sn_addr <= 20'h3401F; sn_len <= 4'd1;
        @(posedge clk);
        sn_v <= 1; sn_addr <= 20'h34030; sn_len <= 4'd0;
        @(posedge clk);
        sn_v <= 0;
        repeat (3) @(posedge clk);
        check(20'h3401F, 8'h03, "T7 word lo");
        check(20'h34020, 8'h04, "T7 word hi");
        check(20'h34030, 8'hA1, "T7 second commit line");

        drain();

        if (errors == 0)
            $display("PASS: snoop invalidates every committed line");
        else
            $display("TOTAL FAILURES: %0d", errors);
        $finish(errors != 0);
    end

    // watchdog
    initial begin
        #500000;
        $display("FAIL: timeout (errors=%0d)", errors);
        $finish(1);
    end

`ifdef SNOOP_DEBUG
    // edge-trace around the snoop window: which edge each piece lands on
    always @(posedge clk) if (!reset)
        $display("%0t st=%0d kill=%b t_we=%b t_wa=%0d look_idx=%0d sn_v=%b sn_ours=%b sn_i0=%0d rd=%b rd_pend=%b rd_ready=%b hit=%b tqv=%b tqt=%0d",
                 $time, dut.st, dut.kill, dut.t_we, dut.t_wa, dut.look_idx,
                 sn_v, dut.sn_ours, dut.sn_i0, rd, dut.rd_pend, rd_ready,
                 dut.hit, dut.t_q[7], dut.t_q[6:0]);
`endif
endmodule
