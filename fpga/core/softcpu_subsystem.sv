//
// PicoRV32 softcore subsystem.
//
// A small RISC-V computer that services the disk controllers and draws the
// on-screen keyboard. It runs firmware from an on-chip ROM, with work RAM for its
// stack and buffers, and reaches the disk bridge (softcpu_fdd_bridge) through
// memory-mapped registers at 0x3xxxxxxx; the bridge pulls sectors from an APF
// dataslot and streams them into the floppy and IDE controllers' mgmt FIFOs. It
// also owns the OSD framebuffer, read out below in the video clock domain.
//
// The CPU runs on clk_pico, a clock derived from clk_sys by gating it down to a
// single-cycle pulse every six cycles (about 8.3 MHz). Every clk_pico edge is
// also a clk_sys edge, so a register written in the clk_pico domain is stable for
// the whole period and can be read from clk_sys logic without a synchroniser.
//
// Adapted from the softcore approach in the myc64-pocket and OpenFPGA ZX Spectrum
// Pocket cores.
//

module softcpu_subsystem (
    input clk_sys,   // clk_chipset, 50 MHz
    input clk_74a,   // APF bridge clock
    input reset,     // softcore reset: FPGA infrastructure not ready, independent of the guest reset
    // Firmware image load, from an SD data slot. The ROM's $readmemh contents
    // are the default; this overwrites them when a slot supplies a file.
    input        fw_wr_clk,
    input        fw_wr_en,
    input [12:0] fw_wr_addr,
    input [31:0] fw_wr_data,

    // Softcore clock, exported so core_top can clock the datatable's port A with it.
    output reg clk_pico,

    // floppy.v request flags (CHIPSET fdd_request): {write-pending, read-pending}
    input [1:0] fdd_request,

    // ide.v request (CHIPSET ide0_request): 6=reset, 4=command, 5=data, 0=idle
    input [2:0] ide0_request,

    // Mounted floppy image size in sectors, per drive (from the dataslot-update event).
    input [31:0] fdd0_disk_size,
    input [31:0] fdd1_disk_size,

    // Datatable port A, routed on to the disk bridge (softcpu_fdd_bridge) where the
    // firmware reads the HDD and Settings slot sizes by id.
    output  [9:0] datatable_addr,
    output [31:0] datatable_data,
    output        datatable_wren,
    input  [31:0] datatable_q,

    // Per-floppy-drive image-rebind toggle: flips on every dataslot update so the
    // firmware re-mounts a swapped image even at an unchanged size.
    input        fdd0_rebind,
    input        fdd1_rebind,

    // Management-bus master to floppy.v via CHIPSET
    output [15:0] mgmt_addr,
    output [15:0] mgmt_dout,
    output        mgmt_wr,
    output        mgmt_rd,
    input  [15:0] mgmt_din,

    // APF host DMA into the disk bridge RAM
    input         bridge_wr,
    input  [31:0] bridge_addr,
    input  [31:0] bridge_wr_data,

    // APF target-dataslot transfer handshake
    output        target_dataslot_read,
    output        target_dataslot_write,
    output [15:0] target_dataslot_id,
    output [31:0] target_dataslot_slotoffset,
    output [31:0] target_dataslot_bridgeaddr,
    output [31:0] target_dataslot_length,
    input         target_dataslot_ack,
    input         target_dataslot_done,
    input   [2:0] target_dataslot_err,

    output [31:0] bridge_rd_data_out,

    // OSD overlay: framebuffer read out in the video clock domain (clk_pix),
    // located by the raster counters from the video output stage. The CPU write
    // side of the framebuffer lands in clk_pico.
    input         clk_pix,
    input   [9:0] osd_hcnt,
    input   [9:0] osd_vcnt,
    output  [3:0] osd_palette_idx,
    output        osd_in_area,

    // Controller-1 buttons in; OSD-shown flag out (both firmware-facing).
    input  [15:0] cont1_key,
    input   [7:0] dock_key_code,  // last docked-keyboard make, for the key picker
    input         dock_key_ext,   // its E0 flag
    input         dock_key_stb,   // toggles per docked make; firmware change-detects it
    input         credits_active, // credits overlay up: firmware suppresses OSD button input
    input         osd_open_req,   // interact "Extra Options" requests the settings OSD
    input   [9:0] raster_w,       // presented raster size, for overlay placement
    input   [9:0] raster_h,
    input         dataslots_ready, // APF has finished the initial dataslot load
    output        soft_guest_hold, // boot-master guest reset: held until settings are staged
    // SDRAM self-test window (docs/P0_SELFTEST_SPEC.md). The firmware drives
    // guest SDRAM through core_top's ext-port master while the 8088 is held,
    // so a failing address can be reported instead of inferred from a beep.
    output [19:0] st_addr,
    output  [7:0] st_wdata,
    output        st_we,    // 1 = write, 0 = read
    output        st_req,   // level; held until st_done comes back
    input         st_done,
    input   [7:0] st_rdata,
    // POST monitor (post_monitor.sv): the guest's progress on I/O port 0x80,
    // so the firmware can put "where the BIOS got to" on screen.
    // INTR into the CPU, served at 0x500000B4. See core_top.
    input  [15:0] int_count,
    input         int_live,
    // The master GDC's view, served at 0x500000B0. See PERIPHERALS.
    input   [7:0] dbg_pic_irr,
    input   [7:0] dbg_pic_imr,
    input   [7:0] dbg_pic_isr,
    input   [7:0] dbg_inta_vec,
    input  [15:0] dbg_inta_count,
    input   [7:0] dbg_pic2_irr,
    input   [7:0] dbg_pic2_imr,
    input   [7:0] dbg_pic2_isr,
    input   [7:0] dbg_motor_arms,
    input   [7:0] dbg_motor_pulses,
    input   [7:0] dbg_chg,
    input   [7:0] dbg_strb_be, dbg_strb_94, dbg_strb_cc, dbg_strb_dat,
    input   [7:0] dbg_last_ctrl,
    input  [31:0] dbg_fdc_x,
    input  [31:0] dbg_fdc_y,
    input  [95:0] dbg_fdc_z,
    input  [31:0] dbg_fdc_w,
    input  [31:0] dbg_fdc_v,
    input  [15:0] dbg_w_path, dbg_rw_lvl,
    input   [7:0] dbg_irq_level,
    input   [7:0] dbg_timer_count,
    input   [7:0] dbg_kbd_irq_count,
    input   [7:0] dbg_kbd_rd_count,
    input  [14:0] dbg_gdc_sad,
    input   [7:0] dbg_gdc_pitch,
    input   [7:0] dbg_gdc_unk_cmd,
    input   [7:0] dbg_gdc_unk_count,
    input         dbg_gdc_disp_on,
    input  [23:0] dbg_gdc_cur,
    input   [7:0] dbg_gdc_csrcnt,
    input  [31:0] dbg_gdc_csrtrace,
    // The guest-reset terms (core_top's dbg_bits low byte), the hardware-band
    // strip's replacement: {~RESET, reset, interact_reset, bios_ever_loaded,
    // 0, 0, guest_hold_sync2, soft_guest_hold} -- the reset_wire terms, read
    // on the POST panel where they are legible.
    input   [7:0] dbg_reset_terms,
    // The drawing server's view of the two GDCs, already in this domain via
    // the synchronisers below; the done LEVEL the engine writes back.
    input   [1:0]  gdc_draw_req,
    input   [1:0]  gdc_draw_busy,
    input  [15:0]  gdc_draw_ops,
    input [319:0]  gdc_draw_snaps,
    output  [1:0]  gdc_srv_done_levels,
    // How far a key press gets, served at 0x500000AC. See core_top.
    input   [7:0] key_count,
    input   [7:0] key_last,
    // The memory-sizing evidence, served at 0x500000A8. See post_monitor.
    input   [7:0] memsw_seen,
    input   [7:0] memsize_seen,
    input   [7:0] f0_count,
    input   [7:0] post_code,
    input   [7:0] post_prev,
    input  [63:0] post_hist,
    input  [19:0] post_mem_addr,
    input  [19:0] post_live_addr,
    input  [19:0] post_live_max,
    input  [15:0] post_live_cs,
    input  [15:0] post_live_ip,
    input  [15:0] post_derail_cs,
    input  [15:0] post_derail_ip,
    input  [15:0] post_ring_ip0, post_ring_ip1, post_ring_ip2, post_ring_ip3,
    input  [15:0] post_land_cs,  post_land_ip,
    input  [19:0] post_fr0_addr, post_fr1_addr,
    input  [7:0]  post_fr0_data, post_fr1_data,
    input  [15:0] post_count,
    input   [7:0] post_max,
    input  [15:0] post_restarts,
    input  [15:0] ivt16_off,
    input  [15:0] ivt16_seg,
    input   [7:0] ivt16_wr_count,
    input  [15:0] ivt13_off,
    input  [15:0] ivt13_seg,
    input  [15:0] ivt12_off,
    input  [15:0] ivt12_seg,
    input  [15:0] wr_any_count,
    input  [15:0] tvram_wr_count,
    input  [63:0] tvram_row0_code,
    input  [63:0] tvram_row0_hi,
    input  [63:0] pc98_tvfill_view,
    input  [15:0] pc98_rowbuf_freq_count,
    input  [15:0] pc98_rowbuf_fvalid_count,
    input  [63:0] tvram_row0_attr,
    input  [15:0] rd_any_count,
    input  [15:0] ivt_touch_count,
    input  [19:0] wr_last_addr,
    input  [19:0] tvram_last_addr,
    input   [3:0] raw_strobes,
    input  [15:0] wr_low_cycles,
    input  [15:0] rd_low_cycles,
    output [15:0] rom_win,          // W 0x5000007C: CPU-read snoop window
    input [127:0] rom_read_data,
    input [127:0] rom_load_data,
    input   [7:0] rom_load_count,
    // BIOS-load FIFO health: words the FIFO had to throw away, and how deep it
    // ever got. See core_top -- there is no backpressure to the APF bridge.
    // Which I/O ports the guest has written, and the ITF bank state. On PC-98
    // the ITF's progress is visible only through the ports it touches.
    input  [63:0] io_port_hist,
    input  [15:0] io_wr_count,
    input         itf_bank,
    input  [15:0] rlf_drops,
    input  [15:0] rlf_level_max,
    input   [7:0] rom_read_count,
    output        osd_active,
    output        osd_credits_req,

    // Virtual-keyboard key event: {make, Set-2 code}, with a strobe that toggles
    // per firmware write so pocket_keyboard pushes exactly one queue entry.
    output  [8:0] vkb_key,
    output        vkb_stb,

    // Machine settings edited in the OSD, driven out to core_top (clk_sys), one output per wired
    // setting; the indices into osd_settings[] below match settings_ui.c's SET_* enum.
    output  [2:0] osd_palette,
    output  [1:0] osd_cpu_speed,
    output  [1:0] osd_bios_wr,
    output  [1:0] osd_boost,
    output  [1:0] osd_spk_vol,
    output  [1:0] osd_stereo,
    output        osd_ems,
    output  [1:0] osd_ems_frame,
    output        osd_a000,
    output  [1:0] osd_gamepad,

    // Per-control key config {ext, Set-2 code}, one 9-bit entry per D-pad direction and button,
    // driven out to pocket_keyboard via core_top. Slot ids are documented at KEYCFG_REG.
    output [16*9-1:0] key_cfg_flat
);

    //
    // CPU clock: gate clk_sys down to one pulse every six cycles, about 8.3 MHz.
    //
    reg [2:0] clk_div;
    always @(posedge clk_sys) begin
        clk_div  <= (clk_div == 3'd5) ? 3'd0 : clk_div + 3'd1;
        clk_pico <= (clk_div == 3'd0);
    end

    //
    // PicoRV32 CPU. RV32IM: the firmware is built for -march=rv32im with no
    // libgcc, so the CPU must provide both the multiplier and the divider. No
    // compressed ISA, no interrupts.
    //
    wire        cpu_mem_valid;
    wire        cpu_mem_instr;
    reg         cpu_mem_ready;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire  [3:0] cpu_mem_wstrb;
    reg  [31:0] cpu_mem_rdata;
    // PicoRV32 trap output, deliberately unmonitored: the softcore should never trap, and
    // Reset PC is the recovery if it somehow does.
    wire        cpu_trap;

    // The built-in timer interrupt drives the OSD service (see the firmware irq handler),
    // so a disk transfer can block without starving the keyboard. No external IRQ lines.
    picorv32 #(
        .COMPRESSED_ISA(0),
        .ENABLE_IRQ(1),
        .ENABLE_MUL(1),
        // No divider. picorv32_pcpi_div was 216 ALMs and this firmware had six
        // division instructions -- two menu wraps and the IDE's LBA-to-CHS
        // maths -- all of which are now compares and a shift-subtract helper
        // (ide_service.c's udiv32). The multiplier stays: seventeen uses, and
        // it is inside the core rather than a separate 216-ALM block. Verified
        // by objdump: the image contains no div/divu/rem/remu.
        .ENABLE_DIV(0)
    ) pico (
        .clk       (clk_pico),
        .resetn    (~reset),
        .trap      (cpu_trap),
        .irq       (32'd0),
        .mem_valid (cpu_mem_valid),
        .mem_instr (cpu_mem_instr),
        .mem_ready (cpu_mem_ready),
        .mem_addr  (cpu_mem_addr),
        .mem_wdata (cpu_mem_wdata),
        .mem_wstrb (cpu_mem_wstrb),
        .mem_rdata (cpu_mem_rdata),
        .pcpi_wr   (1'b0),
        .pcpi_rd   (32'd0),
        .pcpi_wait (1'b0),
        .pcpi_ready(1'b0)
    );

    //
    // Address decode. ROM at 0x0xxxxxxx, work RAM at 0x1xxxxxxx, status/control at
    // 0x2xxxxxxx, the disk bridge at 0x3xxxxxxx, the OSD framebuffer at 0x4xxxxxxx,
    // the OSD font at 0x7xxxxxxx.
    //
    wire sel_rom    = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h0);
    wire sel_ram    = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h1);
    wire sel_status = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h2);
    wire sel_fdd    = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h3);
    wire sel_fb     = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h4);
    // Region 0x5: SDRAM self-test. It gets a region of its own rather than a
    // few spare words in 0x2, because every decode there matches on
    // cpu_mem_addr[4:2] and ignores bit 5 -- 0x20000030 would also have fired
    // OSD_ACTION at 0x20000010, 0x34 the compositor origin, and so on.
    wire sel_st     = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h5);
    // Region 0x7: the OSD font load window (see the font RAM below). Not 0x6:
    // that prefix is the bridge RAM's APF-side address space (FDD_BRIDGE_BASE),
    // which the CPU never addresses directly but which shares a number with it
    // in every datasheet that matters.
    wire sel_font   = cpu_mem_valid && (cpu_mem_addr[31:28] == 4'h7);

    // The drawing server's handshake synchronisers: req/busy cross from the
    // chipset domain (quasi-static -- the engine holds each state for
    // microseconds), and the done LEVEL the engine writes toggles per
    // command; Peripherals edge-detects its synchronized rise.
    logic [7:0] rst_terms_s1 = 8'h00, rst_terms_s2 = 8'h00;
    logic [1:0] draw_req_s1 = 2'b00, draw_req_s = 2'b00;
    logic [1:0] draw_busy_s = 2'b00;
    reg   [1:0] gdc_srv_done_levels_r = 2'b00;
    always @(posedge clk_pico) begin
        rst_terms_s1 <= dbg_reset_terms;
        rst_terms_s2 <= rst_terms_s1;
        draw_req_s1  <= gdc_draw_req;
        draw_req_s   <= draw_req_s1;
        draw_busy_s  <= gdc_draw_busy;
        if (cpu_mem_valid && cpu_mem_wstrb[0] && cpu_mem_addr == 32'h5000_015C)
            gdc_srv_done_levels_r[0] <= cpu_mem_wdata[0];
        if (cpu_mem_valid && cpu_mem_wstrb[0] && cpu_mem_addr == 32'h5000_019C)
            gdc_srv_done_levels_r[1] <= cpu_mem_wdata[0];
    end
    assign gdc_srv_done_levels = gdc_srv_done_levels_r;

    // OSD control at 0x20000004: bit0 = overlay shown.
    reg osd_active_r = 1'b0;
    always @(posedge clk_pico) begin
        if (reset)
            osd_active_r <= 1'b0;
        else if (sel_status && cpu_mem_wstrb[0] && cpu_mem_addr[4:2] == 3'd1)
            osd_active_r <= cpu_mem_wdata[0];
    end
    assign osd_active = osd_active_r;

    // OSD action trigger at 0x20000010: bit1 the credits overlay, bit2 toggles the displayed
    // video card. core_top edge-detects both (the firmware re-arms the register with a zero
    // write before each request). A guest reset is orchestrated through soft_guest_hold below,
    // not here.
    reg osd_credits_req_r = 1'b0;
    always @(posedge clk_pico) begin
        if (reset) begin
            osd_credits_req_r <= 1'b0;
        end else if (sel_status && cpu_mem_wstrb[0] && cpu_mem_addr[4:2] == 3'd4) begin
            osd_credits_req_r <= cpu_mem_wdata[1];
        end
    end
    assign osd_credits_req = osd_credits_req_r;

    // Boot-master guest hold at 0x2000001C: powers up asserted so the guest stays in reset until
    // the firmware releases it (writes 0); the firmware writes 1 to re-assert it for an
    // orchestrated guest reset. Re-armed only by the softcore reset, not a guest reset.
    reg soft_guest_hold_r = 1'b1;
    always @(posedge clk_pico) begin
        if (reset)
            soft_guest_hold_r <= 1'b1;
        else if (sel_status && cpu_mem_wstrb[0] && cpu_mem_addr[4:2] == 3'd7)
            soft_guest_hold_r <= cpu_mem_wdata[0];
    end
    assign soft_guest_hold = soft_guest_hold_r;

    // SDRAM self-test registers, 0x50000000/04/08/0C.
    //   00 W  address[19:0]
    //   04 W  write data[7:0]
    //   08 W  bit0 = start a write, bit1 = start a read
    //   0C R  {busy, rdata[7:0]}
    // clk_pico is clk_chipset gated one-in-six, so st_req is stable for six
    // chipset cycles and core_top's sequencer can sample it directly; the
    // request stays up until st_done returns, which is what stops one firmware
    // write from launching several accesses.
    // The CPU-read snoop's window, address[19:4]. Powers up where each machine
    // had it hardwired, so a build whose firmware never writes this behaves
    // exactly as it always did: the PC-98 reset vector at FFFF, and F D88 -- the
    // PC/AT BIOS entry the bring-up was watching -- otherwise.
    reg [15:0] rom_win_r = 16'hFFFF;
    always @(posedge clk_pico)
        if (sel_st && cpu_mem_wstrb[0] && cpu_mem_ready && cpu_mem_addr[7:0] == 8'h7C)
            rom_win_r <= cpu_mem_wdata[15:0];
    assign rom_win = rom_win_r;

    reg [19:0] st_addr_r  = 20'd0;
    reg  [7:0] st_wdata_r = 8'd0;
    reg        st_we_r    = 1'b0;
    reg        st_req_r   = 1'b0;
    wire       st_trig    = sel_st && cpu_mem_wstrb[0] && cpu_mem_ready
                                   && cpu_mem_addr[3:2] == 2'd2;

    always @(posedge clk_pico) begin
        if (reset) begin
            st_addr_r  <= 20'd0;
            st_wdata_r <= 8'd0;
            st_we_r    <= 1'b0;
            st_req_r   <= 1'b0;
        end else begin
            if (sel_st && cpu_mem_wstrb[0] && cpu_mem_ready && cpu_mem_addr[3:2] == 2'd0)
                st_addr_r <= cpu_mem_wdata[19:0];
            if (sel_st && cpu_mem_wstrb[0] && cpu_mem_ready && cpu_mem_addr[3:2] == 2'd1)
                st_wdata_r <= cpu_mem_wdata[7:0];
            if (st_trig && !st_req_r && (cpu_mem_wdata[1:0] != 2'b00)) begin
                st_we_r  <= cpu_mem_wdata[0];
                st_req_r <= 1'b1;
            end else if (st_req_r && st_done) begin
                st_req_r <= 1'b0;
            end
        end
    end

    assign st_addr  = st_addr_r;
    assign st_wdata = st_wdata_r;
    assign st_we    = st_we_r;
    assign st_req   = st_req_r;

    // Compositor origin at 0x20000014: {y[25:16], x[9:0]}, the raster position of
    // the framebuffer's top-left; the firmware derives it from the presented
    // raster size (read back at 0x20000018).
    reg [9:0] osd_org_x = 10'd0;
    reg [9:0] osd_org_y = 10'd0;
    always @(posedge clk_pico) begin
        if (reset) begin
            osd_org_x <= 10'd0;
            osd_org_y <= 10'd0;
        end else if (sel_status && cpu_mem_wstrb[0] && cpu_mem_addr[4:2] == 3'd5) begin
            osd_org_x <= cpu_mem_wdata[9:0];
            osd_org_y <= cpu_mem_wdata[25:16];
        end
    end

    // Virtual-keyboard key event, written by the firmware at 0x20000008. The CPU
    // holds a store across two clk_pico cycles, so the write is edge-detected to
    // toggle the strobe exactly once; pocket_keyboard reads the strobe directly
    // (clk_pico is a gated clk_sys) and turns each toggle into one queue push.
    wire      vkb_wr = sel_status && cpu_mem_wstrb[0] && cpu_mem_addr[4:2] == 3'd2;
    reg       vkb_wr_d  = 1'b0;
    reg [8:0] vkb_key_r = 9'd0;
    reg       vkb_stb_r = 1'b0;
    always @(posedge clk_pico) begin
        if (reset) begin
            vkb_wr_d  <= 1'b0;
            vkb_key_r <= 9'd0;
            vkb_stb_r <= 1'b0;
        end else begin
            vkb_wr_d <= vkb_wr;
            if (vkb_wr && !vkb_wr_d) begin
                vkb_key_r <= cpu_mem_wdata[8:0];
                vkb_stb_r <= ~vkb_stb_r;
            end
        end
    end
    assign vkb_key = vkb_key_r;
    assign vkb_stb = vkb_stb_r;

    // OSD-edited machine settings, written by the firmware at 0x2000000C as {index[12:8],
    // value[7:0]} into a small register file; the index order matches settings_ui.c's SET_* enum.
    // A plain value latch: the two-cycle PicoRV32 store just writes the same value twice, so no
    // strobe or edge-detect is needed. Only the settings wired to an output leave this module.
    // The file deliberately survives machine resets (registers power up 0): reset-latched
    // consumers like hgc_mode sample it at reset release, before the restarted firmware can
    // re-push values.
    // The index order is the firmware's SET_* enum (settings_ui.c), version 5:
    // the settings whose hardware left the machine (CGA/HGC, video 1st, splash,
    // OPL2, C/MS, composite, the game port pair) are gone from both sides.
    localparam SET_IDX_CPU_SPEED = 5'd0;   // System
    localparam SET_IDX_BIOS_WR   = 5'd1;
    localparam SET_IDX_BOOST     = 5'd2;   // Audio & Video
    localparam SET_IDX_SPK_VOL   = 5'd3;
    localparam SET_IDX_STEREO    = 5'd4;
    localparam SET_IDX_DISPLAY   = 5'd5;
    localparam SET_IDX_EMS       = 5'd6;   // Hardware
    localparam SET_IDX_EMS_FRAME = 5'd7;
    localparam SET_IDX_A000      = 5'd8;
    // index 9 is the D-pad preset, delivered through key_cfg rather than an osd_settings slot.
    localparam SET_IDX_GAMEPAD   = 5'd10;  // Controls
    reg [7:0] osd_settings [0:31];
    wire settings_wr = sel_status && cpu_mem_wstrb[0] && cpu_mem_addr[4:2] == 3'd3;
    always @(posedge clk_pico) begin
        if (settings_wr) begin
            osd_settings[cpu_mem_wdata[12:8]] <= cpu_mem_wdata[7:0];
        end
    end
    assign osd_palette   = osd_settings[SET_IDX_DISPLAY][2:0];
    assign osd_cpu_speed = osd_settings[SET_IDX_CPU_SPEED][1:0];
    assign osd_bios_wr   = osd_settings[SET_IDX_BIOS_WR][1:0];
    assign osd_boost     = osd_settings[SET_IDX_BOOST][1:0];
    assign osd_spk_vol   = osd_settings[SET_IDX_SPK_VOL][1:0];
    assign osd_stereo    = osd_settings[SET_IDX_STEREO][1:0];
    assign osd_ems       = osd_settings[SET_IDX_EMS][0];
    assign osd_ems_frame = osd_settings[SET_IDX_EMS_FRAME][1:0];
    assign osd_a000      = osd_settings[SET_IDX_A000][0];
    assign osd_gamepad   = osd_settings[SET_IDX_GAMEPAD][1:0];

    // Per-control key config, written at KEYCFG_REG (0x20000020) as {id[12:9], ext[8], code[7:0]}.
    // pocket_keyboard reads one 9-bit {ext, code} per D-pad direction (ids 0-3) and button (ids 4-10);
    // the firmware key-binding and D-pad-preset code fill it. Separate from osd_settings so a scancode
    // never shares a byte with an option value.
    reg [8:0] key_cfg [0:15];
    wire keycfg_wr = sel_status && cpu_mem_wstrb[0] && cpu_mem_addr[5:2] == 4'd8;
    always @(posedge clk_pico) begin
        if (keycfg_wr)
            key_cfg[cpu_mem_wdata[12:9]] <= cpu_mem_wdata[8:0];
    end
    genvar ki;
    generate
        for (ki = 0; ki < 16; ki = ki + 1) begin : g_key_cfg
            assign key_cfg_flat[ki*9 +: 9] = key_cfg[ki];
        end
    endgenerate

    //
    // Memory ready. The ROM read is registered, so it needs two clk_pico cycles;
    // RAM completes in one. Any other (undecoded) access still gets a ready, so a
    // stray load or store cannot wedge the CPU.
    //
    reg [1:0] rom_wait_cnt;
    reg       cpu_mem_ready_rom;
    reg       cpu_mem_ready_other;

    always @(posedge clk_pico) begin
        if (reset) begin
            rom_wait_cnt      <= 0;
            cpu_mem_ready_rom <= 0;
        end else if (sel_rom) begin
            if (rom_wait_cnt == 0 && cpu_mem_valid)
                rom_wait_cnt <= 1;
            else if (rom_wait_cnt == 1) begin
                rom_wait_cnt      <= 0;
                cpu_mem_ready_rom <= 1;
            end else
                cpu_mem_ready_rom <= 0;
        end else begin
            rom_wait_cnt      <= 0;
            cpu_mem_ready_rom <= 0;
        end
    end

    always @(posedge clk_pico) begin
        if (reset)
            cpu_mem_ready_other <= 0;
        else
            cpu_mem_ready_other <= ~cpu_mem_ready_other & cpu_mem_valid & ~sel_rom;
    end

    assign cpu_mem_ready = cpu_mem_ready_rom | cpu_mem_ready_other;

    //
    // Firmware ROM: 24 KB (6144 x 32), initialised from the built firmware image.
    // The path is relative to the Quartus project directory (src/fpga).
    //
    wire [31:0] rom_rdata;

    sprom #(
        .aw(13),
        .dw(32),
        // 8192 words = 32 KB. The drawing server (gdc_service.c) needs more
        // than the old 24 KB held; the M10K budget has the room (47% used)
        // and the data_loader's fw_word is 13 bits already.
        .numwords(8192),
        .MEM_INIT_FILE("../firmware/firmware.vh")
    ) pico_rom (
        .clk  (clk_pico),
        .rst  (reset),
        .ce   (sel_rom),
        .oe   (1'b1),
        .addr (cpu_mem_addr[14:2]),
        .dout (rom_rdata),
        .wr_clk  (fw_wr_clk),
        .wr_en   (fw_wr_en),
        .wr_addr (fw_wr_addr),
        .wr_data (fw_wr_data)
    );

    //
    // Work RAM: 2 KB as four byte lanes (512 x 8 each), so byte and halfword
    // stores land through cpu_mem_wstrb. Registered read, one clk_pico of
    // latency.
    //
    // It ran as one 512 x 32 byte-enabled altsyncram for one build, for the
    // two M10K blocks that would save (8 -> 2). Hardware said no: the machine
    // came up black with the guest held, which is what a CPU whose memory
    // returns the wrong bytes looks like -- and byte enables with an
    // unregistered output is exactly the corner a behavioural simulation stub
    // cannot disagree about. Until that corner is understood, the shape that
    // has been on hardware since run#371 is the one that ships: four M10K
    // blocks instead of two, and the difference is not worth a dead machine.
    //
    // The size is the measured one: .data + .bss come to 772 bytes and the
    // deepest stack the image can reach is about 416 bytes -- the 192-byte
    // live chain at its deepest point (main -> gdc_poll, 48+144) plus the
    // 224-byte interrupt chain (irq -> vkb_ui_tick -> settings_input ->
    // vkb_ui_open_picker -> vkb_draw_keyboard -> draw_legendn). Both come from
    // -fstack-usage frames walked over the call graph, and 2 KB leaves a 3x
    // margin over the worst case.
    //
    // The lanes ignore address bits above [10], so a stray access past
    // 0x100007FF aliases here rather than faulting. The linker script's 2K RAM
    // keeps the firmware (and its stack top) inside the window.
    //
    wire [8:0] ram_word_addr = cpu_mem_addr[10:2];

    reg [7:0] ram0 [0:511];
    reg [7:0] ram1 [0:511];
    reg [7:0] ram2 [0:511];
    reg [7:0] ram3 [0:511];

    reg [7:0] ram0_q, ram1_q, ram2_q, ram3_q;

    always @(posedge clk_pico) begin
        if (sel_ram) begin
            if (cpu_mem_wstrb[0]) ram0[ram_word_addr] <= cpu_mem_wdata[7:0];
            if (cpu_mem_wstrb[1]) ram1[ram_word_addr] <= cpu_mem_wdata[15:8];
            if (cpu_mem_wstrb[2]) ram2[ram_word_addr] <= cpu_mem_wdata[23:16];
            if (cpu_mem_wstrb[3]) ram3[ram_word_addr] <= cpu_mem_wdata[31:24];
            ram0_q <= ram0[ram_word_addr];
            ram1_q <= ram1[ram_word_addr];
            ram2_q <= ram2[ram_word_addr];
            ram3_q <= ram3[ram_word_addr];
        end
    end

    wire [31:0] ram_rdata = {ram3_q, ram2_q, ram1_q, ram0_q};

    //
    // OSD framebuffer: full-screen 640x200 at 4bpp (two pixels per byte), four byte lanes. Each
    // lane is one true-dual-port M10K: Port A (clk_sys) is the GPU's read-modify-write, Port B
    // (clk_pix) is the scanout read, both one-cycle reads (unregistered output over the registered
    // address).
    //
    wire [7:0] pa_q [0:3];   // Port A read data per lane (GPU read-modify-write)
    wire [7:0] fbq [0:3];    // Port B read data per lane (scanout)

    genvar fbl;
    generate
        for (fbl = 0; fbl < 4; fbl = fbl + 1) begin : fb_lane
            altsyncram #(
                .operation_mode ("BIDIR_DUAL_PORT"),
                .width_a        (8),
                .widthad_a      (14),
                .numwords_a     (16384),
                .width_b        (8),
                .widthad_b      (14),
                .numwords_b     (16384),
                .address_reg_b  ("CLOCK1"),
                .outdata_reg_a  ("UNREGISTERED"),
                .outdata_reg_b  ("UNREGISTERED"),
                .lpm_type       ("altsyncram"),
                .intended_device_family ("Cyclone V")
            ) fb (
                .clock0    (clk_sys),
                .address_a (pa_addr),
                .data_a    (pa_wd),
                .wren_a    (pa_we[fbl]),
                .q_a       (pa_q[fbl]),

                .clock1    (clk_pix),
                .address_b (osd_word_addr),
                .data_b    (8'd0),
                .wren_b    (1'b0),
                .q_b       (fbq[fbl]),

                .aclr0 (1'b0),
                .aclr1 (1'b0),
                .addressstall_a (1'b0),
                .addressstall_b (1'b0),
                .byteena_a (1'b1),
                .byteena_b (1'b1),
                .clocken0 (1'b1),
                .clocken1 (1'b1),
                .clocken2 (1'b1),
                .clocken3 (1'b1),
                .clock2 (1'b0),
                .clock3 (1'b0),
                .eccstatus (),
                .rden_a (1'b1),
                .rden_b (1'b1)
            );
        end
    endgenerate

    localparam [15:0] OSD_STRIDE = 16'd320; // framebuffer bytes per row (640 / 2)

    //
    // OSD GPU. The CPU no longer writes pixels; it writes drawing commands at 0x4xxxxxxx
    // (clk_pico) and a small FSM renders them into the framebuffer at clk_sys. Command
    // registers:
    //   0x40000000 XY   {y[15:0], x[15:0]}
    //   0x40000004 WH   {h[15:0], w[15:0]}
    //   0x40000008 FILL color[3:0]                  -> fill the XY/WH rectangle
    //   0x40000010 STATUS (read) bit0 = busy
    //   0x40000014 OUTLINE {round, color[3:0]}       -> outline the XY/WH rectangle
    //   0x40000018 CHAR {transp, bg[3:0], fg[3:0], char[7:0]} -> 8x8 glyph at XY
    // A launch write toggles gpu_req; the FSM acknowledges when the command completes.
    // clk_pico is a gated clk_sys pulse, so the parameter registers are stable when the
    // FSM samples them; req/ack cross the domains through two-flop synchronisers.
    //
    localparam [1:0] OP_FILL = 2'd0, OP_OUTLINE = 2'd1, OP_CHAR = 2'd2;

    reg [15:0] gpu_x, gpu_y, gpu_w, gpu_h;
    reg  [3:0] gpu_color;             // FILL/OUTLINE colour, or CHAR foreground
    reg  [3:0] gpu_bg;                // CHAR background (drawn only when not transparent)
    reg  [7:0] gpu_char;              // CHAR glyph index
    reg  [1:0] gpu_op;
    reg        gpu_round;             // OUTLINE: omit the four corner pixels (1px-rounded look)
    reg        gpu_transp;            // CHAR: leave background pixels untouched
    reg        gpu_req;
    // A PicoRV32 store holds the bus for two clk_pico cycles, so a raw write select asserts
    // twice. Committing on cpu_mem_ready (asserted only on the single accept cycle) fires each
    // write once; the launch toggle is edge-detected on top of that so it can never cancel
    // itself, which would leave req == ack, busy stuck low, and any command issued mid-draw
    // dropped. FILL, OUTLINE and CHAR are launches.
    wire gpu_cmd_wr = sel_fb && cpu_mem_wstrb[0] && cpu_mem_ready;
    wire gpu_launch = gpu_cmd_wr && (cpu_mem_addr[4:2] == 3'd2 || cpu_mem_addr[4:2] == 3'd5 ||
                                     cpu_mem_addr[4:2] == 3'd6);
    reg  gpu_launch_d;
    always @(posedge clk_pico) begin
        if (reset) begin
            gpu_req      <= 1'b0;
            gpu_launch_d <= 1'b0;
        end else begin
            gpu_launch_d <= gpu_launch;
            if (gpu_cmd_wr) begin
                case (cpu_mem_addr[4:2])
                    3'd0: begin gpu_x <= cpu_mem_wdata[15:0]; gpu_y <= cpu_mem_wdata[31:16]; end
                    3'd1: begin gpu_w <= cpu_mem_wdata[15:0]; gpu_h <= cpu_mem_wdata[31:16]; end
                    3'd2: begin gpu_color <= cpu_mem_wdata[3:0]; gpu_op <= OP_FILL; end
                    3'd5: begin
                        gpu_color <= cpu_mem_wdata[3:0];
                        gpu_round <= cpu_mem_wdata[4];
                        gpu_op    <= OP_OUTLINE;
                    end
                    3'd6: begin
                        gpu_char   <= cpu_mem_wdata[7:0];
                        gpu_color  <= cpu_mem_wdata[11:8];
                        gpu_bg     <= cpu_mem_wdata[15:12];
                        gpu_transp <= cpu_mem_wdata[16];
                        gpu_op     <= OP_CHAR;
                    end
                    default: ;
                endcase
            end
            if (gpu_launch && !gpu_launch_d) gpu_req <= ~gpu_req; // one toggle per command
        end
    end

    // The command hand-off crosses clocks: gpu_req (clk_pico) is synchronised into clk_sys for
    // the FSM, and the FSM's gpu_ack (clk_sys) is synchronised back so busy = req != ack reads
    // in the CPU's own domain. Each side toggles only its own bit.
    reg gpu_ack;                        // toggled by the FSM (clk_sys)
    reg gpu_ack_s1, gpu_ack_s2;         // gpu_ack -> clk_pico
    always @(posedge clk_pico) begin
        if (reset) {gpu_ack_s2, gpu_ack_s1} <= 2'b00;
        else       {gpu_ack_s2, gpu_ack_s1} <= {gpu_ack_s1, gpu_ack};
    end
    wire [31:0] gpu_status = {31'd0, gpu_req != gpu_ack_s2};

    reg gpu_req_s1, gpu_req_s2;         // gpu_req -> clk_sys
    always @(posedge clk_sys) begin
        if (reset) {gpu_req_s2, gpu_req_s1} <= 2'b00;
        else       {gpu_req_s2, gpu_req_s1} <= {gpu_req_s1, gpu_req};
    end

    //
    // Drawing FSM (clk_sys). Each pixel is one nibble, so the byte is read, the nibble
    // replaced, and written back: GS_RD issues the read, GS_WR writes the modified byte and
    // steps to the next pixel. FILL, OUTLINE and CHAR all walk a rectangle row by row (CHAR a
    // fixed 8x8 cell); OUTLINE writes only the edge pixels and CHAR only the pixels its glyph
    // lights, so each costs a fill of its bounding box. The byte address is an accumulator (row
    // base plus x/2) so there is no per-pixel multiply. A FILL byte that lies fully inside the
    // span is written as one solid byte covering two pixels, so an aligned fill costs one
    // read-write pair per byte instead of one per pixel.
    //
    localparam GS_IDLE = 2'd0, GS_RD = 2'd1, GS_WR = 2'd2;
    reg  [1:0] gs;
    reg [15:0] beg_x, cur_x, end_x, beg_y, cur_y, end_y;
    reg [15:0] row_base, baddr;
    reg        nib;
    reg  [3:0] draw_col, gs_bg;
    reg        gs_outline, gs_round, gs_char, gs_transp;
    reg  [7:0] gs_glyph;
    reg  [2:0] gx, gy;                // glyph-local column/row within the 8x8 cell

    // OSD font RAM: 256 glyphs x 8 rows, one 8-pixel row bitmap per byte (bit 7 = leftmost).
    // Port B (clk_sys) is the glyph read the CHAR op drives; port A (clk_pico) is the
    // firmware's load window at 0x7xxxxxxx, word-addressed with byte enables so any
    // store width lands (the loader's copy uses words; the glyph patch could use bytes).
    // A PicoRV32 store holds the bus for two clk_pico cycles, so each byte is written
    // twice with identical data: idempotent.
    //
    // The contents are deliberately NOT in the bitstream. The font this panel
    // showed was IBM CP437 / NEC font.rom lineage baked in through $readmemh,
    // which put copyrighted glyph data into a public repository and every build
    // artifact. Instead the firmware copies font.rom's 8x8 ANK bank (the first
    // 2 KB of a file the user must already place as a required data slot) into
    // this RAM at boot and patches in this core's own symbol glyphs; until that
    // load the glyphs read as zero, and nothing draws before it (see osd_font.c
    // and main.c's boot order). The CPU-side read serves the same window for
    // bring-up checks.
    // (font_q / font_cpu_q are declared with the font RAM below)

    wire [1:0]  cur_lane = baddr[1:0];
    wire [7:0]  cur_byte = pa_q[cur_lane];   // Port A read of the current lane
    // CHAR paints a glyph's lit pixels in the foreground colour and, when not transparent, the
    // rest in the background; FILL and OUTLINE paint their single colour.
    wire       font_bit = font_q[3'd7 - gx];
    wire [3:0] draw_nib = gs_char ? (font_bit ? draw_col : gs_bg) : draw_col;
    wire [7:0]  cur_byte_mod = nib ? {cur_byte[7:4], draw_nib} : {draw_nib, cur_byte[3:0]};
    wire [13:0] pa_addr = baddr[15:2];
    // A FILL byte fully inside the span (byte-aligned, so this nibble and the next are both
    // filled) is written as one solid byte, both pixels at once. OUTLINE, CHAR and a FILL's
    // ragged first/last nibble take the per-nibble read-modify-write path.
    wire fill_byte = !gs_outline && !gs_char && (nib == 1'b0) && (cur_x < end_x);
    // What each op writes at the current pixel: OUTLINE only the rectangle edges (a rounded
    // outline drops the four corners); CHAR only lit pixels unless it is opaque; FILL every one.
    wire on_edge   = (cur_x == beg_x) || (cur_x == end_x) || (cur_y == beg_y) || (cur_y == end_y);
    wire at_corner = (cur_x == beg_x || cur_x == end_x) && (cur_y == beg_y || cur_y == end_y);
    wire draw_px   = gs_char    ? (font_bit || !gs_transp)
                   : gs_outline ? (on_edge && !(gs_round && at_corner))
                   :              1'b1;
    wire  [3:0] pa_we   = (gs == GS_WR && draw_px) ? (4'd1 << cur_lane) : 4'd0;
    wire  [7:0] pa_wd   = fill_byte ? {draw_col, draw_col} : cur_byte_mod;

    // Font RAM. Four same-width 8-bit lanes -- the pattern the framebuffer
    // above uses -- because Quartus refuses a mixed-width dual port outright
    // (Error 272006: cannot use port A width with port B width), M10K or not.
    // Port A is the CPU load window on clk_pico (byte enables become per-lane
    // wren, so a byte, halfword or word store all land); port B is the GPU's
    // glyph read on clk_sys. All four lanes see the same word address, and the
    // addressed byte is picked out of the four registered lane outputs with a
    // combinational mux, so the glyph row keeps the framebuffer's one-cycle
    // read contract. The CPU's read-back word reassembles the lanes the same
    // way as q_a did.
    wire [7:0] font_q;
    wire [31:0] font_cpu_q;
    // A concatenation cannot be bit-selected directly in Quartus's Verilog
    // front-end (Error 10170 at the "["), so the byte address lands on a wire
    // first and is sliced off it.
    wire [10:0] font_addr = {gs_glyph, gy};
    wire [8:0]  font_waddr = font_addr[10:2];
    wire [1:0]  font_lane  = font_addr[1:0];
    wire [7:0] font_a_lane0, font_a_lane1, font_a_lane2, font_a_lane3;
    wire [7:0] font_b_lane0, font_b_lane1, font_b_lane2, font_b_lane3;

    // Four hand-written instances: Quartus's front-end wants no unpacked-array
    // wires and no generate-conditional assigns here, so plain is plainest.
    altsyncram #(
        .operation_mode ("BIDIR_DUAL_PORT"), .width_a (8), .widthad_a (9),
        .numwords_a (512), .width_b (8), .widthad_b (9), .numwords_b (512),
        .address_reg_b ("CLOCK1"), .outdata_reg_a ("UNREGISTERED"),
        .outdata_reg_b ("UNREGISTERED"), .lpm_type ("altsyncram"),
        .intended_device_family ("Cyclone V")
    ) font_lane0 (
        .clock0 (clk_pico), .address_a (cpu_mem_addr[10:2]),
        .data_a (cpu_mem_wdata[7:0]), .wren_a (sel_font && cpu_mem_wstrb[0]),
        .q_a (font_a_lane0),
        .clock1 (clk_sys), .address_b (font_waddr), .data_b (8'd0),
        .wren_b (1'b0), .q_b (font_b_lane0),
        .aclr0 (1'b0), .aclr1 (1'b0), .addressstall_a (1'b0),
        .addressstall_b (1'b0), .byteena_a (1'b1), .byteena_b (1'b1),
        .clocken0 (1'b1), .clocken1 (1'b1), .clocken2 (1'b1), .clocken3 (1'b1),
        .clock2 (1'b0), .clock3 (1'b0),
        .eccstatus (), .rden_a (1'b1), .rden_b (1'b1)
    );
    altsyncram #(
        .operation_mode ("BIDIR_DUAL_PORT"), .width_a (8), .widthad_a (9),
        .numwords_a (512), .width_b (8), .widthad_b (9), .numwords_b (512),
        .address_reg_b ("CLOCK1"), .outdata_reg_a ("UNREGISTERED"),
        .outdata_reg_b ("UNREGISTERED"), .lpm_type ("altsyncram"),
        .intended_device_family ("Cyclone V")
    ) font_lane1 (
        .clock0 (clk_pico), .address_a (cpu_mem_addr[10:2]),
        .data_a (cpu_mem_wdata[15:8]), .wren_a (sel_font && cpu_mem_wstrb[1]),
        .q_a (font_a_lane1),
        .clock1 (clk_sys), .address_b (font_waddr), .data_b (8'd0),
        .wren_b (1'b0), .q_b (font_b_lane1),
        .aclr0 (1'b0), .aclr1 (1'b0), .addressstall_a (1'b0),
        .addressstall_b (1'b0), .byteena_a (1'b1), .byteena_b (1'b1),
        .clocken0 (1'b1), .clocken1 (1'b1), .clocken2 (1'b1), .clocken3 (1'b1),
        .clock2 (1'b0), .clock3 (1'b0),
        .eccstatus (), .rden_a (1'b1), .rden_b (1'b1)
    );
    altsyncram #(
        .operation_mode ("BIDIR_DUAL_PORT"), .width_a (8), .widthad_a (9),
        .numwords_a (512), .width_b (8), .widthad_b (9), .numwords_b (512),
        .address_reg_b ("CLOCK1"), .outdata_reg_a ("UNREGISTERED"),
        .outdata_reg_b ("UNREGISTERED"), .lpm_type ("altsyncram"),
        .intended_device_family ("Cyclone V")
    ) font_lane2 (
        .clock0 (clk_pico), .address_a (cpu_mem_addr[10:2]),
        .data_a (cpu_mem_wdata[23:16]), .wren_a (sel_font && cpu_mem_wstrb[2]),
        .q_a (font_a_lane2),
        .clock1 (clk_sys), .address_b (font_waddr), .data_b (8'd0),
        .wren_b (1'b0), .q_b (font_b_lane2),
        .aclr0 (1'b0), .aclr1 (1'b0), .addressstall_a (1'b0),
        .addressstall_b (1'b0), .byteena_a (1'b1), .byteena_b (1'b1),
        .clocken0 (1'b1), .clocken1 (1'b1), .clocken2 (1'b1), .clocken3 (1'b1),
        .clock2 (1'b0), .clock3 (1'b0),
        .eccstatus (), .rden_a (1'b1), .rden_b (1'b1)
    );
    altsyncram #(
        .operation_mode ("BIDIR_DUAL_PORT"), .width_a (8), .widthad_a (9),
        .numwords_a (512), .width_b (8), .widthad_b (9), .numwords_b (512),
        .address_reg_b ("CLOCK1"), .outdata_reg_a ("UNREGISTERED"),
        .outdata_reg_b ("UNREGISTERED"), .lpm_type ("altsyncram"),
        .intended_device_family ("Cyclone V")
    ) font_lane3 (
        .clock0 (clk_pico), .address_a (cpu_mem_addr[10:2]),
        .data_a (cpu_mem_wdata[31:24]), .wren_a (sel_font && cpu_mem_wstrb[3]),
        .q_a (font_a_lane3),
        .clock1 (clk_sys), .address_b (font_waddr), .data_b (8'd0),
        .wren_b (1'b0), .q_b (font_b_lane3),
        .aclr0 (1'b0), .aclr1 (1'b0), .addressstall_a (1'b0),
        .addressstall_b (1'b0), .byteena_a (1'b1), .byteena_b (1'b1),
        .clocken0 (1'b1), .clocken1 (1'b1), .clocken2 (1'b1), .clocken3 (1'b1),
        .clock2 (1'b0), .clock3 (1'b0),
        .eccstatus (), .rden_a (1'b1), .rden_b (1'b1)
    );

    reg [7:0] font_q_mux;
    always @* case (font_lane)
        2'd0: font_q_mux = font_b_lane0;
        2'd1: font_q_mux = font_b_lane1;
        2'd2: font_q_mux = font_b_lane2;
        2'd3: font_q_mux = font_b_lane3;
    endcase
    assign font_q     = font_q_mux;
    assign font_cpu_q = {font_a_lane3, font_a_lane2, font_a_lane1, font_a_lane0};

    always @(posedge clk_sys) begin
        if (reset) begin
            gs      <= GS_IDLE;
            gpu_ack <= 1'b0;
        end else begin
            case (gs)
                GS_IDLE:
                    if (gpu_req_s2 != gpu_ack) begin
                        draw_col   <= gpu_color;
                        gs_bg      <= gpu_bg;
                        gs_outline <= (gpu_op == OP_OUTLINE);
                        gs_round   <= gpu_round;
                        gs_char    <= (gpu_op == OP_CHAR);
                        gs_transp  <= gpu_transp;
                        gs_glyph   <= gpu_char;
                        gx         <= 3'd0;
                        gy         <= 3'd0;
                        beg_x      <= gpu_x;
                        cur_x      <= gpu_x;
                        beg_y      <= gpu_y;
                        cur_y      <= gpu_y;
                        end_x      <= (gpu_op == OP_CHAR) ? (gpu_x + 16'd7) : (gpu_x + gpu_w - 16'd1);
                        end_y      <= (gpu_op == OP_CHAR) ? (gpu_y + 16'd7) : (gpu_y + gpu_h - 16'd1);
                        row_base   <= gpu_y * OSD_STRIDE;
                        baddr      <= gpu_y * OSD_STRIDE + {1'b0, gpu_x[15:1]};
                        nib        <= gpu_x[0];
                        gs         <= GS_RD;
                    end
                GS_RD: gs <= GS_WR;
                GS_WR:
                    if (fill_byte ? (cur_x + 16'd1 >= end_x) : (cur_x >= end_x)) begin
                        if (cur_y >= end_y) begin
                            gpu_ack <= ~gpu_ack;
                            gs      <= GS_IDLE;
                        end else begin
                            cur_y    <= cur_y + 16'd1;
                            row_base <= row_base + OSD_STRIDE;
                            cur_x    <= beg_x;
                            baddr    <= row_base + OSD_STRIDE + {1'b0, beg_x[15:1]};
                            nib      <= beg_x[0];
                            gx       <= 3'd0;
                            gy       <= gy + 3'd1;
                            gs       <= GS_RD;
                        end
                    end else if (fill_byte) begin
                        cur_x <= cur_x + 16'd2;         // solid byte covers two pixels
                        baddr <= baddr + 16'd1;
                        gs    <= GS_RD;
                    end else begin
                        cur_x <= cur_x + 16'd1;
                        if (nib) baddr <= baddr + 16'd1;
                        nib   <= ~nib;
                        gx    <= gx + 3'd1;
                        gs    <= GS_RD;
                    end
            endcase
        end
    end

    // Display area: the 640x200 framebuffer drawn 1:1 with its top-left at the compositor
    // origin. The origin is quasi-static, so it crosses into clk_pix through two plain
    // register stages; a word torn mid-change costs at most one frame of a misplaced overlay.
    localparam [9:0] OSD_W = 10'd640;
    localparam [9:0] OSD_H = 10'd200;

    reg [19:0] osd_org_pix_s = 20'd0;
    reg [19:0] osd_org_pix   = 20'd0;
    always @(posedge clk_pix) begin
        osd_org_pix_s <= {osd_org_y, osd_org_x};
        osd_org_pix   <= osd_org_pix_s;
    end

    // Stride 320 bytes/row, so the row offset is a constant multiply.
    wire  [9:0] osd_x = osd_hcnt - osd_org_pix[9:0];                        // 0..639
    wire  [9:0] osd_y = osd_vcnt - osd_org_pix[19:10];                      // 0..199

    wire osd_in_bounds = (osd_hcnt >= osd_org_pix[9:0])  && (osd_x < OSD_W) &&
                         (osd_vcnt >= osd_org_pix[19:10]) && (osd_y < OSD_H);
    wire [15:0] osd_byte_addr = osd_y[7:0] * 16'd320 + {7'd0, osd_x[9:1]};  // y*320 + x/2
    wire [13:0] osd_word_addr = osd_byte_addr[15:2];

    // Port B scanout is the altsyncram's clk_pix side (one-cycle read); the lane/nibble/area
    // selectors are pipelined one stage to match it.
    reg [1:0] osd_lane_r;
    reg       osd_nib_r;
    reg       osd_in_area_r;
    always @(posedge clk_pix) begin
        osd_lane_r    <= osd_byte_addr[1:0];
        osd_nib_r     <= osd_x[0];
        osd_in_area_r <= osd_in_bounds;
    end

    wire [7:0] osd_byte = fbq[osd_lane_r];

    assign osd_palette_idx = osd_nib_r ? osd_byte[3:0] : osd_byte[7:4];
    assign osd_in_area     = osd_in_area_r;

    //
    // Disk bridge: APF dataslot to floppy.v mgmt bus, mapped at 0x3xxxxxxx.
    //
    wire [31:0] fdd_rdata;

    softcpu_fdd_bridge #(
        .BRIDGE_ADDR(32'h60000000)
    ) fdd_bridge (
        .clk_pico   (clk_pico),
        .clk_sys    (clk_sys),
        .clk_74a    (clk_74a),
        .reset      (reset),

        .cpu_valid  (sel_fdd),
        .cpu_addr   (cpu_mem_addr),
        .cpu_wdata  (cpu_mem_wdata),
        .cpu_wstrb  (cpu_mem_wstrb),
        .cpu_rdata  (fdd_rdata),

        .fdd_request(fdd_request),
        .ide0_request(ide0_request),
        .fdd0_disk_size(fdd0_disk_size),
        .fdd1_disk_size(fdd1_disk_size),
        .datatable_addr(datatable_addr),
        .datatable_data(datatable_data),
        .datatable_wren(datatable_wren),
        .datatable_q(datatable_q),
        .fdd0_rebind(fdd0_rebind),
        .fdd1_rebind(fdd1_rebind),

        .mgmt_addr  (mgmt_addr),
        .mgmt_dout  (mgmt_dout),
        .mgmt_wr    (mgmt_wr),
        .mgmt_rd    (mgmt_rd),
        .mgmt_din   (mgmt_din),

        .bridge_wr      (bridge_wr),
        .bridge_addr    (bridge_addr),
        .bridge_wr_data (bridge_wr_data),

        .target_dataslot_read       (target_dataslot_read),
        .target_dataslot_write      (target_dataslot_write),
        .target_dataslot_id         (target_dataslot_id),
        .target_dataslot_slotoffset (target_dataslot_slotoffset),
        .target_dataslot_bridgeaddr (target_dataslot_bridgeaddr),
        .target_dataslot_length     (target_dataslot_length),
        .target_dataslot_ack        (target_dataslot_ack),
        .target_dataslot_done       (target_dataslot_done),
        .target_dataslot_err        (target_dataslot_err),

        .bridge_rd_data_out (bridge_rd_data_out)
    );

    //
    // CPU read mux.
    //
    always_comb begin
        casez (cpu_mem_addr)
            32'h0???_????: cpu_mem_rdata = rom_rdata;
            32'h1???_????: cpu_mem_rdata = ram_rdata;
            32'h2000_0000: cpu_mem_rdata = {3'd0, dock_key_stb, dock_key_ext, dataslots_ready, osd_open_req, credits_active, dock_key_code, cont1_key};
            32'h2000_0018: cpu_mem_rdata = {6'd0, raster_h, 6'd0, raster_w};

            32'h3???_????: cpu_mem_rdata = fdd_rdata;
            32'h4???_????: cpu_mem_rdata = gpu_status;
            32'h7???_????: cpu_mem_rdata = font_cpu_q;
            32'h5000_000C: cpu_mem_rdata = {23'd0, st_req_r, st_rdata};
            // POST monitor, read-only.
            32'h5000_0010: cpu_mem_rdata = {post_count, post_prev, post_code};
            32'h5000_0014: cpu_mem_rdata = {12'd0, post_mem_addr};
            32'h5000_0018: cpu_mem_rdata = post_hist[31:0];    // newest four
            32'h5000_001C: cpu_mem_rdata = post_hist[63:32];   // oldest four
            32'h5000_0020: cpu_mem_rdata = {8'd0, post_max, post_restarts};
            32'h5000_0024: cpu_mem_rdata = {12'd0, post_live_addr};
            32'h5000_0110: cpu_mem_rdata = {post_live_ip, post_live_cs};
            32'h5000_0114: cpu_mem_rdata = {post_derail_ip, post_derail_cs};
            32'h5000_0118: cpu_mem_rdata = {post_land_ip,  post_land_cs};
            32'h5000_011C: cpu_mem_rdata = {post_ring_ip0, post_ring_ip1};
            32'h5000_0120: cpu_mem_rdata = {post_ring_ip2, post_ring_ip3};
            32'h5000_0124: cpu_mem_rdata = {12'd0, post_fr0_data, post_fr0_addr};
            32'h5000_0128: cpu_mem_rdata = {12'd0, post_fr1_data, post_fr1_addr};
            32'h5000_0028: cpu_mem_rdata = {12'd0, post_live_max};
            32'h5000_002C: cpu_mem_rdata = {ivt16_wr_count, ivt16_seg, ivt16_off[15:8]};
            32'h5000_0030: cpu_mem_rdata = {16'd0, ivt16_off};
            // The two FDC vectors: 0x4C/0x4E = INT 13h (2HD), 0x48/0x4A =
            // INT 12h (2DD). Zero throughout means the BIOS never installed
            // the handlers before the drive probe interrupted.
            32'h5000_00C8: cpu_mem_rdata = {ivt13_seg, ivt13_off};
            32'h5000_00CC: cpu_mem_rdata = {ivt12_seg, ivt12_off};
            32'h5000_0034: cpu_mem_rdata = {rd_any_count, wr_any_count};
            32'h5000_003C: cpu_mem_rdata = {12'd0, raw_strobes, ivt_touch_count};
            32'h5000_0040: cpu_mem_rdata = {rd_low_cycles, wr_low_cycles};
            32'h5000_0044: cpu_mem_rdata = rom_read_data[31:0];
            32'h5000_004C: cpu_mem_rdata = rom_read_data[63:32];
            32'h5000_0050: cpu_mem_rdata = rom_read_data[95:64];
            32'h5000_0054: cpu_mem_rdata = rom_read_data[127:96];
            32'h5000_0058: cpu_mem_rdata = rom_load_data[31:0];
            32'h5000_005C: cpu_mem_rdata = rom_load_data[63:32];
            32'h5000_0060: cpu_mem_rdata = rom_load_data[95:64];
            32'h5000_0064: cpu_mem_rdata = rom_load_data[127:96];
            32'h5000_0068: cpu_mem_rdata = {24'd0, rom_load_count};
            32'h5000_006C: cpu_mem_rdata = {rlf_level_max, rlf_drops};
            32'h5000_0070: cpu_mem_rdata = io_port_hist[31:0];    // newest two
            32'h5000_0074: cpu_mem_rdata = io_port_hist[63:32];   // older two
            32'h5000_0078: cpu_mem_rdata = {15'd0, itf_bank, io_wr_count};
            32'h5000_0048: cpu_mem_rdata = {24'd0, rom_read_count};
            32'h5000_007C: cpu_mem_rdata = {16'd0, rom_win_r};
            // [13:0], not [11:0]: the text plane is 0x0000-0x3FFF and twelve
            // bits could not tell byte 0x0F9 from 0x10F9 -- two different rows.
            32'h5000_0080: cpu_mem_rdata = {2'd0, tvram_last_addr[13:0], tvram_wr_count};
            // Row 0's first eight cells, as written. Codes and attributes.
            32'h5000_0084: cpu_mem_rdata = tvram_row0_code[31:0];
            32'h5000_0088: cpu_mem_rdata = tvram_row0_code[63:32];
            32'h5000_008C: cpu_mem_rdata = tvram_row0_attr[31:0];
            32'h5000_0090: cpu_mem_rdata = tvram_row0_attr[63:32];
            // The same cells' HIGH bytes: nonzero = two-byte flagged = the
            // cell renders as kanji. That flag is the whole story of the
            // run#191 screen.
            32'h5000_0094: cpu_mem_rdata = tvram_row0_hi[31:0];
            32'h5000_0098: cpu_mem_rdata = tvram_row0_hi[63:32];
            // The row buffer's own view of row 0's first cells (byte 2n =
            // high, 2n+1 = low), and the kanji fetch path's activity.
            32'h5000_009C: cpu_mem_rdata = pc98_tvfill_view[31:0];
            32'h5000_00A0: cpu_mem_rdata = pc98_tvfill_view[63:32];
            32'h5000_00A4: cpu_mem_rdata = {pc98_rowbuf_fvalid_count,
                                            pc98_rowbuf_freq_count};
            // MSW = A3FEA as the guest read it, SZ = what the ITF recorded at
            // [0501], F0 = OUT 0F0h requests. 04/04/01 is a healthy 640 KB
            // boot; 00/00 and a rising F0 is the MEMORY 128KB loop.
            32'h5000_00A8: cpu_mem_rdata = {8'd0, f0_count, memsize_seen, memsw_seen};
            32'h5000_00AC: cpu_mem_rdata = {8'd0, dbg_gdc_pitch, key_last, key_count};
            // 8 + 8 + 1 + 15 = 32. The first cut of this packed 34 bits into
            // 32 and silently lost the top of unk_count and shifted unk_cmd.
            32'h5000_00B0: cpu_mem_rdata = {dbg_gdc_unk_count, dbg_gdc_unk_cmd,
                                            dbg_gdc_disp_on, dbg_gdc_sad};
            // The cursor's GDC-side registers plus the CSRW/CSRFORM command
            // count, packed ccEaaatb (count, enable, cell, top, bottom) so
            // one hex call on the panel prints it in reading order.
            32'h5000_012C: cpu_mem_rdata = {dbg_gdc_csrcnt, dbg_gdc_cur};
            // The CSRFORM byte trace: {how many, first three bytes after
            // the last 4B}. The panel's CT word.
            32'h5000_0130: cpu_mem_rdata = dbg_gdc_csrtrace;
            // The guest-reset terms, synchronised: {~RESET, reset,
            // interact_reset, bios_ever_loaded, 0, 0, guest_hold_sync2,
            // soft_guest_hold}.
            32'h5000_0134: cpu_mem_rdata = {24'd0, rst_terms_s2};
            // ---- the drawing server --------------------------------------
            // 0x140/0x180: {busy, req, opcode} for master/slave; +4..+0x14:
            // the five snapshot words. 0x15C/0x19C (writes): the done LEVEL
            // -- the engine writes 1 then 0, whose rising edge retires the
            // EXECUTE in the GDC's own domain.
            32'h5000_0140: cpu_mem_rdata = {22'd0, draw_req_s[0],
                                            draw_busy_s[0], gdc_draw_ops[7:0]};
            32'h5000_0144: cpu_mem_rdata = gdc_draw_snaps[31:0];
            32'h5000_0148: cpu_mem_rdata = gdc_draw_snaps[63:32];
            32'h5000_014C: cpu_mem_rdata = gdc_draw_snaps[95:64];
            32'h5000_0150: cpu_mem_rdata = gdc_draw_snaps[127:96];
            32'h5000_0154: cpu_mem_rdata = gdc_draw_snaps[159:128];
            32'h5000_0180: cpu_mem_rdata = {22'd0, draw_req_s[1],
                                            draw_busy_s[1], gdc_draw_ops[15:8]};
            32'h5000_0184: cpu_mem_rdata = gdc_draw_snaps[191:160];
            32'h5000_0188: cpu_mem_rdata = gdc_draw_snaps[223:192];
            32'h5000_018C: cpu_mem_rdata = gdc_draw_snaps[255:224];
            32'h5000_0190: cpu_mem_rdata = gdc_draw_snaps[287:256];
            32'h5000_0194: cpu_mem_rdata = gdc_draw_snaps[319:288];
            32'h5000_00B8: cpu_mem_rdata = {16'd0, dbg_kbd_rd_count, dbg_kbd_irq_count};
            32'h5000_00BC: cpu_mem_rdata = {8'd0,
                                            dbg_timer_count, dbg_irq_level, 8'd0};
            // The master PIC's own three registers -- the last part of the
            // interrupt path a panel could not see.
            32'h5000_00C0: cpu_mem_rdata = {8'd0, dbg_pic_isr,
                                            dbg_pic_imr, dbg_pic_irr};
            // The vector byte the CPU received at the last INTA, and the
            // acknowledge count. 0x12/0x13 = the pair delivered the FDC's
            // handler; 0x0F = the master answered its own cascade line
            // (spurious); anything else = the acknowledge came back wrong.
            32'h5000_00C4: cpu_mem_rdata = {8'd0, dbg_inta_vec,
                                            dbg_inta_count};
            // The drive probe's interrupt, link by link: the slave PIC's
            // own three registers, and the motor timer's arms and pulses.
            // r2/m2/s2 = the slave; MA/MP = motor arms/pulses.
            32'h5000_00D0: cpu_mem_rdata = {8'd0, dbg_pic2_isr,
                                            dbg_pic2_imr, dbg_pic2_irr};
            32'h5000_00D4: cpu_mem_rdata = {8'd0, dbg_chg,
                                            dbg_motor_pulses, dbg_motor_arms};
            // Did the glue's write strobe ever fire, per port, and what
            // was the last control byte it carried?
            // Byte 0 and byte 2, NOT byte 0 and byte 1: postmon reads these
            // as (x & 0xFF) and (x >> 16). Packed adjacent, the second field
            // of each pair read back as a constant zero -- nBE and nD were
            // structurally 00 on every panel that ever showed them, and a
            // whole build was spent explaining a zero that was the readout's
            // own. The other debug words here are read the same way; these
            // two were the pair that disagreed.
            32'h5000_00D8: cpu_mem_rdata = {8'd0, dbg_strb_dat,
                                            8'd0, dbg_strb_cc};
            32'h5000_00DC: cpu_mem_rdata = {8'd0, dbg_strb_be,
                                            8'd0, dbg_strb_94};
            32'h5000_00E0: cpu_mem_rdata = {24'd0, dbg_last_ctrl};
            // The controller itself: byte 0 the MSR the guest last read,
            // byte 1 floppy.v's interrupt rises, byte 2 the DOR it holds,
            // byte 3 the result bytes read back; then the last byte written
            // to 0x94 and to 0xCC, kept apart. Byte-aligned, read as
            // (x >> 8*n) & 0xFF -- see the D8/DC packing bug.
            32'h5000_00EC: cpu_mem_rdata = dbg_fdc_x;
            32'h5000_00F0: cpu_mem_rdata = dbg_fdc_y;
            // The FIFO ring, newest four bytes first. Twelve bytes is the
            // whole conversation at CA 07: seven commands and their
            // parameters, which is what it takes to read the stream rather
            // than guess at its tail.
            32'h5000_00F4: cpu_mem_rdata = dbg_fdc_z[31:0];
            32'h5000_0100: cpu_mem_rdata = dbg_fdc_z[63:32];
            32'h5000_0104: cpu_mem_rdata = dbg_fdc_z[95:64];
            32'h5000_00F8: cpu_mem_rdata = dbg_fdc_w;
            32'h5000_0108: cpu_mem_rdata = dbg_fdc_v;
            // The write path counted in PERIPHERALS: {any-port write
            // strobe, decode clocks} and {write levels, read levels}.
            32'h5000_00E4: cpu_mem_rdata = dbg_w_path;
            32'h5000_00E8: cpu_mem_rdata = dbg_rw_lvl;
            32'h5000_00B4: cpu_mem_rdata = {15'd0, int_live, int_count};
            32'h5000_0038: cpu_mem_rdata = {12'd0, wr_last_addr};
            default:       cpu_mem_rdata = 32'd0;
        endcase
    end

endmodule
