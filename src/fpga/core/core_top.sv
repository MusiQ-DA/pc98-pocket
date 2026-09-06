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

// bridge_endian_little is the FRAMEWORK BRIDGE word-order convention, NOT the
// guest CPU endianness: every working core (including the x86-based
// desaster.PCXT) sets 0, and core_bridge_cmd matches its "CM" command marker
// against the big-endian word. Setting 1 made the framework report
// "RS: Host commands ignored". The apf_bridge_loader splits each 32-bit write
// high-word-first, which keeps little-endian ROM files in byte order for the
// 8-bit CPU fetches once the ROM lane mux below is matched to it.
assign bridge_endian_little = 1'b0;

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
wire        dio_ack;            // driven by the machine (always 1 in phase 2)

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
    .dio_ack        ( dio_ack            ),
    .busy           (                    )
);

// ---- font data slot (second streamed slot) --------------------------------
localparam [15:0] SLOT_FONT = 16'd201;
wire        font_loader_active;
wire        fnt_dio_download;
wire [7:0]  fnt_dio_index;
wire [24:0] fnt_dio_addr;
wire [15:0] fnt_dio_data;
wire        fnt_dio_wr;

always @(posedge clk_74a) begin
    if (dataslot_requestwrite)
        font_loader_active <= (dataslot_requestwrite_id == SLOT_FONT);
    else if (dataslot_allcomplete)
        font_loader_active <= 1'b0;
end

apf_bridge_loader #(
    .ADDR_BASE ( 32'h2000_0000 ),   // FONT.ROM window (data.json slot 201)
    .ADDR_MASK ( 32'hF000_0000 )
) font_loader (
    .clk_74a        ( clk_74a            ),
    .bridge_addr    ( bridge_addr        ),
    .bridge_wr      ( bridge_wr          ),
    .bridge_wr_data ( bridge_wr_data     ),
    .slot_id        ( 16'd1              ),
    .slot_active    ( font_loader_active ),
    .clk_sys        ( clk_74a            ),
    .reset          ( 1'b0               ),
    .dio_download   ( fnt_dio_download   ),
    .dio_index      ( fnt_dio_index      ),
    .dio_addr       ( fnt_dio_addr       ),
    .dio_data       ( fnt_dio_data       ),
    .dio_wr         ( fnt_dio_wr         ),
    .dio_ack        ( 1'b1               ),
    .busy           (                    )
);

// ---- boot handshake --------------------------------------------------------
// The OS polls "Request Status" (host cmd 0x0000) and needs to observe the
// progression  1:booting -> 2:setup (slots streaming) -> 3:idle (all loaded)
//              -> 4:running (after Reset Exit)
// Constant-1 statuses never transition and the framework fails with
// "Core not ready to run". So:
//   boot_done  rises ~1 us after configuration
//   setup_done rises once the BIOS stream finished AND the font stream
//              finished (or a hold-off expires when no font.rom is present)

// NOTE: setup_done must rise UNCONDITIONALLY, independent of data-slot
// streaming. The OS only starts streaming data slots once the core reports
// idle (3); gating setup_done on stream completion deadlocks the launch
// (core waits for streams, OS waits for idle -> "Core not ready to run").
// The machine (pc98_top) still holds ITS CPU in reset until the BIOS stream
// arrives - that part is internal and unrelated to the framework handshake.

reg [25:0] boot_cnt = 26'd0;

wire boot_done_r  = (boot_cnt >= 26'd64);      // ~0.9 us after configuration
wire setup_done_r = (boot_cnt >= 26'd4096);    // ~55 us after boot_done

// ---- bridge diagnostics: which host commands has the OS issued? -----------
// 8-bit sticky mask, rendered as blocks on the bottom screen edge:
//  [0]=status poll(0x0000) [1]=slot read(0x0081) [2]=slot write(0x0082)
//  [3]=allcomplete(0x008F) [4]=reset exit(0x0011) [5]=reset enter(0x0010)
//  [6]=target window write [7]=datatable write
reg [7:0] cmd_seen = 8'd0;
always @(posedge clk_74a) begin
    if (bridge_wr && bridge_addr[31:24] == 8'hF8) begin
        if (bridge_addr[15:8] == 8'h00 && bridge_wr_data[31:16] == 16'h434D) begin
            case (bridge_wr_data[15:0])
                16'h0000: cmd_seen[0] <= 1'b1;
                16'h0081: cmd_seen[1] <= 1'b1;
                16'h0082: cmd_seen[2] <= 1'b1;
                16'h008F: cmd_seen[3] <= 1'b1;
                16'h0011: cmd_seen[4] <= 1'b1;
                16'h0010: cmd_seen[5] <= 1'b1;
                default:  cmd_seen[6] <= 1'b1;
            endcase
        end
        if (bridge_addr[15:8] == 8'h10)    cmd_seen[5] <= 1'b1;
        if (bridge_addr[15:8] == 8'h2x || (bridge_addr[15:8] == 8'h20)) cmd_seen[7] <= 1'b1;
    end
end

wire [23:0] mach_rgb;
wire        mach_de;

pc98_top machine (
    .clk_74a       ( clk_74a          ),
    .dio_download  ( ldr_dio_download ),
    .dio_addr      ( ldr_dio_addr     ),
    .dio_data      ( ldr_dio_data     ),
    .dio_wr        ( ldr_dio_wr       ),
    .dio_ack       ( dio_ack          ),
    .fnt_download  ( fnt_dio_download ),
    .fnt_addr      ( fnt_dio_addr     ),
    .fnt_data      ( fnt_dio_data     ),
    .fnt_wr        ( fnt_dio_wr       ),
    .pix_ce        ( pix_ce           ),
    .hcount        ( hcount           ),
    .vcount        ( vcount           ),
    .video_rgb     ( mach_rgb         ),
    .video_de      ( mach_de          )
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

    .status_boot_done        ( boot_done_r     ),
    .status_setup_done       ( setup_done_r    ),
    .status_running          ( br_reset_n      ),

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

// ---- video timing: 640x400, pixel rate 24.75 MHz (74.25/3) ----------------
//   H: 640 vis, sync 96 @ 656..751, total 800
//   V: 400 vis, sync 2  @ 401..402, total 449

reg [1:0]  pix_div = 2'd0;
wire       pix_ce;
assign     pix_ce = (pix_div == 2'd2);
always @(posedge clk_74a) pix_div <= pix_div + 2'd1;

reg [9:0] hcount = 10'd0;
reg [8:0] vcount = 9'd0;
reg       hsync_r = 1'b0, vsync_r = 1'b0;

wire hsync_on = (hcount >= 10'd656) && (hcount < 10'd752);
wire vsync_on = (vcount >=  9'd401) && (vcount <  9'd403);

always @(posedge clk_74a) if (pix_ce) begin
    if (hcount == 10'd799) begin
        hcount <= 10'd0;
        if (vcount == 9'd448) begin
            vcount <= 9'd0;
        end else begin
            vcount <= vcount + 9'd1;
        end
    end else begin
        hcount <= hcount + 10'd1;
    end

    hsync_r <= ~hsync_on;   // negative sync
    vsync_r <= ~vsync_on;
end

assign video_rgb_clock    = clk_74a;
// NOTE: proper 90-degree clock forward via PLL/DDIO comes in Phase 2.
assign video_rgb_clock_90 = ~clk_74a;
// bottom-edge diagnostic strip: 8 blocks, lit = command seen
reg [2:0] dbg_block;
always @(posedge clk_74a) if (pix_ce && vcount >= 9'd396)
    dbg_block <= hcount[9:3] / 3'd10;
wire [2:0] dbg_block_r = dbg_block;

assign video_rgb          = (vcount >= 9'd396)
                            ? (cmd_seen[dbg_block_r] ? 24'hFFFFFF : 24'h303030)
                            : mach_rgb;
assign video_de           = mach_de;
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
