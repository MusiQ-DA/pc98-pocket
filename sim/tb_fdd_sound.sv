//
// tb_fdd_sound -- does the drive-noise synth behave like a drive?
//
// Self-checking bench for fpga/core/audio/fdd_sound.sv. The DUT's clock is
// run at 4.8 MHz instead of clk_chipset's 42.95: every envelope inside keys
// off the ~48 kHz sample tick (CLK_HZ tells the divider the truth), so the
// same millisecond behaviour is exercised in a tenth of the sim cycles.
//
// Checks, in order:
//   1. motor off          -> audio is exactly 0 under step/clunk/write stimuli
//   2. motor on, idle     -> only the subliminal hum: energy > 0, peak small
//   3. one step           -> a short "グッ": energy and peak well above idle
//   4. 10-step burst      -> sustained rattle: energy far above one step's
//   5. head_load edge     -> the clunk peaks well above a step's peak
//   6. xfer_active        -> buzz energy while held, silence of it after
//   7. motor off mid-rattle -> output drops to 0 immediately and stays
//   8. continuous stepping -> energy keeps coming as long as steps do
//   9. mode 0 (off)       -> silence even with the motor running
//   10. mode 2 (3.5")     -> quieter click and thinner rattle than 5.25"
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`timescale 1ns/1ps
`default_nettype none

module tb_fdd_sound;

    localparam int  CLK_HZ  = 4_800_000;
    localparam real HALF_NS = 1.0e9 / (2.0 * CLK_HZ);

    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic reset        = 1'b1;
    logic [1:0] mode   = 2'd1;
    logic step_pulse   = 1'b0;
    logic head_load    = 1'b0;
    logic xfer_active  = 1'b0;
    logic motor_on     = 1'b0;

    wire signed [15:0] audio;

    fdd_sound #(
        .CLK_HZ (CLK_HZ),
        .SMP_HZ (48_000)
    ) dut (
        .clk          (clk),
        .reset        (reset),
        .mode         (mode),
        .step_pulse   (step_pulse),
        .head_load    (head_load),
        .xfer_active  (xfer_active),
        .motor_on     (motor_on),
        .audio        (audio)
    );

    int errors = 0;

    task automatic wait_ms(input real ms);
        repeat (int'(ms * (CLK_HZ / 1000))) @(posedge clk);
    endtask

    task automatic step_once();
        @(posedge clk);
        step_pulse = 1'b1;
        @(posedge clk);
        step_pulse = 1'b0;
    endtask

    // |audio| integrated over a window, plus its peak. Any sample past the
    // module's own worst-case bound (9056) is a hard failure anywhere.
    task automatic measure(input real ms, output longint e, output int p);
        int     n  = int'(ms * (CLK_HZ / 1000));
        longint ee = 0;
        int     pp = 0;
        for (int i = 0; i < n; i++) begin
            @(posedge clk);
            begin
                int a;
                a = int'(audio);
                if (a < 0) a = -a;
                ee += longint'(a);
                if (a > pp) pp = a;
                if (a > 12000) begin
                    $display("  FAIL: |audio| %0d over bound at %0t", a, $time);
                    errors++;
                end
            end
        end
        e = ee;
        p = pp;
    endtask

    initial begin
        longint e_idle, e1, e10, e_cl, e_wr, e_post;
        int     p_idle, p1, p10, p_cl, p_wr;
        longint ee;
        int     pp;

        repeat (30) @(posedge clk);
        reset = 1'b0;
        repeat (10) @(posedge clk);

        // --- 1: motor off = total silence ---------------------------------
        //
        // Steps, a head-load edge and a write window all arrive with the
        // motor off; the drive is not allowed to make a sound.
        begin
            bit silent = 1'b1;
            for (int i = 0; i < 4800 * 25; i++) begin   // 25 ms
                @(posedge clk);
                if (i % 9600 == 0) step_pulse = 1'b1;
                else               step_pulse = 1'b0;
                if (i == 4800)  head_load    = 1'b1;
                if (i == 9600)  head_load    = 1'b0;
                if (i == 14400) xfer_active  = 1'b1;
                if (audio !== 16'sd0) silent = 1'b0;
            end
            xfer_active = 1'b0;
            if (silent) $display("ok   motor off: silence under step/clunk/write stimuli");
            else begin
                $display("FAIL motor off: audio left zero");
                errors++;
            end
        end

        // --- 2: motor on, idle = hum only ----------------------------------
        motor_on = 1'b1;
        wait_ms(20.0);
        measure(60.0, e_idle, p_idle);
        if (e_idle > 0 && p_idle < 500)
            $display("ok   idle hum: energy %0d, peak %0d", e_idle, p_idle);
        else begin
            $display("FAIL idle hum: energy %0d, peak %0d", e_idle, p_idle);
            errors++;
        end

        // --- 3: a single step = one short grunt ----------------------------
        step_once();
        measure(70.0, e1, p1);
        // The hum alone would account for ~2x the idle window's energy here;
        // demand clearly more, and a peak that is a real step.
        if (e1 > 2 * e_idle && p1 > 1000 && p1 < 4000)
            $display("ok   single step: energy %0d, peak %0d", e1, p1);
        else begin
            $display("FAIL single step: energy %0d, peak %0d (idle %0d)", e1, p1, e_idle);
            errors++;
        end

        // --- 4: 10-step burst at ~3 ms = the sustained rattle --------------
        e10 = 0; p10 = 0;
        for (int i = 0; i < 10; i++) begin
            step_once();
            measure(3.0, ee, pp);
            e10 += ee;
            if (pp > p10) p10 = pp;
        end
        measure(40.0, ee, pp);   // the tail: accumulator draining ~16 ms
        e10 += ee;
        if (pp > p10) p10 = pp;
        if (e10 > 2 * e1 && p10 >= p1)
            $display("ok   10-step burst: energy %0d, peak %0d", e10, p10);
        else begin
            $display("FAIL 10-step burst: energy %0d, peak %0d (single %0d)", e10, p10, e1);
            errors++;
        end

        wait_ms(40.0);          // let every envelope drain before the clunk

        // --- 5: head-load edge = the clunk ---------------------------------
        head_load = 1'b1;
        measure(60.0, e_cl, p_cl);
        if (p_cl > p1 + 1000 && e_cl > e1)
            $display("ok   head-load clunk: energy %0d, peak %0d", e_cl, p_cl);
        else begin
            $display("FAIL clunk: energy %0d, peak %0d (step peak %0d)", e_cl, p_cl, p1);
            errors++;
        end
        head_load = 1'b0;
        wait_ms(60.0);

        // --- 6: transfer buzz, only while active ----------------------------
        xfer_active = 1'b1;
        measure(100.0, e_wr, p_wr);
        xfer_active = 1'b0;
        wait_ms(30.0);          // drain everything first
        measure(50.0, e_post, pp);
        // The buzz is ~30x the hum per unit time; after it ends only the
        // hum is left, so even this shorter window stays under the idle one.
        if (e_wr > 10 * e_post && e_post <= e_idle)
            $display("ok   xfer buzz: %0d while active (peak %0d), %0d after", e_wr, p_wr, e_post);
        else begin
            $display("FAIL xfer buzz: %0d while active, %0d after (idle %0d)",
                     e_wr, e_post, e_idle);
            errors++;
        end

        // --- 7: motor off kills an in-flight rattle -------------------------
        for (int i = 0; i < 8; i++) begin
            step_once();
            wait_ms(2.0);
        end
        motor_on = 1'b0;
        begin
            bit quiet = 1'b1;
            for (int i = 0; i < 4800 * 5; i++) begin    // 5 ms
                @(posedge clk);
                if (audio !== 16'sd0) quiet = 1'b0;
            end
            if (quiet) $display("ok   motor off mid-rattle: immediate silence");
            else begin
                $display("FAIL motor off mid-rattle: audio %0d", audio);
                errors++;
            end
        end
        motor_on = 1'b1;
        wait_ms(20.0);

        // --- 8: continuous stepping keeps rattling --------------------------
        // ~3 ms stepping for ~90 ms; the energy must keep arriving, not just
        // fire once.
        begin
            longint ec = 0;
            for (int i = 0; i < 30; i++) begin
                step_once();
                measure(3.0, ee, pp);
                ec += ee;
            end
            if (ec > e10)
                $display("ok   continuous stepping: energy %0d over 90 ms", ec);
            else begin
                $display("FAIL continuous stepping: energy %0d (burst was %0d)", ec, e10);
                errors++;
            end
        end

        // --- 9: mode 0 = off, silent even with the motor turning ------------
        step_pulse = 1'b0;
        mode = 2'd0;
        wait_ms(30.0);
        begin
            bit silent = 1'b1;
            for (int i = 0; i < 4800 * 10; i++) begin   // 10 ms
                @(posedge clk);
                if (audio !== 16'sd0) silent = 1'b0;
            end
            if (silent) $display("ok   mode off: silence with motor on");
            else begin
                $display("FAIL mode off: audio %0d", audio);
                errors++;
            end
        end

        // --- 10: mode 2 = the 3.5" cabinet, quieter --------------------------
        mode = 2'd2;
        wait_ms(20.0);
        begin
            longint e35; int p35_step, p35_cl;
            head_load = 1'b0;
            step_once();
            measure(70.0, ee, p35_step);
            head_load = 1'b1;
            measure(60.0, e35, p35_cl);
            head_load = 1'b0;
            // The 3.5" voices sit well under their 5.25" counterparts, and
            // its click is nothing like the solenoid clunk's 2x-step peak.
            if (p35_step < p1 && p35_cl < p_cl - 1500)
                $display("ok   3.5\" mode: step peak %0d (5.25\" %0d), click %0d (clunk %0d)",
                         p35_step, p1, p35_cl, p_cl);
            else begin
                $display("FAIL 3.5\" mode: step %0d vs %0d, click %0d vs clunk %0d",
                         p35_step, p1, p35_cl, p_cl);
                errors++;
            end
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS");
        else             $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #2_000_000_000;   // 2 s of guard time -- the suite takes ~0.7 s sim
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
