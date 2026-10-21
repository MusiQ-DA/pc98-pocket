// tb_z86_loop -- z86 alone on a fixed-latency Wishbone memory: how many
// clocks does `loop $` cost, and how many bus reads does it make?
//
// Program at +org=<hex> (default 00400, reached by a far jump from the
// reset vector): mov cx,N ; loop $ ; hlt. Every Wishbone cycle is acked
// LAT clocks after it is raised (one edge wide, as cpu_bus_bridge does).
//
// Build: see scripts/sim_z86_loop.sh.
`timescale 1ns/1ps
module tb_z86_loop;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;

    wire [19:1] adr; wire [1:0] sel; wire we, tga, stb, cyc, tgc_o;
    wire [15:0] dat_o; logic [15:0] dat_i; logic ack = 0;
    wire [19:0] pc; wire halted;

    // +gate: stop the core's clock at random, the way cpu_bus_bridge gates
    // it, so z86_cache's ce qualification is exercised. run_arm changes on
    // the falling edge only, like the bridge's.
    int gate = 0;
    initial if ($test$plusargs("gate")) gate = 1;
    logic run_arm = 1'b1;
    always @(negedge clk) run_arm <= gate ? ($urandom % 4 != 0) : 1'b1;
    wire zclk = clk & (run_arm | reset);
    wire zce  = run_arm | reset;
    // +nocache: z86_cache's enable low -- every access takes the Wishbone.
    int nocache = 0;
    initial if ($test$plusargs("nocache")) nocache = 1;

    // sdram_mp port F: req held until ack, then the burst's beats, then done.
    wire f_req, f_we; wire [23:0] f_addr; wire [3:0] f_len;
    wire [15:0] f_wd0, f_wd1;
    logic f_ack = 0, f_rvalid = 0, f_done = 0; logic [15:0] f_rdata;
    logic sn_v = 0; logic [23:0] sn_addr = 0; logic [3:0] sn_len = 0;
    int f_rd_n = 0, f_wr_n = 0;
    always @(posedge clk) begin : port_f
        f_ack <= 0; f_rvalid <= 0; f_done <= 0;
        if (f_req && !f_ack) begin
            // arbitration + ACTIVATE: 3..(3+lat) clocks
            repeat (3 + (latrand ? ($urandom % (lat + 1)) : lat)) @(posedge clk);
            f_ack <= 1;
            @(posedge clk); f_ack <= 0;
            repeat (2) @(posedge clk);
            if (f_we) begin
                f_wr_n++;
                mem[f_addr[19:0]] <= f_wd0[7:0];
                if (wlog != 0) $fdisplay(wlog, "%05x %02x", f_addr[19:0], f_wd0[7:0]);
                if (f_len == 4'd1) begin
                    mem[f_addr[19:0] + 20'd1] <= f_wd1[7:0];
                    if (wlog != 0) $fdisplay(wlog, "%05x %02x", f_addr[19:0] + 20'd1, f_wd1[7:0]);
                end
                @(posedge clk);
            end else begin
                f_rd_n++;
                for (int i = 0; i <= f_len; i++) begin
                    f_rvalid <= 1; f_rdata <= {8'h00, mem[f_addr[19:0] + 20'(i)]};
                    @(posedge clk);
                end
                f_rvalid <= 0;
            end
            f_done <= 1;
        end
    end

    z86 u (.clk(zclk), .reset(reset), .clk_free(clk), .ce(zce), .cache_en(nocache == 0),
           .bios_shadow(1'b0), .bios_protect(1'b0),
           .f_req(f_req), .f_we(f_we), .f_addr(f_addr), .f_len(f_len),
           .f_wdata0(f_wd0), .f_wdata1(f_wd1), .f_ack(f_ack), .f_rvalid(f_rvalid),
           .f_rdata(f_rdata), .f_done(f_done), .sn_v(sn_v), .sn_addr(sn_addr), .sn_len(sn_len),
           .dbg_watch_a(20'h0), .dbg_sn_kills(),
           .wb_adr_o(adr), .wb_sel_o(sel),
           .wb_we_o(we), .wb_tga_o(tga), .wb_dat_o(dat_o), .wb_stb_o(stb),
           .wb_cyc_o(cyc), .wb_ack_i(ack), .wb_dat_i(tgc_o ? {8'h00, irq_vec} : dat_i),
           .wb_tgc_i(intr), .wb_tgc_o(tgc_o), .pc(pc), .dbg_ds(), .dbg_regs(), .dbg_stop(1'b0), .dbg_stopped(), .dbg_next_ip(),
           .dbg_halted(halted));

    logic [7:0] mem [0:1048575];
    int lat = 4, n = 1000, cur_lat = 4, latrand = 0;
    initial if ($test$plusargs("latrand")) latrand = 1;
    logic [19:0] org = 20'h00400;
    string prog, dumpf, memf;
    logic [19:0] stop_pc = 20'hFFFFF;
    initial void'($value$plusargs("stop_pc=%h", stop_pc));
    logic [7:0] pbuf [0:4095];
    initial for (int i = 0; i < 4096; i++) pbuf[i] = 8'hF4;
    int rd_n = 0, wr_n = 0, cnt = 0;
    // +wlog=<file>: every byte the CPU writes, in bus order (z86_fuzz.py
    // diffs it against the reference's write stream to find the first
    // wrong store).
    int wlog = 0;
    string wlogf;
    initial begin
        if ($value$plusargs("wlog=%s", wlogf)) wlog = $fopen(wlogf, "w");
        void'($value$plusargs("lat=%d", lat));
        void'($value$plusargs("n=%d", n));
        for (int i = 0; i < 1048576; i++) mem[i] = 8'h90;
        void'($value$plusargs("org=%h", org));
        // +mem=<hex file>: a whole 1 MB image (one byte per line) under the
        // program -- a RAM dump from hardware plus ROMs, for replaying a call.
        if ($value$plusargs("mem=%s", memf)) $readmemh(memf, mem);
        // FFFF0: jmp {org[19:16],000}:{org[15:0]} -- or, with +org=ffff0,
        // the program sits at the reset vector itself.
        if (org != 20'hFFFF0) begin
            mem[20'hFFFF0] = 8'hEA; mem[20'hFFFF1] = org[7:0]; mem[20'hFFFF2] = org[15:8];
            mem[20'hFFFF3] = 8'h00; mem[20'hFFFF4] = {org[19:16], 4'h0};
        end
        // org: mov cx,n ; loop $ ; hlt -- or +prog=<hex> (one byte per line)
        if ($value$plusargs("prog=%s", prog)) begin
            $readmemh(prog, pbuf);
            for (int i = 0; i < 4096; i++) mem[org+i] = pbuf[i];
            // data the program may walk: word i at 0800+2i = i*0x0123+0x4567
            if (memf.len() == 0) for (int i = 0; i < 256; i++) begin
                logic [15:0] w;
                w = i * 16'h0123 + 16'h4567;
                mem[20'h00800 + 2*i] = w[7:0]; mem[20'h00801 + 2*i] = w[15:8];
            end
        end else begin
            mem[org+0] = 8'hB9; mem[org+1] = n[7:0]; mem[org+2] = n[15:8];
            mem[org+3] = 8'hE2; mem[org+4] = 8'hFE;
            mem[org+5] = 8'hF4;
        end
        repeat (5) @(posedge clk);
        reset = 0;
    end

    always @(posedge clk) begin
        // ack stays up until a gated-clock edge has seen it (cpu_bus_bridge
        // presents it for exactly one edge of the core's clock)
        ack <= ack & ~zce;
        sn_v <= 1'b0;
        if (f0reset && !reset && stb && we && tga && {adr,1'b0} == 20'h000F0) begin
            // +f0reset: OUT 0F0h resets the CPU before its cycle is acked,
            // the order the PC-98 bus gives at 10 MHz
            reset <= 1'b1;
            repeat (40) @(posedge clk);
            reset <= 1'b0;
        end else if (!reset && stb && !ack) begin
            cnt <= cnt + 1;
            if (cnt + 1 >= cur_lat) begin
                cnt <= 0;
                ack <= 1'b1;
                if (we) begin
                    wr_n++;
                    if (wlog != 0) begin
                        if (sel[0]) $fdisplay(wlog, "%05x %02x", {adr,1'b0}, dat_o[7:0]);
                        if (sel[1]) $fdisplay(wlog, "%05x %02x", {adr,1'b1}, dat_o[15:8]);
                    end
                    if (sel[0]) mem[{adr,1'b0}] <= dat_o[7:0];
                    if (sel[1]) mem[{adr,1'b1}] <= dat_o[15:8];
                    // a memory write through the bus commits on port A:
                    // the cache's snoop sees it
                    if (!tga) begin
                        sn_v    <= 1'b1;
                        sn_addr <= {4'h0, adr, ~sel[0]};
                        sn_len  <= (sel == 2'b11) ? 4'd1 : 4'd0;
                    end
                end else begin
                    rd_n++;
                    dat_i <= {mem[{adr,1'b1}], mem[{adr,1'b0}]};
                end
            end
        end else if (!stb) begin
            cnt <= 0;
            // +latrand: each access waits 1..lat clocks, so loads, stores
            // and branches meet in every order (the in-flight-load-vs-branch
            // fetch bug only shows with uneven latency)
            cur_lat <= latrand ? 1 + ($urandom % lat) : lat;
        end
    end

    // +irq=<clocks>: raise INTR every that many clocks (held until the
    // acknowledge, like an 8259 output), vector +vec=<hex> (default 20h).
    // The vector rides wb_dat_i during the wb_tgc_o pulse. Lets the fuzzer
    // check that interrupts landing anywhere -- mid-REP, between prefixes,
    // inside microcode -- leave the program's results unchanged.
    int irq_period = 0, irq_cnt = 0, irq_n = 0;
    logic [7:0] irq_vec = 8'h20;
    logic intr = 1'b0;
    initial begin
        void'($value$plusargs("irq=%d", irq_period));
        void'($value$plusargs("vec=%h", irq_vec));
    end
    // +irqclr: an OUT to port 70h/71h withdraws a pending INTR, the way a
    // PIT channel-0 write clears the PC-98 master's IRR0 (and a mask write
    // drops INT). An acknowledge with INTR already low is what an 8259
    // answers with IRQ7's vector -- counted as spurious; the CPU must sample
    // INTR at an instruction boundary, after that OUT, and never ask.
    int spurious_n = 0;
    logic irqclr = 1'b0;
    initial irqclr = $test$plusargs("irqclr");
    always @(posedge clk) begin
        if (tgc_o) begin
            if (!intr) spurious_n++;
            intr <= 1'b0; irq_n++;
        end else if (irqclr && stb && ack && we && tga && adr == 19'h38) intr <= 1'b0;
        else if (!reset && irq_period != 0) begin
            irq_cnt <= irq_cnt + 1;
            if (irq_cnt + 1 >= irq_period) begin irq_cnt <= 0; intr <= 1'b1; end
        end
    end

    // +rst_at=<clock>: one CPU reset (5 clocks) mid-run, as OUT 0F0h does on
    // the PC-98 -- the program must restart and still finish.
    longint rst_at = 0;
    logic   rst_on_halt = 1'b0, rst_done = 1'b0, f0reset = 1'b0;
    initial f0reset = $test$plusargs("f0reset");
    initial rst_on_halt = $test$plusargs("rst_on_halt");
    initial void'($value$plusargs("rst_at=%d", rst_at));
    longint cyc_n = 0;
    always @(posedge clk)
        if (rst_at != 0 && cyc_n == rst_at) begin
            reset <= 1'b1;
            repeat (5) @(posedge clk);
            reset <= 1'b0;
        end
    // +ctrace: every request z86_cache answers, as the core sees it.
    int ctrace = 0;
    initial if ($test$plusargs("ctrace")) ctrace = 1;
    always @(posedge clk) if (ctrace && !reset) begin
        if (u.u_cache.wr_ready && zce)
            $display("%0d WR %05x %04x w%0d io%0d", cyc_n, u.u_cache.wr_addr, u.u_cache.wr_data, u.u_cache.wr_word, u.u_cache.wr_io);
        if (u.u_cache.rd && zce)
            $display("%0d RDREQ %05x w%0d io%0d", cyc_n, u.u_cache.rd_addr, u.u_cache.rd_word, u.u_cache.rd_io);
        if (u.u_cache.rd_ready && !$past(u.u_cache.rd_ready))
            $display("%0d RDDATA %04x", cyc_n, u.u_cache.rd_data);
        if (u.u_cache.ld_ack != $past(u.u_cache.ld_ack))
            $display("%0d LD %05x", cyc_n, u.u_cache.ld_addr);
    end
    // With +irq a HLT is only the end once it has outlasted two interrupt
    // periods: an interrupt IF admits wakes it.
    int halt_n = 0;
    always @(posedge clk) halt_n <= halted ? halt_n + 1 : 0;
    always @(posedge clk) begin
        if (!reset) cyc_n++;
        if (rst_on_halt && halted && !rst_done) begin
            // +rst_on_halt: the first HLT gets a CPU reset, as the ITF's
            // OUT 0F0h / HLT does; the program must come back from FFFF0.
            rst_done <= 1'b1;
            reset <= 1'b1;
            repeat (40) @(posedge clk);
            reset <= 1'b0;
        end else if (((halted && (irq_period == 0 || halt_n > 2 * irq_period))
                      || (stop_pc != 20'hFFFFF && pc == stop_pc)) && !u.cache_busy) begin
            // (the cache's write buffer drained first: memory is final)
            if (!halted) $display("STOP at %05x", pc);
            if (irq_period != 0) $display("interrupts taken: %0d spurious: %0d", irq_n, spurious_n);
            $display("n=%0d lat=%0d: %0d clocks, %0d reads, %0d writes -> %0.1f clk/iter",
                     n, lat, cyc_n, rd_n, wr_n, real'(cyc_n) / n);
            $display("port F: %0d fills, %0d writes", f_rd_n, f_wr_n);
            for (int a = 0; a < 20'h20000; a += 2)
                if ({mem[a+1], mem[a]} == 16'hA000)
                    $display("A000 found at %05x", a);
            $write("mem 0700:");
            for (int i = 0; i < 32; i++) $write(" %02x%02x", mem[20'h701 + 2*i], mem[20'h700 + 2*i]);
            $display("");
            $write("mem 0600:");
            for (int i = 0; i < 32; i++) $write(" %02x", mem[20'h600 + i]);
            $display("");
            // +dump=<file>: 0000-3FFF as hex, for diffing against a reference
            // emulator (scripts/z86_fuzz.py).
            if ($value$plusargs("dump=%s", dumpf))
                $writememh(dumpf, mem, 0, memf.len() ? 20'h9FFFF : 20'h3FFF);
            $display("REGS AX=%04X BX=%04X CX=%04X DX=%04X SI=%04X DI=%04X BP=%04X SP=%04X DS=%04X ES=%04X SS=%04X CS=%04X FL=%04X",
                     u.u_regfile.regs[0], u.u_regfile.regs[3], u.u_regfile.regs[1], u.u_regfile.regs[2],
                     u.u_regfile.regs[6], u.u_regfile.regs[7], u.u_regfile.regs[5], u.u_regfile.regs[4],
                     u.seg_DS, u.seg_ES, u.seg_SS, u.seg_CS, u.u_execute.reg_f);
            $finish;
        end
        if (cyc_n > 10_000_000) begin
            $display("TIMEOUT pc=%05x reads=%0d interrupts=%0d spurious: %0d", pc, rd_n, irq_n, spurious_n);
            $finish;
        end
    end
endmodule
