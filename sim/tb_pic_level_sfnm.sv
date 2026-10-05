//
// tb_pic_level_sfnm -- the NEON-demo freeze: the master PIC was left in
// LEVEL-triggered mode (a guest write of ICW1=0x18 was observed as the last
// I/O write before the machine parked), while the BIOS's ICW4=0x1D had put
// it in special-fully-nested mode (SFNM) and the PIT's counter-0 OUT pin
// sat latched HIGH from an expired mode-0 one-shot.
//
// Hardware signature (JTAG, merged zet-cpu build): the CPU re-entered the
// IRQ0 handler (FDE38 sti / push ax / push ds) forever, never reaching the
// body at FDE3F -- INTR re-asserted within ~2 instructions of every STI.
//
// Mechanism: with LTIM set the IRR followed the pin, so the parked pin
// re-armed IRR0 the clock after every acknowledge cleared it; and with
// SFNM set the resolver deliberately let a request at the level already in
// service re-assert INT.  The combination re-dispatched IRQ0 while ISR0
// was still in service -- a storm.
//
// Fix under test: np21w feeds the PIC an *event* per PIT terminal count,
// not a level (io/pit.c systimer -> pic_setirq; io/pic.c has no LTIM path).
// i8259.edge_requests bit 0 keeps IRQ0 edge-captured under LTIM: the
// parked-high pin requests nothing, and only a fresh rising edge does.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pic_level_sfnm;

    logic clk = 1'b0;
    always #11.641 clk = ~clk;
    logic reset = 1'b1;

    // same 2.4576 MHz timer_clock synthesis as Peripherals.sv
    logic timer_clock = 1'b0;
    logic [31:0] pit_clk_phase = 32'd0;
    localparam logic [31:0] PIT_CLK_TOGGLE_HZ = 32'd4_915_200;
    localparam logic [31:0] CHIPSET_HZ        = 32'd42_954_545;
    always_ff @(posedge clk) begin
        if ({1'b0, pit_clk_phase} + PIT_CLK_TOGGLE_HZ >= CHIPSET_HZ) begin
            pit_clk_phase <= pit_clk_phase + PIT_CLK_TOGGLE_HZ - CHIPSET_HZ;
            timer_clock   <= ~timer_clock;
        end
        else
            pit_clk_phase <= pit_clk_phase + PIT_CLK_TOGGLE_HZ;
    end

    logic        pit_cs_n = 1'b1;
    logic        pit_wr_n = 1'b1;
    logic [1:0]  pit_a    = 2'b00;
    logic [7:0]  pit_din  = 8'h00;
    wire  [7:0]  pit_dout;
    wire         out0, out1, out2;

    i8253 u_pit (
        .clock            (clk),
        .reset            (reset),
        .chip_select_n    (pit_cs_n),
        .read_enable_n    (1'b1),
        .write_enable_n   (pit_wr_n),
        .address          (pit_a),
        .data_bus_in      (pit_din),
        .data_bus_out     (pit_dout),
        .counter_0_clock  (timer_clock), .counter_0_gate (1'b1),
        .counter_0_out    (out0),
        .counter_1_clock  (timer_clock), .counter_1_gate (1'b1),
        .counter_1_out    (out1),
        .counter_2_clock  (timer_clock), .counter_2_gate (1'b1),
        .counter_2_out    (out2)
    );

    logic pit_write_cycle_q = 1'b0;
    wire  pit_write_cycle   = ~pit_cs_n & ~pit_wr_n;
    wire  pit_write_done    = pit_write_cycle_q & ~pit_write_cycle;
    wire  pit0_write_clears_irr0 = pit_write_done &
           (  (pit_a == 2'b00)
            | ((pit_a == 2'b11) & (pit_din[7:6] == 2'b00)
                                & (pit_din[5:4] != 2'b00)));
    always_ff @(posedge clk)
        pit_write_cycle_q <= pit_write_cycle;

    logic       pic_cs_n = 1'b1;
    logic       pic_rd_n = 1'b1;
    logic       pic_wr_n = 1'b1;
    logic       pic_a    = 1'b0;
    logic [7:0] pic_din  = 8'h00;
    wire  [7:0] pic_dout;
    logic       inta_n   = 1'b1;
    wire        pic_int;

    logic kbd_irq = 1'b0;

    i8259 #(.edge_requests (8'h01)) u_pic (
        .clock            (clk),
        .reset            (reset),
        .chip_select_n    (pic_cs_n),
        .read_enable_n    (pic_rd_n),
        .write_enable_n   (pic_wr_n),
        .address          (pic_a),
        .data_bus_in      (pic_din),
        .data_bus_out     (pic_dout),
        .data_bus_io      (),
        .cascade_in       (3'b000),
        .cascade_out      (),
        .cascade_io       (),
        .slave_program_n  (1'b1),
        .interrupt_acknowledge_n (inta_n),
        .interrupt_to_cpu (pic_int),
        .external_irr_clear ({7'b0, pit0_write_clears_irr0}),
        .interrupt_request({6'b0, kbd_irq, out0})
    );

    wire [7:0] irr = u_pic.u_Interrupt_Request.interrupt_request_register;
    wire [7:0] isr = u_pic.u_In_Service.in_service_register;

    task automatic pit_write(input logic [1:0] a, input logic [7:0] d);
        begin
            @(negedge clk);
            pit_a = a; pit_din = d; pit_cs_n = 1'b0; pit_wr_n = 1'b0;
            repeat (4) @(negedge clk);
            pit_wr_n = 1'b1;
            @(negedge clk);
            pit_cs_n = 1'b1;
            repeat (8) @(negedge clk);
        end
    endtask

    task automatic pic_write(input logic a, input logic [7:0] d);
        begin
            @(negedge clk);
            pic_a = a; pic_din = d; pic_cs_n = 1'b0; pic_wr_n = 1'b0;
            repeat (4) @(negedge clk);
            pic_wr_n = 1'b1;
            @(negedge clk);
            pic_cs_n = 1'b1;
            repeat (8) @(negedge clk);
        end
    endtask

    task automatic inta_cycle(output logic [7:0] vec);
        begin
            @(negedge clk);
            inta_n = 1'b0;
            repeat (6) @(negedge clk);
            inta_n = 1'b1;
            repeat (6) @(negedge clk);
            inta_n = 1'b0;
            repeat (3) @(negedge clk);
            vec = pic_dout;
            repeat (3) @(negedge clk);
            inta_n = 1'b1;
            repeat (6) @(negedge clk);
        end
    endtask

    localparam int CLK_PER_US = 43;

    int errors = 0;
    logic [7:0] vec;
    int  int_waits;

    initial begin
        repeat (40) @(negedge clk);
        reset = 1'b0;
        repeat (10) @(negedge clk);

        // The BIOS's master init: edge-triggered, cascade, SFNM (ICW4=0x1D).
        pic_write(1'b0, 8'h11);
        pic_write(1'b1, 8'h08);
        pic_write(1'b1, 8'h80);
        pic_write(1'b1, 8'h1D);          // SFNM=1, BUF, 8086
        pic_write(1'b1, 8'hFF);          // mask all

        // Park counter 0 the way the ROMs leave it: mode 0, expired -> OUT high.
        pit_write(2'b11, 8'h30);
        pit_write(2'b00, 8'h40);         // count 0x0040
        pit_write(2'b00, 8'h00);
        repeat (200 * CLK_PER_US) @(posedge clk);
        if (out0 !== 1'b1) begin
            $display("*** FAIL: setup -- OUT never latched high");
            errors = errors + 1;
        end

        // ================================================================
        // The demo's reprogram, observed on the bus as the last I/O write
        // before the park: ICW1 = 0x18 -> LTIM=1 (level), cascade, no ICW4.
        // ICW4 is skipped, so SFNM stays as the BIOS left it.
        // ================================================================
        $display("\n=== level mode + SFNM + pin latched high ===");
        pic_write(1'b0, 8'h18);          // ICW1: LTIM=1, SNGL=0, IC4=0
        pic_write(1'b1, 8'h08);          // ICW2: vectors 08-0F
        pic_write(1'b1, 8'h80);          // ICW3: slave on IRQ7
        pic_write(1'b1, 8'hFE);          // OCW1: unmask IRQ0

        // pin high + level mode + IMR[0]=0 -- but IRQ0 is edge-captured, so
        // the parked-high pin is no event: INT must stay low and IRR0 clear.
        repeat (200) @(posedge clk);
        if (pic_int === 1'b1 || irr[0] === 1'b1) begin
            $display("*** FAIL: parked-high pin still requested IRQ0 (INT=%b IRR=%02X)",
                     pic_int, irr);
            errors = errors + 1;
        end else
            $display("--- parked-high pin requests nothing (INT=%b IRR=%02X)",
                     pic_int, irr);

        // LTIM itself must still work: the keyboard line (bit 1, still
        // masked, still in the level path) has to track its pin.
        kbd_irq = 1'b1;
        repeat (4) @(posedge clk);
        if (irr[1] !== 1'b1) begin
            $display("*** FAIL: level path lost -- IRR1 did not follow pin high");
            errors = errors + 1;
        end
        kbd_irq = 1'b0;
        repeat (4) @(posedge clk);
        if (irr[1] !== 1'b0) begin
            $display("*** FAIL: level path lost -- IRR1 did not follow pin low");
            errors = errors + 1;
        end else
            $display("--- level path intact on unforced pins (IRR1 tracked pin)");

        // A fresh event still delivers: reprogram counter 0 to mode 3 with
        // a tiny count; every rising edge of OUT must produce one IRQ0.
        pit_write(2'b11, 8'h36);
        pit_write(2'b00, 8'h08);
        pit_write(2'b00, 8'h00);

        for (int r = 0; r < 2; r++) begin
            int_waits = 0;
            while (pic_int !== 1'b1 && int_waits < 4000) begin
                @(posedge clk);
                int_waits++;
            end
            if (pic_int !== 1'b1) begin
                $display("*** FAIL: no IRQ0 after mode-3 reprogram (round %0d)", r);
                errors = errors + 1;
            end else begin
                inta_cycle(vec);
                if (vec !== 8'h08) begin
                    $display("*** FAIL: vector %02X, expected 08", vec);
                    errors = errors + 1;
                end else if (isr[0] !== 1'b1) begin
                    $display("*** FAIL: ISR0 not set after the acknowledge");
                    errors = errors + 1;
                end else
                    $display("--- rising-edge event dispatched IRQ0 (vec 08)");
                pic_write(1'b0, 8'h20);   // non-specific EOI
            end
        end

        if (errors == 0)
            $display("\nPASS tb_pic_level_sfnm\nRESULT: PASS");
        else begin
            $display("\n*** %0d storm-path failures ***\nRESULT: FAIL", errors);
        end
        $finish;
    end

endmodule
