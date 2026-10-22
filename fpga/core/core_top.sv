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

    // CPU clock: ce_generator derives the guest CPU's CE strobes;
    // clk_select sets the speed and is reloaded each bus cycle (biu_done).
    logic  biu_done;
    logic  [7:0] clock_cycle_counter_division_ratio;
    logic  [7:0] clock_cycle_counter_decrement_value;
    logic        shift_read_timing;
    logic  [1:0] ram_read_wait_cycle;
    logic  [1:0] ram_write_wait_cycle;
    logic        cycle_accrate;
    logic        vram_wait_en;
    logic  [1:0] clk_select;
`ifdef PC98_JTAG
    // JTAG slot 0x89 can pin the speed for scripted benchmark runs;
    // otherwise the OSD setting owns clk_select_next exactly as before.
    logic        jtag_spd_ovr = 1'b0;
    logic  [1:0] jtag_spd_sel = 2'b00;
    // pf OFF by default: pf ON wedges ITF POST (TIMER INTERRUPT ERROR,
    // ~1/12 boots) on the SD build. The 286 BIU-queue model stays
    // available for A/B via slot 0x89 (bit3 polarity: wdata[3]=1 ->
    // jtag_pf_dis=0 -> ON).
    logic        jtag_pf_dis  = 1'b1;
    logic        jtag_cache_dis = 1'b0; // [11] z86_cache off: every access on the bus
    logic  [7:0] jtag_thr_num = 8'd0;   // [19:12] nonzero: throttle duty override (n/256)
    // Per-mechanism prefetch kills, for bisecting which half of the
    // engine a failure lives in without a rebuild:
    //   [4] pf_nofill  -- pure (idle-gap) fills never run
    //   [5] pf_nofillm -- fill-on-miss never runs (guest reads always pay)
    //   [6] pf_nohit   -- windows fill but hits never serve: if the fault
    //                     persists, the corruption lives in the fill
    //                     bursts' effect on the port, not the served data
    logic        jtag_pf_nofill  = 1'b0;
    logic        jtag_pf_nofillm = 1'b0;
    logic        jtag_pf_nohit   = 1'b0;
    //   [7]/[8] reserved -- were Zet's fetch-window / odd-wrap kill bits
    //   [9]  pf_wkill -- any guest memory write kills BOTH prefetch
    //                    windows, not just the ones it overlaps
    //  [10]  pf_bkill -- any memory write strobe on the chipset bus (any
    //                    master) kills both windows
    logic        jtag_pf_wkill   = 1'b0;
    logic        jtag_pf_bkill   = 1'b0;
    // (The write-watchpoint address is retired with the ring.)
    wire   [1:0] clk_select_next = jtag_spd_ovr ? jtag_spd_sel
                                              : cpu_speed_cfg;
`else
    // The CPU speed is the OSD's alone.
    wire   [1:0] clk_select_next = cpu_speed_cfg;
    // The bridge prefetch engine is OFF. With it on, SuperDepth's title
    // loop intermittently (~5%) popped stale pre-push stack bytes on a RET
    // (the CPU got "acox &" from the credits string instead of 315E/021E at
    // 384A0 while memory held the right words), ran on with DS=2620 and
    // wrote into its own code (ABE0 at 2818C) or quit with "not enough
    // memory" at START. Hardware A/B, fails/trials: engine on 3/50,
    // no pure fills 2/57, no hits 1/85, kill-on-any-write 1/85, engine
    // off 0/85 -- the hole is in the fill bursts, not the overlap
    // invalidation, and was never reproduced in tb_mem_perf.
    wire         jtag_pf_dis  = 1'b1;  // pf off: pf ON wedges ITF POST at boot
    wire         jtag_cache_dis = 1'b0;
    wire   [7:0] jtag_thr_num = 8'd0;
    wire         jtag_pf_nofill  = 1'b0;
    wire         jtag_pf_nofillm = 1'b0;
    wire         jtag_pf_nohit   = 1'b0;
    wire         jtag_pf_wkill   = 1'b0;
    wire         jtag_pf_bkill   = 1'b0;
`endif

    always @(posedge clk_chipset, posedge reset)
    begin
        if (reset)
            clk_select <= 2'b00;
        else if (biu_done)
            clk_select <= clk_select_next;
    end

    // Speed throttle -- retired to zero in the bus-faithful design. The
    // paced modes now price the bus at real 286 rates two layers down:
    // ce_generator runs the CE train at 1x the named clock, and the
    // bridge runs its pairs on the 286 Ts/Tc profile, so a duty gate on
    // top would only stack a second slowdown on an already-correct one.
    // (The old design blended three time bases: 2x CE, the V30-shaped
    // 4T byte engine, and this Bresenham duty fitted to CPUBENCH
    // averages -- per-instruction timing diverged up to 2x even when
    // the Dhrystone number matched.) The mechanism stays alive for the
    // JTAG slot-9 [19:12] trim override only.
    localparam [7:0] THR_8MHZ  = 8'd0;
    localparam [7:0] THR_10MHZ = 8'd0;
    localparam [7:0] THR_12MHZ = 8'd0;
    wire  [7:0] thr_num_mode = (clk_select == 2'b00) ? THR_8MHZ
                             : (clk_select == 2'b01) ? THR_10MHZ
                             : (clk_select == 2'b10) ? THR_12MHZ : 8'd0;
    wire  [7:0] thr_num = (jtag_thr_num != 8'd0) ? jtag_thr_num : thr_num_mode;
    logic [7:0] thr_acc  = 8'd0;
    logic       thr_hold = 1'b0;
    wire  [8:0] thr_sum  = {1'b0, thr_acc} + {1'b0, thr_num};
    always @(posedge clk_chipset) begin
        thr_acc  <= thr_sum[7:0];
        thr_hold <= (thr_num != 8'd0) && !thr_sum[8];
    end

    ce_generator u_ce_generator
    (
        .clock                              (clk_chipset),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (clk_select_next),
        // The pin clock output is open: the CPU takes the CEs, not a
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
    // ri_greset is fdd_ramimg's boot-from-RAM-image term (PC98_JTAG): a probe
    // write pulses it after a mount so the BIOS walks into drive A on its own.
    wire ri_greset;
    wire reset_wire = RESET | load_active | ~bios_ever_loaded | interact_reset
                    | guest_hold_sync2 | soft_guest_hold | ri_greset;
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
    // JTAG reflash: APF does not re-stream the slots into a bitstream loaded
    // over JTAG, but SDRAM still holds them. Probe write slot 0x0c bit0
    // declares them present (BIOS loaded, slots ready) so the guest leaves
    // reset without relaunching the core on the Pocket.
    reg         jtag_slots_ok = 1'b0;
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

    // fdd_ramimg (PC98_JTAG): the RAM-disk floppy server. Two fences keep it
    // and the firmware from ever touching the controller at once:
    //
    //   * The request mask -- while `own` is high the softcore sees
    //     fdd_request == 0, so fdd_poll parks. Mount/write requests the
    //     firmware raises anyway (a dataslot rebind mid-session) hit the
    //     second fence: its F2-window strobes are dropped for as long as own
    //     is high. Everything else on the bus -- the SCSI window at F4, OPNA
    //     at F5 -- still belongs to the softcore, on every cycle the RAM
    //     server is not itself strobing.
    //
    //   * The strobe arbitration -- on a cycle the RAM server reads or
    //     writes, the bus carries its operands and the firmware strobes
    //     are fenced entirely, not just the F2-windowed ones: a softcore
    //     strobe landing on a server cycle would execute against the
    //     server's address. Observed on hardware: firmware F4/F5 polls
    //     (scsi_poll, OPNA) coinciding with 0xF20F pushes arrived as
    //     nibble-F reads -- floppy.v decodes that as a FIFO pop, the
    //     fill ends a byte short, the level-triggered re-serve appends
    //     the head bytes, and the guest receives the sector rotated
    //     (sim/tb_ramimg_fdc.sv reproduces it byte-for-byte).
    //
    // Without the JTAG build flag the mux is a pass-through and nothing else
    // changes.
    wire [15:0] cs_mgmt_addr;          // muxed -> CHIPSET
    wire [15:0] cs_mgmt_dout;
    wire        cs_mgmt_rd;
    wire        cs_mgmt_wr;
    // The CHIPSET-facing carve-out port; tied off without the JTAG build.
    wire        ramimg_req, ramimg_we, ramimg_ack, ramimg_rvalid, ramimg_done;
    wire [23:0] ramimg_addr;
    wire  [3:0] ramimg_len;
    wire [15:0] ramimg_wdata, ramimg_rdata;
    // The CPU cache's SDRAM port (u_RAM's sdram_shim port F) and the port-A
    // write-commit snoop it invalidates against. Word addresses, one guest
    // byte per SDRAM word, as on port A; all on clk_chipset.
    wire        cachef_req, cachef_we, cachef_ack, cachef_rvalid, cachef_done;
    wire [23:0] cachef_addr;
    wire  [3:0] cachef_len;
    wire [15:0] cachef_wdata0, cachef_wdata1, cachef_rdata;
    wire        ram_wr_snoop_v;
    wire [23:0] ram_wr_snoop_addr;
    wire  [3:0] ram_wr_snoop_len;
    // Driven by z86's cache (z86_cache, in u_cpu).
    wire  [1:0] fdd_req_fw;
`ifdef PC98_JTAG
    wire [15:0] ri_mgmt_addr, ri_mgmt_dout;
    wire        ri_mgmt_wr, ri_mgmt_rd, ri_own;
    wire [31:0] ri_dbg0, ri_dbg1, ri_dbg2;
    wire        fw_fdd_hit = mgmt_addr[15:8] == 8'hF2;
    mgmt_arb u_mgmt_arb (
        .fw_addr (mgmt_addr),  .fw_dout (mgmt_dout),
        .fw_rd   (mgmt_rd),    .fw_wr   (mgmt_wr),
        .ri_addr (ri_mgmt_addr), .ri_dout (ri_mgmt_dout),
        .ri_rd   (ri_mgmt_rd), .ri_wr   (ri_mgmt_wr), .ri_own (ri_own),
        .cs_addr (cs_mgmt_addr), .cs_dout (cs_mgmt_dout),
        .cs_rd   (cs_mgmt_rd), .cs_wr   (cs_mgmt_wr)
    );
    assign fdd_req_fw   = mgmt_req[7:6] & ~{2{ri_own}};
`else
    assign ri_greset    = 1'b0;
    assign ramimg_req   = 1'b0;
    assign ramimg_we    = 1'b0;
    assign ramimg_addr  = 24'd0;
    assign ramimg_len   = 4'd0;
    assign ramimg_wdata = 16'd0;
    assign cs_mgmt_addr = mgmt_addr;
    assign cs_mgmt_dout = mgmt_dout;
    assign cs_mgmt_wr   = mgmt_wr;
    assign cs_mgmt_rd   = mgmt_rd;
    assign fdd_req_fw   = mgmt_req[7:6];
`endif

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
    wire       osd_cpu_cache;
    wire [31:0] osd_set_word;
    wire  [2:0] osd_set_sel;   // probe slot 0xA0+g selects group g (see the read mux)
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

    wire [31:0] dbg_pico_w;    // pico-domain liveness for probe slot 0x2A

    softcpu_subsystem u_softcpu (
        .fw_wr_clk                  (clk_chipset),
        .fw_wr_en                   (fw_wr_en_r),
        .fw_wr_addr                 (fw_wr_addr_r),
        .fw_wr_data                 (fw_wr_data_r),
        .clk_sys                    (clk_chipset),
        .clk_74a                    (clk_74a),
        .reset                      (reset_soft),
        .clk_pico                   (clk_pico),

        .fdd_request                (fdd_req_fw),
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
        .dataslots_ready            (dataslots_ready | jtag_slots_ok),
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
        .osd_cpu_cache              (osd_cpu_cache),
        .osd_set_sel                (osd_set_sel),
        .osd_set_word               (osd_set_word),
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
        .accel_status               (accel_status_w),
        .dbg_pico                   (dbg_pico_w)
    );

`ifdef PC98_JTAG
    //
    // JTAG probe -- the panel's readout without a camera.
    //
    // A USB Blaster on the FPGA's JTAG port reads these over the SLD hub:
    // scripts/jtag_probe.cfg + jtag_probe_read.tcl drive USER1/USER0.
    // The magic word proves the protocol end-to-end before any value is trusted.
    logic [31:0] probe_data, probe_data_c;
    // Dot capture (write slot 0x8C, reads 0x42-0x44): 32 presented dots of
    // one raster line, sampled where pocket_video takes them. Declared here
    // because the read mux below precedes the video wires.
    wire   [7:0] probe_addr;
    assign osd_set_sel = probe_addr[2:0];
    // The nuV30's architectural state, live -- was. These taps were the old
    // core's dbg pins; no CPU since has an equivalent, so every one is tied
    // to 0 now and the slots below keep their addresses only for map
    // compatibility.
    // z86's registers in the old V30 layout {psw, ip, DS, SS, CS, ES, DI..AX}:
    // live until the probe trigger (slot 0x06) hits, then frozen at that
    // moment until the trigger is rewritten.
    wire [223:0] z86_dbg_regs;
    // JTAG debug stop: write slot 0x0f = {arm, 15'b0, AX}. The next trigger
    // hit (slot 6) with that AX stops z86 at an instruction boundary; read
    // 0x65 = {stopped, 15'b0, next IP} (CS in 0x12). Writing 0x0f again
    // releases it. For replaying a DOS call off a RAM dump.
    reg          jtag_dbg_arm  = 1'b0;
    reg  [15:0]  jtag_dbg_ax   = 16'h0;
    reg          jtag_dbg_stop = 1'b0;
    wire         z86_dbg_stopped;
    wire         z86_halted;
    wire [15:0]  z86_dbg_next_ip;
    reg  [223:0] v30_dbg_regs = '0;
    reg          z86_snap_held = 1'b0;
    wire  [15:0] v30_dbg_core  = '0;       // EU/BIU interlock: halt/queue/eu_bs
    wire  [31:0] v30_dbg_core2 = '0;       // posted access: eu_addr/seg + slots
    wire  [31:0] v30_dbg_core3 = '0;       // BIU launch-law registers
    wire  [31:0] v30_dbg_core4 = '0;       // EU stall ledger: ucode row + wait wires
    wire  [31:0] v30_dbg_core5 = '0;       // queue bytes r_q_mem[0..3]
    wire  [31:0] v30_dbg_core6 = '0;       // queue bytes r_q_mem[4..5] + fetch_ptr
    wire         v30_first_pop = 1'b0;     // EU consumed an instruction's byte 0
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
    wire       io_port_read  = ~chipset_io_read_n  & ~chipset_aen;
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
    wire [7:0] dbg_sysport_w;
    // 0x35/0x37 forensics: the byte the guest actually reads back from the
    // 8255 port-C latch decides cold vs resume at the ITF entry (F805B).
    // last_35_rdata is what the CPU got; entry_branch records which path
    // the entry took afterwards -- F8061 = resume (bit7 read 0), F806A =
    // cold (bit7 read 1), F9497 = the resume landing, F9A30/F9A2A = the
    // shutdown OUT-0xF0 sites. Sticky: the first observation per boot
    // wins, and the loop supplies plenty.
    reg [7:0] last_35_rdata = 8'h00;
    reg [7:0] last_37_wdata = 8'h00;
    reg [3:0] entry_branch  = 4'h0;
    reg       f0_seen       = 1'b0;
    // JTAG TVRAM dump: write slot 0x0B arms the shared dbg_tvram_cell,
    // read slot 0xF7 returns {cell[7:0] echo, attr, char_hi, char_lo}
    // (remapped from bench-next186's 0x8B/0x74 -- 0x74 lives inside the
    // rst_snap ring's 0x61-0x80 window on this branch). The read rides
    // tvram's guest pipeline whenever no guest read owns it -- never
    // steals a cycle.
    wire [31:0] tvram_dbg_q;
    always_ff @(posedge clk_chipset) begin
        rd35_q  <= io_port_read && (chipset_address[15:0] == 16'h0035);
        rd35_qq <= rd35_q;
        if (rd35_q && ~rd35_qq) begin
            in35_data  <= data_bus;
            in35_count <= in35_count + 8'd1;
        end
        if (io_port_read && (chipset_address[15:0] == 16'h0035))
            last_35_rdata <= data_bus;
        if (io_port_write && (chipset_address[15:0] == 16'h0037))
            last_37_wdata <= cpu_data_bus;
        if (f0_port_write) f0_seen <= 1'b1;
        if (itf_bank && pc_now == 20'hF8061) entry_branch[0] <= 1'b1;
        if (itf_bank && pc_now == 20'hF806A) entry_branch[1] <= 1'b1;
        if (itf_bank && pc_now == 20'hF9497) entry_branch[2] <= 1'b1;
        if (itf_bank && (pc_now == 20'hF9A30 || pc_now == 20'hF9A2A))
            entry_branch[3] <= 1'b1;
    end

    // BIOS-side milestones: once resume+handover land, the question moves
    // to where the BIOS hands control back. b0=FD802 hand-over landing,
    // b1=FD834 init entry, b2=FD880 IVT copy, b3=fetch in the 0x4F0-0x4FF
    // trampoline window (either side re-running the bank-switch stub),
    // b4=0:0064-0x0067 (int19 vector fetch = boot attempted),
    // b5=FD8E7 (int18 ROM-BASIC call), b6=BIOS-bank reset entry FD800,
    // b7=ITF errhalt F99E5 reached.
    reg [7:0] bios_branch = 8'h00;
    reg [7:0] in42_count   = 8'h00;
    reg [7:0] last_42_rdata = 8'h00;
    reg [7:0] w43d_10_count = 8'h00;
    reg [7:0] w43d_12_count = 8'h00;
    always_ff @(posedge clk_chipset) begin
        if (io_port_read && (chipset_address[15:0] == 16'h0042)) begin
            last_42_rdata <= data_bus;
            in42_count    <= in42_count + 8'd1;
        end
        if (io_port_write && (chipset_address[15:0] == 16'h043D)) begin
            if (cpu_data_bus == 8'h10) w43d_10_count <= w43d_10_count + 1'b1;
            if (cpu_data_bus == 8'h12) w43d_12_count <= w43d_12_count + 1'b1;
        end
        if (!itf_bank && pc_now == 20'hFD802) bios_branch[0] <= 1'b1;
        if (!itf_bank && pc_now == 20'hFD834) bios_branch[1] <= 1'b1;
        if (!itf_bank && pc_now == 20'hFD880) bios_branch[2] <= 1'b1;
        if ((pc_now >= 20'h004F0) && (pc_now <= 20'h00500))
            bios_branch[3] <= 1'b1;
        if ((pc_now >= 20'h00060) && (pc_now <= 20'h00068))
            bios_branch[4] <= 1'b1;
        if (!itf_bank && pc_now == 20'hFD8E7) bios_branch[5] <= 1'b1;
        if (!itf_bank && pc_now == 20'hFD800) bios_branch[6] <= 1'b1;
        if (itf_bank && pc_now == 20'hF99E5) bios_branch[7] <= 1'b1;
    end

    // Slots 0x40-0x5F: a 32-deep ring of the guest's fetch cursor (zet_pc),
    // frozen
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
    wire [19:0] pc_now = zet_pc;
    wire       pc_in_errhalt = (pc_now == 20'hF99E5);
    // Probe write 0x85 re-arms the history: the boot-time F0 write fires
    // the freeze long before any guest crash, so without this the snapshot
    // can never see a guest fault's trail. Registered, like the readout
    // stage below -- a raw decode into the ring's reset feeds the same
    // combinational cone that trips Quartus 18.1's fitter (VPR20KMAIN).
    wire       pc_rearm_c = probe_wr_pulse && (probe_waddr_c == 7'h05);
    reg        pc_rearm = 1'b0;
    always_ff @(posedge clk_chipset) pc_rearm <= pc_rearm_c;
    // Stray-store freeze, keyed on the arbiter's write-watch log (probe
    // slot 0x0a, read back at 0xE1-0xE4): when its newest entry turns into
    // a CPU store landing on top of a DMA write, the ring freezes -- its 32
    // fetches name the code that overwrote freshly loaded bytes. The log
    // sees the arbiter's own bus, which a DMA cycle drives and
    // chipset_address does not. SuperDepth's turbo START failure lands a
    // CPU store of garbage on the same spot of its own code every time.
    // RETIRED with the watch ring itself (Bus_Arbiter's dbg_dma3 is 0 now,
    // slots 0xE1-0xE4 read dead) -- its registers bought back the LABs the
    // run#976 triage taps (0xA8/0xA9) and the poll/DRQ triggers need.
    // Bus ring: the last 256 Wishbone transfers the CPU completed --
    // fetches included -- with the live DS beside each: {ds, exec, we,
    // sel, adr, data}. Block RAM, frozen with pc_hist; probe write slot
    // 0x0D picks the entry, reads 0x01 (low word) / 0x02 (high word) /
    // 0x03 (write pointer) return it.
    (* ramstyle = "M10K" *) reg [54:0] brg [0:255];
    reg  [7:0] brg_w = 8'd0;
    reg  [7:0] brg_ri = 8'd0;
    reg [54:0] brg_q = 55'd0;
    reg        brg_ack_q = 1'b0;
    always_ff @(posedge clk_chipset) begin
        brg_ack_q <= zwb_ack;
        if (zwb_ack && !brg_ack_q && zwb_cyc && !pc_hist_frozen) begin
            brg[brg_w] <= {zet_ds, zet_exec, zwb_we, zwb_sel, zwb_adr,
                           zwb_we ? zwb_dat_o : zwb_dat_i};
            brg_w      <= brg_w + 8'd1;
        end
        brg_q <= brg[brg_ri];
    end
    always_ff @(posedge clk_chipset) begin
        if (reset || soft_reset_cpu || pc_rearm) begin
            pc_hist_frozen <= 1'b0;
            pc_hist_w      <= 5'd0;
            delay_cnt      <= 5'd0;
        end else if (!pc_hist_frozen) begin
            if (hist_src != pc_hist_prev) begin
                pc_hist_prev       <= hist_src;
                pc_hist[pc_hist_w] <= hist_src;
                pc_hist_w          <= pc_hist_w + 5'd1;
                if (delay_cnt != 5'd0) begin
                    delay_cnt <= delay_cnt - 5'd1;
                    if (delay_cnt == 5'd1)
                        pc_hist_frozen <= 1'b1;
                end
            end
            if (f0_port_write || pc_in_errhalt || zet_fault || w43d_10 ||
                (tlog_trap && pc_wild) ||
                tap_latch ||
                (trig_hit && trig_freeze && !trig_delay))
                pc_hist_frozen <= 1'b1;
            if (trig_hit && trig_freeze && trig_delay)
                delay_cnt <= 5'd24;
        end
    end

    // Address-triggered capture, probe-writable via write slot 0x06
    // ({en,addr[19:0]}, handled with the other probe writes below).
    // Defaults to the reset vector: every reset path -- hard, soft,
    // watchdog -- ends with a FFFF0 fetch, so a reset the cause bits
    // cannot name still leaves its trail.
    reg [19:0] trig_addr = 20'hFFFF0;
    reg        trig_en   = 1'b1;
    reg        trig_freeze = 1'b0;
    // bit29 of write slot 0x06: delay the trig freeze ~24 fetches so the
    // ring keeps the code AFTER the hit (e.g. the landing of the resume
    // retf at f8069 when armed on f8061).
    reg        trig_delay  = 1'b0;
    reg  [4:0] delay_cnt   = 5'd0;
    // bit28 of write slot 0x06: record raw bus addresses (fetches AND
    // data accesses) instead of just the fetch stream, so a restore's
    // [0x404]/[0x406] reads and the retf's stack pops are visible.
    reg        trig_bus    = 1'b0;
    // bit27 of write slot 0x06: f0_snap records only WRITE commands
    // (memory or I/O). Display DMA is read-only, so the ring stops
    // drowning in framebuffer sweeps and keeps the 32 cycles of guest
    // writes leading into the F0 -- the whole save sequence's addresses.
    reg        trig_wronly = 1'b0;
    // bit26 of write slot 0x06: the trigger compares the live DS register
    // against trig_addr[15:0] instead of the fetch PC -- freezing the ring
    // on the moment a stray segment value lands in DS.
    reg        trig_ds     = 1'b0;
    // bits 27+28 together arm a WRITE watchpoint: the trigger matches the
    // address of a guest-RAM write cycle instead of the fetch PC, so a
    // stray write -- the 0xA1 that lands on the high-score date byte at
    // 0x373A3 during SuperDepth's boot -- freezes the rings on the culprit
    // cycle itself.  Two taps together cover every master that can write
    // guest RAM:
    //
    //  * the chipset bus (chipset_memory_write_n + chipset_address): the
    //    i8288's AMWC for CPU stores, the uPD71071's strobe for DMA fills,
    //    and the ext path for the ROM loader.  The strobe is a LEVEL held
    //    through the command phase and the arbiter's address (ALE-latched
    //    cpu_address / DMA page+address / address_ext) is stable across
    //    its whole length, so a same-cycle compare is exact.  (The
    //    watchpoint "never fired" on hardware twice, both times unarmed:
    //    the script first wrote slot 0x04 -- the GVRAM dump launcher --
    //    then sent the BARE slot number, which pc98_jtag_probe.sv treats
    //    as a READ: a write scan needs addr bit 7 set (0x86 for this
    //    slot, 0x8e for the tlog mode).  Read slot 0x06 below now echoes
    //    the armed word, so a silent no-arm cannot hide again.)
    //  * z86_cache's port-F buffer take (z86_pf_wr_*): in Turbo+cache a
    //    store to 00000-9FFFF/E8000-FFFFF runs no bus cycle at all --
    //    write-through goes straight to the SDRAM's port F -- so only the
    //    cache's own commit witness can see it.
    //
    // Word coverage: a CPU word write addresses the EVEN base and moves
    // both lanes in one cycle, so an armed ODD byte must match base+1.
    // cpu_word_access is the bridge's flag for the CPU's own cycle and
    // goes stale through a DMA grant, hence the ~AEN qualification (the
    // same term the GVRAM sequencer uses).  DMA and loader writes are
    // byte cycles on the bus; the cache tap carries its own word flag.
    wire        bus_mem_wr  = ~chipset_memory_write_n;
    wire        bus_wr_word = bus_mem_wr && cpu_word_access && ~chipset_aen;
    wire        z86_pf_wr_v, z86_pf_wr_two;
    wire [19:0] z86_pf_wr_a0;
    // z86_cache's watched-line snoop-kill count (slot 0x70): trig_addr is
    // the watched guest address, shared with the bus-side write watchpoint
    // above, so one arm serves both taps. Registered at the boundary --
    // the probe mux's dbg cone is a known Quartus-internal-error hotspot
    // (see probe_data's pipeline comment) and v30_dbg_regs is latched the
    // same way.
    wire [15:0] z86_sn_kills_w;
    reg  [15:0] z86_sn_kills = 16'd0;
    always_ff @(posedge clk_chipset)
        z86_sn_kills <= z86_sn_kills_w;
    wire        trig_w_bus = bus_mem_wr &&
                             ((chipset_address[19:0] == trig_addr) ||
                              (bus_wr_word &&
                               (chipset_address[19:0] + 20'd1) == trig_addr));
    wire        trig_w_pf  = z86_pf_wr_v &&
                             ((z86_pf_wr_a0 == trig_addr) ||
                              (z86_pf_wr_two &&
                               (z86_pf_wr_a0 + 20'd1) == trig_addr));
    wire       trig_w_hit  = trig_bus && trig_wronly && (trig_w_bus || trig_w_pf);
    wire       trig_hit  = trig_en && (trig_bus && trig_wronly ? trig_w_hit
                                           : trig_ds ? (zet_ds == trig_addr[15:0])
                                           : (pc_now == trig_addr));
    wire [19:0] hist_src = trig_bus ? chipset_address : pc_now;
    // Trigger log: a 64-entry ring of {PC, SS, SP, CS, DS, ES, DI, SI, DX,
    // CX, BX, AX}. Default mode logs each time the fetch PC lands on the
    // slot-6 trigger address (armed on the INT 21h entry: every DOS call).
    // Write slot 0x0e = {.., trap, all, 2'b0, index[5:0]}: 'all' logs every
    // change of the fetch PC instead (the last 64 branches with registers);
    // 'trap' freezes the log and pc_hist and stops z86 the moment the PC
    // enters a region no code lives in (IVT 000-3FF, A0000-CFFFF,
    // E0000-E7FFF -- D0000-DFFFF holds the SCSI option ROM), so a
    // crash leaves the path into it. Reads 0x60-0x65 return the entry (low
    // word first), 0x67 the count.
    (* ramstyle = "M10K" *) reg [207:0] tlog [0:63];
    reg  [5:0]   tlog_ri = 6'd0;
    reg  [15:0]  tlog_n  = 16'd0;
    reg  [207:0] tlog_q  = '0;
    reg          trig_hit_d = 1'b0;
    reg  [19:0]  tlog_pc_d = 20'd0;
    reg          tlog_all = 1'b0, tlog_trap = 1'b0, tlog_frozen = 1'b0;
    // Also a trap: HLT with IF clear (nothing can wake it -- a crash that
    // ran into an F4 in data) and OUT 0F0h (the CPU reset a crash ends in).
    wire         pc_wild = (pc_now < 20'h00400) ||
                           (pc_now >= 20'hA0000 && pc_now < 20'hD0000) ||   // VRAM, nothing
                           (pc_now >= 20'hE0000 && pc_now < 20'hE8000) ||   // (D0000: SCSI ROM)
                           (z86_halted && !z86_dbg_regs[217]) ||           // HLT, IF=0
                           f0_port_write;
    wire         tlog_ev = tlog_all ? (pc_now != tlog_pc_d) : (trig_hit && !trig_hit_d);
    always_ff @(posedge clk_chipset) begin
        trig_hit_d <= trig_hit;
        tlog_pc_d  <= pc_now;
        if (probe_wr_pulse && probe_waddr_c == 7'h06) begin
            tlog_n <= 16'd0;
            tlog_frozen <= 1'b0;
        end else if (tlog_ev && !tlog_frozen) begin
            tlog[tlog_n[5:0]] <= {12'h0, pc_now,               // 207:176
                                  z86_dbg_regs[175:160], z86_dbg_regs[79:64],     // SS, SP
                                  z86_dbg_regs[159:144],                          // CS
                                  z86_dbg_regs[191:176], z86_dbg_regs[143:128],   // DS, ES
                                  z86_dbg_regs[127:112], z86_dbg_regs[111:96],    // DI, SI
                                  z86_dbg_regs[47:32],   z86_dbg_regs[31:16],     // DX, CX
                                  z86_dbg_regs[63:48],   z86_dbg_regs[15:0]};     // BX, AX
            tlog_n <= tlog_n + 16'd1;
        end
        if (((tlog_trap && pc_wild) ||
             (trig_hit && trig_freeze && !trig_delay) ||
             tap_latch) && !tlog_frozen)
            tlog_frozen <= 1'b1;
        if (probe_wr_pulse && probe_waddr_c == 7'h0e) begin
            tlog_ri   <= probe_wdata_c[5:0];
            tlog_all  <= probe_wdata_c[8];
            tlog_trap <= probe_wdata_c[9];
        end
        tlog_q <= tlog[tlog_ri];
        if (probe_wr_pulse && probe_waddr_c == 7'h0f) begin
            jtag_dbg_arm  <= probe_wdata_c[31];
            jtag_dbg_ax   <= probe_wdata_c[15:0];
            jtag_dbg_stop <= 1'b0;
        end else if ((jtag_dbg_arm && trig_hit && !trig_hit_d &&
                      z86_dbg_regs[15:0] == jtag_dbg_ax) ||
                     (tlog_trap && pc_wild && !tlog_frozen)) begin
            jtag_dbg_stop <= 1'b1;
            jtag_dbg_arm  <= 1'b0;
        end
        tlog_q <= tlog[tlog_ri];
    end
    always_ff @(posedge clk_chipset) begin
        if (probe_wr_pulse && probe_waddr_c == 7'h06)
            z86_snap_held <= 1'b0;
        else if (trig_hit && !z86_snap_held)
            z86_snap_held <= 1'b1;
        if (!z86_snap_held || jtag_dbg_stop)
            v30_dbg_regs <= z86_dbg_regs;
    end

    // The BIOS->ITF hand-back always ends in an OUT 0x43D,0x10 -- the
    // cold path's bank restore -- so freezing the ring on that write
    // keeps the ~32 fetches that led into the bounce, whichever code
    // path took it there.
    wire       w43d_10   = io_port_write &&
                           (chipset_address[15:0] == 16'h043D) &&
                           (cpu_data_bus == 8'h10);
    wire       pc_hist_new = (hist_src != pc_hist_prev);
    // The first zet fault's decode-side evidence: which PC's instruction
    // decoded to INVOP/INTD. Pairs with dbg_opc (the byte it saw, latched
    // inside the core); expected-vs-seen at that PC is the corruption
    // signature. Re-arms with each CPU reset like the opc latch does.
    reg [19:0] fault_pc   = 20'h00000;
    reg        fault_seen = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (reset || soft_reset_cpu)
            fault_seen <= 1'b0;
        else if (zet_fault && !fault_seen) begin
            fault_seen <= 1'b1;
            fault_pc   <= zet_pc;
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

    // Port-A write-commit snoop witnesses (slots 0x6c-0x70). The feed is
    // sdram_shim's a_wr_* -- the same wire z86_cache and the bridge's pf
    // windows invalidate against -- tapped here at the source, in the
    // clk_chipset domain the pulse lives in:
    //   sn_v_cnt      every port-A write commit (any master: guest, DMA,
    //                 loader; any address the port can name)
    //   sn_dma_cnt    commits while chipset_aen (AEN) is high -- the CPU
    //                 has the bus parked, so during an FDC fill these are
    //                 the 71071's bytes draining. A posted write can
    //                 commit a few clocks past the window's end; those land
    //                 only in sn_v_cnt (the tail sn_dma_cnt misses).
    //   sn_last_*     the newest commit's word address and words-1
    //   sn_dma_last_* the newest AEN-window commit's pair
    //
    // Both counters are 16-bit FREE-RUNNING (no saturation compare -- the
    // ITF's memory test alone passes 64K port-A writes, so a saturating
    // count would pin before the game ever boots): read them as deltas,
    // mod 65536. The enable terms are kept flat on purpose; the earlier
    // nested-if 32-bit saturating shape is what CI's Quartus died on
    // (S2T internal error, runs 39543865833/39546532071).
    reg  [15:0] sn_v_cnt          = 16'd0;
    reg  [15:0] sn_dma_cnt        = 16'd0;
    reg  [23:0] sn_last_addr      = 24'd0;
    reg  [ 3:0] sn_last_len       = 4'd0;
    reg  [23:0] sn_dma_last_addr  = 24'd0;
    reg  [ 3:0] sn_dma_last_len   = 4'd0;
    wire sn_ev  = ram_wr_snoop_v;
    wire sn_dev = ram_wr_snoop_v & chipset_aen;
    always_ff @(posedge clk_chipset) begin
        if (sn_ev)     sn_v_cnt   <= sn_v_cnt + 16'd1;
        if (sn_dev)    sn_dma_cnt <= sn_dma_cnt + 16'd1;
        if (sn_ev) begin
            sn_last_addr      <= ram_wr_snoop_addr;
            sn_last_len       <= ram_wr_snoop_len;
        end
        if (sn_dev) begin
            sn_dma_last_addr  <= ram_wr_snoop_addr;
            sn_dma_last_len   <= ram_wr_snoop_len;
        end
    end

    // ------------------------------------------------------------------
    // THE WEDGE TAP (PC98_JTAG): a frozen post-mortem of the memory path.
    //
    // The wedge this hunts: the machine stops retiring instructions (slot
    // 0x17 static, fetch cursor slot 0x18 static) and greset does not cure
    // it -- the stuck state lives in the sdram_reset domain (RAM.sv,
    // pc98_gvram_seq, sdram_shim/sdram_mp), which a guest reset never
    // touches. Worse, the machine often walks into a reset loop afterwards
    // that wipes the greset-able witnesses (Bus_Arbiter, DMA, READY, the
    // bridge) and dirties memory. So: the moment retirement has been
    // static for ~390 ms (2^24 clk_chipset) -- with the CPU running, not
    // paused, not held in reset, not probe-stopped -- every tap below is
    // FROZEN. The reset loop can then do its worst; slots 0xA0-0xA7 read
    // the machine as it died.
    //
    // The taps, registered here at the core_top boundary (the probe mux's
    // dbg cone is a known Quartus S2T internal-error hotspot -- one
    // register stage hides it, same as v30_dbg_regs / z86_sn_kills):
    //   snap_arb    Bus_Arbiter {dce_pin, hrq_ff1, hrq_ff2, 5'0} +
    //               upd71071 {state, channel, HRQ, TC, EOP}   (slot A0 hi)
    //   snap_rdy    READY {wait, CE-sampled wait, Qn, bus-state edges} (A0)
    //   snap_arbhold the arbiter's live hold byte (slot 0x19's, frozen) (A0 lo)
    //   snap_ram    RAM.sv {park FIFO, rd_conflicts, FSM, wait counts,
    //               nonidle age}                                    (slot A1)
    //   snap_sdram  shim/mp {port-A req/busy ages, per-port reqs,
    //               controller state/grant}                  (slots A2/A3)
    //   snap_bridge cpu_bus_bridge {pair kind flags, witnesses, posted
    //               depth, B_CMD age}                                 (A4)
    //   snap_seq    pc98_gvram_seq {expand, leg strobes, walk flags,
    //               nonidle age} + READY-facing chipset_dbg2          (A5)
    //   snap_chip2  {processor_ready, memory_access_ready, dma_ready,
    //               DACKn, no-command} -- frozen                      (A5)
    //   snap_retired/snap_pc  the liveness pair the runbook polls      (A6/A7)
    // Write slot 0x08: [0] clear the latch and re-arm, [1] pulse
    // CHIPSET's ram_unstick (drop RAM.sv's parked queue, force IDLE) --
    // an A/B for "is the stuck state RAM.sv's bookkeeping".
    // ------------------------------------------------------------------
    reg         wedge_latch = 1'b0;
    reg  [23:0] wedge_static = 24'd0;
    reg  [23:0] wedge_ret_prev = 24'd0;
    reg  [19:0] wedge_pc_prev  = 20'd0;
    reg  [15:0] snap_arb      = 16'd0;
    reg  [7:0]  snap_rdy      = 8'd0;
    reg  [7:0]  snap_arbhold  = 8'd0;
    reg  [23:0] snap_ram      = 24'd0;
    reg  [39:0] snap_sdram    = 40'd0;
    reg  [23:0] snap_bridge   = 24'd0;
    reg  [15:0] snap_seq      = 16'd0;
    reg  [7:0]  snap_chip2    = 8'd0;
    reg  [23:0] snap_retired  = 24'd0;
    reg  [19:0] snap_pc       = 20'd0;
    reg  [31:0] snap_dma      = 32'd0;
    reg  [31:0] snap_fdc2     = 32'd0;
    reg  [31:0] snap_z86      = 32'd0;
    reg         ram_unstick_r = 1'b0;
    // Retirement stops legitimately while the core is paused, probe-stopped
    // or in reset -- those windows must not arm the latch.
    wire wedge_run = ~reset_cpu & ~pause_core & ~z86_dbg_stopped
                   & ~jtag_dbg_stop;
    // Liveness is the fetch cursor, not retired_cnt: z86 has no retire
    // tap (v30_first_pop is tied 0, so slot 0x17 reads 0 forever), and
    // the freeze signature -- pc parked in a poll loop -- stops zet_pc
    // while a healthy machine keeps it moving. The OR keeps any future
    // retire feed useful without changing the criterion.
    wire wedge_moving = (retired_cnt != wedge_ret_prev)
                      | (pc_now != wedge_pc_prev);
    //
    // Poll-trap trigger (write slot 0x87, {en[31], pc[19:0]}): the CPU
    // walking a tight poll loop never stops retiring, so the wedge
    // detector above never arms -- the run#976 shape sat at 0x317A8 for
    // seconds with the latch at 0. This trigger latches when the fetch
    // cursor stays inside the armed 32-byte window (pc[19:5] match -- a
    // poll loop is a handful of instructions that never leaves its
    // window) for the same ~390 ms the wedge detector uses. On latch the
    // wedge snapshot freezes with pc_hist and tlog, catching the
    // transition INTO the stuck poll.
    reg         poll_en   = 1'b0;
    reg  [19:0] poll_pc   = 20'd0;
    reg  [23:0] poll_static = 24'd0;
    reg         poll_latch = 1'b0;
    wire        poll_in_win = poll_en & (pc_now[19:5] == poll_pc[19:5]);
    //
    // FDC DRQ-stall trigger: the FDC's dma_req is a LEVEL that only the
    // 71071's DACK (or TC) folds -- a healthy byte train re-dips it every
    // few hundred clocks. dma_req held up for ~390 ms means the 71071
    // never came: exactly the run#976 freeze shape (state=SI, drq=0011),
    // latched the moment it stalls instead of whenever the CPU happens
    // to stop polling. Bit 7 of the live cs_fdc2 view is the wire
    // (floppy.v's dma_req == Peripherals' fdd_dma_req_wire; the dbg2
    // field sits one up because [0] is the TC latch).
    reg  [23:0] fdq_static  = 24'd0;
    reg         fdq_latch   = 1'b0;
    wire        fdq_up      = cs_fdc2[7];
    //
    // Wild-fetch trigger (write slot 0x87 bit30, armed with the poll
    // window): the run#977 shape -- the cursor bouncing 0:0000-0:000F
    // inside the IVT while the machine's devices sat freshly initialized
    // -- moves the cursor the whole time, so neither the wedge detector
    // (stillness) nor the poll window (a chosen 32-byte hole) can catch
    // it, and by the time something parks the wild code's own port
    // writes have re-initialized the 71071/FDC and destroyed the
    // evidence. pc_wild (the tlog trap's zone list, f0 term stripped --
    // port 0xF0 is a legitimate write) says no legal execution ever
    // lives there: below the IVT+low-RAM fence, in VRAM, in the SCSI ROM
    // hole, or HLT with IF clear. Latching wild freezes the whole wedge
    // tap + pc_hist + tlog at the FIRST wild instant, before the guest
    // state is overwritten -- unlike the tlog_trap (slot 0x0e bit9) this
    // does NOT stop the CPU, so the run can also watch what the wild
    // code does next (an F0 write, a 71071/FDC reset port). Debounced
    // 2^10 clk: a real wild execution stays put for thousands of cycles,
    // a decode transient does not.
    reg         wild_en     = 1'b0;
    reg  [9:0]  wild_static = 10'd0;
    reg         wild_latch  = 1'b0;
    wire        wild_zone   = wild_en & wedge_run
                           & (pc_wild & ~f0_port_write);
    // The transition-catch latches: any one freezes the wedge tap
    // (through wedge_latch below) plus pc_hist and tlog.
    wire        tap_latch   = poll_latch | fdq_latch | wild_latch;
    always_ff @(posedge clk_chipset) begin
        if (probe_wr_pulse && probe_waddr_c == 7'h08
            && probe_wdata_c[0]) begin
            wedge_latch   <= 1'b0;
            wedge_static  <= 24'd0;
            poll_static   <= 24'd0;
            poll_latch    <= 1'b0;
            fdq_static    <= 24'd0;
            fdq_latch     <= 1'b0;
            wild_static   <= 10'd0;
            wild_latch    <= 1'b0;
        end else begin
            if (!wedge_latch && wedge_run) begin
                wedge_ret_prev <= retired_cnt;
                wedge_pc_prev  <= pc_now;
                if (!wedge_moving) begin
                    wedge_static <= wedge_static + 24'd1;
                    if (wedge_static == 24'hFF_FFFF)
                        wedge_latch <= 1'b1;
                end else
                    wedge_static <= 24'd0;
            end
            if (!poll_latch && wedge_run) begin
                if (poll_in_win) begin
                    poll_static <= poll_static + 24'd1;
                    if (poll_static == 24'hFF_FFFF)
                        poll_latch <= 1'b1;
                end else
                    poll_static <= 24'd0;
            end
            if (!fdq_latch && wedge_run) begin
                if (fdq_up) begin
                    fdq_static <= fdq_static + 24'd1;
                    if (fdq_static == 24'hFF_FFFF)
                        fdq_latch <= 1'b1;
                end else
                    fdq_static <= 24'd0;
            end
            if (!wild_latch && wedge_run) begin
                if (wild_zone) begin
                    wild_static <= wild_static + 10'd1;
                    if (&wild_static)
                        wild_latch <= 1'b1;
                end else
                    wild_static <= 10'd0;
            end
            // Any catch latches the wedge snapshot too.
            if (tap_latch && !wedge_latch)
                wedge_latch <= 1'b1;
        end
        if (!wedge_latch) begin
            snap_arb     <= cs_w_arb;
            snap_rdy     <= cs_w_rdy;
            snap_arbhold <= chipset_dbg[7:0];
            snap_ram     <= cs_w_ram;
            snap_sdram   <= cs_w_sdram;
            snap_bridge  <= bridge_dbg_w;
            snap_seq     <= cs_w_seq;
            snap_chip2   <= chipset_dbg2;
            snap_retired <= retired_cnt;
            snap_pc      <= zet_pc;
            snap_dma     <= cs_w_dma;
            snap_fdc2    <= cs_fdc2;
            // The CPU's own answer at the freeze instant: HLT vs a dead
            // pipeline, IF's state (an unwakeable HLT), the full IP. The
            // live slots (0x10-0x16) keep churning; this copy is frozen
            // with everything else. [31] z86_halted, [27:16] FLAGS[11:0]
            // (bit25 = IF, bit24 = TF), [15:0] IP.
            snap_z86     <= {z86_halted, 3'b000,
                             z86_dbg_regs[219:208], z86_dbg_regs[207:192]};
        end
        ram_unstick_r <= (probe_wr_pulse && probe_waddr_c == 7'h08
                          && probe_wdata_c[1]);
    end
    assign ram_unstick_w = ram_unstick_r;

    always_comb begin
        case (probe_addr)
            // The bisect-era taps (PIC/timer/keyboard counts, the wedge-PC
            // taps, the JTAG guest-memory master, the JTAG FDD/mgmt
            // channels) went out with PC98_PROBE_EXTRA -- the dbg_regs dump
            // below is what replaced them for "where is the CPU". The slots
            // carry z86's register view, latched; slot 0x18 (zet_pc) is the
            // live PC.
            8'h10:   probe_data_c = v30_dbg_regs[223:192];  // psw:pc
            8'h11:   probe_data_c = v30_dbg_regs[191:160];  // sreg3:sreg2
            8'h12:   probe_data_c = v30_dbg_regs[159:128];  // sreg1:sreg0
            8'h13:   probe_data_c = v30_dbg_regs[127:96];   // gpr7:gpr6
            8'h14:   probe_data_c = v30_dbg_regs[95:64];    // gpr5:gpr4
            8'h15:   probe_data_c = v30_dbg_regs[63:32];    // gpr3:gpr2
            8'h16:   probe_data_c = v30_dbg_regs[31:0];     // gpr1:gpr0
            8'h17:   probe_data_c = {8'h00, retired_cnt};   // liveness
            8'h18:   probe_data_c = {12'h000, zet_pc};      // current bus cycle
            8'h60:   probe_data_c = tlog_q[31:0];           // trigger log, see tlog
            8'h61:   probe_data_c = tlog_q[63:32];
            8'h62:   probe_data_c = tlog_q[95:64];
            8'h63:   probe_data_c = tlog_q[127:96];
            8'h64:   probe_data_c = tlog_q[159:128];
            8'h65:   probe_data_c = tlog_q[191:160];
            8'h68:   probe_data_c = {16'h0, tlog_q[207:192]};
            8'h69:   probe_data_c = f0w_a;
            8'h6a:   probe_data_c = f0w_b;
            8'h6b:   probe_data_c = f0w_c;
            // 0x6c-0x70: the port-A write-commit snoop witnesses -- see the
            // counter block by ce_count. 0x6c sn_v_cnt, 0x6d sn_dma_cnt
            // (AEN-window commits) -- both 16-bit free-running, read as
            // deltas mod 65536; 0x6e/0x6f the newest commit's
            // {len[31:28], addr[23:0]} (any / AEN-window); 0x70 the cache's
            // watched-line kill count (line of slot-0x06's trig_addr,
            // registered at this boundary).
            8'h6c:   probe_data_c = {16'h0, sn_v_cnt};
            8'h6d:   probe_data_c = {16'h0, sn_dma_cnt};
            8'h6e:   probe_data_c = {sn_last_len, 4'h0, sn_last_addr};
            8'h6f:   probe_data_c = {sn_dma_last_len, 4'h0, sn_dma_last_addr};
            8'h70:   probe_data_c = {16'h0, z86_sn_kills};
            8'h66:   probe_data_c = {z86_dbg_stopped, 15'h0, z86_dbg_next_ip};
            8'h67:   probe_data_c = {tlog_frozen, 15'h0, tlog_n};
            8'h01:   probe_data_c = brg_q[31:0];
            8'h02:   probe_data_c = {9'h0, brg_q[54:32]};
            8'h03:   probe_data_c = {24'h0, brg_w};
            // 0x06/0x0e: echo the live trigger and tlog-mode words, in the
            // exact layout of their write slots.  A write scan needs addr
            // bit 7 set (0x86/0x8e, see pc98_jtag_probe.sv); the bare slot
            // number is a pure READ -- the freeze script sent bare numbers,
            // so its "arm" never landed and the watchpoint sat disarmed
            // while the positive control wrote away.  Reading the word
            // back is the one-scan proof an arm actually took (0xDEAD00xx
            // = a bitstream without these readback slots).
            8'h06:   probe_data_c = {trig_en, trig_freeze, trig_delay,
                                     trig_bus, trig_wronly, trig_ds,
                                     6'b0, trig_addr};
            8'h0e:   probe_data_c = {22'b0, tlog_trap, tlog_all,
                                     2'b0, tlog_ri};
            // 0x19: {arbiter hold/DRQ, RAM FSM state} -- names WHY a fetch
            // never completes; 0x1a: the ready chain the CPU waits on.
            8'h19:   probe_data_c = {16'h0, chipset_dbg};
            8'h1a:   probe_data_c = {24'h0, chipset_dbg2};
            // 0x31: the GVRAM sequencer -- {svc_req, svc_done, svc_hold,
            // fsm[2:0], plane[1:0]}. A GDC-draw stall reads differently by
            // where it parks: S_RDW = RAM never answered, S_DONE+svc_hold
            // = guest strobe never dropped, svc_req alone = nobody granted
            // the channel (the guest bus is saturated or a hold/HLDA).
            // While fsm is IDLE the low five bits instead carry the last
            // svc-write arm's {svc_raw_wr, egc_here, grcg_active, window,
            // grcg_here} -- which term denied the charger, see the seq's
            // dbg port comment.
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
            // 0x39/0x3a: the slave GDC's display registers as the graphics
            // fetch consumes them -- {disp_on, page-0xA4, analogue, 5MHz,
            // doubled-200, CSRFORM LR, SYNC AL, PITCH} low and
            // {SAD0, LEN0} high. A mis-shaped picture reads back against
            // what the guest programmed.
            8'h39:   probe_data_c = dbg_gdc_s[31:0];
            8'h3a:   probe_data_c = dbg_gdc_s[63:32];
            // 0x3b/0x3c: slave GDC partitions one to three -- the stage
            // wipe in DEPTH walks SAD1..3 while SAD0 stays zero.
            8'h3b:   probe_data_c = dbg_gdc_s2[31:0];  // {SAD1,SAD2} lo/hi
            8'h3c:   probe_data_c = { 2'd0, dbg_gdc_s2[63:48],  // SAD3
                                      dbg_gdc_s3[29:0] };       // {LEN3,LEN2,LEN1}
            // 0x2D/0x2E: the CRT interrupt path (Peripherals dbg_crt) --
            // lo {IMR,ISR,IRR (master), spur_n[3:0], 0, pend, armed,
            // int_to_cpu}, hi {fire_n, isr_n, arm_n, lost_n[3:0],
            // cancel_n[3:0]}. scripts/jtag_crtirq.tcl decodes it.
            // 0x2F: the bus bridge's INTA witness -- {bad_n, last_bad,
            // cut_n (AEN rising mid-acknowledge), last_vec}.
            8'h2f:   probe_data_c = bridge_dbg_inta;
            8'h2d:   probe_data_c = dbg_crt[31:0];
            8'h2e:   probe_data_c = dbg_crt[63:32];
            // 0x82/0x83: graphics display-fetch underrun telemetry.
            // Low word {skip_cnt, late_cnt, max_fill}; high word the live
            // {line_now, act_tgt, f_chunk, f_plane, cur_part, dbl,
            // disp_page, disp_on_c, fill_page, f_active}.
            8'h82:   probe_data_c = dbg_gvdisp[31:0];
            8'h83:   probe_data_c = dbg_gvdisp[63:32];
            // 0x35: BIOS-side milestones + the 0x43D write tally
            // {bios_branch[7:0], in42_count, last_42_rdata,
            //  w43d_10_count[3:0], w43d_12_count[3:0]}
            8'h35:   probe_data_c = {bios_branch, in42_count,
                                     last_42_rdata, w43d_10_count[3:0],
                                     w43d_12_count[3:0]};
            // 0x90-0x99: rstprobe-era ITF forensics (remapped off 0x34/0x36
            // which the screen/GVRAM dump slots own on this branch).
            // 0x90: {itf_bank, f0_seen, entry_branch[3:0], in35_count,
            //        last_35_rdata, last_37_wdata} -- the 0x35 readback
            // bit 7 decides cold vs resume; entry_branch says which way
            // the entry actually went (b0 resume b1 cold b2 landed b3 F0).
            8'h90:   probe_data_c = {entry_branch, in35_count,
                                     last_35_rdata, last_37_wdata};
            // (itf_bank/f0_seen used to ride here in a 36-bit concat that
            // silently truncated -- bits 31:24 always read entry_branch,
            // never the named flags; they now live in 0xAA's pad nibble.)
            // bench-next186 probe block, remapped off 0x35-0x3A (owned by
            // the sysport/TVRAM/GVRAM/GDC slots above) and 0x64-0x74 (inside
            // this branch's rst_snap ring, 0x61-0x80):
            //
            // 0x9A-0x9C: the RAM-image floppy server's witness -- enough to
            // prove the feature is in the image ('R'=0x52 tag at the top),
            // that a mount ran, how much image has landed, and what a
            // readback probe of any byte offset returns. See fdd_ramimg for
            // the field layout.
            8'h9a:   probe_data_c = ri_dbg0;
            8'h9b:   probe_data_c = ri_dbg1;
            8'h9c:   probe_data_c = ri_dbg2;
            // 0x9D: first zet fault's {seen, opcode-seen, pc}. opc=00 with
            // seen=0 just means no fault yet; seen=1 pins the instruction
            // whose decode faulted, and opc is the byte it decoded.
            8'h9d:   probe_data_c = {3'b000, fault_seen, zet_opc, fault_pc};
            // 0x9E/0x9F: RAM.sv's DMA-fill loss witness -- 0x9E =
            // {first-drop FSM state, in-flight-was-write, dropped addr,
            //  drop count}, 0x9F = parked-write count. A nonzero drop
            // count is a byte the guest asked to store and nobody wrote.
            8'h9e:   probe_data_c = chipset_dbg3;
            8'h9f:   probe_data_c = chipset_dbg4;
            // 0x3b-0x3e: Bus_Arbiter's DMA-stream counters (dbg_dma): 0x3e
            // packs {break_cnt[7:0], grant_cnt[7:0], ack_wr_cnt[15:0]} --
            // grant = FDC DACK windows seen, ack_wr = memory-write strobes
            // that started under one (saturating; the low 16 bits are the
            // useful half). 0x3b-0x3d read zero: the old burst rings were
            // dropped for LAB headroom once the byte0 wrap-clobber was
            // found. ack_wr is the BUS-side count to set against the
            // commit-side sn_dma_cnt at 0x6d.
            8'h3b:   probe_data_c = chipset_dbg5[31:0];
            8'h3c:   probe_data_c = chipset_dbg5[63:32];
            8'h3d:   probe_data_c = chipset_dbg5[95:64];
            8'h3e:   probe_data_c = chipset_dbg5[127:96];
            // 0x3f: the service channel's launched operands, read straight
            // off the softcpu-subsystem wires -- {st_addr[19:0],
            // st_wdata[7:0], st_req, st_we, st_raw}. During the op these
            // are the operand {addr, wdata}; when the op's st_done lands
            // the subsystem parks the TRIGGER STORE's own fingerprint:
            // st_addr <= {cpu_mem_wstrb[3:0], cpu_mem_wdata[15:0]} and
            // st_wdata <= cpu_mem_wdata[7:0], all sampled at the launch.
            // So a parked read shows the trigger store's {wstrb,
            // wdata[15:0]} | {wdata[7:0], req, we, raw}: when raw is set,
            // the fingerprint beside it is the decisive witness -- a
            // clean sw-1 parks 0xF0001/0x01 (st_raw corrupted downstream),
            // a sw-5 parks 0xF0005/0x05 (bus really carried a 5), an sb-5
            // parks 0x10505/0x05, an s5=0x2FF leak parks 0xF02FF/0xFF.
            8'h3f:   probe_data_c = {1'b0, st_addr_w, st_wdata_w,
                                     st_req_w, st_we_w, st_raw_w};
            // 0xE1-0xE4: the write watchpoint ring -- RETIRED (its hunt
            // answered; the registers bought back the LABs the run#976
            // triage taps need). Reads return the dead-slot default.
            // 0xE5: RAM's uncovered-write witness {cnt, st, first addr};
            // 0xE6: {last data, last addr, first data}.
            8'he5:   probe_data_c = chipset_dbg8;
            8'he6:   probe_data_c = chipset_dbg9;
            // 0xE7-0xEA: retired with the arbiter's overlap witness (its
            // hunt answered zero; nothing ever read the slots). Reads
            // return the dead-slot default above.
            // 0xEB-0xED: RAM accept-side write ring (newest last at 0xEB);
            // 0xEE: accepted-write count.
            8'heb:   probe_data_c = chipset_dbg11[31:0];
            8'hec:   probe_data_c = chipset_dbg11[63:32];
            8'hed:   probe_data_c = chipset_dbg11[95:64];
            8'hee:   probe_data_c = {24'h0, chipset_dbg11[103:96]};
            // 0xEF: last accepted write to the watch address
            // ({1,pend,word,addr[19:0],data}); 0xF0: {wseen,wacc} counts --
            // wseen < arbiter watch_cnt means writes die before write_command
            // (sequencer swallow); wacc < wseen means accepted elsewhere or
            // mapped away (gvram_page1 redirect shows a wrong addr in 0xEF).
            8'hef:   probe_data_c = chipset_dbg12[31:0];
            8'hf0:   probe_data_c = {16'h0, chipset_dbg12[55:32]};
            // 0xF7: TVRAM cell readback {cell echo, attr, char_hi, char_lo}
            // armed by write slot 0x0B (bench-next186 used 0x74/0x8B).
            8'hf7:   probe_data_c = tvram_dbg_q;
            // 0x40-0x5F: pc_hist ring (see above). Frozen contents stay
            // readable while the post-0xF0 reboot runs.
            8'h40,8'h41,8'h42,8'h43,8'h44,8'h45,8'h46,8'h47,
            8'h48,8'h49,8'h4a,8'h4b,8'h4c,8'h4d,8'h4e,8'h4f,
            8'h50,8'h51,8'h52,8'h53,8'h54,8'h55,8'h56,8'h57,
            8'h58,8'h59,8'h5a,8'h5b,8'h5c,8'h5d,8'h5e,8'h5f:
                       probe_data_c = {7'h00, pc_hist_frozen, pc_hist_w,
                                       pc_hist[probe_addr[4:0]]};
            // 0x1b: {bridge park/engine FSM, ce edge counter}. parked=1 with a
            // frozen ce_count is the dead-CE signature; a live count with
            // parked=1 points at the engine's release conditions instead.
            8'h1b:   probe_data_c = {bridge_dbg, ce_count};
            // 0x1c: {ALE'd bus address, processor_status, the reset/pause
            // terms}. cpu_ad_out vs slot 0x18's zet_pc separates "the engine
            // is driving this cycle" from "the core's pins are frozen".
            8'h1c:   probe_data_c = {3'h0, cpu_ad_out, processor_status,
                                     pause_core, reset_cpu, reset_chipset,
                                     reset, soft_reset_cpu, cpu_ce_posedge};
            // 0x2b/0x2c: last data-bus byte addresses (BS_MEMW / BS_MEMR).
            // Instruction fetches are BS_CODE so these isolate the guest's
            // DS/ES physical segment -- the SuperDepth string-copy loop.
            8'h2b:   probe_data_c = {12'h000, zet_dbus_wr};
            8'h2c:   probe_data_c = {12'h000, zet_dbus_rd};
            // 0x20: {last byte-pair fed to the core, dbg_core}. The pins say
            // PASV while the core does not move: zwb_dat_i shows what it
            // last consumed. dbg_core was the nuV30's EU/BIU interlock --
            // z86 has no equivalent tap and the half reads 0.
            8'h20:   probe_data_c = {zwb_dat_i, v30_dbg_core};
            // 0x21: the posted access itself -- where the EU's MEMW wants to
            // land and which handshake bits are holding the slot.
            8'h21:   probe_data_c = v30_dbg_core2;
            // 0x22-0x25: nuV30 internals, all 0 on this build.
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
            // 0x2A: softcore liveness, sampled raw out of the clk_pico domain
            // -- {fetch completions[15:0], 0x2000_0000 polls[7:0], 2'b00,
            // firmware cpu_speed[1:0], osd_req seen, trap seen, trap live,
            // osd_open_req live}. A frozen fetch word is a dead pico; a
            // frozen poll byte beside a moving fetch word is a wedged loop.
            8'h2a:   probe_data_c = dbg_pico_w;
            // 0xA0-0xA7: every OSD setting, four per slot (settings_ui.c's
            // SET_* index order): slot 0xA0+g = {set[4g+3] .. set[4g]}.
            8'ha0,8'ha1,8'ha2,8'ha3,8'ha4,8'ha5,8'ha6,8'ha7:
                     probe_data_c = osd_set_word;
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
            // 0x74: text-VRAM dump -- armed by write slot 0x8b; returns
            // {cell[7:0] echo, attr, char_hi, char_lo} for that cell.
            8'h74:   probe_data_c = tvram_dbg_q;
            // ---- the wedge tap's frozen snapshot (see the WEDGE TAP
            // block above; write slot 0x08 clears/re-arms it) ---------
            8'ha0:   probe_data_c = {snap_arb, snap_rdy, snap_arbhold};
            8'ha1:   probe_data_c = snap_ram;
            8'ha2:   probe_data_c = snap_sdram[31:0];
            8'ha3:   probe_data_c = {24'h0, snap_sdram[39:32]};
            8'ha4:   probe_data_c = snap_bridge;
            8'ha5:   probe_data_c = {snap_seq, snap_chip2, 8'h0};
            8'ha6:   probe_data_c = {wedge_latch, 7'h0, snap_retired};
            8'ha7:   probe_data_c = {12'h0, snap_pc};
            // The run#976 triage slots (frozen with the wedge tap; live
            // until it latches): 0xA8 -- the uPD71071's request-side
            // registers (upd71071's dbg_mask; layout fixed in run#977 --
            // the original 36-bit concat truncated and the commented
            // layout never reached the metal):
            // [31] controller_disable  [30] rotating_priority
            // [29] dreq_sense_active_low
            // [28:25] mask_register  [24:21] request_register
            // [20:17] dma_request_ff (raw pins after sense)
            // [16:13] dma_request_lock
            // [12:11] transfer_mode[3]  [10:9] transfer_mode[2]
            // [8] autoinit[3]  [7] autoinit[2]  [6:0] 0
            8'ha8:   probe_data_c = snap_dma;
            // 0xA9 -- the floppy engine's execution-phase view
            // (Peripherals' dbg_fdc2 = {0, floppy.v's dbg2, TC latch}):
            // [31] 0, [30:27] main state, [26:16] fifo_count,
            // [15] execute_ndma, [14] ndma_irq, [13] ndma timeout seen,
            // [12] dma_irq_enable (0x94 DMAE), [11] dma_has_terminated
            // (TC seen), [10] cmd_read_in_progress,
            // [9] cmd_write_in_progress, [8] cmd_format_in_progress,
            // [7] dma_req, [6] irq, [5] busy, [4] in_seek_mode,
            // [3] datareg_ready, [2] transfer_to_cpu, [1] dma_ack pulse
            // (rw_ack), [0] TC latch.
            8'ha9:   probe_data_c = snap_fdc2;
            // 0xAA -- the trigger statuses: which latch fired and how far
            // the poll window dwell had counted (poll_static is full
            // 24'hFFFFFF only at the latch -- read mid-run to watch it
            // climb). Bit29 wild_latch: the cursor entered a zone no
            // legal execution lives in (slot 0x87 bit30 arms it).
            // [27:26] carry itf_bank/f0_seen -- their old home (slot
            // 0x90) truncated them off the metal in an over-wide concat.
            8'haa:   probe_data_c = {wedge_latch, poll_latch, fdq_latch,
                                     wild_latch, itf_bank, f0_seen, 2'b00,
                                     poll_static};
            // 0xAB -- the frozen z86 view: [31] halted, [27:16]
            // FLAGS[11:0] ([25]=IF, [24]=TF), [15:0] IP. Separates
            // "parked in HLT waiting for an interrupt that never comes"
            // from "pipeline dead" and names where the reboot/wild run
            // stopped, which the live cursor (slot 0x18) can no longer
            // prove after the fact.
            8'hab:   probe_data_c = snap_z86;
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
    wire       mabiki;                  // mode1[4]: odd rasterlines stay dark
    wire       dbl_skip_pix;
    // The odd-line skip fires for the machine's own mabiki flag (mode1[4] --
    // software's 200-line display bit, np21w makegrph) OR when the user
    // asked for the "Skip" presentation of a doubled mode.
    synch_3              s_dbl_skip_pix ((osd_dbl_skip & dbl200) | mabiki,
                                         dbl_skip_pix, clk_pix);
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
    // simulation +keys channel is bench-side only (tb_pc98_boot.sv drives its
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
        if (probe_wr_pulse && probe_waddr_c == 7'h0c)
            jtag_slots_ok <= probe_wdata_c[0];
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
        // Write slot 0x06: the rst_snap address trigger --
        // {en,freeze,delay,bus,wronly,addr[19:0]}. freeze additionally
        // stops pc_hist on a hit so the ring holds whatever led to the
        // watched address. (rstprobe used slot 0x04; here that slot
        // launches GVRAM dumps, so the trigger moved to 0x06.)
        if (probe_wr_pulse && probe_waddr_c == 7'h06) begin
            trig_addr   <= probe_wdata_c[19:0];
            trig_en     <= probe_wdata_c[31];
            trig_freeze <= probe_wdata_c[30];
            trig_delay  <= probe_wdata_c[29];
            trig_bus    <= probe_wdata_c[28];
            trig_wronly <= probe_wdata_c[27];
            trig_ds     <= probe_wdata_c[26];
        end
        // Slot 0x07 (wr 0x87): arm the poll-trap and wild-fetch triggers
        // -- {poll_en[31], wild_en[30], pc[19:0]}. The 32-byte poll
        // window is pc[19:5] of the armed address; the trigger latches
        // (freezing the wedge tap + pc_hist + tlog) when the fetch cursor
        // stays inside it for ~390 ms. bit30 arms the wild-fetch trigger
        // (a cursor entering the no-legal-code zones freezes the same
        // tap within ~1024 clk). Arm both when the game starts playing;
        // clearing en[31] disarms the poll window, clearing bit30 the
        // wild watch.
        if (probe_wr_pulse && probe_waddr_c == 7'h07) begin
            poll_en <= probe_wdata_c[31];
            wild_en <= probe_wdata_c[30];
            poll_pc <= probe_wdata_c[19:0];
        end
        // Slot 0x09: CPU-speed override for scripted runs -- wdata[2] forces
        // clk_select_next to wdata[1:0] instead of the OSD setting. Same
        // handoff the menu uses (ce_generator reloads on the next biu_done).
        // wdata[3] ENABLES the (default-off) prefetch engine; wdata[6:4] kill
        // pure fills / fill-on-miss / hit serving individually for A/B.
        if (probe_wr_pulse && probe_waddr_c == 7'h09) begin            jtag_spd_ovr  <= probe_wdata_c[2];
            jtag_spd_sel  <= probe_wdata_c[1:0];
            jtag_pf_dis   <= ~probe_wdata_c[3];
            jtag_pf_nofill  <= probe_wdata_c[4];
            jtag_pf_nofillm <= probe_wdata_c[5];
            jtag_pf_nohit   <= probe_wdata_c[6];
            jtag_pf_wkill <= probe_wdata_c[9];
            jtag_pf_bkill <= probe_wdata_c[10];
            jtag_cache_dis <= probe_wdata_c[11];
            jtag_thr_num  <= probe_wdata_c[19:12];
        end
        // Slot 0x0a: guest-address watchpoint -- RETIRED with the write
        // ring it armed (Bus_Arbiter's dbg_dma3 reads 0; see the 0xE1-0xE4
        // note at the mux). A write here is accepted and ignored.
        if (probe_wr_pulse && probe_waddr_c == 7'h0d)
            brg_ri <= probe_wdata_c[7:0];
        // Slot 0x0b: arm the text-VRAM dump cell (readback on slot 0xF7;
        // shared with the screen probe's cell, which also auto-advances on
        // every completed 0x36 read).
        if (probe_wr_pulse && probe_waddr_c == 7'h0b)
            dbg_tvram_cell <= probe_wdata_c[11:0];
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
        if ((load_active_d & ~load_active)  // APF done AND the FIFO fully drained
            || jtag_slots_ok)
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
                    //
                    // ram_rw_complete is memory_access_ready now: it reads 1
                    // while no access is in flight, so honour it only after
                    // the write has had time to reach RAM's pins through the
                    // arbiter hold and the sequencer -- four clocks. Before
                    // that, a 1 is the idle default, not coverage.
                    if (((bios_write_wait_cnt >= 8'd4) && ram_rw_complete)
                        || (bios_write_wait_cnt == 8'd63))
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
    // The 16-bit memory path's extra lane, between cpu_bus_bridge and the
    // chipset's RAM/option-ROM muxes.
    wire [7:0] cpu_data_bus_hi;
    wire [7:0] data_bus_hi;
    wire       cpu_word_access;
    // The prefetch engine's side channel on the same path: cpu_pf_len asks
    // RAM for a multi-word read burst and pf_beat_* streams the words
    // back one at a time for the bridge's queue.
    wire [4:0] cpu_pf_len;
    wire       pf_beat_v;
    wire [7:0] pf_beat_dat;
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
    wire [31:0]  chipset_dbg3;
    wire [31:0]  chipset_dbg4;
    wire [127:0] chipset_dbg5;
    wire  [31:0] chipset_dbg8;
    wire  [31:0] chipset_dbg9;
    wire [103:0] chipset_dbg11;
    wire  [55:0] chipset_dbg12;
    // The wedge tap's live views (PC98_JTAG only; frozen copies live in the
    // snap_* registers): the 71071's request-side registers and the floppy
    // engine's execution-phase view, both registered at this boundary.
    wire [31:0]  cs_w_dma;
    wire [31:0]  cs_fdc2;
    // ...and the rest of the wedge tap's live feeds (PC98_JTAG only;
    // frozen copies live in the snap_* registers under the macro).
    // Declared here so the CHIPSET instance below connects unconditionally.
    wire [15:0]  cs_w_arb;
    wire  [7:0]  cs_w_rdy;
    wire [15:0]  cs_w_seq;
    wire [23:0]  cs_w_ram;
    wire [39:0]  cs_w_sdram;
    wire         ram_unstick_w;
`ifndef PC98_JTAG
    assign ram_unstick_w = 1'b0;
`endif
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
    wire [63:0]  dbg_gdc_s;    // slave GDC display regs: {SAD0,LEN0} hi,
    wire [63:0]  dbg_gdc_s2;   // slave GDC SADs 1..3
    wire [63:0]  dbg_gdc_s3;   // slave GDC LENs 1..3
                             // {disp_on,page,analog,5MHz,dbl,LR,AL,PITCH} lo
    wire [63:0]  dbg_gvdisp;   // graphics display fetch: {line,fill FSM} hi,
                             // {skip,late,max_fill} lo
    wire [63:0]  dbg_crt;      // CRT IRQ2: {fire,isr,arm,lost,cancel} hi,
                             // {IMR,ISR,IRR,spur,pend,armed,int} lo

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

    // F0 witness: the bus as it stood when the OUT 0F0h detector first saw
    // its port -- chipset address, 8288 status, the bridge's own address
    // and the z86 Wishbone cycle -- so a CPU reset that loops at 10 MHz can
    // be tied to the access that raised it. Reads 0x69 / 0x6A / 0x6B.
    reg  f0_seen_d = 1'b0;
    reg  [31:0] f0w_a = 32'h0, f0w_b = 32'h0, f0w_c = 32'h0;
    always @(posedge clk_chipset) begin
        f0_seen_d <= f0_port_write;
        if (f0_port_write && !f0_seen_d) begin
            f0w_a <= {4'h0, processor_status, 1'b0, chipset_io_write_n, chipset_aen,
                      2'b00, chipset_address};
            f0w_b <= {zwb_cyc, zwb_stb, zwb_we, zwb_tga, zwb_sel, 6'h0, cpu_ad_out};
            f0w_c <= {12'h0, zet_pc};
        end
    end

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
        .cpu_pf_len                         (cpu_pf_len),
        .pf_beat_v                          (pf_beat_v),
        .pf_beat_dat                        (pf_beat_dat),
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
        .tvram_dbg_q                        (tvram_dbg_q),
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
        .mabiki                             (mabiki),
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
        .dbg_chipset3                       (chipset_dbg3),
        .dbg_chipset4                       (chipset_dbg4),
        .dbg_chipset5                       (chipset_dbg5),
        .dbg_chipset8                       (chipset_dbg8),
        .dbg_chipset9                       (chipset_dbg9),
        .dbg_chipset11                      (chipset_dbg11),
        .dbg_chipset12                      (chipset_dbg12),
        // The wedge tap: live views out, the escape-hatch pulse in.
        .dbg_w_arb                          (cs_w_arb),
        .dbg_w_rdy                          (cs_w_rdy),
        .dbg_w_seq                          (cs_w_seq),
        .dbg_w_ram                          (cs_w_ram),
        .dbg_w_sdram                        (cs_w_sdram),
        .dbg_w_dma                          (cs_w_dma),
        .ram_unstick                        (ram_unstick_w),
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
        .mgmt_writedata                     (cs_mgmt_dout),
        .mgmt_address                       (cs_mgmt_addr),
        .mgmt_write                         (cs_mgmt_wr),
        .mgmt_read                          (cs_mgmt_rd),
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
        .dbg_fdc2                           (cs_fdc2),
        .dbg_gdc_s                          (dbg_gdc_s),
        .dbg_gdc_s2                         (dbg_gdc_s2),
        .dbg_gdc_s3                         (dbg_gdc_s3),
        .dbg_gvdisp                         (dbg_gvdisp),
        .dbg_crt                            (dbg_crt),
        .wait_count_clk_en                  (cpu_ce_negedge),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle),
        .vram_wait_en                       (vram_wait_en),
        .pause_core                         (pause_core_chipset),
        .ram_rw_complete                    (ram_rw_complete)
        ,.sdram_wr_taken                   (sdram_wr_taken)
        ,.sdram_rd_ready                   (sdram_rd_ready)
        ,.pc98_key_stb                      (pc98_key_stb)
        ,.pc98_key_byte                     (pc98_key_code)
        ,.mouse_dx                          (mouse_dx)
        ,.mouse_dy                          (mouse_dy)
        ,.mouse_ev                          (mouse_ev)
        ,.mouse_btn                         (mouse_btn)
        ,.opna_joy                          (opna_joy)
        ,.ramimg_req                        (ramimg_req)
        ,.ramimg_we                         (ramimg_we)
        ,.ramimg_addr                       (ramimg_addr)
        ,.ramimg_len                        (ramimg_len)
        ,.ramimg_wdata                      (ramimg_wdata)
        ,.ramimg_ack                        (ramimg_ack)
        ,.ramimg_rvalid                     (ramimg_rvalid)
        ,.ramimg_rdata                      (ramimg_rdata)
        ,.ramimg_done                       (ramimg_done)
        ,.cachef_req                        (cachef_req)
        ,.cachef_we                         (cachef_we)
        ,.cachef_addr                       (cachef_addr)
        ,.cachef_len                        (cachef_len)
        ,.cachef_wdata0                     (cachef_wdata0)
        ,.cachef_wdata1                     (cachef_wdata1)
        ,.cachef_ack                        (cachef_ack)
        ,.cachef_rvalid                     (cachef_rvalid)
        ,.cachef_rdata                      (cachef_rdata)
        ,.cachef_done                       (cachef_done)
        ,.ram_wr_snoop_v                    (ram_wr_snoop_v)
        ,.ram_wr_snoop_addr                 (ram_wr_snoop_addr)
        ,.ram_wr_snoop_len                  (ram_wr_snoop_len)
    );

`ifdef PC98_JTAG
    // The RAM-disk floppy server: streams a JTAG-uploaded image into its
    // SDRAM carve-out, mounts the 2HD geometry on drive A over the shared
    // management bus (the mux is above the softcore's instance), and serves
    // the controller's sector requests straight from SDRAM. reset aborts an
    // in-flight transfer only -- the mounted disk survives the guest reset
    // that boots from it, because floppy.v's media_present has no reset.
    fdd_ramimg u_fdd_ramimg (
        .clk             (clk_chipset),
        .reset           (reset),
        .power_reset     (reset_sdram),
        .fdd_request     (mgmt_req[7:6]),
        .fw_busy         ((mgmt_wr | mgmt_rd) & ~fw_fdd_hit),
        .mgmt_addr       (ri_mgmt_addr),
        .mgmt_dout       (ri_mgmt_dout),
        .mgmt_wr         (ri_mgmt_wr),
        .mgmt_rd         (ri_mgmt_rd),
        .mgmt_din        (mgmt_din),
        .sd_req          (ramimg_req),
        .sd_we           (ramimg_we),
        .sd_addr         (ramimg_addr),
        .sd_len          (ramimg_len),
        .sd_wdata        (ramimg_wdata),
        .sd_ack          (ramimg_ack),
        .sd_rvalid       (ramimg_rvalid),
        .sd_rdata        (ramimg_rdata),
        .sd_done         (ramimg_done),
        .ctl_pulse       (probe_wr_pulse),
        .ctl_addr        (probe_waddr_c),
        .ctl_data        (probe_wdata_c),
        .own             (ri_own),
        .guest_reset_req (ri_greset),
        .dbg0            (ri_dbg0),
        .dbg1            (ri_dbg1),
        .dbg2            (ri_dbg2)
    );
`endif

    // CHIPSET per-access "done" pulse (COMPLETE_RAM_RW); drives the ROM-load FSM.
    wire        ram_rw_complete;
    // CHIPSET's posted-write capture witness; the bridge's drain engine
    // holds each queued write strobe until this says it is durably held.
    wire        sdram_wr_taken;
    wire        sdram_rd_ready;

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
    // z86, the 80286-class core, on a Wishbone master, bridged to the 8288
    // byte world -- cpu_bus_bridge runs each 16-bit cycle as one two-lane
    // cycle where the SDRAM answers and two byte cycles everywhere else on
    // the eight-bit bus. See cpu_bus_bridge.sv's header for the contract.
    // z86 covers the full 286 real-mode instruction set -- the ITF's
    // `push imm16` that derailed the old i8088 is legal for it -- but it is
    // not cycle-accurate; the bridge's bus pacing is what models the metal.
    //
    // The CE generator's outputs still pace the CHIPSET's RAM waits, which
    // is where they are consumed.
    wire [15:0] bridge_dbg;
    wire [31:0] bridge_dbg_inta;  // INTA witness, probe slot 0x2F
    wire [23:0] bridge_dbg_w;     // wedge tap's engine view, slot 0xA4

    wire        zet_clk;
    // The bridge's zet_edge: high on the clk_chipset posedges that also
    // reach zet_clk -- the clock enable for logic stepping with z86.
    wire        z86_ce;
    wire [15:0] zwb_dat_i, zwb_dat_o;
    wire [19:1] zwb_adr;
    wire        zwb_we, zwb_tga, zwb_stb, zwb_cyc, zwb_ack;
    wire [ 1:0] zwb_sel;
    wire        zwb_inta, zwb_nmia;
    wire [19:0] zet_pc;
    wire [15:0] zet_ds;
    wire        zet_exec;
    wire        zet_fault;
    wire [7:0]  zet_opc;

    // Every speed setting is a 286-class machine, so the bus pairs run
    // the 286 Ts/Tc profile unconditionally. A future V30-accurate mode
    // would drive this from its own settings instead.
    wire pace_286 = 1'b1;

    cpu_bus_bridge #(.REQ_SETTLE(0)) u_cpu_bridge (
        .clk               (clk_chipset),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .pace_286          (pace_286),
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
        .pf_req_len        (cpu_pf_len),
        .pf_beat_v         (pf_beat_v),
        .pf_beat_dat       (pf_beat_dat),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (data_bus_hi),
        .data_bus          (data_bus),
        .processor_ready   (processor_ready),
        .address_enable_n  (chipset_aen),
        .sdram_wr_taken    (sdram_wr_taken),
        .sdram_rd_ready    (sdram_rd_ready),
        .pause_core        (pause_core),
        .throttle          (thr_hold),
        .biu_done          (biu_done),
        .zet_edge_o        (z86_ce),
        // Prefetch windows default OFF (jtag_pf_dis=1 above): pf ON wedges
        // ITF POST (TIMER INTERRUPT ERROR, ~1/12 boots) on the SD build;
        // the 286 BIU-queue model is A/B-only now (slot 0x89 bit3).
        // NOTE: keep this feed a plain wire. 7f85bf0 AND-ed a clk_select
        // term in here; the extra gate at this high-fanout node perturbed
        // placement into a -0.039ns setup miss on the main core clock and
        // a grey build (paced supply collapsed to ~3.4). Reverted.
        .pf_disable        (jtag_pf_dis),
        .pf_nofill         (jtag_pf_nofill),
        .pf_nofillm        (jtag_pf_nofillm),
        .pf_nohit          (jtag_pf_nohit),
        .pf_wkill          (jtag_pf_wkill),
        .pf_bkill          (jtag_pf_bkill),
        .bus_mem_write_n   (chipset_memory_write_n),
        // foreign-commit snoop: same port-A feed the z86 cache snoops --
        // kills only pf windows a committed span overlaps (DMA, loader)
        .sn_v              (ram_wr_snoop_v),
        .sn_addr           (ram_wr_snoop_addr),
        .sn_len            (ram_wr_snoop_len),
        .bios_shadow_flag  (bios_shadow_flag),
        .dbg               (bridge_dbg),
        .dbg_inta          (bridge_dbg_inta),
        .dbg_w             (bridge_dbg_w)
    );

    // z86 (fpga/core/z86): a pipelined 286-class core on the bridge's
    // Wishbone/INTA contract -- the only CPU the tree carries.
    // The cache runs on the free clk_chipset with the bridge's zet_edge as
    // its enable. It stays off while the ITF is mapped: the ITF's IRQ0 test
    // expects the timer interrupt within 32 turns of a TEST/JNZ/LOOP, a
    // window a cached loop runs through long before the PIT gets there.
    // It also stays off in the paced modes: those are bus-faithful now --
    // 1x CE + the 286 Ts/Tc pair profile -- and a VX2/VX21/RX had no
    // cache; the cache is the Turbo setting's headroom. Toggling at
    // runtime is safe: the cache is write-through no-allocate, uncached
    // writes ride the port-A commits whose snoop clears lines, and
    // clk_select latches on biu_done.
    z86 u_cpu (
        .clk       (zet_clk),
        .reset     (reset_cpu),
        .clk_free  (clk_chipset),
        .ce        (z86_ce),
        .cache_en  (osd_cpu_cache & (clk_select == 2'b11)
                    & ~jtag_cache_dis & ~itf_bank),
        .bios_shadow  (bios_shadow_flag),
        .bios_protect (bios_protect_flag[1]),
        .f_req     (cachef_req),
        .f_we      (cachef_we),
        .f_addr    (cachef_addr),
        .f_len     (cachef_len),
        .f_wdata0  (cachef_wdata0),
        .f_wdata1  (cachef_wdata1),
        .f_ack     (cachef_ack),
        .f_rvalid  (cachef_rvalid),
        .f_rdata   (cachef_rdata),
        .f_done    (cachef_done),
        .sn_v      (ram_wr_snoop_v),
        .sn_addr   (ram_wr_snoop_addr),
        .sn_len    (ram_wr_snoop_len),
        // watched-line snoop-kill witness: the slot-0x06 trigger address is
        // the watched line, shared with the bus-side write watchpoint.
        .dbg_watch_a (trig_addr),
        .dbg_sn_kills (z86_sn_kills_w),
        .wb_adr_o  (zwb_adr),
        .wb_sel_o  (zwb_sel),
        .wb_we_o   (zwb_we),
        .wb_tga_o  (zwb_tga),
        .wb_dat_o  (zwb_dat_o),
        .wb_stb_o  (zwb_stb),
        .wb_cyc_o  (zwb_cyc),
        .wb_ack_i  (zwb_ack),
        .wb_dat_i  (zwb_dat_i),
        .wb_tgc_i  (interrupt_to_cpu),
        .wb_tgc_o  (zwb_inta),
        .pc        (zet_pc),
        .dbg_ds    (zet_ds),
        .dbg_regs  (z86_dbg_regs),
        .dbg_stop  (jtag_dbg_stop),
        .dbg_stopped (z86_dbg_stopped),
        .dbg_next_ip (z86_dbg_next_ip),
        .dbg_halted(z86_halted),
        // write watchpoint: cached stores that bypass the chipset bus
        .dbg_wr_v  (z86_pf_wr_v),
        .dbg_wr_a0 (z86_pf_wr_a0),
        .dbg_wr_two(z86_pf_wr_two)
    );
    assign zwb_nmia  = 1'b0;
    assign zet_fault = 1'b0;
    assign zet_opc   = 8'h00;
    assign zet_exec  = 1'b0;

    // Debug: the last guest data-bus read / write byte addresses. Instruction
    // fetches are BS_CODE and I/O is BS_IOR/BS_IOW on processor_status, so a
    // MEMR/MEMW sample isolates the guest's data segment (DS/ES physical).
    reg [19:0] zet_dbus_rd, zet_dbus_wr;
    always @(posedge clk_chipset) begin
        if (processor_status == 3'b101) zet_dbus_rd <= cpu_ad_out;
        if (processor_status == 3'b110) zet_dbus_wr <= cpu_ad_out;
    end

    // The probe slots that used to expose nuV30 guts read the CPU view where
    // one exists (0x18/0x1c/0x20 = zet_pc / processor_status / the Wishbone
    // data-in); the dbg_core taps z86 has no answer for read 0.

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
