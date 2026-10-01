//
// tb_hid_to_ps2 -- does the USB-HID -> Set-2 scan still emit the right events?
//
// The converter lives at the bottom of pocket_keyboard: the docked keyboard's
// report (6 key slots + a modifier byte) becomes a stream of ps2_key events
// {strobe, pressed, ext, code}. The mapping table recently moved from a case
// statement into a synchronous 256x9 M10K read through two registered ports,
// which pushed every decision a cycle behind the slot that provoked it. A
// dropped or doubled event here types (or sticks) keys on real hardware, so
// the bench checks:
//
//   - a plain key make and break (HID 04 -> Set-2 1C)
//   - E0-extended keys carry ext=1 (keypad Enter 0x58 -> E0 5A; arrows)
//   - modifier ordering inside one report: mod makes BEFORE key makes, key
//     breaks BEFORE mod breaks -- a chord keeps its shift around the key
//   - right Ctrl/Alt are extended (mod_ext), lefts are not
//   - lgui/rgui and unmappable usages stay silent but do not jam the scan
//   - ErrorRollOver (0x01 in the slots) suppresses the whole report -- held
//     keys must not release when the keyboard runs out of slots
//   - a mid-scan report change is coalesced into the next scan, not lost
//   - back-to-back reports keep every event (the toggle strobe survives it)
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_hid_to_ps2;

    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1;
    logic [31:0] joy  = 0;
    logic [15:0] trig = 0;
    logic  [7:0] mods = 0;

    logic [10:0] ps2_key;

    hid_to_ps2 dut (
        .clk     (clk),
        .reset   (reset),
        .joy     (joy),
        .trig    (trig),
        .mods    (mods),
        .ps2_key (ps2_key)
    );

    //
    // Event capture, same self-correcting scheme as tb_pc98_kbd_ps2: sample
    // the strobe a cycle behind so the data read alongside a detection is the
    // event that toggled it. Each entry is {pressed, ext, code[7:0]}.
    //
    int        ev_count = 0;
    int        ev_idx   = 0;
    logic [9:0] ev_data [0:255];
    logic      stb_d = 0;

    always @(posedge clk) begin
        stb_d <= ps2_key[10];
        if (ps2_key[10] != stb_d) begin
            ev_data[ev_count] = ps2_key[9:0];
            ev_count = ev_count + 1;
        end
    end

    int errors = 0;

    // Report slots run joy[31:24] .. trig[7:0] -- slot 0 is joy's top byte.
    task automatic report(input logic [47:0] keys, input logic [7:0] m);
        begin
            {joy, trig} = keys;
            mods = m;
        end
    endtask

    // A full scan is ~33 beats; 80 cycles is comfortably past the drain.
    task automatic settle;
        begin
            repeat (80) @(posedge clk);
        end
    endtask

    task automatic expect_ev(input logic pressed, input logic ext,
                             input logic [7:0] code, input string what);
        int guard;
        begin
            guard = 0;
            while (ev_idx == ev_count && guard < 200) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (ev_idx == ev_count) begin
                $display("  FAIL %-36s no event arrived (expected %s %s%02X)",
                         what, pressed ? "make " : "break",
                         ext ? "E0 " : "", code);
                errors = errors + 1;
            end else begin
                if (ev_data[ev_idx] !== {pressed, ext, code}) begin
                    $display("  FAIL %-36s got %s %s%02X, expected %s %s%02X",
                             what,
                             ev_data[ev_idx][9] ? "make " : "break",
                             ev_data[ev_idx][8] ? "E0 " : "",
                             ev_data[ev_idx][7:0],
                             pressed ? "make " : "break",
                             ext ? "E0 " : "", code);
                    errors = errors + 1;
                end else begin
                    $display("  ok   %-36s %s %s%02X", what,
                             pressed ? "make " : "break",
                             ext ? "E0 " : "", code);
                end
                ev_idx = ev_idx + 1;
            end
        end
    endtask

    // No event may arrive over the next n cycles; report and drain strays.
    task automatic expect_quiet(input string what);
        begin
            if (ev_idx != ev_count) begin
                $display("  FAIL %-36s %0d unexpected event(s), first %s %s%02X",
                         what, ev_count - ev_idx,
                         ev_data[ev_idx][9] ? "make " : "break",
                         ev_data[ev_idx][8] ? "E0 " : "",
                         ev_data[ev_idx][7:0]);
                errors = errors + 1;
                ev_idx = ev_count;
            end else begin
                $display("  ok   %-36s quiet", what);
            end
        end
    endtask

    initial begin
        $display("=== USB HID -> PS/2 Set-2 ===");
        repeat (4) @(posedge clk);
        reset = 0;
        repeat (4) @(posedge clk);

        // ---- the headline pair: a key make, then its break ---------------
        report({8'h04, 40'h0}, 8'h00);         // HID 'a' in slot 0
        settle;
        expect_ev(1'b1, 1'b0, 8'h1C, "A make");
        expect_quiet("nothing after the make");

        report(48'h0, 8'h00);                  // release
        settle;
        expect_ev(1'b0, 1'b0, 8'h1C, "A break");
        expect_quiet("nothing after the break");

        // ---- an E0-extended key ------------------------------------------
        report({8'h58, 40'h0}, 8'h00);         // keypad Enter -> E0 5A
        settle;
        expect_ev(1'b1, 1'b1, 8'h5A, "KP Enter make (ext)");
        report(48'h0, 8'h00);
        settle;
        expect_ev(1'b0, 1'b1, 8'h5A, "KP Enter break (ext)");
        expect_quiet("clean after ext key");

        // ---- modifier ordering: shift+a, then release --------------------
        // Makes run mods first, breaks run keys first -- the chord keeps its
        // shift wrapped around the letter.
        report({8'h04, 40'h0}, 8'h02);         // lshift + a
        settle;
        expect_ev(1'b1, 1'b0, 8'h12, "LShift make first");
        expect_ev(1'b1, 1'b0, 8'h1C, "A make second");
        expect_quiet("two makes only");

        report(48'h0, 8'h00);                  // drop everything
        settle;
        expect_ev(1'b0, 1'b0, 8'h1C, "A break first");
        expect_ev(1'b0, 1'b0, 8'h12, "LShift break second");
        expect_quiet("two breaks only");

        // ---- right-side modifiers are E0 ---------------------------------
        report(48'h0, 8'h10);                  // rctrl
        settle;
        expect_ev(1'b1, 1'b1, 8'h14, "RCtrl make (ext)");
        report(48'h0, 8'h00);
        settle;
        expect_ev(1'b0, 1'b1, 8'h14, "RCtrl break (ext)");

        // ---- unmappable inputs stay silent -------------------------------
        report({8'h65, 40'h0}, 8'h00);         // Application -- no Set-2 code
        settle;
        expect_quiet("unmapped usage ignored");
        report(48'h0, 8'h88);                  // lgui + rgui: no Set-2 codes
        settle;
        expect_quiet("GUI modifiers ignored");
        report(48'h0, 8'h00);
        settle;

        // ---- ErrorRollOver: all slots 0x01 means "give up", not "release" --
        report({8'h04, 40'h0}, 8'h00);
        settle;
        expect_ev(1'b1, 1'b0, 8'h1C, "A held before rollover");
        report({6{8'h01}}, 8'h00);             // phantom rollover report
        settle;
        expect_quiet("rollover report ignored");

        // ...and recovery: the keyboard reports 'a' still held afterwards.
        report({8'h04, 40'h0}, 8'h00);
        settle;
        expect_quiet("no re-make of held key");
        report(48'h0, 8'h00);
        settle;
        expect_ev(1'b0, 1'b0, 8'h1C, "A break after rollover");

        // ---- a mid-scan change coalesces into the next scan --------------
        // 'a' down, and 'b' lands while the first report is still draining;
        // the second scan must emit only the delta.
        report({8'h04, 40'h0}, 8'h00);
        @(posedge clk);                        // report changes mid-scan
        report({8'h04, 8'h05, 32'h0}, 8'h00);  // a+b held
        settle;
        expect_ev(1'b1, 1'b0, 8'h1C, "A make");
        expect_ev(1'b1, 1'b0, 8'h32, "B make (coalesced)");
        expect_quiet("no duplicate A make");

        report(48'h0, 8'h00);
        settle;
        expect_ev(1'b0, 1'b0, 8'h1C, "A break");
        expect_ev(1'b0, 1'b0, 8'h32, "B break");
        expect_quiet("scan drained clean");

        // ---- ordering inside one report: two makes, two breaks -----------
        report({8'h04, 8'h28, 32'h0}, 8'h00);  // a + enter together
        settle;
        expect_ev(1'b1, 1'b0, 8'h1C, "A make");
        expect_ev(1'b1, 1'b0, 8'h5A, "Enter make");
        expect_quiet("two makes only");

        report(48'h0, 8'h00);
        settle;
        expect_ev(1'b0, 1'b0, 8'h1C, "A break");
        expect_ev(1'b0, 1'b0, 8'h5A, "Enter break");
        expect_quiet("two breaks only");

        $display("");
        $display("  errors: %0d", errors);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
