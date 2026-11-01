// tb_z86_wrtap -- z86_cache's port-F write witness (dbg_wr_*) against a
// port-F model.
//
// core_top's write watchpoint matches two taps: the chipset bus cycle
// (CPU/DMA/loader) and this cache witness -- in Turbo+cache a store to the
// cached ranges runs NO bus cycle at all, so dbg_wr_* is the only place it
// can be seen. The bench checks the witness contract the watchpoint needs:
//
//   * a cached store pulses dbg_wr_v exactly once, carrying the store's
//     guest byte address and the word flag (odd partner = base+1),
//   * uncached and I/O stores never pulse it (they ride the Wishbone),
//   * every pulsed byte reaches port F at exactly that address with the
//     stored data -- buffer-take equals SDRAM write.
//
// Build/run: scripts/sim_z86_wrtap.sh
`timescale 1ns/1ps
module tb_z86_wrtap;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;

    // ce is every edge here (the bridge's gating is exercised elsewhere);
    // what matters is the witness, not the pacing.
    logic cache_en = 1'b1;

    // write_back's store port
    logic [19:0] wr_addr = 20'h0;
    logic        wr_valid = 0;
    wire         wr_ready;
    logic [15:0] wr_data = 16'h0;
    logic        wr_word = 0, wr_io = 0;

    // Wishbone (the uncached/I/O path): one-edge ack a clock after stb.
    wire [19:1] wb_adr; wire [1:0] wb_sel; wire wb_we, wb_tga, wb_stb, wb_cyc;
    wire [15:0] wb_dat;
    logic wb_ack = 0;
    logic [4:0] wb_watches = 0;      // uncached/I/O stores that went to the bus
    logic [19:1] wb_last_adr = 0;
    logic wb_last_we = 0, wb_last_tga = 0;

    // port F model: fixed 6-clock write transaction (never read: no line
    // fills run in this bench, every tag is invalid after the flush).
    wire f_req, f_we; wire [23:0] f_addr; wire [3:0] f_len;
    wire [15:0] f_wd0, f_wd1;
    logic f_ack = 0, f_rvalid = 0, f_done = 0;

    wire busy;
    wire dbg_v; wire [19:0] dbg_a0; wire dbg_two;

    z86_cache dut (
        .clk(clk), .ce(1'b1), .reset(reset), .cache_en(cache_en), .pace(1'b0), .pace_ce(1'b0), .pace_rd_wait(2'd0), .pace_wr_wait(2'd0),
        .bios_shadow(1'b0), .bios_protect(1'b0),
        .f_req(f_req), .f_we(f_we), .f_addr(f_addr), .f_len(f_len),
        .f_wdata0(f_wd0), .f_wdata1(f_wd1),
        .f_ack(f_ack), .f_rvalid(f_rvalid), .f_rdata(16'h0), .f_done(f_done),
        .sn_v(1'b0), .sn_addr(24'h0), .sn_len(4'h0),
        .dbg_watch_a(20'h0), .dbg_sn_kills(),
        .busy(busy),
        .ld_addr(20'h0), .ld_req(1'b0), .ld_ack(), .ld_data(),
        .rd_addr(20'h0), .rd(1'b0), .rd_ready(), .rd_data(),
        .rd_io(1'b0), .rd_word(1'b0),
        .wr_addr(wr_addr), .wr_valid(wr_valid), .wr_ready(wr_ready),
        .wr_data(wr_data), .wr_word(wr_word), .wr_io(wr_io),
        .wb_adr_o(wb_adr), .wb_sel_o(wb_sel), .wb_we_o(wb_we),
        .wb_tga_o(wb_tga), .wb_dat_o(wb_dat), .wb_stb_o(wb_stb),
        .wb_cyc_o(wb_cyc), .wb_ack_i(wb_ack), .wb_dat_i(16'h0),
        .dbg_wr_v(dbg_v), .dbg_wr_a0(dbg_a0), .dbg_wr_two(dbg_two)
    );

    // ---- checkers ------------------------------------------------------
    int errors = 0;
    int pulses = 0, pf_writes = 0;
    int exp_cnt [0:19'hFFFFF];       // bytes the witness promised port F
    logic [7:0] exp_dat [0:19'hFFFFF];

    logic dbg_v_d = 0;
    always @(posedge clk) begin
        dbg_v_d <= dbg_v;
        if (dbg_v && !dbg_v_d) begin
            pulses++;
            exp_cnt[dbg_a0]++;
            exp_dat[dbg_a0] = wr_data[7:0];
            if (dbg_two) begin
                exp_cnt[dbg_a0 + 20'd1]++;
                exp_dat[dbg_a0 + 20'd1] = wr_data[15:8];
            end
        end
    end

    // Wishbone: ack + record what left by the bus (must be the uncached
    // and I/O stores only).
    always @(posedge clk) begin
        wb_ack <= wb_stb && !wb_ack;
        if (wb_stb && wb_ack) begin  // sampled at the edge the DUT takes ack
            wb_last_adr <= wb_adr; wb_last_we <= wb_we; wb_last_tga <= wb_tga;
            if (wb_we) wb_watches <= wb_watches + 5'd1;
        end
    end

    // port F: commit writes, pop the promised bytes
    always @(posedge clk) begin
        f_ack <= 0; f_rvalid <= 0; f_done <= 0;
        if (f_req && !f_ack) begin
            repeat (3) @(posedge clk);
            f_ack <= 1;
            @(posedge clk); f_ack <= 0;
            repeat (2) @(posedge clk);
            if (f_we) begin
                pf_writes++;
                if (exp_cnt[f_addr[19:0]] == 0) begin
                    errors++;
                    $display("FAIL: port F write at %05x nobody witnessed", f_addr[19:0]);
                end else if (f_wd0[7:0] !== exp_dat[f_addr[19:0]]) begin
                    errors++;
                    $display("FAIL: port F data %02x at %05x, expected %02x",
                             f_wd0[7:0], f_addr[19:0], exp_dat[f_addr[19:0]]);
                end
                exp_cnt[f_addr[19:0]]--;
                if (f_len == 4'd1) begin
                    if (exp_cnt[f_addr[19:0] + 20'd1] == 0) begin
                        errors++;
                        $display("FAIL: port F word hi at %05x nobody witnessed",
                                 f_addr[19:0] + 20'd1);
                    end else if (f_wd1[7:0] !== exp_dat[f_addr[19:0] + 20'd1]) begin
                        errors++;
                        $display("FAIL: port F word hi %02x at %05x, expected %02x",
                                 f_wd1[7:0], f_addr[19:0] + 20'd1,
                                 exp_dat[f_addr[19:0] + 20'd1]);
                    end
                    exp_cnt[f_addr[19:0] + 20'd1]--;
                end
                @(posedge clk);
            end
            f_done <= 1;
        end
    end

    // ---- driver --------------------------------------------------------
    task store(input logic [19:0] a, input logic [15:0] d,
               input logic word, input logic io);
        begin
            wr_addr = a; wr_data = d; wr_word = word; wr_io = io;
            @(posedge clk);
            wr_valid = 1;
            do @(posedge clk); while (!wr_ready);
            wr_valid = 0;
            // let the buffer/F engine/burst drain fully before the verdict
            while (busy) @(posedge clk);
            repeat (4) @(posedge clk);
        end
    endtask

    task drain;
        begin
            repeat (4) @(posedge clk);
            while (busy || f_req) @(posedge clk);
            repeat (4) @(posedge clk);
        end
    endtask

    int p0, w0, f0;
    initial begin
        for (int i = 0; i < 21'h100000; i++) exp_cnt[i] = 0;
        repeat (5) @(posedge clk);
        reset = 0;
        repeat (1200) @(posedge clk);      // S_FLUSH: one line per edge

        // 1. the sound-IRQ control itself: a word store to 0x36BAE/0x36BAF
        p0 = pulses; w0 = wb_watches;
        store(20'h36BAE, 16'hBEEF, 1'b1, 1'b0);
        if (pulses != p0 + 1) begin errors++; $display("FAIL: word 36BAE no pulse"); end
        if (wb_watches != w0) begin errors++; $display("FAIL: cached store hit the bus"); end

        // 2. the corruption target itself, odd byte
        store(20'h373A3, 16'h00A1, 1'b0, 1'b0);
        if (pulses != p0 + 2) begin errors++; $display("FAIL: byte 373A3 no pulse"); end

        // 3. word at a column-tail offset (0x30FFE/0x30FFF): one pulse, one
        //    two-word port-F burst -- the multiset checker must balance both
        //    bytes and their data
        store(20'h30FFE, 16'h1234, 1'b1, 1'b0);
        if (pulses != p0 + 3) begin errors++; $display("FAIL: straddle no pulse"); end

        // 4. uncached store: no pulse, a Wishbone write instead
        cache_en = 1'b0;
        p0 = pulses; w0 = wb_watches;
        store(20'h50000, 16'h0055, 1'b0, 1'b0);
        if (pulses != p0) begin errors++; $display("FAIL: uncached store pulsed"); end
        if (wb_watches != w0 + 1 || wb_last_adr != 20'h50000>>1 || wb_last_tga)
            begin errors++; $display("FAIL: uncached store missed the bus"); end

        // 5. I/O store (cache on): no pulse, tga on the bus
        cache_en = 1'b1;
        store(20'h00061, 16'h0036, 1'b0, 1'b1);
        if (pulses != p0) begin errors++; $display("FAIL: I/O store pulsed"); end
        if (wb_watches != w0 + 2 || !wb_last_tga)
            begin errors++; $display("FAIL: I/O store missed the bus"); end

        drain();

        // every witnessed byte landed, nothing else did
        for (int i = 0; i < 21'h100000; i++)
            if (exp_cnt[i] != 0) begin
                errors++;
                $display("FAIL: byte %05x witnessed but never written", i);
            end

        if (errors == 0)
            $display("PASS: %0d cached stores witnessed, %0d port-F writes, %0d bus stores",
                     pulses, pf_writes, wb_watches);
        else
            $display("TOTAL FAILURES: %0d", errors);
        $finish(errors != 0);
    end

    // watchdog
    initial begin
        #200000;
        $display("FAIL: timeout (pulses=%0d pf=%0d wb=%0d)", pulses, pf_writes, wb_watches);
        $finish(1);
    end
endmodule
