// pc98_kbd8251 -- the keyboard's 8251, and the keyboard behind it.
//
// PC-98 ports 0x41 (data) / 0x43 (control) are the USART that talks to the
// keyboard's own MCU. Both ROMs drive it, and they drive it differently, so
// the model has to be the chip rather than a stub shaped like one caller's
// expectations:
//
//   * the ITF (F85FA-F8649) writes 3A/32/16 to 0x43, polls 0x43 bit 1
//     (RxRDY) for 0x3000 LOOP iterations -- measured 82 ms on the boot
//     bench (6.7 us per iteration: IN+TEST+JNZ+LOOP at this core's clocks)
//     -- and reads up to five bytes from 0x41, checking each against 0x60.
//     A 0x60 means the keyboard answered its reset: the ITF then sets bit 7
//     of [0x0500] and takes the keyboard-present path (F86AA). No byte
//     inside the window means no keyboard: the ITF takes its own
//     no-keyboard path (F864B), which is also a real machine.
//   * the BIOS never polls 0x43 at all. Its IRQ1 handler (FE65D) checks the
//     error bits, writes 0x16, and reads whatever is pending; its keyboard
//     reset (INT 18h AH=3, FE7C3) is the same 3A/32/16 break sequence the
//     ITF uses.
//
// The reset itself is the 8251's SEND-BREAK bit, not a data byte: the host
// writes a command with SBRK set (0x3A) and then one without (0x32), and the
// break's falling edge is what resets the keyboard (np2 io/serial.c,
// keyboard_o43: `if ((!(dat & 8)) && (cmd & 8)) keyboard_resetsignal()`).
// That edge is the ONLY thing that may arm an ACK here. The first hardware
// version of this model armed on every write to 0x43 AND on writes to 0x73
// -- which is the BEEP data port (np2 io/pit.c pit_o73), which the ITF's
// no-keyboard path programs twice (F8671/F8679). Those phantom ACKs left a
// 0x60 pending forever, the ITF's 1.4 s re-cycle then "found" it, took the
// keyboard-present path mid-cycle, and the machine sat black with the guest
// cycling in F84xx-F86xx: exactly what the Pocket showed.
//
// After the break the keyboard MCU re-runs itself and answers 0x60. Neither
// np2 (whose keyboard only re-sends held keys there, io/keystat.c
// keystat_resendstat) nor the ROMs leave much doubt about the speed: a real
// keyboard answers in ~10 ms, far inside the ITF's 82 ms poll window (the
// V30 bench agrees: tb_pc98_v30 with +kbdpass1 catches even an 80 ms ACK).
// The window exists precisely to catch the answer: the ITF sets the
// [0x0500] flag the BIOS branches on (FD897) only if it reads the 0x60
// itself.
//
// The shipped delay is nevertheless OUTSIDE that window, on purpose. The
// keyboard-present ITF path (F86AA) skips the memory-test display entirely
// and, measured on the V30 bench (+kbdpass1), lands the machine in BASIC's
// strap with an empty work area: parked in RAM at 0000:03F4 with one TVRAM
// write to its name -- the black screen the Pocket showed with the first
// version of this model. The boot this core completes today is the OTHER
// one: the ITF times out, runs its memory test and display, and the BIOS
// enters its no-keyboard two-pass flow (whose pass-2 "keyboard arrived"
// step still needs machine work outside this module -- the dirty pass-1
// BASIC cannot reach its own reset yet, which tb_pc98_v30 works around by
// forcing it). So the model answers late enough that the ITF takes the
// path this machine can walk, while the 8251 itself stays fully alive for
// the BIOS's INT 18h AH=3 reset (whose 0x60 then arrives through IRQ1) and
// for the key stream, once something injects it. When the direct
// keyboard-present boot works end to end, set ACK_DELAY_TICKS back to
// ~429 545 (10 ms): that value is proven to carry the ITF through F86AA
// and the F945D reset dance on the V30 core.
//
// Status follows np2's keyboard_i43: `return(status | 0x85)` -- TxRDY, TxE
// and DSR permanently set (the transmitter is always idle here and the
// keyboard is always connected), RxRDY while a byte waits. Reading 0x41
// returns the byte and drops RxRDY and IRQ1 (keyboard_i41). The data
// register holds the last byte after the read, the way the real one does;
// its reset value is 0xFF.
//
// What is deliberately NOT here: this core never generates framing, parity
// or overrun (there is no serial line, and nothing injects a second byte
// while one waits), so the error bits read zero and the ER command bit is a
// no-op; and the keyboard's replies to host commands sent through 0x41
// (0x9C/0x9D/0x9F -> 0xFA.., np2 keystat_ctrlsend) are not synthesised
// because neither ROM writes 0x41 during boot. Both can grow on this module
// without changing its ports.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_kbd8251 #(
    // ~350 ms at the 42.954545 MHz chipset clock. Outside the ITF's poll
    // window by 4x (see the block comment above for why that is the shipped
    // side of the line, and for the in-window value to return to).
    parameter int unsigned ACK_DELAY_TICKS = 15_034_091
) (
    input  wire logic clock,
    input  wire logic reset,

    // Bus view. The selects are level strobes over the whole access (decode
    // AND the active-low read/write), the same shapes the previous inline
    // stub used.
    input  wire logic ctrl_write_strobe,     // 0x43 selected, io_write_n low
    input  wire logic data_read_strobe,      // 0x41 selected, io_read_n low
    input  wire logic stat_read_strobe,      // 0x43 selected, io_read_n low
    input  wire logic [7:0] data_in,         // internal_data_bus

    // Key injection, from the Set-2 -> PC-98 translator (pc98_kbd_ps2), i.e.
    // from the dock's USB keyboard and the virtual keyboard. stb TOGGLES per
    // event; code is the PC-98 matrix byte, bit 7 already set on a release,
    // so it goes on the receive wire as-is. An event that arrives while the
    // holding register still holds a byte the guest has not read waits in a
    // one-deep side queue; pocket_keyboard's typematic rate spaces real key
    // events far wider than a BIOS poll cycle, so one slot of slack is the
    // measured need (make, break, and a repeat share the slot in turn).
    input  wire logic key_stb,
    input  wire logic [7:0] key_byte,

    output wire logic read_select,           // this module drives the bus
    output wire logic [7:0] read_data,
    output wire logic irq                    // RxRDY, level, to PIC IR1
);

    // np2's keybrd.cmd: the last command byte written to 0x43.
    logic [7:0] cmd_q;
    // The receive side: one byte deep, like the real 8251's holding register.
    logic [7:0] rx_q;
    logic       rx_full;
    // Samples for the end-of-cycle commits (the file's sysport idiom: the
    // byte is stable for the whole write, the address is latched, so sample
    // during and commit at the strobe's end).
    logic [7:0] wr_data_q;
    logic       ctrl_wr_level_q;
    logic       data_rd_level_q;
    // The injection side's delayed strobe copy and its one-deep queue.
    logic       key_stb_q;
    logic [7:0] key_hold;
    logic       key_pending;

    logic [23:0] ack_timer;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cmd_q           <= 8'h00;
            wr_data_q       <= 8'h00;
            ctrl_wr_level_q <= 1'b0;
            data_rd_level_q <= 1'b0;
            rx_q            <= 8'hFF;            // np2's reset value
            rx_full         <= 1'b0;
            ack_timer       <= 24'd0;
            key_stb_q       <= 1'b0;
            key_hold        <= 8'h00;
            key_pending     <= 1'b0;
        end else begin
            ctrl_wr_level_q <= ctrl_write_strobe;
            data_rd_level_q <= data_read_strobe;
            if (ctrl_write_strobe)
                wr_data_q <= data_in;

            // The expiry load first, the countdown and the write-end after:
            // if a 0x43 write happens to end on the ACK's very last tick,
            // the edge's re-arm and receiver clear are the assignments that
            // must win, and in a single always block the later statement
            // does.
            if (ack_timer == 24'd1 && !rx_full) begin
                rx_q    <= 8'h60;                // the reset ACK
                rx_full <= 1'b1;
            end
            if (ack_timer != 24'd0)
                ack_timer <= ack_timer - 24'd1;

            // End of a 0x43 write: np2's keyboard_o43. A break's falling
            // edge (SBRK was set, now clear) resets the keyboard: the
            // pending answer timer restarts and anything still in the
            // receiver is dropped (keyboard_resetsignal clears status and
            // buffers).
            if (ctrl_wr_level_q && ~ctrl_write_strobe) begin
                if (!wr_data_q[3] && cmd_q[3]) begin
                    ack_timer <= ACK_DELAY_TICKS[23:0];
                    rx_full   <= 1'b0;
                    // np2's keyboard_resetsignal clears the pending buffers
                    // too: a key that was still queued when the keyboard was
                    // reset belongs to the cycle that just died.
                    key_pending <= 1'b0;
                end
                cmd_q <= wr_data_q;
            end

            // Reading 0x41 takes the byte and drops RxRDY/IRQ1 (np2's
            // keyboard_i41) -- after the cycle has ended, so the CPU has
            // latched what it was handed.
            if (data_rd_level_q && ~data_read_strobe)
                rx_full <= 1'b0;

            // Key injection. Written last so an event landing on the same
            // tick as the ACK expiry or a read completing takes the register:
            // a real key press outranks both bookkeeping paths.
            key_stb_q <= key_stb;
            if (key_stb != key_stb_q) begin
                if (!rx_full) begin
                    rx_q    <= key_byte;
                    rx_full <= 1'b1;
                end else if (!key_pending) begin
                    key_hold    <= key_byte;
                    key_pending <= 1'b1;
                end
            end else if (key_pending && !rx_full) begin
                rx_q        <= key_hold;
                rx_full     <= 1'b1;
                key_pending <= 1'b0;
            end
        end
    end

    assign read_select = data_read_strobe | stat_read_strobe;
    assign read_data   = data_read_strobe ? rx_q
                                                // 0x85: TxRDY | TxE | DSR
                                              : (8'h85 | (rx_full ? 8'h02 : 8'h00));
    assign irq         = rx_full;

endmodule

`default_nettype wire
