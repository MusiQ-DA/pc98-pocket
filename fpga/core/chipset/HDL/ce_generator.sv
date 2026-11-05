//
// ce_generator
//
// Generate the virtual CPU CLK pin plus synchronous clock-enable pulses for
// the chipset domain from the single 42.954545 MHz chipset clock. One
// posedge CE is one guest CPU clock: the ratios below run the named machine
// at 1x, not at a multiple of its rate.
//
module ce_generator (
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
    output  logic   [1:0]   ram_write_wait_cycle,
    // The faithful speeds model the GDC's display-refresh bus sharing --
    // the fast settings bought their speed by not modelling it (np21w's
    // MEMWAIT_VRAM, charged per CPU cycle by RAM.sv's wait counters).
    output  logic           vram_wait_en
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
        vram_wait_en = 1'b0;
        cpu_edge_num = 9'd2;
        cpu_edge_den = 9'd9;

        // PC-98 speeds, priced at 1x: one CE pulse is one CPU clock of the
        // 286-class machine the menu entry names. The bus engine
        // (cpu_bus_bridge) paces every bus cycle at the 286 Ts/Tc profile --
        // two CPU clocks a cycle -- so the CPU clock itself is what this
        // generator has to make; the old 2x ratios (built for the V30's 4T
        // bus, with core_top's duty gate throttling the average back down)
        // are retired.
        //
        // 92/201 is the 2.4576 MHz-family value -- the class the ITF selects
        // when [0x0501] bit 7 is clear, which is what this build presents
        // and what the PIT is already clocked for (docs/HANDOVER.md 3.6) --
        // 9.830393 MHz, within 0.0001% of the VX21's 9.8304. The 8 and 12 MHz
        // classes have no exact ratio against this clock, so they take the
        // nearest rationals: 75/201 = 8.013908 MHz (+0.17% off the VX2's
        // nominal 8) and 112/201 = 11.967435 MHz (-0.27% off the RX class's
        // nominal 12); 201 stays the shared denominator and still fits the
        // 9-bit accumulator.
        //
        // The clock_cycle_counter_* and shift_read_timing outputs below belong
        // to the CPU this generator was originally built against, which is not
        // the part instantiated here (core_top puts z86 + cpu_bus_bridge
        // there); only the edge ratio and the RAM waits are consumed.
        case (active_clk_select)
            2'b00:
            begin                                   // 8.013908 MHz: "286
                cpu_edge_num = 9'd75;               // 8MHz" (VX2 class,
                cpu_edge_den = 9'd201;              // nearest fit +0.17%)
                vram_wait_en = 1'b1;
            end

            2'b01:
            begin                                   // 9.830393 MHz: "286
                cpu_edge_num = 9'd92;               // 10MHz" (VX21 class,
                cpu_edge_den = 9'd201;              // family exact)
                vram_wait_en = 1'b1;
            end

            2'b10:
            begin                                   // 11.967435 MHz: "286
                cpu_edge_num = 9'd112;              // 12MHz" (RX class,
                cpu_edge_den = 9'd201;              // nearest fit -0.27%)
                ram_read_wait_cycle = 2'd1;         // as the 1/1 step needs
            end

            2'b11:                                  // 21.477 MHz, the chipset
            begin                                   // clock itself
                cpu_edge_num = 9'd1;
                cpu_edge_den = 9'd1;
                cycle_accrate = 1'b0;
                ram_read_wait_cycle = 2'd1;
            end
        endcase
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