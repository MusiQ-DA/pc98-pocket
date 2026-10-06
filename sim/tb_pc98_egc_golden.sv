// tb_pc98_egc_golden -- differential bench: every op in an op stream goes to
// BOTH the sequencer+EGC RTL and the np21w golden model (sim/golden/, DPI).
// Reads compare per access; X compares the whole 4-plane x 2-page VRAM image.
//
// Stream format: sim/golden/FORMAT.md (the np2kai recorder writes the same).
// Modes:
//   +stream=<file>          replay the ops (records validate this bench too)
//   +seed=<n> [+nops=<k>]   fuzz: generate a seeded stream, run it, and dump
//                           it to +dump=<file> (default fuzz-<seed>.ops) so a
//                           failure replays standalone.
//   +cmpmod=<0|1>           0 compares after X only; 1 also after every op.

`timescale 1ns/1ps

module tb_pc98_egc_golden;

    // ---- golden model ----------------------------------------------------
    import "DPI-C" function void golden_reset();
    import "DPI-C" function void golden_mode(int m);
    import "DPI-C" function void golden_egc_write(int rg, int val);
    import "DPI-C" function void golden_grcg_mode(int val);
    import "DPI-C" function void golden_grcg_tile(int p, int val);
    import "DPI-C" function void golden_access_page(int v);
    import "DPI-C" function int  golden_rd8(int addr);
    import "DPI-C" function void golden_wr8(int addr, int val);
    import "DPI-C" function int  golden_rd16(int addr);
    import "DPI-C" function int  golden_egc_sft();
    import "DPI-C" function int  golden_egc_mask2();
    import "DPI-C" function int  golden_egc_srcmask();
    import "DPI-C" function int  golden_egc_remain();
    import "DPI-C" function int  golden_egc_stack();
    import "DPI-C" function int  golden_egc_ope();
    import "DPI-C" function int  golden_egc_patreg(input int p);
    import "DPI-C" function int  golden_egc_fgbg();
    import "DPI-C" function int  golden_egc_src(input int p);
    import "DPI-C" function int  golden_egc_srcbit();
    import "DPI-C" function int  golden_egc_dstbit();
    import "DPI-C" function int  golden_egc_func();
    import "DPI-C" function int  golden_egc_inptr();
    import "DPI-C" function int  golden_egc_outptr();
    import "DPI-C" function int  golden_egc_buf(input int i);
    import "DPI-C" function void golden_wr16(int addr, int val);
    import "DPI-C" function int  golden_vram_byte(int addr);
    import "DPI-C" function void golden_vram_poke(int addr, int val);
    import "DPI-C" function void golden_egc_dbgev(input int v);

    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic reset = 1'b1;

    int errors = 0;
    int opno   = 0;
    int cmpmod = 0;
    int egcdbg = 0;

    // ---- guest pins (as tb_pc98_egc) -------------------------------------
    logic        cpu_gvram = 1'b0;
    logic        cpu_rd = 1'b0, cpu_wr = 1'b0;
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
    wire        mem_rd, mem_wr, mem_word;
    wire [7:0]  mem_wdata_hi = cpu_wdata_hi;
    logic [7:0] mem_rdata, mem_rdata_hi;
    logic       mem_done;
    // RAM.sv's memory_access_ready: while a command strobe is up, ready
    // answers only at the access's own completion -- the guest holds its
    // bus cycle that long and takes data then. An idle bus always reads
    // ready. (RAM.sv: COMPLETE_RAM_RW & strobe-match, else 1.)
    wire        mem_ready = (mem_rd | mem_wr) ? m_done_lvl : 1'b1;

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
        .svc_wdata(8'h00), .svc_done(), .svc_rdata(), .dbg(),
        .grcg_active(grcg_active), .grcg_rmw(grcg_rmw),
        .grcg_mask(grcg_mask), .grcg_tile(grcg_tile),
        .analog_mode(analog_mode),
        .access_page(access_page), .mem_page1(mem_page1),
        .egc_active(egc_active), .egc_wr(egc_wr),
        .egc_rg(egc_rg), .egc_d(egc_d),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_word(mem_word),
        .mem_rd(mem_rd), .mem_wr(mem_wr),
        .mem_rdata(mem_rdata), .mem_rdata_hi(mem_rdata_hi),
        // Every access this model flies came from the seq's own strobes --
        // the parked slot promotes only into the held strobe's slot -- so
        // each done pulse is the own edge by construction.
        .mem_done(mem_done), .mem_own(1'b1), .mem_ready(mem_ready)
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

    function automatic int banked(input [19:0] a);
        banked = mem_page1 ? (24'h600000 + {7'b0, a[16:0]}) : a;
    endfunction

    // RAM.sv behaviour: a command is captured whole at issue (accept_*),
    // flies LAT cycles, then raises a done level the guest's held strobe
    // samples -- COMPLETE_RAM_RW waits on the strobe releasing, so the level
    // survives as long as mem_rd|mem_wr stays up. A strobe arriving while an
    // access is in flight parks in a depth-one pending slot (wc_pend) and
    // flies after. Write data always commits from the captured copy, never
    // the live pins -- a parked write's strobe may already be gone.
    logic        armed = 1'b1;
    logic        busy = 1'b0;
    logic        m_done_lvl = 1'b0;
    int          lat_n = 0;
    logic [19:0] wr_addr;
    logic [7:0]  wr_data, wr_data_hi;
    logic        wr_word, wr_page1, wr_pend = 1'b0;
    logic        pend_v = 1'b0, pend_wr, pend_word, pend_page1;
    logic [19:0] pend_addr;
    logic [7:0]  pend_data, pend_data_hi;

    always_ff @(posedge clk) begin
        mem_done <= 1'b0;
        if (reset) begin
            busy <= 1'b0; lat_n <= 0; armed <= 1'b1;
            wr_pend <= 1'b0; pend_v <= 1'b0; m_done_lvl <= 1'b0;
        end else begin
            if (!(mem_rd | mem_wr)) begin
                // bus quiet: the strobe that was being answered is gone
                armed      <= 1'b1;
                m_done_lvl <= 1'b0;
            end else if (armed) begin
                armed <= 1'b0;
                if (busy | m_done_lvl) begin
                    // strobe while an access is in flight or completing:
                    // park it whole, it flies afterwards (RAM.sv wc_pend)
                    pend_v       <= 1'b1;
                    pend_wr      <= mem_wr;
                    pend_addr    <= mem_addr;
                    pend_data    <= mem_wdata;
                    pend_data_hi <= mem_wdata_hi;
                    pend_word    <= mem_word;
                    pend_page1   <= mem_page1;
                end else begin
                    busy  <= 1'b1;
                    lat_n <= LAT;
                    if (mem_wr) begin
                        wr_pend    <= 1'b1;
                        wr_addr    <= mem_addr;
                        wr_data    <= mem_wdata;
                        wr_data_hi <= mem_wdata_hi;
                        wr_word    <= mem_word;
                        wr_page1   <= mem_page1;
                    end
                end
            end
            if (busy) begin
                if (lat_n > 1) lat_n <= lat_n - 1;
                else begin
                    busy       <= 1'b0;
                    m_done_lvl <= 1'b1;
                    mem_done   <= 1'b1;
                    if (wr_pend) begin
                        wr_pend <= 1'b0;
                        store[wr_page1 ? 24'h600000 + {7'b0, wr_addr[16:0]}
                                       : {4'b0, wr_addr}] = wr_data;
                        if (wr_word)
                            store[wr_page1 ? 24'h600000 + {7'b0, wr_addr[16:0]} + 1
                                           : {4'b0, wr_addr} + 1] = wr_data_hi;
                    end
                    if (pend_v) begin
                        // promote the parked command: it flies next
                        pend_v     <= 1'b0;
                        busy       <= 1'b1;
                        lat_n      <= LAT;
                        m_done_lvl <= 1'b0;
                        mem_done   <= 1'b0;
                        if (pend_wr) begin
                            wr_pend    <= 1'b1;
                            wr_addr    <= pend_addr;
                            wr_data    <= pend_data;
                            wr_data_hi <= pend_data_hi;
                            wr_word    <= pend_word;
                            wr_page1   <= pend_page1;
                        end
                    end
                end
            end
        end
        if (mem_rd) begin
            mem_rdata    <= store.exists(banked(mem_addr))
                            ? store[banked(mem_addr)] : 8'h00;
            mem_rdata_hi <= store.exists(banked(mem_addr) + 1)
                            ? store[banked(mem_addr) + 1] : 8'h00;
        end
    end

    // ---- guest access tasks ----------------------------------------------
    // A real guest holds its strobe until READY -- for a passthrough access
    // that is RAM.sv's memory_access_ready, which answers 1 while idle but
    // only goes out at COMPLETE_RAM_RW once the command is selected. The
    // seq registers cpu_rd/wr into mem_rd/mem_wr one clock after they rise,
    // so ready is still high at the first posedge: a guest that samples
    // ready on that edge releases before the RAM ever saw the command. Wait
    // one full clock after asserting, then poll the level.
    task automatic g_wr(input [19:0] a, input [7:0] v);
        begin
            @(negedge clk);
            cpu_gvram = 1'b1; cpu_addr = a; cpu_wdata = v; cpu_wr = 1'b1;
            @(posedge clk);
            // Command registered? Passthrough shows it on mem_rd/mem_wr;
            // an expanded access shows it by the walk leaving S_IDLE (a
            // fully-masked expanded write may raise no mem strobe at all).
            while (!(mem_rd | mem_wr) && (dut.st == 3'd0)) @(posedge clk);
            while (!cpu_ready) @(posedge clk);
            @(negedge clk);
            cpu_wr = 1'b0; cpu_gvram = 1'b0;
            while (dut.st != 3'd0) @(posedge clk);
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic g_wwr(input [19:0] a, input [15:0] v);
        begin
            @(negedge clk);
            cpu_gvram = 1'b1; cpu_addr = a; cpu_word = 1'b1;
            cpu_wdata = v[7:0]; cpu_wdata_hi = v[15:8]; cpu_wr = 1'b1;
            @(posedge clk);
            // Command registered? Passthrough shows it on mem_rd/mem_wr;
            // an expanded access shows it by the walk leaving S_IDLE (a
            // fully-masked expanded write may raise no mem strobe at all).
            while (!(mem_rd | mem_wr) && (dut.st == 3'd0)) @(posedge clk);
            while (!cpu_ready) @(posedge clk);
            @(negedge clk);
            cpu_wr = 1'b0; cpu_gvram = 1'b0; cpu_word = 1'b0;
            while (dut.st != 3'd0) @(posedge clk);
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic g_rd(input [19:0] a, output [7:0] v);
        begin
            @(negedge clk);
            cpu_gvram = 1'b1; cpu_addr = a; cpu_rd = 1'b1;
            @(posedge clk);
            // Command registered? Passthrough shows it on mem_rd/mem_wr;
            // an expanded access shows it by the walk leaving S_IDLE (a
            // fully-masked expanded write may raise no mem strobe at all).
            while (!(mem_rd | mem_wr) && (dut.st == 3'd0)) @(posedge clk);
            while (!cpu_ready) @(posedge clk);
            v = cpu_rdata;
            @(negedge clk);
            cpu_rd = 1'b0; cpu_gvram = 1'b0;
            while (dut.st != 3'd0) @(posedge clk);
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic g_wrd(input [19:0] a, output [15:0] v);
        begin
            @(negedge clk);
            cpu_gvram = 1'b1; cpu_addr = a; cpu_word = 1'b1; cpu_rd = 1'b1;
            @(posedge clk);
            // Command registered? Passthrough shows it on mem_rd/mem_wr;
            // an expanded access shows it by the walk leaving S_IDLE (a
            // fully-masked expanded write may raise no mem strobe at all).
            while (!(mem_rd | mem_wr) && (dut.st == 3'd0)) @(posedge clk);
            while (!cpu_ready) @(posedge clk);
            v = {cpu_rdata_hi, cpu_rdata};
            @(negedge clk);
            cpu_rd = 1'b0; cpu_gvram = 1'b0; cpu_word = 1'b0;
            while (dut.st != 3'd0) @(posedge clk);
            repeat (2) @(negedge clk);
        end
    endtask

    // ---- bookkeeping -------------------------------------------------------
    task automatic fail(input string what, input int got, input int exp);
        begin
            errors = errors + 1;
            if (errors <= 40)
                $display("DIFF  op#%0d  %-28s  got %02x  exp %02x",
                         opno, what, got, exp);
            dump_state();
        end
    endtask

    // Shift-pipeline internals, both sides, on the first divergence.
    bit qdumped = 0;
    task automatic midq(input int a);
        int ob;
        $display("STATE op#%0d @%05x rtl f=%0d s=%0d d=%0d rem=%0d stk=%0d qd=%0d sm=%04x",
                 opno, a, dut.g_egc.u_egc.sf_func, dut.g_egc.u_egc.sf_srcbit,
                 dut.g_egc.u_egc.sf_dstbit, dut.g_egc.u_egc.sf_remain,
                 dut.g_egc.u_egc.sf_stack, dut.g_egc.u_egc.sf_qd,
                 dut.g_egc.u_egc.sf_srcmask);
        $display("STATE op#%0d @%05x gld f=%0d s=%0d d=%0d rem=%0d stk=%0d in=%0d out=%0d sm=%04x",
                 opno, a, golden_egc_func(), golden_egc_srcbit(),
                 golden_egc_dstbit(), golden_egc_remain(),
                 golden_egc_stack(), golden_egc_inptr(),
                 golden_egc_outptr(), golden_egc_srcmask());
        for (int p = 0; p < 4; p++)
            $display("  p%0d  src rtl %04x  gld %04x", p,
                     dut.g_egc.u_egc.src_q[p], 16'(golden_egc_src(p)));
        ob = golden_egc_outptr();
        for (int p = 0; p < 4; p++) begin
            $write("  p%0d gold:", p);
            for (int i = -1; i < 7; i++)
                $write(" %02x", 8'(golden_egc_buf(ob + p*4 + i)));
            $write("  rtl:");
            for (int i = 0; i < 7; i++)
                $write(" %02x", dut.g_egc.u_egc.sf_q[p][i]);
            $display("");
        end
    endtask

    task automatic dump_state();
        if (qdumped) return;
        qdumped = 1;
        midq(0);
    endtask

    int dump_fd = 0;
    task automatic emit(input string s);
        if (dump_fd) $fwrite(dump_fd, "%s\n", s);
    endtask

    // RTL shift-event internals, one line per commit: what the combinational
    // event computed (pops, produced lane) against the pre-commit state.
    always @(posedge clk) begin
        if (egcdbg && dut.g_egc.u_egc.sf_evt)
            $display({"  rtl evt op#%0d wr=%0d wd=%0d tl=%0d ext=%0d",
                      " s=%0d d=%0d rem=%0d stk=%0d qd=%0d pops=%0d",
                      " prod=%0d out3=%02x sm=%04x"},
                     opno, dut.g_egc.u_egc.sf_evt_wr,
                     dut.g_egc.u_egc.sf_evt_word, dut.g_egc.u_egc.sf_evt_tail,
                     dut.g_egc.u_egc.ev_ext, dut.g_egc.u_egc.sf_srcbit,
                     dut.g_egc.u_egc.sf_dstbit, dut.g_egc.u_egc.sf_remain,
                     dut.g_egc.u_egc.sf_stack, dut.g_egc.u_egc.sf_qd,
                     dut.g_egc.u_egc.ev_pops, dut.g_egc.u_egc.ev_prod,
                     dut.g_egc.u_egc.ev_out[3], dut.g_egc.u_egc.sf_srcmask);
        if (egcdbg && dut.g_egc.u_egc.sf_push)
            $display("  rtl push op#%0d p%0d <- %02x (qd=%0d off=%0d)",
                     opno, dut.g_egc.u_egc.sf_push_plane,
                     dut.g_egc.u_egc.sf_push_d, dut.g_egc.u_egc.sf_qd,
                     dut.g_egc.u_egc.sf_push_off);
    end

    // ---- op drivers: one op -> RTL + golden -------------------------------
    // M <n>: engine select. Golden keeps GRCG operate bits from modereg no
    // matter what M says, so M only moves egc_active here.
    task automatic op_mode(input int m);
        egc_active = (m == 2);
        golden_mode(m);
        emit($sformatf("M %0d", m));
    endtask

    task automatic op_ereg(input int rg, input int v);
        // Port 0x4A0-4AF only decodes while the EGC is enabled -- np21w's
        // egc_o4a0 drops the write itself, and on the machine Peripherals
        // never raises the strobe; mirror that here so neither side latches.
        if (egc_active) egc_set(rg[3:0], v[7:0]);
        golden_egc_write(rg, v);
        emit($sformatf("E %x %02x", rg, v));
    endtask

    task automatic op_gm(input int v);
        // port 0x7C: bit7 GRCG on, bit6 RMW, 3:0 plane-skip mask.
        grcg_active = v[7];
        grcg_rmw    = v[6];
        grcg_mask   = v[3:0];
        golden_grcg_mode(v);
        emit($sformatf("GM %02x", v));
    endtask

    task automatic op_gt(input int p, input int v);
        if (v[15:8] != v[7:0])
            $display("note: op#%0d GT plane %0d halves differ (%04x) -- taking low",
                     opno, p, v);
        grcg_tile[p & 3] = v[7:0];
        golden_grcg_tile(p, v);
        emit($sformatf("GT %0d %04x", p, v));
    endtask

    task automatic op_page(input int v);
        access_page = v[0];
        golden_access_page(v);
        emit($sformatf("P %0d", v));
    endtask

    task automatic op_w8(input int a, input int v);
        note_addr(a);
        g_wr(20'(a), v[7:0]);
        golden_wr8(a, v);
        if (egcdbg && egc_active)
            $display("EGCD op#%0d W8 %05x <- %02x  ope=%04x sft=%04x m2=%04x src=%04x rem=%0d stk=%0d",
                     opno, a, v, golden_egc_ope(), golden_egc_sft(),
                     golden_egc_mask2(), golden_egc_srcmask(),
                     golden_egc_remain(), golden_egc_stack());
        emit($sformatf("W8 %x %02x", a, v));
    endtask

    // A word access at an odd address never reaches the seq as a word cycle:
    // every CPU that drives this logic splits it into two byte bus cycles,
    // and np21w does the same in memegc_rd16/wr16 -- lo byte first, except
    // hi byte first when the EGC shifts downward (egc.sft bit 12). The byte
    // order has to match on the RTL side because EGC byte ops move the shift
    // queue. The golden side takes byte calls too rather than its own
    // dispatch_*16: the GRCG word macros write mem[a..a+1] flat, so at a
    // window boundary the high byte bleeds into the NEXT plane's slot with
    // the wrong tile -- an artifact of np21w's flat array, not hardware. Two
    // byte dispatches match what the seq (and a real machine) does.
    function automatic bit odd_hi_first(input int a);
        odd_hi_first = a[0] & egc_active & ((golden_egc_sft() & 16'h1000) != 0);
    endfunction

    task automatic op_w16(input int a, input int v);
        note_addr(a);
        if (a[0]) begin
            if (odd_hi_first(a)) begin
                g_wr(20'(a) + 1, v[15:8]); golden_wr8(a + 1, v[15:8]);
                g_wr(20'(a),     v[7:0]);  golden_wr8(a,     v[7:0]);
            end else begin
                g_wr(20'(a),     v[7:0]);  golden_wr8(a,     v[7:0]);
                g_wr(20'(a) + 1, v[15:8]); golden_wr8(a + 1, v[15:8]);
            end
        end else begin
            g_wwr(20'(a), v[15:0]);
            golden_wr16(a, v);
        end
        if (egcdbg && egc_active)
            $display("EGCD op#%0d W16 %05x <- %04x  ope=%04x sft=%04x m2=%04x src=%04x rem=%0d stk=%0d",
                     opno, a, v, golden_egc_ope(), golden_egc_sft(),
                     golden_egc_mask2(), golden_egc_srcmask(),
                     golden_egc_remain(), golden_egc_stack());
        emit($sformatf("W16 %x %04x", a, v));
    endtask

    task automatic op_r8(input int a, input int exp);
        logic [7:0] got;
        int         want;
        note_addr(a);
        g_rd(20'(a), got);
        want = golden_rd8(a);
        if (got !== want[7:0])
            fail($sformatf("R8 %05x", a), got, want);
        if (egcdbg && egc_active)
            $display("EGCD op#%0d R8 %05x -> %02x (rtl %02x)  ope=%04x sft=%04x m2=%04x src=%04x rem=%0d stk=%0d",
                     opno, a, want, got, golden_egc_ope(), golden_egc_sft(),
                     golden_egc_mask2(), golden_egc_srcmask(),
                     golden_egc_remain(), golden_egc_stack());
        emit($sformatf("R8 %x %02x", a, want));
    endtask

    task automatic op_r16(input int a, input int exp);
        logic [15:0] got;
        logic [7:0]  lo, hi;
        int          want;
        note_addr(a);
        if (a[0]) begin
            int want_lo, want_hi;
            if (odd_hi_first(a)) begin
                g_rd(20'(a) + 1, hi); want_hi = golden_rd8(a + 1);
                if (egcdbg && egc_active) midq(a + 1);
                g_rd(20'(a),     lo); want_lo = golden_rd8(a);
            end else begin
                g_rd(20'(a),     lo); want_lo = golden_rd8(a);
                if (egcdbg && egc_active) midq(a);
                g_rd(20'(a) + 1, hi); want_hi = golden_rd8(a + 1);
            end
            got  = {hi, lo};
            want = {8'(want_hi), 8'(want_lo)};
        end else begin
            g_wrd(20'(a), got);
            want = golden_rd16(a);
        end
        if (got !== want[15:0])
            fail($sformatf("R16 %05x", a), got, want);
        if (egcdbg && egc_active)
            $display("EGCD op#%0d R16 %05x -> %04x (rtl %04x)  ope=%04x sft=%04x m2=%04x src=%04x rem=%0d stk=%0d",
                     opno, a, want, got, golden_egc_ope(), golden_egc_sft(),
                     golden_egc_mask2(), golden_egc_srcmask(),
                     golden_egc_remain(), golden_egc_stack());
        emit($sformatf("R16 %x %04x", a, want));
    endtask

    // seed VRAM without an access: both memories take the byte directly.
    task automatic op_poke(input int a, input int v);
        int k;
        note_addr(a);
        k = banked_key(a);
        store[k] = v[7:0];
        golden_vram_poke(a, v);
        emit($sformatf("F %x %02x", a, v));
    endtask

    // TB-store key for a golden mem[] address -- plane x page mapping, the
    // inverse of banked(): golden page 1 sits at +0x100000 in mem[] while
    // this bench keys it 0x600000 + plane*0x8000 + off.
    function automatic int plane_index(input int a);
        if (a[19:15] == 5'b11100)      plane_index = 3;
        else if (a[19:15] == 5'b10101) plane_index = 0;
        else if (a[15])                plane_index = 2;
        else                           plane_index = 1;
    endfunction

    function automatic int banked_key(input int ga);
        if (ga >= 24'h100000)
            banked_key = 24'h600000 + plane_index(ga & 20'hfffff) * 24'h8000
                         + (ga & 20'h7fff);
        else
            banked_key = ga;
    endfunction

    // Offsets any access could have written: every guest op touches its own
    // LOW15 offset (and the next one for a word). Both sides only ever write
    // there, so comparing these cells against golden covers the whole image.
    int touched [int];

    bit pat_bad = 0;
    task automatic note_addr(input int a);
        touched[a & 24'h7fff] = 1;
        touched[(a + 1) & 24'h7fff] = 1;
        // The pattern registers are hidden state: a load divergence only
        // surfaces as wrong write data many ops later. Flag the first op
        // boundary where the two sides disagree.
        if (!pat_bad && egc_active)
            for (int p = 0; p < 4; p++) begin
                if (dut.g_egc.u_egc.patreg[p] !== 16'(golden_egc_patreg(p))) begin
                    $display("PATDIFF op#%0d plane%0d  rtl %04x  golden %04x",
                             opno, p, dut.g_egc.u_egc.patreg[p],
                             16'(golden_egc_patreg(p)));
                    pat_bad = 1;
                end
                if (dut.g_egc.u_egc.src_q[p] !== 16'(golden_egc_src(p))) begin
                    $display("SRCDIFF op#%0d plane%0d  rtl %04x  golden %04x",
                             opno, p, dut.g_egc.u_egc.src_q[p],
                             16'(golden_egc_src(p)));
                    pat_bad = 1;
                end
            end
        // The shift accounting underneath: if the queue pointers disagree
        // every later produced byte does too.
        if (!pat_bad && egc_active) begin
            int ob;
            bit dn;
            ob = golden_egc_outptr();
            dn = (golden_egc_func() & 1) != 0;
            for (int p = 0; p < 4 && !pat_bad; p++)
                // Only the live region counts: np21w's flat buf keeps stale
                // bytes beyond in/out that the window model never had.
                for (int i = 0; i < dut.g_egc.u_egc.sf_qd && !pat_bad; i++)
                    // dn runs fill buf downward from outptr; the window's
                    // head slot still faces outptr, the tail faces inptr.
                    if (dut.g_egc.u_egc.sf_q[p][i]
                        !== 8'(golden_egc_buf(
                             dn ? ob + p*4 - i : ob + p*4 + i))) begin
                        $display("QDIFF op#%0d plane%0d slot%0d  rtl %02x  golden %02x",
                                 opno, p, i, dut.g_egc.u_egc.sf_q[p][i],
                                 8'(golden_egc_buf(dn ? ob + p*4 - i
                                                     : ob + p*4 + i)));
                        pat_bad = 1;
                    end
            if (dut.g_egc.u_egc.sf_srcbit !== 4'(golden_egc_srcbit())
             || dut.g_egc.u_egc.sf_dstbit !== 4'(golden_egc_dstbit())
             || dut.g_egc.u_egc.sf_remain !== 13'(golden_egc_remain())
             || dut.g_egc.u_egc.sf_func   !== 3'(golden_egc_func())) begin
                $display({"STATEDIFF op#%0d  rtl s/d/rem/f=%0d/%0d/%0d/%0d",
                          "  golden %0d/%0d/%0d/%0d"},
                         opno, dut.g_egc.u_egc.sf_srcbit,
                         dut.g_egc.u_egc.sf_dstbit, dut.g_egc.u_egc.sf_remain,
                         dut.g_egc.u_egc.sf_func,
                         golden_egc_srcbit(), golden_egc_dstbit(),
                         golden_egc_remain(), golden_egc_func());
                pat_bad = 1;
            end
        end
        // Queue windows, when anything above flagged: golden's buf around
        // outptr vs the RTL's sliding sf_q. np21w strides planes by 4 from
        // outptr; the RTL's window head is sf_qd.
        if (pat_bad) dump_state();
        if (egcdbg && egc_active) midq(a);
    endtask

    task automatic compare_image();
        int          gaddr, k;
        logic [7:0]  tb;
        int          gv;
        int          diffs = 0;
        static int   bases [0:3] = '{20'hA8000, 20'hB0000, 20'hB8000, 20'hE0000};
        // RTL-written cells (may include offsets golden never touched -- the
        // poke/seed F ops live here too).
        foreach (store[k]) begin
            if (k >= 24'h600000)
                gaddr = bases[(k - 24'h600000) / 24'h8000] + 24'h100000
                        + ((k - 24'h600000) % 24'h8000);
            else
                gaddr = k;
            gv = golden_vram_byte(gaddr);
            tb = store[k];
            if (tb !== gv[7:0]) begin
                diffs = diffs + 1;
                if (diffs <= 40)
                    $display("VRAMDIFF op#%0d  ga %06x  got %02x  exp %02x",
                             opno, gaddr, tb, gv[7:0]);
            end
        end
        // Cells only golden could have written (an op's own offsets, both
        // pages and planes).
        foreach (touched[off])
            for (int pg = 0; pg < 2; pg++)
                for (int p = 0; p < 4; p++) begin
                    gaddr = bases[p] + pg * 24'h100000 + off;
                    gv = golden_vram_byte(gaddr);
                    k  = banked_key(gaddr);
                    tb = store.exists(k) ? store[k] : 8'h00;
                    if (tb !== gv[7:0]) begin
                        diffs = diffs + 1;
                        if (diffs <= 40)
                            $display("VRAMDIFF op#%0d  ga %06x  got %02x  exp %02x",
                                     opno, gaddr, tb, gv[7:0]);
                    end
                end
        if (diffs) begin
            errors = errors + diffs;
            $display("VRAM image: %0d bytes differ", diffs);
        end
    endtask

    // ---- stream replay -----------------------------------------------------
    task automatic replay(input int fd);
        string line, op;
        int    a, v, r, code;
        forever begin
            r = $fgets(line, fd);
            if (r == 0) break;
            line = line.tolower();
            if (line.len() == 0) continue;
            if (line[0] == "#") begin
                // "# P <n>" page markers are informational comments from the
                // recorder; a real P op also sets the page -- honor the
                // comment so comment-only streams stay faithful.
                if ($sscanf(line, "# p %x", a) == 1) op_page(a);
                continue;
            end
            code = $sscanf(line, "%s", op);
            if (code < 1) continue;
            opno = opno + 1;
            if (op == "e" && $sscanf(line, "e %x %x", a, v) == 2)
                op_ereg(a, v);
            else if (op == "gt" && $sscanf(line, "gt %x %x", a, v) == 2)
                op_gt(a, v);
            else if (op == "gm" && $sscanf(line, "gm %x", v) == 1)
                op_gm(v);
            else if (op == "p" && $sscanf(line, "p %x", v) == 1)
                op_page(v);
            else if (op == "m" && $sscanf(line, "m %x", v) == 1)
                op_mode(v);
            else if (op == "w8" && $sscanf(line, "w8 %x %x", a, v) == 2)
                op_w8(a, v);
            else if (op == "w16" && $sscanf(line, "w16 %x %x", a, v) == 2)
                op_w16(a, v);
            else if (op == "r8" && $sscanf(line, "r8 %x %x", a, v) == 2)
                op_r8(a, v);
            else if (op == "r16" && $sscanf(line, "r16 %x %x", a, v) == 2)
                op_r16(a, v);
            else if (op == "f" && $sscanf(line, "f %x %x", a, v) == 2)
                op_poke(a, v);
            else if (op == "x") begin
                compare_image();
                emit("X");
                break;
            end else
                $display("note: op#%0d skipped line: %s", opno, line);
            if (cmpmod) compare_image();
        end
    endtask

    // ---- fuzzer -------------------------------------------------------------
    // Weighted ops over all four window bases + boundary offsets; register
    // writes lean on the fields that decide datapath shape.
    function automatic int rnd(input int lo, input int hi);
        rnd = lo + ($urandom() % (hi - lo + 1));
    endfunction

    function automatic int win_base();
        case (rnd(0, 3))
            0: win_base = 20'hA8000;
            1: win_base = 20'hB0000;
            2: win_base = 20'hB8000;
            default: win_base = 20'hE0000;
        endcase
    endfunction

    function automatic int fuzz_addr();
        int pick = rnd(0, 9);
        if (pick < 2)        fuzz_addr = win_base() + rnd(0, 7);        // top edge
        else if (pick < 4)   fuzz_addr = win_base() + 20'h7ff0 + rnd(0, 15); // wrap
        else if (pick < 6)   fuzz_addr = win_base() + (rnd(0, 255) << 7) + rnd(0, 3); // row heads
        else                 fuzz_addr = win_base() + rnd(0, 20'h7fff);
    endfunction

    task automatic fuzz(input int nops, input int cmpmod);
        int i;
        for (i = 0; i < nops; i++) begin
            int sel = rnd(0, 99);
            opno = opno + 1;
            if (sel < 42) begin                       // VRAM accesses
                int a = fuzz_addr();
                int t = rnd(0, 9);
                if (t < 5)      op_w8(a, rnd(0, 255));
                else if (t < 8) op_w16(a, rnd(0, 20'hffff));
                else if (t < 9) op_r8(a, 0);
                else            op_r16(a, 0);
            end else if (sel < 62) begin              // EGC regs
                int rg = rnd(0, 15);
                int vv = (rnd(0, 3) == 0) ? rnd(0, 255)
                                          : ((rnd(0,1) ? 8'hff : 8'h00) |
                                             (rnd(0,1) ? 8'h0f : 8'hf0));
                op_ereg(rg, vv);
            end else if (sel < 68) begin              // GRCG tiles/mode
                if (rnd(0, 1)) op_gt(rnd(0, 3), {2{8'(rnd(0, 255))}});
                else           op_gm(rnd(0, 255) & 8'hcf); // stay in hw bits
            end else if (sel < 72)                    op_mode(rnd(0, 2));
            else if (sel < 76)                        op_page(rnd(0, 1));
            else if (sel < 84)                        op_poke(int'(fuzz_addr()), rnd(0, 255));
            else begin                                 // directed-ish bursts:
                int a = fuzz_addr();                   // a few fills through one
                for (int j = 0; j < rnd(2, 8); j++)    // setup are where EGC
                    op_w16(a + j * 2, rnd(0, 20'hffff)); // patterns live
            end
            if (cmpmod) compare_image();
        end
        compare_image();
        emit("X");
    endtask

    // -------------------------------------------------------------------------
    initial begin
        string sf, df;
        int    fd, seed, nops;
        // GRCG's own-mask semantics on the bench: mask bit = 1 means skip.
        // Start sane: EGC off, GRCG off, page 0.
        repeat (6) @(negedge clk);
        reset <= 1'b0;
        golden_reset();
        repeat (2) @(negedge clk);

        if (!$value$plusargs("seed=%d", seed)) seed = -1;
        if (!$value$plusargs("nops=%d", nops)) nops = 4000;
        if (!$value$plusargs("cmpmod=%d", cmpmod)) cmpmod = 0;
        egcdbg = $test$plusargs("egcdbg");
        golden_egc_dbgev(egcdbg);

        if ($value$plusargs("stream=%s", sf)) begin
            fd = $fopen(sf, "r");
            if (fd == 0) begin
                $display("FAILED: cannot open %s", sf);
                $fatal(1);
            end
            replay(fd);
            $fclose(fd);
        end else begin
            if (seed < 0) seed = $urandom();
            void'($urandom(seed));
            df = $sformatf("fuzz-%08x.ops", seed);
            if ($value$plusargs("dump=%s", df)) ;
            dump_fd = $fopen(df, "w");
            $display("fuzz seed %08x -> %s", seed, df);
            fuzz(nops, cmpmod);
            $fclose(dump_fd);
        end

        if (errors == 0) $display("PASS tb_pc98_egc_golden (%0d ops)", opno);
        else             $display("FAILED tb_pc98_egc_golden: %0d diffs (%0d ops)",
                                  errors, opno);
        $finish;
    end
endmodule
