//
// tb_post_monitor -- does the POST monitor record what the guest actually wrote?
//
// testB16 shipped without this and came back with SEQ FF 53 74 C3 6F, which are
// not POST codes at all -- the BIOS only ever writes 00-12, 21-25, 30-32,
// 40-43, 52, 54 and 55 -- and ADDR 00080, which is the port number rather than
// a memory address. Both were sampling bugs in the monitor, not findings about
// the guest.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_post_monitor;

    logic clk = 0, rst = 1;
    always #11.64 clk = ~clk;

    logic [19:0] address = 20'h0;
    logic  [7:0] cpu_data = 8'h00;
    logic        io_write_n = 1, memory_read_n = 1, memory_write_n = 1;
    logic        aen_n = 0;   // address_enable_n: 0 = normal CPU cycle, 1 = DMA

    logic  [7:0] bus_data = 8'h00;

    logic [19:0] ld_addr = 20'h0;
    logic  [7:0] ld_data = 8'h00;
    logic        ld_we_n = 1'b1;

    wire [127:0] rom_read_data, rom_load_data;
    wire   [7:0] rom_read_count, rom_load_count;
    wire  [63:0] io_port_hist;
    wire  [15:0] io_wr_count;
    wire  [7:0] post_code, post_prev, post_max;
    wire [63:0] post_hist;
    wire [19:0] last_mem_addr;
    wire [15:0] post_count, restart_count;

    post_monitor u_dut (
        .clk(clk), .rst(rst),
        .address(address), .cpu_data(cpu_data), .bus_data(bus_data),
        .io_write_n(io_write_n), .address_enable_n(aen_n),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .post_code(post_code), .post_prev(post_prev), .post_hist(post_hist),
        .last_mem_addr(last_mem_addr), .post_count(post_count),
        .post_max(post_max), .restart_count(restart_count),
        // The snoop window is a register now, so the bench has to say where it
        // looks. FD88 is what the PC/AT build hardwired, which is what these
        // expectations were written against; the PC-98 build powers up at FFFF.
        .rom_win(16'hFD88),
        .rom_read_data(rom_read_data), .rom_read_count(rom_read_count),
        .ld_addr(ld_addr), .ld_data(ld_data), .ld_we_n(ld_we_n),
        .rom_load_data(rom_load_data), .rom_load_count(rom_load_count),
        .io_port_hist(io_port_hist), .io_wr_count(io_wr_count)
    );

    int errors = 0;
    logic [15:0] io_after_glitch;

    // A CPU read out of the snooped ROM window. Data is valid at the END of the
    // cycle: the bus carries the PREVIOUS transfer's byte while the strobe goes
    // active and only settles later. Latching on the leading edge is the bug
    // that produced SEQ FF 53 74 C3 6F on the POST port and then, after that was
    // fixed, CPURD 59 FC 2E FC on this one -- the same mistake twice, so the
    // stale byte here is deliberately the previous slot's value.
    // The BIOS loader's write of one byte: strobe held until the RAM
    // controller completes, address and data stable throughout.
    task automatic loader_write(input logic [19:0] a, input logic [7:0] v);
        ld_addr = a; ld_data = v; ld_we_n = 1'b0;
        repeat (6) @(posedge clk);
        ld_we_n = 1'b1; ld_addr = 20'h0;
        repeat (3) @(posedge clk);
    endtask

    task automatic rom_read(input logic [19:0] a,
                            input logic  [7:0] stale,
                            input logic  [7:0] val);
        address = a;
        bus_data = stale;
        memory_read_n = 0;
        repeat (2) @(posedge clk);
        bus_data = val;
        repeat (3) @(posedge clk);
        memory_read_n = 1;
        address = 20'h0;
        repeat (3) @(posedge clk);
    endtask

    // A guest memory access, the thing ADDR is supposed to report.
    task automatic mem_read(input logic [19:0] a);
        address = a; memory_read_n = 0;
        repeat (4) @(posedge clk);
        memory_read_n = 1; address = 20'h0;
        repeat (2) @(posedge clk);
    endtask

    // A guest memory WRITE, data settling mid-cycle like out80's does.
    task automatic mem_write(input logic [19:0] a, input logic [7:0] v);
        address = a; cpu_data = 8'hC3; memory_write_n = 0;
        repeat (2) @(posedge clk);
        cpu_data = v;
        repeat (3) @(posedge clk);
        memory_write_n = 1; address = 20'h0;
        repeat (3) @(posedge clk);
    endtask

    // A guest memory READ whose data arrives late, like rom_read's.
    task automatic mem_read_val(input logic [19:0] a,
                                input logic  [7:0] stale,
                                input logic  [7:0] val);
        address = a; bus_data = stale; memory_read_n = 0;
        repeat (2) @(posedge clk);
        bus_data = val;
        repeat (3) @(posedge clk);
        memory_read_n = 1; address = 20'h0;
        repeat (3) @(posedge clk);
    endtask

    // An I/O write to an arbitrary port.
    task automatic out_port(input logic [15:0] p, input logic [7:0] v);
        address = {4'h0, p};
        cpu_data = v;
        io_write_n = 0;
        repeat (4) @(posedge clk);
        io_write_n = 1;
        address = 20'h0;
        repeat (3) @(posedge clk);
    endtask

    // out 0x80,al the way the bus does it: address and command up first, data
    // settling only partway through. A monitor that latches on the leading edge
    // captures the garbage that is on the bus beforehand.
    task automatic out80(input logic [7:0] v);
        address = 20'h00080;
        cpu_data = 8'hC3;          // stale bus content, deliberately wrong
        io_write_n = 0;
        repeat (2) @(posedge clk);
        cpu_data = v;              // real data settles mid-cycle
        repeat (3) @(posedge clk);
        io_write_n = 1;
        address = 20'h0;
        repeat (3) @(posedge clk);
    endtask

    // An I/O write to a DIFFERENT port whose address happens to sweep through
    // 0x0080 for one cycle on the way. testB17 recorded MAX 63, a value the
    // BIOS never writes to port 0x80, so a transient like this must not count.
    task automatic out_other_glitch(input logic [7:0] v);
        io_write_n = 0;
        address = 20'h00080;       // one cycle only, in transit
        cpu_data = v;
        @(posedge clk);
        address = 20'h00081;       // settles on the real port
        repeat (4) @(posedge clk);
        io_write_n = 1;
        address = 20'h0;
        repeat (3) @(posedge clk);
    endtask

    initial begin
        $display("=== post_monitor capture ===");
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        // A plausible POST run with memory work between the codes.
        mem_read(20'h00400);
        out80(8'h00);
        mem_read(20'h07FFE);
        out80(8'h01);
        out80(8'h02);
        mem_read(20'h12345);
        out80(8'h03);
        out80(8'h04);
        mem_read(20'h0ABCD);
        out80(8'h54);          // the memory-test failure code

        repeat (8) @(posedge clk);

        $display("  count    = %0d (want 6)", post_count);
        $display("  code     = %02h (want 54)", post_code);
        $display("  prev     = %02h (want 04)", post_prev);
        $display("  max      = %02h (want 54)", post_max);
        $display("  restarts = %0d (want 0)", restart_count);
        $display("  addr     = %05h (want 0ABCD, NOT 00080)", last_mem_addr);
        $display("  hist     = %02h %02h %02h %02h %02h %02h  (want 00 01 02 03 04 54)",
                 post_hist[47:40], post_hist[39:32], post_hist[31:24],
                 post_hist[23:16], post_hist[15:8], post_hist[7:0]);

        if (post_count !== 16'd6)      begin $display("  FAIL count");    errors++; end
        if (post_code  !== 8'h54)      begin $display("  FAIL code");     errors++; end
        if (post_prev  !== 8'h04)      begin $display("  FAIL prev");     errors++; end
        if (post_max   !== 8'h54)      begin $display("  FAIL max");      errors++; end
        if (last_mem_addr !== 20'h0ABCD) begin $display("  FAIL addr");   errors++; end
        if (post_hist[47:40] !== 8'h00 || post_hist[39:32] !== 8'h01 ||
            post_hist[31:24] !== 8'h02 || post_hist[23:16] !== 8'h03 ||
            post_hist[15:8]  !== 8'h04 || post_hist[7:0]   !== 8'h54)
            begin $display("  FAIL hist"); errors++; end

        // A DMA cycle: AEN high, IOW asserted, and a MEMORY address whose low
        // 16 bits are 0x0080. An XT refreshes RAM this way continuously, so if
        // this counts the readout is buried -- testB18 showed MAX C0 and
        // RESTARTS 13 for exactly this reason.
        aen_n = 1;                   // DMA owns the bus
        address = 20'h30080;         // memory address, low 16 bits look like the port
        cpu_data = 8'hC0;
        io_write_n = 0;
        repeat (6) @(posedge clk);
        io_write_n = 1;
        address = 20'h0;
        aen_n = 0;
        repeat (4) @(posedge clk);
        if (post_count !== 16'd6) begin
            $display("  FAIL DMA cycle counted (count=%0d, want 6)", post_count); errors++;
        end
        if (post_max === 8'hC0) begin $display("  FAIL DMA reached max"); errors++; end
        $display("  DMA cycle ignored: count=%0d max=%02h", post_count, post_max);

        // A one-cycle sweep through 0x0080 must be ignored entirely.
        out_other_glitch(8'h63);
        repeat (4) @(posedge clk);
        if (post_count !== 16'd6) begin
            $display("  FAIL glitch counted (count=%0d, want 6)", post_count); errors++;
        end
        if (post_max === 8'h63) begin $display("  FAIL glitch reached max"); errors++; end
        $display("  glitch ignored: count=%0d max=%02h", post_count, post_max);
        // The write itself was real -- it just went to 0x0081, not 0x0080. The
        // port trace must say so, and must say it while the entry is still in
        // the four-deep window.
        io_after_glitch = io_port_hist[15:0];
        $display("  port after glitch: %04h (want 0081)", io_after_glitch);
        if (io_after_glitch !== 16'h0081) begin
            $display("  FAIL glitch recorded against the wrong port"); errors++;
        end

        // A restart. The history holds DEPTH=8 entries, and six are used so far,
        // so these two fill it -- the freeze is only expected after that.
        out80(8'h00);          // restart #1
        out80(8'h01);          // history now full
        repeat (4) @(posedge clk);
        if (restart_count !== 16'd1) begin $display("  FAIL restart count"); errors++; end

        // From here the frozen fields must not move, while the counters do.
        out80(8'h02);
        out80(8'h00);          // restart #2
        repeat (8) @(posedge clk);
        $display("  after freeze: count=%0d restarts=%0d code=%02h (code must stay 01)",
                 post_count, restart_count, post_code);
        if (post_code !== 8'h01)      begin $display("  FAIL freeze");         errors++; end
        if (post_count !== 16'd10)    begin $display("  FAIL live count");     errors++; end
        if (restart_count !== 16'd2)  begin $display("  FAIL live restarts");  errors++; end

        // The ROM window: sixteen bytes at F000:D880, read in order, each one
        // preceded on the bus by the byte before it.
        begin
            logic [7:0] img [0:15];
            logic [7:0] got;
            img[0]='hF8; img[1]='h2E; img[2]='hE8; img[3]='hD2;
            img[4]='hEF; img[5]='h50; img[6]='hE3; img[7]='hF2;
            img[8]='hE6; img[9]='h6E; img[10]='hFE; img[11]='h53;
            img[12]='hFF; img[13]='h53; img[14]='hFF; img[15]='hA4;
            got = 8'h59;   // whatever the bus carried before the first read
            for (int i = 0; i < 16; i++) begin
                rom_read(20'hFD880 + i[19:0], got, img[i]);
                got = img[i];
            end

            // A read just OUTSIDE the window must not land in it.
            rom_read(20'hFD890, 8'hA4, 8'h11);
            // An EXT read of the window itself must not land in it either.
            // The arbiter drives address_enable_n from hold_acknowledge and
            // hold_request includes ext_access_request, so an ext access looks
            // exactly like this. run#105's six guest_peek reads of these very
            // addresses overwrote the first six slots and took N from 16 to 22.
            aen_n = 1;
            rom_read(20'hFD880, 8'h00, 8'h51);
            rom_read(20'hFD881, 8'h51, 8'h51);
            aen_n = 0;
            // And one inside the window during a DMA cycle is still a real
            // memory read, so it is allowed -- but a read at a wholly unrelated
            // address must not be.
            rom_read(20'h0ABCD, 8'h00, 8'h77);

            $display("  romN     = %0d (want 16)", rom_read_count);
            if (rom_read_count !== 8'd16) begin
                $display("  FAIL rom count"); errors++;
            end
            for (int i = 0; i < 16; i++) begin
                got = rom_read_data[i*8 +: 8];
                if (got !== img[i]) begin
                    $display("  FAIL rom byte %0d: got %02h want %02h", i, got, img[i]);
                    errors++;
                end
            end
            $display("  rom      = %02h %02h %02h %02h %02h %02h %02h %02h",
                     rom_read_data[7:0], rom_read_data[15:8], rom_read_data[23:16],
                     rom_read_data[31:24], rom_read_data[39:32], rom_read_data[47:40],
                     rom_read_data[55:48], rom_read_data[63:56]);
            $display("             %02h %02h %02h %02h %02h %02h %02h %02h",
                     rom_read_data[71:64], rom_read_data[79:72], rom_read_data[87:80],
                     rom_read_data[95:88], rom_read_data[103:96], rom_read_data[111:104],
                     rom_read_data[119:112], rom_read_data[127:120]);

            // The loader window: sixteen writes off the loader's own FSM,
            // plus one outside it. The window is FFFF0-FFFFF on this machine
            // -- d85e939 pointed the loader snoop at the reset vector, which
            // is the sixteen bytes worth watching -- and it is HARDWIRED, not
            // the firmware-set rom_win register the CPU-read snoop above
            // uses. The writes here used to be FD880, the PC/AT entry, from
            // before the machine layer was the only layer.
            for (int i = 0; i < 16; i++)
                loader_write(20'hFFFF0 + i[19:0], img[i]);
            loader_write(20'hFFFE0, 8'h99);

            $display("  loadN    = %0d (want 16)", rom_load_count);
            if (rom_load_count !== 8'd16) begin
                $display("  FAIL load count"); errors++;
            end
            for (int i = 0; i < 16; i++) begin
                got = rom_load_data[i*8 +: 8];
                if (got !== img[i]) begin
                    $display("  FAIL load byte %0d: got %02h want %02h", i, got, img[i]);
                    errors++;
                end
            end
        end

        // The I/O port trace. Every out80() above was an I/O write, and the
        // glitch and the DMA cycle must not have counted.
        $display("  io ports = %04h %04h %04h %04h  N %0d",
                 io_port_hist[15:0], io_port_hist[31:16],
                 io_port_hist[47:32], io_port_hist[63:48], io_wr_count);
        if (io_port_hist[15:0] !== 16'h0080) begin
            $display("  FAIL newest I/O port is not 0080"); errors++;
        end
        // Eleven writes: six out80, four more after the freeze, and the glitch
        // -- which went to its real port. The DMA cycle is not among them.
        if (io_wr_count !== 16'd11) begin
            $display("  FAIL io write count %0d, want 11", io_wr_count); errors++;
        end

        // ---------------------------------------------- the 128KB instruments
        //
        // MSW/SZ/F0 on the POST panel exist to say why MEMORY stops at 128KB,
        // so they have to be right about a bus that settles late -- the same
        // hazard out80 and rom_read were written for. A3FEA must come back as
        // the byte on bus_data at the END of the read, [0501] as cpu_data at
        // the end of the write, and F0 must count one per OUT, not one per
        // cycle the strobe is held.
        mem_read_val(20'hA3FEA, 8'hC3, 8'h04);
        if (u_dut.memsw_seen !== 8'h04) begin
            $display("  FAIL MSW = %02h (want 04)", u_dut.memsw_seen); errors++;
        end
        mem_read_val(20'hA3FEB, 8'h00, 8'h99);   // the neighbour must not count
        if (u_dut.memsw_seen !== 8'h04) begin
            $display("  FAIL MSW moved on A3FEB: %02h", u_dut.memsw_seen); errors++;
        end
        mem_write(20'h00501, 8'h04);
        if (u_dut.memsize_seen !== 8'h04) begin
            $display("  FAIL SZ = %02h (want 04)", u_dut.memsize_seen); errors++;
        end
        out_port(16'h00F0, 8'h07);
        out_port(16'h00F0, 8'h00);
        out_port(16'h0037, 8'h0E);               // not 0F0, must not count
        if (u_dut.f0_count !== 8'd2) begin
            $display("  FAIL F0 = %0d (want 2)", u_dut.f0_count); errors++;
        end
        $display("  128KB instruments: MSW %02h  SZ %02h  F0 %0d",
                 u_dut.memsw_seen, u_dut.memsize_seen, u_dut.f0_count);

        // ---------------------------------------------- the FDC vector watches
        //
        // IVT13/IVT12 exist to say whether the BIOS installed the drive
        // handlers before the probe's interrupt fired. Pin the same shape as
        // ivt16: the four bytes land in the right lanes, the neighbour
        // vector does not leak, and a later overwrite replaces the value.
        mem_write(20'h0004C, 8'hF6);             // INT 13h offset lo
        mem_write(20'h0004D, 8'hFA);             // offset hi
        mem_write(20'h0004E, 8'h00);             // segment lo
        mem_write(20'h0004F, 8'hF0);             // segment hi
        if (u_dut.ivt13_off !== 16'hFAF6 || u_dut.ivt13_seg !== 16'hF000) begin
            $display("  FAIL IVT13 = %04h:%04h (want F000:FAF6)",
                     u_dut.ivt13_seg, u_dut.ivt13_off); errors++;
        end
        mem_write(20'h00048, 8'hF7);             // INT 12h
        mem_write(20'h00049, 8'hFA);
        mem_write(20'h0004A, 8'h00);
        mem_write(20'h0004B, 8'hF0);
        if (u_dut.ivt12_off !== 16'hFAF7 || u_dut.ivt12_seg !== 16'hF000) begin
            $display("  FAIL IVT12 = %04h:%04h (want F000:FAF7)",
                     u_dut.ivt12_seg, u_dut.ivt12_off); errors++;
        end
        // A neighbour's write must not leak into the watched slots.
        mem_write(20'h00047, 8'hED);
        mem_write(20'h00050, 8'hDC);
        if (u_dut.ivt12_off !== 16'hFAF7 || u_dut.ivt13_off !== 16'hFAF6) begin
            $display("  FAIL neighbour leaked into IVT12/13"); errors++;
        end
        // And a later install replaces, as the BIOS re-init would.
        mem_write(20'h0004D, 8'hB6);
        if (u_dut.ivt13_off !== 16'hB6F6) begin
            $display("  FAIL IVT13 did not update: %04h", u_dut.ivt13_off); errors++;
        end
        $display("  FDC vectors: V13 %04h:%04h  V12 %04h:%04h",
                 u_dut.ivt13_seg, u_dut.ivt13_off,
                 u_dut.ivt12_seg, u_dut.ivt12_off);

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
