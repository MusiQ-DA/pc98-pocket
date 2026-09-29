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
// board sits and where np21w copies its own stub (cbus/scsiio.c:735).
//
// WHAT IS HERE. The image assembled from fpga/scsi_rom.asm: all four POST
// entries (the BIOS runs one pass per entry offset -- 0x000C, 0x000F, 0x0012,
// 0x0015), a real disk BIOS behind the 0x4B0 XROM table for the SCSI
// devtypes 0x2x and 0xAx, and the HDD boot the system BIOS never had -- its
// per-class boot iterator only serves the FDD classes, so entry 0x12 reads
// the IPL to 1FC0:0000 and far-calls it, exactly what a -55's own ROM does.
//
// The image is $readmemh'd rather than written in Verilog literals; the two
// builds look for it from different working directories, so the path is
// picked the same way v30u_ucrom picks HEXDIR.
//
// The window is a byte ROM on a machine that reads WORDS: byte 9 of the
// signature lives on the HIGH lane. q_hi is the same array read at
// addr|1, registered the same clock as q, so a word read gets both lanes in
// the same cycle and Chipset can mux the odd byte onto data_bus_hi.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_scsi_rom (
    input  wire        clk,
    input  wire [11:0] addr,        // offset within the 4 KB window
    input  wire [11:0] addr_hi,     // addr|1 -- the odd byte for the hi lane
    output logic [7:0] q,
    output logic [7:0] q_hi
);

    (* ramstyle = "M10K" *) logic [7:0] rom [0:4095];

`ifdef SYNTHESIS
    // Quartus resolves $readmemh against the project directory (fpga/),
    // and 18.1 refuses a `parameter string` here ("aggregate value"), so
    // the path stays a literal in each branch.
    initial $readmemh("core/scsi_rom.hex", rom);
`else
    // The benches run Verilator from the repository root.
    initial $readmemh("fpga/core/scsi_rom.hex", rom);
`endif

    // Two registered ports of the same array: a true dual-port M10K, so the
    // odd byte is free. Lane timing matches the data_bus_out path that has
    // always served this window.
    always_ff @(posedge clk) begin
        q    <= rom[addr];
        q_hi <= rom[addr_hi];
    end

`ifndef SYNTHESIS
    // The F44 lesson from v30u_ucrom applies here: a wrong path is two
    // warnings and a silent all-zero ROM. Probe the signature after the load
    // and take the run down if it did not arrive.
    initial begin
        #1;
        if (rom[9] !== 8'h55 || rom[10] !== 8'hAA)
            $fatal(1, "pc98_scsi_rom: scsi_rom.hex did not load");
    end
`endif

endmodule

`default_nettype wire
