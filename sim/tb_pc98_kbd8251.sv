// tb_pc98_kbd8251 -- the keyboard 8251 model against what the ROMs do.
//
// The contract under test comes from the ITF and BIOS disassembly and np2:
//
//   1. status reads 0x85 | RxRDY (np2 keyboard_i43), data reads hold the
//      last byte (0xFF after reset),
//   2. only the 8251 break's falling edge (a 0x43 write with SBRK=1 then
//      one with SBRK=0) arms the 0x60 reset ACK -- plain command writes
//      (the 02/40/5E the BIOS and ITF both send) never do, and no other
//      port can,
//   3. the ACK lands ACK_DELAY_TICKS after the edge; the shipped default
//      is OUTSIDE the ITF's ~82 ms poll window on purpose (the
//      keyboard-present boot path is not walkable by this machine yet --
//      see pc98_kbd8251.sv), so the default is asserted to stay past it,
//      while a short-delay instance proves the in-window behaviour the
//      machine will switch back to,
//   4. reading 0x41 takes the byte and drops RxRDY/IRQ1,
//   5. a second break edge while an ACK is still pending drops it and
//      restarts the timer (np2 keyboard_resetsignal).
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

    // The shipped instance, with its shipped delay. Only its parameter and
    // its "stays silent through an ITF window" behaviour are tested here --
    // at 350 ms a full protocol exercise would be needlessly slow.
    wire       ship_read_select, ship_irq;
    wire [7:0] ship_read_data;

    logic       ship_ctrl_wr = 0, ship_data_rd = 0, ship_stat_rd = 0;
    logic [7:0] ship_data_in = 8'h00;

    pc98_kbd8251 u_shipped (
        .clock              (clock),
        .reset              (reset),
        .ctrl_write_strobe  (ship_ctrl_wr),
        .data_read_strobe   (ship_data_rd),
        .stat_read_strobe   (ship_stat_rd),
        .data_in            (ship_data_in),
        .read_select        (ship_read_select),
        .read_data          (ship_read_data),
        .irq                (ship_irq)
    );

    // The exercised instance: a short ACK delay so the protocol tests run
    // in reasonable time. 1000 ticks = ~23 us.
    localparam int unsigned FAST_TICKS = 1000;

    logic       fast_ctrl_wr = 0, fast_data_rd = 0, fast_stat_rd = 0;
    logic [7:0] fast_data_in = 8'h00;

    wire       fast_read_select, fast_irq;
    wire [7:0] fast_read_data;

    pc98_kbd8251 #(.ACK_DELAY_TICKS(FAST_TICKS)) u_fast (
        .clock              (clock),
        .reset              (reset),
        .ctrl_write_strobe  (fast_ctrl_wr),
        .data_read_strobe   (fast_data_rd),
        .stat_read_strobe   (fast_stat_rd),
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

    task automatic wr43(input logic which_ship, input logic [7:0] cmd);
        begin
            @(negedge clock);
            if (which_ship) begin ship_data_in = cmd; ship_ctrl_wr = 1'b1; end
            else            begin fast_data_in = cmd; fast_ctrl_wr = 1'b1; end
            repeat (3) @(negedge clock);
            ship_ctrl_wr = 1'b0;
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

    task automatic rd43_ship(output logic [7:0] b);
        begin
            @(negedge clock);
            ship_stat_rd = 1'b1;
            @(negedge clock);
            b = ship_read_data;
            repeat (2) @(negedge clock);
            ship_stat_rd = 1'b0;
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

        // ---- 0: the shipped delay stays outside the ITF window ------------
        // The window measured 82 ms = ~3.52 M ticks (12288 poll iterations
        // at ~6.7 us on the 8088 boot bench). If someone wants the
        // keyboard-present boot back, that is a machine fix first -- see
        // pc98_kbd8251.sv -- so the default must stay past the window.
        if (u_shipped.ACK_DELAY_TICKS <= 3_600_000) begin
            errors = errors + 1;
            $display("FAIL: shipped ACK_DELAY_TICKS %0d is inside the ITF window",
                     u_shipped.ACK_DELAY_TICKS);
        end

        // And the shipped model proves it: a full ITF probe's worth of
        // silence after the break. 3.52 M ticks ~= 82 ms of guest time.
        wr43(1'b1, 8'h3A);
        wr43(1'b1, 8'h32);
        wr43(1'b1, 8'h16);
        repeat (3_525_000) @(negedge clock);     // one poll window and change
        rd43_ship(b); expect_eq(b, 8'h85, "shipped: silent through the window");
        if (ship_irq !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: shipped model raised irq inside the window");
        end
        // ... and its ACK does land, after the window: 15.03 M ticks.
        repeat (15_100_000 - 3_525_000) @(negedge clock);
        if (ship_irq !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: shipped model never answered after its delay");
        end
        rd43_ship(b); expect_eq(b, 8'h87, "shipped: ACK pending after delay");

        // ---- 1: reset state (fast instance) -------------------------------
        rd43(b); expect_eq(b, 8'h85, "status after reset");
        rd41(b); expect_eq(b, 8'hFF, "data hold value after reset");
        if (fast_irq !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: irq set after reset");
        end

        // ---- 2: plain command writes arm nothing --------------------------
        // The ITF/BIOS preamble: 02, 40, 5E, none has SBRK.
        wr43(1'b0, 8'h02); wr43(1'b0, 8'h40); wr43(1'b0, 8'h5E);
        repeat (64) @(negedge clock);
        rd43(b); expect_eq(b, 8'h85, "status after 02/40/5E");

        // Wait far past the ACK delay: nothing may arrive.
        repeat (FAST_TICKS + 100) @(negedge clock);
        rd43(b); expect_eq(b, 8'h85, "no phantom ACK from plain writes");

        // ---- 3: the break edge arms the ACK, on the tick ------------------
        // ITF F85FC-F860E: 3A (break on) ... 32 (break off: the edge) ... 16.
        wr43(1'b0, 8'h3A);
        wr43(1'b0, 8'h32);
        wr43(1'b0, 8'h16);

        // Nothing until the timer runs out.
        repeat (FAST_TICKS - 50) @(negedge clock);
        rd43(b); expect_eq(b, 8'h85, "status before ACK delay elapses");
        repeat (100) @(negedge clock);
        if (fast_irq !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: ACK did not land at ACK_DELAY_TICKS");
        end
        rd43(b); expect_eq(b, 8'h87, "status with ACK pending");

        // ---- 4: the read takes it ----------------------------------------
        rd41(b); expect_eq(b, 8'h60, "reset ACK byte");
        if (fast_irq !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: irq still set after 0x41 read");
        end
        rd43(b); expect_eq(b, 8'h85, "status after ACK consumed");
        rd41(b); expect_eq(b, 8'h60, "data register holds the byte");

        // ---- 5: a second break while one waits ---------------------------
        wr43(1'b0, 8'h3A);                     // break on
        repeat (FAST_TICKS / 2) @(negedge clock);
        wr43(1'b0, 8'h32);                     // edge: pending answer is void
        repeat (64) @(negedge clock);
        rd43(b); expect_eq(b, 8'h85, "edge dropped the pending ACK");
        repeat (FAST_TICKS - 100) @(negedge clock);
        rd43(b); expect_eq(b, 8'h85, "still nothing until the new delay");
        wait (fast_irq === 1'b1);
        rd41(b); expect_eq(b, 8'h60, "second ACK");

        // The BIOS's INT 18h AH=3 sequence does it a third time; same shape.
        wr43(1'b0, 8'h3A); wr43(1'b0, 8'h32); wr43(1'b0, 8'h16);
        wait (fast_irq === 1'b1);
        rd41(b); expect_eq(b, 8'h60, "third ACK (BIOS reset)");

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
