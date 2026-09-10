//
// MiSTer PCXT RAM
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
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

module RAM (
    input   logic           clock,
    input   logic           reset,
    input   logic           enable_sdram,
    output  logic           initilized_sdram,
    // I/O Ports
    input   logic   [19:0]  address,
    input   logic   [7:0]   internal_data_bus,
    output  logic   [7:0]   data_bus_out,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    input   logic           no_command_state,
    output  logic           memory_access_ready,
    // ROM-load (Pocket): read-only tap on the write/read completion state.
    output  logic           access_complete,
    output  logic           ram_address_select_n,
    // SDRAM
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
     input   logic   [6:0]   map_ems[0:3],
     input   logic           ems_b1,
     input   logic           ems_b2,
     input   logic           ems_b3,
     input   logic           ems_b4,
     // BIOS
     input  logic    [1:0]  bios_protect_flag,
    // Font bank: while set, guest addresses are redirected above the machine's
    // megabyte so the loader can write FONT.ROM somewhere the guest cannot see.
    // The same trick as the ITF shadow, one bit further up.
     input  logic           font_bank_flag,
    // Video-side read port, straight through to the controller's port B.
     input  logic           font_rd_req,
     input  logic   [23:0]  font_rd_addr,
     input  logic    [3:0]  font_rd_len,
     output logic           font_rd_ack,
     output logic           font_rd_valid,
     output logic   [15:0]  font_rd_data,
     output logic           font_rd_done,
    // Second video-side reader: the character generator window.
     input  logic           cg_rd_req,
     input  logic   [23:0]  cg_rd_addr,
     input  logic    [3:0]  cg_rd_len,
     output logic           cg_rd_ack,
     output logic           cg_rd_valid,
     output logic   [15:0]  cg_rd_data,
     output logic           cg_rd_done,
     input  logic           tandy_bios_flag,
    // Optional flags
    input  logic           enable_a000h,
    // Wait mode
    input   logic           wait_count_clk_en,
    input   logic   [1:0]   ram_read_wait_cycle,
    input   logic   [1:0]   ram_write_wait_cycle
);

    typedef enum {IDLE, RAM_WRITE_1, RAM_WRITE_2, RAM_READ_1, RAM_READ_2, COMPLETE_RAM_RW, WAIT} state_t;

    state_t         state;
    state_t         next_state;
    logic   [22:0]  latch_address;
    logic   [7:0]   latch_data;
    logic           write_command;
    logic           read_command;
    logic           prev_no_command_state;
    logic           enable_refresh;
    logic           write_protect;
    logic           tandy_bios_select;

    logic   [1:0]   read_wait_count;
    logic   [1:0]   write_wait_count;
    logic           access_ready;

    //
    // RAM Address Select (0x00000-0xAFFFF and 0xC0000-0xFFFFF)
    //
`ifdef MACHINE_PC98
    // The machine this BIOS comes from has 640 KB of RAM and empty
    // C0000-E7FFF slots, and its POST decides how much memory to test by
    // probing them. With SDRAM answering there it saw an "expansion" that
    // does not exist and swept on into D0000, where it stopped (LIVE DA9EA,
    // N frozen). So the SDRAM answers 00000-BFFFF only: the main RAM, plus
    // the A8000-BFFFF window the GVRAM probe writes through. A0000-A7FFF is
    // still excluded -- text VRAM and the CG window answer from elsewhere.
    //
    // E8000-FFFFF stays SELECTED on purpose: the BIOS image lives in the
    // SDRAM (the loader writes it there, the guest fetches it from there),
    // and taking it out of the select -- which one revision did -- starved
    // the loader into DROP 38190 and left BAD 0F2 on the compare.
    assign ram_address_select_n = ~(enable_sdram
                             && ((address[19:16] < 4'hC)             // RAM + GVRAM window
                              || (address[19:15] >= 5'b11101))        // E8000-FFFFF: ROM image
                             && ~(address[19:15] == 5'b10100));       // A0000-A7FFF
`else
    assign ram_address_select_n = ~(enable_sdram && ~(address[19:16] == 4'b1011) &&  // B0000h reserved for VRAM
	                               ~(~enable_a000h && address[19:16] == 4'b1010));    // A0000h is optional
`endif
	 

`ifdef MACHINE_PC98
    // The ITF bank. F8000-FFFFF, 32 KB, mapped to the shadow copy at 1F8000
    // through latch_address's spare bit -- the same bit and the same mechanism
    // the Tandy BIOS shadow uses, reused rather than duplicated because the
    // PC/AT machine layer this file belongs to is going away anyway.
    //
    // Set: the guest sees the ITF (power-on, and after port 0x043D gets 0x10).
    // Clear: it sees the system BIOS's own F8000-FFFFF (after 0x043D gets 0x12).
    // core_top owns the flag; during the ITF load it is driven by the loader so
    // the image is written into the shadow instead of over the BIOS.
    assign tandy_bios_select    = tandy_bios_flag & (address[19:15] == 5'b11111);
`else
    assign tandy_bios_select    = `ROM_IS_TANDY ? (tandy_bios_flag & (address[19:16] == 4'b1111)) : 1'b0;
`endif


    //
    // Write protect
    //
`ifdef MACHINE_PC98
    // PC-98's ROM is E8000-FFFFF (96 KB), not the PC/AT's F0000-FFFFF plus the
    // EC00 option-ROM window. bios_protect_flag[1] covers the whole of it.
    assign write_protect = bios_protect_flag[1] & ((address[19:16] == 4'b1111)
                                                |  (address[19:15] == 5'b11101));
`else
    assign write_protect = bios_protect_flag[1] & (address[19:16] == 4'b1111)
                         | bios_protect_flag[0] & (address[19:14] == 6'b111011);
`endif


    //
    // I/O Ports
    //
    // Address
    always_comb begin
        if (ems_b1)
            latch_address   = {1'b0, 1'b1, map_ems[0], address[13:0]};
        else if (ems_b2)
            latch_address   = {1'b0, 1'b1, map_ems[1], address[13:0]};
        else if (ems_b3)
            latch_address   = {1'b0, 1'b1, map_ems[2], address[13:0]};
        else if (ems_b4)
            latch_address   = {1'b0, 1'b1, map_ems[3], address[13:0]};
        else if (font_bank_flag)
            // 0x400000 upward: past EMS, which owns bit 21.
            latch_address   = {1'b1, 2'b00, address};
        else
            latch_address   = {2'b00, tandy_bios_select, address};
    end

    // Data
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            latch_data      <= 0;
        else
            latch_data      <= internal_data_bus;
    end

    // Write Command
    assign write_command = ~ram_address_select_n & ~memory_write_n & ~write_protect;

    // Read Command
    assign read_command  = ~ram_address_select_n & ~memory_read_n;

    // Generate refresh timing
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_no_command_state   <= 1'b0;
        end
        else begin
            prev_no_command_state   <= no_command_state;
        end
    end

    assign  enable_refresh  = no_command_state & ~prev_no_command_state;


    //
    // SDRAM Controller
    //
    logic   [24:0]  access_address;
    logic   [9:0]   access_num;
    logic   [15:0]  access_data_in;
    logic   [15:0]  access_data_out;
    logic           write_request;
    logic           read_request;
    logic           write_flag;
    logic           read_flag;
    logic           idle;
    logic           refresh_mode;

`ifdef SDRAM_USE_MP
    // sdram_kf_shim presents KFSDRAM's port list on top of sdram_mp, so the
    // unmodified PCXT can be booted through the new controller as an A/B check
    // before the PC-98 machine layer depends on it. See docs/P0_SDRAM_DESIGN.md.
    sdram_kf_shim u_KFSDRAM (
        .sdram_clock        (clock),
        .sdram_reset        (reset),
        .address            (access_address),
        .access_num         (access_num),
        .data_in            (access_data_in),
        .data_out           (access_data_out),
        .write_request      (write_request),
        .read_request       (read_request),
        .enable_refresh     (enable_refresh),
        .write_flag         (write_flag),
        .read_flag          (read_flag),
        .idle               (idle),
        .refresh_mode       (refresh_mode),
        .sdram_address      (sdram_address),
        .sdram_cke          (sdram_cke),
        .sdram_cs           (sdram_cs),
        .sdram_ras          (sdram_ras),
        .sdram_cas          (sdram_cas),
        .sdram_we           (sdram_we),
        .sdram_ba           (sdram_ba),
        .sdram_dq_in        (sdram_dq_in),
        .sdram_dq_out       (sdram_dq_out),
        .sdram_dq_io        (sdram_dq_io),
        .b_req              (font_rd_req),
        .b_addr             (font_rd_addr),
        .b_len              (font_rd_len),
        .b_ack              (font_rd_ack),
        .b_rvalid           (font_rd_valid),
        .b_rdata            (font_rd_data),
        .b_done             (font_rd_done),
        .c_req              (cg_rd_req),
        .c_addr             (cg_rd_addr),
        .c_len              (cg_rd_len),
        .c_ack              (cg_rd_ack),
        .c_rvalid           (cg_rd_valid),
        .c_rdata            (cg_rd_data),
        .c_done             (cg_rd_done)
    );
`else
    KFSDRAM u_KFSDRAM (
        .sdram_clock        (clock),
        .sdram_reset        (reset),
        .address            (access_address),
        .access_num         (access_num),
        .data_in            (access_data_in),
        .data_out           (access_data_out),
        .write_request      (write_request),
        .read_request       (read_request),
        .enable_refresh     (enable_refresh),
        .write_flag         (write_flag),
        .read_flag          (read_flag),
        .idle               (idle),
        .refresh_mode       (refresh_mode),
        .sdram_address      (sdram_address),
        .sdram_cke          (sdram_cke),
        .sdram_cs           (sdram_cs),
        .sdram_ras          (sdram_ras),
        .sdram_cas          (sdram_cas),
        .sdram_we           (sdram_we),
        .sdram_ba           (sdram_ba),
        .sdram_dq_in        (sdram_dq_in),
        .sdram_dq_out       (sdram_dq_out),
        .sdram_dq_io        (sdram_dq_io)
    );
    // Stock KFSDRAM has no second master.
    assign font_rd_ack   = 1'b0;
    assign font_rd_valid = 1'b0;
    assign font_rd_data  = 16'h0000;
    assign font_rd_done  = 1'b0;
    assign cg_rd_ack     = 1'b0;
    assign cg_rd_valid   = 1'b0;
    assign cg_rd_data    = 16'h0000;
    assign cg_rd_done    = 1'b0;
`endif


    //
    // State machine
    //
    always_comb begin
        next_state = state;
        casez (state)
            IDLE: begin
                if (write_command)
                    next_state = RAM_WRITE_1;
                else if (read_command)
                    next_state = RAM_READ_1;
            end
            RAM_WRITE_1: begin
                if (~write_command)
                    next_state = WAIT;
                if (write_flag)
                    next_state = RAM_WRITE_2;
            end
            RAM_WRITE_2: begin
                if (~write_command)
                    next_state = WAIT;
                if (~write_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            RAM_READ_1: begin
                if (~read_command)
                    next_state = WAIT;
                if (read_flag)
                    next_state = RAM_READ_2;
            end
            RAM_READ_2: begin
                if (~read_command)
                    next_state = WAIT;
                if (~read_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            COMPLETE_RAM_RW: begin
                if ((~write_command) && (~read_command))
                    next_state = IDLE;
            end
            WAIT: begin
                if (idle)
                    next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            state = IDLE;
        else
            state = next_state;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            initilized_sdram <= 1'b0;
        else if (idle)
            initilized_sdram <= 1'b1;
        else
            initilized_sdram <= initilized_sdram;
    end


    //
    // Output SDRAM Control Signals
    //
    always_comb begin
        casez (state)
            IDLE: begin
                access_address  = {6'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = write_command ? 1'b1 : 1'b0;
                read_request    = read_command  ? 1'b1 : 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_1: begin
                access_address  = {6'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = 1'b1;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_2: begin
                access_address  = {6'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_1: begin
                access_address  = {6'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b1;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_2: begin
                access_address  = {6'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            COMPLETE_RAM_RW: begin
                access_address  = 25'h0000000;
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            WAIT: begin
                access_address  = 25'h0000000;
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b1;
                sdram_udqm      = 1'b1;
            end
        endcase
    end


    //
    // Databus Out
    //
    logic   [7:0]   data_bus_out_reg;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            data_bus_out_reg    <= 0;
        else if (read_flag)
            data_bus_out_reg    <= access_data_out[7:0];
        else
            data_bus_out_reg    <= data_bus_out_reg;
    end

    assign  data_bus_out = ~read_command ? 0 : ~read_flag ? data_bus_out_reg : access_data_out[7:0];


    //
    // Ready/Wait Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            access_ready <= 1'b0;
        else if (state == COMPLETE_RAM_RW)
            access_ready <= 1'b1;
        else if (state == IDLE)
            access_ready <= idle;
        else if ((write_command) && (refresh_mode))
            access_ready <= 1'b0;
        else if ((read_command)  && (refresh_mode))
            access_ready <= 1'b0;
        else
            access_ready <= access_ready;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            read_wait_count     <= 0;
        else if (~read_command)
            read_wait_count     <= ram_read_wait_cycle;
        else if ((wait_count_clk_en) && (read_wait_count != 0))
            read_wait_count     <= read_wait_count - 1;
        else
            read_wait_count     <= read_wait_count;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            write_wait_count    <= 0;
        else if (~write_command)
            write_wait_count    <= ram_write_wait_cycle;
        else if ((wait_count_clk_en) && (write_wait_count != 0))
            write_wait_count    <= write_wait_count - 1;
        else
            write_wait_count    <= write_wait_count;
    end

    assign  memory_access_ready = ((~ram_address_select_n) && ((~memory_read_n) || (~memory_write_n)))
                                        ? (access_ready & ((read_wait_count==0) || (~read_command)) & ((write_wait_count==0) || (~write_command))) : 1'b1;

    // ROM-load (Pocket): a clean per-access "done" pulse for core_top's BIOS
    // loader. COMPLETE_RAM_RW is reached only after the SDRAM write truly
    // finishes (refresh-safe) and is independent of the CPU-bus wait throttle.
    assign  access_complete = (state == COMPLETE_RAM_RW);

endmodule
