//
// pc98_ems98 -- the NEC-style EMS board's bank registers.
//
// The V30's address bus stops at 0xFFFFF, so "extended memory" on this
// machine exists only through banking: this is the PC-9801-53-class
// interface np21w models in io/emsio.c, four 16 KB page windows at
// C0000-CFFFF programmed through byte registers at 08E1h-08E7h, with 08E9h
// selecting WHICH megabyte of board memory a page number addresses into.
// (The other EMS board in this machine -- Lo-tech, ports 0260h-0263h, the
// OSD "EMS" switch -- is a different card with a different frame and page
// granularity; the two coexist, and RAM.sv gives it priority if both map
// the same window.)
//
//   OUT 08E1h, p    window 0 (C0000-C3FFF) := 16 KB page p of the selected
//   OUT 08E3h, p    window 1 (C4000-C7FFF)    megabyte. Only p[7:2] count --
//   OUT 08E5h, p    window 2 (C8000-CBFFF)    np21w computes the byte offset
//   OUT 08E7h, p    window 3 (CC000-CFFFF)    as (p & 0xFC) << 12.
//   OUT 08E9h, t    select megabyte t for the next page writes.
//   IN  08E9h       00h while t is a megabyte this board has, FFh otherwise.
//                   Software sizes the board by scanning t = 1, 2, ... until
//                   the read returns FFh -- that is the "report the size"
//                   half of the interface.
//
// Semantics are np21w's, with one deliberate deviation:
//   t == 0: a page write maps the window to its own base frame --
//           SDRAM word 0xC0000+pos*0x4000, the "unbanked" state np21w calls
//           addr[pos] = 0xC0000 + (pos << 14).
//   1..8:   the window banks into the pool at SDRAM word 0x800000-0xFFFFFF
//           (8 MB, the top half of the 32 MB part; nothing else in the map
//           reaches past 0x61FFFF -- see RAM.sv's latch mux).
//   t > 8:  the write is dropped and the window keeps its last mapping,
//           and IN 08E9h already reads FFh there.
//   reset:  every window UNMAPPED -- np21w resets them onto the base frames,
//           but base RAM there does not exist on this machine, and a mapped
//           window would answer the POST's option-ROM scan with unwritten
//           SDRAM (the phantom-ROM hang the C0000-E7FFF hole exists to
//           prevent). Unmapped windows let the hole keep answering FFh.
//
// map[] is what RAM.sv's latch needs, not a copy of the software value:
// {mapped, SDRAM word[23:14]} -- the top ten address bits of the 16 KB
// page the window currently shows, so RAM.sv only has to concatenate the
// guest's low fourteen bits on.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_ems98 (
    input  logic        clock,
    input  logic        reset,
    input  logic [19:0] address,             // bus address: the PORT on an I/O cycle
    input  logic [7:0]  internal_data_bus,
    input  logic        io_write_n,
    input  logic        address_enable_n,
    output logic [10:0] map [0:3],           // {mapped, word[23:14]} per window
    output logic [7:0]  status               // the IN 08E9h answer
);

    // Megabytes of board memory fitted: the pool is 8 MB, targets 1-8.
    localparam logic [3:0] MAXMEM = 4'd8;

    logic [3:0] target;

    // The 24-bit word address of a page's base. A target's megabyte sits at
    // 0x800000 + (t-1)*0x100000, a page at p*0x4000 inside it, so the top ten
    // bits are {1'b1, t-1, p}; at t == 0 the base alias is 10'h030 + pos
    // (0xC0000-0xCFFFF is words 0x030-0x033 of the map, in 16 KB units).
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            target <= 4'd0;
            map    <= '{11'h000, 11'h000, 11'h000, 11'h000};
        end
        else if (~io_write_n && ~address_enable_n) begin
            case (address[15:0])
                16'h08E1, 16'h08E3, 16'h08E5, 16'h08E7: begin
                    // pos = (port >> 1) & 3 is just address[2:1].
                    if (target == 4'd0)
                        map[address[2:1]] <= {1'b1, 10'h030 + {8'h00, address[2:1]}};
                    else if (target <= MAXMEM)
                        // target[2:0]-1 wraps 8->7, which is exactly the bank
                        // the eighth megabyte needs.
                        map[address[2:1]] <= {1'b1, 1'b1, target[2:0] - 3'd1,
                                              internal_data_bus[7:2]};
                    // t > MAXMEM: keep the last mapping, per np21w.
                end
                16'h08E9: target <= internal_data_bus[3:0];
                default: ;
            endcase
        end
    end

    assign status = ((target != 4'd0) && (target <= MAXMEM)) ? 8'h00 : 8'hFF;

endmodule

`default_nettype wire
