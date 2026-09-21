//
// KF8255_Interrupt_Request
//
// Written by Kitune-san
//
module KF8259_Interrupt_Request (
    input   logic           clock,
    input   logic           reset,

    // Inputs from control logic
    input   logic           level_or_edge_toriggered_config,
    input   logic           freeze,

    // np2 (io/pit.c pit_o71/pit_o77): writing the interval timer's count
    // (or a control word for channel 0) clears the master PIC's IRR bit 0 on
    // the real machine -- it is what keeps a timer interrupt latched BEFORE a
    // reprogram from being delivered AFTER it, into a handler that may since
    // have been replaced.  A strobe, one bit per request line.
    input   logic   [7:0]   external_irr_clear,
    input   logic   [7:0]   clear_interrupt_request,

    // External inputs
    input   logic   [7:0]   interrupt_request_pin,

    // Outputs
    output  logic   [7:0]   interrupt_request_register
);

    logic   [7:0]   low_input_latch;
    wire    [7:0]   interrupt_request_edge;

    genvar ir_bit_no;
    generate
    for (ir_bit_no = 0; ir_bit_no <= 7; ir_bit_no = ir_bit_no + 1) begin: Request_Latch
        //
        // Edge Sense
        //
        // A real 8259A recognizes the LOW-to-HIGH TRANSITION: the detector
        // arms while the input is low and disarms once the request register
        // below has taken the edge, so a pin that STAYS high produces exactly
        // one request.  Without the disarm the detector armed on low and
        // never rearmed-down, which turns "edge" into level-following: every
        // clock of the high half re-asserts IRR.
        //
        // That is not a cosmetic difference on this machine.  The interval
        // timer's OUT is LEGITIMATELY latched high for long stretches: the
        // ITF's own tests drive counter 0 in mode 0 (F854E ctrl 0x30 count
        // 65536; F8A3C count 0x001A for the INT 08 test; F8A60 count 65536
        // again) and mode 0's output goes high at terminal count and STAYS
        // high -- np2 models exactly that, firing pic_setirq(0) once per
        // terminal count and only re-arming PIT_FLAG_I when the mode field
        // says rate generator or square wave (io/pit.c systimer():
        // "(pitch->ctrl & 0x0c) == 0x04").  The POST panel measured the
        // aftermath on hardware: LVL bit 0 asserted (OUT high) with TMR
        // stopped at 5 -- five mode-0 terminal counts across the whole boot
        // and no square wave ever -- while INT, the count of INTR rising
        // edges, sat frozen at 0A57 and the CPU went on executing.
        //
        // Level-following on a pin like that makes IRR bit 0 unclearable.
        // In particular it defeats np2's own defence: a channel-0 write
        // clears the master's IRR bit 0 (io/pit.c pit_o71 and pit_o77:
        // "pic.pi[0].irr &= (~1)"), which is what stops an interrupt latched
        // before a reprogram from being delivered after it.  Peripherals.sv
        // drives that through external_irr_clear below -- and it was inert,
        // because the never-disarmed detector re-asserted the request on the
        // very next clock.  sim/tb_pit_boot_seq.sv phase D measured it:
        // "FAIL: D IRR0 survived a ch0 control write".  The FD80 POST's
        // timed wait is built on that clear (FDE02 ctrl 0x36, FDE0D/FDE15
        // the count, then FDE29 "cli / in al,2 / and al,0FEh / out 2,al /
        // sti"), so with it inert the guest takes an IRQ0 it never armed the
        // instant IF goes up -- and IRQ0 is the master's highest priority,
        // so a handler that does not EOI parks ISR bit 0 and starves the
        // keyboard's IRQ1 and the CRT's IRQ2 for good.
        //
        // The disarm was previously compiled out (KF8259_EDGE_DISARM, commit
        // d0180ef) on the theory that it blanked the Pocket's screen at the
        // ITF's INT 08 test.  That was never bisected -- it was one of four
        // RTL changes since the last bitstream that built, and the same
        // commit also touched Peripherals.sv -- and phase B of the new
        // sim/tb_pic_irq0_edge.sv replays F8A3C..F8A5C and shows the edge
        // detector delivers that request on time.
        //
        // While freeze holds the request register (an acknowledge is
        // sampling it), the detector stays armed so the edge is delivered
        // when the acknowledge finishes instead of being lost.
        always_ff @(posedge clock, posedge reset) begin
        if (reset)
            low_input_latch[ir_bit_no] <= 1'b0;
        else if (clear_interrupt_request[ir_bit_no])
            low_input_latch[ir_bit_no] <= 1'b0;
        else if (~interrupt_request_pin[ir_bit_no])
            low_input_latch[ir_bit_no] <= 1'b1;
        else if (low_input_latch[ir_bit_no] && !freeze)
            low_input_latch[ir_bit_no] <= 1'b0;
        else
            low_input_latch[ir_bit_no] <= low_input_latch[ir_bit_no];
        end

        assign interrupt_request_edge[ir_bit_no] = (low_input_latch[ir_bit_no] == 1'b1) & (interrupt_request_pin[ir_bit_no] == 1'b1);

        //
        // Request Latch
        //
        // Latched, not level-following: the real 8259's IRR holds an edge
        // until the acknowledge clears it. Writing the edge through every
        // clock (IRR <= edge) made any request whose pin did not STAY high
        // -- the CRT interrupt's one-frame pulse, above all -- vanish before
        // ACK1 could sample it, and the chip then acknowledged nothing as
        // IRQ7's vector. The timer got away with it only because mode 0's
        // output stays high.  The freeze hold also keeps the priority
        // resolver's input stable for the whole acknowledge, so the request
        // the ACK2 latch clears is the request the CPU is being told about.
        always_ff @(posedge clock, posedge reset) begin
            if (reset)
                interrupt_request_register[ir_bit_no] <= 1'b0;
            else if (clear_interrupt_request[ir_bit_no])
                interrupt_request_register[ir_bit_no] <= 1'b0;
            else if (freeze)
                interrupt_request_register[ir_bit_no] <= interrupt_request_register[ir_bit_no];
            else if (external_irr_clear[ir_bit_no])
                interrupt_request_register[ir_bit_no] <= 1'b0;
            else if (level_or_edge_toriggered_config)
                interrupt_request_register[ir_bit_no] <= interrupt_request_pin[ir_bit_no];
            else
                interrupt_request_register[ir_bit_no] <= interrupt_request_register[ir_bit_no]
                                                      | interrupt_request_edge[ir_bit_no];
        end
    end
    endgenerate

endmodule
