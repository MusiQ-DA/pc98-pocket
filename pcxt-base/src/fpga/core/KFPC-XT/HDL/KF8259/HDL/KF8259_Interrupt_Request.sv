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
        // below has actually taken the edge, so a pin that STAYS high -- the
        // interval timer's mode-3 square wave holds IRQ0 high for a whole
        // half-period -- produces exactly one request per rising edge.  The
        // original here armed on low but never disarmed, which turned "edge"
        // into level-following: every clock of the high half re-asserted IRR,
        // and the timer interrupt re-fired immediately after every
        // acknowledge.  While freeze holds the request register (an
        // acknowledge is sampling it), the detector stays armed so the edge
        // is delivered when the acknowledge finishes instead of being lost.
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
