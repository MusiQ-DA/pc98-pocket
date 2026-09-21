//
// tb_pc98_beep -- the boot beep, from the 0x37/0x73/0x77 writes the guest
// actually issues to the speaker pin.
//
// The machine's beep never sounded, and the ITF was doing its job -- the IO
// history filled with 0037 -- so the question was what those writes never
// reached. This bench rebuilds the wiring under test exactly as
// Peripherals.sv has it under MACHINE_PC98:
//
//   - the KF8253 chip model, selected by the PC-98 decode (0x71/73/75/77)
//   - the system-port C latch (0x35 whole-byte, 0x37 bit set/reset; np2
//     io/sysport.c semantics -- mode words ignored, reset value 0xF9)
//   - the beeper: counter 1's mode-3 square, muted by latch bit 3
//
// and replays the ITF's own boot-beep program (PC98_ITF_TRACE.md 1.8/1.11):
//
//   F805C4  OUT 77h,76h   counter 1, LSB+MSB, mode 3
//   F805CC  OUT 73h,(DX)  0x4CD with this machine's 0x42 read (bit5 clear)
//   F80729  OUT 37h,06h   buzzer ON  (bit3 clear -- sounds while bit3 is 0)
//   F80734  OUT 37h,07h   buzzer OFF
//   F80738  OUT 77h,76h   counter 1 again, divisor DX*2
//   F8074C  OUT 37h,06h   buzzer ON  -- the second, lower tone
//   F80755  OUT 37h,07h   buzzer OFF
//
// What each phase proves:
//   A. reset state: latch 0xF9 (muted), so a counter already programmed and
//      running produces no speaker edges. The mute is downstream, like the
//      real machine whose PIT gates are all hard-wired high.
//   B. the ITF's first tone: 0x37 <- 06h opens the beeper with nothing but
//      bit set/reset words ever issued -- no mode word. This is the exact
//      spot the old wiring died: it enabled the beeper off the 8255's
//      ~port_c_io, and port C never leaves input mode without a mode word.
//      The PPI itself is gone from the machine now; the latch below is what
//      answers 0x31-0x37.
//   C. the tone measures the counter-1 divisor (0x4CD and 0x99A at the
//      2.4576 MHz PIT clock), not some free-running default.
//   D. 0x37 <- 07h closes the gate mid-song: silence at once.
//   E. a mode word (0x37 <- B6h, top nibble set) must not touch the gate --
//      np2 ignores mode words on the system port.
//   F. 0x35 <- F7/FF gates the beeper too (whole-byte path) and the latch
//      is what 0x35 reads back.
//   G. counter 2 is NOT the beeper: with counter 1 at ~2 kHz and counter 2
//      reprogrammed to ~12 kHz, the speaker pin keeps counter 1's cadence.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_beep;

    // clk_chipset: 42.954545 MHz, the way every other bench here clocks it
    logic clk = 1'b0;
    always #11.641 clk = ~clk;

    logic reset = 1'b1;

    // The PC-98 PIT input clock, generated the way Peripherals.sv does:
    // phase-accumulate 4.9152 MHz toggles against 42.954545 MHz so the
    // edges the chip counts land at exactly 2.4576 MHz on average.
    logic timer_clock = 1'b0;
    logic [31:0] pit_clk_phase = 32'd0;
    localparam logic [31:0] PIT_CLK_TOGGLE = 32'd4_915_200;  // 2 toggles/period
    localparam logic [31:0] CHIPSET_HZ     = 32'd42_954_545;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            timer_clock   <= 1'b0;
            pit_clk_phase <= 32'd0;
        end
        else if ({1'b0, pit_clk_phase} + PIT_CLK_TOGGLE >= CHIPSET_HZ) begin
            pit_clk_phase <= pit_clk_phase + PIT_CLK_TOGGLE - CHIPSET_HZ;
            timer_clock   <= ~timer_clock;
        end
        else
            pit_clk_phase <= pit_clk_phase + PIT_CLK_TOGGLE;
    end

    // ---- the bus, driven the way the boot bench's 8288 does ---------------
    logic [19:0] address = 20'hFFFFF;      // idle: no PC-98 port selected
    logic [7:0]  internal_data_bus = 8'h00;
    logic        io_read_n  = 1'b1;
    logic        io_write_n = 1'b1;
    logic        address_enable_n = 1'b1;

    wire iorq = ~io_read_n | ~io_write_n;

    // ---- the PC-98 decodes, verbatim from Peripherals.sv ------------------
    wire pc98_io       = iorq & ~address_enable_n & ~address[9] & ~address[8];
    wire pc98_io_exact = iorq & ~address_enable_n & (address[15:8] == 8'h00);

    wire timer_chip_select_n = ~(pc98_io & address[0] & (address[7:4] == 4'h7));

    wire [1:0] pit_reg_addr = address[2:1];

    logic [7:0] timer_data_bus_out;

    // ---- the system-port C latch, verbatim from Peripherals.sv ------------
    logic [7:0] pc98_sysport_c;
    logic       sysp_prev_wr_n;
    logic [7:0] sysp_wr_data;
    wire sysport_35_select = pc98_io_exact & (address[7:0] == 8'h35);
    wire sysport_37_select = pc98_io_exact & (address[7:0] == 8'h37);
    wire sysp_addr_35 = ~address_enable_n & (address[15:8] == 8'h00)
                      & (address[7:0] == 8'h35);
    wire sysp_addr_37 = ~address_enable_n & (address[15:8] == 8'h00)
                      & (address[7:0] == 8'h37);

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            pc98_sysport_c <= 8'hF9;
            sysp_prev_wr_n <= 1'b1;
            sysp_wr_data   <= 8'h00;
        end
        else begin
            sysp_prev_wr_n <= io_write_n;
            if ((sysport_35_select | sysport_37_select) & ~io_write_n)
                sysp_wr_data <= internal_data_bus;
            if (io_write_n & ~sysp_prev_wr_n) begin
                if (sysp_addr_35)
                    pc98_sysport_c <= sysp_wr_data;
                else if (sysp_addr_37 && (sysp_wr_data[7:4] == 4'h0))
                    pc98_sysport_c[sysp_wr_data[3:1]] <= sysp_wr_data[0];
            end
        end
    end

    // ---- the beeper, exactly as Peripherals.sv wires it (MACHINE_PC98) ----
    wire [2:0] timer_counter_out;
    wire tim2gatespk = 1'b1;                   // PC-98: all PIT gates high
    wire spktone     = timer_counter_out[1];   // the beep IS counter 1
    wire spkdata     = ~pc98_sysport_c[3];     // 1 = muted; F9 at reset
    wire speaker_out = spktone & spkdata;

    KF8253 u_pit (
        .clock            (clk),
        .reset            (reset),
        .chip_select_n    (timer_chip_select_n),
        .read_enable_n    (io_read_n),
        .write_enable_n   (io_write_n),
        .address          (pit_reg_addr),
        .data_bus_in      (internal_data_bus),
        .data_bus_out     (timer_data_bus_out),
        .counter_0_clock  (timer_clock), .counter_0_gate (1'b1),
        .counter_0_out    (timer_counter_out[0]),
        .counter_1_clock  (timer_clock), .counter_1_gate (1'b1),
        .counter_1_out    (timer_counter_out[1]),
        .counter_2_clock  (timer_clock), .counter_2_gate (tim2gatespk),
        .counter_2_out    (timer_counter_out[2])
    );

    // ---- bus driving -------------------------------------------------------
    task automatic io_write(input logic [7:0] p, input logic [7:0] d);
        begin
            @(negedge clk);
            address           = {12'h000, p};
            internal_data_bus = d;
            address_enable_n  = 1'b0;
            io_write_n        = 1'b0;
            repeat (4) @(negedge clk);
            io_write_n        = 1'b1;     // chips + the latch commit here
            @(negedge clk);
            address_enable_n  = 1'b1;
            address           = 20'hFFFFF; // idle again
            internal_data_bus = 8'h00;
            repeat (4) @(negedge clk);
        end
    endtask

    // ---- speaker edge census, with half-period averaging -------------------
    int      errors = 0;
    int      edges  = 0;
    logic    measuring = 1'b0;
    logic    skip_first = 1'b0;      // the half-edge straddling run start
    logic    spk_q = 1'b0;
    realtime t_edge = 0.0;
    realtime half_sum = 0.0;
    int      half_n = 0;

    always_ff @(posedge clk) begin
        spk_q <= speaker_out;
        if (speaker_out != spk_q) begin
            edges = edges + 1;
            if (measuring) begin
                if (skip_first)
                    skip_first = 1'b0;  // first half after "go" is partial
                else begin
                    half_sum = half_sum + ($realtime - t_edge);
                    half_n   = half_n + 1;
                end
            end
            t_edge = $realtime;
        end
    end

    task automatic run_ms(input int ms);
        begin
            edges       = 0;
            half_sum    = 0.0;
            half_n      = 0;
            skip_first  = 1'b1;
            measuring   = 1'b1;
            repeat (ms * 42955) @(posedge clk);   // 42.955 clocks/us
            measuring   = 1'b0;
        end
    endtask

    task automatic check(input bit ok, input string what);
        begin
            if (ok)
                $display("--- PASS: %s", what);
            else begin
                $display("*** FAIL: %s", what);
                errors = errors + 1;
            end
        end
    endtask

    real half_us;

    initial begin
        repeat (40) @(negedge clk);
        reset = 1'b0;
        repeat (40) @(negedge clk);

        // ---- A: the ITF pre-programs counter 1 while still muted -----------
        // F805C4/F805CC: ctrl 76h (ctr1, LSB+MSB, mode 3), count 0x4CD --
        // this machine answers 0x42 = 0x02, bit5 clear, so DX = 0x4CD.
        $display("\n=== A: F805C4 pre-program (ctr1 mode 3, 0x4CD), gate still F9 ===");
        io_write(8'h77, 8'h76);
        io_write(8'h73, 8'hCD);
        io_write(8'h73, 8'h04);
        run_ms(3);
        $display("    latch=%02X  speaker edges in 3 ms: %0d", pc98_sysport_c, edges);
        check(pc98_sysport_c == 8'hF9, "A: system-port C reads 0xF9 after reset");
        check(edges == 0,             "A: counter 1 running, beeper muted (no edges)");

        // ---- B: F80729 OUT 37h,06h -- the buzzer opens ----------------------
        $display("\n=== B: F80729 OUT 37h,06h -- buzzer ON, tone 0x4CD @ 2.4576 MHz ===");
        io_write(8'h37, 8'h06);
        run_ms(5);
        half_us = (half_n > 0) ? half_sum / half_n / 1000.0 : 0.0;
        $display("    edges=%0d  half-period avg=%.2f us (expect ~250.1)", edges, half_us);
        check(edges >= 17 && edges <= 23, "B: ~2 kHz square on the speaker pin");
        check(half_us > 220.0 && half_us < 280.0, "B: half-period is 0x4CD/2 PIT clocks");

        // ---- C/D: F80734 OFF, F80738-48 reprogram 0x99A, F8074C ON ----------
        $display("\n=== C: F80734 OFF; F80738-48 ctr1 := 0x99A; F8074C ON -- tone 2 ===");
        io_write(8'h37, 8'h07);
        run_ms(2);
        check(edges == 0, "C: 0x37 <- 07h closes the beeper at once");

        io_write(8'h77, 8'h76);
        io_write(8'h73, 8'h9A);
        io_write(8'h73, 8'h09);
        io_write(8'h37, 8'h06);
        run_ms(10);
        half_us = (half_n > 0) ? half_sum / half_n / 1000.0 : 0.0;
        $display("    edges=%0d  half-period avg=%.2f us (expect ~500.1)", edges, half_us);
        check(edges >= 17 && edges <= 23, "C: ~1 kHz second tone");
        check(half_us > 440.0 && half_us < 560.0, "C: half-period is 0x99A/2 PIT clocks");

        // ---- D: F80755 OFF, F80759-6B reprogram 0x4CD ------------------------
        $display("\n=== D: F80755 OFF; F80759-6B ctr1 := 0x4CD; stays silent ===");
        io_write(8'h37, 8'h07);
        io_write(8'h77, 8'h76);
        io_write(8'h73, 8'hCD);
        io_write(8'h73, 8'h04);
        run_ms(2);
        $display("    latch=%02X  edges=%0d", pc98_sysport_c, edges);
        check(edges == 0, "D: gate closed, no re-triggered tone");

        // ---- E: a mode word to 0x37 must not touch the gate ------------------
        $display("\n=== E: 0x37 <- B6h (mode word) must leave the latch alone ===");
        io_write(8'h37, 8'hB6);
        run_ms(2);
        $display("    latch=%02X  edges=%0d", pc98_sysport_c, edges);
        check(pc98_sysport_c == 8'hF9, "E: mode word ignored (np2 sysp_o37)");
        check(edges == 0, "E: no sound through a mode word");

        // ---- F: the whole-byte path 0x35 also gates ---------------------------
        $display("\n=== F: 0x35 <- F7 opens, 0x35 <- FF closes ===");
        io_write(8'h35, 8'hF7);
        check(pc98_sysport_c == 8'hF7, "F: whole byte landed in the latch");
        run_ms(2);
        $display("    edges=%0d (ctr1 is 0x4CD -> ~2 kHz)", edges);
        check(edges >= 6 && edges <= 10, "F: whole-byte write gates the beeper");
        io_write(8'h35, 8'hFF);
        check(pc98_sysport_c == 8'hFF, "F: 0x35 <- FF latched (bit3 = muted)");
        run_ms(2);
        check(edges == 0, "F: 0x35 <- FF closes the beeper");

        // ---- G: counter 2 must not drive the speaker --------------------------
        $display("\n=== G: ctr2 := 0x00C8 (~12 kHz) while ctr1 runs -- speaker keeps ctr1 ===");
        io_write(8'h37, 8'h06);
        io_write(8'h77, 8'hB6);
        io_write(8'h75, 8'hC8);
        io_write(8'h75, 8'h00);
        run_ms(10);
        half_us = (half_n > 0) ? half_sum / half_n / 1000.0 : 0.0;
        $display("    edges=%0d  half-period avg=%.2f us", edges, half_us);
        check(edges >= 36 && edges <= 44, "G: speaker follows counter 1 (~2 kHz), not 2");
        check(half_us > 220.0 && half_us < 280.0, "G: period unchanged by the ctr2 program");

        if (errors == 0)
            $display("\nRESULT: PASS");
        else
            $display("\nRESULT: FAIL (%0d)", errors);
        $finish;
    end

endmodule

`default_nettype wire
