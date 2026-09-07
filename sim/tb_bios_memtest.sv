//
// tb_bios_memtest -- the BIOS's own base-64K memory test, cycle for cycle.
//
// The in-core self-test walks the same region and passes on hardware, but it
// spends about 16 us per access. The BIOS does it with rep stosw / lodsw, which
// is roughly nineteen times faster and is what actually fails. This bench
// reproduces the BIOS code rather than an approximation of it.
//
// From the shipped PCXT BIOS at F000:E11A (POST 04):
//
//     xor si,si / xor di,di / mov ds,di / mov es,di
//     mov ax,0x55aa ; mov cx,0x4000 ; rep stosw     ; write 32 KB
//     mov cx,0x4000 ; lodsw ; cmp ax,0x55aa ; jnz fail ; loop  ; read it back
//     mov ax,0xaa55 ; ... the same again with the other pattern
//     failure -> POST 54 and an error tone
//
// A word access is two byte bus cycles on an 8088, back to back, so the
// stimulus here is a stream of byte cycles with no idle between them -- the
// densest traffic the machine can produce, and the thing every other bench has
// been too polite to generate.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_bios_memtest;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    // 8088 at 4.77 MHz: nine chipset clocks per T state, four T states a cycle.
    localparam int T_STATE  = 9;
    localparam int BUS_CYCLE = 4 * T_STATE;

    // Scaled down from the BIOS's 32 KB so the run is tractable; the pattern,
    // the density and the write-all-then-read-all ordering are what matter.
    localparam int WORDS = 1024;   // 2 KB, 2048 byte bus cycles per pass

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    logic [19:0] address = '0;
    logic  [7:0] internal_data_bus = '0;
    logic        memory_read_n = 1, memory_write_n = 1, no_command_state = 1;
    wire   [7:0] data_bus_out;
    wire         memory_access_ready, access_complete, ram_address_select_n;
    logic        initilized_sdram;

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [6:0] map [0:3] = '{7'd0, 7'd0, 7'd0, 7'd0};

    RAM dut (
        .clock(clock), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(address), .internal_data_bus(internal_data_bus),
        .data_bus_out(data_bus_out),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .no_command_state(no_command_state),
        .memory_access_ready(memory_access_ready),
        .access_complete(access_complete),
        .ram_address_select_n(ram_address_select_n),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .map_ems(map), .ems_b1(1'b0), .ems_b2(1'b0), .ems_b3(1'b0), .ems_b4(1'b0),
        .bios_protect_flag(2'b00), .tandy_bios_flag(1'b0),
        .enable_a000h(1'b1), .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0)
    );

    sdram_board_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                        .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    int errors = 0, waits_total = 0;

    // One 8088 byte bus cycle: command out in T2, READY checked at the end of
    // T3, wait states inserted a T state at a time, data latched, T4, next.
    task automatic bus_byte(input bit is_write, input logic [19:0] a,
                            input logic [7:0] d, output logic [7:0] q);
        int w = 0;
        address = a;
        internal_data_bus = d;
        no_command_state = 0;
        if (is_write) memory_write_n = 0; else memory_read_n = 0;
        repeat (2 * T_STATE) @(posedge clock);        // T2 .. end of T3
        while (!memory_access_ready && w < 60) begin
            repeat (T_STATE) @(posedge clock);
            w++;
        end
        waits_total += w;
        q = data_bus_out;
        repeat (T_STATE) @(posedge clock);            // T4
        memory_write_n = 1;
        memory_read_n  = 1;
        no_command_state = 1;
        @(posedge clock);                             // back to back, no idle
    endtask

    // rep stosw / lodsw: a word is two byte cycles, low then high.
    task automatic word_write(input int wa, input logic [15:0] v);
        logic [7:0] ig;
        bus_byte(1'b1, 20'(wa * 2),     v[7:0],  ig);
        bus_byte(1'b1, 20'(wa * 2 + 1), v[15:8], ig);
    endtask

    task automatic word_read(input int wa, output logic [15:0] v);
        logic [7:0] lo, hi;
        bus_byte(1'b0, 20'(wa * 2),     8'h00, lo);
        bus_byte(1'b0, 20'(wa * 2 + 1), 8'h00, hi);
        v = {hi, lo};
    endtask

    // The 8088 is also FETCHING while it does this. The BIOS runs from SDRAM at
    // F000:E130, so every few data accesses the bus goes off to 0xFE1xx and
    // comes back -- a different row, and under sdram_mp's {row, bank, col}
    // mapping a different bank too. Neither this bench nor the in-core
    // self-test did that, and it is the last structural difference between what
    // passes here and what fails on hardware.
    int fetch_ptr = 0;
    task automatic code_fetch();
        logic [7:0] ig;
        bus_byte(1'b0, 20'(20'hFE130 + fetch_ptr), 8'h00, ig);
        fetch_ptr = (fetch_ptr + 1) & 15;
    endtask

    task automatic pass(input logic [15:0] patt, input string name);
        logic [15:0] v;
        int base_err = errors;
        for (int i = 0; i < WORDS; i++) begin
            word_write(i, patt);
            if ((i & 3) == 3) code_fetch();     // prefetch refills the queue
        end
        for (int i = 0; i < WORDS; i++) begin
            if ((i & 3) == 3) code_fetch();
            word_read(i, v);
            if (v !== patt) begin
                if (errors - base_err < 4)
                    $display("  %s MISMATCH word %0d (addr %05h): got %04h want %04h",
                             name, i, i * 2, v, patt);
                errors++;
            end
        end
        $display("  %s: %0d / %0d words wrong", name, errors - base_err, WORDS);
    endtask

    // POST 05's interrupt-vector setup, which is the pattern nothing has tested:
    //
    //     mov si,0xd855 ; mov cx,0x20 ; mov ax,0xf000 ; movsw
    //
    // a read from F000:D855 and a write to 0000:0000, alternating. Two
    // addresses 0xFD855 apart, so every access changes row -- and under
    // sdram_mp's {row, bank, col} mapping, bank as well. Every other bench
    // here writes a block and then reads a block; none of them alternate
    // between distant rows.
    //
    // It matters because the guest stops at POST 08 (hardware, testB19), whose
    // first real work is int 0x16 -- the first use of a vector out of the table
    // this loop builds. A table written wrong sends the CPU into the weeds.
    task automatic ivt_copy(input int words);
        logic [7:0] lo, hi, glo, ghi;
        int bad = 0;
        for (int i = 0; i < words; i++) begin
            // Seed the source in high memory, then copy it down like movsw.
            bus_byte(1'b1, 20'(20'hFD855 + i * 2),     8'(i),       lo);
            bus_byte(1'b1, 20'(20'hFD855 + i * 2 + 1), 8'(i ^ 8'hA5), hi);
        end
        for (int i = 0; i < words; i++) begin
            bus_byte(1'b0, 20'(20'hFD855 + i * 2),     8'h00, lo);
            bus_byte(1'b1, 20'(i * 2),                 lo,    glo);
            bus_byte(1'b0, 20'(20'hFD855 + i * 2 + 1), 8'h00, hi);
            bus_byte(1'b1, 20'(i * 2 + 1),             hi,    ghi);
        end
        for (int i = 0; i < words; i++) begin
            bus_byte(1'b0, 20'(i * 2),     8'h00, glo);
            bus_byte(1'b0, 20'(i * 2 + 1), 8'h00, ghi);
            if (glo !== 8'(i) || ghi !== 8'(i ^ 8'hA5)) begin
                if (bad < 4)
                    $display("  IVT MISMATCH vector %0d: got %02h %02h want %02h %02h",
                             i, glo, ghi, 8'(i), 8'(i ^ 8'hA5));
                bad++;
                errors++;
            end
        end
        $display("  IVT copy (alternating F000:D855 <-> 0000:0000): %0d / %0d wrong",
                 bad, words);
    endtask

    initial begin
`ifdef SDRAM_USE_MP
        $display("=== BIOS base-64K memory test through sdram_mp ===");
`else
        $display("=== BIOS base-64K memory test through KFSDRAM (reference) ===");
`endif
        $display("    rep stosw / lodsw, %0d words, back-to-back bus cycles", WORDS);
        repeat (8) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);

        pass(16'h55AA, "55AA");
        pass(16'hAA55, "AA55");
        ivt_copy(32);          // mov cx,0x20 -- the BIOS copies 32 vectors

        $display("\n=== summary ===");
        $display("  word errors        : %0d", errors);
        $display("  wait states        : %0d", waits_total);
        $display("  protocol violations: %0d", sdr.u_part.violations);
        if (errors == 0 && sdr.u_part.violations == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL -- this is POST 54 on hardware");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
