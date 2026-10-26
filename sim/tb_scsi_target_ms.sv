// tb_scsi_target_ms -- the ROM's MODE SENSE exchange against pc98_scsi +
// tb_scsi_target, at bus level, to debug the boot bench quickly.
`default_nettype none
`timescale 1ns/1ps
module tb_scsi_target_ms;
    logic clk = 0;
    always #10 clk = ~clk;
    logic rst = 1;
    logic cs = 0, io_read_n = 1, io_write_n = 1;
    logic [1:0] a1a2 = 0;
    logic [7:0] data_in = 0;
    wire  [7:0] data_out;
    wire req; wire [7:0] cb;
    wire [4:0] ra; wire rwe; wire [7:0] rwd, rrd;
    wire [12:0] ba; wire bwe; wire [7:0] bwd, brd;
    wire [7:0] aux, st; wire auxwe, stwe, rclr, wclr;
    int n;
    pc98_scsi u (.clk(clk), .rst(rst), .cs(cs), .a1a2(a1a2),
        .io_read_n(io_read_n), .io_write_n(io_write_n), .data_in(data_in),
        .data_out(data_out), .read_select(), .cmd_req(req), .cmd_byte(cb),
        .mg_reg_addr(ra), .mg_reg_we(rwe), .mg_reg_wdata(rwd), .mg_reg_rdata(rrd),
        .mg_buf_addr(ba), .mg_buf_we(bwe), .mg_buf_wdata(bwd), .mg_buf_rdata(brd),
        .mg_auxstatus(aux), .mg_auxstatus_we(auxwe), .mg_scsistatus(st),
        .mg_scsistatus_we(stwe), .mg_rdptr_clr(rclr), .mg_wrptr_clr(wclr));
    tb_scsi_target #(.MAX_BYTES(4096), .LATENCY(20)) t (.clk(clk), .cmd_req(req),
        .reg_addr(ra), .reg_we(rwe), .reg_wdata(rwd), .reg_rdata(rrd),
        .buf_addr(ba), .buf_we(bwe), .buf_wdata(bwd), .buf_rdata(brd),
        .aux(aux), .aux_we(auxwe), .status(st), .status_we(stwe),
        .rdptr_clr(rclr), .wrptr_clr(wclr), .n_cmds(n));

    task automatic io_wr(input [1:0] port, input [7:0] v);
        a1a2 = port; cs = 1; data_in = v; io_write_n = 0;
        repeat (4) @(posedge clk);
        io_write_n = 1; @(posedge clk); cs = 0; repeat (8) @(posedge clk);
    endtask
    task automatic io_rd(input [1:0] port, output [7:0] v);
        a1a2 = port; cs = 1; io_read_n = 0;
        repeat (3) @(posedge clk); v = data_out;
        repeat (1) @(posedge clk); io_read_n = 1; @(posedge clk); cs = 0;
        repeat (8) @(posedge clk);
    endtask

    logic [7:0] v;
    initial begin
        repeat (5) @(posedge clk); rst = 0;
        repeat (50) @(posedge clk);
        io_wr(0, 8'h03);
        foreach (v[i]) ;
        io_wr(1, 8'h1A); io_wr(1, 8'h08); io_wr(1, 8'h04); io_wr(1, 0); io_wr(1, 36); io_wr(1, 0);
        io_wr(0, 8'h18); io_wr(1, 8'h20);
        do io_rd(0, v); while (!v[7]);
        io_wr(0, 8'h17); io_rd(1, v); $display("status %02x", v);
        for (int i = 0; i < 12; i++) begin io_rd(3, v); $write(" %02x", v); end
        $display("");
        $finish;
    end
endmodule
`default_nettype wire
