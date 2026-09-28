//
// Pocket mouse: present the shared mouse source (pc98_mouse_src) to the
// machine as a two-button Microsoft serial mouse on COM1: an 'M'
// identification byte when the driver asserts RTS, then three-byte
// movement packets at 1200 baud. The dock report capture, scaling and
// gamepad merge live in pc98_mouse_src so the bus mouse sees the same
// stream.
//

module pocket_mouse #(
    parameter clk_rate = 28'd50000000   // clk frequency in Hz, sets the baud divisor
) (
    input               clk,          // clk_chipset
    input  signed [15:0] ev_dx,       // movement step, valid while ev_v
    input  signed [15:0] ev_dy,
    input               ev_v,         // one step arrived this cycle
    input         [1:0] btn_now,      // {right, left} merged buttons, 1 = pressed
    input               rts_n,        // COM1 RTS; the assert edge requests identification
    output reg          rd = 1'b1,    // serial data into COM1 RX
    output              flush         // RTS assert edge; resets the source's scale residue
);

    //
    // Accumulate deltas between packets, saturating at the packet's signed
    // 8-bit range; reports arriving while a packet is in flight sum into the
    // next one.
    //
    reg  signed [7:0] acc_x = 8'sd0, acc_y = 8'sd0;
    reg  [1:0]        btn_sent = 2'd0;

    function signed [7:0] sat8(input signed [16:0] v);
        sat8 = (v > 17'sd127) ? 8'sd127 : (v < -17'sd127) ? -8'sd127 : v[7:0];
    endfunction

    //
    // Serial transmit: a 30-bit frame (three 10-bit 7N1 bytes, LSB first)
    // shifted out at 1200 baud, line idle high. Packet byte 1 carries the sync
    // flag (bit 6), buttons and delta bits 7:6; bytes 2 and 3 the low six
    // delta bits. Bit 7 is 1 on every byte, so an 8-bit read sees a stop bit
    // in its place.
    //
    localparam [15:0] BAUDDIV = clk_rate / 1200 - 1;   // 1200 baud, minus one

    // 'M' identification, led by 20 bit times of idle line: the power-up
    // settle a driver waits out after asserting RTS.
    localparam [29:0] FRAME_M = 30'h39AFFFFF;

    wire [7:0]  pkt_b1 = {2'b11, btn_now[0], btn_now[1], acc_y[7:6], acc_x[7:6]};
    wire [7:0]  pkt_b2 = {2'b10, acc_x[5:0]};
    wire [7:0]  pkt_b3 = {2'b10, acc_y[5:0]};
    wire [29:0] frame_pkt = {1'b1, pkt_b3, 2'b01, pkt_b2, 2'b01, pkt_b1, 1'b0};

    reg [29:0] shift   = {30{1'b1}};
    reg  [4:0] bits    = 5'd0;
    reg [15:0] baud    = 16'd0;
    reg        rts_n_q = 1'b1;

    wire rts_assert = rts_n_q & ~rts_n;
    wire tx_idle    = (bits == 5'd0) && (baud == 16'd0);
    // A packet may not load in the cycle a step folds in: a report that
    // changes buttons AND carries a delta would otherwise ship the button
    // change with the pre-fold (zero) delta and send the movement in a
    // second packet. Deferring one clock lets the accumulator see the step.
    wire pkt_load   = tx_idle && !rts_n && !ev_v &&
                      ((acc_x != 8'sd0) || (acc_y != 8'sd0) || (btn_now != btn_sent));

    // A packet load empties the accumulators; a step landing that same cycle
    // still folds in.
    wire signed [16:0] sum_x = (pkt_load ? 17'sd0 : acc_x) + (ev_v ? ev_dx : 17'sd0);
    wire signed [16:0] sum_y = (pkt_load ? 17'sd0 : acc_y) + (ev_v ? ev_dy : 17'sd0);

    assign flush = rts_assert;

    always @(posedge clk) begin
        rts_n_q <= rts_n;

        acc_x <= rts_assert ? 8'sd0 : sat8(sum_x);
        acc_y <= rts_assert ? 8'sd0 : sat8(sum_y);

        if (baud != 16'd0)
            baud <= baud - 16'd1;
        else if (bits != 5'd0) begin
            {shift, rd} <= {1'b1, shift};
            bits <= bits - 5'd1;
            baud <= BAUDDIV;
        end

        // The RTS assert edge answers 'M', aborting any frame in flight;
        // otherwise pending movement or a button change loads a packet.
        if (rts_assert || pkt_load) begin
            {shift, rd} <= {1'b1, rts_assert ? FRAME_M : frame_pkt};
            bits     <= 5'd29;
            baud     <= BAUDDIV;
            btn_sent <= btn_now;
        end
    end

endmodule
