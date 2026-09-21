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
// THE EGC SHAPES (np2kai mem/memegc.c, egc_writebyte/egc_readbyte). When the
// EGC is active it supersedes the GRCG's transform, and every access walks
// all four planes regardless of the GRCG's mask -- the EGC's own access
// register gates them:
//
//   write  read every plane (dst for the raster op, and the pattern
//          registers' load when ope 9:8 is 0b10), then write every plane
//          whose access bit is CLEAR: plane = (plane & ~mask) | (data & mask),
//          with data from pc98_egc's datapath.
//   read   read every plane (latching the source for the next write), and
//          answer with the plane fgbg 9:8 names, unless ope 0x2000 asks for
//          the raw plane -- the same byte, until the shift pipeline exists.
//
// THE ACCESS PAGE (port 0xA6 bit 0, np2kai's gdcs.access). Page one of the
// graphics RAM has no guest address -- the real machine rebanks the same
// windows -- so this module readdresses every plane access through
// pc98_gvram_plane1 and raises mem_page1, and RAM.sv banks the byte at
// 0x600000. Plain single-plane accesses take that path too when the page bit
// is set: a plain write with page one selected must NOT land in the page-zero
// window just because no charger is armed.
//
// PLANE E IS NOT WHERE THE OTHERS ARE. B, R and G are 0x8000 apart from
// A8000; E is at E0000, and it only exists in analog mode. Both facts live
// in pc98_sdram_map.svh so this module and RAM.sv cannot disagree about them.
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
    input  wire        mem_ready,

    // ---- the access page (port 0xA6 bit 0) -------------------------------
    // Rebanks every plane window between the two 640x400 pages, np2kai's
    // gdcs.access. When set, this module addresses planes through
    // pc98_gvram_plane1 and asserts mem_page1 so RAM.sv banks the byte at
    // 0x600000, past the guest's map and EMS alike.
    input  wire        access_page,
    output reg         mem_page1,

    // ---- the EGC ---------------------------------------------------------
    // Register writes decoded upstream (Peripherals, ports 0x4A0-0x4AF) and
    // forwarded here, where the engine that consumes them lives. egc_active
    // is mode2 bits 3 and 2 together (np2kai's VOPBIT_EGC gate, io/gdc.c
    // gdc_o6a: bit 3 arms the EGC-capable G-RCG, bit 2 switches the memory
    // layer onto the EGC path).
    input  wire        egc_active,
    input  wire        egc_wr,
    input  wire  [3:0] egc_rg,
    input  wire  [7:0] egc_d
);

`include "pc98_sdram_map.svh"

    // Which plane a plain access's own window names: A8000 B, B0000 R,
    // B8000 G, E0000 E. The three 0x8000-apart windows differ in address
    // bits 17:16 minus one; the E window is its own check.
    function automatic logic [1:0] own_plane(input logic [19:0] a);
        if (a[19:15] == 5'b11100)      own_plane = 2'd3;
        else if (a[19:15] == 5'b10101) own_plane = 2'd0;
        else if (a[15])                own_plane = 2'd2;
        else                           own_plane = 2'd1;
    endfunction

    // Claimed: a charger expands it, or the page bit banks even a plain one.
    wire window    = cpu_gvram & pc98_gvram_hits(cpu_addr, analog_mode);
    wire egc_here  = egc_active & window;
    wire grcg_here = ~egc_active & grcg_active & window;
    wire plain_pg1 = ~egc_active & ~grcg_active & window & access_page;
    wire expand    = egc_here | grcg_here | plain_pg1;
    wire [1:0] own = own_plane(cpu_addr);

    localparam [2:0] S_IDLE = 3'd0,
                     S_RD   = 3'd1,   // read this plane (RMW, or a TCR read)
                     S_RDW  = 3'd2,   // wait for it
                     S_WR   = 3'd3,   // write this plane
                     S_WRW  = 3'd4,   // wait for it
                     S_DONE = 3'd5;

    reg [2:0] st;
    reg [1:0] gp;             // which plane
    reg       is_read;        // this access is a read
    reg [7:0] tcr;            // the match mask being accumulated
    reg [7:0] rd_hold;        // what the last plane read gave
    reg [7:0] rdata_pass;     // the pass-through answer

    // The EGC engine's registers and datapath live one module down; the load
    // strobes and the plane walk are this FSM's business.
    wire [15:0] egc_access, egc_fgbg, egc_ope, egc_mask;
    wire [15:0] egc_fgc [0:3], egc_bgc [0:3], egc_patreg [0:3], egc_src [0:3];
    wire [7:0]  egc_op_data;
    reg         egc_pat_ld, egc_src_ld;
    reg  [1:0]  egc_ld_plane;
    reg         egc_ld_ext;

    pc98_egc u_egc (
        .clk(clk), .rst(reset),
        .wr(egc_wr), .rg(egc_rg), .d(egc_d),
        .access_r(egc_access), .fgbg_r(egc_fgbg), .ope_r(egc_ope),
        .mask_r(egc_mask), .sft_r(), .leng_r(),
        .fgc(egc_fgc), .bgc(egc_bgc),
        .pat_ld(egc_pat_ld), .pat_plane(egc_ld_plane),
        .pat_ext(egc_ld_ext), .pat_d(mem_rdata), .patreg(egc_patreg),
        .src_ld(egc_src_ld), .src_plane(egc_ld_plane),
        .src_ext(egc_ld_ext), .src_d(mem_rdata), .src_q(egc_src),
        .op_plane(gp), .op_ext(cpu_addr[0]),
        .op_dst(rd_hold), .op_val(cpu_wdata), .op_data(egc_op_data)
    );

    // Which plane an EGC read answers with, and the byte it gave.
    wire [1:0] egc_rd_plane = egc_fgbg[9:8];
    reg  [7:0] egc_rd_q;
    // The mask byte this write applies, np2kai's mask2: the mask register's
    // byte for THIS half of the word (egc_writebyte's ext). A zero byte
    // suppresses the plane's write entirely, as egc_writebyte's `if` does.
    wire [7:0] egc_mask_b = cpu_addr[0] ? egc_mask[15:8] : egc_mask[7:0];
    // The pattern registers load on a read when ope 9:8 is 0b01 and on a
    // write when 0b10 (egc_readbyte / egc_writebyte's ope & 0x0300 tests).
    wire egc_pat_on_rd = (egc_ope[9:8] == 2'b01);
    wire egc_pat_on_wr = (egc_ope[9:8] == 2'b10);

    // Plane liveness, split by phase:
    //   read  GRCG: the grcg mask (a TCR read skips masked planes); EGC: all
    //         of them, because the source latch and the pattern load want
    //         every byte; plane E needs analog either way.
    //   write GRCG: the mask; EGC: the access register's bit SET means the
    //         plane is not written, and a zero mask byte has nothing to
    //         write (egc_writebyte's `if`); plain: the window's own plane.
    function automatic logic rd_live_f(input logic [1:0] p);
        if (egc_here)
            rd_live_f = ((p != 2'd3) | analog_mode);
        else if (grcg_here)
            rd_live_f = ~grcg_mask[p] & ((p != 2'd3) | analog_mode);
        else
            rd_live_f = (p == own);
    endfunction

    function automatic logic wr_live_f(input logic [1:0] p);
        if (egc_here)
            wr_live_f = ((p != 2'd3) | analog_mode)
                       & ~egc_access[p] & (egc_mask_b != 8'h00);
        else if (grcg_here)
            wr_live_f = ~grcg_mask[p] & ((p != 2'd3) | analog_mode);
        else
            wr_live_f = (p == own);
    endfunction

    // Which planes the CURRENT PHASE touches: the read phase of an EGC write
    // still walks all four (the pattern load and the raster's dst each want
    // every byte); the write phase is where the access register and the mask
    // bite.
    wire       cur_live = (st == S_WR) ? wr_live_f(gp) : rd_live_f(gp);
    wire       last_gp  = (gp == 2'd3);
    wire [7:0] cur_tile = grcg_tile[gp];

    // Where this plane's byte lives, page banked when 0xA6 says so.
    function automatic logic [19:0] plane_addr(input logic [19:0] a,
                                               input logic [1:0] p);
        plane_addr = access_page ? {3'b000, pc98_gvram_plane1(a, p)}
                                 : pc98_gvram_plane(a, p);
    endfunction

    // The transform, per np2kai: TDW lays the tile down and discards the
    // guest's byte; RMW uses it as a mask between the tile and what is there;
    // the EGC masks the engine's byte into what is there; a plain access
    // writes the guest's byte unchanged.
    wire [7:0] wr_byte = egc_here
        ? ((rd_hold & ~egc_mask_b) | (egc_op_data & egc_mask_b))
        : grcg_here
            ? (grcg_rmw
                ? ((rd_hold & ~cpu_wdata) | (cpu_wdata & cur_tile))
                : cur_tile)
        : cpu_wdata;

    assign cpu_ready = expand ? (st == S_DONE) : mem_ready;

    // COMBINATIONAL, and it has to be. Assigning it inside the S_DONE arm did
    // not work: by the time S_DONE is the current state the guest has seen
    // cpu_ready and dropped its strobes, `expand` is false, and the arm never
    // runs. The guest samples while its own command is still up, which is
    // exactly when this mux is valid.
    assign cpu_rdata = (egc_here & is_read & (st == S_DONE)) ? egc_rd_q
                     : (grcg_here & is_read & (st == S_DONE)) ? ~tcr
                     : (plain_pg1 & is_read & (st == S_DONE)) ? rd_hold
                     : rdata_pass;

    always_ff @(posedge clk) begin
        if (reset) begin
            st        <= S_IDLE;
            gp        <= 2'd0;
            is_read   <= 1'b0;
            tcr       <= 8'h00;
            rd_hold   <= 8'h00;
            rdata_pass<= 8'h00;
            egc_rd_q  <= 8'h00;
            egc_pat_ld<= 1'b0;
            egc_src_ld<= 1'b0;
            egc_ld_plane <= 2'd0;
            egc_ld_ext   <= 1'b0;
            mem_addr  <= 20'h0;
            mem_wdata <= 8'h00;
            mem_rd    <= 1'b0;
            mem_wr    <= 1'b0;
            mem_page1 <= 1'b0;
        end else if (!expand) begin
            // Pass-through: the guest's own access, unchanged.
            mem_addr  <= cpu_addr;
            mem_wdata <= cpu_wdata;
            mem_rd    <= cpu_rd;
            mem_wr    <= cpu_wr;
            mem_page1 <= 1'b0;
            // ONLY WHILE A READ IS LIVE. Assigning this unconditionally
            // clobbered a TCR answer the moment the guest's strobes dropped
            // and `expand` went false -- the answer has to survive until the
            // guest has taken it, and the guest takes it while its own read
            // command is still up.
            if (cpu_rd) rdata_pass <= mem_rdata;
            st        <= S_IDLE;
            gp        <= 2'd0;
        end else begin
            // The EGC's load strobes are one cycle each: cleared by default,
            // set only by the cycle that has a byte in hand.
            egc_pat_ld <= 1'b0;
            egc_src_ld <= 1'b0;
            case (st)
              S_IDLE: begin
                mem_rd <= 1'b0;
                mem_wr <= 1'b0;
                if (cpu_rd | cpu_wr) begin
                    is_read <= cpu_rd;
                    // A plain page-one access walks exactly one plane: the
                    // one its window names, and no other.
                    gp      <= plain_pg1 ? own : 2'd0;
                    // A TCR read starts from all-match and clears bits; a
                    // write starts by reading only if RMW needs it. The EGC
                    // always reads first -- the raster op needs dst, and the
                    // pattern registers may be loading.
                    tcr     <= 8'h00;
                    st      <= (cpu_rd | grcg_rmw | egc_here) ? S_RD : S_WR;
                end
              end

              // ---- read this plane ------------------------------------
              S_RD: begin
                if (!cur_live) begin
                    // Masked, or plane E in digital mode: nothing to read and
                    // nothing to contribute to the match.
                    if (last_gp) st <= S_DONE;
                    else begin gp <= gp + 2'd1; st <= S_RD; end
                end else begin
                    mem_addr  <= plane_addr(cpu_addr, gp);
                    mem_page1 <= access_page;
                    mem_rd    <= 1'b1;
                    st        <= S_RDW;
                end
              end

              S_RDW: if (mem_done) begin
                mem_rd  <= 1'b0;
                rd_hold <= mem_rdata;
                if (egc_here) begin
                    // The source latch takes every EGC read's plane bytes
                    // (egc_readbyte's shift input -- aligned pipeline, so
                    // what goes in is what comes out). The pattern registers
                    // take them when ope asks, on either direction.
                    egc_src_ld  <= is_read;
                    egc_pat_ld  <= is_read ? egc_pat_on_rd : egc_pat_on_wr;
                    egc_ld_plane<= gp;
                    egc_ld_ext  <= cpu_addr[0];
                    if (is_read & (gp == egc_rd_plane))
                        egc_rd_q <= mem_rdata;
                end else if (is_read) begin
                    // A GRCG read accumulates the match mask.
                    tcr <= tcr | (mem_rdata ^ cur_tile);
                end
                if (is_read) begin
                    if (last_gp) st <= S_DONE;
                    else begin gp <= gp + 2'd1; st <= S_RD; end
                end else
                    st <= S_WR;
              end

              // ---- write this plane -----------------------------------
              S_WR: begin
                if (!cur_live) begin
                    if (last_gp) st <= S_DONE;
                    else begin
                        gp <= gp + 2'd1;
                        st <= grcg_rmw | egc_here ? S_RD : S_WR;
                    end
                end else begin
                    mem_addr  <= plane_addr(cpu_addr, gp);
                    mem_page1 <= access_page;
                    mem_wdata <= wr_byte;
                    mem_wr    <= 1'b1;
                    st        <= S_WRW;
                end
              end

              S_WRW: if (mem_done) begin
                mem_wr <= 1'b0;
                if (last_gp) st <= S_DONE;
                else begin
                    gp <= gp + 2'd1;
                    st <= grcg_rmw | egc_here ? S_RD : S_WR;
                end
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
