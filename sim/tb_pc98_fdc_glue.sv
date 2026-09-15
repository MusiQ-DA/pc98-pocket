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
// Checked against np2kai io/fdc.c (fdc_o94's three live bits, fdc_i94's
// constant, fdc_obe/fdc_ibe and the ((port>>4)^chgreg)&1 guard, fdc_intwait's
// pic_setirq) and against the ROM: ITF F85C3 (slave ICW2 = 0x10), BIOS FF438 /
// FF4B3 (the slave mask each path checks), FFAF6 / FFB69 (the two handlers).
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
    logic        mgmt_write = 1'b0;
    logic [3:0]  mgmt_address = 4'd0;
    logic [15:0] mgmt_writedata = 16'd0;

    floppy u_floppy (
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
        .request        ()
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

        // ======== WHAT STILL STANDS BETWEEN THIS AND PC98_FDC_REAL =========
        //
        // A CHARACTERISATION, not a check -- it records floppy.v's behaviour
        // with NO DISK IN THE DRIVE, which is this core's normal state and the
        // reason the macro is still off. No assertions, so that fixing the
        // behaviour does not turn this bench red; the numbers are here to be
        // compared against.
        //
        // READ ID is fine: it interrupts and hands back seven bytes. READ DATA
        // is not. floppy.v's cmd_read_write_hang_at_start is named after what
        // it does -- with no media the command is accepted (command_first sets
        // busy) and then nothing: it is in neither enter_result_phase nor
        // raise_interrupt, so the MSR parks at 0x90, CB set, forever.
        //
        // That is fatal to the boot, and not because of the interrupt. The
        // BIOS's FFA0B waits for CB to clear before it can send ANY further
        // command (`in dx / test al,0x10 / loopne`), so a stuck CB kills the
        // controller for the rest of POST -- and the IPL read is issued right
        // after MEMORY 640KB OK, which is where the hardware stopped.
        //
        // The stub this path replaces answered the same probe with seven
        // result bytes meaning "no drive", which is why it booted. Fixing the
        // interrupt routing does not fix this: it is a separate defect, it is
        // in floppy.v rather than in the glue, and it wants its own change and
        // its own evidence before PC98_FDC_REAL goes back on.
        $display("--- floppy.v with no disk: the remaining blocker ---");
        begin
            logic [7:0] msr, dummy;
            int guard;

            rst = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(posedge clk);
            window(1'b0);
            // No mgmt write this time: media_present stays 0, which is a core
            // with nothing in the drive.
            wr(2, 8'h08);              // interrupts enabled
            wr(1, 8'h0A);              // READ ID
            wr(1, 8'h00);              // head 0, unit 0

            guard = 0;
            while (!fd_irq && guard < 20000) begin
                @(negedge clk);
                guard++;
            end
            #1;
            rd(0, msr);
            $display("  ..   no-media READ ID: irq=%0d after %0d cycles, MSR=%02h",
                     fd_irq, guard, msr);
            for (int b = 0; b < 8; b++) begin
                rd(0, msr);
                rd(1, dummy);
                $display("  ..   result[%0d] = %02h   MSR now %02h  irq %0d",
                         b, dummy, msr, fd_irq);
            end

            // READ DATA, the one the IPL actually issues. Its guard chain is
            // cmd_read_write_hang_at_start, which is a different wire from
            // READ ID's, so it gets measured too rather than reasoned about.
            wr(1, 8'h46);   // READ DATA, MFM
            wr(1, 8'h00);   // head 0, unit 0
            wr(1, 8'h00);   // C
            wr(1, 8'h00);   // H
            wr(1, 8'h01);   // R
            wr(1, 8'h02);   // N = 512
            wr(1, 8'h08);   // EOT
            wr(1, 8'h1B);   // GPL
            wr(1, 8'hFF);   // DTL
            guard = 0;
            while (!fd_irq && guard < 40000) begin
                @(negedge clk);
                guard++;
            end
            rd(0, msr);
            $display("  ..   no-media READ DATA: irq=%0d after %0d cycles, MSR=%02h",
                     fd_irq, guard, msr);
            $display("  ..   (0x90 = RQM+CB with no result phase: CB never");
            $display("  ..    clears, so FFA0B's wait for it never ends)");
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("PASS tb_pc98_fdc_glue");
        else             $display("FAILED tb_pc98_fdc_glue: %0d", errors);
        $finish;
    end

    initial begin
        #5000000;
        $display("FAILED tb_pc98_fdc_glue: timeout");
        $finish;
    end

endmodule

`default_nettype wire
