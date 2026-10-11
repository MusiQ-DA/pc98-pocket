/*
 *  Instruction decoder for Zet
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

`include "defines.v"

module zet_decode (
    input clk,
    input rst,
    input [7:0] opcode,
    input [7:0] modrm,
    input       rep,
    input       f0f,
    input block,
    input exec_st,
    input div_exc,
    input ld_base,
    input div,
    input        tfl,
    output       tflm,

    output need_modrm,
    output need_off,
    output need_imm,
    output off_size,
    output imm_size,

    input  [2:0] sop_l,

    input        intr,
    input        ifl,
    output       iflm,
    output reg   inta,
    output reg   ext_int,
    input        nmir,
    output reg   nmia,
    input        wr_ss,
    output       iflss,

    // to microcode
    output [`MICRO_ADDR_WIDTH-1:0] seq_addr,   // DECODE-stage micro address
    output [`MICRO_ADDR_WIDTH-1:0] seq_addr_x, // executing op's micro address
    output       div_wait,                     // seq held by the divider
    output [1:0] spec,
    output [3:0] src,
    output [3:0] dst,
    output [3:0] base,
    output [3:0] index,
    output [1:0] seg,
    output [2:0] f,

    // from microcode
    input  end_seq
  );

  // Net declarations
  wire [`MICRO_ADDR_WIDTH-1:0] base_addr;
  reg  [`MICRO_ADDR_WIDTH-1:0] seq;
  reg  dive;
  reg  tfle;
  reg  tfld;
  reg  ifld;
  reg  iflssd;
  reg  old_ext_int;

  reg [4:0] div_cnt;

  // Module instantiations
  zet_opcode_deco opcode_deco (opcode, modrm, rep, f0f, sop_l, base_addr, need_modrm,
                             need_off, need_imm, off_size, imm_size, src, dst,
                             base, index, seg);

  // Two-stage micro-op pipe. seq stays the index of the op that is in
  // the EXECUTE stage (the registered micro-op word in zet_core), while
  // seq_addr runs one slot ahead fetching the next word from the micro
  // ROM. Every sequencing input to this module (end_seq, div, dive,
  // tfle, ext_int) describes the EXECUTING op, so the register updates
  // below keep their old meanings -- only the ROM address is ahead.
  //
  // seq_d is the offset being fetched this cycle: under reset and
  // outside execu_st it prefetch-decodes the instruction's first
  // micro-op (op0 is captured while the operand bytes arrive, so it
  // executes on the first execute clock); inside execu_st it is seq+1,
  // or 0 once the executing op's end_seq says the sequence is done.
  wire [`MICRO_ADDR_WIDTH-1:0] seq_d;
  assign seq_d = (rst | !exec_st) ? `MICRO_ADDR_WIDTH'd0
               : end_seq          ? `MICRO_ADDR_WIDTH'd0
               : seq + `MICRO_ADDR_WIDTH'd1;

  // The sequence base for the fetch must switch the SAME cycle the
  // redirect decides -- otherwise the first op of the trap/interrupt
  // routine would be fetched late and a stale word would execute. So
  // the mux runs on the D-inputs of the redirect registers (the pulse
  // conditions are identical), not on the registers themselves.
  // Priority is the old mux order: INTT > INTD > EINT/EINTP > base.
  wire tfle_n, dive_n, eint_n;
  assign tfle_n = ((((tflm & !tfle) & iflss) & exec_st & end_seq)
                | (tfle & !end_seq));
  assign dive_n = div_exc | (dive & !end_seq);
  assign eint_n = ((((nmir | (intr & iflm)) & iflss) & exec_st & end_seq)
                | (ext_int & !end_seq));

  assign seq_addr = (tfle_n ? `INTT : (dive_n ? `INTD
    : (eint_n ? (rep ? `EINTP : `EINT) : base_addr))) + seq_d;

  // Executing-op micro address: the old seq_addr expression verbatim
  // (registered redirects + seq). Used for the fault probe -- NOT for
  // the ROM fetch (the BOUND overlay indexes seq_addr, the fetch side,
  // so its table word rides the pipe register with the op).
  assign seq_addr_x = (tfle ? `INTT : (dive ? `INTD
    : (ext_int ? (rep ? `EINTP : `EINT) : base_addr))) + seq;

  // While the divider iterates, the executing op must persist in the
  // pipe register: zet_core gates the micro-op capture on this.
  assign div_wait = exec_st & (|div_cnt);

  // Overlay markers for zet_core: [0]=salc (0xD6), [1]=bound (0x62).
  // Compared directly on the latched opcode byte -- the src/dst=4'hF
  // markers these replaced forced comparators onto the opcode_deco
  // combinational cone, which Quartus Lite's S2T map could not process.
  // 0Fxx escapes decode elsewhere, so f0f suppresses both.
  assign spec = {opcode == 8'h62 && !f0f, opcode == 8'hD6 && !f0f};

  assign f = opcode[7] ? modrm[5:3] : opcode[5:3];

  assign iflm = ifl & ifld;
  assign tflm = tfl & tfld;

  assign iflss = !wr_ss & iflssd;

  // Behaviour
  always @(posedge clk)
    ifld <= rst ? 1'b0 : (exec_st ? ifld : ifl);

  always @(posedge clk)
    tfld <= rst ? 1'b0 : (exec_st ? tfld : tfl);

  always @(posedge clk)
    if (rst)
      iflssd <= 1'b0;
    else
    begin
      if (!exec_st)
        iflssd <= 1'b1;
      else if (wr_ss)
        iflssd <= 1'b0;
    end

  // seq
  always @(posedge clk)
    seq <= rst ? `MICRO_ADDR_WIDTH'd0
         : block ? seq
         : end_seq ? `MICRO_ADDR_WIDTH'd0
         : |div_cnt ? seq
         : exec_st ? (seq + `MICRO_ADDR_WIDTH'd1) : `MICRO_ADDR_WIDTH'd0;

  // div_cnt - divisor counter
  always @(posedge clk)
    div_cnt <= rst ? 5'd0
       : ((div & exec_st) ? (div_cnt==5'd0 ? 5'd18 : div_cnt - 5'd1) : 5'd0);

  // dive
  always @(posedge clk)
    if (rst) dive <= 1'b0;
    else dive <= block ? dive
     : (div_exc ? 1'b1 : (dive ? !end_seq : 1'b0));

  // tfle
  always @(posedge clk)
    if (rst) tfle <= 1'b0;
    else tfle <= block ? tfle
     : ((((tflm & !tfle) & iflss) & exec_st & end_seq) ? 1'b1 : (tfle ? !end_seq : 1'b0));

  // ext_int
  always @(posedge clk)
    if (rst) ext_int <= 1'b0;
    else ext_int <= block ? ext_int
      : ((((nmir | (intr & iflm)) & iflss) & exec_st & end_seq) ? 1'b1
        : (ext_int ? !end_seq : 1'b0));

  // old_ext_int
  always @(posedge clk) old_ext_int <= rst ? 1'b0 : ext_int;

  // inta
  always @(posedge clk)
    inta <= rst ? 1'b0 : (!nmir & (!old_ext_int & ext_int));

  // nmia
  always @(posedge clk)
    nmia <= rst ? 1'b0 : (nmir & (!old_ext_int & ext_int));

endmodule
