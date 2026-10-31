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
//     than this on metal -- if THIS passes, everything slower passes),
//   * T12: the READ datapath's byte-lane selection after a fill -- every
//     offset 0..15 as a 1-byte read AND as a word read (the real core
//     issues rd_word=1 for every memory operand), the offset-0xF straddle,
//     consecutive odd-address reads, lanes around a write-through patch,
//     and odd re-reads after a DMA commit.
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

    // watched-line kill witness (probe slots 0x70/0x06 on metal)
    logic [19:0] dbg_watch_a = 20'h30010;
    wire  [15:0] dbg_sn_kills;

    wire busy;

    z86_cache dut (
        .clk(clk), .ce(1'b1), .reset(reset), .cache_en(cache_en), .pace(1'b0), .pace_ce(1'b0), .pace_rd_wait(2'd0), .pace_wr_wait(2'd0),
        .bios_shadow(1'b0), .bios_protect(1'b0),
        .f_req(f_req), .f_we(f_we), .f_addr(f_addr), .f_len(f_len),
        .f_wdata0(f_wd0), .f_wdata1(f_wd1),
        .f_ack(f_ack), .f_rvalid(f_rvalid), .f_rdata(f_rdata), .f_done(f_done),
        .sn_v(sn_v), .sn_addr(sn_addr), .sn_len(sn_len),
        .dbg_watch_a(dbg_watch_a), .dbg_sn_kills(dbg_sn_kills),
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

    // A strict WORD read -- the shape the real core issues for every memory
    // operand (decode.sv drives rd_word=1 unconditionally for memory): the
    // contract is rd_data[7:0] = byte at a and rd_data[15:8] = byte at a+1,
    // for even AND odd a, with the odd-offset-15 case straddling two lines.
    task cpu_read_word(input logic [19:0] a, output logic [7:0] lo,
                       output logic [7:0] hi);
        begin
            @(posedge clk);
            rd_addr = a; rd_word = 1; rd = 1;
            @(posedge clk);
            rd = 0; rd_word = 0;
            @(posedge clk);          // the DUT drops rd_ready by now
            while (!rd_ready) @(posedge clk);
            lo = rd_data[7:0];
            hi = rd_data[15:8];
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

    logic [7:0] wlo, whi;
    task check_word(input logic [19:0] a, input logic [7:0] explo,
                    input logic [7:0] exphi, input string what);
        begin
            cpu_read_word(a, wlo, whi);
            if (wlo !== explo || whi !== exphi) begin
                errors++;
                $display("FAIL: %s: word read %05x got %02x/%02x expected %02x/%02x",
                         what, a, wlo, whi, explo, exphi);
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
        // The word's SECOND line is primed first so a dropped kill shows:
        // the straddle arms a second-line kill that loses the tag-write
        // slot to the next edge's commit -- it must retry, not vanish.
        ext_byte(20'h34000, 8'h01);
        ext_byte(20'h34010, 8'h02);
        check(20'h34020, 8'hA1, "T7 prime second line");
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

        // ---- T8: the watched-line kill witness (slots 0x70/0x06) ---------
        // dbg_sn_kills counts the tag writes aimed at dbg_watch_a's line:
        // +1 for a commit into the line, +1 more when a word span's second
        // line is the watched one, +0 for a neighbour line. This is the
        // counter the metal measurement reads while the FDC streams the
        // armed buffer, so prove its arithmetic here. The witness is
        // STAGED (its facts register one edge, the count the next), so
        // settle two edges after each commit before reading.
        begin
            automatic int c0;
            dbg_watch_a = 20'h3F010;
            c0 = dbg_sn_kills;
            ext_byte(20'h3F010, 8'h55);            // the watched line
            repeat (2) @(posedge clk);
            if (dbg_sn_kills != c0 + 1) begin
                errors++;
                $display("FAIL: T8: watched-line byte: kills %0d -> %0d (want +1)",
                         c0, dbg_sn_kills);
            end
            ext_byte(20'h3F000, 8'h56);            // the previous line
            repeat (2) @(posedge clk);
            if (dbg_sn_kills != c0 + 1) begin
                errors++;
                $display("FAIL: T8: neighbour line counted: kills %0d (want %0d)",
                         dbg_sn_kills, c0 + 1);
            end
            ext_word(20'h3F00F, 8'h57, 8'h58);     // span, second line watched
            repeat (2) @(posedge clk);
            if (dbg_sn_kills != c0 + 2) begin
                errors++;
                $display("FAIL: T8: span second line: kills %0d (want %0d)",
                         dbg_sn_kills, c0 + 2);
            end
            ext_word(20'h3F020, 8'h59, 8'h5A);     // span, watched line untouched
            repeat (2) @(posedge clk);
            if (dbg_sn_kills != c0 + 2) begin
                errors++;
                $display("FAIL: T8: foreign span counted: kills %0d (want %0d)",
                         dbg_sn_kills, c0 + 2);
            end
            check(20'h3F010, 8'h58, "T8 span wrote the watched line");
        end

        // ---- T9: a kill landing on ANOTHER line's install edge ------------
        // The install's tag write and the snoop's kill share t_we/t_wa/t_wd,
        // and the FSM's assignment is the later one in the always block, so
        // a commit arriving on the fill's install edge for any line BUT the
        // filled one had its kill silently overwritten: the commit's line
        // kept its VALID tag over pre-commit data while the snoop feed (and
        // the witness counter) showed the kill as fired. That is the
        // dropped-kill window behind the metal failure -- kills counted on
        // the watched line, yet 0x373A3 still served its stale 0xA1. Sweep
        // a byte commit to a CACHED line across the fill's completion
        // edges; every offset must leave the committed line fresh.
        for (int k = 0; k <= 8; k++) begin
            automatic logic [19:0] fl = 20'h35000 + 20'(20'h100 * k);
            automatic logic [19:0] cm = 20'h36000 + 20'(20'h10 * k);
            automatic logic [7:0]  v  = 8'hC0 + 8'(k);
            automatic int beats = 0;
            check(cm, 8'hA1, "T9 prime committed line");
            @(posedge clk);                     // a read of fl: miss -> fill
            rd_addr = fl; rd = 1;
            @(posedge clk);
            rd = 0;
            while (beats < 16) begin
                @(posedge clk);
                if (f_rvalid) beats++;
            end
            // B was the last beat's edge; k edges later the commit fires
            // (k=3 is the install edge itself)
            repeat (k) @(posedge clk);
            mem[cm] = v;                        // port-A byte commits
            sn_v <= 1; sn_addr <= cm; sn_len <= 4'd0;
            @(posedge clk);
            sn_v <= 0;
            while (!rd_ready) @(posedge clk);   // the fill's read finishes
            check(cm, v, "T9 kill beside an install must land");
        end

        // ---- T10: the PREVIOUS OCCUPANT of a filled index -----------------
        // 2aff963 made the install defer its valid bit whenever any kill
        // shares its edge -- but the DATA still installs, and the index's
        // OLD tag is left VALID over the NEW line's bytes. The old line's
        // address then "hits" and serves foreign data, and no commit ever
        // kills it (nothing writes the victim). T9 checked only the
        // committed line, never the evicted occupant -- on metal the index
        // almost always holds a live line (16 KB direct-mapped under a
        // >16 KB footprint), so every deferred install corrupts whatever
        // 16 KB alias lives there. Prime a victim line, evict it with a
        // fill whose install edge carries a commit, then read the victim:
        // it must serve its OWN bytes (a refill), not the filler's.
        for (int k = 0; k <= 8; k++) begin
            automatic logic [19:0] vic = 20'h38000 + 20'(20'h10 * k);   // victim
            automatic logic [19:0] fl  = vic + 20'h4000;   // same index, 16 KB alias
            automatic logic [19:0] cm  = 20'h39000 + 20'(20'h10 * k);   // committed line
            automatic logic [7:0]  cv  = 8'hE0 + 8'(k);
            automatic int beats = 0;
            // distinct bytes everywhere: victim F0-ish, filler A1-pattern
            mem[vic] = 8'hF0 + 8'(k); mem[fl] = 8'hBA;
            check(vic, 8'hF0 + 8'(k), "T10 prime victim");
            @(posedge clk);                     // a read of fl: miss -> fill
            rd_addr = fl; rd = 1;
            @(posedge clk);
            rd = 0;
            while (beats < 16) begin
                @(posedge clk);
                if (f_rvalid) beats++;
            end
            // B was the last beat's edge; k edges later the commit fires
            // (k=3 is the install edge itself)
            repeat (k) @(posedge clk);
            mem[cm] = cv;                       // port-A byte commits
            sn_v <= 1; sn_addr <= cm; sn_len <= 4'd0;
            @(posedge clk);
            sn_v <= 0;
            while (!rd_ready) @(posedge clk);   // the filler's read lands
            // the victim must NOT serve the filler's 0xBA
            check(vic, 8'hF0 + 8'(k), "T10 evicted occupant must not lie");
            // and the filler must serve its own byte
            check(fl, 8'hBA, "T10 filler fresh");
        end

        // ---- T10b: the eviction PARKED behind a kill on the miss edge -----
        // A commit landing exactly on the miss edge takes the tag-write
        // slot, so the eviction parks and must retry -- the victim may not
        // serve the filler's bytes even then, and the commit's own line
        // must still die.
        begin
            automatic logic [19:0] vic = 20'h3A000;
            automatic logic [19:0] fl  = 20'h3E000;   // same index
            automatic logic [19:0] cm  = 20'h3B000;
            automatic int beats = 0;
            mem[vic] = 8'h9C; mem[fl] = 8'h5D; mem[cm] = 8'h6E;
            check(vic, 8'h9C, "T10b prime victim");
            check(cm,  8'h6E, "T10b prime committed line");
            // a read of fl: miss; the commit fires on the same edge
            @(posedge clk);
            rd_addr = fl; rd = 1;
            sn_v <= 1; sn_addr <= cm; sn_len <= 4'd0;
            @(posedge clk);
            rd = 0; sn_v <= 0;
            while (!rd_ready) @(posedge clk);
            check(vic, 8'h9C, "T10b parked eviction still lands");
            check(cm,  8'h6E, "T10b the kill that took the slot landed");
            check(fl,  8'h5D, "T10b filler fresh");
        end

        // ---- T11: the FETCH path through the same eviction window --------
        // The metal-shaped case: the filler is the fetch unit's line load
        // (code), the victim a data line -- or the reverse; both go through
        // the same S_CMP miss. The evicted occupant must never serve the
        // filler's bytes.
        begin
            automatic logic [19:0] vic = 20'h1C000;   // data line
            automatic logic [19:0] fl  = 20'h20000;   // code line, same index
            automatic logic [19:0] cm  = 20'h1D000;
            automatic int beats = 0;
            mem[vic] = 8'h11; mem[fl] = 8'h22; mem[cm] = 8'h33;
            check(vic, 8'h11, "T11 prime victim");
            check(cm,  8'h33, "T11 prime committed line");
            // a code load of fl misses; the commit rides the install edge
            @(posedge clk);
            ld_addr = fl; ld_req <= ~ld_req;
            @(posedge clk);
            while (beats < 16) begin
                @(posedge clk);
                if (f_rvalid) beats++;
            end
            repeat (3) @(posedge clk);          // the install edge
            mem[cm] = 8'h44;
            sn_v <= 1; sn_addr <= cm; sn_len <= 4'd0;
            @(posedge clk);
            sn_v <= 0;
            while (ld_ack !== ld_req) @(posedge clk);
            for (int i = 0; i < 16; i++) ld_snap[i] = ld_data[8*i +: 8];
            if (ld_snap[0] !== 8'h22) begin
                errors++;
                $display("FAIL: T11: ld line byte 0 got %02x expected 22",
                         ld_snap[0]);
            end
            check(vic, 8'h11, "T11 evicted data line must not lie");
            check(cm,  8'h44, "T11 committed line died");
        end

        // ---- T9b: the second line of a straddling word, same window ------
        // A word commit whose SECOND line is the cached one arms its kill
        // one edge after the pulse -- landing exactly on the install edge
        // when the pulse is on f_done's edge (k=2). The pending second-line
        // kill must not be overwritten by the install either.
        begin
            automatic logic [19:0] cm = 20'h37000;
            automatic int beats = 0;
            check(cm, 8'hA1, "T9b prime committed line");
            @(posedge clk);                     // a read of 0x37100: fill
            rd_addr = 20'h37100; rd = 1;
            @(posedge clk);
            rd = 0;
            while (beats < 16) begin
                @(posedge clk);
                if (f_rvalid) beats++;
            end
            repeat (2) @(posedge clk);          // f_done's edge: pulse here
            mem[cm - 20'd1] = 8'hD1; mem[cm] = 8'hD2;
            sn_v <= 1; sn_addr <= cm - 20'd1; sn_len <= 4'd1;
            @(posedge clk);
            sn_v <= 0;
            while (!rd_ready) @(posedge clk);
            check(cm, 8'hD2, "T9b second-line kill beside an install");
            check(cm - 20'd1, 8'hD1, "T9b first-line kill landed");
        end

        // ---- T12: byte-lane selection after a fill -----------------------
        // The READ datapath's offset mux: every existing case reads with
        // rd_word=0, but the real core issues WORD reads for every memory
        // operand (decode.sv hardwires rd_word=1), so the lo/hi lane pair
        // and the offset-0xF straddle have never been exercised. Seed two
        // lines with offset-encoded bytes, fill them, then:
        //   (a) every offset 0..15 as a 1-byte read,
        //   (b) every offset 0..14 as a word read, plus the 0xF straddle
        //       whose hi byte belongs to the NEXT line,
        //   (c) consecutive odd-address byte reads, forward and back,
        //   (d) a write-through store patched into the line, then byte and
        //       word reads around the patched offset,
        //   (e) a DMA commit at an odd offset, then odd re-reads and word
        //       reads spanning it, plus a commit to the straddle's second
        //       line re-read as a straddling word.
        begin
            // virgin addresses: T10's fl sweep cached 0x3C000+0x10k, and a
            // bare mem[] write (below) carries no sn_v, so a line any earlier
            // case left in the cache would serve its stale byte here.
            automatic logic [19:0] ln  = 20'h2C000;   // the filled line
            automatic logic [19:0] ln2 = 20'h2C010;   // its neighbour
            for (int i = 0; i < 16; i++) begin
                mem[ln  + 20'(i)] = 8'h40 + 8'(i);
                mem[ln2 + 20'(i)] = 8'h60 + 8'(i);
            end
            // prime both lines (fill), then the offset sweep
            check(ln, 8'h40, "T12 prime line");
            check(ln2, 8'h60, "T12 prime neighbour");
            for (int i = 0; i < 16; i++)
                check(ln + 20'(i), 8'h40 + 8'(i), "T12a byte at each offset");
            for (int i = 0; i < 15; i++)
                check_word(ln + 20'(i), 8'h40 + 8'(i), 8'h40 + 8'(i + 1),
                           "T12b word at each offset");
            check_word(ln + 20'hF, 8'h4F, 8'h60, "T12b straddling word");
            // (c) odd addresses, forward then back
            for (int i = 1; i < 16; i += 2)
                check(ln + 20'(i), 8'h40 + 8'(i), "T12c odd forward");
            for (int i = 15; i > 0; i -= 2)
                check(ln + 20'(i), 8'h40 + 8'(i), "T12c odd backward");
            // (d) a write-through store into the line, then lanes around it
            @(posedge clk);
            wr_addr = ln + 20'd5; wr_data = 16'h00AA; wr_word = 0;
            wr_valid = 1;
            @(posedge clk);
            while (!wr_ready) @(posedge clk);
            wr_valid = 0;
            check (ln + 20'd5, 8'hAA, "T12d patched byte");
            check_word(ln + 20'd4, 8'h44, 8'hAA, "T12d word before patch");
            check_word(ln + 20'd5, 8'hAA, 8'h46, "T12d word at patch");
            // (e) DMA commit at an odd offset, then odd re-reads + spans
            ext_byte(ln + 20'd7, 8'h77);
            check (ln + 20'd7, 8'h77, "T12e committed odd byte");
            check (ln + 20'd5, 8'hAA, "T12e patch survived the kill");
            check_word(ln + 20'd6, 8'h46, 8'h77, "T12e word before commit");
            check_word(ln + 20'd7, 8'h77, 8'h48, "T12e word at commit");
            for (int i = 15; i > 0; i -= 2)
                if (i == 7)      check(ln + 20'(i), 8'h77, "T12e odd backward");
                else if (i == 5) check(ln + 20'(i), 8'hAA, "T12e odd backward");
                else             check(ln + 20'(i), 8'h40 + 8'(i), "T12e odd backward");
            // and the straddle's second line committed: the straddling word
            // must refill and serve the fresh neighbour byte up top
            ext_byte(ln2, 8'h99);
            check_word(ln + 20'hF, 8'h4F, 8'h99, "T12e straddle after commit");
        end

        // ---- T12f: word reads on a COLD line ------------------------------
        // The first touch of a line as a word read (the fill path's own
        // serve), at an even offset, an odd offset, and the 0xF straddle
        // whose BOTH halves miss (two fills).
        begin
            automatic logic [19:0] ln  = 20'h2C100;
            automatic logic [19:0] ln2 = 20'h2C110;
            for (int i = 0; i < 16; i++) begin
                mem[ln  + 20'(i)] = 8'h80 + 8'(i);
                mem[ln2 + 20'(i)] = 8'hA0 + 8'(i);
            end
            check_word(ln + 20'd2, 8'h82, 8'h83, "T12f cold even word");
            check_word(ln + 20'd9, 8'h89, 8'h8A, "T12f cold odd word");
            check_word(ln + 20'hF, 8'h8F, 8'hA0, "T12f cold straddle word");
            check_word(ln2 + 20'd1, 8'hA1, 8'hA2, "T12f second line odd word");
        end

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
