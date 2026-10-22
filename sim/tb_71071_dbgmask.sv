//
// tb_71071_dbgmask -- pin the uPD71071 request-side snapshot's ACTUAL
// bit layout (probe slot 0xA8), unit-level on the real upd71071.
//
// The run#977 freeze was decoded against a layout that never reached
// the metal: the priority encoder's dbg port is [22:0] assigned a
// 19-bit concat (zero-extension -- fields at [18:0]) and upd71071.sv's
// dbg_mask concat is 36 bits into the 32-bit port (truncation -- the
// top four bits fall off). A repack that shipped the documented layout
// crashed CI's Quartus deterministically (S2T internal error at
// s2t_sgate_tdb_map.cpp:395, then 8 LABs over at the fitter, runs
// 39835977543..39863568833; the 0f87752 shape re-proved green twice),
// so the ugly layout IS the interface and this bench pins the decode
// it actually delivers -- so the hunt scripts never lie again:
//   [25] controller_disable  [24] rotating_priority
//   [23] dreq_sense_active_low  [22:19] mask_register
//   [18:15] request_register  [14:11] dma_request_ff
//   [10:7] dma_request_lock   [26] and [6:0] read 0
//   [31] transfer_mode[3][0]  [30:29] transfer_mode[2]
//   [28] autoinit[3]  [27] autoinit[2]
// (transfer_mode[3][1] is the one bit the truncation eats: ch3 block
// mode reads the same as demand at [31].)
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_71071_dbgmask;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clk = 0;
    always #(HALF_NS) clk = ~clk;

    logic        reset = 1'b1;
    logic        chip_select_n = 1'b1;
    logic        io_write_n_in = 1'b1;
    logic        io_read_n_in  = 1'b1;
    logic [3:0]  address_in = 4'd0;
    logic [7:0]  data_bus_in = 8'd0;
    logic        ready = 1'b1;
    logic        hold_acknowledge = 1'b0;
    logic [3:0]  dma_request = 4'b1111;     // pins idle (active low)
    logic        end_of_process_n_in = 1'b1;

    wire  [31:0] dbg_mask;
    logic [31:0] mask_q = 32'h0;
    always @(posedge clk) mask_q <= dbg_mask;   // settle before checks

    upd71071 u_dmac (
        .clock              (clk),
        .cpu_ce_posedge     (1'b0),
        .cpu_ce_negedge     (1'b0),
        .reset              (reset),
        .chip_select_n      (chip_select_n),
        .ready              (ready),
        .hold_acknowledge   (hold_acknowledge),
        .dma_request        (dma_request),
        .data_bus_in        (data_bus_in),
        .data_bus_out       (),
        .io_read_n_in       (io_read_n_in),
        .io_read_n_out      (),
        .io_read_n_io       (),
        .io_write_n_in      (io_write_n_in),
        .io_write_n_out     (),
        .io_write_n_io      (),
        .end_of_process_n_in(end_of_process_n_in),
        .end_of_process_n_out(),
        .address_in         (address_in),
        .address_out        (),
        .output_highst_address(),
        .hold_request       (),
        .dma_acknowledge    (),
        .address_enable     (),
        .address_strobe     (),
        .memory_read_n      (),
        .memory_write_n     (),
        .dbg                (),
        .dbg_mask           (dbg_mask)
    );

    // One guest register write: select the DMAC, hold address+data with
    // IOW low, then raise IOW -- the write lands on the strobe's rise
    // (write_flag), using the address captured while the window was ours.
    task automatic wr(input logic [3:0] a, input logic [7:0] d);
        begin
            @(negedge clk);
            chip_select_n = 1'b0;
            address_in    = a;
            data_bus_in   = d;
            io_write_n_in = 1'b0;
            repeat (3) @(negedge clk);
            io_write_n_in = 1'b1;   // the rise latches the write
            repeat (2) @(negedge clk);
            chip_select_n = 1'b1;
            @(negedge clk);
        end
    endtask

    int errors = 0;

    task automatic chk(input string what, input logic [31:0] got,
                       input int hi, input int lo, input logic [31:0] exp);
        logic [31:0] fld;
        begin
            fld = (got >> lo) & ((32'h1 << (hi - lo + 1)) - 1);
            if (fld !== (32'(exp))) begin
                errors++;
                $display("FAIL: %s [%2d:%2d] got %b, expected %b (raw %08x)",
                         what, hi, lo, fld, exp, got);
            end else
                $display("pass: %s [%2d:%2d] = %b", what, hi, lo, fld);
        end
    endtask

    initial begin
        reset = 1'b1;
        repeat (4) @(negedge clk);
        reset = 1'b0;
        repeat (2) @(negedge clk);

        // (1) post-reset: all channels masked, modes cleared, command
        // bits clear. Pins idle (1111) with sense=0 read back as ff=1111
        // -- the raw pin level, not a request.
        chk("reset mask",        mask_q, 22, 19, 4'hF);
        chk("reset request",     mask_q, 18, 15, 4'h0);
        chk("reset sense",       mask_q, 25, 23, 3'b000);
        chk("reset ch3 mode",    mask_q, 31, 31, 1'b0);
        chk("reset ch2 mode",    mask_q, 30, 29, 2'b00);
        chk("reset ch3 autoinit",mask_q, 28, 28, 1'b0);
        chk("reset ch2 autoinit",mask_q, 27, 27, 1'b0);
        chk("reset ff=pins",     mask_q, 14, 11, 4'b1111);

        // (2) command 0x54: DREQ-sense active low (bit6), rotating
        // priority (bit4), controller disable (bit2). Sense folds the
        // idle pins: ff reads 0000.
        wr(4'h8, 8'h54);
        chk("cmd disable",   mask_q, 25, 25, 1'b1);
        chk("cmd rotating",  mask_q, 24, 24, 1'b1);
        chk("cmd sense low", mask_q, 23, 23, 1'b1);
        chk("sense folds ff",mask_q, 14, 11, 4'h0);

        // (3) mode ch3 = 0x9B: block mode + autoinit + ch3. Block reads
        // at [31]=tm3[0]=0 (tm3[1] is truncated away) -- this is the
        // documented blind spot, pinned so nobody trusts [31] for ch3.
        wr(4'hB, 8'h9B);
        chk("ch3 block->0",  mask_q, 31, 31, 1'b0);
        chk("ch3 autoinit",  mask_q, 28, 28, 1'b1);

        // (4) mode ch2 = 0x56: single mode + autoinit + ch2; ch3 keeps
        // its own bits (a per-channel field bleed is the failure this
        // catches).
        wr(4'hB, 8'h56);
        chk("ch2 single",    mask_q, 30, 29, 2'b01);
        chk("ch2 autoinit",  mask_q, 27, 27, 1'b1);
        chk("ch3 kept ai",   mask_q, 28, 28, 1'b1);

        // (5) write-all-mask 0x05: only ch0 and ch2 masked.
        wr(4'hF, 8'h05);
        chk("wr mask 0101",  mask_q, 22, 19, 4'd5);

        // (6) software request ch3 (0x07 = set, ch 3).
        wr(4'h9, 8'h07);
        chk("sw request ch3",mask_q, 18, 15, 4'b1000);

        // (7) master clear (0x0D): mask back to 1111, modes cleared,
        // autoinits cleared, request dropped, command bits cleared, and
        // sense=0 again so ff re-reads the raw pins -- exactly the post-
        // init shape run#977's 0x00F80000 decoded as (sense|mask).
        wr(4'hD, 8'h00);
        chk("mclr mask",     mask_q, 22, 19, 4'hF);
        chk("mclr request",  mask_q, 18, 15, 4'h0);
        chk("mclr command",  mask_q, 25, 23, 3'b000);
        chk("mclr ch3 mode", mask_q, 31, 31, 1'b0);
        chk("mclr ch2 mode", mask_q, 30, 29, 2'b00);
        chk("mclr ch3 ai",   mask_q, 28, 28, 1'b0);
        chk("mclr ch2 ai",   mask_q, 27, 27, 1'b0);
        chk("mclr ff=pins",  mask_q, 14, 11, 4'b1111);
        if (mask_q[31:0] !== 32'h00787800) begin
            errors++;
            $display("FAIL: mclr word got %08x, expected 00787800", mask_q);
        end else
            $display("pass: mclr word = 00787800");

        // (8) the run#977 snapshot, reconstructed: after the master
        // clear the BIOS reprograms the command register's sense bit
        // (0x40) -- the word becomes exactly 0x00F80000, which the hunt
        // first misread as "autoinit[3]=1, mask=1111" against the
        // phantom layout: bit23 is sense, the mask sits at [22:19].
        wr(4'h8, 8'h40);
        chk("977 sense",     mask_q, 23, 23, 1'b1);
        chk("977 mask",      mask_q, 22, 19, 4'hF);
        chk("977 ff folded", mask_q, 14, 11, 4'h0);
        if (mask_q[31:0] !== 32'h00F80000) begin
            errors++;
            $display("FAIL: run977 word got %08x, expected 00F80000", mask_q);
        end else
            $display("pass: run977 word = 00F80000");

        if (errors == 0)
            $display("=== PASS tb_71071_dbgmask ===");
        else
            $display("=== FAIL tb_71071_dbgmask ===");
        $finish;
    end

endmodule

`default_nettype wire
