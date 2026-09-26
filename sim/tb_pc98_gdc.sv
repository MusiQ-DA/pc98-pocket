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
    wire [15:0] cursor_addr;
    wire [3:0]  cursor_dot;
    wire        cursor_en, cursor_blink_en;
    wire [4:0]  cursor_top, cursor_bottom;
    wire [5:0]  cursor_rate;
    wire [7:0]  csr_wr_count;
    wire [31:0] csr_trace;
    wire        draw_req, draw_busy;
    wire [7:0]  draw_op;
    wire [31:0] draw_snap [0:4];
    logic       srv_done = 1'b0;
    logic [7:0] st_v;

    // Peek a parameter byte, the way the engine's snapshot does.
    function [7:0] para_rd(input int idx);
        para_rd = dut.para[idx];
    endfunction

    // One status read: set the port up, sample after the clock.
    task automatic status_rd(output logic [7:0] v);
        cs = 1'b1; a1 = 1'b0; io_read_n = 1'b0;
        @(posedge clk);
        v = data_out;
        io_read_n = 1'b1; cs = 1'b0;
    endtask
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
        .csr_wr_count(csr_wr_count), .csr_trace(csr_trace),
        .draw_req(draw_req), .draw_op(draw_op), .draw_busy(draw_busy),
        .srv_done_stb(srv_done), .draw_snap(draw_snap),
        .unk_cmd(unk_cmd), .unk_count(unk_count)
    );

    int errors = 0;

    task automatic wr(input logic odd, input logic [7:0] d);
        @(posedge clk);
        cs = 1'b1; a1 = odd; data_in = d; io_write_n = 1'b0;
        // The real bus holds io_write_n low ~11 clk of the 42.95 MHz clock,
        // not one -- a level-sensitive write would drop the byte into every
        // parameter slot the strobe spans. The GDC commits it once, on the
        // strobe's rising edge.
        repeat (11) @(posedge clk);
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

        // ---- the CSRFORM power-on values -----------------------------------
        // The BIOS's boot sends CSRFORM as ONE byte (the enable with TEXT_LR)
        // and never the full three, so the form the cursor draws with is the
        // one the chip woke with: np2kai's gdc_reset seeds the MASTER to
        // {P1=0F, P2=C0, P3=7B} -- top 0, bottom 15, a full block, and P2
        // bit5 CLEAR so it blinks (np2: a set bit is "does not blink").
        // Reset-zero made bottom 0: a one-line sliver at the top of the
        // right cell, which is "it blinks, but small and in the wrong
        // place" on hardware.
        want("reset cursor disabled",     cursor_en,         0);
        want("reset cursor blinks (P2 b5)", cursor_blink_en, 1);
        want("reset cursor top 0",        cursor_top,        5'd0);
        want("reset cursor bottom 15",    cursor_bottom,     5'd15);
        want("no CSRFORM traced at reset", csr_trace,        32'h0);

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
        // The address is a plain little-endian word (np2kai maketext:
        // LOADINTELWORD(para + GDC_CSRW)); the manual's interleaved reading
        // drops bits 7-5 of byte 0 and scrambles the cell -- the bug that
        // made the cursor invisible on hardware.
        cmd(8'h49); par(8'h21); par(8'h43); par(8'h05);
        want("cursor EAD, plain LE word", cursor_addr, 16'h4321);
        want("cursor dot address",        cursor_dot,  4'h0);
        // CSRFORM: enable P1 bit7, TOP P2 bits 4-0 (P1's low bits are the
        // text row height, not the top -- maketext reads them as TEXT_LR),
        // bottom P3 bits 7-3, and P2 bit 5 is "does NOT blink" -- the driver
        // carries 0x00 (blink, top 0) or 0x20 (solid, top 0) in [0x53D] as
        // exactly that byte.
        cmd(8'h4B); par(8'hC1); par(8'h20); par(8'h88);
        want("cursor enable",        cursor_en,         1);
        want("cursor solid (P2 bit5)", cursor_blink_en, 0);
        want("cursor top line (P2)", cursor_top,        5'd0);
        want("cursor bottom line",   cursor_bottom,     5'h11);
        cmd(8'h4B); par(8'hC1); par(8'h05); par(8'h88); // top=5, blinking
        want("cursor blinking (P2 bit5 clear)", cursor_blink_en, 1);
        want("cursor top from P2 low bits", cursor_top, 5'd5);
        want("CSR command count", csr_wr_count, 8'd3);  // 1x CSRW + 2x CSRFORM
        want("CSRFORM trace bytes", csr_trace[23:0], 24'hC10588);
        want("CSRFORM trace count", csr_trace[27:24], 4'd3);

        // ---- the status register --------------------------------------------
        // bit 6 hblank, bit 5 vsync, bit 2 FIFO empty, and bit 7 CLEAR.
        //
        // Bit 7 is LIGHT PEN DETECT and this machine has no light pen. It was
        // 1 here, copied from np2kai's unconditional 0x80, and the BIOS hung
        // on it: F305E reads the status, sees the pen, issues LPRD at F3074
        // and waits for DRDY, which never arrives because nothing queues
        // read-back data -- then F3097 starts the whole sequence again. See
        // pc98_gdc.sv. This bench asserted the value that produced the hang,
        // which is why nothing caught it.
        hblank = 1'b0; vsync = 1'b0; @(posedge clk);
        cs = 1'b1; a1 = 1'b0; io_read_n = 1'b0; @(posedge clk);
        want("status, quiet raster (no light pen)", data_out, 8'h04);
        hblank = 1'b1; vsync = 1'b1; @(posedge clk);
        want("status, hblank+vsync", data_out, 8'h64);
        io_read_n = 1'b1; cs = 1'b0;

        // ---- the drawing server's handshake ---------------------------------
        // VECTE/TEXTE are EXECUTE-class now: latched with a snapshot of the
        // vector parameters, throttled (the FIFO-empty status bit clears)
        // until the engine's done edge retires them and runs the vector
        // reset. Anything ELSE drawing-shaped stays counted as unknown --
        // the scope guard this always was.
        want("no unknown commands yet", unk_count, 0);
        cmd(8'h49); par(8'h34); par(8'h12); par(8'h00); // CSRW: EAD 0x1234
        cmd(8'h4C);                                      // VECTW, 11 params
        par(8'h49); par(8'h0A); par(8'h00);              //  ope=0x49, DC=10
        par(8'h0A); par(8'h00);                          //  D  = 10
        par(8'h0A); par(8'h00);                          //  D2 = 10
        par(8'h14); par(8'h00);                          //  D1 = 20
        par(8'h00); par(8'h00);                          //  DM = 0
        cmd(8'h6C);                                      // VECTE
        want("VECTE latched for the server", draw_req, 1);
        want("VECTE opcode carried",        draw_op,  8'h6C);
        want("snapshot ope",                draw_snap[0][7:0],  8'h49);
        want("snapshot DC",                 draw_snap[0][23:8], 16'h000A);
        want("snapshot D1",                 {draw_snap[2][7:0], draw_snap[1][31:24]},
                                                          16'h0014);
        want("snapshot CSRW low",           draw_snap[2][31:24], 8'h34);
        want("snapshot CSRW mid",           draw_snap[3][7:0],   8'h12);
        // FIFO empty clears while pending (the throttle).
        cs = 1'b1; a1 = 1'b0; io_read_n = 1'b0; @(posedge clk);
        want("FIFO empty clears while pending", data_out & 8'h04, 8'h00);
        io_read_n = 1'b1; cs = 1'b0;
        cmd(8'h6C);                        // a second EXECUTE while pending
        want("second EXECUTE while pending is unknown", unk_count, 1);
        want("second EXECUTE recorded", unk_cmd, 8'h6C);
        @(posedge clk);
        srv_done = 1; @(posedge clk);      // one full clock of done
        srv_done = 0; @(posedge clk);
        @(posedge clk);                    // let the busy hold cycle pass
        @(posedge clk);
        want("done retires the request", draw_req, 0);
        want("vector reset: DC low",  para_rd(33), 8'h00);
        want("vector reset: D low",   para_rd(35), 8'h08);
        want("vector reset: D2 low",  para_rd(37), 8'h08);
        want("vector reset: D1 high", para_rd(40), 8'hFF);
        status_rd(st_v);
        want("FIFO empty returns",    st_v & 8'h04, 8'h04);

        cmd(8'h6D);                        // an unassigned drawing opcode
        want("unknown stays counted", unk_count, 2);
        want("unknown recorded",      unk_cmd,   8'h6D);
        // ...and a command that IS implemented must not be counted.
        cmd(8'h0D);
        want("START not counted unknown",  unk_count, 2);
        cmd(8'hE0);                        // CSRR -- known, zero parameters
        want("CSRR not counted unknown",   unk_count, 2);

        // ---- the read-back FIFO: CSRR and LPEN answer with bytes ---------
        // CSRR queues five off CSRW (the high address byte masked to two
        // bits, then two zeros); LPEN queues three zeros -- no pen fitted.
        // DRDY (status bit 0) sets while the queue holds data, a data-port
        // read returns the head and pops it AFTER the strobe ends, and bit
        // 7 (pen detect) never sets, so the BIOS's F305E exit stays the
        // path a penless machine takes.
        // Drain whatever the earlier CSRR test queued (five bytes of the
        // old CSRW) before issuing a fresh one: the FIFO is only eight deep.
        for (int d = 0; d < 5; d++) begin
            cs = 1'b1; a1 = 1'b1; io_read_n = 1'b0;
            @(posedge clk);
            io_read_n = 1'b1; cs = 1'b0; @(posedge clk);
        end
        cmd(8'h49); par(8'hCD); par(8'hAB); par(8'h06);  // CSRW = 0x06ABCD
        cmd(8'hE0);                                        // CSRR
        status_rd(st_v);
        want("CSRR sets DRDY", st_v & 8'h01, 8'h01);
        want("and bit 7 stays clear", st_v & 8'h80, 8'h00);
        cs = 1'b1; a1 = 1'b1; io_read_n = 1'b0;
        @(posedge clk);
        want("CSRR byte 0 (EAD low)", data_out, 8'hCD);
        io_read_n = 1'b1; @(posedge clk); io_read_n = 1'b0;
        @(posedge clk);
        want("CSRR byte 1 (EAD mid)", data_out, 8'hAB);
        io_read_n = 1'b1; @(posedge clk); io_read_n = 1'b0;
        @(posedge clk);
        want("CSRR byte 2 (EAD high & 3)", data_out, 8'h02);
        io_read_n = 1'b1; @(posedge clk); io_read_n = 1'b0;
        @(posedge clk);
        want("CSRR byte 3 (zero)", data_out, 8'h00);
        io_read_n = 1'b1; @(posedge clk); io_read_n = 1'b0;
        @(posedge clk);
        want("CSRR byte 4 (zero)", data_out, 8'h00);
        io_read_n = 1'b1; cs = 1'b0; @(posedge clk);
        status_rd(st_v);
        want("drained: DRDY falls", st_v & 8'h01, 8'h00);
        want("and the status reads again", st_v & 8'h04, 8'h04);

        cmd(8'hC0);                                        // LPEN
        status_rd(st_v);
        want("LPEN sets DRDY", st_v & 8'h01, 8'h01);
        cs = 1'b1; a1 = 1'b1; io_read_n = 1'b0;
        @(posedge clk);
        want("LPEN byte 0 (no pen: zero)", data_out, 8'h00);
        io_read_n = 1'b1; @(posedge clk); io_read_n = 1'b0;
        @(posedge clk);
        want("LPEN byte 1 (zero)", data_out, 8'h00);
        io_read_n = 1'b1; @(posedge clk); io_read_n = 1'b0;
        @(posedge clk);
        want("LPEN byte 2 (zero)", data_out, 8'h00);
        io_read_n = 1'b1; cs = 1'b0; @(posedge clk);
        status_rd(st_v);
        want("LPEN drained too", st_v & 8'h01, 8'h00);

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
