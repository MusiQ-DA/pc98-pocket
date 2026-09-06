// ============================================================================
// PC-98 for the Analogue Pocket — Font ROM (Phase 3)
// ----------------------------------------------------------------------------
// Stores the first 64 KB of FONT.ROM (np2-compatible dump):
//   0x0000-0x07FF  ANK 8x8   (256 chars x 8 bytes)   [unused in phase 3]
//   0x0800-0x17FF  ANK 8x16  (codes 0x00-0xFF, 16 bytes each)
//   0x1800-        kanji blocks (JIS block-ordered; rendered in a later phase)
//
// Physically a 32768 x 16 simple dual-port RAM (registered 16-bit read, the
// byte-lane mux sits outside the RAM so inference stays clean):
// 512 Kbit = 50 M10K blocks.
// ============================================================================

`default_nettype none

module font_rom (
    input  wire        clk74,

    // loader write port (16-bit words, little-endian file order)
    input  wire        wr_en,
    input  wire [14:0] wr_waddr,   // word index
    input  wire [15:0] wr_data,

    // video read port (byte address; 1-cycle registered read)
    input  wire [15:0] rd_addr,    // byte address into FONT.ROM
    output wire [7:0]  rd_data
);

(* ramstyle = "M10K" *) reg [15:0] mem  [0:32767];
reg                   [15:0] q16;

always @(posedge clk74) begin
    if (wr_en)
        mem[wr_waddr] <= wr_data;
    q16 <= mem[rd_addr[15:1]];
end

assign rd_data = rd_addr[0] ? q16[15:8] : q16[7:0];

endmodule

`default_nettype wire
