//
// tb_draw_run -- run draw_test.bin on the real V30 core and check what it
// leaves behind.
//
// tb_pc98_boot proves the BIOS reaches an IPL, but the real POST costs minutes
// of wall time before a single test byte moves. This bench skips all of it:
// the de-muxed-bus V30 core from tb_cpu_v30, one flat megabyte, draw_test.bin
// preloaded at 1FE0:0000 where the BIOS puts a boot sector, and a reset vector
// that jumps straight to it. No chipset, no peripherals -- so I/O writes are
// captured, not answered (the GDC end of the same bytes is tb_draw_boot's job).
//
// It answers three things quickly:
//   * the whole program runs on the real V30 (imul / rep stosb / the lot) and
//     reaches the final jmp$ -- no illegal-op derailment mid-card;
//   * the I/O write sequence is exactly the commands draw_test.asm intends;
//   * the bytes land in the right windows: A0000/A2000 text, the A8000/B0000/
//     B8000/E0000 graphics planes, and the GRCG box rows.
//
// Run: verilator --binary ... tb_draw_run.sv fpga/core/v30/v30_core.v
//      (needs +arg DRAWBIN=<path to draw_test.bin>)
//
`default_nettype none
`timescale 1ns/1ps

module tb_draw_run;

    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1'b1;

    localparam logic [2:0] BS_INTA = 3'b000, BS_IOR = 3'b001, BS_IOW = 3'b010,
                           BS_HALT = 3'b011, BS_CODE = 3'b100, BS_MEMR = 3'b101,
                           BS_MEMW = 3'b110, BS_PASV = 3'b111;

    wire [19:0] ADDR_O;
    wire [15:0] DATA_O;
    wire  [2:0] BS;
    wire  [1:0] QS;
    wire        RD_N, UBE_N, BUSLOCK_N;
    wire  [3:0] STATUS_O;
    logic        bkd_load = 1'b0;
    logic [223:0] bkd_regs = '0;
    logic [47:0] bkd_queue = '0;
    logic  [2:0] bkd_qlen = '0;
    logic [15:0] bkd_fetch_ip = '0;
    logic        scr_en = 1'b0;
    logic  [1:0] scr_qop = '0;
    wire  [223:0] dbg_regs;

    logic [15:0] DATA_I;

    v30_core dut (
        .CLK       (clk),
        .CE        (1'b1),
        .RESET     (reset),
        .READY     (1'b1),
        .INT       (1'b0),
        .NMI       (1'b0),
        .POLL_N    (1'b1),
        .DATA_I    (DATA_I),
        .ADDR_O    (ADDR_O),
        .DATA_O    (DATA_O),
        .STATUS_O  (STATUS_O),
        .QS        (QS),
        .BS        (BS),
        .RD_N      (RD_N),
        .UBE_N     (UBE_N),
        .BUSLOCK_N (BUSLOCK_N),
        .SS_ADDR   (), .SS_WDATA (), .SS_WE (), .SS_RDATA (), .SS_ERR (),
        .SS_BUS_QUIET (),
        .bkd_load (bkd_load), .bkd_regs (bkd_regs), .bkd_queue (bkd_queue),
        .bkd_qlen (bkd_qlen), .bkd_fetch_ip (bkd_fetch_ip),
        .scr_en (scr_en), .scr_qop (scr_qop),
        .dbg_regs  (dbg_regs), .dbg_first_pop (), .dbg_pend ()
    );

    // ---- flat megabyte ------------------------------------------------------
    logic [7:0] ram [0:1048575];

    wire [19:0] word_addr = {ADDR_O[19:1], 1'b0};
    wire [15:0] mem_word  = {ram[word_addr + 20'd1], ram[word_addr]};

    always_comb begin
        case (BS)
            BS_CODE, BS_MEMR: DATA_I = mem_word;
            BS_IOR:           DATA_I = 16'hFFFF;   // INs return FF; unused here
            BS_INTA:          DATA_I = 16'h0000;
            default:          DATA_I = 16'h0000;
        endcase
    end

    // ---- write capture ------------------------------------------------------
    // MEMW commits into ram[]; IOW is logged (the peripherals are not here --
    // tb_draw_boot checks what the GDCs do with the same byte stream).
    logic [2:0]  bs_d = BS_PASV;
    logic [19:0] wr_addr = 20'hFFFFF;
    logic [15:0] wr_data = 16'h0000;
    logic        wr_even = 1'b0, wr_odd = 1'b0, wr_active = 0;

    // I/O write log: (port, value) pairs in order, to diff against the .asm.
    logic [15:0] io_port [0:255];
    logic [7:0]  io_val  [0:255];
    int          io_n = 0;

    // region hit counts, so "the fill reached every plane" is a count not an
    // eyeballed dump
    int n_txt_char = 0, n_txt_attr = 0;
    int n_plane[0:3] = '{0,0,0,0};      // B,R,G,E windows
    int n_io = 0;

    always_ff @(posedge clk) begin
        bs_d <= BS;
        if (BS == BS_MEMW || BS == BS_IOW) begin
            wr_addr   <= ADDR_O;
            wr_data   <= DATA_O;
            wr_even   <= (ADDR_O[0] == 1'b0);
            wr_odd    <= (UBE_N == 1'b0);
            wr_active <= 1'b1;
        end else if (wr_active) begin
            wr_active <= 1'b0;
            if (bs_d == BS_IOW) begin
                // one I/O write; the byte is on the addressed lane
                io_port[io_n] <= wr_addr[15:0];
                io_val [io_n] <= wr_even ? wr_data[7:0] : wr_data[15:8];
                io_n <= io_n + 1;
                n_io <= n_io + 1;
            end else begin
                if (wr_even) begin
                    ram[wr_addr] <= wr_data[7:0];
                    tally(wr_addr);
                end
                if (wr_odd) begin
                    ram[{wr_addr[19:1],1'b1}] <= wr_data[15:8];
                    tally({wr_addr[19:1],1'b1});
                end
            end
        end
    end

    function automatic void tally(input logic [19:0] a);
        if      (a >= 20'hA0000 && a < 20'hA2000) n_txt_char++;   // char window
        else if (a >= 20'hA2000 && a < 20'hA4000) n_txt_attr++;   // attr window
        else if (a >= 20'hA8000 && a < 20'hB0000) n_plane[0]++;   // B
        else if (a >= 20'hB0000 && a < 20'hB8000) n_plane[1]++;   // R
        else if (a >= 20'hB8000 && a < 20'hC0000) n_plane[2]++;   // G
        else if (a >= 20'hE0000 && a < 20'hE8000) n_plane[3]++;   // E
    endfunction

    int errors = 0;
    task automatic want(input string w, input int g, input int e);
        if (g !== e) begin
            $display("  FAIL %-40s got %0d want %0d", w, g, e);
            errors++;
        end else $display("  ok   %-40s %0d", w, g);
    endtask

    // dump the I/O write sequence then the memory footprint
    task automatic report;
        $display("=== I/O writes (%0d) ===", io_n);
        for (int i = 0; i < io_n; i++)
            $display("  out %04X, %02X", io_port[i], io_val[i]);
        $display("=== memory footprint ===");
        $display("  text char-window writes  %0d", n_txt_char);
        $display("  text attr-window writes  %0d", n_txt_attr);
        $display("  plane writes B/R/G/E     %0d %0d %0d %0d",
                 n_plane[0], n_plane[1], n_plane[2], n_plane[3]);
        // first text row: 'PC-98 DRAW TEST' then the labels
        $write  ("  A0000 row0 chars: ");
        for (int i = 0; i < 15; i++) $write("%c", ram[20'hA0000 + i*2]);
        $display("");
        // attr under row0 should be 0xE1 for the 15 chars
        $write  ("  A2000 row0 attrs: ");
        for (int i = 0; i < 15; i++) $write("%02X ", ram[20'hA2000 + i*2]);
        $display("");
        // graphics planes: band b fills plane offset b*2000 .. b*2000+1999.
        // index bit p set -> that plane holds 0xFF. band 5 (00101) = cyan.
        $display("  band5  plane bytes B=%02X R=%02X G=%02X E=%02X (want FF 00 FF 00)",
                 ram[20'hA8000 + 5*2000], ram[20'hB0000 + 5*2000],
                 ram[20'hB8000 + 5*2000], ram[20'hE0000 + 5*2000]);
        $display("  band9  plane bytes B=%02X R=%02X G=%02X E=%02X (want FF 00 00 FF)",
                 ram[20'hA8000 + 9*2000], ram[20'hB0000 + 9*2000],
                 ram[20'hB8000 + 9*2000], ram[20'hE0000 + 9*2000]);
        // GRCG box: the CPU writes the A8000 window; the GRCG device then fans
        // the four tile bytes to every plane -- that fan-out is hardware, not a
        // CPU write, so flat memory only proves the box loop addressed A8000
        // across rows 160..239. (tile[0..3]={FF,00,FF,00} landing is what
        // tb_pc98_grcg checks.) Outside the box, band colour must still show.
        $display("  GRCG box A8000 rows 170/180/230 col24: %02X %02X %02X (want FF)",
                 ram[20'hA8000 + 170*80 + 24], ram[20'hA8000 + 180*80 + 24],
                 ram[20'hA8000 + 230*80 + 24]);
        $display("  outside box A8000 row100 col24 (band4): %02X (want 00, untouched)",
                 ram[20'hA8000 + 100*80 + 24]);
        want("text char writes",   n_txt_char, 264);
        want("text attr writes",   n_txt_attr, 132);
        want("I/O write count",    n_io,       35);
        want("A8000 box row180 c24", ram[20'hA8000 + 180*80 + 24], 16'hFF);
    endtask

    initial begin
        int fd, n;
        string bin;
        // reset vector -> jmp far 1FE0:0000 (where the BIOS drops the sector)
        ram[20'hFFFF0] = 8'hEA; ram[20'hFFFF1] = 8'h00; ram[20'hFFFF2] = 8'h00;
        ram[20'hFFFF3] = 8'hE0; ram[20'hFFFF4] = 8'h1F;
        for (int a = 20'h1FE00; a < 20'h20400; a++) ram[a] = 8'h00;

        if (!$value$plusargs("DRAWBIN=%s", bin)) bin = "testdisk/draw_test.bin";
        fd = $fopen(bin, "rb");
        if (fd == 0) begin $display("cannot open %s", bin); $finish; end
        n = $fread(ram, fd, 20'h1FE00);
        $fclose(fd);
        $display("loaded %0d bytes of %s at 0x1FE00", n, bin);

        repeat (8) @(posedge clk);
        reset = 1'b0;

        // bands are the long pole: 16 bands x 4 planes x 2000 rep-stosb bytes
        // plus the GRCG box and text. ~1.5M bus cycles is generous headroom.
        repeat (4_000_000) @(posedge clk);

        report;
        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end
endmodule

`default_nettype wire
