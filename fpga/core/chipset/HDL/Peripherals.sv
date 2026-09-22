//
// PC-98 Peripherals (grown out of the MiSTer PCXT base)
// Ported by @spark2k06
//
// Based on chipset written by @kitune-san
//
`ifndef ENABLE_EMS
`define ENABLE_EMS 0
`endif
// PC/XT peripherals with no PC-98 counterpart at the same ports. They were
// synthesised into the PC-98 build because nothing gated them, and at 97 per
// cent ALM occupancy that is not free: the fit report has the MC146818 at 349
// ALMs, the two 16550s at 412 and the XT IDE pair at 216, none of which any
// PC-98 ROM can reach.
//   RTC   this is the PCXT's at 0x02C0; a PC-98 has a uPD4990A at 0x20/0x22/0x33
//   UART  0x3F8 / 0x2F8; a PC-98's serial is an 8251 at 0x30/0x32
// config.tcl turns them off for MACHINE_PC98 and the PC/XT build keeps them.
//
// The XT IDE pair (216 ALMs at 0x0300) is NOT on this list on purpose: the
// PC-98 build keeps it, so the storage path that exists stays reachable while
// a PC-98 one is not written yet.

module PERIPHERALS #(
        parameter ps2_over_time = 16'd1000,
		parameter clk_rate = 28'd50000000
    ) (
        input   logic           clock,
        // Sixteen-colour mode, out to the memory path: it decides whether
        // E0000-E7FFF is the fourth graphics plane or nothing at all.
        output  logic           pc98_analog,
        // The GRCG's registers, out to the sequencer that owns the planes.
        output  logic           grcg_active,
        output  logic           grcg_rmw,
        output  logic   [3:0]   grcg_mask,
        output  logic   [7:0]   grcg_tile [0:3],
        // The graphics pages: 0xA4's display bit is the raster's to consume,
        // 0xA6's access bit banks the CPU's plane windows (pc98_gvram_seq).
        output  logic           gvram_disp_page,
        output  logic           gvram_access_page,
        // The EGC's state: the arm-and-switch pair off mode2, and the
        // 0x4A0-0x4AF register writes, forwarded to the sequencer that owns
        // the engine.
        output  logic           egc_active,
        output  logic           egc_wr,
        output  logic   [3:0]   egc_rg,
        output  logic   [7:0]   egc_d,
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
        // VGA
        input   logic           clk_vga_cga,
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
        output  logic   [5:0]   VID_R,
        output  logic   [5:0]   VID_G,
        output  logic   [5:0]   VID_B,
        output  logic           VID_HSYNC,
        output  logic           VID_VSYNC,
        output  logic           VID_HBlank,
        output  logic           VID_VBlank,
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
        input   logic   [7:0]   kb_byte,
        input   logic           kb_valid,
        output  logic           kb_ready,
        // JTOPL
        // The row buffer's own view of row 0's first eight cells, latched as the
    // fill reads them -- what the renderer will actually draw. If the banks
    // dropped a write, or the fill's first sample is stale, it shows HERE
    // even while the bus snoops (TVC/TVH) read clean.
    // Where the TEXT renderer is POINTED, as opposed to where the guest
    // writes. pc98_text_render takes its start address and pitch from the
    // master GDC, so a guest that reprograms the GDC in a way this decode does
    // not follow writes one region and displays another -- which is exactly
    // what "the characters are in TVRAM but the screen is blank" looks like.
    // unk_cmd/unk_count are the commands the decode did not recognise.
    // The keyboard's last two hops. KEY (core_top) says the translator emitted
    // the event; these say whether the 8251 raised IRQ1 for it and whether the
    // guest ever came to collect the byte at 0x41.
    // The master PIC's eight request lines as a level, and a count of timer
    // ticks. INT (core_top) says the CPU stopped being interrupted; these say
    // whether anything is still ASKING.
    // The master PIC's own registers. INTR going quiet while a request line
    // is high is either a mask or an un-EOI'd in-service bit, and nothing
    // outside the chip can tell those apart.
    output  logic    [7:0]  dbg_pic_irr,
    output  logic    [7:0]  dbg_pic_imr,
    output  logic    [7:0]  dbg_pic_isr,
    // The vector byte the CPU actually received on the second INTA pulse,
    // and how many acknowledges there have been. The two-PIC cascade was
    // proven right at the protocol level (tb_pic_cascade) while the machine
    // still landed the CPU at 0:0500 -- so the remaining suspects are the
    // real bridge's INTA timing and the IVT's content, and this byte is what
    // splits them: 0x12/0x13 means delivery worked, anything else (0x0F, 0x00,
    // garbage) means the acknowledge itself came back wrong.
    output  logic    [7:0]  dbg_inta_vec,
    output  logic   [15:0]  dbg_inta_count,
    // The slave PIC's own three, and the motor timer's progress. The drive
    // probe's interrupt dies somewhere between a 0xCC write and the slave's
    // IRR; these four say exactly which link gave out.
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
    // The controller itself, from the chipset's side of it: the MSR the
    // guest last READ, the count of floppy.v interrupt rises, the DOR byte
    // floppy.v last latched, the count of result bytes read, and the last
    // byte written to each control port separately (dbg_last_ctrl mixes
    // 0x94 and 0xCC, which is how a 48 with no matching ROM constant went
    // unexplained).
    output  logic   [31:0]  dbg_fdc_x,   // {rd results, DOR, irq rises, MSR}
    output  logic   [31:0]  dbg_fdc_y,   // {last read byte, 0, 0xCC, 0x94}
    output  logic   [95:0]  dbg_fdc_z,   // the last TWELVE bytes into the FIFO
    output  logic   [31:0]  dbg_fdc_w,   // {drops, accepts, reply_left, 0}
    output  logic   [31:0]  dbg_fdc_v,   // {last port, dead reads, live reads}
    // The write path counted in PERIPHERALS, before any glue: {raw write
    // strobe, pc98_io_exact clocks} and {write levels, read levels} on the
    // FDC port selects.
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
    // The cursor's GDC-side state, served at 0x5000012C, packed to read as
    // hex digits in panel order: cc E aaa t b (command count, enable, cell
    // address, slice top, slice bottom). "Sane here and nothing draws"
    // blames the render path; "E 0 / t b 0 / cc 00" blames the BIOS never
    // having sent the form or the enable.
    output  logic   [23:0]  dbg_gdc_cur,
    output  logic    [7:0]  dbg_gdc_csrcnt,
    // The byte trace after the last CSRFORM: {count, three bytes}. Whether
    // the metal's driver sends the one-byte ON or the three-byte table form
    // -- and where the bytes actually land -- is what the panel's CT reads.
    output  logic   [31:0]  dbg_gdc_csrtrace,
    // The drawing server: the softcore's GDC engine. Two channels, master
    // and slave; each carries the EXECUTE handshake (req/busy + opcode) and
    // the five snapshot words, and takes back a done LEVEL whose rising
    // edge (synchronised here, the softcore is in another domain) retires
    // the command and runs the vector reset.
    output  logic   [1:0]   gdc_draw_req,
    output  logic   [1:0]   gdc_draw_busy,
    output  logic  [15:0]   gdc_draw_ops,
    output  logic [319:0]   gdc_draw_snaps,
    input   logic   [1:0]   gdc_srv_done_levels,
    output  logic   [63:0]  pc98_tvfill_view,
    // The kanji fetch path's activity: f_req pulses and f_valid beats. With
    // ANK out of the BRAM these only move for two-byte cells, so on a screen
    // of plain text they should sit still -- and a solid tofu where a kanji
    // should be says whether the fetch ever answered.
    output  logic   [15:0]  pc98_rowbuf_freq_count,
    output  logic   [15:0]  pc98_rowbuf_fvalid_count,
        // PC-9801-86 OPNA, stereo. Zero on a non-PC-98 build.
    output  logic signed [15:0] opna_snd_l,
    output  logic signed [15:0] opna_snd_r,
        // C/MS Audio
        // TANDY
        // UART
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
        // The calendar, packed the way pc98_upd4990 wants it (see the module):
        // year BCD, month<<4|week, day, hour, min, sec -- from the Pocket's
        // bridge RTC. A PC-98 reads the date off this chip's serial line.
        input   logic   [47:0]  rtc_time,
        output  logic   [1:0]   fdd_present,
        output  logic   [1:0]   fdd_request,
        output  logic           fdd_dma_req,
        input   logic           fdd_dma_ack,
        input   logic           terminal_count,
        // Others
        output  logic           pause_core,
        input   logic   [3:0]   crt_h_offset,
        input   logic   [2:0]   crt_v_offset,
        input   logic   [2:0]   vsync_width_osd,
        input   logic   [2:0]   hsync_width_osd
        // PC-98 keyboard injection: the Set-2 -> PC-98 translator's output
        // (dock USB keyboard + virtual keyboard), landing on the 8251's
        // receive wire. stb toggles per event; byte's bit 7 is set on a
        // release. Passed through from core_top via CHIPSET.
        ,
        input   logic           pc98_key_stb,
        input   logic   [7:0]   pc98_key_byte
        
    );

    //

    wire    iorq = ~io_read_n | ~io_write_n;

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
    // for now -- chipset is an XT and carries one -- so the slave's addresses
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
    // The floppy controller, shared with sim/tb_pc98_boot.sv rather than
    // copied into it -- see pc98_fdc.sv for why that stopped being optional.
    wire       fdc_base_select, fdc_msr_select, fdc_fifo_select;
    wire [7:0] fdc_msr, fdc_fifo;
    wire       fdc_irq3, fdc_irq2;

    pc98_fdc u_pc98_fdc (
        .clock            (clock),
        .reset            (reset),
        .address          (address[15:0]),
        .address_enable_n (address_enable_n),
        .io_read_n        (io_read_n),
        .io_write_n       (io_write_n),
        .data_in          (internal_data_bus),
        .base_select      (fdc_base_select),
        .msr_select       (fdc_msr_select),
        .fifo_select      (fdc_fifo_select),
        .msr              (fdc_msr),
        .fifo             (fdc_fifo),
        .irq_int          (fdc_irq3),
        .irq_2dd          (fdc_irq2)
    );

    // The house strobes: one cycle after the command drops, used by the FDC
    // glue and its witness counters below.
    logic prev_io_read_n;
    logic prev_io_write_n;

    always_ff @(posedge clock) begin
        prev_io_read_n  <= io_read_n;
        prev_io_write_n <= io_write_n;
    end

`ifdef PC98_FDC_REAL
    // 0x90/0x92 and 0xC8/0xCA now come from the real controller. 0xBE, 0x94
    // and 0xCC have no XT counterpart at all, so pc98_fdc_glue answers them:
    // 0xBE is a real latch (the BIOS steers itself with the readback -- ITF
    // FAFD0 tests bit 0 to pick between 0x90 and 0xC8, BIOS FF3C3 does a
    // read-modify-write of it), and 0x94/0xCC are np2kai's fdc_i94 constants
    // rather than the written byte. The glue is instantiated two thousand
    // lines down, beside floppy.v; these are its outputs reaching back.
    logic [7:0] fdc_mode_readback;   // 0xBE
    logic [7:0] fdc_ctrl_readback;   // 0x94 / 0xCC
    logic       fdc_group_live;      // this cycle's window is chgreg's choice
    logic       fdc_glue_irq_2hd;    // slave IRQ11 -> INT 13h
    logic       fdc_glue_irq_2dd;    // slave IRQ10 -> INT 12h

    // np2kai's guard (io/fdc.c, first statement of fdc_o92/fdc_i90/fdc_i92):
    // the window chgreg did NOT select ignores writes and reads 0xFF. Decoded
    // here rather than from floppy0_chip_select_n because that is declared a
    // hundred lines further down; the four ports are the same four.
    wire fdd_dead_select = pc98_io_exact & ~fdc_group_live
                         & ((address[7:0] == 8'h90) || (address[7:0] == 8'h92)
                         ||  (address[7:0] == 8'hC8) || (address[7:0] == 8'hCA));

    wire fdd_stub_read = (fdd_be_select | fdd_94_select
                          | fdd_cc_select | fdd_dead_select) & ~io_read_n;
`else
    wire fdd_stub_read = (fdd_be_select | fdd_90_select | fdd_94_select
                          | fdd_cc_select | fdc_base_select) & ~io_read_n;
`endif
`ifdef PC98_FDC_REAL
    wire [7:0] fdd_stub_data = fdd_be_select   ? fdc_mode_readback
                             : (fdd_94_select | fdd_cc_select)
                                               ? fdc_ctrl_readback
                             :                   8'hFF;   // the dead window
`else
    wire [7:0] fdd_stub_data = fdd_be_select  ? 8'hFB
                             : fdd_90_select  ? fdc_msr
                             : fdd_94_select  ? 8'h44
                             : fdd_cc_select  ? fdd_cc_data
                             : fdc_msr_select ? fdc_msr
                             :                  fdc_fifo;
`endif

    wire    [3:0] ems_page_address  = (ems_address == 2'b00) ? 4'b1100 : (ems_address == 2'b01) ? 4'b1101 : 4'b1110;
    wire    ems_chip_select         = `ENABLE_EMS ? (iorq && ~address_enable_n && ems_enabled && ({address[15:2], 2'd0} == 16'h0260)) : 1'b0;          // 260h..263h
    assign  ems_b1                  = `ENABLE_EMS ? (~iorq && ena_ems[0] && (address[19:14] == {ems_page_address, 2'b00})) : 1'b0; // C0000h - D0000h - E0000h
    assign  ems_b2                  = `ENABLE_EMS ? (~iorq && ena_ems[1] && (address[19:14] == {ems_page_address, 2'b01})) : 1'b0; // C4000h - D4000h - E4000h
    assign  ems_b3                  = `ENABLE_EMS ? (~iorq && ena_ems[2] && (address[19:14] == {ems_page_address, 2'b10})) : 1'b0; // C8000h - D8000h - E0000h
    assign  ems_b4                  = `ENABLE_EMS ? (~iorq && ena_ems[3] && (address[19:14] == {ems_page_address, 2'b11})) : 1'b0; // CC000h - DC000h - EC000h
    // PC-98 text VRAM, A0000-A3FFF: characters at A0000 (two bytes per cell)
    // and attributes at A2000. A BRAM in the guest's address space, qualified
    // with AEN so a DMA cycle carrying a matching address cannot reach it.
    wire    tvram_mem_select        = ~iorq && ~address_enable_n
                                    && (address[19:14] == 6'b101000);
    // A4000-A4FFF: the character generator window. RAM.sv already keeps SDRAM
    // out of A0000-A7FFF; this claims the read AND the write, because the
    // window is RAM -- the ITF's CG test writes a pattern through it and reads
    // the pattern back, and user-defined characters load the same way.
    wire    cgwin_mem_select        = ~iorq && ~address_enable_n
                                    && (address[19:12] == 8'b10100100);
    // No IDE on this machine -- see the XT2IDE block. Held deasserted so the
    // read mux arm at the bottom of the file is unreachable and prunes.
    wire    ide0_chip_select_n      = 1'b1;
`ifdef PC98_FDC_REAL
    // THE REAL uPD765 ON THE PC-98's PORTS.
    //
    // floppy.v is a uPD765, which is the right chip -- a PC-98's FDC is a
    // uPD765A -- and it holds the disk image and the DMA path. What was wrong
    // was only WHERE it listened: 0x03F0-0x03F7, the PC/XT's window. A PC-98
    // guest writes 0x90/0x92 (2HD) and 0xC8/0xCA (2DD), which reached the stub
    // below and nothing else.
    //
    // np2kai io/fdc.c attaches both groups to the same four handlers
    // (`iocore_attachcmnoutex(0x0090, 0x00f9, fdco90, 4)` and the same for
    // 0x00c8), so the two windows are one register set:
    //
    //     0x90 / 0xC8   read: main status (MSR)
    //     0x92 / 0xCA   read/write: the data register
    //     0x94 / 0xCC   control -- NOT the same shape as the XT's DOR, so it
    //                   keeps the PC-98 handling below rather than being
    //                   translated
    //
    // The translation is therefore only of the two that do correspond: MSR at
    // the XT's offset 4, data at 5.
    //
    // NOW ON. It was off because the stub below was tuned against the ROM's
    // probes for a machine WITH NO DRIVE -- its comments record what each
    // constant had to be to get the BIOS past them -- and nothing here reached
    // an FDD transfer to say whether the real path behaved. It does now:
    // sim/tb_pc98_fdc_glue runs the BIOS's own sequence against the real
    // floppy.v behind the real glue, interrupt loop and all, and against the
    // case the stub was standing in for -- an EMPTY DRIVE, which used to hang
    // floppy.v with CB set forever and now ends in a not-ready result phase
    // (see NOT_READY_ENDS_COMMAND at the instantiation below, and config.tcl).
    wire    floppy0_chip_select_n   = ~(~address_enable_n
                                     && (address[15:8] == 8'h00)
                                     && ((address[7:0] == 8'h90) || (address[7:0] == 8'h92)
                                      || (address[7:0] == 8'hC8) || (address[7:0] == 8'hCA)));
`else
    wire    floppy0_chip_select_n   = ~(~address_enable_n && (({address[15:2], 2'd0} == 16'h03F0) || ({address[15:1], 1'd0} == 16'h03F4) || ({address[15:0]} == 16'h03F7)));
`endif

    logic   [1:0]   ems_access_address;
    logic           ems_write_enable;
    logic   [7:0]   write_map_ems_data;
    logic           write_map_ena_data;
	 
    //
    // I/O Ports
    //
    // Address
    always_comb begin
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
    logic           fdd_interrupt;
    logic   [7:0]   interrupt_data_bus_out;
    logic           interrupt_to_cpu_buf;

    logic   [7:0]   interrupt2_data_bus_out;
    logic           interrupt2_data_bus_io;
    logic           interrupt2_to_cpu;
    logic   [2:0]   interrupt_cascade_out;
    logic           interrupt_cascade_io;

    // np2's timer-write quirk, decoded at the source: the byte lands in the
    // i8253 on the trailing edge of the I/O write, and on that same edge the
    // master PIC's IRR bit 0 drops if the byte was a channel-0 count or a
    // control word aimed at channel 0 with a real read/load code (a latch
    // command arms nothing, so np2 leaves the request alone for it).
    logic           pit_write_cycle_q;
    wire            pit_write_cycle  = ~timer_chip_select_n & ~io_write_n;
    wire            pit_write_done   = pit_write_cycle_q & ~pit_write_cycle;
    wire            pit0_write_clears_irr0 = pit_write_done &
           (  (pit_reg_addr == 2'b00)
            | ((pit_reg_addr == 2'b11) & (internal_data_bus[7:6] == 2'b00)
                                      & (internal_data_bus[5:4] != 2'b00)));
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            pit_write_cycle_q    <= 1'b0;
        else
            pit_write_cycle_q    <= pit_write_cycle;
    end

    wire    interrupt2_chip_select_n;

    // What the PC-98's master IRQ6 actually carries. With the real FDC on,
    // nothing: floppy.v's irq has moved to the slave, where the machine puts
    // it. With the stub, fdd_interrupt is floppy.v listening at the PC/XT's
    // 0x3F0 window that a PC-98 guest never writes -- it is left where it was
    // rather than changed underneath a configuration nothing exercises.
`ifdef PC98_FDC_REAL
    wire    pc98_master_irq6 = 1'b0;
`else
    wire    pc98_master_irq6 = fdd_interrupt;
`endif

    i8259 u_i8259
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
        .cascade_in                 (3'b000),
        .cascade_out                (interrupt_cascade_out),
        .cascade_io                 (interrupt_cascade_io),
        .slave_program_n            (1'b1),
        //.buffer_enable              (),
        //.slave_program_or_enable_buffer     (),
        .interrupt_acknowledge_n    (interrupt_acknowledge_n),
        .interrupt_to_cpu           (interrupt_to_cpu_buf),
        // np2 (io/pit.c): writing the interval timer -- a count byte for
        // channel 0, or a control word aimed at it -- clears the master's IRR
        // bit 0, so an interrupt latched before the reprogram cannot fire
        // after it.  The strobe is decoded below, next to the PIT.
        .external_irr_clear         ({7'b0, pit0_write_clears_irr0}),
        // IRQ7 is the slave's cascade line; the machine's own IRQ7 has to
        // stand down for it. IRQ2 is the CRT interrupt -- see crt_vsync_irq
        // above; without it the BIOS parks at FED44 for good. The drive's
        // own interrupts live on the slave (IRQ2 XTMASK, IRQ3 FDC).
        //
        // MASTER IRQ6 IS NOT THE FLOPPY. That is the PC/XT's wiring; on a
        // PC-98 IRQ6 is INT3, a free expansion line, and the FDC is slave
        // IRQ10/IRQ11 -- np2kai io/fdc.c:46-51 (pic_setirq 0x0a / 0x0b) and
        // the BIOS's own gates at FF438 and FF4B3, which read the SLAVE mask
        // at 0x0A and refuse the call if bit 2 / bit 3 is set. Driving
        // floppy.v's irq in here is what put LVL 41 on the POST panel: a
        // request nobody had a handler for, latched high for good because the
        // only thing that lowers it is the result-phase read the handler
        // would have done.
        .interrupt_request          ({interrupt2_to_cpu,
                                        pc98_master_irq6,
                                        interrupt_request[5],
                                        1'b0,   // was the XT UART pair
                                        1'b0,
                                        crt_vsync_irq,
                                        keybord_interrupt,
                                        timer_interrupt})
        ,
        .dbg_irr                    (dbg_pic_irr),
        .dbg_imr                    (dbg_pic_imr),
        .dbg_isr                    (dbg_pic_isr)
    );

    // Declared here rather than beside pc98_opna: the board's interrupt is a
    // slave-PIC line and the slave is instantiated two thousand lines before
    // the sound board is.
`ifdef ENABLE_OPNA
    wire opna_irq;
`else
    wire opna_irq = 1'b0;
`endif

    // The slave PIC, 0008-000F even. Its INT feeds the master's IRQ7 and its
    // cascade lines close the loop, so an IRQ8-15 acknowledge gets its vector
    // from the slave exactly the way the metal does it.
    assign interrupt2_chip_select_n = ~(pc98_io & ~address[0] & address[3]
                                        & (address[7:4] == 4'h0));

    i8259 u_i8259_2
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
        .dbg_irr                    (dbg_pic2_irr),
        .dbg_imr                    (dbg_pic2_imr),
        .dbg_isr                    (dbg_pic2_isr),

        // I/O
        .cascade_in                 (interrupt_cascade_out),
        .cascade_out                (),
        .cascade_io                 (),
        .slave_program_n            (1'b0),
        .interrupt_acknowledge_n    (interrupt_acknowledge_n),
        .interrupt_to_cpu           (interrupt2_to_cpu),
        .external_irr_clear         (8'h00),
        // IRQ3 is the FDC's own interrupt (RECALIBRATE finding no drive);
        // IRQ2 is the XTMASK pulse the 100 ms 0xCC timer fires. IRQ4 is the
        // PC-9801-86's: np2kai sound/opntimer.c:13 has the board's four jumper
        // positions as {0x03, 0x0d, 0x0a, 0x0c} -- INT0/INT6/INT41/INT5 -- and
        // the factory setting is INT5, which is IRQ12, slave bit 4.
        //
        // With the real controller those two lines come from floppy.v through
        // pc98_fdc_glue, steered by chgreg exactly as np2kai's fdc_intwait
        // steers pic_setirq (io/fdc.c:46-51): 2HD window -> IRQ11 (bit 3,
        // INT 13h, handler at FFAF6), 2DD window -> IRQ10 (bit 2, INT 12h,
        // handler at FFB69). The stub's own lines and the 0xCC timer stand
        // down -- they existed only because there was no chip to raise them.
`ifdef PC98_FDC_REAL
        .interrupt_request          ({3'b0, opna_irq, fdc_glue_irq_2hd,
                                     fdc_glue_irq_2dd, 2'b0})
`else
        .interrupt_request          ({3'b0, opna_irq, fdc_irq3,
                                     fdd_cc_irq | fdc_irq2, 2'b0})
`endif
    );

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
    // The PC-98 interval timer counts at the machine's 2.4576 MHz PIT clock
    // (1.9968 MHz on the 8 MHz class; np2's clk_base for this VM is 2.4576).
    // The XT's 1.193181 MHz below is half that and halves every programmed
    // rate: the BIOS's FDE20 load of 0x6000 ticks at 50 Hz instead of 100 Hz.
    // 42.954545 MHz is not an integer multiple (17.48...), so phase-accumulate
    // and toggle on carry: a square wave whose falling edges -- what the chip
    // counts -- land at exactly 2.4576 MHz on average.
    logic           timer_clock;
    logic [31:0]    pit_clk_phase;
    localparam logic [31:0] PIT_CLK_HZ_TOGGLE = 32'd4_915_200;  // 2 toggles per period
    localparam logic [31:0] CHIPSET_HZ       = 32'd42_954_545;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset) begin
            timer_clock     <= 1'b0;
            pit_clk_phase   <= 32'd0;
        end
        else begin
            if ({1'b0, pit_clk_phase} + PIT_CLK_HZ_TOGGLE >= CHIPSET_HZ) begin
                pit_clk_phase <= pit_clk_phase + PIT_CLK_HZ_TOGGLE - CHIPSET_HZ;
                timer_clock   <= ~timer_clock;
            end
            else
                pit_clk_phase <= pit_clk_phase + PIT_CLK_HZ_TOGGLE;
        end
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
    // The beeper's TONE is counter 1, not counter 2. Counter 2 is the
    // RS-232C baud source (np2 io/pit.c: pit_o75 -> pit_setrs232cspeed);
    // the B6h the ITF writes at F805DC is that channel's init, not a beep.
    // The boot beep is the ITF's F80738 76h -- counter 1, LSB+MSB, mode 3
    // -- with the divisor fed to 0x73 at F80740/48, exactly the channel
    // np2's beeper follows (pit_o73 -> beep_hzset / beep_lheventset).
    //
    // The beeper's MUTE is system-port C bit 3, INVERTED: 1 = silent,
    // 0 = sounding (np2 sound/beepc.c: buz = (sysport.c & 8) ? 0 : 1), and
    // the latch resets to 0xF9 -- muted. The gate is the LATCH, the thing
    // 0x35 reads back, not the XT 8255's port C pin: the BIOS only ever
    // issues bit set/reset words to 0x37, never a mode word, so the chip
    // holds port C in input mode and port_c_io[3] never drops. Keying the
    // enable on ~port_c_io muted the beeper forever -- the machine's boot
    // beep was silent while 0037 stacked up in the IO history.
    wire    tim2gatespk = 1'b1;
    wire    spktone     = timer_counter_out[1];
    wire    spkdata     = ~pc98_sysport_c[3];

    i8253 u_i8253 
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
    assign  speaker_out     = spktone & spkdata;


    //
    // ps2_keyboard -- kept for the pacing, not for the keycodes.
    //
    // Nothing on this machine reads its XT keycode buffer: a PC-98's keyboard
    // is the 8251 at 0x41/0x43, and pc98_kbd_ps2 taps the Set-2 stream
    // UPSTREAM of this converter. What it still does is pace that stream --
    // kb_ready is the only thing stopping pocket_keyboard's queue from
    // running ahead of the consumer.
    //
    // Its output side is drained unconditionally (clear_keycode = 1). Left to
    // wait for the port-0x61 PB7 acknowledge an XT BIOS would send, the irq
    // latch would stay high after the first byte, kb_ready would never come
    // back, and exactly one key event would ever cross.
    //
    logic           keybord_irq;
    wire            clear_keycode = 1'b1;
    logic           kb_ready_int;
    assign  kb_ready = kb_ready_int;

    ps2_keyboard #(.clk_rate(clk_rate)) u_ps2_keyboard
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),

        // Set-2 byte in
        .kb_byte                    (kb_byte),
        .kb_valid                   (kb_valid),
        .kb_ready                   (kb_ready_int),

        // I/O
        .irq                        (keybord_irq),
        .keycode                    (),
        .clear_keycode              (clear_keycode),
        .pause_core                 (pause_core),
        // The card-swap hotkey and its Tandy variant: no second card to
        // swap to on a PC-98, so the converter's display side is held quiet.
        .swap_video                 (),
        .video_output               (1'b0),
        .tandy_video                (1'b0)
    );

//
// The PC-98 keyboard 8251's RxRDY line -- declared here because the IRQ
// synchroniser below is its first user; the model itself sits down at the
// 0x41/0x43 decode.
    logic   kbd8251_irq;
    logic   keybord_interrupt_ff;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            keybord_interrupt_ff    <= 1'b0;
            keybord_interrupt       <= 1'b0;
        end
        else
        begin
            // PC-98: IRQ1 is the 8251's RxRDY line, not the XT PS/2
            // keyboard's -- the machine has no port 0x60 keyboard, and a
            // PS/2 byte raising IRQ1 there only made the BIOS's FE65D
            // handler read a phantom 0x41. With the 8251 model compiled out
            // the XT line stands in, which is what the build did before.
`ifdef PC98_KBD_8251
            keybord_interrupt_ff    <= kbd8251_irq;
`else
            keybord_interrupt_ff    <= keybord_irq;
`endif
            keybord_interrupt       <= keybord_interrupt_ff;
        end
    end

    // ---------------------------------------------------------- PC-98 video
    //
    // One plane, one mode: 640x400 text on the 21.0526 MHz dot clock, which
    // core_top routes in as clk_pc98_dot. The CGA and HGC generators went
    // with the PC/AT machine layer; nothing here looks at them.
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
    // THE MOCK IS GONE. pc98_gdc is the real command and parameter interface --
    // see docs/PC98_GDC_DESIGN.md for what it does and does not implement, and
    // the module header for the two things np2kai's enum would have got wrong.
    // One note carried over: the mock's bit 7 was CLEAR, and np2kai's gdc_i60
    // sets it unconditionally. The real module sets it.
    //
    // Text GDC at 0x60/0x62, graphics GDC at 0xA0/0xA2. The even port is
    // status (read) and parameter (write); the odd-numbered one two up is the
    // read-back FIFO and the command port. Both watch the same raster, because
    // this core generates it in pc98_video_timing rather than in either GDC.
    wire gdc_m_cs = pc98_io_exact & ((address[7:0] == 8'h60) | (address[7:0] == 8'h62));
    wire gdc_s_cs = pc98_io_exact & ((address[7:0] == 8'hA0) | (address[7:0] == 8'hA2));

    wire [7:0] gdc_m_dout, gdc_s_dout;
    wire [7:0] gdc_m_unk_cmd, gdc_m_unk_count;
    wire [7:0] gdc_s_unk_cmd, gdc_s_unk_count;

    // The display registers are not consumed yet: pc98_text_render still
    // derives its cell index from the raster. Wiring them in is the next step
    // and its regression test is that one partition at SAD 0 reduces to the
    // expression the renderer uses today.
    wire        gdc_m_disp_on, gdc_s_disp_on;
    wire [7:0]  gdc_m_pitch,   gdc_s_pitch;
    wire [15:0] gdc_m_sad [0:3], gdc_s_sad [0:3];
    wire [9:0]  gdc_m_len [0:3], gdc_s_len [0:3];
    wire [15:0] gdc_m_cur_addr,  gdc_s_cur_addr;
    wire [3:0]  gdc_m_cur_dot,   gdc_s_cur_dot;
    wire        gdc_m_cur_en,    gdc_s_cur_en;
    wire        gdc_m_cur_bl,    gdc_s_cur_bl;
    wire [4:0]  gdc_m_cur_top,   gdc_s_cur_top;
    wire [4:0]  gdc_m_cur_bot,   gdc_s_cur_bot;
    wire [5:0]  gdc_m_cur_rate,  gdc_s_cur_rate;
    wire [7:0]  gdc_m_csrcnt;
    wire [31:0] gdc_m_csrtrace;
    wire [1:0]  gdc_m_zoom,      gdc_s_zoom;

    assign dbg_gdc_sad       = gdc_m_sad[0][14:0];
    assign dbg_gdc_pitch     = gdc_m_pitch;
    assign dbg_gdc_unk_cmd   = gdc_m_unk_cmd;
    assign dbg_gdc_unk_count = gdc_m_unk_count;
    assign dbg_gdc_disp_on   = gdc_m_disp_on;
    // The drawing-server plumbing: the two channels' handshakes and the
    // done-level synchronisers (the softcore writes the level; the rising
    // edge here retires the EXECUTE in the GDC).
    wire        gdc_m_draw_req, gdc_m_draw_busy, gdc_m_done_stb;
    wire        gdc_s_draw_req, gdc_s_draw_busy, gdc_s_done_stb;
    wire [7:0]  gdc_m_draw_op,  gdc_s_draw_op;
    wire [31:0] gdc_m_draw_snap [0:4];
    wire [31:0] gdc_s_draw_snap [0:4];

    logic [1:0] srv_done_s1 = 2'b00, srv_done_s2 = 2'b00, srv_done_s3 = 2'b00;
    always_ff @(posedge clock) begin
        srv_done_s1 <= gdc_srv_done_levels;
        srv_done_s2 <= srv_done_s1;
        srv_done_s3 <= srv_done_s2;
    end

    assign gdc_draw_req   = {gdc_s_draw_req,   gdc_m_draw_req};
    assign gdc_draw_busy  = {gdc_s_draw_busy,  gdc_m_draw_busy};
    assign gdc_draw_ops   = {gdc_s_draw_op,    gdc_m_draw_op};
    assign gdc_m_done_stb = srv_done_s2[0] & ~srv_done_s3[0];
    assign gdc_s_done_stb = srv_done_s2[1] & ~srv_done_s3[1];
    genvar dsg;
    generate
        for (dsg = 0; dsg < 5; dsg = dsg + 1) begin : g_dsnap
            assign gdc_draw_snaps[dsg*32 +: 32]      = gdc_m_draw_snap[dsg];
            assign gdc_draw_snaps[160 + dsg*32 +: 32] = gdc_s_draw_snap[dsg];
        end
    endgenerate

    assign dbg_gdc_cur       = {gdc_m_csrcnt,     // cc: command count
                                gdc_m_cur_en, 3'b000, // E
                                gdc_m_cur_addr[11:0], // aaa: the cell
                                gdc_m_cur_top[3:0],   // t
                                gdc_m_cur_bot[3:0]};  // b
    assign dbg_gdc_csrcnt    = gdc_m_csrcnt;
    assign dbg_gdc_csrtrace  = gdc_m_csrtrace;

    pc98_gdc u_gdc_m (
        .clk(clock), .reset(reset),
        .cs(gdc_m_cs), .a1(address[1]),
        .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(internal_data_bus), .data_out(gdc_m_dout),
        .hblank(gdc_hb_q), .vsync(gdc_vs_q),
        .disp_on(gdc_m_disp_on), .pitch(gdc_m_pitch),
        .part_sad(gdc_m_sad), .part_len(gdc_m_len),
        .cursor_addr(gdc_m_cur_addr), .cursor_dot(gdc_m_cur_dot),
        .cursor_en(gdc_m_cur_en), .cursor_blink_en(gdc_m_cur_bl),
        .cursor_top(gdc_m_cur_top), .cursor_bottom(gdc_m_cur_bot),
        .cursor_rate(gdc_m_cur_rate), .zoom_disp(gdc_m_zoom),
        .csr_wr_count(gdc_m_csrcnt), .csr_trace(gdc_m_csrtrace),
        .draw_req(gdc_m_draw_req), .draw_op(gdc_m_draw_op),
        .draw_busy(gdc_m_draw_busy), .srv_done_stb(gdc_m_done_stb),
        .draw_snap(gdc_m_draw_snap),
        .unk_cmd(gdc_m_unk_cmd), .unk_count(gdc_m_unk_count)
    );

    pc98_gdc #(.MASTER(1'b0)) u_gdc_s (
        .clk(clock), .reset(reset),
        .cs(gdc_s_cs), .a1(address[1]),
        .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(internal_data_bus), .data_out(gdc_s_dout),
        .hblank(gdc_hb_q), .vsync(gdc_vs_q),
        .disp_on(gdc_s_disp_on), .pitch(gdc_s_pitch),
        .part_sad(gdc_s_sad), .part_len(gdc_s_len),
        .cursor_addr(gdc_s_cur_addr), .cursor_dot(gdc_s_cur_dot),
        .cursor_en(gdc_s_cur_en), .cursor_blink_en(gdc_s_cur_bl),
        .cursor_top(gdc_s_cur_top), .cursor_bottom(gdc_s_cur_bot),
        .cursor_rate(gdc_s_cur_rate), .zoom_disp(gdc_s_zoom),
        .csr_wr_count(),  // the slave has no cursor; only the master's counts
        .draw_req(gdc_s_draw_req), .draw_op(gdc_s_draw_op),
        .draw_busy(gdc_s_draw_busy), .srv_done_stb(gdc_s_done_stb),
        .draw_snap(gdc_s_draw_snap),
        .unk_cmd(gdc_s_unk_cmd), .unk_count(gdc_s_unk_count)
    );

    wire       gdc_stat_read = (gdc_m_cs | gdc_s_cs) & ~io_read_n;
    wire [7:0] gdc_status    = gdc_m_cs ? gdc_m_dout : gdc_s_dout;

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
    // 0x31 is DIP switch 2 (np2's default set is 3E E3 7B; the E3 is this
    // port). Bit 0 set is the boot order: the ROM goes straight to int 1E and
    // skips IVT[1F]'s D800:2A00, an entry for a BASIC option-ROM card nothing
    // here has. Bit 4 CLEAR tells the ROM NOT to re-initialise the memory
    // switch at A3FE0 -- on a real machine that is battery-backed VRAM, and
    // np2 keeps the bit clear because it pre-writes the switch bytes itself
    // at every reset. pc98_tvram does the same now (it pre-seeds
    // {48 05 04 08 01 00 00 6E} on reset and drops guest writes to those
    // cells), so the bit must be clear here too: the ROM's own writer tops
    // out at A3FEA=2 (512 KB class) where a 640 KB machine carries 4.
    //
    // This port used to answer 0x10 -- bit 4 SET, "please initialise" -- for
    // the opposite reason: the tvram came up empty and the ROM was the only
    // writer. With the pre-seed in place that answer would now fight it, and
    // MEMORY 128KB OK on a 640 KB machine was the old result anyway.
    // 0x35, the system port's port-C latch -- and the shutdown flag.
    //
    // Bit 7 is what the ITF reads at F805B to tell a power-on from a return
    // from OUT 0F0h: set means cold boot, clear means "restore SS:SP from
    // 0000:0404 and RETF". It clears the bit through the 8255's bit
    // set/reset -- out 37h, 0Eh -- just before asking for the reset.
    //
    // A constant A0 could never carry that: the flag has to be written and
    // read back. So the latch lives here, resetting to F9 and answering both
    // the whole-byte write at 0x35 and the single-bit write at 0x37 (np2
    // io/sysport.c, sysp_o35 and sysp_o37, as a behaviour reference). Note
    // that a MODE word -- anything with a bit set in the top nibble -- leaves
    // it alone; only the bit set/reset form touches it.
    logic [7:0] pc98_sysport_c;
    logic       sysp_prev_wr_n;
    logic [7:0] sysp_wr_data;
    wire sysport_37_select = pc98_io_exact & (address[7:0] == 8'h37);
    wire sysp_addr_35 = ~address_enable_n & (address[15:8] == 8'h00)
                      & (address[7:0] == 8'h35);
    wire sysp_addr_37 = ~address_enable_n & (address[15:8] == 8'h00)
                      & (address[7:0] == 8'h37);

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            pc98_sysport_c <= 8'hF9;
            sysp_prev_wr_n <= 1'b1;
            sysp_wr_data   <= 8'h00;
        end else begin
            sysp_prev_wr_n <= io_write_n;
            if ((sysport_35_select | sysport_37_select) & ~io_write_n)
                sysp_wr_data <= internal_data_bus;
            if (io_write_n & ~sysp_prev_wr_n) begin
                if (sysp_addr_35)
                    pc98_sysport_c <= sysp_wr_data;
                else if (sysp_addr_37 && (sysp_wr_data[7:4] == 4'h0))
                    pc98_sysport_c[sysp_wr_data[3:1]] <= sysp_wr_data[0];
            end
        end
    end

    wire sysport_31_select = pc98_io_exact & (address[7:0] == 8'h31);
    wire sysport_35_select = pc98_io_exact & (address[7:0] == 8'h35);
    wire sysport_42_select = pc98_io_exact & (address[7:0] == 8'h42);

    // 0x33, the 8255's port B: bit 3 an inverted DIP, bits 7-5 the RS-232C
    // modem lines, bit 0 the calendar clock -- uPD4990's cdat, the serial
    // data line the BIOS clocks 48 bits out of (FD80's 0x15D3C loop issues
    // the uPD4990 read command at 0x20 and samples THIS bit eight times per
    // byte, six bytes: the date). np2 answers bit3 | rs232c_stat()&0xe0 |
    // uPD4990.cdat; with the stock dip set (3E -> bit3=1), no modem (0) and
    // a resting clock line (0) that is 0x08. The port used to be unmodelled
    // here and read as open-bus FF -- every date bit 1, a calendar no real
    // chip produces -- and the BIOS sat validating it forever with LIVE
    // dancing on the work buffer and the drive probe never advancing.
    wire sysport_33_select = pc98_io_exact & (address[7:0] == 8'h33);

    // The calendar chip's command port: every write is one STB/CLK/DATA
    // phase, latched while the cycle is live and strobed at its end -- the
    // same shape the memory-switch writer below uses.
    wire sysport_20_wlevel = pc98_io_exact & (address[7:0] == 8'h20)
                           & ~io_write_n;
    logic       upd4990_wr_stb = 1'b0;
    logic       upd4990_wr_lvl_q = 1'b0;
    logic [7:0] upd4990_wr_data = 8'h00;
    logic       upd4990_cdat;
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            upd4990_wr_lvl_q <= 1'b0;
            upd4990_wr_stb   <= 1'b0;
            upd4990_wr_data  <= 8'h00;
        end else begin
            upd4990_wr_lvl_q <= sysport_20_wlevel;
            upd4990_wr_stb   <=  upd4990_wr_lvl_q & ~sysport_20_wlevel;
            if (sysport_20_wlevel)
                upd4990_wr_data <= internal_data_bus;
        end
    end
    pc98_upd4990 u_upd4990 (
        .clk      (clock),
        .rst      (reset),
        .wr_stb   (upd4990_wr_stb),
        .wr_data  (upd4990_wr_data),
        .time_in  (rtc_time),
        .cdat     (upd4990_cdat)
    );
    wire sysport_read      = (sysport_31_select | sysport_33_select
                            | sysport_35_select | sysport_42_select) & ~io_read_n;
    // 0x42 bit 1: this machine has no protected mode.
    //
    // The UX ITF tests it at F8B95 and, with the bit CLEAR, walks into
    //
    //     F8BBC  lidt [es:bp+0]
    //     F8BC4  lgdt [es:bp+0]
    //
    // to size memory above 1 MB. Those are 286 instructions, and on an 8086
    // 0F is POP CS -- so the machine popped a word off the stack into CS and
    // left the ROM. That is the CS f800 -> 0000 jump that ended every run
    // right after MEMORY 640KB OK was printed.
    //
    // With the bit SET the ITF branches to F8FA2 and skips the whole
    // protected-mode block, which is the truth about this CPU rather than a
    // way around the symptom. The BIOS never looks at bit 1 -- it tests bits
    // 0, 3, 4, 5 and 6 of the same port -- so nothing else changes.
    // 0x31 = 0xE3. The detour through 0x12 is worth recording.
    //
    // When 0xE3 first went in, the Pocket's screen went completely blank and
    // this value was the obvious suspect, so it was walked back to 0x12 --
    // 0x10's bits plus bit 1, with bit 4 SET so the ITF initialises the
    // memory switch itself. The screen stayed blank, and the real cause
    // turned out to be the keyboard 8251 claiming ports 0x41/0x43. With that
    // gated off the picture came back -- and said MEMORY SWITCH ERROR,
    // because bit 4 set asks the ROM to write a switch that pc98_tvram
    // write-protects: the ITF's initialisation is swallowed and the readback
    // disagrees with what it just wrote.
    //
    // So bit 4 stays CLEAR, which is what it was always for: the switch is
    // the tvram's to hold, pre-seeded at reset, not the ROM's to rewrite.
    // Bit 0 is boot-first (int 1E, skip IVT[1F]) and bit 1 skips the
    // protected-mode block described above.
    wire [7:0] sysport_data = sysport_35_select ? pc98_sysport_c
                            : sysport_31_select ? 8'hE3
                            : sysport_33_select ? (8'h08 | {7'd0, upd4990_cdat})
                            : sysport_42_select ? 8'h02
                            :                     8'h00;

    // ------------------------------------------------- keyboard 8251
    //
    // 0x41 data / 0x43 status+command: the keyboard's 8251. The chip model
    // itself -- np2's io/serial.c semantics, the break-edge reset, the 0x60
    // answer and its timing against the ITF's poll window -- lives in
    // pc98_kbd8251.sv with the full derivation; here it is only decoded and
    // wired. Note the decode is exact and 0x73 is NOT claimed: 0x73 is the
    // beep data port (np2 pit_o73), and the ITF's no-keyboard path programs
    // it twice -- arming ACKs there is what blanked the Pocket's screen.
    wire kbd_data_select = pc98_io_exact & (address[7:0] == 8'h41);
    wire kbd_stat_select = pc98_io_exact & (address[7:0] == 8'h43);

    logic       kbd8251_read_select;
    logic [7:0] kbd8251_read_data;

    pc98_kbd8251 u_pc98_kbd8251 (
        .clock              (clock),
        .reset              (reset),
        .ctrl_write_strobe  (kbd_stat_select & ~io_write_n),
        .data_read_strobe   (kbd_data_select & ~io_read_n),
        .stat_read_strobe   (kbd_stat_select & ~io_read_n),
        .data_in            (internal_data_bus),
        .key_stb            (pc98_key_stb),
        .key_byte           (pc98_key_byte),
        .read_select        (kbd8251_read_select),
        .read_data          (kbd8251_read_data),
        .irq                (kbd8251_irq)
    );

    logic timer_interrupt_q;
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            timer_interrupt_q <= 1'b0;
            dbg_timer_count   <= 8'h00;
        end else begin
            timer_interrupt_q <= timer_interrupt;
            if (timer_interrupt & ~timer_interrupt_q && dbg_timer_count != 8'hFF)
                dbg_timer_count <= dbg_timer_count + 8'd1;
        end
    end
    // The MASTER's eight request lines, as levels -- what LVL on the POST
    // panel reads. Bit 6 is whatever the master is actually given, which with
    // the real FDC is nothing: the drive's interrupt is a SLAVE line now, and
    // a panel that kept showing fdd_interrupt here would be reporting a wire
    // that no longer goes anywhere. LVL 41 -- bit 0 and bit 6 -- is the
    // reading this replaced.
    assign dbg_irq_level = {interrupt2_to_cpu, pc98_master_irq6, interrupt_request[5],
                            1'b0, 1'b0, crt_vsync_irq,
                            keybord_interrupt, timer_interrupt};

    logic kbd8251_irq_q;
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            kbd8251_irq_q     <= 1'b0;
            dbg_kbd_irq_count <= 8'h00;
            dbg_kbd_rd_count  <= 8'h00;
        end else begin
            kbd8251_irq_q <= kbd8251_irq;
            if (kbd8251_irq & ~kbd8251_irq_q && dbg_kbd_irq_count != 8'hFF)
                dbg_kbd_irq_count <= dbg_kbd_irq_count + 8'd1;
            if (kbd_data_select & ~io_read_n && dbg_kbd_rd_count != 8'hFF)
                dbg_kbd_rd_count <= dbg_kbd_rd_count + 8'd1;
        end
    end

    wire [7:0] pc98_font_row;      // driven by the row buffer below
    wire [6:0] pc98_font_cell;
    wire [3:0] pc98_font_line;
    wire [2:0] pc98_grb;
    wire       pc98_pixel, pc98_kanji_seen;

    // The master GDC's display registers, carried into the pixel domain.
    //
    // TAKEN AT VSYNC, not synchronised bit by bit. gdc_pitch and gdc_sad are
    // multi-bit and the guest writes them a byte at a time, so a two-flop
    // synchroniser would eventually hand the renderer half of one value and
    // half of the next -- a torn start address is a screen that jumps. Real
    // hardware latches these at the frame boundary and so does this, which
    // also means a program that writes them mid-frame sees the change on the
    // next one, as it would on the machine.
    //
    // gdc_on is one bit and is synchronised plainly; the renderer falls back
    // to 80 columns from cell 0 while it is low, which is the picture that
    // works today.
    logic gdc_on_s1, gdc_on_px;
    logic pc98_vs_s1, pc98_vs_px, pc98_vs_px_d;
    logic [7:0]  gdc_pitch_px;
    logic [15:0] gdc_sad_px;
    logic [15:0] gdc_cur_addr_px;
    logic [4:0]  gdc_cur_top_px, gdc_cur_bot_px;
    logic gdc_cur_en_s1, gdc_cur_en_px;
    logic gdc_cur_bl_s1, gdc_cur_bl_px;

    always_ff @(posedge clk_vga_cga) begin
        gdc_on_s1  <= gdc_m_disp_on;  gdc_on_px  <= gdc_on_s1;
        pc98_vs_s1 <= pc98_vs;        pc98_vs_px <= pc98_vs_s1;
        pc98_vs_px_d <= pc98_vs_px;
        gdc_cur_en_s1 <= gdc_m_cur_en; gdc_cur_en_px <= gdc_cur_en_s1;
        gdc_cur_bl_s1 <= gdc_m_cur_bl; gdc_cur_bl_px <= gdc_cur_bl_s1;
        if (pc98_vs_px & ~pc98_vs_px_d) begin
            gdc_pitch_px <= gdc_m_pitch;
            gdc_sad_px   <= gdc_m_sad[0];
            gdc_cur_addr_px <= gdc_m_cur_addr;
            gdc_cur_top_px  <= gdc_m_cur_top;
            gdc_cur_bot_px  <= gdc_m_cur_bot;
        end
    end

    pc98_text_render u_pc98_text (
        .clk(clk_vga_cga), .pix_ce(1'b1),
        .gdc_on(gdc_on_px), .gdc_pitch(gdc_pitch_px), .gdc_sad(gdc_sad_px),
        .cur_addr(gdc_cur_addr_px), .cur_en(gdc_cur_en_px),
        .cur_blink(gdc_cur_bl_px),
        .cur_top(gdc_cur_top_px), .cur_bot(gdc_cur_bot_px),
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
    logic       pc98_f_req_q = 1'b0;
    wire [19:0] pc98_f_addr;
    wire  [7:0] pc98_f_data;
    wire  [7:0] pc98_ank_code;
    wire  [3:0] pc98_ank_line;
    wire  [7:0] pc98_ank_row;

    // ------------------------------------------------ GDC mode (port 0x68)
    //
    // The mode flip-flops the BIOS drives around its CRT and CG-window
    // sequences -- see pc98_gdc_mode1's header for the ROM measurements. Bit
    // 5 decides whether a cell's high byte can make it a kanji at all, and
    // the POST's own printer (FE0F0) stores single bytes into the code plane
    // and never clears that high byte, so the machine HAS to be able to
    // honour the "all cells ANK" mode the same way np2's gdc_restorekacmode
    // does. Same trailing-edge shape as the system port above it: address and
    // command do not change together, and a mode flip taken from a glitched
    // sweep through 0x68 would change every cell's width.
    wire  mode68_select = pc98_io_exact & (address[7:0] == 8'h68);
    wire  mode68_addr   = ~address_enable_n & (address[15:8] == 8'h00)
                        & (address[7:0] == 8'h68);
    logic       mode68_prev_wr_n;
    logic [7:0] mode68_data;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            mode68_prev_wr_n <= 1'b1;
            mode68_data      <= 8'h00;
        end else begin
            mode68_prev_wr_n <= io_write_n;
            if (mode68_select & ~io_write_n)
                mode68_data <= internal_data_bus;
        end
    end

    wire mode68_wr = io_write_n & ~mode68_prev_wr_n & mode68_addr;

    // Port 0x6A, the same bit set/reset shape as 0x68 and for the same reason:
    // its bit 0 is sixteen-colour mode, which MOVES THE MEMORY MAP by bringing
    // the fourth graphics plane at E0000-E7FFF into existence.
    wire  mode6a_select = pc98_io_exact & (address[7:0] == 8'h6A);
    wire  mode6a_addr   = ~address_enable_n & (address[15:8] == 8'h00)
                        & (address[7:0] == 8'h6A);
    logic       mode6a_prev_wr_n;
    logic [7:0] mode6a_data;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            mode6a_prev_wr_n <= 1'b1;
            mode6a_data      <= 8'h00;
        end else begin
            mode6a_prev_wr_n <= io_write_n;
            if (mode6a_select & ~io_write_n)
                mode6a_data <= internal_data_bus;
        end
    end

    wire mode6a_wr = io_write_n & ~mode6a_prev_wr_n & mode6a_addr;

    logic [7:0] mode2_q;
    logic       egc_prev_wr_n;

    pc98_gdc_mode2 u_gdc_mode2 (
        .clk            (clock),
        .rst            (reset),
        .wr             (mode6a_wr),
        .d              (mode6a_data),
        // This core has the four planes, so it admits to the hardware. The
        // input exists so that is a decision rather than an assumption.
        .analog_capable (1'b1),
        .mode2          (mode2_q),
        .analog         (pc98_analog)
    );

    // Bits 3 and 2 of the same register are the EGC's arm and switch: np2kai
    // only honours bit 2 (VOPBIT_EGC) while bit 3 is set AND the G-RCG is
    // the EGC-capable one (io/gdc.c gdc_o6a's `mode2 & 0x08` and
    // `grcg.chip == 3`). This machine's charger is, so the gate is those two
    // flip-flops and nothing else.
    assign egc_active = mode2_q[3] & mode2_q[2];

    // Ports 0xA4/0xA6: the display and access page bits (np2kai gdc_oa4/
    // gdc_oa6 -- gdcs.disp and gdcs.access). The access bit banks every
    // graphics window between the two 640x400 pages, and pc98_gvram_seq
    // consumes it; the display bit is the graphics raster's to consume.
    wire pg_a4_cs = pc98_io_exact & (address[7:0] == 8'hA4);
    wire pg_a6_cs = pc98_io_exact & (address[7:0] == 8'hA6);

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            gvram_disp_page   <= 1'b0;
            gvram_access_page <= 1'b0;
        end else begin
            if (pg_a4_cs & ~io_write_n) gvram_disp_page   <= internal_data_bus[0];
            if (pg_a6_cs & ~io_write_n) gvram_access_page <= internal_data_bus[0];
        end
    end

    // Ports 0x4A0-0x4AF: the EGC register file, forwarded one strobe at a
    // time to the sequencer that owns the engine. np2kai hangs no read
    // handlers on these (iocore_attachout only), so neither does this.
    wire egc_cs = pc98_io_exact & (address[15:4] == 12'h04A);
    assign egc_rg = address[3:0];

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            egc_prev_wr_n <= 1'b1;
            egc_d         <= 8'h00;
        end else begin
            egc_prev_wr_n <= io_write_n;
            if (egc_cs & ~io_write_n) egc_d <= internal_data_bus;
        end
    end

    assign egc_wr = io_write_n & ~egc_prev_wr_n & egc_cs;

    // The GRCG's own two ports. 0x7C is the mode register (and writing it
    // resets the tile counter); 0x7E walks the four tile registers.
    wire grcg_mode_cs = pc98_io_exact & (address[7:0] == 8'h7C);
    wire grcg_tile_cs = pc98_io_exact & (address[7:0] == 8'h7E);
    wire [7:0] grcg_mode_rd;

    pc98_grcg u_pc98_grcg (
        .clk(clock), .reset(reset),
        .cs_mode(grcg_mode_cs), .cs_tile(grcg_tile_cs),
        .io_read_n(io_read_n), .io_write_n(io_write_n),
        .io_data_in(internal_data_bus), .io_data_out(grcg_mode_rd),
        .active(grcg_active), .rmw(grcg_rmw), .plane_mask(grcg_mask),
        .tile_o(grcg_tile),
        // The transform's own ports are unused here: the sequencer in CHIPSET
        // does the plane arithmetic, and it takes the registers rather than
        // the transform, because it is the one that has the planes' contents.
        .cpu_wdata(8'h00),
        .plane_rdata('{8'h00, 8'h00, 8'h00, 8'h00}),
        .plane_wdata(), .plane_we(), .cpu_rdata()
    );

    wire [7:0] pc98_bitac;

    pc98_gdc_mode1 u_gdc_mode1 (
        .clk  (clock),
        .rst  (reset),
        .wr   (mode68_wr),
        .d    (mode68_data),
        // mode1 itself: nothing downstream wants the other bits yet -- bit 3's
        // 8x8/8x16 font select and the graphics-display bits are future work.
        .mode1 (),
        .bitac(pc98_bitac)
    );

    pc98_glyph_rowbuf u_pc98_rowbuf (
        .clk(clock), .rst(reset),
        .fill_start(pc98_row_fill), .row_base(pc98_row_base),
        .bitac(pc98_bitac), .busy(pc98_fill_busy),
        .tv_cell(tvram_fil_cell),
        .tv_char_lo(tvram_vid_char_lo), .tv_char_hi(tvram_vid_char_hi),
        .f_req(pc98_f_req), .f_addr(pc98_f_addr), .f_busy(pc98_f_busy),
        .f_valid(pc98_f_valid), .f_data(pc98_f_data),
        // ANK cells read the local 4 KB BRAM instead of the SDRAM -- the bytes
        // the loader wrote straight in, with no bank redirect and no video
        // port between them and the screen.
        .ank_code(pc98_ank_code), .ank_line(pc98_ank_line),
        .ank_row(pc98_ank_row),
        // Indexed by the cell the renderer is FETCHING, not the one it is
        // drawing: it runs one cell ahead, and using the current column here
        // would shift every line by one.
        .rd_clk(clk_vga_cga), .rd_cell(pc98_font_cell), .rd_line(pc98_font_line),
        .rd_byte(pc98_font_row), .kanji_seen(pc98_kanji_seen)
    );

    // The fill's view, latched per cell: tvram_fil_cell/lo/hi are stable for
    // several clocks per cell, so a straight register catches the settled
    // pair. Only row 0's cells 0-7 are kept (tv_cell is the plane-wide cell
    // index, so no other row's fill reaches index <8). Byte 2n = hi, 2n+1 =
    // lo, so one reading reads like the TVRAM itself.
    always_ff @(posedge clock) begin
        // BYTE lanes, not bit indices, and FOUR cells, not eight.
        //
        // This used to index pc98_tvfill_view -- 64 BITS -- with 0..15 and
        // assign an eight-bit value to the single bit it selected: every byte
        // collapsed to its LSB, in the wrong place, and the TVF readout has
        // been noise since the day it was added. The comment always said
        // "byte", and eight cells of {hi,lo} is 128 bits, which never fit:
        // softcpu_subsystem serves exactly two words (0x5000009C and A0), so
        // four cells is what the panel can show.
        if (tvram_fil_cell < 12'd4) begin
            pc98_tvfill_view[{tvram_fil_cell[1:0], 1'b0} * 8 +: 8] <= tvram_vid_char_hi;
            pc98_tvfill_view[{tvram_fil_cell[1:0], 1'b1} * 8 +: 8] <= tvram_vid_char_lo;
        end
    end

    always_ff @(posedge clock) begin
        if (pc98_f_req & ~pc98_f_req_q) pc98_rowbuf_freq_count <= pc98_rowbuf_freq_count + 16'd1;
        pc98_f_req_q <= pc98_f_req;
        if (pc98_f_valid) pc98_rowbuf_fvalid_count <= pc98_rowbuf_fvalid_count + 16'd1;
    end


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
        .mem_wr(cgwin_mem_select & ~memory_write_n),
        .wr_addr(address[11:0]), .wr_data(internal_data_bus),
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

    // The ANK BRAM: the row buffer's ANK source, on the same clock as its FSM.
    // Plain text comes out of here -- the SDRAM burst path is for kanji only.
    pc98_font_ank u_pc98_font (
        .wr_clk(font_wr_clk), .wr_en(font_wr_en),
        .wr_addr(font_wr_addr), .wr_data(font_wr_data),
        .rd_clk(clock),
        .code(pc98_ank_code), .line(pc98_ank_line),
        .row(pc98_ank_row)
    );

    // The attribute's colour field is G R B, so it maps to the output that way
    // round. Full intensity: PC-98 text has no half-bright.
    assign VID_R     = (pc98_pixel & pc98_grb[1]) ? 6'h3F : 6'h00;
    assign VID_G     = (pc98_pixel & pc98_grb[2]) ? 6'h3F : 6'h00;
    assign VID_B     = (pc98_pixel & pc98_grb[0]) ? 6'h3F : 6'h00;
    assign VID_HSYNC = pc98_hs;
    assign VID_VSYNC = pc98_vs;
    assign VID_HBlank = pc98_hb;
    assign VID_VBlank = pc98_vb;
    assign de_o      = pc98_de;

    wire [7:0]  tvram_cpu_q;
    wire [11:0] tvram_vid_cell = tvram_vid_cell_w;   // renderer, attributes
    wire [11:0] tvram_fil_cell;                      // row buffer, codes
    wire [7:0]  tvram_vid_char_lo, tvram_vid_char_hi, tvram_vid_attr;

    pc98_tvram u_tvram (
        .clk         (clock),
        // Reloads the memory switch registers at A3FE2+4i -- see the module.
        .rst         (reset),
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


    //
    // XT2IDE
    //
    // GONE ON PC-98. The AT task-file at 0x300-0x30F is a PC/XT interface; a
    // PC-98 uses SASI (0x80/0x82), SCSI (0xCC0-0xCC6) or -- only from the
    // 9821 generation -- IDE at 0x640-0x64F. Neither bios.rom nor itf.rom
    // references 0x640-0x64F at all, in any addressing form, so nothing in
    // this machine's ROM set could ever drive what is here. It was inherited
    // from the PC/XT base and instantiated unconditionally, so it has been
    // occupying a device that is at 91% ALM.
    //
    // np2kai agrees about the generation: SUPPORT_IDEIO is in its ia32 /
    // PC-9821 definitions only, while the V30/286 common build gets
    // SUPPORT_SCSI. SCSI at 0xCC0 is what replaces this.
    // (Nothing is left to read out of that block: the request output it used
    // to drive went with it, and core_top holds the softcore's ide0_request at
    // 3'b000 directly.)


    //
    // SCSI -- the PC-9801-55 board at 0x0CC0-0x0CC7
    //
    // The window itself is pc98_scsi.sv; this is the decode and the softcore's
    // way in. mgmt chip-select 0xF4, next to ide.v's 0xF0 and floppy.v's 0xF2.
    //
    // The management side is eight registers, because mgmt_address carries
    // only four bits of register within a chip-select and the data buffer is
    // 8 KB. An index-plus-autoincrementing-data-port pair reaches both the
    // control file and the buffer, which is the same shape ide.v uses for
    // sector data (its mgmt register 0xF).
    //
    //   0  R: {cmd_byte, 7'd0, cmd_req}   W: bit0 acknowledges the request
    //   1  W: control-register index
    //   2  R/W: control register at the index, index post-increments
    //   3  W: buffer pointer (13 bits)
    //   4  R/W: buffer byte at the pointer, pointer post-increments
    //   5  W: auxstatus, the byte 0xCC0 hands the guest
    //   6  W: scsistatus, the byte index 0x17 hands the guest
    //   7  W: bit0 rewinds the guest's read pointer, bit1 its write pointer
    //
    wire scsi_cs = iorq & ~address_enable_n & (address[15:3] == 13'h198);

    // The board's option ROM at D2000-D2FFF. The BIOS scan at FFF23 walks
    // sixteen 4 KB windows from D000 and far-calls offset 000C of any that
    // carries 55 AA at offset 9; D200 is the third. The SDRAM map does not
    // cover D0000-DFFFF (pc98_sdram_map.svh: a[19:16] >= 0xC and below
    // 0b11101 hits nothing), so this window is the only thing there.
    wire    scsi_rom_select = ~iorq && ~address_enable_n
                            && (address[19:12] == 8'hD2);
    wire [7:0] scsi_rom_q;

    pc98_scsi_rom u_pc98_scsi_rom (
        .clk  (clock),
        .addr (address[11:0]),
        .q    (scsi_rom_q)
    );

    logic        mgmt_scsi_cs;
    assign       mgmt_scsi_cs = (mgmt_address[15:8] == 8'hF4);
    wire         mgmt_scsi_wr = mgmt_write & mgmt_scsi_cs;
    wire         mgmt_scsi_rd = mgmt_read  & mgmt_scsi_cs;
    wire  [3:0]  mgmt_scsi_reg = mgmt_address[3:0];

    logic  [4:0] scsi_mg_reg_addr;
    logic [12:0] scsi_mg_buf_addr;
    logic        scsi_cmd_ack;            // the firmware's copy of cmd_req

    wire   [7:0] scsi_mg_reg_rdata;
    wire   [7:0] scsi_mg_buf_rdata;
    wire         scsi_cmd_req;
    wire   [7:0] scsi_cmd_byte;
    wire   [7:0] scsi_data_out;
    wire         scsi_read_select;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            scsi_mg_reg_addr <= 5'd0;
            scsi_mg_buf_addr <= 13'd0;
            scsi_cmd_ack     <= 1'b0;
        end else begin
            if (mgmt_scsi_wr) begin
                case (mgmt_scsi_reg)
                    4'd0: if (mgmt_writedata[0]) scsi_cmd_ack <= scsi_cmd_req;
                    4'd1: scsi_mg_reg_addr <= mgmt_writedata[4:0];
                    4'd2: scsi_mg_reg_addr <= scsi_mg_reg_addr + 5'd1;
                    4'd3: scsi_mg_buf_addr <= mgmt_writedata[12:0];
                    4'd4: scsi_mg_buf_addr <= scsi_mg_buf_addr + 13'd1;
                    default: ;
                endcase
            end
            // A read advances the same way a write does, so the firmware can
            // stream a sector out of the buffer without re-addressing it.
            if (mgmt_scsi_rd) begin
                case (mgmt_scsi_reg)
                    4'd2: scsi_mg_reg_addr <= scsi_mg_reg_addr + 5'd1;
                    4'd4: scsi_mg_buf_addr <= scsi_mg_buf_addr + 13'd1;
                    default: ;
                endcase
            end
        end
    end

    logic [15:0] mgmt_scsi_readdata;
    always_comb begin
        case (mgmt_scsi_reg)
            4'd0: mgmt_scsi_readdata = {scsi_cmd_byte,
                                        7'd0, scsi_cmd_req ^ scsi_cmd_ack};
            4'd2: mgmt_scsi_readdata = {8'd0, scsi_mg_reg_rdata};
            4'd4: mgmt_scsi_readdata = {8'd0, scsi_mg_buf_rdata};
            default: mgmt_scsi_readdata = 16'h0000;
        endcase
    end

    pc98_scsi u_pc98_scsi (
        .clk                (clock),
        .rst                (reset),
        .cs                 (scsi_cs),
        .a1a2               (address[2:1]),
        .io_read_n          (io_read_n),
        .io_write_n         (io_write_n),
        .data_in            (internal_data_bus),
        .data_out           (scsi_data_out),
        .read_select        (scsi_read_select),
        .cmd_req            (scsi_cmd_req),
        .cmd_byte           (scsi_cmd_byte),
        .mg_reg_addr        (scsi_mg_reg_addr),
        .mg_reg_we          (mgmt_scsi_wr & (mgmt_scsi_reg == 4'd2)),
        .mg_reg_wdata       (mgmt_writedata[7:0]),
        .mg_reg_rdata       (scsi_mg_reg_rdata),
        .mg_buf_addr        (scsi_mg_buf_addr),
        .mg_buf_we          (mgmt_scsi_wr & (mgmt_scsi_reg == 4'd4)),
        .mg_buf_wdata       (mgmt_writedata[7:0]),
        .mg_buf_rdata       (scsi_mg_buf_rdata),
        .mg_auxstatus       (mgmt_writedata[7:0]),
        .mg_auxstatus_we    (mgmt_scsi_wr & (mgmt_scsi_reg == 4'd5)),
        .mg_scsistatus      (mgmt_writedata[7:0]),
        .mg_scsistatus_we   (mgmt_scsi_wr & (mgmt_scsi_reg == 4'd6)),
        .mg_rdptr_clr       (mgmt_scsi_wr & (mgmt_scsi_reg == 4'd7) & mgmt_writedata[0]),
        .mg_wrptr_clr       (mgmt_scsi_wr & (mgmt_scsi_reg == 4'd7) & mgmt_writedata[1])
    );

`ifdef ENABLE_OPNA
    //
    // OPNA -- the PC-9801-86 sound board's YM2608 at 0x0188-0x018F
    //
    // The chip and its register router are pc98_opna.sv; this is the decode,
    // the softcore's way in, and the one register the board keeps outside the
    // chip. mgmt chip-select 0xF5, next to pc98_scsi's 0xF4.
    //
    // np2kai cbus/board86.c:171 binds the ports as
    //   cbuscore_attachsndex(0x188 + g_opna[0].s.base, opna_o, opna_i)
    // with s.base 0 for the default dip setting (board86.c:158-162), and only
    // the even addresses in the window are the board.
    //
    // 0xA460 bit 0 is the odd one out: it is not a YM2608 register at all.
    // np2kai cbus/pcm86io.c:45-51 has pcm86_oa460 call fmboard_extenable(val&1)
    // and board86.c:107-120 makes that the difference between a 6-channel
    // stereo OPNA with a second register pair and a 3-channel mono OPN. Every
    // PC-98 FM driver sets it, and without it half the chip is invisible.
    // The rest of 0xA460-0xA46C is the -86's own 16-bit PCM, which this core
    // does not have.
    //
    wire opna_cs = iorq & ~address_enable_n
                 & (address[15:3] == 13'h031) & ~address[0];

    wire opna_a460_wr = iorq & ~address_enable_n & ~io_write_n
                      & (address[15:0] == 16'hA460);

    logic opna_extend;
    always_ff @(posedge clock, posedge reset) begin
        if (reset)             opna_extend <= 1'b0;
        else if (opna_a460_wr) opna_extend <= internal_data_bus[0];
    end

    logic        mgmt_opna_cs;
    assign       mgmt_opna_cs = (mgmt_address[15:8] == 8'hF5);
    wire         mgmt_opna_wr = mgmt_write & mgmt_opna_cs;
    wire  [3:0]  mgmt_opna_reg = mgmt_address[3:0];
    wire [15:0]  mgmt_opna_readdata;

    wire  [7:0]  opna_data_out;
    wire         opna_read_select;
    wire [23:0]  opna_adpcmb_addr;
    wire         opna_adpcmb_roe_n;

    pc98_opna u_pc98_opna (
        .clk          (clock),
        .rst          (reset),
        .cs           (opna_cs),
        .a2a1         (address[2:1]),
        .io_read_n    (io_read_n),
        .io_write_n   (io_write_n),
        .data_in      (internal_data_bus),
        .data_out     (opna_data_out),
        .read_select  (opna_read_select),
        .ext_enable   (opna_extend),
        .irq          (opna_irq),
        .mg_reg       (mgmt_opna_reg),
        .mg_wr        (mgmt_opna_wr),
        .mg_wdata     (mgmt_writedata),
        .mg_rdata     (mgmt_opna_readdata),
        // No fourth sdram_mp.sv port yet, so the board's 256 KB of ADPCM RAM
        // reads as zero and the DELTA-T channel is silent. Nothing else in the
        // chip depends on it; see the gap list in pc98_opna.sv.
        .adpcmb_addr  (opna_adpcmb_addr),
        .adpcmb_roe_n (opna_adpcmb_roe_n),
        .adpcmb_data  (8'h00),
        .snd_l        (opna_snd_l),
        .snd_r        (opna_snd_r)
    );
`else
    // OFF BY DEFAULT, AND THE REASON IS THE DEVICE, NOT THE DESIGN.
    //
    // pc98_opna measures 1733 ALMs standalone against about 1806 free, which
    // read as fitting with room to spare. It does not:
    //
    //   Error (170012): Fitter requires 1876 LABs to implement the design,
    //                   but the device contains only 1848 LABs
    //
    // ALM count is not the binding constraint at this density. A LAB holds ten
    // ALMs and cannot be packed arbitrarily, so 99 per cent of the ALM budget
    // is more than 100 per cent of the LAB budget, and "73 ALMs to spare" was
    // measuring the wrong thing.
    //
    // Everything stays: the vendored jt12, pc98_opna.sv, the decode above and
    // tb_pc98_opna in CI. Define ENABLE_OPNA when there is real room -- the
    // audio filter's fixed-coefficient rework is about 490 ALMs and is the
    // nearest candidate.
    assign opna_snd_l = 16'sd0;
    assign opna_snd_r = 16'sd0;
`endif

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
    logic   [7:0]   fdd_io_writedata;
    logic   [7:0]   fdd_readdata_wire;
    logic   [7:0]   fdd_dma_readdata;
    logic   [7:0]   fdd_readdata;
    logic           fdd_dma_req_wire;
    logic           fdd_dma_read;
    logic           prev_fdd_dma_ack;
    logic           fdd_dma_rw_ack;
    logic           fdd_dma_tc;
    wire    [7:0]   fdc_cmd_accepts;
    wire    [7:0]   fdc_cmd_drops;
    wire    [3:0]   fdc_reply_left;

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
        if (~io_read_n && ~address_enable_n)
            fdc_last_rdport <= address[7:0];
    end

`ifdef PC98_FDC_REAL
    // The PC-98 ports onto floppy.v's PC/XT register file. The MSR and FIFO
    // map straight across; the control port has to BECOME a Digital Output
    // Register, because a PC-98 has none and floppy.v will not run without
    // one. pc98_fdc_glue does that -- see it for what each bit becomes and
    // why.
    wire [2:0] fdc_glue_addr;
    wire       fdc_glue_write;
    wire       fdc_glue_read;
    wire [7:0] fdc_glue_wdata;

    // THE WRITE IS DECODED FROM A LATCHED ADDRESS, and this is the whole
    // reason the FDC never worked.
    //
    // The house idiom fires a write one cycle AFTER the strobe ends
    // (io_write_n & ~prev_io_write_n) and decodes the port from the LIVE
    // address bus at that moment. By then the address has usually moved on
    // to the next bus cycle -- the prefetch that follows the OUT. So the
    // decode catches a write only when the guest happens to do nothing on
    // the bus right after it, and the counters said exactly that:
    //
    //   ITF 1BA3   in 0BEh / out 0BEh,al        -> plain code follows: MISSED
    //              out 94h,80h / LOOP $         -> 65536 idle iterations: HIT
    //              out 94h,10h / (loop above)   -> HIT
    //   BIOS       out 94h,08h / ret            -> stack + prefetch: MISSED
    //              the command bytes to 0x92    -> a tight loop of bus
    //                                             cycles: ALWAYS MISSED
    //
    // n94 02 (the two ITF writes with LOOP behind them, and nothing else),
    // nBE 00, nD 00, and an LB of 48 -- a byte no ROM ever writes to these
    // ports, because the address that latched it belonged to one write and
    // the data to another.
    //
    // So the port is captured WHILE the write is on the bus and used at the
    // end -- the same shape write_to_fdd uses for the byte, and for the same
    // reason. Not at the start: capturing on the falling edge of io_write_n
    // took n94 from 02 to 00 and nCC from 03 to 00 on metal, which says the
    // address is not settled yet when the strobe goes low. Sampled on every
    // low cycle, what survives is the last one before the strobe rises --
    // the real port, and immune to the next bus cycle claiming the pins on
    // the very clock the strobe ends. Reads are untouched: they decode live,
    // on their own start-of-read strobe.
    logic [15:0] io_wr_addr_q = 16'h0000;
    logic        io_wr_aen_q  = 1'b1;
    always_ff @(posedge clock) begin
        if (~io_write_n) begin
            io_wr_addr_q <= address[15:0];
            io_wr_aen_q  <= address_enable_n;
        end
    end

    wire        fdc_wr_edge  = io_write_n & ~prev_io_write_n;
    wire [15:0] fdc_addr_eff = fdc_wr_edge ? io_wr_addr_q     : address[15:0];
    wire        fdc_aen_eff  = fdc_wr_edge ? io_wr_aen_q      : address_enable_n;

    wire pc98_addr_win = ~fdc_aen_eff & (fdc_addr_eff[15:8] == 8'h00);
    wire fdd_ctrl_win  = pc98_addr_win & ((fdc_addr_eff[7:0] == 8'h94)
                                        |  (fdc_addr_eff[7:0] == 8'hCC));
    wire fdd_mode_win  = pc98_addr_win &  (fdc_addr_eff[7:0] == 8'hBE);
    // The MSR/FIFO pairs, the same set floppy0_chip_select_n covers, but off
    // the effective address so a write lands on the port it was issued to.
    wire fdd_fifo_win  = pc98_addr_win & ((fdc_addr_eff[7:0] == 8'h90)
                                        |  (fdc_addr_eff[7:0] == 8'h92)
                                        |  (fdc_addr_eff[7:0] == 8'hC8)
                                        |  (fdc_addr_eff[7:0] == 8'hCA));

    pc98_fdc_glue u_pc98_fdc_glue (
        .clk           (clock),
        .rst           (reset),
        // floppy0_chip_select_n covers 0x90/0x92/0xC8/0xCA in this build;
        // address[1] is what separates status from data within each pair, and
        // address[6] is what separates the 2HD window from the 2DD one --
        // 0x90/0x92/0x94 have it clear, 0xC8/0xCA/0xCC set. The glue needs
        // that to apply np2kai's ((port >> 4) ^ chgreg) & 1 guard and to know
        // which slave line an interrupt belongs on.
        .sel_stat      (fdd_fifo_win & ~fdc_addr_eff[1]),
        .sel_data      (fdd_fifo_win &  fdc_addr_eff[1]),
        .sel_ctrl      (fdd_ctrl_win),
        .sel_mode      (fdd_mode_win),
        .port_2dd      (fdc_addr_eff[6]),
        // The selects already carry the window -- and, on the end-of-write
        // cycle, the window of the write that just finished.
        .wr_stb        (fdc_wr_edge),
        .wr_data       (write_to_fdd),
        .rd_stb        (~io_read_n & prev_io_read_n & ~floppy0_chip_select_n),
        .fd_addr       (fdc_glue_addr),
        .fd_write      (fdc_glue_write),
        .fd_read       (fdc_glue_read),
        .fd_wdata      (fdc_glue_wdata),
        .fd_irq        (fdd_interrupt),
        .ctrl_readback (fdc_ctrl_readback),
        .mode_readback (fdc_mode_readback),
        .group_live    (fdc_group_live),
        .irq_2hd       (fdc_glue_irq_2hd),
        .irq_2dd       (fdc_glue_irq_2dd),
        .dbg_motor_arms   (dbg_motor_arms),
        .dbg_motor_pulses (dbg_motor_pulses),
        .dbg_chg       (dbg_chg),
        .dbg_strb_be   (dbg_strb_be),
        .dbg_strb_94   (dbg_strb_94),
        .dbg_strb_cc   (dbg_strb_cc),
        .dbg_strb_dat  (dbg_strb_dat),
        .dbg_last_ctrl (dbg_last_ctrl)
    );

    always_ff @(posedge clock)
    begin
        fdd_io_address     <= fdc_glue_addr;
        // The read strobe carries the guard too, and the glue applies it. A
        // read of the window chgreg did not select must not reach floppy.v at
        // all: register 5 is where the interrupt gets acknowledged (floppy.v
        // lowers irq on exactly `io_read && io_address == 5`), and a probe of
        // the dead window would otherwise throw away the interrupt the live
        // one is holding.
        fdd_io_read        <= fdc_glue_read;
        fdd_io_read_1      <= fdd_io_read;
        fdd_io_write       <= fdc_glue_write;
        // AND THE BYTE. fd_wdata is not the guest's byte: on a 0x94 write the
        // glue addresses register 2 and hands over a SYNTHESISED DOR, and on
        // a pending reset register 4 with 0x80. floppy.v was wired straight
        // to write_to_fdd -- the raw guest byte -- so the DOR it latched was
        // whatever the PC-98 control port happened to hold, and bit 2 of that
        // is not "enable". LB 48 clears it, which holds floppy.v in reset:
        // MSR never raises RQM, the BIOS polls 0x90 forever and never writes
        // a command byte (nD 00 on metal, with n94 02 / nCC 03 above it).
        // The address and the strobe are registered here, so the byte has to
        // be registered with them or it arrives a cycle early.
        fdd_io_writedata   <= fdc_glue_wdata;
    end
`else
    always_ff @(posedge clock)
    begin
        fdd_io_address     <= address[2:0];
        fdd_io_read        <= ~io_read_n & prev_io_read_n   & ~floppy0_chip_select_n;
        fdd_io_read_1      <= fdd_io_read;
        fdd_io_write       <= io_write_n & ~prev_io_write_n & ~floppy0_chip_select_n;
        fdd_io_writedata   <= write_to_fdd;   // the PC/XT path: the guest's byte
    end
`endif

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

    // NOT_READY_ENDS_COMMAND is a property of the DRIVES, not of the register
    // mapping, so it follows MACHINE_PC98 rather than PC98_FDC_REAL: a PC-98's
    // 2HD/2DD drives return READY and a PC/AT's do not (see floppy.v). With no
    // disk in the drive -- this core's normal state -- it is the difference
    // between a result phase carrying ST0 = 48h and a CB bit that never clears.

    // ---- write-path witnesses, counted HERE, before any glue ------------
    //
    // The glue's strobe counters came back all zero while the IO trace showed
    // the writes, and G 03 hints the 0xBE READ path works -- so the split to
    // make is decode/level/edge, each counted on the same ports:
    //   w_ioexact   clocks pc98_io_exact was true at all
    //   w_rd_lvl    read levels on fdd_94|cc|be selects (~io_read_n)
    //   w_wr_lvl    write levels on the same selects (~io_write_n)
    //   w_wr_edge   the raw io_write_n & ~prev_io_write_n strobe, any port
    logic [7:0] w_ioexact = 8'd0, w_rd_lvl = 8'd0, w_wr_lvl = 8'd0, w_wr_edge = 8'd0;
    always_ff @(posedge clock) begin
        if (pc98_io_exact && w_ioexact != 8'hFF)
            w_ioexact <= w_ioexact + 8'd1;
        if ((fdd_94_select | fdd_cc_select | fdd_be_select) & ~io_read_n
            && w_rd_lvl != 8'hFF)
            w_rd_lvl <= w_rd_lvl + 8'd1;
        if ((fdd_94_select | fdd_cc_select | fdd_be_select) & ~io_write_n
            && w_wr_lvl != 8'hFF)
            w_wr_lvl <= w_wr_lvl + 8'd1;
        if (io_write_n & ~prev_io_write_n && w_wr_edge != 8'hFF)
            w_wr_edge <= w_wr_edge + 8'd1;
    end
    assign dbg_w_path = {w_wr_edge, w_ioexact};   // [15:8] edge, [7:0] decode
    assign dbg_rw_lvl = {w_wr_lvl, w_rd_lvl};     // [15:8] writes, [7:0] reads

`ifdef PC98_FDC_REAL
    // ---- the controller, watched where it meets the chipset -------------
    //
    // nD 0D says the command bytes now land; r2 00 with m2 F7 says the BIOS
    // has unmasked slave bit 3 (INT 13h, the 2HD line) and is waiting for an
    // interrupt that never comes. Between those two facts sit floppy.v's MSR,
    // its irq pin, and the DOR it is holding -- none of which anything has
    // ever read out. IQ 00 means the chip never raised irq; a DOR with bit 3
    // clear means it was told not to.
    logic [7:0] fdc_msr_seen   = 8'h00;
    logic [7:0] fdc_irq_rises  = 8'd0;
    logic [7:0] fdc_dor_seen   = 8'h00;
    logic [7:0] fdc_res_reads  = 8'd0;
    logic [7:0] fdc_last_94    = 8'h00;
    logic [7:0] fdc_last_be    = 8'h00;   // last byte written to 0xBE (chgreg)
    logic [7:0] fdc_last_cc    = 8'h00;
    logic [7:0] fdc_last_rd    = 8'h00;
    // The port of the LAST I/O read of any kind -- which poll loop the CPU
    // is in RIGHT NOW: 0x90 the MSR wait, 0x92 the result drain, 0x08 the
    // slave-PIC in-service poll, 0x33 the calendar, 0x42 the printer gate.
    // Sampled while the cycle is live, same as write_to_fdd.
    logic [7:0] fdc_last_rdport = 8'h00;
    // Reads that reached the chip, against reads the window guard answered
    // with 0xFF from the chipset. The guest's MSR poll is the boot's whole
    // inner loop, so if it is polling a DEAD window it sees FF forever --
    // and MS, which only updates on a read that gets through, freezes at
    // whatever it last really saw. MS D0 with RL 0 is exactly that shape.
    logic [7:0] fdc_live_reads = 8'd0;
    logic [7:0] fdc_dead_reads = 8'd0;
    logic [7:0] fdc_last_port  = 8'h00;
    logic [95:0] fdc_fifo_ring = 96'h0;
    logic       prev_fdd_irq   = 1'b0;
    always_ff @(posedge clock) begin
        prev_fdd_irq <= fdd_interrupt;
        if (fdd_interrupt & ~prev_fdd_irq & (fdc_irq_rises != 8'hFF))
            fdc_irq_rises <= fdc_irq_rises + 8'd1;
        if (~io_read_n & prev_io_read_n & pc98_addr_win
            & ((address[7:0] == 8'h90) | (address[7:0] == 8'h92)
             | (address[7:0] == 8'hC8) | (address[7:0] == 8'hCA))) begin
            fdc_last_port <= address[7:0];
            if (fdc_group_live) begin
                if (fdc_live_reads != 8'hFF)
                    fdc_live_reads <= fdc_live_reads + 8'd1;
            end
            else if (fdc_dead_reads != 8'hFF)
                fdc_dead_reads <= fdc_dead_reads + 8'd1;
        end
        if (fdd_io_read_1 & ~address_enable_n) begin
            if (fdd_io_address == 3'd4) fdc_msr_seen <= fdd_readdata_wire;
            if (fdd_io_address == 3'd5) begin
                fdc_last_rd <= fdd_readdata_wire;
                if (fdc_res_reads != 8'hFF)
                    fdc_res_reads <= fdc_res_reads + 8'd1;
            end
        end
        if (fdd_io_write && (fdd_io_address == 3'd2))
            fdc_dor_seen <= fdd_io_writedata;
        // The command stream itself, newest byte in the low end. A 07 01
        // is a RECALIBRATE of drive 1; 08 is SENSE INTERRUPT STATUS; 04 is
        // SENSE DRIVE STATUS. Four bytes is one command plus its parameters.
        if (fdd_io_write && (fdd_io_address == 3'd5))
            fdc_fifo_ring <= {fdc_fifo_ring[87:0], fdd_io_writedata};
        if (fdc_wr_edge && fdd_ctrl_win && ~fdc_addr_eff[6])
            fdc_last_94 <= write_to_fdd;
        if (fdc_wr_edge && fdd_ctrl_win &&  fdc_addr_eff[6])
            fdc_last_cc <= write_to_fdd;
        if (fdc_wr_edge && fdd_mode_win)
            fdc_last_be <= write_to_fdd;
    end
    assign dbg_fdc_x = {fdc_res_reads, fdc_dor_seen, fdc_irq_rises, fdc_msr_seen};
    assign dbg_fdc_y = {fdc_last_rd, fdc_last_be, fdc_last_cc, fdc_last_94};
    assign dbg_fdc_z = fdc_fifo_ring;
    // The bottom byte: what the CPU last got back from a read of the SLAVE
    // PIC's IMR port, 0x0A -- the FDC exec's guard tests bit 3 of it before
    // every command, and the panel's m2 reads the REGISTER while this reads
    // the BUS. If the two disagree, the guard is bailing on a ghost.
    logic [7:0] fdc_imr_seen = 8'h00;
    always_ff @(posedge clock)
        if (~io_read_n && ~address_enable_n && (address[7:0] == 8'h0A))
            fdc_imr_seen <= interrupt2_data_bus_out;
    assign dbg_fdc_w = {fdc_cmd_drops, fdc_cmd_accepts, 4'd0, fdc_reply_left, fdc_imr_seen};
    assign dbg_fdc_v = {fdc_last_rdport, fdc_last_port, fdc_dead_reads, fdc_live_reads};
`else
    assign dbg_fdc_x = 32'd0;
    assign dbg_fdc_y = 32'd0;
    assign dbg_fdc_z = 96'd0;
    assign dbg_fdc_w = 32'd0;
    assign dbg_fdc_v = 32'd0;
`endif

    floppy #(
        .NOT_READY_ENDS_COMMAND     (1)
    ) floppy
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
        .io_writedata               (fdd_io_writedata),

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

        .request                    (fdd_request),

        .dbg_cmd_accepts            (fdc_cmd_accepts),
        .dbg_cmd_drops              (fdc_cmd_drops),
        .dbg_reply_left             (fdc_reply_left)
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
`ifdef ENABLE_OPNA
    assign mgmt_readdata = mgmt_scsi_cs ? mgmt_scsi_readdata
                         : mgmt_opna_cs ? mgmt_opna_readdata : mgmt_fdd_readdata;
`else
    assign mgmt_readdata = mgmt_scsi_cs ? mgmt_scsi_readdata : mgmt_fdd_readdata;
`endif


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

	 
    



    //
    // data_bus_out
    //
    
    // The vector byte of the LAST acknowledge, latched as the SECOND pulse
    // of the pair closes. The 8288 sequences two pulses per interrupt and
    // the chip answers on the second, so the byte sitting on the mux below
    // near the end of that pulse is what the CPU takes.
    logic       inta_q;
    logic       inta_second;         // 1 while the pulse in flight is #2
    logic [7:0] inta_vec_sample;
    always_ff @(posedge clock) inta_q <= interrupt_acknowledge_n;
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            inta_second     <= 1'b0;
            inta_vec_sample <= 8'h00;
            dbg_inta_vec    <= 8'h00;
            dbg_inta_count  <= 16'd0;
        end
        else begin
            // Track the bus through the pulse; the answer is on it well
            // before the pulse ends.
            if (~interrupt_acknowledge_n)
                inta_vec_sample <= data_bus_out;
            // A pulse just closed. The second of the pair carried the
            // vector -- keep it.
            if (~inta_q && interrupt_acknowledge_n) begin
                if (inta_second) begin
                    dbg_inta_vec <= inta_vec_sample;
                    if (dbg_inta_count != 16'hFFFF)
                        dbg_inta_count <= dbg_inta_count + 16'd1;
                end
                inta_second <= ~inta_second;
            end
        end
    end

    always_ff @(posedge clock)
    begin
        if (~interrupt_acknowledge_n)
        begin
            // During the acknowledge the master either drives its own vector
            // or puts the slave's ID on the cascade lines and stands down --
            // data_bus_io is how the slave says it recognized itself.
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= (~interrupt2_data_bus_io) ? interrupt2_data_bus_out
                                                      : interrupt_data_bus_out;
        end
        else if ((~interrupt2_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= interrupt2_data_bus_out;
        end
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
        // BEFORE the 8255, and this order is the whole point.
        //
        // 0x31, 0x35 and 0x37 are the PPI's registers on a PC-98 as well, so
        // the chip answers them -- and its port C resets to zero. The ITF
        // reads bit 7 of 0x35 at F805D to tell a power-on from a return from
        // OUT 0F0h; zero means "resume", so it restored SS:SP from an
        // uninitialised 0000:0404 and RETF'd into nothing. On the hardware
        // that is a machine parked at FD807 with one I/O write to its name.
        //
        // The bench never had a PPI on those addresses, answered from its own
        // model, and booted -- which is exactly the kind of divergence a bench
        // is supposed to catch rather than create.
        else if (sysport_read)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= sysport_data;
        end
        // The keyboard 8251 at 0x41/0x43, claiming exactly those two ports.
        // The decode is exact so nothing above can collide with it; this
        // entry sits after the timer/interrupt/sysport ones only to keep the
        // mux's history.
        //
        // Default ON (config.tcl defines PC98_KBD_8251): without it nobody
        // answers 0x41/0x43, the ITF takes its no-keyboard path, [0x0500]
        // bit 7 never gets set, and BASIC has no keyboard at all. Undefine
        // the macro to fall back to the dead ports -- e.g. to bisect a
        // suspect keyboard interaction on hardware.
`ifdef PC98_KBD_8251
        else if (kbd8251_read_select)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= kbd8251_read_data;
        end
`endif
        else if (scsi_rom_select && (~memory_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= scsi_rom_q;
        end
        else if (scsi_read_select)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= scsi_data_out;
        end
`ifdef ENABLE_OPNA
        else if (opna_read_select)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= opna_data_out;
        end
`endif
        else if (grcg_mode_cs & ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= grcg_mode_rd;
        end
        else if (pg_a4_cs & ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= {7'b0, gvram_disp_page};   // np2kai gdc_ia4
        end
        else if (pg_a6_cs & ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= {7'b0, gvram_access_page}; // np2kai gdc_ia6
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
        else if (`ENABLE_EMS && (ems_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ena_ems[address[1:0]] ? map_ems[address[1:0]] : 8'hFF;
        end
        else if ((~floppy0_chip_select_n || fdd_dma_read) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= fdd_readdata;
        end
        else
        begin
            data_bus_out_from_chipset <= 1'b0;
            data_bus_out <= 8'b00000000;
        end
    end

endmodule
