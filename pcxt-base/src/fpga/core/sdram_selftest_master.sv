//
// sdram_selftest_master -- softcore-driven access to guest memory through
// CHIPSET's external-access port.
//
// Exists so the firmware can read and write guest SDRAM with the 8088 held in
// reset and report which address fails, instead of us inferring it from a POST
// beep count. See docs/P0_SELFTEST_SPEC.md.
//
// It borrows the port the BIOS loader uses, so the write direction is already
// proven on hardware; the read direction is the same port's memory_read_n_ext,
// which CHIPSET and BUS_ARBITER both implement symmetrically with the write mux
// and which core_top previously tied off.
//
// This lives in its own file rather than inline in core_top because core_top
// cannot be simulated -- CHIPSET pulls in Peripherals.sv, which this Verilator
// rejects -- and the first three hardware builds of the self-test showed
// nothing on screen precisely because this logic had never been through a
// testbench. A module with an interface can be.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module sdram_selftest_master #(
    // Cycles to wait for RAM.sv before giving up on an access. A stuck
    // controller must return a wrong answer we can read, never hang the
    // softcore. Also the normal path for addresses RAM.sv does not own --
    // CGA VRAM at 0xB0000-0xBFFFF never raises ram_rw_complete.
    parameter int GUARD = 200
) (
    input  wire        clk,              // clk_chipset
    input  wire        rst,

    // Request side, driven from the softcore's clk_pico domain. clk_pico is
    // clk_sys gated one-in-six and every clk_pico edge is a clk_sys edge, so
    // these are stable for a whole clk_pico period and need no synchroniser.
    input  wire        req,              // level, held until done
    input  wire        we,               // 1 = write, 0 = read
    input  wire [19:0] addr,
    input  wire  [7:0] wdata,
    output logic       done,             // level, held until req drops
    output logic [7:0] rdata,

    // Conditions under which the port may be taken.
    input  wire        initilized_sdram,
    input  wire        loader_busy,      // the BIOS loader always wins

    // CHIPSET external-access port.
    output logic       run,              // drives ext_access_request and the muxes
    output logic       write_n,
    output logic       read_n,
    input  wire        ram_rw_complete,
    input  wire  [7:0] ext_rdata
);

    typedef enum logic [1:0] { S_IDLE, S_ACCESS, S_DRAIN } state_t;
    state_t state;

    logic [15:0] guard;
    wire         grant = req & ~loader_busy;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state   <= S_IDLE;
            run     <= 1'b0;
            write_n <= 1'b1;
            read_n  <= 1'b1;
            done    <= 1'b0;
            rdata   <= 8'h00;
            guard   <= 16'd0;
        end else begin
            case (state)

            S_IDLE: begin
                run     <= 1'b0;
                write_n <= 1'b1;
                read_n  <= 1'b1;
                done    <= 1'b0;
                if (grant && initilized_sdram) begin
                    run     <= 1'b1;
                    write_n <= ~we;
                    read_n  <=  we;
                    guard   <= 16'd0;
                    state   <= S_ACCESS;
                end
            end

            // Hold the command until RAM.sv reports the access finished, or the
            // guard expires.
            S_ACCESS: begin
                guard <= guard + 16'd1;
                if (ram_rw_complete || (guard == 16'(GUARD))) begin
                    rdata   <= we ? 8'h00 : ext_rdata;
                    write_n <= 1'b1;
                    read_n  <= 1'b1;
                    done    <= 1'b1;
                    state   <= S_DRAIN;
                end
            end

            // Drop the bus, then wait for the requester to see done and lower
            // req, so one firmware write cannot launch two accesses.
            S_DRAIN: begin
                run <= 1'b0;
                if (~req) begin
                    done  <= 1'b0;
                    state <= S_IDLE;
                end
            end

            default: state <= S_IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire
