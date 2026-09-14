//
// tb_pc98_gdc -- does the GDC put the parameters where np2kai puts them?
//
// pc98_gdc's whole job is a lookup: a command byte says where the bytes that
// follow belong and how many there are. Getting that wrong is not a crash, it
// is a screen that scrolls to the wrong address, so the table is worth an
// assertion per entry rather than a reading.
//
// The expectations here come from np2kai's io/gdc_cmd.tbl (the 256-entry
// {destination, count} table) and io/gdc.c, not from the enum in gdc_cmd.h --
// two of its names are misleading and both were nearly believed:
//
//   * 0x70-0x7F are ONE command, a write into a sixteen-byte PRAM starting at
//     the low nibble, taking 16 - nibble parameters. CMD_SCROLL (0x70) and
//     CMD_TEXTW (0x78) name offsets 0 and 8 of the same block.
//   * ZOOM is 0x46. The enum says 0x06; the table has nothing there.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_gdc;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic       reset = 1'b1;
    logic       cs = 1'b0, a1 = 1'b0;
    logic       io_read_n = 1'b1, io_write_n = 1'b1;
    logic [7:0] data_in = 8'h00;
    wire  [7:0] data_out;
    logic       hblank = 1'b0, vsync = 1'b0;

    wire        disp_on;
    wire [7:0]  pitch;
    wire [15:0] part_sad [0:3];
    wire [9:0]  part_len [0:3];
    wire [14:0] cursor_addr;
    wire [3:0]  cursor_dot;
    wire        cursor_en, cursor_blink_en;
    wire [4:0]  cursor_top, cursor_bottom;
    wire [5:0]  cursor_rate;
    wire [1:0]  zoom_disp;
    wire [7:0]  unk_cmd, unk_count;

    pc98_gdc dut (
        .clk(clk), .reset(reset),
        .cs(cs), .a1(a1), .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(data_out),
        .hblank(hblank), .vsync(vsync),
        .disp_on(disp_on), .pitch(pitch),
        .part_sad(part_sad), .part_len(part_len),
        .cursor_addr(cursor_addr), .cursor_dot(cursor_dot),
        .cursor_en(cursor_en), .cursor_blink_en(cursor_blink_en),
        .cursor_top(cursor_top), .cursor_bottom(cursor_bottom),
        .cursor_rate(cursor_rate), .zoom_disp(zoom_disp),
        .unk_cmd(unk_cmd), .unk_count(unk_count)
    );

    int errors = 0;

    task automatic wr(input logic odd, input logic [7:0] d);
        @(posedge clk);
        cs = 1'b1; a1 = odd; data_in = d; io_write_n = 1'b0;
        @(posedge clk);
        io_write_n = 1'b1; cs = 1'b0;
        @(posedge clk);
    endtask

    task automatic cmd(input logic [7:0] c);  wr(1'b1, c); endtask
    task automatic par(input logic [7:0] p);  wr(1'b0, p); endtask

    task automatic want(input string what, input int got, input int exp);
        if (got !== exp) begin
            $display("FAIL %-34s got %0d (%04x), want %0d (%04x)",
                     what, got, got, exp, exp);
            errors++;
        end else
            $display("ok   %-34s %0d (%04x)", what, got, got);
    endtask

    initial begin
        repeat (8) @(posedge clk);
        reset = 1'b0;
        repeat (4) @(posedge clk);

        // ---- START and STOP ------------------------------------------------
        cmd(8'h0D);  want("START -> disp_on", disp_on, 1);
        cmd(8'h0C);  want("STOP  -> disp_on", disp_on, 0);
        cmd(8'h6B);  want("START_ (0x6B)",    disp_on, 1);
        cmd(8'h05);  want("STOP_  (0x05)",    disp_on, 0);
        cmd(8'h0D);

        // ---- PITCH ---------------------------------------------------------
        cmd(8'h47); par(8'd80);
        want("PITCH = 80", pitch, 80);

        // ---- ZOOM is 0x46, not 0x06 ----------------------------------------
        cmd(8'h46); par(8'h03);
        want("ZOOM (0x46) = 3", zoom_disp, 3);

        // ---- the PRAM: 0x70 writes from offset 0 ---------------------------
        // Partition 0: SAD 0x0000, LEN 0x0190 -> 25 lines ((0x190 & 0x3FFF)>>4)
        // Partition 1: SAD 0x07D0, LEN 0x00F0 -> 15 lines
        cmd(8'h70);
        par(8'h00); par(8'h00); par(8'h90); par(8'h01);
        par(8'hD0); par(8'h07); par(8'hF0); par(8'h00);
        want("part0 SAD raw",             part_sad[0], 16'h0000);
        want("part0 LEN lines",           part_len[0], 16'h0190 >> 4);
        // RAW: the graphics side shifts it, the text side masks it to 12
        // bits, and neither belongs in the GDC. See its header.
        want("part1 SAD raw",             part_sad[1], 16'h07D0);
        want("part1 LEN lines",           part_len[1], 16'h00F0 >> 4);

        // ---- 0x78 is the SAME PRAM, from offset 8 --------------------------
        // If it were a separate register bank this would not land in
        // partition 2.
        cmd(8'h78);
        par(8'h34); par(8'h12); par(8'h00); par(8'h02);
        want("0x78 lands in partition 2 SAD", part_sad[2], 16'h1234);
        want("0x78 partition 2 LEN lines",    part_len[2], 16'h0200 >> 4);

        // ---- a PRAM write from a non-zero nibble ----------------------------
        // 0x74 starts at PRAM offset 4 -- partition 1.
        cmd(8'h74);
        par(8'hFF); par(8'h00); par(8'h10); par(8'h00);
        want("0x74 starts at partition 1", part_sad[1], 16'h00FF);

        // ---- a command cuts a parameter run short --------------------------
        // Two of the four parameters, then a new command. The third and fourth
        // must NOT land: a real 7220 abandons the run.
        cmd(8'h70);
        par(8'hAA); par(8'hBB);
        cmd(8'h47); par(8'd40);
        want("PITCH after a cut-short run", pitch, 40);
        want("partition 0 SAD took the two", part_sad[0], 16'hBBAA);

        // ---- CSRW / CSRFORM -------------------------------------------------
        cmd(8'h49); par(8'h21); par(8'h43); par(8'h05);
        want("cursor EAD low bits",  cursor_addr[4:0],  5'h01);
        want("cursor dot address",   cursor_dot,        4'h0);
        cmd(8'h4B); par(8'hC1); par(8'h20); par(8'h88);
        want("cursor enable",        cursor_en,         1);
        want("cursor blink enable",  cursor_blink_en,   1);
        want("cursor top line",      cursor_top,        5'h01);
        want("cursor bottom line",   cursor_bottom,     5'h11);

        // ---- the status register --------------------------------------------
        // np2kai gdc_i60: bit 7 always, bit 6 hblank, bit 5 vsync, bit 2 empty.
        // The mock this replaced had bit 7 CLEAR.
        hblank = 1'b0; vsync = 1'b0; @(posedge clk);
        cs = 1'b1; a1 = 1'b0; io_read_n = 1'b0; @(posedge clk);
        want("status, quiet raster", data_out, 8'h84);
        hblank = 1'b1; vsync = 1'b1; @(posedge clk);
        want("status, hblank+vsync", data_out, 8'hE4);
        io_read_n = 1'b1; cs = 1'b0;

        // ---- the guard on the scope decision --------------------------------
        // The drawing processor is not implemented; asking for it has to be
        // visible, because "PC-98 software draws through the GRCG" is a
        // judgement and this is what falsifies it.
        want("no unknown commands yet", unk_count, 0);
        cmd(8'h6C);                        // VECTE -- a drawing command
        want("VECTE counted as unknown",  unk_count, 1);
        want("VECTE recorded",            unk_cmd,   8'h6C);
        cmd(8'h68);                        // TEXTE
        want("TEXTE counted too",         unk_count, 2);
        // ...and a command that IS implemented must not be counted.
        cmd(8'h0D);
        want("START not counted unknown",  unk_count, 2);
        cmd(8'hE0);                        // CSRR -- known, zero parameters
        want("CSRR not counted unknown",   unk_count, 2);

        if (errors == 0) $display("PASS tb_pc98_gdc");
        else             $display("FAILED tb_pc98_gdc: %0d", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("FAILED tb_pc98_gdc: timeout");
        $finish;
    end

endmodule

`default_nettype wire
