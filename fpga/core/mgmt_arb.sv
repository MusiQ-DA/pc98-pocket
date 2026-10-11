// mgmt_arb -- the management-bus arbitration between the softcore and the
// RAM-image floppy server (fdd_ramimg), factored out of core_top so the
// sim benches elaborate the real gate.
//
// The server wins whole cycles: while it strobes, the address AND data are
// its operands and the firmware strobes are fenced entirely. The fence has
// to cover strobes aimed at OTHER windows, not just F2-windowed ones --
// the cycle the server pushes a FIFO byte the bus address is already its
// 0xF20F, so an unrelated softcore read (the scsi_poll/OPNA polls at F4/F5)
// OR'd onto the same cycle arrives at floppy.v as a nibble-F read: a FIFO
// pop that eats the fill's head byte. The fill then ends short of
// fifo_full, the FDC keeps its request raised, the server re-serves the
// same LBA, and the guest receives the sector rotated by the pop count --
// the exact hardware symptom this gate fixes (sim/tb_ramimg_fdc.sv
// reproduces it byte-for-byte).
//
// Outside a server strobe the firmware's own accesses pass through, with
// the standing fence: while `own` is high its F2-window strobes are still
// dropped, because the server owns the floppy for the whole enabled
// period, not just while it is mid-transaction.
//
// SPDX-License-Identifier: GPL-3.0-or-later

`default_nettype none

module mgmt_arb (
    // softcore side (the bus's normal owner)
    input  wire [15:0] fw_addr,
    input  wire [15:0] fw_dout,
    input  wire        fw_rd,
    input  wire        fw_wr,

    // RAM-image server side
    input  wire [15:0] ri_addr,
    input  wire [15:0] ri_dout,
    input  wire        ri_rd,
    input  wire        ri_wr,
    input  wire        ri_own,

    // CHIPSET side
    output wire [15:0] cs_addr,
    output wire [15:0] cs_dout,
    output wire        cs_rd,
    output wire        cs_wr
);

    wire ri_stb     = ri_rd | ri_wr;
    wire fw_fdd_hit = fw_addr[15:8] == 8'hF2;

    assign cs_addr = ri_stb ? ri_addr : fw_addr;
    assign cs_dout = ri_stb ? ri_dout : fw_dout;
    assign cs_rd   = ri_rd | (fw_rd & ~ri_stb & ~(ri_own & fw_fdd_hit));
    assign cs_wr   = ri_wr | (fw_wr & ~ri_stb & ~(ri_own & fw_fdd_hit));

endmodule

`default_nettype wire
