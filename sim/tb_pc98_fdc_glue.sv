//
// tb_pc98_fdc_glue -- the PC-98 FDC ports really do land on floppy.v's file,
// and its interrupt really does land on the PIC line the BIOS is waiting on.
//
// The PERIPHERALS comment that kept PC98_FDC_REAL switched off says what this
// is for: "Turning this on trades a known-good stub for an untested path; it
// wants a bench that gets there first." The first version of this bench covered
// the register mapping and NOT the interrupt, and the hardware said so: POST
// stopped at MEMORY 640KB OK with LVL 41 -- master IRQ6, the PC/XT's floppy
// line, asserted and never cleared, on a machine whose FDC interrupt is a SLAVE
// line. So the second half of this bench is the routing.
//
// The third part is the state this core is normally in: AN EMPTY DRIVE, which
// floppy.v used to accept a command in and then never answer. That was the
// last thing keeping PC98_FDC_REAL off, it is fixed in floppy.v behind the
// NOT_READY_ENDS_COMMAND parameter, and it is asserted here.
//
// Checked against np2kai io/fdc.c (fdc_o94's three live bits, fdc_i94's
// constant, fdc_obe/fdc_ibe and the ((port>>4)^chgreg)&1 guard, fdc_intwait's
// pic_setirq, FDC_DriveCheck and fdcsend_error7 for the not-ready result) and
// against the ROM: ITF F85C3 (slave ICW2 = 0x10), BIOS FF438 / FF4B3 (the
// slave mask each path checks), FFAF6 / FFB69 (the two handlers), FF98F (the
// result-byte decoder that turns ST0 into the AH the caller sees).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_fdc_glue;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst = 1'b1;
    logic sel_stat = 1'b0, sel_data = 1'b0, sel_ctrl = 1'b0, sel_mode = 1'b0;
    logic port_2dd = 1'b0;
    logic wr_stb = 1'b0;
    logic rd_stb = 1'b0;
    logic [7:0] wr_data = 8'h00;

    // The first half of this bench drives fd_irq by hand, to check the routing
    // in isolation. The second half hands the wire to the real floppy.v.
    logic loop_mode = 1'b0;      // 1 = floppy.v owns fd_irq
    logic fd_irq_force = 1'b0;
    wire  fd_irq = loop_mode ? fdd_irq : fd_irq_force;

    wire [2:0] fd_addr;
    wire       fd_write;
    wire       fd_read;
    wire [7:0] fd_wdata;
    wire [7:0] ctrl_readback;
    wire [7:0] mode_readback;
    wire       group_live;
    wire       irq_2hd;
    wire       irq_2dd;

    pc98_fdc_glue dut (
        .clk(clk), .rst(rst),
        .sel_stat(sel_stat), .sel_data(sel_data), .sel_ctrl(sel_ctrl),
        .sel_mode(sel_mode), .port_2dd(port_2dd),
        .wr_stb(wr_stb), .wr_data(wr_data), .rd_stb(rd_stb),
        .fd_addr(fd_addr), .fd_write(fd_write), .fd_read(fd_read),
        .fd_wdata(fd_wdata), .fd_irq(fd_irq),
        .ctrl_readback(ctrl_readback), .mode_readback(mode_readback),
        .group_live(group_live), .irq_2hd(irq_2hd), .irq_2dd(irq_2dd)
    );

    // THE REAL CONTROLLER, behind the glue. The interrupt contract is a loop --
    // floppy.v raises irq, the guest's handler reads the result phase, floppy.v
    // drops it -- and a bench that stubs either end proves nothing about the
    // loop closing. This is the chip the bitstream ships.
    wire       fdd_irq;
    wire [7:0] fdd_readdata;
    wire [1:0] fdd_request;
    logic        mgmt_write = 1'b0;
    logic [3:0]  mgmt_address = 4'd0;
    logic [15:0] mgmt_writedata = 16'd0;

    // NOT_READY_ENDS_COMMAND is what Peripherals.sv passes under MACHINE_PC98:
    // a PC-98's drives report READY, so an empty one ends a command instead of
    // parking CB. The PC/XT build passes 0 and keeps floppy.v's old behaviour.
    floppy #(.NOT_READY_ENDS_COMMAND(1)) u_floppy (
        .clk            (clk),
        .rst_n          (~rst),
        .dma_req        (),
        .dma_ack        (1'b0),
        .dma_tc         (1'b0),
        .dma_readdata   (8'h00),
        .dma_writedata  (),
        .irq            (fdd_irq),
        .io_address     (fd_addr),
        .io_read        (fd_read),
        .io_readdata    (fdd_readdata),
        .io_write       (fd_write),
        .io_writedata   (fd_wdata),
        .fdd0_inserted  (),
        .mgmt_address   (mgmt_address),
        .mgmt_fddn      (1'b0),
        .mgmt_write     (mgmt_write),
        .mgmt_writedata (mgmt_writedata),
        .mgmt_read      (1'b0),
        .mgmt_readdata  (),
        .wp             (2'b00),
        // Small, so the step-rate chain in floppy.v lands on delay_last_cycle
        // in a handful of cycles instead of a hardware second. It only scales
        // the seek delay; nothing about the interrupt depends on its value.
        .clock_rate     (28'd2000),
        .request        (fdd_request)
    );

    // fd_read is a one-cycle strobe, so looking at it after a read task has
    // returned proves nothing. Latch whether it ever fired.
    logic fd_read_seen = 1'b0;
    logic fd_read_clear = 1'b0;
    always @(posedge clk) begin
        if (fd_read_clear) fd_read_seen <= 1'b0;
        else if (fd_read)  fd_read_seen <= 1'b1;
    end
    task automatic watch_reads;
        @(negedge clk); fd_read_clear = 1'b1;
        @(negedge clk); fd_read_clear = 1'b0;
        #1;
    endtask

    int errors = 0;
    task automatic want(input string what, input [7:0] got, input [7:0] exp);
        if (got !== exp) begin
            $display("  FAIL %-38s %02h (want %02h)", what, got, exp);
            errors++;
        end else
            $display("  ok   %-38s %02h", what, got);
    endtask
    task automatic want1(input string what, input logic got, input logic exp);
        if (got !== exp) begin
            $display("  FAIL %-38s %0d (want %0d)", what, got, exp);
            errors++;
        end else
            $display("  ok   %-38s %0d", what, got);
    endtask

    // A guest write: the port is selected, wr_stb is the single cycle at the
    // end with the data already settled.
    // Drive the strobe and STOP inside it, so the caller can look at what the
    // glue is presenting to floppy.v during the write. wr_end() finishes it.
    // which: 0 = status, 1 = data, 2 = control, 3 = 0xBE.
    task automatic wr_begin(input int which, input [7:0] v);
        sel_stat = (which == 0); sel_data = (which == 1);
        sel_ctrl = (which == 2); sel_mode = (which == 3);
        wr_data = v;
        @(negedge clk);
        wr_stb = 1'b1;
        #1;
    endtask

    task automatic wr_end;
        @(negedge clk);
        wr_stb = 1'b0;
        sel_stat = 0; sel_data = 0; sel_ctrl = 0; sel_mode = 0;
        #1;
    endtask

    task automatic wr(input int which, input [7:0] v);
        wr_begin(which, v);
        wr_end();
    endtask

    // A guest read, shaped the way the chipset shapes it: rd_stb is one cycle
    // at the START of the read, and floppy.v registers io_readdata on the clock
    // edge inside it.
    task automatic rd(input int which, output logic [7:0] v);
        sel_stat = (which == 0); sel_data = (which == 1);
        sel_ctrl = 0; sel_mode = 0;
        @(negedge clk);
        rd_stb = 1'b1;
        @(negedge clk);
        rd_stb = 1'b0;
        #1;
        v = fdd_readdata;
        sel_stat = 0; sel_data = 0;
        #1;
    endtask

    // Pick the window this cycle names, the way the chipset's address[6] does:
    // 0x90/0x92/0x94 have it clear, 0xC8/0xCA/0xCC set.
    task automatic window(input logic dd);
        port_2dd = dd;
        #1;
    endtask

    // Count clocks each interrupt line spends high across the motor tests,
    // so a stuck level cannot pass as a pulse. Cleared through motor_clr.
    logic [7:0] motor_hi_2dd = 0, motor_hi_2hd = 0;
    logic       motor_clr = 1'b0;
    always @(posedge clk) begin
        if (irq_2dd) motor_hi_2dd <= motor_hi_2dd + 1;
        else if (motor_clr) motor_hi_2dd <= 0;
        if (irq_2hd) motor_hi_2hd <= motor_hi_2hd + 1;
        else if (motor_clr) motor_hi_2hd <= 0;
    end

    initial begin
        $display("=== PC-98 FDC port mapping ===");
        repeat (3) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // ---- 0xBE out of reset is 3, so the 2HD window is the live one -----
        // np2 fdc_reset (io/fdc.c:1155-1161) sets fdc.chgreg = 3; fdc_ibe
        // returns (chgreg & 3) | 8 | 0xf0.
        window(1'b0);
        want("0xBE reads 0xFB at reset", mode_readback, 8'hFB);
        want1("2HD window live at reset", group_live, 1'b1);
        window(1'b1);
        want1("2DD window dead at reset", group_live, 1'b0);
        want("dead window's control reads FF", ctrl_readback, 8'hFF);
        window(1'b0);

        // ---- 0x90 is the MSR: floppy.v register 4, and never a write -------
        sel_stat = 1'b1; sel_data = 1'b0; sel_ctrl = 1'b0;
        #1;
        want("0x90 selects reg 4 (MSR)", {5'd0, fd_addr}, 8'd4);
        want1("and does not write", fd_write, 1'b0);
        sel_stat = 1'b0;

        // ---- 0x92 is the FIFO: register 5, both directions -----------------
        sel_data = 1'b1;
        #1;
        want("0x92 selects reg 5 (FIFO)", {5'd0, fd_addr}, 8'd5);
        sel_data = 1'b0;

        wr_begin(1, 8'h03);   // a SPECIFY opcode going into the FIFO
        want("FIFO write carries the byte", fd_wdata, 8'h03);
        want("FIFO write addresses reg 5", {5'd0, fd_addr}, 8'd5);
        want1("and asserts a write", fd_write, 1'b1);
        wr_end();

        // ---- 0x94 becomes a DOR write at register 2 ------------------------
        // The bits floppy.v needs that a PC-98 does not supply are constants:
        // enable (2) and both motors (4,5). Interrupt enable comes from the
        // guest's bit 3. Drive select stays 0 -- the uPD765 command's unit
        // field is what really picks the drive.
        wr_begin(2, 8'h08);
        want("0x94 write addresses reg 2 (DOR)", {5'd0, fd_addr}, 8'd2);
        want1("and asserts a write", fd_write, 1'b1);
        want("DOR: enable+motors+irq", fd_wdata, 8'h3C);
        wr_end();

        // ---- 0x94 READS A CONSTANT, not the byte just written --------------
        // np2kai fdc_i94, io/fdc.c:1064-1087: 0x40, plus 0x20|0x10 for the
        // 0xCx port only, plus 0x04 for "internal drives first" (this dip
        // setting) or 0x08 for the other. The old glue handed back ctrl_q,
        // which after the 0x08 above would read 0x08.
        want("0x94 reads np2's 0x44", ctrl_readback, 8'h44);

        // Interrupt enable off: the same constants, bit 3 clear.
        wr_begin(2, 8'h00);
        want("DOR with irq disabled", fd_wdata, 8'h34);
        wr_end();

        // ---- bit 7 going 0 -> 1 pulses a reset -----------------------------
        // np2's fdc_o94 resets on the EDGE, not the level, so a guest that
        // leaves the bit set does not hold the controller down. floppy.v takes
        // a reset at register 4 with bit 7 set. reset_pending is raised by the
        // edge that ends the write, so the pulse is the cycle AFTER it -- look
        // there, not at the write itself.
        wr(2, 8'h80);
        want("reset goes to reg 4", {5'd0, fd_addr}, 8'd4);
        want("reset writes bit 7", fd_wdata, 8'h80);
        want1("reset asserts a write", fd_write, 1'b1);

        // It lasts one cycle and then the mapping is normal again.
        @(negedge clk); #1;
        want1("reset is one cycle", fd_write, 1'b0);

        // Writing again with bit 7 already set must NOT reset.
        wr(2, 8'h88);
        want1("no second reset while bit 7 stays set", fd_write, 1'b0);

        // Dropping it and raising it again does.
        wr(2, 8'h08);
        wr(2, 8'h88);
        want("a fresh 0 -> 1 resets again", fd_wdata, 8'h80);
        want1("and writes", fd_write, 1'b1);
        @(negedge clk); #1;

        // ================= THE INTERRUPT CONTRACT ==========================
        //
        // floppy.v's irq is a level that stays up until the guest reads the
        // result phase. Which PIC line it appears on is chgreg's business --
        // np2kai io/fdc.c:46-51, pic_setirq(0x0b) when chgreg & 1 else
        // pic_setirq(0x0a) -- and NEITHER of them is the master's IRQ6 that
        // the first build drove.
        $display("--- interrupt routing ---");
        fd_irq_force = 1'b0; #1;
        want1("idle: no 2HD request", irq_2hd, 1'b0);
        want1("idle: no 2DD request", irq_2dd, 1'b0);

        fd_irq_force = 1'b1; #1;
        // chgreg is still 3 here, so the 2HD window owns the interrupt.
        want1("2HD window -> slave IRQ11", irq_2hd, 1'b1);
        want1("and NOT the 2DD line", irq_2dd, 1'b0);

        // ---- 0xBE latches, and moves the interrupt with the window ---------
        // BIOS FF3C3 is a read-modify-write of this port and ITF FAFD0/FAFEE/
        // FB01B steer on bit 0 of the readback, so a frozen 0xFB is a lie the
        // guest acts on. Writing 2 selects the 2DD window.
        wr(3, 8'h02);
        window(1'b0);
        want("0xBE reads back what was written", mode_readback, 8'hFA);
        want1("2HD window now dead", group_live, 1'b0);
        window(1'b1);
        want1("2DD window now live", group_live, 1'b1);
        want("0xCC reads np2's 0x74", ctrl_readback, 8'h74);

        want1("interrupt follows: not 2HD", irq_2hd, 1'b0);
        want1("interrupt follows: slave IRQ10", irq_2dd, 1'b1);
        fd_irq_force = 1'b0; #1;
        want1("and it drops when floppy.v drops it", irq_2dd, 1'b0);

        // ---- the dead window reaches floppy.v not at all -------------------
        // np2's guard is the first statement of fdc_o92/fdc_o94/fdc_i90/
        // fdc_i92/fdc_i94: ((port >> 4) ^ chgreg) & 1 -> return. With chgreg
        // now even, 0x92 is dead and 0xCA is live.
        window(1'b0);                      // 0x92, the dead one
        wr_begin(1, 8'h07);                // RECALIBRATE into the dead FIFO
        want1("dead window: no write to floppy.v", fd_write, 1'b0);
        want("dead window: parks on reg 4", {5'd0, fd_addr}, 8'd4);
        wr_end();
        wr_begin(2, 8'h80);                // and a reset on the dead control
        want1("dead window: control write ignored", fd_write, 1'b0);
        wr_end();
        @(negedge clk); #1;
        want1("dead window: and no reset pulse after", fd_write, 1'b0);

        window(1'b1);                      // 0xCA, the live one
        wr_begin(1, 8'h07);
        want1("live window still writes", fd_write, 1'b1);
        want("live window still reg 5", {5'd0, fd_addr}, 8'd5);
        want("carrying the byte", fd_wdata, 8'h07);
        wr_end();

        // ---- chgreg bit 1 is the media type and must not disturb bit 0 -----
        // BIOS FF3C3 does `in al,0xBE / xor al,2 / and al,3 / out 0xBE,al`.
        wr(3, 8'h00);
        want("0xBE = 0 reads 0xF8", mode_readback, 8'hF8);
        window(1'b1);
        want1("bit 0 clear keeps the 2DD window", group_live, 1'b1);
        wr(3, 8'h03);
        want1("back to 3: 2DD dead again", group_live, 1'b0);
        window(1'b0);
        want1("and 2HD live again", group_live, 1'b1);
        fd_irq_force = 1'b1; #1;
        want1("interrupt back on slave IRQ11", irq_2hd, 1'b1);
        want1("not on IRQ10", irq_2dd, 1'b0);
        fd_irq_force = 1'b0; #1;

        // ============ THE LOOP, CLOSED, AGAINST THE REAL floppy.v ===========
        //
        // Everything above is the glue in isolation. This is the sequence the
        // BIOS actually runs, against the chip the bitstream ships, and it is
        // the check the first build did not have: an interrupt that goes up and
        // CANNOT BE PUT DOWN is what LVL 41 was.
        //
        //   BIOS FF4D9   out 0x94, 0x08     enable the interrupt
        //   BIOS FA0B    (via 0x92)         RECALIBRATE, unit 0
        //   INT 13h      FFB08  in 0x90     the handler reads the MSR
        //                FFB0D  cmd 08h     CB clear -> SENSE INTERRUPT STATUS
        //                FFB14  in 0x92     and reads ST0/PCN
        //
        // floppy.v lowers irq on that last read and on nothing else the guest
        // can do, so the read has to be the thing that lowers it here.
        $display("--- the loop, against floppy.v ---");
        begin
            logic [7:0] msr, st0, pcn;
            int guard;

            // Start from a clean chip so this section does not inherit the
            // reset_sensei / ctrl_q state the mapping tests left behind.
            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(posedge clk);
            loop_mode = 1'b1;
            window(1'b0);           // 0x90/0x92/0x94, and chgreg is 3 again

            // A disk in drive 0, through the same management port the core's
            // file loader uses (floppy.v mgmt register 0, bit 0).
            @(negedge clk);
            mgmt_address = 4'd0; mgmt_writedata = 16'h0001; mgmt_write = 1'b1;
            @(negedge clk);
            mgmt_write = 1'b0;
            #1;

            want1("fresh chip: no interrupt", fd_irq, 1'b0);

            // out 0x94, 0x08 -- DOR bit 3, which is floppy.v's dma_irq_enable
            // and therefore the gate on raise_interrupt.
            wr(2, 8'h08);
            @(negedge clk); #1;
            want1("enabling the interrupt raises none", fd_irq, 1'b0);

            // RECALIBRATE unit 0, two bytes into the data port.
            wr(1, 8'h07);
            wr(1, 8'h00);

            guard = 0;
            while (!fd_irq && guard < 2000) begin
                @(negedge clk);
                guard++;
            end
            #1;
            want1("RECALIBRATE raises floppy.v's irq", fd_irq, 1'b1);
            want1("on slave IRQ11, the 2HD window's", irq_2hd, 1'b1);
            want1("and not on IRQ10", irq_2dd, 1'b0);

            // The handler's first move: read the MSR. CB (0x10) clear means no
            // result phase is waiting, so the SENSE INTERRUPT path it is --
            // and an MSR read must NOT acknowledge anything.
            rd(0, msr);
            want("MSR after RECALIBRATE", msr, 8'h81);   // RQM + seek-busy d0
            want1("reading the MSR does not clear irq", fd_irq, 1'b1);

            // A probe of the DEAD window's data port must not clear it either.
            // This is np2's guard doing the one job that actually costs
            // something if it is missing.
            window(1'b1);
            watch_reads();
            rd(1, st0);
            want1("dead window's data read reaches nothing", fd_read_seen, 1'b0);
            want1("so the interrupt is still up", fd_irq, 1'b1);
            window(1'b0);
            // ... and the live one does, so the check above is not vacuous.
            watch_reads();
            rd(0, msr);
            want1("the live window's read does reach it", fd_read_seen, 1'b1);

            // SENSE INTERRUPT STATUS, and the two result bytes.
            wr(1, 8'h08);
            @(negedge clk); #1;
            want1("SENSE INT alone does not clear it", fd_irq, 1'b1);

            rd(1, st0);
            want("ST0 says seek end, unit 0", st0, 8'h20);
            want1("THE RESULT READ CLEARS IT", fd_irq, 1'b0);
            want1("and the slave line drops with it", irq_2hd, 1'b0);

            rd(1, pcn);
            want("PCN is track 0", pcn, 8'h00);
            want1("still clear after the second byte", fd_irq, 1'b0);

            // The MSR's drive-busy bits, the other half of a seek. The 765
            // sets one when the seek starts and clears it at the SENSE
            // INTERRUPT STATUS that collects it, and the PC-98 FDD BIOS
            // waits on exactly that. floppy.v used to set them and never
            // clear them: the panel came back MS D2, D1B still up for a
            // RECALIBRATE of drive 1 that had finished and been sensed long
            // before, and the boot sat there.
            rd(0, msr);
            want1("seek bits clear once the interrupt is sensed",
                  |(msr & 8'h0F), 1'b0);

            // Drive 1, which is the case the machine actually runs and the
            // one that hung: RECALIBRATE takes its unit from the command
            // byte, while the reply's ST0 takes it from the DOR's drive
            // field -- and the glue parks that at 0, because a PC-98 has no
            // DOR to put it in. A clear keyed on ST0 would miss this.
            wr(1, 8'h07);
            wr(1, 8'h01);
            rd(0, msr);
            want1("drive 1 reads busy while it seeks", msr[1], 1'b1);
            guard = 0;
            while (!fd_irq && guard < 2000) begin
                @(negedge clk);
                guard++;
            end
            #1;
            want1("drive 1's recalibrate interrupts", fd_irq, 1'b1);
            wr(1, 8'h08);
            rd(1, st0);
            rd(1, pcn);
            rd(0, msr);
            want1("and drive 1's busy bit clears with it", msr[1], 1'b0);
            want("the MSR is idle again", msr & 8'hF0, 8'h80);

            // SENSE INTERRUPT STATUS with NOTHING pending: the 765 calls
            // that an invalid command -- ST0 = 80h and a ONE byte result
            // phase. Two bytes would leave the phase open on a host that
            // reads the 80 and stops, and a result phase that never ends
            // holds busy up and makes every later command write vanish.
            // FW 07 03 08 08 / RB 80 / MS D0 on the panel was that state.
            wr(1, 8'h08);
            rd(1, st0);
            want("no interrupt pending: ST0 is 80", st0, 8'h80);
            rd(0, msr);
            want("and the chip is idle, not mid-result", msr, 8'h80);

            // And the loop goes round again: a second RECALIBRATE has to raise
            // a fresh interrupt. An edge-triggered 8259 gets nothing from a
            // line that never came down, which is the other half of why a
            // stuck irq is fatal rather than merely untidy.
            wr(1, 8'h07);
            wr(1, 8'h00);
            guard = 0;
            while (!fd_irq && guard < 2000) begin
                @(negedge clk);
                guard++;
            end
            #1;
            want1("a second command interrupts again", fd_irq, 1'b1);
            want1("again on IRQ11", irq_2hd, 1'b1);
            wr(1, 8'h08);
            rd(1, st0);
            want1("and clears again", fd_irq, 1'b0);
            rd(1, pcn);

            // With the interrupt disabled (control bit 3 low -> DOR bit 3 low
            // -> floppy.v's dma_irq_enable low) a command must raise nothing.
            // That is np2's fdc_o94 bit 0x08 and floppy.v's raise_interrupt
            // agreeing, and it is what makes the enable meaningful.
            wr(2, 8'h00);
            wr(1, 8'h07);
            wr(1, 8'h00);
            guard = 0;
            while (guard < 200) begin
                @(negedge clk);
                guard++;
            end
            #1;
            want1("interrupt disabled: no request", fd_irq, 1'b0);
            want1("and nothing on either slave line", irq_2hd | irq_2dd, 1'b0);
        end

        // =============== THE DRIVE WITH NOTHING IN IT ======================
        //
        // This core's normal state is an empty drive, and it is the state the
        // macro used to die in. floppy.v's three media commands each had a
        // *_hang_at_start wire that accepted the command -- command_first has
        // already set CB -- and then answered nothing, being in neither
        // enter_result_phase nor raise_interrupt, so the MSR parked at 0x90 for
        // good. The BIOS's FFA0B (`xor cx,cx / in al,dx / test al,0x10 /
        // loopne`) will not send another command until CB clears and FF966
        // spins 40*65536 polls for the interrupt, so one probe of an empty
        // drive cost every later FDC call an AH=0x90 timeout at FFA57. The IPL
        // read that triggers it is issued right after MEMORY 640KB OK.
        //
        // What it must answer instead, from np2kai:
        //   READ/WRITE DATA and FORMAT go through FDC_DriveCheck (io/fdc.c:
        //   176-182) -> ST0 = FDCRLT_IC0|FDCRLT_NR|(hd<<2)|us = 0x48 here,
        //   ST1 = ST2 = 0, C/H/R/N echoed from the command, seven bytes and an
        //   interrupt (fdcsend_error7, io/fdc.c:97-117).
        //   READ ID (io/fdc.c:646-650) gives IC0|ND instead: ST0 = 0x40,
        //   ST1 = 0x04.
        // and what the BIOS makes of it, from its own decoder at FF98F: ST0 &
        // 0xC0 nonzero -> FF9A1, EC (0x10) tested first -> AH=0x40, then NR
        // (0x08) -> AH=0x60 "drive not ready", then the ST1 bits, of which ND
        // -> AH=0xC0. 0x60 is the answer an empty drive is supposed to give.
        //
        // MEDIA_PRESENT HAS NO RESET in floppy.v (it is written only by mgmt
        // register 0), so rst does NOT undo the disk the section above put in:
        // the first version of this block relied on that and was measuring a
        // drive with a disk in it. Eject explicitly.
        $display("--- floppy.v with no disk in the drive ---");
        begin
            logic [7:0] msr, st0, st1, st2, c, h, r, n;
            int guard;

            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(posedge clk);
            window(1'b0);

            // EJECT. mgmt register 0 bit 0 is floppy.v's media_present, the
            // same bit fdd_service.c's fdd_mount() sets (FMGMT_PRESENT).
            @(negedge clk);
            mgmt_address = 4'd0; mgmt_writedata = 16'h0000; mgmt_write = 1'b1;
            @(negedge clk);
            mgmt_write = 1'b0;
            #1;

            wr(2, 8'h08);              // out 0x94,08 -- interrupts enabled

            // ---- READ DATA, the command the IPL actually issues ------------
            wr(1, 8'h46);   // READ DATA, MFM
            wr(1, 8'h00);   // HDS/US: head 0, unit 0
            wr(1, 8'h00);   // C
            wr(1, 8'h00);   // H
            wr(1, 8'h01);   // R
            wr(1, 8'h02);   // N = 512
            wr(1, 8'h08);   // EOT
            wr(1, 8'h1B);   // GPL
            wr(1, 8'hFF);   // DTL

            guard = 0;
            while (!fd_irq && guard < 2000) begin
                @(negedge clk);
                guard++;
            end
            #1;
            want1("no-media READ DATA interrupts", fd_irq, 1'b1);
            want1("on the 2HD window's slave IRQ11", irq_2hd, 1'b1);

            // RQM + DIO + CB: a result phase is waiting. The old behaviour was
            // 0x90 -- RQM + CB with nothing to read and nothing coming.
            rd(0, msr);
            want("MSR offers a result phase", msr, 8'hD0);

            rd(1, st0);
            want("ST0 = IC abnormal + NR", st0, 8'h48);
            want1("the result read clears the interrupt", fd_irq, 1'b0);
            rd(1, st1);  want("ST1 is clear (not EC, not ND)", st1, 8'h00);
            rd(1, st2);  want("ST2 is clear", st2, 8'h00);
            rd(1, c);    want("C echoes the command", c, 8'h00);
            rd(1, h);    want("H echoes the command", h, 8'h00);
            rd(1, r);    want("R echoes the command", r, 8'h01);
            rd(1, n);    want("N echoes the command", n, 8'h02);

            // THE THING THAT KILLED POST: CB back down, so FFA0B's wait ends
            // and the next command can be sent at all.
            rd(0, msr);
            want("CB clear again after seven bytes", msr, 8'h80);

            // FF98F decodes ST0 = 0x48 as: & 0xC0 nonzero -> abnormal; EC
            // (0x10) clear so not AH=0x40; NR (0x08) set -> AH=0x60. Spelled
            // out here because getting EC wrong reads as a broken drive.
            want1("BIOS FF98F: abnormal termination", |(st0 & 8'hC0), 1'b1);
            want1("BIOS FF98F: EC clear, so not AH=40", |(st0 & 8'h10), 1'b0);
            want1("BIOS FF98F: NR set, so AH=60 not ready", |(st0 & 8'h08), 1'b1);

            // ---- and the controller is still alive afterwards --------------
            // One empty-drive probe used to end POST. A second command has to
            // be accepted and answered like the first.
            wr(1, 8'h46); wr(1, 8'h00); wr(1, 8'h00); wr(1, 8'h00);
            wr(1, 8'h01); wr(1, 8'h02); wr(1, 8'h08); wr(1, 8'h1B);
            wr(1, 8'hFF);
            guard = 0;
            while (!fd_irq && guard < 2000) begin
                @(negedge clk);
                guard++;
            end
            #1;
            want1("a second empty-drive read answers too", fd_irq, 1'b1);
            rd(1, st0);
            want("and says not ready again", st0, 8'h48);
            for (int b = 0; b < 6; b++) rd(1, msr);
            rd(0, msr);
            want("controller idle again", msr, 8'h80);

            // ---- READ ID, the other command that hung ----------------------
            // The previous version of this bench recorded READ ID as "fine".
            // It was not: it was measured against a drive that still had the
            // section above's disk in it. Its guard chain is a different wire
            // (cmd_read_id_hang_at_start) and it hung for the same reason.
            wr(1, 8'h4A);   // READ ID, MFM
            wr(1, 8'h00);   // HDS/US
            guard = 0;
            while (!fd_irq && guard < 2000) begin
                @(negedge clk);
                guard++;
            end
            #1;
            want1("no-media READ ID interrupts", fd_irq, 1'b1);
            rd(0, msr);
            want("READ ID offers a result phase", msr, 8'hD0);
            rd(1, st0);  want("READ ID ST0 = IC abnormal, no NR", st0, 8'h40);
            rd(1, st1);  want("READ ID ST1 = ND, np2's choice", st1, 8'h04);
            rd(1, st2);  want("READ ID ST2 is clear", st2, 8'h00);
            for (int b = 0; b < 4; b++) rd(1, msr);   // C H R N
            rd(0, msr);
            want("CB clear after READ ID too", msr, 8'h80);

            // ---- FORMAT TRACK, for completeness ----------------------------
            // Not on the boot path, but the same hang and the same fix, and a
            // core that hangs when someone formats an empty drive is no better
            // than one that hangs at POST.
            wr(1, 8'h4D);   // FORMAT TRACK (WRITE ID), MFM
            wr(1, 8'h00);   // HDS/US
            wr(1, 8'h02);   // N
            wr(1, 8'h08);   // SC
            wr(1, 8'h1B);   // GPL
            wr(1, 8'hE5);   // D, the filler byte
            guard = 0;
            while (!fd_irq && guard < 2000) begin
                @(negedge clk);
                guard++;
            end
            #1;
            want1("no-media FORMAT interrupts", fd_irq, 1'b1);
            rd(1, st0);  want("FORMAT ST0 = IC abnormal + NR", st0, 8'h48);
            for (int b = 0; b < 6; b++) rd(1, msr);
            rd(0, msr);
            want("CB clear after FORMAT too", msr, 8'h80);

            // ---- and a disk put back in still reads normally ---------------
            // The not-ready path must be exactly that and nothing more: with
            // media present the command has to reach the old ok_at_start path,
            // not the new result phase. Geometry too -- media_cylinders has no
            // reset either, and a C past the end of it is one of the hangs
            // this change deliberately did NOT touch.
            @(negedge clk);
            mgmt_address = 4'd2; mgmt_writedata = 16'd80; mgmt_write = 1'b1;  // cylinders
            @(negedge clk);
            mgmt_address = 4'd3; mgmt_writedata = 16'd8;                      // sectors/track
            @(negedge clk);
            mgmt_address = 4'd5; mgmt_writedata = 16'd2;                      // heads
            @(negedge clk);
            mgmt_address = 4'd0; mgmt_writedata = 16'h0001;                   // insert
            @(negedge clk);
            mgmt_write = 1'b0;
            #1;
            wr(1, 8'h46); wr(1, 8'h00); wr(1, 8'h00); wr(1, 8'h00);
            wr(1, 8'h01); wr(1, 8'h02); wr(1, 8'h08); wr(1, 8'h1B);
            wr(1, 8'hFF);
            repeat (20) @(negedge clk);
            #1;
            want1("with a disk in, no not-ready interrupt", fd_irq, 1'b0);
            rd(0, msr);
            want1("and it is transferring, not in a result phase", msr[6], 1'b0);

            // ---- SENSE DRIVE STATUS answers READY from the MEDIA ------------
            // The BIOS's drive probe (FD80:F4E8) issues SENSE DRIVE STATUS
            // sixteen times and reads ST3 bit 5 -- a PC-98's 2HD drive only
            // raises READY with media in it, which is what lets an empty
            // machine finish probing and fall through to ROM BASIC instead
            // of retrying IPL reads on a drive that answers ready forever.
            // PC/AT keeps the strapped-true bit (NOT_READY_ENDS_COMMAND 0).
            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(negedge clk);
            // media_present survives reset (it has none), so eject first --
            // the same dance the no-media section above has to do.
            @(negedge clk);
            mgmt_address = 4'd0; mgmt_writedata = 16'h0000; mgmt_write = 1'b1;
            @(negedge clk);
            mgmt_write = 1'b0;
            #1;
            wr(1, 8'h04);   // SENSE DRIVE STATUS, unit 0
            wr(1, 8'h00);
            repeat (10) @(negedge clk); #1;
            rd(0, msr);
            want("sense status offers its result", msr, 8'hD0);
            rd(1, st0);
            want("empty drive: READY bit down", st0 & 8'h20, 8'h00);
            rd(0, msr);
            want("CB clear after sense", msr, 8'h80);

            // ...and up with a disk in.
            @(negedge clk);
            mgmt_address = 4'd0; mgmt_writedata = 16'h0001; mgmt_write = 1'b1;
            @(negedge clk);
            mgmt_write = 1'b0;
            #1;
            wr(1, 8'h04); wr(1, 8'h00);
            repeat (10) @(negedge clk); #1;
            rd(1, st0);
            want("with a disk: READY bit up", st0 & 8'h20, 8'h20);
            rd(0, msr);
            want("CB clear after that too", msr, 8'h80);
        end

        // ================================================================
        // The motor interrupt. The BIOS's 2DD init ends with OUT 0CCh,09 /
        // OUT 0CCh,0C (FF6BF..FF6C5) and its 2HD HANDLER's tail writes the
        // same pair as 0D/0C without switching the window (FFB9F..FFBA5) --
        // so the timer arms on ANY 0xCC write, window be damned, and the
        // pulse lands on the 2DD line, slave bit 2, exactly where MAME's
        // fdc_trigger and the old (boot-proven) stub put it.
        begin
            $display("--- the motor interrupt ---");

            // 2DD window live: chgreg bit0 clear.
            window(1'b1);
            wr(3, 8'h02);                       // 0xBE = 2: 0xC8/0xCA/0xCC live
            #1;
            want1("2DD window is live", group_live, 1'b1);

            // Arm-then-gate, the BIOS's own pair.
            wr(2, 8'h08);                       // bit0 stays down: no arm
            wr(2, 8'h09);                       // bit0 rises: arm
            wr(2, 8'h0C);                       // bit2 up: XTMASK
            motor_clr = 1'b1; @(negedge clk); motor_clr = 1'b0;
            repeat (4_295_010) @(posedge clk);
            #1;
            want("2DD motor pulse clocks", motor_hi_2dd[7:0], 8'd1);
            want("2HD line stayed quiet", motor_hi_2hd[7:0], 8'd0);

            // No XTMASK, no interrupt.
            wr(2, 8'h08);
            wr(2, 8'h09);
            wr(2, 8'h08);                       // bit2 down
            motor_clr = 1'b1; @(negedge clk); motor_clr = 1'b0;
            repeat (4_295_010) @(posedge clk);
            #1;
            want("no XTMASK, no pulse on 2DD", motor_hi_2dd[7:0], 8'd0);
            want("no XTMASK, no pulse on 2HD", motor_hi_2hd[7:0], 8'd0);

            // THE CASE THE HARDWARE MEASURED: the 2HD window is live and
            // the 2HD handler's tail still writes 0D/0C to 0xCC. The timer
            // must arm anyway (the drive adapter is outside the window
            // guard) and the pulse must land on the 2DD line.
            wr(3, 8'h03);                       // 0xBE = 3: 2HD window live
            window(1'b0);
            #1;
            want1("0x94 window is the live one", group_live, 1'b1);
            window(1'b1);                       // write 0xCC: a dead window
            #1;
            want1("0xCC is the dead window now", group_live, 1'b0);
            wr(2, 8'h0D);                       // bit0 rises on a DEAD port
            wr(2, 8'h0C);
            motor_clr = 1'b1; @(negedge clk); motor_clr = 1'b0;
            repeat (4_295_010) @(posedge clk);
            #1;
            want("dead-window 0xCC still armed", motor_hi_2dd[7:0], 8'd1);
            want("and pulsed the 2DD line", motor_hi_2dd[7:0], 8'd1);
            want("2HD line quiet: 0xCC is the 2DD timer", motor_hi_2hd[7:0], 8'd0);

            // The mirror: the 2DD handler's tail writes 0D/0C to 0x94
            // (FFAD6..FFADC), and that pulse belongs on the 2HD line --
            // slave bit 3, INT 13h -- regardless of the window. Make 0x94
            // the dead window first (chgreg bit0 clear).
            wr(3, 8'h02);                       // 0xBE = 2: 2DD window live
            window(1'b0);                       // ...so 0x94 is dead
            #1;
            want1("0x94 is the dead window now", group_live, 1'b0);
            wr(2, 8'h0D);                       // bit0 rises on a DEAD port
            wr(2, 8'h0C);
            motor_clr = 1'b1; @(negedge clk); motor_clr = 1'b0;
            repeat (4_295_010) @(posedge clk);
            #1;
            want("dead-window 0x94 armed too", motor_hi_2hd[7:0], 8'd1);
            want("and pulsed the 2HD line", motor_hi_2hd[7:0], 8'd1);
            want("2DD line quiet: 0x94 is the 2HD timer", motor_hi_2dd[7:0], 8'd0);

            // Leave the window the way the bench found it.
            window(1'b1);
            wr(3, 8'h02);
        end

        // ---- the machine's own conversation, replayed ------------------
        //
        // Off the panel's FIFO ring, oldest byte first:
        //
        //     [03] BF 32    SPECIFY
        //     07 00         RECALIBRATE unit 0
        //     07 01         RECALIBRATE unit 1
        //     07 02         RECALIBRATE unit 2
        //     07 03         RECALIBRATE unit 3
        //     08 08         SENSE INTERRUPT STATUS, twice
        //
        // Four seeks issued together and collected one at a time -- the 765's
        // overlapped seek, which the BIOS's drive probe is built on. CA 07
        // counts exactly those seven commands.
        $display("--- the BIOS drive probe: four seeks at once ---");
        begin
            logic [7:0] msr, st0, pcn;
            int guard, i;

            rst = 1'b1; repeat (4) @(posedge clk); rst = 1'b0;
            repeat (2) @(posedge clk);
            loop_mode = 1'b1;
            window(1'b0);
            @(negedge clk);
            mgmt_address = 4'd0; mgmt_writedata = 16'h0001; mgmt_write = 1'b1;
            @(negedge clk);
            mgmt_write = 1'b0; #1;

            wr(2, 8'h08);                              // interrupts enabled
            wr(1, 8'h03); wr(1, 8'hBF); wr(1, 8'h32);  // SPECIFY
            wr(1, 8'h07); wr(1, 8'h00);
            wr(1, 8'h07); wr(1, 8'h01);
            wr(1, 8'h07); wr(1, 8'h02);
            wr(1, 8'h07); wr(1, 8'h03);

            rd(0, msr);
            want("all four drives read busy", msr & 8'h0F, 8'h0F);

            guard = 0;
            while (!fd_irq && guard < 8_000_000) begin
                @(negedge clk); guard++;
            end
            #1;
            want1("the seeks interrupt", fd_irq, 1'b1);

            // One SENSE INTERRUPT STATUS per drive, in order, each clearing
            // its own busy bit and leaving the line up for the next.
            for (i = 0; i < 4; i++) begin
                wr(1, 8'h08);
                rd(1, st0);
                rd(1, pcn);
                want("ST0 names the drive, seek end", st0 & 8'h23,
                     8'h20 | i[1:0]);
                if (i < 3) begin
                    repeat (2) @(negedge clk); #1;
                    want1("and the line comes back for the next", fd_irq, 1'b1);
                end
            end
            repeat (2) @(negedge clk); #1;
            want1("four sensed, the line finally rests", fd_irq, 1'b0);
            rd(0, msr);
            want("and the MSR is idle", msr, 8'h80);

            // The fifth ask gets the invalid-command answer, one byte.
            wr(1, 8'h08);
            rd(1, st0);
            want("a fifth SENSE gets 80", st0, 8'h80);
            rd(0, msr);
            want("still idle after it", msr, 8'h80);
        end

        // ================================================================
        // 2HD: 1024-byte sectors (N=3). The PC-98's standard disk is 77
        // cylinders, 8 sectors, 2 heads of 1024 bytes -- twice the width
        // everything above assumed. The FIFO's full threshold, and the N a
        // READ ID reports, key off the media's declared width; and a command
        // whose N names the WRONG width is an error ANSWER, not a hang,
        // because the BIOS probes a drive in more than one format and must
        // get ST0 back to fall through to the next try.
        $display("--- 2HD: 1024-byte sectors ---");
        begin
            logic [7:0] msr, st0, b0, blast;
            int guard;

            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(posedge clk);
            window(1'b0);

            // Mount the 1232 KB disk, the way fdd_mount() would.
            @(negedge clk);
            mgmt_address = 4'd2; mgmt_writedata = 16'd77; mgmt_write = 1'b1;
            @(negedge clk);
            mgmt_address = 4'd3; mgmt_writedata = 16'd8;
            @(negedge clk);
            mgmt_address = 4'd5; mgmt_writedata = 16'd2;
            @(negedge clk);
            mgmt_address = 4'd6; mgmt_writedata = 16'd1;  // sectors are 1024B
            @(negedge clk);
            mgmt_address = 4'd0; mgmt_writedata = 16'd1;  // insert
            @(negedge clk);
            mgmt_write = 1'b0;
            #1;

            wr(2, 8'h08);                                // interrupts enabled
            // SPECIFY with NDMA set (byte 2 bit 0): the bench drains the
            // sector over the data port rather than keeping a DMA engine
            // busy. The BIOS's own value is 32 -- DMA mode -- which needs
            // the 8237; this exercises the same FIFO either way.
            wr(1, 8'h03); wr(1, 8'hBF); wr(1, 8'h33);    // SPECIFY, NDMA on

            // READ DATA: C0 H0 R1 N3 EOT1 -- one 1024-byte sector.
            wr(1, 8'h46); wr(1, 8'h00); wr(1, 8'h00); wr(1, 8'h00);
            wr(1, 8'h01); wr(1, 8'h03); wr(1, 8'h01); wr(1, 8'h1B);
            wr(1, 8'hFF);

            repeat (10) @(negedge clk); #1;
            want1("2HD read raises the sector request", fdd_request[0], 1'b1);

            // 512 bytes -- a whole 2DD sector -- is HALF a 2HD one, and the
            // request must still be standing.
            mgmt_address = 4'hF;
            for (int i = 0; i < 512; i++) begin
                @(negedge clk);
                mgmt_writedata = {8'h00, i[7:0]};
                mgmt_write = 1'b1;
            end
            @(negedge clk);
            mgmt_write = 1'b0;
            repeat (10) @(negedge clk); #1;
            want1("512 bytes did not fill a 2HD sector", fdd_request[0], 1'b1);

            // The second half completes it, and the chip moves on to handing
            // the bytes to the guest.
            for (int i = 0; i < 512; i++) begin
                @(negedge clk);
                mgmt_writedata = {8'h00, (i[7:0] ^ 8'hA5)};
                mgmt_write = 1'b1;
            end
            @(negedge clk);
            mgmt_write = 1'b0;
            guard = 0;
            while (fdd_request[0] && guard < 20_000) begin
                @(negedge clk); guard++;
            end
            #1;
            want1("1024 bytes completed the sector", fdd_request[0], 1'b0);

            // The guest drains it over NDMA: first byte of the first half,
            // last byte of the second (i=511: 511&FF ^ A5 = 5A).
            rd(1, b0);
            want("first byte of the sector", b0, 8'h00);
            for (int i = 0; i < 1022; i++) rd(1, msr);
            rd(1, blast);
            want("last byte of the sector", blast, 8'h5A);

            // EOT was 1, so the transfer is over: result phase, interrupt,
            // and a clean ST0.
            guard = 0;
            while (!fd_irq && guard < 20_000) begin
                @(negedge clk); guard++;
            end
            #1;
            want1("the read interrupts", fd_irq, 1'b1);
            rd(1, st0);
            want("ST0 clean", st0, 8'h00);
            for (int b = 0; b < 6; b++) rd(1, msr);
            rd(0, msr);
            want("MSR idle after the result", msr, 8'h80);

            // ---- a READ ID on the same media reports ITS N as 3 -----------
            wr(1, 8'h0A); wr(1, 8'h00);   // READ ID, head 0 unit 0
            guard = 0;
            while (!fd_irq && guard < 10_000) begin
                @(negedge clk); guard++;
            end
            #1;
            want1("READ ID interrupts", fd_irq, 1'b1);
            rd(1, st0);
            want("READ ID ST0 clean", st0, 8'h00);
            rd(1, msr); rd(1, msr); rd(1, msr); rd(1, msr); rd(1, msr);
            rd(1, b0);
            want("READ ID reports N=3 for 2HD", b0, 8'h03);
            rd(0, msr);
            want("MSR idle after READ ID", msr, 8'h80);

            // ---- and the WRONG N is an answer, not a hang ------------------
            wr(1, 8'h46); wr(1, 8'h00); wr(1, 8'h00); wr(1, 8'h00);
            wr(1, 8'h01); wr(1, 8'h02); wr(1, 8'h01); wr(1, 8'h1B);
            wr(1, 8'hFF);
            guard = 0;
            while (!fd_irq && guard < 20_000) begin
                @(negedge clk); guard++;
            end
            #1;
            want1("N=2 on a 2HD disk interrupts", fd_irq, 1'b1);
            rd(1, st0);
            want("ST0 = IC abnormal, not a hang", st0 & 8'hC0, 8'h40);
            want1("and no sector request was made", fdd_request[0], 1'b0);
            for (int b = 0; b < 6; b++) rd(1, msr);
            rd(0, msr);
            want("MSR idle after the error", msr, 8'h80);
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("PASS tb_pc98_fdc_glue");
        else             $display("FAILED tb_pc98_fdc_glue: %0d", errors);
        $finish;
    end

    initial begin
        // The motor phases each wait out a real ~100 ms timer (4 x 42.95 ms
        // of simulation at the bench's 10 ns clock), so the watchdog has to
        // clear them with room to spare.
        #250000000;
        $display("FAILED tb_pc98_fdc_glue: timeout");
        $finish;
    end

endmodule

`default_nettype wire
