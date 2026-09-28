//
// Shared mouse source: turn the docked USB mouse report stream (cont4_*)
// and the gamepad's mouse mode into one event stream feeding the PC-98
// bus mouse (pc98_busmouse). The Microsoft-serial front end that used to
// share this stream is gone -- the core has no COM1 UART for it to feed.
//
// ev_v strobes once per movement step: a consumed report carries its scaled
// delta, a held D-pad direction carries one pad unit, and a cycle that has
// both delivers their sum. btn is the merged button level,
// {right, left}, 1 = pressed.
//

module pc98_mouse_src #(
    parameter clk_rate = 28'd50000000   // clk frequency in Hz, sets the pad tick divisor
) (
    input               clk,          // clk_chipset
    input        [31:0] cont4_joy,    // docked USB: buttons [23:16], X delta [15:0]
    input        [15:0] cont4_key,    // docked USB: report counter
    input        [15:0] cont4_trig,   // docked USB: Y delta
    input        [5:0]  pad,          // gamepad mouse mode: {B, A, right, left, down, up}, 0 when off
    output reg signed [15:0] ev_dx,
    output reg signed [15:0] ev_dy,
    output reg               ev_v,
    output       [1:0]  btn           // {right, left}, 1 = pressed
);

    //
    // Report capture. The dock rewrites the three cont4 words one at a time,
    // so a raw crossing could pair a new report counter with a stale delta.
    // Latch a snapshot only after all three words have held steady for
    // ~160 us (longer than the gap between the dock's word writes, well
    // inside its poll period): each snapshot is then one complete report,
    // consumed once when its counter changes.
    //
    reg [31:0] joy_s0, joy_s1, joy_s;
    reg [15:0] key_s0, key_s1, key_s;
    reg [15:0] trig_s0, trig_s1, trig_s;
    reg [12:0] rpt_stable;
    wire       rpt_steady = (joy_s0 == joy_s1) && (key_s0 == key_s1) && (trig_s0 == trig_s1);

    always @(posedge clk) begin
        joy_s0  <= cont4_joy;  joy_s1  <= joy_s0;
        key_s0  <= cont4_key;  key_s1  <= key_s0;
        trig_s0 <= cont4_trig; trig_s1 <= trig_s0;
        if (!rpt_steady)
            rpt_stable <= 13'd0;
        else if (!(&rpt_stable))
            rpt_stable <= rpt_stable + 13'd1;
        else begin
            joy_s  <= joy_s1;
            key_s  <= key_s1;
            trig_s <= trig_s1;
        end
    end

    // Report fields, little endian; deltas signed, Y positive downward.
    wire signed [15:0] rpt_dx  = {joy_s[7:0], joy_s[15:8]};
    wire signed [15:0] rpt_dy  = {trig_s[7:0], trig_s[15:8]};
    wire         [1:0] rpt_btn = joy_s[17:16];   // [0] = left, [1] = right

    //
    // Sensitivity: scale each arriving report's deltas by 1/8 (tuned on
    // hardware), rounding toward zero so both directions quantise alike, and
    // carry the remainder per axis so slow motion is scaled rather than lost.
    //
    reg signed [3:0] res_x = 4'sd0, res_y = 4'sd0;

    function signed [16:0] tzshr3(input signed [16:0] v);
        tzshr3 = v[16] ? -((-v) >>> 3) : (v >>> 3);
    endfunction

    wire signed [16:0] scl_x  = res_x + rpt_dx;
    wire signed [16:0] scl_y  = res_y + rpt_dy;
    wire signed [16:0] out_x  = tzshr3(scl_x);
    wire signed [16:0] out_y  = tzshr3(scl_y);
    wire signed [16:0] nres_x = scl_x - (out_x <<< 3);
    wire signed [16:0] nres_y = scl_y - (out_y <<< 3);

    reg  [15:0] rpt_count = 16'd0;   // counter of the last consumed report
    reg  [1:0]  btn_q = 2'd0;        // last report's buttons

    wire rpt_new = (key_s != rpt_count);

    //
    // Gamepad mouse: while a D-pad direction is held, step once per pad tick
    // (tuned on hardware); A and B act as the left and right buttons
    // alongside the docked mouse's.
    //
    localparam [17:0] PAD_DIV = clk_rate / 200 - 1;   // 200 counts per second, minus one

    reg [17:0] pad_div = 18'd0;
    wire       pad_tick = (pad_div == 18'd0) && (pad[3:0] != 4'd0);

    wire signed [15:0] pad_dx = pad[3] ? 16'sd1 : pad[2] ? -16'sd1 : 16'sd0;
    wire signed [15:0] pad_dy = pad[1] ? 16'sd1 : pad[0] ? -16'sd1 : 16'sd0;

    assign btn = btn_q | {pad[5], pad[4]};

    always @(posedge clk) begin
        pad_div <= (pad_div == 18'd0) ? PAD_DIV : pad_div - 18'd1;

        if (rpt_new) begin
            rpt_count <= key_s;
            btn_q     <= rpt_btn;
            res_x     <= nres_x[3:0];
            res_y     <= nres_y[3:0];
        end

        ev_v  <= rpt_new | pad_tick;
        ev_dx <= (rpt_new  ? out_x[15:0]  : 16'sd0) + (pad_tick ? pad_dx : 16'sd0);
        ev_dy <= (rpt_new  ? out_y[15:0]  : 16'sd0) + (pad_tick ? pad_dy : 16'sd0);
    end

endmodule
