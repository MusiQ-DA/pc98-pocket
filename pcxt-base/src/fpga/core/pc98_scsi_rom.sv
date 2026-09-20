//
// pc98_scsi_rom -- the PC-9801-55's option ROM window at D2000.
//
// WHY A ROM AT ALL. The SCSI ports are useless on their own: nothing in this
// machine's BIOS drives them. On a PC-98 the disk BIOS for SASI, SCSI and IDE
// alike lives on the board, in an option ROM, and the main BIOS finds it by
// scanning. That scan is at FFF23 in bios.rom and it is exact:
//
//     FFFCC  mov bx,04D0             per-window flag table at 0000:04D0
//            mov cx,10h              sixteen windows
//            mov word [04AE],0D000h  starting at segment D000
//     FFF23  mov word [04AC],000Ch   the entry is at offset 000C
//     FFF2C  mov es,[04AE]
//     FFF30  cmp word [es:0009],AA55 the signature, at offset 9
//     FFF39  cmp word [es:0009],AA55 read twice -- a bus-stability check
//     FFF42  mov al,[bx] / or al,al  the window's flag byte must be zero
//     FFF48  call FFFC1              -> call word far [04AC]
//     FFF4E  add word [04AE],0100    next window, 4 KB on
//
// So: signature 55 AA at offset 9, entry far-called at offset 000C, windows
// 4 KB apart from D000. D200 is the third of them, which is where the 55
// board sits and where np2kai copies its own stub (cbus/scsiio.c:735).
//
// WHAT IS HERE. The window and a stub that survives the scan: the signature,
// and an entry that marks the window as claimed and returns. It does NOT
// install a disk BIOS yet -- that is the INT 1Bh contract, the drive table and
// the DA/UA numbering, and getting it wrong means a far call into nothing.
// This machine has been there before: memsw[3] was set to 0x08 once, BASIC
// far-called the empty CC00 window and never came back.
//
// Which is why A3FEE stays 0x00 in pc98_tvram.sv for now. The window exists
// and can be read; turning the scan on is a separate step and comes after the
// handler does something.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_scsi_rom (
    input  wire        clk,
    input  wire [11:0] addr,        // offset within the 4 KB window
    output logic [7:0] q
);

    // 256 bytes of real storage; the rest of the window reads 00. The stub is
    // sixteen bytes and a disk BIOS will not be written in Verilog literals --
    // when there is one it becomes a $readmemh image like the font and splash
    // ROMs, and this array grows to match.
    localparam int ROM_BYTES = 256;

    (* ramstyle = "M10K" *) logic [7:0] rom [0:ROM_BYTES-1];

    initial begin
        for (int i = 0; i < ROM_BYTES; i++) rom[i] = 8'h00;

        // 0000: three far-return entry slots, the shape np2's stub uses. A
        // board that is asked for a service it does not implement returns
        // rather than faulting.
        rom[8'h00] = 8'hCB; rom[8'h01] = 8'h90; rom[8'h02] = 8'h90;  // retf
        rom[8'h03] = 8'hCB; rom[8'h04] = 8'h90; rom[8'h05] = 8'h90;  // retf
        rom[8'h06] = 8'hCB; rom[8'h07] = 8'h90; rom[8'h08] = 8'h90;  // retf

        // 0009: the signature the scan at FFF30 looks for, and the size byte
        // after it (np2's stub carries 02).
        rom[8'h09] = 8'h55; rom[8'h0A] = 8'hAA; rom[8'h0B] = 8'h02;

        // 000C: the initialisation entry, far-called with BX pointing at this
        // window's byte in the 0000:04D0 flag table. Claim the window so the
        // scan does not offer it again, and return.
        //
        //   000C  C6 07 FF    mov byte [bx],0FFh
        //   000F  CB          retf
        //
        // A byte, not np2's word: the scan reads one byte at [bx] and the next
        // byte belongs to the next window, which must stay zero or that window
        // is silently skipped.
        rom[8'h0C] = 8'hC6; rom[8'h0D] = 8'h07; rom[8'h0E] = 8'hFF;
        rom[8'h0F] = 8'hCB;

        // 0012 and 0015: THE OTHER TWO ENTRY POINTS. The POST does not scan
        // once -- bios.rom runs FOUR passes over the window, one per option-
        // ROM SIZE CLASS, and the class picks the entry offset: 0x000C, then
        // 0x000F, then 0x0012, then 0x0015 (FFF23, FFF57, FFF5F, FFF91).
        // This stub's storage past the signature was ZERO, and 0x00 0x00 is
        // `add [bx+si],al` -- a two-byte walk through four kilobytes of
        // nothing and on into open RAM. The metal derailed exactly here on
        // every boot: the first two passes returned (the ring saw their
        // wrapper pops), the third stepped off the retf at 0x0F into the
        // zeros and never came back. A far return at every entry the ROM's
        // own scan can pick.
        rom[8'h12] = 8'hCB;
        rom[8'h15] = 8'hCB;
    end

    logic [7:0] rq;
    logic       in_rom;
    always_ff @(posedge clk) begin
        rq     <= rom[addr[7:0]];
        in_rom <= (addr < 12'(ROM_BYTES));
    end

    assign q = in_rom ? rq : 8'h00;

endmodule

`default_nettype wire
