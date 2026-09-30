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
        // PC-98 video
        input   logic           clk_pc98_dot,
        output  logic   [1:0]   gdc_draw_req,
        output  logic   [1:0]   gdc_draw_busy,
        output  logic  [15:0]   gdc_draw_ops,
        output  logic [319:0]   gdc_draw_snaps,
        input   logic   [1:0]   gdc_srv_done_levels,
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
        input   logic   [3:0]   dma_request,
        output  logic   [3:0]   dma_acknowledge_n,
        output  logic           address_enable_n,
        output  logic           terminal_count_n,
        // JTAG probe (PC98_JTAG): arbiter hold/DRQ view and RAM.sv's FSM
        // state, out to core_top's probe. Unconsumed they synthesise away.
        output  logic   [15:0]  dbg_chipset,
        output  logic   [7:0]   dbg_chipset2,
        // Peripherals
        output  logic   [2:0]   timer_counter_out,
        output  logic           speaker_out,
        input   logic   [7:0]   kb_byte,
        input   logic           kb_valid,
        output  logic           kb_ready,
        // PC-9801-86 OPNA, stereo, straight from Peripherals to the mixer.
        output  logic signed [15:0] opna_snd_l,
        output  logic signed [15:0] opna_snd_r,
        // FONT.ROM load: while font_bank_flag is set, RAM.sv redirects guest
        // addresses above the machine's megabyte, so the loader can write the
        // font where the guest cannot reach it.
        input   logic           font_bank_flag,
        // ITF shadow: while set, RAM.sv banks F8000-FFFFF to the copy at
        // 1F8000. core_top drives it -- the loader for the ITF write, the
        // guest's port 0x043D afterwards.
        input   logic           bios_shadow_flag,
        input   logic           font_wr_clk,
        input   logic           font_wr_en,
        input   logic   [11:0]  font_wr_addr,
        input   logic   [15:0]  font_wr_data,
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
        // EMS board (pc98_ems98): how many megabytes it reports fitted --
        // the OSD's extended-memory capacity.
        input   logic   [3:0]   ems98_maxmem,
        // BIOS
        input  logic    [1:0]   bios_protect_flag,
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
        output  logic           scsi_request,
        // JTAG probe: the floppy engine's transfer state and live command.
        output  wire    [63:0]  dbg_fdc,
        output  wire    [63:0]  dbg_fdc_cmd,
        // RAM wait mode
        input   logic           wait_count_clk_en,
        input   logic   [1:0]   ram_read_wait_cycle,
        input   logic   [1:0]   ram_write_wait_cycle,
        // Others
        output  logic           pause_core,
        // PC-98 keyboard injection, passed to PERIPHERALS' 8251 model.
        input   logic           pc98_key_stb,
        input   logic   [7:0]   pc98_key_byte,
        // Bus mouse: the shared pc98_mouse_src stream out of core_top.
        input   logic signed [15:0] mouse_dx,
        input   logic signed [15:0] mouse_dy,
        input   logic               mouse_ev,
        input   logic   [1:0]       mouse_btn,
        // -86 board joystick port byte, active low (np21w joymng.h order).
        input   logic   [7:0]       opna_joy,
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
    wire    [7:0]   scsi_rom_hi;
    logic           data_bus_out_from_chipset;
    logic           internal_data_bus_direction;
    logic           no_command_state;

    logic           prev_timer_count_1;
    logic           DRQ0;

    // The EMS board (pc98_ems98): ports 08E1h-08E9h bank four 16 KB
    // windows at C0000-CFFFF into the SDRAM pool at 0x800000-0xFFFFFF.
    // On a V30 this banking is the only way past the 20-bit bus, so this is
    // what "extended memory" means here -- details in pc98_ems98.sv.
    logic   [10:0]  ems98_map[0:3];
    logic   [7:0]   ems98_status;
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
    // io_channel_ready used to AND in a third term whose producer is gone;
    // an undriven net synthesised to GND, processor_ready never asserted, and
    // the CPU hung on its first cycle (LIVE pinned at FFFF0, no fetches). The
    // expression keeps the two terms that remain.
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
        .dbg                                (arb_dbg),
        // DRQ is active-low on the PC-98 bus (the data book names the pins
        // DRQ3O..DRQ0O) and the BIOS programs the 71071's DREQ sense bit
        // (0x11 bit6) to match. The sources here are active-high "request
        // present" logic, so they are inverted onto the pin: a pin at zero
        // is a request, and a tied-off dma_request[] input idles high.
        .dma_request                        (~{fdd_dma_req | dma_request[3], fdd_dma_req, dma_request[1], DRQ0}),
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
    wire        gv_rd_req, gv_rd_ack, gv_rd_valid, gv_rd_done;
    wire [23:0] gv_rd_addr;
    wire  [3:0] gv_rd_len;
    wire [15:0] gv_rd_data;

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
        .gv_rd_req                          (gv_rd_req),
        .gv_rd_addr                         (gv_rd_addr),
        .gv_rd_len                          (gv_rd_len),
        .gv_rd_ack                          (gv_rd_ack),
        .gv_rd_valid                        (gv_rd_valid),
        .gv_rd_data                         (gv_rd_data),
        .gv_rd_done                         (gv_rd_done),
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
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .clk_select                         (clk_select),
        .reset                              (reset),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .clk_pc98_dot                       (clk_pc98_dot),
        .de_o                               (de_o),
        .gdc_draw_req                       (gdc_draw_req),
        .gdc_draw_busy                      (gdc_draw_busy),
        .gdc_draw_ops                       (gdc_draw_ops),
        .gdc_draw_snaps                     (gdc_draw_snaps),
        .gdc_srv_done_levels                (gdc_srv_done_levels),
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
        .scsi_rom_hi                        (scsi_rom_hi),
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
        .mgmt_address                       (mgmt_address),
        .mgmt_read                          (mgmt_read),
        .mgmt_readdata                      (mgmt_readdata),
        .mgmt_write                         (mgmt_write),
        .mgmt_writedata                     (mgmt_writedata),
        .floppy_wp                          (floppy_wp),
        .rtc_time                           (rtc_time),
        .fdd_present                        (fdd_present),
        .fdd_request                        (fdd_request),
        .scsi_request                       (scsi_request),
        .fdd_dma_req                        (fdd_dma_req),
        .dbg_fdc                            (dbg_fdc),
        .dbg_fdc_cmd                        (dbg_fdc_cmd),
        // The BIOS runs 2HD (0x90 window) transfers on channel 2 and 2DD
        // (0xC8 window) on channel 3 -- the arbiter pairs ack[2] with page
        // register 1 (port 0x23) and ack[3] with page register 2 (0x25),
        // which is exactly what the two setup paths program.
        .fdd_dma_ack                        (~dma_acknowledge_n[2] | ~dma_acknowledge_n[3]),
        .terminal_count                     (terminal_count_n),
        .pause_core                         (pause_core)
        ,.pc98_key_stb                      (pc98_key_stb)
        ,.pc98_key_byte                     (pc98_key_byte)
        ,.mouse_dx                          (mouse_dx)
        ,.mouse_dy                          (mouse_dy)
        ,.mouse_ev                          (mouse_ev)
        ,.mouse_btn                         (mouse_btn)
        ,.opna_joy                          (opna_joy)
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
    wire [7:0]  ram_dout_hi_w;
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
        .bios_shadow_flag                   (bios_shadow_flag),
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
        .gv_rd_req                          (gv_rd_req),
        .gv_rd_addr                         (gv_rd_addr),
        .gv_rd_len                          (gv_rd_len),
        .gv_rd_ack                          (gv_rd_ack),
        .gv_rd_valid                        (gv_rd_valid),
        .gv_rd_data                         (gv_rd_data),
        .gv_rd_done                         (gv_rd_done),
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
        .data_bus_out_hi                    (ram_dout_hi_w),
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
        .ems98_map                          (ems98_map),
        .bios_protect_flag                  (bios_protect_flag),
        .wait_count_clk_en                  (wait_count_clk_en),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle),
        .dbg                                (ram_dbg)
    );

    // JTAG probe bundle: {arbiter hold/DRQ, RAM FSM state} plus the wait
    // chain -- proc_ready is the term the CPU actually waits on.
    wire [7:0] arb_dbg, ram_dbg;
    assign  dbg_chipset  = {arb_dbg, ram_dbg};
    assign  dbg_chipset2 = {processor_ready, memory_access_ready, dma_ready,
                            dma_acknowledge_n[3:0], no_command_state};

    // The NEC EMS board's register half. Its port decode sits on the live
    // bus (same convention as PERIPHERALS); the window state it produces is
    // consumed inside RAM.sv's address latch. SDRAM_CLK == clock, so there
    // is no domain crossing on ems98_map.
    pc98_ems98 u_ems98 (
        .clock                              (clock),
        .reset                              (reset),
        .address                            (address),
        .internal_data_bus                  (internal_data_bus),
        .io_write_n                         (io_write_n),
        .address_enable_n                   (address_enable_n),
        .maxmem                             (ems98_maxmem),
        .map                                (ems98_map),
        .status                             (ems98_status)
    );

    assign  data_bus = internal_data_bus;



    // The odd lane inside the option ROM. Reads here must answer on
    // both lanes the way SDRAM does: the high lane always carries the
    // byte at addr|1, which covers word fetches (aligned pair) and byte
    // reads at odd addresses (BHE selects this lane) such as the
    // signature's 55h at offset 9. Undecoded space reports 0 here, so
    // without the injection the ROM's odd bytes never reach the CPU.
    wire xrom_read = (~memory_read_n) && (address[19:8] == 12'hD00);
    // The SCSI option ROM at D2000 has the same problem -- its AA55 signature
    // halves sit one byte apart on different lanes -- so Peripherals brings
    // the odd byte up on its own read port, and this mux puts it on the high
    // lane whenever the window is being read. Without it the scan's signature
    // word never reaches the CPU.
    wire scsi_rom_hi_read = (~memory_read_n) && (address[19:12] == 8'hD2);
    assign data_bus_hi = xrom_read         ? xrom_byte(address[7:0] | 8'h01)
                       : scsi_rom_hi_read  ? scsi_rom_hi
                       :                     ram_dout_hi_w;

    // fpga/xrom.asm (nasm -f bin). The NEC option-ROM format: AA55h at
    // offset 9, POST entries at 0x0C/0x0F/0x12/0x15, and the disk-BIOS
    // extension entry at 0x18 which the BIOS tail-jumps to through the
    // 0x4B0 devtype table.
    localparam logic [7:0] XROM_BYTES [0:227] = '{
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h55, 8'hAA, 8'h90,
            8'hE9, 8'h85, 8'h00, 8'hE9, 8'h82, 8'h00, 8'hE9, 8'h7F, 8'h00, 8'hEB, 8'h7D, 8'h90,
            8'h56, 8'h57, 8'h8B, 8'h76, 8'h00, 8'h8A, 8'h46, 8'h01, 8'h24, 8'h0F, 8'h3C, 8'h04,
            8'h74, 8'h38, 8'hFF, 8'h36, 8'hFA, 8'h05, 8'hFF, 8'h36, 8'hF8, 8'h05, 8'hC7, 8'h06,
            8'hF8, 8'h05, 8'hBC, 8'h00, 8'h8C, 8'hC8, 8'hA3, 8'hFA, 8'h05, 8'h89, 8'hF0, 8'h24,
            8'h0F, 8'h0C, 8'h90, 8'h8B, 8'h5E, 8'h02, 8'h8B, 8'h4E, 8'h04, 8'h8B, 8'h56, 8'h06,
            8'h8E, 8'h46, 8'h0A, 8'h8B, 8'h7E, 8'h08, 8'h87, 8'hFD, 8'hCD, 8'h1B, 8'h87, 8'hFD,
            8'h8F, 8'h06, 8'hF8, 8'h05, 8'h8F, 8'h06, 8'hFA, 8'h05, 8'hEB, 8'h1A, 8'h89, 8'hF0,
            8'h30, 8'hE4, 8'hA8, 8'h80, 8'h74, 8'h03, 8'h80, 8'hCC, 8'h01, 8'h89, 8'hF1, 8'h81,
            8'hE1, 8'h40, 8'h8F, 8'h81, 8'hF9, 8'h00, 8'h84, 8'h75, 8'h03, 8'h80, 8'hCC, 8'h0C,
            8'h88, 8'h66, 8'h01, 8'h80, 8'h66, 8'h16, 8'hFE, 8'h80, 8'hFC, 8'h20, 8'h72, 8'h04,
            8'h80, 8'h4E, 8'h16, 8'h01, 8'h5F, 8'h5E, 8'h58, 8'h5B, 8'h59, 8'h5A, 8'h5D, 8'h07,
            8'h5F, 8'h5E, 8'h1F, 8'hCF, 8'h50, 8'h1E, 8'h31, 8'hC0, 8'h8E, 8'hD8, 8'hC6, 8'h06,
            8'hD0, 8'h04, 8'hFF, 8'h80, 8'h0E, 8'hAE, 8'h05, 8'h03, 8'h8C, 8'hC8, 8'h88, 8'hE0,
            8'hA2, 8'hB3, 8'h04, 8'hA2, 8'hBB, 8'h04, 8'hC7, 8'h06, 8'hF8, 8'h05, 8'hBC, 8'h00,
            8'h8C, 8'hC8, 8'hA3, 8'hFA, 8'h05, 8'h1F, 8'h58, 8'hCB, 8'hC4, 8'h00, 8'hC4, 8'h00,
            8'hC4, 8'h00, 8'hC4, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h1A, 8'h07, 8'h1A, 8'h1B,
            8'h1A, 8'h0E, 8'h1A, 8'h36, 8'h0F, 8'h0E, 8'h0F, 8'h2A, 8'h12, 8'h1B, 8'h12, 8'h54,
            8'h08, 8'h1B, 8'h08, 8'h3A, 8'h08, 8'h35, 8'h08, 8'h74, 8'h00, 8'h00, 8'h00, 8'h00 };

    function automatic logic [7:0] xrom_byte(input logic [7:0] a);
        xrom_byte = (a < 8'd228) ? XROM_BYTES[a] : 8'hFF;
    endfunction

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
        // The built-in 3-mode FDD option ROM. A real adapter carried a
        // BIOS-extension ROM in the D0000 scan slot; ours is the stub
        // assembled from fpga/xrom.asm. It claims the NEC devtype
        // 0x3x/0xBx calls through the 0x4B0 XROM table, marks drives 0/1
        // as 1.44-capable in work-area 0x5AE, and hands INT 1Bh a
        // 1.44-aware F2HD parameter table. Bytes past the image read
        // 0xFF like the empty window that surrounds the slot.
        else if (xrom_read)
        begin
            internal_data_bus_ext = xrom_byte(address[7:0]);
            data_bus_direction    = 1'b0;
        end
        // IN 08E9h: the NEC EMS board answers "is this megabyte fitted".
        // Its window reads never reach here -- a mapped window is claimed
        // by the SDRAM branch above, an unmapped one by the hole below.
        else if ((~io_read_n) && (~address_enable_n)
                 && (address[15:0] == 16'h08E9))
        begin
            internal_data_bus_ext = ems98_status;
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

