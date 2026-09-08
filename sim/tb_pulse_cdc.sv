//
// tb_pulse_cdc -- does a pulse survive the crossing, at awkward clock ratios?
//
// The failure this guards against is not "it does not work at all" -- a naive
// synchroniser works fine at a convenient ratio, which is exactly why it gets
// shipped. It drops or doubles pulses at some ratios and phases and not
// others, and on hardware that is an intermittently wrong display.
//
// So the bench sweeps ratios, including ones where the destination is slower
// than the source and where the periods are not related by a whole number.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pulse_cdc;

    // Two independent generators; the period of each is set per case.
    real src_hp = 5.0, dst_hp = 7.0;
    logic src_clk = 0, dst_clk = 0;
    always #(src_hp) src_clk = ~src_clk;
    always #(dst_hp) dst_clk = ~dst_clk;

    logic rst = 1;
    logic src_pulse = 0;
    wire  src_busy, dst_pulse;

    pulse_cdc dut (
        .src_clk(src_clk), .src_rst(rst), .src_pulse(src_pulse),
        .src_busy(src_busy),
        .dst_clk(dst_clk), .dst_rst(rst), .dst_pulse(dst_pulse)
    );

    int sent = 0, got = 0, errors = 0;

    always @(posedge dst_clk) if (!rst && dst_pulse) got++;

    task automatic one_case(input real s_hp, input real d_hp,
                            input int n, input string what);
        src_hp = s_hp; dst_hp = d_hp;
        rst = 1;
        repeat (4) @(posedge src_clk);
        rst = 0;
        repeat (8) @(posedge src_clk);
        sent = 0; got = 0;

        for (int i = 0; i < n; i++) begin
            // Well separated, the way a text row is: the fill is far shorter
            // than the gap between rows.
            repeat (40) @(posedge src_clk);
            src_pulse = 1'b1;
            @(posedge src_clk);
            src_pulse = 1'b0;
            sent++;
        end
        repeat (80) @(posedge src_clk);
        repeat (80) @(posedge dst_clk);

        $display("  %-28s sent %0d, arrived %0d", what, sent, got);
        if (got !== sent) begin
            $display("    FAIL"); errors++;
        end
    endtask

    initial begin
        $display("=== pulse across clock domains ===");
        // dot -> chipset, the real pair: 21.0526 and 42.954545 MHz.
        one_case(23.750, 11.640, 20, "21.05 -> 42.95 (real)");
        // and back the other way, which is the direction that drops pulses if
        // a plain synchroniser is used.
        one_case(11.640, 23.750, 20, "42.95 -> 21.05 (slower dst)");
        // Awkward ratios with no whole-number relationship.
        one_case(5.000, 7.000, 20, "100 -> 71.4 MHz");
        one_case(7.000, 5.000, 20, "71.4 -> 100 MHz");
        one_case(3.100, 17.900, 20, "161 -> 27.9 MHz");
        // Nearly equal, where a pulse can land right on the edge.
        one_case(10.000, 10.001, 20, "almost identical");

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #5_000_000;
        $display("GLOBAL TIMEOUT"); $finish;
    end

endmodule

`default_nettype wire
