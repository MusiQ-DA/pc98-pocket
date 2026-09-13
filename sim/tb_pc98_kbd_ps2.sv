//
// tb_pc98_kbd_ps2 -- does the Set-2 -> PC-98 keyboard translation hold up?
//
// The converter sits between pocket_keyboard's Set-2 byte stream and the
// keyboard 8251's injection queue. A wrong code here types the wrong thing in
// N88-BASIC; a lost shift breaks every capital letter. So the bench checks:
//
//   - the code table: letters, digits, symbols, keypad, F-keys, modifiers
//     (spot values are np2kai's sdl/kbtrans.c tables; A make 0x1C -> 0x1D and
//     break -> 0x9D are the pair the task was stated in)
//   - break handling: bit 7 set, through the plain F0 and the E0 F0 forms
//   - the multi-byte sentinels: Pause (E1 ...) must yield ONE STOP make and
//     leave the parser resynchronised; Print Screen (E0 12 E0 7C ...) must
//     yield ONE COPY make/break with the fake shifts swallowed
//   - unmappable keys (F11/F12, Num/Scroll Lock) are silent and do not jam
//     the parser, including as the code of an F0 break
//   - back-to-back makes on consecutive cycles still deliver both events
//     (the toggle strobe is what makes that survivable)
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_kbd_ps2;

    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1;
    logic [7:0] kb_byte = 0;
    logic kb_valid = 0;
    logic kb_ready = 1;     // KFPS2KB paces the real stream; the bench does not test pacing

    logic key_stb, key_make;
    logic [7:0] key_code;

    pc98_kbd_ps2 dut (
        .clk      (clk),
        .reset    (reset),
        .kb_byte  (kb_byte),
        .kb_valid (kb_valid),
        .kb_ready (kb_ready),
        .key_stb  (key_stb),
        .key_make (key_make),
        .key_code (key_code)
    );

    //
    // Event capture. Sampling one cycle behind the toggle is self-correcting:
    // each edge compares the current strobe against the last one seen, so a
    // burst of alternating toggles is caught one per cycle and the data read
    // alongside a detection is the previous cycle's -- exactly the event that
    // caused that toggle.
    //
    int   ev_count = 0;
    int   ev_idx   = 0;
    logic [8:0] ev_data [0:255];
    logic stb_d = 0;

    always @(posedge clk) begin
        stb_d <= key_stb;
        if (key_stb != stb_d) begin
            ev_data[ev_count] = {key_make, key_code};
            ev_count = ev_count + 1;
        end
    end

    int errors = 0;

    // One Set-2 byte, with a couple of idle cycles after it (the real stream
    // is PACE-timed by KFPS2KB and never this dense).
    task automatic send(input logic [7:0] b);
        begin
            kb_byte  = b;
            kb_valid = 1'b1;
            @(posedge clk);
            kb_valid = 1'b0;
            kb_byte  = 8'h00;
            repeat (2) @(posedge clk);
        end
    endtask

    // A burst of bytes on consecutive cycles: valid held, no gaps. This is
    // denser than the real stream ever gets -- it is here to prove no event
    // is lost when two of them land back-to-back.
    logic [7:0] seq_buf [0:15];
    task automatic burst(input int n);
        int i;
        begin
            for (i = 0; i < n; i++) begin
                kb_byte  = seq_buf[i];
                kb_valid = 1'b1;
                @(posedge clk);
            end
            kb_valid = 1'b0;
            kb_byte  = 8'h00;
            repeat (4) @(posedge clk);
        end
    endtask

    // An extended-key pair helper: [E0, b] or [E0, F0, b].
    task automatic send_ext(input logic brk, input logic [7:0] b);
        begin
            send(8'hE0);
            if (brk) send(8'hF0);
            send(b);
        end
    endtask

    task automatic expect_ev(input logic make, input logic [7:0] code,
                             input string what);
        int guard;
        begin
            guard = 0;
            while (ev_idx == ev_count && guard < 1000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (ev_idx == ev_count) begin
                $display("  FAIL %-34s no event arrived (expected %s %02X)",
                         what, make ? "make " : "break", code);
                errors = errors + 1;
            end else begin
                if (ev_data[ev_idx] !== {make, code}) begin
                    $display("  FAIL %-34s got %s %02X, expected %s %02X",
                             what,
                             ev_data[ev_idx][8] ? "make " : "break", ev_data[ev_idx][7:0],
                             make ? "make " : "break", code);
                    errors = errors + 1;
                end else begin
                    $display("  ok   %-34s %s %02X", what,
                             make ? "make " : "break", code);
                end
                ev_idx = ev_idx + 1;
            end
        end
    endtask

    // No event may arrive over the next n cycles; report and drain strays.
    task automatic expect_quiet(input int n, input string what);
        int i;
        begin
            repeat (n) @(posedge clk);
            if (ev_idx != ev_count) begin
                $display("  FAIL %-34s %0d unexpected event(s), first %s %02X",
                         what, ev_count - ev_idx,
                         ev_data[ev_idx][8] ? "make " : "break", ev_data[ev_idx][7:0]);
                errors = errors + 1;
                ev_idx = ev_count;
            end else begin
                $display("  ok   %-34s quiet", what);
            end
        end
    endtask

    task automatic check(input logic [7:0] set2, input logic [7:0] pc98,
                         input string what);
        begin
            send(set2);
            expect_ev(1'b1, pc98, what);
        end
    endtask

    initial begin
        $display("=== PS/2 Set-2 -> PC-98 keyboard codes ===");
        repeat (4) @(posedge clk);
        reset = 0;
        repeat (4) @(posedge clk);

        // ---- the headline pair: A make/break -----------------------------
        send(8'h1C);              expect_ev(1'b1, 8'h1D, "A make (0x1C)");
        send(8'hF0); send(8'h1C); expect_ev(1'b0, 8'h9D, "A break (F0 0x1C)");

        // ---- letters: the three rows --------------------------------------
        check(8'h15, 8'h10, "Q");   check(8'h1D, 8'h11, "W");   check(8'h24, 8'h12, "E");
        check(8'h2D, 8'h13, "R");   check(8'h2C, 8'h14, "T");   check(8'h35, 8'h15, "Y");
        check(8'h3C, 8'h16, "U");   check(8'h43, 8'h17, "I");   check(8'h44, 8'h18, "O");
        check(8'h4D, 8'h19, "P");
        check(8'h1C, 8'h1D, "A");   check(8'h1B, 8'h1E, "S");   check(8'h23, 8'h1F, "D");
        check(8'h2B, 8'h20, "F");   check(8'h34, 8'h21, "G");   check(8'h33, 8'h22, "H");
        check(8'h3B, 8'h23, "J");   check(8'h42, 8'h24, "K");   check(8'h4B, 8'h25, "L");
        check(8'h1A, 8'h29, "Z");   check(8'h22, 8'h2A, "X");   check(8'h21, 8'h2B, "C");
        check(8'h2A, 8'h2C, "V");   check(8'h32, 8'h2D, "B");   check(8'h31, 8'h2E, "N");
        check(8'h3A, 8'h2F, "M");

        // ---- digits and the symbols N88-BASIC needs ------------------------
        check(8'h16, 8'h01, "1");   check(8'h1E, 8'h02, "2");   check(8'h26, 8'h03, "3");
        check(8'h25, 8'h04, "4");   check(8'h2E, 8'h05, "5");   check(8'h36, 8'h06, "6");
        check(8'h3D, 8'h07, "7");   check(8'h3E, 8'h08, "8");   check(8'h46, 8'h09, "9");
        check(8'h45, 8'h0A, "0");
        check(8'h4E, 8'h0B, "- (JIS -)");
        check(8'h55, 8'h0C, "= (JIS ^)");
        check(8'h54, 8'h1A, "[ (JIS @)");
        check(8'h5B, 8'h1B, "] (JIS [)");
        check(8'h5D, 8'h28, "\\ (JIS ])");
        check(8'h4C, 8'h26, "; (JIS ;)");
        check(8'h52, 8'h27, "' (JIS :)");
        check(8'h61, 8'h33, "ISO \\ (JIS _)");
        check(8'h41, 8'h30, ",");   check(8'h49, 8'h31, ".");   check(8'h4A, 8'h32, "/");
        check(8'h29, 8'h34, "space");
        check(8'h5A, 8'h1C, "enter");
        check(8'h66, 8'h0E, "backspace");
        check(8'h76, 8'h00, "ESC (code 00)");
        check(8'h0D, 8'h0F, "tab");

        // ---- modifiers as keys: shifts, ctrl, alt, caps --------------------
        check(8'h12, 8'h70, "left shift");
        send(8'hF0); send(8'h12);   expect_ev(1'b0, 8'hF0, "left shift break");
        check(8'h59, 8'h7D, "right shift");
        send(8'hF0); send(8'h59);   expect_ev(1'b0, 8'hFD, "right shift break");
        check(8'h14, 8'h74, "left ctrl -> CTRL");
        check(8'h11, 8'h51, "left alt -> NFER");
        check(8'h58, 8'h71, "caps lock");

        // a shifted key as the BIOS sees it: shift, A make, A break, shift break
        send(8'h12);               expect_ev(1'b1, 8'h70, "chord: shift down");
        send(8'h1C);               expect_ev(1'b1, 8'h1D, "chord: A down");
        send(8'hF0); send(8'h1C);  expect_ev(1'b0, 8'h9D, "chord: A up");
        send(8'hF0); send(8'h12);  expect_ev(1'b0, 8'hF0, "chord: shift up");

        // ---- extended keys -------------------------------------------------
        send_ext(0, 8'h75);        expect_ev(1'b1, 8'h3A, "up");
        send_ext(1, 8'h75);        expect_ev(1'b0, 8'hBA, "up break");
        send_ext(0, 8'h74);        expect_ev(1'b1, 8'h3C, "right");
        send_ext(0, 8'h6B);        expect_ev(1'b1, 8'h3B, "left");
        send_ext(0, 8'h72);        expect_ev(1'b1, 8'h3D, "down");
        send_ext(0, 8'h70);        expect_ev(1'b1, 8'h38, "insert -> INS");
        send_ext(0, 8'h71);        expect_ev(1'b1, 8'h39, "delete -> DEL");
        send_ext(0, 8'h6C);        expect_ev(1'b1, 8'h3E, "home -> HOME/CLR");
        send_ext(0, 8'h69);        expect_ev(1'b1, 8'h3F, "end -> HELP");
        send_ext(0, 8'h7D);        expect_ev(1'b1, 8'h36, "pgup -> ROLLUP");
        send_ext(0, 8'h7A);        expect_ev(1'b1, 8'h37, "pgdn -> ROLLDOWN");
        send_ext(0, 8'h14);        expect_ev(1'b1, 8'h73, "right ctrl -> GRPH");
        send_ext(1, 8'h14);        expect_ev(1'b0, 8'hF3, "GRPH break");
        send_ext(0, 8'h11);        expect_ev(1'b1, 8'h35, "right alt -> XFER");
        send_ext(0, 8'h4A);        expect_ev(1'b1, 8'h41, "keypad /");
        send_ext(0, 8'h5A);        expect_ev(1'b1, 8'h1C, "keypad enter -> RETURN");

        // ---- the numeric keypad (non-extended codes) ------------------------
        check(8'h6C, 8'h42, "kp 7");   check(8'h75, 8'h43, "kp 8");   check(8'h7D, 8'h44, "kp 9");
        check(8'h6B, 8'h46, "kp 4");   check(8'h73, 8'h47, "kp 5");   check(8'h74, 8'h48, "kp 6");
        check(8'h69, 8'h4A, "kp 1");   check(8'h72, 8'h4B, "kp 2");   check(8'h7A, 8'h4C, "kp 3");
        check(8'h70, 8'h4E, "kp 0");   check(8'h71, 8'h50, "kp .");
        check(8'h7B, 8'h40, "kp -");   check(8'h7C, 8'h45, "kp *");   check(8'h79, 8'h49, "kp +");
        send(8'hF0); send(8'h73);  expect_ev(1'b0, 8'hC7, "kp 5 break");

        // ---- function keys --------------------------------------------------
        check(8'h05, 8'h62, "F1");     check(8'h06, 8'h63, "F2");
        check(8'h04, 8'h64, "F3");     check(8'h0C, 8'h65, "F4");
        check(8'h03, 8'h66, "F5");     check(8'h0B, 8'h67, "F6");
        check(8'h83, 8'h68, "F7");     check(8'h0A, 8'h69, "F8");
        check(8'h01, 8'h6A, "F9");     check(8'h09, 8'h6B, "F10");

        // ---- unmappable keys are silent -------------------------------------
        send(8'h78);   // F11
        send(8'h07);   // F12
        send(8'h77);   // Num Lock
        send(8'h7E);   // Scroll Lock
        expect_quiet(10, "F11/F12/NumLock/ScrollLock silent");
        send(8'h1C);   expect_ev(1'b1, 8'h1D, "parser alive after ignores");
        send(8'hF0); send(8'h78);   // F11 break: nothing, but must return to IDLE
        send(8'h1C);   expect_ev(1'b1, 8'h1D, "parser alive after F0-ignore");

        // ---- Pause: one STOP make out of the 8-byte sequence ----------------
        seq_buf[0]=8'hE1; seq_buf[1]=8'h14; seq_buf[2]=8'h77; seq_buf[3]=8'hE1;
        seq_buf[4]=8'hF0; seq_buf[5]=8'h14; seq_buf[6]=8'hF0; seq_buf[7]=8'h77;
        burst(8);
        expect_ev(1'b1, 8'h60, "Pause -> STOP make");
        expect_quiet(10, "Pause tail swallowed");
        send(8'h1C);   expect_ev(1'b1, 8'h1D, "parser resynced after Pause");

        // ---- Print Screen: COPY, fake shifts swallowed ----------------------
        seq_buf[0]=8'hE0; seq_buf[1]=8'h12; seq_buf[2]=8'hE0; seq_buf[3]=8'h7C;
        burst(4);
        expect_ev(1'b1, 8'h61, "PrintScreen -> COPY make");
        expect_quiet(10, "no phantom shift from PrtSc");
        seq_buf[0]=8'hE0; seq_buf[1]=8'hF0; seq_buf[2]=8'h7C; seq_buf[3]=8'hE0;
        seq_buf[4]=8'hF0; seq_buf[5]=8'h12;
        burst(6);
        expect_ev(1'b0, 8'hE1, "PrintScreen -> COPY break");
        expect_quiet(10, "no phantom shift break");

        // ---- back-to-back makes on consecutive cycles -------------------------
        seq_buf[0]=8'h1C; seq_buf[1]=8'h32;         // A make, B make, no gaps
        burst(2);
        expect_ev(1'b1, 8'h1D, "burst: A");
        expect_ev(1'b1, 8'h2D, "burst: B");

        // ---- typing what the +keys bench types: 3 then RETURN ----------------
        send(8'h26);               expect_ev(1'b1, 8'h03, "typed '3'");
        send(8'hF0); send(8'h26);  expect_ev(1'b0, 8'h83, "typed '3' release");
        send(8'h5A);               expect_ev(1'b1, 8'h1C, "typed RETURN");
        send(8'hF0); send(8'h5A);  expect_ev(1'b0, 8'h9C, "typed RETURN release");

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("GLOBAL TIMEOUT");
        $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
