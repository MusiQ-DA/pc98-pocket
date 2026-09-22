//
// tb_pic_irq0_edge -- the master PIC's IRQ0 against an interval timer whose
// OUT is legitimately LATCHED HIGH, which is the state the PC-98's own ROMs
// leave counter 0 in for most of a boot.
//
// Why this bench exists.  The guest froze at N88-BASIC's "How many
// files(0-15)?" prompt with every interrupt dead and the CPU still running.
// The POST panel read, at the freeze:
//
//     INT 0A57   INTR rising edges into the CPU  -- FROZEN
//     TMR 05     rising edges of timer_interrupt -- 5, ever
//     LVL 01     the master's eight request lines, live -- bit 0 ASSERTED
//     IRQ 03 / RD 1B   the keyboard raised IRQ1 three times, guest read 27
//
// TMR 05 with LVL bit 0 high is not a broken counter.  It is counter 0 doing
// mode 0 exactly right: OUT goes high at terminal count and STAYS high.  The
// ROMs only ever drive it that way -- ITF F854E (ctrl 0x30, count 65536),
// F8A3C (count 0x001A for the INT 08 test), F8A60 (65536 again) -- and the
// only mode-3 programming in either ROM is FD80's FDE02 (ctrl 0x36, count
// 0x6000 = 100 Hz), which this boot never reached: a square wave would have
// pinned TMR at its 0xFF saturation in half a second.  np2 models the same
// thing as an event, not a level: systimer() calls pic_setirq(0) once per
// terminal count and only re-arms PIT_FLAG_I when the mode field says rate
// generator or square wave (io/pit.c: "(pitch->ctrl & 0x0c) == 0x04").
//
// What was broken was the 8259's edge detector.  It armed while the pin was
// low and never disarmed, so "edge" meant "the pin is high and has ever been
// low" -- a level.  On a pin latched high that makes IRR bit 0 unclearable,
// and in particular it defeats np2's own defence: a channel-0 write clears
// the master's IRR bit 0 (io/pit.c pit_o71 and pit_o77,
// "pic.pi[0].irr &= (~1)"), which Peripherals.sv drives through
// external_irr_clear.  With the clear inert the guest takes an IRQ0 it never
// armed the moment it raises IF -- and IRQ0 outranks everything, so a
// handler that does not EOI parks ISR bit 0 and starves IRQ1 and IRQ2.
//
// Phases:
//   A. A pin that stays high requests ONCE, and stays cleared once the np2
//      channel-0 write has cleared it.  (Before the fix: it came straight
//      back, one clock later, forever.)
//   B. The ITF's INT 08 test replayed byte for byte (F8A3C..F8A5C): with the
//      pin already latched high from the previous one-shot, the new count
//      must produce exactly one IRQ0, at its terminal count -- not at the
//      unmask, and not at all before.
//   C. The FD80 POST's timed wait replayed (FDE02 ctrl 0x36, FDE0D/FDE15
//      count 0x6000, FDE29 unmask): the control word clears IRR0 on the way
//      past, so the first IRQ0 is the square wave's first rising edge one
//      full period later -- not an instant spurious one at the STI.
//   D. Regression guard: with IRQ0's pin still latched high and IRQ0 masked,
//      the keyboard's IRQ1 still reaches the CPU with its own vector.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pic_irq0_edge;

    logic clk = 1'b0;
    always #11.641 clk = ~clk;                 // 42.954545 MHz chipset clock
    logic reset = 1'b1;

    // The PC-98 PIT clock, generated the way Peripherals.sv does: phase
    // accumulate 4.9152 MHz of toggles against the chipset clock so the
    // falling edges the chip counts land at 2.4576 MHz on average.
    logic timer_clock = 1'b0;
    logic [31:0] pit_clk_phase = 32'd0;
    localparam logic [31:0] PIT_CLK_TOGGLE_HZ = 32'd4_915_200;
    localparam logic [31:0] CHIPSET_HZ        = 32'd42_954_545;
    always_ff @(posedge clk) begin
        if ({1'b0, pit_clk_phase} + PIT_CLK_TOGGLE_HZ >= CHIPSET_HZ) begin
            pit_clk_phase <= pit_clk_phase + PIT_CLK_TOGGLE_HZ - CHIPSET_HZ;
            timer_clock   <= ~timer_clock;
        end
        else
            pit_clk_phase <= pit_clk_phase + PIT_CLK_TOGGLE_HZ;
    end

    // ---- the PIT -----------------------------------------------------
    logic        pit_cs_n = 1'b1;
    logic        pit_wr_n = 1'b1;
    logic [1:0]  pit_a    = 2'b00;
    logic [7:0]  pit_din  = 8'h00;
    wire  [7:0]  pit_dout;
    wire         out0, out1, out2;

    i8253 u_pit (
        .clock            (clk),
        .reset            (reset),
        .chip_select_n    (pit_cs_n),
        .read_enable_n    (1'b1),
        .write_enable_n   (pit_wr_n),
        .address          (pit_a),
        .data_bus_in      (pit_din),
        .data_bus_out     (pit_dout),
        .counter_0_clock  (timer_clock), .counter_0_gate (1'b1),
        .counter_0_out    (out0),
        .counter_1_clock  (timer_clock), .counter_1_gate (1'b1),
        .counter_1_out    (out1),
        .counter_2_clock  (timer_clock), .counter_2_gate (1'b1),
        .counter_2_out    (out2)
    );

    // np2's channel-0 IRR clear, decoded exactly as Peripherals.sv does it.
    logic pit_write_cycle_q = 1'b0;
    wire  pit_write_cycle   = ~pit_cs_n & ~pit_wr_n;
    wire  pit_write_done    = pit_write_cycle_q & ~pit_write_cycle;
    wire  pit0_write_clears_irr0 = pit_write_done &
           (  (pit_a == 2'b00)
            | ((pit_a == 2'b11) & (pit_din[7:6] == 2'b00)
                                & (pit_din[5:4] != 2'b00)));
    always_ff @(posedge clk)
        pit_write_cycle_q <= pit_write_cycle;

    // ---- the master PIC ----------------------------------------------
    logic        pic_cs_n = 1'b1;
    logic        pic_rd_n = 1'b1;
    logic        pic_wr_n = 1'b1;
    logic        pic_a    = 1'b0;
    logic [7:0]  pic_din  = 8'h00;
    wire  [7:0]  pic_dout;
    logic        inta_n   = 1'b1;
    wire         pic_int;

    logic        kbd_irq  = 1'b0;          // IRQ1, the 8251's line

    i8259 u_pic (
        .clock            (clk),
        .reset            (reset),
        .chip_select_n    (pic_cs_n),
        .read_enable_n    (pic_rd_n),
        .write_enable_n   (pic_wr_n),
        .address          (pic_a),
        .data_bus_in      (pic_din),
        .data_bus_out     (pic_dout),
        .data_bus_io      (),
        .cascade_in       (3'b000),
        .cascade_out      (),
        .cascade_io       (),
        .slave_program_n  (1'b1),
        .interrupt_acknowledge_n (inta_n),
        .interrupt_to_cpu (pic_int),
        .external_irr_clear ({7'b0, pit0_write_clears_irr0}),
        .interrupt_request({6'b0, kbd_irq, out0})
    );

    wire [7:0] irr = u_pic.u_Interrupt_Request.interrupt_request_register;
    wire [7:0] isr = u_pic.u_In_Service.in_service_register;

    // ---- bus tasks ----------------------------------------------------
    task automatic pit_write(input logic [1:0] a, input logic [7:0] d);
        begin
            @(negedge clk);
            pit_a = a; pit_din = d; pit_cs_n = 1'b0; pit_wr_n = 1'b0;
            repeat (4) @(negedge clk);
            pit_wr_n = 1'b1;
            @(negedge clk);
            pit_cs_n = 1'b1;
            repeat (8) @(negedge clk);
        end
    endtask

    task automatic pic_write(input logic a, input logic [7:0] d);
        begin
            @(negedge clk);
            pic_a = a; pic_din = d; pic_cs_n = 1'b0; pic_wr_n = 1'b0;
            repeat (4) @(negedge clk);
            pic_wr_n = 1'b1;
            @(negedge clk);
            pic_cs_n = 1'b1;
            repeat (8) @(negedge clk);
        end
    endtask

    // Two INTA pulses, the way the 8288 sequences them; the vector comes
    // back on the second.
    task automatic inta_cycle(output logic [7:0] vec);
        begin
            @(negedge clk);
            inta_n = 1'b0;
            repeat (6) @(negedge clk);
            inta_n = 1'b1;
            repeat (6) @(negedge clk);
            inta_n = 1'b0;
            repeat (3) @(negedge clk);
            vec = pic_dout;
            repeat (3) @(negedge clk);
            inta_n = 1'b1;
            repeat (6) @(negedge clk);
        end
    endtask

    // Wait for INT, with a deadline in chipset clocks. ok=0 means it never
    // came.
    task automatic wait_int(input int deadline, output bit ok, output int took);
        begin
            ok = 1'b0; took = 0;
            while (took < deadline && !ok) begin
                @(posedge clk);
                took = took + 1;
                ok = pic_int;
            end
        end
    endtask

    // chipset clocks per microsecond, for the deadlines below
    localparam int CLK_PER_US = 43;

    int errors = 0;
    logic [7:0] vec;
    bit  got;
    int  took;

    initial begin
        repeat (40) @(negedge clk);
        reset = 1'b0;
        repeat (10) @(negedge clk);

        // The VM BIOS's master ICWs, FDA2F-FDA3D: edge triggered (ICW1 bit 3
        // clear), cascade, ICW4; vectors 08-0F; slave on IRQ7; 8086 mode.
        pic_write(1'b0, 8'h11);
        pic_write(1'b1, 8'h08);
        pic_write(1'b1, 8'h80);
        pic_write(1'b1, 8'h1D);
        pic_write(1'b1, 8'hFF);          // IMR: everything masked

        // ================================================================
        // A. A pin latched high requests once, and the np2 clear sticks.
        //
        // Counter 0 powers up in mode 3 idle (i8253.sv RESET_MODE 3), so
        // OUT is high and has never fallen: nothing is armed and IRR0 must
        // be clear.  The ITF's F854E control word takes it to mode 0 and
        // drops OUT; its terminal count is the machine's first real IRQ0
        // rising edge.
        // ================================================================
        $display("\n=== A: one request per rising edge, and it stays cleared ===");
        if (irr[0] !== 1'b0) begin
            $display("*** FAIL: A IRR0 set at power-up with OUT never having fallen");
            errors = errors + 1;
        end

        pit_write(2'b11, 8'h30);          // ITF F854E: ctrl 0x30, mode 0
        pit_write(2'b00, 8'h00);          // count 65536
        pit_write(2'b00, 8'h00);
        if (out0 !== 1'b0) begin
            $display("*** FAIL: A mode 0 did not drop OUT on the count load");
            errors = errors + 1;
        end
        // 65536 counts at 2.4576 MHz = 26.67 ms; wait it out plus slack.
        repeat (1_250_000) @(posedge clk);
        if (out0 !== 1'b1) begin
            $display("*** FAIL: A mode 0 never reached terminal count");
            errors = errors + 1;
        end
        if (irr[0] !== 1'b1) begin
            $display("*** FAIL: A the terminal-count rising edge did not latch IRR0");
            errors = errors + 1;
        end else
            $display("--- A: OUT latched high at terminal count, IRR0 set once");

        // np2's clear, and it must HOLD while the pin sits high.  This is
        // the measurement the old level-following detector failed: IRR0 came
        // back on the next clock, every clock, because the edge detector
        // never disarmed.
        pit_write(2'b00, 8'h1A);          // ITF F8A3E: out 71h, 1Ah
        repeat (200) @(posedge clk);
        if (irr[0] !== 1'b0) begin
            $display("*** FAIL: A IRR0 survived a channel-0 write with OUT high");
            errors = errors + 1;
        end else
            $display("--- A: channel-0 write cleared IRR0 and it stayed cleared");

        // ================================================================
        // B. The ITF's INT 08 test, F8A3C..F8A5C.
        //
        //   F8A3C  mov al,1Ah / out 71h,al      count LSB (done above)
        //   F8A40  xor ax,ax / out 71h,al       count MSB -> 0x001A
        //   F8A4B  mov al,0FEh / out 2,al       unmask IRQ0 only
        //   F8A4F  test ah,0FFh / loop          wait for the handler
        //   F8A6C  mov ah,0FFh / out 2,0FFh / out 0,20h / iret
        //
        // 0x1A counts at 2.4576 MHz is 10.6 us.  Nothing may arrive before
        // that: an IRQ0 at the unmask means the request was a level, not the
        // terminal count.
        // ================================================================
        $display("\n=== B: ITF INT 08 test (F8A3C): one IRQ0, at the terminal count ===");
        pit_write(2'b00, 8'h00);          // F8A46: count MSB -> 0x001A
        pic_write(1'b1, 8'hFE);           // F8A4D: unmask IRQ0

        // 5 us of slack around the write; the terminal count is 10.6 us out.
        repeat (5 * CLK_PER_US) @(posedge clk);
        if (pic_int !== 1'b0) begin
            $display("*** FAIL: B IRQ0 asserted at the unmask, %0d us before its terminal count",
                     10 - 5);
            errors = errors + 1;
        end else
            $display("--- B: quiet at the unmask, as it must be");

        wait_int(20 * CLK_PER_US, got, took);
        if (!got) begin
            $display("*** FAIL: B the terminal-count IRQ0 never arrived (ITF halts at F8A56)");
            errors = errors + 1;
        end else begin
            $display("--- B: IRQ0 arrived %0d us after the unmask (0x1A counts = 10.6 us)",
                     (took + 5 * CLK_PER_US) / CLK_PER_US);
            inta_cycle(vec);
            if (vec !== 8'h08) begin
                $display("*** FAIL: B vector %02X, expected 08", vec);
                errors = errors + 1;
            end
            pic_write(1'b1, 8'hFF);       // F8A6E: the handler masks all
            pic_write(1'b0, 8'h20);       // F8A76: non-specific EOI
            if (isr !== 8'h00) begin
                $display("*** FAIL: B EOI did not clear ISR (%02X)", isr);
                errors = errors + 1;
            end
        end

        // ================================================================
        // C. The FD80 POST's timed wait, FDE00..FDE34.
        //
        //   FDE00  mov al,36h / out 77h,al      ctrl: ch0, LSB+MSB, mode 3
        //   FDE0B  mov al,0 / out 71h,al        count LSB
        //   FDE0F  mov al,60h / out 71h,al      count MSB -> 0x6000, 100 Hz
        //   FDE29  cli / in al,2 / and al,0FEh / out 2,al / sti
        //
        // Counter 0's OUT is still latched high from B's mode-0 one-shot --
        // the exact hardware state the panel measured (LVL 01, TMR frozen).
        // The mode-3 control word drives OUT high again as its idle level,
        // so on a level-following detector the STI at FDE34 takes an
        // immediate IRQ0 that the ROM never asked for.  np2 is explicit that
        // it must not: the control word clears IRR0 (pit_o77).
        //
        // The square wave's OUT starts high, falls at the first terminal
        // count 5 ms later, and rises 5 ms after that: the first legitimate
        // IRQ0 is one full 10 ms period out.
        // ================================================================
        $display("\n=== C: FD80 timed wait (FDE00): no spurious IRQ0 at the STI ===");

        // First the ITF's own last word on counter 0, F8A60: "xor al,al /
        // out 71h,al / out 71h,al" -- mode 0 again, count 65536, with IRQ0
        // masked by the handler that just ran.  Its terminal count 26.7 ms
        // later latches IRR0 with nobody to acknowledge it, and leaves OUT
        // high for the rest of the boot.  That is the state the panel read.
        pit_write(2'b00, 8'h00);          // F8A62
        pit_write(2'b00, 8'h00);          // F8A68
        repeat (1_250_000) @(posedge clk);
        if (out0 !== 1'b1 || irr[0] !== 1'b1) begin
            $display("*** FAIL: C setup -- expected OUT high and IRR0 latched, got out0=%b irr0=%b",
                     out0, irr[0]);
            errors = errors + 1;
        end else
            $display("--- C: ITF F8A60 left OUT latched high and IRR0 set, IRQ0 masked");

        pit_write(2'b11, 8'h36);          // FDE02
        pit_write(2'b00, 8'h00);          // FDE0D
        pit_write(2'b00, 8'h60);          // FDE23 -> 0x6000
        pic_write(1'b1, 8'hFE);           // FDE30: unmask IRQ0

        // 2 ms of quiet is the assertion; the real edge is 10 ms out.
        repeat (2000 * CLK_PER_US) @(posedge clk);
        if (pic_int !== 1'b0) begin
            $display("*** FAIL: C spurious IRQ0 at the STI -- the ch0 writes did not clear IRR0");
            errors = errors + 1;
        end else
            $display("--- C: 2 ms of quiet after the unmask, IRR0 %b", irr[0]);

        // and the real one must still come, one period later
        wait_int(12000 * CLK_PER_US, got, took);
        if (!got) begin
            $display("*** FAIL: C the square wave's first IRQ0 never arrived");
            errors = errors + 1;
        end else begin
            $display("--- C: the square wave's first IRQ0 at %0d ms after the unmask",
                     (took + 2000 * CLK_PER_US) / (1000 * CLK_PER_US));
            inta_cycle(vec);
            if (vec !== 8'h08) begin
                $display("*** FAIL: C vector %02X, expected 08", vec);
                errors = errors + 1;
            end
            pic_write(1'b0, 8'h20);       // EOI
        end

        // ================================================================
        // D. The keyboard still gets in.  Park counter 0 back in a spent
        // mode-0 one-shot -- OUT high, IRQ0 masked -- which is the state the
        // freeze was measured in, and check that IRQ1 reaches the CPU with
        // its own vector.  IRQ 03 / RD 1B on the panel says the 8251 was
        // raising IRQ1 and the guest was reading the port; what it never got
        // was the interrupt.
        // ================================================================
        $display("\n=== D: with IRQ0's pin latched high, the keyboard still gets in ===");
        pit_write(2'b11, 8'h30);          // mode 0
        pit_write(2'b00, 8'h40);          // count 0x0040, 26 us
        pit_write(2'b00, 8'h00);
        repeat (200 * CLK_PER_US) @(posedge clk);   // let it latch high
        pic_write(1'b1, 8'hFD);           // mask IRQ0, unmask IRQ1
        repeat (100) @(posedge clk);

        kbd_irq = 1'b1;
        repeat (20) @(posedge clk);
        kbd_irq = 1'b0;
        wait_int(200 * CLK_PER_US, got, took);
        if (!got) begin
            $display("*** FAIL: D the keyboard's IRQ1 never reached the CPU");
            errors = errors + 1;
        end else begin
            inta_cycle(vec);
            if (vec !== 8'h09) begin
                $display("*** FAIL: D vector %02X, expected 09 (IRQ1)", vec);
                errors = errors + 1;
            end else
                $display("--- D: IRQ1 delivered as vector 09 with OUT still high");
            pic_write(1'b0, 8'h20);
        end

        if (errors == 0)
            $display("\nPASS tb_pic_irq0_edge\nRESULT: PASS");
        else
            $display("\n*** %0d FAILURES ***\nRESULT: FAIL", errors);
        $finish;
    end

endmodule

`default_nettype wire
