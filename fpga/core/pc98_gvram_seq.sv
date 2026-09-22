//
// pc98_gvram_seq -- one CPU access to graphics VRAM, several to memory.
//
// The GRCG's arithmetic is pc98_grcg's. This is the part that costs time: a
// single guest write to A8000, B0000, B8000 or E0000 has to reach EVERY
// unmasked plane, and in RMW mode each plane must be READ before it is
// written. One CPU bus cycle becomes up to four memory accesses, or eight.
//
// WHY A SEQUENCER AND NOT A CHANGE TO RAM.sv. RAM.sv is the proven path --
// it is what boots the machine, and its ready handshake was the subject of a
// bug found only today. Wrapping it keeps the expansion out of it: this drives
// RAM.sv's own one-byte interface repeatedly and holds the guest off with
// cpu_ready until the last one lands, which is exactly what RAM.sv already
// does for a single access, one level up.
//
// PASS-THROUGH IS THE DEFAULT. With the GRCG off, or for an address that is
// not a graphics window, the request goes straight out and the answer straight
// back -- one access, no state. A machine that never turns the GRCG on behaves
// as if this module were not here, which is what makes it safe to add before
// anything uses it.
//
// THE THREE SHAPES (np2kai mem/memvram.c):
//
//   write, TDW  one write per unmasked plane, of that plane's tile. The byte
//               the guest wrote is discarded.
//   write, RMW  one read and one write per unmasked plane:
//               plane = (plane & ~data) | (data & tile)
//   read        one read per unmasked plane, and the answer is the TCR mask:
//               a bit is 1 where EVERY unmasked plane matches its tile bit.
//
// PLANE E IS NOT WHERE THE OTHERS ARE. B, R and G are 0x8000 apart from
// A8000; E is at E0000, and it only exists in analog mode. Both facts live in
// pc98_sdram_map.svh so this module and RAM.sv cannot disagree about them.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_gvram_seq (
    input  wire        clk,
    input  wire        reset,

    // ---- the guest's access ---------------------------------------------
    input  wire        cpu_gvram,        // the address is a graphics window
    input  wire        cpu_rd,           // level, as the 8288's commands are
    input  wire        cpu_wr,
    input  wire [19:0] cpu_addr,
    input  wire [7:0]  cpu_wdata,
    output wire [7:0]  cpu_rdata,
    output wire        cpu_ready,

    // ---- the GRCG's registers -------------------------------------------
    input  wire        grcg_active,
    input  wire        grcg_rmw,
    input  wire [3:0]  grcg_mask,        // 1 = skip this plane
    input  wire [7:0]  grcg_tile [0:3],
    input  wire        analog_mode,

    // ---- RAM.sv's one-byte interface ------------------------------------
    output reg  [19:0] mem_addr,
    output reg  [7:0]  mem_wdata,
    output reg         mem_rd,
    output reg         mem_wr,
    input  wire [7:0]  mem_rdata,
    input  wire        mem_done,         // RAM.sv's access_complete
    // RAM.sv's memory_access_ready, which is NOT access_complete: it is 1
    // whenever no selected access is in flight, which is the semantics the
    // guest's READY has always had. Pass-through must hand that through
    // unchanged or every non-graphics access in the machine changes shape.
    input  wire        mem_ready
);

`include "pc98_sdram_map.svh"

    // Expanded only when the GRCG is on AND this is a graphics window. Held
    // as a wire so the pass-through case never enters the state machine.
    wire expand = grcg_active & cpu_gvram
                & pc98_gvram_hits(cpu_addr, analog_mode);

    localparam [2:0] S_IDLE = 3'd0,
                     S_RD   = 3'd1,   // read this plane (RMW, or a TCR read)
                     S_RDW  = 3'd2,   // wait for it
                     S_WR   = 3'd3,   // write this plane
                     S_WRW  = 3'd4,   // wait for it
                     S_DONE = 3'd5;

    reg [2:0] st;
    reg [1:0] gp;             // which plane
    reg       is_read;        // this access is a read (TCR)
    reg [7:0] tcr;            // the match mask being accumulated
    reg [7:0] rd_hold;        // what the last plane read gave
    reg [7:0] rdata_pass;     // the pass-through answer

    // The next unmasked plane at or after p, and whether there is one. Plane 3
    // does not exist at all in digital mode.
    function automatic logic plane_live(input logic [1:0] p);
        plane_live = ~grcg_mask[p] & ((p != 2'd3) | analog_mode);
    endfunction

    wire       cur_live  = plane_live(gp);
    wire       last_gp   = (gp == 2'd3);
    wire [7:0] cur_tile  = grcg_tile[gp];

    // The transform, per np2kai: TDW lays the tile down and discards the
    // guest's byte; RMW uses it as a mask between the tile and what is there.
    wire [7:0] wr_byte = grcg_rmw
        ? ((rd_hold & ~cpu_wdata) | (cpu_wdata & cur_tile))
        : cur_tile;

    assign cpu_ready = expand ? (st == S_DONE) : mem_ready;

    // COMBINATIONAL, and it has to be. Assigning it inside the S_DONE arm did
    // not work: by the time S_DONE is the current state the guest has seen
    // cpu_ready and dropped its strobes, `expand` is false, and the arm never
    // runs. The guest samples while its own command is still up, which is
    // exactly when this mux is valid.
    assign cpu_rdata = (expand & is_read & (st == S_DONE)) ? ~tcr : rdata_pass;

    always_ff @(posedge clk) begin
        if (reset) begin
            st        <= S_IDLE;
            gp        <= 2'd0;
            is_read   <= 1'b0;
            tcr       <= 8'h00;
            rd_hold    <= 8'h00;
            rdata_pass <= 8'h00;
            mem_addr  <= 20'h0;
            mem_wdata <= 8'h00;
            mem_rd    <= 1'b0;
            mem_wr    <= 1'b0;
        end else if (!expand) begin
            // Pass-through: the guest's own access, unchanged.
            mem_addr  <= cpu_addr;
            mem_wdata <= cpu_wdata;
            mem_rd    <= cpu_rd;
            mem_wr    <= cpu_wr;
            // ONLY WHILE A READ IS LIVE. Assigning this unconditionally
            // clobbered a TCR answer the moment the guest's strobes dropped
            // and `expand` went false -- the answer has to survive until the
            // guest has taken it, and the guest takes it while its own read
            // command is still up.
            if (cpu_rd) rdata_pass <= mem_rdata;
            st        <= S_IDLE;
            gp        <= 2'd0;
        end else begin
            case (st)
              S_IDLE: begin
                mem_rd <= 1'b0;
                mem_wr <= 1'b0;
                if (cpu_rd | cpu_wr) begin
                    is_read <= cpu_rd;
                    gp      <= 2'd0;
                    // A TCR read starts from all-match and clears bits; a
                    // write starts by reading only if RMW needs it.
                    tcr     <= 8'h00;
                    st      <= (cpu_rd | grcg_rmw) ? S_RD : S_WR;
                end
              end

              // ---- read this plane ------------------------------------
              S_RD: begin
                if (!cur_live) begin
                    // Masked, or plane E in digital mode: nothing to read and
                    // nothing to contribute to the match.
                    st <= is_read ? (last_gp ? S_DONE : S_RD)
                                  : (last_gp ? S_DONE : S_RD);
                    if (!last_gp) gp <= gp + 2'd1;
                end else begin
                    mem_addr <= pc98_gvram_plane(cpu_addr, gp);
                    mem_rd   <= 1'b1;
                    st       <= S_RDW;
                end
              end

              S_RDW: if (mem_done) begin
                mem_rd  <= 1'b0;
                rd_hold <= mem_rdata;
                // A read accumulates the match mask; a write goes on to use
                // what it just read.
                if (is_read) begin
                    tcr <= tcr | (mem_rdata ^ cur_tile);
                    if (last_gp) st <= S_DONE;
                    else begin gp <= gp + 2'd1; st <= S_RD; end
                end else
                    st <= S_WR;
              end

              // ---- write this plane -----------------------------------
              S_WR: begin
                if (!cur_live) begin
                    if (last_gp) st <= S_DONE;
                    else begin gp <= gp + 2'd1; st <= grcg_rmw ? S_RD : S_WR; end
                end else begin
                    mem_addr  <= pc98_gvram_plane(cpu_addr, gp);
                    mem_wdata <= wr_byte;
                    mem_wr    <= 1'b1;
                    st        <= S_WRW;
                end
              end

              S_WRW: if (mem_done) begin
                mem_wr <= 1'b0;
                if (last_gp) st <= S_DONE;
                else begin gp <= gp + 2'd1; st <= grcg_rmw ? S_RD : S_WR; end
              end

              // ---- the answer -----------------------------------------
              S_DONE: begin
                // The answer itself is the mux above -- TCR returns the
                // INVERSE, a bit set where every unmasked plane matched, and
                // with every plane masked nothing differs and it is 0xFF,
                // which is np2kai's behaviour too.
                if (!(cpu_rd | cpu_wr)) st <= S_IDLE;
              end

              default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
