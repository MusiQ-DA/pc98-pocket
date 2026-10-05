/*
 *  Wishbone master interface module for Zet
 *  Copyright (C) 2010  Zeus Gomez Marmolejo <zeus@aluzina.org>
 *
 *  This file is part of the Zet processor. This processor is free
 *  hardware; you can redistribute it and/or modify it under the terms of
 *  the GNU General Public License as published by the Free Software
 *  Foundation; either version 3, or (at your option) any later version.
 *
 *  Zet is distrubuted in the hope that it will be useful, but WITHOUT
 *  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 *  or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
 *  License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with Zet; see the file COPYING. If not, see
 *  <http://www.gnu.org/licenses/>.
 */

module zet_wb_master (
    input             cpu_byte_o,
    input             cpu_memop,
    input             cpu_m_io,
    input             cpu_fetch,   // request is part of the instruction stream
    input      [19:0] cpu_adr_o,
    input      [19:0] pc,          // next fetch address during execute
    output reg        cpu_block,
    output reg [15:0] cpu_dat_i,
    input      [15:0] cpu_dat_o,
    input             cpu_we_o,

    input             wb_clk_i,
    input             wb_rst_i,
    input      [15:0] wb_dat_i,
    output reg [15:0] wb_dat_o,
    output reg [19:1] wb_adr_o,
    output            wb_we_o,
    output            wb_tga_o,
    output reg [ 1:0] wb_sel_o,
    output reg        wb_stb_o,
    output            wb_cyc_o,
    input             wb_ack_i
  );

  // Register and nets declarations
  reg  [ 2:0] cs; // current state
  reg  [ 2:0] ns; // next state
  reg  [19:1] adr1; // next address (for unaligned acc)
  reg  [ 2:0] idle_cnt; // consecutive bus-idle clocks

  wire        op; // in an operation
  wire        odd_word; // unaligned word
  wire        a0;  // address 0 pin
  wire [15:0] blw; // low byte (sign extended)
  wire [15:0] bhw; // high byte (sign extended)
  wire [ 1:0] sel_o; // bus byte select

  // Instruction fetch window: every instruction byte used to cost one full
  // bus transaction.  Two word slots are kept instead -- the aligned word
  // currently feeding fetches (cur) and the following word (nxt), which is
  // prefetched whenever the bus sits idle while the CPU executes.  A fetch
  // that lands inside the window completes without a Wishbone cycle.
  reg  [19:1] cur_addr, nxt_addr;
  reg  [15:0] cur_dat,  nxt_dat;
  reg         cur_v,    nxt_v;
  reg  [19:1] pf_adr;             // latched prefetch target
  reg         pf_iscur;           // prefetch lands in cur (window restart)

  // Declare the symbolic names for states
  localparam [2:0]
    IDLE    = 3'd0,
    stb1_hi = 3'd1,
    stb2_hi = 3'd2,
    bloc_lo = 3'd3,
    hit_st  = 3'd4,
    pf_stb  = 3'd5,
    pf_blk  = 3'd6;

  // Assignments
  assign op        = (cpu_memop | cpu_m_io);
  assign odd_word  = (cpu_adr_o[0] & !cpu_byte_o);
  assign a0        = cpu_adr_o[0];
  assign blw       = { {8{wb_dat_i[7]}}, wb_dat_i[7:0] };
  assign bhw       = { {8{wb_dat_i[15]}}, wb_dat_i[15:8] };
  assign wb_cyc_o  = wb_stb_o;

  // prefetch bus cycles are reads: keep we/tga clear while they own the bus
  wire pf_bus = (cs == pf_stb) | (cs == pf_blk);
  assign wb_we_o   = cpu_we_o & ~pf_bus;
  assign wb_tga_o  = cpu_m_io & ~pf_bus;

  // fetch-stream read hitting the buffered window; word accesses only hit
  // when even-aligned
  wire fetch_rd = cpu_fetch & cpu_memop & ~cpu_m_io & ~cpu_we_o;
  wire hit_cur  = fetch_rd & cur_v & (cpu_adr_o[19:1] == cur_addr)
                & (cpu_byte_o | ~a0);
  wire hit_nxt  = fetch_rd & nxt_v & (cpu_adr_o[19:1] == nxt_addr)
                & (cpu_byte_o | ~a0);
  wire hit      = (cs == IDLE) & op & (hit_cur | hit_nxt);
  wire [15:0] hitw = hit_cur ? cur_dat : nxt_dat;

  // a fetch read at an even address that misses pulls the whole aligned
  // word; the sibling byte then serves the next fetch for free
  wire fillw = fetch_rd & ~a0;
  assign sel_o = a0 ? 2'b10
                    : (cpu_byte_o & ~fetch_rd) ? 2'b01 : 2'b11;

  // prefetch whenever the bus has been idle a couple of clocks and a window
  // slot is free: nxt holds cur+1 while the window lives; once it is empty
  // (branch landed, write flushed it) cur is re-seeded from pc's word so the
  // next fetch stream resumes ahead of itself
  wire pf_go = (cs == IDLE) & ~op & (~cur_v | ~nxt_v) & (idle_cnt >= 3'd1);
  wire [19:1] pf_targ = cur_v ? (cur_addr + 19'd1) : pc[19:1];

  // Behaviour
  // cpu_dat_i
  always @(posedge wb_clk_i)
    cpu_dat_i <= cpu_we_o ? cpu_dat_i
               : hit ? (cpu_byte_o ? (a0 ? { {8{hitw[15]}}, hitw[15:8] }
                                         : { {8{hitw[ 7]}}, hitw[ 7:0] })
                                   : hitw)
               : ((cs == stb1_hi) ?
                   (wb_ack_i ?
                     (a0 ? bhw : (cpu_byte_o ? blw : wb_dat_i))
                   : cpu_dat_i)
                 : ((cs == stb2_hi && wb_ack_i) ?
                     { wb_dat_i[7:0], cpu_dat_i[7:0] }
                   : cpu_dat_i));

  // adr1
  always @(posedge wb_clk_i)
    adr1 <= cpu_adr_o[19:1] + 1'b1;

  // wb_adr_o
  always @(posedge wb_clk_i)
    wb_adr_o <= (ns==stb2_hi) ? adr1
              : (ns==pf_stb) ? pf_targ
              : pf_bus ? pf_adr
              : cpu_adr_o[19:1];

  // wb_sel_o
  always @(posedge wb_clk_i)
    wb_sel_o <= (ns==stb1_hi) ? sel_o
              : (ns==pf_stb) ? 2'b11 : 2'b01;

  // wb_stb_o
  always @(posedge wb_clk_i)
    wb_stb_o <= (ns==stb1_hi || ns==stb2_hi || ns==pf_stb);

  // wb_dat_o
  always @(posedge wb_clk_i)
    wb_dat_o <= a0 ? { cpu_dat_o[7:0], cpu_dat_o[15:8] }
                       : cpu_dat_o;

  // fetch window bookkeeping
  always @(posedge wb_clk_i)
    if (wb_rst_i) begin
      cur_v <= 1'b0;
      nxt_v <= 1'b0;
    end else if ((cs == IDLE) & op & cpu_we_o) begin
      // any write flushes the window so self-modifying code refetches
      cur_v <= 1'b0;
      nxt_v <= 1'b0;
    end else begin
      if (hit & hit_nxt) begin
        // sequential stream reached the prefetched word: promote it
        cur_addr <= nxt_addr;
        cur_dat  <= nxt_dat;
        cur_v    <= 1'b1;
        nxt_v    <= 1'b0;
      end
      if ((cs == stb1_hi) & wb_ack_i & fillw) begin
        cur_addr <= cpu_adr_o[19:1];
        cur_dat  <= wb_dat_i;
        cur_v    <= 1'b1;
        nxt_v    <= 1'b0;
      end
      if ((cs == pf_stb) & wb_ack_i) begin
        if (pf_iscur) begin
          cur_addr <= pf_adr;
          cur_dat  <= wb_dat_i;
          cur_v    <= 1'b1;
        end else begin
          nxt_addr <= pf_adr;
          nxt_dat  <= wb_dat_i;
          nxt_v    <= 1'b1;
        end
      end
    end

  // prefetch target latch (cur_addr must not move mid-prefetch)
  always @(posedge wb_clk_i)
    if (ns == pf_stb) begin
      pf_adr   <= pf_targ;
      pf_iscur <= ~cur_v;
    end

  // bus-idle counter (gates prefetch so tight exec op gaps are left alone)
  always @(posedge wb_clk_i)
    idle_cnt <= (wb_rst_i | op) ? 3'd0
              : idle_cnt[2] ? idle_cnt : idle_cnt + 3'd1;

  // cpu_block
  always @(*)
    case (cs)
      IDLE:    cpu_block <= op;
      hit_st:  cpu_block <= 1'b0;
      pf_stb,
      pf_blk:  cpu_block <= op;  // a real op waits out the prefetch
      bloc_lo: cpu_block <= wb_ack_i;
      default: cpu_block <= 1'b1;
    endcase

  // state machine
  // cs - current state
  always @(posedge wb_clk_i)
    cs <= wb_rst_i ? IDLE : ns;

  // ns - next state
  always @(*)
    case (cs)
      IDLE:    ns <= wb_ack_i ? IDLE
                   : op ? (hit ? hit_st : stb1_hi)
                   : (pf_go ? pf_stb : IDLE);
      stb1_hi: ns <= wb_ack_i ? (odd_word ? stb2_hi : bloc_lo) : stb1_hi;
      stb2_hi: ns <= wb_ack_i ? bloc_lo : stb2_hi;
      bloc_lo: ns <= wb_ack_i ? bloc_lo : IDLE;
      hit_st:  ns <= IDLE;
      pf_stb:  ns <= wb_ack_i ? pf_blk : pf_stb;
      pf_blk:  ns <= wb_ack_i ? pf_blk : IDLE;
      default: ns <= IDLE;
    endcase

endmodule
