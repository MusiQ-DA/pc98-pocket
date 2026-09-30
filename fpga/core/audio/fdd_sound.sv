// SPDX-License-Identifier: GPL-3.0-or-later
//
// fdd_sound -- a loud 5.25" drive, synthesised into the audio mix.
//
// What a real drive sounds like, and which input provokes it:
//
//   SEEK RATTLE ("グッ" / "ジーコジー") -- step_pulse, one clk pulse per head
//   step (floppy.v's delay_steps decrement). Each pulse adds STEP_K to an
//   8-bit energy accumulator that decays linearly (~16 ms from full). The
//   audio source -- LFSR noise XOR a ~2 kHz resonant square -- is gated on by
//   comparing the accumulator against a free-running sawtooth ramp, so the
//   accumulator sets the DENSITY of the burst, not its amplitude: a single
//   step is a short ~62%-density grunt, a burst saturates the accumulator and
//   the rattle goes continuous. Retriggerable, no multiplier anywhere.
//
//   HEAD-LOAD CLUNK ("ガチャン") -- rising edge of head_load. Loads its own
//   8-bit accumulator to full and decays ~32 ms (half the rattle's rate);
//   the source is a ~500 Hz square XOR noise, at over twice the rattle's
//   amplitude: heavier and distinctly louder than any single step.
//
//   TRANSFER BUZZ ("グッ…グッ…グッ") -- xfer_active level, held during the
//   data phase of reads, writes and formats alike (a head on media makes the
//   same noise whichever way the bytes go; formats just hold it longest).
//   A ~400 Hz square made harsh with sparse LFSR bits, gated by an ~8 Hz
//   tremolo at 75% duty so it chugs instead of droning.
//
//   MOTOR HUM -- while motor_on, a ±96-LSB gated-noise whir. Nearly
//   subliminal (-50 dBFS); it exists so "drive spinning" is not quite the
//   same silence as "drive off".
//
//   mode picks the cabinet the synth pretends to be: 1 = a loud 5.25" unit
//   (deep clunk, low rattle), 2 = a 3.5" unit (a soft click instead of the
//   solenoid clunk, thinner rattle, quieter everything), 0 = off.
//   motor_on && mode!=0 is the master gate: low freezes every counter (the
//   cheapest mute), clears the accumulators, and forces audio to exactly 0.
//
// Timing: everything advances on an internal ~48 kHz sample tick divided out
// of clk -- the same cadence the jt12 path feeds audio_mixer -- so `audio`
// holds between ticks and the mixer's change-detect FIFO sees ~48 kHz of
// writes, never a 42.95 MHz burst.
//
// Area: one LFSR, one ramp, two 8-bit accumulators, three toggling divider
// counters and one sum of constants. No multipliers, no ROMs.
//
// SPDX-FileType: SOURCE

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
    // 42.95 MHz (~48.0 kHz; needs CLK_HZ/SMP_HZ < 1024). A fractional
    // accumulator is not worth the adder width for noise glue.
    localparam int SMP_DIV = CLK_HZ / SMP_HZ;
    logic [9:0] smp_div;
    wire        smp_ce = (smp_div == 10'(SMP_DIV - 1));
    always_ff @(posedge clk) begin
        if (reset || !drive_en) smp_div <= 10'd0;
        else                    smp_div <= smp_ce ? 10'd0 : smp_div + 10'd1;
    end

    // Envelope ticks off the sample tick: tick3 every 3rd sample (~16 kHz)
    // paces the rattle decay (~16 ms from full) and the tremolo, tick6
    // (~8 kHz) the clunk's (~32 ms).
    logic [2:0] env_div;
    wire        tick3 = smp_ce && (env_div == 3'd2 || env_div == 3'd5);
    wire        tick6 = smp_ce && (env_div == 3'd5);
    always_ff @(posedge clk) begin
        if (reset || !drive_en)     env_div <= 3'd0;
        else if (smp_ce)            env_div <= (env_div == 3'd5) ? 3'd0 : env_div + 3'd1;
    end

    // -------------------------------------------- shared noise and ramp
    //
    // One 16-bit Fibonacci LFSR (x^16 + x^14 + x^13 + x^11 + 1) feeds every
    // source; one 8-bit sawtooth is the PWM-density reference both energy
    // accumulators compare against (period ~5.3 ms).
    logic [15:0] lfsr;
    logic [ 7:0] ramp;
    wire         lfsr_fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    always_ff @(posedge clk) begin
        if (reset) begin
            lfsr <= 16'hACE1;
            ramp <= 8'd0;
        end else if (smp_ce) begin
            lfsr <= {lfsr[14:0], lfsr_fb};
            ramp <= ramp + 8'd1;
        end
    end

    // --------------------------------------------------------- resonators
    //
    // Four gated squares off the sample tick, in the ranges the ear expects:
    //   sq2k   ~2.0 kHz (SMP/24) -- seek-rattle resonance (5.25")
    //   sq3k   ~3.4 kHz (SMP/14) -- the same rattle on a 3.5" drive
    //   sq500  ~500 Hz  (SMP/96) -- head-load clunk body
    //   sq400  ~400 Hz  (SMP/120) -- transfer buzz
    logic [3:0] c2k;
    logic [2:0] c3k;
    logic [5:0] c500;
    logic [6:0] c400;
    logic       sq2k, sq3k, sq500, sq400;
    always_ff @(posedge clk) begin
        if (reset || !drive_en) begin
            c2k   <= 4'd0;  sq2k  <= 1'b0;
            c3k   <= 3'd0;  sq3k  <= 1'b0;
            c500  <= 6'd0;  sq500 <= 1'b0;
            c400  <= 7'd0;  sq400 <= 1'b0;
        end else if (smp_ce) begin
            if (c2k  == 4'd11)  begin c2k  <= 4'd0;  sq2k  <= ~sq2k;  end
            else                     c2k  <= c2k + 4'd1;
            if (c3k  == 3'd6)   begin c3k  <= 3'd0;  sq3k  <= ~sq3k;  end
            else                     c3k  <= c3k + 3'd1;
            if (c500 == 6'd47)  begin c500 <= 6'd0;  sq500 <= ~sq500; end
            else                     c500 <= c500 + 6'd1;
            if (c400 == 7'd59)  begin c400 <= 7'd0;  sq400 <= ~sq400; end
            else                     c400 <= c400 + 7'd1;
        end
    end

    // ------------------------------------------------- energy envelopes
    //
    // rattle: +STEP_K per step, saturating; -1 per tick3 -> full to zero in
    // ~16 ms (255 x 3 samples at ~48 kHz). A single step gives ~62% density
    // for ~10 ms; steps faster than ~1/4.7 ms keep it saturated = the rattle.
    localparam logic [8:0] STEP_K = 9'd160;
    logic [7:0] rattle;
    wire  [8:0] rattle_add = {1'b0, rattle} + STEP_K;
    always_ff @(posedge clk) begin
        if (reset || !drive_en)      rattle <= 8'd0;
        else if (step_pulse)         rattle <= rattle_add[8] ? 8'hFF : rattle_add[7:0];
        else if (tick3 && |rattle)   rattle <= rattle - 8'd1;
    end

    // clunk: edge-triggered on head_load, -1 per tick6 -> ~32 ms of decay.
    logic       head_load_q;
    logic [7:0] clunk;
    always_ff @(posedge clk) begin
        if (reset) head_load_q <= 1'b0;
        else       head_load_q <= head_load;
    end
    always_ff @(posedge clk) begin
        if (reset || !drive_en)             clunk <= 8'd0;
        else if (head_load && !head_load_q) clunk <= 8'hFF;
        else if (tick6 && |clunk)           clunk <= clunk - 8'd1;
    end

    // trem: ~7.8 Hz (2048 tick3s) at 75% duty paces the transfer buzz. Held
    // at 0 until xfer_active, so every transfer window attacks immediately.
    logic [10:0] trem;
    wire         trem_on = (trem[10:9] != 2'b11);
    always_ff @(posedge clk) begin
        if (reset || !drive_en || !xfer_active) trem <= 11'd0;
        else if (tick3)                         trem <= trem + 11'd1;
    end

    // ------------------------------------------------------------- voice
    //
    // Density gates: the accumulator beats the ramp for acc/256 of each
    // sawtooth period, so envelope decay reads as thinning bursts, not a
    // volume slider -- mechanical, not fader.
    wire rattle_gate = (rattle > ramp);
    wire clunk_gate  = (clunk  > ramp);
    wire buzz_gate   = xfer_active && trem_on;

    // mode35 swaps each source for the 3.5" cabinet's: the solenoid clunk a
    // 5.25" load makes is just a click on a small drive (they self-load on
    // insert), the rattle sits an octave-ish up and everything is quieter.
    wire rattle_src = (mode35 ? sq3k  : sq2k ) ^ lfsr[0];  // resonance + noise
    wire clunk_src  = (mode35 ? sq2k  : sq500) ^ lfsr[5];  // body + thud
    wire buzz_src   = (mode35 ? sq2k  : sq400) ^ (lfsr[9] & lfsr[12]);
    wire hum_src    = lfsr[3];                             // subliminal whir

    // Peak |mix| = 4608+2304+2048+96 = 9056 on 5.25" (~-11 dBFS): clearly
    // audible next to the OPNA path it joins in audio_mixer, bounded so the
    // mixer's own saturating add has real headroom. The clamp below is
    // belt-and-braces for a retuned table, not load-bearing.
    wire signed [16:0] rattle_amp = mode35 ? 17'sd1408 : 17'sd2048;
    wire signed [16:0] clunk_amp  = mode35 ? 17'sd1536 : 17'sd4608;
    wire signed [16:0] buzz_amp   = mode35 ? 17'sd1408 : 17'sd2304;
    wire signed [16:0] hum_amp    = mode35 ? 17'sd48   : 17'sd96;

    logic signed [16:0] mix;
    always_comb begin
        mix = hum_src ? hum_amp : -hum_amp;
        if (rattle_gate) mix = mix + (rattle_src ? rattle_amp : -rattle_amp);
        if (clunk_gate)  mix = mix + (clunk_src  ? clunk_amp  : -clunk_amp);
        if (buzz_gate)   mix = mix + (buzz_src   ? buzz_amp   : -buzz_amp);
    end

    always_ff @(posedge clk) begin
        if (reset || !drive_en) audio <= 16'sd0;
        else if (smp_ce)
            audio <= (^mix[16:15]) ? {mix[16], {15{mix[15]}}} : mix[15:0];
    end

endmodule

`default_nettype wire
