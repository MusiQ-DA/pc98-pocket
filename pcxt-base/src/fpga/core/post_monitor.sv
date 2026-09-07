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
    input  wire  [7:0] data_bus,
    input  wire        io_write_n,
    input  wire        memory_read_n,
    input  wire        memory_write_n,

    output logic [7:0] post_code,         // most recent write to port 0x80
    output logic [7:0] post_prev,         // the one before it
    output logic [DEPTH*8-1:0] post_hist, // FROZEN: the first DEPTH codes, oldest first
    output logic [19:0] last_mem_addr,    // memory address at the last recorded code
    output logic [15:0] post_count,       // how many codes have been seen, ever
    output logic [7:0] post_max,          // highest code seen
    output logic [15:0] restart_count     // times the guest went back to POST 00
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
    wire io_write = ~io_write_n;
    wire is_post  = io_write && (address[15:0] == 16'h0080);

    logic io_write_q;
    logic [19:0] mem_addr_q;

    logic [$clog2(DEPTH+1)-1:0] filled;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            post_code     <= 8'h00;
            post_prev     <= 8'h00;
            post_hist     <= '0;
            last_mem_addr <= 20'h0;
            post_count    <= 16'd0;
            post_max      <= 8'h00;
            restart_count <= 16'd0;
            filled        <= '0;
            io_write_q    <= 1'b0;
            mem_addr_q    <= 20'h0;
        end else begin
            io_write_q <= io_write;

            // Track the most recent MEMORY access, so the snapshot taken with a
            // POST code says where the guest was working.
            if (~memory_read_n || ~memory_write_n)
                mem_addr_q <= address;

            // Edge, so one bus cycle records one code however long it is held.
            if (is_post && ~io_write_q) begin
                // Always live: how much has happened, and how far it ever got.
                post_count <= post_count + 16'd1;
                if (data_bus > post_max) post_max <= data_bus;
                if (post_count != 16'd0 && data_bus == 8'h00)
                    restart_count <= restart_count + 16'd1;

                // Frozen after the first pass, so the screen can be read.
                if (filled != DEPTH[$clog2(DEPTH+1)-1:0]) begin
                    post_code     <= data_bus;
                    post_prev     <= post_code;
                    post_hist     <= {post_hist[(DEPTH-1)*8-1:0], data_bus};
                    last_mem_addr <= mem_addr_q;
                    filled        <= filled + 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
