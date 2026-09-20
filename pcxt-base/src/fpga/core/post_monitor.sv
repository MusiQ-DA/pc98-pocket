//
// post_monitor -- watch the guest's POST progress port.
//
// The BIOS writes progress codes to I/O port 0x80 (27 sites in the shipped
// image). Latching them turns "it stops somewhere between two boot sounds"
// into "it stops at POST 04", which is the base 64 KB memory test at
// F000:E11A. See docs/HANDOVER.md 1.5.
//
// It also snapshots the last memory address the CPU touched before each POST
// code, because the code that fails that test is a lodsw loop -- so the address
// captured alongside POST 54 is within a few accesses of the byte that came
// back wrong.
//
// Purely observational: nothing here drives the guest.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module post_monitor #(
    parameter int DEPTH = 8              // how many POST codes to remember
) (
    input  wire        clk,
    input  wire        rst,

    // Guest bus, as CHIPSET presents it.
    input  wire [19:0] address,
    // The CPU's own write data, not the shared bus. CHIPSET's data_bus is a mux
    // whose source depends on who is driving, and testB17 recorded MAX 63 with
    // it -- a value the BIOS never writes to this port (a linear disassembly
    // shows every one of its writes is a constant: 01-12, 52, 54). Taking the
    // 8088's dout removes the ambiguity.
    input  wire  [7:0] cpu_data,
    // The shared data bus, which carries READ data back to the CPU. cpu_data is
    // the 8088's own output and only means anything on writes.
    input  wire  [7:0] bus_data,
    input  wire        io_write_n,
    // AEN. During a DMA cycle the bus carries a 20-bit MEMORY address while
    // IOW is asserted, so every memory address whose low 16 bits happen to be
    // 0x0080 looks like a write to the POST port -- and an XT refreshes RAM
    // through DMA channel 0 continuously, so it never stops. This is the same
    // qualifier Peripherals.sv puts on cga_mem_select, and leaving it out is
    // what produced MAX C0 and RESTARTS 13 on testB18.
    input  wire        address_enable_n,
    input  wire        memory_read_n,
    input  wire        memory_write_n,

    output logic [7:0] post_code,         // most recent write to port 0x80
    output logic [7:0] post_prev,         // the one before it
    output logic [DEPTH*8-1:0] post_hist, // FROZEN: the first DEPTH codes, oldest first
    output logic [19:0] last_mem_addr,    // memory address at the last recorded code
    // The V30's own register view, retired-instruction granularity. CS:IP
    // through here names the instruction the loop is stuck on when every
    // other witness is a RAM address.
    input  wire    [15:0] dbg_cs,
    input  wire    [15:0] dbg_ip,
    input  wire           dbg_first_pop,
    output logic   [15:0] live_cs,
    output logic   [15:0] live_ip,
    // The derail catch: the CS:IP of the LAST cycle before CS left the ROM
    // segments. Sampled every clock in hardware, so the exact site of the
    // jump into garbage survives even when the CPU is lost a cycle later.
    output logic   [15:0] derail_cs,
    output logic   [15:0] derail_ip,
    // The last EIGHT retired IPs while CS was still ROM, sampled every clock
    // (the retired IP changes only at the core's CE, so every instruction is
    // caught), frozen at the ROM-exit edge -- and the first non-ROM CS:IP,
    // the landing address of the derail itself.
    output logic   [15:0] ring_ip0, ring_ip1, ring_ip2, ring_ip3,
    output logic   [15:0] land_cs,  land_ip,
    // The last committed ROM-window reads: address and the byte that came
    // back. The ROM-copy scan verifies what the PEEK sees; this catches
    // what the FETCH actually got -- if the byte the CPU decoded at the
    // derail address is not the byte in the file, the fetch path corrupted
    // it, and the value is on the panel.
    output logic   [19:0] fr0_addr, fr1_addr,
    output logic   [7:0]  fr0_data, fr1_data,
    // LIVE, never frozen. The guest stops rather than restarting, so this
    // settles on whatever it is spinning in -- which is the one thing the
    // frozen snapshot cannot say. testB19 gave ADDR FE1DD, the prefetch at the
    // moment POST 08 was written, and that is simply where it was, not where it
    // ended up.
    output logic [19:0] live_mem_addr,
    output logic [19:0] live_mem_max,     // highest address touched, ever
    output logic [15:0] post_count,       // how many codes have been seen, ever
    output logic [7:0] post_max,          // highest code seen
    output logic [15:0] restart_count,    // times the guest went back to POST 00
    // What the guest WROTE to INT 16h's vector, caught on the bus as it went
    // past. Reading that vector back after the hang shows the aftermath: by
    // then the runaway CPU has been scribbling. This is the value at the moment
    // POST 05's install loop stored it.
    output logic [15:0] ivt16_off,
    output logic [15:0] ivt16_seg,
    output logic  [7:0] ivt16_wr_count,
    // The two FDC vectors, same treatment. The 2HD handler goes to INT 13h
    // (0x4C-0x4F) and the 2DD handler to INT 12h (0x48-0x4B); the drive
    // probe interrupts through them, and a machine that lands the CPU at
    // 0:0500 needs to say whether these were ever installed and what they
    // pointed at when the interrupt fired.
    output logic [15:0] ivt13_off,
    output logic [15:0] ivt13_seg,
    output logic [15:0] ivt12_off,
    output logic [15:0] ivt12_seg,
    // Diagnostics for the snoop itself. NW came back 0 on hardware, so one of
    // the terms in the filter is wrong; counting them separately says which,
    // instead of another round of guessing.
    // Counted separately because WR came back 0 while LIVE, which is driven by
    // (~memory_read_n | ~memory_write_n), was clearly moving. Either writes
    // really never assert -- impossible, the memory test writes 32 KB -- or my
    // counter is wrong. Three counters settle it without another guess.
    output logic [15:0] wr_any_count,     // memory WRITE strobes
    output logic [15:0] tvram_wr_count,   // writes into the text plane A0000-A3FFF
    output logic [15:0] rd_any_count,     // memory READ strobes
    output logic [15:0] ivt_touch_count,  // any access with address in 0x58-0x5B
    output logic [19:0] wr_last_addr,     // address of the last memory write
    output logic [19:0] tvram_last_addr,  // last write into the text plane
    // The first eight cells of row 0, snooped as the guest writes them:
    // codes at A0000 + 2n, attributes at A2000 + 2n. Passive -- the self-test
    // master cannot read the text VRAM at all (the arbiter raises
    // address_enable_n for its accesses and tvram_mem_select is qualified with
    // ~address_enable_n), and reaching for it froze the machine.
    output logic [63:0] tvram_row0_code,
    output logic [63:0] tvram_row0_attr,
    // The HIGH bytes of the same cells (A0000 + 2n + 1). A nonzero high byte
    // is the two-byte flag: the cell renders as kanji, which on this machine
    // is the difference between a letter and a solid block. The run#191
    // screen drew every letter through that path because the word writes
    // that should have cleared the highs never landed.
    output logic [63:0] tvram_row0_hi,
    // The raw strobes, and how many cycles each spends asserted. Edge counting
    // came back 0 for reads AND writes while LIVE looked busy, and both facts
    // fit one explanation: the strobes sit LOW permanently, so mem_access is
    // always true (LIVE just follows the address bus) and no rising edge ever
    // happens. Levels cannot lie about that.
    output logic  [3:0] raw_strobes,       // {mem_rd_n, mem_wr_n, io_wr_n, aen_n}
    output logic [15:0] wr_low_cycles,     // cycles memory_write_n was low
    output logic [15:0] rd_low_cycles,     // cycles memory_read_n was low

    // ---- the MEMORY 128KB question ---------------------------------------
    //
    // The ITF sizes RAM from ONE byte: A3FEA, the memory switch in text VRAM.
    // F8B58 reads it, ANDs 7, clamps to 4 and compares (n+1)*2 against the
    // 64 KB block count -- so 4 means 640 KB and 0 means it stops after the
    // first 128 KB block. pc98_tvram pre-seeds it to 4 and its unit bench
    // agrees; whether the GUEST sees the 4 is a different question and only
    // the machine can answer it. memsw_seen is the byte the guest actually
    // got, taken off bus_data (the read side) on the trailing edge.
    //
    // memsize_seen is what the ITF concluded: F8B91 does OR [0501],DH with DH
    // already halved and decremented, so 04 means 640 KB and 00 means 128 KB.
    //
    // f0_count is how many times the ITF has asked for a CPU reset (OUT 0F0h,
    // F9A2C/F9A32). One is normal -- that is how POST hands over, and the
    // boot chime belongs to it. More than one is the loop.
    output logic  [7:0] memsw_seen,
    output logic  [7:0] memsize_seen,
    output logic  [7:0] f0_count,
    // What the CPU READ out of F000:D880-D883 -- the two words POST 05's movsw
    // copies into INT 16h's vector. Passive, like the write snoop: reading that
    // region with the self-test master came back 11 11 11 11 11 11 11 11, which
    // is not memory content, so the master's read of the BIOS region is broken
    // and only a bus snoop can be trusted here.
    // Which 16 bytes the CPU-read snoop watches, as address[19:4].
    //
    // It was fixed at FFFF, and sixteen bytes was all of the guest's memory the
    // panel could ever see through the CPU's own eyes. That is how a fault that
    // spares the reset vector stayed invisible: the peek reads the ROM through
    // CHIPSET's external port and finds it intact, while the CPU reads the same
    // bytes through its own path and evidently does not. Now the firmware
    // points this anywhere, so the two paths can be compared at any address for
    // the cost of a file copy.
    input  wire   [15:0] rom_win,
    output logic [127:0] rom_read_data,
    output logic  [7:0] rom_read_count,
    // The BIOS LOADER's own write of the same sixteen bytes, taken straight
    // off core_top's loader FSM rather than decoded from the bus. Together
    // with rom_read_data this splits the one question left: run#102 showed the
    // CPU taking in 41 D6 where the image holds E8 D2, and either the loader
    // wrote the wrong bytes or the memory did not keep what it was given.
    input  wire  [19:0] ld_addr,
    input  wire   [7:0] ld_data,
    input  wire         ld_we_n,
    output logic [127:0] rom_load_data,
    output logic  [7:0] rom_load_count,
    // Which I/O PORTS the guest has written, newest first, and how many writes
    // there have been. On PC/AT the interesting port is 0x80 and the data is
    // the progress code; on PC-98 there is no such port and progress shows in
    // WHICH ports get touched -- the ITF's route to the ROM bank switch runs
    // through 0x0461 and then 0x043D, so seeing those in order says it got
    // there. Same two qualifiers as the POST decode: AEN, and two cycles of
    // stability so an address sweeping through a port on its way to another
    // one is not recorded as a write to it.
    output logic [63:0] io_port_hist,
    output logic [15:0] io_wr_count
);

    // The history FREEZES once it holds DEPTH codes.
    //
    // testB16 put a live readout on screen and the user reported the values
    // changing too fast to read -- which is itself the finding: port 0x80 is a
    // genuine progress port in this image (27 of its 28 write sites load AL
    // with a constant first), so a code that keeps moving means the guest is
    // going round and round rather than stopping. A live display cannot be read
    // in that state, so keep the FIRST pass through POST, which is the one that
    // says where it turns around, and let the counters show the looping.

    // Port 0x80 is decoded on the low 16 bits; the BIOS uses out 0x80,al.
    wire io_write   = ~io_write_n;
    wire mem_access = ~memory_read_n | ~memory_write_n;
    logic [7:0] memsw_q;
    logic       memsw_hold;
    logic       f0_wr_q, f0_wr_qq;
    wire f0_wr_any = ~io_write_n & ~address_enable_n & (address[15:0] == 16'h00F0);
    wire is_post    = io_write && ~address_enable_n
                               && (address[15:0] == 16'h0080);

    // Require the decode to hold for two cycles before believing it: the
    // address and command lines do not change together, so a transition through
    // 0x0080 on the way to another port would otherwise register as a write.
    logic io_write_q, is_post_q, is_post_d;
    wire  is_post_stable = is_post & is_post_d;
    logic [7:0]  data_q;
    logic [19:0] mem_addr_q;

    logic [$clog2(DEPTH+1)-1:0] filled;

    // Snoop guest writes to 0x58-0x5B. Purely passive -- it watches the same
    // bus the POST codes come from and never asks for it.
    wire mem_write = ~memory_write_n & ~address_enable_n;
    wire in_ivt16  = (address[19:2] == 18'h00016);   // 0x58..0x5B
    wire in_ivt13  = (address[19:2] == 18'h00013);   // 0x4C..0x4F
    wire in_ivt12  = (address[19:2] == 18'h00012);   // 0x48..0x4B
    logic mem_write_q, mem_write_q_raw, mem_read_q_raw;
    logic [7:0] tv_wr_data;
    logic [15:0] io_port_q;
    logic        io_wr_q, io_wr_qq;
    wire         io_wr_any = io_write & ~address_enable_n;

    logic [3:0] rom_slot_q;
    logic [7:0] rom_byte_q;
    logic rom_hold_q;
    // F000:D880-D88F. Four bytes was enough to prove the read is corrupt but
    // not to show its SHAPE: D880/D881 came back right and D882/D883 wrong,
    // which is one bad 16-bit word next to one good one. Sixteen bytes says
    // whether that alternates, runs, or is a single word.
    //
    // ~address_enable_n matters here for the same reason it does on the POST
    // port: the arbiter sets address_enable_n from hold_acknowledge, and
    // hold_request is (dma_hold_request | ext_access_request), so an EXT access
    // drives this very bus with AEN high. run#105 added six guest_peek reads of
    // this window and they landed in these slots -- N went 16 to 22 and the
    // first six bytes came back as the ext port's answer, not the CPU's,
    // destroying the measurement. This window is the CPU's alone.
`ifdef MACHINE_PC98
    // The reset vector and the fifteen bytes with it. On PC-98 this is the one
    // window that matters: a genuine ITF holds EA 00 00 00 F8 there (jump to
    // F800:0000, itself), and a genuine system BIOS holds EA 00 00 80 FD. Any
    // other content means the CPU is executing whatever happened to be in
    // memory, which is what "LIVE 07E83, stopped" looks like from outside.
    wire  in_rom_win = (address[19:4] == rom_win) & ~address_enable_n;
`else
    wire  in_rom_win = (address[19:4] == rom_win) & ~address_enable_n;
`endif

    // Moving the window starts a fresh capture: bytes taken at the old address
    // mixed with the new ones would read as corruption that is not there.
    logic [15:0] rom_win_q;

    // The loader writes each byte with the strobe held until the RAM controller
    // completes, so address and data are stable throughout and no edge games
    // are needed -- unlike the bus snoops, this one can just take what it sees.
`ifdef MACHINE_PC98
    // And what the LOADER put there, so the two halves separate the same way
    // they did for the PC/AT BIOS: LD right and RD wrong means the memory did
    // not keep it, LD wrong means it was never written.
    wire  in_ld_win  = (ld_addr[19:4] == 16'hFFFF) & ~ld_we_n;
`else
    wire  in_ld_win  = (ld_addr[19:4] == 16'hFD88) & ~ld_we_n;
`endif
    logic ld_seen_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            post_code     <= 8'h00;
            post_prev     <= 8'h00;
            post_hist     <= '0;
            last_mem_addr <= 20'h0;
            live_mem_addr <= 20'h0;
            live_mem_max  <= 20'h0;
            post_count    <= 16'd0;
            post_max      <= 8'h00;
            restart_count <= 16'd0;
            filled        <= '0;
            io_write_q    <= 1'b0;
            mem_write_q   <= 1'b0;
            mem_write_q_raw <= 1'b0;
            wr_any_count  <= 16'd0;
            rd_any_count  <= 16'd0;
            ivt_touch_count <= 16'd0;
            mem_read_q_raw <= 1'b0;
            raw_strobes   <= 4'hF;
            wr_low_cycles <= 16'd0;
            rd_low_cycles <= 16'd0;
            rom_read_data <= 128'd0;
            rom_win_q     <= 16'hFFFF;
            fr0_addr      <= 20'h00000; fr0_data <= 8'h00;
            fr1_addr      <= 20'h00000; fr1_data <= 8'h00;
            fr_hold_q     <= 1'b0;
            io_port_hist  <= 64'd0;
            io_wr_count   <= 16'd0;
            io_port_q     <= 16'd0;
            io_wr_q       <= 1'b0;
            io_wr_qq      <= 1'b0;
            memsw_seen    <= 8'h00;
            memsw_q       <= 8'h00;
            memsw_hold    <= 1'b0;
            memsize_seen  <= 8'h00;
            f0_count      <= 8'h00;
            f0_wr_q       <= 1'b0;
            f0_wr_qq      <= 1'b0;
            rom_load_data <= 128'd0;
            rom_load_count<= 8'd0;
            ld_seen_q     <= 1'b0;
            rom_read_count<= 8'd0;
            rom_slot_q    <= 2'd0;
            rom_byte_q    <= 8'd0;
            rom_hold_q    <= 1'b0;
            wr_last_addr  <= 20'd0;
            tvram_wr_count <= 16'd0;
            tvram_last_addr <= 20'd0;
            tvram_row0_code <= 64'd0;
            tvram_row0_attr <= 64'd0;
            tvram_row0_hi   <= 64'd0;
            tv_wr_data      <= 8'h00;
            ivt16_off     <= 16'h0;
            ivt16_seg     <= 16'h0;
            ivt16_wr_count<= 8'd0;
            ivt13_off     <= 16'h0;
            ivt13_seg     <= 16'h0;
            ivt12_off     <= 16'h0;
            ivt12_seg     <= 16'h0;
            is_post_q     <= 1'b0;
            is_post_d     <= 1'b0;
            data_q        <= 8'h00;
            mem_addr_q    <= 20'h0;
        end else begin
            mem_write_q <= mem_write;
            // Write data is guaranteed at the END of the cycle, so keep the
            // last value seen while the strobe is low and use it on the edge.
            if (~memory_write_n) tv_wr_data <= cpu_data;
            if (memory_write_n && mem_write_q_raw
                && address[19:15] == 5'b10100) begin
                if (~address[0] && ~address[14] && ~address[13]
                    && address[12:4] == 9'd0)
                    tvram_row0_code[address[3:1]*8 +: 8] <= tv_wr_data;
                if (~address[0] && ~address[14] &&  address[13]
                    && address[12:4] == 9'd0)
                    tvram_row0_attr[address[3:1]*8 +: 8] <= tv_wr_data;
                if (address[0] && ~address[14] && ~address[13]
                    && address[12:4] == 9'd0)
                    tvram_row0_hi[address[3:1]*8 +: 8] <= tv_wr_data;
            end
            if (~memory_write_n && ~mem_write_q_raw) begin
                if (wr_any_count != 16'hFFFF) wr_any_count <= wr_any_count + 16'd1;
                wr_last_addr <= address;
                // The text plane: did the BIOS ever put a character there?
                if (address[19:15] == 5'b10100 && !address[14]) begin
                    if (tvram_wr_count != 16'hFFFF) tvram_wr_count <= tvram_wr_count + 16'd1;
                    tvram_last_addr <= address;
                end
            end
            if (~memory_read_n && ~mem_read_q_raw)
                if (rd_any_count != 16'hFFFF) rd_any_count <= rd_any_count + 16'd1;
            if (in_ivt16 && (~memory_read_n || ~memory_write_n)
                         && ~(mem_read_q_raw | mem_write_q_raw))
                if (ivt_touch_count != 16'hFFFF)
                    ivt_touch_count <= ivt_touch_count + 16'd1;
            mem_write_q_raw <= ~memory_write_n;
            mem_read_q_raw  <= ~memory_read_n;

            // Snoop the CPU's read of the vector table entry.
            //
            // Read data is valid at the END of the cycle, not its start.
            // Latching on the LEADING edge returned 59 FC 2E FC where the image
            // holds F8 2E E8 D2 -- the whole thing shifted by one, 59 being the
            // byte fetched just before. Same mistake as the POST port, so: hold
            // the address and the bus while the read is active, and commit when
            // the strobe releases.
            rom_win_q <= rom_win;
            if (rom_win_q != rom_win) begin
                rom_read_data  <= 128'd0;
                rom_read_count <= 8'd0;
                rom_hold_q     <= 1'b0;
            end
            else if (~memory_read_n && in_rom_win) begin
                rom_slot_q <= address[3:0];
                rom_byte_q <= bus_data;
                rom_hold_q <= 1'b1;
            end
            if (memory_read_n && rom_hold_q) begin
                rom_read_data[{rom_slot_q, 3'd0} +: 8] <= rom_byte_q;
                if (rom_read_count != 8'hFF) rom_read_count <= rom_read_count + 8'd1;
                rom_hold_q <= 1'b0;
            end

            // The fetch ring: the last two reads the bus made in the ROM
            // ADDRESS RANGE (0xE0000-0xFFFFF). Latched WHILE the read cycle
            // is live -- address and data are both stable then -- and only
            // shifted once per cycle (the hold flag), so one bus read is
            // one ring entry. Once the CPU derails into RAM these stop
            // happening, and the ring freezes on the last ROM bytes the
            // CPU ever fetched.
            if (~memory_read_n && ~address_enable_n
                && address[19:17] == 3'b111 && ~fr_hold_q) begin
                fr1_addr <= fr0_addr;  fr1_data <= fr0_data;
                fr0_addr <= address;
                fr0_data <= bus_data;
                fr_hold_q <= 1'b1;
            end
            if (memory_read_n)
                fr_hold_q <= 1'b0;

            // Any I/O write, by port. Commit on the trailing edge, after two
            // cycles of the same decode -- a port number latched while the
            // address bus is still moving is the transient that produced POST
            // codes the BIOS never wrote.
            io_wr_q  <= io_wr_any;
            io_wr_qq <= io_wr_q;
            if (io_wr_any) io_port_q <= address[15:0];
            if (io_wr_q && io_wr_qq && ~io_wr_any) begin
                io_port_hist <= {io_port_hist[47:0], io_port_q};
                if (io_wr_count != 16'hFFFF) io_wr_count <= io_wr_count + 16'd1;
            end

            // A3FEA, held while the read strobe is low and committed on its
            // trailing edge -- the same shape as the ROM window above, and for
            // the same reason: the address bus is still moving at the start.
            if (~memory_read_n && ~address_enable_n && address == 20'hA3FEA) begin
                memsw_q    <= bus_data;
                memsw_hold <= 1'b1;
            end
            if (memory_read_n && memsw_hold) begin
                memsw_seen <= memsw_q;
                memsw_hold <= 1'b0;
            end

            // [0501]: the size the ITF settled on. cpu_data, because this is a
            // write.
            if (~memory_write_n && ~address_enable_n && address == 20'h00501)
                memsize_seen <= cpu_data;

            // OUT 0F0h, two-cycle qualified like io_port_hist.
            f0_wr_q  <= f0_wr_any;
            f0_wr_qq <= f0_wr_q;
            if (f0_wr_q && f0_wr_qq && ~f0_wr_any && f0_count != 8'hFF)
                f0_count <= f0_count + 8'd1;

            // One count per write, not one per cycle the strobe is held.
            ld_seen_q <= in_ld_win;
            if (in_ld_win) begin
                rom_load_data[{ld_addr[3:0], 3'd0} +: 8] <= ld_data;
                if (~ld_seen_q && rom_load_count != 8'hFF)
                    rom_load_count <= rom_load_count + 8'd1;
            end

            raw_strobes <= {memory_read_n, memory_write_n, io_write_n, address_enable_n};
            if (~memory_write_n && wr_low_cycles != 16'hFFFF)
                wr_low_cycles <= wr_low_cycles + 16'd1;
            if (~memory_read_n && rd_low_cycles != 16'hFFFF)
                rd_low_cycles <= rd_low_cycles + 16'd1;

            // Latch the lane on EVERY clock the write is active, not just its
            // opening edge: data settles mid-cycle on this bus, and the
            // first-cut opening-edge latch here kept the stale byte (the
            // bench writes C3 before the real value) -- the same trap the
            // POST-code path documents above.
            if (mem_write && in_ivt16) begin
                case (address[1:0])
                    2'd0: ivt16_off[7:0]   <= cpu_data;
                    2'd1: ivt16_off[15:8]  <= cpu_data;
                    2'd2: ivt16_seg[7:0]   <= cpu_data;
                    2'd3: ivt16_seg[15:8]  <= cpu_data;
                endcase
            end
            // One count per write, not one per clock the strobe is held.
            if (mem_write && ~mem_write_q && in_ivt16
                                         && ivt16_wr_count != 8'hFF)
                ivt16_wr_count <= ivt16_wr_count + 8'd1;

            // The FDC vectors, same shape: keep the last byte seen while the
            // write is in flight.
            if (mem_write && in_ivt13) begin
                case (address[1:0])
                    2'd0: ivt13_off[7:0]   <= cpu_data;
                    2'd1: ivt13_off[15:8]  <= cpu_data;
                    2'd2: ivt13_seg[7:0]   <= cpu_data;
                    2'd3: ivt13_seg[15:8]  <= cpu_data;
                endcase
            end
            if (mem_write && in_ivt12) begin
                case (address[1:0])
                    2'd0: ivt12_off[7:0]   <= cpu_data;
                    2'd1: ivt12_off[15:8]  <= cpu_data;
                    2'd2: ivt12_seg[7:0]   <= cpu_data;
                    2'd3: ivt12_seg[15:8]  <= cpu_data;
                endcase
            end

            io_write_q <= io_write;
            is_post_d  <= is_post;
            is_post_q  <= is_post_stable;
            // Write data is valid throughout the command and guaranteed at its
            // END; sample it continuously while the cycle is active and use the
            // last value. testB16 latched on the LEADING edge instead and
            // returned garbage -- FF 53 74 C3 6F where the BIOS only ever
            // writes 00-12, 21-25, 30-32, 40-43, 52, 54, 55.
            if (is_post_stable) data_q <= cpu_data;

            // Track the most recent MEMORY access, so the snapshot taken with a
            // POST code says where the guest was working. Qualified with "not
            // an I/O cycle", or the port number itself lands here -- testB16
            // reported ADDR 00080, which is the port, not a memory address.
            if (mem_access && ~io_write) begin
                mem_addr_q    <= address;
                live_mem_addr <= address;
                if (address > live_mem_max) live_mem_max <= address;
            end

            // Record at the END of the write cycle, when the data is settled.
            if (is_post_q && ~is_post_stable) begin
                // Always live: how much has happened, and how far it ever got.
                post_count <= post_count + 16'd1;
                if (data_q > post_max) post_max <= data_q;
                if (post_count != 16'd0 && data_q == 8'h00)
                    restart_count <= restart_count + 16'd1;

                // Frozen after the first pass, so the screen can be read.
                if (filled != DEPTH[$clog2(DEPTH+1)-1:0]) begin
                    post_code     <= data_q;
                    post_prev     <= post_code;
                    post_hist     <= {post_hist[(DEPTH-1)*8-1:0], data_q};
                    last_mem_addr <= mem_addr_q;
                    filled        <= filled + 1'b1;
                end
            end
        end
    end

    wire is_rom_cs = (dbg_cs == 16'hFD80) || (dbg_cs == 16'hE800)
                   || (dbg_cs >= 16'hF000 && dbg_cs <= 16'hF880);

    logic        rom_prev;
    logic [15:0] cs_q, ip_q;
    logic        ring_frozen;
    logic        fr_hold_q;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            live_cs   <= 16'h0000;
            live_ip   <= 16'h0000;
            derail_cs <= 16'h0000;
            derail_ip <= 16'h0000;
            rom_prev  <= 1'b0;
            cs_q      <= 16'h0000;
            ip_q      <= 16'h0000;
            ring_frozen <= 1'b0;
            ring_ip0 <= 16'h0000; ring_ip1 <= 16'h0000;
            ring_ip2 <= 16'h0000; ring_ip3 <= 16'h0000;
            land_cs  <= 16'h0000; land_ip  <= 16'h0000;
        end else begin
            live_cs <= dbg_cs;
            live_ip <= dbg_ip;
            cs_q    <= dbg_cs;
            ip_q    <= dbg_ip;
            rom_prev <= is_rom_cs;
            // The edge: this cycle's CS is NOT ROM, last cycle's WAS --
            // the CPU just jumped out. cs_q/ip_q hold where it came from.
            if (rom_prev && !is_rom_cs) begin
                derail_cs <= cs_q;
                derail_ip <= ip_q;
            end
            if (rom_prev && !is_rom_cs) begin
                land_cs  <= dbg_cs;
                land_ip  <= dbg_ip;
                ring_frozen <= 1'b1;
            end
            // Strobed on first_pop: one entry per instruction the EU
            // actually began -- retire-true, not prefetch noise. dbg_ip at
            // the strobe is the instruction's own IP.
            if (is_rom_cs && !ring_frozen && dbg_first_pop) begin
                ring_ip3 <= ring_ip2;
                ring_ip2 <= ring_ip1;
                ring_ip1 <= ring_ip0;
                ring_ip0 <= dbg_ip;
            end
        end
    end

endmodule

`default_nettype wire
