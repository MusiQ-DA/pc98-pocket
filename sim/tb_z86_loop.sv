// tb_z86_loop -- z86 alone on a fixed-latency Wishbone memory: how many
// clocks does `loop $` cost, and how many bus reads does it make?
//
// Program at +org=<hex> (default 00400, reached by a far jump from the
// reset vector): mov cx,N ; loop $ ; hlt. Every Wishbone cycle is acked
// LAT clocks after it is raised (one edge wide, as zet_cpu_bridge does).
//
// Build: see scripts/sim_z86_loop.sh.
`timescale 1ns/1ps
module tb_z86_loop;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;

    wire [19:1] adr; wire [1:0] sel; wire we, tga, stb, cyc, tgc_o;
    wire [15:0] dat_o; logic [15:0] dat_i; logic ack = 0;
    wire [19:0] pc; wire halted;

    z86 u (.clk(clk), .reset(reset), .wb_adr_o(adr), .wb_sel_o(sel),
           .wb_we_o(we), .wb_tga_o(tga), .wb_dat_o(dat_o), .wb_stb_o(stb),
           .wb_cyc_o(cyc), .wb_ack_i(ack), .wb_dat_i(dat_i),
           .wb_tgc_i(1'b0), .wb_tgc_o(tgc_o), .pc(pc), .dbg_ds(),
           .dbg_halted(halted));

    logic [7:0] mem [0:1048575];
    int lat = 4, n = 1000;
    logic [19:0] org = 20'h00400;
    string prog, dumpf;
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
            for (int i = 0; i < 256; i++) begin
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
        ack <= 1'b0;
        if (!reset && stb && !ack) begin
            cnt <= cnt + 1;
            if (cnt + 1 >= lat) begin
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
                end else begin
                    rd_n++;
                    dat_i <= {mem[{adr,1'b1}], mem[{adr,1'b0}]};
                end
            end
        end else if (!stb) cnt <= 0;
    end

    longint cyc_n = 0;
    always @(posedge clk) begin
        if (!reset) cyc_n++;
        if (halted) begin
            $display("n=%0d lat=%0d: %0d clocks, %0d reads, %0d writes -> %0.1f clk/iter",
                     n, lat, cyc_n, rd_n, wr_n, real'(cyc_n) / n);
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
            if ($value$plusargs("dump=%s", dumpf)) $writememh(dumpf, mem, 0, 20'h3FFF);
            $finish;
        end
        if (cyc_n > 10_000_000) begin
            $display("TIMEOUT pc=%05x reads=%0d", pc, rd_n);
            $finish;
        end
    end
endmodule
