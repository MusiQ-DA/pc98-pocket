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
// machine. The code set and the position choices are np21w's (sdl/kbtrans.c,
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
    // Non-extended Set-2 -> PC-98 (ROM page 0), ANSI keyboard order. The
    // Set-2 column matches hid_to_ps2's output byte for byte; the choices
    // are np21w's (sdl/kbtrans.c, the 101/106 tables): the JIS bracket row
    // sits one key left of the ANSI one, US `~ doubles as the JIS yen key,
    // and Set-2 0x61 is the JIS _/ro key. Modifiers map as KEYS: shifts
    // 0x70/0x7D, CTRL 0x74, GRPH 0x73, NFER 0x51, XFER 0x35 -- the BIOS
    // builds its shift state from those bytes exactly as from the real
    // keyboard. PC-98-only keys ride Set-2 codes a USB keyboard never emits
    // (STOP 0x08, KANA 0x0F, GRPH 0x10, XFER 0x13, NFER 0x17, HMCR 0x27,
    // HELP 0x18, ROLL UP 0x19, ROLL DOWN 0x1F, INS 0x20, DEL 0x28, _/RO
    // 0x2F, keypad / 0x30) -- vkb_layout.c's table produces them.
    //
    // Page 1 is the extended (0xE0-prefixed) map: the nav block, the keypad
    // twins, right-Ctrl/Alt, and Print Screen -> COPY.
    //
    // Both tables live in one 512x8 block ROM, and BOTH pages are read when
    // a byte is captured -- which page applies is the parser's business a
    // cycle later (the E0 prefix only changes state at decode), so the
    // dual-port read keeps the ROM synchronous without the FSM knowing the
    // byte's class ahead of time. The case tables this replaced (~110
    // entries) cost the fit more ALMs than the M10K, which is the resource
    // with headroom.
    (* ramstyle = "M10K" *) reg [7:0] map [0:511];

`ifdef SYNTHESIS
    // Quartus resolves $readmemh against the project directory (fpga/).
    initial $readmemh("core/pc98_kbd_ps2.hex", map);
`else
    // The benches run Verilator from the repository root.
    initial $readmemh("fpga/core/pc98_kbd_ps2.hex", map);
`endif

    // The byte queue: every handshake captures into q_byte and raises q_v
    // for one beat, so no stream byte can land while its map is in flight
    // -- a byte is always either captured or decoded, never dropped.
    reg [7:0] q_byte, roma_q, romb_q;
    reg       q_v;

    always @(posedge clk) begin
        if (reset) begin
            q_v <= 1'b0;
        end else if (kb_valid && kb_ready) begin
            q_byte <= kb_byte;
            roma_q <= map[{1'b0, kb_byte}];
            romb_q <= map[{1'b1, kb_byte}];
            q_v    <= 1'b1;
        end else if (q_v) begin
            q_v <= 1'b0;                    // consumed this beat
        end
    end

    //
    // Byte-stream parser, one beat behind the wire. pocket_keyboard's framer
    // emits well-formed Set-2: make [E0] code, break [E0] F0 code, plus the
    // fixed Print Screen and Pause sequences. E0 12 / E0 59 inside Print
    // Screen are fake shifts, not keys -- both are discarded so COPY does
    // not leave a phantom shift held. Pause arrives as the 8-byte E1
    // sequence and is make-only: it becomes a STOP make and the remaining
    // 7 bytes are swallowed.
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
        end else if (q_v) begin
            case (state)
                S_IDLE: begin
                    case (q_byte)
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
                            if (roma_q != KC_NONE) begin
                                key_stb  <= ~key_stb;
                                key_make <= 1'b1;
                                key_code <= roma_q;
                            end
                        end
                    endcase
                end

                S_EXT: begin
                    if (q_byte == 8'hE0)
                        state <= S_EXT;                    // consecutive prefixes
                    else if (q_byte == 8'hF0)
                        state <= S_EXT_BRK;                // extended break
                    else if (q_byte == 8'h12 || q_byte == 8'h59)
                        state <= S_IDLE;                   // Print Screen fake shift
                    else begin
                        state <= S_IDLE;
                        if (romb_q != KC_NONE) begin
                            key_stb  <= ~key_stb;
                            key_make <= 1'b1;
                            key_code <= romb_q;
                        end
                    end
                end

                S_BRK: begin                               // release of a plain key
                    state <= S_IDLE;
                    if (roma_q != KC_NONE) begin
                        key_stb  <= ~key_stb;
                        key_make <= 1'b0;
                        key_code <= roma_q | 8'h80;
                    end
                end

                S_EXT_BRK: begin                           // release of an extended key
                    state <= S_IDLE;
                    if (q_byte != 8'h12 && q_byte != 8'h59   // fake shift break
                            && romb_q != KC_NONE) begin
                        key_stb  <= ~key_stb;
                        key_make <= 1'b0;
                        key_code <= romb_q | 8'h80;
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
