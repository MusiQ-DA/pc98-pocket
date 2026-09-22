//
// PC-98 Chipset (grown out of the MiSTer PCXT base)
// Ported by @spark2k06
//
// Based on chipset written by @kitune-san
//
module CHIPSET #(
        parameter clk_rate = 28'd50000000)
        (
        input   logic           clock,
        input   logic           cpu_ce_posedge,
        input   logic           cpu_ce_negedge,
        input   logic           clk_sys,
        input   logic           peripheral_ce,
        input   logic   [1:0]   clk_select,
        input   logic           reset,
        input   logic           sdram_reset,
        // CPU
        input   logic   [19:0]  cpu_address,
        input   logic   [7:0]   cpu_data_bus,
        // The 16-bit memory path (PC98_WORD_MEM): v30_cpu_bridge asks for a
        // word, RAM.sv turns it into one two-word SDRAM burst instead of two
        // bus cycles, and the odd lane travels on its own pair of wires rather
        // than widening the chipset's eight-bit bus. Tied off in every other
        // build -- see pc98_sdram_map.svh for which addresses can take one.
        input   logic           cpu_word_access,
        input   logic   [7:0]   cpu_data_bus_hi,
        output  logic   [7:0]   data_bus_hi,
        // Sixteen-colour mode, out to core_top for v30_cpu_bridge: it and
        // RAM.sv must agree on whether E0000-E7FFF is memory.
        output  logic           pc98_analog,
        input   logic   [2:0]   processor_status,
        input   logic           processor_lock_n,
        output  logic           processor_transmit_or_receive_n,
        output  logic           processor_ready,
        output  logic           interrupt_to_cpu,
        // SplashScreen
        // VGA
        input   logic           clk_vga_cga,
        // The PC-98 row buffer's own view of text row 0 and its fill counters.
        // PERIPHERALS produces them and softcpu_subsystem serves them to the
        // firmware (0x5000009C/A0/A4); CHIPSET sits between the two and has to
        // carry them, which is what was missing -- core_top connected them to
        // an instance whose module never declared them and Quartus failed on
        // every build since.
        // The master GDC's view, carried for the POST panel. See PERIPHERALS.
        output  logic    [7:0]  dbg_pic_irr,
        output  logic    [7:0]  dbg_pic_imr,
        output  logic    [7:0]  dbg_pic_isr,
        output  logic    [7:0]  dbg_inta_vec,
        output  logic   [15:0]  dbg_inta_count,
        output  logic    [7:0]  dbg_pic2_irr,
        output  logic    [7:0]  dbg_pic2_imr,
        output  logic    [7:0]  dbg_pic2_isr,
        output  logic    [7:0]  dbg_motor_arms,
        output  logic    [7:0]  dbg_motor_pulses,
        output  logic    [7:0]  dbg_chg,
        output  logic    [7:0]  dbg_strb_be,
        output  logic    [7:0]  dbg_strb_94,
        output  logic    [7:0]  dbg_strb_cc,
        output  logic    [7:0]  dbg_strb_dat,
        output  logic    [7:0]  dbg_last_ctrl,
        output  logic   [31:0]  dbg_fdc_x,
        output  logic   [31:0]  dbg_fdc_y,
        output  logic   [95:0]  dbg_fdc_z,
        output  logic   [31:0]  dbg_fdc_w,
        output  logic   [31:0]  dbg_fdc_v,
        output  logic   [15:0]  dbg_w_path,
        output  logic   [15:0]  dbg_rw_lvl,
        output  logic    [7:0]  dbg_irq_level,
        output  logic    [7:0]  dbg_timer_count,
        output  logic    [7:0]  dbg_kbd_irq_count,
        output  logic    [7:0]  dbg_kbd_rd_count,
        output  logic   [14:0]  dbg_gdc_sad,
        output  logic    [7:0]  dbg_gdc_pitch,
        output  logic    [7:0]  dbg_gdc_unk_cmd,
        output  logic    [7:0]  dbg_gdc_unk_count,
        output  logic           dbg_gdc_disp_on,
        // The cursor's registers and the CSRW/CSRFORM arrival count, relayed
        // to the softcore's panel (0x5000012C) the way the fields above are.
        output  logic   [23:0]  dbg_gdc_cur,
        output  logic    [7:0]  dbg_gdc_csrcnt,
        output  logic   [31:0]  dbg_gdc_csrtrace,
        output  logic   [1:0]   gdc_draw_req,
        output  logic   [1:0]   gdc_draw_busy,
        output  logic  [15:0]   gdc_draw_ops,
        output  logic [319:0]   gdc_draw_snaps,
        input   logic   [1:0]   gdc_srv_done_levels,
        output  logic   [63:0]  pc98_tvfill_view,
        output  logic   [15:0]  pc98_rowbuf_freq_count,
        output  logic   [15:0]  pc98_rowbuf_fvalid_count,
        output  logic           de_o,
        output  logic   [5:0]   VID_R,
        output  logic   [5:0]   VID_G,
        output  logic   [5:0]   VID_B,
        output  logic           VID_HSYNC,
        output  logic           VID_VSYNC,
        output  logic           VID_HBlank,
        output  logic           VID_VBlank,
        // I/O Ports
        output  logic   [19:0]  address,
        input   logic   [19:0]  address_ext,
        output  logic           address_direction,
        output  logic   [7:0]   data_bus,
        input   logic   [7:0]   data_bus_ext,
        output  logic           data_bus_direction,
        output  logic           address_latch_enable,
        input   logic           io_channel_check,
        input   logic           io_channel_ready,
        input   logic   [7:0]   interrupt_request,
        output  logic           io_read_n,
        input   logic           io_read_n_ext,
        output  logic           io_read_n_direction,
        output  logic           io_write_n,
        input   logic           io_write_n_ext,
        output  logic           io_write_n_direction,
        output  logic           memory_read_n,
        input   logic           memory_read_n_ext,
        output  logic           memory_read_n_direction,
        output  logic           memory_write_n,
        input   logic           memory_write_n_ext,
        output  logic           memory_write_n_direction,
        input   logic           ext_access_request,
        // Read data for the external-access port. RAM.sv's read byte is
        // otherwise consumed only by the internal bus mux below, so an external
        // master (the BIOS loader, and now the SDRAM self-test) could write but
        // never read back. See docs/P0_SELFTEST_SPEC.md.
        output  logic   [7:0]   data_bus_ext_out,
        input   logic   [3:0]   dma_request,
        output  logic   [3:0]   dma_acknowledge_n,
        output  logic           address_enable_n,
        output  logic           terminal_count_n,
        // Peripherals
        output  logic   [2:0]   timer_counter_out,
        output  logic           speaker_out,
        input   logic   [7:0]   kb_byte,
        input   logic           kb_valid,
        output  logic           kb_ready,
        // JTOPL
        // PC-9801-86 OPNA, stereo, straight from Peripherals to the mixer.
        output  logic signed [15:0] opna_snd_l,
        output  logic signed [15:0] opna_snd_r,
        // C/MS Audio
        // TANDY
        // FONT.ROM load: while font_bank_flag is set, RAM.sv redirects guest
        // addresses above the machine's megabyte, so the loader can write the
        // font where the guest cannot reach it.
        input   logic           font_bank_flag,
        input   logic           font_wr_clk,
        input   logic           font_wr_en,
        input   logic   [10:0]  font_wr_addr,
        input   logic   [15:0]  font_wr_data,
        // UART
        // SDRAM
        input   logic           enable_sdram,
        output  logic           initilized_sdram,
        input   logic           sdram_clock,    // 50MHz
        output  logic   [12:0]  sdram_address,
        output  logic           sdram_cke,
        output  logic           sdram_cs,
        output  logic           sdram_ras,
        output  logic           sdram_cas,
        output  logic           sdram_we,
        output  logic   [1:0]   sdram_ba,
        input   logic   [15:0]  sdram_dq_in,
        output  logic   [15:0]  sdram_dq_out,
        output  logic           sdram_dq_io,
        output  logic           sdram_ldqm,
        output  logic           sdram_udqm,
        // EMS
        input   logic           ems_enabled,
        input   logic   [1:0]   ems_address,
        // BIOS
        input  logic    [1:0]   bios_protect_flag,
        // MMC interface
        input   logic   [1:0]   use_mmc,
        output  logic           spi_clk,
        output  logic           spi_cs,
        output  logic           spi_mosi,
        input   logic           spi_miso,
        // FDD
        input   logic   [15:0]  mgmt_address,
        input   logic           mgmt_read,
        output  logic   [15:0]  mgmt_readdata,
        input   logic           mgmt_write,
        input   logic   [15:0]  mgmt_writedata,
        input   logic   [1:0]   floppy_wp,
        input   logic   [47:0]  rtc_time,
        output  logic   [1:0]   fdd_present,
        output  logic   [1:0]   fdd_request,
        // XTCTL DATA
        // Optional flags
        input   logic           enable_a000h,
        // RAM wait mode
        input   logic           wait_count_clk_en,
        input   logic   [1:0]   ram_read_wait_cycle,
        input   logic   [1:0]   ram_write_wait_cycle,
        // Others
        output  logic           pause_core,
        input   logic   [3:0]   crt_h_offset,
        input   logic   [2:0]   crt_v_offset,
        input   logic   [2:0]   vsync_width_osd,
        input   logic   [2:0]   hsync_width_osd,
        // PC-98 keyboard injection, passed to PERIPHERALS' 8251 model.
        input   logic           pc98_key_stb,
        input   logic   [7:0]   pc98_key_byte,
        // ROM-load (Pocket): expose the RAM access-complete pulse so core_top's
        // BIOS loader can pace on the real SDRAM write instead of a fixed delay.
        output  logic           ram_rw_complete

    );

	 logic   [19:0]  latch_address;
	 
    logic           dma_ready;
    logic           dma_wait_n;
    logic           interrupt_acknowledge_n;
    logic           dma_chip_select_n;
    logic           dma_page_chip_select_n;
    logic           memory_access_ready;
    logic           ram_address_select_n;
    logic   [7:0]   internal_data_bus;
    logic   [7:0]   internal_data_bus_ext;
    logic   [7:0]   internal_data_bus_chipset;
    logic   [7:0]   internal_data_bus_ram;
    logic           data_bus_out_from_chipset;
    logic           internal_data_bus_direction;
    logic           no_command_state;

    logic           prev_timer_count_1;
    logic           DRQ0;

    logic   [6:0]   map_ems[0:3];
    logic           ena_ems[0:3];
    logic           ems_b1;
    logic           ems_b2;
    logic           ems_b3;
    logic           ems_b4;
    logic           fdd_dma_req;


    always_ff @(posedge clock)
    begin
        if (reset)
            prev_timer_count_1 <= 1'b1;
        else
            prev_timer_count_1 <= timer_counter_out[1];
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            DRQ0 <= 1'b0;
        else if (~dma_acknowledge_n[0])
            DRQ0 <= 1'b0;
        else if (~prev_timer_count_1 & timer_counter_out[1])
            DRQ0 <= 1'b1;
        else
            DRQ0 <= DRQ0;
    end

    // tandy_snd_rdy was ANDed in here and, on a PC-98 build, was 1'b1 by
    // construction (`ENABLE_TANDY_AUDIO ? ... : 1'b1`). The XT hardware's
    // removal deleted the PERIPHERALS output that drove it but left this
    // use, and an undriven net synthesises to GND -- io_channel_ready
    // became a constant zero, processor_ready never asserted, and the CPU
    // hung forever on its first cycle (LIVE pinned at FFFF0, no fetches,
    // PC frozen in its reset state). The term was the Tandy sound's, and
    // the Tandy sound is gone; the expression keeps the two that remain.
    READY u_READY 
    (
        .clock                              (clock),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .processor_ready                    (processor_ready),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .io_channel_ready                   (io_channel_ready & memory_access_ready),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .dma0_acknowledge_n                 (dma_acknowledge_n[0]),
        .address_enable_n                   (address_enable_n)
    );

    BUS_ARBITER u_BUS_ARBITER 
    (
        .clock                              (clock),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .cpu_address                        (cpu_address),
        .cpu_data_bus                       (cpu_data_bus),
        .processor_status                   (processor_status),
        .processor_lock_n                   (processor_lock_n),
        .processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .address                            (address),
        .address_ext                        (address_ext),
        .address_direction                  (address_direction),
        .data_bus_ext                       (internal_data_bus_ext),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_direction                 (internal_data_bus_direction),
        .address_latch_enable               (address_latch_enable),
        .io_read_n                          (io_read_n),
        .io_read_n_ext                      (io_read_n_ext),
        .io_read_n_direction                (io_read_n_direction),
        .io_write_n                         (io_write_n),
        .io_write_n_ext                     (io_write_n_ext),
        .io_write_n_direction               (io_write_n_direction),
        .memory_read_n                      (memory_read_n),
        .memory_read_n_ext                  (memory_read_n_ext),
        .memory_read_n_direction            (memory_read_n_direction),
        .memory_write_n                     (memory_write_n),
        .memory_write_n_ext                 (memory_write_n_ext),
        .memory_write_n_direction           (memory_write_n_direction),
        .no_command_state                   (no_command_state),
        .ext_access_request                 (ext_access_request),
        .dma_request                        ({dma_request[3], fdd_dma_req, dma_request[1], DRQ0}),
        .dma_acknowledge_n                  (dma_acknowledge_n),
        .address_enable_n                   (address_enable_n),
        .terminal_count_n                   (terminal_count_n)
    );

    // Video-side glyph reads, RAM.sv's port B out to PERIPHERALS.
    wire        font_rd_req, font_rd_ack, font_rd_valid, font_rd_done;
    wire [23:0] font_rd_addr;
    wire  [3:0] font_rd_len;
    wire [15:0] font_rd_data;
    wire        cg_rd_req, cg_rd_ack, cg_rd_valid, cg_rd_done;
    wire [23:0] cg_rd_addr;
    wire  [3:0] cg_rd_len;
    wire [15:0] cg_rd_data;

    PERIPHERALS #(.clk_rate(clk_rate)) u_PERIPHERALS 
    (
        .font_rd_req                        (font_rd_req),
        .font_rd_addr                       (font_rd_addr),
        .font_rd_len                        (font_rd_len),
        .font_rd_ack                        (font_rd_ack),
        .font_rd_valid                      (font_rd_valid),
        .font_rd_data                       (font_rd_data),
        .font_rd_done                       (font_rd_done),
        .cg_rd_req                          (cg_rd_req),
        .cg_rd_addr                         (cg_rd_addr),
        .cg_rd_len                          (cg_rd_len),
        .cg_rd_ack                          (cg_rd_ack),
        .cg_rd_valid                        (cg_rd_valid),
        .cg_rd_data                         (cg_rd_data),
        .cg_rd_done                         (cg_rd_done),
        .font_wr_clk                        (font_wr_clk),
        .font_wr_en                         (font_wr_en),
        .font_wr_addr                       (font_wr_addr),
        .font_wr_data                       (font_wr_data),
        .clock                              (clock),
        .pc98_analog                        (pc98_analog),
        .grcg_active                        (grcg_active),
        .grcg_rmw                           (grcg_rmw),
        .grcg_mask                          (grcg_mask),
        .grcg_tile                          (grcg_tile),
        .gvram_disp_page                    (gvram_disp_page_w),
        .gvram_access_page                  (gvram_access_page_w),
        .egc_active                         (egc_active_w),
        .egc_wr                             (egc_wr_w),
        .egc_rg                             (egc_rg_w),
        .egc_d                              (egc_d_w),
        .clk_sys                            (clk_sys),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .clk_select                         (clk_select),
        .reset                              (reset),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .clk_vga_cga                        (clk_vga_cga),
        .de_o                               (de_o),
        .dbg_pic_irr                        (dbg_pic_irr),
        .dbg_pic_imr                        (dbg_pic_imr),
        .dbg_pic_isr                        (dbg_pic_isr),
        .dbg_inta_vec                       (dbg_inta_vec),
        .dbg_inta_count                     (dbg_inta_count),
        .dbg_pic2_irr                       (dbg_pic2_irr),
        .dbg_pic2_imr                       (dbg_pic2_imr),
        .dbg_pic2_isr                       (dbg_pic2_isr),
        .dbg_motor_arms                     (dbg_motor_arms),
        .dbg_motor_pulses                   (dbg_motor_pulses),
        .dbg_chg                         (dbg_chg),
        .dbg_strb_be                     (dbg_strb_be),
        .dbg_strb_94                     (dbg_strb_94),
        .dbg_strb_cc                     (dbg_strb_cc),
        .dbg_strb_dat                     (dbg_strb_dat),
        .dbg_last_ctrl                   (dbg_last_ctrl),
        .dbg_fdc_x                       (dbg_fdc_x),
        .dbg_fdc_y                       (dbg_fdc_y),
        .dbg_fdc_z                       (dbg_fdc_z),
        .dbg_fdc_w                       (dbg_fdc_w),
        .dbg_fdc_v                       (dbg_fdc_v),
        .dbg_w_path                      (dbg_w_path),
        .dbg_rw_lvl                      (dbg_rw_lvl),
        .dbg_irq_level                      (dbg_irq_level),
        .dbg_timer_count                    (dbg_timer_count),
        .dbg_kbd_irq_count                  (dbg_kbd_irq_count),
        .dbg_kbd_rd_count                   (dbg_kbd_rd_count),
        .dbg_gdc_sad                        (dbg_gdc_sad),
        .dbg_gdc_pitch                      (dbg_gdc_pitch),
        .dbg_gdc_unk_cmd                    (dbg_gdc_unk_cmd),
        .dbg_gdc_unk_count                  (dbg_gdc_unk_count),
        .dbg_gdc_disp_on                    (dbg_gdc_disp_on),
        .dbg_gdc_cur                        (dbg_gdc_cur),
        .dbg_gdc_csrcnt                     (dbg_gdc_csrcnt),
        .dbg_gdc_csrtrace                   (dbg_gdc_csrtrace),
        .gdc_draw_req                       (gdc_draw_req),
        .gdc_draw_busy                      (gdc_draw_busy),
        .gdc_draw_ops                       (gdc_draw_ops),
        .gdc_draw_snaps                     (gdc_draw_snaps),
        .gdc_srv_done_levels                (gdc_srv_done_levels),
        .pc98_tvfill_view                   (pc98_tvfill_view),
        .pc98_rowbuf_freq_count             (pc98_rowbuf_freq_count),
        .pc98_rowbuf_fvalid_count           (pc98_rowbuf_fvalid_count),
        .VID_R                              (VID_R),
        .VID_G                              (VID_G),
        .VID_B                              (VID_B),
        .VID_HSYNC                          (VID_HSYNC),
        .VID_VSYNC                          (VID_VSYNC),
        .VID_HBlank                         (VID_HBlank),
        .VID_VBlank                         (VID_VBlank),
        .address                            (address),
	    .latch_address                      (latch_address),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_out                       (internal_data_bus_chipset),
        .data_bus_out_from_chipset          (data_bus_out_from_chipset),
        .interrupt_request                  (interrupt_request),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .memory_write_n                     (memory_write_n),
        .address_enable_n                   (address_enable_n),
        .timer_counter_out                  (timer_counter_out),
        .speaker_out                        (speaker_out),
        .kb_byte                            (kb_byte),
        .kb_valid                           (kb_valid),
        .kb_ready                           (kb_ready),
        .opna_snd_l                         (opna_snd_l),
        .opna_snd_r                         (opna_snd_r),
        .ems_enabled                       (ems_enabled),
        .ems_address                       (ems_address),
        .map_ems                           (map_ems),
        .ena_ems                           (ena_ems),
        .ems_b1                            (ems_b1),
        .ems_b2                            (ems_b2),
        .ems_b3                            (ems_b3),
        .ems_b4                            (ems_b4),
        .use_mmc                            (use_mmc),
        .spi_clk                            (spi_clk),
        .spi_cs                             (spi_cs),
        .spi_mosi                           (spi_mosi),
        .spi_miso                           (spi_miso),
        .mgmt_address                       (mgmt_address),
        .mgmt_read                          (mgmt_read),
        .mgmt_readdata                      (mgmt_readdata),
        .mgmt_write                         (mgmt_write),
        .mgmt_writedata                     (mgmt_writedata),
        .floppy_wp                          (floppy_wp),
        .rtc_time                           (rtc_time),
        .fdd_present                        (fdd_present),
        .fdd_request                        (fdd_request),
        .fdd_dma_req                        (fdd_dma_req),
        .fdd_dma_ack                        (~dma_acknowledge_n[2]),
        .terminal_count                     (terminal_count_n),
        .pause_core                         (pause_core),
        .crt_h_offset                       (crt_h_offset),
        .crt_v_offset                       (crt_v_offset),
        .vsync_width_osd                    (vsync_width_osd),
        .hsync_width_osd                    (hsync_width_osd)
        ,.pc98_key_stb                      (pc98_key_stb)
        ,.pc98_key_byte                     (pc98_key_byte)
    );

    // ---- the GRCG's plane expansion, ahead of RAM.sv -------------------
    //
    // pc98_gvram_seq turns one guest access to a graphics window into one per
    // unmasked plane -- two per plane in RMW mode -- and holds the guest off
    // until the last one lands. RAM.sv is not changed: the sequencer drives
    // its one-byte interface repeatedly, which is what the module was shaped
    // to do rather than surgery on the path that boots the machine.
    //
    // TRANSPARENT WITH THE GRCG OFF, which is how it comes out of reset: the
    // request goes straight through and cpu_ready is RAM.sv's own
    // memory_access_ready, unchanged. That is the property that makes this
    // safe to insert before anything uses it.
    wire        grcg_active, grcg_rmw;
    wire [3:0]  grcg_mask;
    wire [7:0]  grcg_tile [0:3];

    // The graphics pages and the EGC, PERIPHERALS to the sequencer.
    wire        gvram_disp_page_w, gvram_access_page_w;
    wire        egc_active_w, egc_wr_w;
    wire [3:0]  egc_rg_w;
    wire [7:0]  egc_d_w;
    wire        gvram_mem_page1;

    wire [19:0] ram_addr_w;
    wire [7:0]  ram_wdata_w;
    wire        ram_rd_w, ram_wr_w;
    wire [7:0]  ram_dout_w;
    wire        ram_complete_w, ram_ready_w;
    wire        gvram_sel = ~ram_address_select_n;

    pc98_gvram_seq u_gvram_seq (
        .clk(sdram_clock), .reset(sdram_reset),
        .cpu_gvram(gvram_sel),
        .cpu_rd(~memory_read_n), .cpu_wr(~memory_write_n),
        .cpu_addr(latch_address), .cpu_wdata(internal_data_bus),
        .cpu_rdata(internal_data_bus_ram), .cpu_ready(memory_access_ready),
        .grcg_active(grcg_active), .grcg_rmw(grcg_rmw),
        .grcg_mask(grcg_mask), .grcg_tile(grcg_tile),
        .analog_mode(pc98_analog),
        .access_page(gvram_access_page_w), .mem_page1(gvram_mem_page1),
        .egc_active(egc_active_w), .egc_wr(egc_wr_w),
        .egc_rg(egc_rg_w), .egc_d(egc_d_w),
        .mem_addr(ram_addr_w), .mem_wdata(ram_wdata_w),
        .mem_rd(ram_rd_w), .mem_wr(ram_wr_w),
        .mem_rdata(ram_dout_w), .mem_done(ram_complete_w),
        .mem_ready(ram_ready_w)
    );

    // The ROM loader's per-access done pulse still comes from RAM.sv itself:
    // it writes E8000-FFFFF, which is never a graphics window, so it takes the
    // sequencer's pass-through and sees the memory's own completion.
    assign ram_rw_complete = ram_complete_w;

    RAM u_RAM 
    (
        .gvram_page1_flag                   (gvram_mem_page1),
        .font_bank_flag                     (font_bank_flag),
        .font_rd_req                        (font_rd_req),
        .font_rd_addr                       (font_rd_addr),
        .font_rd_len                        (font_rd_len),
        .font_rd_ack                        (font_rd_ack),
        .font_rd_valid                      (font_rd_valid),
        .font_rd_data                       (font_rd_data),
        .font_rd_done                       (font_rd_done),
        .cg_rd_req                          (cg_rd_req),
        .cg_rd_addr                         (cg_rd_addr),
        .cg_rd_len                          (cg_rd_len),
        .cg_rd_ack                          (cg_rd_ack),
        .cg_rd_valid                        (cg_rd_valid),
        .cg_rd_data                         (cg_rd_data),
        .cg_rd_done                         (cg_rd_done),
        .clock                              (sdram_clock),
        .reset                              (sdram_reset),
        .enable_sdram                       (enable_sdram),
        .initilized_sdram                   (initilized_sdram),
        .address                            (ram_addr_w),
        .internal_data_bus                  (ram_wdata_w),
        .data_bus_out                       (ram_dout_w),
        .analog_mode                        (pc98_analog),
        .word_access                        (cpu_word_access),
        .internal_data_bus_hi               (cpu_data_bus_hi),
        .data_bus_out_hi                    (data_bus_hi),
        .memory_read_n                      (~ram_rd_w),
        .memory_write_n                     (~ram_wr_w),
        .no_command_state                   (no_command_state),
        .memory_access_ready                (ram_ready_w),
        .access_complete                    (ram_complete_w),
        .ram_address_select_n               (ram_address_select_n),
        .sdram_address                      (sdram_address),
        .sdram_cke                          (sdram_cke),
        .sdram_cs                           (sdram_cs),
        .sdram_ras                          (sdram_ras),
        .sdram_cas                          (sdram_cas),
        .sdram_we                           (sdram_we),
        .sdram_ba                           (sdram_ba),
        .sdram_dq_in                        (sdram_dq_in),
        .sdram_dq_out                       (sdram_dq_out),
        .sdram_dq_io                        (sdram_dq_io),
        .sdram_ldqm                         (sdram_ldqm),
        .sdram_udqm                         (sdram_udqm),
        .map_ems                            (map_ems),
        .ems_b1                             (ems_b1),
        .ems_b2                             (ems_b2),
        .ems_b3                             (ems_b3),
        .ems_b4                             (ems_b4),
        .bios_protect_flag                  (bios_protect_flag),
        .enable_a000h                       (enable_a000h),
        .wait_count_clk_en                  (wait_count_clk_en),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle)
    );

    assign  data_bus = internal_data_bus;

    // Straight tap on RAM.sv's read byte, valid while the RAM read is in
    // flight; the external master latches it on ram_rw_complete.
    assign  data_bus_ext_out = internal_data_bus_ram;

    always_comb
    begin
        if (data_bus_out_from_chipset)
        begin
            internal_data_bus_ext = internal_data_bus_chipset;
            data_bus_direction    = 1'b0;
        end
        else if ((~ram_address_select_n) && (~memory_read_n))
        begin
            internal_data_bus_ext = internal_data_bus_ram;
            data_bus_direction    = 1'b0;
        end
        // The empty option-ROM window. C0000-E7FFF is deliberately not
        // served by the SDRAM (RAM.sv's map), so reads here used to fall
        // through to the external-bus branch below and return whatever the
        // loader had last written there -- residue the POST's option-ROM
        // scan can mistake for a 55 AA signature, and it CALLS into it.
        // The metal derailed exactly there: FD80:27C4 `call far [4AC]`
        // with [4AE]=D200, landing in garbage RAM (landing CS D200, then
        // soup). An empty slot on the real machine reads open bus; answer
        // 0xFF so the scan's signature check never matches and the POST
        // falls through to IVT[1E] and BASIC.
        else if ((~memory_read_n) && (address[19:16] >= 4'hC)
                                          && (address[19:15] < 5'b11101))
        begin
            internal_data_bus_ext = 8'hFF;
            data_bus_direction    = 1'b0;
        end
        else
        begin
            if (internal_data_bus_direction == 1'b1)
            begin
                internal_data_bus_ext = data_bus_ext;
                data_bus_direction    = 1'b1;
            end
            else
            begin
                internal_data_bus_ext = 0;
                data_bus_direction    = 1'b0;
            end
        end
    end

endmodule

