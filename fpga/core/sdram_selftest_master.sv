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
    // the graphics VRAM window at 0xB0000-0xBFFFF never raises
    // ram_rw_complete.
    parameter int GUARD = 200,
    // Clocks to keep the bus borrowed in hold_only mode (~46 ms at 43 MHz --
    // the same order as the whole BIOS verify walk).
    parameter int HOLD_LEN = 2_000_000
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

    // CHIPSET's address_enable_n, i.e. HLDA for this master. The command
    // strobes must wait for it: BUS_ARBITER needs up to two cpu_ce periods
    // after ext_access_request before its address mux selects address_ext, and
    // until then it still presents cpu_address while our memory_read_n_ext is
    // already low -- RAM.sv would latch the guest CPU's address (0, with the
    // guest held) and the read would return one fixed word for every address.
    // That is the "11 11 11 11 -- a constant, not memory" the PC/AT postmon
    // once read through this master, and it is a HOLD-protocol violation on
    // any 8088 bus: raise HOLD, wait for HLDA, then command.
    input  wire        bus_granted,

    // Strict mode for the JTAG verify walk: a guard-expired byte is garbage
    // folded into the checksums, so strict waits for a real HLDA forever and
    // retries a timed-out access (up to 15 times) instead of accepting it.
    input  wire        strict,

    // Bisect mode for the early-POST kill: request and take the bus like a
    // normal access, then simply sit on it for HOLD_LEN clocks without ever
    // asserting write_n/read_n, and report done. POST dying under this is
    // the bare freeze; surviving it means the walk's strobes do the damage.
    input  wire        hold_only,

    // CHIPSET external-access port.
    output logic       run,              // drives ext_access_request and the muxes
    output logic       write_n,
    output logic       read_n,
    input  wire        ram_rw_complete,
    input  wire  [7:0] ext_rdata
);

    typedef enum logic [1:0] { S_IDLE, S_GRANT, S_ACCESS, S_DRAIN } state_t;
    state_t state;

    logic [15:0] guard;
    logic [3:0]  retries;
    logic [7:0]  grant_stable;
    logic        saw_complete_low;
    logic [21:0] hold_cnt;
    wire         grant = req & ~loader_busy;
    // Strict mode only counts a completion once the line has been seen low
    // while our strobe is up -- a complete already high on entry belongs to
    // an older access and would fold that byte into our checksum.
    wire         complete_ok = strict ? (saw_complete_low & ram_rw_complete)
                                      : ram_rw_complete;

    // bus_granted must stay high this many clocks before a strict access
    // strobes. HLDA (address_enable_n) only updates at cpu_ce boundaries
    // (~9 clk), so a stale-high grant with a drop already queued is flushed
    // out by watching it for longer than one full cpu_ce period. Strict also
    // holds `run` across the whole requester sequence (see S_DRAIN), so once
    // the first grant lands the bus never returns to the CPU mid-walk -- the
    // ram_rw_complete line then cannot pulse for anyone else's access.
    localparam int GRANT_STABLE = 16;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state   <= S_IDLE;
            run     <= 1'b0;
            write_n <= 1'b1;
            read_n  <= 1'b1;
            done    <= 1'b0;
            rdata   <= 8'h00;
            guard   <= 16'd0;
            retries <= 4'd0;
            grant_stable <= 8'd0;
            saw_complete_low <= 1'b0;
            hold_cnt <= 22'd0;
        end else begin
            case (state)

            S_IDLE: begin
                if (!strict)
                    run <= 1'b0;
                // Strict keeps `run` up between accesses so the arbiter never
                // hands the address bus back to the CPU mid-walk. If the
                // requester went away for good, release the bus anyway or the
                // guest would starve.
                else if (!req) begin
                    guard <= guard + 16'd1;
                    if (guard == 16'(GUARD)) begin
                        run   <= 1'b0;
                        guard <= 16'd0;
                    end
                end else
                    guard <= 16'd0;
                write_n <= 1'b1;
                read_n  <= 1'b1;
                done    <= 1'b0;
                retries <= 4'd0;
                grant_stable <= 8'd0;
                saw_complete_low <= 1'b0;
                if (grant && initilized_sdram) begin
                    run     <= 1'b1;    // request the bus, commands still idle
                    guard   <= 16'd0;
                    state   <= S_GRANT;
                end
            end

            // HOLD is up; wait for HLDA before strobing. The guard is the
            // backstop for a build with no arbiter in front of this master:
            // after GUARD cycles the access is attempted anyway, which is
            // exactly what the old single-state behavior did.
            S_GRANT: begin
                guard <= guard + 16'd1;
                // Strict mode needs a grant that has provably settled: the
                // arbiter's HLDA (address_enable_n) only updates at cpu_ce
                // boundaries, so between back-to-back walk accesses it can
                // read high while a drop is already queued in the request
                // pipeline. Strobing then lands while the address mux has
                // already switched back to the guest CPU, and the read
                // returns whatever the CPU was fetching -- the non-repeatable
                // walk sums seen on hardware. A grant that stays high for
                // longer than one cpu_ce period cannot be in that window, and
                // once taken it cannot tear mid-access because HLDA is sticky
                // while ext_access_request stays up.
                // Count only cycles that are granted AND quiescent: a pending
                // ram_rw_complete is someone else's access still draining --
                // strobing through it lands our read on their byte. While the
                // bus is held (strict) no new guest access can be accepted, so
                // once this drains it stays drained.
                if (bus_granted && !ram_rw_complete)
                    grant_stable <= (grant_stable != 8'hFF) ? grant_stable + 8'd1
                                                            : grant_stable;
                else
                    grant_stable <= 8'd0;
                if (bus_granted && (!strict || grant_stable >= 8'(GRANT_STABLE))) begin
                    // hold_only takes the grant but never strobes: the bus
                    // stays borrowed for HOLD_LEN clocks, then done -- the
                    // pure-freeze half of the early-POST kill for bisecting.
                    write_n  <= hold_only ? 1'b1 : ~we;
                    read_n   <= hold_only ? 1'b1 :  we;
                    hold_cnt <= 22'd0;
                    guard    <= 16'd0;
                    state    <= S_ACCESS;
                end else if (!strict && (guard == 16'(GUARD))) begin
                    write_n <= ~we;
                    read_n  <=  we;
                    guard   <= 16'd0;
                    state   <= S_ACCESS;
                end else if (strict && (guard == 16'(GUARD)))
                    guard <= 16'd0;     // keep waiting for a settled grant
            end

            // Hold the command until RAM.sv reports the access finished, or the
            // guard expires. Strict retries the access a bounded number of
            // times rather than summing a byte that never really completed.
            // Strict also requires the complete line to have been LOW since
            // the strobe went up: a complete already high on entry belongs to
            // an older access and would fold that byte into our checksum.
            S_ACCESS: begin
                guard <= guard + 16'd1;
                if (hold_only) begin
                    hold_cnt <= hold_cnt + 22'd1;
                    if (hold_cnt == 22'(HOLD_LEN)) begin
                        rdata <= 8'h00;
                        done  <= 1'b1;
                        state <= S_DRAIN;
                    end
                end else begin
                if (~ram_rw_complete)
                    saw_complete_low <= 1'b1;
                if (complete_ok || (guard == 16'(GUARD))) begin
                    if (!complete_ok && strict && retries != 4'hF) begin
                        write_n <= 1'b1;
                        read_n  <= 1'b1;
                        retries <= retries + 4'd1;
                        guard   <= 16'd0;
                        saw_complete_low <= 1'b0;
                        state   <= S_GRANT;
                    end else begin
                        rdata   <= we ? 8'h00 : ext_rdata;
                        write_n <= 1'b1;
                        read_n  <= 1'b1;
                        done    <= 1'b1;
                        state   <= S_DRAIN;
                    end
                end
                end
            end

            // Drop the bus, then wait for the requester to see done and lower
            // req, so one firmware write cannot launch two accesses. Strict
            // keeps `run` up: releasing between walk bytes lets the arbiter
            // hand the bus to the CPU for a few clocks, whose access can then
            // complete inside our next access's window and get summed as ours.
            S_DRAIN: begin
                if (!strict)
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
