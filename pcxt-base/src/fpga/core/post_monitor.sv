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
    // Diagnostics for the snoop itself. NW came back 0 on hardware, so one of
    // the terms in the filter is wrong; counting them separately says which,
    // instead of another round of guessing.
    // Counted separately because WR came back 0 while LIVE, which is driven by
    // (~memory_read_n | ~memory_write_n), was clearly moving. Either writes
    // really never assert -- impossible, the memory test writes 32 KB -- or my
    // counter is wrong. Three counters settle it without another guess.
    output logic [15:0] wr_any_count,     // memory WRITE strobes
    output logic [15:0] rd_any_count,     // memory READ strobes
    output logic [15:0] ivt_touch_count,  // any access with address in 0x58-0x5B
    output logic [19:0] wr_last_addr,     // address of the last memory write
    // The raw strobes, and how many cycles each spends asserted. Edge counting
    // came back 0 for reads AND writes while LIVE looked busy, and both facts
    // fit one explanation: the strobes sit LOW permanently, so mem_access is
    // always true (LIVE just follows the address bus) and no rising edge ever
    // happens. Levels cannot lie about that.
    output logic  [3:0] raw_strobes,       // {mem_rd_n, mem_wr_n, io_wr_n, aen_n}
    output logic [15:0] wr_low_cycles,     // cycles memory_write_n was low
    output logic [15:0] rd_low_cycles,     // cycles memory_read_n was low
    // What the CPU READ out of F000:D880-D883 -- the two words POST 05's movsw
    // copies into INT 16h's vector. Passive, like the write snoop: reading that
    // region with the self-test master came back 11 11 11 11 11 11 11 11, which
    // is not memory content, so the master's read of the BIOS region is broken
    // and only a bus snoop can be trusted here.
    output logic [31:0] rom_read_data,
    output logic  [7:0] rom_read_count
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
    logic mem_write_q, mem_write_q_raw, mem_read_q_raw;
    logic [1:0] rom_slot_q;
    logic [7:0] rom_byte_q;
    logic rom_hold_q;
    wire  in_rom_win = (address[19:2] == 18'h3F620);   // F000:D880-D883

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
            rom_read_data <= 32'd0;
            rom_read_count<= 8'd0;
            rom_slot_q    <= 2'd0;
            rom_byte_q    <= 8'd0;
            rom_hold_q    <= 1'b0;
            wr_last_addr  <= 20'd0;
            ivt16_off     <= 16'h0;
            ivt16_seg     <= 16'h0;
            ivt16_wr_count<= 8'd0;
            is_post_q     <= 1'b0;
            is_post_d     <= 1'b0;
            data_q        <= 8'h00;
            mem_addr_q    <= 20'h0;
        end else begin
            mem_write_q <= mem_write;
            if (~memory_write_n && ~mem_write_q_raw) begin
                if (wr_any_count != 16'hFFFF) wr_any_count <= wr_any_count + 16'd1;
                wr_last_addr <= address;
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
            if (~memory_read_n && in_rom_win) begin
                rom_slot_q <= address[1:0];
                rom_byte_q <= bus_data;
                rom_hold_q <= 1'b1;
            end
            if (memory_read_n && rom_hold_q) begin
                case (rom_slot_q)
                    2'd0: rom_read_data[7:0]   <= rom_byte_q;
                    2'd1: rom_read_data[15:8]  <= rom_byte_q;
                    2'd2: rom_read_data[23:16] <= rom_byte_q;
                    2'd3: rom_read_data[31:24] <= rom_byte_q;
                endcase
                if (rom_read_count != 8'hFF) rom_read_count <= rom_read_count + 8'd1;
                rom_hold_q <= 1'b0;
            end

            raw_strobes <= {memory_read_n, memory_write_n, io_write_n, address_enable_n};
            if (~memory_write_n && wr_low_cycles != 16'hFFFF)
                wr_low_cycles <= wr_low_cycles + 16'd1;
            if (~memory_read_n && rd_low_cycles != 16'hFFFF)
                rd_low_cycles <= rd_low_cycles + 16'd1;

            if (~memory_write_n && ~mem_write_q_raw && in_ivt16) begin
                case (address[1:0])
                    2'd0: ivt16_off[7:0]   <= cpu_data;
                    2'd1: ivt16_off[15:8]  <= cpu_data;
                    2'd2: ivt16_seg[7:0]   <= cpu_data;
                    2'd3: ivt16_seg[15:8]  <= cpu_data;
                endcase
                if (ivt16_wr_count != 8'hFF) ivt16_wr_count <= ivt16_wr_count + 8'd1;
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

endmodule

`default_nettype wire
