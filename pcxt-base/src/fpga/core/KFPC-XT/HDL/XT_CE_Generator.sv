//
// XT_CE_Generator
//
// Generate the virtual 8088 CLK pin plus synchronous clock-enable pulses for
// the XT/chipset domain from the single 50 MHz chipset clock.
//
module XT_CE_Generator (
    input   logic           clock,
    input   logic           reset,
    input   logic           clk_select_load,
    input   logic   [1:0]   clk_select,

    output  logic           cpu_clk_pin,
    output  logic           cpu_ce_posedge,
    output  logic           cpu_ce_negedge,
    output  logic           peripheral_ce,

    output  logic           cycle_accrate,
    output  logic   [7:0]   clock_cycle_counter_division_ratio,
    output  logic   [7:0]   clock_cycle_counter_decrement_value,
    output  logic           shift_read_timing,
    output  logic   [1:0]   ram_read_wait_cycle,
    output  logic   [1:0]   ram_write_wait_cycle
);

    localparam logic [8:0] PERIPHERAL_CE_NUM = 9'd1;
    localparam logic [8:0] PERIPHERAL_CE_DEN = 9'd18;

    logic   [1:0]   active_clk_select;
    logic   [8:0]   cpu_phase_acc;
    logic   [8:0]   peripheral_phase_acc;
    logic   [8:0]   cpu_edge_num;
    logic   [8:0]   cpu_edge_den;
    logic   [9:0]   cpu_phase_sum;
    logic   [9:0]   peripheral_phase_sum;

    wire speed_change = clk_select_load && (clk_select != active_clk_select);

    always_comb
    begin
        cpu_phase_sum = {1'b0, cpu_phase_acc} + {1'b0, cpu_edge_num};
        peripheral_phase_sum = {1'b0, peripheral_phase_acc} + {1'b0, PERIPHERAL_CE_NUM};

        cycle_accrate = 1'b1;
        clock_cycle_counter_division_ratio = 8'd0;
        clock_cycle_counter_decrement_value = 8'd1;
        shift_read_timing = 1'b0;
        ram_read_wait_cycle = 2'd0;
        ram_write_wait_cycle = 2'd0;
        cpu_edge_num = 9'd2;
        cpu_edge_den = 9'd9;

`ifdef MACHINE_PC98
        // PC-98 speeds. The machine is a 2.4576 MHz-family box -- the class the
        // ITF selects when [0x0501] bit 7 is clear, which is what this build
        // presents and what the PIT is already clocked for (docs/HANDOVER.md
        // 3.6) -- so the V30's two real speeds are 2.4576 MHz x2 and x4, the
        // "5 MHz" and "10 MHz" of a PC-9801VM/VX front panel. The third step is
        // twice the fast one: not a speed any real machine had, but still
        // cycle-paced, unlike the fourth. 201 is the denominator that lands all
        // three within 0.0001% of the exact frequency, and 184/201 still fits
        // the 9-bit accumulator.
        //
        // The clock_cycle_counter_* and shift_read_timing outputs below are the
        // 8088 BIU's, and the 8088 is not instantiated in this build (core_top
        // puts the nuV30 + v30_cpu_bridge there); only the edge ratio and the
        // RAM waits are consumed here.
        case (active_clk_select)
            2'b00:
            begin                                   // 4.915197 MHz ("5 MHz")
                cpu_edge_num = 9'd46;
                cpu_edge_den = 9'd201;
            end

            2'b01:
            begin                                   // 9.830393 MHz ("10 MHz")
                cpu_edge_num = 9'd92;
                cpu_edge_den = 9'd201;
            end

            2'b10:
            begin                                   // 19.660787 MHz (2 x fast)
                cpu_edge_num = 9'd184;
                cpu_edge_den = 9'd201;
                ram_read_wait_cycle = 2'd1;         // as the 1/1 step needs
            end

            2'b11:
            begin                                   // 21.477 MHz, the chipset
                cpu_edge_num = 9'd1;                // clock itself
                cpu_edge_den = 9'd1;
                cycle_accrate = 1'b0;
                ram_read_wait_cycle = 2'd1;
            end
        endcase
`else
        case (active_clk_select)
            2'b00:
            begin
                cpu_edge_num = 9'd2;
                cpu_edge_den = 9'd9;
                clock_cycle_counter_division_ratio = 8'd6 - 8'd1;
                clock_cycle_counter_decrement_value = 8'd7;
            end

            2'b01:
            begin
                cpu_edge_num = 9'd1;
                cpu_edge_den = 9'd3;
                clock_cycle_counter_division_ratio = 8'd4 - 8'd1;
                clock_cycle_counter_decrement_value = 8'd7;
            end

            2'b10:
            begin
                cpu_edge_num = 9'd4;
                cpu_edge_den = 9'd9;
                clock_cycle_counter_division_ratio = 8'd9 - 8'd1;
                clock_cycle_counter_decrement_value = 8'd22;
            end

            2'b11:
            begin
                cpu_edge_num = 9'd1;
                cpu_edge_den = 9'd1;
                cycle_accrate = 1'b0;
                clock_cycle_counter_decrement_value = 8'd6;
                shift_read_timing = 1'b1;
                ram_read_wait_cycle = 2'd1;
            end
        endcase
`endif
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            active_clk_select <= 2'b00;
            cpu_phase_acc <= 9'd0;
            peripheral_phase_acc <= 9'd0;
            cpu_clk_pin <= 1'b0;
            cpu_ce_posedge <= 1'b0;
            cpu_ce_negedge <= 1'b0;
            peripheral_ce <= 1'b0;
        end
        else
        begin
            cpu_ce_posedge <= 1'b0;
            cpu_ce_negedge <= 1'b0;
            peripheral_ce <= 1'b0;

            if (speed_change)
            begin
                active_clk_select <= clk_select;
                cpu_phase_acc <= 9'd0;
            end
            else if (cpu_phase_sum >= {1'b0, cpu_edge_den})
            begin
                cpu_phase_acc <= cpu_phase_sum[8:0] - cpu_edge_den;
                if (cpu_clk_pin)
                    cpu_ce_negedge <= 1'b1;
                else
                    cpu_ce_posedge <= 1'b1;

                cpu_clk_pin <= ~cpu_clk_pin;
            end
            else
                cpu_phase_acc <= cpu_phase_sum[8:0];

            if (peripheral_phase_sum >= {1'b0, PERIPHERAL_CE_DEN})
            begin
                peripheral_phase_acc <= peripheral_phase_sum[8:0] - PERIPHERAL_CE_DEN;
                peripheral_ce <= 1'b1;
            end
            else
                peripheral_phase_acc <= peripheral_phase_sum[8:0];
        end
    end

endmodule