//
// tb_pc98_gvram_seq -- one guest access, the right several to memory.
//
// pc98_grcg's bench proved the arithmetic. This proves the SEQUENCE: which
// planes are touched, in what order, at what addresses, and how many memory
// accesses a single guest access actually costs -- which is the number that
// decides whether the machine is fast enough to be worth using.
//
// The memory model here answers with a per-access done pulse, the way RAM.sv's
// access_complete does, and with a settable latency so the sequencer cannot
// pass by accident on a memory that answers instantly.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_gvram_seq;

    localparam real HALF_NS = 500.0 / 42.954545;
    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic        reset = 1'b1;
    logic        cpu_gvram = 1'b0, cpu_rd = 1'b0, cpu_wr = 1'b0;
    logic        cpu_word = 1'b0;
    logic [19:0] cpu_addr = 20'h0;
    logic [7:0]  cpu_wdata = 8'h00;
    logic [7:0]  cpu_wdata_hi = 8'h00;
    wire  [7:0]  cpu_rdata;
    wire  [7:0]  cpu_rdata_hi;
    wire         cpu_ready;

    logic        grcg_active = 1'b0, grcg_rmw = 1'b0;
    logic [3:0]  grcg_mask = 4'h0;
    logic [7:0]  grcg_tile [0:3];
    logic        analog_mode = 1'b0;

    wire [19:0] mem_addr;
    wire [7:0]  mem_wdata;
    wire        mem_word;
    wire        mem_rd, mem_wr;
    logic [7:0] mem_rdata;
    logic [7:0] mem_rdata_hi;
    logic       mem_done;
    // Chipset feeds the RAM's high byte straight from the CPU bus: during
    // expansion mem_word stays low and RAM ignores it.
    wire [7:0]  mem_wdata_hi = cpu_wdata_hi;
    // RAM.sv's memory_access_ready, modelled as RAM.sv actually behaves: it
    // goes HIGH AT COMPLETE_RAM_RW WHILE THE COMMAND IS STILL UP -- that is
    // how it tells the CPU the data has arrived -- and reads 1 whenever no
    // selected access is in flight. "No access in flight" alone deadlocks: the
    // command stays up waiting for a ready that cannot come until it drops.
    logic       completed = 1'b0;
    wire        mem_ready = (mem_rd | mem_wr) ? completed : 1'b1;

    pc98_gvram_seq dut (
        .clk(clk), .reset(reset),
        .cpu_gvram(cpu_gvram), .cpu_rd(cpu_rd), .cpu_wr(cpu_wr),
        .cpu_word(cpu_word),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_wdata_hi(cpu_wdata_hi),
        .cpu_rdata(cpu_rdata), .cpu_rdata_hi(cpu_rdata_hi),
        .cpu_ready(cpu_ready),
        .grcg_active(grcg_active), .grcg_rmw(grcg_rmw),
        .grcg_mask(grcg_mask), .grcg_tile(grcg_tile),
        .analog_mode(analog_mode),
        .access_page(access_page), .mem_page1(mem_page1),
        .egc_active(egc_active), .egc_wr(egc_wr),
        .egc_rg(egc_rg), .egc_d(egc_d),
        .svc_req(svc_req), .svc_we(svc_we), .svc_addr(svc_addr),
        .svc_wdata(svc_wdata), .svc_done(svc_done), .svc_rdata(svc_rdata), .dbg(),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_word(mem_word),
        .mem_rd(mem_rd), .mem_wr(mem_wr),
        .mem_rdata(mem_rdata), .mem_rdata_hi(mem_rdata_hi),
        .mem_done(mem_done), .mem_ready(mem_ready)
    );

    // The EGC's register writes, driven as PERIPHERALS forwards them.
    logic       egc_active = 1'b0;
    logic       egc_wr = 1'b0;
    logic [3:0] egc_rg = 4'h0;
    logic [7:0] egc_d = 8'h00;
    logic       access_page = 1'b0;
    wire        mem_page1;

    // The softcore guest-VRAM service channel (firmware GDC engine).
    logic        svc_req = 1'b0, svc_we = 1'b0;
    logic [19:0] svc_addr = 20'h0;
    logic [7:0]  svc_wdata = 8'h00;
    wire         svc_done;
    wire  [7:0]  svc_rdata;

    task automatic egc_set(input [3:0] rg, input [7:0] v);
        begin
            @(negedge clk); egc_wr = 1'b1; egc_rg = rg; egc_d = v;
            @(negedge clk); egc_wr = 1'b0;
        end
    endtask

    // ---- the memory: sparse, with a latency ------------------------------
    logic [7:0] store [int];
    int         LAT = 3;
    int         lat_n = 0;
    logic       busy = 1'b0;

    // What the sequencer asked for, in order. `wd` records whether RAM saw
    // the access as a word -- an expanded half must NEVER ask for one.
    typedef struct packed { logic [19:0] a; logic [7:0] d; logic wr; logic wd; } acc_t;
    acc_t log_a [0:47];
    int   log_n = 0;

    // RAM.sv does not start a second access while the command is still up: it
    // reaches COMPLETE_RAM_RW, stays there until both commands drop, and only
    // then returns to IDLE. A model that re-triggers on the overlap counts an
    // access that the real memory would not perform -- which is what made
    // every count in this bench one too high.
    logic armed = 1'b1;

    always_ff @(posedge clk) begin
        mem_done <= 1'b0;
        if (reset) begin busy <= 1'b0; lat_n <= 0; armed <= 1'b1; end
        else if (!(mem_rd | mem_wr)) begin armed <= 1'b1; completed <= 1'b0; end
        else if (!busy && armed && (mem_rd | mem_wr)) begin
            busy  <= 1'b1;
            lat_n <= LAT;
        end else if (busy) begin
            if (lat_n > 1) lat_n <= lat_n - 1;
            else begin
                busy <= 1'b0;
                armed <= 1'b0;          // not again until the command drops
                completed <= 1'b1;
                mem_done <= 1'b1;
                if (mem_wr) begin
                    store[int'(mem_addr)] = mem_wdata;
                    if (mem_word)
                        store[int'(mem_addr) + 1] = mem_wdata_hi;
                    log_a[log_n[5:0]] <= '{mem_addr, mem_wdata, 1'b1, mem_word};
                end else begin
                    log_a[log_n[5:0]] <= '{mem_addr, 8'h00, 1'b0, mem_word};
                end
                log_n <= log_n + 1;
            end
        end
        if (mem_rd) begin
            mem_rdata <= store.exists(int'(mem_addr)) ? store[int'(mem_addr)] : 8'h00;
            mem_rdata_hi <= store.exists(int'(mem_addr) + 1) ? store[int'(mem_addr) + 1] : 8'h00;
        end
    end

    logic [7:0] last_rdata, last_rdata_hi;
    int errors = 0;
    task automatic want(input string what, input int got, input int exp);
        if (got !== exp) begin
            $display("FAIL %-40s got %0d (%05x), want %0d (%05x)",
                     what, got, got, exp, exp);
            errors++;
        end else
            $display("ok   %-40s %0d (%05x)", what, got, got);
    endtask

    task automatic guest(input logic rd, input logic [19:0] a,
                         input logic [7:0] d);
        guestx(rd, a, d, 8'h00, 1'b0);
    endtask

    task automatic guestx(input logic rd, input logic [19:0] a,
                          input logic [7:0] d, input logic [7:0] dh,
                          input logic wd);
        log_n = 0;
        @(posedge clk);
        cpu_gvram = 1'b1; cpu_addr = a; cpu_wdata = d; cpu_wdata_hi = dh;
        cpu_word = wd;
        cpu_rd = rd; cpu_wr = ~rd;
        // One edge before looking at ready. The strobes were only just
        // assigned, so cpu_ready still carries its previous value in this time
        // step -- and with pass-through's ready being "no access in flight",
        // that value is HIGH and the loop would exit before anything happened.
        // A real 8288 asserts the command and samples ready on a later edge.
        @(posedge clk);
        // Drop the strobes ON the ready, the way the 8288 does. Holding them
        // one cycle longer started another memory access and made every count
        // in this bench one too high.
        while (!cpu_ready) @(posedge clk);
        // Sample the answer while the command is still up, as the chipset
        // does: cpu_rdata is valid exactly while cpu_ready is.
        last_rdata = cpu_rdata;
        last_rdata_hi = cpu_rdata_hi;
        cpu_rd = 1'b0; cpu_wr = 1'b0; cpu_gvram = 1'b0; cpu_word = 1'b0;
        repeat (3) @(posedge clk);
    endtask

    // The firmware service channel: request a byte op, wait for done, read
    // the answer back.
    task automatic svc(input logic we, input logic [19:0] a,
                       input logic [7:0] d);
        log_n = 0;
        svc_addr = a; svc_wdata = d; svc_we = we;
        @(posedge clk);
        svc_req = 1'b1;
        while (!svc_done) @(posedge clk);
        last_rdata = svc_rdata;
        svc_req = 1'b0;
        repeat (4) @(posedge clk);
    endtask

    initial begin
        grcg_tile[0] = 8'h00; grcg_tile[1] = 8'h00;
        grcg_tile[2] = 8'h00; grcg_tile[3] = 8'h00;
        mem_rdata = 8'h00; mem_rdata_hi = 8'h00;
        repeat (8) @(posedge clk);
        reset = 1'b0;
        repeat (4) @(posedge clk);

        // ---- TDW, digital: three planes, three writes -------------------
        grcg_active = 1'b1; grcg_rmw = 1'b0; grcg_mask = 4'h0;
        analog_mode = 1'b0;
        grcg_tile[0] = 8'h11; grcg_tile[1] = 8'h22;
        grcg_tile[2] = 8'h44; grcg_tile[3] = 8'h88;
        guest(1'b0, 20'hA8123, 8'hFF);
        want("TDW digital: accesses",        log_n, 3);
        want("  plane B address",            log_a[0].a, 20'hA8123);
        want("  plane R address",            log_a[1].a, 20'hB0123);
        want("  plane G address",            log_a[2].a, 20'hB8123);
        want("  plane B data = tile0",       log_a[0].d, 8'h11);
        want("  plane G data = tile2",       log_a[2].d, 8'h44);

        // ---- TDW, analog: the fourth plane appears, at E0000 -------------
        analog_mode = 1'b1;
        guest(1'b0, 20'hA8123, 8'hFF);
        want("TDW analog: accesses",         log_n, 4);
        want("  plane E address is E0000+",  log_a[3].a, 20'hE0123);
        want("  plane E data = tile3",       log_a[3].d, 8'h88);

        // ---- the mask skips planes --------------------------------------
        grcg_mask = 4'b0101;            // skip planes 0 and 2
        guest(1'b0, 20'hB0456, 8'hFF);
        want("masked: two accesses",         log_n, 2);
        want("  first is plane R",           log_a[0].a, 20'hB0456);
        want("  second is plane E",          log_a[1].a, 20'hE0456);

        // ---- RMW: a read and a write per plane --------------------------
        grcg_mask = 4'h0; grcg_rmw = 1'b1; analog_mode = 1'b0;
        store[20'hA8200] = 8'h55; store[20'hB0200] = 8'h55;
        store[20'hB8200] = 8'h55;
        guest(1'b0, 20'hA8200, 8'h3C);
        want("RMW digital: accesses",        log_n, 6);
        want("  first is a READ",            log_a[0].wr, 0);
        want("  then a WRITE",               log_a[1].wr, 1);
        want("  plane B = (55 & ~3C)|(3C & 11)",
             log_a[1].d, (8'h55 & ~8'h3C) | (8'h3C & 8'h11));
        want("  plane G = (55 & ~3C)|(3C & 44)",
             log_a[5].d, (8'h55 & ~8'h3C) | (8'h3C & 8'h44));

        // ---- TCR: read every plane, answer the match mask ---------------
        grcg_rmw = 1'b0;
        store[20'hA8300] = 8'h11; store[20'hB0300] = 8'h22;
        store[20'hB8300] = 8'h44;
        guest(1'b1, 20'hA8300, 8'h00);
        want("TCR digital: three reads",     log_n, 3);
        want("  every plane matches -> FF",  last_rdata, 8'hFF);
        store[20'hB0300] = 8'h23;       // one bit differs
        guest(1'b1, 20'hA8300, 8'h00);
        want("TCR one bit differs",          last_rdata, 8'hFE);

        // ---- pass-through: the GRCG off is one access, unchanged --------
        grcg_active = 1'b0;
        guest(1'b0, 20'hA8123, 8'h5A);
        want("GRCG off: one access",         log_n, 1);
        want("  at the guest's own address", log_a[0].a, 20'hA8123);
        want("  with the guest's own byte",  log_a[0].d, 8'h5A);

        // ---- TDW WORD write: both halves expand, neither bursts ----------
        // The old RTL passed the two-SDRAM-word burst through whole: the
        // even byte got the tile and the odd byte kept the guest's raw data
        // -- the regular-interval byte-lane corruption on ruled lines.
        grcg_active = 1'b1; grcg_rmw = 1'b0; grcg_mask = 4'h0;
        analog_mode = 1'b0;
        grcg_tile[0] = 8'h11; grcg_tile[1] = 8'h22;
        grcg_tile[2] = 8'h44; grcg_tile[3] = 8'h88;
        store[20'hA8200] = 8'h00; store[20'hA8201] = 8'h00;
        store[20'hB0200] = 8'h00; store[20'hB0201] = 8'h00;
        store[20'hB8200] = 8'h00; store[20'hB8201] = 8'h00;
        guestx(1'b0, 20'hA8200, 8'hCD, 8'hAB, 1'b1);
        want("TDW word: accesses",           log_n, 6);
        want("  half0 plane B addr",         log_a[0].a, 20'hA8200);
        want("  half1 plane B addr",         log_a[3].a, 20'hA8201);
        want("  half1 plane G addr",         log_a[5].a, 20'hB8201);
        want("  no burst on half0",          log_a[0].wd, 0);
        want("  no burst on half1",          log_a[3].wd, 0);
        want("  B lo = tile0",               store[20'hA8200], 8'h11);
        want("  B hi = tile0, not raw",      store[20'hA8201], 8'h11);
        want("  R hi = tile1, not raw",      store[20'hB0201], 8'h22);
        want("  G hi = tile2, not raw",      store[20'hB8201], 8'h44);

        // ---- ITF tiles: 33h/55h through a word WDAT-shaped write --------
        // The ITF loads tile[0]=33 tile[1]=55 tile[2]=00 tile[3]=00 (its
        // four OUT 7Eh writes) with mask=0, then its WDAT word fill must
        // leave A8000=3333 B0000=5555 B8000=0000.
        grcg_tile[0] = 8'h33; grcg_tile[1] = 8'h55;
        grcg_tile[2] = 8'h00; grcg_tile[3] = 8'h00;
        grcg_mask = 4'b0000;
        guestx(1'b0, 20'hA8000, 8'hFF, 8'hFF, 1'b1);
        want("ITF tiles: accesses",          log_n, 6);
        want("  A8000 = 33",                 store[20'hA8000], 8'h33);
        want("  A8001 = 33",                 store[20'hA8001], 8'h33);
        want("  B0000 = 55",                 store[20'hB0000], 8'h55);
        want("  B0001 = 55",                 store[20'hB0001], 8'h55);
        want("  B8000 = 00",                 store[20'hB8000], 8'h00);

        // ---- RMW WORD write: rd+wr per plane, per half -------------------
        // Tiles are still the ITF's 33/55/00/00 from the test above.
        grcg_mask = 4'h0; grcg_rmw = 1'b1;
        store[20'hA8200] = 8'h55; store[20'hA8201] = 8'hAA;
        store[20'hB0200] = 8'h55; store[20'hB0201] = 8'hAA;
        store[20'hB8200] = 8'h55; store[20'hB8201] = 8'hAA;
        guestx(1'b0, 20'hA8200, 8'h3C, 8'hC3, 1'b1);
        want("RMW word: accesses",           log_n, 12);
        want("  half1 rd is B+1",            log_a[6].a, 20'hA8201);
        want("  half1 rd is a READ",         log_a[6].wr, 0);
        want("  B lo = (55&~3C)|(3C&33)",
             log_a[1].d, (8'h55 & ~8'h3C) | (8'h3C & 8'h33));
        want("  B hi = (AA&~C3)|(C3&33)",
             log_a[7].d, (8'hAA & ~8'hC3) | (8'hC3 & 8'h33));

        // ---- TCR WORD read: two match masks, one access ------------------
        grcg_rmw = 1'b0; grcg_active = 1'b1;
        grcg_tile[0] = 8'h11; grcg_tile[1] = 8'h22; grcg_tile[2] = 8'h44;
        store[20'hA8300] = 8'h11; store[20'hA8301] = 8'h11;
        store[20'hB0300] = 8'h22; store[20'hB0301] = 8'h23;
        store[20'hB8300] = 8'h44; store[20'hB8301] = 8'h44;
        guestx(1'b1, 20'hA8300, 8'h00, 8'h00, 1'b1);
        want("TCR word: accesses",           log_n, 6);
        want("  lo = FF (all match)",        last_rdata, 8'hFF);
        want("  hi = FE (one bit differs)",  last_rdata_hi, 8'hFE);

        // ---- pass-through word stays one burst ---------------------------
        grcg_active = 1'b0;
        store[20'hA8400] = 8'h00; store[20'hA8401] = 8'h00;
        guestx(1'b0, 20'hA8400, 8'h5A, 8'hA5, 1'b1);
        want("GRCG off word: one access",    log_n, 1);
        want("  still a word burst",         log_a[0].wd, 1);
        want("  lo byte stored",             store[20'hA8400], 8'h5A);
        want("  hi byte stored",             store[20'hA8401], 8'hA5);

        // ---- the softcore service channel -------------------------------
        // Unarmed svc write = a plain own-plane byte write; svc read returns
        // the byte. This is the channel gdc_service.c's vr_read8/vr_write8
        // drive after the 0x50000000 window comes back.
        svc(1'b1, 20'hA8500, 8'h77);
        want("svc unarmed write: accesses",  log_n, 1);
        want("  at its own address",         log_a[0].a, 20'hA8500);
        want("  its own byte",               log_a[0].d, 8'h77);
        svc(1'b0, 20'hA8500, 8'h00);
        want("svc unarmed read: accesses",   log_n, 1);
        want("  returns stored byte",        last_rdata, 8'h77);

        // Armed svc write goes through the charger: the ITF WDAT fill.
        grcg_active = 1'b1; grcg_rmw = 1'b0; grcg_mask = 4'b0000;
        grcg_tile[0] = 8'h33; grcg_tile[1] = 8'h55;
        grcg_tile[2] = 8'h00; grcg_tile[3] = 8'h00;
        svc(1'b1, 20'hA8002, 8'hFF);
        want("svc TDW write: accesses",      log_n, 3);
        want("  A8002 = 33",                 store[20'hA8002], 8'h33);
        want("  B0002 = 55",                 store[20'hB0002], 8'h55);
        want("  B8002 = 00",                 store[20'hB8002], 8'h00);

        // A svc request raised while a guest access is in flight waits for
        // the guest; the memory order must stay guest-then-svc.
        grcg_active = 1'b0;
        log_n = 0;
        @(posedge clk);
        cpu_gvram = 1'b1; cpu_addr = 20'hA8600; cpu_wdata = 8'h01;
        cpu_wr = 1'b1;
        svc_addr = 20'hA8601; svc_wdata = 8'h02; svc_we = 1'b1;
        @(posedge clk);
        svc_req = 1'b1;
        while (!cpu_ready) @(posedge clk);
        cpu_wr = 1'b0; cpu_gvram = 1'b0;
        while (!svc_done) @(posedge clk);
        svc_req = 1'b0;
        repeat (4) @(posedge clk);
        want("svc vs guest: two accesses",   log_n, 2);
        want("  guest first",                log_a[0].a, 20'hA8600);
        want("  svc second",                 log_a[1].a, 20'hA8601);
        want("  guest byte",                 log_a[0].d, 8'h01);
        want("  svc byte",                   log_a[1].d, 8'h02);

        // The reverse hazard: a guest access raised MID-SVC-OP must not take
        // the svc's S_DONE ready -- it would sample a stale rdata_pass for a
        // read that never reached memory. The ~svc_hold gate keeps ready low
        // until the guest's own walk (here, its pass-through read) runs.
        store[20'hA8701] = 8'h42;
        log_n = 0;
        svc_addr = 20'hA8700; svc_wdata = 8'h77; svc_we = 1'b1;
        @(posedge clk);
        svc_req = 1'b1;
        while (log_n == 0) @(posedge clk);  // the svc write is in flight
        cpu_gvram = 1'b1; cpu_addr = 20'hA8701; cpu_rd = 1'b1;
        while (!cpu_ready) @(posedge clk);  // ready was low the whole walk
        last_rdata = cpu_rdata;
        cpu_rd = 1'b0; cpu_gvram = 1'b0;
        while (!svc_done) @(posedge clk);
        svc_req = 1'b0;
        repeat (4) @(posedge clk);
        want("guest mid-svc: two accesses",  log_n, 2);
        want("  svc write first",            log_a[0].a, 20'hA8700);
        want("  guest read second",          log_a[1].a, 20'hA8701);
        want("  guest read is a READ",       log_a[1].wr, 0);
        want("  guest got the real byte",    last_rdata, 8'h42);

        if (errors == 0) $display("PASS tb_pc98_gvram_seq");
        else             $display("FAILED tb_pc98_gvram_seq: %0d", errors);
        $finish;
    end

    initial begin
        #5000000;
        $display("FAILED tb_pc98_gvram_seq: timeout");
        $finish;
    end

endmodule

`default_nettype wire
