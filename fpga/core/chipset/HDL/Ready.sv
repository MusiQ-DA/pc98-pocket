//
// chipset Ready_Signal
// Written by kitune-san
//
module READY (
    input   logic           clock,
    input   logic           cpu_ce_posedge,
    input   logic           cpu_ce_negedge,
    input   logic           reset,
    // CPU
    output  logic           processor_ready,
    // Bus Arbiter
    output  logic           dma_ready,
    input   logic           dma_wait_n,
    // I/O
    input   logic           io_channel_ready,
    input   logic           io_read_n,
    input   logic           io_write_n,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    input   logic           dma0_acknowledge_n,
    input   logic           address_enable_n
);


    //
    // Ready/Wait Signal
    //
    logic   prev_bus_state;
    logic   ready_n_or_wait;
    logic   ready_n_or_wait_Qn;
    logic   prev_ready_n_or_wait;

    // The DMA write phase must count as a bus cycle too. Without it a ready
    // sequence still settling from the transfer's I/O phase fires inside SW
    // and the uPD71071 releases memory_write_n early -- a fixed-width pulse
    // RAM may still be too busy to accept, so the byte silently drops.
    // Re-arming the toggle at the write strobe's rise flushes any stale
    // pulse; the write then completes only on its own io_channel_ready.
    wire    memwr_cmd  = dma0_acknowledge_n & ~memory_write_n & address_enable_n;
    logic   prev_memwr_cmd;
    wire    memwr_start = memwr_cmd & ~prev_memwr_cmd;

    wire    bus_state = ~io_read_n | ~io_write_n
                      | (dma0_acknowledge_n & ~memory_read_n & address_enable_n)
                      | memwr_cmd;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_bus_state <= 1'b1;
            prev_memwr_cmd <= 1'b0;
        end else begin
            prev_bus_state <= bus_state;
            prev_memwr_cmd <= memwr_cmd;
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            ready_n_or_wait     <= 1'b1;
            ready_n_or_wait_Qn  <= 1'b0;
        end
        else if (memwr_start) begin
            // First in the chain: a write strobe starting flushes whatever
            // ready sequence was still settling, so a stale pulse can never
            // fire inside SW. The write's own completion re-fires it.
            ready_n_or_wait     <= 1'b1;
            ready_n_or_wait_Qn  <= 1'b0;
        end
        else if (~io_channel_ready & prev_ready_n_or_wait) begin
            ready_n_or_wait     <= 1'b1;
            ready_n_or_wait_Qn  <= 1'b1;
        end
        else if (~io_channel_ready & ~prev_ready_n_or_wait) begin
            ready_n_or_wait     <= 1'b1;
            ready_n_or_wait_Qn  <= 1'b0;
        end
        else if (io_channel_ready & prev_ready_n_or_wait) begin
            ready_n_or_wait     <= 1'b0;
            ready_n_or_wait_Qn  <= 1'b1;
        end
        else if (~prev_bus_state & bus_state) begin
            ready_n_or_wait     <= 1'b1;
            ready_n_or_wait_Qn  <= 1'b0;
        end
        else begin
            ready_n_or_wait     <= ready_n_or_wait;
            ready_n_or_wait_Qn  <= ready_n_or_wait_Qn;
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_ready_n_or_wait    <= 1'b0;
        else if (cpu_ce_posedge)
            prev_ready_n_or_wait    <= ready_n_or_wait;
        else
            prev_ready_n_or_wait    <= prev_ready_n_or_wait;
    end


    //
    // Ready to DMA
    //
    assign  dma_ready = ~prev_ready_n_or_wait & ready_n_or_wait_Qn;


    //
    // Ready Signal (Instead of 8284)
    //
    logic   processor_ready_ff_1;
    logic   processor_ready_ff_2;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            processor_ready_ff_1    <= 1'b0;
        else if (cpu_ce_posedge)
            processor_ready_ff_1    <= dma_wait_n & ~ready_n_or_wait;
        else
            processor_ready_ff_1    <= processor_ready_ff_1;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            processor_ready_ff_2    <= 1'b0;
        else if (cpu_ce_negedge)
            processor_ready_ff_2    <= processor_ready_ff_1 & dma_wait_n & ~ready_n_or_wait;
        else
            processor_ready_ff_2    <= processor_ready_ff_2;
    end

    assign  processor_ready = processor_ready_ff_2;

endmodule

