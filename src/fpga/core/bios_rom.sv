// ============================================================================
// PC-98 for the Analogue Pocket — BIOS ROM (Phase 2)
// ----------------------------------------------------------------------------
// 96 KB byte-addressed BIOS window (0xE8000-0xFFFFF), physically organised as
// 49152 x 16-bit words to match the loader's 16-bit stream.
//
//   port A (loader, clk_74a): 16-bit writes from the data slot stream
//   port B (CPU):             8-bit reads, registered (infers M10K)
//
// 49152 x 16 = 768 Kbit = 75 M10K blocks (of 308 available).
// ============================================================================

`default_nettype none

module bios_rom (
    input  wire        clk74,

    // loader write port
    input  wire        wr_en,
    input  wire [14:0] wr_waddr,   // word index (0..49151)
    input  wire [15:0] wr_data,

    // CPU read port (address in the CPU domain, registered read data)
    input  wire [14:0] rd_waddr,
    input  wire        rd_selhi,   // 0 = low byte, 1 = high byte
    output reg  [7:0]  rd_data
);

(* ramstyle = "M10K" *) reg [15:0] mem [0:49151];

always @(posedge clk74) begin
    if (wr_en)
        mem[wr_waddr] <= wr_data;
    rd_data <= rd_selhi ? mem[rd_waddr][7:0] : mem[rd_waddr][15:8];
end

endmodule

`default_nettype wire
