// ============================================================================
// PC-98 for the Analogue Pocket — TVRAM (Phase 3)
// ----------------------------------------------------------------------------
// Text VRAM: 80x25 cells, 2 bytes per cell (char at even, attribute at odd),
// CPU window 0xA0000-0xA0FFF (4 KB).
//
//   CPU port:  8-bit, byte-addressed across both banks
//   Video port: parallel char+attribute fetch by cell index
//
// 2 x 2048 x 8 = 32 Kbit = 4 M10K blocks.
// ============================================================================

`default_nettype none

module tvram (
    input  wire        clk74,

    // CPU port
    input  wire [11:0] cpu_addr,     // byte address within 4 KB window
    input  wire        cpu_wren,
    input  wire [7:0]  cpu_wdata,
    output reg  [7:0]  cpu_q,        // registered read

    // video port (cell index, parallel fetch)
    input  wire [10:0] vid_addr,     // cell index (0..1999)
    output reg  [7:0]  vid_char,
    output reg  [7:0]  vid_attr
);

(* ramstyle = "M10K" *) reg [7:0] cbank [0:2047];  // char codes
(* ramstyle = "M10K" *) reg [7:0] abank [0:2047];  // attributes

wire        bank_sel = cpu_addr[0];              // 0=char, 1=attr
wire [10:0] cpu_idx  = cpu_addr[11:1];

always @(posedge clk74) begin
    // CPU write
    if (cpu_wren) begin
        if (bank_sel) abank[cpu_idx] <= cpu_wdata;
        else          cbank[cpu_idx] <= cpu_wdata;
    end
    // CPU read (registered)
    cpu_q <= bank_sel ? abank[cpu_idx] : cbank[cpu_idx];
    // video read
    vid_char <= cbank[vid_addr];
    vid_attr <= abank[vid_addr];
end

endmodule

`default_nettype wire
