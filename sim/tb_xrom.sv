//
// tb_xrom -- the built-in 3-mode FDD option ROM, on the real Chipset.
//
// The POST scans D0000-DFFFF in 4KB slots and checks word [seg:9] for
// AA55h, so the signature's first byte sits at an ODD address -- it
// answers on the high lane (BHE), while the code bytes the prefetcher
// reads as words need the low lane at even addresses plus the odd byte
// on the high lane. This bench drives reads straight at the Chipset's
// guest-memory interface (cpu_address + memory_read_n_ext) and checks
// both lanes, in and around the 256-byte ROM window.
//
// It deliberately exercises the boundary: the first slot's tail and the
// neighbouring slots must still read 0xFF like the empty window they
// share the decode region with.
//
`default_nettype none
`timescale 1ns/1ps

module tb_xrom;

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
        .st_req(1'b0), .st_we(1'b0), .st_addr(20'h0), .st_wdata(8'h00),
        .st_done(), .st_rdata(), .accel_status(), .dbg_gvram(),
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
        .floppy_wp(2'b00), .fdd_turbo(1'b0),
        .cfg_dipsw2(8'hE3), .cfg_a3fea(8'h04),
        .cfg_a3fee(8'h00), .cfg_a3ff2(8'h01), .rtc_time(48'h0),
        .fdd_present(), .fdd_request(), .scsi_request(),
        .wait_count_clk_en(1'b0),
        .ram_read_wait_cycle(2'b00), .ram_write_wait_cycle(2'b00),
        .pause_core(),
        .pc98_key_stb(1'b0), .pc98_key_byte(8'h00),
        .mouse_dx(16'sd0), .mouse_dy(16'sd0), .mouse_ev(1'b0),
        .mouse_btn(2'b00), .opna_joy(8'hFF), .ram_rw_complete()
    );

    int errors = 0;

    task automatic check(input int a, input logic [7:0] lo, input logic [7:0] hi);
        cpu_address = 20'(a);
        memory_read_n_ext = 1'b0;
        repeat (4) @(posedge clock);
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
        $display("=== xrom option-ROM decode ===");
        repeat (20) @(posedge clock);
        reset = 0; sdram_reset = 0;
        repeat (20) @(posedge clock);

        // The signature: word [D0009] = AA55h. Byte@9 (odd) must show on
        // the high lane; byte@10 (even) on the low lane.
        check(20'hD0009, 8'h55, 8'h55);   // odd byte: hi lane carries it
        check(20'hD000A, 8'hAA, 8'h90);   // even byte: lo=AA, hi=pad byte
        // The four POST phase entries are jmp stubs at
        // 0x0C/0x0F/0x12/0x15; the dispatch entry sits at 0x18.
        check(20'hD000C, 8'hE9, 8'h85);   // word@0x0C = 85 E9 = jmp near init
        check(20'hD000F, 8'hE9, 8'hE9);   // odd byte: hi lane = the byte itself
        check(20'hD0012, 8'hE9, 8'h7F);
        check(20'hD0015, 8'hEB, 8'hEB);   // odd byte: hi lane = the byte itself
        check(20'hD0018, 8'h56, 8'h57);   // xrom_disk: push si / push di
        check(20'hD002E, 8'hC7, 8'h06);   // mov word [5F8],fdpara
        check(20'hD0032, 8'hBC, 8'h00);   //   fdpara immediate = 00BC
        check(20'hD0050, 8'hCD, 8'h1B);   // int 1Bh re-dispatch
        // The parameter table inside the image: fdpara at 0xBC points
        // all four units at rec144 (0xC4); its N=2 record is the 1.44MB
        // geometry at 0xD4. Init also writes the [5F8] repoint itself at
        // 0xAE so the BIOS's own 0x9x path sees the same table.
        check(20'hD0094, 8'h50, 8'h1E);   // init: push ax / push ds
        check(20'hD00AE, 8'hC7, 8'h06);   // init: mov word [5F8],fdpara
        check(20'hD00B2, 8'hBC, 8'h00);   //   fdpara immediate = 00BC
        check(20'hD00BC, 8'hC4, 8'h00);   // fdpara[0] = rec144
        check(20'hD00D4, 8'h12, 8'h1B);   // N=2: EOT=18, GPL=1B
        check(20'hD00D6, 8'h12, 8'h54);   //       SC=18, GPL=54
        // Tail of the image and the open window around it.
        check(20'hD00E3, 8'h00, 8'h00);   // byte 227 = last image byte
        check(20'hD00E4, 8'hFF, 8'hFF);   // beyond the image -> open slot
        check(20'hD00FF, 8'hFF, 8'hFF);   // end of the 256B window
        check(20'hD0100, 8'hFF, 8'h00);   // next page: the empty window
        check(20'hD1000, 8'hFF, 8'h00);   // the next 4KB scan slot
        check(20'hC0000, 8'hFF, 8'h00);   // below the window
        check(20'hDFFFF, 8'hFF, 8'h00);   // top of the scan region
        // An even byte read (word_access low) still places the odd pair
        // byte on the high lane, matching the SDRAM lane convention.
        cpu_word_access = 1'b1;
        check(20'hD0008, 8'h00, 8'h55);   // word@8: lo=00, hi=55 (offset 9)
        cpu_word_access = 1'b0;

        $display("%s  (errors %0d)", errors ? "FAIL" : "PASS", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
