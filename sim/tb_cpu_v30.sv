//
// tb_cpu_v30 -- the V30 core swap's acceptance bench.
//
// The machine's CPUs are V30s and its ROMs use the 186-class instructions
// that chip has. The first one measured was the ITF's `push imm16` in its
// CPU-reset save sequence, which the 8088 core dispatched to the undocumented
// JS alias and derailed the stream with. This bench runs the same program on
// nuV30 (vendored under pcxt-base/src/fpga/core/v30) and checks what actually
// lands on the stack.
//
// De-muxed bus view: ADDR_O is the owning cycle's linear address, DATA_I is
// served combinationally, writes commit on the cycle's trailing edge with
// byte lanes from A0/UBE_N -- the same protocol hdl/rtl/nec_bus.sv drives the
// real part with.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_cpu_v30;

    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1'b1;

    // BS = the max-mode S2-S0 the 8288 family decodes.
    localparam logic [2:0] BS_INTA = 3'b000, BS_IOR = 3'b001, BS_IOW = 3'b010,
                           BS_HALT = 3'b011, BS_CODE = 3'b100, BS_MEMR = 3'b101,
                           BS_MEMW = 3'b110, BS_PASV = 3'b111;

    wire [19:0] ADDR_O;
    wire [15:0] DATA_O;
    wire  [2:0] BS;
    wire  [1:0] QS;
    wire        RD_N, UBE_N, BUSLOCK_N;
    wire  [3:0] STATUS_O;
    // V30_BACKDOOR compiles the debug/bkd ports in -- here only for dbg_regs,
    // the live register view the boot bench will log from. The backdoor inputs
    // themselves stay tied off.
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
        .CE        (1'b1),          // de-muxed mode: CE every fabric clock is legal
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

    // ---- flat memory, served as the aligned word the CPU asks of it ---------
    logic [7:0] ram [0:1048575];

    wire [19:0] word_addr = {ADDR_O[19:1], 1'b0};
    wire [15:0] mem_word  = {ram[word_addr + 20'd1], ram[word_addr]};

    always_comb begin
        case (BS)
            BS_CODE, BS_MEMR: DATA_I = mem_word;
            BS_IOR:           DATA_I = 16'hFFFF;   // nothing is connected
            BS_INTA:          DATA_I = 16'h0000;
            default:          DATA_I = 16'h0000;
        endcase
    end

    // Writes: hold the cycle's address/data/lanes, commit when the cycle ends
    // (BS moves off the write type -- the protocol always has a passive gap,
    // the same property nec_bus's cycle reconstruction stands on).
    logic [2:0]  bs_d = BS_PASV;
    logic [19:0] wr_addr = 20'hFFFFF;
    logic [15:0] wr_data = 16'h0000;
    logic        wr_even = 1'b0, wr_odd = 1'b0, wr_active = 1'b0;

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
            if (wr_even) ram[wr_addr] <= wr_data[7:0];
            if (wr_odd)  ram[{wr_addr[19:1], 1'b1}] <= wr_data[15:8];
        end
    end

    int errors = 0;

    initial begin
        // CS:IP = F000:0100 via the reset vector.
        ram[20'hFFFF0] = 8'hEA; ram[20'hFFFF1] = 8'h00; ram[20'hFFFF2] = 8'h01;
        ram[20'hFFFF3] = 8'h00; ram[20'hFFFF4] = 8'hF0;

        // 0100: B8 00 02        mov ax, 0x0200
        // 0103: 8E D0           mov ss, ax
        // 0105: BC 60 00        mov sp, 0x0060
        // 0108: 68 34 12        push 0x1234
        // 010B: 68 78 56        push 0x5678
        // 010E: 6A FE           push -2        (sign-extends to FFFE)
        // 0110: 6A 42           push byte 0x42
        // 0112: EB FE           jmp $
        ram[20'hF0100]=8'hB8; ram[20'hF0101]=8'h00; ram[20'hF0102]=8'h02;
        ram[20'hF0103]=8'h8E; ram[20'hF0104]=8'hD0;
        ram[20'hF0105]=8'hBC; ram[20'hF0106]=8'h60; ram[20'hF0107]=8'h00;
        ram[20'hF0108]=8'h68; ram[20'hF0109]=8'h34; ram[20'hF010A]=8'h12;
        ram[20'hF010B]=8'h68; ram[20'hF010C]=8'h78; ram[20'hF010D]=8'h56;
        ram[20'hF010E]=8'h6A; ram[20'hF010F]=8'hFE;
        ram[20'hF0110]=8'h6A; ram[20'hF0111]=8'h42;
        ram[20'hF0112]=8'hEB; ram[20'hF0113]=8'hFE;

        for (int i = 20'h2040; i < 20'h2080; i++) ram[i] = 8'h00;

        repeat (8) @(posedge clk);
        reset = 1'b0;

        // A handful of instructions; ten thousand clocks is many times over.
        repeat (10000) @(posedge clk);

        $display("=== V30 push immediates (nuV30) ===");
        // SS = 0x0200, so the pushes land at 0x2000+0x58..0x5F.
        $display("  [0205E] %02X %02X (want 34 12)  push 1234",
                 ram[20'h0205F], ram[20'h0205E]);
        $display("  [0205C] %02X %02X (want 78 56)  push 5678",
                 ram[20'h0205D], ram[20'h0205C]);
        $display("  [0205A] %02X %02X (want FE FF)  push -2",
                 ram[20'h0205B], ram[20'h0205A]);
        $display("  [02058] %02X %02X (want 42 00)  push 42",
                 ram[20'h02059], ram[20'h02058]);
        if ({ram[20'h0205F], ram[20'h0205E]} !== 16'h1234) begin $display("  FAIL push imm16 first");  errors++; end
        if ({ram[20'h0205D], ram[20'h0205C]} !== 16'h5678) begin $display("  FAIL push imm16 second"); errors++; end
        if ({ram[20'h0205B], ram[20'h0205A]} !== 16'hFFFE) begin $display("  FAIL push imm8 negative sign-extension"); errors++; end
        if ({ram[20'h02059], ram[20'h02058]} !== 16'h0042) begin $display("  FAIL push imm8 positive"); errors++; end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
