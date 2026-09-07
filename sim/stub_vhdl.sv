// Stubs for the CHIPSET-level testbench. uart_16750 and dpram are VHDL
// (uart/uart_16750.vhd, common/bram.vhd), which this Verilator cannot read.
// Neither has anything to do with the external-access port under test.
`default_nettype none

module uart_16750 (
    input  wire        CLK, RST, BAUDCE, CS, WR, RD,
    input  wire  [2:0] A,
    input  wire  [7:0] DIN,
    output wire  [7:0] DOUT,
    input  wire        RCLK,
    output wire        BAUDOUTN,
    output wire        RTSN, DTRN,
    input  wire        CTSN, DSRN, DCDN, RIN, SIN,
    output wire        SOUT, INT
);
    wire _u = &{1'b0, CLK, RST, BAUDCE, CS, WR, RD, A, DIN, RCLK,
                CTSN, DSRN, DCDN, RIN, SIN, 1'b0};
    assign DOUT = 8'd0;
    assign {BAUDOUTN, RTSN, DTRN, SOUT, INT} = 5'd0;
endmodule

module dpram #(parameter ADDRWIDTH = 12, parameter DATAWIDTH = 16) (
    input  wire                    clock,
    input  wire [ADDRWIDTH-1:0]    address_a, address_b,
    input  wire [DATAWIDTH-1:0]    data_a, data_b,
    input  wire                    wren_a, wren_b,
    output reg  [DATAWIDTH-1:0]    q_a, q_b
);
    reg [DATAWIDTH-1:0] mem [(1<<ADDRWIDTH)-1:0];
    always @(posedge clock) begin
        if (wren_a) mem[address_a] <= data_a;
        q_a <= mem[address_a];
        if (wren_b) mem[address_b] <= data_b;
        q_b <= mem[address_b];
    end
endmodule

`default_nettype wire
