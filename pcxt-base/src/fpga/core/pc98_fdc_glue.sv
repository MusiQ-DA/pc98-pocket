//
// pc98_fdc_glue -- the PC-98 FDC ports, onto floppy.v's PC/XT register file.
//
// floppy.v is a uPD765 with a PC/XT skin: the chip's own MSR and FIFO sit at
// its registers 4 and 5, and everything else it needs -- drive select, motor,
// DMA/IRQ enable, reset -- arrives through the AT's Digital Output Register at
// register 2, plus a data rate at 4 or 7.
//
// A PC-98 has the same uPD765 and none of that skin. It has TWO windows onto
// one register file, an interface-select port that says which of them is live,
// and its interrupt on the SLAVE 8259:
//
//     0x90 / 0xC8   R    main status (MSR)
//     0x92 / 0xCA   R/W  data (the command/result FIFO)
//     0x94 / 0xCC   R/W  control
//     0xBE          R/W  interface select ("chgreg")
//
// ---------------------------------------------------------------------------
// THE INTERRUPT CONTRACT -- what this module exists for the second time.
//
// The first cut of this glue mapped the registers and said nothing about the
// interrupt, and that cost a hardware cycle: the on-screen POST panel stopped
// at MEMORY 640KB OK reading LVL 41 -- master IRQ0 plus master IRQ6 asserted
// and never cleared -- with the guest still inside the FDC code (IO 00BE 00CC).
// Master IRQ6 is the PC/XT's floppy line. A PC-98 does not have one there.
//
//   WHO ASSERTS IT. floppy.v's irq, on command completion -- see its
//   raise_interrupt, gated by dma_irq_enable, which is DOR bit 3 and therefore
//   the control port's bit 3 below.
//
//   WHERE IT GOES. The SLAVE PIC: IRQ11 (INT 13h) when the 2HD window is the
//   live one, IRQ10 (INT 12h) when the 2DD window is. Three independent
//   witnesses:
//     * np2kai io/fdc.c:46-51 -- fdc_intwait does pic_setirq(0x0b) when
//       fdc.chgreg & 1, else pic_setirq(0x0a).
//     * The BIOS gates each entry point on the SLAVE's mask register: FF4B3
//       `in al,0x0A / test al,0x08` before the 2HD path at FF4D9, and FF438
//       `in al,0x0A / test al,0x04` before the 2DD path at FF44C. Masked ->
//       AH=40h, "no such equipment".
//     * ITF F85C3-F85D8 programs the slave with ICW2 = 0x10, so slave IRQ2/3
//       are INT 12h/13h -- the vectors the two handlers at FFAF6 (2HD, reads
//       0x90) and FFB69 (2DD, reads 0xC8) sit on.
//
//   WHAT CLEARS IT. A read of the result phase from the DATA port, and nothing
//   else. The BIOS's handler at FFB08/FFB7A reads the MSR, and either CB is set
//   and it drains the result bytes, or it issues SENSE INTERRUPT STATUS (08h)
//   and reads ST0/PCN -- both are reads of 0x92/0xCA. That is floppy.v's
//   register 5, and floppy.v lowers irq on exactly `io_read && io_address == 5`.
//   np2kai agrees: io/fdc.c:920-928, fdc_dataread calls fdc_interruptreset()
//   once the result phase has drained. There is no acknowledge port, and the
//   control port does not clear it -- only a reset does (below).
//
// So the mapping was never the missing half; the ROUTING was. This module now
// owns both, and hands the chipset irq_2hd / irq_2dd instead of one line into
// the master.
//
// ---------------------------------------------------------------------------
// 0xBE, THE INTERFACE SELECT. np2kai io/fdc.c:1089-1115 (fdc_obe / fdc_ibe)
// and the guard at the head of fdc_o92/fdc_o94/fdc_i90/fdc_i92/fdc_i94:
//
//     if (((port >> 4) ^ fdc.chgreg) & 1) return;     // or return 0xff
//
// (port >> 4) & 1 is 1 for 0x9x and 0 for 0xCx, so chgreg bit 0 picks which
// window reaches the chip; the other one ignores writes and reads 0xFF. Bit 1
// is the media type, bit 2 arms np2's ready-attention interrupt. Reset value is
// 3 (fdc_reset, io/fdc.c:1155-1161), which is why the stub's 0xBE constant was
// 0xFB. The read is `(chgreg & 3) | 8 | 0xf0`.
//
// A constant is not good enough once the floppy is real. The BIOS steers ITSELF
// with this byte -- ITF FAFD0 / FAFEE / FB01B all do `in al,0xBE / test al,1`
// to choose between 0x90 and 0xC8, and FF3C3 does a read-modify-write
// (`in al,0xBE / xor al,2 / and al,3 / out 0xBE,al`) to flip the media type
// while probing. Answering 0xFB forever tells it the flip never took.
//
// 0x94 / 0xCC READ. Also NOT a readback of what was written: np2kai's fdc_i94
// (io/fdc.c:1064-1087) synthesises a constant --
//
//     0x40 always
//   | 0x20 | 0x10  for the 0xCx port only  (DMA, and "ready")
//   | 0x04         if dipsw[0] & 8 ("internal drives first"), else 0x08
//
// -- so 0x94 reads 0x44 and 0xCC reads 0x74 on this machine's dip setting,
// which is the one the stub's 0x94 constant already chose. Both bits matter:
// the BIOS's 2DD ready test at FFE6E is `in al,0xCC / test al,0x10`, and FF6DA
// uses bits 2 and 3 to pick which half of the drive-equipment mask survives --
// EXACTLY ONE of them may be set, and the old `latch | 0x30` readback set both.
//
// ---------------------------------------------------------------------------
// WHAT floppy.v WANTS in register 2 (its io_readdata_prepare and the writes
// underneath):
//
//     bit 0  selected_drive      bit 2  enable -- clearing it RESETS
//     bit 3  dma_irq_enable      bit 4  motor_enable[0]
//     bit 5  motor_enable[1]
//
// The PC-98 control port (np2kai fdc_o94, io/fdc.c:990-1040) acts on three
// bits and ignores the rest:
//
//     0x80   0 -> 1 resets the FDC (fdcstatusreset)
//     0x10   any change resets status and re-checks the DMA controller
//     0x08   interrupt enable
//
// So the mapping is not bit-for-bit, it is by meaning:
//
//   enable       held at 1. A PC-98 has no enable bit because the controller
//                is always enabled; leaving it 0 would keep floppy.v in reset
//                forever.
//   motors       held at 1. Motor control on a PC-98 is not in this register
//                and floppy.v refuses to seek without them.
//   drive select left to floppy.v, which already takes it from the unit field
//                of each uPD765 command (cmd_recalibrate_start and friends
//                latch io_writedata[0]) -- which is how a real PC-98 does it.
//   dma_irq_en   from control bit 3, the one np2 treats as interrupt enable.
//   reset        control bit 7 going 0 -> 1 pulses it, as np2 does. floppy.v
//                accepts a reset at register 4 with bit 7 set, so the pulse
//                goes there rather than by dropping enable -- dropping enable
//                would need a second write to restore it and the guest never
//                makes one.
//   bit 0x10     NOT mapped, deliberately. np2's fdcstatusreset() only puts the
//                command engine back to RQM-idle; floppy.v's nearest equivalent
//                is sw_reset, which also CLEARS IRQ and reloads reset_sensei.
//                The BIOS drops bit 4 (0x18 -> 0x08 at FF44C/FF4DB) right
//                before it waits for the drive, so spending a sw_reset there
//                would throw away the interrupt that wait is for. Nothing in
//                either ROM is known to need it; if something turns out to,
//                it wants its own narrower reset in floppy.v, not this one.
//
// One known divergence, recorded rather than invented: np2's fdc_o94 schedules
// an interrupt when bit 7 rises with bit 3 already set (io/fdc.c:1005-1015, the
// OSASK workaround), and floppy.v instead raises irq only on a 0->1 edge of DOR
// bit 2, which this glue never produces. The ITF's own reset sequence (F9BB5
// `out 0x94,0x80` / F9BC2 `out 0xCC,0xA8`, each followed by a LOOP delay, not
// an interrupt wait) does not depend on it, so it is left alone. floppy.v's
// reset_sensei does hand back 0xC0|unit -- np2's FDCRLT_AI -- to the first four
// SENSE INTERRUPT commands after a reset, which is the same information.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_fdc_glue (
    input  wire        clk,
    input  wire        rst,

    // Guest side. sel_stat/sel_data/sel_ctrl are the decodes for 0x90/0xC8,
    // 0x92/0xCA and 0x94/0xCC -- BOTH windows, undivided; port_2dd is which of
    // the two this cycle names, and the chgreg guard below decides whether it
    // is the live one. sel_mode is 0xBE. wr_stb is one cycle at the END of a
    // write, the house idiom, with wr_data sampled while the strobe was low.
    input  wire        sel_stat,
    input  wire        sel_data,
    input  wire        sel_ctrl,
    input  wire        sel_mode,
    input  wire        port_2dd,     // 0 = 0x90/0x92/0x94, 1 = 0xC8/0xCA/0xCC
    input  wire        wr_stb,
    input  wire  [7:0] wr_data,
    // rd_stb is the matching one-cycle strobe at the START of a read of the
    // status or data port. It has to come through here rather than straight to
    // floppy.v because a read of the data port is THE interrupt acknowledge --
    // see the contract above -- so the chgreg guard has to cover it too, or a
    // probe of the dead window silently eats the live window's interrupt.
    input  wire        rd_stb,

    // floppy.v side: which of its registers this cycle addresses, whether a
    // read or a write is happening and what a write carries, and its interrupt
    // coming back.
    output logic [2:0] fd_addr,
    output logic       fd_write,
    output logic       fd_read,
    output logic [7:0] fd_wdata,
    input  wire        fd_irq,

    // Chipset side.
    output logic [7:0] ctrl_readback,  // 0x94 / 0xCC read
    output logic [7:0] mode_readback,  // 0xBE read
    output logic       group_live,     // this cycle's window is the selected one
    output logic       irq_2hd,        // slave IRQ11 -> INT 13h
    output logic       irq_2dd,        // slave IRQ10 -> INT 12h
    // How far the motor timer got, saturating: arms (a live-window control
    // write with bit 0 rising) and expiry pulses delivered to the steering.
    // The BIOS's motor wait needs BOTH to move; a stuck pair says the write
    // never armed the timer, a moved pair with the slave's IRR empty says
    // the pulse died between here and the PIC.
    output logic [7:0] dbg_motor_arms,
    output logic [7:0] dbg_motor_pulses,
    // Write-strobe witnesses, saturating: did wr_stb EVER fire for each
    // port? The panel's motor fields said "no arm" across two builds while
    // every decode traced clean on paper, so the question is no longer what
    // the glue DOES with a strobe but whether one arrives at all.
    //   dbg_strb_be  0xBE writes seen
    //   dbg_strb_94  0x94 writes seen
    //   dbg_strb_cc  0xCC writes seen
    //   dbg_strb_dat 0x92/0xCA writes seen
    //   dbg_last_ctrl the last control byte at a 0x94/0xCC strobe
    output logic [7:0] dbg_strb_be,
    output logic [7:0] dbg_strb_94,
    output logic [7:0] dbg_strb_cc,
    output logic [7:0] dbg_strb_dat,
    output logic [7:0] dbg_last_ctrl,
    // The window register itself. 0xBE's last byte: bit0 picks which of the
    // two port groups is live, and the same bit steers the interrupts. The
    // 0xCC motor writes are only seen when bit0 is CLEAR -- np2's
    // ((port>>4)^chgreg)&1 guard drops them otherwise -- so a 3 here with
    // MA 00 means the BIOS is writing 0xCC into a dead window, and the
    // question moves to why the ROM does that.
    output logic [7:0] dbg_chg
);

    logic [7:0] ctrl_q;
    logic [7:0] chgreg;
    logic       reset_pending;

    // ---- the motor interrupts the drive probes actually wait for -------
    //
    // THE TRIGGER IS BIT 3 (0x08), NOT BIT 0. np2kai's fdc_o94 (io/fdc.c
    // 1104-1116): when the register's 0x08 bit RISES (with the 2HD window
    // selected via 0xBE's bit 2), every READY drive gets an "attention"
    // interrupt after FDC_INT_DELAY (6 x 100 ms in np2's event tick) on
    // the FDC's line -- unconditionally, no XTMASK gate. The BIOS's own
    // boot sequence agrees (out 0x94 sites in bios.rom): FF56C writes 0x08,
    // FF638 writes 0x18 -- bit 3 set, BIT 0 NEVER -- and the metal showed
    // exactly that (n94 saturated, the last control byte 0x18, MA 00: the
    // bit-0 arm this used to watch could not fire). The 2DD side's
    // FF6BF pair (0x09 then 0x0C to 0xCC) carries bit 3 as well, and the
    // handlers' tails (0x0D/0x0C) keep the chain fed. Each side arms on its
    // own port's bit-3 rising edge and pulses its slave line ~600 ms later:
    // 0x94 -> slave bit 3, INT 13h; the 2DD-window 0xCC -> slave bit 2,
    // INT 12h (MAME's fdc_2hd_2dd_ctrl / fdc_trigger pair). A pulse while
    // the line is masked merely parks in the slave's IRR and delivers at
    // the unmask, which is what the handler's write-then-unmask order needs.
    logic        motor_armed_2hd,  motor_armed_2dd;
    logic [24:0] motor_timer_2hd,  motor_timer_2dd;
    logic        motor_pulse_2hd,  motor_pulse_2dd;
    logic [7:0]  motor_arms        = 8'd0;   // both timers, summed
    logic [7:0]  motor_pulses      = 8'd0;
    logic        ctrl3_q_2hd,      ctrl3_q_2dd;
    logic [7:0]  ctrlcc_q_2hd,     ctrlcc_q_2dd;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            motor_armed_2hd <= 1'b0;  motor_armed_2dd <= 1'b0;
            motor_timer_2hd <= 25'd0; motor_timer_2dd <= 25'd0;
            motor_pulse_2hd <= 1'b0;  motor_pulse_2dd <= 1'b0;
            ctrl3_q_2hd     <= 1'b0;  ctrl3_q_2dd     <= 1'b0;
            ctrlcc_q_2hd    <= 8'h00; ctrlcc_q_2dd    <= 8'h00;
            motor_arms      <= 8'd0;  motor_pulses    <= 8'd0;
        end
        else begin
            // 0x94 -- the 2HD drive adapter's control.
            if (wr_stb && sel_ctrl && ~port_2dd) begin
                if (wr_data[3] && !ctrl3_q_2hd) begin
                    motor_armed_2hd <= 1'b1;
                    motor_timer_2hd <= 25'd0;
                    if (motor_arms != 8'hFF) motor_arms <= motor_arms + 8'd1;
                end
                ctrl3_q_2hd  <= wr_data[3];
                ctrlcc_q_2hd <= wr_data;
            end
            // 0xCC -- the 2DD drive adapter's control, window ignored.
            if (wr_stb && sel_ctrl && port_2dd) begin
                if (wr_data[3] && !ctrl3_q_2dd) begin
                    motor_armed_2dd <= 1'b1;
                    motor_timer_2dd <= 25'd0;
                    if (motor_arms != 8'hFF) motor_arms <= motor_arms + 8'd1;
                end
                ctrl3_q_2dd  <= wr_data[3];
                ctrlcc_q_2dd <= wr_data;
            end
            if (motor_armed_2hd) begin
                if (motor_timer_2hd == 25'd25_772_000) begin  // ~600 ms
                    motor_armed_2hd <= 1'b0;
                    motor_pulse_2hd <= 1'b1;
                    if (motor_pulses != 8'hFF) motor_pulses <= motor_pulses + 8'd1;
                end
                else
                    motor_timer_2hd <= motor_timer_2hd + 25'd1;
            end
            else if (motor_pulse_2hd)
                motor_pulse_2hd <= 1'b0;
            if (motor_armed_2dd) begin
                if (motor_timer_2dd == 25'd25_772_000) begin  // ~600 ms
                    motor_armed_2dd <= 1'b0;
                    motor_pulse_2dd <= 1'b1;
                    if (motor_pulses != 8'hFF) motor_pulses <= motor_pulses + 8'd1;
                end
                else
                    motor_timer_2dd <= motor_timer_2dd + 25'd1;
            end
            else if (motor_pulse_2dd)
                motor_pulse_2dd <= 1'b0;
        end
    end
    assign dbg_motor_arms   = motor_arms;
    assign dbg_motor_pulses = motor_pulses;
    assign dbg_chg          = chgreg;

    // The strobe witnesses.
    logic [7:0] strb_be = 8'd0, strb_94 = 8'd0, strb_cc = 8'd0, strb_dat = 8'd0;
    logic [7:0] last_ctrl_byte = 8'd0;
    always_ff @(posedge clk) begin
        if (wr_stb) begin
            if (sel_mode && strb_be  != 8'hFF) strb_be  <= strb_be  + 8'd1;
            if (sel_ctrl && ~port_2dd && strb_94 != 8'hFF) strb_94 <= strb_94 + 8'd1;
            if (sel_ctrl &&  port_2dd && strb_cc != 8'hFF) strb_cc <= strb_cc + 8'd1;
            if (sel_data && strb_dat != 8'hFF) strb_dat <= strb_dat + 8'd1;
            if (sel_ctrl) last_ctrl_byte <= wr_data;
        end
    end
    assign dbg_strb_be   = strb_be;
    assign dbg_strb_94   = strb_94;
    assign dbg_strb_cc   = strb_cc;
    assign dbg_strb_dat  = strb_dat;
    assign dbg_last_ctrl = last_ctrl_byte;

    // np2 fdc_reset (io/fdc.c:1155-1161): fdc.chgreg = 3. Bit 0 set means the
    // 0x90/0x92/0x94 window is the live one out of reset.
    always_ff @(posedge clk, posedge rst) begin
        if (rst) chgreg <= 8'h03;
        else if (wr_stb && sel_mode) chgreg <= wr_data;
    end

    // np2's guard, ((port >> 4) ^ chgreg) & 1, with (port >> 4) & 1 written as
    // ~port_2dd: live when chgreg[0] and port_2dd disagree.
    assign group_live = chgreg[0] ^ port_2dd;

    // fdc_ibe, io/fdc.c:1109-1115: (chgreg & 3) | 8 | 0xf0.
    assign mode_readback = 8'hF8 | {6'd0, chgreg[1:0]};

    // fdc_i94, io/fdc.c:1152-1180. The dead window reads 0xFF, as every one
    // of np2's handlers does when the guard rejects the port. The live value
    // is 0x40 | 0x20 | 0x10 (0xCx port only) | (0x04 if dipsw[0]&8 else
    // 0x08), and the dipsw[0] THERE IS NOT WHAT PORT 0x31 READS -- that is
    // dipsw[1], DIP 1-4; fdc_i94 reads dipsw[0], DIP 5-8, which np2 defaults
    // to 0x3E. Bit 3 set, so the 0x04 arm: 0x44, the value the stub chose all
    // along. (The swap to 0x48 cost a hardware round: the probe's FD80:F41F
    // helper may shift the byte left, and 0x48 shifted is 0x90, whose bit 3
    // is clear -- [0x480] bit 3 never rose and the boot parked on SENSE
    // INTERRUPT forever.)
    assign ctrl_readback = ~group_live ? 8'hFF
                         :  port_2dd   ? 8'h74   // 0x40 | 0x20 | 0x10 | 0x04
                                       : 8'h44;  // 0x40 |               0x04

    // np2's pic_setirq(0x0b) / pic_setirq(0x0a), io/fdc.c:47-51: the same
    // chgreg bit that picks the window picks the interrupt -- for the
    // CONTROLLER's own (floppy.v's) interrupts. The motor pulse is
    // different hardware (the drive adapter at 0xCC) and always belongs to
    // the 2DD line, slave bit 2 / INT 12h -- MAME's fdc_trigger and the old
    // stub both pulse exactly there, whatever the window says.
    assign irq_2hd = (fd_irq & chgreg[0]) | motor_pulse_2hd;
    assign irq_2dd = (fd_irq & ~chgreg[0]) | motor_pulse_2dd;

    // Only the live window reads the chip. The dead one is answered with 0xFF
    // by the chipset and never reaches floppy.v, so it cannot lower irq.
    assign fd_read = rd_stb & group_live & (sel_stat | sel_data);

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            ctrl_q        <= 8'h00;
            reset_pending <= 1'b0;
        end else begin
            if (wr_stb && sel_ctrl && group_live) begin
                // np2: the reset fires on the 0 -> 1 edge of bit 7, not on the
                // level. A guest that leaves the bit set does not hold the
                // controller down.
                if (wr_data[7] && !ctrl_q[7])
                    reset_pending <= 1'b1;
                ctrl_q <= wr_data;
            end
            else if (reset_pending)
                reset_pending <= 1'b0;   // one cycle is one write to floppy.v
        end
    end

    // The synthesised DOR. Bit 2 (enable) and bits 4-5 (motors) are constants
    // because the PC-98 has nothing that drives them; bit 3 is the guest's.
    //
    // Taken from the byte being WRITTEN, not from ctrl_q. ctrl_q does not hold
    // it until the clock edge that ends the write, and the DOR has to reach
    // floppy.v during the write -- built from ctrl_q it carried the PREVIOUS
    // interrupt-enable bit, so every change arrived one write late.
    wire       ctrl_now = (wr_stb && sel_ctrl && group_live) ? wr_data[3]
                                                            : ctrl_q[3];
    wire [7:0] dor = {2'b00, 1'b1, 1'b1, ctrl_now, 1'b1, 1'b0, 1'b0};
    //                      mot1  mot0   dma_irq  enable      drive

    always_comb begin
        // Order matters: a pending reset outranks the cycle's own access, and
        // a control write becomes a DOR write rather than reaching floppy.v's
        // register 4, which would be read as a data-rate change. A window that
        // chgreg has not selected reaches floppy.v not at all -- neither the
        // address nor the write -- which is np2's guard.
        if (reset_pending) begin
            fd_addr  = 3'd4;
            fd_write = 1'b1;
            fd_wdata = 8'h80;          // floppy.v resets on reg 4 bit 7
        end
        else if (wr_stb && sel_ctrl && group_live) begin
            fd_addr  = 3'd2;
            fd_write = 1'b1;
            fd_wdata = dor;
        end
        else if (sel_data && group_live) begin
            fd_addr  = 3'd5;
            fd_write = wr_stb;
            fd_wdata = wr_data;
        end
        else if (sel_stat) begin
            fd_addr  = 3'd4;           // the MSR, and it is read-only
            fd_write = 1'b0;
            fd_wdata = wr_data;
        end
        else begin
            // Everything else parks on the MSR too: the dead window, and any
            // cycle that is none of ours. Register 4 is harmless to address.
            fd_addr  = 3'd4;
            fd_write = 1'b0;
            fd_wdata = wr_data;
        end
    end

endmodule

`default_nettype wire
