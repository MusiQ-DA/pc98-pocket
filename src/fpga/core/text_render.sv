// ============================================================================
// PC-98 for the Analogue Pocket — text plane renderer (Phase 3)
// ----------------------------------------------------------------------------
// Renders the 80x25 text screen (8x16 cells on 640x400) from TVRAM + FONT.ROM.
//
// Pipeline (sys clock 74.25 MHz, one pixel every 3rd cycle via pix_ce):
//   each character cell_idx spans 24 sys cycles:
//     ph 0        : pixel 0 out; TVRAM read address switched to the NEXT cell_idx
//     ph 1        : char/attribute of the next cell_idx registered
//     ph 2        : char/attr latched; FONT.ROM byte address driven
//     ph 4        : glyph for the next cell_idx latched
//     ph 3p (p=0..7): pixel p output from the current glyph register
//     cell_start  : glyph/attr registers roll over
//
// Attributes (phase 3): bit 1 = reverse video. Others TODO (blink/secret/
// underline/colour palette ports).
// ============================================================================

`default_nettype none

module text_render (
    input  wire        clk74,
    input  wire        pix_ce,          // pixel-rate enable (24.75 MHz)
    input  wire [9:0]  hcount,          // 0..799
    input  wire [9:0]  vcount,          // 0..448

    // TVRAM video port
    output wire [10:0] tvram_addr,      // cell_idx index
    input  wire [7:0]  tvram_char_q,
    input  wire [7:0]  tvram_attr_q,

    // font port (byte address, registered data)
    output wire [15:0] font_addr,
    input  wire [7:0]  font_q,

    output reg  [23:0] rgb,
    output reg         de
);

wire visible = (hcount < 10'd640) && (vcount < 10'd400);

// cell_idx geometry: 80 cols x 25 rows
wire [6:0] col = hcount[9:3];         // 0..79
wire [4:0] row = vcount[8:4];         // 0..24
wire [12:0] rowbase = {3'd0, row, 6'd0} + {5'd0, row, 4'd0};   // row*80
wire [10:0] cell_idx = rowbase[10:0] + {1'b0, col};

// next cell_idx (fetch-ahead); clamps to start-of-row at the end
wire [6:0] next_col = (col == 7'd79) ? 7'd0 : col + 7'd1;
wire [10:0] next_cell_idx = rowbase[10:0] + {1'b0, next_col};

// ---------------------------------------------------------------------------
// cell_idx phase: counts 24 sys cycles per cell_idx, reset at cell_start
// ---------------------------------------------------------------------------
reg [4:0] ph = 5'd23;
wire cell_start = pix_ce && (hcount[2:0] == 3'd0);
always @(posedge clk74) begin
    if (cell_start)          ph <= 5'd0;
    else if (ph != 5'd23)    ph <= ph + 5'd1;
end

// TVRAM address: point at the next cell_idx during the fetch window
assign tvram_addr = (ph <= 5'd2) ? next_cell_idx : cell_idx;

// ---------------------------------------------------------------------------
// font addressing: char code -> glyph row byte
//   0x00-0x7F : 0x0800 + code*16
//   0x80-0xFF : 0x1000 + (code-0x80)*16
// ---------------------------------------------------------------------------
wire [15:0] fbyte = ((tvram_char_q[7] ? 16'h1000 : 16'h0800)
                     + {tvram_char_q[6:0], 4'd0}
                     + {12'd0, vcount[3:0]});
assign font_addr = fbyte;

// ---------------------------------------------------------------------------
// pipeline registers
// ---------------------------------------------------------------------------
reg [7:0] glyph_reg = 8'h00;       // glyph byte of the cell_idx being rendered
reg       reverse_reg = 1'b0;
reg [7:0] next_glyph = 8'h00;
reg       next_reverse = 1'b0;
reg [7:0] char_r = 8'h00;
reg [7:0] attr_r = 8'h00;
reg [2:0] pix_r = 3'd0;            // pixel index within the cell_idx

wire [2:0] pix_in_cell = hcount[2:0];

always @(posedge clk74) begin
    // --- fetch pipeline for the NEXT cell_idx ---
    if (ph == 5'd2) begin
        char_r <= tvram_char_q;
        attr_r <= tvram_attr_q;
    end
    if (ph == 5'd4) begin              // font read latency: 1 cycle
        next_glyph   <= font_q;
        next_reverse <= attr_r[1];    // bit 1: reverse video
    end

    // --- pixel output (pixel p at ph == 3p) ---
    if (pix_ce) begin
        pix_r <= pix_in_cell;
        de    <= visible;
        if (visible) begin
            if (pix_in_cell == 3'd0)
                rgb <= ((glyph_reg[7] ^ reverse_reg) ? 24'hC0C0C0 : 24'h202020);
            else
                rgb <= ((glyph_reg[3'd7 - pix_in_cell] ^ reverse_reg)
                        ? 24'hC0C0C0 : 24'h202020);
        end else begin
            rgb <= 24'h000000;
        end
    end

    // --- roll the pipeline at the cell_idx boundary ---
    if (cell_start) begin
        glyph_reg   <= next_glyph;
        reverse_reg <= next_reverse;
    end
end

endmodule

`default_nettype wire
