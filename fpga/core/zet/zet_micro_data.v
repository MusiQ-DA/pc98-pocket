/*
 *  Microcode instruction generator for Zet
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

module zet_micro_data (
    input  [`MICRO_ADDR_WIDTH-1:0] n_micro,
    input  [15:0] off_i,
    input  [15:0] imm_i,
    input  [ 3:0] src,
    input  [ 3:0] dst,
    input  [ 3:0] base,
    input  [ 3:0] index,
    input  [ 1:0] seg,
    input  [ 2:0] fdec,
    output        div,
    output        end_seq,

    output [`IR_SIZE-1:0] ir,
    output [15:0]         off_o,
    output [15:0]         imm_o
  );

  // Net declarations
  wire [ 6:0] ir1;
  wire [ 1:0] ir0;
  wire var_s, var_off;
  wire [1:0] var_a, var_b, var_c, var_d;
  wire [2:0] var_imm;

  wire [3:0] addr_a, addr_b, addr_c, addr_d;
  wire [3:0] micro_a, micro_b, micro_c, micro_d;
  wire [1:0] addr_s, micro_s;
  wire [2:0] t;
  wire [2:0] f;
  wire [2:0] f_rom;
  wire       wr_flag;
  wire       wr_mem;
  wire       wr_rom;
  wire       wr_d;

  // Module instantiations
  zet_micro_rom micro_rom (n_micro, micro_raw);

  // SALC (0xD6): the opcode decode cannot afford a seq_addr of its own --
  // the 10-bit MICRO_ADDR_WIDTH this used to take crashed Quartus' SCL
  // map -- so it decodes to NOP with the marker operand pair src=dst=4'hF
  // and the op is swapped in at the ir level instead. See rom_def.v.
  wire [`MICRO_DATA_WIDTH-1:0] micro_raw;
  wire is_salc = (n_micro == `NOP) & (src == 4'hF) & (dst == 4'hF);

  // BOUND (0x62, np21w i286c_mn.c `_bound`): same constraint, bigger
  // microprogram -- decode points at `PUSHA with src=4'hF and this case
  // overlays all 20 ops, spanning PUSHA (0x1ce..0x1da) into POPA's head
  // (0x1db..0x1e1). Native PUSHA/POPA are unaffected: their decodes
  // never set src=4'hF. Ops +9..+19 mirror the INT dispatch tail --
  // push flags / clear IF/TF / push the bound IP (r14) / push CS /
  // vector through IVT[5] -- because a faulting BOUND is restartable
  // and must push the bound instruction's own IP like INVOP does.
  wire is_bound = (src == 4'hF) & (n_micro >= `PUSHA)
                              & (n_micro <= `PUSHA + 9'd19);

  // The overlay substitutes on the assembled ir / side outputs, NOT on
  // micro_o: putting a mux on the microcode ROM's q net crashed Quartus
  // Lite's S2T map (tsm/s2t/s2t_sgate_tdb_map.cpp:395) in the full
  // ap_core build -- CI bisect run 37347471654 proved the ROM bus must
  // stay a plain wire. Each bound op below is its 50-bit micro-word
  // expanded to the {ir1,f,t,ir0,wr_d,wr_mem,wr_flag,d,c,b,a,s} vector
  // with var_* fields already resolved against base/index/seg/dst.
  localparam [`IR_SIZE-1:0] SALC_IR =
      {7'h23, 3'd4, 3'd1, 2'b00, 1'b1, 1'b0, 1'b0,
       4'd0, 4'd0, 4'd0, 4'd0, 2'd0};                 // al <- al-al-cf
  reg [`IR_SIZE-1:0] bound_ir;
  always @(*) case (n_micro)
    9'h1ce: bound_ir = {7'h04,3'd0,3'd7,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,index,base,seg}; // r13 <- mem[EA]
    9'h1cf: bound_ir = {7'h00,3'd5,3'd5,2'b00,1'b0,1'b0,1'b1,4'd0,4'd0,4'd13,dst,2'd0};    // dst - r13
    9'h1d0: bound_ir = {7'h12,3'd0,3'd0,2'b01,1'b0,1'b0,1'b0,4'd12,4'd0,4'd12,4'd0,2'd0}; // jl -> r12=1
    9'h1d1: bound_ir = {7'h04,3'd1,3'd7,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,index,base,seg}; // r13 <- mem[EA+2]
    9'h1d2: bound_ir = {7'h00,3'd5,3'd5,2'b00,1'b0,1'b0,1'b1,4'd0,4'd0,4'd13,dst,2'd0};    // dst - r13
    9'h1d3: bound_ir = {7'h12,3'd0,3'd0,2'b01,1'b0,1'b0,1'b0,4'd12,4'd0,4'd15,4'd0,2'd0}; // jg -> r12=1
    9'h1d4: bound_ir = {7'h12,3'd5,3'd5,2'b00,1'b0,1'b0,1'b1,4'd0,4'd0,4'd0,4'd12,2'd0};  // zf <- (r12==0)
    9'h1d5: bound_ir = {7'h02,3'd3,3'd2,2'b00,1'b1,1'b0,1'b0,4'd12,4'd0,4'd0,4'd0,2'd0};  // r12<-0, exit if zf
    9'h1d6: bound_ir = {7'h12,3'd5,3'd1,2'b00,1'b1,1'b0,1'b0,4'd4,4'd0,4'd0,4'd4,2'd0};   // sp <- sp-2
    9'h1d7: bound_ir = {7'h12,3'd5,3'd7,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd0,2'd0};  // r13 <- flags
    9'h1d8: bound_ir = {7'h04,3'd0,3'd7,2'b00,1'b0,1'b1,1'b0,4'd0,4'd13,4'd12,4'd4,2'd2}; // push flags
    9'h1d9: bound_ir = {7'h12,3'd6,3'd7,2'b00,1'b0,1'b0,1'b1,4'd0,4'd0,4'd0,4'd0,2'd0};   // flags &= ~{IF,TF}
    9'h1da: bound_ir = {7'h12,3'd5,3'd1,2'b00,1'b1,1'b0,1'b0,4'd4,4'd0,4'd0,4'd4,2'd0};   // sp <- sp-4
    9'h1db: bound_ir = {7'h04,3'd0,3'd7,2'b00,1'b0,1'b1,1'b0,4'd0,4'd14,4'd12,4'd4,2'd2}; // push r14 (bound IP)
    9'h1dc: bound_ir = {7'h04,3'd1,3'd7,2'b00,1'b0,1'b1,1'b0,4'd0,4'd9,4'd12,4'd4,2'd2};  // push r9 (CS)
    9'h1dd: bound_ir = {7'h12,3'd0,3'd0,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd0,2'd0};  // r13 <- 4
    9'h1de: bound_ir = {7'h12,3'd1,3'd1,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd13,2'd0}; // r13 <- r13+1
    9'h1df: bound_ir = {7'h12,3'd4,3'd6,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd13,2'd0}; // r13 <- r13<<2
    9'h1e0: bound_ir = {7'h14,3'd1,3'd1,2'b00,1'b1,1'b0,1'b0,4'd9,4'd0,4'd0,4'd13,2'd0};  // r9 <- mem[22]
    default: bound_ir = {7'h14,3'd1,3'd1,2'b00,1'b1,1'b0,1'b0,4'd15,4'd0,4'd0,4'd13,2'd0};// r15 <- mem[20]
  endcase

  // imm constants the overlaid ops consume (the native ops underneath
  // would hand exec the wrong immediate)
  reg [15:0] bound_imm;
  always @(*) case (n_micro)
    9'h1d0, 9'h1d3: bound_imm = 16'd1; // condition-met write data
    9'h1d6: bound_imm = 16'd2;         // sp -= 2
    9'h1da, 9'h1dd: bound_imm = 16'd4; // sp -= 4 / r13 <- 4
    9'h1de: bound_imm = 16'd1;         // r13 += 1
    9'h1df, 9'h1e0: bound_imm = 16'd2; // r13 <<= 2 / read offset
    default: bound_imm = 16'd0;
  endcase

  // CI S2T bisect: the microcode ROM bus stays a plain wire.
  wire [`MICRO_DATA_WIDTH-1:0] micro_o = micro_raw;

  // Assignments
  assign micro_s = micro_o[1:0];
  assign micro_a = micro_o[5:2];
  assign micro_b = micro_o[9:6];
  assign micro_c = micro_o[13:10];
  assign micro_d = micro_o[17:14];
  assign wr_flag = micro_o[18];
  assign wr_mem  = micro_o[19];
  assign wr_rom  = micro_o[20];
  assign ir0     = micro_o[22:21];
  assign t       = micro_o[25:23];
  assign f_rom   = micro_o[28:26];
  assign ir1     = micro_o[35:29];
  assign var_s   = micro_o[36];
  assign var_a   = micro_o[38:37];
  assign var_b   = micro_o[40:39];
  assign var_c   = micro_o[42:41];
  assign var_d   = micro_o[44:43];
  assign var_off = micro_o[45];
  assign var_imm = micro_o[48:46];

  // SALC is a single op (its end bit lived in the overlaid word, not in
  // ir); bound ops terminate only on the last overlaid op -- the in-range
  // early exit at +7 is nstate's job (bound_z / zf).
  assign end_seq = is_salc ? 1'b1
                 : is_bound ? (n_micro == `PUSHA + 9'd19)
                            : micro_o[49];

  wire [15:0] rom_imm = var_imm == 3'd0 ? (16'h0000)
               : (var_imm == 3'd1 ? (16'h0002)
               : (var_imm == 3'd2 ? (16'h0004)
               : (var_imm == 3'd3 ? off_i
               : (var_imm == 3'd4 ? imm_i
               : (var_imm == 3'd5 ? 16'hffff
               : (var_imm == 3'd6 ? 16'b11 : 16'd1))))));

  assign imm_o = is_bound ? bound_imm : rom_imm;

  // bound's two EA reads (low bound / high bound) need the displacement;
  // every other overlaid op works on registers only
  assign off_o = is_bound ? ((n_micro == 9'h1ce || n_micro == 9'h1d1)
                             ? off_i : 16'h0000)
                          : (var_off ? off_i : 16'h0000);

  assign addr_a = var_a == 2'd0 ? micro_a
                : (var_a == 2'd1 ? base
                : (var_a == 2'd2 ? dst : src ));
  assign addr_b = var_b == 2'd0 ? micro_b
                : (var_b == 2'd1 ? index : src);
  assign addr_c = var_c == 2'd0 ? micro_c
                : (var_c == 2'd1 ? dst : src);
  assign addr_d = var_d == 2'd0 ? micro_d
                : (var_d == 2'd1 ? dst : src);
  assign addr_s = var_s ? seg : micro_s;

  assign div  = (is_salc | is_bound) ? 1'b0
              : (t==3'd3 && (f_rom[2]|f_rom[1]) && !wr_rom);
  assign f    = (t==3'd6 && wr_flag || t==3'd5 && wr_rom) ? fdec : f_rom;
  assign wr_d = (t==3'd5 && f==3'd7) ? 1'b0 : wr_rom; /* CMP doesn't write */

  wire [`IR_SIZE-1:0] ir_rom = { ir1, f, t, ir0, wr_d, wr_mem, wr_flag,
                                 addr_d, addr_c, addr_b, addr_a, addr_s };
  assign ir = is_salc ? SALC_IR : is_bound ? bound_ir : ir_rom;
endmodule
