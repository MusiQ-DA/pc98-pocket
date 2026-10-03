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

    wire clk_28_636;             // 28.6 MHz; its half is the boot hold's 14.3 tick
    logic cpu_ce_posedge;        // CPU clock-enable, rising
    logic cpu_ce_negedge;        // CPU clock-enable, falling
    wire clk_chipset;            // 42.95 MHz, main domain

    localparam [27:0] cur_rate = `CHIPSET_HZ;   // chipset clock rate, Hz (3 x 14.31818 MHz)

    wire clk_sdram_ph;           // SDRAM pin clock, phase-shifted
    wire clk_pix;                // pixel clock, video out
    wire clk_pix_90;             // pixel clock, 90 deg

    // System PLL: chipset 42.95, dram 42.95@180, and the 28.64 MHz clock whose
    // half drives the boot hold's 14.3 MHz tick. The open outputs are
    // unrouted on purpose -- repinning a generated PLL is riskier than
    // leaving wires open.
    pll pll
    (
        .refclk   (clk_74a),
        .rst      (1'b0),
        .outclk_0 (clk_chipset),
        .outclk_1 (),
        .outclk_2 (clk_sdram_ph),
        .outclk_3 (clk_28_636),
        .outclk_4 (),
        .outclk_5 (),
        .locked   (pll_locked)
    );

    // 14.318 MHz tick (clk_28_636 / 2): clock-enable for the boot hold.
    reg ce_14_318 = 1'b0;
    always @(posedge clk_28_636)
        ce_14_318 <= ~ce_14_318;

    // CPU clock: ce_generator derives the V30's CE strobes; clk_select sets
    // the speed and is reloaded each bus cycle (biu_done).
    logic  biu_done;
    logic  [7:0] clock_cycle_counter_division_ratio;
    logic  [7:0] clock_cycle_counter_decrement_value;
    logic        shift_read_timing;
    logic  [1:0] ram_read_wait_cycle;
    logic  [1:0] ram_write_wait_cycle;
    logic        cycle_accrate;
    logic        vram_wait_en;
    logic  [1:0] clk_select;
    // The CPU speed is the OSD's alone.
    wire   [1:0] clk_select_next = cpu_speed_cfg;

    always @(posedge clk_chipset, posedge reset)
    begin
        if (reset)
            clk_select <= 2'b00;
        else if (biu_done)
            clk_select <= clk_select_next;
    end

    ce_generator u_ce_generator
    (
        .clock                              (clk_chipset),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (clk_select_next),
        // The pin clock output is open: the V30 takes the CEs, not a
        // pin clock, and nothing else ever read it.
        .cpu_clk_pin                        (),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (),
        .cycle_accrate                      (cycle_accrate),
        .clock_cycle_counter_division_ratio (clock_cycle_counter_division_ratio),
        .clock_cycle_counter_decrement_value(clock_cycle_counter_decrement_value),
        .shift_read_timing                  (shift_read_timing),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle),
        .vram_wait_en                       (vram_wait_en)
    );

    // vid_blank is the softcore's (SOFT_GUEST_HOLD bit1): it forces the
    // presented frame dark through an orchestrated guest reset, so the
    // stale VRAM picture cannot sit on screen until the BIOS repaints.
    wire vid_blank = soft_vid_blank;

    // One video mode, so no switch: the dot clock goes straight out.
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

    //
    // RESET
    //

    // Global power-on reset until all PLLs lock.
    wire RESET = ~pll_locked | ~pll_pc98_locked;

    // The disk/OSD softcore is the boot master; it drives this hold (declared here so the guest
    // reset can use it, sourced from u_softcpu below). soft_vid_blank is the
    // same register's bit1, declared here for the pocket_video instance.
    wire soft_guest_hold;
    wire soft_vid_blank;

    // Guest reset terms: PLL lock (RESET), ROM load and the first-BIOS gate, the interact
    // Reset PC, the boot hold, and the softcore's boot-master hold (soft_guest_hold), which
    // keeps the guest in reset until the softcore has staged settings. sdram holds on lock only.
    wire reset_wire = RESET | load_active | ~bios_ever_loaded | interact_reset
                    | guest_hold_sync2 | soft_guest_hold;
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
    // terms (BIOS load, the boot hold, the guest reset, or its own soft_guest_hold), which would deadlock.
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

    always @(negedge clk_chipset, posedge reset)
    begin
        if (reset)
        begin
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

    // ------------------------------------------------ the chipset's own reset
    //
    // reset_cpu is the CPU's, and OUT 0F0h is one of its terms. CHIPSET was
    // taking it too, so the ITF's own hand-over reset wiped the chipset -- and
    // with it pc98_sysport_c, the 8255 port C latch that carries the shutdown
    // flag. It reset to F9, bit 7 SET, and the ITF entry at F8005B reads bit 7
    // to tell a power-on from a return from OUT 0F0h:
    //
    //     F9471   mov al,0Eh / out 37h,al   clear PC7: "resume"
    //     F9475   push cs / push 1497       the address to come back to
    //     F9479   mov [0406],ss / [0404],sp
    //     F9A30   mov al,7 / out F0,al      reset me
    //     F8005B  in al,35h / test al,80h   ... and here it read SET again
    //
    // so every hand-over came back as a cold boot: black screen, boot chime,
    // MEMORY counting from 000KB, and another OUT 0F0h. The POST panel's F0
    // count climbing is that loop. On the hardware OUT 0F0h pulses the CPU's
    // RESET pin and nothing else -- the 8255, the PIC, the PIT and the GDCs
    // all keep their state -- which is what the port decode's own comment says
    // it does ("The CPU alone") and what tb_pc98_boot models, which is why the
    // bench never reproduced the restart and the machine did.
    //
    // Identical to reset_cpu in every other way, including the 0x2A-cycle
    // release, so power-up timing is unchanged.
    logic reset_chipset = 1'b1;
    logic [15:0] reset_chipset_count = 16'h0000;

    always @(negedge clk_chipset, posedge reset)
    begin
        if (reset)
        begin
            reset_chipset <= 1'b1;
            reset_chipset_count <= 16'h0000;
        end
        else if (reset_chipset)
        begin
            reset_chipset <= reset_cpu_ff;
            reset_chipset_count <= 16'h0000;
        end
        else
        begin
            if (reset_chipset_count != 16'h002A)
            begin
                reset_chipset <= reset_cpu_ff;
                reset_chipset_count <= reset_chipset_count + 16'h0001;
            end
            else
            begin
                reset_chipset <= 1'b0;
                reset_chipset_count <= reset_chipset_count;
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

    // The Pocket's real clock, packed for the uPD4990. The bridge hands over
    // BCD bytes -- date {day [23:16], month [15:8], year [7:0]}, time {hour
    // [23:16], min [15:8], sec [7:0]} -- and np21w's date2bcd wants year, then
    // month with the weekday in the low nibble, then day/hour/min/sec. The
    // weekday the bridge does not carry, so it comes off Sakamoto's table
    // (0 = Sunday). Combinational helpers rather than block-locals: Quartus
    // rejects "automatic" declarations inside always_ff even where the
    // simulator accepts them.
    wire [31:0] rtc_epoch_seconds;
    wire [31:0] rtc_date_bcd;
    wire [31:0] rtc_time_bcd;
    wire        rtc_valid;

    function automatic [6:0] bcd2bin(input [7:0] b);
        bcd2bin = (b[7:4] * 7'd10) + {3'd0, b[3:0]};   // 10*hi + lo
    endfunction

    wire [3:0]  rtc_mo  = bcd2bin(rtc_date_bcd[15:8]);
    wire [4:0]  rtc_da  = bcd2bin(rtc_date_bcd[23:16]);
    wire [11:0] rtc_y   = 12'd2000 + {8'd0, bcd2bin(rtc_date_bcd[7:0])};
    wire [11:0] rtc_yy  = (rtc_mo < 4'd3) ? (rtc_y - 12'd1) : rtc_y;

    function automatic [2:0] sakamoto(input [3:0] mo);   // month 1..12
        case (mo)
        4'd1:  sakamoto = 3'd0;  4'd2:  sakamoto = 3'd3;
        4'd3:  sakamoto = 3'd2;  4'd4:  sakamoto = 3'd5;
        4'd5:  sakamoto = 3'd0;  4'd6:  sakamoto = 3'd3;
        4'd7:  sakamoto = 3'd5;  4'd8:  sakamoto = 3'd1;
        4'd9:  sakamoto = 3'd4;  4'd10: sakamoto = 3'd6;
        4'd11: sakamoto = 3'd2;  4'd12: sakamoto = 3'd4;
        default: sakamoto = 3'd0;
        endcase
    endfunction

    // (d + t + yy + yy/4 + 1 - 15) mod 7 -- the -15 folds y/100-y/400 for
    // 2000-2099 (20-5), the +1 keeps it positive.
    wire [15:0] rtc_acc = 16'(rtc_da) + 16'(sakamoto(rtc_mo))
                        + 16'(rtc_yy) + 16'(rtc_yy >> 2) + 16'd1 - 16'd15;

    logic [47:0] rtc_time = 48'd0;
    logic        rtc_valid_q = 1'b0;
    // The latched snapshot never advanced, so TIME$ froze at load time.
    // The real chip ticks: count clk_74a seconds and walk the BCD fields
    // (sec/min/hour BCD, month binary, weekday mod 7, month lengths with
    // leap-February when the BCD year divides by four).
    localparam int RTC_DIV = 74_250_000;
    logic [26:0] rtc_div = 27'd0;
    wire         rtc_tick = (rtc_div == RTC_DIV - 1);

    function automatic [7:0] bcd_inc(input [7:0] b);
        bcd_inc = (b[3:0] == 4'd9) ? {b[7:4] + 4'd1, 4'd0} : b + 8'd1;
    endfunction
    // mod-7 without a divider: 8 ≡ 1 (mod 7), so the octal digits can just be
    // summed. Six 3-bit groups (< 50), one more fold (< 14), one subtract.
    // The lpm_divide Quartus inferred for "% 7" needed ~14.3 ns -- the whole
    // remaining -1.2 ns of clk_74a slack after the pipelining pass.
    function automatic [2:0] mod7(input [15:0] v);
        logic [6:0] s;
        logic [3:0] t;
        s = {4'd0, v[2:0]} + {4'd0, v[5:3]} + {4'd0, v[8:6]}
          + {4'd0, v[11:9]} + {4'd0, v[14:12]} + {6'd0, v[15]};
        t = {1'b0, s[2:0]} + {1'b0, s[6:3]};
        mod7 = (t >= 4'd7) ? t[2:0] - 3'd7 : t[2:0];
    endfunction
    function automatic [4:0] days_in(input [3:0] mo, input logic leap);
        case (mo)
        4'd4, 4'd6, 4'd9, 4'd11: days_in = 5'd30;
        4'd2:                  days_in = leap ? 5'd29 : 5'd28;
        default:               days_in = 5'd31;
        endcase
    endfunction
    // {mo,wday} is a 7-bit value zero-extended into [15:8]: mo lives at
    // [14:11], wday at [10:8], bit 15 stays clear.
    wire [3:0] cur_mo   = rtc_time[14:11];
    wire       cur_leap = (bcd2bin(rtc_time[7:0]) % 4) == 4'd0;
    wire [4:0] cur_dim  = days_in(cur_mo, cur_leap);

    // clk_74a is the domain that fails setup, and the old code evaluated the
    // whole rollover in one cycle: a six-deep nested compare+BCD chain whose
    // day check reached through bcd2bin + %4 + days_in, plus the rtc_acc % 7
    // (a 16-bit modulo) on the rtc_valid write. rtc_time only changes on the
    // tick or a load, so every rollover term is registered continuously and
    // the tick becomes a flat mux per field -- the arithmetic keeps a full
    // cycle to settle.
    wire roll_sec  = (rtc_time[47:40] == 8'h59);
    wire roll_min  = roll_sec  & (rtc_time[39:32] == 8'h59);
    wire roll_hour = roll_min  & (rtc_time[31:24] == 8'h23);
    wire roll_day  = roll_hour & (bcd2bin(rtc_time[23:16]) == {2'd0, cur_dim});
    wire roll_mo   = roll_day  & (cur_mo == 4'd12);

    reg        roll_sec_q = 1'b0, roll_min_q = 1'b0, roll_hour_q = 1'b0,
               roll_day_q = 1'b0, roll_mo_q = 1'b0;
    reg  [7:0] sec_next_q = 8'd0, min_next_q = 8'd0, hr_next_q = 8'd0,
               day_next_q = 8'd0, yr_next_q = 8'd0;
    reg  [2:0] wday_next_q = 3'd0;
    // rtc_acc's adds get a cycle, then the 16-bit %7 gets its own --
    // rtc_date_bcd is a level held by the bridge, so the two-stage result is
    // settled by the time the load commit fires two cycles after the edge.
    reg [15:0] rtc_acc_q   = 16'd0;
    reg  [2:0] rtc_wday_q  = 3'd0;
    reg  [1:0] rtc_load_pend = 2'b00;

    always_ff @(posedge clk_74a) begin
        roll_sec_q  <= roll_sec;
        roll_min_q  <= roll_min;
        roll_hour_q <= roll_hour;
        roll_day_q  <= roll_day;
        roll_mo_q   <= roll_mo;
        sec_next_q  <= bcd_inc(rtc_time[47:40]);
        min_next_q  <= bcd_inc(rtc_time[39:32]);
        hr_next_q   <= bcd_inc(rtc_time[31:24]);
        day_next_q  <= bcd_inc(rtc_time[23:16]);
        yr_next_q   <= (rtc_time[7:0] == 8'h99) ? 8'h00
                                                : bcd_inc(rtc_time[7:0]);
        wday_next_q <= (rtc_time[10:8] == 3'd6) ? 3'd0
                                                : rtc_time[10:8] + 3'd1;
        rtc_acc_q   <= rtc_acc;
        rtc_wday_q  <= mod7(rtc_acc_q);
    end

    always_ff @(posedge clk_74a) begin
        rtc_valid_q <= rtc_valid;
        rtc_load_pend <= {rtc_load_pend[0], rtc_valid & ~rtc_valid_q};
        if (rtc_load_pend[1]) begin
            rtc_time <= {rtc_time_bcd[7:0],      // second
                         rtc_time_bcd[15:8],     // minute
                         rtc_time_bcd[23:16],    // hour
                         rtc_date_bcd[23:16],    // day
                         {1'b0, rtc_mo, rtc_wday_q},  // bit15 clear | month | wday
                         rtc_date_bcd[7:0]};     // year
            rtc_div <= 27'd0;
        end else if (rtc_tick) begin
            rtc_div <= 27'd0;
            rtc_time[47:40] <= roll_sec_q ? 8'h00 : sec_next_q;
            if (roll_sec_q)
                rtc_time[39:32] <= roll_min_q ? 8'h00 : min_next_q;
            if (roll_min_q)
                rtc_time[31:24] <= roll_hour_q ? 8'h00 : hr_next_q;
            if (roll_hour_q) begin
                rtc_time[10:8]  <= wday_next_q;
                rtc_time[23:16] <= roll_day_q ? 8'h01 : day_next_q;
            end
            if (roll_day_q)
                rtc_time[14:11] <= roll_mo_q ? 4'd1 : cur_mo + 4'd1;
            if (roll_mo_q)
                rtc_time[7:0]   <= yr_next_q;
        end else
            rtc_div <= rtc_div + 27'd1;
    end

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

        .rtc_epoch_seconds         (rtc_epoch_seconds),
        .rtc_date_bcd              (rtc_date_bcd),
        .rtc_time_bcd              (rtc_time_bcd),
        .rtc_valid                 (rtc_valid),

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
    wire  [7:0] mgmt_req;              // [7:6] fdd request, [0] scsi pending (from CHIPSET)
    assign mgmt_req[5:1] = 5'b00000;

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
    wire [8:0] vkb_key;
    wire       vkb_stb;
    wire [2:0] osd_palette;
    wire [1:0] osd_cpu_speed;
    wire [1:0] osd_bios_wr;
    wire [1:0] osd_boost;
    wire [1:0] osd_spk_vol;
    wire [1:0] osd_stereo;
    wire       osd_disk_led;
    wire [1:0] osd_extmem;
    wire       osd_dbl_skip;
    wire       osd_fdd_turbo;
    wire [7:0] osd_dipsw2;
    wire [7:0] osd_a3fea;
    wire [7:0] osd_a3fee;
    wire [7:0] osd_a3ff2;
    wire [1:0] osd_gamepad;
    wire [16*9-1:0] key_cfg;   // per-control {ext, Set-2 code} file from the softcore

    // Last docked-keyboard make, tapped for the softcore key picker (pocket_keyboard -> softcpu).
    wire [7:0] dock_key_code;
    wire       dock_key_ext;
    wire       dock_key_stb;

    wire  [1:0] gdc_draw_req, gdc_draw_busy, gdc_srv_done_levels;
    wire  [1:0] gdc_draw_to;              // {slave, master} watchdog pulses
    wire        egc_flag_w;               // 0000:054D bit6 write seen (sticky)
    // The firmware GDC engine's guest-VRAM channel (subsystem <-> CHIPSET's
    // GVRAM sequencer).
    wire        st_req_w, st_we_w, st_raw_w, st_done_w;
    wire [19:0] st_addr_w;
    wire  [7:0] st_wdata_w, st_rdata_w, accel_status_w;
    wire [15:0] gdc_draw_ops;
    wire [383:0] gdc_draw_snaps;

`ifdef PC98_JTAG
    // How far does a key get? key_count counts pc98_key_stb pulses and
    // key_last keeps the last {make, code}; the probe's key slot reads them.
    logic [7:0] key_count = 8'h00;
    logic [7:0] key_last  = 8'h00;
`endif

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
        .osd_open_req               (osd_open_req),
        .raster_w                   (osd_raster_w),
        .raster_h                   (osd_raster_h),
        .dataslots_ready            (dataslots_ready),
        .soft_guest_hold            (soft_guest_hold),
        .soft_vid_blank             (soft_vid_blank),
        .scsi_media                 (scsi_media),
        .osd_active                 (osd_active),
        .vkb_key                    (vkb_key),
        .vkb_stb                    (vkb_stb),
        .osd_palette                (osd_palette),
        .osd_cpu_speed              (osd_cpu_speed),
        .osd_bios_wr                (osd_bios_wr),
        .osd_boost                  (osd_boost),
        .osd_spk_vol                (osd_spk_vol),
        .osd_stereo                 (osd_stereo),
        .osd_gamepad                (osd_gamepad),
        .osd_disk_led               (osd_disk_led),
        .osd_extmem                 (osd_extmem),
        .osd_dbl_skip               (osd_dbl_skip),
        .osd_fdd_turbo              (osd_fdd_turbo),
        .osd_dipsw2                 (osd_dipsw2),
        .osd_a3fea                  (osd_a3fea),
        .osd_a3fee                  (osd_a3fee),
        .osd_a3ff2                  (osd_a3ff2),
        .key_cfg_flat               (key_cfg),
        .gdc_draw_req               (gdc_draw_req),
        .gdc_draw_busy              (gdc_draw_busy),
        .gdc_draw_ops               (gdc_draw_ops),
        .gdc_draw_snaps             (gdc_draw_snaps),
        .gdc_srv_done_levels        (gdc_srv_done_levels),
        // The firmware GDC engine's guest-VRAM byte channel, terminated in
        // the chipset's GVRAM sequencer (through the charger when armed).
        .st_req                     (st_req_w),
        .st_we                      (st_we_w),
        .st_raw                     (st_raw_w),
        .st_addr                    (st_addr_w),
        .st_wdata                   (st_wdata_w),
        .st_done                    (st_done_w),
        .st_rdata                   (st_rdata_w),
        .accel_status               (accel_status_w)
    );

`ifdef PC98_JTAG
    //
    // JTAG probe -- the panel's readout without a camera.
    //
    // A USB Blaster on the FPGA's JTAG port reads these over the SLD hub:
    // scripts/jtag_probe.cfg + jtag_probe_read.tcl drive USER1/USER0.
    // The magic word proves the protocol end-to-end before any value is trusted.
    logic [31:0] probe_data, probe_data_c;
    wire   [7:0] probe_addr;
    // The V30's architectural state, live. dbg_regs leaves the EU every
    // cycle so the probe snapshot is "the CPU is executing THIS" -- a frozen
    // CS:IP on a dead machine reads exactly like the wedge-era PC tap did.
    wire [223:0] v30_dbg_regs;             // {psw, pc, sreg3..0, gpr7..0}
    wire  [15:0] v30_dbg_core;             // EU/BIU interlock: halt/queue/eu_bs
    wire  [31:0] v30_dbg_core2;            // posted access: eu_addr/seg + slots
    wire  [31:0] v30_dbg_core3;            // BIU launch-law registers
    wire  [31:0] v30_dbg_core4;            // EU stall ledger: ucode row + wait wires
    wire  [31:0] v30_dbg_core5;            // queue bytes r_q_mem[0..3]
    wire  [31:0] v30_dbg_core6;            // queue bytes r_q_mem[4..5] + fetch_ptr
    wire         v30_first_pop;            // EU consumed an instruction's byte 0
    reg  [23:0]  retired_cnt = 24'd0;      // saturating instruction counter
    reg          first_pop_q = 1'b0;
    always_ff @(posedge clk_chipset) begin
        first_pop_q <= v30_first_pop;
        if (v30_first_pop && !first_pop_q && retired_cnt != 24'hFF_FFFF)
            retired_cnt <= retired_cnt + 24'd1;
    end

    // Watchdog retirement is a one-clock pulse per channel -- latch it so a
    // probe read seconds later still reports "a draw went unanswered"
    // (slot 0x32). Same clock domain as the GDC block that emits it.
    reg [1:0] draw_to_seen = 2'b00;
    always_ff @(posedge clk_chipset)
        if (reset) draw_to_seen <= 2'b00;
        else       draw_to_seen <= draw_to_seen | gdc_draw_to;

    // Slot 0x33: the last guest I/O write, from the chipset pins -- same
    // two-cycle qualification as itf_port_write/f0_port_write below, so a
    // write strobing its way to another port cannot leave a false record.
    // The latch keeps sampling for as long as the strobe holds (a write
    // whose cycle never completes still names its port), the count ticks
    // once per write, so between two probe reads it separates "parked
    // after this port" from "still writing" -- a beep loop keeps it
    // moving. Pure witness: it reads pins the peripherals already see.
    reg        io_snoop_q = 1'b0, io_snoop_qq = 1'b0;
    reg        io_snoop_armed = 1'b1;
    reg  [7:0] io_wr_count  = 8'h00;
    reg [15:0] last_io_port = 16'h0000;
    reg  [7:0] last_io_data = 8'h00;
    wire       io_port_write = ~chipset_io_write_n & ~chipset_aen;
    always_ff @(posedge clk_chipset) begin
        io_snoop_q  <= io_port_write;
        io_snoop_qq <= io_snoop_q;
        if (io_snoop_qq && io_port_write) begin
            last_io_port <= chipset_address[15:0];
            last_io_data <= cpu_data_bus;
            if (io_snoop_armed) begin
                io_wr_count    <= io_wr_count + 8'd1;
                io_snoop_armed <= 1'b0;
            end
        end else if (!io_port_write)
            io_snoop_armed <= 1'b1;
    end

    // Slot 0x34: the resume-flag read witness. The ITF reads 0035h once per
    // entry (F8005B: in al,35h / test al,80h) to tell a cold boot from a
    // return from OUT 0F0h; the hardware boots the memtest over and over,
    // which is exactly what a stuck bit-7 produces. Latch the value the
    // data bus actually carried on each 0035h read (sampled mid-strobe,
    // same two-cycle qualification as the write snoop), plus a per-read
    // counter, plus the live pc98_sysport_c so a write that never landed
    // is distinguishable from a read that returned stale data.
    reg        rd35_q = 1'b0, rd35_qq = 1'b0;
    reg  [7:0] in35_count = 8'h00;
    reg  [7:0] in35_data  = 8'h00;
    wire       io_port_read = ~chipset_io_read_n & ~chipset_aen;
    wire [7:0] dbg_sysport_w;
    always_ff @(posedge clk_chipset) begin
        rd35_q  <= io_port_read && (chipset_address[15:0] == 16'h0035);
        rd35_qq <= rd35_q;
        if (rd35_q && ~rd35_qq) begin
            in35_data  <= data_bus;
            in35_count <= in35_count + 8'd1;
        end
    end

    // Slots 0x40-0x5F: a 32-deep ring of the guest's fetch cursor (v30_addr
    // alias = zet_pc under PC98_ZET, n186_pc under PC98_NEXT186), frozen
    // when the guest writes port 0xF0 (the PC-98 shutdown/soft-reset) or
    // parks in the ITF error halt (f99e5: cli; jmp $). The ITF failure
    // path resets through 0xF0, which wipes the live cursor before anyone
    // can read it -- this ring survives the reset long enough to name the
    // check that dispatched to the error handler (the entries just before
    // the 0x995d-region jump are the failing test's own instructions).
    // Entries fill oldest-first at write-pointer order; freeze latches the
    // pointer so 0x40+w is the LAST pre-freeze fetch.
    reg [19:0] pc_hist [0:31];
    reg  [4:0] pc_hist_w    = 5'd0;
    reg [19:0] pc_hist_prev = 20'h0;
    reg        pc_hist_frozen = 1'b0;
    wire [19:0] pc_now = v30_addr;
    wire       pc_in_errhalt = (pc_now == 20'hF99E5);
    // Probe write 0x85 re-arms the history: the boot-time F0 write fires
    // the freeze long before any guest crash, so without this the snapshot
    // can never see a guest fault's trail.
    wire       pc_rearm = probe_wr_pulse && (probe_waddr_c == 7'h05);
    always_ff @(posedge clk_chipset) begin
        if (reset || soft_reset_cpu || pc_rearm) begin
            pc_hist_frozen <= 1'b0;
            pc_hist_w      <= 5'd0;
        end else if (!pc_hist_frozen) begin
            if (pc_now != pc_hist_prev) begin
                pc_hist_prev       <= pc_now;
                pc_hist[pc_hist_w] <= pc_now;
                pc_hist_w          <= pc_hist_w + 5'd1;
            end
            if (f0_port_write || pc_in_errhalt || zet_fault)
                pc_hist_frozen <= 1'b1;
        end
    end

    // The freeze has to outlive the soft reset the 0xF0 write triggers,
    // but dropping soft_reset_cpu from the block above deterministically
    // crashes Quartus 18.1's fitter (VPR20KMAIN tdc_util) -- so keep the
    // proven structure and snapshot the ring+pointer into a second bank
    // on the trigger instead. The snapshot clears only on hard reset, so
    // a repeated boot loop keeps the FIRST failure's trail. The fetch
    // landing this same cycle (the jmp$ right after `out`) misses the
    // bulk copy, so it is written into snap[w] explicitly.
    reg [19:0] pc_snap [0:31];
    reg  [4:0] pc_snap_w     = 5'd0;
    reg        pc_snap_valid = 1'b0;
    wire       pc_hist_new   = (pc_now != pc_hist_prev);
    always_ff @(posedge clk_chipset) begin
        if (reset || pc_rearm)
            pc_snap_valid <= 1'b0;
        else if (!pc_snap_valid && (f0_port_write || pc_in_errhalt || zet_fault)) begin
            pc_snap_valid <= 1'b1;
            for (int i = 0; i < 32; i++)
                pc_snap[i] <= pc_hist[i];
            if (pc_hist_new)
                pc_snap[pc_hist_w] <= pc_now;
            pc_snap_w <= pc_hist_w + {4'd0, pc_hist_new};
        end
    end

    // Register the readout: the dbg cones through this mux into the SLD
    // capture were one giant combinational path that crashes Quartus 18.1's
    // timing-driven clustering (VPR20KMAIN tdc_util internal error). One
    // pipeline stage hides the cone; at JTAG speeds the extra clock is free.
    always_ff @(posedge clk_chipset)
        probe_data <= probe_data_c;

    // cpu_ce liveness: every chip-side wait eventually needs a posedge, so
    // a ce_count that moves between probe reads separates "clock enable
    // died" (engine/park frozen, everything else looks ready) from "the
    // engine is stuck on a condition" (count still ticks).
    reg  [15:0] ce_count = 16'd0;
    always_ff @(posedge clk_chipset)
        if (cpu_ce_posedge) ce_count <= ce_count + 16'd1;

    always_comb begin
        case (probe_addr)
            // The bisect-era taps (PIC/timer/keyboard counts, the wedge-PC
            // taps, the JTAG guest-memory master, the JTAG FDD/mgmt
            // channels) went out with PC98_PROBE_EXTRA -- the dbg_regs dump
            // below is what replaced them for "where is the CPU".
            8'h10:   probe_data_c = v30_dbg_regs[223:192];  // psw:pc
            8'h11:   probe_data_c = v30_dbg_regs[191:160];  // sreg3:sreg2
            8'h12:   probe_data_c = v30_dbg_regs[159:128];  // sreg1:sreg0
            8'h13:   probe_data_c = v30_dbg_regs[127:96];   // gpr7:gpr6
            8'h14:   probe_data_c = v30_dbg_regs[95:64];    // gpr5:gpr4
            8'h15:   probe_data_c = v30_dbg_regs[63:32];    // gpr3:gpr2
            8'h16:   probe_data_c = v30_dbg_regs[31:0];     // gpr1:gpr0
            8'h17:   probe_data_c = {8'h00, retired_cnt};   // liveness
            8'h18:   probe_data_c = {12'h000, v30_addr};    // current bus cycle
            // 0x19: {arbiter hold/DRQ, RAM FSM state} -- names WHY a fetch
            // never completes; 0x1a: the ready chain the CPU waits on.
            8'h19:   probe_data_c = {16'h0, chipset_dbg};
            8'h1a:   probe_data_c = {24'h0, chipset_dbg2};
            // 0x31: the GVRAM sequencer -- {svc_req, svc_done, svc_hold,
            // fsm[2:0], plane[1:0]}. A GDC-draw stall reads differently by
            // where it parks: S_RDW = RAM never answered, S_DONE+svc_hold
            // = guest strobe never dropped, svc_req alone = nobody granted
            // the channel (the guest bus is saturated or a hold/HLDA).
            8'h31:   probe_data_c = {24'h0, gvram_dbg};
            // 0x32: the drawing server's health, one read. Ops = the two
            // channels' live opcode bytes {slave, master}; flag = the
            // ITF's EGC-present write to 0000:054D landed; to_seen latches
            // a watchdog retirement (stays set until reset -- a set bit
            // here IS the old stall signature). busy/req are the live
            // handshake; accel_status = {page, EGC, RMW, GRCG armed}.
            8'h32:   probe_data_c = {gdc_draw_ops, egc_flag_w,
                                    draw_to_seen, gdc_draw_busy,
                                    gdc_draw_req, accel_status_w[3:0], 5'b0};
            // 0x33: {writes seen, last port, last byte} -- the ITF's
            // error path talks to 0x35/0x37; a moving count with port
            // 0x37 last is the beep loop, a parked one is the write it
            // died on.
            8'h33:   probe_data_c = {io_wr_count, last_io_port,
                                     last_io_data};
            // 0x34: the resume-flag witness -- {sysport_c, in35 count,
            // in35 data}. bit 7 of the first byte is what the ITF's
            // in-al-35h/test-80h decides cold-boot vs resume on; the last
            // byte is what the data bus actually gave that read.
            8'h34:   probe_data_c = {dbg_sysport_w, 8'h00, in35_count,
                                   in35_data};
            // 0x36: the screen-readback cell {attr,char_hi,char_lo} at
            // dbg_tvram_cell -- each completed read also steps the cell
            // (rd_adv below), so scripts/jtag_screen.tcl dumps the plane
            // one scan per cell. 0x37 echoes the index being sampled.
            8'h36:   probe_data_c = {8'h00, tvram_dbg_word};
            8'h37:   probe_data_c = {20'h0, dbg_tvram_cell};
            // 0x38: a guest-VRAM byte through the sequencer's service
            // channel -- write slot 0x84 launches the address's read, the
            // word below reports {busy, addr, data} and each completed
            // read launches the next address. jtag_gvram.tcl walks ranges.
            8'h38:   probe_data_c = {gv_dbg_req | gv_dbg_busy, 3'b000,
                                   gv_srv_addr, gv_dbg_data};
            // 0x40-0x5F: pc_hist ring (see above). Frozen contents stay
            // readable while the post-0xF0 reboot runs.
            8'h40,8'h41,8'h42,8'h43,8'h44,8'h45,8'h46,8'h47,
            8'h48,8'h49,8'h4a,8'h4b,8'h4c,8'h4d,8'h4e,8'h4f,
            8'h50,8'h51,8'h52,8'h53,8'h54,8'h55,8'h56,8'h57,
            8'h58,8'h59,8'h5a,8'h5b,8'h5c,8'h5d,8'h5e,8'h5f:
                       probe_data_c = pc_snap_valid
                                    ? {7'h00, 1'b1, pc_snap_w,
                                       pc_snap[probe_addr[4:0]]}
                                    : {7'h00, pc_hist_frozen, pc_hist_w,
                                       pc_hist[probe_addr[4:0]]};
            // 0x1b: {bridge park/engine FSM, ce edge counter}. parked=1 with a
            // frozen ce_count is the dead-CE signature; a live count with
            // parked=1 points at the engine's release conditions instead.
            8'h1b:   probe_data_c = {bridge_dbg, ce_count};
            // 0x1c: {ALE'd bus address, v30_bs, the reset/pause terms}.
            // cpu_ad_out vs slot 0x18's v30_addr separates "the engine is
            // driving this cycle" from "the core's pins are frozen".
            8'h1c:   probe_data_c = {3'h0, cpu_ad_out, v30_bs,
                                     pause_core, reset_cpu, reset_chipset,
                                     reset, soft_reset_cpu, cpu_ce_posedge};
            // 0x20: {last byte-pair fed to the core, EU/BIU state}. The
            // pins say PASV while the core does not move: v30_data_i shows
            // what it last consumed, dbg_core says whether the EU waits on
            // the queue (q_cnt=0, ripe=0) or is halted (biu_halted).
            8'h20:   probe_data_c = {v30_data_i, v30_dbg_core};
            // 0x21: the posted access itself -- where the EU's MEMW wants to
            // land and which handshake bits are holding the slot.
            8'h21:   probe_data_c = v30_dbg_core2;
            // 0x22: the BIU's launch-law registers -- {q_head,q_cnt, e_pend,
            // halted, halt_pending, run,cur_fetch/halt/wr,evald, cmt_*, rq_n,
            // slot_busys, opr_held, absorb_ttl, ts}. The posted MEMW has to
            // be sitting on exactly one of these stages.
            8'h22:   probe_data_c = v30_dbg_core3;
            8'h23:   probe_data_c = v30_dbg_core4;
            // 0x24/0x25: the prefetch queue raw bytes + fetch pointer -- the
            // wedged stream itself, for a fingerprint match against the ROM.
            8'h24:   probe_data_c = v30_dbg_core5;
            8'h25:   probe_data_c = v30_dbg_core6;
            // FDD engine: where a disk boot is parked (state/fifo), how many
            // commands stuck, the request bits, the LBA it named, and the
            // command bytes themselves -- a failed boot keeps the failing
            // transaction visible here.
            8'h26:   probe_data_c = fdc_dbg[31:0];
            // SCSI boot witness: the probe window reads only the low 32 bits,
            // so the counters pack under the state flags. Fields, MSB first:
            // scsi_media | cmd_ack | cmd_req | mg_rd[4:0] | post[7:0] |
            // rom_rd[15:0].
            8'h30:   probe_data_c = {scsi_media, dbg_scsi[33:32],
                                   dbg_scsi[28:24], dbg_scsi[23:0]};
            8'h27:   probe_data_c = fdc_dbg[63:32];
            8'h28:   probe_data_c = fdc_dbg_cmd[31:0];
            8'h29:   probe_data_c = fdc_dbg_cmd[63:32];
            // 0x1e/0x1f: the pad words. 1e is what the softcore actually sees
            // (settled | injected, in clk_chipset); 1f is the probe-held mask
            // itself -- a bit stuck there reads as a button held forever, so
            // edge-detection in firmware never fires ("B does nothing").
            8'h1e:   probe_data_c = {cont2_key_chip, cont1_key_chip};
            8'h1f:   probe_data_c = {jtag_btn2, jtag_btn1};
            8'h1d:   probe_data_c = {16'h0, key_count, key_last};
            8'hFF:   probe_data_c = 32'h98C0_DE98;
            default: probe_data_c = {8'hDE, 8'hAD, 8'h00, probe_addr};
        endcase
    end

    wire        probe_wr_tog;
    wire [6:0]  probe_wr_addr;
    wire [31:0] probe_wr_data;
    wire        probe_rd_adv;
    wire        probe_rd_adv_gv;
    pc98_jtag_probe u_jtag_probe (
        .probe_addr_sel (probe_addr),
        .probe_data     (probe_data),
        .wr_tog         (probe_wr_tog),
        .wr_addr        (probe_wr_addr),
        .wr_data        (probe_wr_data),
        .rd_adv         (probe_rd_adv),
        .rd_adv_gv      (probe_rd_adv_gv)
    );
`endif

    //
    // SETTINGS
    //

    wire [1:0] buttons;

    // Interact "Reset PC" (0x50): stretch the one-shot write to a level, sync to the
    // chipset clock, and fold into the guest reset so the machine re-POSTs.
    reg [19:0] interact_reset_delay = 20'd0;
    // Interact "Extra Options" (0x54): same one-shot stretch to the softcore, which
    // opens the settings OSD (the guaranteed opener if Button Select was remapped).
    reg [19:0] osd_open_delay = 20'd0;
    // Interact list settings: each latched write-only from its bridge address, then
    // synced into the core clock below.
    reg  [1:0] wp_cfg_74a        = 2'd0;   // floppy write-protect {B:, A:}
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
    // Probe-held buttons: write slot 0x83 latches {cont2_mask, cont1_mask} into jtag_btn*
    // (in clk_chipset below), which ORs onto the settled pad words as a held-press level.
    // Every consumer downstream -- the any-button wake, the chipset-domain pad words,
    // pocket_keyboard's pad->key mapper, mouse mode -- sees them as real presses.
    // The masks change only on JTAG writes, so the cross-domain OR is a quasi-static level.
`ifdef PC98_JTAG
    reg  [15:0] jtag_btn1 = 16'd0, jtag_btn2 = 16'd0;
    wire [15:0] cont1_key_eff = cont1_key_s | jtag_btn1;
    wire [15:0] cont2_key_eff = cont2_key_s | jtag_btn2;
`else
    wire [15:0] cont1_key_eff = cont1_key_s;
    wire [15:0] cont2_key_eff = cont2_key_s;
`endif

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
    end
    wire       interact_reset;
    wire       osd_open_req;
    wire [1:0] wp_cfg;
    wire [2:0] palette_cfg;

    // osd_* are in the clk_chipset domain (clk_pico is a gated clk_chipset).
    wire [1:0] cpu_speed_cfg  = osd_cpu_speed;
    wire [1:0] bios_wr_cfg    = osd_bios_wr;
    wire [1:0] boost_cfg      = osd_boost;
    wire [1:0] spk_vol_cfg    = osd_spk_vol;
    wire [1:0] stereo_mix_cfg = osd_stereo;
    synch_3              s_interact_reset (|interact_reset_delay, interact_reset, clk_chipset);
    synch_3              s_osd_open       (|osd_open_delay,    osd_open_req,  clk_chipset);
    synch_3 #(.WIDTH(2)) s_wp_cfg         (wp_cfg_74a,        wp_cfg,        clk_chipset);
    synch_3 #(.WIDTH(16)) s_cont1_chip    (cont1_key_eff,     cont1_key_chip, clk_chipset);
    synch_3 #(.WIDTH(16)) s_cont2_chip    (cont2_key_eff,     cont2_key_chip, clk_chipset);
    synch_3 #(.WIDTH(3)) s_palette_cfg    (osd_palette,       palette_cfg,   clk_pix);
    // The 200-line skip's two terms are both chipset-domain: the OSD bit and
    // CHIPSET's doubled-mode flag. Their product crosses to clk_pix once --
    // a quasi-static pair, so tearing between them is at most one frame.
    wire       dbl200;                  // CHIPSET video: a doubled 200-line mode is up
    wire       dbl_skip_pix;
    synch_3              s_dbl_skip_pix (osd_dbl_skip & dbl200, dbl_skip_pix, clk_pix);
    wire       vid_txt;                 // CHIPSET video: the composited dot is text's
    wire pause_core = pause_core_chipset;

    // Disk-access lamp: a management service request lights an on-screen lamp for a
    // beat, but only one with media behind it. The floppy side arrives already
    // qualified by the requesting drive's present bit (an eject can leave a
    // request raised while the softcore drains the dying command), and the SCSI
    // side is qualified by the firmware's image-mounted flag because the option
    // ROM's TEST UNIT READY probes toggle the request through POST on an empty
    // machine. The request level is a short pulse per sector, so a stretcher
    // keeps it visible -- 2^20 clk_pix ticks is about 0.1 s (was 2^22/0.4 s;
    // the part is one LAB short of full).
    wire fdd_media_req;
    wire scsi_media;
    wire disk_act_chip = fdd_media_req | (mgmt_req[0] & scsi_media);
    wire disk_act_pix;
    synch_3 s_disk_act (disk_act_chip, disk_act_pix, clk_pix);
    reg [19:0] disk_led_t = 20'd0;
    always @(posedge clk_pix) begin
        if (disk_act_pix)        disk_led_t <= 20'hFFFFF;
        else if (|disk_led_t)    disk_led_t <= disk_led_t - 20'd1;
    end
    wire disk_led_on = osd_disk_led & (|disk_led_t);

    // gamepad_mode picks what the pad drives: mapped keys, the game port, or the serial mouse. The
    // softcore's per-control key_cfg reaches pocket_keyboard unchanged.
    wire [1:0]  gamepad_mode = osd_gamepad;
    wire        mousepad = (gamepad_mode == 2'd2);
    wire [15:0] cont1_key_chip;
    wire [15:0] cont2_key_chip;

    // Game-port options from the settings OSD: [4]=Sync-to-CPU turbo timing, [3:2]=Joystick 2,
    // [1:0]=Joystick 1; each 2-bit field is 0=Analog, 1=Digital, 2=Disabled.


    // MiSTer front-panel buttons; the Pocket has none.
    assign buttons = 2'b00;

    //
    // INPUT
    //

    wire  [7:0] kb_byte;
    wire        kb_valid;
    wire        kb_ready;

    //
    // Keyboard: pad buttons + docked USB keyboard + VKB merged into one Set-2 byte
    // stream (kb_byte/kb_valid, paced by kb_ready). In mouse mode the D-pad and A/B
    // drop out (they drive the mouse); X/Y and Select/Start stay mapped keys.
    wire [15:0] kb_buttons = mousepad ? (cont1_key_eff & 16'hFFC0) : cont1_key_eff;

    pocket_keyboard #(.clk_rate(cur_rate)) u_pocket_keyboard (
        .clk          (clk_chipset),
        .reset        (reset),
        .buttons      (kb_buttons),
        // "Joystick" mode: the pad drives the -86 board's SSG game port
        // (opna_joy below) instead of the mapped keys, so the pad->keys
        // mapping stays suppressed here.
        .gamepad      (gamepad_mode == 2'd1),
        .osd_active   (osd_active),
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
    // PC-98 keyboard: the Set-2 stream above is the PS/2 scan language;
    // a PC-98 keyboard is a serial device on the 8251 at ports 0x41/0x43 that
    // sends one matrix byte per key, bit 7 set on release. pc98_kbd_ps2 taps
    // the SAME stream -- it never stalls it, ps2_keyboard's kb_ready keeps the
    // pace -- and re-emits each key as a PC-98 event.
    //
    // INTEGRATION CONTRACT (the 8251 model in Peripherals.sv): these feed
    // its key-
    // injection port through CHIPSET (pc98_kbd8251's key_stb/key_byte; the
    // byte rides as-is because bit 7 is already set on a release). The
    // simulation +keys channel is bench-side only (tb_pc98_v30.sv drives its
    // own model), so the two sources never meet in RTL.
    //
    // ps2_keyboard's keybord_interrupt is OFF the master PIC's IRQ1 in the PC-98
    // build -- IRQ1 now comes from the 8251's RxRDY line (see Peripherals.sv).
    //
    wire       pc98_key_stb;
    wire       pc98_key_make;
    wire [7:0] pc98_key_code;
    wire       kbd_key_stb;
    wire       kbd_key_make;
    wire [7:0] kbd_key_code;

    // How far does a key get? key_count counts pc98_key_stb pulses and key_last
    // holds the last event ({make, code}) -- the output of the translator, so
    // before the 8251 and before IRQ1. The panel's KEY field reads them.
    //
    // Zero after pressing keys means the virtual keyboard, the firmware's
    // vkb_stb toggle or pocket_keyboard's queue never produced the byte.
    // Climbing means the key reached the PC-98 side and whatever is wrong is
    // downstream: the 8251 model, IRQ1 off its RxRDY, or the guest.
    // key_stb TOGGLES per event -- pc98_kbd_ps2's mailbox idiom, and what
    // pc98_kbd8251 compares against its own copy. Counting it as a LEVEL, which
    // this did at first, adds one per CLOCK for as long as the toggle sits
    // high: KEY saturated at FF within microseconds of the first key and said
    // nothing. Count transitions, so KEY is comparable with IRQ below it.
`ifdef PC98_JTAG
    logic pc98_key_stb_q = 1'b0;
    always @(posedge clk_chipset) begin
        pc98_key_stb_q <= pc98_key_stb;
        if (pc98_key_stb != pc98_key_stb_q) begin
            key_last <= {pc98_key_make, pc98_key_code[6:0]};
            if (key_count != 8'hFF) key_count <= key_count + 8'd1;
        end
    end
`endif

    pc98_kbd_ps2 u_pc98_kbd_ps2 (
        .clk      (clk_chipset),
        .reset    (reset),
        .kb_byte  (kb_byte),
        .kb_valid (kb_valid),
        .kb_ready (kb_ready),
        .key_stb  (kbd_key_stb),
        .key_make (kbd_key_make),
        .key_code (kbd_key_code)
    );

`ifdef PC98_JTAG
    // Probe writes land in clk_chipset once, as a pulse with the payload
    // copied alongside it. Slot 0x81 is a PC-98 matrix byte for the key line;
    logic [2:0] jw_sync = 3'd0;
    logic [2:0] adv_sync = 3'd0;
    logic [2:0] gva_sync = 3'd0;
    logic [2:0] gvd_sync = 3'd0;
    logic [2:0] gvi_sync = 3'd0;
    logic       probe_wr_pulse;
    logic [6:0] probe_waddr_c;
    logic [31:0] probe_wdata_c;
    always_ff @(posedge clk_chipset) begin
        jw_sync  <= {jw_sync[1:0], probe_wr_tog};
        adv_sync <= {adv_sync[1:0], probe_rd_adv};
        gva_sync <= {gva_sync[1:0], probe_rd_adv_gv};
        gvd_sync <= {gvd_sync[1:0], st_done_w};
        gvi_sync <= {gvi_sync[1:0], st_req_w};
        probe_wr_pulse <= jw_sync[2] != jw_sync[1];
        if (jw_sync[2] != jw_sync[1]) begin
            probe_waddr_c <= probe_wr_addr;
            probe_wdata_c <= probe_wr_data;
        end
        // Slot 0x83: {cont2, cont1} held-button masks, OR-ed onto the settled
        // pad words in clk_74a. A set bit stays down until the mask clears.
        if (probe_wr_pulse && probe_waddr_c == 7'h03) begin
            jtag_btn1 <= probe_wdata_c[15:0];
            jtag_btn2 <= probe_wdata_c[31:16];
        end
        // Slot 0x82 selects the TVRAM cell the screen probe samples; every
        // completed screen-slot read (the rd_adv toggle) steps it instead,
        // so a dump is one JTAG scan per cell.
        if (probe_wr_pulse && probe_waddr_c == 7'h02)
            dbg_tvram_cell <= probe_wdata_c[11:0];
        else if (adv_sync[2] != adv_sync[1])
            dbg_tvram_cell <= dbg_tvram_cell + 12'd1;

        // Slot 0x84 launches a guest-VRAM byte read on the service channel;
        // every completed 0x38 read re-arms it at the next address, so a
        // dump is one scan per byte. The claim waits for the firmware's
        // request to be idle (a level, synced) and holds to done.
        if (probe_wr_pulse && probe_waddr_c == 7'h04) begin
            gv_dbg_addr <= probe_wdata_c[19:0];
            gv_dbg_req  <= 1'b1;
        end else if (gva_sync[2] != gva_sync[1] && !gv_dbg_req
                     && !gv_dbg_busy) begin
            // Never move the address while a read is in flight -- the mux
            // feeds it straight to the sequencer.
            gv_dbg_addr <= gv_dbg_addr + 20'd1;
            gv_dbg_req  <= 1'b1;
        end
        if (gv_dbg_req && !gv_dbg_busy && !gvi_sync[2]) begin
            // The address the sequencer sees is latched at the claim, so a
            // probe write that lands mid-read cannot bend it.
            gv_srv_addr <= gv_dbg_addr;
            gv_dbg_req  <= 1'b0;
            gv_dbg_busy <= 1'b1;
        end else if (gv_dbg_busy && (gvd_sync[2] != gvd_sync[1])) begin
            gv_dbg_busy <= 1'b0;
            gv_dbg_data <= st_rdata_w;
        end
    end

    // JTAG-injected keystrokes ride the same event line the 8251 drains; a
    // probe write to slot 0x81 lands one toggle per injected matrix byte.
    pc98_key_inject u_pc98_key_inject (
        .clk      (clk_chipset),
        .wr_pulse (probe_wr_pulse),
        .wr_addr  (probe_waddr_c),
        .wr_data  (probe_wdata_c),
        .kbd_stb  (kbd_key_stb),
        .kbd_make (kbd_key_make),
        .kbd_code (kbd_key_code),
        .key_stb  (pc98_key_stb),
        .key_make (pc98_key_make),
        .key_code (pc98_key_code)
    );
`else
    assign pc98_key_stb  = kbd_key_stb;
    assign pc98_key_make = kbd_key_make;
    assign pc98_key_code = kbd_key_code;
`endif

    //
    // Mouse: the dock report stream lands on pc98_mouse_src and feeds the
    // PC-98 bus mouse's second 8255 inside CHIPSET -- the only guest-facing
    // mouse interface, since this machine has no COM1 UART for a serial
    // mouse to feed. In mouse mode the pad's D-pad and A/B drive it too;
    // quiet under an overlay.
    //
    wire [5:0] mouse_pad = (mousepad && !osd_active) ? cont1_key_chip[5:0] : 6'd0;

    // In joystick mode the pad feeds the -86 board's game port instead: OPNA
    // SSG index 0x0E (IOA) reads it back, active low, in np21w's joymng.h
    // order {B, A, rapidB, rapidA, R, L, D, U}. Pad bits are {B, A, R, L, D,
    // U} on [5:0] with X/Y as the rapid-fire pair on [7:6]; 8'hFF in the other
    // modes reads as no stick fitted.
    wire [7:0] opna_joy =
        (gamepad_mode == 2'd1 && !osd_active)
            ? ~{cont1_key_chip[5], cont1_key_chip[4],
                cont1_key_chip[7], cont1_key_chip[6],
                cont1_key_chip[3], cont1_key_chip[2],
                cont1_key_chip[1], cont1_key_chip[0]}
            : 8'hFF;

    wire signed [15:0] mouse_dx, mouse_dy;
    wire               mouse_ev;
    wire        [1:0]  mouse_btn;

    pc98_mouse_src #(.clk_rate(cur_rate)) u_pc98_mouse_src (
        .clk          (clk_chipset),
        .cont4_joy    (cont4_joy),
        .cont4_key    (cont4_key),
        .cont4_trig   (cont4_trig),
        .pad          (mouse_pad),
        .ev_dx        (mouse_dx),
        .ev_dy        (mouse_dy),
        .ev_v         (mouse_ev),
        .btn          (mouse_btn)
    );

    //
    // ROM AND BIOS LOAD
    //

    wire        ioctl_download;
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

    // Decoupling FIFO, entry = {slot_tag, addr[24:0], data[15:0]}: the slot tag rides each
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
    // PC-98's slots are decided purely by address, so the predicate is exact:
    // every image slot is a fixed address window with no index discriminator.
    wire rom_dl_wanted = (dl_addr[24:17] == 8'h00)      // bios.rom
                       | (dl_addr[24:15] == 10'h004)    // itf.rom
                       | (dl_addr[24:20] == 5'h01);     // font.rom

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
    // answers in ten cycles where the old single-port answered in five, so a change of
    // controller changes whether the assumption holds.
    //
    // That matters because run#106 showed the BIOS image arriving incomplete:
    // the loader never presented F000:D882-D883 or D88E-D88F, while every other
    // byte of that window was written correctly. A dropped ioctl word is
    // exactly that shape, and it would be invisible to every SDRAM testbench.
    //
    // That danger is now only historical context -- the drop/level counters
    // that watched it left with postmon, and the FIFO's full flag is still
    // what keeps a dropped word impossible.

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
        if (rlf_pop && ~rlf_empty)
            rlf_rptr <= rlf_rptr + 1'b1;
    end

    // Copier: present the FIFO head to the BIOS FSM as ioctl, honoring ioctl_wait.
    assign ioctl_download = load_active;
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

    // ANK font load, straight off data_loader rather than through the ROM FIFO
    // and the ext port. It is a 6 KB BRAM with no handshake, so queueing it
    // behind the BIOS load would buy nothing.
    //
    // data.json puts font.rom at bridge 0x10100000. The BRAM keeps the file's
    // ANK sets: the 8x16 half (file 0x0800-0x17FF) at words 0x000-0x7FF and,
    // for the mode1-bit-3-clear case, the 8x8 half (file 0x0000-0x07FF) at
    // words 0x800-0xBFF (np21w font/fontv98.c). So the window is the whole
    // dl_addr 0x100000-0x1017FF.
    wire        font_dl_hit  = dl_wr && (dl_addr[27:16] == 12'h010)
                                     && (dl_addr[15:0] <  16'h1800);
    wire [11:0] font_dl_addr = (dl_addr[15:0] >= 16'h0800)
                             ? ({1'b0, dl_addr[11:1]} - 12'h400)   // 8x16 bank
                             :  (dl_addr[11:1] + 12'h800);        // 8x8 bank

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
    // The slot's 64 KB decode window is wider than the 48 KB ROM; past the
    // top the word address would wrap and corrupt the image from below.
    wire        fw_dl_hit  = dl_wr && fw_dl_slot && (dl_addr[15:0] < 16'hC000);
    wire [13:0] fw_word    = dl_addr[15:2];
    reg  [15:0] fw_lo;
    reg         fw_wr_en_r;
    reg  [13:0] fw_wr_addr_r;
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
    reg        bios_shadow_write;
    reg        font_bank_write;
    // PC-98: BIOS.ROM is 0x18000 bytes at physical 0x0E8000, which is where np21w
    // reads it to and what the file size says (docs/PC98_MACHINE_SPEC.md F1).
    // Ninety-six KB, so the slot's address needs seventeen bits, not sixteen --
    // masking addr[24:16] to zero would land everything in one 64 KB page at
    // F0000 and fold the top third of the image back over the bottom.
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
    // writing and RAM.sv routes it to the shadow bank.
    wire select_bios  = (ioctl_addr[24:17] == 8'h00);
    wire select_itf   = (ioctl_addr[24:15] == 10'h004);
    // font.rom, 0x46800 bytes at bridge 0x10100000. The slot's address is
    // chosen so the low twenty bits ARE the file offset: the font bank
    // redirects those to 0x400000 upward inside RAM.sv, so the loader needs no
    // arithmetic and the ext port's twenty bits are enough for a 282 KB image.
    wire select_font  = (ioctl_addr[24:20] == 5'h01);
    wire select_shadow = select_itf;

    wire [19:0] bios_access_address_wire =
         select_bios ? (PC98_BIOS_BASE + {3'b000, ioctl_addr[16:0]}) :
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
    // for us. np21w writes exactly the same five bytes (bios.c: mem[0xffff0] =
    // 0xea, then 0xfd800000) -- it restores the vector too.
    //
    // Only the word at FFFF0 differs, so one address needs intercepting.
    wire        rom_patch_reset = select_bios
                                & (bios_access_address_wire == 20'hFFFF0);
    wire [15:0] rom_data_in     = rom_patch_reset ? 16'h00EA : ioctl_data;

    wire bios_load_n = ~(ioctl_download & (select_bios | select_itf | select_font));

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
            bios_shadow_write    <= 1'b0;
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
                    bios_shadow_write    <= 1'b0;
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
                    bios_shadow_write    <= select_shadow;
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
                    bios_shadow_write    <= bios_shadow_write;
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
                    bios_shadow_write    <= bios_shadow_write;
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
                    bios_shadow_write    <= bios_shadow_write;
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
                    bios_shadow_write    <= 1'b0;
                    ioctl_wait          <= 1'b0;
                    bios_load_state     <= 4'h00;
                end
            endcase
        end
    end

    //
    // CHIPSET bus
    //
    wire [19:0] chipset_address;
    wire        chipset_io_write_n, chipset_memory_read_n, chipset_memory_write_n;
    wire        chipset_io_read_n;
    wire        chipset_aen;

    //
    // BOOT HOLD
    //
    // What is kept is the synchronisation that merely shared the
    // name: hold the guest in reset until the BIOS dataslot has streamed in
    // and the softcore has pushed the saved settings, so the machine does not
    // start executing against a half-loaded ROM.
    //
    reg guest_hold = 1'b1;
    reg phys_reset_hold = 0;
    reg [23:0] phys_reset_cnt = 24'd0;
    localparam [23:0] PHYS_RESET_HOLD = 24'd2863600;
    wire bios_ever_loaded_28;
    wire soft_guest_hold_28;
    synch_3 s_bios_loaded (bios_ever_loaded, bios_ever_loaded_28, clk_28_636);
    synch_3 s_soft_hold   (soft_guest_hold,  soft_guest_hold_28,  clk_28_636);

    always @(posedge clk_28_636)
    if (ce_14_318)
    begin
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

        if (guest_hold && bios_ever_loaded_28 && ~soft_guest_hold_28)
            guest_hold <= 1'b0;
    end

    // Over to the chipset clock, where the guest reset is assembled.
    reg guest_hold_sync1 = 1'b1;
    reg guest_hold_sync2 = 1'b1;
    always @(posedge clk_chipset)
    begin
        guest_hold_sync1 <= guest_hold;
        guest_hold_sync2 <= guest_hold_sync1;
    end

    //
    // THE MACHINE
    //

    wire pause_core_chipset;

    wire [7:0] data_bus;
    wire [19:0] cpu_ad_out;
    reg  [19:0] cpu_address;
    wire [7:0] cpu_data_bus;
    // The 16-bit memory path's extra lane, between v30_cpu_bridge and the
    // chipset's RAM/option-ROM muxes.
    wire [7:0] cpu_data_bus_hi;
    wire [7:0] data_bus_hi;
    wire       cpu_word_access;
    // Sixteen-colour mode: CHIPSET decides it (port 0x6A) and the bridge has
    // to know, because it and RAM.sv must agree on where memory is.
    wire       pc98_analog;
    wire processor_ready;
    wire interrupt_to_cpu;
    wire address_latch_enable;
    wire address_direction;

    wire lock_n;
    wire [2:0]processor_status;

    wire [3:0]   dma_acknowledge_n;
    // PC98_JTAG probe taps from deep inside the chipset: arbiter hold/DRQ
    // and RAM FSM state (0x19), the ready chain (0x1a). Costs nothing when
    // the macro is off -- the cone prunes.
    wire [15:0]  chipset_dbg;
    wire  [7:0]  chipset_dbg2;
    wire  [7:0]  gvram_dbg;   // the GVRAM sequencer's walk + service channel
    wire [23:0]  tvram_dbg_word; // screen probe: {attr,char_hi,char_lo}
    logic [11:0] dbg_tvram_cell; // screen probe: the cell being sampled
    // Probe-driven guest-VRAM reads ride the sequencer's service channel
    // the firmware owns (softcpu 0x5000_0000). A pending probe read claims
    // the channel whenever the firmware isn't requesting, holds until the
    // sequencer's done edge, then answers slot 0x38.
    logic [19:0] gv_dbg_addr = 20'd0;
    logic [19:0] gv_srv_addr = 20'd0;
    logic        gv_dbg_req  = 1'b0;
    logic        gv_dbg_busy = 1'b0;
    logic [7:0]  gv_dbg_data = 8'h00;
    wire        st_req_m = gv_dbg_busy ? 1'b1         : st_req_w;
    wire        st_we_m  = gv_dbg_busy ? 1'b0         : st_we_w;
    wire        st_raw_m = gv_dbg_busy ? 1'b0         : st_raw_w;
    wire [19:0] st_addr_m  = gv_dbg_busy ? gv_srv_addr : st_addr_w;
    wire [7:0]  st_wdata_m = gv_dbg_busy ? 8'h00      : st_wdata_w;
    wire [33:0]  dbg_scsi;   // {ack,req,mg_rd_cnt,post_cnt,rom_rd_cnt}
    wire [63:0]  fdc_dbg;      // floppy engine: state, fifo, reqs, LBA
    wire [63:0]  fdc_dbg_cmd;  // live command {op,unit,C,H,R,N,EOT,GPL}

    wire    [1:0]   fdd_present;
    reg     [7:0]   sw;

    wire    [5:0]   sw_base;
    wire    [1:0]   sw_floppy;

    assign  sw_base = 6'b101101;
    assign  sw_floppy = fdd_present[1] ? 2'b01 : 2'b00;
    assign  sw = {sw_floppy, sw_base}; // DIP switches (display type and floppy count)

    // ---------------------------------------------------------------- ITF bank
    //
    // F8000-FFFFF is 32 KB of ROM that is the ITF at power-on and the system
    // BIOS afterwards. The ITF switches it itself, through port 0x043D:
    // 0x10 selects the ITF, 0x12 selects the BIOS (np21w io/necio.c, and the real
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
    // protected mode. On a real-mode V30 it cannot reach its own hand-over, however
    // much of the I/O map is in place -- and this session put the map in place
    // and watched it get as far as the GDC vsync wait at F80388.
    //
    // So boot where the ITF would have handed over. BIOS.ROM's reset vector is
    // already EA 00 00 80 FD, its entry at FD800 is EB 02 EB 5D FA 33 C0 ... --
    // plain 8086 throughout -- and np21w boots exactly this way, having no ITF at
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
            // cycle -- a transient that once logged POST codes the BIOS never
            // wrote. Switching the ROM out from under the
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

    // One flag drives both directions of the shadow: while the loader writes
    // it routes the ITF image in, and at all other times it decides which of
    // the two ROMs the guest sees at F8000.
    //
    // The self-test master is the one reader that must NOT see the shadow. It
    // is a diagnostic window onto the image the loader wrote at a guest
    // address, and with PC98_BOOT_ITF the machine powers up with itf_bank set
    // -- so a peek of FD800 with the guest still held would read the ITF copy
    // at 1FD800 instead of the BIOS at FD800. The ITF
    // image holds nothing but zero padding from file offset 0x5800 up, so the
    // panel read BAD 0EC: 236 of 256 bytes "wrong", which is exactly 256 minus
    // the 20 bytes the BIOS entry itself holds as zero.
    wire bios_shadow_flag = bios_write_n ? itf_bank : bios_shadow_write;
    // Only ever set during a loader write: the guest has no font bank to see.
    wire font_bank_load  = ~bios_write_n & font_bank_write;

    // The EMS board's fitted size from the OSD: None/2/4/8 MB -> 0/2/4/8.
    wire [3:0] ems98_maxmem = (osd_extmem == 2'd3) ? 4'd8 : {osd_extmem, 1'b0};

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

        .clk_select                         (clk_select),
        .reset                              (reset_chipset),
        .sdram_reset                        (reset_sdram),
        .cpu_address                        (cpu_address),
        .cpu_data_bus                       (cpu_data_bus),
        .cpu_word_access                    (cpu_word_access),
        .cpu_data_bus_hi                    (cpu_data_bus_hi),
        .data_bus_hi                        (data_bus_hi),
        .pc98_analog                        (pc98_analog),
        .processor_status                   (processor_status),
        .processor_lock_n                   (lock_n),
    //  .processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
        .processor_ready                    (processor_ready),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .clk_pc98_dot                       (clk_pc98_dot),

        .gdc_draw_req                       (gdc_draw_req),
        .gdc_draw_busy                      (gdc_draw_busy),
        .gdc_draw_ops                       (gdc_draw_ops),
        .gdc_draw_to                        (gdc_draw_to),
        .dbg_egc_flag                       (egc_flag_w),
        .dbg_sysport                        (dbg_sysport_w),
        .tvram_dbg_cell                     (dbg_tvram_cell),
        .tvram_dbg_word                     (tvram_dbg_word),
        .gdc_draw_snaps                     (gdc_draw_snaps),
        .gdc_srv_done_levels                (gdc_srv_done_levels),
        .st_req                             (st_req_m),
        .st_we                              (st_we_m),
        .st_raw                             (st_raw_m),
        .st_addr                            (st_addr_m),
        .st_wdata                           (st_wdata_m),
        .st_done                            (st_done_w),
        .st_rdata                           (st_rdata_w),
        .accel_status                       (accel_status_w),

        .VID_R                              (r),
        .VID_G                              (g),
        .VID_B                              (b),
        .VID_HSYNC                          (HSync),
        .VID_VSYNC                          (VSync),
        .VID_HBlank                         (HBlank),
        .VID_VBlank                         (VBlank),
        .dbl200                             (dbl200),
        .VID_TXT                            (vid_txt),
        .address                            (chipset_address),
        .address_ext                        (bios_access_address),
        .ext_access_request                 (bios_access_request),
        .address_direction                  (address_direction),
        .data_bus                           (data_bus),
        .data_bus_ext                       (bios_write_data[7:0]),
    //  .data_bus_direction                 (data_bus_direction),
        .address_latch_enable               (address_latch_enable),
        .io_channel_ready                   (1'b1),
        .interrupt_request                  (0),    // use? -> It does not seem to be necessary.
        .io_read_n                          (chipset_io_read_n),
        .io_read_n_ext                      (1'b1),
    //  .io_read_n_direction                (io_read_n_direction),
        .io_write_n                         (chipset_io_write_n),
        .io_write_n_ext                     (1'b1),
    //  .io_write_n_direction               (io_write_n_direction),
        .memory_read_n                      (chipset_memory_read_n),
        .memory_read_n_ext                  (1'b1),
    //  .memory_read_n_direction            (memory_read_n_direction),
        .memory_write_n                     (chipset_memory_write_n),
        .memory_write_n_ext                 (bios_write_n),
    //  .memory_write_n_direction           (memory_write_n_direction),
        .dma_request                        (0),    // use? -> I don't know if it will ever be necessary, at least not during testing.
        .dma_acknowledge_n                  (dma_acknowledge_n),
        .address_enable_n                   (chipset_aen),
        .dbg_chipset                        (chipset_dbg),
        .dbg_chipset2                       (chipset_dbg2),
        .dbg_gvram                          (gvram_dbg),
        .dbg_scsi                           (dbg_scsi),
    //  .terminal_count_n                   (terminal_count_n)
        .speaker_out                        (speaker_out),
        .kb_byte                            (kb_byte),
        .kb_valid                           (kb_valid),
        .kb_ready                           (kb_ready),
        .opna_snd_l                         (opna_snd_l),
        .opna_snd_r                         (opna_snd_r),
        .font_bank_flag                     (font_bank_load),
        .bios_shadow_flag                    (bios_shadow_flag),
        .font_wr_clk                        (clk_chipset),
        .font_wr_en                         (font_dl_hit),
        .font_wr_addr                       (font_dl_addr),
        .font_wr_data                       (dl_data),
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
        .ems98_maxmem                       (ems98_maxmem),
        .bios_protect_flag                  (bios_protect_flag),
        .mgmt_readdata                      (mgmt_din),
        .mgmt_writedata                     (mgmt_dout),
        .mgmt_address                       (mgmt_addr),
        .mgmt_write                         (mgmt_wr),
        .mgmt_read                          (mgmt_rd),
        .floppy_wp                          (wp_cfg),
        // The FDC's domain IS clk_chipset, so the setting bit arrives on a
        // plain wire, the way osd_extmem reaches the EMS board below it.
        .fdd_turbo                          (osd_fdd_turbo),
        .cfg_dipsw2                         (osd_dipsw2),
        .cfg_a3fea                          (osd_a3fea),
        .cfg_a3fee                          (osd_a3fee),
        .cfg_a3ff2                          (osd_a3ff2),
        .rtc_time                           (rtc_time),
        .fdd_present                        (fdd_present),
        .fdd_request                        (mgmt_req[7:6]),
        .fdd_media_req                      (fdd_media_req),
        .scsi_request                       (mgmt_req[0]),
        .dbg_fdc                            (fdc_dbg),
        .dbg_fdc_cmd                        (fdc_dbg_cmd),
        .wait_count_clk_en                  (cpu_ce_negedge),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle),
        .vram_wait_en                       (vram_wait_en),
        .pause_core                         (pause_core_chipset),
        .ram_rw_complete                    (ram_rw_complete)
        ,.pc98_key_stb                      (pc98_key_stb)
        ,.pc98_key_byte                     (pc98_key_code)
        ,.mouse_dx                          (mouse_dx)
        ,.mouse_dy                          (mouse_dy)
        ,.mouse_ev                          (mouse_ev)
        ,.mouse_btn                         (mouse_btn)
        ,.opna_joy                          (opna_joy)
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

    wire [2:0] SEGMENT;

    // ---------------------------------------------------------------- the CPU
    //
    // nuV30 (the real part whose microcode the ROMs expect -- the ITF's
    // F9476 pushes imm16, a 186-class opcode an 8086 dispatches to an
    // undocumented JS alias) through v30_cpu_bridge, which runs each 16-bit
    // cycle as one two-lane cycle where the SDRAM answers and two byte
    // cycles everywhere else on the eight-bit bus. The wiring follows
    // tb_pc98_v30, the
    // bench that booted N88-BASIC on this core, and tb_v30_bridge, the
    // bench that proved the bridge: CLK=clk_chipset, CE gated by the
    // bridge, INT from the PIC, DATA_I assembled by the bridge.
    //
    // The CE generator's outputs still pace the CHIPSET's RAM waits, which
    // is where they are consumed.
    wire [15:0] bridge_dbg;

`ifdef PC98_ZET
    // --------------------------------------------------------------------
    // EXPERIMENTAL (zet-cpu branch): the Zet 80186-class core on a Wishbone
    // master, bridged to the same 8288 byte world. See zet_cpu_bridge.sv's
    // header for the contract. This is NOT the shipping CPU -- nuV30 is.
    // --------------------------------------------------------------------
    wire        zet_clk;
    wire [15:0] zwb_dat_i, zwb_dat_o;
    wire [19:1] zwb_adr;
    wire        zwb_we, zwb_tga, zwb_stb, zwb_cyc, zwb_ack;
    wire [ 1:0] zwb_sel;
    wire        zwb_inta, zwb_nmia;
    wire [19:0] zet_pc;
    wire        zet_fault;

    zet_cpu_bridge u_zet_bridge (
        .clk               (clk_chipset),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .reset             (reset_cpu),
        .zet_clk           (zet_clk),
        .wb_dat_o          (zwb_dat_o),
        .wb_dat_i          (zwb_dat_i),
        .wb_adr_o          (zwb_adr),
        .wb_we_o           (zwb_we),
        .wb_tga_o          (zwb_tga),
        .wb_sel_o          (zwb_sel),
        .wb_stb_o          (zwb_stb),
        .wb_cyc_o          (zwb_cyc),
        .wb_ack_i          (zwb_ack),
        .wb_tgc_o          (zwb_inta),
        .nmia              (zwb_nmia),
        .processor_status  (processor_status),
        .ad_out            (cpu_ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (lock_n),
        .analog_mode       (pc98_analog),
        .word_access       (cpu_word_access),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (data_bus_hi),
        .data_bus          (data_bus),
        .processor_ready   (processor_ready),
        .address_enable_n  (chipset_aen),
        .pause_core        (pause_core),
        .biu_done          (biu_done),
        .dbg               (bridge_dbg)
    );

    zet u_cpu (
        .wb_clk_i  (zet_clk),
        .wb_rst_i  (reset_cpu),
        .wb_dat_i  (zwb_dat_i),
        .wb_dat_o  (zwb_dat_o),
        .wb_adr_o  (zwb_adr),
        .wb_we_o   (zwb_we),
        .wb_tga_o  (zwb_tga),
        .wb_sel_o  (zwb_sel),
        .wb_stb_o  (zwb_stb),
        .wb_cyc_o  (zwb_cyc),
        .wb_ack_i  (zwb_ack),
        .wb_tgc_i  (interrupt_to_cpu),
        .wb_tgc_o  (zwb_inta),
        .nmi       (1'b0),
        .nmia      (zwb_nmia),
        .pc        (zet_pc),
        .dbg_fault (zet_fault)
    );

    // The probe slots that usually expose V30 guts get the Zet view instead.
    wire [19:0] v30_addr = zet_pc;
    wire [2:0]  v30_bs   = processor_status;
    wire [15:0] v30_data_i = zwb_dat_i;
`else
    wire [2:0]  v30_bs;
    wire [19:0] v30_addr;
    wire [15:0] v30_data_o, v30_data_i;
    wire        v30_ube_n, v30_ce, v30_ready;
    wire        v30_ss_err_unused, v30_ss_quiet_unused;
    wire [15:0] v30_ss_rdata_unused;
    wire        zet_fault = 1'b0;

    v30_cpu_bridge u_v30_bridge (
        .clk               (clk_chipset),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .reset             (reset_cpu),
        .v30_bs            (v30_bs),
        .v30_addr          (v30_addr),
        .v30_ube_n         (v30_ube_n),
        .v30_data_o        (v30_data_o),
        .v30_data_i        (v30_data_i),
        .v30_ready         (v30_ready),
        .v30_ce            (v30_ce),
        .processor_status  (processor_status),
        .ad_out            (cpu_ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (lock_n),
        .analog_mode       (pc98_analog),
        .word_access       (cpu_word_access),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (data_bus_hi),
        .data_bus          (data_bus),
        .processor_ready   (processor_ready),
        .address_enable_n  (chipset_aen),
        .pause_core        (pause_core),
        .biu_done          (biu_done),
        .dbg               (bridge_dbg)
    );

    v30_core u_cpu (
        .CLK        (clk_chipset),
        .CE         (v30_ce),
        .RESET      (reset_cpu),
        .READY      (v30_ready),
        .INT        (interrupt_to_cpu),
        .NMI        (1'b0),
        .POLL_N     (1'b1),
        .DATA_I     (v30_data_i),
        .ADDR_O     (v30_addr),
        .DATA_O     (v30_data_o),
        .STATUS_O   (),
        .QS         (),
        .BS         (v30_bs),
        .RD_N       (),
`ifdef PC98_JTAG
        .dbg_regs      (v30_dbg_regs),
        .dbg_first_pop (v30_first_pop),
        .dbg_core      (v30_dbg_core),
        .dbg_core2     (v30_dbg_core2),
        .dbg_core3     (v30_dbg_core3),
        .dbg_core4     (v30_dbg_core4),
        .dbg_core5     (v30_dbg_core5),
        .dbg_core6     (v30_dbg_core6),
`endif
        .UBE_N      (v30_ube_n),
        .BUSLOCK_N  (),
        .SS_ADDR    ('0),
        .SS_WDATA   ('0),
        .SS_WE      (1'b0),
        .SS_RDATA   (v30_ss_rdata_unused),
        .SS_ERR     (v30_ss_err_unused),
        .SS_BUS_QUIET (v30_ss_quiet_unused)
    );
`endif // PC98_ZET

    //
    // AUDIO
    //

    // PC-9801-86. jt12_top's snd_left/snd_right are FM+SSG already summed
    // (jt12_top.v:484-485) and signed 16-bit, so they join the mix
    // sign-extended by one and clamped below.
    wire signed [15:0] opna_snd_l;
    wire signed [15:0] opna_snd_r;
    wire        [16:0] opna_l = {opna_snd_l[15], opna_snd_l};
    wire        [16:0] opna_r = {opna_snd_r[15], opna_snd_r};
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

        tmp_l <= spk_vol + opna_l;

        // clamp the output
        out_l <= (^tmp_l[16:15]) ? {tmp_l[16], {15{tmp_l[15]}}} : tmp_l[15:0];

        cmp_l <= compr(out_l);
    end

    reg [15:0] cmp_r;
    reg [15:0] out_r;
    always @(posedge clk_chipset)
    begin
        reg [16:0] tmp_r;

        tmp_r <= spk_vol + opna_r;

        // clamp the output
        out_r <= (^tmp_r[16:15]) ? {tmp_r[16], {15{tmp_r[15]}}} : tmp_r[15:0];

        cmp_r <= compr(out_r);
    end

    // Audio out: audio_mixer runs the crossfeed mix and drives the codec
    // clocks. The MiSTer IIR/DC-blocker chain was cut for OPNA fit headroom
    // -- raw audio reaches the codec unfiltered.
    wire [15:0] audio_l = pause_core ? 16'd0 : (boost_cfg ? cmp_l : out_l);
    wire [15:0] audio_r = pause_core ? 16'd0 : (boost_cfg ? cmp_r : out_r);

    // Drive noise lives in the OPNA's ADPCM-A voices now: the softcore polls
    // floppy's taps over mgmt reg 0xE and keys its own samples, so it arrives
    // inside core_l/core_r already mixed.
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

    // CHIPSET's raster feeds pocket_video, which composites the OSD and drives the
    // APF scaler. r/g/b + syncs leave CHIPSET on the dot clock; clk_pix is its half-rate
    // sibling, so pocket_video samples one pixel per edge.
    wire        HBlank;
    wire        HSync;
    wire        VBlank;
    wire        VSync;
    wire [5:0]  r, g, b;

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
    //   2  guest_hold_sync2     6  interact_reset
    //   3  reset (the guest reset)
    //   4  ~RESET
    //
    // reset_wire is RESET | load_active | ~bios_ever_loaded | interact_reset |
    // guest_hold_sync2 | soft_guest_hold, and the bands are every one of those
    // still unaccounted for. Whichever is lit is the one holding the machine.
    //
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
        .disk_led           (disk_led_on),
        .vid_blank          (vid_blank),
        .dbl_skip           (dbl_skip_pix),
        .txt_pix            (vid_txt),
        .osd_active         (osd_active),
        .osd_palette_idx    (osd_palette_idx),
        .osd_in_area        (osd_in_area),
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
