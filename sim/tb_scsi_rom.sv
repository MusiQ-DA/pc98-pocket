//
// tb_scsi_rom -- the PC-9801-55 option ROM window at D2000, on the real
// Chipset.
//
// Same shape as tb_xrom: the POST's signature check reads word [seg:9] and
// byte 9 sits on the HIGH lane, which this bench drives and samples
// directly. The window's storage is the 4 KB $readmemh image assembled
// from fpga/scsi_rom.asm -- signature, all four POST entry points and the
// 0x18 INT 1Bh dispatch entry -- so the checks pin bytes that have to be
// there for the ROM scan, the XROM registration and the IPL load to work,
// plus the boundary: inside D2000-D2FFF the byte comes from the ROM, outside
// it reads like the empty window it shares the decode region with.
//
// The low lane arrives through Peripherals' registered data_bus_out; the
// high lane is the ROM's second read port muxed in Chipset, so this bench
// is what proves the signature word can reach the CPU at all.
//
`default_nettype none
`timescale 1ns/1ps

module tb_scsi_rom;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1, sdram_reset = 1;
    always #(HALF_NS) clock = ~clock;

    // The arbiter only leaves its reset state (address_enable_n=1, which
    // selects address_ext/DMA) on cpu_ce_posedge, so it must pulse like
    // the real CPU clock-enable or guest reads never take the bus.
    logic cpu_ce_posedge = 1'b0, cpu_ce_negedge = 1'b0;
    int   ce_div = 0;
    always @(posedge clock) begin
        cpu_ce_posedge <= 1'b0;
        cpu_ce_negedge <= 1'b0;
        if (ce_div == 7) begin
            cpu_ce_posedge <= 1'b1;
            ce_div <= 0;
        end else if (ce_div == 3) begin
            cpu_ce_negedge <= 1'b1;
            ce_div <= ce_div + 1;
        end else
            ce_div <= ce_div + 1;
    end

    logic [19:0] cpu_address = '0;
    logic        cpu_word_access = 1'b0;
    logic        memory_read_n_ext = 1'b1;

    wire  [19:0] address;
    wire  [7:0]  data_bus, data_bus_hi;
    wire         memory_read_n, data_bus_direction;

    CHIPSET u_chipset (
        .clock(clock), .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(cpu_ce_negedge),
        .clk_select(2'b00), .reset(reset), .sdram_reset(sdram_reset),
        .cpu_address(cpu_address), .cpu_data_bus(8'h00),
        .cpu_word_access(cpu_word_access), .cpu_data_bus_hi(8'h00),
        .data_bus_hi(data_bus_hi), .pc98_analog(),
        .processor_status(3'b111), .processor_lock_n(1'b1),
        .processor_transmit_or_receive_n(), .processor_ready(),
        .interrupt_to_cpu(), .clk_pc98_dot(clock),
        .gdc_draw_req(), .gdc_draw_busy(),
        .gdc_draw_ops(), .gdc_draw_snaps(),
        .gdc_srv_done_levels(2'b00), .de_o(),
        .VID_R(), .VID_G(), .VID_B(), .VID_HSYNC(), .VID_VSYNC(),
        .VID_HBlank(), .VID_VBlank(),
        .address(address), .address_ext(20'h00000), .address_direction(),
        .data_bus(data_bus), .data_bus_ext(8'h00),
        .data_bus_direction(data_bus_direction), .address_latch_enable(),
        .io_channel_ready(1'b1), .interrupt_request(8'h00),
        .io_read_n(), .io_read_n_ext(1'b1), .io_read_n_direction(),
        .io_write_n(), .io_write_n_ext(1'b1), .io_write_n_direction(),
        .memory_read_n(memory_read_n), .memory_read_n_ext(memory_read_n_ext),
        .memory_read_n_direction(),
        .memory_write_n(), .memory_write_n_ext(1'b1),
        .memory_write_n_direction(),
        .ext_access_request(1'b0),
        // DRQ pins are active-low: all-ones = no request.
        .dma_request(4'hF), .dma_acknowledge_n(),
        .address_enable_n(), .terminal_count_n(),
        .timer_counter_out(), .speaker_out(),
        .kb_byte(8'h00), .kb_valid(1'b0), .kb_ready(),
        .opna_snd_l(), .opna_snd_r(),
        .font_bank_flag(1'b0), .bios_shadow_flag(1'b0),
        .font_wr_clk(1'b0), .font_wr_en(1'b0),
        .font_wr_addr(12'h000), .font_wr_data(16'h0000),
        .enable_sdram(1'b0), .initilized_sdram(),
        .sdram_clock(clock), .sdram_address(), .sdram_cke(), .sdram_cs(),
        .sdram_ras(), .sdram_cas(), .sdram_we(), .sdram_ba(),
        .sdram_dq_in(16'h0000), .sdram_dq_out(), .sdram_dq_io(),
        .sdram_ldqm(), .sdram_udqm(),
        .ems98_maxmem(4'd8), .bios_protect_flag(2'b00),
        .mgmt_address(16'h0000), .mgmt_read(1'b0), .mgmt_readdata(),
        .mgmt_write(1'b0), .mgmt_writedata(16'h0000),
        .floppy_wp(2'b00), .rtc_time(48'h0),
        .fdd_present(), .fdd_request(), .scsi_request(),
        .wait_count_clk_en(1'b0),
        .ram_read_wait_cycle(2'b00), .ram_write_wait_cycle(2'b00),
        .pause_core(),
        .pc98_key_stb(1'b0), .pc98_key_byte(8'h00),
        .mouse_dx(16'sd0), .mouse_dy(16'sd0), .mouse_ev(1'b0),
        .mouse_btn(2'b00), .ram_rw_complete()
    );

    int errors = 0;

    task automatic check(input int a, input logic [7:0] lo, input logic [7:0] hi);
        cpu_address = 20'(a);
        memory_read_n_ext = 1'b0;
        repeat (6) @(posedge clock);
        if (data_bus !== lo) begin
            errors++;
            $display("  LO MISMATCH @%05h: got %02h want %02h", a, data_bus, lo);
        end
        if (data_bus_hi !== hi) begin
            errors++;
            $display("  HI MISMATCH @%05h: got %02h want %02h", a, data_bus_hi, hi);
        end
        memory_read_n_ext = 1'b1;
        repeat (2) @(posedge clock);
    endtask

    initial begin
        $display("=== scsi rom option-ROM decode ===");
        repeat (20) @(posedge clock);
        reset = 0; sdram_reset = 0;
        repeat (20) @(posedge clock);

        // The signature: word [D2009] = AA55h. Byte@9 (odd) must show on
        // the high lane; byte@10 (even) on the low lane.
        check(20'hD2009, 8'h55, 8'h55);   // odd byte: hi lane carries it
        check(20'hD200A, 8'hAA, 8'h90);   // even byte: lo=AA, hi=pad byte
        // The four POST phase entries are at 0x0C/0x0F/0x12/0x15 and the
        // INT 1Bh dispatch entry at 0x18.
        check(20'hD200C, 8'hE9, 8'hF8);   // word@0x0C = F8 E9 -> jmp post_init
        check(20'hD200F, 8'hE9, 8'hE9);   // odd byte: hi lane = the byte itself
        check(20'hD2012, 8'hE9, 8'h11);   // word@0x12 = 11 E9 -> jmp post_boot
        check(20'hD2015, 8'hCB, 8'hCB);   // pass-4 entry: retf (odd: hi=lo)
        check(20'hD2018, 8'h56, 8'h57);   // handler: push si / push di
        check(20'hD201E, 8'h50, 8'h50);   // the locals pushes
        // Bytes the dispatch table registration must contain: post_common
        // at 0x4F9 claims the flag and writes the segment byte to
        // 0x4B2/0x4BA (the 0x2x and 0xAx devtype slots).
        check(20'hD24F9, 8'hC6, 8'hC6);   // mov byte [bx],0FFh (odd: hi=lo)
        check(20'hD2500, 8'hA2, 8'hB2);   // mov [0x04B2],al
        check(20'hD2504, 8'hBA, 8'h04);   // mov [0x04BA],al
        // The transfer loop rebuilds CX after issue_xfer -- the mailbox
        // poll consumes it, and pull_in/pull_skip take their count from it.
        check(20'hD2222, 8'h8B, 8'h4E);   // mov cx,[bp-14]; shl cx,9
        check(20'hD2225, 8'hC1, 8'hC1);   //   (odd: hi=lo)
        // The disk-init and boot paths exist inside the image.
        check(20'hD246E, 8'hBF, 8'hA0);   // disk_init: mov di,0x05A0
        check(20'hD25C2, 8'hCB, 8'hFF);   // post_ret's retf, then open pad
        // Image padding and the window boundary.
        check(20'hD25C3, 8'hFF, 8'hFF);   // odd byte past the code
        check(20'hD2FFF, 8'hFF, 8'hFF);   // last byte of the window
        check(20'hD3000, 8'hFF, 8'h00);   // next 4KB slot: the empty window
        check(20'hD1FFF, 8'hFF, 8'h00);   // the slot below
        check(20'hD1000, 8'hFF, 8'h00);   // the FDD xrom's slot is separate
        check(20'hC0000, 8'hFF, 8'h00);   // below the scan region
        check(20'hDFFFF, 8'hFF, 8'h00);   // top of the scan region
        // A word read at D2008: the signature word reaches the CPU as one
        // unit -- lo=00 (pad byte), hi=55 (the signature's first half).
        cpu_word_access = 1'b1;
        check(20'hD2008, 8'h00, 8'h55);   // word@8: lo=00, hi=55 (offset 9)
        cpu_word_access = 1'b0;

        $display("%s tb_scsi_rom  (errors %0d)", errors ? "FAIL" : "PASS", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
