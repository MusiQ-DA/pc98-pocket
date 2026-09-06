// ============================================================================
// PC-98 for the Analogue Pocket — machine top (Phase 2)
// ----------------------------------------------------------------------------
// The PC-98 "machine" itself, kept free of Analogue-specific code:
//
//   - MCL86 CPU (i8088_min wrapper, minimum-mode 8-bit bus for now;
//     migration to the BIU-max 16-bit bus comes with the SDRAM phase)
//   - CPU clock 74.25/8 = 9.28125 MHz (V30 class machines run 8-10 MHz)
//   - memory map (phase 2 subset):
//       0x00000-0x0FFFF  64 KB RAM stub          (block RAM)
//       0xE8000-0xFFFFF  96 KB BIOS ROM          (block RAM, loader-loaded)
//       everything else  open bus (0xFF)
//   - I/O space: writes ignored, reads return 0xFF (peripherals come later)
//
// The CPU is held in reset until the BIOS data slot has streamed once.
// ============================================================================

`default_nettype none

module pc98_top (
    input  wire        clk_74a,

    // BIOS data slot stream (from apf_bridge_loader in the chassis)
    input  wire        dio_download,
    input  wire [24:0] dio_addr,
    input  wire [15:0] dio_data,
    input  wire        dio_wr,
    output wire        dio_ack,

    // debug heartbeat: toggles on every bus read (visible on future probes)
    output reg         dbg_cpu_fetch
);

// ---------------------------------------------------------------------------
// CPU clock: 74.25 MHz / 8 = 9.28125 MHz
// ---------------------------------------------------------------------------
reg [2:0] clkdiv = 3'd0;
always @(posedge clk_74a) clkdiv <= clkdiv + 3'd1;
wire clk_cpu = clkdiv[2];           // 9.28125 MHz (register-derived clock)
wire cpu_tick = (clkdiv == 3'd0);   // one sys cycle per CPU cycle boundary

// ---------------------------------------------------------------------------
// reset: power-on + hold until the BIOS has streamed once
// ---------------------------------------------------------------------------
reg [7:0] por_cnt = 8'hFF;
reg       rom_loaded = 1'b0;
reg       dl_d = 1'b0;
wire     cpu_reset = (por_cnt != 8'd0) || !rom_loaded;

always @(posedge clk_74a) begin
    if (por_cnt != 8'd0)
        por_cnt <= por_cnt - 8'd1;
    dl_d <= dio_download;
    if (dl_d && !dio_download)
        rom_loaded <= 1'b1;
end

// ---------------------------------------------------------------------------
// CPU
// ---------------------------------------------------------------------------
wire [19:0] cpu_addr;
wire [7:0]  cpu_dout, cpu_din;
wire        cpu_ale, cpu_rd_n, cpu_wr_n, cpu_iom;

i8088_min cpu (
    .CORE_CLK   ( clk_74a    ),
    .CLK        ( clk_cpu    ),
    .RESET      ( cpu_reset  ),
    .READY      ( 1'b1       ),
    .INTR       ( 1'b0       ),
    .NMI        ( 1'b0       ),
    .addr       ( cpu_addr   ),
    .dout       ( cpu_dout   ),
    .din        ( cpu_din    ),
    .ALE        ( cpu_ale    ),
    .INTA_n     (            ),
    .RD_n       ( cpu_rd_n   ),
    .WR_n       ( cpu_wr_n   ),
    .IOM        ( cpu_iom    ),
    .DTR        (            ),
    .DEN        (            )
);

// ---------------------------------------------------------------------------
// bus: address latch + decode
// ---------------------------------------------------------------------------
reg [19:0] bus_addr = 20'd0;
always @(posedge clk_74a) if (cpu_ale) bus_addr <= cpu_addr;

wire bus_mem  = ~cpu_iom;                       // 0 = memory space
wire ram_sel  = bus_mem && (bus_addr[19:16] == 4'b0000);
wire rom_sel  = bus_mem && (bus_addr[19:17] == 3'b111);
wire bus_rd   = bus_mem && ~cpu_rd_n;
wire bus_wr   = bus_mem && ~cpu_wr_n;

// ---------------------------------------------------------------------------
// BIOS ROM
// ---------------------------------------------------------------------------
wire [7:0] rom_byte;
wire loader_wr = dio_download && dio_wr;

bios_rom bios (
    .clk74    ( clk_74a                    ),
    .wr_en    ( loader_wr                  ),
    .wr_waddr ( dio_addr[15:1]             ),  // byte offset -> word index
    .wr_data  ( dio_data                   ),
    .rd_waddr ( bus_addr[16:1]             ),  // 0xE8000-based offset
    .rd_selhi ( bus_addr[0]                ),
    .rd_data  ( rom_byte                   )
);

assign dio_ack = 1'b1;              // BRAM keeps up with the stream

// ---------------------------------------------------------------------------
// RAM stub
// ---------------------------------------------------------------------------
wire [7:0] ram_q;

ram64k ram (
    .clk74 ( clk_74a ),
    .rd_en ( cpu_tick ),
    .addr  ( bus_addr[15:0] ),
    .wr_en ( ram_sel && bus_wr && cpu_tick ),
    .wdata ( cpu_dout ),
    .q     ( ram_q )
);

// ---------------------------------------------------------------------------
// data-in mux (registered BRAM outputs land well inside the CPU cycle)
// ---------------------------------------------------------------------------
assign cpu_din = rom_sel ? rom_byte :
                 ram_sel ? ram_q    : 8'hFF;

// ---------------------------------------------------------------------------
// debug: toggle on every memory read
// ---------------------------------------------------------------------------
always @(posedge clk_74a) begin
    if (bus_rd && (clkdiv == 3'd0))
        dbg_cpu_fetch <= ~dbg_cpu_fetch;
end

endmodule

`default_nettype wire
