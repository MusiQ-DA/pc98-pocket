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
    output logic  [7:0] ivt16_wr_count
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
    logic mem_write_q;

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
            ivt16_off     <= 16'h0;
            ivt16_seg     <= 16'h0;
            ivt16_wr_count<= 8'd0;
            is_post_q     <= 1'b0;
            is_post_d     <= 1'b0;
            data_q        <= 8'h00;
            mem_addr_q    <= 20'h0;
        end else begin
            mem_write_q <= mem_write;
            if (mem_write && ~mem_write_q && in_ivt16) begin
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
