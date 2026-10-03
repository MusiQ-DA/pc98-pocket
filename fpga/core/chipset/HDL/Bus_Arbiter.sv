//
// chipset Bus_Arbiter
// Written by kitune-san
//
module BUS_ARBITER (
    input   logic           clock,
    input   logic           cpu_ce_posedge,
    input   logic           cpu_ce_negedge,
    input   logic           reset,
    // CPU
    input   logic   [19:0]  cpu_address,
    input   logic   [7:0]   cpu_data_bus,
    input   logic   [2:0]   processor_status,
    input   logic           processor_lock_n,
    output  logic           processor_transmit_or_receive_n,
    // Ready Logic
    input   logic           dma_ready,
    output  logic           dma_wait_n,
    // Peripherals
    output  logic           interrupt_acknowledge_n,
    input   logic           dma_chip_select_n,
    input   logic           dma_page_chip_select_n,
    // I/O
    output  logic   [19:0]  address,
    input   logic   [19:0]  address_ext,
    output  logic           address_direction,
    input   logic   [7:0]   data_bus_ext,
    output  logic   [7:0]   internal_data_bus,
    output  logic           data_bus_direction,
    output  logic           address_latch_enable,
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
    output  logic           no_command_state,
    input   logic           ext_access_request,
    input   logic   [3:0]   dma_request,
    output  logic   [3:0]   dma_acknowledge_n,
    output  logic           address_enable_n,
    output  logic           terminal_count_n,
    // JTAG probe (PC98_JTAG): why the CPU is off the bus --
    // {hold granted, bus released, dmac wants hold, external master wants
    //  hold, DRQ3..DRQ0 seen as requests (pin low)}.
    output  logic   [7:0]   dbg,
    // JTAG probe (PC98_JTAG): the first four memory writes of the latest
    // channel-2 burst. A fresh burst begins when DACK2 falls; each falling
    // edge of the arbiter's memory-write strobe records {address, data} --
    // exactly what the RAM port is offered -- so a byte-0 that arrived
    // stale, at the wrong address, or not at all stays visible afterwards.
    // [27:0] = write0 {addr[19:0], data[7:0]}, [31:28] = burst counter,
    // then write1..3 packed in 28-bit fields above it.
    output  logic   [127:0] dbg_dma
);

    //
    // Hold Acknowledge Signal
    //
    logic   hold_request_ff_1;
    logic   hold_request_ff_2;
    logic   hold_acknowledge;
    logic   dma_hold_request;

    wire    hold_request = dma_hold_request | ext_access_request;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            hold_request_ff_1 <= 1'b0;
        else if (cpu_ce_posedge)
            if (processor_status[0] & processor_status[1] & processor_lock_n & hold_request)
                hold_request_ff_1 <= 1'b1;
            else
                hold_request_ff_1 <= 1'b0;
        else
            hold_request_ff_1 <= hold_request_ff_1;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            hold_request_ff_2 <= 1'b0;
        else if (cpu_ce_negedge)
            if (~hold_request)
                hold_request_ff_2 <= 1'b0;
            else if (hold_request_ff_2)
                hold_request_ff_2 <= 1'b1;
            else
                hold_request_ff_2 <= hold_request_ff_1;
        else
            hold_request_ff_2 <= hold_request_ff_2;
    end

    assign  hold_acknowledge = (hold_request) ? hold_request_ff_2 : 1'b0;


    //
    // Address/Command Enable Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            address_enable_n <= 1'b1;
        else if (cpu_ce_posedge)
            address_enable_n <= hold_acknowledge;
        else
            address_enable_n <= address_enable_n;
    end


    //
    // DMA Wait Signal
    //
    logic   dma_wait;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            dma_wait <= 1'b0;
        else if (cpu_ce_posedge)
            dma_wait <= address_enable_n;
        else
            dma_wait <= dma_wait;
    end

    assign dma_wait_n = ~dma_wait;


    //
    // DMA Enable Signal
    //
    wire    dma_enable_n = ~(dma_wait & address_enable_n);


    //
    // 8288 Bus Controller
    //
    logic           bc_io_write_n;
    logic           bc_io_read_n;
    logic           bc_enable_io;
    logic           bc_memory_write_n;
    logic           bc_memory_read_n;
    logic           bc_memory_enable;
    logic           direction_transmit_or_receive_n;
    logic           data_enable;

    i8288 u_i8288 (
        .clock                              (clock),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .address_enable_n                   (address_enable_n),
        .command_enable                     (~address_enable_n),
        .io_bus_mode                        (1'b0),
        .processor_status                   (processor_status),
        .enable_io_command                  (bc_enable_io),
        .advanced_io_write_command_n        (bc_io_write_n),
        //.io_write_command_n                 (),
        .io_read_command_n                  (bc_io_read_n),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .enable_memory_command              (bc_memory_enable),
        .advanced_memory_write_command_n    (bc_memory_write_n),
        //.memory_write_command_n             (),
        .memory_read_command_n              (bc_memory_read_n),
        .direction_transmit_or_receive_n    (direction_transmit_or_receive_n),
        .data_enable                        (data_enable),
        //.master_cascade_enable              (),
        //.peripheral_data_enable_n           (),
        .address_latch_enable               (address_latch_enable)
    );

    assign  processor_transmit_or_receive_n = direction_transmit_or_receive_n;


    //
    // 8237 (DMA Controller)
    //
    logic           dma_io_write_n;
    logic   [7:0]   dma_data_out;
    logic           dma_io_read_n;
    logic           terminal_count;
    logic   [15:0]  dma_address_out;
    logic           dma_memory_read_n;
    logic           dma_memory_write_n;

    upd71071 u_upd71071 (
        .clock                              (clock),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .chip_select_n                      (dma_chip_select_n),
        .ready                              (dma_ready),
        .hold_acknowledge                   (hold_acknowledge & ~ext_access_request),
        .dma_request                        (dma_request),
        .data_bus_in                        (internal_data_bus),
        .data_bus_out                       (dma_data_out),
        .io_read_n_in                       (io_read_n),
        .io_read_n_out                      (dma_io_read_n),
        //.io_read_n_io                       (),
        .io_write_n_in                      (io_write_n),
        .io_write_n_out                     (dma_io_write_n),
        //.io_write_n_io                      (),
        .end_of_process_n_in                (1'b1),
        .end_of_process_n_out               (terminal_count),
        // PC-98 puts the DMA controller on the ODD addresses of 0x01-0x1F, so
        // A0 is part of the chip select and the register comes from the bits
        // above it. Same silicon, shifted decode.
        .address_in                         (address[4:1]),
        .address_out                        (dma_address_out),
        //.output_highst_address              (),
        .hold_request                       (dma_hold_request),
        .dma_acknowledge                    (dma_acknowledge_n),
        //.address_enable                     (),
        //.address_strobe                     (),
        .memory_read_n                      (dma_memory_read_n),
        .memory_write_n                     (dma_memory_write_n)
    );

    assign  terminal_count_n = ~terminal_count;

    assign  dbg = {hold_acknowledge, address_enable_n, dma_hold_request,
                   ext_access_request,
                   ~dma_request[3], ~dma_request[2], ~dma_request[1],
                   ~dma_request[0]};


    //
    // 74xx670 (DMA Page Register)
    //
    logic   [1:0]   bit_select[4] = '{ 2'b00, 2'b01, 2'b10, 2'b11 };
    logic   [3:0]   dma_page_register[4];

    genvar dma_page_i;
    generate
    for (dma_page_i = 0; dma_page_i < 4; dma_page_i = dma_page_i + 1) begin : DMA_PAGE_REGISTERS
        always_ff @(posedge clock, posedge reset) begin
            if (reset)
                dma_page_register[dma_page_i] <= 0;
            else if ((~dma_page_chip_select_n) && (~io_write_n) && (bit_select[dma_page_i] == address[2:1]))
                dma_page_register[dma_page_i] <= internal_data_bus[3:0];
            else
                dma_page_register[dma_page_i] <= dma_page_register[dma_page_i];
        end
    end
    endgenerate


    //
    // R/W Command Signals
    //
    wire    ab_io_write_n               = ~((~bc_io_write_n & bc_enable_io) | ~dma_io_write_n);
    wire    ab_io_read_n                = ~((~bc_io_read_n  & bc_enable_io) | ~dma_io_read_n);
    wire    ab_memory_write_n           = ~((~bc_memory_write_n & bc_memory_enable) | ~dma_memory_write_n);
    wire    ab_memory_read_n            = ~((~bc_memory_read_n  & bc_memory_enable) | ~dma_memory_read_n);
    assign  io_write_n_direction        = ab_io_write_n;
    assign  io_read_n_direction         = ab_io_read_n;
    assign  memory_write_n_direction    = ab_memory_write_n;
    assign  memory_read_n_direction     = ab_memory_read_n;
    assign  io_write_n                  = io_write_n_direction     ? io_write_n_ext     : ab_io_write_n;
    assign  io_read_n                   = io_read_n_direction      ? io_read_n_ext      : ab_io_read_n;
    assign  memory_write_n              = memory_write_n_direction ? memory_write_n_ext : ab_memory_write_n;
    assign  memory_read_n               = memory_read_n_direction  ? memory_read_n_ext  : ab_memory_read_n;
    assign no_command_state             = io_write_n & io_read_n & memory_write_n & memory_read_n;


    //
    // DMA sequence-break witness (JTAG probe)
    //
    // The 71071 grants per byte in this design, so "burst boundary" does
    // not isolate anything -- every write is its own grant. What marks a
    // new FDC fill is an address break inside the ack window: fills are
    // contiguous ascending, so the first write of each buffer (and any
    // stray write that escapes the stream) is where address != prev+1.
    // The ring holds the last three such writes as
    // {cpu_owned, dma_owned, drq_pin, 1'b0, addr[19:0], data[7:0]} -- a
    // head write landing on the previous buffer's base or carrying stale
    // data stays visible afterwards.
    //
    logic           prev_ab_mw;
    logic           prev_fdc_ack;
    logic           have_prev;
    logic   [19:0]  prev_dma_addr;
    logic   [7:0]   break_cnt;
    logic   [7:0]   grant_cnt;
    logic   [15:0]  ack_wr_cnt;
    logic   [31:0]  head_log [0:2];

    wire    fdc_ack  = ~dma_acknowledge_n[2] | ~dma_acknowledge_n[3];
    wire    dma_own  = ~dma_enable_n && ~(&dma_acknowledge_n);
    wire    drq_pin  = ~dma_request[2] | ~dma_request[3];

    always_ff @(posedge clock) begin
        if (reset) begin
            prev_ab_mw    <= 1'b1;
            prev_fdc_ack  <= 1'b0;
            have_prev     <= 1'b0;
            prev_dma_addr <= 20'd0;
            break_cnt     <= 8'd0;
            grant_cnt     <= 8'd0;
            ack_wr_cnt    <= 16'd0;
        end
        else begin
            prev_ab_mw   <= ab_memory_write_n;
            prev_fdc_ack <= fdc_ack;

            if (~prev_fdc_ack & fdc_ack && grant_cnt != 8'hff)
                grant_cnt <= grant_cnt + 8'd1;

            if (prev_ab_mw & ~ab_memory_write_n) begin
                if (fdc_ack && ack_wr_cnt != 16'hffff)
                    ack_wr_cnt <= ack_wr_cnt + 16'd1;
                if (fdc_ack) begin
                    // Log every address break in the DMA stream, and every
                    // write the CPU manages to slip into the ack window --
                    // both are where a buffer's first byte can go missing
                    // or land somewhere it should not.
                    if (!dma_own || !have_prev ||
                        address != prev_dma_addr + 20'd1) begin
                        head_log[2] <= head_log[1];
                        head_log[1] <= head_log[0];
                        head_log[0] <= {~address_enable_n && ~dma_own, dma_own,
                                        drq_pin, 1'b0, address,
                                        internal_data_bus};
                        if (break_cnt != 8'hff)
                            break_cnt <= break_cnt + 8'd1;
                    end
                    if (dma_own) begin
                        prev_dma_addr <= address;
                        have_prev <= 1'b1;
                    end
                end
            end
        end
    end

    assign dbg_dma = {break_cnt, grant_cnt, ack_wr_cnt,
                      head_log[2], head_log[1], head_log[0]};


    //
    // Address
    //
    always_comb begin
        if (~dma_enable_n && ~(&dma_acknowledge_n))
            if (~dma_acknowledge_n[2]) begin
                address           = {dma_page_register[1], dma_address_out};
                address_direction = 1'b0;
            end
            else if (~dma_acknowledge_n[3]) begin
                address           = {dma_page_register[2], dma_address_out};
                address_direction = 1'b0;
            end
            else begin
                address           = {dma_page_register[3], dma_address_out};
                address_direction = 1'b0;
            end
        else if (~address_enable_n) begin
            address           = cpu_address;
            address_direction = 1'b0;
        end
        else begin
            address           = address_ext;
            address_direction = 1'b1;
        end
    end


    //
    // Data Bus
    //
    always_comb begin
        if (~interrupt_acknowledge_n) begin
            internal_data_bus  = data_bus_ext;
            data_bus_direction = 1'b0;
        end
        else if ((data_enable) && (direction_transmit_or_receive_n)) begin
            internal_data_bus  = cpu_data_bus;
            data_bus_direction = 1'b0;
        end
        else if ((~dma_chip_select_n) && (~io_read_n)) begin
            internal_data_bus  = dma_data_out;
            data_bus_direction = 1'b0;
        end
        else begin
            internal_data_bus  = data_bus_ext;
            data_bus_direction = 1'b1;
        end
    end


endmodule

