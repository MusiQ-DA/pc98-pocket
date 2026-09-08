//
// pc98_tvram -- PC-98 text VRAM, A0000-A3FFF.
//
// Two separate 8 KB regions, NOT an interleaved char/attribute pair:
//
//   A0000 + idx*2      character code, low byte
//   A0001 + idx*2      character code, high byte (kanji, and flags the GDC
//                      masks with gdc.bitac)
//   A2000 + idx*2      attribute byte (odd addresses in this region unused)
//
// Verified against np2 vram/maketext.c, which reads exactly those three
// addresses. The tvram.sv in the pre-pivot src/ tree assumed char at even and
// attribute at odd addresses inside one 4 KB window; that is wrong, and it is
// the kind of wrong that would have produced a screen of plausible-looking
// garbage rather than an obvious failure.
//
// 80x25 = 2000 cells, so only 4000 bytes of each region are in use, but the
// windows are 8 KB each and the guest may address all of it. Two 8 KB banks,
// byte-wide, dual-ported: 16 KB total = 4 M10K blocks.
//
// The video side reads a whole cell at once -- both character bytes and the
// attribute -- because the renderer needs them together and fetching them
// through the CPU port would cost three accesses per cell.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_tvram (
    input  wire        clk,

    // Guest side, byte addressed within A0000-A3FFF.
    input  wire [13:0] cpu_addr,       // offset from A0000
    input  wire        cpu_wren,
    input  wire  [7:0] cpu_wdata,
    output logic [7:0] cpu_q,

    // Video side, by cell index.
    input  wire [11:0] vid_cell,       // 0..4095
    output logic [7:0] vid_char_lo,
    output logic [7:0] vid_char_hi,
    output logic [7:0] vid_attr
);

    // A0000-A1FFF is the character region, A2000-A3FFF the attribute region;
    // one address bit tells them apart.
    wire        is_attr  = cpu_addr[13];
    wire [12:0] off      = cpu_addr[12:0];

    // Character codes are 16 bits per cell, so the character region is stored
    // as two byte-wide banks indexed by cell -- low and high -- rather than one
    // byte-wide bank indexed by address. That way the video side gets both
    // halves in a single cycle.
    (* ramstyle = "M10K" *) logic [7:0] char_lo [0:4095];
    (* ramstyle = "M10K" *) logic [7:0] char_hi [0:4095];
    (* ramstyle = "M10K" *) logic [7:0] attr    [0:4095];

    wire [11:0] cpu_cell = off[12:1];
    wire        cpu_hi   = off[0];

    logic [7:0] q_char_lo, q_char_hi, q_attr;
    logic       q_is_attr, q_hi;

    always_ff @(posedge clk) begin
        if (cpu_wren) begin
            if (is_attr)      attr[cpu_cell]    <= cpu_wdata;
            else if (cpu_hi)  char_hi[cpu_cell] <= cpu_wdata;
            else              char_lo[cpu_cell] <= cpu_wdata;
        end

        // Read-back for the guest, one cycle late, selected after the fact so
        // all three banks are read unconditionally and the mux is outside them.
        q_char_lo <= char_lo[cpu_cell];
        q_char_hi <= char_hi[cpu_cell];
        q_attr    <= attr[cpu_cell];
        q_is_attr <= is_attr;
        q_hi      <= cpu_hi;

        vid_char_lo <= char_lo[vid_cell];
        vid_char_hi <= char_hi[vid_cell];
        vid_attr    <= attr[vid_cell];
    end

    always_comb begin
        if (q_is_attr)   cpu_q = q_attr;
        else if (q_hi)   cpu_q = q_char_hi;
        else             cpu_q = q_char_lo;
    end

endmodule

`default_nettype wire
