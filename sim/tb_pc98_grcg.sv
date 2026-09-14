//
// tb_pc98_grcg -- the three operations, against np2kai's own expressions.
//
// The GRCG is four lines of arithmetic and a counter, and every one of the
// four is easy to get backwards:
//
//   * the plane mask is SET MEANS SKIP
//   * TDW throws the written byte away
//   * RMW uses it as a mask, not as data
//   * TCR returns a MATCH mask, so it inverts
//
// Each is asserted here against mem/memvram.c's macro, not against a reading
// of it.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_grcg;

    localparam real HALF_NS = 500.0 / 42.954545;
    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic       reset = 1'b1;
    logic       cs_mode = 1'b0, cs_tile = 1'b0;
    logic       io_read_n = 1'b1, io_write_n = 1'b1;
    logic [7:0] io_data_in = 8'h00;
    wire  [7:0] io_data_out;
    wire        active, rmw;
    wire  [3:0] plane_mask;
    logic [7:0] cpu_wdata = 8'h00;
    logic [7:0] plane_rdata [0:3];
    wire  [7:0] plane_wdata [0:3];
    wire  [3:0] plane_we;
    wire  [7:0] cpu_rdata;

    pc98_grcg dut (
        .clk(clk), .reset(reset),
        .cs_mode(cs_mode), .cs_tile(cs_tile),
        .io_read_n(io_read_n), .io_write_n(io_write_n),
        .io_data_in(io_data_in), .io_data_out(io_data_out),
        .active(active), .rmw(rmw), .plane_mask(plane_mask),
        .cpu_wdata(cpu_wdata), .plane_rdata(plane_rdata),
        .plane_wdata(plane_wdata), .plane_we(plane_we),
        .cpu_rdata(cpu_rdata)
    );

    int errors = 0;

    task automatic io_wr(input logic mode_port, input logic [7:0] d);
        @(posedge clk);
        cs_mode = mode_port; cs_tile = ~mode_port;
        io_data_in = d; io_write_n = 1'b0;
        @(posedge clk);
        io_write_n = 1'b1; cs_mode = 1'b0; cs_tile = 1'b0;
        @(posedge clk);
    endtask

    task automatic want(input string what, input int got, input int exp);
        if (got !== exp) begin
            $display("FAIL %-38s got %02x, want %02x", what, got, exp);
            errors++;
        end else
            $display("ok   %-38s %02x", what, got);
    endtask

    // Four tile bytes, written the way software does: mode first (which
    // resets the counter), then four writes to 0x7E.
    task automatic set_tiles(input logic [7:0] m,
                             input logic [7:0] t0, t1, t2, t3);
        io_wr(1'b1, m);
        io_wr(1'b0, t0); io_wr(1'b0, t1); io_wr(1'b0, t2); io_wr(1'b0, t3);
    endtask

    initial begin
        plane_rdata[0] = 8'h00; plane_rdata[1] = 8'h00;
        plane_rdata[2] = 8'h00; plane_rdata[3] = 8'h00;
        repeat (8) @(posedge clk);
        reset = 1'b0;
        repeat (4) @(posedge clk);

        // ---- off ------------------------------------------------------
        io_wr(1'b1, 8'h00);
        want("mode reads back",        io_data_out, 8'h00);
        want("GRCG off: no plane written", plane_we, 4'b0000);

        // ---- TDW: the tile lands, the data does not --------------------
        set_tiles(8'h80, 8'h11, 8'h22, 8'h44, 8'h88);
        cpu_wdata = 8'hFF; @(posedge clk);
        want("TDW active",             active, 1);
        want("TDW not rmw",            rmw, 0);
        want("TDW all four written",   plane_we, 4'b1111);
        want("TDW plane0 = tile0",     plane_wdata[0], 8'h11);
        want("TDW plane1 = tile1",     plane_wdata[1], 8'h22);
        want("TDW plane2 = tile2",     plane_wdata[2], 8'h44);
        want("TDW plane3 = tile3",     plane_wdata[3], 8'h88);
        // the written byte is discarded -- change it, nothing moves
        cpu_wdata = 8'h00; @(posedge clk);
        want("TDW ignores the data",   plane_wdata[0], 8'h11);

        // ---- the plane mask: SET MEANS SKIP ----------------------------
        // 0x85 = on, TDW, mask bits 0 and 2 set -> planes 0 and 2 SKIPPED
        set_tiles(8'h85, 8'hAA, 8'hBB, 8'hCC, 8'hDD);
        want("mask 0101 -> we 1010",   plane_we, 4'b1010);

        // ---- RMW: the data is a mask between tile and what is there -----
        // np2kai: plane = (plane & ~data) | (data & tile)
        set_tiles(8'hC0, 8'hFF, 8'h00, 8'hF0, 8'h0F);
        plane_rdata[0] = 8'h55; plane_rdata[1] = 8'h55;
        plane_rdata[2] = 8'h55; plane_rdata[3] = 8'h55;
        cpu_wdata = 8'h3C; @(posedge clk);
        want("RMW is rmw",             rmw, 1);
        want("RMW plane0",             plane_wdata[0],
             (8'h55 & ~8'h3C) | (8'h3C & 8'hFF));
        want("RMW plane1",             plane_wdata[1],
             (8'h55 & ~8'h3C) | (8'h3C & 8'h00));
        want("RMW plane2",             plane_wdata[2],
             (8'h55 & ~8'h3C) | (8'h3C & 8'hF0));
        want("RMW plane3",             plane_wdata[3],
             (8'h55 & ~8'h3C) | (8'h3C & 8'h0F));

        // ---- TCR: a MATCH mask, so it inverts ---------------------------
        // Every plane equal to its tile -> every bit matches -> 0xFF.
        set_tiles(8'h80, 8'h12, 8'h34, 8'h56, 8'h78);
        plane_rdata[0] = 8'h12; plane_rdata[1] = 8'h34;
        plane_rdata[2] = 8'h56; plane_rdata[3] = 8'h78;
        @(posedge clk);
        want("TCR all planes match",   cpu_rdata, 8'hFF);
        // one plane differs in one bit -> that bit goes 0
        plane_rdata[1] = 8'h35;
        @(posedge clk);
        want("TCR one bit differs",    cpu_rdata, 8'hFE);
        // ...and masking that plane out brings the bit back
        set_tiles(8'h82, 8'h12, 8'h34, 8'h56, 8'h78);
        plane_rdata[1] = 8'h35;
        @(posedge clk);
        want("TCR masked plane ignored", cpu_rdata, 8'hFF);

        // ---- the tile counter resets on a mode write --------------------
        // Three tile bytes, then a mode write, then one more: the last must
        // land in tile 0, not tile 3.
        io_wr(1'b1, 8'h80);
        io_wr(1'b0, 8'h01); io_wr(1'b0, 8'h02); io_wr(1'b0, 8'h03);
        io_wr(1'b1, 8'h80);          // mode write -> counter back to 0
        io_wr(1'b0, 8'hEE);
        cpu_wdata = 8'h00; @(posedge clk);
        want("mode write reset the counter", plane_wdata[0], 8'hEE);
        want("  ...and tile1 kept its value", plane_wdata[1], 8'h02);

        if (errors == 0) $display("PASS tb_pc98_grcg");
        else             $display("FAILED tb_pc98_grcg: %0d", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("FAILED tb_pc98_grcg: timeout");
        $finish;
    end

endmodule

`default_nettype wire
