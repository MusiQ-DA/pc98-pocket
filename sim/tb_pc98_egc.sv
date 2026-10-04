//
// tb_pc98_egc -- the charger's engine, against np21w's arithmetic.
//
// pc98_egc's registers are np21w io/egc.c; the engine that consumes them is
// mem/memegc.c's egc_writebyte/egc_readbyte. This bench drives the sequencer
// with the EGC on and checks, per plane, the bytes that land in memory:
//
//   * the reset state (access FFF0, mask FFFF) writes every plane
//   * ope 0x0000 replicates the written byte to every plane
//   * the access register's SET bits take planes out of the write
//   * the mask register RMWs only its set bits
//   * ope 0x1000 with fgbg 0x4000 fills the foreground colour's planes
//   * a read latches the source; ope 0x0800 code 0xF0 (src) blits it -- the
//     aligned REP MOVSW case, the reason the source latch exists
//   * ope 9:8 = 0b10 loads the pattern registers from the planes on a write
//   * the shift pipeline: a misaligned read->write stream (memegc.c's
//     upr_sub/upl_sub/dnr_sub cases, the first/last byte masks, leng's
//     run restart, and the srcbit/dstbit >= 8 byte-skip paths), plus the
//     write-push input form (ope 0x400)
//   * the access page banks every plane address through pc98_gvram_plane1
//     with mem_page1 up, and a plain access with the page bit set lands on
//     one plane only
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_egc;

    localparam real HALF_NS = 500.0 / 42.954545;
    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic        reset = 1'b1;
    logic        cpu_gvram = 1'b0, cpu_rd = 1'b0, cpu_wr = 1'b0;
    logic [19:0] cpu_addr = 20'h0;
    logic [7:0]  cpu_wdata = 8'h00;
    logic        cpu_word = 1'b0;
    logic [7:0]  cpu_wdata_hi = 8'h00;
    wire  [7:0]  cpu_rdata;
    wire  [7:0]  cpu_rdata_hi;
    wire         cpu_ready;

    logic        grcg_active = 1'b0, grcg_rmw = 1'b0;
    logic [3:0]  grcg_mask = 4'h0;
    logic [7:0]  grcg_tile [0:3];
    logic        analog_mode = 1'b1;

    wire [19:0] mem_addr;
    wire [7:0]  mem_wdata;
    wire        mem_rd, mem_wr;
    logic [7:0] mem_rdata;
    logic       mem_done;
    logic       completed = 1'b0;
    wire        mem_ready = (mem_rd | mem_wr) ? completed : 1'b1;

    logic       egc_active = 1'b0;
    logic       egc_wr = 1'b0;
    logic [3:0] egc_rg = 4'h0;
    logic [7:0] egc_d = 8'h00;
    logic       access_page = 1'b0;
    wire        mem_page1;

    pc98_gvram_seq dut (
        .clk(clk), .reset(reset),
        .cpu_gvram(cpu_gvram), .cpu_rd(cpu_rd), .cpu_wr(cpu_wr),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_word(cpu_word), .cpu_wdata_hi(cpu_wdata_hi),
        .cpu_rdata_hi(cpu_rdata_hi),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .svc_req(1'b0), .svc_we(1'b0), .svc_raw(1'b0), .svc_addr(20'h0),
        .svc_wdata(8'h00), .svc_done(), .svc_rdata(), .dbg(), .dbg2(),
        .grcg_active(grcg_active), .grcg_rmw(grcg_rmw),
        .grcg_mask(grcg_mask), .grcg_tile(grcg_tile),
        .analog_mode(analog_mode),
        .access_page(access_page), .mem_page1(mem_page1),
        .egc_active(egc_active), .egc_wr(egc_wr),
        .egc_rg(egc_rg), .egc_d(egc_d),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr),
        .mem_rdata(mem_rdata), .mem_done(mem_done), .mem_ready(mem_ready)
    );

    task automatic egc_set(input [3:0] rg, input [7:0] v);
        begin
            @(negedge clk); egc_wr = 1'b1; egc_rg = rg; egc_d = v;
            @(negedge clk); egc_wr = 1'b0;
        end
    endtask

    // ---- memory: keyed by the FULL address the RAM would bank ----------
    logic [7:0] store [int];
    int         LAT = 2;
    int         lat_n = 0;
    logic       busy = 1'b0;

    function automatic int banked(input [19:0] a);
        // What RAM.sv turns (mem_addr, mem_page1) into.
        banked = mem_page1 ? (24'h600000 + {7'b0, a[16:0]}) : a;
    endfunction

    always_ff @(posedge clk) begin
        completed <= 1'b0;
        if (busy) begin
            if (lat_n == LAT) begin
                busy      <= 1'b0;
                completed <= 1'b1;
                // blocking: newer Verilator refuses a nonblocking write into
                // an associative array (IEEE 1800-2023 6.21), and the store
                // is a pure behavioural model either way.
                if (mem_wr) store[banked(mem_addr)] = mem_wdata;
                else        mem_rdata <= store[banked(mem_addr)];
            end
            lat_n <= lat_n + 1;
        end else if (mem_rd | mem_wr) begin
            busy  <= 1'b1;
            lat_n <= 0;
        end
        if (mem_done !== 1'bx) ; // (done follows below)
    end

    always_comb mem_done = completed & (mem_rd | mem_wr);

    // ---- one guest access, held until ready ---------------------------
    task automatic g_wr(input [19:0] a, input [7:0] v);
        begin
            @(negedge clk);
            cpu_gvram = 1'b1; cpu_addr = a; cpu_wdata = v; cpu_wr = 1'b1;
            @(posedge cpu_ready);
            @(negedge clk);
            cpu_wr = 1'b0; cpu_gvram = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic g_wwr(input [19:0] a, input [15:0] v);
        begin
            @(negedge clk);
            cpu_gvram = 1'b1; cpu_addr = a; cpu_word = 1'b1;
            cpu_wdata = v[7:0]; cpu_wdata_hi = v[15:8]; cpu_wr = 1'b1;
            @(posedge cpu_ready);
            @(negedge clk);
            cpu_wr = 1'b0; cpu_gvram = 1'b0; cpu_word = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic g_rd(input [19:0] a, output [7:0] v);
        begin
            @(negedge clk);
            cpu_gvram = 1'b1; cpu_addr = a; cpu_rd = 1'b1;
            @(posedge cpu_ready);
            v = cpu_rdata;
            @(negedge clk);
            cpu_rd = 1'b0; cpu_gvram = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    // Plane p of window address a, page zero, in the bench's own keying.
    function automatic int p0(input [19:0] a, input [1:0] p);
        // Plane p at A8000 + p*0x8000, plane E at E0000 (pc98_sdram_map).
        p0 = (p == 2'd3) ? (20'hE0000 + a[14:0])
                         : (20'hA8000 + (20'(p) << 15) + a[14:0]);
    endfunction

    int errors = 0;
    task automatic want(input string what, input int got, input int exp);
        if (got !== exp) begin
            $display("FAIL %-40s got %02x, want %02x", what, got, exp);
            errors++;
        end else
            $display("ok   %-40s %02x", what, got);
    endtask

    logic [7:0] rdb;

    // ---- the shift-pipeline vectors, from np21w's memegc.c --------------
    // srcA: eight bytes per plane of distinct data. expX[i][p] is what
    // np21w's egc_writebyte lands in plane p on iteration i; retA is the
    // produced byte the READ returns (unmasked -- the mask applies on the
    // write). wdE is the byte stream the write-push case pushes.
    logic [7:0] srcA [0:7][0:3] = '{
        '{8'h9c, 8'h35, 8'h66, 8'ha7}, '{8'h12, 8'h48, 8'h80, 8'hf0},
        '{8'haa, 8'h55, 8'h33, 8'hcc}, '{8'h01, 8'h23, 8'h45, 8'h67},
        '{8'h89, 8'hab, 8'hcd, 8'hef}, '{8'h70, 8'h0e, 8'hd2, 8'h5a},
        '{8'hff, 8'h00, 8'h81, 8'h7e}, '{8'h11, 8'h22, 8'h44, 8'h88}};
    logic [7:0] retA [0:7] = '{8'h13, 8'h82, 8'h55, 8'h40,
                               8'h31, 8'h2e, 8'h1f, 8'he2};
    logic [7:0] rdbA [0:7];
    logic [7:0] expA [0:7][0:3] = '{
        '{8'h13, 8'h06, 8'h0c, 8'h14}, '{8'h82, 8'ha9, 8'hd0, 8'hfe},
        '{8'h55, 8'h0a, 8'h06, 8'h19}, '{8'h40, 8'ha4, 8'h68, 8'h8c},
        '{8'h31, 8'h75, 8'hb9, 8'hfd}, '{8'h20, 8'h60, 8'ha0, 8'he0},
        '{8'h1f, 8'h00, 8'h10, 8'h0f}, '{8'he2, 8'h04, 8'h28, 8'hd1}};
    logic [7:0] expB [0:7][0:3] = '{
        '{8'h00, 8'h00, 8'h00, 8'h00}, '{8'h20, 8'h2a, 8'h34, 8'h3f},
        '{8'h95, 8'h42, 8'h01, 8'h86}, '{8'h50, 8'ha9, 8'h9a, 8'h63},
        '{8'h0c, 8'h1d, 8'h2e, 8'h3f}, '{8'h40, 8'h40, 8'h40, 8'h40},
        '{8'h00, 8'h00, 8'h00, 8'h00}, '{8'h38, 8'h01, 8'h0a, 8'h34}};
    logic [7:0] expD [0:7][0:3] = '{
        '{8'h00, 8'h00, 8'h00, 8'h00}, '{8'h88, 8'h10, 8'h20, 8'h40},
        '{8'hf8, 8'h01, 8'h0a, 8'hf4}, '{8'h87, 8'h70, 8'h94, 8'hd3},
        '{8'h4b, 8'h58, 8'h6e, 8'h7a}, '{8'h04, 8'h05, 8'h06, 8'h07},
        '{8'h50, 8'ha8, 8'h98, 8'h60}, '{8'h95, 8'h42, 8'h01, 8'h86}};
    logic [7:0] expE [0:5][0:3] = '{
        '{8'h13, 8'h13, 8'h13, 8'h13}, '{8'h82, 8'h82, 8'h82, 8'h82},
        '{8'h55, 8'h55, 8'h55, 8'h55}, '{8'h40, 8'h40, 8'h40, 8'h40},
        '{8'h31, 8'h31, 8'h31, 8'h31}, '{8'h20, 8'h20, 8'h20, 8'h20}};
    logic [7:0] wdE [0:5] = '{8'h9c, 8'h12, 8'haa, 8'h01, 8'h89, 8'h70};
    // expF: np21w rev106 suppresses a byte event at dstbit 9..15 FOREVER --
    // the front-end guard `(UINT)(8 - dstbit)` wraps to a huge count, so the
    // stack check fails every time and the *_sub's `dstbit >= 8` decrement
    // is unreachable (it fires only for dstbit == 8, where 8-8 slips under
    // the guard). The old x86 asm strided dstbit -= 8 instead; this table
    // pins np21w's actual behaviour: nothing lands, ever.
    logic [7:0] expF [0:7][0:3] = '{
        '{8'h00, 8'h00, 8'h00, 8'h00}, '{8'h00, 8'h00, 8'h00, 8'h00},
        '{8'h00, 8'h00, 8'h00, 8'h00}, '{8'h00, 8'h00, 8'h00, 8'h00},
        '{8'h00, 8'h00, 8'h00, 8'h00}, '{8'h00, 8'h00, 8'h00, 8'h00},
        '{8'h00, 8'h00, 8'h00, 8'h00}, '{8'h00, 8'h00, 8'h00, 8'h00}};
    logic [7:0] expG [0:7][0:3] = '{
        '{8'h00, 8'h00, 8'h00, 8'h00}, '{8'h13, 8'h06, 8'h0c, 8'h14},
        '{8'h82, 8'ha9, 8'hd0, 8'hfe}, '{8'h55, 8'h0a, 8'h06, 8'h19},
        '{8'h40, 8'ha4, 8'h68, 8'h8c}, '{8'h31, 8'h75, 8'hb9, 8'hfd},
        '{8'h20, 8'h60, 8'ha0, 8'he0}, '{8'h00, 8'h00, 8'h00, 8'h00}};

    initial begin
        grcg_tile[0] = 8'h00; grcg_tile[1] = 8'h00;
        grcg_tile[2] = 8'h00; grcg_tile[3] = 8'h00;

        repeat (4) @(negedge clk);
        reset = 1'b0;
        repeat (2) @(negedge clk);

        // np21w i286c/cpumem.c vacctbl: the EGC intercepts the graphics
        // windows only while the GRCG arm (modereg[7]) is also set -- the
        // engine-enable bit alone leaves rows 0x02/0x03 as plain VRAM.
        grcg_active = 1'b1;
        egc_active = 1'b1;

        // ---- 1. reset state: mask FFFF, access FFF0, ope 0000 ----------
        // Every plane's byte at offset 0x40 becomes the written byte.
        g_wr(20'hA8040, 8'hA5);
        want("reset state: plane B", store[p0(20'hA8040, 2'd0)], 8'hA5);
        want("reset state: plane R", store[p0(20'hA8040, 2'd1)], 8'hA5);
        want("reset state: plane G", store[p0(20'hA8040, 2'd2)], 8'hA5);
        want("reset state: plane E", store[p0(20'hA8040, 2'd3)], 8'hA5);

        // ---- 2. the access register's SET bits skip the write ----------
        // 0xFFFE: only plane B is written; the others keep their bytes.
        egc_set(4'h0, 8'hFE);            // access low  (0x4A0)
        egc_set(4'h1, 8'hFF);            // access high (0x4A1)
        g_wr(20'hA8040, 8'h3C);
        want("access FFFE: plane B written", store[p0(20'hA8040, 2'd0)], 8'h3C);
        want("access FFFE: plane R kept",   store[p0(20'hA8040, 2'd1)], 8'hA5);
        want("access FFFE: plane E kept",   store[p0(20'hA8040, 2'd3)], 8'hA5);
        egc_set(4'h0, 8'hF0);            // back to reset

        // ---- 3. the mask RMWs only its set bits ------------------------
        egc_set(4'h8, 8'h0F);            // mask low  (0x4A8)
        egc_set(4'h9, 8'h0F);            // mask high
        g_wr(20'hA8041, 8'h5A);
        want("mask 0F0F: (0 & ~0F) | (5A & 0F)",
             store[p0(20'hA8041, 2'd0)], 8'h0A);
        egc_set(4'h8, 8'hFF); egc_set(4'h9, 8'hFF);

        // ---- 4. ope 0x1000 with fgbg 0x4000: the foreground colour ----
        // fg colour 0b0101 lights planes B and G: they fill with FF where
        // the colour bit is set and 00 where it is not; R and E get 00.
        egc_set(4'h6, 8'h05);            // fg colour 0x4A6
        egc_set(4'h3, 8'h40);            // fgbg high = 0x4000 (0x4A3)
        egc_set(4'h2, 8'h00);            // fgbg low
        egc_set(4'h5, 8'h10);            // ope high: 0x1000 (0x4A5)
        egc_set(4'h4, 8'h00);            // ope low
        g_wr(20'hA8080, 8'h77);
        want("fg fill: plane B FF", store[p0(20'hA8080, 2'd0)], 8'hFF);
        want("fg fill: plane R 00", store[p0(20'hA8080, 2'd1)], 8'h00);
        want("fg fill: plane G FF", store[p0(20'hA8080, 2'd2)], 8'hFF);
        want("fg fill: plane E 00", store[p0(20'hA8080, 2'd3)], 8'h00);

        // ---- 5. the source latch and the aligned blit ------------------
        // Seed four distinct plane bytes, read them (latching the source),
        // then write elsewhere with ope 0x0800 code 0xF0 (K_S: src).
        store[p0(20'hA8100, 2'd0)] = 8'h11;
        store[p0(20'hA8100, 2'd1)] = 8'h22;
        store[p0(20'hA8100, 2'd2)] = 8'h44;
        store[p0(20'hA8100, 2'd3)] = 8'h88;
        g_rd(20'hA8100, rdb);            // the read also latches
        egc_set(4'h5, 8'h08);            // ope high: 0x0800
        egc_set(4'h4, 8'hF0);            // ope code F0 = src
        g_wr(20'hA8180, 8'h00);
        want("blit: plane B",  store[p0(20'hA8180, 2'd0)], 8'h11);
        want("blit: plane R",  store[p0(20'hA8180, 2'd1)], 8'h22);
        want("blit: plane G",  store[p0(20'hA8180, 2'd2)], 8'h44);
        want("blit: plane E",  store[p0(20'hA8180, 2'd3)], 8'h88);

        // ---- 6. the read's answer is fgbg 9:8's plane ------------------
        // fgbg bits 9:8 = 0b01: plane R answers.
        egc_set(4'h3, 8'h01);            // fgbg bits 9:8 = 01 -> plane R
        g_rd(20'hA8100, rdb);
        want("read answers plane R", rdb, 8'h22);
        egc_set(4'h3, 8'h00);

        // ---- 7. ope 9:8 = 0b10 loads the pattern registers on write ---
        // A write at a fresh offset with ope 0x0200 first reads every plane
        // into patreg, then does the (masked, replicated-value) write.
        egc_set(4'h5, 8'h02);            // ope = 0x0200
        egc_set(4'h4, 8'h00);
        store[p0(20'hA8200, 2'd0)] = 8'hC3;
        g_wr(20'hA8200, 8'h5A);          // value written; patreg takes C3..
        want("pat load write: plane B value", store[p0(20'hA8200, 2'd0)], 8'h5A);
        // Now a raster write through the pattern: ope 0x0800, code 0x88 is
        // the general engine with minterms 7 and 3 set -- np21w's table
        // order, P.S.D | P.~S.D, which is P.~D... no: both terms need D, so
        // it is P AND D with the source irrelevant. The constants here:
        // patreg B holds C3 (loaded above), destination 5A (this test's
        // value), and the source latch would matter only on other codes.
        //   result = (C3 & 11 & 5A) | (C3 & EE & 5A) = (C3 & 5A) = 42
        egc_set(4'h5, 8'h08); egc_set(4'h4, 8'h88);
        g_wr(20'hA8200, 8'h00);
        want("pat-raster B = C3 & (S|~S) & 5A", store[p0(20'hA8200, 2'd0)], 8'h42);
        want("pat-raster R (no pattern)",        store[p0(20'hA8200, 2'd1)], 8'h00);
        want("pat-raster G (no pattern)",        store[p0(20'hA8200, 2'd2)], 8'h00);
        want("pat-raster E (no pattern)",        store[p0(20'hA8200, 2'd3)], 8'h00);

        // ---- 8. the shift pipeline, misaligned copies -------------------
        // The golden bytes below come from np21w's mem/memegc.c run as a
        // reference model. Eight distinct bytes per plane seed the source,
        // then a REP MOVSB-style stream alternates read + write one byte at
        // a time -- ope 0x08F0 (the raster op's src code) throughout.
        egc_set(4'h3, 8'h00); egc_set(4'h2, 8'hFF);   // fgbg 00FF (plane B answers)
        egc_set(4'h5, 8'h08); egc_set(4'h4, 8'hF0);   // ope 0x08F0
        for (int i = 0; i < 8; i++) begin
            store[p0(20'hA8100 + 20'(i), 2'd0)] = srcA[i][0];
            store[p0(20'hA8100 + 20'(i), 2'd1)] = srcA[i][1];
            store[p0(20'hA8100 + 20'(i), 2'd2)] = srcA[i][2];
            store[p0(20'hA8100 + 20'(i), 2'd3)] = srcA[i][3];
        end

        // A. sft 0x0030: direction up, dstbit 3, srcbit 0 (upr_sub). leng
        //    0x0027 arms a 40-bit run: masks 1F, FF, FF, FF, FF, E0; the
        //    sixth write is the run's last byte, then remain hits zero and
        //    the pipeline re-arms for the next 40 bits.
        egc_set(4'hC, 8'h30); egc_set(4'hD, 8'h00);   // sft
        egc_set(4'hE, 8'h27); egc_set(4'hF, 8'h00);   // leng
        for (int i = 0; i < 8; i++) begin
            g_rd(20'hA8100 + 20'(i), rdb);
            rdbA[i] = rdb;                  // the produced byte, unmasked
            g_wr(20'hA8280 + 20'(i), 8'h00);
        end
        for (int i = 0; i < 8; i++)
            want($sformatf("A rd byte %0d", i), rdbA[i], retA[i]);
        for (int i = 0; i < 8; i++)
            for (int p = 0; p < 4; p++)
                want($sformatf("A dst[%0d] plane %0d", i, p),
                     store[p0(20'hA8280 + 20'(i), 2'(p))], expA[i][p]);

        // B. sft 0x0025: direction up, dstbit 2, srcbit 5 (upl_sub) -- the
        //    head byte slides LEFT into the tail of the one after it; the
        //    first access's stack is still under the byte's need, so it is
        //    suppressed entirely (mask 00, nothing lands).
        egc_set(4'hC, 8'h25); egc_set(4'hD, 8'h00);
        egc_set(4'hE, 8'h1F); egc_set(4'hF, 8'h00);
        for (int i = 0; i < 8; i++) begin
            g_rd(20'hA8100 + 20'(i), rdb);
            g_wr(20'hA8300 + 20'(i), 8'h00);
        end
        for (int i = 0; i < 8; i++)
            for (int p = 0; p < 4; p++)
                want($sformatf("B dst[%0d] plane %0d", i, p),
                     store[p0(20'hA8300 + 20'(i), 2'(p))], expB[i][p]);

        // D. down direction, sft 0x1030 (dnr_sub): the same funnel read
        //    backwards -- a REP MOVSB with the direction flag set, source
        //    and destination both walking to lower addresses.
        egc_set(4'hC, 8'h30); egc_set(4'hD, 8'h10);
        egc_set(4'hE, 8'h27); egc_set(4'hF, 8'h00);
        for (int i = 0; i < 8; i++) begin
            g_rd(20'hA8108 - 20'(i), rdb);
            g_wr(20'hA8408 - 20'(i), 8'h00);
        end
        for (int i = 0; i < 8; i++)
            for (int p = 0; p < 4; p++)
                want($sformatf("D dst[%0d] plane %0d", i, p),
                     store[p0(20'hA8408 - 20'(i), 2'(p))], expD[i][p]);

        // E. the write-push input form: ope 0x0CF0 keeps the raster op but
        //    sets 0x400, so each WRITE byte is pushed into the queue and the
        //    shifted product is written -- all four planes take the same
        //    byte in, so the shifted bytes come out equal.
        egc_set(4'h5, 8'h0C);                         // ope 0x0CF0
        egc_set(4'hC, 8'h30); egc_set(4'hD, 8'h00);
        egc_set(4'hE, 8'h27); egc_set(4'hF, 8'h00);
        for (int i = 0; i < 6; i++)
            g_wr(20'hA8500 + 20'(i), wdE[i]);
        for (int i = 0; i < 6; i++)
            for (int p = 0; p < 4; p++)
                want($sformatf("E dst[%0d] plane %0d", i, p),
                     store[p0(20'hA8500 + 20'(i), 2'(p))], expE[i][p]);
        egc_set(4'h5, 8'h08);                         // back to 0x08F0

        // F. dstbit 9..15: sft 0x00B0 starts the run eleven bits into the
        //    destination -- the x86 asm strides one whole byte per event
        //    (dstbit -= 8 with a word-wide mask clear), so the first access
        //    writes nothing and the second lands the first byte.
        egc_set(4'hC, 8'hB0); egc_set(4'hD, 8'h00);
        egc_set(4'hE, 8'h17); egc_set(4'hF, 8'h00);   // leng 24 bits
        for (int i = 0; i < 8; i++) begin
            g_rd(20'hA8100 + 20'(i), rdb);
            g_wr(20'hA8600 + 20'(i), 8'h00);
        end
        for (int i = 0; i < 8; i++)
            for (int p = 0; p < 4; p++)
                want($sformatf("F dst[%0d] plane %0d", i, p),
                     store[p0(20'hA8600 + 20'(i), 2'(p))], expF[i][p]);

        // G. srcbit >= 8: sft 0x0038 spends the first input byte as eight
        //    bits of lead-in credit, so the stream starts one byte later.
        egc_set(4'hC, 8'h38); egc_set(4'hD, 8'h00);
        egc_set(4'hE, 8'h27); egc_set(4'hF, 8'h00);
        for (int i = 0; i < 8; i++) begin
            g_rd(20'hA8100 + 20'(i), rdb);
            g_wr(20'hA8700 + 20'(i), 8'h00);
        end
        for (int i = 0; i < 8; i++)
            for (int p = 0; p < 4; p++)
                want($sformatf("G dst[%0d] plane %0d", i, p),
                     store[p0(20'hA8700 + 20'(i), 2'(p))], expG[i][p]);

        // ---- W. word accesses: the two-lane shiftinput_incw/decw ------
        // A word is ONE input accounting and ONE stack check for both
        // lanes (egcsftw_*), not two byte events. These cases pin the
        // differences the byte model gets wrong.
        egc_set(4'h5, 8'h0C);                         // ope 0x0CF0
        for (int p = 0; p < 4; p++) begin
            store[p0(20'hA8900, 2'(p))] = 8'h5A;
            store[p0(20'hA8901, 2'(p))] = 8'h5A;
            store[p0(20'hA8920, 2'(p))] = 8'h5A;
            store[p0(20'hA8921, 2'(p))] = 8'h5A;
            store[p0(20'hA8940, 2'(p))] = 8'h5A;
            store[p0(20'hA8941, 2'(p))] = 8'h5A;
            store[p0(20'hA8960, 2'(p))] = 8'h5A;
            store[p0(20'hA8961, 2'(p))] = 8'h5A;
        end

        // W1. up, leng 8: lane 1 (the low byte) spends the whole run, so
        //     remain==0 mid-word suppresses lane 2 -- the odd address is
        //     NOT written. The byte model wrote both halves.
        egc_set(4'hC, 8'h00); egc_set(4'hD, 8'h00);   // sft up, aligned
        egc_set(4'hE, 8'h07); egc_set(4'hF, 8'h00);   // leng 8
        g_wwr(20'hA8900, 16'hD2E1);
        for (int p = 0; p < 4; p++) begin
            want($sformatf("W1 even plane %0d = guest lo", p),
                 store[p0(20'hA8900, 2'(p))], 8'hE1);
            want($sformatf("W1 odd plane %0d suppressed", p),
                 store[p0(20'hA8901, 2'(p))], 8'h5A);
        end

        // W2. up, leng 16: both lanes land -- L on the even byte, H on the
        //     odd one. Catches a lane-order swap.
        egc_set(4'hE, 8'h0F); egc_set(4'hF, 8'h00);   // leng 16
        g_wwr(20'hA8920, 16'hD2E1);
        for (int p = 0; p < 4; p++) begin
            want($sformatf("W2 even plane %0d = lo", p),
                 store[p0(20'hA8920, 2'(p))], 8'hE1);
            want($sformatf("W2 odd plane %0d = hi", p),
                 store[p0(20'hA8921, 2'(p))], 8'hD2);
        end

        // W3. dn, leng 16: decw queues the pair high-then-low and lane 1
        //     is the HIGH byte; the odd leg walks first. The guest's bytes
        //     still land in guest order.
        egc_set(4'hC, 8'h00); egc_set(4'hD, 8'h10);   // sft dn, aligned
        g_wwr(20'hA8940, 16'hD2E1);
        for (int p = 0; p < 4; p++) begin
            want($sformatf("W3 even plane %0d = lo", p),
                 store[p0(20'hA8940, 2'(p))], 8'hE1);
            want($sformatf("W3 odd plane %0d = hi", p),
                 store[p0(20'hA8941, 2'(p))], 8'hD2);
        end

        // W4. dn, leng 8: the HIGH lane spends the run; the low lane is
        //     suppressed, so the EVEN address is the one left untouched.
        egc_set(4'hE, 8'h07); egc_set(4'hF, 8'h00);   // leng 8
        g_wwr(20'hA8960, 16'hD2E1);
        for (int p = 0; p < 4; p++) begin
            want($sformatf("W4 even plane %0d suppressed", p),
                 store[p0(20'hA8960, 2'(p))], 8'h5A);
            want($sformatf("W4 odd plane %0d = hi", p),
                 store[p0(20'hA8961, 2'(p))], 8'hD2);
        end
        egc_set(4'h5, 8'h08);                         // back to 0x08F0

        // ---- 9. the access page ---------------------------------------
        egc_set(4'h5, 8'h00); egc_set(4'h4, 8'h00);   // ope 0x0000
        access_page = 1'b1;
        g_wr(20'hA8040, 8'h99);
        // pc98_gvram_plane1: plane p at bit 16:15 of the seventeen.
        want("page 1: plane B banked at 0x600040",
             store[24'h600000 + 18'h040], 8'h99);
        want("page 1: plane R banked at 0x608040",
             store[24'h600000 + 18'h8040], 8'h99);
        access_page = 1'b0;

        // A plain access with the page bit set touches ONE plane: its own.
        // GRCG comes off with the EGC so the window is genuinely plain --
        // with modereg[7] still set this would be a TDW write instead.
        egc_active = 1'b0;
        grcg_active = 1'b0;
        access_page = 1'b1;
        g_wr(20'hB0060, 8'h66);          // the R window
        want("plain page 1: own plane only",
             store[24'h600000 + 18'h8060], 8'h66);
        want("plain page 1: B's slot untouched",
             store[24'h600000 + 18'h060], 8'h00);
        access_page = 1'b0;

        if (errors == 0) $display("PASS tb_pc98_egc");
        else             $display("FAILED tb_pc98_egc: %0d", errors);
        $finish;
    end

endmodule

`default_nettype wire
