// Stub for the CHIPSET-level testbench. The real sound/saa1099.sv uses
// unpacked-array initialisers this Verilator build rejects, and the ext-port
// question has nothing to do with audio.
`default_nettype none
module saa1099 (
    input  wire       clk_sys,
    input  wire       ce,
    input  wire       rst_n,
    input  wire       cs_n,
    input  wire       a0,
    input  wire       wr_n,
    input  wire [7:0] din,
    output wire [7:0] out_l,
    output wire [7:0] out_r
);
    wire _unused = &{1'b0, clk_sys, ce, rst_n, cs_n, a0, wr_n, din, 1'b0};
    assign out_l = 8'd0;
    assign out_r = 8'd0;
endmodule
`default_nettype wire
