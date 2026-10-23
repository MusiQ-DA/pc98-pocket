//
// tb_itf_stubwin -- the crash trap's low-RAM terms vs the machine's own boot.
//
// tlog_trap stops z86 the moment pc_wild says the fetch cursor went where no
// code lives: below 0x400 (the IVT), VRAM, the SCSI hole, HLT with IF=0, or an
// OUT 0F0h.  The hardware catch decoded the trap's one false positive family:
// the ITF hand-over legitimately runs code at 0000:0000-0000:007E (F88BD copies
// the bank-switch stub there and jumps to it), and the ITF's own POST shutdown
// writes port 0F0h from F9A2A/F9A30.  Both happen with the ITF bank mapped, so
// core_top masks the IVT term through a stub window latched at the first fetch
// below 0x100 while the bank is up, and masks the F0 term while the bank is up.
//
// This bench pins the three properties the mask must keep and the two it must
// not break:
//
//   * the hand-over walk (0:0 -> the stub's branches -> the bank DROPPING
//     mid-stub on its own OUT 043Dh,12h -> still under 0x100 -> out to
//     F800:0919) never trips;
//   * a game-state fetch into the IVT (bank down) still trips, including at
//     0000:0000 itself -- the classic null-vector crash the trap hunts;
//   * a wild walk that crosses 0x100 inside the IVT is caught the cycle it
//     crosses -- the window does not blanket the whole vector table;
//   * the boot's own OUT 0F0h (bank up) does not trip; a game-state OUT 0F0h
//     (bank down) still does;
//   * the window re-arms per boot and does not leak across one.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_itf_stubwin;

    logic clk = 0, rst = 1;
    always #11.64 clk = ~clk;

    // ---- the inputs --------------------------------------------------------
    logic [19:0] pc_now         = 20'hF8000;
    logic        halted         = 1'b0;
    logic [223:0] dbg_regs      = 224'h0;   // bit217 = IF
    logic        io_write_n     = 1'b1;
    logic        aen            = 1'b0;
    logic [19:0] address        = 20'h0;

    // ---- the logic under test, written as core_top writes it ---------------
    wire f0_port_write = ~io_write_n & ~aen & (address[15:0] == 16'h00F0);

    reg itf_bank = 1'b1;
    reg itf_io_q, itf_io_qq;
    reg [7:0] itf_io_data;
    wire itf_port_write = ~io_write_n & ~aen & (address[15:0] == 16'h043D);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            itf_bank    <= 1'b1;
            itf_io_q    <= 1'b0;
            itf_io_qq   <= 1'b0;
            itf_io_data <= 8'h00;
        end else begin
            itf_io_q  <= itf_port_write;
            itf_io_qq <= itf_io_q;
            if (itf_port_write) itf_io_data <= cpu_data_bus;
            if (itf_io_q && itf_io_qq && ~itf_port_write) begin
                if      (itf_io_data == 8'h10) itf_bank <= 1'b1;
                else if (itf_io_data == 8'h12) itf_bank <= 1'b0;
            end
        end
    end
    logic [7:0] cpu_data_bus = 8'h00;

    wire pc_stub  = (pc_now < 20'h00100);
    wire stub_arm = pc_stub && itf_bank;
    reg  stub_win = 1'b0;
    always_ff @(posedge clk) begin
        if (stub_arm)      stub_win <= 1'b1;
        else if (!pc_stub) stub_win <= 1'b0;
    end
    wire [19:0] wild_floor = (stub_win | stub_arm) ? 20'h00100 : 20'h00000;
    wire pc_wild = ((pc_now >= wild_floor) && (pc_now < 20'h00400)) ||
                   (pc_now >= 20'hA0000 && pc_now < 20'hD0000) ||
                   (pc_now >= 20'hE0000 && pc_now < 20'hE8000) ||
                   (halted && !dbg_regs[217]) ||
                   (f0_port_write && !itf_bank);

    // The trap's stop, as core_top gates it: tlog_trap armed, not yet frozen.
    bit  tlog_trap = 1'b1, tlog_frozen = 0, stop = 0;
    always_ff @(posedge clk) begin
        if (tlog_trap && pc_wild && !tlog_frozen) begin
            tlog_frozen <= 1'b1;
            stop        <= 1'b1;
        end
    end

    int errors = 0;

    task automatic check(input bit want_wild, input string what);
        if (pc_wild !== want_wild) begin
            $display("  FAIL %s: pc_wild=%0b want %0b (pc=%06x bank=%0d win=%0d)",
                     what, pc_wild, want_wild, pc_now, itf_bank, stub_win);
            errors++;
        end
    endtask

    // Drive a cursor value, let a whole clock settle (the window and the stop
    // latch on the edge), then report.  check() reads the combinational term,
    // check_stop() the registered trap.
    task automatic visit(input logic [19:0] p, input bit want_wild,
                         input string what);
        pc_now = p;
        @(posedge clk); @(posedge clk);
        check(want_wild, what);
    endtask

    task automatic check_stop(input bit want_stop, input string what);
        if (stop !== want_stop) begin
            $display("  FAIL %s: stop=%0b want %0b", what, stop, want_stop);
            errors++;
        end
    endtask

    // Park the cursor somewhere ordinary and drop any frozen/stop state, the
    // way a probe write re-arms the real trap.
    task automatic rearm;
        pc_now    = 20'h30100;
        @(posedge clk); @(posedge clk);
        tlog_frozen = 0;
        stop        = 0;
    endtask

    // out 0x043D,al the way the bus does it (tb_itf_bank's shape).
    task automatic out43d(input logic [7:0] v);
        address       = 20'h0043D;
        cpu_data_bus  = 8'hC3;
        io_write_n    = 1'b0;
        repeat (2) @(posedge clk);
        cpu_data_bus  = v;
        repeat (3) @(posedge clk);
        io_write_n    = 1'b1;
        address       = 20'h0;
        repeat (4) @(posedge clk);
    endtask

    // out 0xF0,al the way the bus does it.
    task automatic outf0;
        address      = 20'h000F0;
        cpu_data_bus = 8'h00;
        io_write_n   = 1'b0;
        repeat (3) @(posedge clk);
        io_write_n   = 1'b1;
        address      = 20'h0;
        repeat (4) @(posedge clk);
    endtask

    initial begin
        $display("=== ITF hand-over vs the crash trap ===");
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        // -- 1. the hand-over walk, exactly as the ROM runs it ----------------
        // The ITF is mapped (power-on default), the cursor runs POST in F8xxx,
        // then the copy at F88BD finishes and the far jump lands at 0000:0000.
        visit(20'hF88BD, 0, "POST fetch");
        visit(20'h00000, 0, "jmp 0:0, the stub launch");
        check_stop(0, "the trap stopped the hand-over");
        // The stub's own branches (the checksum loops live at 0:6-0x3E).
        visit(20'h00006, 0, "stub: mov ax,ds");
        visit(20'h0001A, 0, "stub: checksum loop");
        // The stub's FIRST instruction flips the bank to the BIOS: the window
        // must hold on its own latch, not on the live bank.
        out43d(8'h12);
        if (itf_bank !== 1'b0) begin $display("  FAIL out43d(12) ignored"); errors++; end
        visit(20'h00038, 0, "stub after its own bank flip");
        visit(20'h00044, 0, "stub tail");
        // The stub re-maps the ITF and jumps back into ROM: window must drop.
        out43d(8'h10);
        visit(20'hF8919, 0, "jmp F800:0919, back in ROM");
        if (stub_win !== 1'b0) begin $display("  FAIL stub_win leaked past the stub"); errors++; end
        check_stop(0, "the trap stopped the boot");

        // -- 2. a game-state crash into the IVT still trips -------------------
        // Steady game state: the BIOS is mapped (0x12), not the ITF.
        out43d(8'h12);
        rearm;
        visit(20'h00000, 1, "game-state fetch at 0:0 (null vector)");
        check_stop(1, "the trap missed a null-vector crash");

        // -- 3. a wild walk crossing 0x100 is caught the cycle it crosses -----
        rearm;
        out43d(8'h10);                  // boot state again
        visit(20'h00000, 0, "boot re-entry arms the window");
        visit(20'h000FE, 0, "still inside the stub page");
        visit(20'h00100, 1, "walk crossed 0x100 into the IVT");
        check_stop(1, "the trap missed a walk above the stub page");

        // -- 4. the other wild terms are untouched ----------------------------
        rearm;
        pc_now = 20'hA8000; @(posedge clk); check(1, "VRAM fetch");
        rearm;
        pc_now = 20'hE0000; @(posedge clk); check(1, "SCSI-hole fetch");
        rearm;
        pc_now = 20'h30100; dbg_regs[217] = 1'b0; halted = 1'b1;
        @(posedge clk); check(1, "HLT with IF=0");
        halted = 1'b0; dbg_regs[217] = 1'b1;

        // -- 5. the F0 term: the boot's own write vs a game-state write -------
        rearm;
        out43d(8'h10);                  // the ITF's POST state
        outf0;                          // F9A2A/F9A30-class write, bank up
        check_stop(0, "the boot's own OUT F0 tripped the trap");
        rearm;
        out43d(8'h12);                  // game state
        outf0;
        check_stop(1, "a game-state OUT F0 did not trip");

        // -- 6. the window does not leak between boots ------------------------
        rearm;
        out43d(8'h10);                  // a boot maps the ITF again
        visit(20'h00000, 0, "second boot arms again");
        visit(20'hF8000, 0, "back in ROM");
        if (stub_win !== 1'b0) begin $display("  FAIL window armed outside the stub page"); errors++; end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
