// tb_pc98_busmouse -- the second-8255 bus mouse against np21w io/mouseif.c.
//
// The contract under test:
//
//   1. reset state: portc=0xF0 (latched, Y axis, high nibble, IRQ masked),
//      mode=0x93 (all input), latch_x/latch_y=-1, so port A reads 0xEF and
//      port C reads 0xF8, port B reads 0x40;
//   2. port A read: mode bit4 set -> {~L, 1, ~R, 0} | nibble; bit6 picks
//      the axis (1=Y), bit5 the nibble (1=high), bit7 the latch;
//   3. a rising port C bit 7 -- from a port C write OR a control-port bit
//      set -- snapshots the counters clamped to s8 and zeroes them;
//   4. port B reads 0x40 while mode bit1 says input, the written latch
//      otherwise; port A/B read the written byte in output mode;
//   5. port C read applies the mode masks: PORTCH -> & 0x1F, PORTCL ->
//      low nibble 0x08 (np21w's default DIP switches);
//   6. 0x7FDF bit7 set is a mode write, clear is a port C bit set/reset;
//   7. IRQ: port C bit 4 low pulses irq every (clk_rate/120) << timing
//      clocks (0xBFDB picks timing), masked while bit 4 is set;
//   8. the four port A reads after a latch clamp the live counter to s8
//      (np21w mouseif_limitcounter), later reads see it raw.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_busmouse;

    localparam real CLK_MHZ = 42.954545;
    localparam HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0;
    always #(HALF_NS) clock = ~clock;

    logic reset = 1;

    // A short IRQ base so the timing test runs in reasonable time:
    // 48000 Hz -> IRQ_BASE 400 clocks at timing=0.
    localparam int unsigned TEST_CLK = 48000;
    localparam int unsigned IRQ_BASE = TEST_CLK / 120;

    logic       cs = 0, tmr_cs = 0, wr = 0, rd = 0;
    logic [1:0] sel = 0;
    logic [7:0] din = 8'h00;
    wire  [7:0] dout;
    wire        read_select, irq;

    logic signed [15:0] m_dx = 0, m_dy = 0;
    logic               m_ev = 0;
    logic        [1:0]  m_btn = 2'b00;

    pc98_busmouse #(.clk_rate(TEST_CLK)) dut (
        .clk          (clock),
        .rst          (reset),
        .cs           (cs),
        .sel          (sel),
        .wr           (wr),
        .rd           (rd),
        .tmr_cs       (tmr_cs),
        .din          (din),
        .dout         (dout),
        .read_select  (read_select),
        .irq          (irq),
        .m_dx         (m_dx),
        .m_dy         (m_dy),
        .m_ev         (m_ev),
        .m_btn        (m_btn)
    );

    int errors = 0;

    task automatic expect_eq(input logic [7:0] got, input logic [7:0] want,
                             input string what);
        begin
            if (got !== want) begin
                errors = errors + 1;
                $display("FAIL: %s: got %02X want %02X", what, got, want);
            end
        end
    endtask

    // One mouse step, held a cycle like the shared source emits.
    task automatic step(input signed [15:0] dx, input signed [15:0] dy);
        begin
            @(negedge clock);
            m_dx = dx; m_dy = dy; m_ev = 1'b1;
            @(negedge clock);
            m_ev = 1'b0; m_dx = 0; m_dy = 0;
            @(negedge clock);
        end
    endtask

    // Bus access helpers -- strobes held over a few cycles like a real bus
    // cycle, the byte stable throughout.
    task automatic bus_wr(input logic [1:0] port, input logic [7:0] v);
        begin
            @(negedge clock);
            sel = port; cs = 1'b1; din = v; wr = 1'b1;
            repeat (3) @(negedge clock);
            wr = 1'b0; cs = 1'b0;
            @(negedge clock);
        end
    endtask

    task automatic tmr_wr(input logic [7:0] v);
        begin
            @(negedge clock);
            tmr_cs = 1'b1; din = v; wr = 1'b1;
            repeat (3) @(negedge clock);
            wr = 1'b0; tmr_cs = 1'b0;
            @(negedge clock);
        end
    endtask

    task automatic bus_rd(input logic [1:0] port, output logic [7:0] v);
        begin
            @(negedge clock);
            sel = port; cs = 1'b1; rd = 1'b1;
            repeat (2) @(negedge clock);
            v = dout;
            @(negedge clock);
            rd = 1'b0; cs = 1'b0;
            @(negedge clock);
        end
    endtask

    // Port C bit set/reset through the control port, np21w's sft encoding.
    task automatic bsr(input logic [2:0] bitno, input logic on);
        bus_wr(2'd3, {4'b0000, bitno, on});
    endtask

    logic [7:0] b;
    int pulses;

    // Count irq pulses over a window, sampled at negedge.
    task automatic count_irq(input int cycles);
        int i; logic prev;
        begin
            pulses = 0; prev = irq;
            for (i = 0; i < cycles; i++) begin
                @(negedge clock);
                if (irq & ~prev) pulses = pulses + 1;
                prev = irq;
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clock);
        reset = 1'b0;
        repeat (2) @(negedge clock);

        // ---- 0: reset state -------------------------------------------
        // portc=0xF0 read through PORTCL-input mode -> 0xF8; port A is the
        // latched -1 high nibble with buttons released -> 0xEF.
        bus_rd(2'd2, b); expect_eq(b, 8'hF8, "port C after reset");
        bus_rd(2'd0, b); expect_eq(b, 8'hEF, "port A after reset");
        bus_rd(2'd1, b); expect_eq(b, 8'h40, "port B input after reset");
        // 0x7FDF reads are unclaimed in np21w.
        @(negedge clock);
        sel = 2'd3; cs = 1'b1; rd = 1'b1;
        @(negedge clock);
        if (read_select !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: 0x7FDF read was claimed");
        end
        rd = 1'b0; cs = 1'b0;
        @(negedge clock);

        // ---- 1: live counters -----------------------------------------
        // Bit 7 low reads the live counters: +3 X lands in the low nibble
        // once bit5 is cleared, sign bits visible in the high nibble.
        step(16'sd3, -16'sd2);
        bsr(3'd7, 1'b0);                    // live counters     portc: 70
        bsr(3'd6, 1'b0);                    // X axis            portc: 30
        bsr(3'd5, 1'b0);                    // low nibble        portc: 10
        bus_rd(2'd0, b); expect_eq(b, 8'hE3, "live X low nibble");
        bsr(3'd5, 1'b1);                    // high nibble       portc: 30
        bus_rd(2'd0, b); expect_eq(b, 8'hE0, "live X high nibble");
        bsr(3'd6, 1'b1);                    // Y axis            portc: 70
        bsr(3'd5, 1'b0);                    //                   portc: 50
        bus_rd(2'd0, b); expect_eq(b, 8'hEE, "live Y low nibble (-2)");
        bsr(3'd5, 1'b1);                    //                   portc: 70
        bus_rd(2'd0, b); expect_eq(b, 8'hEF, "live Y high nibble (-2)");

        // ---- 2: latch ---------------------------------------------------
        // Bit 7 rising edge snapshots clamped-to-s8 and clears the counters.
        // mx is 3 now; two +120 steps make 243, clamped to 0x7F = 127.
        // my is -2; -100 makes -102 = 0xFF9A -> nibbles A/9 (in range).
        step(16'sd120, 16'sd0);
        step(16'sd120, -16'sd100);
        bsr(3'd7, 1'b1);                    // latch             portc: F0
        bsr(3'd6, 1'b0);                    //                   portc: B0
        bsr(3'd5, 1'b0);                    //                   portc: 90
        bus_rd(2'd0, b); expect_eq(b, 8'hEF, "latched X low nibble (clamped)");
        bsr(3'd5, 1'b1);                    //                   portc: B0
        bus_rd(2'd0, b); expect_eq(b, 8'hE7, "latched X high nibble (clamped)");
        bsr(3'd6, 1'b1);                    //                   portc: F0
        bsr(3'd5, 1'b0);                    //                   portc: D0
        bus_rd(2'd0, b); expect_eq(b, 8'hEA, "latched Y low nibble");
        bsr(3'd5, 1'b1);                    //                   portc: F0
        bus_rd(2'd0, b); expect_eq(b, 8'hE9, "latched Y high nibble");

        // The counters restarted empty; a post-latch step reads live again.
        step(16'sd5, 16'sd0);               // mx = 5
        bsr(3'd7, 1'b0);                    //                   portc: 70
        bsr(3'd6, 1'b0);                    //                   portc: 30
        bsr(3'd5, 1'b0);                    //                   portc: 10
        bus_rd(2'd0, b); expect_eq(b, 8'hE5, "live X after latch clear");

        // ---- 3: buttons --------------------------------------------------
        // {~L, 1, ~R, 0} -- a pressed button clears its bit.
        m_btn = 2'b01;                       // left down
        bus_rd(2'd0, b); expect_eq(b[7:4], 4'h6, "left button");
        m_btn = 2'b10;                       // right down
        bus_rd(2'd0, b); expect_eq(b[7:4], 4'hC, "right button");
        m_btn = 2'b11;
        bus_rd(2'd0, b); expect_eq(b[7:4], 4'h4, "both buttons");
        m_btn = 2'b00;

        // ---- 4: port C read masks ----------------------------------------
        // Whole-port write: bits 7,5,4,2 set (0xB4). The latch edge fires
        // again -- harmless, mx is small -- then the mode masks shape reads.
        bus_wr(2'd2, 8'hB4);                                   // portc: B4
        bus_rd(2'd2, b); expect_eq(b, 8'hB8, "port C read, PORTCL input");
        bus_wr(2'd3, 8'h9B);                 // PORTCH input
        bus_rd(2'd2, b); expect_eq(b, 8'h18, "port C PORTCH-input mask");
        bus_wr(2'd3, 8'h9A);                 // PORTCL output too
        bus_rd(2'd2, b); expect_eq(b, 8'h14, "port C low nibble reads back");
        bus_wr(2'd3, 8'h93);                 // back to the reset mode

        // ---- 5: port latches in output mode ------------------------------
        bus_wr(2'd3, 8'h82);                 // PORTA output, PORTB input
        bus_wr(2'd0, 8'h5A);                 // write port A latch
        bus_rd(2'd0, b); expect_eq(b, 8'h5A, "port A output readback");
        bus_wr(2'd3, 8'h91);                 // PORTA input, PORTB output
        bus_wr(2'd1, 8'hA5);
        bus_rd(2'd1, b); expect_eq(b, 8'hA5, "port B output readback");
        bus_wr(2'd3, 8'h93);

        // ---- 6: BSR flips a port C bit ----------------------------------
        // portc is still 0xB4; set and clear bit 6 through the control port
        // (readable through the PORTCL-forced low nibble's upper half).
        bsr(3'd6, 1'b1);                                       // portc: F4
        bus_rd(2'd2, b); expect_eq(b, 8'hF8, "BSR set bit 6");
        bsr(3'd6, 1'b0);                                       // portc: B4
        bus_rd(2'd2, b); expect_eq(b, 8'hB8, "BSR clear bit 6");

        // ---- 7: IRQ ------------------------------------------------------
        // bit 4 clear enables the timer: 400-clk base at timing=0, so two
        // pulses land in ~2.5 periods; masked again the line stays quiet.
        bsr(3'd4, 1'b0);                                       // portc: A4
        count_irq(IRQ_BASE * 2 + IRQ_BASE / 2);                // ~1000 clks
        expect_eq(pulses[7:0], 8'd2, "irq pulses in 2.5 periods");
        bsr(3'd4, 1'b1);                                       // portc: B4
        count_irq(IRQ_BASE * 2);
        expect_eq(pulses[7:0], 8'd0, "irq while masked");
        tmr_wr(8'h01);                       // timing=1 -> 800-clk period
        bsr(3'd4, 1'b0);                                       // portc: A4
        count_irq(IRQ_BASE * 3);                               // ~1200 clks
        expect_eq(pulses[7:0], 8'd1, "irq pulses at doubled period");
        bsr(3'd4, 1'b1);                                       // portc: B4

        // ---- 8: the post-latch clamp -------------------------------------
        // np21w mouseif_limitcounter: four port A reads after a latch see
        // the live counter clamped to s8; the fifth sees it raw.
        bsr(3'd7, 1'b0);                                       // portc: 34
        step(16'sd90, 16'sd0);
        step(16'sd90, 16'sd0);               // mx = 180 = 0xB4
        bsr(3'd7, 1'b1);                     // latch: mx->0     portc: B4
        step(16'sd90, 16'sd0);
        step(16'sd90, 16'sd0);               // mx = 180 again
        bsr(3'd7, 1'b0);                     // live             portc: 34
        bsr(3'd6, 1'b0);                                       // portc: 34
        bsr(3'd5, 1'b0);                                       // portc: 14
        bus_rd(2'd0, b); expect_eq(b, 8'hEF, "clamped live X low (1/4)");
        bus_rd(2'd0, b); expect_eq(b, 8'hEF, "clamped live X low (2/4)");
        bus_rd(2'd0, b); expect_eq(b, 8'hEF, "clamped live X low (3/4)");
        bus_rd(2'd0, b); expect_eq(b, 8'hEF, "clamped live X low (4/4)");
        bus_rd(2'd0, b); expect_eq(b, 8'hE4, "raw live X low (5th read)");

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
