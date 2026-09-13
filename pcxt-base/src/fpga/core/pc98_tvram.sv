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
// TWO read ports, not one, and they read different banks:
//
//   fil  character bytes, on the chipset clock -- the glyph row buffer, which
//        needs the codes to work out where each glyph lives
//   vid  the attribute, on the dot clock -- the renderer, which needs colour
//        and reverse and blink for the cell it is drawing
//
// Splitting them that way costs nothing. Each bank still has one write port and
// one read port, so nothing has to be duplicated. Sharing a single read port
// between the two would need it in two clock domains at once, and driving it
// from both is a multiple-driver error the Fitter catches rather than a subtle
// one -- which is how this was found.
//
// ------------------------------------------------------------- memory switch
//
// A3FE0-A3FFF (attribute cells 0xFF0-0xFFF) is the PC-98's memory switch:
// eight configuration bytes at A3FE2+4i, battery-backed text VRAM on real
// hardware. np2's pccore_reset writes them from cfg {48 05 04 08 01 00 00 6E}
// BEFORE the ROM runs, and keeps DIP switch 2 bit 4 (port 0x31) clear so the
// ROM never re-initialises them. A3FEA is the one that matters most: its low
// bits say how many 128 KB units of RAM to count, so 04 = 640 KB -- the value
// the whole BIOS/BASIC work-area arithmetic is built around. Zero there and
// the machine counts 128 KB and stacks BASIC into ROM.
//
// The BIOS POST's screen clear at FECBB sweeps the full 16 KB of text VRAM
// and would stomp these bytes to 0xE1 -- the ITF's own VRAM test stops at
// 0x3FDF, sixteen bytes short, precisely to avoid this. So the eight switch
// bytes live in dedicated registers, reset-loaded with the np2 defaults, and
// guest writes anywhere in the 0xFF0-0xFFF cell range are silently dropped:
// the pre-seeded switch survives every clear exactly as the battery-backed
// original survives a power cycle. Confirmed in sim/tb_pc98_v30.sv, where
// the pre-seed plus the write gate is what carries the boot to int 1E with
// a 640 KB machine underneath it.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_tvram (
    input  wire        clk,
    input  wire        rst,            // reloads the memory switch registers

    // Guest side, byte addressed within A0000-A3FFF.
    input  wire [13:0] cpu_addr,       // offset from A0000
    input  wire        cpu_wren,
    input  wire  [7:0] cpu_wdata,
    output logic [7:0] cpu_q,

    // Fill side: character codes, on the clock the row buffer runs on.
    input  wire        fil_clk,
    input  wire [11:0] fil_cell,
    output logic [7:0] fil_char_lo,
    output logic [7:0] fil_char_hi,

    // Render side: the attribute, on the dot clock.
    input  wire        vid_clk,
    input  wire [11:0] vid_cell,
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

    // The memory switch: the eight attribute cells 0xFF1, 0xFF3, ... 0xFFF
    // (A3FE2-A3FFE at 4-byte intervals). Everything else in 0xFF0-0xFFF is
    // switch territory too and is equally write-protected. See the header.
    wire memsw_wr_block = is_attr & (cpu_cell[11:4] == 8'hFF);  // cells 0xFF0-0xFFF
    wire memsw_rd_hit   = memsw_wr_block & cpu_cell[0];         // the eight bytes

    logic [7:0] memsw [0:7];
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            memsw[0] <= 8'h48;   // A3FE2
            memsw[1] <= 8'h05;   // A3FE6
            memsw[2] <= 8'h04;   // A3FEA = 640 KB
            // A3FEE is the mask of INSTALLED OPTION ROMS, not inert config.
            // N88-BASIC reads it (E824D: MOV BX,0EEh / CALL A1D1 reads
            // A3F0:00EE) and FAR-CALLS every window whose bit is set:
            // bit0 C000, bit1 C400, bit2 C800, bit6 CA00, bit3 CC00,
            // bit7 CE00, bit4 D000, bit5 D400.
            //
            // np2's default here is 0x08, and this was copied from it -- but
            // that bit says "there is a ROM at CC00", and this machine has no
            // option ROMs at all. Measured: with 0x08 the boot printed the
            // whole BASIC banner and then jumped into CC00:0000 -- an empty
            // window, all zeros -- and never came back. With 0x00 it walks
            // all eight gates and reaches the Ok prompt.
            //
            // Do not restore np2's value without also providing the ROM it
            // claims. (np2's own byte is a saved battery-backed state, which
            // on real hardware the last boot's scan wrote; ours has no scan
            // result to inherit because the block above keeps the POST from
            // writing here at all.)
            memsw[3] <= 8'h00;   // A3FEE -- no option ROMs on this machine
            memsw[4] <= 8'h01;   // A3FF2
            memsw[5] <= 8'h00;   // A3FF6
            memsw[6] <= 8'h00;   // A3FFA
            memsw[7] <= 8'h6E;   // A3FFE
        end
    end

    logic [7:0] q_char_lo, q_char_hi, q_attr;
    logic       q_is_attr, q_hi;
    logic       q_memsw;
    logic [2:0] q_memsw_idx;

    always_ff @(posedge clk) begin
        if (cpu_wren & ~memsw_wr_block) begin
            if (is_attr)      attr[cpu_cell]    <= cpu_wdata;
            else if (cpu_hi)  char_hi[cpu_cell] <= cpu_wdata;
            else              char_lo[cpu_cell] <= cpu_wdata;
        end

        // Read-back for the guest, one cycle late, selected after the fact so
        // all three banks are read unconditionally and the mux is outside them.
        // The switch mux rides the same registered stage so its data and its
        // select arrive together.
        q_char_lo  <= char_lo[cpu_cell];
        q_char_hi  <= char_hi[cpu_cell];
        q_attr     <= attr[cpu_cell];
        q_is_attr  <= is_attr;
        q_hi       <= cpu_hi;
        q_memsw     <= memsw_rd_hit;
        q_memsw_idx <= cpu_cell[3:1];

    end

    always_ff @(posedge fil_clk) begin
        fil_char_lo <= char_lo[fil_cell];
        fil_char_hi <= char_hi[fil_cell];
    end

    always_ff @(posedge vid_clk) begin
        vid_attr <= attr[vid_cell];
    end

    always_comb begin
        if (q_memsw)        cpu_q = memsw[q_memsw_idx];
        else if (q_is_attr) cpu_q = q_attr;
        else if (q_hi)      cpu_q = q_char_hi;
        else                cpu_q = q_char_lo;
    end

endmodule

`default_nettype wire
