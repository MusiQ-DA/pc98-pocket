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
    logic        mem_wr = 0;
    logic        mem_rd = 0;
    logic [11:0] wr_addr = 0;
    logic  [7:0] wr_data = 0;
    logic [11:0] rd_addr = 0;
    wire   [7:0] rd_data;
    wire   [7:0] a9_data;
    wire         g_we;
    wire  [12:0] g_addr;
    wire   [7:0] g_wdata, g_rdata;
    wire         f_req, busy;
    wire  [19:0] f_addr;
    logic        f_busy = 0, f_valid = 0;
    logic  [7:0] f_data = 0;
    logic        ank8 = 0;

    pc98_cgwindow dut (
        .clk(clk), .rst(rst),
        .io_wr(io_wr), .io_port(io_port), .io_data(io_data),
        .mem_wr(mem_wr), .mem_rd(mem_rd), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .a9_data(a9_data), .ank8(ank8),
        .g_we(g_we), .g_addr(g_addr), .g_wdata(g_wdata), .g_rdata(g_rdata),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data), .busy(busy)
    );

    // The real user CG RAM, port B unused on this side.
    pc98_gaiji_ram u_gaiji (
        .clk(clk),
        .a_we(g_we), .a_addr(g_addr), .a_wdata(g_wdata), .a_rdata(g_rdata),
        .b_addr(13'd0), .b_rdata()
    );

    // Model font: byte at A is A's low eight bits.
    logic [19:0] burst_addr;
    int          n;
    // Keep the LAST two, not the first two: np21w recomputes the window on every
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
        rd_addr = 12'(k); mem_rd = 1'b1;
        @(posedge clk); @(posedge clk);   // the gaiji RAM reads on the clock
        v = rd_data;
        mem_rd = 1'b0;
    endtask

    // 0xA9 is a real guest read: present the code on A1/A3, the line/half on
    // A5, then watch a9_data -- the RAM registers the read on the clock, so
    // sample a cycle on.
    task automatic a9rd(output logic [7:0] v);
        @(posedge clk); @(posedge clk);
        v = a9_data;
    endtask

    initial begin
        $display("=== CG window ===");
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // Hiragana A: ku index 4, ten 0x22. np21w puts the HIGH byte on 0x00A1
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

        // The window is NOT RAM for a ROM-glyph code: np21w memtram_wr8 lets
        // a store land only on an odd offset of a gaiji code (the `writable`
        // arm). Writes to this hiragana cell are discarded, so the reads must
        // still answer the font's right half (0x3C50 fetched above).
        port(16'h00A1, 8'h22);
        port(16'h00A3, 8'h04);
        port(16'h00A5, 8'h00);
        // No wait: march straight in, the way stosb does.
        for (int k = 0; k < 16; k++) begin
            wr_addr = 12'(2 * k + 1); wr_data = 8'hA5 ^ 8'(k); mem_wr = 1'b1;
            @(posedge clk);
        end
        mem_wr = 1'b0;
        repeat (80) @(posedge clk);   // let any in-flight refill finish
        for (int k = 0; k < 16; k++) begin
            rd(2 * k + 1, got);
            if (got !== 8'h50 + 8'(k)) begin
                $display("  FAIL ROM-code store line %0d: %02h want %02h",
                         k, got, 8'h50 + 8'(k)); errors++;
            end
        end
        $display("  writes to a ROM-glyph code are discarded, per np21w");

        // A code change after that hands the window back to the font store.
        port(16'h00A1, 8'h22);
        port(16'h00A3, 8'h04);
        repeat (4) @(posedge clk);
        wait (busy == 1'b0);
        repeat (40) @(posedge clk);
        rd(1, got);
        if (got !== 8'(20'h03C50 & 20'hFF)) begin
            $display("  FAIL window did not refill after a code change: %02h", got);
            errors++;
        end
        $display("  a code change refills the window again");

        // ---- cgwindowset's folded ranges ----------------------------------
        //
        // np21w folds the a5 half-select into `high` for ku 0x0C-0x0F and
        // 0x58-0x5F, and gates it behind the dummy region for 0x09-0x0B. The
        // even offsets are the dummy region -- 0x00 -- for every code that
        // is not a normal kanji cell. Model bytes are the fetch address's
        // low eight plus the line, so left half reads read base+l and the
        // right base+0x10+l.
        //
        // ku 0x09, ten 0x22 -> file 0x1800+8*0xC00+0x40 = 0x7840/0x7850.
        port(16'h00A1, 8'h22);
        port(16'h00A3, 8'h09);
        repeat (4) @(posedge clk);
        wait (busy == 1'b0);
        repeat (40) @(posedge clk);
        port(16'h00A5, 8'h20);           // bit5 set = left half selected
        rd(0, got);
        if (got !== 8'h00) begin
            $display("  FAIL 09-0B even offset: %02h want 00", got); errors++;
        end
        rd(2 * 3 + 1, got);
        if (got !== 8'h43) begin         // left half, line 3
            $display("  FAIL 09-0B odd, left selected: %02h want 43", got);
            errors++;
        end
        port(16'h00A5, 8'h00);           // bit5 clear = right half selected
        rd(2 * 3 + 1, got);
        if (got !== 8'h00) begin         // lr -> dummy
            $display("  FAIL 09-0B odd, right selected: %02h want 00", got);
            errors++;
        end
        $display("  ku 09-0B: even is dummy, odd is left or dummy");

        // ku 0x0C, ten 0x22 -> file 0x1800+0xB*0xC00+0x40 = 0x9C40/0x9C50.
        port(16'h00A1, 8'h22);
        port(16'h00A3, 8'h0C);
        repeat (4) @(posedge clk);
        wait (busy == 1'b0);
        repeat (40) @(posedge clk);
        rd(0, got);
        if (got !== 8'h00) begin
            $display("  FAIL fold-range even offset: %02h want 00", got);
            errors++;
        end
        port(16'h00A5, 8'h20);           // left selected
        rd(2 * 5 + 1, got);
        if (got !== 8'h45) begin         // left half, line 5
            $display("  FAIL fold-range odd, left: %02h want 45", got);
            errors++;
        end
        port(16'h00A5, 8'h00);           // right selected
        rd(2 * 5 + 1, got);
        if (got !== 8'h55) begin         // right half, line 5
            $display("  FAIL fold-range odd, right: %02h want 55", got);
            errors++;
        end
        $display("  ku 0C-0F: odd follows the a5 half-select");

        // ku 0x58, ten 0x22 -> file 0x1800+0x57*0xC00+0x40 = 0x45C40/0x45C50.
        port(16'h00A1, 8'h22);
        port(16'h00A3, 8'h58);
        repeat (4) @(posedge clk);
        wait (busy == 1'b0);
        repeat (40) @(posedge clk);
        port(16'h00A5, 8'h00);           // right selected
        rd(2 * 1 + 1, got);
        if (got !== 8'h51) begin         // right half, line 1
            $display("  FAIL ku58 odd, right: %02h want 51", got); errors++;
        end
        rd(2, got);
        if (got !== 8'h00) begin
            $display("  FAIL ku58 even: %02h want 00", got); errors++;
        end
        $display("  ku 58-5F folds the same way");

        // ---- ANK in the window: even is dummy, odd is the glyph -----------
        port(16'h00A1, 8'h00);
        port(16'h00A3, 8'h41);
        repeat (4) @(posedge clk);
        wait (busy == 1'b0);
        repeat (40) @(posedge clk);
        rd(0, got);
        if (got !== 8'h00) begin
            $display("  FAIL ANK even: %02h want 00", got); errors++;
        end
        rd(2 * 4 + 1, got);
        if (got !== 8'h14) begin         // 0x0C10 + 4
            $display("  FAIL ANK odd: %02h want 14", got); errors++;
        end
        $display("  ANK in the window: even dummy, odd glyph");

        // ---- the ITF's KANJI CG RAM test, instruction for instruction ------
        //
        // itf.rom F8743-F87D5 (disassembled with scratch/dis8086.py). ES=A400,
        // DX walks 0x5620..0x567F then 0x5720..0x577F -- ku 0x56/0x57, the
        // gaiji region -- and for each code:
        //
        //   MOV AL,DL / OUT A1   MOV AL,DH / OUT A3      set the code
        //   MOV AL,00 / OUT A5   16 x (INC DI; STOSB)    write the pattern
        //   MOV AL,20 / OUT A5   16 x (INC DI; STOSB)    write it again
        //   MOV AL,00 / OUT A5   16 x (INC DI; SCASB)    read it back
        //   MOV AL,20 / OUT A5   16 x (INC DI; SCASB)    and again
        //
        // then JNZ -> MOV SI,17DEh, which is the string "KANJI CG RAM ERROR".
        // INC DI before each STOSB/SCASB means only the ODD offsets are
        // touched, four patterns FF/AA/55/00 in turn.
        //
        // The point of the sequence is the THIRD OUT A5: the guest changes the
        // line/half selector between writing and reading. Port A5 does not
        // change which character the window is looking at, so nothing it does
        // may disturb what the guest put there.
        //
        // The gaps model the 4.77 MHz CPU against the 42.95 MHz chipset: an
        // OUT is eight CPU cycles, about seventy here, so any refill an OUT
        // starts has landed long before the next instruction's bus cycle.
        for (int p = 0; p < 4; p++) begin
            logic [7:0] pat;
            pat = 8'hFF - 8'(p) * 8'h55;

            port(16'h00A1, 8'h20);           // DL: code[15:8] = ten
            port(16'h00A3, 8'h56);           // DH: code[7:0]  = ku 0x56
            repeat (70) @(posedge clk);

            port(16'h00A5, 8'h00);
            repeat (70) @(posedge clk);
            for (int k = 0; k < 16; k++) begin
                wr_addr = 12'(2 * k + 1); wr_data = pat; mem_wr = 1'b1;
                @(posedge clk);
            end
            mem_wr = 1'b0;

            port(16'h00A5, 8'h20);
            repeat (70) @(posedge clk);
            for (int k = 0; k < 16; k++) begin
                wr_addr = 12'(2 * k + 1); wr_data = pat; mem_wr = 1'b1;
                @(posedge clk);
            end
            mem_wr = 1'b0;

            port(16'h00A5, 8'h00);
            repeat (70) @(posedge clk);
            for (int k = 0; k < 16; k++) begin
                rd(2 * k + 1, got);
                if (got !== pat) begin
                    $display("  FAIL ITF pattern %02h, A5=00, line %0d: %02h",
                             pat, k, got); errors++;
                end
            end

            port(16'h00A5, 8'h20);
            repeat (70) @(posedge clk);
            for (int k = 0; k < 16; k++) begin
                rd(2 * k + 1, got);
                if (got !== pat) begin
                    $display("  FAIL ITF pattern %02h, A5=20, line %0d: %02h",
                             pat, k, got); errors++;
                end
            end
        end
        $display("  the ITF's KANJI CG RAM test reads back what it wrote");

        // ---- port 0xA9: the CG data port (np21w cgrom_oa9/cgrom_ia9) -------
        //
        // SuperDepth's loader does this: OUT A1/A3 a gaiji code, OUT A5 a
        // line+half, then sixteen pattern bytes through 0xA9 -- and later a
        // backup pass that reads them back. A glyph stored for one code must
        // survive a code change, because the game uploads 256 and THEN draws.
        port(16'h00A1, 8'h30);           // index 0x30
        port(16'h00A3, 8'h56);           // ku 0x56
        repeat (80) @(posedge clk);      // let the refill finish
        for (int l = 0; l < 16; l++) begin
            port(16'h00A5, 8'(l));       // bit5 clear = right half (lr=0x800)
            port(16'h00A9, 8'hC0 ^ 8'(l));
            port(16'h00A5, 8'h20 | 8'(l));
            port(16'h00A9, 8'hD0 ^ 8'(l));
        end
        // Read both halves back through the port.
        for (int l = 0; l < 16; l++) begin
            port(16'h00A5, 8'(l));
            a9rd(got);
            if (got !== (8'hC0 ^ 8'(l))) begin
                $display("  FAIL A9 read right line %0d: %02h", l, got); errors++;
            end
            port(16'h00A5, 8'h20 | 8'(l));
            a9rd(got);
            if (got !== (8'hD0 ^ 8'(l))) begin
                $display("  FAIL A9 read left line %0d: %02h", l, got); errors++;
            end
        end
        $display("  0xA9 writes land in the gaiji RAM and read back");

        // Persistence: select another gaiji code, come back, the glyph stays.
        port(16'h00A1, 8'h31);
        port(16'h00A3, 8'h56);
        repeat (80) @(posedge clk);
        port(16'h00A1, 8'h30);
        port(16'h00A3, 8'h56);
        repeat (80) @(posedge clk);
        port(16'h00A5, 8'h05);
        a9rd(got);
        if (got !== (8'hC0 ^ 8'h05)) begin
            $display("  FAIL gaiji glyph lost across a code change: %02h", got);
            errors++;
        end
        $display("  a stored glyph survives a code change");

        // The window sees the same bytes: odd offsets, a5-selected half.
        // A5=00 picked the right half above, so the odd-offset read returns
        // the 0xC0^n bytes.
        port(16'h00A5, 8'h00);
        rd(2 * 3 + 1, got);
        if (got !== (8'hC0 ^ 8'h03)) begin
            $display("  FAIL window read of port-stored gaiji: %02h", got);
            errors++;
        end
        // And the port sees what the window stored.
        wr_addr = 12'(2 * 7 + 1); wr_data = 8'h5A; mem_wr = 1'b1;
        @(posedge clk); mem_wr = 1'b0;
        port(16'h00A5, 8'h07);           // same half, line 7
        a9rd(got);
        if (got !== 8'h5A) begin
            $display("  FAIL A9 read of window-stored gaiji: %02h", got);
            errors++;
        end
        $display("  window and port reach the same gaiji cells");

        // A9 reads of a non-gaiji code hand back the prefetched font bytes:
        // hiragana A's right half fetched at 0x3C50, so line l is 0x50+l.
        port(16'h00A1, 8'h22);
        port(16'h00A3, 8'h04);
        repeat (80) @(posedge clk);
        port(16'h00A5, 8'h02);           // bit5 clear = right half, line 2
        a9rd(got);
        if (got !== 8'h52) begin
            $display("  FAIL A9 font read: %02h want 52", got); errors++;
        end
        $display("  0xA9 reads ROM glyphs too");

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
