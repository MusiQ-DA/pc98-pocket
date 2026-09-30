// SPDX-License-Identifier: GPL-3.0-or-later
//
// fdd_sound -- a floppy drive's mechanism noise, synthesised into the mix.
//
// A real drive's sound is percussive, not tonal: each head step is a short
// mechanical knock (a broadband snap plus a low resonant body that decays
// in a few milliseconds), the head-load solenoid is a deeper, louder thud,
// and the media under the head is a steady hiss while it spins. So every
// voice here is an exponentially-decaying envelope driving noise and one
// low square -- the envelope falls as env -= env>>K, no multipliers.
//
//   STEP KNOCK ("グッ" / the "ガガガ" of a long seek) -- step_pulse, one clk
//   pulse per head step (floppy.v's seek terms). Each pulse reloads the
//   knock envelope; it decays in ~3 ms, so a burst of steps chains knocks at
//   the step rate exactly the way the actuator does. Body ~380 Hz on the
//   5.25" voice, ~560 Hz on a 3.5".
//
//   HEAD-LOAD THUD ("カコン") -- the rising edge of head_load: the solenoid
//   thud, ~10 ms decay on a ~190 Hz body, the loudest voice. (head_load
//   tracks motor_on here, so the release edge can never play -- the gate
//   mutes the same cycle. If a real head-load line ever lands, give the
//   falling edge a click of its own.)
//
//   MEDIA HISS ("シャー", the contact friction of a transfer) -- xfer_active
//   level, pure LFSR noise with a ~5.5 Hz rotational wobble between two
//   levels; sector gaps gate it, so a sequential read chugs with the drive's
//   own rhythm. Track hops inside the transfer still land as knocks.
//
//   MOTOR WHIR -- while motor_on, a ±low noise whir with a faint ~300 Hz
//   hum under it; nearly subliminal, it exists so a spinning drive is not
//   the same silence as an off one.
//
//   mode picks the cabinet: 1 = loud 5.25" (deep thud, heavy knock),
//   2 = 3.5" (higher knock, quiet everything -- the drives self-load on
//   insert, so their load click is small too), 0 = off.
//   motor_on && mode!=0 is the master gate: low freezes every counter,
//   clears the envelopes, and forces audio to exactly 0.
//
// Timing: everything advances on an internal ~48 kHz sample tick divided
// out of clk -- the cadence audio_mixer expects -- so `audio` holds between
// ticks and the mixer's change-detect FIFO sees ~48 kHz of writes.
//
// Area: one LFSR, two envelopes, three toggle dividers, two shift-decays.
// No multipliers, no ROMs.
//
// SPDX-FileType: SOURCE
//
`default_nettype none

module fdd_sound #(
    parameter int CLK_HZ = 42_954_545,  // clk frequency (clk_chipset)
    parameter int SMP_HZ = 48_000       // sample tick rate
) (
    input  logic               clk,
    input  logic               reset,
    input  logic [1:0]         mode,      // 0=off, 1=5.25", 2=3.5"
    input  logic               step_pulse,
    input  logic               head_load,
    input  logic               xfer_active,
    input  logic               motor_on,
    output logic signed [15:0] audio
);

    wire mode35   = (mode == 2'd2);
    wire drive_en = motor_on && (mode != 2'd0);

    // ------------------------------------------------------------- timing
    //
    // Sample tick: a plain integer divider, CLK_HZ/SMP_HZ = 894 clocks at
    // 42.95 MHz (~48.0 kHz; needs CLK_HZ/SMP_HZ < 1024).
    localparam int SMP_DIV = CLK_HZ / SMP_HZ;
    logic [9:0] smp_div;
    wire        smp_ce = (smp_div == 10'(SMP_DIV - 1));
    always_ff @(posedge clk) begin
        if (reset || !drive_en) smp_div <= 10'd0;
        else                    smp_div <= smp_ce ? 10'd0 : smp_div + 10'd1;
    end

    // ------------------------------------------------------------ noise
    //
    // One 16-bit Fibonacci LFSR (x^16 + x^14 + x^13 + x^11 + 1) supplies
    // every noise source; different taps decorrelate the voices.
    logic [15:0] lfsr;
    wire         lfsr_fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    always_ff @(posedge clk) begin
        if (reset)          lfsr <= 16'hACE1;
        else if (smp_ce)    lfsr <= {lfsr[14:0], lfsr_fb};
    end

    // --------------------------------------------------- body resonators
    //
    // Low squares pace the percussive voices -- what the ear hears as the
    // "thock"/"thud" pitch is this, not a filter:
    //   sq380 ~381 Hz (SMP/126)  -- 5.25" step-knock body (560 Hz on 3.5")
    //   sq560 ~571 Hz (SMP/84)   -- 3.5" step-knock body
    //   sq190 ~190 Hz (SMP/252)  -- head-load thud body
    //   sq300 ~298 Hz (SMP/161)  -- motor hum
    logic [6:0] c380;
    logic [6:0] c560;
    logic [7:0] c190;
    logic [7:0] c300;
    logic       sq380, sq560, sq190, sq300;
    always_ff @(posedge clk) begin
        if (reset || !drive_en) begin
            c380 <= 7'd0;    sq380 <= 1'b0;
            c560 <= 7'd0;    sq560 <= 1'b0;
            c190 <= 8'd0;    sq190 <= 1'b0;
            c300 <= 8'd0;    sq300 <= 1'b0;
        end else if (smp_ce) begin
            if (c380 == 7'd62)   begin c380 <= 7'd0;  sq380 <= ~sq380; end
            else                      c380 <= c380 + 7'd1;
            if (c560 == 7'd41)   begin c560 <= 7'd0;  sq560 <= ~sq560; end
            else                      c560 <= c560 + 7'd1;
            if (c190 == 8'd125)  begin c190 <= 8'd0;  sq190 <= ~sq190; end
            else                      c190 <= c190 + 8'd1;
            if (c300 == 8'd80)   begin c300 <= 8'd0;  sq300 <= ~sq300; end
            else                      c300 <= c300 + 8'd1;
        end
    end

    // ----------------------------------------------------- the envelopes
    //
    // Exponential decay as env -= (env>>K)|1 per sample tick: tau ~ 2^K
    // samples up top (the part that reads as the decay time) and the |1
    // walks the tail to zero. K=7 -> ~2.7 ms knock, K=9 -> ~10.7 ms thud.
    // A strike reloads the envelope outright -- every step is one identical
    // knock, and fast step bursts just retrigger.

    // knock: one per head step.
    localparam logic [11:0] KNOCK_AMP = 12'h900;
    logic [11:0] knock_env;
    always_ff @(posedge clk) begin
        if (reset || !drive_en)  knock_env <= 12'd0;
        else if (step_pulse)     knock_env <= KNOCK_AMP;
        else if (smp_ce && |knock_env)
            knock_env <= knock_env - (12'(knock_env >> 7) | 12'd1);
    end

    // thud: the head-load (motor-on) rising edge, the loudest voice.
    logic        head_load_q;
    logic [11:0] clunk_env;
    always_ff @(posedge clk) begin
        if (reset) head_load_q <= 1'b0;
        else       head_load_q <= head_load;
    end
    wire head_edge = head_load ^ head_load_q;
    always_ff @(posedge clk) begin
        if (reset || !drive_en)          clunk_env <= 12'd0;
        else if (head_edge && head_load) clunk_env <= mode35 ? 12'h600 : 12'hFFF;
        else if (smp_ce && |clunk_env)
            clunk_env <= clunk_env - (12'(clunk_env >> 9) | 12'd1);
    end

    // Rotational wobble for the hiss: ~5.5 Hz at the sample rate, 60% of the
    // period at the louder level -- the disk's surface modulates the contact
    // noise once per revolution.
    logic [13:0] wobble;
    always_ff @(posedge clk) begin
        if (reset || !drive_en) wobble <= 14'd0;
        else if (smp_ce)        wobble <= (wobble == 14'd8730) ? 14'd0 : wobble + 14'd1;
    end
    wire hiss_hi = (wobble < 14'd5300);

    // ------------------------------------------------------------- voice
    //
    // Each voice is a sign flip of its envelope (or a fixed level for the
    // continuous noises) -- a signed ±1 multiplier is free. The knock and
    // thud sum a body square and a noise snap under the same envelope.
    wire signed [13:0] knock_a = $signed({2'b00, knock_env});
    wire signed [13:0] clunk_a = $signed({2'b00, clunk_env});
    wire        knock_body = mode35 ? sq560 : sq380;
    wire signed [13:0] knock_term =
        (knock_body ? knock_a : -knock_a) +
        (lfsr[0]   ? knock_a : -knock_a);

    wire signed [13:0] clunk_term =
        (sq190   ? (clunk_a <<< 1) : -(clunk_a <<< 1)) +
        (lfsr[5] ? clunk_a         : -clunk_a);

    wire [11:0] hiss_amp = xfer_active ? (hiss_hi ? 12'd1600 : 12'd1000) : 12'd0;
    wire signed [13:0] hiss_a    = $signed({2'b00, hiss_amp});
    wire signed [13:0] hiss_term = lfsr[9] ? hiss_a : -hiss_a;

    wire [7:0]  motor_amp = mode35 ? 8'd48 : 8'd96;
    wire signed [13:0] motor_a    = $signed({6'b000000, motor_amp});
    wire signed [13:0] motor_term =
        (sq300   ? motor_a : -motor_a) +
        (lfsr[3] ? motor_a : -motor_a);

    // Peak |mix| ~= knock 2*0x900 + thud 3*0x400-ish + hiss + whir << 15 bits.
    wire signed [15:0] mix =
        knock_term + clunk_term + hiss_term + motor_term;

    always_ff @(posedge clk) begin
        if (reset || !drive_en) audio <= 16'sd0;
        else if (smp_ce)        audio <= mix;
    end

endmodule

`default_nettype wire
