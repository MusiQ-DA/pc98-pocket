module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable,

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,

///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,

output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
//
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig

);

// ============================================================================
// PC-98 for the Analogue Pocket — minimal chassis (Phase 1)
// ----------------------------------------------------------------------------
// Derived from danifunker/MacLC_pocket (which derives from the Analogue
// openFPGA template). This file keeps the Analogue-facing port contract
// byte-for-byte identical to the template and implements, for now:
//
//   - a static 640x400-ish test pattern (colour bars + moving marker)
//   - silent I2S audio (proves the audio contract compiles)
//   - core_bridge_cmd with no dataslots wired yet
//
// The PC-98 machine RTL will replace the test pattern in Phase 2+.
// See docs/PORT_PLAN.md for the roadmap.
// ============================================================================

`default_nettype none

// ---- chassis statics ------------------------------------------------------
assign port_ir_tx          = 1'b0;
assign port_ir_rx_disable  = 1'b1;
assign cart_pin30_pwroff_reset = 1'b1;

// cartridge level translators: keep everything input/off
assign cart_tran_bank0_dir = 1'b0;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_pin30_dir = 1'b0;
assign cart_tran_pin31_dir = 1'b0;

assign dbg_tx              = 1'b0;
assign user1               = 1'b0;

// little-endian bridge: the PC-98 (V30 family) is little-endian, so file bytes
// stay in file order all the way into ROM/RAM.
assign bridge_endian_little = 1'b1;

// ---- core_bridge_cmd: standard Analogue command processor -----------------
wire        br_reset_n;
wire [31:0] datatable_q;

// dataslot plumbing (BIOS ROM slot for now)
localparam [15:0] SLOT_BIOS = 16'd200;

wire        dataslot_requestread;
wire [15:0] dataslot_requestread_id;
wire        dataslot_requestwrite;
wire [15:0] dataslot_requestwrite_id;
wire [31:0] dataslot_requestwrite_size;
wire        dataslot_update;
wire [15:0] dataslot_update_id;
wire [31:0] dataslot_update_size;
wire        dataslot_allcomplete;

reg         loader_active;
always @(posedge clk_74a) begin
    if (dataslot_requestwrite)
        loader_active <= (dataslot_requestwrite_id == SLOT_BIOS);
    else if (dataslot_allcomplete)
        loader_active <= 1'b0;
end

wire        ldr_dio_download;
wire [7:0]  ldr_dio_index;
wire [24:0] ldr_dio_addr;
wire [15:0] ldr_dio_data;
wire        ldr_dio_wr;

apf_bridge_loader #(
    .ADDR_BASE ( 32'h1000_0000 ),   // BIOS ROM window (data.json slot 200)
    .ADDR_MASK ( 32'hF000_0000 )
) loader (
    .clk_74a        ( clk_74a            ),
    .bridge_addr    ( bridge_addr        ),
    .bridge_wr      ( bridge_wr          ),
    .bridge_wr_data ( bridge_wr_data     ),
    .slot_id        ( 16'd0              ),
    .slot_active    ( loader_active      ),
    .clk_sys        ( clk_74a            ),
    .reset          ( 1'b0               ),
    .dio_download   ( ldr_dio_download   ),
    .dio_index      ( ldr_dio_index      ),
    .dio_addr       ( ldr_dio_addr       ),
    .dio_data       ( ldr_dio_data       ),
    .dio_wr         ( ldr_dio_wr         ),
    .dio_ack        ( 1'b1               ),
    .busy           (                    )
);

wire dbg_cpu_fetch;

pc98_top machine (
    .clk_74a       ( clk_74a          ),
    .dio_download  ( ldr_dio_download ),
    .dio_addr      ( ldr_dio_addr     ),
    .dio_data      ( ldr_dio_data     ),
    .dio_wr        ( ldr_dio_wr       ),
    .dio_ack       ( dio_ack          ),
    .dbg_cpu_fetch ( dbg_cpu_fetch    )
);

core_bridge_cmd bridge_cmds (

    .clk                     ( clk_74a         ),
    .reset_n                 ( br_reset_n      ),

    .bridge_endian_little    ( bridge_endian_little ),
    .bridge_addr             ( bridge_addr     ),
    .bridge_rd               ( bridge_rd       ),
    .bridge_rd_data          ( bridge_rd_data  ),
    .bridge_wr               ( bridge_wr       ),
    .bridge_wr_data          ( bridge_wr_data  ),

    .status_boot_done        ( 1'b1            ),
    .status_setup_done       ( 1'b1            ),
    .status_running          ( 1'b1            ),

    .dataslot_requestread    ( dataslot_requestread    ),
    .dataslot_requestread_id ( dataslot_requestread_id ),
    .dataslot_requestread_ack( 1'b0                    ),
    .dataslot_requestread_ok ( 1'b0                    ),

    .dataslot_requestwrite     ( dataslot_requestwrite     ),
    .dataslot_requestwrite_id  ( dataslot_requestwrite_id  ),
    .dataslot_requestwrite_size( dataslot_requestwrite_size),
    .dataslot_requestwrite_ack ( 1'b1                      ),
    .dataslot_requestwrite_ok  ( 1'b1                      ),

    .dataslot_update        ( dataslot_update        ),
    .dataslot_update_id     ( dataslot_update_id     ),
    .dataslot_update_size   ( dataslot_update_size   ),

    .dataslot_allcomplete   ( dataslot_allcomplete   ),

    .rtc_epoch_seconds      ( 32'd0                  ),
    .rtc_date_bcd           ( 32'd0                  ),
    .rtc_time_bcd           ( 32'd0                  ),
    .rtc_valid              ( 1'b0                   ),

    .savestate_supported    ( 1'b0                   ),
    .savestate_addr         ( 32'd0                  ),
    .savestate_size         ( 32'd0                  ),
    .savestate_maxloadsize  ( 32'd0                  ),

    .osnotify_inmenu        (                        ),

    .savestate_start        (                        ),
    .savestate_start_ack    ( 1'b0                   ),
    .savestate_start_busy   ( 1'b0                   ),
    .savestate_start_ok     ( 1'b0                   ),
    .savestate_start_err    ( 1'b0                   ),

    .savestate_load         (                        ),
    .savestate_load_ack     ( 1'b0                   ),
    .savestate_load_busy    ( 1'b0                   ),
    .savestate_load_ok      ( 1'b0                   ),
    .savestate_load_err     ( 1'b0                   ),

    .target_dataslot_read        ( 1'b0                 ),
    .target_dataslot_write       ( 1'b0                 ),
    .target_dataslot_getfile     ( 1'b0                 ),
    .target_dataslot_openfile    ( 1'b0                 ),

    .target_dataslot_ack         (                      ),
    .target_dataslot_done        (                      ),
    .target_dataslot_err         (                      ),

    .target_dataslot_id          ( 16'd0                ),
    .target_dataslot_slotoffset  ( 32'd0                ),
    .target_dataslot_bridgeaddr  ( 32'd0                ),
    .target_dataslot_length      ( 32'd0                ),

    .target_buffer_param_struct  ( 32'd0                ),
    .target_buffer_resp_struct   ( 32'd0                ),

    .datatable_addr           ( 10'd0                   ),
    .datatable_wren           ( 1'b0                    ),
    .datatable_data           ( 32'd0                   ),
    .datatable_q              ( datatable_q             )

);

// ---- video: 640x400 test pattern, pixel clock enable from 74.25 MHz -------
// pixel rate 24.75 MHz (74.25/3). VESA 640x400@70-ish timings:
//   H: 640 vis, sync 96 @ 656..751, total 800
//   V: 400 vis, sync 2  @ 401..402, total 449

reg [1:0]  pix_div = 2'd0;
wire       pix_ce;
assign     pix_ce = (pix_div == 2'd2);
always @(posedge clk_74a) pix_div <= pix_div + 2'd1;

reg [9:0] hcount = 10'd0;
reg [8:0] vcount = 9'd0;
reg       hsync_r = 1'b0, vsync_r = 1'b0, de_r = 1'b0;
reg [23:0] rgb_r = 24'd0;
reg [7:0]  frame = 8'd0;

wire hsync_on = (hcount >= 10'd656) && (hcount < 10'd752);
wire vsync_on = (vcount >=  9'd401) && (vcount <  9'd403);
wire visible  = (hcount < 10'd640)  && (vcount <  9'd400);

// colour bars: 8 bars across, gradient down, moving white marker
reg [7:0] bar_r, bar_g, bar_b;
always @* begin
    case (hcount[8:6])
        3'd0: begin bar_r = 8'hFF; bar_g = 8'hFF; bar_b = 8'hFF; end
        3'd1: begin bar_r = 8'hFF; bar_g = 8'hFF; bar_b = 8'h00; end
        3'd2: begin bar_r = 8'h00; bar_g = 8'hFF; bar_b = 8'hFF; end
        3'd3: begin bar_r = 8'h00; bar_g = 8'hFF; bar_b = 8'h00; end
        3'd4: begin bar_r = 8'hFF; bar_g = 8'h00; bar_b = 8'hFF; end
        3'd5: begin bar_r = 8'hFF; bar_g = 8'h00; bar_b = 8'h00; end
        3'd6: begin bar_r = 8'h00; bar_g = 8'h00; bar_b = 8'hFF; end
        default: begin bar_r = 8'h00; bar_g = 8'h00; bar_b = 8'h00; end
    endcase
end

wire marker = ((hcount[3:0] + frame[3:0]) == 4'd0) && (vcount[3:0] == 4'd0);

always @(posedge clk_74a) if (pix_ce) begin
    if (hcount == 10'd799) begin
        hcount <= 10'd0;
        if (vcount == 9'd448) begin
            vcount <= 9'd0;
            frame  <= frame + 8'd1;
        end else begin
            vcount <= vcount + 9'd1;
        end
    end else begin
        hcount <= hcount + 10'd1;
    end

    de_r    <= visible;
    hsync_r <= ~hsync_on;   // negative sync
    vsync_r <= ~vsync_on;
    rgb_r   <= visible ? (marker ? 24'hFFFFFF
                                 : {bar_r, bar_g, bar_b})
                       : 24'h000000;
end

assign video_rgb_clock    = clk_74a;
// NOTE: proper 90-degree clock forward via PLL/DDIO comes in Phase 2.
assign video_rgb_clock_90 = ~clk_74a;
assign video_rgb          = rgb_r;
assign video_de           = de_r;
assign video_hs           = hsync_r;
assign video_vs           = vsync_r;
assign video_skip         = 1'b0;

// ---- audio: silence (contract exercised, no source yet) -------------------
i2s audio_out (
    .clk_74a     ( clk_74a     ),
    .left_audio  ( 16'd0       ),
    .right_audio ( 16'd0       ),
    .audio_mclk  ( audio_mclk  ),
    .audio_dac   ( audio_dac   ),
    .audio_lrck  ( audio_lrck  )
);

endmodule
`default_nettype wire
