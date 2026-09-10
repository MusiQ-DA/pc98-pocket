//
// MiSTer PCXT Peripherals
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
//
`ifndef ENABLE_TANDY_VIDEO
`define ENABLE_TANDY_VIDEO 0
`endif
`ifndef ENABLE_TANDY_AUDIO
`define ENABLE_TANDY_AUDIO 0
`endif
`ifndef ENABLE_TANDY_KBD
`define ENABLE_TANDY_KBD 0
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

module PERIPHERALS #(
        parameter ps2_over_time = 16'd1000,
		parameter clk_rate = 28'd50000000
    ) (
        input   logic           clock,
        input   logic           clk_sys,
        input   logic           cpu_ce_posedge,
        input   logic           cpu_ce_negedge,
        input   logic           peripheral_ce,
        input   logic   [1:0]   clk_select,
        input   logic           reset,
        // CPU
        output  logic           interrupt_to_cpu,
        // Bus Arbiter
        input   logic           interrupt_acknowledge_n,
        output  logic           dma_chip_select_n,
        output  logic           dma_page_chip_select_n,
        // SplashScreen
        input   logic           splashscreen,
        input   logic           status0_clear,
        // VGA
        output  logic           std_hsyncwidth,
        input   logic           composite,
        input   logic           video_output,
        input   logic           clk_vga_cga,
        input   logic           enable_cga,
        input   logic           clk_vga_hgc,
        input   logic           enable_hgc,
        input   logic   [1:0]   hgc_rgb,
        output  logic           de_o,
        // PC-98 ANK font load, straight off the loader (core_top's dl_wr).
        // Glyph reads from SDRAM, the controller's second port.
        output  logic           font_rd_req,
        output  logic   [23:0]  font_rd_addr,
        output  logic    [3:0]  font_rd_len,
        input   logic           font_rd_ack,
        input   logic           font_rd_valid,
        input   logic   [15:0]  font_rd_data,
        input   logic           font_rd_done,
        output  logic           cg_rd_req,
        output  logic   [23:0]  cg_rd_addr,
        output  logic    [3:0]  cg_rd_len,
        input   logic           cg_rd_ack,
        input   logic           cg_rd_valid,
        input   logic   [15:0]  cg_rd_data,
        input   logic           cg_rd_done,
        input   logic           font_wr_clk,
        input   logic           font_wr_en,
        input   logic   [10:0]  font_wr_addr,
        input   logic   [15:0]  font_wr_data,
        output  logic   [5:0]   VGA_R,
        output  logic   [5:0]   VGA_G,
        output  logic   [5:0]   VGA_B,
        output  logic           VGA_HSYNC,
        output  logic           VGA_VSYNC,
        output  logic           VGA_HBlank,
        output  logic           VGA_VBlank,
        output  logic           VGA_VBlank_border,
        // I/O Ports
        input   logic   [19:0]  address,
        output  logic   [19:0]  latch_address,
        input   logic   [7:0]   internal_data_bus,
        output  logic   [7:0]   data_bus_out,
        output  logic           data_bus_out_from_chipset,
        input   logic   [7:0]   interrupt_request,
        input   logic           io_read_n,
        input   logic           io_write_n,
        input   logic           memory_read_n,
        input   logic           memory_write_n,
        input   logic           address_enable_n,
        // Peripherals
        output  logic   [2:0]   timer_counter_out,
        output  logic           speaker_out,
        output  logic   [7:0]   port_a_out,
        output  logic           port_a_io,
        input   logic   [7:0]   port_b_in,
        output  logic   [7:0]   port_b_out,
        output  logic           port_b_io,
        input   logic   [7:0]   port_c_in,
        output  logic   [7:0]   port_c_out,
        output  logic   [7:0]   port_c_io,
        input   logic   [7:0]   kb_byte,
        input   logic           kb_valid,
        output  logic           kb_ready,
        input   logic           uart_rx,
        output  logic           uart_rts_n,
        input   logic   [4:0]   joy_opts,
        input   logic   [13:0]  joy0,
        input   logic   [13:0]  joy1,
        input   logic   [15:0]  joya0,
        input   logic   [15:0]  joya1,
        // JTOPL
        output  logic   [15:0]  jtopl2_snd_e,
        input   logic   [1:0]   opl2_io,
        // C/MS Audio
        input   logic           cms_en,
        output  reg     [15:0]  o_cms_l,
        output  reg     [15:0]  o_cms_r,
        // TANDY
        input   logic           tandy_video,
        output  logic   [10:0]  tandy_snd_e,
        output  logic           tandy_snd_rdy,
        output  logic           tandy_16_gfx,
        output  logic           tandy_color_16,
        // UART
        input   logic           clk_uart,
        input   logic           uart2_rx,
        output  logic           uart2_tx,
        input   logic           uart2_cts_n,
        input   logic           uart2_dcd_n,
        input   logic           uart2_dsr_n,
        output  logic           uart2_rts_n,
        output  logic           uart2_dtr_n,
        // EMS
        input   logic           ems_enabled,
        input   logic   [1:0]   ems_address,
        output  reg     [6:0]   map_ems[0:3], // Segment hx000, hx400, hx800, hxC00
        output  reg             ena_ems[0:3], // Enable Segment Map hx000, hx400, hx800, hxC00
        output  logic           ems_b1,
        output  logic           ems_b2,
        output  logic           ems_b3,
        output  logic           ems_b4,
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
        output  logic   [1:0]   fdd_present,
        output  logic   [1:0]   fdd_request,
        output  logic   [2:0]   ide0_request,
        output  logic           fdd_dma_req,
        input   logic           fdd_dma_ack,
        input   logic           terminal_count,
        // XTCTL DATA
        output  logic   [7:0]   xtctl = 8'h00,
        // Others
        output  logic           pause_core,
        input   logic           cga_hw,
        input   logic           cga_scandouble_en,
        input   logic           hercules_hw,
        output  logic           swap_video,
        input   logic   [3:0]   crt_h_offset,
        input   logic   [2:0]   crt_v_offset,
        input   logic   [2:0]   vsync_width_osd,
        input   logic   [2:0]   hsync_width_osd
        
    );

    wire [4:0] clkdiv;
    wire grph_mode;
    wire hres_mode;

    wire tandy_video_en = `ENABLE_TANDY_VIDEO ? tandy_video : 1'b0;
    wire tandy_audio_en = `ENABLE_TANDY_AUDIO ? 1'b1 : 1'b0;
    wire tandy_kbd_en = `ENABLE_TANDY_KBD ? 1'b1 : 1'b0;

    wire tandy_io_en = tandy_video_en | tandy_audio_en;

    wire hgc_enable = `ENABLE_HGC ? enable_hgc : 1'b0;
    wire hgc_grph_mode;
    wire hgc_grph_page;

    assign tandy_16_gfx = `ENABLE_CGA ? (tandy_video_en & grph_mode & hres_mode) : 1'b0;



    //
    // chip select
    //
    logic   [7:0]   chip_select_n;

    always_comb
    begin
        if (iorq & ~address_enable_n & ~address[9] & ~address[8] & (tandy_io_en ? ~address[4] : 1'b1))
        begin
            casez (address[7:5])
                3'b000:
                    chip_select_n = 8'b11111110;
                3'b001:
                    chip_select_n = 8'b11111101;
                3'b010:
                    chip_select_n = 8'b11111011;
                3'b011:
                    chip_select_n = 8'b11110111;
                3'b100:
                    chip_select_n = 8'b11101111;
                3'b101:
                    chip_select_n = 8'b11011111;
                3'b110:
                    chip_select_n = 8'b10111111;
                3'b111:
                    chip_select_n = 8'b01111111;
                default:
                    chip_select_n = 8'b11111111;
            endcase
        end
        else
        begin
            chip_select_n = 8'b11111111;
        end
    end

    wire    iorq = ~io_read_n | ~io_write_n;

`ifdef MACHINE_PC98
    // ------------------------------------------------- PC-98 chip selects
    //
    // On a PC-98, A0 says WHICH CHIP, not which register. Two devices
    // interleave through the same range on even and odd addresses, and the
    // register within a device is selected by the bits above A0. Nothing about
    // the PC/AT decode above survives that: it splits I/O space into 32-byte
    // blocks by address[7:5] and hands each block to one device.
    //
    //   0x00-0x0F  even  8259 PIC     odd  8237 DMA
    //   0x30-0x3F  even  8251         odd  8255 system port
    //   0x70-0x7F  even  CRTC/GRCG    odd  8253 PIT
    //
    // Master 8259 at 0x00/0x02, slave at 0x08/0x0A. Only the master is wired
    // for now -- KFPC-XT is an XT and carries one -- so the slave's addresses
    // are left undecoded rather than answered wrongly.
    //
    // The register selects change with the map: the 8259's A0 comes from
    // address[1], and the 8253's and 8255's two bits from address[2:1].
    // Qualified the way the PC/AT decode above qualifies: A9 and A8 low, and
    // nothing said about A15-A10 -- which is not just what the original did,
    // but what a PC-98 does. The machine's own I/O map mirrors 0000-00FF at
    // 0100-03FF, 0400-0FFF and beyond, so the upper lines are genuinely
    // don't care to the chipset. (The BIOS's 8253 test at FD885 reads counter
    // 0 at 0071; a boot simulation of exactly that cycle shows 0071 on the
    // latched address, so the upper bits are not garbage either -- the loose
    // decode is for fidelity, not to rescue a missing select.)
    wire pc98_io  = iorq & ~address_enable_n & ~address[9] & ~address[8];

    // The single-port stubs below stay strict: they answer one address each and
    // have no business claiming aliases.
    wire pc98_io_exact = iorq & ~address_enable_n & (address[15:8] == 8'h00);

    assign dma_chip_select_n        = ~(pc98_io &  address[0] & ~address[7] & ~address[6] & ~address[5] & ~address[4]);
    wire   interrupt_chip_select_n  = ~(pc98_io & ~address[0] & (address[7:3] == 5'b00000));
    wire   timer_chip_select_n      = ~(pc98_io &  address[0] & (address[7:4] == 4'h7));
    wire   ppi_chip_select_n        = ~(pc98_io &  address[0] & (address[7:4] == 4'h3));

    // 0x21-0x2F odd: the DMA bank (page) registers.
    assign dma_page_chip_select_n   = ~(pc98_io &  address[0] & (address[7:4] == 4'h2));

    wire   [0:0] pic_reg_addr  = address[1];
    wire   [1:0] pit_reg_addr  = address[2:1];
    wire   [1:0] ppi_reg_addr  = address[2:1];
    wire   [3:0] dma_reg_addr  = address[4:1];

    // ---------------------------------------------- floppy interface stub
    //
    // Three ports the ITF polls before it will go any further. There is no
    // drive here and none is needed: with nothing attached these read as
    // constants on a real machine, and answering them is the whole of what the
    // ITF wants at this stage.
    //
    //   0x00BE  FDD interface select. Bit 3 reads 1, bit 2 reads 0, and the low
    //           two bits are the latch, which resets to 3 -- so 0xFB. The ITF
    //           does IN AL,0BEh / TEST AL,1 / JZ, and bit 0 is what it is
    //           testing.
    //   0x0090  uPD765A main status. Idle is RQM alone, 0x80. The ITF tests
    //           bit 4 (FDC busy) in a LOOPNE, so 0x00 would spin it out and
    //           0xFF would fake a result phase that never comes.
    //   0x0094  control register. The read side is a constant, 0x44.
    //
    // 0x0092 is the data register and is left out deliberately: it only means
    // anything mid-command, and there are no commands without a drive.
    wire fdd_be_select = pc98_io_exact & (address[7:0] == 8'hBE);
    wire fdd_90_select = pc98_io_exact & (address[7:0] == 8'h90);
    wire fdd_94_select = pc98_io_exact & (address[7:0] == 8'h94);

    // 0x00CC  2DD drive/motor control (MAME fdc_2hd_2dd_ctrl<0>). The write
    //          latches; bit 3 is the motor; bit 0's rising edge arms a
    //          ~100 ms timer whose expiry raises the drive interrupt --
    //          MAME's fdc_trigger pulses the SLAVE PIC's IRQ2, and only
    //          when bit 2 (XTMASK) is set. The VM BIOS writes 0x09/0x0C
    //          here and waits for that interrupt; with nothing wired it
    //          rewrote the port forever (N frozen at 17244, IO 00CC 00CC
    //          00CC). Read returns the latch with bit 5 set and bit 4 as
    //          drive-ready; a driveless machine still reports ready
    //          rather than halting, so a constant one is what it wants.
    wire fdd_cc_select = pc98_io_exact & (address[7:0] == 8'hCC);
    logic [7:0] fdd_cc_latch;
    logic       fdd_cc_trig_q;
    logic [22:0] fdd_cc_timer;
    logic        fdd_cc_armed;
    logic        fdd_cc_irq;      // XTMASK interrupt: slave IRQ2
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            fdd_cc_latch  <= 8'h00;
            fdd_cc_trig_q <= 1'b0;
            fdd_cc_timer  <= 23'd0;
            fdd_cc_armed  <= 1'b0;
            fdd_cc_irq    <= 1'b0;
        end else begin
            fdd_cc_trig_q <= fdd_cc_latch[0];
            if (fdd_cc_select & ~io_write_n)
                fdd_cc_latch <= internal_data_bus;
            // A fresh bit0 rising edge (re)arms the 100 ms timer.
            if (fdd_cc_latch[0] & ~fdd_cc_trig_q) begin
                fdd_cc_armed <= 1'b1;
                fdd_cc_timer <= 23'd0;
            end
            if (fdd_cc_armed) begin
                if (fdd_cc_timer == 23'd4_295_000) begin  // ~100 ms at 42.95 MHz
                    fdd_cc_armed <= 1'b0;
                    fdd_cc_irq   <= fdd_cc_latch[2];
                end else
                    fdd_cc_timer <= fdd_cc_timer + 23'd1;
            end else if (fdd_cc_irq)
                fdd_cc_irq <= 1'b0;   // one chipset clock is a whole edge
        end
    end
    wire        fdd_cc_read  = fdd_cc_select & ~io_read_n;
    wire [7:0]  fdd_cc_data  = fdd_cc_latch | 8'h30;

    // Minimal uPD765 at 0x90-0x93 and its 0xC8-0xCB mirror (MAME maps the
    // 2HD controller there; the VM BIOS drives it with DX). Command bytes
    // are counted per the uPD765 table, every command finishes at once, and
    // the answers all say "no drive attached":
    //   0x03 SPECIFY     3 bytes in, no result -- back to idle
    //   0x04 SENSE DRIVE 2 in, 1 result (0x00)
    //   0x07 RECALIBRATE 2 in, no result, and a pulse on the slave's IRQ3,
    //                     exactly how the real chip interrupts when the
    //                     drive it was told to seek is not there
    //   0x08 SENSE INT   1 in, 2 results (ST0 = 0x80 "not ready", PCN = 0)
    //   0x0F SEEK        3 in, no result, same IRQ3 as RECALIBRATE
    //   0x4A/0x0A READ ID          2 in, 7 results -- the IPL probe needs the
    //                               full seven bytes or its result loop runs
    //                               off the end of the status port
    //   66/46/06/E6 read data, 65/45/05/E5 write, 4D/CD format: 9 (6 for
    //                               format) in, 7 results, all zero error
    //   anything else    treated as 1 in, 2 results, so an unexpected
    //                     command still hands the BIOS an answer instead of
    //                     a status port that never reaches the result phase
    wire fdc_base_select = pc98_io_exact
                         & ((address[7:2] == 6'h24) | (address[7:2] == 6'h32));
    wire fdc_msr_select  = fdc_base_select & ~address[1];
    wire fdc_fifo_select = fdc_base_select &  address[1];

    logic [7:0] fdc_cmd;
    logic [3:0] fdc_writes_left;
    logic [3:0] fdc_results_left;
    logic [3:0] fdc_result_idx;
    logic [7:0] fdc_result0, fdc_result1;
    logic       fdc_in_result;
    logic       fdc_cmd_done;     // high for one clock when a command completes
    logic       fdc_irq3;

    // One event per ACCESS, not one per clock.
    //
    // fdc_fifo_select is a LEVEL: iorq is asserted for the whole bus cycle,
    // which at 42.95 MHz against a 4.77 MHz CPU is around eighteen chipset
    // clocks. The state machine below consumes a byte every clock it sees the
    // select, so one command byte was consumed eighteen times -- writes_left
    // counted through zero and wrapped to fifteen, cmd_done fired on a command
    // the BIOS had not finished writing, and the model parked in the result
    // phase. MSR then reads C0 for good, and the BIOS sits at FFA26 waiting
    // for 80: the FFA26-FFA2D range the hardware readout came back with.
    //
    // Every other device in this file already takes the prev_io_*_n edges for
    // exactly this reason; the FDC was the one that did not. The address hit
    // is computed without iorq because the strobe has already gone by at the
    // edge being used, and the write byte is latched while the cycle is live
    // -- the bus moves on before the edge, which is the same reason the
    // memory-write path here samples continuously and keeps the last value.
    logic       fdc_prev_wr_n, fdc_prev_rd_n;
    logic [7:0] fdc_wr_data;
    wire fdc_addr_hit  = ~address_enable_n & (address[15:8] == 8'h00)
                       & ((address[7:2] == 6'h24) | (address[7:2] == 6'h32));
    wire fdc_fifo_addr = fdc_addr_hit & address[1];
    wire fdc_wr_pulse  = fdc_fifo_addr & io_write_n & ~fdc_prev_wr_n;
    wire fdc_rd_pulse  = fdc_fifo_addr & io_read_n & ~fdc_prev_rd_n;

    // SENSE INTERRUPT's answer, honestly shaped.
    //
    // The bench read one result byte and stopped, and the model sat on the
    // second one for ever. That is the BIOS behaving correctly: this returned
    // ST0 = 80, and 80 is IC = "invalid command / no interrupt pending", the
    // one case where a uPD765 hands back ONE byte instead of two. The BIOS
    // took its byte and left; the model still wanted to give another.
    //
    // So say what actually happened. A RECALIBRATE or SEEK here finds no
    // drive, which is a real, describable outcome: IC = abnormal termination,
    // SE (seek end) and EC (equipment check) both set, unit in the low two
    // bits -- 70 | unit -- followed by PCN 0. That is two bytes, and the BIOS
    // reads two. With no interrupt pending it is 80 and one byte, as before.
    logic [1:0] fdc_unit;
    logic       fdc_int_pending;

    // Command shape: bytes still to write after the first, and results.
    //
    // Of the byte ARRIVING, not of fdc_cmd. fdc_cmd still holds the PREVIOUS
    // command at the moment the counts are loaded -- it is assigned in the
    // same non-blocking block -- so every command was set up with its
    // predecessor's byte count, and the model desynchronised on the second
    // command it ever saw.
    //
    // What that looks like from the BIOS: SENSE INTERRUPT (0x08, no parameter
    // bytes, two results) is followed by SPECIFY (0x03, two parameter bytes,
    // no results). SPECIFY loaded 0x08's shape -- zero writes, two results --
    // so the model declared itself finished on the command byte alone and
    // went into the result phase. MSR then reads C0 (RQM with DIO set: "read
    // me"), and the BIOS, waiting at FFA26 for MSR & C0 == 80 before it may
    // write a parameter, spins out its whole CX -- 65536 reads, most of a
    // second -- and gives up. Every FDC command after the first cost a full
    // timeout, which is the "IN from 0090 x65538, IN from 00c8 x45172" in the
    // bench trace and the frozen I/O write count on the hardware.
    function automatic logic [7:0] fdc_shape(input logic [7:0] c);
        case (c)
        8'h03: fdc_shape = {4'd2, 4'd0};
        8'h04: fdc_shape = {4'd1, 4'd1};
        8'h07: fdc_shape = {4'd1, 4'd0};
        8'h08: fdc_shape = {4'd0, 4'd2};
        8'h0F: fdc_shape = {4'd2, 4'd0};
        8'h0A, 8'h4A: fdc_shape = {4'd1, 4'd7};
        8'h05, 8'h06, 8'h45, 8'h46, 8'h65, 8'h66, 8'hE5, 8'hE6:
               fdc_shape = {4'd8, 4'd7};
        8'h4D, 8'hCD: fdc_shape = {4'd5, 4'd7};
        default: fdc_shape = {4'd0, 4'd2};
        endcase
    endfunction
    // Sliced off a wire, not off the call: indexing a function's
    // result directly is a syntax error to both Verilator and Quartus.
    wire [7:0] fdc_shape_now   = fdc_shape(fdc_wr_data);
    wire [3:0] fdc_new_writes  = fdc_shape_now[7:4];
    wire [3:0] fdc_new_results = fdc_shape_now[3:0];

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            fdc_cmd         <= 8'h00;
            fdc_writes_left <= 4'd0;
            fdc_results_left<= 4'd0;
            fdc_result_idx  <= 4'd0;
            fdc_result0     <= 8'h00;
            fdc_result1     <= 8'h00;
            fdc_in_result   <= 1'b0;
            fdc_cmd_done    <= 1'b0;
            fdc_irq3        <= 1'b0;
            fdc_unit        <= 2'd0;
            fdc_int_pending <= 1'b0;
            fdc_prev_wr_n   <= 1'b1;
            fdc_prev_rd_n   <= 1'b1;
            fdc_wr_data     <= 8'h00;
        end else begin
            fdc_prev_wr_n <= io_write_n;
            fdc_prev_rd_n <= io_read_n;
            // The byte, sampled while the cycle is live: at the trailing
            // edge the bus has already moved on.
            if (fdc_fifo_select & ~io_write_n) fdc_wr_data <= internal_data_bus;
            fdc_cmd_done <= 1'b0;
            if (fdc_wr_pulse) begin
                if (fdc_writes_left == 4'd0) begin
                    // First byte: it IS the command.
                    fdc_cmd        <= fdc_wr_data;
                    fdc_result_idx <= 4'd0;
                    case (fdc_wr_data)
                        8'h04: fdc_result0 <= 8'h00;
                        8'h08: begin
                            fdc_result0     <= fdc_int_pending ? {2'b01, 2'b11, 2'b00, fdc_unit}
                                                               : 8'h80;
                            fdc_result1     <= 8'h00;
                            fdc_int_pending <= 1'b0;
                        end
                        default: begin fdc_result0 <= 8'h80; fdc_result1 <= 8'h00; end
                    endcase
                    fdc_writes_left  <= fdc_new_writes;
                    fdc_results_left <= (fdc_wr_data == 8'h08)
                                      ? (fdc_int_pending ? 4'd2 : 4'd1)
                                      : fdc_new_results;
                    if (fdc_new_writes == 4'd0)
                        fdc_cmd_done <= 1'b1;      // single-byte command
                end else begin
                    fdc_writes_left <= fdc_writes_left - 4'd1;
                // The unit is the first parameter of RECALIBRATE and
                // SEEK, and it is what ST0 has to name afterwards.
                if ((fdc_cmd == 8'h07 && fdc_writes_left == 4'd1)
                 || (fdc_cmd == 8'h0F && fdc_writes_left == 4'd2))
                    fdc_unit <= fdc_wr_data[1:0];
                    if (fdc_writes_left == 4'd1)
                        fdc_cmd_done <= 1'b1;      // that was the last byte
                end
            end else begin
                // Reading results hands them out one by one; the last one
                // returns the chip to idle.
                if (fdc_rd_pulse && fdc_in_result) begin
                    fdc_result_idx <= fdc_result_idx + 4'd1;
                    if (fdc_result_idx + 4'd1 >= fdc_results_left) begin
                        fdc_in_result    <= 1'b0;
                        fdc_results_left <= 4'd0;
                    end
                end
            end
            if (fdc_cmd_done) begin
                if (fdc_results_left != 4'd0)
                    fdc_in_result <= 1'b1;
                else if (fdc_cmd == 8'h07 || fdc_cmd == 8'h0F)
                    begin
                    fdc_irq3        <= 1'b1;   // no drive: the seek ends at once
                    fdc_int_pending <= 1'b1;
                end
            end
            if (fdc_irq3)
                fdc_irq3 <= 1'b0;
        end
    end
    // MSR, with the busy bit the BIOS actually tests.
    //
    // FFC16 is the BIOS's result-phase wait:
    //
    //     in al,dx / and al,D0 / cmp al,D0 / loopne FFC16
    //
    // RQM and DIO are not enough -- it wants bit 4, CB, the chip's "a command
    // is in progress" flag, which on a uPD765 is set from the first command
    // byte until the last result byte has been read. This model answered C0 in
    // the result phase, CB clear, so the BIOS could never take the two bytes
    // that SENSE INTERRUPT (08) had waiting, the model stayed in the result
    // phase, and the next command's wait at FFA26 -- MSR & C0 == 80 -- spun
    // out its whole CX. That is the FA26-FA2D the hardware readout named.
    //
    // The other two waits agree with modelling CB properly: FFC00 wants
    // D0 == 80, CB CLEAR, before the first command byte, and FFA26 masks CB
    // off entirely for the parameter bytes that follow.
    wire fdc_busy = fdc_in_result | (fdc_writes_left != 4'd0);
    wire [7:0] fdc_msr = fdc_in_result ? 8'hD0     // RQM + DIO + CB: read me
                       : fdc_busy      ? 8'h90     // RQM + CB: next parameter
                       :                 8'h80;    // RQM: idle, send a command
    wire [7:0] fdc_fifo = (fdc_result_idx == 4'd0) ? fdc_result0
                        : (fdc_result_idx == 4'd1) ? fdc_result1
                        :                            8'h00;

    wire fdd_stub_read = (fdd_be_select | fdd_90_select | fdd_94_select
                          | fdd_cc_select | fdc_base_select) & ~io_read_n;
    wire [7:0] fdd_stub_data = fdd_be_select  ? 8'hFB
                             : fdd_90_select  ? fdc_msr
                             : fdd_94_select  ? 8'h44
                             : fdd_cc_select  ? fdd_cc_data
                             : fdc_msr_select ? fdc_msr
                             :                  fdc_fifo;
`else
    assign  dma_chip_select_n       = chip_select_n[0]; // 0x00 .. 0x1F
    wire    interrupt_chip_select_n = chip_select_n[1]; // 0x20 .. 0x3F
    wire    timer_chip_select_n     = chip_select_n[2]; // 0x40 .. 0x5F
    wire    ppi_chip_select_n       = chip_select_n[3]; // 0x60 .. 0x7F
    wire   [0:0] pic_reg_addr  = address[0];
    wire   [1:0] pit_reg_addr  = address[1:0];
    wire   [1:0] ppi_reg_addr  = address[1:0];
    wire   [3:0] dma_reg_addr  = address[3:0];
    assign  dma_page_chip_select_n  = chip_select_n[4]; // 0x80 .. 0x8F
`endif
    wire    nmi_chip_select_n       = chip_select_n[5]; // 0xA0 .. 0xBF
    wire    joystick_select         = (iorq && ~address_enable_n && address[15:3] == (16'h0200 >> 3)); // 0x200 .. 0x207
    wire    tandy_chip_select_n     = tandy_io_en ? chip_select_n[6] : 1'b1; // 0xC0 .. 0xDF
    wire    nmi_mask_register       = (tandy_video_en && ~nmi_chip_select_n);

    wire    opl_388_chip_select     = `ENABLE_OPL2 ? (iorq && ~address_enable_n && ~opl2_io[1] && address[15:1] == (16'h0388 >> 1)) : 1'b0; // 0x388 .. 0x389 (Adlib)
    wire    opl_228_chip_select     = `ENABLE_OPL2 ? (iorq && ~address_enable_n && (opl2_io == 2'b01) && address[15:1] == (16'h0228 >> 1)) : 1'b0; // 0x228 .. 0x229 (Sound Blaster FM)
    wire    cms_220_chip_select     = `ENABLE_CMS ? (iorq && ~address_enable_n && address[15:4] == (16'h0220 >> 4)) : 1'b0; // 0x220 .. 0x22F (C/MS Audio)
    wire    video_mem_select        = `ENABLE_TANDY_VIDEO ? (tandy_video_en && ~iorq && ~address_enable_n & (address[19:17] == nmi_mask_register_data[3:1])) : 1'b0; // 128KB
    wire    cga_mem_select          = `ENABLE_CGA ? (~iorq && ~address_enable_n && enable_cga & (address[19:15] == 5'b10111)) : 1'b0; // B8000 - BFFFF (16 KB / 32 KB)
`ifdef MACHINE_PC98
    // PC-98 text VRAM, A0000-A3FFF: characters at A0000 (two bytes per cell)
    // and attributes at A2000. Same shape as the CGA window above -- a BRAM in
    // the guest's address space, qualified with AEN so a DMA cycle carrying a
    // matching address cannot reach it.
    wire    tvram_mem_select        = ~iorq && ~address_enable_n
                                    && (address[19:14] == 6'b101000);
    // A4000-A4FFF: the character generator window. RAM.sv already keeps SDRAM
    // out of A0000-A7FFF, so this only has to claim the read.
    wire    cgwin_mem_select        = ~iorq && ~address_enable_n
                                    && (address[19:12] == 8'b10100100);
`else
    wire    tvram_mem_select        = 1'b0;
    wire    cgwin_mem_select        = 1'b0;
`endif
    wire    hgc_mem_select          = `ENABLE_HGC ? (~iorq && ~address_enable_n && hgc_enable & (address[19:15] == {5'b1011, hgc_grph_page})) : 1'b0; // B0000 - BFFFF (32KB / 64 KB)
    wire    uart_chip_select        = (~address_enable_n && {address[15:3], 3'd0} == 16'h03F8);
    wire    uart2_chip_select       = (~address_enable_n && {address[15:3], 3'd0} == 16'h02F8);
    wire    lpt_chip_select         = (iorq && ~address_enable_n && address[15:1] == (16'h0378 >> 1)); // 0x378 ... 0x379
	 wire    lpt_ctrl_select         = (iorq && ~address_enable_n && address[15:0] == 16'h037A); // 0x37A
    wire    tandy_page_chip_select  = `ENABLE_TANDY_VIDEO ? (tandy_video_en && iorq && ~address_enable_n && address[15:0] == 16'h03DF) : 1'b0;
    wire    xtctl_chip_select       = (iorq && ~address_enable_n && address[15:0] == 16'h8888);
    wire    rtc_chip_select         = (iorq && ~address_enable_n && address[15:1] == (16'h02C0 >> 1)); // 0x2C0 .. 0x2C1

    wire    [3:0] ems_page_address  = (ems_address == 2'b00) ? 4'b1100 : (ems_address == 2'b01) ? 4'b1101 : 4'b1110;
    wire    ems_chip_select         = `ENABLE_EMS ? (iorq && ~address_enable_n && ems_enabled && ({address[15:2], 2'd0} == 16'h0260)) : 1'b0;          // 260h..263h
    assign  ems_b1                  = `ENABLE_EMS ? (~iorq && ena_ems[0] && (address[19:14] == {ems_page_address, 2'b00})) : 1'b0; // C0000h - D0000h - E0000h
    assign  ems_b2                  = `ENABLE_EMS ? (~iorq && ena_ems[1] && (address[19:14] == {ems_page_address, 2'b01})) : 1'b0; // C4000h - D4000h - E4000h
    assign  ems_b3                  = `ENABLE_EMS ? (~iorq && ena_ems[2] && (address[19:14] == {ems_page_address, 2'b10})) : 1'b0; // C8000h - D8000h - E0000h
    assign  ems_b4                  = `ENABLE_EMS ? (~iorq && ena_ems[3] && (address[19:14] == {ems_page_address, 2'b11})) : 1'b0; // CC000h - DC000h - EC000h
    wire    ide0_chip_select_n      = ~(iorq && ~address_enable_n && ({address[15:4], 4'd0} == 16'h0300));
    wire    floppy0_chip_select_n   = ~(~address_enable_n && (({address[15:2], 2'd0} == 16'h03F0) || ({address[15:1], 1'd0} == 16'h03F4) || ({address[15:0]} == 16'h03F7)));

    logic   [1:0]   ems_access_address;
    logic           ems_write_enable;
    logic   [7:0]   write_map_ems_data;
    logic           write_map_ena_data;
	 
    //
    // I/O Ports
    //
    // Address
    always_comb begin
        if (`ENABLE_TANDY_VIDEO && cga_mem_select && ~memory_write_n && tandy_video_en)
            latch_address   = {nmi_mask_register_data[3:1], tandy_page_data[3] ? {tandy_page_data[5:3], video_ram_address[13:0]} : {tandy_page_data[5:4], video_ram_address[14:0]}};
        else
            latch_address   = address;
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            ems_access_address  <= 2'b11;
            ems_write_enable    <= 1'b0;
            write_map_ems_data  <= 8'd0;
            write_map_ena_data  <= 1'b0;
        end
        else if (`ENABLE_EMS)
        begin
            ems_access_address  <= address[1:0];
            ems_write_enable    <= ems_chip_select && ~io_write_n;
            write_map_ems_data  <= (internal_data_bus == 8'hFF) ? 8'hFF : (internal_data_bus < 8'h80) ? internal_data_bus[6:0] : map_ems[address[1:0]];
            write_map_ena_data  <= (internal_data_bus == 8'hFF) ? 1'b0  : (internal_data_bus < 8'h80) ? 1'b1 : ena_ems[address[1:0]];
        end
        else
        begin
            ems_access_address  <= 2'b11;
            ems_write_enable    <= 1'b0;
            write_map_ems_data  <= 8'd0;
            write_map_ena_data  <= 1'b0;
        end
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset || !`ENABLE_EMS)
        begin
            map_ems = '{7'h00, 7'h00, 7'h00, 7'h00};
            ena_ems = '{1'b0, 1'b0, 1'b0, 1'b0};
        end
        else if (ems_write_enable)
        begin
            map_ems[ems_access_address] <= write_map_ems_data;
            ena_ems[ems_access_address] <= write_map_ena_data;
        end
    end


    //
    // 8259
    //
    // PC-98 carries two: the master at 0000-0007 even, the slave at 0008-000F
    // even. The BIOS initializes both (ICW3 master 0x80: the slave hangs off
    // IRQ7; slave ID 7) and then tests each IMR by writing and reading back --
    // an absent slave reads FF, and the VM BIOS halts at FDA65 on exactly
    // that. The timer stays on the master's IRQ0; the slave's own lines are
    // quiet until something needs IRQ8-15.
    logic           timer_interrupt;
    logic           keybord_interrupt;
    logic           uart_interrupt;
    logic           fdd_interrupt;
    logic           uart2_interrupt;
    logic   [7:0]   interrupt_data_bus_out;
    logic           interrupt_to_cpu_buf;

    logic   [7:0]   interrupt2_data_bus_out;
    logic           interrupt2_data_bus_io;
    logic           interrupt2_to_cpu;
    logic   [2:0]   interrupt_cascade_out;
    logic           interrupt_cascade_io;

`ifdef MACHINE_PC98
    wire    interrupt2_chip_select_n;
`endif

    KF8259 u_KF8259
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (interrupt_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (pic_reg_addr),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (interrupt_data_bus_out),

        // I/O
`ifdef MACHINE_PC98
        .cascade_in                 (3'b000),
        .cascade_out                (interrupt_cascade_out),
        .cascade_io                 (interrupt_cascade_io),
`else
        .cascade_in                 (3'b000),
        //.cascade_out                (),
        //.cascade_io                 (),
`endif
        .slave_program_n            (1'b1),
        //.buffer_enable              (),
        //.slave_program_or_enable_buffer     (),
        .interrupt_acknowledge_n    (interrupt_acknowledge_n),
        .interrupt_to_cpu           (interrupt_to_cpu_buf),
`ifdef MACHINE_PC98
        // IRQ7 is the slave's cascade line; the machine's own IRQ7 has to
        // stand down for it. IRQ2 is the CRT interrupt -- see crt_vsync_irq
        // above; without it the BIOS parks at FED44 for good. The drive's
        // own interrupts live on the slave (IRQ2 XTMASK, IRQ3 FDC).
        .interrupt_request          ({interrupt2_to_cpu,
                                        fdd_interrupt,
                                        interrupt_request[5],
                                        uart_interrupt,
                                        uart2_interrupt,
                                        crt_vsync_irq,
                                        keybord_interrupt,
                                        timer_interrupt})
`else
        .interrupt_request          ({interrupt_request[7],
                                        fdd_interrupt,
                                        interrupt_request[5],
                                        uart_interrupt,
                                        uart2_interrupt,
                                        interrupt_request[2],
                                        keybord_interrupt,
                                        timer_interrupt})
`endif
    );

`ifdef MACHINE_PC98
    // The slave PIC, 0008-000F even. Its INT feeds the master's IRQ7 and its
    // cascade lines close the loop, so an IRQ8-15 acknowledge gets its vector
    // from the slave exactly the way the metal does it.
    assign interrupt2_chip_select_n = ~(pc98_io & ~address[0] & address[3]
                                        & (address[7:4] == 4'h0));

    KF8259 u_KF8259_2
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (interrupt2_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (pic_reg_addr),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (interrupt2_data_bus_out),
        .data_bus_io                (interrupt2_data_bus_io),

        // I/O
        .cascade_in                 (interrupt_cascade_out),
        .cascade_out                (),
        .cascade_io                 (),
        .slave_program_n            (1'b0),
        .interrupt_acknowledge_n    (interrupt_acknowledge_n),
        .interrupt_to_cpu           (interrupt2_to_cpu),
        // IRQ3 is the FDC's own interrupt (RECALIBRATE finding no drive);
        // IRQ2 is the XTMASK pulse the 100 ms 0xCC timer fires.
        .interrupt_request          ({4'b0, fdc_irq3, fdd_cc_irq, 2'b0})
    );
`endif

    always_ff @(posedge clock, posedge reset)
        if (reset)
            interrupt_to_cpu    <= 1'b0;
        else if (cpu_ce_negedge)
            interrupt_to_cpu    <= interrupt_to_cpu_buf;
        else
            interrupt_to_cpu    <= interrupt_to_cpu;


    //
    // 8253
    //
    logic   timer_clock;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            timer_clock         <= 1'b0;
        else if (peripheral_ce)
            timer_clock         <= ~timer_clock;
        else
            timer_clock         <= timer_clock;
    end

    logic   [7:0]   timer_data_bus_out;

    // The AT gates counter 2 off port B bit 0 (speaker gate). A PC-98 keeps
    // all three PIT gates hard-wired high and mutes the beeper downstream
    // instead -- and it matters: the VM BIOS tests counter 2 at FD885 before
    // writing a single byte to the 8255 (nothing but the two control words to
    // 0x37 precede it in the trace). With port B at its reset value the AT
    // wiring held counter 2's gate low, it never counted, the readback
    // returned the load value, and the test read that as a dead chip and
    // halted. That is exactly where the machine stopped: N=34 is counter 2's
    // first pass through the loop, one latch short of the read that halts.
    //
    // The beep is left unmuted on purpose: the machine's boot beep IS counter
    // 2 in mode 3 (FD8B4 programs it), so hearing it confirms this fix the
    // same way the POST codes confirm the rest.
`ifdef MACHINE_PC98
    wire    tim2gatespk = 1'b1;
    // The beeper's gate is 8255 port C bit 3, and it is INVERTED: the beep
    // sounds while PC3 is LOW (MAME: m_beeper->set_state(!(data & 8))). The
    // BIOS's FE0DF routine clears PC3 (0x06), waits, sets it (0x07) -- the
    // wait IS the beep, so following the bit straight would hold the gate
    // shut exactly when it should sing.
    wire    spkdata     = ~port_c_out[3] & ~port_c_io;
`else
    wire    tim2gatespk = port_b_out[0] & ~port_b_io;
    wire    spkdata     = port_b_out[1] & ~port_b_io;
`endif

    KF8253 u_KF8253 
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (timer_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (pit_reg_addr),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (timer_data_bus_out),

        // I/O
        .counter_0_clock            (timer_clock),
        .counter_0_gate             (1'b1),
        .counter_0_out              (timer_counter_out[0]),
        .counter_1_clock            (timer_clock),
        .counter_1_gate             (1'b1),
        .counter_1_out              (timer_counter_out[1]),
        .counter_2_clock            (timer_clock),
        .counter_2_gate             (tim2gatespk),
        .counter_2_out              (timer_counter_out[2])
    );

    assign  timer_interrupt = timer_counter_out[0];
    assign  speaker_out     = timer_counter_out[2] & spkdata;

    //
    // 8255
    //
    logic   [7:0]   ppi_data_bus_out;
    logic   [7:0]   port_a_in;

    KF8255 u_KF8255 
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (ppi_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (ppi_reg_addr),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (ppi_data_bus_out),

        // I/O
        .port_a_in                  (port_a_in),
        .port_a_out                 (port_a_out),
        .port_a_io                  (port_a_io),
        .port_b_in                  (port_b_in),
        .port_b_out                 (port_b_out),
        .port_b_io                  (port_b_io),
        .port_c_in                  (port_c_in),
        .port_c_out                 (port_c_out),
        .port_c_io                  (port_c_io)
    );

    //
    // KFPS2KB
    //
    logic           keybord_irq;
    logic           uart_irq;
    logic           uart2_irq;
    logic   [7:0]   keycode_buf;
    logic   [7:0]   keycode;
    logic   [7:0]   tandy_keycode_conv;
    logic           swap_video_buffer_1;
    logic           swap_video_buffer_2;
    localparam [15:0] OPL_WARM_RESET_HOLD = 16'd5000;
    logic           prev_keybord_irq;
    logic           ctrl_down;
    logic           alt_down;
    logic   [15:0]  opl_reset_cnt;
    wire            opl_warm_reset = `ENABLE_OPL2 ? (opl_reset_cnt != 16'd0) : 1'b0;

    wire    clear_keycode = port_b_out[7];
    wire    ps2_reset_n   = ~tandy_video ? port_b_out[6] : 1'b1;

    // Keyboard self-test response: releasing the port-B reset line makes a real XT
    // keyboard run its self-test and send 0xAA, and the BIOS keyboard POST depends on
    // seeing that byte. Inject it into the Set-2 stream after roughly a real
    // keyboard's reset-to-response delay, holding off the external stream meanwhile.
    localparam [16:0] KB_BAT_DELAY = 17'd100000;    // ~2 ms
    logic           prev_ps2_reset_n;
    logic   [16:0]  kb_bat_delay_cnt;
    logic           kb_ready_int;
    wire            kb_bat_pending = (kb_bat_delay_cnt == 17'd1);
    wire    [7:0]   kb_byte_int    = kb_bat_pending ? 8'hAA : kb_byte;
    wire            kb_valid_int   = kb_bat_pending ? 1'b1  : kb_valid;
    assign  kb_ready = kb_bat_pending ? 1'b0 : kb_ready_int;

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            prev_ps2_reset_n <= 1'b0;
        else
            prev_ps2_reset_n <= ps2_reset_n;
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            kb_bat_delay_cnt <= 17'd0;
        else if (~prev_ps2_reset_n & ps2_reset_n)
            kb_bat_delay_cnt <= KB_BAT_DELAY;
        else if (kb_bat_pending)
            kb_bat_delay_cnt <= kb_ready_int ? 17'd0 : kb_bat_delay_cnt;
        else if (kb_bat_delay_cnt != 17'd0)
            kb_bat_delay_cnt <= kb_bat_delay_cnt - 17'd1;
    end

    KFPS2KB #(.clk_rate(clk_rate)) u_KFPS2KB
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),

        // Set-2 byte in
        .kb_byte                    (kb_byte_int),
        .kb_valid                   (kb_valid_int),
        .kb_ready                   (kb_ready_int),

        // I/O
        .irq                        (keybord_irq),
        .keycode                    (keycode_buf),
        .clear_keycode              (clear_keycode),
        .pause_core                 (pause_core),
        .swap_video                 (swap_video_buffer_1),
        .video_output               (video_output),
        .tandy_video                (tandy_video_en)
    );

    assign  keycode = ps2_reset_n ? keycode_buf : 8'h80;

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            prev_keybord_irq <= 1'b0;
            ctrl_down        <= 1'b0;
            alt_down         <= 1'b0;
            opl_reset_cnt    <= 16'd0;
        end
        else if (`ENABLE_OPL2)
        begin
            prev_keybord_irq <= keybord_irq;
            if (opl_reset_cnt != 16'd0)
                opl_reset_cnt <= opl_reset_cnt - 16'd1;

            if (keybord_irq && ~prev_keybord_irq)
            begin
                case (keycode)
                    8'h1D: ctrl_down <= 1'b1;
                    8'h9D: ctrl_down <= 1'b0;
                    8'h38: alt_down  <= 1'b1;
                    8'hB8: alt_down  <= 1'b0;
                    default: ;
                endcase

                if (keycode == 8'h53 && ctrl_down && alt_down)
                    opl_reset_cnt <= OPL_WARM_RESET_HOLD;
            end
        end
        else
        begin
            prev_keybord_irq <= 1'b0;
            ctrl_down        <= 1'b0;
            alt_down         <= 1'b0;
            opl_reset_cnt    <= 16'd0;
        end
    end

    // Convert Tandy scancode
    Tandy_Scancode_Converter u_Tandy_Scancode_Converter 
    (
        .clock                      (clock),
        .reset                      (reset),
        .scancode                   (keycode),
        .keybord_irq                (keybord_irq),
        .convert_data               (tandy_keycode_conv)
    );
    wire [7:0] tandy_keycode = `ENABLE_TANDY_KBD ? tandy_keycode_conv : keycode;

    always_ff @(posedge clk_vga_hgc)
    begin
        swap_video_buffer_2 <= swap_video_buffer_1;
        swap_video          <= swap_video_buffer_2;
    end


    wire [7:0] jtopl2_dout_int;
    wire [15:0] jtopl2_snd_e_int;
    wire [7:0] jtopl2_dout = `ENABLE_OPL2 ? jtopl2_dout_int : 8'hFF;
    assign jtopl2_snd_e = `ENABLE_OPL2 ? jtopl2_snd_e_int : 16'd0;

    reg clk_en_opl2;
    always @(posedge clock) begin
        reg [27:0] sum = 0;

        clk_en_opl2 <= 0;
        sum = sum + 28'd3579545;
        if(sum >= clk_rate) begin
            sum = sum - clk_rate;
            clk_en_opl2 <= 1;
        end
    end

    jtopl2 jtopl2_inst
    (
        .rst(reset | opl_warm_reset),
        .clk(clock),
        .cen(clk_en_opl2),
        .din(internal_data_bus),
        .dout(jtopl2_dout_int),
        .addr(address[0]),
        .cs_n(~(opl_228_chip_select || opl_388_chip_select)),
        .wr_n(io_write_n),
        .irq_n(),
        .snd(jtopl2_snd_e_int),
        .sample()
    );


    wire [10:0] tandy_snd_e_int;
    wire        tandy_snd_rdy_int;
    assign tandy_snd_e = `ENABLE_TANDY_AUDIO ? tandy_snd_e_int : 11'd0;
    assign tandy_snd_rdy = `ENABLE_TANDY_AUDIO ? tandy_snd_rdy_int : 1'b1;

    // Tandy sound
		 jt89 sn76489
    (
        .rst(reset),
		  .clk(clock),
		  .clk_en(clk_en_opl2), // 3.579MHz
		  .wr_n(io_write_n),
		  .cs_n(tandy_chip_select_n),
		  .din(internal_data_bus),
		  .sound(tandy_snd_e_int),
		  .ready(tandy_snd_rdy_int)
    );
	 
//------------------------------------------------------------------------------

reg ce_1us;
always @(posedge clock) begin
	reg [27:0] sum = 0;

	ce_1us <= 0;
	sum = sum + 28'd1000000;
	if(sum >= clk_rate) begin
		sum = sum - clk_rate;
		ce_1us <= 1;
	end
end	 
	 
//------------------------------------------------------------------------------ c/ms

    reg [7:0] cms_det;
    wire cms_rd = `ENABLE_CMS ? ((address[3:0] == 4'h4 || address[3:0] == 4'hB) && cms_220_chip_select && cms_en) : 1'b0;
    wire [7:0] data_from_cms = `ENABLE_CMS ? (address[3] ? cms_det : 8'h7F) : 8'hFF;

    wire cms_wr = `ENABLE_CMS ? (~address[3] & cms_220_chip_select & cms_en) : 1'b0;
    always @(posedge clock)
        if (`ENABLE_CMS && ~io_write_n && cms_wr && &address[2:1])
            cms_det <= internal_data_bus;
        else if (!`ENABLE_CMS)
            cms_det <= 8'h00;

    reg ce_saa;
    always @(posedge clock) begin
	    reg [27:0] sum = 0;

	    if (`ENABLE_CMS)
        begin
	        ce_saa <= 0;
	        sum = sum + 28'd7159090;
	        if(sum >= clk_rate) begin
		        sum = sum - clk_rate;
		        ce_saa <= 1;
	        end
        end
        else
            ce_saa <= 1'b0;
    end

    wire [7:0] saa1_l,saa1_r;
    saa1099 ssa1
    (
	    .clk_sys(clock),
	    .ce(ce_saa),
	    .rst_n(~reset & cms_en),
	    .cs_n(~(cms_wr && (address[2:1] == 0))),
	    .a0(address[0]),
	    .wr_n(io_write_n),
	    .din(internal_data_bus),
	    .out_l(saa1_l),
	    .out_r(saa1_r)
    );

    wire [7:0] saa2_l,saa2_r;
    saa1099 ssa2
    (
	    .clk_sys(clock),
	    .ce(ce_saa),
	    .rst_n(~reset & cms_en),
	    .cs_n(~(cms_wr && (address[2:1] == 1))),
	    .a0(address[0]),
	    .wr_n(io_write_n),
	    .din(internal_data_bus),
	    .out_l(saa2_l),
	    .out_r(saa2_r)
    );

    wire [8:0] cms_l = {1'b0, saa1_l} + {1'b0, saa2_l};
    wire [8:0] cms_r = {1'b0, saa1_r} + {1'b0, saa2_r};
	 
    reg [15:0] sample_pre_l, sample_pre_r;
    always @(posedge clock) begin
        if (`ENABLE_CMS)
        begin
	        sample_pre_l <= {2'b0, cms_l, cms_l[8:4]};
	        sample_pre_r <= {2'b0, cms_r, cms_r[8:4]};
        end
        else
        begin
            sample_pre_l <= 16'd0;
            sample_pre_r <= 16'd0;
        end
    end

    always @(posedge clock) begin
        if (`ENABLE_CMS)
        begin
	        o_cms_l <= $signed(sample_pre_l) >>> ~{3'd7};
	        o_cms_r <= $signed(sample_pre_r) >>> ~{3'd7};
        end
        else
        begin
            o_cms_l <= 16'd0;
            o_cms_r <= 16'd0;
        end
    end
	 
//

    logic   keybord_interrupt_ff;
    logic   uart_interrupt_ff;
    logic   uart2_interrupt_ff;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            keybord_interrupt_ff    <= 1'b0;
            keybord_interrupt       <= 1'b0;
            uart_interrupt_ff       <= 1'b0;
            uart_interrupt          <= 1'b0;
            uart2_interrupt_ff      <= 1'b0;
            uart2_interrupt         <= 1'b0;
        end
        else
        begin
            keybord_interrupt_ff    <= keybord_irq;
            keybord_interrupt       <= keybord_interrupt_ff;
            uart_interrupt_ff       <= uart_irq;
            uart_interrupt          <= uart_interrupt_ff;
            uart2_interrupt_ff      <= uart2_irq;
            uart2_interrupt         <= uart2_interrupt_ff;
        end
    end

    logic prev_io_read_n;
    logic prev_io_write_n;
    logic [7:0] write_to_uart;
    logic [7:0] write_to_uart2;
    logic [7:0] uart_readdata_1;
    logic [7:0] uart_readdata;
    logic [7:0] uart2_readdata_1;
    logic [7:0] uart2_readdata;

    always_ff @(posedge clock)
    begin
        prev_io_read_n <= io_read_n;
        prev_io_write_n <= io_write_n;
    end

    logic   [7:0]   keycode_ff;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            keycode_ff  <= 8'h00;
            port_a_in   <= 8'h00;
        end
        else
        begin
            keycode_ff  <= tandy_kbd_en ? tandy_keycode : keycode;
            port_a_in   <= keycode_ff;
        end
    end

    reg [7:0] lpt_reg = 8'hFF;
	 reg [7:0] lpt_ctrl = 8'h00;
	 reg [7:0] lpt_enable_irq = 8'h00;
    reg [7:0] tandy_page_data = 8'h00;
    reg [7:0] nmi_mask_register_data = 8'hFF;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)        
        begin
            xtctl <= 8'b00;
            tandy_page_data <= 8'h00;
            nmi_mask_register_data <= 8'hFF;
        end
        else begin
            if (~io_write_n)
            begin
                write_to_uart <= internal_data_bus;
                write_to_uart2 <= internal_data_bus;
            end
            else
            begin
                write_to_uart <= write_to_uart;
                write_to_uart2 <= write_to_uart2;
            end

            if ((lpt_chip_select) && (~io_write_n) && ~address[0])
                lpt_reg <= internal_data_bus;

            if ((lpt_ctrl_select) && (~io_write_n))
            begin
                lpt_ctrl <= internal_data_bus;
                lpt_enable_irq <= internal_data_bus & 8'h10;
            end

            if ((xtctl_chip_select) && (~io_write_n))
                xtctl <= internal_data_bus;

            if (`ENABLE_TANDY_VIDEO && (tandy_page_chip_select) && (~io_write_n))
                tandy_page_data <= internal_data_bus;

            if (`ENABLE_TANDY_VIDEO && nmi_mask_register && (~io_write_n))
                nmi_mask_register_data <= internal_data_bus;
        end

    end

    wire iorq_uart = (io_write_n & ~prev_io_write_n) || (~io_read_n  & prev_io_read_n);

    uart uart1
    (
        .clk               (clock),
        .br_clk            (clk_uart),
        .reset             (reset),

        .address           (address[2:0]),
        .writedata         (write_to_uart),
        .read              (~io_read_n  & prev_io_read_n),
        .write             (io_write_n & ~prev_io_write_n),
        .readdata          (uart_readdata_1),
        .cs                (uart_chip_select & iorq_uart),
        .rx                (uart_rx),
        .cts_n             (0),
        .dcd_n             (0),
        .dsr_n             (0),
        .ri_n              (1),
        .rts_n             (uart_rts_n),
        .irq               (uart_irq)
    );
	 

    uart uart2
    (
        .clk               (clock),
        .br_clk            (clk_uart),
        .reset             (reset),

        .address           (address[2:0]),
        .writedata         (write_to_uart2),
        .read              (~io_read_n  & prev_io_read_n),
        .write             (io_write_n & ~prev_io_write_n),
        .readdata          (uart2_readdata_1),
        .cs                (uart2_chip_select & iorq_uart),

        .rx                (uart2_rx),
        .tx                (uart2_tx),
        .cts_n             (uart2_cts_n),
        .dcd_n             (uart2_dcd_n),
        .dsr_n             (uart2_dsr_n),
        .rts_n             (uart2_rts_n),
        .dtr_n             (uart2_dtr_n),
        .ri_n              (1),

        .irq               (uart2_irq)
    );

    // Timing of the readings may need to be reviewed.
    always_ff @(posedge clock)
    begin
        if (~io_read_n)
        begin
            uart_readdata <= uart_readdata_1;
            uart2_readdata <= uart2_readdata_1;
        end
        else
        begin
            uart_readdata <= uart_readdata;
            uart2_readdata <= uart2_readdata;
        end
    end


    logic  [16:0]  video_ram_address;
    logic  [7:0]   video_ram_data;
    logic          video_memory_write_n;
    logic          hgc_mem_select_1;
    logic          cga_mem_select_1;
    logic          video_mem_select_1;
    logic  [14:0]  video_io_address;
    logic  [7:0]   video_io_data;
    logic          video_io_write_n;
    logic          video_io_read_n;
    logic          video_address_enable_n;
    logic  [14:0]  hgc_io_address_1;
    logic  [14:0]  hgc_io_address_2;
    logic  [7:0]   hgc_io_data_1;
    logic  [7:0]   hgc_io_data_2;
    logic          hgc_io_write_n_1;
    logic          hgc_io_write_n_2;
    logic          hgc_io_write_n_3;
    logic          hgc_io_read_n_1;
    logic          hgc_io_read_n_2;
    logic          hgc_io_read_n_3;
    logic          hgc_address_enable_n_1;
    logic          hgc_address_enable_n_2;
    logic  [14:0]  cga_io_address_1;
    logic  [14:0]  cga_io_address_2;
    logic  [7:0]   cga_io_data_1;
    logic  [7:0]   cga_io_data_2;
    logic          cga_io_write_n_1;
    logic          cga_io_write_n_2;
    logic          cga_io_read_n_1;
    logic          cga_io_read_n_2;
    logic          cga_address_enable_n_1;
    logic          cga_address_enable_n_2;
    localparam int SPLASH_COPY_SIZE = 4000;
    // 16 KB CGA VRAM. The clear address width sets the inferred RAM depth, so a 14-bit
    // clear lets synthesis trim the VRAM to 16 KB (the declared AW=17 would give 128 KB).
    localparam int TEXT_CLEAR_SIZE = 16384;
    localparam [11:0] SPLASH_COPY_LAST = SPLASH_COPY_SIZE - 1;
    localparam [13:0] TEXT_CLEAR_LAST = TEXT_CLEAR_SIZE - 1;
    logic         splashscreen_ff = 1'b0;
    logic         splash_copy_active = 1'b0;
    logic [11:0]  splash_copy_addr = 12'd0;
    logic         splash_clear_active = 1'b0;
    logic         splash_clear_pending = 1'b0;
    logic [13:0]  splash_clear_addr = 14'd0;
    wire          splash_copy_start = splashscreen & ~splashscreen_ff;
    wire          splash_clear_start = ~splashscreen & splashscreen_ff;
    wire          status0_clear_start = status0_clear;
    wire  [7:0]   splash_rom_data;
    wire          cga_vram_copy = splash_copy_active | splash_clear_active;
    wire  [7:0]   splash_clear_data = 8'h00;

    always_ff @(posedge clock)
    begin
        if (~io_write_n | ~io_read_n)
        begin
            video_io_address    <= address[13:0];
            video_io_data       <= internal_data_bus;
        end
        else
        begin
            video_io_address    <= video_io_address;
            video_io_data       <= video_io_data;
        end
    end

    always_ff @(posedge clock)
    begin
        video_ram_address       <= address[16:0];
        video_ram_data          <= internal_data_bus;
        video_memory_write_n    <= memory_write_n;
        hgc_mem_select_1        <= hgc_mem_select;
        cga_mem_select_1        <= cga_mem_select;
        video_mem_select_1      <= video_mem_select;

        video_io_write_n        <= io_write_n;
        video_io_read_n         <= io_read_n;
        video_address_enable_n  <= address_enable_n;
    end

    always_ff @(posedge clock)
    begin
        splashscreen_ff <= splashscreen;

        if (splash_copy_start)
        begin
            splash_copy_active <= 1'b1;
            splash_copy_addr   <= 12'd0;
        end
        else if (splash_copy_active)
        begin
            if (splash_copy_addr == SPLASH_COPY_LAST)
            begin
                splash_copy_active <= 1'b0;
                splash_copy_addr   <= 12'd0;
            end
            else
            begin
                splash_copy_addr <= splash_copy_addr + 12'd1;
            end
        end
        else
        begin
            splash_copy_active <= 1'b0;
            splash_copy_addr   <= 12'd0;
        end

        if (splash_clear_start || status0_clear_start)
            splash_clear_pending <= 1'b1;

        if (~splash_copy_active && splash_clear_pending && ~splash_clear_active && ~splashscreen)
        begin
            splash_clear_active  <= 1'b1;
            splash_clear_pending <= 1'b0;
            splash_clear_addr    <= 14'd0;
        end
        else if (splash_clear_active)
        begin
            if (splash_clear_addr == TEXT_CLEAR_LAST)
            begin
                splash_clear_active <= 1'b0;
                splash_clear_addr   <= 14'd0;
            end
            else
            begin
                splash_clear_addr <= splash_clear_addr + 14'd1;
            end
        end
        else
        begin
            splash_clear_active <= 1'b0;
            splash_clear_addr   <= 14'd0;
        end
    end

    always_ff @(posedge clk_vga_hgc)
    begin
        if (`ENABLE_HGC)
        begin
            hgc_io_address_1        <= video_io_address;
            hgc_io_address_2        <= hgc_io_address_1;
            hgc_io_data_1           <= video_io_data;
            hgc_io_data_2           <= hgc_io_data_1;
            hgc_io_write_n_1        <= video_io_write_n;
            hgc_io_write_n_2        <= hgc_io_write_n_1;
            hgc_io_write_n_3        <= hgc_io_write_n_2;
            hgc_io_read_n_1         <= video_io_read_n;
            hgc_io_read_n_2         <= hgc_io_read_n_1;
            hgc_io_read_n_3         <= hgc_io_read_n_2;
            hgc_address_enable_n_1  <= video_address_enable_n;
            hgc_address_enable_n_2  <= hgc_address_enable_n_1;
        end
        else
        begin
            hgc_io_address_1        <= 15'd0;
            hgc_io_address_2        <= 15'd0;
            hgc_io_data_1           <= 8'd0;
            hgc_io_data_2           <= 8'd0;
            hgc_io_write_n_1        <= 1'b1;
            hgc_io_write_n_2        <= 1'b1;
            hgc_io_write_n_3        <= 1'b1;
            hgc_io_read_n_1         <= 1'b1;
            hgc_io_read_n_2         <= 1'b1;
            hgc_io_read_n_3         <= 1'b1;
            hgc_address_enable_n_1  <= 1'b1;
            hgc_address_enable_n_2  <= 1'b1;
        end
    end

    always_ff @(posedge clk_vga_cga)
    begin
        if (`ENABLE_CGA)
        begin
            cga_io_address_1        <= video_io_address;
            cga_io_address_2        <= cga_io_address_1;
            cga_io_data_1           <= video_io_data;
            cga_io_data_2           <= cga_io_data_1;
            cga_io_write_n_1        <= video_io_write_n;
            cga_io_write_n_2        <= cga_io_write_n_1;
            cga_io_read_n_1         <= video_io_read_n;
            cga_io_read_n_2         <= cga_io_read_n_1;
            cga_address_enable_n_1  <= video_address_enable_n;
            cga_address_enable_n_2  <= cga_address_enable_n_1;
        end
        else
        begin
            cga_io_address_1        <= 15'd0;
            cga_io_address_2        <= 15'd0;
            cga_io_data_1           <= 8'd0;
            cga_io_data_2           <= 8'd0;
            cga_io_write_n_1        <= 1'b1;
            cga_io_write_n_2        <= 1'b1;
            cga_io_read_n_1         <= 1'b1;
            cga_io_read_n_2         <= 1'b1;
            cga_address_enable_n_1  <= 1'b1;
            cga_address_enable_n_2  <= 1'b1;
        end
    end


    wire  [5:0]   R_CGA;
    wire  [5:0]   G_CGA;
    wire  [5:0]   B_CGA;
    wire          HSYNC_CGA;
    wire          VSYNC_CGA;
    wire          HBLANK_CGA;
    wire          VBLANK_CGA;
    wire          de_o_cga;

    wire [3:0] video_cga;
    wire       hsync_cga_raw;
    wire       hsync_cga_sd;
    wire [3:0] video_cga_raw;
    wire [3:0] video_cga_sd;
    reg   [5:0]   R_HGC;
    reg   [5:0]   G_HGC;
    reg   [5:0]   B_HGC;
    reg           HSYNC_HGC;
    reg           VSYNC_HGC;
    reg           HBLANK_HGC;
    reg           VBLANK_HGC;
    reg           de_o_hgc;
    wire          video_hgc;

    wire swap_video_sel = `ENABLE_HGC ? (`ENABLE_CGA ? (swap_video & ~tandy_video_en) : ~tandy_video_en) : 1'b0;

`ifdef MACHINE_PC98
    // ---------------------------------------------------------- PC-98 video
    //
    // One plane, one mode: 640x400 text on the 21.0526 MHz dot clock, which
    // core_top routes in as clk_vga_cga. The CGA and HGC generators are still
    // instanced below -- they are the PC/AT machine layer and go when it does
    // -- but nothing downstream of here looks at them.
    wire [11:0] tvram_vid_cell_w;   // renderer -> TVRAM, instanced further down
    wire [9:0] pc98_h, pc98_v;
    wire       pc98_hs, pc98_vs, pc98_hb, pc98_vb, pc98_de, pc98_fs;

    // Free-running: the raster does not belong to the guest.
    //
    // Held by `reset`, the timing generator stops whenever the guest does --
    // and the OSD is composited into the frame this produces, so holding the
    // 8088 takes the display with it. That makes every diagnostic that needs
    // the guest stopped, the SDRAM self-test above all, impossible to read: it
    // holds the guest, and the screen goes dark exactly when it has something
    // to say. The splash and the boot hold have the same problem in smaller
    // form.
    //
    // These are free-running counters with no state worth resetting, and the
    // dot clock is up long before anything else, so there is nothing to hold
    // them for.
    pc98_video_timing u_pc98_timing (
        .clk(clk_vga_cga), .ce(1'b1), .rst(1'b0),
        .hcount(pc98_h), .vcount(pc98_v),
        .hsync(pc98_hs), .vsync(pc98_vs),
        .hblank(pc98_hb), .vblank(pc98_vb), .de(pc98_de), .frame_start(pc98_fs)
    );

    // Blink, about 2 Hz: one toggle every 32 frames of 56.4 Hz is 1.76 Hz.
    // Initialised at declaration rather than reset, for the same reason as the
    // timing generator: it must keep running while the guest is held.
    logic [5:0] pc98_blink_cnt = 6'd0;
    logic       pc98_blink     = 1'b1;
    always_ff @(posedge clk_vga_cga) begin
        if (pc98_fs) begin
            pc98_blink_cnt <= pc98_blink_cnt + 6'd1;
            if (pc98_blink_cnt == 6'd31) begin
                pc98_blink_cnt <= 6'd0;
                pc98_blink     <= ~pc98_blink;
            end
        end
    end

    // ------------------------------------------------------ GDC status
    //
    // The CRT interrupt. The text GDC raises IRQ2 once per frame in vertical
    // retrace; the BIOS's FED23 sequence installs a handler on INT 0x0A,
    // unmasks IRQ2 (IMR bit 2), and spins at FED44 until the handler clears
    // 0x53C bit 6 -- which is where the machine sits without this. The raster
    // is already running (it drew the cursor), so its vsync edge IS the
    // interrupt; the 8259 is edge-triggered and one clean edge per frame is
    // exactly what the real GDC gives it. The flag lives here rather than in
    // core_top because everything else the BIOS polls is answered here too.
    logic vs_irq_s1 = 1'b0, vs_irq_s2 = 1'b0, vs_irq_s3 = 1'b0;
    always_ff @(posedge clk_vga_cga) begin
        vs_irq_s1 <= pc98_vs;
        vs_irq_s2 <= vs_irq_s1;
        vs_irq_s3 <= vs_irq_s2;
    end
    wire crt_vsync_irq = vs_irq_s2 & ~vs_irq_s3;

    // The ITF's first hard gate. At F80388 it does IN AL,60h / TEST AL,20h and
    // waits for bit 5 to go low, high, low -- twice -- before it will go on.
    // With that port answering a constant it spins there forever, which is
    // exactly what the hardware showed: LIVE parked at 08383, which is ROM
    // offset 0383 because (F8000 + off) & FFFF is 8000 + off.
    //
    // uPD7220 status: [7] light pen, [6] HBLANK, [5] VSYNC, [4] DMA execute,
    // [3] drawing, [2] FIFO empty, [1] FIFO full, [0] data ready. Nothing here
    // has a command FIFO yet, so it reports permanently empty and ready, and
    // the two timing bits come from the raster the renderer is already running.
    //
    // Crossing into the chipset clock: two flops, because a status bit read one
    // cycle stale is a status bit, and a metastable one is a coin toss.
    logic gdc_vs_s1, gdc_vs_q, gdc_hb_s1, gdc_hb_q;
    always_ff @(posedge clock) begin
        gdc_vs_s1 <= pc98_vs;  gdc_vs_q <= gdc_vs_s1;
        gdc_hb_s1 <= pc98_hb;  gdc_hb_q <= gdc_hb_s1;
    end
    wire [7:0] gdc_status = {1'b0, gdc_hb_q, gdc_vs_q, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1};

    // Text GDC at 0x60, graphics GDC at 0xA0. Both answer the same status: the
    // ITF checks both, and both watch the same raster.
    wire gdc_stat_select = pc98_io_exact & ((address[7:0] == 8'h60) | (address[7:0] == 8'hA0));
    wire gdc_stat_read   = gdc_stat_select & ~io_read_n;

    // ------------------------------------------------- system port stubs
    //
    // 0x35 is the 8255's port C on a PC-98, and the BIOS reads it on its second
    // instruction: FD809 is IN AL,35h / TEST AL,80h / JNZ. Bits 7 and 5 have to
    // read 1 or it branches away before it has done anything. The 8255 here is
    // a real chip with its port C pins tied off, so the read is answered
    // directly rather than by inventing pin values for it.
    //
    // 0x42 is the printer side of 0x40-0x4F; the ITF trace has it tested for
    // bit 1 clear. Zero satisfies that and claims nothing else.
    wire sysport_35_select = pc98_io_exact & (address[7:0] == 8'h35);
    wire sysport_42_select = pc98_io_exact & (address[7:0] == 8'h42);
    wire sysport_read      = (sysport_35_select | sysport_42_select) & ~io_read_n;
    wire [7:0] sysport_data = sysport_35_select ? 8'hA0 : 8'h00;

    wire [7:0] pc98_font_row;      // driven by the row buffer below
    wire [6:0] pc98_font_cell;
    wire [3:0] pc98_font_line;
    wire [2:0] pc98_grb;
    wire       pc98_pixel, pc98_kanji_seen;

    pc98_text_render u_pc98_text (
        .clk(clk_vga_cga), .pix_ce(1'b1),
        .hcount(pc98_h), .vcount(pc98_v), .blink_on(pc98_blink),
        .tv_cell(tvram_vid_cell_w), .tv_attr(tvram_vid_attr),
        .font_cell(pc98_font_cell), .font_line(pc98_font_line),
        .font_row(pc98_font_row),
        .grb(pc98_grb), .pixel(pc98_pixel)
    );

    // ------------------------------------------------- glyphs, out of SDRAM
    //
    // The ANK font in BRAM covers 256 characters; the kanji is 282 KB and
    // lives in SDRAM. Rather than two sources in the renderer, EVERY glyph now
    // comes through the row buffer, which fetches a text row's worth at a time
    // over the controller's second port.
    //
    // The fill runs on the chipset clock -- that is where the TVRAM and the
    // SDRAM port are -- and the renderer reads on the dot clock, so the start
    // of a row crosses domains as a toggle rather than a synchronised pulse
    // (pulse_cdc).
    wire       pc98_row_fill;
    wire       pc98_fill_busy;

    // One pulse at the top of each text row, on the dot clock: line 0 of the
    // cell, first dot. The row FETCHED is the NEXT one, because the buffer is
    // double-buffered and the renderer is reading the row being displayed.
    wire pc98_row_tick = pc98_de && (pc98_h == 10'd0) && (pc98_v[3:0] == 4'd0);
    logic pc98_row_tick_q;
    always_ff @(posedge clk_vga_cga) pc98_row_tick_q <= pc98_row_tick;
    wire pc98_row_start = pc98_row_tick & ~pc98_row_tick_q;

    pulse_cdc u_pc98_rowsync (
        .src_clk(clk_vga_cga), .src_rst(reset), .src_pulse(pc98_row_start),
        .src_busy(),
        .dst_clk(clock), .dst_rst(reset), .dst_pulse(pc98_row_fill)
    );

    // row * 80 for the row after the one on screen.
    wire [4:0]  pc98_next_row  = (pc98_v[8:4] == 5'd24) ? 5'd0 : pc98_v[8:4] + 5'd1;
    wire [11:0] pc98_row_base  = {1'b0, pc98_next_row, 6'd0}
                              + {3'd0, pc98_next_row, 4'd0};

    wire        pc98_f_req, pc98_f_busy, pc98_f_valid;
    wire [19:0] pc98_f_addr;
    wire  [7:0] pc98_f_data;

    pc98_glyph_rowbuf u_pc98_rowbuf (
        .clk(clock), .rst(reset),
        .fill_start(pc98_row_fill), .row_base(pc98_row_base),
        .bitac(8'hFF), .busy(pc98_fill_busy),
        .tv_cell(tvram_fil_cell),
        .tv_char_lo(tvram_vid_char_lo), .tv_char_hi(tvram_vid_char_hi),
        .f_req(pc98_f_req), .f_addr(pc98_f_addr), .f_busy(pc98_f_busy),
        .f_valid(pc98_f_valid), .f_data(pc98_f_data),
        // Indexed by the cell the renderer is FETCHING, not the one it is
        // drawing: it runs one cell ahead, and using the current column here
        // would shift every line by one.
        .rd_clk(clk_vga_cga), .rd_cell(pc98_font_cell), .rd_line(pc98_font_line),
        .rd_byte(pc98_font_row), .kanji_seen(pc98_kanji_seen)
    );

    // ------------------------------------------------------- CG window
    //
    // The guest reads glyphs through A4000-A4FFF, having set the code on ports
    // 0x00A1/0x00A3/0x00A5. Its own SDRAM port, because it is idle almost all
    // the time -- one prefetch per character asked for -- while the row buffer
    // runs for the whole visible frame.
    //
    // The port decode is qualified the way every other one here had to be, and
    // for the same reason: address and command lines do not change together, so
    // a write on its way to another port sweeps through these for a cycle. A
    // corrupted window makes the guest draw the wrong character, which is
    // harder to notice than a corrupted POST code.
    wire cg_io_hit = ~io_write_n & ~address_enable_n
                   & ((address[15:0] == 16'h00A1)
                   |  (address[15:0] == 16'h00A3)
                   |  (address[15:0] == 16'h00A5));
    logic cg_io_q, cg_io_qq;
    logic  [7:0] cg_io_data;
    logic [15:0] cg_io_port;
    logic        cg_io_commit;

    always_ff @(posedge clock) begin
        cg_io_commit <= 1'b0;
        if (reset) begin
            cg_io_q <= 1'b0; cg_io_qq <= 1'b0;
        end else begin
            cg_io_q  <= cg_io_hit;
            cg_io_qq <= cg_io_q;
            if (cg_io_hit) begin
                cg_io_data <= internal_data_bus;
                cg_io_port <= address[15:0];
            end
            if (cg_io_q && cg_io_qq && ~cg_io_hit) cg_io_commit <= 1'b1;
        end
    end

    wire [7:0] cgwin_q;
    wire       cg_f_req, cg_f_busy, cg_f_valid;
    wire [19:0] cg_f_addr;
    wire  [7:0] cg_f_data;

    pc98_cgwindow u_pc98_cgwin (
        .clk(clock), .rst(reset),
        .io_wr(cg_io_commit), .io_port(cg_io_port), .io_data(cg_io_data),
        .rd_addr(address[11:0]), .rd_data(cgwin_q),
        .f_req(cg_f_req), .f_addr(cg_f_addr), .f_busy(cg_f_busy),
        .f_valid(cg_f_valid), .f_data(cg_f_data), .busy()
    );

    pc98_font_fetch u_pc98_cgfetch (
        .clk(clock), .rst(reset),
        .f_req(cg_f_req), .f_addr(cg_f_addr), .f_busy(cg_f_busy),
        .f_valid(cg_f_valid), .f_data(cg_f_data),
        .p_req(cg_rd_req), .p_addr(cg_rd_addr), .p_len(cg_rd_len),
        .p_ack(cg_rd_ack), .p_rvalid(cg_rd_valid), .p_rdata(cg_rd_data),
        .p_done(cg_rd_done)
    );

    pc98_font_fetch u_pc98_fetch (
        .clk(clock), .rst(reset),
        .f_req(pc98_f_req), .f_addr(pc98_f_addr), .f_busy(pc98_f_busy),
        .f_valid(pc98_f_valid), .f_data(pc98_f_data),
        .p_req(font_rd_req), .p_addr(font_rd_addr), .p_len(font_rd_len),
        .p_ack(font_rd_ack), .p_rvalid(font_rd_valid), .p_rdata(font_rd_data),
        .p_done(font_rd_done)
    );

    // The ANK BRAM stays for the CG window at A4000-A4FFF, which the guest
    // reads directly and which does not want to wait on a burst.
    wire [7:0] pc98_ank_row_unused;
    pc98_font_ank u_pc98_font (
        .wr_clk(font_wr_clk), .wr_en(font_wr_en),
        .wr_addr(font_wr_addr), .wr_data(font_wr_data),
        .rd_clk(clk_vga_cga),
        .code(8'h00), .line(4'd0),
        .row(pc98_ank_row_unused)
    );

    // The attribute's colour field is G R B, so it maps to the output that way
    // round. Full intensity: PC-98 text has no half-bright.
    assign VGA_R     = (pc98_pixel & pc98_grb[1]) ? 6'h3F : 6'h00;
    assign VGA_G     = (pc98_pixel & pc98_grb[2]) ? 6'h3F : 6'h00;
    assign VGA_B     = (pc98_pixel & pc98_grb[0]) ? 6'h3F : 6'h00;
    assign VGA_HSYNC = pc98_hs;
    assign VGA_VSYNC = pc98_vs;
    assign VGA_HBlank = pc98_hb;
    assign VGA_VBlank = pc98_vb;
    assign de_o      = pc98_de;
`else
    assign VGA_R = swap_video_sel ? R_HGC : (`ENABLE_CGA ? R_CGA : 6'd0);
    assign VGA_G = swap_video_sel ? G_HGC : (`ENABLE_CGA ? G_CGA : 6'd0);
    assign VGA_B = swap_video_sel ? B_HGC : (`ENABLE_CGA ? B_CGA : 6'd0);
    assign VGA_HSYNC = swap_video_sel ? HSYNC_HGC : (`ENABLE_CGA ? HSYNC_CGA : 1'b0);
    assign VGA_VSYNC = swap_video_sel ? VSYNC_HGC : (`ENABLE_CGA ? VSYNC_CGA : 1'b0);

    assign VGA_HBlank = swap_video_sel ? HBLANK_HGC : (`ENABLE_CGA ? HBLANK_CGA : 1'b0);
    assign VGA_VBlank = swap_video_sel ? VBLANK_HGC : (`ENABLE_CGA ? VBLANK_CGA : 1'b0);

    assign de_o = swap_video_sel ? de_o_hgc : (`ENABLE_CGA ? de_o_cga : 1'b0);
`endif
    assign HSYNC_CGA = cga_scandouble_en ? hsync_cga_sd : hsync_cga_raw;
    assign video_cga = cga_scandouble_en ? video_cga_sd : video_cga_raw;

    wire HGC_VRAM_ENABLE;
    wire [18:0] HGC_VRAM_ADDR;
    wire [7:0] HGC_VRAM_DOUT;
    wire HGC_CRTC_OE;
    reg  HGC_CRTC_OE_1;
    reg  HGC_CRTC_OE_2;
    wire [7:0] HGC_CRTC_DOUT;
    reg  [7:0] HGC_CRTC_DOUT_1;
    reg  [7:0] HGC_CRTC_DOUT_2;

    wire intensity;


    hgc_vgaport vga_hgc 
    (
        .clk(clk_vga_hgc),
        .video(video_hgc),
        .intensity(intensity),
        .red(R_HGC),
        .green(G_HGC),
        .blue(B_HGC),
        .hgc_rgb(hgc_rgb)
    );

    hgc hgc1
    (
        .clk                        (clk_vga_hgc),
        .bus_a                      (hgc_io_address_2),
        .bus_ior_l                  (hgc_io_read_n_3),
        .bus_iow_l                  (hgc_io_write_n_3),
        .bus_memr_l                 (1'd0),
        .bus_memw_l                 (1'd0),
        .bus_d                      (hgc_io_data_2),
        .bus_out                    (HGC_CRTC_DOUT),
        .bus_dir                    (HGC_CRTC_OE),
        .bus_aen                    (hgc_address_enable_n_2),
        .ram_we_l                   (HGC_VRAM_ENABLE),
        .ram_a                      (HGC_VRAM_ADDR),
        .ram_d                      (HGC_VRAM_DOUT),
        .hsync                      (HSYNC_HGC),
        .hblank                     (HBLANK_HGC),
        .vsync                      (VSYNC_HGC),
        .vblank                     (VBLANK_HGC),
        .intensity                  (intensity),
        .video                      (video_hgc),
        .de_o                       (de_o_hgc),
        .grph_mode                  (hgc_grph_mode),
        .grph_page                  (hgc_grph_page),
        .std_hsyncwidth             (std_hsyncwidth_hgc),
        .vblank_border              (vblank_border_hgc),
        .hercules_hw                (hercules_hw)

    );

    always_ff @(posedge clock)
    begin
        if (`ENABLE_HGC)
        begin
            HGC_CRTC_DOUT_1 <= HGC_CRTC_DOUT;
            HGC_CRTC_DOUT_2 <= HGC_CRTC_DOUT_1;
            HGC_CRTC_OE_1   <= HGC_CRTC_OE;
            HGC_CRTC_OE_2   <= HGC_CRTC_OE_1;
        end
        else
        begin
            HGC_CRTC_DOUT_1 <= 8'h00;
            HGC_CRTC_DOUT_2 <= 8'h00;
            HGC_CRTC_OE_1   <= 1'b0;
            HGC_CRTC_OE_2   <= 1'b0;
        end
    end


    wire CGA_VRAM_ENABLE;
    wire [18:0] CGA_VRAM_ADDR;
    wire [7:0] CGA_VRAM_DOUT;
    wire        CGA_CRTC_OE;
    logic       CGA_CRTC_OE_1;
    logic       CGA_CRTC_OE_2;
    wire [7:0]  CGA_CRTC_DOUT;
    logic [7:0] CGA_CRTC_DOUT_1;
    logic [7:0] CGA_CRTC_DOUT_2;
    wire        VGA_VBlank_border_raw;
    wire        std_hsyncwidth_raw;
    wire        tandy_color_16_raw;
    wire        std_hsyncwidth_hgc;
    wire        vblank_border_hgc;

    // Sets up the card to generate a video signal
    // that will work with a standard VGA monitor
    // connected to the VGA port.
    localparam HGC_70HZ = 0;

    // wire composite_on;
    wire thin_font;

    // Composite mode switch
    //assign composite_on = switch3; (TODO: Test in next version, from the original Graphics Gremlin sources)

    // Thin font switch (TODO: switchable with Keyboard shortcut)
    assign thin_font = 1'b0; // Default: No thin font

    wire composite_cga = tandy_video_en ? (swap_video ? ~composite : composite) : composite;

    assign VGA_VBlank_border = `ENABLE_CGA ? VGA_VBlank_border_raw : (`ENABLE_HGC ? vblank_border_hgc : 1'b0);
    assign std_hsyncwidth = `ENABLE_CGA ? std_hsyncwidth_raw : (`ENABLE_HGC ? std_hsyncwidth_hgc : 1'b0);
    assign tandy_color_16 = `ENABLE_CGA ? tandy_color_16_raw : 1'b0;


    // CGA digital to analog converter
    cga_vgaport vga_cga 
    (
        .clk(clk_vga_cga),
        .clkdiv(clkdiv),
        .video(video_cga),
        .hblank(HBLANK_CGA),
        .composite(composite_cga),
        .red(R_CGA),
        .green(G_CGA),
        .blue(B_CGA)
    );

    cga cga1 
    (
        .clk                        (clk_vga_cga),
        .clkdiv                     (clkdiv),
        .bus_a                      (cga_io_address_2),
        .bus_ior_l                  (cga_io_read_n_2),
        .bus_iow_l                  (cga_io_write_n_2),
        .bus_memr_l                 (1'd0),
        .bus_memw_l                 (1'd0),
        .bus_d                      (cga_io_data_2),
        .bus_out                    (CGA_CRTC_DOUT),
        .bus_dir                    (CGA_CRTC_OE),
        .bus_aen                    (cga_address_enable_n_2),
        .ram_we_l                   (CGA_VRAM_ENABLE),
        .ram_a                      (CGA_VRAM_ADDR),
        .ram_d                      (CGA_VRAM_DOUT),
        .hsync                      (hsync_cga_raw),
        .dbl_hsync                  (hsync_cga_sd),
        .hblank                     (HBLANK_CGA),
        .vsync                      (VSYNC_CGA),
        .vblank                     (VBLANK_CGA),
        .vblank_border              (VGA_VBlank_border_raw),
        .std_hsyncwidth             (std_hsyncwidth_raw),
        .de_o                       (de_o_cga),
        .video                      (video_cga_raw),
        .dbl_video                  (video_cga_sd),
        .splashscreen               (splashscreen),
        .thin_font                  (thin_font),
        .tandy_video                (tandy_video_en),
        .scandouble_en              (cga_scandouble_en),
        .grph_mode                  (grph_mode),
        .hres_mode                  (hres_mode),
        .tandy_color_16             (tandy_color_16_raw),
        .cga_hw                     (cga_hw),
        .crt_h_offset               (crt_h_offset),
        .crt_v_offset               (crt_v_offset),
        .vsync_width_osd            (vsync_width_osd),
        .hsync_width_osd            (hsync_width_osd)
    );

    always_ff @(posedge clock)
    begin
        if (`ENABLE_CGA)
        begin
            CGA_CRTC_OE_1   <= CGA_CRTC_OE;
            CGA_CRTC_OE_2   <= CGA_CRTC_OE_1;
            CGA_CRTC_DOUT_1 <= CGA_CRTC_DOUT;
            CGA_CRTC_DOUT_2 <= CGA_CRTC_DOUT_1;
        end
        else
        begin
            CGA_CRTC_OE_1   <= 1'b0;
            CGA_CRTC_OE_2   <= 1'b0;
            CGA_CRTC_DOUT_1 <= 8'h00;
            CGA_CRTC_DOUT_2 <= 8'h00;
        end
    end


    defparam cga1.BLINK_MAX = 24'd4772727;
    defparam hgc1.BLINK_MAX = 24'd5166000;
`ifdef MACHINE_PC98
    wire [7:0]  tvram_cpu_q;
    wire [11:0] tvram_vid_cell = tvram_vid_cell_w;   // renderer, attributes
    wire [11:0] tvram_fil_cell;                      // row buffer, codes
    wire [7:0]  tvram_vid_char_lo, tvram_vid_char_hi, tvram_vid_attr;

    pc98_tvram u_tvram (
        .clk         (clock),
        .cpu_addr    (address[13:0]),
        .cpu_wren    (tvram_mem_select & ~memory_write_n),
        .cpu_wdata   (internal_data_bus),
        .cpu_q       (tvram_cpu_q),
        // Character codes to the row buffer, on the chipset clock.
        .fil_clk     (clock),
        .fil_cell    (tvram_fil_cell),
        .fil_char_lo (tvram_vid_char_lo),
        .fil_char_hi (tvram_vid_char_hi),
        // The attribute to the renderer, on the dot clock.
        .vid_clk     (clk_vga_cga),
        .vid_cell    (tvram_vid_cell),
        .vid_attr    (tvram_vid_attr)
    );
`endif

    wire [7:0] cga_vram_cpu_dout;
    wire [7:0] hgc_vram_cpu_dout;

    splash_rom splash_rom_inst
    (
        .addr       (splash_copy_addr),
        .data       (splash_rom_data)
    );

    wire [13:0] cga_copy_addr  = splash_copy_active ? {2'd0, splash_copy_addr} : splash_clear_addr;
    wire [7:0]  cga_copy_data  = splash_copy_active ? splash_rom_data : splash_clear_data;
    wire [16:0] cga_vram_addra = `ENABLE_CGA ? (cga_vram_copy ? cga_copy_addr :
                                 (tandy_video_en ? (video_mem_select_1 ? video_ram_address :
                                 (tandy_page_data[3] ? {tandy_page_data[5:3], video_ram_address[13:0]} :
                                 {tandy_page_data[5:4], video_ram_address[14:0]})) : {3'b000, video_ram_address[13:0]})) : 17'd0;
    wire [16:0] cga_vram_addrb = `ENABLE_CGA ? (tandy_video_en ?
                                 ((grph_mode & hres_mode) ? {tandy_page_data[2:1], CGA_VRAM_ADDR[14:0]} :
                                 {tandy_page_data[2:0], CGA_VRAM_ADDR[13:0]}) : {3'b000, CGA_VRAM_ADDR[13:0]}) : 17'd0;
    wire [7:0]  cga_vram_dina  = cga_vram_copy ? cga_copy_data : video_ram_data;
    wire        cga_vram_ena   = `ENABLE_CGA ? (cga_vram_copy ? 1'b1 : (cga_mem_select_1 || video_mem_select_1)) : 1'b0;
    wire        cga_vram_wea   = `ENABLE_CGA ? (cga_vram_copy ? 1'b1 : (~video_memory_write_n & memory_write_n)) : 1'b0;
    wire        cga_vram_enb   = `ENABLE_CGA ? CGA_VRAM_ENABLE : 1'b0;

    vram #(.AW(17)) cga_vram
    (
        .clka                       (clock),
        .ena                        (cga_vram_ena),
        .wea                        (cga_vram_wea),
        .addra                      (cga_vram_addra),
        .dina                       (cga_vram_dina),
        .douta                      (cga_vram_cpu_dout),
        .clkb                       (clk_vga_cga),
        .web                        (1'b0),
        .enb                        (cga_vram_enb),
        .addrb                      (cga_vram_addrb),
        .dinb                       (8'h0),
        .doutb                      (CGA_VRAM_DOUT)
    );

    wire hgc_vram_ena = `ENABLE_HGC ? hgc_mem_select_1 : 1'b0;
    wire hgc_vram_enb = `ENABLE_HGC ? HGC_VRAM_ENABLE : 1'b0;

    vram #(.AW(16)) hgc_vram
    (
        .clka                       (clock),
        .ena                        (hgc_vram_ena),
        .wea                        (`ENABLE_HGC ? ~video_memory_write_n : 1'b0),
        .addra                      ({hgc_grph_page, video_ram_address[14:0]}),
        .dina                       (video_ram_data),
        .douta                      (hgc_vram_cpu_dout),
        .clkb                       (clk_vga_hgc),
        .web                        (1'b0),
        .enb                        (hgc_vram_enb),
        .addrb                      ({hgc_grph_page, HGC_VRAM_ADDR[14:0]}),
        .dinb                       (8'h0),
        .doutb                      (HGC_VRAM_DOUT)
    );


    //
    // XT2IDE
    //
    logic   [7:0]   xt2ide0_data_bus_out;
    logic           ide0_cs1fx;
    logic           ide0_cs3fx;
    logic           ide0_io_read_n;
    logic           ide0_io_write_n;
    logic   [2:0]   ide0_address;
    logic   [15:0]  ide0_data_bus_in;
    logic   [15:0]  ide0_data_bus_out;

    XT2IDE xt2ide0 (
        .clock              (clock),
        .reset              (reset),

        .high_speed         (0),

        .chip_select_n      (ide0_chip_select_n),
        .io_read_n          (io_read_n),
        .io_write_n         (io_write_n),

        .address            (address[3:0]),
        .data_bus_in        (internal_data_bus),
        .data_bus_out       (xt2ide0_data_bus_out),

        .ide_cs1fx          (ide0_cs1fx),
        .ide_cs3fx          (ide0_cs3fx),
        .ide_io_read_n      (ide0_io_read_n),
        .ide_io_write_n     (ide0_io_write_n),

        .ide_address        (ide0_address),
        .ide_data_bus_in    (ide0_data_bus_in),
        .ide_data_bus_out   (ide0_data_bus_out)
    );


    //
    // IDE
    //
    logic           mgmt_ide0_cs;
    logic [15:0]    mgmt_ide0_readdata;
    logic           ide0_command_cs;
    logic           ide0_control_cs;
    logic           ide0_comd_ctrl_select;
    logic           ide0_io_read;
    logic           ide0_io_read_1;
    logic           ide0_io_write;
    logic           prev_ide0_io_read;
    logic           prev_ide0_io_write;
    logic [3:0]     ide0_address_1;
    logic [15:0]    ide0_writedata;
    logic [15:0]    ide_readdata;
    logic           ide_ignore;

    assign mgmt_ide0_cs     = (mgmt_address[15:8] == 8'hF0);

    assign ide0_command_cs  = ~ide0_cs1fx;
    assign ide0_control_cs  = ~ide0_cs3fx & &ide0_address[2:1];
    assign ide0_io_read     = ~ide0_io_read_n  & (ide0_command_cs | ide0_control_cs);
    assign ide0_io_write    = ~ide0_io_write_n & (ide0_command_cs | ide0_control_cs);

    always_ff @(posedge clock)
    begin
        ide0_io_read_1          <= ide0_io_read;
        prev_ide0_io_read       <= ide0_io_read_1;
        prev_ide0_io_write      <= ide0_io_write;
        ide0_address_1          <= ~ide0_control_cs ? {1'b0, ide0_address} : {1'b1, ide0_address};
        ide0_writedata          <= ide0_data_bus_out;
    end

    ide ide
    (
        .clk            (clock),
        .rst_n          (~reset),

//        .irq            (),
//        .drq            (),

        .use_fast       (0),
//        .no_data        (),

//        .drive_en       (),

        .io_address     (ide0_address_1),
        .io_read        (ide0_io_read   & ~prev_ide0_io_read),
        .io_readdata    (ide_readdata),
        .io_write       (~ide0_io_write & prev_ide0_io_write),
        .io_writedata   (ide0_writedata),
        .io_32          (0),

//        .io_wait        (),

        .request                    (ide0_request),
        .mgmt_address               (mgmt_address[3:0]),
        .mgmt_writedata             (mgmt_writedata),
        .mgmt_readdata              (mgmt_ide0_readdata),
        .mgmt_write                 (mgmt_write & mgmt_ide0_cs),
        .mgmt_read                  (mgmt_read & mgmt_ide0_cs),

        .primary_only               (use_mmc == 2'b10),
        .secondary_only             (use_mmc == 2'b01),
        .ignore_access              (ide_ignore)
    );


    //
    // XTIDE-MMC
    //
    logic [15:0]    mmcide_readdata;
    wire    enable_mmc_n    = ~((use_mmc == 2'b01) | (use_mmc == 2'b10));

    KFMMC_DRIVE_IDE #(
        .init_spi_clock_cycle               (8'd150),
        .normal_spi_clock_cycle             (8'd002)
    ) u_KFMMC_DRIVE_IDE (
        .clock              (clock),
        .reset              (reset),

        .ide_cs1fx_n        (ide0_cs1fx),
        .ide_cs3fx_n        (ide0_cs3fx),
        .ide_io_read_n      (ide0_io_read_n  | enable_mmc_n),
        .ide_io_write_n     (ide0_io_write_n | enable_mmc_n),

        .ide_address        (ide0_address),
        .ide_data_bus_in    (ide0_data_bus_out),
        .ide_data_bus_out   (mmcide_readdata),

        .device_master      (use_mmc == 2'b01),

        .spi_clk            (spi_clk),
        .spi_cs             (spi_cs),
        .spi_mosi           (spi_mosi),
        .spi_miso           (spi_miso)

    );

    assign ide0_data_bus_in = ~ide_ignore ? ide_readdata : mmcide_readdata;


    //
    // FDC
    //
    logic           mgmt_fdd_cs;
    logic   [15:0]  mgmt_fdd_readdata;
    logic   [7:0]   write_to_fdd;
    logic   [2:0]   fdd_io_address;
    logic           fdd_io_read;
    logic           fdd_io_read_1;
    logic           fdd_io_write;
    logic   [7:0]   fdd_readdata_wire;
    logic   [7:0]   fdd_dma_readdata;
    logic   [7:0]   fdd_readdata;
    logic           fdd_dma_req_wire;
    logic           fdd_dma_read;
    logic           prev_fdd_dma_ack;
    logic           fdd_dma_rw_ack;
    logic           fdd_dma_tc;

    assign  mgmt_fdd_cs = (mgmt_address[15:8] == 8'hF2);

    always_ff @(posedge clock)
    begin
        if (mgmt_write & mgmt_fdd_cs & (mgmt_address[3:0] == 4'd0))
            fdd_present[mgmt_address[7]] <= mgmt_writedata[0];
    end

    always_ff @(posedge clock)
    begin
        if (~io_write_n)
            write_to_fdd  <= internal_data_bus;
        else
            write_to_fdd  <= write_to_fdd;
    end

    always_ff @(posedge clock)
    begin
        fdd_io_address     <= address[2:0];
        fdd_io_read        <= ~io_read_n & prev_io_read_n   & ~floppy0_chip_select_n;
        fdd_io_read_1      <= fdd_io_read;
        fdd_io_write       <= io_write_n & ~prev_io_write_n & ~floppy0_chip_select_n;
    end

    assign  fdd_dma_read    = fdd_dma_ack & ~io_read_n;

    always_ff @(posedge clock)
    begin
        prev_fdd_dma_ack   <= fdd_dma_ack;
    end

    assign  fdd_dma_rw_ack  = prev_fdd_dma_ack & ~fdd_dma_ack;

    always_ff @(posedge clock)
    begin
        if (fdd_dma_ack)
            if (fdd_dma_tc == 1'b0)
                fdd_dma_tc <= terminal_count;
            else
                fdd_dma_tc <= fdd_dma_tc;
        else
            fdd_dma_tc <= 1'b0;
    end

    floppy floppy 
    (
        .clk                        (clock),
        .rst_n                      (~reset),

        //dma
        .dma_req                    (fdd_dma_req_wire),
        .dma_ack                    (fdd_dma_rw_ack),
        .dma_tc                     (fdd_dma_tc & fdd_dma_rw_ack),
        .dma_readdata               (write_to_fdd),
        .dma_writedata              (fdd_dma_readdata),

        //irq
        .irq                        (fdd_interrupt),

        //io buf
        .io_address                 (fdd_io_address),
        .io_read                    (fdd_io_read),
        .io_readdata                (fdd_readdata_wire),
        .io_write                   (fdd_io_write),
        .io_writedata               (write_to_fdd),

        //        .fdd0_inserted              (),

        .mgmt_address               (mgmt_address[3:0]),
        .mgmt_fddn                  (mgmt_address[7]),
        .mgmt_write                 (mgmt_write & mgmt_fdd_cs),
        .mgmt_writedata             (mgmt_writedata),
        .mgmt_read                  (mgmt_read  & mgmt_fdd_cs),
        .mgmt_readdata              (mgmt_fdd_readdata),

        .wp                         (floppy_wp),

        .clock_rate                 (clk_select[1] == 1'b0 ? clk_rate :
                                     clk_select[0] == 1'b0 ? {1'b0, clk_rate[27:1]} : {2'b00, clk_rate[27:2]}),

        .request                    (fdd_request)
    );

    always_ff @(posedge clock)
    begin
        if (fdd_dma_ack)
            fdd_dma_req <= 1'b0;
        else if (cpu_ce_negedge)
            fdd_dma_req <= fdd_dma_req_wire;
        else
            fdd_dma_req <= fdd_dma_req;
    end

    always_ff @(posedge clock)
    begin
        if ((fdd_io_read_1) && (~address_enable_n))
            fdd_readdata <= fdd_readdata_wire;
        else if (fdd_dma_read)
            fdd_readdata <= fdd_dma_readdata;
        else
            fdd_readdata <= fdd_readdata;
    end


    //
    // mgmt_readdata
    //
    assign mgmt_readdata = mgmt_ide0_cs ? mgmt_ide0_readdata : mgmt_fdd_readdata;


    //
    // KFTVGA
    //
    
    // logic   [7:0]   tvga_data_bus_out;

    // KFTVGA u_KFTVGA (
    //     // Bus
    //     .clock                      (clock),
    //     .reset                      (reset),
    //     .chip_select_n              (tvga_chip_select_n),
    //     .read_enable_n              (memory_read_n),
    //     .write_enable_n             (memory_write_n),
    //     .address                    (address[13:0]),
    //     .data_bus_in                (internal_data_bus),
    //     .data_bus_out               (tvga_data_bus_out),

    //     // I/O
    //     .video_clock                (video_clock),
    //     .video_reset                (video_reset),
    //     .video_h_sync               (video_h_sync),
    //     .video_v_sync               (video_v_sync),
    //     .video_r                    (video_r),
    //     .video_g                    (video_g),
    //     .video_b                    (video_b)
    // );

	 
    // RTC
	 
    logic           mgmt_rtc_cs;
    logic   [7:0]   rtc_readdata;
	 
    assign mgmt_rtc_cs   = (mgmt_address[15:8] == 8'hF4);

    rtc rtc
    (
       .clk               (clock),
       .rst_n             (~reset),

       .clock_rate        (clk_rate),

       .io_address        (address[0]),
       .io_writedata      (internal_data_bus),
       .io_read           (~io_read_n & rtc_chip_select),
       .io_write          (~io_write_n & rtc_chip_select),
       .io_readdata       (rtc_readdata),

       .mgmt_address      (mgmt_address),
       .mgmt_write        (mgmt_write & mgmt_rtc_cs),
       .mgmt_writedata    (mgmt_writedata[7:0]),

       .memcfg            (1'b0),
       .bootcfg           (5'd0)
    );
    

    //
    // Joysticks
    //

    logic [7:0] joy_data;

    tandy_pcjr_joy joysticks
    (
        .clk                       (clock),
        .reset                     (reset),
        .en                        (joystick_select && ~io_write_n),
        .clk_select                (clk_select),
        .joy_opts                  (joy_opts),
        .joy0                      (joy0),
        .joy1                      (joy1),
        .joya0                     (joya0),
        .joya1                     (joya1),
        .d_out                     (joy_data)
    );


    //
    // data_bus_out
    //
    
    always_ff @(posedge clock)
    begin
        if (~interrupt_acknowledge_n)
        begin
            // During the acknowledge the master either drives its own vector
            // or puts the slave's ID on the cascade lines and stands down --
            // data_bus_io is how the slave says it recognized itself.
            data_bus_out_from_chipset <= 1'b1;
`ifdef MACHINE_PC98
            data_bus_out <= (~interrupt2_data_bus_io) ? interrupt2_data_bus_out
                                                      : interrupt_data_bus_out;
`else
            data_bus_out <= interrupt_data_bus_out;
`endif
        end
`ifdef MACHINE_PC98
        else if ((~interrupt2_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= interrupt2_data_bus_out;
        end
`endif
        else if ((~interrupt_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= interrupt_data_bus_out;
        end
        else if ((~timer_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= timer_data_bus_out;
        end
        else if ((~ppi_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ppi_data_bus_out;
        end
`ifdef MACHINE_PC98
        else if (sysport_read)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= sysport_data;
        end
        else if (gdc_stat_read)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= gdc_status;
        end
        else if (fdd_stub_read)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= fdd_stub_data;
        end
        else if (tvram_mem_select && (~memory_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= tvram_cpu_q;
        end
        else if (cgwin_mem_select && (~memory_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= cgwin_q;
        end
`endif
        else if (`ENABLE_CGA && cga_mem_select && (~memory_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= cga_vram_cpu_dout;
        end
        else if (`ENABLE_HGC && hgc_mem_select && (~memory_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= hgc_vram_cpu_dout;
        end
        else if (`ENABLE_CGA && CGA_CRTC_OE_2)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= CGA_CRTC_DOUT_2;
        end
        else if (`ENABLE_HGC && HGC_CRTC_OE_2)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= HGC_CRTC_DOUT_2;
        end
        else if (`ENABLE_OPL2 && (opl_228_chip_select || opl_388_chip_select) && ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= jtopl2_dout;
        end
        else if (cms_rd && ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= data_from_cms;
        end
        else if ((uart_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= uart_readdata;
        end
        else if ((uart2_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= uart2_readdata;
        end
        else if (`ENABLE_EMS && (ems_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ena_ems[address[1:0]] ? map_ems[address[1:0]] : 8'hFF;
        end
        else if ((lpt_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= address[0] ? 8'hDF : lpt_reg;
        end
        else if ((lpt_ctrl_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= 8'hE0 | lpt_ctrl | lpt_enable_irq;
        end
        else if ((xtctl_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= xtctl;
        end
        else if (`ENABLE_TANDY_VIDEO && nmi_mask_register && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= nmi_mask_register_data;
        end
        else if (joystick_select && ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= joy_data;
        end
        else if ((~ide0_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= xt2ide0_data_bus_out;
        end
        else if ((~floppy0_chip_select_n || fdd_dma_read) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= fdd_readdata;
        end
        else if (rtc_chip_select && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= rtc_readdata;
        end
        else
        begin
            data_bus_out_from_chipset <= 1'b0;
            data_bus_out <= 8'b00000000;
        end
    end

endmodule
