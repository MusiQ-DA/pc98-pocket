// tb_v30_ea_disp16 -- does the nuV30 compute [reg+disp16] effective addresses?
//
// Measured in the full-machine boot (sim/tb_pc98_v30.sv, run keys1): N88-BASIC
// prints a character and then blanks it, every character, and the screen ends
// up empty. The two instructions are BASIC's character-output tail at F4912:
//
//   F4912  26 89 05        MOV ES:[DI],AX          ; the character   -> cell N
//   F4915  26 88 BD 00 20  MOV ES:[DI+2000h],BH    ; the attribute   -> cell N  (!)
//
// The attribute plane on a PC-98 is 0x2000 above the code plane, and BH is the
// attribute byte (0x20 = plain green). Landing it at the CHARACTER address
// overwrites the character with 0x20, which renders as a space -- a machine
// that boots, runs, echoes keys, and shows a blank screen.
//
// So: feed the real core that instruction and the near-miss forms around it,
// and print where each store actually goes. mod=10 (disp16) against every r/m,
// with mod=01 (disp8) and mod=00 (no disp) as controls.
//
// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps
`default_nettype none

module tb_v30_ea_disp16;

    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic reset = 1'b1;

    localparam logic [2:0] BS_INTA = 3'b000, BS_IOR = 3'b001, BS_IOW = 3'b010,
                           BS_HALT = 3'b011, BS_CODE = 3'b100, BS_MEMR = 3'b101,
                           BS_MEMW = 3'b110, BS_PASV = 3'b111;

    logic [19:0] ADDR_O;
    logic [15:0] DATA_O;
    logic  [2:0] STATUS_O;
    logic  [3:0] QS;
    logic  [2:0] BS;
    logic        RD_N, UBE_N, BUSLOCK_N;

    logic         bkd_load = 1'b0;
    logic [223:0] bkd_regs = '0;
    logic  [47:0] bkd_queue = '0;
    logic   [2:0] bkd_qlen = '0;
    logic  [15:0] bkd_fetch_ip = '0;
    logic         scr_en = 1'b0;
    logic   [1:0] scr_qop = '0;
    wire  [223:0] dbg_regs;

    logic [15:0] DATA_I_i;

    v30_core dut (
        .CLK       (clk),
        .CE        (1'b1),
        .RESET     (reset),
        .READY     (1'b1),
        .INT       (1'b0),
        .NMI       (1'b0),
        .POLL_N    (1'b1),
        .DATA_I    (DATA_I_i),
        .ADDR_O    (ADDR_O),
        .DATA_O    (DATA_O),
        .STATUS_O  (STATUS_O),
        .QS        (QS),
        .BS        (BS),
        .RD_N      (RD_N),
        .UBE_N     (UBE_N),
        .BUSLOCK_N (BUSLOCK_N),
        .SS_ADDR (), .SS_WDATA (), .SS_WE (), .SS_RDATA (), .SS_ERR (),
        .SS_BUS_QUIET (),
        .bkd_load (bkd_load), .bkd_regs (bkd_regs), .bkd_queue (bkd_queue),
        .bkd_qlen (bkd_qlen), .bkd_fetch_ip (bkd_fetch_ip),
        .scr_en (scr_en), .scr_qop (scr_qop),
        .dbg_regs  (dbg_regs), .dbg_first_pop (), .dbg_pend ()
    );

    logic [7:0] ram [0:1048575];
    wire [19:0] word_addr = {ADDR_O[19:1], 1'b0};
    wire [15:0] mem_word  = {ram[word_addr + 20'd1], ram[word_addr]};

    always_comb begin
        case (BS)
            BS_CODE, BS_MEMR: DATA_I_i = mem_word;
            BS_IOR:           DATA_I_i = 16'hFFFF;
            BS_INTA:          DATA_I_i = 16'h0000;
            default:          DATA_I_i = 16'h0000;
        endcase
    end

    // ---- the write log: one entry per memory write cycle --------------------
    logic [19:0] wr_a   [0:63];
    logic [15:0] wr_d   [0:63];
    logic        wr_w   [0:63];       // both lanes live == a word store
    int          wr_n = 0;

    logic [19:0] wr_addr = 20'hFFFFF;
    logic [15:0] wr_data = 16'h0000;
    logic        wr_even = 1'b0, wr_odd = 1'b0, wr_active = 1'b0;

    always_ff @(posedge clk) begin
        if (BS == BS_MEMW) begin
            wr_addr   <= ADDR_O;
            wr_data   <= DATA_O;
            wr_even   <= (ADDR_O[0] == 1'b0);
            wr_odd    <= (UBE_N == 1'b0);
            wr_active <= 1'b1;
        end else if (wr_active) begin
            if (wr_n < 64) begin
                wr_a[wr_n] <= wr_addr;
                wr_d[wr_n] <= wr_data;
                wr_w[wr_n] <= wr_even & wr_odd;
                wr_n       <= wr_n + 1;
            end
            if (wr_even) ram[wr_addr]        <= wr_data[7:0];
            if (wr_odd)  ram[{wr_addr[19:1], 1'b1}] <= wr_data[15:8];
            wr_active <= 1'b0;
        end
    end

    // ---- the program --------------------------------------------------------
    //
    // ES = 0x2000 (base 0x20000), DI = 0x0004, SI = 0x0006, BX = 0x20AA
    // (so BH = 0x20, the attribute byte), BP = 0x0008, AX = 0x1234.
    //
    // Every store carries the ES: prefix, so [BP+disp] is ES-relative too and
    // every expected address below is ES base + offset.
    localparam int NSTORE = 8;
    logic [19:0] want_a [0:NSTORE-1];
    string       want_s [0:NSTORE-1];

    int i, bad;

    task automatic emit(input int unsigned at, input int unsigned n,
                        input logic [7:0] b0, input logic [7:0] b1,
                        input logic [7:0] b2, input logic [7:0] b3,
                        input logic [7:0] b4);
        begin
            ram[20'(at + 0)] = b0;
            if (n > 1) ram[20'(at + 1)] = b1;
            if (n > 2) ram[20'(at + 2)] = b2;
            if (n > 3) ram[20'(at + 3)] = b3;
            if (n > 4) ram[20'(at + 4)] = b4;
        end
    endtask

    initial begin
        int p;
        for (i = 0; i < 1048576; i = i + 1) ram[i] = 8'h00;

        p = 20'hF0000;
        // 1: the ROM's own instruction -- MOV ES:[DI+2000h],BH
        emit(p, 5, 8'h26, 8'h88, 8'hBD, 8'h00, 8'h20); p += 5;
        want_a[0] = 20'h22004; want_s[0] = "MOV ES:[DI+2000h],BH  (mod=10 rm=101, 8-bit)";
        // 2: the same effective address, 16-bit store
        emit(p, 5, 8'h26, 8'h89, 8'h85, 8'h00, 8'h20); p += 5;
        want_a[1] = 20'h22004; want_s[1] = "MOV ES:[DI+2000h],AX  (mod=10 rm=101, 16-bit)";
        // 3: a different disp16, to separate "disp16 dropped" from "0x2000 special"
        emit(p, 5, 8'h26, 8'h88, 8'hBD, 8'h00, 8'h10); p += 5;
        want_a[2] = 20'h21004; want_s[2] = "MOV ES:[DI+1000h],BH  (mod=10 rm=101, 8-bit)";
        // 4: disp8 control
        emit(p, 4, 8'h26, 8'h88, 8'h7D, 8'h20, 8'h00); p += 4;
        want_a[3] = 20'h20024; want_s[3] = "MOV ES:[DI+20h],BH    (mod=01 rm=101, disp8)";
        // 5: no-displacement control
        emit(p, 3, 8'h26, 8'h88, 8'h3D, 8'h00, 8'h00); p += 3;
        want_a[4] = 20'h20004; want_s[4] = "MOV ES:[DI],BH        (mod=00 rm=101)";
        // 6-8: the other disp16 r/m forms
        emit(p, 5, 8'h26, 8'h88, 8'hBC, 8'h00, 8'h20); p += 5;
        want_a[5] = 20'h22006; want_s[5] = "MOV ES:[SI+2000h],BH  (mod=10 rm=100)";
        emit(p, 5, 8'h26, 8'h88, 8'hBF, 8'h00, 8'h20); p += 5;
        want_a[6] = 20'h240AA; want_s[6] = "MOV ES:[BX+2000h],BH  (mod=10 rm=111)";
        emit(p, 5, 8'h26, 8'h88, 8'hBE, 8'h00, 8'h20); p += 5;
        want_a[7] = 20'h22008; want_s[7] = "MOV ES:[BP+2000h],BH  (mod=10 rm=110)";
        // park
        emit(p, 2, 8'hEB, 8'hFE, 8'h00, 8'h00, 8'h00);

        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002,   // psw
                    16'h0000,   // ip
                    16'h3000,   // ds
                    16'h0030,   // ss
                    16'hF000,   // cs
                    16'h2000,   // es
                    16'h0004,   // di
                    16'h0006,   // si
                    16'h0008,   // bp
                    16'h0100,   // sp
                    16'h20AA,   // bx  (BH = 0x20, the attribute byte)
                    16'h00C8,   // dx
                    16'h0000,   // cx
                    16'h1234};  // ax
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;

        repeat (4000) @(posedge clk);

        $display("");
        $display("tb_v30_ea_disp16: %0d stores observed, %0d expected", wr_n, NSTORE);
        $display("");
        bad = 0;
        for (i = 0; i < NSTORE; i = i + 1) begin
            if (i >= wr_n) begin
                $display("  %-46s  MISSING -- no store reached the bus", want_s[i]);
                bad = bad + 1;
            end else if (wr_a[i] !== want_a[i]) begin
                $display("  %-46s  want %05X  got %05X  <== WRONG (delta %0d)",
                         want_s[i], want_a[i], wr_a[i],
                         $signed({12'b0, wr_a[i]}) - $signed({12'b0, want_a[i]}));
                bad = bad + 1;
            end else begin
                $display("  %-46s  %05X  ok", want_s[i], wr_a[i]);
            end
        end
        $display("");
        if (wr_n > NSTORE) begin
            $display("  extra stores (the core wrote more than the program asked):");
            for (i = NSTORE; i < wr_n; i = i + 1)
                $display("    %05X <= %04X%s", wr_a[i], wr_d[i], wr_w[i] ? " (word)" : "");
        end
        // A ternary between two string LITERALS pads the shorter one with NULs
        // and prints garbage -- which is what the first run of this bench did.
        if (bad == 0) $display("tb_v30_ea_disp16: PASS");
        else          $display("tb_v30_ea_disp16: FAIL (%0d wrong)", bad);
        $finish;
    end

endmodule

`default_nettype wire
