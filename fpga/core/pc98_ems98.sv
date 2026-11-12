//
// pc98_ems98 -- the EMS bank registers, the np21w way (np21w io/emsio.c).
//
// Four 16 KB page windows at C0000-CFFFF, programmed through byte registers
// at 08E1h-08E7h, with 08E9h selecting which megabyte a page number
// addresses into. Unlike a separate EMS board, np21w banks the windows onto
// the CPU's OWN extended memory: emsio_o08e1 sets the window to
//
//     addr = (target << 20) + ((dat & 0xFC) << 12)
//
// -- a guest-linear address, so EMS megabyte t IS linear megabyte t, the
// same memory XMS/HIMEM sees above 100000h. emsio_reset sets
// maxmem = pccore.extmem (the extended-memory size in MB), and emsio_bind
// only attaches the ports when maxmem != 0.
//
//   OUT 08E1h, p    window 0 (C0000-C3FFF) := 16 KB page p of megabyte t
//   OUT 08E3h, p    window 1 (C4000-C7FFF)    (only p[7:2] count)
//   OUT 08E5h, p    window 2 (C8000-CBFFF)
//   OUT 08E7h, p    window 3 (CC000-CFFFF)
//   OUT 08E9h, t    select megabyte t (t = dat & 0x0F)
//   IN  08E9h       00h while 1 <= t <= maxmem, FFh otherwise.
//
// Here maxmem is core_top's: EXT_MB (8) with the OSD's Ext Memory on, 0
// with it None -- the ports then stay inert (no window ever maps, 08E9h
// reads FFh), as np21w leaves them unattached.
//
// The SDRAM side: linear megabyte t is SDRAM word 0x800000 + (t-1)*0x100000
// (z86_cache's map, phys = linear + 0x700000), so a mapped window's word
// address is {1, t-1, p[7:2], a[13:0]} -- the same SDRAM the 286 reaches
// on port F. z86_cache's snoop covers 0x800000 up so a window store kills
// the CPU's cached copy of that line.
//
// Two deliberate deviations, both for the C0000-E7FFF option-ROM hole
// (Chipset.sv: the POST's option-ROM scan must read FFh there, or it
// CALLs into a phantom 55 AA signature):
//   reset:  every window UNMAPPED. np21w resets them onto the base frames
//           C0000+pos*4000h, but no RAM sits there on this machine; an
//           unmapped window is the hole. Only the chipset reset clears
//           them -- OUT F0h (the 286's return from protected mode) must
//           not, any more than it resets a real board.
//   t == 0: a page write UNMAPS the window (np21w: back to its own base
//           frame -- the same hole here).
//   t > maxmem: the write is dropped and the window keeps its mapping
//           (np21w), and IN 08E9h already reads FFh there.
//
// map is what RAM.sv's latch needs: per window {mapped, word[22:14]}
// (word bit 23 is always 1), packed window 3 .. window 0.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_ems98 (
    input  logic        clock,
    input  logic        reset,
    input  logic [15:0] address,             // the PORT on an I/O cycle
    input  logic [7:0]  internal_data_bus,
    input  logic        io_write_n,
    input  logic        address_enable_n,
    input  logic [3:0]  maxmem,              // megabytes: EXT_MB, or 0 (Ext Memory None)
    output logic [39:0] map,                 // {mapped, word[22:14]} x 4
    output logic [7:0]  status               // the IN 08E9h answer
);

    logic [3:0] target;
    logic [3:0] mapped;
    logic [8:0] page [0:3];

    wire fitted = (target != 4'd0) && (target <= maxmem);

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            target <= 4'd0;
            mapped <= 4'd0;
        end
        else if (~io_write_n && ~address_enable_n) begin
            case (address)
                16'h08E1, 16'h08E3, 16'h08E5, 16'h08E7: begin
                    // pos = (port >> 1) & 3 is address[2:1].
                    if (target == 4'd0)
                        mapped[address[2:1]] <= 1'b0;
                    else if (fitted)
                        mapped[address[2:1]] <= 1'b1;
                end
                16'h08E9: target <= internal_data_bus[3:0];
                default: ;
            endcase
        end
    end

    // The page itself needs no reset: it only matters while mapped.
    // target[2:0]-1 wraps 8 -> 7, the eighth megabyte's bank.
    always_ff @(posedge clock)
        if (~io_write_n && ~address_enable_n && fitted
            && (address[15:3] == 13'h011C) && address[0])   // 08E1-08E7 odd
            page[address[2:1]] <= {target[2:0] - 3'd1, internal_data_bus[7:2]};

    // Ext Memory switched to None at run time: nothing stays mapped.
    wire on = (maxmem != 4'd0);
    assign map = {on & mapped[3], page[3], on & mapped[2], page[2],
                  on & mapped[1], page[1], on & mapped[0], page[0]};

    assign status = fitted ? 8'h00 : 8'hFF;

endmodule

`default_nettype wire
