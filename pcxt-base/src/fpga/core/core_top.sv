//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

    //
    // FEATURE CONFIGURATION
    //

`ifndef SYSTEM_VARIANT_TANDY
`define SYSTEM_VARIANT_TANDY 0
`endif
`ifndef ROM_VARIANT_TANDY
`define ROM_VARIANT_TANDY `SYSTEM_VARIANT_TANDY
`endif
`ifndef ROM_IS_TANDY
`define ROM_IS_TANDY `ROM_VARIANT_TANDY
`endif
`ifndef CONF_STR_SYSTEM
`define CONF_STR_SYSTEM (`SYSTEM_VARIANT_TANDY ? "Tandy1000;UART115200:115200;" : "PCXT;UART115200:115200;")
`endif
`ifndef ENABLE_TANDY_VIDEO
`define ENABLE_TANDY_VIDEO 0
`endif
`ifndef ENABLE_TANDY_AUDIO
`define ENABLE_TANDY_AUDIO 0
`endif
`ifndef ENABLE_TANDY_KBD
`define ENABLE_TANDY_KBD 0
`endif
`ifndef ENABLE_A000_UMB
`define ENABLE_A000_UMB 0
`endif
`ifndef ENABLE_CGA
`define ENABLE_CGA 1
`endif
`ifndef ENABLE_HGC
`define ENABLE_HGC 0
`endif
`ifndef ENABLE_OPL2
`define ENABLE_OPL2 0
`endif
`ifndef ENABLE_CMS
`define ENABLE_CMS 0
`endif
`ifndef ENABLE_EMS
`define ENABLE_EMS 0
`endif
`ifndef CHIPSET_HZ
`define CHIPSET_HZ 42954545
`endif
module core_top (

    //
    // physical connections
    //

    // clock inputs, 74.25 MHz (not phase aligned; treat as async domains)
    input  wire         clk_74a,
    input  wire         clk_74b,

    // cartridge interface (unused)
    inout  wire [7:0]   cart_tran_bank2,
    output wire         cart_tran_bank2_dir,
    inout  wire [7:0]   cart_tran_bank3,
    output wire         cart_tran_bank3_dir,
    inout  wire [7:0]   cart_tran_bank1,
    output wire         cart_tran_bank1_dir,
    inout  wire [7:4]   cart_tran_bank0,
    output wire         cart_tran_bank0_dir,
    inout  wire         cart_tran_pin30,
    output wire         cart_tran_pin30_dir,
    output wire         cart_pin30_pwroff_reset,
    inout  wire         cart_tran_pin31,
    output wire         cart_tran_pin31_dir,

    // infrared
    input  wire         port_ir_rx,
    output wire         port_ir_tx,
    output wire         port_ir_rx_disable,

    // GBA link port
    inout  wire         port_tran_si,
    output wire         port_tran_si_dir,
    inout  wire         port_tran_so,
    output wire         port_tran_so_dir,
    inout  wire         port_tran_sck,
    output wire         port_tran_sck_dir,
    inout  wire         port_tran_sd,
    output wire         port_tran_sd_dir,

    // cellular PSRAM 0 and 1 (unused)
    output wire [21:16] cram0_a,
    inout  wire [15:0]  cram0_dq,
    input  wire         cram0_wait,
    output wire         cram0_clk,
    output wire         cram0_adv_n,
    output wire         cram0_cre,
    output wire         cram0_ce0_n,
    output wire         cram0_ce1_n,
    output wire         cram0_oe_n,
    output wire         cram0_we_n,
    output wire         cram0_ub_n,
    output wire         cram0_lb_n,
    output wire [21:16] cram1_a,
    inout  wire [15:0]  cram1_dq,
    input  wire         cram1_wait,
    output wire         cram1_clk,
    output wire         cram1_adv_n,
    output wire         cram1_cre,
    output wire         cram1_ce0_n,
    output wire         cram1_ce1_n,
    output wire         cram1_oe_n,
    output wire         cram1_we_n,
    output wire         cram1_ub_n,
    output wire         cram1_lb_n,

    // SDRAM, 16-bit: the PC's main memory + BIOS live here
    output wire [12:0]  dram_a,
    output wire [1:0]   dram_ba,
    inout  wire [15:0]  dram_dq,
    output wire [1:0]   dram_dqm,
    output wire         dram_clk,
    output wire         dram_cke,
    output wire         dram_ras_n,
    output wire         dram_cas_n,
    output wire         dram_we_n,

    // SRAM (unused)
    output wire [16:0]  sram_a,
    inout  wire [15:0]  sram_dq,
    output wire         sram_oe_n,
    output wire         sram_we_n,
    output wire         sram_ub_n,
    output wire         sram_lb_n,

    // vblank from dock
    input  wire         vblank,

    // debug UART + solderable user pads
    output wire         dbg_tx,
    input  wire         dbg_rx,
    output wire         user1,
    input  wire         user2,

    // RFU I2C + PLL feed
    inout  wire         aux_sda,
    output wire         aux_scl,
    output wire         vpll_feed,

    //
    // logical connections
    //

    // video + audio output to the scaler
    output wire [23:0]  video_rgb,
    output wire         video_rgb_clock,
    output wire         video_rgb_clock_90,
    output wire         video_de,
    output wire         video_skip,
    output wire         video_vs,
    output wire         video_hs,

    output wire         audio_mclk,
    input  wire         audio_adc,
    output wire         audio_dac,
    output wire         audio_lrck,

    // bridge bus (synchronous to clk_74a)
    output wire         bridge_endian_little,
    input  wire [31:0]  bridge_addr,
    input  wire         bridge_rd,
    output reg  [31:0]  bridge_rd_data,
    input  wire         bridge_wr,
    input  wire [31:0]  bridge_wr_data,

    // controller data (4 players)
    input  wire [15:0]  cont1_key,
    input  wire [15:0]  cont2_key,
    input  wire [15:0]  cont3_key,
    input  wire [15:0]  cont4_key,
    input  wire [31:0]  cont1_joy,
    input  wire [31:0]  cont2_joy,
    input  wire [31:0]  cont3_joy,
    input  wire [31:0]  cont4_joy,
    input  wire [15:0]  cont1_trig,
    input  wire [15:0]  cont2_trig,
    input  wire [15:0]  cont3_trig,
    input  wire [15:0]  cont4_trig
);

    //
    // UNUSED PHYSICAL INTERFACES
    //

    // IR off, receiver disabled to save power
    assign port_ir_tx              = 0;
    assign port_ir_rx_disable      = 1;

    assign bridge_endian_little    = 0;

    // cartridge level translators (dir 0:IN 1:OUT), unused
    assign cart_tran_bank3         = 8'hzz;
    assign cart_tran_bank3_dir     = 1'b0;
    assign cart_tran_bank2         = 8'hzz;
    assign cart_tran_bank2_dir     = 1'b0;
    assign cart_tran_bank1         = 8'hzz;
    assign cart_tran_bank1_dir     = 1'b0;
    assign cart_tran_bank0         = 4'hf;
    assign cart_tran_bank0_dir     = 1'b1;
    assign cart_tran_pin30         = 1'b0;
    assign cart_tran_pin30_dir     = 1'bz;
    assign cart_pin30_pwroff_reset = 1'b0;
    assign cart_tran_pin31         = 1'bz;
    assign cart_tran_pin31_dir     = 1'b0;

    // GBA link port: input only
    assign port_tran_so            = 1'bz;
    assign port_tran_so_dir        = 1'b0;
    assign port_tran_si            = 1'bz;
    assign port_tran_si_dir        = 1'b0;
    assign port_tran_sck           = 1'bz;
    assign port_tran_sck_dir       = 1'b0;
    assign port_tran_sd            = 1'bz;
    assign port_tran_sd_dir        = 1'b0;

    // cellular PSRAM: unused
    assign cram0_a                 = 'h0;
    assign cram0_dq                = {16{1'bZ}};
    assign cram0_clk               = 0;
    assign cram0_adv_n             = 1;
    assign cram0_cre               = 0;
    assign cram0_ce0_n             = 1;
    assign cram0_ce1_n             = 1;
    assign cram0_oe_n              = 1;
    assign cram0_we_n              = 1;
    assign cram0_ub_n              = 1;
    assign cram0_lb_n              = 1;
    assign cram1_a                 = 'h0;
    assign cram1_dq                = {16{1'bZ}};
    assign cram1_clk               = 0;
    assign cram1_adv_n             = 1;
    assign cram1_cre               = 0;
    assign cram1_ce0_n             = 1;
    assign cram1_ce1_n             = 1;
    assign cram1_oe_n              = 1;
    assign cram1_we_n              = 1;
    assign cram1_ub_n              = 1;
    assign cram1_lb_n              = 1;

    // SRAM: unused
    assign sram_a                  = 'h0;
    assign sram_dq                 = {16{1'bZ}};
    assign sram_oe_n               = 1;
    assign sram_we_n               = 1;
    assign sram_ub_n               = 1;
    assign sram_lb_n               = 1;

    assign dbg_tx                  = 1'bZ;
    assign user1                   = 1'bZ;
    assign aux_scl                 = 1'bZ;
    assign vpll_feed               = 1'bZ;

    //
    // CLOCKING
    //

    wire pll_locked;             // system PLL lock

    wire clk_core;               // 85.909 MHz, i8088 core
    wire clk_28_636;             // CGA dot clock
    wire clk_32_514;             // HGC dot clock (x2)
    wire clk_cpu;                // 8088 pin clock (gated)
    logic cpu_ce_posedge;        // CPU clock-enable, rising
    logic cpu_ce_negedge;        // CPU clock-enable, falling
    logic peripheral_ce;         // peripheral clock-enable
    wire clk_chipset;            // 42.95 MHz, main domain

    localparam [27:0] cur_rate = `CHIPSET_HZ;   // chipset clock rate, Hz (3 x 14.31818 MHz)

    wire clk_sdram_ph;           // SDRAM pin clock, phase-shifted
    wire clk_pix_cga;            // CGA pixel
    wire clk_pix_cga_90;         // CGA pixel, 90 deg
    wire clk_pix_hgc;            // HGC pixel
    wire clk_pix_hgc_90;         // HGC pixel, 90 deg
    wire clk_pix;                // selected pixel, video out
    wire clk_pix_90;             // selected pixel, 90 deg
    wire pll_video_locked = 1'b1; // CGA on the system PLL; no separate lock
    wire pll_video_hgc_locked;   // HGC PLL lock

    // System PLL: chipset 42.95, core 85.9 (2:1), dram 42.95@180, CGA dot 28.64,
    // pixel 14.32 (+90) MHz. One VCO, so the CPU stays phase-locked to the CGA beam.
    pll pll
    (
        .refclk   (clk_74a),
        .rst      (1'b0),
        .outclk_0 (clk_chipset),
        .outclk_1 (clk_core),
        .outclk_2 (clk_sdram_ph),
        .outclk_3 (clk_28_636),
        .outclk_4 (clk_pix_cga),
        .outclk_5 (clk_pix_cga_90),
        .locked   (pll_locked)
    );

    // Hercules video PLL: 32.514 MHz (HGC dot clock x2), 16.257 MHz pixel + 90-deg
    // sibling. From clk_74b: the system pll occupies a clk_74a fractional-PLL site.
    generate if (`ENABLE_HGC) begin : gen_pll_video_hgc
    pll_video_hgc pll_video_hgc
    (
        .refclk   (clk_74b),
        .rst      (1'b0),
        .outclk_0 (clk_32_514),
        .outclk_1 (clk_pix_hgc),
        .outclk_2 (clk_pix_hgc_90),
        .locked   (pll_video_hgc_locked)
    );
    end else begin : gen_pll_video_hgc
    assign clk_32_514           = 1'b0;
    assign clk_pix_hgc          = 1'b0;
    assign clk_pix_hgc_90       = 1'b0;
    assign pll_video_hgc_locked = 1'b1;
    end endgenerate

    // 14.318 MHz tick (clk_28_636 / 2): clock-enable for the splash timer and the
    // UART baud base.
    reg ce_14_318 = 1'b0;
    always @(posedge clk_28_636)
        ce_14_318 <= ~ce_14_318;

    // CPU clock: XT_CE_Generator derives the 8088 pin clock and its CE strobes;
    // clk_select sets the speed and is reloaded each bus cycle (biu_done).
    logic  biu_done;
    logic  [7:0] clock_cycle_counter_division_ratio;
    logic  [7:0] clock_cycle_counter_decrement_value;
    logic        shift_read_timing;
    logic  [1:0] ram_read_wait_cycle;
    logic  [1:0] ram_write_wait_cycle;
    logic        cycle_accrate;
    logic  [1:0] clk_select;
    wire   [1:0] clk_select_next = ((xtctl[3:2] == 2'b00) && ~xtctl[7]) ? cpu_speed_cfg :
                                   (xtctl[7] ? 2'b11 : xtctl[3:2] - 2'b01);

    always @(posedge clk_chipset, posedge reset)
    begin
        if (reset)
            clk_select <= 2'b00;
        else if (biu_done)
            clk_select <= clk_select_next;
    end

    XT_CE_Generator u_XT_CE_Generator
    (
        .clock                              (clk_chipset),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (clk_select_next),
        .cpu_clk_pin                        (clk_cpu),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .cycle_accrate                      (cycle_accrate),
        .clock_cycle_counter_division_ratio (clock_cycle_counter_division_ratio),
        .clock_cycle_counter_decrement_value(clock_cycle_counter_decrement_value),
        .shift_read_timing                  (shift_read_timing),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle)
    );

    // COM baud clock-enables: a ce_14_318 edge sampled onto clk_chipset (COM1),
    // divided by 8 for COM2.
    logic clk_uart_ff_1;
    logic clk_uart_ff_2;
    logic clk_uart_ff_3;
    logic clk_uart_en;
    logic clk_uart2_en;
    logic [2:0] clk_uart2_counter;

    always @(posedge clk_chipset)
    begin
        clk_uart_ff_1 <= ce_14_318;
        clk_uart_ff_2 <= clk_uart_ff_1;
        clk_uart_ff_3 <= clk_uart_ff_2;
        clk_uart_en   <= ~clk_uart_ff_3 & clk_uart_ff_2;
    end

    always @(posedge clk_chipset)
    begin
        if (clk_uart_en)
        begin
            if (3'd7 != clk_uart2_counter)
            begin
                clk_uart2_counter <= clk_uart2_counter +3'd1;
                clk_uart2_en <= 1'b0;
            end
            else
            begin
                clk_uart2_counter <= 3'd0;
                clk_uart2_en <= 1'b1;
            end
        end
        else
        begin
            clk_uart2_counter <= clk_uart2_counter;
            clk_uart2_en <= 1'b0;
        end
    end

    // Pixel-clock switch: video_rgb_clock follows the displayed card's pixel pair.
    // On a card change (swap_video), blank the output, flip both muxes mid-window,
    // then un-blank once the scaler has seen frames of the new timing.
    wire swap_video_chip;
    synch_3 s_swap_video (swap_video, swap_video_chip, clk_chipset);
`ifdef MACHINE_PC98
    // This machine has one video mode, so there is nothing to swap to. The
    // switch is not merely useless here, it is harmful: it never checked
    // ENABLE_HGC, so a guest touching the PC/AT video mode register raised
    // swap_video and took pix_sel with it -- and pix_sel selects the Hercules
    // canvas for the OSD's line counter and asks the scaler for mode 1, which
    // the PC-98 video.json does not declare. Both the OSD and the picture go
    // with it. Held at zero.
    wire pix_sel   = 1'b0;
    wire vid_blank = 1'b0;
`else
    reg         pix_sel   = 1'b0;   // 0 = CGA pixel pair, 1 = HGC pixel pair
    reg         vid_blank = 1'b0;   // forces DE low across the clock switch
    reg  [21:0] pix_switch_cnt = 22'd0;
    localparam  PIX_SWITCH_CYCLES = (cur_rate / 25) * 2;   // ~80 ms: 2 frames each side of the flip
    always @(posedge clk_chipset) begin
        if (pix_switch_cnt != 22'd0) begin
            pix_switch_cnt <= pix_switch_cnt - 22'd1;
            if (pix_switch_cnt == (PIX_SWITCH_CYCLES >> 1))
                pix_sel <= swap_video_chip;
            if (pix_switch_cnt == 22'd1)
                vid_blank <= 1'b0;
        end else if (swap_video_chip != pix_sel) begin
            vid_blank      <= 1'b1;
            pix_switch_cnt <= PIX_SWITCH_CYCLES;
        end
    end
`endif

`ifdef MACHINE_PC98
    // One video mode, so no switch: the dot clock goes straight out. The CGA
    // and HGC pairs and the swap machinery above are PC/AT things that this
    // machine has no equivalent of.
    wire clk_pc98_dot, clk_pc98_dot_90, pll_pc98_locked;
    pll_video_pc98 u_pll_pc98 (
        .refclk   (clk_74b),
        .rst      (1'b0),
        .outclk_0 (clk_pc98_dot),
        .outclk_1 (clk_pc98_dot_90),
        .locked   (pll_pc98_locked)
    );
    assign clk_pix    = clk_pc98_dot;
    assign clk_pix_90 = clk_pc98_dot_90;
`else
    cyclonev_clkselect u_pixclk_sw
    (
        .clkselect ({1'b1, pix_sel}),
        .inclk     ({clk_pix_hgc, clk_pix_cga, 2'b00}),
        .outclk    (clk_pix)
    );
    cyclonev_clkselect u_pixclk90_sw
    (
        .clkselect ({1'b1, pix_sel}),
        .inclk     ({clk_pix_hgc_90, clk_pix_cga_90, 2'b00}),
        .outclk    (clk_pix_90)
    );
`endif

    //
    // RESET
    //

    // Global power-on reset until all PLLs lock.
`ifdef MACHINE_PC98
    wire RESET = ~pll_locked | ~pll_pc98_locked;
`else
    wire RESET = ~pll_locked | ~pll_video_locked | ~pll_video_hgc_locked;
`endif

    // The disk/OSD softcore is the boot master; it drives this hold (declared here so the guest
    // reset can use it, sourced from u_softcpu below).
    wire soft_guest_hold;

    // Guest reset terms: PLL lock (RESET), ROM load and the first-BIOS gate, the interact
    // Reset PC, the splash holds, and the softcore's boot-master hold (soft_guest_hold), which
    // keeps the guest in reset until the softcore has staged settings. sdram holds on lock only.
    wire reset_wire = RESET | load_active | ~bios_ever_loaded | interact_reset
                    | splashscreen_sync2 | splash_reset_hold | splash_pending_sync2
                    | soft_guest_hold;
    wire reset_sdram_wire = RESET;

    logic reset = 1'b1;
    logic [15:0] reset_count = 16'h0000;
    logic reset_sdram = 1'b1;
    logic [15:0] reset_sdram_count = 16'h0000;

    always @(posedge clk_chipset, posedge reset_wire)
    begin
        if (reset_wire)
        begin
            reset <= 1'b1;
            reset_count <= 16'h0000;
        end
        else if (reset)
        begin
            if (reset_count != 16'hffff)
            begin
                reset <= 1'b1;
                reset_count <= reset_count + 16'h0001;
            end
            else
            begin
                reset <= 1'b0;
                reset_count <= reset_count;
            end
        end
        else
        begin
            reset <= 1'b0;
            reset_count <= reset_count;
        end
    end

    // The softcore is reset on PLL lock (RESET) only, so it comes up while the guest is still
    // held and can stage settings before releasing it. It is deliberately not held by the guest
    // terms (BIOS load, splash, the guest reset, or its own soft_guest_hold), which would deadlock.
    // The softcore must not run while its own ROM is being written. reset_soft
    // was a fixed 65535-cycle delay -- about 1.5 ms, far shorter than a slot
    // load -- so it would have started on the baked-in image and had the code
    // replaced underneath it.
    //
    // Latch "the boot-time downloads have finished" once, the first time
    // load_active falls after having been high, and hold reset until then.
    // One-shot, so a deferred slot mounted later (a floppy, say) cannot put the
    // softcore back into reset and take the OSD away.
    //
    // WATCHDOG. This condition can hang, and hanging costs the OSD -- which is
    // the only way to ask the core anything. load_active falls only when APF
    // raises dataslot_allcomplete and the ROM FIFO has drained; if either never
    // happens (a slot APF declines to stream, a word the loader never consumes)
    // the softcore stays in reset forever and the machine is mute. That is a
    // strictly worse failure than the one this gate was added to prevent:
    // starting on the baked-in image and having it replaced underneath.
    //
    // So the gate expires. Four seconds at 42.95 MHz is far longer than any
    // real slot load -- the whole 416 KB of ROM moves in about 75 ms -- so a
    // healthy boot never reaches it, and an unhealthy one still gets an OSD to
    // explain itself with.
    localparam [27:0] BOOT_DL_TIMEOUT = 28'd171_818_180;   // 4 s @ 42.95 MHz
    logic boot_dl_seen = 1'b0;
    logic boot_dl_done = 1'b0;
    logic boot_dl_late = 1'b0;
    logic [27:0] boot_dl_timer = 28'd0;
    always @(posedge clk_chipset) begin
        if (load_active)                   boot_dl_seen <= 1'b1;
        if (boot_dl_seen && !load_active)  boot_dl_done <= 1'b1;

        if (boot_dl_done)
            boot_dl_timer <= 28'd0;
        else if (boot_dl_timer == BOOT_DL_TIMEOUT)
            boot_dl_late  <= 1'b1;
        else
            boot_dl_timer <= boot_dl_timer + 28'd1;
    end
    wire boot_dl_release = boot_dl_done | boot_dl_late;

    logic reset_soft = 1'b1;
    logic [15:0] reset_soft_count = 16'h0000;
    always @(posedge clk_chipset, posedge RESET)
    begin
        if (RESET)
        begin
            reset_soft <= 1'b1;
            reset_soft_count <= 16'h0000;
        end
        else if (!boot_dl_release)
        begin
            reset_soft <= 1'b1;
            reset_soft_count <= 16'h0000;
        end
        else if (reset_soft_count != 16'hffff)
        begin
            reset_soft <= 1'b1;
            reset_soft_count <= reset_soft_count + 16'h0001;
        end
        else
            reset_soft <= 1'b0;
    end

    logic reset_cpu_ff = 1'b1;
    logic reset_cpu = 1'b1;
    logic [15:0] reset_cpu_count = 16'h0000;
    // OUT 0F0h asks for a CPU-only reset -- see the port decode further down.
    reg  f0_io_q, f0_io_qq;
    reg  soft_reset_cpu = 1'b0;
    reg  [7:0] soft_reset_count = 8'h00;

    always @(negedge clk_chipset, posedge reset)
    begin
        if (reset)
            reset_cpu_ff <= 1'b1;
        else
            reset_cpu_ff <= reset;
    end

    reg hgc_mode = 0;

    always @(negedge clk_chipset, posedge reset)
    begin
        if (reset)
        begin
            hgc_mode <= `ENABLE_HGC ? (`ENABLE_CGA ? video_1st_cfg : 1'b1) : 1'b0;
            reset_cpu <= 1'b1;
            reset_cpu_count <= 16'h0000;
        end
        // OUT 0F0h. The CPU restarts; nothing else does.
        else if (soft_reset_cpu)
        begin
            reset_cpu <= 1'b1;
            reset_cpu_count <= 16'h0000;
        end
        else if (reset_cpu)
        begin
            reset_cpu <= reset_cpu_ff;
            reset_cpu_count <= 16'h0000;
        end
        else
        begin
            if (reset_cpu_count != 16'h002A)
            begin
                reset_cpu <= reset_cpu_ff;
                reset_cpu_count <= reset_cpu_count + 16'h0001;
            end
            else
            begin
                reset_cpu <= 1'b0;
                reset_cpu_count <= reset_cpu_count;
            end
        end
    end

    always @(posedge clk_chipset, posedge reset_sdram_wire)
    begin
        if (reset_sdram_wire)
        begin
            reset_sdram <= 1'b1;
            reset_sdram_count <= 16'h0000;
        end
        else if (reset_sdram)
        begin
            if (reset_sdram_count != 16'hffff)
            begin
                reset_sdram <= 1'b1;
                reset_sdram_count <= reset_sdram_count + 16'h0001;
            end
            else
            begin
                reset_sdram <= 1'b0;
                reset_sdram_count <= reset_sdram_count;
            end
        end
        else
        begin
            reset_sdram <= 1'b0;
            reset_sdram_count <= reset_sdram_count;
        end
    end

    //
    // HOST BRIDGE
    //

    // Bridge reads: 0xF8=command window, 0x6=softcore dataslot read-back, else 0. The
    // softcore word is registered on bridge_rd (the APF samples before pulsing rd) and
    // gated to 0x6 so a command-window read cannot clobber it.
    wire [31:0] cmd_bridge_rd_data;
    wire [31:0] softcpu_bridge_rd_data;
    reg  [31:0] softcpu_rd_data_buf;
    always @(posedge clk_74a) begin
        if (bridge_rd && bridge_addr[31:28] == 4'h6)
            softcpu_rd_data_buf <= softcpu_bridge_rd_data;
    end
    always @(*) begin
        casex (bridge_addr)
            32'hF8xxxxxx: bridge_rd_data = cmd_bridge_rd_data;
            32'h6xxxxxxx: bridge_rd_data = softcpu_rd_data_buf;
            default:      bridge_rd_data = 32'd0;
        endcase
    end

    // APF host<->core commands (status, dataslot, data table) on clk_74a; savestate,
    // RTC and on-screen-notify are unused and tied off.

    wire        reset_n;   // APF-driven core reset (bridge domain)

    // Status handshake, synchronized into the clk_74a bridge domain.
    wire pll_locked_74a;
    synch_3 s_pll_lock (~RESET, pll_locked_74a, clk_74a);
    wire status_boot_done  = pll_locked_74a;
    wire status_setup_done = pll_locked_74a;
    wire status_running    = reset_n;

    // Gate APF write-requests (ROM streaming) until SDRAM init completes.
    wire initilized_sdram_74a;
    synch_3 s_sdram_init (initilized_sdram, initilized_sdram_74a, clk_74a);

    wire        dataslot_requestread;
    wire [15:0] dataslot_requestread_id;
    wire        dataslot_requestwrite;
    wire [15:0] dataslot_requestwrite_id;
    wire [31:0] dataslot_requestwrite_size;
    wire        dataslot_update;
    wire [15:0] dataslot_update_id;
    wire [31:0] dataslot_update_size;
    wire        dataslot_allcomplete;
    wire        dataslots_ready;   // sticky: APF finished the initial slot load (latched below)
    wire        osnotify_inmenu;

    // Target-dataslot: the disk softcore initiates host reads of floppy images.
    wire        target_dataslot_read;
    wire        target_dataslot_write;
    wire [15:0] target_dataslot_id;
    wire [31:0] target_dataslot_slotoffset;
    wire [31:0] target_dataslot_bridgeaddr;
    wire [31:0] target_dataslot_length;
    wire        target_dataslot_ack;
    wire        target_dataslot_done;
    wire  [2:0] target_dataslot_err;

    // Datatable port A: the disk softcore (clk_pico) reads the HDD sizes by id and
    // re-declares the Settings size through it; port B stays on clk_74a for the APF host.
    wire        clk_pico;
    wire  [9:0] datatable_addr;
    wire        datatable_wren;
    wire [31:0] datatable_data;
    wire [31:0] datatable_q;

    core_bridge_cmd icb (
        .clk                       (clk_74a),
        .reset_n                   (reset_n),
        .bridge_endian_little      (bridge_endian_little),
        .bridge_addr               (bridge_addr),
        .bridge_rd                 (bridge_rd),
        .bridge_rd_data            (cmd_bridge_rd_data),
        .bridge_wr                 (bridge_wr),
        .bridge_wr_data            (bridge_wr_data),

        .status_boot_done          (status_boot_done),
        .status_setup_done         (status_setup_done),
        .status_running            (status_running),

        .dataslot_requestread      (dataslot_requestread),
        .dataslot_requestread_id   (dataslot_requestread_id),
        .dataslot_requestread_ack  (1'b1),
        .dataslot_requestread_ok   (1'b1),

        .dataslot_requestwrite     (dataslot_requestwrite),
        .dataslot_requestwrite_id  (dataslot_requestwrite_id),
        .dataslot_requestwrite_size(dataslot_requestwrite_size),
        .dataslot_requestwrite_ack (initilized_sdram_74a),
        .dataslot_requestwrite_ok  (1'b1),

        .dataslot_update           (dataslot_update),
        .dataslot_update_id        (dataslot_update_id),
        .dataslot_update_size      (dataslot_update_size),

        .dataslot_allcomplete      (dataslot_allcomplete),

        .rtc_epoch_seconds         (),
        .rtc_date_bcd              (),
        .rtc_time_bcd              (),
        .rtc_valid                 (),

        .savestate_supported       (1'b0),
        .savestate_addr            (32'd0),
        .savestate_size            (32'd0),
        .savestate_maxloadsize     (32'd0),

        .osnotify_inmenu           (osnotify_inmenu),

        .savestate_start           (),
        .savestate_start_ack       (1'b0),
        .savestate_start_busy      (1'b0),
        .savestate_start_ok        (1'b0),
        .savestate_start_err       (1'b0),

        .savestate_load            (),
        .savestate_load_ack        (1'b0),
        .savestate_load_busy       (1'b0),
        .savestate_load_ok         (1'b0),
        .savestate_load_err        (1'b0),

        .target_dataslot_read      (target_dataslot_read),
        .target_dataslot_write     (target_dataslot_write),
        .target_dataslot_ack       (target_dataslot_ack),
        .target_dataslot_done      (target_dataslot_done),
        .target_dataslot_err       (target_dataslot_err),
        .target_dataslot_id        (target_dataslot_id),
        .target_dataslot_slotoffset(target_dataslot_slotoffset),
        .target_dataslot_bridgeaddr(target_dataslot_bridgeaddr),
        .target_dataslot_length    (target_dataslot_length),

        .clk_pico                  (clk_pico),
        .datatable_addr            (datatable_addr),
        .datatable_wren            (datatable_wren),
        .datatable_data            (datatable_data),
        .datatable_q               (datatable_q)
    );

    //
    // STORAGE SOFTCORE
    //

    // Disk management bus, mastered by the disk softcore (u_softcpu, below).
    wire [15:0] mgmt_din;              // CHIPSET readdata -> softcore
    wire [15:0] mgmt_dout;             // softcore -> CHIPSET write data
    wire [15:0] mgmt_addr;             // softcore -> CHIPSET address
    wire        mgmt_rd;               // softcore -> CHIPSET read strobe
    wire        mgmt_wr;               // softcore -> CHIPSET write strobe
    wire  [7:0] mgmt_req;              // [7:6] fdd request, [2:0] ide0 (from CHIPSET)
    assign mgmt_req[5:3] = 3'b000;

    // Floppy image size arrives in the dataslot-update event (bytes); latch it per drive.
    // A hot-swapped floppy delivers its new size in the same event, so it is race-free with
    // the media-change edge below. HDD and Settings sizes instead come from the datatable
    // by id in firmware (they load only at boot / core restart).
    reg [31:0] fdd0_slot_bytes_74a = 32'd0;
    reg [31:0] fdd1_slot_bytes_74a = 32'd0;
    always @(posedge clk_74a) begin
        if (dataslot_update && dataslot_update_id == 16'd3)
            fdd0_slot_bytes_74a <= dataslot_update_size;
        if (dataslot_update && dataslot_update_id == 16'd4)
            fdd1_slot_bytes_74a <= dataslot_update_size;
    end

    // A floppy (re)bind arrives as a dataslot update (fires even on a same-size swap).
    // Toggle a per-drive bit on its rising edge so the firmware re-mounts and floppy.v
    // re-asserts media-change (edge, not level: the pulse spans several cycles).
    reg        fdd0_rebind_74a   = 1'b0;
    reg        fdd1_rebind_74a   = 1'b0;
    reg        dataslot_update_d = 1'b0;
    always @(posedge clk_74a) begin
        dataslot_update_d <= dataslot_update;
        if (dataslot_update && !dataslot_update_d) begin
            if (dataslot_update_id == 16'd3) fdd0_rebind_74a <= ~fdd0_rebind_74a;
            if (dataslot_update_id == 16'd4) fdd1_rebind_74a <= ~fdd1_rebind_74a;
        end
    end

    wire [31:0] fdd0_slot_bytes;
    wire [31:0] fdd1_slot_bytes;
    synch_3 #(.WIDTH(32)) s_fdd0_size (
        .i   (fdd0_slot_bytes_74a),
        .o   (fdd0_slot_bytes),
        .clk (clk_chipset)
    );
    synch_3 #(.WIDTH(32)) s_fdd1_size (
        .i   (fdd1_slot_bytes_74a),
        .o   (fdd1_slot_bytes),
        .clk (clk_chipset)
    );
    wire [31:0] fdd0_disk_sectors = fdd0_slot_bytes >> 9;   // bytes / 512
    wire [31:0] fdd1_disk_sectors = fdd1_slot_bytes >> 9;   // bytes / 512

    wire fdd0_rebind;
    wire fdd1_rebind;
    synch_3 s_fdd0_rebind (
        .i   (fdd0_rebind_74a),
        .o   (fdd0_rebind),
        .clk (clk_chipset)
    );
    synch_3 s_fdd1_rebind (
        .i   (fdd1_rebind_74a),
        .o   (fdd1_rebind),
        .clk (clk_chipset)
    );

    // OSD interconnect: pocket_video locates the framebuffer read; the softcore returns a
    // 4bpp palette index + in-area flag, composited in pocket_video.
    wire [9:0] osd_hcnt;
    wire [9:0] osd_vcnt_sel;          // presented-raster line index
    wire [9:0] osd_raster_w;          // presented raster size
    wire [9:0] osd_raster_h;
    wire [3:0] osd_palette_idx;
    wire       osd_in_area;
    wire       osd_active;
    wire [15:0] rom_win;          // softcore-settable CPU-read snoop window
    wire       osd_credits_req;
    wire       osd_video_req;
    wire [8:0] vkb_key;
    wire       vkb_stb;
    wire [2:0] osd_palette;
    wire [1:0] osd_cpu_speed;
    wire [1:0] osd_bios_wr;
    wire [1:0] osd_opl2;
    wire [1:0] osd_boost;
    wire [1:0] osd_spk_vol;
    wire [1:0] osd_stereo;
    wire       osd_cms;
    wire       osd_composite;
    wire       osd_ems;
    wire [1:0] osd_ems_frame;
    wire       osd_a000;
    wire [1:0] osd_joy1;
    wire [1:0] osd_joy2;
    wire       osd_swapjoy;
    wire       osd_syncjoy;
    wire       osd_video_1st;
    wire       osd_cga_gfx;
    wire       osd_hgc_gfx;
    wire       osd_splash;
    wire [1:0] osd_gamepad;
    wire [16*9-1:0] key_cfg;   // per-control {ext, Set-2 code} file from the softcore

    // Last docked-keyboard make, tapped for the softcore key picker (pocket_keyboard -> softcpu).
    wire [7:0] dock_key_code;
    wire       dock_key_ext;
    wire       dock_key_stb;

    softcpu_subsystem u_softcpu (
        .fw_wr_clk                  (clk_chipset),
        .fw_wr_en                   (fw_wr_en_r),
        .fw_wr_addr                 (fw_wr_addr_r),
        .fw_wr_data                 (fw_wr_data_r),
        .clk_sys                    (clk_chipset),
        .clk_74a                    (clk_74a),
        .reset                      (reset_soft),
        .clk_pico                   (clk_pico),

        .fdd_request                (mgmt_req[7:6]),
        .ide0_request               (mgmt_req[2:0]),
        .fdd0_disk_size             (fdd0_disk_sectors),
        .fdd1_disk_size             (fdd1_disk_sectors),
        .datatable_addr             (datatable_addr),
        .datatable_data             (datatable_data),
        .datatable_wren             (datatable_wren),
        .datatable_q                (datatable_q),
        .fdd0_rebind                (fdd0_rebind),
        .fdd1_rebind                (fdd1_rebind),

        .mgmt_addr                  (mgmt_addr),
        .mgmt_dout                  (mgmt_dout),
        .mgmt_wr                    (mgmt_wr),
        .mgmt_rd                    (mgmt_rd),
        .mgmt_din                   (mgmt_din),

        .bridge_wr                  (bridge_wr),
        .bridge_addr                (bridge_addr),
        .bridge_wr_data             (bridge_wr_data),

        .target_dataslot_read       (target_dataslot_read),
        .target_dataslot_write      (target_dataslot_write),
        .target_dataslot_id         (target_dataslot_id),
        .target_dataslot_slotoffset (target_dataslot_slotoffset),
        .target_dataslot_bridgeaddr (target_dataslot_bridgeaddr),
        .target_dataslot_length     (target_dataslot_length),
        .target_dataslot_ack        (target_dataslot_ack),
        .target_dataslot_done       (target_dataslot_done),
        .target_dataslot_err        (target_dataslot_err),

        .bridge_rd_data_out         (softcpu_bridge_rd_data),

        .clk_pix                    (clk_pix),
        .osd_hcnt                   (osd_hcnt),
        .osd_vcnt                   (osd_vcnt_sel),
        .osd_palette_idx            (osd_palette_idx),
        .osd_in_area                (osd_in_area),

        .cont1_key                  (cont1_key_chip),
        .dock_key_code              (dock_key_code),
        .dock_key_ext               (dock_key_ext),
        .dock_key_stb               (dock_key_stb),
        .credits_active             (credits_mode_chip),
        .osd_open_req               (osd_open_req),
        .raster_w                   (osd_raster_w),
        .raster_h                   (osd_raster_h),
        .dataslots_ready            (dataslots_ready),
        .soft_guest_hold            (soft_guest_hold),
        .osd_active                 (osd_active),
        .osd_credits_req            (osd_credits_req),
        .osd_video_req              (osd_video_req),
        .vkb_key                    (vkb_key),
        .vkb_stb                    (vkb_stb),
        .osd_palette                (osd_palette),
        .osd_cpu_speed              (osd_cpu_speed),
        .osd_bios_wr                (osd_bios_wr),
        .osd_opl2                   (osd_opl2),
        .osd_boost                  (osd_boost),
        .osd_spk_vol                (osd_spk_vol),
        .osd_stereo                 (osd_stereo),
        .osd_cms                    (osd_cms),
        .osd_composite              (osd_composite),
        .osd_ems                    (osd_ems),
        .osd_ems_frame              (osd_ems_frame),
        .osd_a000                   (osd_a000),
        .osd_joy1                   (osd_joy1),
        .osd_joy2                   (osd_joy2),
        .osd_swapjoy                (osd_swapjoy),
        .osd_syncjoy                (osd_syncjoy),
        .osd_video_1st              (osd_video_1st),
        .osd_cga_gfx                (osd_cga_gfx),
        .osd_hgc_gfx                (osd_hgc_gfx),
        .osd_splash                 (osd_splash),
        .osd_gamepad                (osd_gamepad),
        .key_cfg_flat               (key_cfg),
        .st_addr                    (st_addr),
        .st_wdata                   (st_wdata),
        .st_we                      (st_we),
        .st_req                     (st_req),
        .st_done                    (st_done),
        .st_rdata                   (st_rdata),
        .post_code                  (post_code),
        .post_prev                  (post_prev),
        .post_hist                  (post_hist),
        .post_mem_addr              (post_mem_addr),
        .post_live_addr             (post_live_addr),
        .post_live_max              (post_live_max),
        .post_count                 (post_count),
        .post_max                   (post_max),
        .post_restarts              (post_restarts),
        .ivt16_off                  (ivt16_off),
        .ivt16_seg                  (ivt16_seg),
        .ivt16_wr_count             (ivt16_wr_count),
        .wr_any_count               (wr_any_count),
        .tvram_wr_count             (tvram_wr_count),
        .rd_any_count               (rd_any_count),
        .ivt_touch_count            (ivt_touch_count),
        .wr_last_addr               (wr_last_addr),
        .tvram_last_addr            (tvram_last_addr),
        .tvram_row0_code            (tvram_row0_code),
        .tvram_row0_hi              (tvram_row0_hi),
        .tvram_row0_attr            (tvram_row0_attr),
        .raw_strobes                (raw_strobes),
        .wr_low_cycles              (wr_low_cycles),
        .rd_low_cycles              (rd_low_cycles),
        .rom_win                    (rom_win),
        .rom_read_data              (rom_read_data),
        .rom_load_data              (rom_load_data),
        .rom_load_count             (rom_load_count),
        .io_port_hist               (io_port_hist),
        .io_wr_count                (io_wr_count),
`ifdef MACHINE_PC98
        .itf_bank                   (itf_bank),
`else
        .itf_bank                   (1'b0),
`endif
        .rlf_drops                  (rlf_drops),
        .rlf_level_max              ({{(16-(RLF_AW+1)){1'b0}}, rlf_level_max}),
        .rom_read_count             (rom_read_count)
    );

    //
    // SETTINGS
    //

    localparam tandy_video_mode = `ENABLE_TANDY_VIDEO;

    wire [1:0] buttons;
    wire [7:0] xtctl;

    // Interact "Reset PC" (0x50): stretch the one-shot write to a level, sync to the
    // chipset clock, and fold into the guest reset so the machine re-POSTs.
    reg [19:0] interact_reset_delay = 20'd0;
    // Interact "Extra Options" (0x54): same one-shot stretch to the softcore, which
    // opens the settings OSD (the guaranteed opener if Button Select was remapped).
    reg [19:0] osd_open_delay = 20'd0;
    // Interact list settings: each latched write-only from its bridge address, then
    // synced into the core clock below.
    reg  [1:0] wp_cfg_74a        = 2'd0;   // floppy write-protect {B:, A:}
    reg        credits_active_74a = 1'b0;  // credits showing: set by the menu action, cleared by any button
    // Pad button words come from an unvalidated ~1 ms poll and can bounce, so publish
    // a word only after it holds ~3.5 ms; analog axes are level-read and pass raw.
    reg [15:0] cont1_key_s = 16'd0;        // settled button words, all consumers below
    reg [15:0] cont2_key_s = 16'd0;
    reg [15:0] key1_cand   = 16'd0;
    reg [15:0] key2_cand   = 16'd0;
    reg [17:0] key_stable  = 18'd0;        // 2^18 clk_74a cycles = 3.5 ms
    always @(posedge clk_74a) begin
        if (cont1_key != key1_cand || cont2_key != key2_cand) begin
            key1_cand  <= cont1_key;
            key2_cand  <= cont2_key;
            key_stable <= 18'd0;
        end else if (!(&key_stable))
            key_stable <= key_stable + 18'd1;
        else begin
            cont1_key_s <= key1_cand;
            cont2_key_s <= key2_cand;
        end
    end
    wire       any_btn_74a;                // any Pocket controller-1 button, synced to this domain
    synch_3 s_anybtn (|cont1_key_s, any_btn_74a, clk_74a);
    wire       osd_credits_req_74a;        // OSD Show Credits request, synced from the softcore
    synch_3 s_osd_credits_74a (osd_credits_req, osd_credits_req_74a, clk_74a);
    reg        any_btn_74a_d = 1'b0;
    reg        osd_credits_req_74a_d = 1'b0;
    always @(posedge clk_74a) begin
        if (interact_reset_delay != 20'd0)
            interact_reset_delay <= interact_reset_delay - 20'd1;
        if (osd_open_delay != 20'd0)
            osd_open_delay <= osd_open_delay - 20'd1;
        if (bridge_wr) begin
            case (bridge_addr)
                32'h0000_0050: interact_reset_delay <= 20'hFFFFF;  // Reset & Apply
                32'h0000_0054: osd_open_delay       <= 20'hFFFFF;  // Extra Options (open OSD)
                32'h0000_006C: wp_cfg_74a        <= bridge_wr_data[1:0];
            endcase
        end
        // Show Credits request (from the OSD) and the any-button dismiss are edge-detected: the
        // button that picks Show Credits is still held, so a level dismiss would clear it at once.
        any_btn_74a_d         <= any_btn_74a;
        osd_credits_req_74a_d <= osd_credits_req_74a;
        if (osd_credits_req_74a & ~osd_credits_req_74a_d)
            credits_active_74a <= 1'b1;
        else if (any_btn_74a & ~any_btn_74a_d)
            credits_active_74a <= 1'b0;
    end
    wire       interact_reset;
    wire       osd_open_req;
    wire [1:0] wp_cfg;
    wire [2:0] palette_cfg;

    // osd_* are in the clk_chipset domain (clk_pico is a gated clk_chipset).
    wire [1:0] cpu_speed_cfg  = osd_cpu_speed;
    wire [1:0] bios_wr_cfg    = osd_bios_wr;
    wire [1:0] opl2_cfg       = osd_opl2;
    wire [1:0] boost_cfg      = osd_boost;
    wire [1:0] spk_vol_cfg    = osd_spk_vol;
    wire [1:0] stereo_mix_cfg = osd_stereo;
    wire       cms_cfg        = osd_cms;
    wire       ems_en_cfg     = osd_ems;
    wire [1:0] ems_frame_cfg  = osd_ems_frame;
    wire       a000_en_cfg    = osd_a000;
    wire       video_1st_cfg  = osd_video_1st;
    synch_3              s_interact_reset (|interact_reset_delay, interact_reset, clk_chipset);
    synch_3              s_osd_open       (|osd_open_delay,    osd_open_req,  clk_chipset);
    synch_3 #(.WIDTH(2)) s_wp_cfg         (wp_cfg_74a,        wp_cfg,        clk_chipset);
    synch_3 #(.WIDTH(16)) s_cont1_chip    (cont1_key_s,       cont1_key_chip, clk_chipset);
    synch_3 #(.WIDTH(16)) s_cont2_chip    (cont2_key_s,       cont2_key_chip, clk_chipset);
    synch_3 #(.WIDTH(32)) s_cont1_joy     (cont1_joy,         cont1_joy_chip, clk_chipset);
    synch_3 #(.WIDTH(32)) s_cont2_joy     (cont2_joy,         cont2_joy_chip, clk_chipset);
    synch_3 #(.WIDTH(3)) s_palette_cfg    (osd_palette,       palette_cfg,   clk_pix);
    wire credits_mode_pix;
    wire credits_mode_chip;
    synch_3 s_credits_pix  (credits_active_74a, credits_mode_pix,  clk_pix);
    synch_3 s_credits_chip (credits_active_74a, credits_mode_chip, clk_chipset);
    wire pause_core = pause_core_chipset | credits_mode_chip;

    // gamepad_mode picks what the pad drives: mapped keys, the game port, or the serial mouse. The
    // softcore's per-control key_cfg reaches pocket_keyboard unchanged.
    wire [1:0]  gamepad_mode = osd_gamepad;
    wire        gamepad  = (gamepad_mode == 2'd1);
    wire        mousepad = (gamepad_mode == 2'd2);
    wire [15:0] cont1_key_chip;
    wire [15:0] cont2_key_chip;
    wire [31:0] cont1_joy_chip, cont2_joy_chip;

    // Game-port options from the settings OSD: [4]=Sync-to-CPU turbo timing, [3:2]=Joystick 2,
    // [1:0]=Joystick 1; each 2-bit field is 0=Analog, 1=Digital, 2=Disabled.
    wire [1:0]  joy1_cfg = osd_joy1, joy2_cfg = osd_joy2;
    wire        swapjoy_cfg = osd_swapjoy, syncjoy_cfg = osd_syncjoy;
    wire [4:0]  joy_opts = {syncjoy_cfg, joy2_cfg, joy1_cfg};

    wire composite_cfg = osd_composite;   // CGA composite colour decode (settings bank, 0x7C)
    wire cga_gfx_cfg = osd_cga_gfx, hgc_gfx_cfg = osd_hgc_gfx;   // CGA/HGC graphics I/O enables (0 = Yes)
    wire composite = composite_cfg | xtctl[0];
    wire a000h = `ENABLE_A000_UMB ? (a000_en_cfg & ~xtctl[6]) : 1'b0;
    wire [2:0] vsync_width_osd = 3'd0;  // 0=Auto (use register), 1-7=override
    wire [2:0] hsync_width_osd = 3'd0;  // 0=Auto, 1-7=fixed width (Nx16 pixel clocks)

    reg         hgc_mode_video_ff;
    reg         cga_hw;
    reg         hercules_hw;

    always @(posedge clk_chipset)
    begin
        cga_hw                  <= `ENABLE_CGA ? (`ENABLE_HGC ? (~cga_gfx_cfg | tandy_video_mode) : 1'b1) : 1'b0;
        hercules_hw             <= `ENABLE_HGC ? (`ENABLE_CGA ? ~hgc_gfx_cfg : 1'b1) : 1'b0;
    end

    always @(posedge clk_chipset)
        hgc_mode_video_ff       <= `ENABLE_HGC ? hgc_mode : 1'b0;

    // MiSTer front-panel buttons; the Pocket has none.
    assign buttons = 2'b00;

    //
    // INPUT
    //

    wire  [7:0] kb_byte;
    wire        kb_valid;
    wire        kb_ready;

    wire        mouse_rd;
    wire        mouse_rts_n;

    wire [13:0] joy0, joy1;
    wire [15:0] joya0, joya1;

    // Pocket controllers -> game-port digital bits: [5]=fire2 [4]=fire1 [3]=up [2]=down
    // [1]=left [0]=right, from cont key bits [0]=up [1]=down [2]=left [3]=right [4]=A [5]=B.
    wire [13:0] cont1_dig = {8'd0, cont1_key_chip[5], cont1_key_chip[4],
                                   cont1_key_chip[0], cont1_key_chip[1],
                                   cont1_key_chip[2], cont1_key_chip[3]};
    wire [13:0] cont2_dig = {8'd0, cont2_key_chip[5], cont2_key_chip[4],
                                   cont2_key_chip[0], cont2_key_chip[1],
                                   cont2_key_chip[2], cont2_key_chip[3]};
    // Left stick -> analog: Pocket axes are unsigned centred on 0x80, the port wants
    // signed centred on 0, so flip the top bit. An all-zero pad (no analog) is held at
    // centre (a raw 0 would otherwise read as full deflection).
    wire [15:0] cont1_ana = (cont1_joy_chip == 32'd0) ? 16'd0
                          : {cont1_joy_chip[15:8] ^ 8'h80, cont1_joy_chip[7:0] ^ 8'h80};
    wire [15:0] cont2_ana = (cont2_joy_chip == 32'd0) ? 16'd0
                          : {cont2_joy_chip[15:8] ^ 8'h80, cont2_joy_chip[7:0] ^ 8'h80};
    // Controller 1 reaches the port only in Gamepad Mode (else its buttons type keys); controller 2
    // is always player 2. Both idle while an OSD panel is open, and a Disabled port sends nothing.
    wire        p1_on = gamepad && !osd_active && (joy1_cfg != 2'd2);
    wire        p2_on = !osd_active && (joy2_cfg != 2'd2);
    assign joy0  = p1_on ? cont1_dig : 14'd0;
    assign joy1  = p2_on ? cont2_dig : 14'd0;
    assign joya0 = p1_on ? cont1_ana : 16'd0;
    assign joya1 = p2_on ? cont2_ana : 16'd0;

    //
    // Keyboard: pad buttons + docked USB keyboard + VKB merged into one Set-2 byte
    // stream (kb_byte/kb_valid, paced by kb_ready). In mouse mode the D-pad and A/B
    // drop out (they drive the mouse); X/Y and Select/Start stay mapped keys.
    wire [15:0] kb_buttons = mousepad ? (cont1_key_s & 16'hFFC0) : cont1_key_s;

    pocket_keyboard #(.clk_rate(cur_rate)) u_pocket_keyboard (
        .clk          (clk_chipset),
        .reset        (reset),
        .buttons      (kb_buttons),
        .gamepad      (gamepad),
        .osd_active   (osd_active | credits_mode_chip),
        .vkb_key      (vkb_key),
        .vkb_stb      (vkb_stb),
        .key_cfg      (key_cfg),
        .cont3_joy    (cont3_joy),
        .cont3_trig   (cont3_trig),
        .cont3_key    (cont3_key),
        .kb_byte      (kb_byte),
        .kb_valid     (kb_valid),
        .kb_ready     (kb_ready),
        .kbd_code     (dock_key_code),
        .kbd_ext      (dock_key_ext),
        .kbd_stb      (dock_key_stb)
    );

    //
    // Mouse: docked USB mouse (cont4_*) -> Microsoft serial byte stream on COM1, paced
    // by RTS. In mouse mode the pad's D-pad and A/B drive it too; quiet under an overlay.
    //
    wire [5:0] mouse_pad = (mousepad && !(osd_active | credits_mode_chip)) ?
                           cont1_key_chip[5:0] : 6'd0;

    pocket_mouse #(.clk_rate(cur_rate)) u_pocket_mouse (
        .clk          (clk_chipset),
        .cont4_joy    (cont4_joy),
        .cont4_key    (cont4_key),
        .cont4_trig   (cont4_trig),
        .pad          (mouse_pad),
        .rts_n        (mouse_rts_n),
        .rd           (mouse_rd)
    );

    //
    // ROM AND BIOS LOAD
    //

    wire        ioctl_download;
    wire  [7:0] ioctl_index;
    wire        ioctl_wr;
    wire [24:0] ioctl_addr;
    wire [15:0] ioctl_data;
    reg         ioctl_wait;

    // ROM-load reset hold: keep the machine in reset while APF streams a slot, and from
    // power-on until the first load lands, so the CPU never runs without a BIOS. The
    // BIOS write path sits on the separate reset_sdram.
    wire        is_downloading;      // APF slot load active (clk_chipset)
    wire        load_active;         // is_downloading OR the FIFO still draining
    reg         bios_ever_loaded = 1'b0;

    // Track an APF->core slot stream (requestwrite..allcomplete) on the bridge clock,
    // then sync into the chipset domain for the loader and reset hold.
    reg         is_downloading_74a = 1'b0;
    reg  [15:0] download_id_74a = 16'd0;
    // Sticky: set once APF signals the initial slot load is complete. The boot-master softcore
    // waits on it before reading the settings slot, so it reads loaded data, not a race.
    reg         dataslots_ready_74a = 1'b0;
    always @(posedge clk_74a) begin
        if (dataslot_requestwrite) begin
            is_downloading_74a <= 1'b1;
            download_id_74a    <= dataslot_requestwrite_id;
        end
        else if (dataslot_allcomplete)
            is_downloading_74a <= 1'b0;
        if (dataslot_allcomplete)
            dataslots_ready_74a <= 1'b1;
    end
    synch_3 s_isdl (is_downloading_74a, is_downloading, clk_chipset);
    synch_3 s_dsready (dataslots_ready_74a, dataslots_ready, clk_chipset);
    wire [15:0] download_id;
    synch_3 #(.WIDTH(16)) s_dlid (download_id_74a, download_id, clk_chipset);

    reg load_active_d = 1'b0;
    always @(posedge clk_chipset) begin
        load_active_d <= load_active;
        if (load_active_d & ~load_active)   // APF done AND the FIFO fully drained
            bios_ever_loaded <= 1'b1;
    end

    // APF streams the BIOS slot into the 0x1xxxxxxx window; data_loader makes 16-bit
    // (addr,data) writes. APF can't be backpressured, so a FIFO catches every write and
    // the copier feeds the BIOS FSM as an ioctl stream that honours ioctl_wait.
    wire        dl_wr;
    wire [27:0] dl_addr;
    wire [15:0] dl_data;

    data_loader #(
        .ADDRESS_MASK_UPPER_4 (4'h1),
        .ADDRESS_SIZE         (28),
        .OUTPUT_WORD_SIZE     (2),
        .WRITE_MEM_CLOCK_DELAY(16)
    ) rom_data_loader (
        .clk_74a             (clk_74a),
        .clk_memory          (clk_chipset),
        .bridge_wr           (bridge_wr),
        .bridge_endian_little(bridge_endian_little),
        .bridge_addr         (bridge_addr),
        .bridge_wr_data      (bridge_wr_data),
        .write_en            (dl_wr),
        .write_addr          (dl_addr),
        .write_data          (dl_data)
    );

    // Decoupling FIFO, entry = {xtide, addr[24:0], data[15:0]}: the slot tag rides each
    // entry so a later stream can't retag a draining tail. 256 deep; the handshake loader
    // keeps it shallow and load_active holds reset until it drains, so it never overflows.
    // The firmware slot's whole window, not just the part copied into the ROM:
    // every word of it has to stay out of the FIFO, including the parts outside
    // the 8x16 ANK range.
    wire fw_dl_slot = (dl_addr[27:16] == 12'h004);

    // Which words the BIOS loader will actually consume.
    //
    // Anything else that reaches the FIFO stays there forever, because the FSM
    // only drains slots it recognises -- and a FIFO that never empties holds
    // load_active high, which holds the softcore in reset. A settings slot, or
    // any future one with its own consumer, would deadlock the same way the
    // firmware slot did.
    //
    // PC-98's slots are decided purely by address, so the predicate is exact.
    // The PC/AT build also selects by index (XT-IDE), which is not available
    // here, so it keeps its old behaviour minus the firmware window.
`ifdef MACHINE_PC98
    wire rom_dl_wanted = (dl_addr[24:17] == 8'h00)      // bios.rom
                       | (dl_addr[24:15] == 10'h004)    // itf.rom
                       | (dl_addr[24:20] == 5'h01);     // font.rom
`else
    wire rom_dl_wanted = ~fw_dl_slot;
`endif

    // 2048 entries, not 256.
    //
    // 256 was enough when the only slots were a 96 KB BIOS and a 32 KB ITF, and
    // the hardware reported DROP 0. font.rom added 282 KB to the same path and
    // the hardware now reports DROP 58: the FIFO overflows, and an overflow
    // here is silent -- data_loader has no ready input, so there is no
    // backpressure to the APF bridge and these entries are the only elasticity
    // in the whole path. Fifty-eight lost words is fifty-eight holes somewhere
    // in a ROM the guest then executes.
    //
    // 2048 x 42 bits is about nine M10K blocks, which this design can afford far
    // more easily than it can afford a corrupted BIOS.
    localparam RLF_AW = 11;
    reg  [41:0]     romfifo [0:(1<<RLF_AW)-1];
    reg  [RLF_AW:0] rlf_wptr = 0;
    reg  [RLF_AW:0] rlf_rptr = 0;
    wire            rlf_empty = (rlf_wptr == rlf_rptr);
    wire            rlf_full  = (rlf_wptr[RLF_AW-1:0] == rlf_rptr[RLF_AW-1:0])
                              && (rlf_wptr[RLF_AW] != rlf_rptr[RLF_AW]);
    wire [41:0]     rlf_head  = romfifo[rlf_rptr[RLF_AW-1:0]];
    reg             rlf_pop;

    // Drain gate: keep loading until APF is done AND the FIFO is emptied, so the
    // tail of the ROM cannot be lost if allcomplete races ahead of the last write.
    assign load_active = is_downloading | ~rlf_empty;

    // "it never overflows" was an assumption, never a measurement, and a full
    // FIFO here drops the word SILENTLY -- data_loader has no ready input, so
    // there is no backpressure to the APF bridge and these 256 entries are the
    // only elasticity in the path. How fast this drains depends on how long
    // RAM.sv takes per byte, which depends on the SDRAM controller: the shim
    // answers in ten cycles where KFSDRAM answers in five, so a change of
    // controller changes whether the assumption holds.
    //
    // That matters because run#106 showed the BIOS image arriving incomplete:
    // the loader never presented F000:D882-D883 or D88E-D88F, while every other
    // byte of that window was written correctly. A dropped ioctl word is
    // exactly that shape, and it would be invisible to every SDRAM testbench.
    //
    // So count them, and record how close the FIFO ever came to full.
    reg [15:0] rlf_drops = 16'd0;
    reg [RLF_AW:0] rlf_level_max = '0;
    wire [RLF_AW:0] rlf_level = rlf_wptr - rlf_rptr;

    // Only words the BIOS loader will actually CONSUME go in here.
    //
    // The firmware slot has its own path -- a direct tap on dl_wr into the
    // softcore's ROM -- and putting its words in this FIFO as well was a
    // deadlock: the loader FSM only drains slots it recognises, so they sat
    // here forever, rlf_empty never came true, load_active never fell, and the
    // softcore (held in reset until the boot downloads finish) never started.
    // No OSD, ever, on a machine that was otherwise running.
    //
    // Any future slot with its own consumer has to be excluded here too.
    always @(posedge clk_chipset) begin
        if (dl_wr && ~rlf_full && rom_dl_wanted) begin
            romfifo[rlf_wptr[RLF_AW-1:0]] <= {download_id == 16'd2, dl_addr[24:0], dl_data};
            rlf_wptr <= rlf_wptr + 1'b1;
        end
        if (dl_wr && rlf_full && rlf_drops != 16'hFFFF)
            rlf_drops <= rlf_drops + 16'd1;
        if (rlf_level > rlf_level_max)
            rlf_level_max <= rlf_level;
        if (rlf_pop && ~rlf_empty)
            rlf_rptr <= rlf_rptr + 1'b1;
    end

    // Copier: present the FIFO head to the BIOS FSM as ioctl, honoring ioctl_wait.
    assign ioctl_download = load_active;
    assign ioctl_index    = rlf_head[41] ? 8'd2 : 8'd0;  // EC00 (XT-IDE)->2, BIOS->0
    assign ioctl_addr     = rlf_head[40:16];
    assign ioctl_data     = rlf_head[15:0];
    reg ioctl_wr_r = 1'b0;
    assign ioctl_wr = ioctl_wr_r;

    always @(posedge clk_chipset) begin
        rlf_pop <= 1'b0;
        if (~load_active)
            ioctl_wr_r <= 1'b0;
        else if (ioctl_wr_r) begin
            if (ioctl_wait) begin        // FSM latched the presented word
                ioctl_wr_r <= 1'b0;
                rlf_pop    <= 1'b1;
            end
        end
        else if (~ioctl_wait && ~rlf_empty)
            ioctl_wr_r <= 1'b1;
    end

`ifdef MACHINE_PC98
    // ANK font load, straight off data_loader rather than through the ROM FIFO
    // and the ext port. It is a 4 KB BRAM with no handshake, so queueing it
    // behind the BIOS load would buy nothing.
    //
    // data.json puts font.rom at bridge 0x10100000, and FONT.ROM's 8x16 ANK set
    // is the contiguous 0x0800-0x17FF of the file (np2 font/fontv98.c), so the
    // window is dl_addr 0x100800-0x1017FF and the BRAM address is the offset
    // within it.
    wire        font_dl_hit  = dl_wr && (dl_addr[27:16] == 12'h010)
                                     && (dl_addr[15:0] >= 16'h0800)
                                     && (dl_addr[15:0] <  16'h1800);
    wire [10:0] font_dl_addr = dl_addr[11:1] - 11'h400;   // word index from 0x800
`endif

    // ---------------------------------------------------------- firmware slot
    //
    // The softcore's ROM is $readmemh'd from firmware.vh at synthesis, which
    // means a one-line change to an on-screen readout costs a fifteen-to-twenty
    // minute Quartus compile. Several of this session's builds were exactly
    // that. A data slot lets the image be replaced by copying a file.
    //
    // The baked-in contents stay as the default: with no file in the slot,
    // nothing is written and the core behaves as it always did. So this cannot
    // brick a card that is missing the file.
    //
    // data.json puts firmware.bin at bridge 0x10040000. data_loader hands over
    // sixteen bits at a time and the ROM is 32 bits wide, so two transfers make
    // a word -- low half first, matching the little-endian image.
    wire        fw_dl_hit  = dl_wr && fw_dl_slot;
    wire [12:0] fw_word    = dl_addr[14:2];
    reg  [15:0] fw_lo;
    reg         fw_wr_en_r;
    reg  [12:0] fw_wr_addr_r;
    reg  [31:0] fw_wr_data_r;

    always @(posedge clk_chipset) begin
        fw_wr_en_r <= 1'b0;
        if (fw_dl_hit) begin
            if (!dl_addr[1]) begin
                fw_lo <= dl_data;
            end else begin
                fw_wr_addr_r <= fw_word;
                fw_wr_data_r <= {dl_data, fw_lo};
                fw_wr_en_r   <= 1'b1;
            end
        end
    end

    reg [4:0]  bios_load_state = 4'h0;
    reg [1:0]  bios_protect_flag;
    reg        bios_access_request;
    reg [19:0] bios_access_address;
    reg [15:0] bios_write_data;
    reg        bios_write_n;
    reg [7:0]  bios_write_wait_cnt;
    reg        bios_write_byte_cnt;
    reg        tandy_bios_write;
    reg        font_bank_write;
`ifdef MACHINE_PC98
    // PC-98: BIOS.ROM is 0x18000 bytes at physical 0x0E8000, which is where np2
    // reads it to and what the file size says (docs/PC98_MACHINE_SPEC.md F1).
    // Ninety-six KB, so the slot's address needs seventeen bits, not sixteen --
    // the PC/AT form below masks addr[24:16] to zero and lands everything in
    // one 64 KB page at F0000, which would fold the top third of the image back
    // over the bottom.
    localparam [19:0] PC98_BIOS_BASE = 20'h E8000;
    localparam [19:0] PC98_ITF_BASE  = 20'h F8000;
    // Which ROM a word belongs to is decided by the slot's bridge ADDRESS
    // alone, not by the slot id as well. data.json puts bios.rom at
    // 0x10000000 and itf.rom at 0x10020000, so the two never overlap and there
    // is one discriminator rather than two that have to agree.
    //
    //   bios.rom  0x00000-0x17FFF (96 KB) -> E8000-FFFFF
    //   itf.rom   0x20000-0x27FFF (32 KB) -> F8000-FFFFF, in the shadow bank
    //
    // The ITF occupies the SAME guest addresses as the top of the system BIOS,
    // which is why it goes to the shadow: the loader asserts select_itf while
    // writing and RAM.sv routes it there, the mechanism the Tandy BIOS shadow
    // already uses.
    wire select_pcxt  = (ioctl_addr[24:17] == 8'h00);
    wire select_itf   = (ioctl_addr[24:15] == 10'h004);
    // font.rom, 0x46800 bytes at bridge 0x10100000. The slot's address is
    // chosen so the low twenty bits ARE the file offset: the font bank
    // redirects those to 0x400000 upward inside RAM.sv, so the loader needs no
    // arithmetic and the ext port's twenty bits are enough for a 282 KB image.
    wire select_font  = (ioctl_addr[24:20] == 5'h01);
    wire select_tandy = 1'b0;
    wire select_xtide = 1'b0;
    wire select_shadow = select_itf;

    wire [19:0] bios_access_address_wire =
         select_pcxt ? (PC98_BIOS_BASE + {3'b000, ioctl_addr[16:0]}) :
         select_itf  ? (PC98_ITF_BASE  + {5'b00000, ioctl_addr[14:0]}) :
         select_font ? ioctl_addr[19:0] : 20'hFFFFF;

    // Restore the reset vector.
    //
    // A real PC-98's system BIOS holds a far jump to its own entry point at
    // FFFF:0000. Checked against a genuine PC-9821Ce2 dump (BANK7, the system
    // BIOS at F8000):
    //
    //     BANK7      EA 00 00 80 FD      JMP FD80:0000
    //     BIOS.ROM   CD 19 00 80 FD      INT 19h, with 00 80 FD left behind
    //
    // The trailing three bytes are identical, so the image circulating as
    // BIOS.ROM is that same vector with its first TWO bytes patched over. The
    // real entry survives untouched at FD80:0000 -- our dump has
    // EB 02 EB 5D FA 33 C0 8E D8 E4 35 (CLI, clear DS, IN AL,35h: the PC-98
    // system port), 8086 code throughout, matching BANK7 almost instruction
    // for instruction.
    //
    // So this is not a workaround, it is undoing someone else's edit, and it
    // is what makes a faithful boot possible without an ITF: the ITF's job is
    // to size memory and bank-switch, and mapping the post-ITF image does that
    // for us. np2 writes exactly the same five bytes (bios.c: mem[0xffff0] =
    // 0xea, then 0xfd800000) -- it restores the vector too.
    //
    // Only the word at FFFF0 differs, so one address needs intercepting.
    wire        rom_patch_reset = select_pcxt
                                & (bios_access_address_wire == 20'hFFFF0);
    wire [15:0] rom_data_in     = rom_patch_reset ? 16'h00EA : ioctl_data;
`else
    wire select_pcxt  = (ioctl_index[5:0] == 0) && (ioctl_addr[24:16] == 9'b000000000);
    wire select_tandy = `ROM_IS_TANDY ? (ioctl_index[5:0] == 1) && (ioctl_addr[24:16] == 9'b000000000) : 1'b0;
    wire select_xtide = ioctl_index == 2;
    wire select_shadow = select_tandy;

    wire [19:0] bios_access_address_wire = select_pcxt  ? { 4'b1111, ioctl_addr[15:0]} :
         select_tandy ? { 4'b1111, ioctl_addr[15:0]} :
         select_xtide ? { 6'b111011, ioctl_addr[13:0]} :
         20'hFFFFF;

    wire [15:0] rom_data_in = ioctl_data;
`endif

`ifdef MACHINE_PC98
    wire bios_load_n = ~(ioctl_download & (select_pcxt | select_itf | select_font));
`else
    wire bios_load_n = ~(ioctl_download & (select_pcxt | select_tandy | select_xtide));
`endif

    always @(posedge clk_chipset, posedge reset_sdram)
    begin
        if (reset_sdram)
        begin
            bios_protect_flag   <= 2'b11;
            bios_access_request <= 1'b0;
            bios_access_address <= 20'hFFFFF;
            bios_write_data     <= 16'hFFFF;
            bios_write_n        <= 1'b1;
            bios_write_wait_cnt <= 'h0;
            bios_write_byte_cnt <= 1'h0;
            tandy_bios_write    <= 1'b0;
            font_bank_write     <= 1'b0;
            ioctl_wait          <= 1'b1;
            bios_load_state     <= 4'h00;
        end
        else if (~initilized_sdram)
        begin
            bios_protect_flag   <= 2'b11;
            bios_access_request <= 1'b0;
            bios_access_address <= 20'hFFFFF;
            bios_write_data     <= 16'hFFFF;
            bios_write_n        <= 1'b1;
            bios_write_wait_cnt <= 'h0;
            bios_write_byte_cnt <= 1'h0;
            ioctl_wait          <= 1'b1;
            bios_load_state     <= 4'h00;
        end
        else
        begin
            casez (bios_load_state)
                4'h00:
                begin
                    bios_protect_flag   <= ~bios_wr_cfg;  // bios_writable
                    bios_access_address <= 20'hFFFFF;
                    bios_write_data     <= 16'hFFFF;
                    bios_write_n        <= 1'b1;
                    bios_write_wait_cnt <= 'h0;
                    bios_write_byte_cnt <= 1'h0;
                    tandy_bios_write    <= 1'b0;
                    if (~ioctl_download)
                    begin
                        bios_access_request <= 1'b0;
                        ioctl_wait          <= 1'b0;
                    end
                    else
                    begin
                        bios_access_request <= 1'b1;
                        ioctl_wait          <= 1'b1;
                    end

                    if ((ioctl_download) && (~processor_ready) && (address_direction))
                        bios_load_state <= 4'h01;
                    else
                        bios_load_state <= 4'h00;
                end
                4'h01:
                begin
                    bios_protect_flag   <= 2'b00;
                    bios_access_request <= 1'b1;
                    bios_write_byte_cnt <= 1'h0;
                    tandy_bios_write    <= select_shadow;
                    // ...and the font's bank, which nothing ever set.
                    //
                    // font_bank_write was declared, reset to zero, and held --
                    // and never once assigned a one. So font_bank_load stayed
                    // low, RAM.sv never redirected the load to 0x400000, and
                    // FONT.ROM went into the low megabyte at its own file
                    // offset instead. The glyph fetcher reads 0x400000 upward,
                    // which nothing had written.
                    //
                    // That is why this machine has never drawn a character.
                    // The hardware readout showed the text VRAM holding
                    // 4B 41 4E 4A 49 -- "KANJI" -- with attribute C1, yellow
                    // and visible and not reversed, and the screen showing a
                    // solid yellow band: the right cells, the right colour,
                    // and every glyph row read out of memory nobody filled.
                    //
                    // Same latch point and same reason as the shadow decision
                    // above: select_font comes from the live ioctl_addr, and
                    // by state 02 it can already describe the next slot.
                    font_bank_write     <= select_font;
                    if (~ioctl_download)
                    begin
                        bios_access_address <= 20'hFFFFF;
                        bios_write_data     <= 16'hFFFF;
                        bios_write_n        <= 1'b1;
                        bios_write_wait_cnt <= 'h0;
                        ioctl_wait          <= 1'b0;
                        bios_load_state     <= 4'h00;
                    end
                    else if ((~ioctl_wr) || (bios_load_n))
                    begin
                        bios_access_address <= 20'hFFFFF;
                        bios_write_data     <= 16'hFFFF;
                        bios_write_n        <= 1'b1;
                        bios_write_wait_cnt <= 'h0;
                        ioctl_wait          <= 1'b0;
                        bios_load_state     <= 4'h01;
                    end
                    else
                    begin
                        bios_access_address <= bios_access_address_wire;
                        bios_write_data     <= rom_data_in;
                        bios_write_n        <= 1'b1;
                        bios_write_wait_cnt <= 'h0;
                        ioctl_wait          <= 1'b1;
                        bios_load_state     <= 4'h02;
                    end
                end
                4'h02:
                begin
                    bios_protect_flag   <= 2'b00;
                    bios_access_request <= 1'b1;
                    bios_access_address <= bios_access_address;
                    bios_write_data     <= bios_write_data;
                    bios_write_byte_cnt <= bios_write_byte_cnt;
                    // HOLD both, do not re-read the selects here.
                    //
                    // select_shadow comes from the live ioctl_addr, and by the
                    // time this state runs the copier has usually popped the
                    // FIFO -- so it reflects the NEXT entry, not the word being
                    // written. Inside a slot that is harmless because the
                    // neighbouring word belongs to the same slot, but the LAST
                    // word of a slot gets judged by the next slot's address and
                    // lands in the wrong bank. The shadow decision belongs with
                    // the address, and the address is latched in state 01.
                    tandy_bios_write    <= tandy_bios_write;
                    font_bank_write     <= font_bank_write;
                    ioctl_wait          <= 1'b1;

                    // Hold the external write until ram_rw_complete, or a safety
                    // timeout (a hang backstop; a normal write never reaches it).
                    if (ram_rw_complete || (bios_write_wait_cnt == 8'd63))
                    begin
                        bios_write_n        <= 1'b1;
                        bios_write_wait_cnt <= 8'h0;
                        bios_load_state     <= 4'h03;
                    end
                    else
                    begin
                        bios_write_n        <= 1'b0;
                        bios_write_wait_cnt <= bios_write_wait_cnt + 8'h1;
                        bios_load_state     <= 4'h02;
                    end
                end
                4'h03:
                begin
                    bios_protect_flag   <= 2'b00;
                    bios_access_request <= 1'b1;
                    bios_access_address <= bios_access_address;
                    bios_write_data     <= bios_write_data;
                    bios_write_n        <= 1'b1;
                    bios_write_byte_cnt <= bios_write_byte_cnt;
                    // HOLD the bank, for the same reason state 02 holds it: one
                    // 16-bit word is written as two byte accesses, and both
                    // belong to the address latched in state 01. Clearing it
                    // here sent the SECOND byte of every word to the normal bank
                    // instead of the shadow, so the ITF went in with only its
                    // even-offset bytes and the guest read its own reset vector
                    // back as EA A8 00 A8 F8 -- correct on the even offsets,
                    // untouched SDRAM on the odd ones.
                    tandy_bios_write    <= tandy_bios_write;
                    font_bank_write     <= font_bank_write;
                    ioctl_wait          <= 1'b1;
                    bios_write_wait_cnt <= bios_write_wait_cnt + 8'h1;

                    // Short settle so the RAM controller returns to IDLE (and
                    // ram_rw_complete drops) before the next byte write.
                    //
                    // Was 4 (five clocks). RAM.sv leaves COMPLETE_RAM_RW as
                    // soon as write_command drops, which is the cycle after
                    // bios_write_n goes high, so one clock is all this needs --
                    // and it is per BYTE, so four of them was most of a tenth
                    // of the load budget. APF gives about 10.9 chipset clocks
                    // per byte and run#107 measured 4682 words dropped for
                    // being slower than that.
                    if (bios_write_wait_cnt >= 8'd1)
                        bios_load_state     <= 4'h04;
                    else
                        bios_load_state     <= 4'h03;
                end
                4'h04:
                begin
                    bios_protect_flag   <= 2'b00;
                    bios_access_request <= 1'b1;
                    bios_access_address <= bios_access_address + 'h1;
                    bios_write_data     <= {8'hFF, bios_write_data[15:8]};
                    bios_write_n        <= 1'b1;
                    bios_write_wait_cnt <= 'h0;
                    bios_write_byte_cnt <= ~bios_write_byte_cnt;
                    // Held here too: this state advances to the word's second
                    // byte and hands back to state 02 to write it.
                    tandy_bios_write    <= tandy_bios_write;
                    font_bank_write     <= font_bank_write;
                    ioctl_wait          <= 1'b1;
                    if (bios_write_byte_cnt == 1'b0)
                        bios_load_state     <= 4'h02;
                    else
                        bios_load_state     <= 4'h01;
                end
                default:
                begin
                    bios_protect_flag   <= 2'b11;
                    bios_access_request <= 1'b0;
                    bios_access_address <= 20'hFFFFF;
                    bios_write_data     <= 16'hFFFF;
                    bios_write_n        <= 1'b1;
                    bios_write_wait_cnt <= 'h0;
                    bios_write_byte_cnt <= 1'h0;
                    tandy_bios_write    <= 1'b0;
                    ioctl_wait          <= 1'b0;
                    bios_load_state     <= 4'h00;
                end
            endcase
        end
    end

    //
    // SDRAM SELF-TEST MASTER  (docs/P0_SELFTEST_SPEC.md)
    //
    // sdram_mp does not boot the board and every logical hypothesis is spent,
    // with all simulation green; the only signal from hardware has been a POST
    // beep count. This lets the softcore read and write guest SDRAM directly
    // while the 8088 is held in reset, so the firmware can report the first
    // mismatching address instead of us guessing from a beep.
    //
    // It borrows CHIPSET's external-access port -- the one the BIOS loader
    // already uses, so the write direction is proven. The read direction is
    // the same port's memory_read_n_ext, which existed but was tied off.
    //
    // Arbitration is strictly time-sliced and the loader always wins: a slot
    // download and a self-test cannot overlap in practice (the test runs after
    // the load, before the guest is released), but nothing here relies on that.

    wire  [7:0] chipset_ext_rdata;   // RAM.sv read byte, tapped out of CHIPSET
    wire [19:0] st_addr;
    wire  [7:0] st_wdata;
    wire        st_we;
    wire        st_req;
    wire        st_done;
    wire  [7:0] st_rdata;
    wire        st_run, st_wr_n, st_rd_n;

    sdram_selftest_master u_selftest (
        .clk              (clk_chipset),
        .rst              (reset_sdram),
        .req              (st_req),
        .we               (st_we),
        .addr             (st_addr),
        .wdata            (st_wdata),
        .done             (st_done),
        .rdata            (st_rdata),
        .initilized_sdram (initilized_sdram),
        .loader_busy      (ioctl_download),
        .run              (st_run),
        .write_n          (st_wr_n),
        .read_n           (st_rd_n),
        .ram_rw_complete  (ram_rw_complete),
        .ext_rdata        (chipset_ext_rdata)
    );

    //
    // POST MONITOR
    //
    // The BIOS reports progress on I/O port 0x80. Surfacing it turns hardware
    // debugging from "it stops between two boot sounds" into "it stops at POST
    // 04" -- the base 64 KB memory test at F000:E11A. Observational only.
    //
    wire [19:0] chipset_address;
    wire        chipset_io_write_n, chipset_memory_read_n, chipset_memory_write_n;
    wire        chipset_aen;
    wire  [7:0] post_code, post_prev;
    wire [63:0] post_hist;
    wire [19:0] post_mem_addr, post_live_addr, post_live_max;
    wire [15:0] post_count;
    wire  [7:0] post_max;
    wire [15:0] post_restarts;
    wire [15:0] ivt16_off, ivt16_seg;
    wire  [7:0] ivt16_wr_count;
    wire [15:0] wr_any_count, rd_any_count, ivt_touch_count;
    wire [15:0] tvram_wr_count;
    wire [19:0] wr_last_addr;
    wire [19:0] tvram_last_addr;
    wire [63:0] tvram_row0_code, tvram_row0_attr, tvram_row0_hi;
    wire [63:0] pc98_tvfill_view;
    wire [15:0] pc98_rowbuf_freq_count, pc98_rowbuf_fvalid_count;
    wire  [3:0] raw_strobes;
    wire [15:0] wr_low_cycles, rd_low_cycles;
    wire [127:0] rom_read_data;
    wire [127:0] rom_load_data;
    wire   [7:0] rom_load_count;
    wire  [7:0] rom_read_count;
    wire [63:0] io_port_hist;
    wire [15:0] io_wr_count;

    post_monitor u_post (
        .clk            (clk_chipset),
        .rst            (reset_sdram),
        .address        (chipset_address),
        .cpu_data       (cpu_data_bus),
        .bus_data       (data_bus),
        .io_write_n     (chipset_io_write_n),
        .address_enable_n (chipset_aen),
        .memory_read_n  (chipset_memory_read_n),
        .memory_write_n (chipset_memory_write_n),
        .post_code      (post_code),
        .post_prev      (post_prev),
        .post_hist      (post_hist),
        .last_mem_addr  (post_mem_addr),
        .live_mem_addr  (post_live_addr),
        .live_mem_max   (post_live_max),
        .post_count     (post_count),
        .post_max       (post_max),
        .restart_count  (post_restarts),
        .ivt16_off      (ivt16_off),
        .ivt16_seg      (ivt16_seg),
        .ivt16_wr_count (ivt16_wr_count),
        .wr_any_count   (wr_any_count),
        .tvram_wr_count (tvram_wr_count),
        .rd_any_count   (rd_any_count),
        .ivt_touch_count(ivt_touch_count),
        .wr_last_addr   (wr_last_addr),
        .tvram_last_addr(tvram_last_addr),
        .tvram_row0_code(tvram_row0_code),
        .tvram_row0_hi  (tvram_row0_hi),
        .pc98_tvfill_view (pc98_tvfill_view),
        .pc98_rowbuf_freq_count (pc98_rowbuf_freq_count),
        .pc98_rowbuf_fvalid_count (pc98_rowbuf_fvalid_count),
        .tvram_row0_attr(tvram_row0_attr),
        .raw_strobes    (raw_strobes),
        .wr_low_cycles  (wr_low_cycles),
        .rd_low_cycles  (rd_low_cycles),
        .rom_win        (rom_win),
        .rom_read_data  (rom_read_data),
        .rom_read_count (rom_read_count),
        .ld_addr        (bios_access_address),
        .ld_data        (bios_write_data[7:0]),
        .ld_we_n        (bios_write_n),
        .rom_load_data  (rom_load_data),
        .rom_load_count (rom_load_count),
        .io_port_hist   (io_port_hist),
        .io_wr_count    (io_wr_count)
    );

    //
    // SPLASH
    //

    reg splash_off = 1'b1;
    reg [24:0] splash_cnt = 0;
    reg [3:0] splash_cnt2 = 0;
    reg splashscreen = 1'b0;
    reg splash_pending = 1'b1;
    reg splash_pending_sync1 = 1'b1;
    reg splash_pending_sync2 = 1'b1;
    reg splashscreen_sync1 = 0;
    reg splashscreen_sync2 = 0;
    reg splashscreen_sync_prev = 0;
    reg splash_reset_hold = 0;
    reg [16:0] splash_reset_cnt = 17'd0;
    localparam [16:0] SPLASH_RESET_HOLD = 17'd131072;
    reg phys_reset_hold = 0;
    reg [23:0] phys_reset_cnt = 24'd0;
    localparam [23:0] PHYS_RESET_HOLD = 24'd2863600;
    wire splash_on_28_cfg;
    wire video_1st_28;
    wire bios_ever_loaded_28;
    wire soft_guest_hold_28;
    synch_3 s_splash_on   (osd_splash,       splash_on_28_cfg,    clk_28_636);
    synch_3 s_video_1st   (osd_video_1st,    video_1st_28,        clk_28_636);
    synch_3 s_bios_loaded (bios_ever_loaded, bios_ever_loaded_28, clk_28_636);
    synch_3 s_soft_hold   (soft_guest_hold,  soft_guest_hold_28,  clk_28_636);
    // The splash draws into CGA VRAM, so a Hercules boot skips it rather than
    // holding the machine on a blank mono screen.
    wire splash_on_28 = splash_on_28_cfg & ~video_1st_28;

    always @(posedge clk_28_636)
    if (ce_14_318)
    begin
        splash_off <= ~splash_on_28;
        if (RESET || buttons[1])
        begin
            phys_reset_hold <= 1'b1;
            phys_reset_cnt <= 24'd0;
        end
        else if (phys_reset_hold)
        begin
            if (phys_reset_cnt == PHYS_RESET_HOLD)
                phys_reset_hold <= 1'b0;
            else
                phys_reset_cnt <= phys_reset_cnt + 24'd1;
        end

        if (splash_pending)
        begin
            // Hold until the BIOS has streamed in and the softcore has pushed the saved settings
            // (soft_guest_hold clears, so the splash enable is valid), then show the splash if
            // enabled, otherwise release straight to POST.
            if (bios_ever_loaded_28 & ~soft_guest_hold_28)
            begin
                if (~splash_off)
                begin
                    splashscreen <= 1'b1;
                    splash_cnt <= 0;
                    splash_cnt2 <= 0;
                end
                splash_pending <= 1'b0;
            end
        end
        else if (splashscreen)
        begin
            if (splash_off)
            begin
                splashscreen <= 0;
            end
            else if(splash_cnt2 == 5) // 5 seconds delay
            begin
                splashscreen <= 0;
            end
            else if (splash_cnt == 14318000)
            begin // 1 second at 14.318Mhz
                splash_cnt2 <= splash_cnt2 + 1;
                splash_cnt <= 0;
            end
            else
                splash_cnt <= splash_cnt + 1;
        end

    end

    always @(posedge clk_chipset)
    begin
        splashscreen_sync1 <= splashscreen;
        splashscreen_sync2 <= splashscreen_sync1;
        splashscreen_sync_prev <= splashscreen_sync2;
        splash_pending_sync1 <= splash_pending;
        splash_pending_sync2 <= splash_pending_sync1;

        if (splashscreen_sync_prev && ~splashscreen_sync2)
        begin
            splash_reset_hold <= 1'b1;
            splash_reset_cnt  <= 17'd0;
        end
        else if (splash_reset_hold)
        begin
            if (splash_reset_cnt == SPLASH_RESET_HOLD)
                splash_reset_hold <= 1'b0;
            else
                splash_reset_cnt <= splash_reset_cnt + 17'd1;
        end
    end

    //
    // THE MACHINE
    //

    wire VGA_VBlank_border;
    wire std_hsyncwidth;
    wire pause_core_chipset;
    wire swap_video;

    wire [7:0] data_bus;
    wire INTA_n;
    wire [19:0] cpu_ad_out;
    reg  [19:0] cpu_address;
    wire [7:0] cpu_data_bus;
    wire processor_ready;
    wire interrupt_to_cpu;
    wire address_latch_enable;
    wire address_direction;

    wire lock_n;
    wire [2:0]processor_status;

    wire [3:0]   dma_acknowledge_n;

    logic   [7:0]   port_b_out;
    logic   [7:0]   port_c_in;
    wire    [1:0]   fdd_present;
    reg     [7:0]   sw;

    wire    [5:0]   sw_base;
    wire    [1:0]   sw_floppy;

    assign  sw_base = `ENABLE_HGC ? (hgc_mode ? 6'b111101 : 6'b101101) : 6'b101101;
    assign  sw_floppy = fdd_present[1] ? 2'b01 : 2'b00;
    assign  sw = {sw_floppy, sw_base}; // DIP switches (display type and floppy count)
    assign  port_c_in[3:0] = port_b_out[3] ? sw[7:4] : sw[3:0];

`ifdef MACHINE_PC98
    // 8255 port B is 0x0033, and on a PC-98 it is an INPUT: bit 3 is a DIP
    // switch inverted, bits 7-5 are the RS-232C modem status, bit 0 is the
    // calendar clock's data line, and everything else reads zero (np2
    // io/sysport.c, sysp_i33 -- behaviour reference, not code).
    //
    // It was wired to port_b_out, a PC/AT leftover where port B is an output
    // and reading it back is harmless. Here it is not: the UX ITF reads 0x33
    // at F889C and tests bit 2, and a set bit 2 means PARITY ERROR -- which is
    // what it printed. Whatever the BIOS last wrote to port B decided whether
    // this machine believed its own memory was faulty.
    //
    // No serial and no clock chip yet, so the modem bits and the clock bit are
    // zero; bit 3 follows the display DIP the way the reference does.
    wire [7:0] pc98_port_b_in = {3'b000, 1'b0, ~sw[0], 3'b000};
`else
    wire [7:0] pc98_port_b_in = port_b_out;
`endif

`ifdef MACHINE_PC98
    // ---------------------------------------------------------------- ITF bank
    //
    // F8000-FFFFF is 32 KB of ROM that is the ITF at power-on and the system
    // BIOS afterwards. The ITF switches it itself, through port 0x043D:
    // 0x10 selects the ITF, 0x12 selects the BIOS (np2 io/necio.c, and the real
    // instructions are in the ROM -- BA 3D 04 B0 12 EE at F8A98).
    //
    // The hand-over at F988D is worth knowing, because it says the switch must
    // take effect on the very next fetch:
    //
    //     C7 06 FC 04 80 FD   MOV WORD [04FC], FD80    ; target segment, in RAM
    //     BA 3D 04 B0 12      MOV DX,043D / MOV AL,12
    //     EA F8 04 00 00      JMP 0000:04F8            ; stub in RAM does the OUT
    //
    // It cannot OUT and keep executing from ROM, because the ROM changes under
    // it -- so it jumps to a stub in RAM, switches there, and far-jumps into
    // FD80:xxxx. All 8086 instructions.
    //
    // Reset value 0: the BIOS bank, not the ITF.
    //
    // The ITF is a 386 image. docs/PC98_ITF_TRACE.md has the disassembly: it
    // uses 66-prefixed REP STOSD, LGDT/LIDT, SMSW/LMSW and SHL EAX,16, prints
    // "Processor is 80386", and runs two of its extended-memory tests in
    // protected mode. On an 8088 it cannot reach its own hand-over, however
    // much of the I/O map is in place -- and this session put the map in place
    // and watched it get as far as the GDC vsync wait at F80388.
    //
    // So boot where the ITF would have handed over. BIOS.ROM's reset vector is
    // already EA 00 00 80 FD, its entry at FD800 is EB 02 EB 5D FA 33 C0 ... --
    // plain 8086 throughout -- and np2 boots exactly this way, having no ITF at
    // all. The ITF stays loaded in the shadow bank and port 0x043D still
    // switches to it, so nothing is lost; only the power-on choice changes.
    //
    // `PC98_BOOT_ITF` puts it back for anyone testing the ITF path.
`ifdef PC98_BOOT_ITF
    reg  itf_bank = 1'b1;
`else
    reg  itf_bank = 1'b0;
`endif
    reg  itf_io_q, itf_io_qq;
    reg  [7:0] itf_io_data;
    wire itf_port_write = ~chipset_io_write_n & ~chipset_aen
                        & (chipset_address[15:0] == 16'h043D);

    // ------------------------------------------------------- OUT 0F0h: reset
    //
    // The ITF ends its memory test by asking for a CPU reset:
    //
    //     F9475  push cs / push 1497        the address to come back to
    //     F9479  mov [0406],ss / mov [0404],sp
    //     F9A30  mov al,7 / out F0,al       reset me
    //     F9A34  jmp $                      and wait for it
    //
    // That is how a PC-98 leaves protected mode, and it is how this ITF gets
    // from the end of POST to the hand-over. Nothing answered 0x0F0, so the
    // machine stopped on that JMP $ with MEMORY 640KB OK on the screen.
    //
    // The CPU alone: memory keeps its contents (the resume needs SS:SP at
    // 0000:0404 and the return address on the stack), and the ROM bank keeps
    // its selection, so the reset vector still lands in the ITF and its entry
    // finds the shutdown flag waiting.
    //
    // Same two-cycle qualification as the bank switch above, and for the same
    // reason: the address lines sweep through other ports on their way, and
    // resetting the CPU on a glitch would be worse than a bad readout.
    wire f0_port_write = ~chipset_io_write_n & ~chipset_aen
                       & (chipset_address[15:0] == 16'h00F0);

    always @(posedge clk_chipset or posedge reset_sdram) begin
        if (reset_sdram) begin
            f0_io_q          <= 1'b0;
            f0_io_qq         <= 1'b0;
            soft_reset_cpu   <= 1'b0;
            soft_reset_count <= 8'h00;
        end else begin
            f0_io_q  <= f0_port_write;
            f0_io_qq <= f0_io_q;
            if (f0_io_q && f0_io_qq && ~f0_port_write) begin
                soft_reset_cpu   <= 1'b1;
                soft_reset_count <= 8'hFF;
            end else if (soft_reset_count != 8'h00)
                soft_reset_count <= soft_reset_count - 8'h01;
            else
                soft_reset_cpu <= 1'b0;
        end
    end

    always @(posedge clk_chipset or posedge reset_sdram) begin
        if (reset_sdram) begin
`ifdef PC98_BOOT_ITF
            itf_bank    <= 1'b1;
`else
            itf_bank    <= 1'b0;
`endif
            itf_io_q    <= 1'b0;
            itf_io_qq   <= 1'b0;
            itf_io_data <= 8'h00;
        end else begin
            // Two-cycle qualification, and take the data at the END of the
            // cycle. Address and command lines do not change together, so a
            // write on its way to another port sweeps through 0x043D for a
            // cycle -- the same transient that logged POST codes the BIOS never
            // wrote (see post_monitor). Switching the ROM out from under the
            // CPU on a glitch would be considerably worse than a bad readout.
            itf_io_q  <= itf_port_write;
            itf_io_qq <= itf_io_q;
            if (itf_port_write) itf_io_data <= cpu_data_bus;
            if (itf_io_q && itf_io_qq && ~itf_port_write) begin
                if      (itf_io_data == 8'h10) itf_bank <= 1'b1;
                else if (itf_io_data == 8'h12) itf_bank <= 1'b0;
            end
        end
    end

    // One flag drives both directions of the shadow, as the Tandy path does:
    // while the loader writes it routes the ITF image in, and at all other
    // times it decides which of the two ROMs the guest sees at F8000.
    wire tandy_bios_flag = bios_write_n ? itf_bank : tandy_bios_write;
    // Only ever set during a loader write: the guest has no font bank to see.
    wire font_bank_load  = ~bios_write_n & font_bank_write;
`else
    wire tandy_bios_flag = bios_write_n ? `ROM_IS_TANDY : tandy_bios_write;
`endif

    // Displayed card = the boot card XOR the Select-button CGA/HGC toggle. The toggle
    // clears at machine reset, so a fresh POST always shows the 1st Video card.
    reg  video_swap = 1'b0;
    wire osd_video_req_chip;
    synch_3 s_osd_video_req (osd_video_req, osd_video_req_chip, clk_chipset);
    reg  osd_video_req_d = 1'b0;
    always @(posedge clk_chipset) begin
        osd_video_req_d <= osd_video_req_chip;
        if (reset)
            video_swap <= 1'b0;
        else if (osd_video_req_chip & ~osd_video_req_d)
            video_swap <= ~video_swap;
    end

    wire video_output_sel = `ENABLE_HGC ? (hgc_mode_video_ff ^ video_swap) : 1'b0;
    wire enable_hgc_sel = `ENABLE_HGC ? 1'b1 : 1'b0;
    wire [1:0] hgc_rgb_sel = `ENABLE_HGC ? 2'b10 : 2'b00;
    wire hercules_hw_sel = `ENABLE_HGC ? hercules_hw : 1'b0;
    wire ems_enabled_sel = `ENABLE_EMS ? ems_en_cfg : 1'b0;
    wire [1:0] ems_address_sel = `ENABLE_EMS ? ems_frame_cfg : 2'b00;

    always @(posedge clk_chipset)
    begin
        if (address_latch_enable)
            cpu_address <= cpu_ad_out;
        else
            cpu_address <= cpu_address;
    end

    CHIPSET #(.clk_rate(cur_rate)) u_CHIPSET
    (
        .clock                              (clk_chipset),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .clk_sys                            (clk_chipset),
        .peripheral_ce                      (peripheral_ce),
        .clk_select                         (clk_select),
        .reset                              (reset_cpu),
        .sdram_reset                        (reset_sdram),
        .cpu_address                        (cpu_address),
        .cpu_data_bus                       (cpu_data_bus),
        .processor_status                   (processor_status),
        .processor_lock_n                   (lock_n),
    //  .processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
        .processor_ready                    (processor_ready),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .splashscreen                       (splashscreen),
        .status0_clear                      (1'b0),
        .std_hsyncwidth                     (std_hsyncwidth),
        .composite                          (composite),
        .video_output                       (video_output_sel),
`ifdef MACHINE_PC98
        .clk_vga_cga                        (clk_pc98_dot),
`else
        .clk_vga_cga                        (clk_28_636),
`endif
        .enable_cga                         (`ENABLE_CGA),
        .clk_vga_hgc                        (clk_32_514),
        .enable_hgc                         (enable_hgc_sel),
        .hgc_rgb                            (hgc_rgb_sel),
    //  .de_o                               (VGA_DE),
        .pc98_tvfill_view                   (pc98_tvfill_view),
        .pc98_rowbuf_freq_count             (pc98_rowbuf_freq_count),
        .pc98_rowbuf_fvalid_count           (pc98_rowbuf_fvalid_count),
        .VGA_R                              (r),
        .VGA_G                              (g),
        .VGA_B                              (b),
        .VGA_HSYNC                          (HSync),
        .VGA_VSYNC                          (VSync),
        .VGA_HBlank                         (HBlank),
        .VGA_VBlank                         (VBlank),
        .VGA_VBlank_border                  (VGA_VBlank_border),
        .address                            (chipset_address),
        .address_ext                        (st_run ? st_addr : bios_access_address),
        .ext_access_request                 (st_run | bios_access_request),
        .data_bus_ext_out                   (chipset_ext_rdata),
        .address_direction                  (address_direction),
        .data_bus                           (data_bus),
        .data_bus_ext                       (st_run ? st_wdata : bios_write_data[7:0]),
    //  .data_bus_direction                 (data_bus_direction),
        .address_latch_enable               (address_latch_enable),
    //  .io_channel_check                   (),
        .io_channel_ready                   (1'b1),
        .interrupt_request                  (0),    // use? -> It does not seem to be necessary.
    //  .io_read_n                          (io_read_n),
        .io_read_n_ext                      (1'b1),
    //  .io_read_n_direction                (io_read_n_direction),
        .io_write_n                         (chipset_io_write_n),
        .io_write_n_ext                     (1'b1),
    //  .io_write_n_direction               (io_write_n_direction),
        .memory_read_n                      (chipset_memory_read_n),
        .memory_read_n_ext                  (st_rd_n),
    //  .memory_read_n_direction            (memory_read_n_direction),
        .memory_write_n                     (chipset_memory_write_n),
        .memory_write_n_ext                 (st_run ? st_wr_n : bios_write_n),
    //  .memory_write_n_direction           (memory_write_n_direction),
        .dma_request                        (0),    // use? -> I don't know if it will ever be necessary, at least not during testing.
        .dma_acknowledge_n                  (dma_acknowledge_n),
        .address_enable_n                   (chipset_aen),
    //  .terminal_count_n                   (terminal_count_n)
        .port_b_out                         (port_b_out),
        .port_c_in                          (port_c_in),
        .port_b_in                          (pc98_port_b_in),
        .speaker_out                        (speaker_out),
        .kb_byte                            (kb_byte),
        .kb_valid                           (kb_valid),
        .kb_ready                           (kb_ready),
        .uart_rx                            (mouse_rd),
        .uart_rts_n                         (mouse_rts_n),
        .joy_opts                           (joy_opts),           //Joy0-Disabled, Joy0-Type, Joy1-Disabled, Joy1-Type, turbo_sync
        .joy0                               (swapjoy_cfg ? joy1 : joy0),
        .joy1                               (swapjoy_cfg ? joy0 : joy1),
        .joya0                              (swapjoy_cfg ? joya1 : joya0),
        .joya1                              (swapjoy_cfg ? joya0 : joya1),
        .jtopl2_snd_e                       (jtopl2_snd_e),
        .tandy_snd_e                        (tandy_snd_e),
        .opl2_io                            (xtctl[4] ? 2'b10 : opl2_cfg),
        .cms_en                             (cms_cfg),
        .o_cms_l                            (cms_l_snd_e),
        .o_cms_r                            (cms_r_snd_e),
        .tandy_video                        (tandy_video_mode),
        .tandy_bios_flag                    (tandy_bios_flag),
`ifdef MACHINE_PC98
        .font_bank_flag                     (font_bank_load),
        .font_wr_clk                        (clk_chipset),
        .font_wr_en                         (font_dl_hit),
        .font_wr_addr                       (font_dl_addr),
        .font_wr_data                       (dl_data),
`else
        .font_bank_flag                     (1'b0),
        .font_wr_clk                        (1'b0),
        .font_wr_en                         (1'b0),
        .font_wr_addr                       (11'd0),
        .font_wr_data                       (16'd0),
`endif
        .tandy_16_gfx                       (tandy_16_gfx),
        .tandy_color_16                     (tandy_color_16),
        .clk_uart                           (clk_uart2_en),
        .uart2_rx                           (uart_rx),
        .uart2_tx                           (uart_tx),
        .uart2_cts_n                        (uart_cts),
        .uart2_dcd_n                        (uart_dcd),
        .uart2_dsr_n                        (uart_dsr),
        .uart2_rts_n                        (uart_rts),
        .uart2_dtr_n                        (uart_dtr),
        .enable_sdram                       (1'b1),
        .initilized_sdram                   (initilized_sdram),
        .sdram_clock                        (SDRAM_CLK),
        .sdram_address                      (SDRAM_A),
        .sdram_cke                          (SDRAM_CKE),
        .sdram_cs                           (SDRAM_nCS),
        .sdram_ras                          (SDRAM_nRAS),
        .sdram_cas                          (SDRAM_nCAS),
        .sdram_we                           (SDRAM_nWE),
        .sdram_ba                           (SDRAM_BA),
        .sdram_dq_in                        (SDRAM_DQ_IN),
        .sdram_dq_out                       (SDRAM_DQ_OUT),
        .sdram_dq_io                        (SDRAM_DQ_IO),
        .sdram_ldqm                         (SDRAM_DQML),
        .sdram_udqm                         (SDRAM_DQMH),
        .ems_enabled                        (ems_enabled_sel),
        .ems_address                        (ems_address_sel),
        .bios_protect_flag                  (bios_protect_flag),
        .use_mmc                            (use_mmc),
        .spi_clk                            (spi_clk),
        .spi_cs                             (spi_cs),
        .spi_mosi                           (spi_mosi),
        .spi_miso                           (spi_miso),
        .mgmt_readdata                      (mgmt_din),
        .mgmt_writedata                     (mgmt_dout),
        .mgmt_address                       (mgmt_addr),
        .mgmt_write                         (mgmt_wr),
        .mgmt_read                          (mgmt_rd),
        .floppy_wp                          (wp_cfg),
        .fdd_present                        (fdd_present),
        .fdd_request                        (mgmt_req[7:6]),
        .ide0_request                       (mgmt_req[2:0]),
        .xtctl                              (xtctl),
        .enable_a000h                       (a000h),
        .wait_count_clk_en                  (cpu_ce_negedge),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle),
        .pause_core                         (pause_core_chipset),
        .cga_hw                             (cga_hw),
        .cga_scandouble_en                  (1'b0),
        .hercules_hw                        (hercules_hw_sel),
        .swap_video                         (swap_video),
        .crt_h_offset                       (4'd0),
        .crt_v_offset                       (3'd0),
        .vsync_width_osd                    (vsync_width_osd),
        .hsync_width_osd                    (hsync_width_osd),
        .ram_rw_complete                    (ram_rw_complete)
    );

    // CHIPSET per-access "done" pulse (COMPLETE_RAM_RW); drives the ROM-load FSM.
    wire        ram_rw_complete;

    // ---- SDRAM boundary: chipset controller -> Pocket dram_* pins ----
    // CHIPSET drives these; pass straight through.
    wire        SDRAM_CLK;
    wire        SDRAM_CKE;
    wire [12:0] SDRAM_A;
    wire  [1:0] SDRAM_BA;
    wire        SDRAM_DQML;
    wire        SDRAM_DQMH;
    wire        SDRAM_nCS;
    wire        SDRAM_nCAS;
    wire        SDRAM_nRAS;
    wire        SDRAM_nWE;
    wire [15:0] SDRAM_DQ_IN;
    wire [15:0] SDRAM_DQ_OUT;
    wire        SDRAM_DQ_IO;
    wire        initilized_sdram;

    assign SDRAM_CLK  = clk_chipset;    // controller clock fed into the chipset
    assign dram_clk   = clk_sdram_ph;   // device clock, phase-shifted 42.95 MHz
    assign dram_cke   = SDRAM_CKE;
    assign dram_a     = SDRAM_A;
    assign dram_ba    = SDRAM_BA;
    assign dram_dqm   = {SDRAM_DQMH, SDRAM_DQML};
    assign dram_ras_n = SDRAM_nRAS;
    assign dram_cas_n = SDRAM_nCAS;
    assign dram_we_n  = SDRAM_nWE;
    // no dram_cs pin on the Pocket; SDRAM_nCS is left unconnected

    assign SDRAM_DQ_IN = dram_dq;
    assign dram_dq     = ~SDRAM_DQ_IO ? SDRAM_DQ_OUT : 16'hZZZZ;

    wire s6_3_mux;
    wire [2:0] SEGMENT;

    i8088 B1    
    (
        .CORE_CLK(clk_core),
        .CLK(clk_cpu),

        .RESET(reset_cpu),
        .READY(processor_ready && ~pause_core),
        .NMI(1'b0),
        .INTR(interrupt_to_cpu),

        .ad_out(cpu_ad_out),
        .dout(cpu_data_bus),
        .din(data_bus),

        .lock_n(lock_n),
        .s6_3_mux(s6_3_mux),
        .s2_s0_out(processor_status),
        .SEGMENT(SEGMENT),

        .biu_done(biu_done),
        .cycle_accrate(cycle_accrate),
        .clock_cycle_counter_division_ratio(clock_cycle_counter_division_ratio),
        .clock_cycle_counter_decrement_value(clock_cycle_counter_decrement_value),
        .shift_read_timing(shift_read_timing)
    );

    //
    // MACHINE PORT STUBS
    //

    wire uart_tx, uart_rts, uart_dtr;   // CHIPSET COM2 outputs, no external pins
    wire uart_rx  = 1'b1;
    wire uart_cts = 1'b1;
    wire uart_dsr = 1'b1;
    wire uart_dcd = 1'b1;

    // SPI/MMC storage path unused; the managed-SD ide.v backend is used instead.
    wire [1:0] use_mmc = 2'b00;
    wire spi_clk, spi_cs, spi_mosi;     // CHIPSET outputs, no external pins
    wire spi_miso = 1'b0;

    //
    // AUDIO
    //

    wire [15:0] cms_l_snd_e;
    wire [16:0] cms_l_snd = {cms_l_snd_e[15],cms_l_snd_e};
    wire [15:0] cms_r_snd_e;
    wire [16:0] cms_r_snd = {cms_r_snd_e[15],cms_r_snd_e};
     
    wire [15:0] jtopl2_snd_e;
    wire [16:0] jtopl2_snd = {jtopl2_snd_e[15], jtopl2_snd_e};
    wire [10:0] tandy_snd_e;
    wire [16:0] tandy_snd = `ENABLE_TANDY_AUDIO ? {{{2{tandy_snd_e[10]}}, {4{tandy_snd_e[10]}}, tandy_snd_e}, 2'b00} : 17'd0;
    wire [16:0] spk_vol =  {2'b00, {3'b000,~speaker_out} << spk_vol_cfg, 11'd0};
    wire        speaker_out;

    localparam [3:0] comp_f1 = 4;
    localparam [3:0] comp_a1 = 2;
    localparam       comp_x1 = ((32767 * (comp_f1 - 1)) / ((comp_f1 * comp_a1) - 1)) + 1; // +1 to make sure it won't overflow
    localparam       comp_b1 = comp_x1 * comp_a1;

    localparam [3:0] comp_f2 = 8;
    localparam [3:0] comp_a2 = 4;
    localparam       comp_x2 = ((32767 * (comp_f2 - 1)) / ((comp_f2 * comp_a2) - 1)) + 1; // +1 to make sure it won't overflow
    localparam       comp_b2 = comp_x2 * comp_a2;

    function [15:0] compr;
        input [15:0] inp;
        reg [15:0] v, v1, v2;
        begin
            v  = inp[15] ? (~inp) + 1'd1 : inp;
            v1 = (v < comp_x1[15:0]) ? (v * comp_a1) : (((v - comp_x1[15:0])/comp_f1) + comp_b1[15:0]);
            v2 = (v < comp_x2[15:0]) ? (v * comp_a2) : (((v - comp_x2[15:0])/comp_f2) + comp_b2[15:0]);
            v  = boost_cfg[1] ? v2 : v1;
            compr = inp[15] ? ~(v-1'd1) : v;
        end
    endfunction

    reg [15:0] cmp_l;
    reg [15:0] out_l;
    always @(posedge clk_chipset)
    begin
        reg [16:0] tmp_l;

        tmp_l <= jtopl2_snd + cms_l_snd + tandy_snd + spk_vol;

        // clamp the output
        out_l <= (^tmp_l[16:15]) ? {tmp_l[16], {15{tmp_l[15]}}} : tmp_l[15:0];

        cmp_l <= compr(out_l);
    end

    reg [15:0] cmp_r;
    reg [15:0] out_r;
    always @(posedge clk_chipset)
    begin
        reg [16:0] tmp_r;

        tmp_r <= jtopl2_snd + cms_r_snd + tandy_snd + spk_vol;

        // clamp the output
        out_r <= (^tmp_r[16:15]) ? {tmp_r[16], {15{tmp_r[15]}}} : tmp_r[15:0];

        cmp_r <= compr(out_r);
    end

    // Filter chain + I2S: audio_mixer supplies the anti-aliasing low-pass + DC blocker
    // (the raw mix has square-wave harmonics past Nyquist), the crossfeed, and codec clocks.
    wire [15:0] audio_l = pause_core ? 16'd0 : (boost_cfg ? cmp_l : out_l);
    wire [15:0] audio_r = pause_core ? 16'd0 : (boost_cfg ? cmp_r : out_r);

    audio_mixer #(.DW(16), .STEREO(1)) audio_mixer (
        .clk_74b    (clk_74b),
        .clk_audio  (clk_chipset),
        .reset      (1'b0),
        .vol_att    (4'd0),
        .mix        (stereo_mix_cfg),
        .is_signed  (1'b1),
        .core_l     (audio_l),
        .core_r     (audio_r),
        .audio_mclk (audio_mclk),
        .audio_lrck (audio_lrck),
        .audio_dac  (audio_dac)
    );

    //
    // VIDEO AND OSD
    //

    // CHIPSET's CGA/HGC raster feeds pocket_video, which composites the OSD and drives the
    // APF scaler. r/g/b + syncs leave CHIPSET on the dot clock; clk_pix is its half-rate
    // sibling, so pocket_video samples one pixel per edge.
    wire        HBlank;
    wire        HSync;
    wire        VBlank;
    wire        VSync;
    wire [5:0]  r, g, b;
    wire        tandy_16_gfx, tandy_color_16;   // CHIPSET Tandy-video outputs (unused)

    // ------------------------------------------------------ hardware bands
    //
    // Sixteen RTL-driven bits, painted by pocket_video as two columns of eight
    // stripes down the left edge. No softcore, no firmware, no guest -- and,
    // since the probe generates its own raster, no CHIPSET either.
    //
    // The first round answered its question: reset_soft 0, boot_dl_done 1,
    // load_active 0, rlf_empty 1, osd_active 1, PLLs locked. The softcore runs,
    // the ROMs loaded, and it is asking for an OSD that never arrives. So the
    // fault is downstream: CHIPSET produces no raster, DE never asserts, and
    // both the picture and the OSD composited into it are lost.
    //
    // These sixteen are the remaining terms of reset_wire plus the evidence for
    // whether the raster runs at all.
    //
    // The left column is these eight; pocket_video measures the right column
    // itself, from signals that only exist there.
    //
    //   1  soft_guest_hold      5  bios_ever_loaded
    //   2  splash_pending_sync2 6  interact_reset
    //   3  splashscreen_sync2   7  reset (the guest reset)
    //   4  splash_reset_hold    8  ~RESET
    //
    // reset_wire is RESET | load_active | ~bios_ever_loaded | interact_reset |
    // splashscreen_sync2 | splash_reset_hold | splash_pending_sync2 |
    // soft_guest_hold, and bands 1-7 are every one of those still unaccounted
    // for. Whichever is lit is the one holding the machine.
    //
    // splash_pending is the one to watch: it powers up asserted and clears only
    // when bios_ever_loaded & ~soft_guest_hold, on clk_28_636 -- the CGA dot
    // clock, which this machine does not otherwise use.
    wire [15:0] dbg_bits = {
        ~RESET, load_active, osd_active, reset_soft,
        reset_cpu, processor_ready, initilized_sdram, dataslots_ready,
        ~RESET, reset,
        interact_reset, bios_ever_loaded,
        splash_reset_hold, splashscreen_sync2, splash_pending_sync2,
        soft_guest_hold
    };

    pocket_video u_pocket_video (
        .clk_pix            (clk_pix),
        .clk_pix_90         (clk_pix_90),
        .RESET              (RESET),
        .r                  (r),
        .g                  (g),
        .b                  (b),
        .HSync              (HSync),
        .VSync              (VSync),
        .HBlank             (HBlank),
        .VBlank             (VBlank),
        .palette_cfg        (palette_cfg),
        .credits_mode_pix   (credits_mode_pix),
        .pix_sel            (pix_sel),
        .vid_blank          (vid_blank),
        .osd_active         (osd_active),
        .osd_palette_idx    (osd_palette_idx),
        .osd_in_area        (osd_in_area),
        .dbg_bits           (dbg_bits),
        .osd_hcnt           (osd_hcnt),
        .osd_vcnt           (osd_vcnt_sel),
        .osd_raster_w       (osd_raster_w),
        .osd_raster_h       (osd_raster_h),
        .video_rgb          (video_rgb),
        .video_de           (video_de),
        .video_hs           (video_hs),
        .video_vs           (video_vs),
        .video_skip         (video_skip),
        .video_rgb_clock    (video_rgb_clock),
        .video_rgb_clock_90 (video_rgb_clock_90)
    );
endmodule
