//
// pc98_grcg -- the Graphic Charger: one CPU access, four planes at once.
//
// PC-98 graphics software does not draw through the GDC. It writes GVRAM, and
// the GRCG is what makes one byte-wide write land on all four colour planes
// with a colour of its own choosing. Without it every coloured pixel costs
// four accesses and a read-modify-write per plane, which is why this is the
// piece that decides whether the machine is usable rather than merely correct.
//
// THE PORTS (np2kai io/crtc.c):
//
//   0x7C  write  mode register; ALSO RESETS THE TILE COUNTER TO 0
//         read   the mode register back
//   0x7E  write  the tile register at the counter, counter += 1 mod 4
//
// The counter reset on a mode write is not incidental: software sets the mode
// and then writes four tile bytes, and relies on the first landing in tile 0.
//
// THE MODE REGISTER:
//
//   bit 7   GRCG on. Clear and every access below is a plain one.
//   bit 6   RMW (1) or TDW (0)
//   bits 3:0  PLANE MASK, one per plane, and SET MEANS SKIP. np2kai writes it
//             as `if (!(grcg.modereg & 1))`, which is easy to read the wrong
//             way round.
//
// THE THREE OPERATIONS, from np2kai mem/memvram.c:
//
//   TDW  plane[p] = tile[p]
//        The written byte is DISCARDED -- the macro ends `(void)(v)`. A solid
//        fill of the tile colour.
//
//   RMW  plane[p] = (plane[p] & ~data) | (data & tile[p])
//        The written byte is a BIT MASK: where it is 1 the plane takes the
//        tile's bit, where 0 the plane keeps what it had. This is how a glyph
//        or a sprite is stamped in one colour in one pass.
//
//   TCR  read: ret = 0; for each unmasked plane ret |= plane[p] ^ tile[p];
//        return ~ret
//        A bit comes back 1 where EVERY unmasked plane matches its tile bit --
//        a colour-match mask, which is what hit detection is built on.
//
// WHAT THIS MODULE IS NOT. It is the transform and the registers, not the
// memory: it takes the four planes' current bytes and hands back what to write
// and which planes to write. Where the planes live is the caller's business.
//
// AND THE FOURTH PLANE IS CONDITIONAL, which a first reading of np2kai's
// address constants misses. memm_vram (i386c/cpumem.c) hangs the VRAM handler
// on all four windows -- A8000 (B), B0000 (R), B8000 (G), E0000 (E) -- and
// then takes the last one back:
//
//     if (!(func & (1 << VOPBIT_ANALOG))) {       // digital
//         memfn0.rd8[0xe0000 >> 15] = memnc_rd8;  //   no-connect
//         memfn0.wr8[0xe0000 >> 15] = memnc_wr8;
//     }
//
// In DIGITAL (eight-colour) mode there are THREE planes and E0000 answers to
// nothing; the fourth exists only in ANALOG (sixteen-colour) mode, switched by
// port 0x6A bit 0 (io/gdc.c's gdc_o6a, and only while gdc.display's analog bit
// is set). So this core's map is not missing a plane -- it is in digital mode,
// where three is correct. Sixteen colours means OPENING AND CLOSING
// E0000-E7FFF with that port, not adding a line to pc98_sdram_map.svh; RAM.sv
// records the POST sweeping into a phantom expansion when C0000 upward was
// made to answer unconditionally.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_grcg (
    input  wire       clk,
    input  wire       reset,

    // ---- the guest's two ports -----------------------------------------
    input  wire       cs_mode,        // 0x7C
    input  wire       cs_tile,        // 0x7E
    input  wire       io_read_n,
    input  wire       io_write_n,
    input  wire [7:0] io_data_in,
    output wire [7:0] io_data_out,    // 0x7C reads the mode back

    // ---- what the memory path needs to know ----------------------------
    output wire       active,         // mode bit 7: the GRCG is in the path
    output wire       rmw,            // mode bit 6
    output wire [3:0] plane_mask,     // 1 = skip this plane
    // The four tile registers, out to whoever owns the planes. This module's
    // own transform below is for a caller that already has the planes' bytes
    // in hand; pc98_gvram_seq fetches them itself and needs the tiles.
    output wire [7:0] tile_o [0:3],

    // ---- the write transform --------------------------------------------
    input  wire [7:0] cpu_wdata,
    input  wire [7:0] plane_rdata [0:3],   // what is there now (RMW needs it)
    output wire [7:0] plane_wdata [0:3],
    output wire [3:0] plane_we,            // which planes this write touches

    // ---- the read transform ---------------------------------------------
    output wire [7:0] cpu_rdata             // TCR's colour-match mask
);

    reg  [7:0] mode;
    reg  [7:0] tile [0:3];
    reg  [1:0] tcount;

    always_ff @(posedge clk) begin
        if (reset) begin
            mode   <= 8'h00;
            tcount <= 2'd0;
            tile[0] <= 8'h00; tile[1] <= 8'h00;
            tile[2] <= 8'h00; tile[3] <= 8'h00;
        end else begin
            if (cs_mode & ~io_write_n) begin
                mode   <= io_data_in;
                // Software sets the mode and then writes four tile bytes
                // expecting the first to be tile 0. np2kai io/crtc.c does this
                // in crtc_o7c and it is load-bearing.
                tcount <= 2'd0;
            end else if (cs_tile & ~io_write_n) begin
                tile[tcount] <= io_data_in;
                tcount       <= tcount + 2'd1;
            end
        end
    end

    assign io_data_out = mode;

    genvar t;
    generate
        for (t = 0; t < 4; t = t + 1) begin : g_tile
            assign tile_o[t] = tile[t];
        end
    endgenerate

    assign active     = mode[7];
    assign rmw        = mode[6];
    assign plane_mask = mode[3:0];

    genvar p;
    generate
        for (p = 0; p < 4; p = p + 1) begin : g_plane
            // SET means SKIP, and a plane is only written at all while the
            // GRCG is on -- off, the caller does its own single-plane write.
            assign plane_we[p] = active & ~mode[p];

            // TDW discards the data and lays down the tile; RMW uses the data
            // as a mask between the tile and what is already there.
            assign plane_wdata[p] = rmw
                ? ((plane_rdata[p] & ~cpu_wdata) | (cpu_wdata & tile[p]))
                : tile[p];
        end
    endgenerate

    // TCR: a bit is 1 where every UNMASKED plane matches its tile bit. Masked
    // planes contribute nothing, so with all four masked every bit matches and
    // the answer is 0xFF -- which is what np2kai's `ret = 0; ... return ~ret`
    // gives, and is worth keeping rather than special-casing.
    wire [7:0] diff = ((mode[0] ? 8'h00 : (plane_rdata[0] ^ tile[0]))
                     | (mode[1] ? 8'h00 : (plane_rdata[1] ^ tile[1]))
                     | (mode[2] ? 8'h00 : (plane_rdata[2] ^ tile[2]))
                     | (mode[3] ? 8'h00 : (plane_rdata[3] ^ tile[3])));

    assign cpu_rdata = ~diff;

    wire _unused = &{1'b0, io_read_n, 1'b0};

endmodule

`default_nettype wire
