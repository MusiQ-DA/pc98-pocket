//
// upd71071
// PROGRAMMABLE DMA CONTROLLER
//
// Written by Kitune-san
//

module upd71071 (
    input   logic           clock,
    input   logic           cpu_ce_posedge,
    input   logic           cpu_ce_negedge,
    input   logic           reset,
    input   logic           chip_select_n,
    input   logic           ready,
    input   logic           hold_acknowledge,
    input   logic   [3:0]   dma_request,
    input   logic   [7:0]   data_bus_in,
    output  logic   [7:0]   data_bus_out,
    input   logic           io_read_n_in,
    output  logic           io_read_n_out,
    output  logic           io_read_n_io,
    input   logic           io_write_n_in,
    output  logic           io_write_n_out,
    output  logic           io_write_n_io,
    input   logic           end_of_process_n_in,
    output  logic           end_of_process_n_out,
    input   logic   [3:0]   address_in,
    output  logic   [15:0]  address_out,
    output  logic           output_highst_address,
    output  logic           hold_request,
    output  logic   [3:0]   dma_acknowledge,
    output  logic           address_enable,
    output  logic           address_strobe,
    output  logic           memory_read_n,
    output  logic           memory_write_n,

    // POSTMON's DC word. The metal case: DRQ parked high at the pins,
    // hold_request flat -- somewhere between "the write never arrived" and
    // "the encoder rejected it" the request dies, and none of those internals
    // reach the outside. 32 bits so the design keeps its fit margin:
    //   [31:28] mask_register       [27:24] encoded_dma
    //   [23:20] dma_request_state   [19:16] dma_request_ff
    //   [15:12] last written register index
    //   [11:8]  write count (saturating)
    //   [7]     sticky: register 1010 (single mask, I/O 0x15) written
    //   [6]     controller_disable
    //   [5:3]   transfer FSM state  [2:0]   unused
    output  logic   [31:0]  dbg
);


    //
    // Data Bus Buffer & Read/Write Control Logic (1)
    //
    logic           lock_bus_control;
    logic   [7:0]   internal_data_bus;
    logic           write_command_register;
    logic           write_mode_register;
    logic           write_request_register;
    logic           set_or_reset_mask_register;
    logic           write_mask_register;
    logic   [3:0]   write_base_and_current_address;
    logic   [3:0]   write_base_and_current_word_count;
    logic           clear_byte_pointer;
    logic           set_byte_pointer;
    logic           master_clear;
    logic           clear_mask_register;
    logic           read_temporary_register;
    logic           read_status_register;
    logic   [3:0]   read_current_address;
    logic   [3:0]   read_current_word_count;

    upd71071_Bus_Control_Logic u_Bus_Control_Logic (
        // Bus
        .clock                              (clock),
        .reset                              (reset),

        .chip_select_n                      (chip_select_n),
        .io_read_n_in                       (io_read_n_in),
        .io_write_n_in                      (io_write_n_in),
        .address_in                         (address_in),
        .data_bus_in                        (data_bus_in),

        .lock_bus_control                   (lock_bus_control),

        // Internal Bus
        .internal_data_bus                  (internal_data_bus),
        // -- write
        .write_command_register             (write_command_register),
        .write_mode_register                (write_mode_register),
        .write_request_register             (write_request_register),
        .set_or_reset_mask_register         (set_or_reset_mask_register),
        .write_mask_register                (write_mask_register),
        .write_base_and_current_address     (write_base_and_current_address),
        .write_base_and_current_word_count  (write_base_and_current_word_count),
        // -- software command
        .clear_byte_pointer                 (clear_byte_pointer),
        .set_byte_pointer                   (set_byte_pointer),
        .master_clear                       (master_clear),
        .clear_mask_register                (clear_mask_register),
        // -- read
        .read_temporary_register            (read_temporary_register),
        .read_status_register               (read_status_register),
        .read_current_address               (read_current_address),
        .read_current_word_count            (read_current_word_count),

        .dbg_wr_last_reg                    (dbg_wr_last_reg),
        .dbg_wr_cnt                         (dbg_wr_cnt),
        .dbg_wr_reg_a                       (dbg_wr_reg_a)
    );


    //
    // Priority Encoder And Rotating Priority Logic
    //
    logic   [1:0]   dma_rotate;
    logic   [3:0]   edge_request;
    logic   [3:0]   dma_request_state;
    logic   [3:0]   encoded_dma;
    logic           end_of_process_internal;
    logic   [3:0]   dma_acknowledge_internal;
    logic   [15:0]  dbg_enc;
    logic   [3:0]   dbg_wr_last_reg;
    logic   [3:0]   dbg_wr_cnt;
    logic           dbg_wr_reg_a;

    upd71071_Priority_Encoder u_Priority_Encoder (
        .clock                              (clock),
        .cpu_clock_posedge                  (cpu_ce_posedge),
        .cpu_clock_negedge                  (cpu_ce_negedge),
        .reset                              (reset),

        // Internal Bus
        .internal_data_bus                  (internal_data_bus),
        // -- write
        .write_command_register             (write_command_register),
        .write_request_register             (write_request_register),
        .set_or_reset_mask_register         (set_or_reset_mask_register),
        .write_mask_register                (write_mask_register),
        // -- software command
        .master_clear                       (master_clear),
        .clear_mask_register                (clear_mask_register),

        // Internal signals
        .dma_rotate                         (dma_rotate),
        .edge_request                       (edge_request),
        .dma_request_state                  (dma_request_state),
        .encoded_dma                        (encoded_dma),
        .end_of_process_internal            (end_of_process_internal),
        .dma_acknowledge_internal           (dma_acknowledge_internal),

        // External signals
        .dma_request                        (dma_request),

        .dbg_enc                            (dbg_enc)
    );


    //
    // Address And Count Registers
    //
    logic   [7:0]   read_address_or_count;
    logic   [3:0]   transfer_register_select;
    logic           initialize_current_register;
    logic           address_hold_config;
    logic           decrement_address_config;
    logic           next_word;
    logic           update_high_address;
    logic           underflow;

    upd71071_Address_And_Count_Registers u_Address_And_Count_Registers (
        .clock                              (clock),
        .cpu_clock_posedge                  (cpu_ce_posedge),
        .cpu_clock_negedge                  (cpu_ce_negedge),
        .reset                              (reset),

        // Internal Bus
        .internal_data_bus                  (internal_data_bus),
        .read_address_or_count              (read_address_or_count),
        // -- write
        .write_base_and_current_address     (write_base_and_current_address),
        .write_base_and_current_word_count  (write_base_and_current_word_count),
        // -- software command
        .clear_byte_pointer                 (clear_byte_pointer),
        .set_byte_pointer                   (set_byte_pointer),
        .master_clear                       (master_clear),
        // -- read
        .read_current_address               (read_current_address),
        .read_current_word_count            (read_current_word_count),

        // Internal signals
        .transfer_register_select           (transfer_register_select),
        .initialize_current_register        (initialize_current_register),
        .address_hold_config                (address_hold_config),
        .decrement_address_config           (decrement_address_config),
        .next_word                          (next_word),
        .update_high_address                (update_high_address),
        .underflow                          (underflow),
        .transfer_address                   (address_out)
    );


    //
    // Timing And Control Logic
    //
    logic           output_temporary_data;
    logic   [7:0]   temporary_register;
    logic   [3:0]   terminal_count_state;
    logic   [2:0]   dbg_state;

    upd71071_Timing_And_Control u_Timing_And_Control (
        .clock                              (clock),
        .cpu_clock_posedge                  (cpu_ce_posedge),
        .cpu_clock_negedge                  (cpu_ce_negedge),
        .reset                              (reset),

        // Internal Bus
        .internal_data_bus                  (internal_data_bus),
        // -- write
        .write_command_register             (write_command_register),
        .write_mode_register                (write_mode_register),
        // -- read
        .read_status_register               (read_status_register),
        // -- software command
        .master_clear                       (master_clear),

        // Internal signals
        .dma_rotate                         (dma_rotate),
        .edge_request                       (edge_request),
        .dma_request_state                  (dma_request_state),
        .encoded_dma                        (encoded_dma),
        .dma_acknowledge_internal           (dma_acknowledge_internal),
        .transfer_register_select           (transfer_register_select),
        .initialize_current_register        (initialize_current_register),
        .address_hold_config                (address_hold_config),
        .decrement_address_config           (decrement_address_config),
        .next_word                          (next_word),
        .update_high_address                (update_high_address),
        .underflow                          (underflow),
        .end_of_process_internal            (end_of_process_internal),
        .lock_bus_control                   (lock_bus_control),
        .output_temporary_data              (output_temporary_data),
        .temporary_register                 (temporary_register),
        .terminal_count_state               (terminal_count_state),

        // External signals
        .hold_request                       (hold_request),
        .hold_acknowledge                   (hold_acknowledge),
        .dma_acknowledge                    (dma_acknowledge),
        .address_enable                     (address_enable),
        .address_strobe                     (address_strobe),
        .output_highst_address              (output_highst_address),
        .memory_read_n                      (memory_read_n),
        .memory_write_n                     (memory_write_n),
        .io_read_n_out                      (io_read_n_out),
        .io_read_n_io                       (io_read_n_io),
        .io_write_n_out                     (io_write_n_out),
        .io_write_n_io                      (io_write_n_io),
        .ready                              (ready),
        .end_of_process_n_in                (end_of_process_n_in),
        .end_of_process_n_out               (end_of_process_n_out),

        .dbg_state                          (dbg_state)
    );


    //
    // Data Bus Buffer & Read/Write Control Logic (2)
    //
    always_comb begin
        if (output_highst_address)
            data_bus_out = address_out[15:8];
        else if ((read_temporary_register) || (output_temporary_data))
            data_bus_out = temporary_register;
        else if (read_status_register)
            data_bus_out = {dma_request_state, terminal_count_state};
        else if ((0 != read_current_address) || (0 != read_current_word_count))
            data_bus_out = read_address_or_count;
        else
            data_bus_out = 8'h00;
    end

    // dbg_enc is {request_register, mask_register, dma_request_ff,
    // controller_disable, dreq_sense_active_low, rotating_priority, 1'b0}.
    assign  dbg = {
        dbg_enc[11:8],      // mask_register
        encoded_dma,
        dma_request_state,
        dbg_enc[7:4],       // dma_request_ff
        dbg_wr_last_reg,
        dbg_wr_cnt,
        dbg_wr_reg_a,
        dbg_enc[3],         // controller_disable
        dbg_state,
        3'b000
    };

endmodule

