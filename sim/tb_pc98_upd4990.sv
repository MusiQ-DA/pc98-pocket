//
// tb_pc98_upd4990 -- the calendar read exactly as bios.rom's INT 1Ch AH=0
// (FD80:0523) performs it: command 3 (time read) and command 1 (register
// shift) sent serially through parallel mode 7, then 48 samples of port
// 0x33 bit 0, each followed by a CLK pulse (OUT 20h,17h) and a DATA write
// (OUT 20h,07h). The six bytes land LSB first, seconds first, as the BIOS
// stores them at ES:BX+5..0.
//
// np21w io/upd4990.c steps pos BEFORE fetching cdat on CLK, and sets
// parallel BEFORE testing it on DATA. The RTL once did both the other way
// round: every sample after the first read a bit the reader's own DATA
// write had just cleared, INT 1Ch returned seconds 00/01 and zeros, and
// MS-DOS 6.2's two-second startup wait spun forever whenever the start
// second read 00. Cold (first read after reset) and warm reads both checked.
//
`default_nettype none
`timescale 1ns/1ps

module tb_pc98_upd4990;
    logic clk = 0, rst = 1, stb = 0;
    logic [7:0] d = 8'h00;
    logic cdat;
    logic [47:0] t;
    always #10 clk = ~clk;

    pc98_upd4990 dut (.clk(clk), .rst(rst), .wr_stb(stb), .wr_data(d),
                      .time_in(t), .cdat(cdat));

    int errors = 0;

    task automatic out20(input logic [7:0] v);
        @(posedge clk); d <= v; stb <= 1'b1;
        @(posedge clk); stb <= 1'b0;
        repeat (3) @(posedge clk);
    endtask

    // FD80:05BE -- four command bits LSB first, then CLK low and an STB pulse.
    task automatic sendcmd(input logic [3:0] c);
        logic [7:0] al;
        for (int i = 0; i < 4; i++) begin
            al = c[i] ? 8'h27 : 8'h07;
            out20(al);
            al |= 8'h10;
            out20(al);
        end
        al &= 8'hEF; out20(al);
        al |= 8'h08; out20(al);
        al &= 8'hF7; out20(al);
    endtask

    task automatic bios_read(output logic [7:0] b [6]);
        logic [7:0] ah;
        sendcmd(4'd3);
        sendcmd(4'd1);
        for (int si = 5; si >= 0; si--) begin
            ah = 8'h00;
            for (int k = 0; k < 8; k++) begin
                ah = {cdat, ah[7:1]};       // IN 33h; SHR AL,1; RCR AH,1
                out20(8'h17);
                out20(8'h07);
            end
            b[si] = ah;
        end
    endtask

    task automatic check(input logic [47:0] tv, input string what);
        logic [7:0] b [6];
        t = tv;
        bios_read(b);
        if ({b[5], b[4], b[3], b[2], b[1], b[0]} !== tv) begin
            errors++;
            $display("  %s: got %h %h %h %h %h %h want %h", what,
                     b[0], b[1], b[2], b[3], b[4], b[5], tv);
        end
    endtask

    initial begin
        $display("=== uPD4990 BIOS calendar read ===");
        repeat (3) @(posedge clk);
        rst = 1'b0;
        // {sec, min, hour, day, (month<<4)|wday, year}
        check({8'h17, 8'h41, 8'h01, 8'h13, 8'hB4, 8'h26}, "cold read");
        check({8'h00, 8'h59, 8'h23, 8'h31, 8'hC3, 8'h99}, "second 00");
        check({8'h59, 8'h00, 8'h00, 8'h01, 8'h16, 8'h00}, "second 59");
        check({8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF}, "all ones");
        check({8'hA5, 8'h5A, 8'hC3, 8'h3C, 8'h81, 8'h18}, "pattern");
        $display("%s tb_pc98_upd4990  (errors %0d)", errors ? "FAIL" : "PASS", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end
endmodule

`default_nettype wire
