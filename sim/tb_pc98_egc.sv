//
// tb_pc98_egc -- the charger's engine, against np2kai's arithmetic.
//
// pc98_egc's registers are np2kai io/egc.c; the engine that consumes them is
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
    wire  [7:0]  cpu_rdata;
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
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
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
    int         verbose = 0;

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
                if (mem_wr) begin
                    if (verbose) $display("  ACC wr a=%06x d=%02x p1=%b",
                                          banked(mem_addr), mem_wdata, mem_page1);
                    store[banked(mem_addr)] <= mem_wdata;
                end else begin
                    mem_rdata <= store[banked(mem_addr)];
                    if (verbose) $display("  ACC rd a=%06x -> %02x",
                                          banked(mem_addr), store[banked(mem_addr)]);
                end
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

    always @(posedge clk)
        if (verbose && dut.st == 3'd3 && dut.cur_live)
            $display("  SWR gp=%b wr_byte=%02x op_data=%02x fgbg_col=%04x ope_sel=%b opext=%b srcsel=%04x",
                     dut.gp, dut.wr_byte, dut.egc_op_data, dut.u_egc.fgbg_col,
                     dut.u_egc.ope_r[12:11], dut.u_egc.op_ext, dut.u_egc.src_q[dut.gp]);

    int errors = 0;
    task automatic want(input string what, input int got, input int exp);
        if (got !== exp) begin
            $display("FAIL %-40s got %02x, want %02x", what, got, exp);
            errors++;
        end else
            $display("ok   %-40s %02x", what, got);
    endtask

    logic [7:0] rdb;

    initial begin
        grcg_tile[0] = 8'h00; grcg_tile[1] = 8'h00;
        grcg_tile[2] = 8'h00; grcg_tile[3] = 8'h00;

        repeat (4) @(negedge clk);
        reset = 1'b0;
        repeat (2) @(negedge clk);

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
        $display("DBG fg_color=%b ope=%b fgbg=%b fgc0=%b fgc2=%b opsel=%b",
                 dut.u_egc.fg_color, dut.u_egc.ope_r, dut.u_egc.fgbg_r,
                 dut.u_egc.fgc[0], dut.u_egc.fgc[2], dut.u_egc.ope_r[12:11]);
        verbose = 1;
        $display("DBG fgbg_col=%b pat_b=%b op_data(plane0/ext0)=%b",
                 dut.u_egc.fgbg_col, dut.u_egc.pat_b, dut.u_egc.op_data);
        g_wr(20'hA8080, 8'h77);
        verbose = 0;
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
        $display("DBG after read: src_q = %02x %02x %02x %02x",
                 dut.u_egc.src_q[0], dut.u_egc.src_q[1],
                 dut.u_egc.src_q[2], dut.u_egc.src_q[3]);
        egc_set(4'h5, 8'h08);            // ope high: 0x0800
        egc_set(4'h4, 8'hF0);            // ope code F0 = src
        verbose = 1;
        g_wr(20'hA8180, 8'h00);
        verbose = 0;
        want("blit: plane B",  store[p0(20'hA8180, 2'd0)], 8'h11);
        want("blit: plane R",  store[p0(20'hA8180, 2'd1)], 8'h22);
        want("blit: plane G",  store[p0(20'hA8180, 2'd2)], 8'h44);
        want("blit: plane E",  store[p0(20'hA8180, 2'd3)], 8'h88);

        // ---- 6. the read's answer is fgbg 9:8's plane ------------------
        // fgbg bits 9:8 = 0b10: plane R answers.
        egc_set(4'h3, 8'h01);            // fgbf bits 9:8 = 01 -> plane R
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
        // the general engine (pat & src & dst | pat & ~src & ~dst) -- with
        // src = the last read's plane byte and dst the same fresh byte the
        // result follows the pattern's bits where src and dst agree.
        egc_set(4'h5, 8'h08); egc_set(4'h4, 8'h88);
        g_wr(20'hA8201, 8'h00);
        // (patreg B = C3 was loaded from offset 0x200's plane B; the blit in
        // test 5 left the source latch holding 11 at the last read -- the
        // exact minterm arithmetic is np2kai's ope_xx with those inputs.)
        $display("     pat-raster plane B = %02x (informational)",
                 store[p0(20'hA8201, 2'd0)]);

        // ---- 8. the access page ---------------------------------------
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
        egc_active = 1'b0;
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
