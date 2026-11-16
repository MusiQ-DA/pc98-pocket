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
// Sections mirrored from testdisk/fm_test.asm:
//   1. FM ch1-3: ALG=0 2-op voices, TL=0x20 AR=0x1F RR=0x0F, FNUM triad,
//      key-on 0x28 <- 03/13/23      -> expect sound within ~200 us
//   2. SSG: periods 0x0888/0x09B0/0x0AC8, mixer 0x38, vol 0x0B -> sound
//   (rhythm needs a filled store; out of scope here -- the WAV kit does
//    that on hardware, and tb_pc98_opna section 9 already covers the
//    silent-until-keyed behaviour)
//
// Not a CI gate: a diagnostic bench. Run from the repo root with the
//   usual binary+timing flow: --top-module tb_fm_replay -Isim ...
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
    pc98_opna #(.USE_ADPCM(1), .USE_PCM(1)) dut (
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
    // Address-latch write (0x188 part0 / 0x18A part1) then data-port write
    // (0x189 / 0x18B), with a status poll between like fm_test's wr0/wr1.
    task io_wr(input [1:0] port, input [7:0] v);
        begin
            @(negedge clk);
            a2a1 = port; data_in = v; cs = 1'b1; io_write_n = 1'b0;
            @(negedge clk);
            io_write_n = 1'b1; cs = 1'b0;
            // settle: two clk is the router's worst case
            repeat (4) @(negedge clk);
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

    int pk;

    initial begin
        repeat (10) @(negedge clk);
        rst = 1'b0;
        repeat (10) @(negedge clk);

        // ---- voice setup: exactly fm_test's tables ----------------------
        // ALG=0 / pan C0 on ch1-3
        wr0(8'hB0, 8'h00); wr0(8'hB1, 8'h00); wr0(8'hB2, 8'h00);
        wr0(8'hB4, 8'hC0); wr0(8'hB5, 8'hC0); wr0(8'hB6, 8'hC0);
        // slots 0/8 per channel: TL 0x20, AR 0x1F, RR 0x0F
        wr0(8'h40, 8'h20); wr0(8'h48, 8'h20);
        wr0(8'h41, 8'h20); wr0(8'h49, 8'h20);
        wr0(8'h42, 8'h20); wr0(8'h4A, 8'h20);
        wr0(8'h50, 8'h1F); wr0(8'h58, 8'h1F);
        wr0(8'h51, 8'h1F); wr0(8'h59, 8'h1F);
        wr0(8'h52, 8'h1F); wr0(8'h5A, 8'h1F);
        wr0(8'h80, 8'h0F); wr0(8'h88, 8'h0F);
        wr0(8'h81, 8'h0F); wr0(8'h89, 8'h0F);
        wr0(8'h82, 8'h0F); wr0(8'h8A, 8'h0F);
        // FNUM triad, block 4
        wr0(8'hA0, 8'h4D); wr0(8'hA4, 8'h22);
        wr0(8'hA1, 8'h66); wr0(8'hA5, 8'h22);
        wr0(8'hA2, 8'h80); wr0(8'hA6, 8'h22);
        // SSG periods / mixer off / volumes
        wr0(8'h00, 8'h88); wr0(8'h01, 8'h08);
        wr0(8'h02, 8'hB0); wr0(8'h03, 8'h09);
        wr0(8'h04, 8'hC8); wr0(8'h05, 8'h0A);
        wr0(8'h07, 8'h3F);
        wr0(8'h08, 8'h0B); wr0(8'h09, 8'h0B); wr0(8'h0A, 8'h0B);
        // rhythm total level + per-voice pan/level (part1)
        wr0(8'h11, 8'h3F);
        wr1(8'h00, 8'hC0); wr1(8'h01, 8'hC0); wr1(8'h02, 8'hC0);
        wr1(8'h03, 8'hC0); wr1(8'h04, 8'hC0); wr1(8'h05, 8'hC0);
        wr1(8'h06, 8'h3F); wr1(8'h07, 8'h3F); wr1(8'h08, 8'h3F);
        wr1(8'h09, 8'h3F); wr1(8'h0A, 8'h3F); wr1(8'h0B, 8'h3F);

        // ---- section 1: FM only -----------------------------------------
        wr0(8'h28, 8'h03); wr0(8'h28, 8'h13); wr0(8'h28, 8'h23);
        peak_over(400, pk);
        $display("FM  peak %0d", pk);
        if (pk == 0) begin errors++; $display("FAIL: FM section silent"); end
        else $display("ok FM section speaks");
        wr0(8'h28, 8'h00); wr0(8'h28, 8'h10); wr0(8'h28, 8'h20);

        // ---- section 2: SSG only ----------------------------------------
        wr0(8'h07, 8'h38);
        peak_over(400, pk);
        $display("SSG peak %0d", pk);
        if (pk == 0) begin errors++; $display("FAIL: SSG section silent"); end
        else $display("ok SSG section speaks");
        wr0(8'h07, 8'h3F);

        if (errors == 0)
            $display("PASS tb_fm_replay");
        else
            $display("DONE: %0d errors / RESULT: FAIL", errors);
        $finish;
    end

endmodule

`default_nettype wire
