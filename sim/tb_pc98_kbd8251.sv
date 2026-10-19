// tb_pc98_kbd8251 -- the keyboard 8251 model against what the ROMs do.
//
// The contract under test comes from the ITF and BIOS disassembly and np21w:
//
//   1. status reads 0x85 | RxRDY (np21w keyboard_i43), data reads hold the
//      last byte (0xFF after reset),
//   2. a keyboard reset (the 8251 break's falling edge: a 0x43 write with
//      SBRK=1 then one with SBRK=0) clears the receiver and the queue and
//      sends NOTHING back (np21w keyboard_resetsignal: only held keys are
//      re-sent). Make code 0x60 is the STOP key; the old synthetic 0x60
//      "reset ACK" reached the BIOS IRQ1 handler as a STOP press (INT 06h)
//      and made N88-BASIC re-print "How many files?" on the first boot,
//   3. plain command writes (the 02/40/5E preamble) do nothing either,
//   4. reading 0x41 takes the byte and drops RxRDY/IRQ1,
//   5. injected keys come out in order through a 16-deep queue.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_kbd8251;

    localparam real CLK_MHZ = 42.954545;
    localparam HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0;
    always #(HALF_NS) clock = ~clock;

    logic reset = 1;

    // The model under test. 15.1 M ticks is the old synthetic ACK's
    // 350 ms delay and change: the silence checks wait past it.
    localparam int unsigned OLD_ACK_TICKS = 15_100_000;

    logic       fast_ctrl_wr = 0, fast_data_rd = 0, fast_stat_rd = 0;
    logic [7:0] fast_data_in = 8'h00;
    // Key injection (the translator's {stb, byte} pair).
    logic       fast_key_stb = 0;
    logic [7:0] fast_key_byte = 8'h00;

    wire       fast_read_select, fast_irq;
    wire [7:0] fast_read_data;

    pc98_kbd8251 u_fast (
        .clock              (clock),
        .reset              (reset),
        .ctrl_write_strobe  (fast_ctrl_wr),
        .data_read_strobe   (fast_data_rd),
        .stat_read_strobe   (fast_stat_rd),
        .key_stb            (fast_key_stb),
        .key_byte           (fast_key_byte),
        .data_in            (fast_data_in),
        .read_select        (fast_read_select),
        .read_data          (fast_read_data),
        .irq                (fast_irq)
    );

    int errors = 0;

    // ---- the guest's side of the bus ------------------------------------
    //
    // Strobes held over a whole fake cycle, the way a decoded 8288 command
    // pulse is, with the byte stable throughout.

    task automatic wr43(input logic [7:0] cmd);
        begin
            @(negedge clock);
            fast_data_in = cmd; fast_ctrl_wr = 1'b1;
            repeat (3) @(negedge clock);
            fast_ctrl_wr = 1'b0;
            @(negedge clock);
        end
    endtask

    task automatic rd41(output logic [7:0] b);
        begin
            @(negedge clock);
            fast_data_rd = 1'b1;
            @(negedge clock);
            b = fast_read_data;
            repeat (2) @(negedge clock);
            fast_data_rd = 1'b0;
            @(negedge clock);
        end
    endtask

    // Toggle the injection strobe for one event.
    task automatic inject(input logic [7:0] b);
        begin
            @(negedge clock);
            fast_key_byte = b;
            fast_key_stb  = ~fast_key_stb;
            @(negedge clock);
            @(negedge clock);
        end
    endtask

    task automatic rd43(output logic [7:0] b);
        begin
            @(negedge clock);
            fast_stat_rd = 1'b1;
            @(negedge clock);
            b = fast_read_data;
            repeat (2) @(negedge clock);
            fast_stat_rd = 1'b0;
            @(negedge clock);
        end
    endtask

    task automatic expect_eq(input logic [7:0] got, input logic [7:0] want,
                             input string what);
        begin
            if (got !== want) begin
                errors = errors + 1;
                $display("FAIL: %s: got %02X want %02X", what, got, want);
            end
        end
    endtask

    logic [7:0] b;

    initial begin
        repeat (4) @(negedge clock);
        reset = 1'b0;
        repeat (2) @(negedge clock);

        // ---- 1: reset state ----------------------------------------------
        rd43(b); expect_eq(b, 8'h85, "status after reset");
        rd41(b); expect_eq(b, 8'hFF, "data hold value after reset");
        if (fast_irq !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: irq set after reset");
        end

        // ---- 2: plain command writes do nothing ---------------------------
        // The ITF/BIOS preamble: 02, 40, 5E, none has SBRK.
        wr43(8'h02); wr43(8'h40); wr43(8'h5E);
        repeat (64) @(negedge clock);
        rd43(b); expect_eq(b, 8'h85, "status after 02/40/5E");

        // ---- 3: a keyboard reset answers nothing --------------------------
        // ITF F85FC-F860E / BIOS FE7C7-FE7DB: 3A (break on), 32 (break off:
        // the edge), 16. Wait past the ITF's 82 ms window AND past the old
        // synthetic ACK's 350 ms: no byte, no IRQ1 -- a 0x60 here is a STOP
        // key press to the BIOS.
        wr43(8'h3A); wr43(8'h32); wr43(8'h16);
        repeat (OLD_ACK_TICKS) @(negedge clock);
        rd43(b); expect_eq(b, 8'h85, "no byte after a keyboard reset");
        if (fast_irq !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: keyboard reset raised IRQ1");
        end
        rd41(b); expect_eq(b, 8'hFF, "data register untouched by the reset");

        // ---- 6: key injection reaches the receive register ---------------
        // A make (0x1D = A) then its break (0x9D), typed through the
        // translator's toggle interface.
        inject(8'h1D);
        rd43(b); expect_eq(b, 8'h87, "status after a key make");
        rd41(b); expect_eq(b, 8'h1D, "key make byte");
        if (fast_irq !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: irq set after reading the make");
        end

        // ---- 7: the one-deep hold ----------------------------------------
        // Two events with no read in between: the first lands, the second
        // waits, and both come out in order across two reads.
        inject(8'h26);                        // '3' make -> holding
        inject(8'hA6);                        // '3' break -> hold slot
        rd41(b); expect_eq(b, 8'h26, "held make");
        rd41(b); expect_eq(b, 8'hA6, "held break");
        if (fast_irq !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: irq set after draining the hold");
        end

        // ---- 8: a break edge clears the hold, not just the register ------
        inject(8'h15);                        // 'Q' make lands
        inject(8'h95);                        // 'Q' break -> queue
        wr43(8'h3A); wr43(8'h32);             // keyboard reset
        repeat (8) @(negedge clock);
        // The register still holds the make (np21w keeps the current byte's
        // readable side simple: only the queue depth is dropped).
        rd41(b); expect_eq(b, 8'h15, "make survived the edge");
        rd43(b); expect_eq(b, 8'h85, "held break was dropped by the edge");

        // ---- 9: keys still flow after a reset -----------------------------
        wr43(8'h16);
        inject(8'h1C);                        // RETURN make
        rd43(b); expect_eq(b, 8'h87, "key pending after a reset");
        rd41(b); expect_eq(b, 8'h1C, "key after a reset");
        rd43(b); expect_eq(b, 8'h85, "no second byte behind it");

        // ---- 10: a burst is queued, not dropped ---------------------------
        // Pad presses landing while IRQ1 sits unserviced: the old one-deep
        // hold lost the third event (a break), leaving the key held down.
        inject(8'h3A); inject(8'hBA); inject(8'h3C); inject(8'hBC); inject(8'h1C);
        rd41(b); expect_eq(b, 8'h3A, "burst 1");
        rd41(b); expect_eq(b, 8'hBA, "burst 2 (break kept)");
        rd41(b); expect_eq(b, 8'h3C, "burst 3");
        rd41(b); expect_eq(b, 8'hBC, "burst 4");
        rd41(b); expect_eq(b, 8'h1C, "burst 5");
        rd43(b); expect_eq(b, 8'h85, "burst drained");

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
