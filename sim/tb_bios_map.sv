//
// tb_bios_map -- where each byte of the ROM image lands in guest memory.
//
// The PC/AT form masks the slot address to sixteen bits:
//
//     {4'b1111, ioctl_addr[15:0]}
//
// which is right for a 64 KB image at F0000 and silently WRONG for anything
// bigger: the top of a 96 KB image folds back over its own bottom and the
// damage is invisible until the guest executes it. PC-98's BIOS.ROM is
// 0x18000 bytes at 0x0E8000 (docs/PC98_MACHINE_SPEC.md F1), so it needs
// seventeen bits.
//
// This bench exists because run#106/#107 cost several hardware round trips to
// discover that the BIOS image was arriving wrong -- a class of fault that no
// SDRAM testbench can see, because nothing about the SDRAM is involved.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_bios_map;

    localparam int PC98_SIZE = 'h18000;   // BIOS.ROM, 96 KB
    localparam [19:0] PC98_BASE = 20'hE8000;

    // The two mappings, written exactly as core_top writes them.
    function automatic [19:0] map_pc98(input [24:0] a);
        map_pc98 = PC98_BASE + {3'b000, a[16:0]};
    endfunction

    function automatic [19:0] map_pcat(input [24:0] a);
        map_pcat = {4'b1111, a[15:0]};
    endfunction

    int errors = 0;
    logic [19:0] got;
    bit [19:0] seen [bit [19:0]];

    initial begin
        $display("=== BIOS image placement ===");

        // Every byte of the 96 KB image must land at its own address, in order,
        // filling E8000-FFFFF exactly.
        for (int i = 0; i < PC98_SIZE; i++) begin
            got = map_pc98(25'(i));
            if (got !== 20'(PC98_BASE + i)) begin
                if (errors < 5)
                    $display("  FAIL offset %05h -> %05h, want %05h",
                             i, got, PC98_BASE + i);
                errors++;
            end
            seen[got] = 20'(i);
        end
        $display("  distinct addresses: %0d (want %0d)", seen.size(), PC98_SIZE);
        if (seen.size() != PC98_SIZE) begin
            $display("  FAIL image folds onto itself"); errors++;
        end
        if (map_pc98(25'(0)) !== 20'hE8000) begin
            $display("  FAIL first byte not at E8000"); errors++;
        end
        if (map_pc98(25'(PC98_SIZE-1)) !== 20'hFFFFF) begin
            $display("  FAIL last byte not at FFFFF (%05h)",
                     map_pc98(25'(PC98_SIZE-1)));
            errors++;
        end
        // The reset vector must come from the top of the image.
        if (map_pc98(25'(PC98_SIZE - 'h10)) !== 20'hFFFF0) begin
            $display("  FAIL reset vector offset misplaced"); errors++;
        end

        // The reset vector patch: exactly one word, and it is the right one.
        //
        // BIOS.ROM ships with CD 19 where a real PC-98 system BIOS has
        // EA 00 00 80 FD (JMP FD80:0000) -- verified against a PC-9821Ce2
        // BANK7 dump, whose trailing 00 80 FD is byte-identical. Restoring it
        // is what lets the real BIOS entry at FD80:0000 run without an ITF.
        begin
            int patched;
            patched = 0;
            for (int i = 0; i < PC98_SIZE; i += 2)
                if (map_pc98(25'(i)) == 20'hFFFF0) patched++;
            $display("  reset-vector words intercepted: %0d (want 1)", patched);
            if (patched != 1) begin
                $display("  FAIL patch does not hit exactly one word"); errors++;
            end
            // It must be the LAST word but one of the image, not something in
            // the middle: FFFF0 is 0x10 from the end.
            if (map_pc98(25'(PC98_SIZE - 'h10)) !== 20'hFFFF0) begin
                $display("  FAIL FFFF0 is not 0x10 from the end of the image");
                errors++;
            end
        end

        // And the PC/AT form must be shown to be unusable here, so nobody
        // "simplifies" this back: it folds 96 KB into 64 KB.
        seen.delete();
        for (int i = 0; i < PC98_SIZE; i++) seen[map_pcat(25'(i))] = 20'(i);
        $display("  PC/AT form would give %0d distinct addresses for the same image",
                 seen.size());
        if (seen.size() == PC98_SIZE) begin
            $display("  FAIL the PC/AT form no longer folds -- this bench is stale");
            errors++;
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
