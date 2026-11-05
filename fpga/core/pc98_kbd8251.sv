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
//     -- and reads up to five bytes from 0x41, checking each against 0x60,
//     0x70 and 0x74 (STOP, SHIFT, CTRL held at power-on; see below). A 0x60
//     sets bit 7 of [0x0500] and takes the F86AA path. No byte inside the
//     window -- the normal case, nothing held -- takes F864B.
//   * the BIOS never polls 0x43 at all. Its IRQ1 handler (FE65D) checks the
//     error bits, writes 0x16, and reads whatever is pending; its keyboard
//     reset (INT 18h AH=3, FE7C3) is the same 3A/32/16 break sequence the
//     ITF uses.
//
// The reset itself is the 8251's SEND-BREAK bit, not a data byte: the host
// writes a command with SBRK set (0x3A) and then one without (0x32), and the
// break's falling edge is what resets the keyboard (np21w io/serial.c,
// keyboard_o43: `if ((!(dat & 8)) && (cmd & 8)) keyboard_resetsignal()`).
// The keyboard answers that reset with NOTHING of its own. np21w's
// keyboard_resetsignal clears the 8251 state and calls keystat_resendstat
// (np21w keystat.c), which re-sends the make code of every key that is
// physically held at that moment -- and no other byte. That is what the ITF
// probe above reads: 0x60 is the STOP key's matrix code, 0x70 SHIFT, 0x74
// CTRL, so the probe asks "which of STOP/SHIFT/CTRL is the user holding at
// power-on" (STOP -> [0x0500] bit 7 and the F86AA path that skips the
// memory-test display; all three -> F9B22). With nothing held the window
// times out and the ITF runs its normal path (F864B) -- the boot this core
// walks.
//
// An earlier version of this model read the 0x60 as a "reset ACK" and
// synthesised one ~350 ms after every break edge (outside the ITF window, so
// the ITF still took F864B). The BIOS keyboard reset (INT 18h AH=3, FE7C3)
// the POST issues at FD8E7 then got that 0x60 through IRQ1 -- and the IRQ1
// handler (FE6C2-FE6DC) treats make code 0x60 as the STOP key and raises
// INT 06h. N88-BASIC's STOP handler at "How many files(0-15)?" re-prints the
// prompt: the first boot after launching the core showed it twice, as if a
// key had been pressed. So: no byte on a reset. The break edge only clears
// the receiver and the queue, as keyboard_resetsignal does.
//
// Held keys are not re-sent on the edge: this model sees key events, not the
// key matrix, and the translator in front of it re-sends nothing either. A
// key held across a keyboard reset therefore stays "down" in the BIOS's own
// map until its release arrives, which is the next event anyway.
//
// Status follows np21w's keyboard_i43: `return(status | 0x85)` -- TxRDY, TxE
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
// (0x9C/0x9D/0x9F -> 0xFA.., np21w keystat_ctrlsend) are not synthesised
// because neither ROM writes 0x41 during boot. Both can grow on this module
// without changing its ports.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_kbd8251 (
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
    // 16-deep queue, as np21w's keyboard_send buffers (io/serial.c, KB_BUF).
    // The old one-deep queue dropped the third of a burst -- a pad press and
    // release landing while a game sat with IRQ1 unserviced lost the break
    // and left the key held down.
    input  wire logic key_stb,
    input  wire logic [7:0] key_byte,

    output wire logic read_select,           // this module drives the bus
    output wire logic [7:0] read_data,
    output wire logic irq                    // RxRDY, level, to PIC IR1
);

    // np21w's keybrd.cmd: the last command byte written to 0x43.
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
    logic [7:0] kq [16];
    logic [3:0] kq_rd, kq_wr;
    logic [4:0] kq_n;
    wire        key_pending = kq_n != 5'd0;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cmd_q           <= 8'h00;
            wr_data_q       <= 8'h00;
            ctrl_wr_level_q <= 1'b0;
            data_rd_level_q <= 1'b0;
            rx_q            <= 8'hFF;            // np21w's reset value
            rx_full         <= 1'b0;
            key_stb_q       <= 1'b0;
            kq_rd           <= 4'd0;
            kq_wr           <= 4'd0;
            kq_n            <= 5'd0;
        end else begin
            ctrl_wr_level_q <= ctrl_write_strobe;
            data_rd_level_q <= data_read_strobe;
            if (ctrl_write_strobe)
                wr_data_q <= data_in;

            // End of a 0x43 write: np21w's keyboard_o43. A break's falling
            // edge (SBRK was set, now clear) resets the keyboard: anything
            // still in the receiver is dropped (keyboard_resetsignal clears
            // status and buffers), and nothing is sent back -- see the header.
            if (ctrl_wr_level_q && ~ctrl_write_strobe) begin
                if (!wr_data_q[3] && cmd_q[3]) begin
                    rx_full   <= 1'b0;
                    // np21w's keyboard_resetsignal clears the pending buffers
                    // too: a key that was still queued when the keyboard was
                    // reset belongs to the cycle that just died.
                    kq_rd <= kq_wr;
                    kq_n  <= 5'd0;
                end
                cmd_q <= wr_data_q;
            end

            // Reading 0x41 takes the byte and drops RxRDY/IRQ1 (np21w's
            // keyboard_i41) -- after the cycle has ended, so the CPU has
            // latched what it was handed.
            if (data_rd_level_q && ~data_read_strobe)
                rx_full <= 1'b0;

            // Key injection. Written last so an event landing on the same
            // tick as a read completing takes the register.
            // Bytes leave in order: a new event goes straight to the
            // receiver only when nothing is queued ahead of it.
            key_stb_q <= key_stb;
            if (key_stb != key_stb_q) begin
                if (!rx_full && !key_pending) begin
                    rx_q    <= key_byte;
                    rx_full <= 1'b1;
                end else if (kq_n != 5'd16) begin
                    kq[kq_wr] <= key_byte;
                    kq_wr     <= kq_wr + 4'd1;
                    kq_n      <= kq_n + 5'd1;
                end
            end else if (key_pending && !rx_full) begin
                rx_q    <= kq[kq_rd];
                rx_full <= 1'b1;
                kq_rd   <= kq_rd + 4'd1;
                kq_n    <= kq_n - 5'd1;
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
