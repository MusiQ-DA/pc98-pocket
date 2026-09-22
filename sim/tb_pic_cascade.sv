//
// tb_pic_cascade -- the two-PIC acknowledge nobody ever ran.
//
// Why this bench exists.  Two boots in a row -- one with the stub FDC, one
// with the real controller -- landed the CPU at exactly 0000:0500 running
// zeroes, with INT frozen at 6/7, TMR 05, LVL 01, IL 0 and the new panel
// row reading R 05 M 3D S 00.  The only thing the two boots shared was the
// path their FDC interrupt has to take: the slave 8259 (ports 08/0A, vectors
// INT 10h-17h) whose INT feeds the MASTER's IR7, with the vector supplied by
// the SLAVE during the second INTA pulse while the master stands down and
// puts the slave's ID on the cascade lines.
//
// Nothing ever exercised that.  tb_pic_irq0_edge has one PIC.  tb_pc98_fdc_
// glue drives the glue's irq outputs into the bench's own flags and stops
// there.  The BIOS programs the pair for real (FDA2F..FDA3D for the master,
// FDC66..FDC92 for both; slave ICW2=0x10, and the ITF does the same at
// F85C3-F85D8), and the POST panel froze exactly when the drive probe's
// interrupt should have been the first thing to come back through it.
//
// The bench wires the pair the way Peripherals.sv does -- slave INT to
// master IR7, master cascade_out to slave cascade_in, one INTA line, and
// the data mux that believes the slave's data_bus_io when it says it is
// driving -- programs the ICWs the way the ROMs do, replays the frozen
// panel's state (master IMR 0x3D, masked timer and vsync requests parked in
// IRR), and then asks for the FDC's interrupts.
//
// Phases:
//   A. Slave IR3 (the 2HD FDC line, INT 13h): INT rises through the
//      cascade, the second INTA returns 0x13, driven by the SLAVE while the
//      master's data pins say "not driving", and both ISR bits land (bit 3
//      on the slave, bit 7 -- the cascade -- on the master).
//   B. Slave IR2 (the 2DD FDC line / the 0xCC motor timer, INT 12h): same
//      walk, vector 0x12.
//   C. The masked stragglers stay put: IR0 and IR2 of the MASTER held high
//      the whole time (the frozen panel's R 05) never leak through IMR 3D.
//   D. A master line still vectors itself: IR1 (the keyboard) returns 0x09
//      with the MASTER driving and the slave standing down.
//   E. The EOIs unwind the pair: the slave's specific EOI frees its line
//      but the cascade bit 7 holds the master blocked until its own EOI --
//      then a second drive interrupt comes through clean.
//   F. SFNM, which the master's ICW4 0x1D asks for: while the cascade bit
//      is in service a NEW slave request still raises INT.  (Without special
//      fully nested mode an in-service IR7 would block itself.)
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pic_cascade;

    logic clk = 1'b0;
    always #11.641 clk = ~clk;                 // 42.954545 MHz chipset clock
    logic reset = 1'b1;

    // ---- the master PIC (0x00/0x02) ------------------------------------
    logic        m_cs_n = 1'b1;
    logic        m_rd_n = 1'b1;
    logic        m_wr_n = 1'b1;
    logic        m_a    = 1'b0;
    logic [7:0]  m_din  = 8'h00;
    wire  [7:0]  m_dout;
    wire         m_dio;
    wire  [2:0]  cas;
    wire         cas_io;
    logic        inta_n = 1'b1;
    wire         m_int;                        // the CPU's line
    wire         s_int;                        // slave INT -> master IR7

    // The frozen panel's background: timer (IR0) and vsync (IR2) lines
    // latched HIGH on the master, both masked by IMR 0x3D.
    logic        m_ir0_latched = 1'b1;
    logic        m_ir1_kbd     = 1'b0;
    logic        m_ir2_vsync_latched = 1'b1;

    // The slave's lines: bit3 = 2HD FDC, bit2 = 2DD FDC / 0xCC timer.
    logic        s_ir2 = 1'b0;
    logic        s_ir3 = 1'b0;

    i8259 u_master (
        .clock            (clk),
        .reset            (reset),
        .chip_select_n    (m_cs_n),
        .read_enable_n    (m_rd_n),
        .write_enable_n   (m_wr_n),
        .address          (m_a),
        .data_bus_in      (m_din),
        .data_bus_out     (m_dout),
        .data_bus_io      (m_dio),
        .cascade_in       (3'b000),
        .cascade_out      (cas),
        .cascade_io       (cas_io),
        .slave_program_n  (1'b0),
        .interrupt_acknowledge_n (inta_n),
        .interrupt_to_cpu (m_int),
        .external_irr_clear (8'h00),
        .interrupt_request({s_int, 1'b0, 1'b0, 1'b0, 1'b0,
                            m_ir2_vsync_latched, m_ir1_kbd, m_ir0_latched})
    );

    // ---- the slave PIC (0x08/0x0A) -------------------------------------
    logic        s_cs_n = 1'b1;
    logic        s_rd_n = 1'b1;
    logic        s_wr_n = 1'b1;
    logic        s_a    = 1'b0;
    logic [7:0]  s_din  = 8'h00;
    wire  [7:0]  s_dout;
    wire         s_dio;

    i8259 u_slave (
        .clock            (clk),
        .reset            (reset),
        .chip_select_n    (s_cs_n),
        .read_enable_n    (s_rd_n),
        .write_enable_n   (s_wr_n),
        .address          (s_a),
        .data_bus_in      (s_din),
        .data_bus_out     (s_dout),
        .data_bus_io      (s_dio),
        .cascade_in       (cas),
        .cascade_out      (),
        .cascade_io       (),
        .slave_program_n  (1'b0),
        .interrupt_acknowledge_n (inta_n),
        .interrupt_to_cpu (s_int),
        .external_irr_clear (8'h00),
        .interrupt_request({4'b0, s_ir3, s_ir2, 2'b0})
    );

    // ---- the Peripherals INTA mux, verbatim ----------------------------
    // During the acknowledge the master either drives its own vector or
    // puts the slave's ID on the cascade lines and stands down --
    // data_bus_io is how the slave says it recognized itself.
    logic [7:0] bus_vec;
    always_comb
        bus_vec = (~s_dio) ? s_dout : m_dout;

    wire [7:0] m_irr = u_master.u_Interrupt_Request.interrupt_request_register;
    wire [7:0] m_isr = u_master.u_In_Service.in_service_register;
    wire [7:0] m_imr = u_master.interrupt_mask;
    wire [7:0] s_irr = u_slave.u_Interrupt_Request.interrupt_request_register;
    wire [7:0] s_isr = u_slave.u_In_Service.in_service_register;

    // ---- bus tasks ------------------------------------------------------
    task automatic m_write(input logic a, input logic [7:0] d);
        begin
            @(negedge clk);
            m_a = a; m_din = d; m_cs_n = 1'b0; m_wr_n = 1'b0;
            repeat (4) @(negedge clk);
            m_wr_n = 1'b1;
            @(negedge clk);
            m_cs_n = 1'b1;
            repeat (8) @(negedge clk);
        end
    endtask

    task automatic s_write(input logic a, input logic [7:0] d);
        begin
            @(negedge clk);
            s_a = a; s_din = d; s_cs_n = 1'b0; s_wr_n = 1'b0;
            repeat (4) @(negedge clk);
            s_wr_n = 1'b1;
            @(negedge clk);
            s_cs_n = 1'b1;
            repeat (8) @(negedge clk);
        end
    endtask

    // Two INTA pulses the way the 8288 sequences them; the vector comes
    // back on the second.  Also reports who was driving it.
    task automatic inta_cycle(output logic [7:0] vec, output bit slave_drove);
        begin
            @(negedge clk);
            inta_n = 1'b0;
            repeat (6) @(negedge clk);
            inta_n = 1'b1;
            repeat (6) @(negedge clk);
            inta_n = 1'b0;
            repeat (3) @(negedge clk);
            vec = bus_vec;
            slave_drove = ~s_dio;
            repeat (3) @(negedge clk);
            inta_n = 1'b1;
            repeat (6) @(negedge clk);
        end
    endtask

    task automatic wait_m_int(input int deadline, output bit ok);
        int took;
        begin
            ok = 1'b0; took = 0;
            while (took < deadline && !ok) begin
                @(posedge clk);
                took = took + 1;
                ok = m_int;
            end
        end
    endtask

    int errors = 0;
    logic [7:0] vec;
    bit  slave_drove, got;

    task automatic check(input bit cond, input string what);
        begin
            if (cond) $display("  ok   %s", what);
            else begin
                $display("  FAIL %s", what);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (40) @(negedge clk);
        reset = 1'b0;
        repeat (10) @(negedge clk);

        // The BIOS's ICWs.  Master: edge triggered, cascade, ICW4, vectors
        // 08-0F, slave on IR7, SFNM+buffered/master+8086 (FDA2F..FDA3D and
        // FDC66..FDC7A).  Slave: vectors 10-17, ID 7, buffered+8086
        // (FDC80..FDC92; the ITF sets the same ICW2 at F85C3).
        m_write(1'b0, 8'h11);
        m_write(1'b1, 8'h08);
        m_write(1'b1, 8'h80);
        m_write(1'b1, 8'h1D);
        // The frozen boot's master mask, straight off the panel: timer and
        // vsync masked, keyboard and the IR7 cascade open.
        m_write(1'b1, 8'h3D);

        s_write(1'b0, 8'h11);
        s_write(1'b1, 8'h10);
        s_write(1'b1, 8'h07);
        s_write(1'b1, 8'h09);
        // The BIOS never writes the slave's OCW1 before the drive probe, and
        // ICW1 clears the mask, so the slave runs wide open here.

        $display("== tb_pic_cascade ==");

        // The frozen panel's background, replayed: timer (IR0) and vsync
        // (IR2) toggled once during the ITF and latched HIGH in the
        // master's IRR, parked under the mask.  A pin that has never been
        // low arms no edge, so walk them low-high first.
        m_ir0_latched = 1'b0; m_ir2_vsync_latched = 1'b0;
        repeat (8) @(negedge clk);
        m_ir0_latched = 1'b1; m_ir2_vsync_latched = 1'b1;
        repeat (8) @(negedge clk);
        check(m_irr[0] && m_irr[2],     "the stragglers parked in IRR");

        // ================================================================
        // A. The 2HD FDC's line: slave IR3 -> INT 13h.
        $display("A: slave IR3 through the cascade");
        s_ir3 = 1'b1;                            // RECALIBRATE finished
        wait_m_int(400, got);
        check(got,                      "master INT rose through IR7");
        check(s_irr[3],                 "slave latched the request");
        check(m_irr[7],                 "master latched the cascade line");
        inta_cycle(vec, slave_drove);
        check(vec == 8'h13,             $sformatf("vector is 0x13 (got %02h)", vec));
        check(slave_drove,              "the SLAVE drove the vector");
        check(s_isr[3],                 "slave ISR bit 3 in service");
        check(m_isr[7],                 "master ISR bit 7 (cascade) in service");
        s_ir3 = 1'b0;                             // the handler's result read

        // ================================================================
        // B. The 2DD line: slave IR2 -> INT 12h.  The cascade bit is still
        // in service on the master from phase A, which is fine: the EOI
        // below clears the slave's bit 3, and a fresh edge on IR2 should
        // still get through the pair.
        $display("B: slave IR2 after the slave EOI");
        s_write(1'b0, 8'h63);                     // OCW2: specific EOI, IR3
        check(!s_isr[3],              "slave EOI cleared its bit");
        check(m_isr[7],               "master cascade bit STILL held (needs its own EOI)");
        s_ir2 = 1'b1;
        wait_m_int(400, got);
        check(got,                    "master INT rose again for IR2");
        inta_cycle(vec, slave_drove);
        check(vec == 8'h12,           $sformatf("vector is 0x12 (got %02h)", vec));
        check(slave_drove,            "the SLAVE drove it again");
        s_ir2 = 1'b0;
        s_write(1'b0, 8'h62);                     // specific EOI, IR2
        m_write(1'b0, 8'h67);                     // specific EOI, IR7 (cascade)
        check(!m_isr[7],             "master EOI released the cascade");

        // ================================================================
        // C. The masked stragglers never leaked.  IR0 and IR2 of the master
        // have been latched high since the top of the run (the panel's
        // R 05).
        $display("C: masked master lines stayed put");
        check(m_irr[0] && m_irr[2],   "both stragglers still parked in IRR");
        check(!m_isr[0] && !m_isr[2], "neither ever reached service");

        // ================================================================
        // D. A master line still vectors itself.
        $display("D: master IR1 (keyboard) vectors itself");
        m_ir1_kbd = 1'b1;
        wait_m_int(400, got);
        check(got,                    "INT rose for IR1");
        inta_cycle(vec, slave_drove);
        check(vec == 8'h09,           $sformatf("vector is 0x09 (got %02h)", vec));
        check(!slave_drove,           "the MASTER drove it, slave stood down");
        m_ir1_kbd = 1'b0;
        m_write(1'b0, 8'h61);                     // specific EOI, IR1

        // ================================================================
        // E. A second drive interrupt after everything was unwound.
        $display("E: a clean second drive interrupt");
        s_ir3 = 1'b1;
        wait_m_int(400, got);
        check(got,                    "INT rose");
        inta_cycle(vec, slave_drove);
        check(vec == 8'h13,           $sformatf("vector is 0x13 again (got %02h)", vec));
        s_ir3 = 1'b0;
        s_write(1'b0, 8'h63);                     // slave EOI, IR3
        // The master's cascade bit stays in service on purpose: F nests
        // through it.

        // ================================================================
        // F. Special fully nested mode: the cascade line may nest.  The
        // master's ICW4 is 0x1D -- SFNM set -- precisely so a second slave
        // request is not blocked by the cascade's own in-service bit.
        $display("F: SFNM lets the cascade nest");
        check(m_isr[7],               "cascade bit still in service entering F");
        s_ir2 = 1'b1;
        wait_m_int(400, got);
        check(got,                    "INT rose while IR7 was in service (SFNM)");
        inta_cycle(vec, slave_drove);
        check(vec == 8'h12,           $sformatf("nested vector is 0x12 (got %02h)", vec));
        s_ir2 = 1'b0;
        s_write(1'b0, 8'h62);
        m_write(1'b0, 8'h67);

        if (errors == 0) $display("PASS tb_pic_cascade");
        else             $display("FAIL tb_pic_cascade: %0d", errors);
        $finish(errors != 0);
    end

endmodule

`default_nettype wire
