//
// upd71071_Bus_Control_Logic
// Data Bus Buffer & Read/Write Control Logic
//
// Written by Kitune-san
//

module upd71071_Bus_Control_Logic (
    // Bus
    input   logic           clock,
    input   logic           reset,

    input   logic           chip_select_n,
    input   logic           io_read_n_in,
    input   logic           io_write_n_in,
    input   logic   [3:0]   address_in,
    input   logic   [7:0]   data_bus_in,

    input   logic           lock_bus_control,

    // Internal Bus
    output  logic   [7:0]   internal_data_bus,
    // -- write
    output  logic           write_command_register,
    output  logic           write_mode_register,
    output  logic           write_request_register,
    output  logic           set_or_reset_mask_register,
    output  logic           write_mask_register,
    output  logic   [3:0]   write_base_and_current_address,
    output  logic   [3:0]   write_base_and_current_word_count,
    // -- software command
    output  logic           clear_byte_pointer,
    output  logic           set_byte_pointer,
    output  logic           master_clear,
    output  logic           clear_mask_register,
    // -- read
    output  logic           read_temporary_register,
    output  logic           read_status_register,
    output  logic   [3:0]   read_current_address,
    output  logic   [3:0]   read_current_word_count
);

    //
    // Internal Signals
    //
    logic           prev_write_enable_n;
    logic           write_flag;
    logic   [3:0]   write_address;
    logic           read_flag;

    //
    // Write Control
    //
    // THE BUS THIS SITS ON (the third deadlock, PC98_JTAG): the write
    // strobe's tail is not the guest's alone. cpu_bus_bridge arms the
    // next access the clock the current pair releases, and the i8288's
    // command strobes retire ~1 CE later -- so the address (and the
    // data) on the pins can switch to the NEXT cycle's while IOW is
    // still low, and chip select falls out of the window with it. The
    // FDC port path documents the same pathology (Peripherals.sv,
    // io_wr_addr_q / write_to_fdd) and survives it by sampling while
    // the strobe is low and consuming the last sample at the rise.
    //
    // This module used to re-arm prev_write_enable_n the moment chip
    // select rose -- so a CS blip in the tail cancelled write_flag and
    // the register write was silently DROPPED. On the metal that ate a
    // 0x15 unmask once every few thousand arms (phase-dependent), the
    // next FDC command raised its DRQ against a still-masked channel,
    // and the uPD71071 parked in SI with the request pending forever --
    // SuperDepth's 6-36 s in-game freeze. Two changes, same shape as
    // the FDC path:
    //   * address+data are captured every clock the cycle is OURS -- chip
    //     select low, which on this decode MEANS the address is inside
    //     the DMAC's window (the select is the address decode) -- and
    //     HOLD once CS leaves, so the decode at the IOW rise uses the
    //     last owned address even if the pins are preempted inside the
    //     tail. The strobe itself is not part of the enable: IOW-high
    //     clks inside the window only ever load dead data, which no
    //     write pulse consumes.
    //   * a pulse that has started can only be retired by the strobe's
    //     rise (or a DMA transfer's bus lock), never by CS dropping.
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            write_address     <= 4'b0000;
            internal_data_bus <= 8'b00000000;
        end
        else if (~chip_select_n) begin
            write_address     <= address_in;
            internal_data_bus <= data_bus_in;
        end
        else begin
            write_address     <= write_address;
            internal_data_bus <= internal_data_bus;
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_write_enable_n <= 1'b1;
        else if (chip_select_n & prev_write_enable_n)
            prev_write_enable_n <= 1'b1;
        else
            prev_write_enable_n <= io_write_n_in | lock_bus_control;
    end
    assign write_flag = ~prev_write_enable_n & io_write_n_in;

    // Generate write request flags
    assign  write_command_register                  = write_flag & (write_address == 4'b1000);
    assign  write_mode_register                     = write_flag & (write_address == 4'b1011);
    assign  write_request_register                  = write_flag & (write_address == 4'b1001);
    assign  set_or_reset_mask_register              = write_flag & (write_address == 4'b1010);
    assign  write_mask_register                     = write_flag & (write_address == 4'b1111);
    assign  write_base_and_current_address[0]       = write_flag & (write_address == 4'b0000);
    assign  write_base_and_current_address[1]       = write_flag & (write_address == 4'b0010);
    assign  write_base_and_current_address[2]       = write_flag & (write_address == 4'b0100);
    assign  write_base_and_current_address[3]       = write_flag & (write_address == 4'b0110);
    assign  write_base_and_current_word_count[0]    = write_flag & (write_address == 4'b0001);
    assign  write_base_and_current_word_count[1]    = write_flag & (write_address == 4'b0011);
    assign  write_base_and_current_word_count[2]    = write_flag & (write_address == 4'b0101);
    assign  write_base_and_current_word_count[3]    = write_flag & (write_address == 4'b0111);

    // Generate software command
    assign  clear_byte_pointer                      = write_flag & (write_address == 4'b1100);
    assign  set_byte_pointer                        = read_flag  & (address_in == 4'b1100);
    assign  master_clear                            = write_flag & (write_address == 4'b1101);
    assign  clear_mask_register                     = write_flag & (write_address == 4'b1110);

    //
    // Read Control
    //
    assign  read_flag = ~io_read_n_in & ~chip_select_n & ~lock_bus_control;

    // Generate read request flags
    assign  read_temporary_register                 = read_flag & (address_in == 4'b1101);
    assign  read_status_register                    = read_flag & (address_in == 4'b1000);
    assign  read_current_address[0]                 = read_flag & (address_in == 4'b0000);
    assign  read_current_address[1]                 = read_flag & (address_in == 4'b0010);
    assign  read_current_address[2]                 = read_flag & (address_in == 4'b0100);
    assign  read_current_address[3]                 = read_flag & (address_in == 4'b0110);
    assign  read_current_word_count[0]              = read_flag & (address_in == 4'b0001);
    assign  read_current_word_count[1]              = read_flag & (address_in == 4'b0011);
    assign  read_current_word_count[2]              = read_flag & (address_in == 4'b0101);
    assign  read_current_word_count[3]              = read_flag & (address_in == 4'b0111);

endmodule

