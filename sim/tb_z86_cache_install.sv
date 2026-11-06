// tb_z86_cache_install -- z86_cache's whole-line install from a store
// combine bank (WCOMB) against a store to ANOTHER line at the same index.
//
// The install's tag/data writes are registered: they land the edge after
// the bank's f_done. A lookup S_IDLE starts on the f_done edge reads the
// old occupant; if that is a cached store hit, its patch lands after the
// install -- the store's bytes went into the installed line, under its
// valid tag (#1047 286-10MHz SuperDepth START failure, slot 0x09 bit 23).
//
// Each round: line X is cached (read fill), 16 bytes are stored into line
// Y = X + 16 KB (same index) so its bank goes out whole and installs, and
// one byte is stored into X d clocks after Y's last store, for every d in
// 0..DMAX so one of them lands on the f_done edge. Then X and Y read back.
//
// Build/run: scripts/sim_z86_cache_install.sh
`timescale 1ns/1ps
module tb_z86_cache_install;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;

    logic [19:0] rd_addr = 0; logic rd = 0; wire rd_ready; wire [15:0] rd_data;
    logic [19:0] wr_addr = 0; logic wr_valid = 0; wire wr_ready;
    logic [15:0] wr_data = 0; logic wr_word = 0;
    logic [19:0] ld_addr = 0; logic ld_req = 0; wire ld_ack; wire [127:0] ld_data;
    wire [19:1] wb_adr; wire [1:0] wb_sel; wire wb_we, wb_tga, wb_stb, wb_cyc;
    wire [15:0] wb_dat; logic wb_ack = 0;
    always @(posedge clk) wb_ack <= wb_stb && !wb_ack;

    logic [7:0] mem [0:20'hFFFFF];
    wire  f_req, f_we; wire [23:0] f_addr; wire [3:0] f_len;
    wire  [15:0] f_wd0, f_wd1;
    logic f_ack = 0, f_rvalid = 0, f_done = 0;
    logic [15:0] f_rdata = 0;
    logic [4:0]  f_wcnt = 0;
    wire busy;

    z86_cache #(.WCOMB(1'b1)) dut (
        .clk(clk), .ce(1'b1), .reset(reset), .cache_en(1'b1), .pace(1'b0), .pace_ce(1'b0),
        .pace_rd_wait(2'd0), .pace_wr_wait(2'd0), .pace_vwait(5'd0), .dx(4'd0),
        .bios_shadow(1'b0), .bios_protect(1'b0),
        .f_req(f_req), .f_we(f_we), .f_addr(f_addr), .f_len(f_len),
        .f_wdata0(f_wd0), .f_wdata1(f_wd1), .f_wcnt(f_wcnt),
        .f_ack(f_ack), .f_rvalid(f_rvalid), .f_rdata(f_rdata), .f_done(f_done),
        .sn_v(1'b0), .sn_addr(24'h0), .sn_len(4'h0),
        .dbg_watch_a(20'h0), .dbg_sn_kills(),
        .busy(busy),
        .a20(1'b0), .ld_addr({4'h0, ld_addr}), .ld_req(ld_req), .ld_ack(ld_ack), .ld_data(ld_data),
        .rd_addr(rd_addr), .rd(rd), .rd_ready(rd_ready), .rd_data(rd_data),
        .rd_io(1'b0), .rd_word(1'b0),
        .wr_addr(wr_addr), .wr_valid(wr_valid), .wr_ready(wr_ready),
        .wr_data(wr_data), .wr_word(wr_word), .wr_io(1'b0),
        .wb_adr_o(wb_adr), .wb_sel_o(wb_sel), .wb_we_o(wb_we),
        .wb_tga_o(wb_tga), .wb_dat_o(wb_dat), .wb_stb_o(wb_stb),
        .wb_cyc_o(wb_cyc), .wb_ack_i(wb_ack), .wb_dat_i(16'h0),
        .dbg_wr_v(), .dbg_wr_a0(), .dbg_wr_two()
    );

    // port F: a write burst takes its bytes by f_wcnt, as sdram_mp's p_wcnt
    always @(posedge clk) begin
        f_ack <= 0; f_rvalid <= 0; f_done <= 0;
        if (f_req && !f_ack) begin
            repeat (2) @(posedge clk);
            f_ack <= 1;
            @(posedge clk);
            f_ack <= 0;
            if (f_we) begin
                for (int w = 0; w <= f_len; w++) begin
                    f_wcnt = 5'(w);
                    #1;
                    mem[f_addr[19:0] + 20'(w)] = (w == 0) ? f_wd0[7:0] : f_wd1[7:0];
                    @(posedge clk);
                end
                f_wcnt = 0;
                @(posedge clk);
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

    task cpu_read(input logic [19:0] a, output logic [7:0] d);
        @(posedge clk); rd_addr = a; rd = 1;
        @(posedge clk); rd = 0;
        @(posedge clk);
        while (!rd_ready) @(posedge clk);
        d = rd_data[7:0];
    endtask
    task cpu_write(input logic [19:0] a, input logic [15:0] v, input logic w);
        @(posedge clk); wr_addr = a; wr_data = v; wr_word = w; wr_valid = 1;
        @(posedge clk);
        while (!wr_ready) @(posedge clk);
        wr_valid = 0; wr_word = 0;
    endtask
    task drain;
        repeat (2) @(posedge clk);
        while (busy || f_req) @(posedge clk);
        repeat (4) @(posedge clk);
    endtask

    localparam int DMAX = 80;
    int errors = 0;
    logic [7:0] got;

    initial begin
        for (int i = 0; i < 21'h100000; i++) mem[i] = 8'h5A;
        repeat (5) @(posedge clk);
        reset = 0;
        repeat (1200) @(posedge clk);
        for (int d = 0; d <= DMAX; d++) begin
            automatic logic [19:0] x = 20'h20000 + 20'(d) * 20'h10;
            automatic logic [19:0] y = x + 20'h04000;
            for (int i = 0; i < 16; i++) begin
                mem[x + 20'(i)] = 8'h10 + 8'(i);
                mem[y + 20'(i)] = 8'h5A;
            end
            cpu_read(x, got);                       // X cached
            for (int i = 0; i < 16; i += 2)         // Y's bank, whole line
                cpu_write(y + 20'(i), {8'hB1 + 8'(i), 8'hB0 + 8'(i)}, 1'b1);
            repeat (d) @(posedge clk);
            cpu_write(x + 20'd3, 16'h00EE, 1'b0);   // X store, d clocks on
            drain();
            for (int i = 0; i < 16; i++) begin
                automatic logic [7:0] ey = 8'hB0 + 8'(i);
                automatic logic [7:0] ex = (i == 3) ? 8'hEE : 8'h10 + 8'(i);
                cpu_read(y + 20'(i), got);
                if (got !== ey) begin
                    errors++;
                    $display("FAIL d=%0d: Y+%0d read %02x expected %02x", d, i, got, ey);
                end
                if (mem[x + 20'(i)] !== ex) begin
                    errors++;
                    $display("FAIL d=%0d: X+%0d in memory %02x expected %02x", d, i, mem[x + 20'(i)], ex);
                end
            end
            cpu_read(x + 20'd3, got);
            if (got !== 8'hEE) begin
                errors++;
                $display("FAIL d=%0d: X+3 read %02x expected ee", d, got);
            end
        end
        // Round 2: a store into the SAME line as a whole bank that is
        // already on its way out (age, a fill, the launch edge). It cannot
        // merge, so it swaps into the other bank and patches the cached
        // line -- and the leaving bank's install must not then put the
        // older bytes back over it.
        for (int d = 0; d <= DMAX; d++) begin
            automatic logic [19:0] y = 20'h40000 + 20'(d) * 20'h10;
            for (int i = 0; i < 16; i++) mem[y + 20'(i)] = 8'h5A;
            cpu_read(y, got);                       // Y cached
            for (int i = 0; i < 16; i += 2)
                cpu_write(y + 20'(i), {8'hB1 + 8'(i), 8'hB0 + 8'(i)}, 1'b1);
            repeat (d) @(posedge clk);
            cpu_write(y + 20'd3, 16'h00EE, 1'b0);
            drain();
            for (int i = 0; i < 16; i++) begin
                automatic logic [7:0] ey = (i == 3) ? 8'hEE : 8'hB0 + 8'(i);
                cpu_read(y + 20'(i), got);
                if (got !== ey) begin
                    errors++;
                    $display("FAIL r2 d=%0d: Y+%0d read %02x expected %02x", d, i, got, ey);
                end
                if (mem[y + 20'(i)] !== ey) begin
                    errors++;
                    $display("FAIL r2 d=%0d: Y+%0d in memory %02x expected %02x", d, i, mem[y + 20'(i)], ey);
                end
            end
        end
        if (errors == 0) $display("PASS: line install vs aliasing store, d=0..%0d", DMAX);
        else $display("TOTAL FAILURES: %0d", errors);
        $finish(errors != 0);
    end
    initial begin #20000000; $display("FAIL: timeout"); $finish(1); end
endmodule
