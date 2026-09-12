//
// KF8253
// PROGRAMMABLE INTERVAL TIMER
//
// Written by Kitune-san
//

module KF8253 (
    // Bus
    input   logic           clock,
    input   logic           reset,
    input   logic           chip_select_n,
    input   logic           read_enable_n,
    input   logic           write_enable_n,
    input   logic   [1:0]   address,
    input   logic   [7:0]   data_bus_in,

    output  logic   [7:0]   data_bus_out,

    // I/O
    input   logic           counter_0_clock,
    input   logic           counter_0_gate,
    output  logic           counter_0_out,

    input   logic           counter_1_clock,
    input   logic           counter_1_gate,
    output  logic           counter_1_out,

    input   logic           counter_2_clock,
    input   logic           counter_2_gate,
    output  logic           counter_2_out
);


    //
    // Data Bus Buffer & Read/Write Control Logic (1)
    //
    logic   [7:0]   internal_data_bus;
    logic           write_control_0;
    logic           write_control_1;
    logic           write_control_2;
    logic           write_counter_0;
    logic           write_counter_1;
    logic           write_counter_2;
    logic           read_counter_0;
    logic           read_counter_1;
    logic           read_counter_2;
    logic   [7:0]   read_counter_0_data;
    logic   [7:0]   read_counter_1_data;
    logic   [7:0]   read_counter_2_data;

    KF8253_Control_Logic u_KF8253_Control_Logic (
        // Bus
        .clock                  (clock),
        .reset                  (reset),
        .chip_select_n          (chip_select_n),
        .read_enable_n          (read_enable_n),
        .write_enable_n         (write_enable_n),
        .address                (address),
        .data_bus_in            (data_bus_in),

        // Control Signals
        .internal_data_bus      (internal_data_bus),
        .write_control_0        (write_control_0),
        .write_control_1        (write_control_1),
        .write_control_2        (write_control_2),
        .write_counter_0        (write_counter_0),
        .write_counter_1        (write_counter_1),
        .write_counter_2        (write_counter_2),
        .read_counter_0         (read_counter_0),
        .read_counter_1         (read_counter_1),
        .read_counter_2         (read_counter_2)
    );


    //
    // Counter #0
    //
    // Counter 0 -- the interval timer -- powers up in mode 3 (square wave),
    // matching np2's itimer_reset (io/pit.c: ch0.ctrl = 0x16 = RL=MSB,
    // mode 3). It stays inert (start_counting = 0) until the first count
    // write, exactly like np2's chip: whatever the ROM writes drives it. On
    // this machine only the FD80 POST programs mode 3 (FDE20: ctrl 0x36,
    // count 0x6000 = 100 Hz at the 2.4576 MHz PIT clock); the ITF's own
    // tests use mode 0 and leave a one-tick-then-silent timer behind, which
    // is correct mode-0 behavior, not a stuck output.
    KF8253_Counter #(
        .RESET_MODE (3'd3)       // MODE_3: square wave, np2's itimer_reset
    ) u_KF8253_Counter_0 (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (internal_data_bus),
        .write_control          (write_control_0),
        .write_counter          (write_counter_0),
        .read_counter           (read_counter_0),

        .read_counter_data      (read_counter_0_data),

        // I/O
        .counter_clock          (counter_0_clock),
        .counter_gate           (counter_0_gate),
        .counter_out            (counter_0_out)
    );


    //
    // Counter #1
    //
    KF8253_Counter u_KF8253_Counter_1 (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (internal_data_bus),
        .write_control          (write_control_1),
        .write_counter          (write_counter_1),
        .read_counter           (read_counter_1),

        .read_counter_data      (read_counter_1_data),

        // I/O
        .counter_clock          (counter_1_clock),
        .counter_gate           (counter_1_gate),
        .counter_out            (counter_1_out)
    );


    //
    // Counter #2
    //
    KF8253_Counter u_KF8253_Counter_2 (
        // Bus
        .clock                  (clock),
        .reset                  (reset),

        .internal_data_bus      (internal_data_bus),
        .write_control          (write_control_2),
        .write_counter          (write_counter_2),
        .read_counter           (read_counter_2),

        .read_counter_data      (read_counter_2_data),

        // I/O
        .counter_clock          (counter_2_clock),
        .counter_gate           (counter_2_gate),
        .counter_out            (counter_2_out)
    );


    //
    // Data Bus Buffer & Read/Write Control Logic (2)
    //
    always_comb begin
        if (read_counter_0)
            data_bus_out = read_counter_0_data;
        else if (read_counter_1)
            data_bus_out = read_counter_1_data;
        else if (read_counter_2)
            data_bus_out = read_counter_2_data;
        else
            data_bus_out = 8'b00000000;
    end

endmodule

