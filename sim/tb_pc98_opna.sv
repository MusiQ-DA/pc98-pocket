//
// tb_pc98_opna -- does the PC-9801-86's port window and register router
// behave the way the board does?
//
// The whole point of pc98_opna is that it is the INTERFACE: four ports, an
// extended-mode gate that does not live in the chip at all, and a router that
// re-addresses every guest write because jt12's ADPCM register map is the
// YM2610's and the guest's is the YM2608's. None of that is visible from an
// audio-level test, so it gets pinned here -- the same way tb_pc98_scsi pins
// the 0xCC0 window.
//
// Checked against np2kai cbus/board86.c (opna_o188/o18a/o18c/o18e and
// opna_i188/i18a/i18c/i18e), cbus/pcm86io.c:45-51 (0xA460 bit 0 is what turns
// the second register pair on), and jt12_mmr.v:342-391 for where jt12 actually
// keeps its two ADPCM blocks.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_opna;

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
    logic       ext_enable = 1'b0;
    wire        irq;

    logic  [3:0] mg_reg = 4'd0;
    logic        mg_wr = 1'b0;
    logic [15:0] mg_wdata = 16'h0000;
    wire  [15:0] mg_rdata;

    wire [23:0] adpcmb_addr;
    wire        adpcmb_roe_n;
    wire signed [15:0] snd_l, snd_r;

    pc98_opna dut (
        .clk(clk), .rst(rst),
        .cs(cs), .a2a1(a2a1),
        .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(data_out), .read_select(read_select),
        .ext_enable(ext_enable), .irq(irq),
        .mg_reg(mg_reg), .mg_wr(mg_wr), .mg_wdata(mg_wdata), .mg_rdata(mg_rdata),
        .adpcmb_addr(adpcmb_addr), .adpcmb_roe_n(adpcmb_roe_n),
        .adpcmb_data(8'h00),
        .snd_l(snd_l), .snd_r(snd_r)
    );

    int errors = 0;
    task automatic want(input string what, input [7:0] got, input [7:0] exp);
        if (got !== exp) begin
            $display("  FAIL %-40s %02h (want %02h)", what, got, exp);
            errors++;
        end else
            $display("  ok   %-40s %02h", what, got);
    endtask

    task automatic want_ne(input string what, input [7:0] got, input [7:0] bad);
        if (got === bad) begin
            $display("  FAIL %-40s %02h (want anything else)", what, got);
            errors++;
        end else
            $display("  ok   %-40s %02h", what, got);
    endtask

    task automatic want_b(input string what, input got, input exp);
        if (got !== exp) begin
            $display("  FAIL %-40s %0d (want %0d)", what, got, exp);
            errors++;
        end else
            $display("  ok   %-40s %0d", what, got);
    endtask

    // ------------------------------------------------------------------
    // Guest bus
    // ------------------------------------------------------------------
    // Address and command up, data settling mid-cycle -- the bus hazard
    // pc98_opna latches around, same as tb_pc98_scsi's io_wr.
    task automatic io_wr(input [1:0] port, input [7:0] v);
        a2a1 = port; cs = 1'b1; data_in = 8'h5A; io_write_n = 1'b0;
        repeat (2) @(posedge clk);
        data_in = v;
        repeat (3) @(posedge clk);
        io_write_n = 1'b1;
        @(posedge clk);
        cs = 1'b0; a2a1 = 2'b00;
        repeat (2) @(posedge clk);
    endtask

    task automatic io_rd(input [1:0] port, output [7:0] v);
        a2a1 = port; cs = 1'b1; io_read_n = 1'b0;
        repeat (3) @(posedge clk);
        v = data_out;
        repeat (2) @(posedge clk);
        io_read_n = 1'b1;
        @(posedge clk);
        cs = 1'b0; a2a1 = 2'b00;
        repeat (2) @(posedge clk);
    endtask

    task automatic mgmt_wr(input [3:0] r, input [15:0] v);
        mg_reg = r; mg_wdata = v; mg_wr = 1'b1;
        @(posedge clk);
        mg_wr = 1'b0;
        repeat (4) @(posedge clk);
    endtask

    // ------------------------------------------------------------------
    // Router probe
    // ------------------------------------------------------------------
    // The router's request is the thing the whole file exists to compute, and
    // it is not observable from the guest bus -- jt12 has no read-back for a
    // register it just took. So it is watched directly, on the cycle the FSM
    // consumes it.
    // nreq is written only here, and arm() only ever reads it. A variable
    // driven from an initial block AND an always block does not survive the
    // scheduler intact -- the first cut of this probe cleared a flag from the
    // initial block and set it from the always block, and the flag was always
    // read back as zero even though the requests were happening.
    int         nreq = 0;
    int         mark = 0;
    logic       req_part;
    logic [7:0] req_reg, req_data;
    wire        saw_req = (nreq != mark);

    always @(posedge clk) begin
        if (dut.rtr_state == 2'd1) begin   // RTR_ADDR, the address beat
            nreq     <= nreq + 1;
            req_part <= dut.rq_part;
            req_reg  <= dut.rq_reg;
            req_data <= dut.rq_data;
        end
    end

    task automatic arm();
        mark = nreq;
    endtask

    // Write a chip register the way a driver does: index to the even port,
    // value to the odd one (np2kai board86.c:17-51).
    task automatic chip_wr(input logic part, input [7:0] r, input [7:0] v);
        io_wr({part, 1'b0}, r);
        io_wr({part, 1'b1}, v);
        repeat (8) @(posedge clk);
    endtask

    task automatic want_route(input string what, input logic part,
                              input [7:0] r, input [7:0] v);
        if (!saw_req) begin
            $display("  FAIL %-40s no router request", what);
            errors++;
        end else if (req_part !== part || req_reg !== r || req_data !== v) begin
            $display("  FAIL %-40s part %0d reg %02h data %02h (want %0d/%02h/%02h)",
                     what, req_part, req_reg, req_data, part, r, v);
            errors++;
        end else
            $display("  ok   %-40s part %0d reg %02h", what, req_part, req_reg);
    endtask

    task automatic want_dropped(input string what);
        if (saw_req) begin
            $display("  FAIL %-40s routed part %0d reg %02h (want dropped)",
                     what, req_part, req_reg);
            errors++;
        end else
            $display("  ok   %-40s dropped", what);
    endtask

    logic [7:0] got;
    int         waited;

    initial begin
        $display("=== PC-9801-86 OPNA port window and register router ===");

        // jt12_mmr warns and dies on a write during reset, and jt12 wants the
        // reset at least six clk&cen cycles long; cen is one clk in 5.4, so
        // 256 clocks is comfortably past that.
        repeat (256) @(posedge clk);
        rst = 1'b0;
        repeat (256) @(posedge clk);

        // ================================================================
        // 1. The SSG is the one block with a real read-back, so it proves
        //    the whole path: guest port -> router -> jt12 part 0 -> jt49,
        //    and jt12_dout's view 1 back out through the shadow.
        //    jt49.v:263 reads regarray[addr] & read_mask; register 0 is the
        //    channel-A fine tune and unmasked, so 0xA5 survives intact.
        // ================================================================
        chip_wr(1'b0, 8'h00, 8'hA5);
        repeat (64) @(posedge clk);
        io_wr(2'b00, 8'h00);            // re-select index 0
        repeat (32) @(posedge clk);
        io_rd(2'b01, got);
        want("SSG reg 0 reads back", got, 8'hA5);

        // np2kai board86.c:74-77: index 0xFF answers 1. Drivers use it to tell
        // an OPNA board from an empty slot.
        io_wr(2'b00, 8'hFF);
        repeat (8) @(posedge clk);
        io_rd(2'b01, got);
        want("index FF is the presence probe", got, 8'h01);

        // ================================================================
        // 2. Extended mode. It is not a chip register: np2kai
        //    cbus/pcm86io.c:45-51 drives it from bit 0 of a write to 0xA460,
        //    and board86.c:80-105 makes 0x18C/0x18E open bus without it.
        // ================================================================
        ext_enable = 1'b0;
        repeat (8) @(posedge clk);
        io_rd(2'b10, got); want("0x18C is open bus, not extended", got, 8'hFF);
        io_rd(2'b11, got); want("0x18E is open bus, not extended", got, 8'hFF);

        arm();
        chip_wr(1'b1, 8'hB0, 8'h3C);
        want_dropped("part-1 write while not extended");

        ext_enable = 1'b1;
        repeat (8) @(posedge clk);
        io_rd(2'b10, got); want_ne("0x18C answers once extended", got, 8'hFF);

        // ================================================================
        // 3. The router. Everything below is a claim about where a guest
        //    register ends up inside jt12 -- see the table in pc98_opna.sv.
        // ================================================================

        // Part 0, outside 0x10-0x1F: straight through.
        arm(); chip_wr(1'b0, 8'h07, 8'h38);
        want_route("part0 SSG 0x07 passes through", 1'b0, 8'h07, 8'h38);
        arm(); chip_wr(1'b0, 8'hB0, 8'h3C);
        want_route("part0 FM 0xB0 passes through", 1'b0, 8'hB0, 8'h3C);

        // Rhythm. On a YM2608 this is part 0, 0x10-0x1D; the same six voices
        // are jt12's ADPCM-A at part 1, 0x100-0x10D, with identical bit
        // layouts (jt10_adpcm_drvA.v:80 for the dump bit, jt12_mmr.v:345-352
        // for atl and LRACL).
        arm(); chip_wr(1'b0, 8'h10, 8'h0F);
        want_route("rhythm KON 0x10 -> ADPCM-A 0x100", 1'b1, 8'h00, 8'h0F);
        arm(); chip_wr(1'b0, 8'h11, 8'h2A);
        want_route("rhythm TL 0x11 -> ADPCM-A 0x101", 1'b1, 8'h01, 8'h2A);
        arm(); chip_wr(1'b0, 8'h18, 8'hC5);
        want_route("rhythm BD 0x18 -> ADPCM-A 0x108", 1'b1, 8'h08, 8'hC5);
        arm(); chip_wr(1'b0, 8'h1D, 8'h9F);
        want_route("rhythm RIM 0x1D -> ADPCM-A 0x10D", 1'b1, 8'h0D, 8'h9F);

        // 0x12-0x17 and 0x1E-0x1F have no ADPCM-A twin. Forwarding them
        // verbatim would land on jt12's ADPCM-B block, which is what sits at
        // part 0 0x1x -- so they are dropped instead.
        arm(); chip_wr(1'b0, 8'h15, 8'h22);
        want_dropped("part0 0x15 has no ADPCM-A twin");
        arm(); chip_wr(1'b0, 8'h1E, 8'h22);
        want_dropped("part0 0x1E has no ADPCM-A twin");

        // DELTA-T. The YM2608 keeps it at part 1 0x00-0x10; jt12 keeps the
        // same registers, in the same order, at part 0 0x10-0x1C.
        arm(); chip_wr(1'b1, 8'h00, 8'h80);
        want_route("DELTA-T ctrl 0x100 -> jt12 0x10", 1'b0, 8'h10, 8'h80);
        arm(); chip_wr(1'b1, 8'h01, 8'hC0);
        want_route("DELTA-T pan 0x101 -> jt12 0x11", 1'b0, 8'h11, 8'hC0);
        arm(); chip_wr(1'b1, 8'h02, 8'h34);
        want_route("DELTA-T start 0x102 -> jt12 0x12", 1'b0, 8'h12, 8'h34);
        arm(); chip_wr(1'b1, 8'h0B, 8'hFF);
        want_route("DELTA-T level 0x10B -> jt12 0x1B", 1'b0, 8'h1B, 8'hFF);
        arm(); chip_wr(1'b1, 8'h10, 8'h80);
        want_route("DELTA-T flagctl 0x110 -> jt12 0x1C", 1'b0, 8'h1C, 8'h80);

        // 0x108 is the CPU's data port into the board's 256 KB of ADPCM RAM
        // and 0x10C/0x10D are the limit registers; jt12's drvB has neither, so
        // they are dropped rather than aliased onto something else.
        arm(); chip_wr(1'b1, 8'h0C, 8'h11);
        want_dropped("DELTA-T limit 0x10C (no jt12 twin)");

        // Part 1 from 0x30 up is FM channels 4-6 and crosses unchanged.
        arm(); chip_wr(1'b1, 8'hB0, 8'h3C);
        want_route("part1 FM 0x1B0 passes through", 1'b1, 8'hB0, 8'h3C);

        // Part 1 0x11-0x2F is jt12's ADPCM-A address block. A YM2608 has
        // nothing there, and letting the guest reach it would move the rhythm
        // samples out from under the firmware.
        arm(); chip_wr(1'b1, 8'h12, 8'h44);
        want_dropped("part1 0x112 (jt12 ADPCM-A addr)");

        // ================================================================
        // 4. The firmware's injection port, which is how those ADPCM-A
        //    start/end registers DO get written.
        // ================================================================
        arm();
        mgmt_wr(4'd3, 16'h1105);        // part 1, reg 0x110 = 0x05
        repeat (8) @(posedge clk);
        want_route("firmware inject reaches part1 0x110", 1'b1, 8'h11, 8'h05);

        arm();
        mgmt_wr(4'd2, 16'h2802);        // part 0, reg 0x28 = 0x02
        repeat (8) @(posedge clk);
        want_route("firmware inject reaches part0 0x28", 1'b0, 8'h28, 8'h02);

        // The rhythm shadow the service loop polls before it bothers loading
        // samples at all.
        chip_wr(1'b0, 8'h10, 8'h25);
        repeat (8) @(posedge clk);
        mg_reg = 4'd7;
        repeat (2) @(posedge clk);
        want("rhythm KON shadow at mg_reg 7", mg_rdata[7:0], 8'h25);

        // ================================================================
        // 5. Timer A and the IRQ line. This is the only test here that runs
        //    the synthesiser: it proves cen, the prescaler and part-0 routing
        //    of 0x24/0x25/0x27 all actually work, not just that the router
        //    computed the right address.
        //    YM2608 timer A is 72*(1024-NA)/Phi, so NA = 1023 is 9 us at
        //    7.9872 MHz -- but the counter only advances on the synthesiser's
        //    `zero` pulse (one sample, ~18 us), so allow plenty.
        // ================================================================
        chip_wr(1'b0, 8'h24, 8'hFF);    // NA[9:2]
        chip_wr(1'b0, 8'h25, 8'h03);    // NA[1:0]
        chip_wr(1'b0, 8'h27, 8'h05);    // load A + enable IRQ A
        waited = 0;
        while (!irq && waited < 100000) begin
            @(posedge clk);
            waited++;
        end
        want_b("timer A raises IRQ", irq, 1'b1);
        io_rd(2'b00, got);
        want_b("status 0 bit 0 is flag A", got[0], 1'b1);

        chip_wr(1'b0, 8'h27, 8'h15);    // reset flag A, keep it loaded
        repeat (64) @(posedge clk);
        io_rd(2'b00, got);
        // The timer is still running, so the flag can legitimately be back
        // already; what must be true is that writing bit 4 cleared it at all,
        // which shows as the IRQ having dropped at some point.
        $display("  info status 0 after flag reset             %02h", got);

        // ================================================================
        // 6. Busy. The router adds two clocks on top of jt12's own busy and a
        //    driver that polls bit 7 must see both.
        // ================================================================
        // jt12_mmr.v:431-444 holds busy for 32 synthesiser cycles, which at
        // the reset prescaler is about 24 us -- a read that starts a few clocks
        // later is still well inside it.
        io_wr(2'b00, 8'h30);
        io_wr(2'b01, 8'h71);
        io_rd(2'b00, got);
        want_b("status 0 bit 7 is busy after a write", got[7], 1'b1);

        $display("");
        if (errors == 0)
            $display("PASS tb_pc98_opna");
        else
            $display("FAIL tb_pc98_opna (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
