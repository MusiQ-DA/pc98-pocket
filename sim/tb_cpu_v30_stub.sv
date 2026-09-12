// tb_cpu_v30_stub -- does the nuV30 execute the BASIC entry stub's first
// ten bytes the way the ROM intends?
//
//   E800:0000: 06            push es
//   E800:0001: 66 18 77 d5   sbb [bx+0xd5], dh   (32-bit operand, V30 0x66)
//   E800:0005: 89 de         mov si, bx
//   E800:0007: f3 a4         rep movsb           (CX=0: must retire clean)
//   E800:0009: eb d6         jmp E800:FFE1       (-0x2A from 0x000B)
//
// The boot bench shows the machine arriving at E800:FFDA (jmp FEFD) without
// ever executing FFE1/FE95 -- seven bytes below the computed target. This
// bench isolates the question: where does `eb d6` from E800:0009 land?

`timescale 1ns/1ps
`default_nettype none

module tb_cpu_v30_stub;

    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic reset = 1'b1;

    // BS = the max-mode S2-S0 the 8288 family decodes.
    localparam logic [2:0] BS_INTA = 3'b000, BS_IOR = 3'b001, BS_IOW = 3'b010,
                           BS_HALT = 3'b011, BS_CODE = 3'b100, BS_MEMR = 3'b101,
                           BS_MEMW = 3'b110, BS_PASV = 3'b111;

    logic [19:0] ADDR_O;
    logic [15:0] DATA_O;
    wire  [15:0] DATA_I;
    logic  [2:0] STATUS_O;
    logic  [3:0] QS;
    logic  [2:0] BS;
    logic  RD_N, UBE_N, BUSLOCK_N;

    logic        bkd_load;
    logic [223:0] bkd_regs;
    logic [47:0] bkd_queue;
    logic  [2:0] bkd_qlen;
    logic [15:0] bkd_fetch_ip;
    logic        scr_en;
    logic  [1:0] scr_qop;
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

    assign DATA_I = DATA_I_i;

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
            if (wr_even) ram[wr_addr]     <= wr_data[7:0];
            if (wr_odd)  ram[wr_addr+1'b1]<= wr_data[15:8];
            wr_active <= 1'b0;
        end
    end

    wire [15:0] r_ip = dbg_regs[207:192];
    wire [15:0] r_cs = dbg_regs[159:144];
    wire [15:0] r_sp = dbg_regs[79:64];
    wire [15:0] r_si = dbg_regs[111:96];
    // The EU's live PC and the loaded displacement -- the short-jump pieces
    wire [15:0] eu_pc_l = dut.u_eu.pc;
    wire [15:0] eu_lddisp = dut.u_eu.ld_disp;

    int errors = 0;

    initial begin
        $dumpfile("tb_cpu_v30_stub.fst");
        $dumpvars(0, tb_cpu_v30_stub);
        bkd_load = 1'b0; bkd_regs = '0; bkd_queue = '0; bkd_qlen = '0;
        bkd_fetch_ip = '0; scr_en = 1'b0; scr_qop = '0;

        // ROM: the exact first bytes of the BASIC entry stub (from bios.rom).
        ram[20'hE8000]=8'h06; ram[20'hE8001]=8'h66; ram[20'hE8002]=8'h18;
        ram[20'hE8003]=8'h77; ram[20'hE8004]=8'hD5; ram[20'hE8005]=8'h89;
        ram[20'hE8006]=8'hDE; ram[20'hE8007]=8'hF3; ram[20'hE8008]=8'hA4;
        ram[20'hE8009]=8'hEB; ram[20'hE800A]=8'hD6;
        // Variant B at another segment (F000:0100): same stream, 66 REMOVED.
        ram[20'hF0100]=8'h06; ram[20'hF0101]=8'h18; ram[20'hF0102]=8'h77;
        ram[20'hF0103]=8'hD5; ram[20'hF0104]=8'h89; ram[20'hF0105]=8'hDE;
        ram[20'hF0106]=8'hF3; ram[20'hF0107]=8'hA4; ram[20'hF0108]=8'hEB;
        ram[20'hF0109]=8'hD2;  // adjusted so the target = F000:0100-0x24=F000:00DC... use FE instead
        ram[20'hF0109]=8'hFE;  // variant B: just jmp $ -- we only care about SI/SP state
        // Landing pads with distinct parks:
        // E800:FFD8: 90 90            (nops -- would fall to FFDA)
        // E800:FFDA: EB FE            jmp $  (the WRONG landing, per the boot bench)
        // E800:FFE1: B8 41 41 EB FE   mov ax,0x4141; jmp $  (the INTENDED target)
        ram[20'hF7FD8]=8'h90; ram[20'hF7FD9]=8'h90;
        ram[20'hF7FDA]=8'hB8; ram[20'hF7FDB]=8'h42; ram[20'hF7FDC]=8'h42;
        ram[20'hF7FDD]=8'hEB; ram[20'hF7FDE]=8'hFE;
        ram[20'hF7FE1]=8'hB8; ram[20'hF7FE2]=8'h41; ram[20'hF7FE3]=8'h41;
        ram[20'hF7FE4]=8'hEB; ram[20'hF7FE5]=8'hFE;

        // Reset state: CS=E800 IP=0000, SS=0030 SP=0100, ES=DF00, BX=04E0,
        // CX=0000, DX=00C8 -- exactly the pass-2 int 1E entry state.
        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002,       // psw: IF set
                    16'h0000,       // ip
                    16'h0000,       // ds
                    16'h0030,       // ss
                    16'hE800,       // cs
                    16'hDF00,       // es
                    16'h0000,       // di
                    16'h0000,       // si
                    16'h0000,       // bp
                    16'h0100,       // sp
                    16'h04E0,       // bx
                    16'h00C8,       // dx
                    16'h0000,       // cx
                    16'h0000};      // ax
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;

        // Log every instruction retirement (IP change) for the first ones.
        fork
            begin : retire_log
                logic [15:0] ip_q = 16'hFFFF;
                int n = 0;
                while (n < 30) begin
                    @(posedge clk);
                    if (reset == 1'b0 && r_ip != ip_q) begin
                        ip_q = r_ip;
                        $display("  [%0d] IP=%04X  op=%02X %02X  PSW=%04X AX=%04X BX=%04X CX=%04X DX=%04X SI=%04X DI=%04X SP=%04X",
                                 n, r_ip, ram[{r_cs,4'h0}+r_ip], ram[{r_cs,4'h0}+r_ip+1],
                                 dbg_regs[223:208],
                                 dbg_regs[15:0], dbg_regs[63:48], dbg_regs[31:16], dbg_regs[47:32],
                                 r_si, dbg_regs[127:112], r_sp);
                        n = n + 1;
                    end
                end
            end
        join_none

        repeat (3000) @(posedge clk);

        // Variant C at F100:0000: `66 90` (prefix + nop) then park.
        ram[20'hF1000]=8'h66; ram[20'hF1001]=8'h90;
        ram[20'hF1002]=8'hB8; ram[20'hF1003]=8'h43; ram[20'hF1004]=8'h43;
        ram[20'hF1005]=8'hEB; ram[20'hF1006]=8'hFE;
        // Variant D at F200:0000: `90` (nop) then park.
        ram[20'hF2000]=8'h90;
        ram[20'hF2001]=8'hB8; ram[20'hF2002]=8'h44; ram[20'hF2003]=8'h44;
        ram[20'hF2004]=8'hEB; ram[20'hF2005]=8'hFE;
        // Variant E at F300:0000: `66 18 77 d5 89 de` (the exact 6 bytes) then park.
        ram[20'hF3000]=8'h66; ram[20'hF3001]=8'h18; ram[20'hF3002]=8'h77;
        ram[20'hF3003]=8'hD5; ram[20'hF3004]=8'h89; ram[20'hF3005]=8'hDE;
        ram[20'hF3006]=8'hB8; ram[20'hF3007]=8'h45; ram[20'hF3008]=8'h45;
        ram[20'hF3009]=8'hEB; ram[20'hF300A]=8'hFE;

        // Variant F at F400:0000: the stub through `rep movsb` then park (no jmp).
        ram[20'hF4000]=8'h06; ram[20'hF4001]=8'h66; ram[20'hF4002]=8'h18;
        ram[20'hF4003]=8'h77; ram[20'hF4004]=8'hD5; ram[20'hF4005]=8'h89;
        ram[20'hF4006]=8'hDE; ram[20'hF4007]=8'hF3; ram[20'hF4008]=8'hA4;
        ram[20'hF4009]=8'hB8; ram[20'hF400A]=8'h46; ram[20'hF400B]=8'h46;
        ram[20'hF400C]=8'hEB; ram[20'hF400D]=8'hFE;
        // Variant G at F500:0000: only `eb d6` (the jmp) after a nop start.
        ram[20'hF5000]=8'h90; ram[20'hF5001]=8'hEB; ram[20'hF5002]=8'hD6;

        // Variant H at F600:0000: full stub, jmp target = F600:FFE1 gets
        // `B8 48 48 EB FE`; FFDA area left as ZEROS (no park) -- if the
        // machine lands there it walks; if it lands at FFE1 it parks.
        ram[20'hF6000]=8'h06; ram[20'hF6001]=8'h66; ram[20'hF6002]=8'h18;
        ram[20'hF6003]=8'h77; ram[20'hF6004]=8'hD5; ram[20'hF6005]=8'h89;
        ram[20'hF6006]=8'hDE; ram[20'hF6007]=8'hF3; ram[20'hF6008]=8'hA4;
        ram[20'hF6009]=8'hEB; ram[20'hF600A]=8'hD6;
        ram[20'h05FE1]=8'hB8; ram[20'h05FE2]=8'h48; ram[20'h05FE3]=8'h48;
        ram[20'h05FE4]=8'hEB; ram[20'h05FE5]=8'hFE;

        // Variant L at F700:0000: the stub with 66 -> 90 (NOP) -- if the jump
        // then lands correctly, the 66-prefix's queue interaction is the bug
        // and NOPing it is the workaround.
        ram[20'hF7000]=8'h06; ram[20'hF7001]=8'h90; ram[20'hF7002]=8'h18;
        ram[20'hF7003]=8'h77; ram[20'hF7004]=8'hD5; ram[20'hF7005]=8'h89;
        ram[20'hF7006]=8'hDE; ram[20'hF7007]=8'hF3; ram[20'hF7008]=8'hA4;
        ram[20'hF7009]=8'hEB; ram[20'hF700A]=8'hD6;
        ram[20'hF6FE1]=8'hB8; ram[20'hF6FE2]=8'h4C; ram[20'hF6FE3]=8'h4C;
        ram[20'hF6FE4]=8'hEB; ram[20'hF6FE5]=8'hFE;

        $display("=== V30 entry-stub first bytes ===");
        $display("  final CS:IP = %04X:%04X  AX=%04X (4141=FFE1 landing, 4242=FFDA landing)",
                 r_cs, r_ip, dbg_regs[15:0]);
        $display("  SP=%04X SI=%04X", r_sp, r_si);
        $display("  push es wrote [030FE]=%02X%02X (want DF00 little-endian 00 DF)",
                 ram[20'h003FF], ram[20'h003FE]);
        if (r_cs == 16'hE800 && r_ip == 16'hFFE1)
            $display("  RESULT A: PASS -- jmp lands on FFE1");
        else if (r_cs == 16'hE800 && r_ip == 16'hFFDA)
            $display("  RESULT A: BUG -- jmp lands on FFDA");
        else
            $display("  RESULT A: OTHER -- landed elsewhere");

        // ---- variant B: same stream without the 66 prefix ------------------
        reset = 1'b1;
        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002, 16'h0100, 16'h0000, 16'h0030, 16'hF000,
                    16'hDF00, 16'h0000, 16'h0000, 16'h0000, 16'h0100,
                    16'h04E0, 16'h00C8, 16'h0000, 16'h0000};
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;
        repeat (2000) @(posedge clk);
        $display("  B: no-66 stream: CS:IP=%04X:%04X SI=%04X (want SI=04E0) SP=%04X",
                 r_cs, r_ip, r_si, r_sp);
        if (r_si == 16'h04E0)
            $display("  RESULT B: PASS -- mov si,bx ran");
        else
            $display("  RESULT B: FAIL -- mov si,bx skipped");
        // ---- variant C: 66 + nop ----
        reset = 1'b1;
        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002, 16'h0000, 16'h0000, 16'h0030, 16'hF100,
                    16'hDF00, 16'h0000, 16'h0000, 16'h0000, 16'h0100,
                    16'h04E0, 16'h00C8, 16'h0000, 16'h0000};
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;
        repeat (500) @(posedge clk);
        $display("  C: 66+nop: IP=%04X (want 0007 if 66 is 1-byte prefix) AX=%04X",
                 r_ip, dbg_regs[15:0]);

        // ---- variant D: plain nop ----
        reset = 1'b1;
        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002, 16'h0000, 16'h0000, 16'h0030, 16'hF200,
                    16'hDF00, 16'h0000, 16'h0000, 16'h0000, 16'h0100,
                    16'h04E0, 16'h00C8, 16'h0000, 16'h0000};
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;
        repeat (500) @(posedge clk);
        $display("  D: nop:    IP=%04X (want 0006) AX=%04X",
                 r_ip, dbg_regs[15:0]);

        // ---- variant E: the exact 6 bytes then park ----
        reset = 1'b1;
        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002, 16'h0000, 16'h0000, 16'h0030, 16'hF300,
                    16'hDF00, 16'h0000, 16'h0000, 16'h0000, 16'h0100,
                    16'h04E0, 16'h00C8, 16'h0000, 16'h0000};
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;
        repeat (500) @(posedge clk);
        $display("  E: 66 18 77 d5 89 de: IP=%04X (want 0008 if 4-byte+2-byte) SI=%04X (want 04E0)",
                 r_ip, r_si);
        // ---- variant F: stub + rep movsb, park (no jmp) ----
        reset = 1'b1;
        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002, 16'h0000, 16'h0000, 16'h0030, 16'hF400,
                    16'hDF00, 16'h0500, 16'h0000, 16'h0000, 16'h0100,
                    16'h04E0, 16'h00C8, 16'h0000, 16'h0000};
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;
        repeat (500) @(posedge clk);
        $display("  F: stub+rep+park: IP=%04X (want 000F) SI=%04X AX=%04X (4646=reached park)",
                 r_ip, r_si, dbg_regs[15:0]);

        // ---- variant G: nop + eb d6 (jmp only) ----
        reset = 1'b1;
        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002, 16'h0000, 16'h0000, 16'h0030, 16'hF500,
                    16'hDF00, 16'h0000, 16'h0000, 16'h0000, 16'h0100,
                    16'h04E0, 16'h00C8, 16'h0000, 16'h0000};
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;
        repeat (500) @(posedge clk);
        $display("  G: nop+jmp d6: IP=%04X (F500:FFDB-FFC4 = wrap target 0x0003-0x2A...)",
                 r_ip);
        // ---- variant H: full stub at F600, park at FFE1, zeros at FFDA ----
        reset = 1'b1;
        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002, 16'h0000, 16'h0000, 16'h0030, 16'hF600,
                    16'hDF00, 16'h0500, 16'h0000, 16'h0000, 16'h0100,
                    16'h04E0, 16'h00C8, 16'h0000, 16'h0000};
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;
        repeat (3000) @(posedge clk);
        $display("  H: F600 stub: IP=%04X AX=%04X (4848=parked at FFE1, else walked)",
                 r_ip, dbg_regs[15:0]);
        // ---- variant L: 66->90 then the full stub ----
        reset = 1'b1;
        repeat (4) @(posedge clk);
        bkd_regs = {16'h0002, 16'h0000, 16'h0000, 16'h0030, 16'hF700,
                    16'hDF00, 16'h0500, 16'h0000, 16'h0000, 16'h0100,
                    16'h04E0, 16'h00C8, 16'h0000, 16'h0000};
        bkd_load = 1'b1;
        repeat (2) @(posedge clk);
        bkd_load = 1'b0;
        reset = 1'b0;
        repeat (3000) @(posedge clk);
        $display("  L: 66->90 stub: IP=%04X AX=%04X SI=%04X (4C4C=parked at FFE1 correct!)",
                 r_ip, dbg_regs[15:0], r_si);
        $finish;
    end

endmodule

`default_nettype wire
