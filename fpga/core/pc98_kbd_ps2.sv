//
// PS/2 Set-2 scancode stream -> PC-98 keyboard make/break events.
//
// A PC-98 keyboard is not a PC keyboard: it is a serial device on the 8251 at
// ports 0x41/0x43, and every key travels as ONE matrix byte with bit 7 set on
// release. pocket_keyboard merges the controller buttons, the docked USB
// keyboard and the on-screen keyboard into a PS/2 Set-2 byte stream paced by
// ps2_keyboard's kb_ready; this module TAPS that stream (it never stalls it --
// ps2_keyboard keeps the pace, its PACE timer spaces the bytes) and re-emits each
// key as a PC-98 event:
//
//     {key_stb, key_make, key_code[7:0]}
//
// key_stb TOGGLES on every event (the house mailbox idiom: usb_key[10],
// vkb_stb, kbd_stb), so a consumer sampling once per clock cannot lose a
// back-to-back event pair. key_make is 1 for a press, 0 for a release.
// key_code is the byte as it goes on the keyboard's wire: the matrix code for
// a press, that code with bit 7 set for a release. Keys with no PC-98
// equivalent (GUI keys, F11/F12, Num/Scroll Lock) are swallowed silently.
//
// The Set-2 -> PC-98 mapping is BY KEY POSITION, an ANSI keyboard on a JIS
// machine. The code set and the position choices are np2kai's (sdl/kbtrans.c,
// the 101/106 tables): the JIS bracket row sits one key left of the ANSI one
// (US [ is JIS @, US ] is JIS [, US ' is JIS :, US \ is JIS ]), US `~ doubles
// as the JIS yen key, and the ISO key next to left shift (Set-2 0x61) is the
// JIS _/ro key. The Set-2 codes on the left are exactly what hid_to_ps2
// produces for the dock's USB keyboard.
//
// Modifier keys map as KEYS, the way the PC-98 does it: both shifts (0x70 /
// 0x7D), CTRL (0x74), GRPH on right-Ctrl (0x73), NFER on left-Alt (0x51) and
// XFER on right-Alt (0x35). The BIOS builds its shift state from those
// make/break bytes exactly as it would from the real keyboard, which is what
// N88-BASIC needs for uppercase and the shifted symbols.
//

`default_nettype none

module pc98_kbd_ps2 (
    input        clk,         // clk_chipset
    input        reset,
    input  [7:0] kb_byte,     // Set-2 stream, tapped from pocket_keyboard
    input        kb_valid,
    input        kb_ready,    // from ps2_keyboard via Peripherals; paces the stream
    output reg   key_stb,     // toggles per event
    output reg   key_make,    // 1 = press, 0 = release
    output reg [7:0] key_code // PC-98 matrix code, bit 7 already set on release
);

    // PC-98 matrix codes run 0x00-0x7D, so 0xFF can mark "no mapping".
    localparam [7:0] KC_NONE = 8'hFF;

    //
    // Non-extended Set-2 -> PC-98, listed in ANSI keyboard order. The Set-2
    // column matches hid_to_ps2's output byte for byte.
    //
    function automatic [7:0] set2_pc98;
        input [7:0] s;
        case (s)
            8'h76: set2_pc98 = 8'h00; // ESC
            8'h16: set2_pc98 = 8'h01; // 1
            8'h1E: set2_pc98 = 8'h02; // 2
            8'h26: set2_pc98 = 8'h03; // 3
            8'h25: set2_pc98 = 8'h04; // 4
            8'h2E: set2_pc98 = 8'h05; // 5
            8'h36: set2_pc98 = 8'h06; // 6
            8'h3D: set2_pc98 = 8'h07; // 7
            8'h3E: set2_pc98 = 8'h08; // 8
            8'h46: set2_pc98 = 8'h09; // 9
            8'h45: set2_pc98 = 8'h0A; // 0
            8'h4E: set2_pc98 = 8'h0B; // -   (JIS -)
            8'h55: set2_pc98 = 8'h0C; // =   (JIS ^)
            8'h0E: set2_pc98 = 8'h0D; // `   (JIS yen)
            8'h66: set2_pc98 = 8'h0E; // backspace
            8'h0D: set2_pc98 = 8'h0F; // tab
            8'h15: set2_pc98 = 8'h10; // Q
            8'h1D: set2_pc98 = 8'h11; // W
            8'h24: set2_pc98 = 8'h12; // E
            8'h2D: set2_pc98 = 8'h13; // R
            8'h2C: set2_pc98 = 8'h14; // T
            8'h35: set2_pc98 = 8'h15; // Y
            8'h3C: set2_pc98 = 8'h16; // U
            8'h43: set2_pc98 = 8'h17; // I
            8'h44: set2_pc98 = 8'h18; // O
            8'h4D: set2_pc98 = 8'h19; // P
            8'h54: set2_pc98 = 8'h1A; // [   (JIS @)
            8'h5B: set2_pc98 = 8'h1B; // ]   (JIS [)
            8'h5A: set2_pc98 = 8'h1C; // enter
            8'h1C: set2_pc98 = 8'h1D; // A
            8'h1B: set2_pc98 = 8'h1E; // S
            8'h23: set2_pc98 = 8'h1F; // D
            8'h2B: set2_pc98 = 8'h20; // F
            8'h34: set2_pc98 = 8'h21; // G
            8'h33: set2_pc98 = 8'h22; // H
            8'h3B: set2_pc98 = 8'h23; // J
            8'h42: set2_pc98 = 8'h24; // K
            8'h4B: set2_pc98 = 8'h25; // L
            8'h4C: set2_pc98 = 8'h26; // ;   (JIS ;)
            8'h52: set2_pc98 = 8'h27; // '   (JIS :)
            8'h5D: set2_pc98 = 8'h28; // \   (JIS ])
            8'h1A: set2_pc98 = 8'h29; // Z
            8'h22: set2_pc98 = 8'h2A; // X
            8'h21: set2_pc98 = 8'h2B; // C
            8'h2A: set2_pc98 = 8'h2C; // V
            8'h32: set2_pc98 = 8'h2D; // B
            8'h31: set2_pc98 = 8'h2E; // N
            8'h3A: set2_pc98 = 8'h2F; // M
            8'h41: set2_pc98 = 8'h30; // ,
            8'h49: set2_pc98 = 8'h31; // .
            8'h4A: set2_pc98 = 8'h32; // /
            8'h61: set2_pc98 = 8'h33; // ISO backslash (JIS _ / ro)
            8'h29: set2_pc98 = 8'h34; // space
            8'h7B: set2_pc98 = 8'h40; // keypad -
            8'h7C: set2_pc98 = 8'h45; // keypad *
            8'h79: set2_pc98 = 8'h49; // keypad +
            8'h6C: set2_pc98 = 8'h42; // keypad 7
            8'h75: set2_pc98 = 8'h43; // keypad 8
            8'h7D: set2_pc98 = 8'h44; // keypad 9
            8'h6B: set2_pc98 = 8'h46; // keypad 4
            8'h73: set2_pc98 = 8'h47; // keypad 5
            8'h74: set2_pc98 = 8'h48; // keypad 6
            8'h69: set2_pc98 = 8'h4A; // keypad 1
            8'h72: set2_pc98 = 8'h4B; // keypad 2
            8'h7A: set2_pc98 = 8'h4C; // keypad 3
            8'h70: set2_pc98 = 8'h4E; // keypad 0
            8'h71: set2_pc98 = 8'h50; // keypad .
            8'h03: set2_pc98 = 8'h66; // F5
            8'h04: set2_pc98 = 8'h64; // F3
            8'h05: set2_pc98 = 8'h62; // F1
            8'h06: set2_pc98 = 8'h63; // F2
            8'h09: set2_pc98 = 8'h6B; // F10
            8'h0A: set2_pc98 = 8'h69; // F8
            8'h0B: set2_pc98 = 8'h67; // F6
            8'h0C: set2_pc98 = 8'h65; // F4
            8'h83: set2_pc98 = 8'h68; // F7
            8'h01: set2_pc98 = 8'h6A; // F9
            8'h12: set2_pc98 = 8'h70; // left shift
            8'h58: set2_pc98 = 8'h71; // caps lock (a plain key to a PC-98)
            8'h11: set2_pc98 = 8'h51; // left alt  -> NFER
            8'h14: set2_pc98 = 8'h74; // left ctrl -> CTRL
            8'h59: set2_pc98 = 8'h7D; // right shift

            // PC-98-only keys the VIRTUAL keyboard sends on Set-2 codes that a
            // real USB keyboard never emits (verified against hid_to_ps2's
            // output table). These codes belong to vkb_layout.c's PC-9801
            // table; a docked keyboard reaches the same PC-98 keys through the
            // entries above and the extended block instead.
            8'h08: set2_pc98 = 8'h60; // STOP   (Pause key on a docked kbd)
            8'h0F: set2_pc98 = 8'h72; // KANA
            8'h10: set2_pc98 = 8'h73; // GRPH   (right ctrl on a docked kbd)
            8'h13: set2_pc98 = 8'h35; // XFER   (right alt on a docked kbd)
            8'h17: set2_pc98 = 8'h51; // NFER   (left alt on a docked kbd)
            8'h27: set2_pc98 = 8'h3E; // HOME CLR (bare sentinel; 0x3E = np2 "HMCR")
            8'h18: set2_pc98 = 8'h3F; // HELP
            8'h19: set2_pc98 = 8'h36; // ROLL UP
            8'h1F: set2_pc98 = 8'h37; // ROLL DOWN
            8'h20: set2_pc98 = 8'h38; // INS
            8'h28: set2_pc98 = 8'h39; // DEL
            8'h2F: set2_pc98 = 8'h33; // _ / RO
            8'h30: set2_pc98 = 8'h41; // keypad /
            default: set2_pc98 = KC_NONE;
        endcase
    endfunction

    //
    // Extended (0xE0-prefixed) Set-2 -> PC-98: the nav block, the keypad
    // twins, right-Ctrl/Alt, and Print Screen. With the E0 prefix 0x7C is
    // Print Screen -> COPY, not the keypad *.
    //
    function automatic [7:0] set2e_pc98;
        input [7:0] s;
        case (s)
            8'h11: set2e_pc98 = 8'h35; // right alt  -> XFER
            8'h14: set2e_pc98 = 8'h73; // right ctrl -> GRPH
            8'h4A: set2e_pc98 = 8'h41; // keypad /
            8'h5A: set2e_pc98 = 8'h1C; // keypad enter -> RETURN
            8'h69: set2e_pc98 = 8'h3F; // end   -> HELP
            8'h6B: set2e_pc98 = 8'h3B; // left
            8'h6C: set2e_pc98 = 8'h3E; // home  -> HOME/CLR
            8'h70: set2e_pc98 = 8'h38; // insert -> INS
            8'h71: set2e_pc98 = 8'h39; // delete -> DEL
            8'h72: set2e_pc98 = 8'h3D; // down
            8'h74: set2e_pc98 = 8'h3C; // right
            8'h75: set2e_pc98 = 8'h3A; // up
            8'h7A: set2e_pc98 = 8'h37; // pgdn  -> ROLLDOWN
            8'h7C: set2e_pc98 = 8'h61; // print screen -> COPY
            8'h7D: set2e_pc98 = 8'h36; // pgup  -> ROLLUP
            default: set2e_pc98 = KC_NONE;
        endcase
    endfunction

    //
    // Byte-stream parser. pocket_keyboard's framer emits well-formed Set-2:
    // make [E0] code, break [E0] F0 code, plus the fixed Print Screen and
    // Pause sequences. E0 12 / E0 59 inside Print Screen are fake shifts, not
    // keys -- both are discarded so COPY does not leave a phantom shift held.
    // Pause arrives as the 8-byte E1 sequence and is make-only: it becomes a
    // STOP make and the remaining 7 bytes are swallowed.
    //
    localparam [2:0] S_IDLE = 3'd0, S_EXT = 3'd1, S_BRK = 3'd2,
                     S_EXT_BRK = 3'd3, S_SKIP = 3'd4;
    reg [2:0] state;
    reg [2:0] skip_cnt;

    always @(posedge clk) begin
        if (reset) begin
            state    <= S_IDLE;
            key_stb  <= 1'b0;
            key_make <= 1'b0;
            key_code <= 8'd0;
            skip_cnt <= 3'd0;
        end else if (kb_valid && kb_ready) begin
            case (state)
                S_IDLE: begin
                    case (kb_byte)
                        8'hE0: state <= S_EXT;
                        8'hF0: state <= S_BRK;
                        8'hE1: begin                       // Pause: a make-only STOP
                            key_stb  <= ~key_stb;
                            key_make <= 1'b1;
                            key_code <= 8'h60;
                            skip_cnt <= 3'd7;              // 14 77 E1 F0 14 F0 77
                            state    <= S_SKIP;
                        end
                        default: begin
                            if (set2_pc98(kb_byte) != KC_NONE) begin
                                key_stb  <= ~key_stb;
                                key_make <= 1'b1;
                                key_code <= set2_pc98(kb_byte);
                            end
                        end
                    endcase
                end

                S_EXT: begin
                    if (kb_byte == 8'hE0)
                        state <= S_EXT;                    // consecutive prefixes
                    else if (kb_byte == 8'hF0)
                        state <= S_EXT_BRK;                // extended break
                    else if (kb_byte == 8'h12 || kb_byte == 8'h59)
                        state <= S_IDLE;                   // Print Screen fake shift
                    else begin
                        state <= S_IDLE;
                        if (set2e_pc98(kb_byte) != KC_NONE) begin
                            key_stb  <= ~key_stb;
                            key_make <= 1'b1;
                            key_code <= set2e_pc98(kb_byte);
                        end
                    end
                end

                S_BRK: begin                               // release of a plain key
                    state <= S_IDLE;
                    if (set2_pc98(kb_byte) != KC_NONE) begin
                        key_stb  <= ~key_stb;
                        key_make <= 1'b0;
                        key_code <= set2_pc98(kb_byte) | 8'h80;
                    end
                end

                S_EXT_BRK: begin                           // release of an extended key
                    state <= S_IDLE;
                    if (kb_byte != 8'h12 && kb_byte != 8'h59   // fake shift break
                            && set2e_pc98(kb_byte) != KC_NONE) begin
                        key_stb  <= ~key_stb;
                        key_make <= 1'b0;
                        key_code <= set2e_pc98(kb_byte) | 8'h80;
                    end
                end

                S_SKIP: begin                              // swallow the Pause tail
                    if (skip_cnt == 3'd1)
                        state <= S_IDLE;
                    else
                        skip_cnt <= skip_cnt - 3'd1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
