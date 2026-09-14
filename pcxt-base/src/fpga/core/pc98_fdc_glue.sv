//
// pc98_fdc_glue -- the PC-98 FDC ports, onto floppy.v's PC/XT register file.
//
// floppy.v is a uPD765 with a PC/XT skin: the chip's own MSR and FIFO sit at
// its registers 4 and 5, and everything else it needs -- drive select, motor,
// DMA/IRQ enable, reset -- arrives through the AT's Digital Output Register at
// register 2, plus a data rate at 4 or 7.
//
// A PC-98 has the same uPD765 and none of that skin:
//
//     0x90 / 0xC8   R    main status (MSR)
//     0x92 / 0xCA   R/W  data (the command/result FIFO)
//     0x94 / 0xCC   R/W  control
//     0xBE               2HD/2DD mode select
//
// The MSR and FIFO map straight across; there is no DOR at all. This module
// makes one, driving floppy.v's register 2 from the PC-98 control port.
//
// WHAT THE CONTROL PORT CARRIES. np2kai io/fdc.c, fdc_o94, acts on three bits
// and ignores the rest:
//
//     0x80   0 -> 1 resets the FDC (fdcstatusreset)
//     0x10   any change resets status and re-checks the DMA controller
//     0x08   interrupt enable
//
// WHAT floppy.v WANTS in register 2 (its io_readdata_prepare and the writes
// underneath):
//
//     bit 0  selected_drive      bit 2  enable -- clearing it RESETS
//     bit 3  dma_irq_enable      bit 4  motor_enable[0]
//     bit 5  motor_enable[1]
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
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_fdc_glue (
    input  wire        clk,
    input  wire        rst,

    // Guest side. sel_stat/sel_data/sel_ctrl are the decodes for 0x90/0xC8,
    // 0x92/0xCA and 0x94/0xCC; wr_stb is one cycle at the END of a write, the
    // house idiom, with wr_data sampled while the strobe was low.
    input  wire        sel_stat,
    input  wire        sel_data,
    input  wire        sel_ctrl,
    input  wire        wr_stb,
    input  wire  [7:0] wr_data,

    // floppy.v side: which of its registers this cycle addresses, whether a
    // write is happening and what it carries.
    output logic [2:0] fd_addr,
    output logic       fd_write,
    output logic [7:0] fd_wdata,

    // The control port reads back what was written, which is what np2's
    // fdc_i94 does and what the BIOS's read-modify-write of it needs.
    output logic [7:0] ctrl_readback
);

    logic [7:0] ctrl_q;
    logic       reset_pending;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            ctrl_q        <= 8'h00;
            reset_pending <= 1'b0;
        end else begin
            if (wr_stb && sel_ctrl) begin
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

    assign ctrl_readback = ctrl_q;

    // The synthesised DOR. Bit 2 (enable) and bits 4-5 (motors) are constants
    // because the PC-98 has nothing that drives them; bit 3 is the guest's.
    //
    // Taken from the byte being WRITTEN, not from ctrl_q. ctrl_q does not hold
    // it until the clock edge that ends the write, and the DOR has to reach
    // floppy.v during the write -- built from ctrl_q it carried the PREVIOUS
    // interrupt-enable bit, so every change arrived one write late.
    wire       ctrl_now = (wr_stb && sel_ctrl) ? wr_data[3] : ctrl_q[3];
    wire [7:0] dor = {2'b00, 1'b1, 1'b1, ctrl_now, 1'b1, 1'b0, 1'b0};
    //                      mot1  mot0   dma_irq  enable      drive

    always_comb begin
        // Order matters: a pending reset outranks the cycle's own access, and
        // a control write becomes a DOR write rather than reaching floppy.v's
        // register 4, which would be read as a data-rate change.
        if (reset_pending) begin
            fd_addr  = 3'd4;
            fd_write = 1'b1;
            fd_wdata = 8'h80;          // floppy.v resets on reg 4 bit 7
        end
        else if (wr_stb && sel_ctrl) begin
            fd_addr  = 3'd2;
            fd_write = 1'b1;
            fd_wdata = dor;
        end
        else begin
            fd_addr  = sel_data ? 3'd5 : 3'd4;
            fd_write = wr_stb && sel_data;
            fd_wdata = wr_data;
        end
        if (sel_stat && !wr_stb && !reset_pending)
            fd_addr = 3'd4;
    end

endmodule

`default_nettype wire
