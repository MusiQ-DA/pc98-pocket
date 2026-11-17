//
// tb_fm_replay -- replay fm_test's exact OPNA register stream and ask the
// only question the Pocket raised: does this stream make the chip speak?
//
// fm_test.hdm is silent on the Pocket (#1193) while game music plays, and
// every decode/side-effect theory has died in review (router forwards all
// part0 FM/SSG regs, reads touch nothing, A460 gates only part1). This
// bench is the decisive local experiment: drive pc98_opna with the exact
// writes the disk issues -- address latch then data, exactly like the
// board sees them -- and watch snd_l/snd_r.
//
// LIMIT: this drives pc98_opna's a2a1 port select directly, below the
// Peripherals.sv opna_cs decode, so it can NOT see a wrong guest port
// number. That is exactly how fm_test v1/v2 hid: the disk wrote its data
// bytes to 0x189/0x18B (inc dx), which opna_cs (~address[0]) never selects,
// while this bench used the correct 0x18A/0x18E and played. v3 of the disk
// writes 0x188/0x18A; keep the two in step by hand.
//
// Sections mirrored from testdisk/fm_test.asm:
//   1. FM ch1-3: ALG=7, OP1+OP2 at TL=0x20 AR=0x1F RR=0x0F, OP3/OP4
//      muted (TL=0x7F), FNUM triad high byte first, key-on 0x28 <-
//      F0/F1/F2 (slots in the high nibble, channel in the low bits)
//   2. SSG: periods 0x0888/0x09B0/0x0AC8, mixer 0x38, vol 0x0B -> sound
//   (rhythm needs a filled store; out of scope here -- the WAV kit does
//    that on hardware, and tb_pc98_opna section 9 already covers the
//    silent-until-keyed behaviour)
//
// CI gate (build.yml, beside tb_pc98_opna). Besides the per-section
// checks it pins three output-stage bugs that made the Pocket's FM sound
// noisy / off against np21w:
//   - idle silence right after a SHORT reset pulse (cen was frozen in reset,
//     so jt12's clk_en-gated reset never landed: -30720 of DC from power-on)
//   - FM ch1 pitch (catches a reversed A4/A0 FNUM order)
//   - no two's-complement wrap anywhere in the run (jt12_acc's 1.25x gain
//     and jt12_top's FM+SSG+ADPCM sum both overflowed 16 bits)
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_fm_replay;

    // clk_chipset: 42.954545 MHz, 23.28 ns.
    logic clk = 0;
    always #11.64 clk = ~clk;

    logic       rst = 1'b1;
    logic       cs = 1'b0;
    logic [1:0] a2a1 = 2'b00;
    logic       io_read_n = 1'b1;
    logic       io_write_n = 1'b1;
    logic [7:0] data_in = 8'h00;
    wire  [7:0] data_out;
    wire        read_select;
    logic       ext_enable = 1'b1;      // fm_test writes 0xA460 <- 1 first
    wire        irq;
    logic [7:0] joy = 8'hFF;

    logic  [3:0] mg_reg = 4'd0;
    logic        mg_wr = 1'b0;
    logic [15:0] mg_wdata = 16'h0000;
    wire  [15:0] mg_rdata;

    wire [23:0] adpcmb_addr;
    wire        adpcmb_roe_n;
    wire signed [15:0] snd_l, snd_r;

    // Production instantiation: ADPCM-A on (rhythm store exists, unused
    // here), PCM on -- the same u_pc98_opna Peripherals.sv builds.
    pc98_opna #(.USE_ADPCM(1), .USE_PCM(0)) dut (
        .clk(clk), .rst(rst),
        .cs(cs), .a2a1(a2a1),
        .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(data_out), .read_select(read_select),
        .ext_enable(ext_enable), .joy(joy), .irq(irq),
        .mg_reg(mg_reg), .mg_wr(mg_wr), .mg_wdata(mg_wdata), .mg_rdata(mg_rdata),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(8'h00),
        .snd_l(snd_l), .snd_r(snd_r)
    );

    int errors = 0;

    // ---- bus helpers: one guest OUT as the bridge delivers it -----------
    // Address-latch write (0x188 part0 / 0x18C part1) then data-port write
    // (0x18A / 0x18E): a2a1 = address[2:1].
    task io_wr(input [1:0] port, input [7:0] v);
        begin
            // Poll status bit 7 like a driver (and fm_test v3's wr0) does:
            // jt12 holds ONE pending operator-register update until its
            // slot comes round (up to 24 clk_en, ~18 us), so un-paced
            // writes silently drop TL/AR/... values. Busy covers that.
            @(negedge clk);
            while (dut.status0_out[7]) @(negedge clk);
            a2a1 = port; data_in = v; cs = 1'b1; io_write_n = 1'b0;
            @(negedge clk);
            io_write_n = 1'b1; cs = 1'b0;
            // ~2.3 us between OUTs: a guest's pace, not the router's two-clk
            // worst case. jt12_reg_ch applies an A0-A2 write with the
            // latch_fnum current when that channel's slot comes round, so
            // back-to-back writes let a LATER A4 leak into an earlier A0 and
            // would hide a reversed FNUM order.
            repeat (100) @(negedge clk);
        end
    endtask

    task wr0(input [7:0] reg_a, input [7:0] reg_d);
        begin
            io_wr(2'b00, reg_a);
            io_wr(2'b01, reg_d);
        end
    endtask

    task wr1(input [7:0] reg_a, input [7:0] reg_d);
        begin
            io_wr(2'b10, reg_a);
            io_wr(2'b11, reg_d);
        end
    endtask

    // Wrap detector, always on: a jump of more than 3/4 full scale between two
    // consecutive output samples is a two's-complement wrap in the mix (FM +
    // unipolar SSG DC + ADPCM summed in 16 bits), not a waveform -- the FM
    // noise on hardware. jt12 updates snd_* once per output sample, so a
    // legit waveform moves far less than that per step.
    int wraps = 0;
    logic signed [15:0] prev_l = 0, prev_r = 0;
    always @(posedge clk) if (!rst) begin
        if ((32'(snd_l) - 32'(prev_l) > 49152) || (32'(prev_l) - 32'(snd_l) > 49152) ||
            (32'(snd_r) - 32'(prev_r) > 49152) || (32'(prev_r) - 32'(snd_r) > 49152))
            wraps++;
        prev_l <= snd_l; prev_r <= snd_r;
    end

    // peak tracker: watch snd_l/snd_r for 'us' microseconds
    task peak_over(input int us, output int signed peak);
        int cycles;
        int p;
        begin
            peak = 0; p = 0;
            cycles = us * 43;
            repeat (cycles) begin
                @(negedge clk);
                if (snd_l > p) p = snd_l;
                if (-snd_l > p) p = -snd_l;
                if (snd_r > p) p = snd_r;
                if (-snd_r > p) p = -snd_r;
            end
            peak = p;
        end
    endtask

    // crossings of snd_l through its own mean over 'us' microseconds: a
    // pitch estimate that the SSG's unipolar DC (volume set, tone bit off)
    // cannot hide. First pass takes the mean, second counts.
    task xings_over(input int us, output int n);
        longint sum;
        int     mid;
        logic   last;
        begin
            sum = 0;
            repeat (us * 43) begin @(negedge clk); sum += longint'(snd_l); end
            mid = int'(sum / (us * 43));
            n = 0; last = (int'(snd_l) >= mid);
            repeat (us * 43) begin
                @(negedge clk);
                if ((int'(snd_l) >= mid) != last) begin n++; last = ~last; end
            end
        end
    endtask

    int pk, xn;

    initial begin
        // A deliberately short reset pulse: pc98_opna must stretch it for
        // jt12 itself (jt_rst) and keep cen running through it, or the EG
        // never leaves its power-up 0 and every idle slot sits at full scale.
        repeat (10) @(negedge clk);
        rst = 1'b0;
        repeat (3000) @(negedge clk);   // past the 2048-clk jt12 reset stretch

        // ---- section -1: idle after reset must be silent ----------------
        peak_over(2000, pk);
        $display("idle peak after reset %0d", pk);
        if (pk > 64) begin errors++; $display("FAIL: output not silent after reset (EG reset never landed?)"); end
        else $display("ok idle silent after reset");

        // ---- voice setup: exactly fm_test's tables ----------------------
        // ALG=7 / pan C0 on ch1-3
        wr0(8'hB0, 8'h07); wr0(8'hB1, 8'h07); wr0(8'hB2, 8'h07);
        wr0(8'hB4, 8'hC0); wr0(8'hB5, 8'hC0); wr0(8'hB6, 8'hC0);
        // slots 0/8 per channel: TL 0x20, AR 0x1F, RR 0x0F
        wr0(8'h40, 8'h20); wr0(8'h48, 8'h20);
        wr0(8'h41, 8'h20); wr0(8'h49, 8'h20);
        wr0(8'h42, 8'h20); wr0(8'h4A, 8'h20);
        // slots 4/C muted
        wr0(8'h44, 8'h7F); wr0(8'h4C, 8'h7F);
        wr0(8'h45, 8'h7F); wr0(8'h4D, 8'h7F);
        wr0(8'h46, 8'h7F); wr0(8'h4E, 8'h7F);
        wr0(8'h50, 8'h1F); wr0(8'h58, 8'h1F);
        wr0(8'h51, 8'h1F); wr0(8'h59, 8'h1F);
        wr0(8'h52, 8'h1F); wr0(8'h5A, 8'h1F);
        wr0(8'h80, 8'h0F); wr0(8'h88, 8'h0F);
        wr0(8'h81, 8'h0F); wr0(8'h89, 8'h0F);
        wr0(8'h82, 8'h0F); wr0(8'h8A, 8'h0F);
        // FNUM triad, block 4 -- high byte (latch) first, low byte commits
        wr0(8'hA4, 8'h22); wr0(8'hA0, 8'h4D);
        wr0(8'hA5, 8'h22); wr0(8'hA1, 8'h66);
        wr0(8'hA6, 8'h22); wr0(8'hA2, 8'h80);
        // SSG periods / mixer off / volumes
        wr0(8'h00, 8'h88); wr0(8'h01, 8'h08);
        wr0(8'h02, 8'hB0); wr0(8'h03, 8'h09);
        wr0(8'h04, 8'hC8); wr0(8'h05, 8'h0A);
        wr0(8'h07, 8'h3F);
        wr0(8'h08, 8'h0B); wr0(8'h09, 8'h0B); wr0(8'h0A, 8'h0B);
        // rhythm total level + per-voice {L,R,IL} (YM2608 part0 map)
        wr0(8'h11, 8'h3F);
        wr0(8'h18, 8'hDF); wr0(8'h19, 8'hDF); wr0(8'h1A, 8'hDF);
        wr0(8'h1B, 8'hDF); wr0(8'h1C, 8'hDF); wr0(8'h1D, 8'hDF);

        // ---- section 0: FM ch1 alone -- catches a reversed FNUM order.
        // A4 only latches and A0 commits, so A0-before-A4 leaves ch1 at
        // block 0 / fnum 0x04D (~2 Hz: a DC drift, still a big peak) instead
        // of block 4 / 0x24D (~124 Hz). Count sign changes, not the peak.
        wr0(8'h28, 8'hF0);
        xings_over(40000, xn);
        $display("FM ch1 sign changes in 40 ms: %0d (~10 expected at 124 Hz)", xn);
        if (xn < 6) begin errors++; $display("FAIL: FM ch1 pitch wrong (FNUM order?)"); end
        else $display("ok FM ch1 pitch");
        wr0(8'h28, 8'h00);
        peak_over(200, pk);

        // ---- section 1: FM only -----------------------------------------
        wr0(8'h28, 8'hF0); wr0(8'h28, 8'hF1); wr0(8'h28, 8'hF2);
        peak_over(400, pk);
        $display("FM  peak %0d", pk);
        if (pk == 0) begin errors++; $display("FAIL: FM section silent"); end
        else $display("ok FM section speaks");
        wr0(8'h28, 8'h00); wr0(8'h28, 8'h01); wr0(8'h28, 8'h02);

        // ---- section 2: SSG only ----------------------------------------
        wr0(8'h07, 8'h38);
        peak_over(400, pk);
        $display("SSG peak %0d", pk);
        if (pk == 0) begin errors++; $display("FAIL: SSG section silent"); end
        else $display("ok SSG section speaks");
        wr0(8'h07, 8'h3F);

        // ---- section 4: FM + SSG together, 20 ms -- the loudest mix --------
        wr0(8'h28, 8'hF0); wr0(8'h28, 8'hF1); wr0(8'h28, 8'hF2);
        wr0(8'h07, 8'h38);
        peak_over(20000, pk);
        $display("ALL peak %0d", pk);
        wr0(8'h28, 8'h00); wr0(8'h28, 8'h01); wr0(8'h28, 8'h02);
        wr0(8'h07, 8'h3F);

        $display("output wraps over the whole run: %0d", wraps);
        if (wraps != 0) begin errors++; $display("FAIL: the output mix wrapped (16-bit overflow)"); end
        else $display("ok no output wrap");

        if (errors == 0)
            $display("PASS tb_fm_replay");
        else
            $display("DONE: %0d errors / RESULT: FAIL", errors);
        $finish;
    end

endmodule

`default_nettype wire
