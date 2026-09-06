// ============================================================================
// PC-98 for the Analogue Pocket — 64 KB RAM stub (Phase 2)
// ----------------------------------------------------------------------------
// Conventional-memory stub at 0x00000-0x0FFFF. The full 640 KB (plus
// expansion) moves to the Pocket's SDRAM in a later phase; this block-RAM
// version is enough for the BIOS to run its early POST and set up the IVT.
//
// 65536 x 8 = 512 Kbit = 50 M10K blocks.
// ============================================================================

`default_nettype none

module ram64k (
    input  wire        clk74,

    // CPU port (address latched in the CPU domain, registered read data)
    input  wire        rd_en,      // sample read data (cpu cycle rate)
    input  wire [15:0] addr,
    input  wire        wr_en,
    input  wire [7:0]  wdata,
    output reg  [7:0]  q
);

(* ramstyle = "M10K" *) reg [7:0] mem [0:65535];

always @(posedge clk74) begin
    if (wr_en)
        mem[addr] <= wdata;
    if (rd_en)
        q <= mem[addr];
end

endmodule

`default_nettype wire
