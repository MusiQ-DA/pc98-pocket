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
  // and the op is swapped in here instead. See rom_def.v.
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
  reg  [`MICRO_DATA_WIDTH-1:0] bound_op;
  always @(*) case (n_micro)
    9'h1ce: bound_op = 50'b00001000001011000010000011100100110100000000000000; // r13 <- mem[EA] (low)
    9'h1cf: bound_op = 50'b00000000000100000000010110100001000000001101000000; // cmp dst-r13 -> flags
    9'h1d0: bound_op = 50'b01110000000000001001000000001000110000001100000000; // jl -> r12=1
    9'h1d1: bound_op = 50'b00001000001011000010000111100100110100000000000000; // r13 <- mem[EA+2] (high)
    9'h1d2: bound_op = 50'b00000000000100000000010110100001000000001101000000; // cmp dst-r13 -> flags
    9'h1d3: bound_op = 50'b01110000000000001001000000001000110000001111000000; // jg -> r12=1
    9'h1d4: bound_op = 50'b00000000000000001001010110100001000000000000110000; // zf <- (r12==0)
    9'h1d5: bound_op = 50'b00000000000000000001001101000100110000000000000000; // r12<-0, exit if zf
    9'h1d6: bound_op = 50'b00010000000000001001010100100100010000000000010000; // sp <- sp-2
    9'h1d7: bound_op = 50'b00000000000000001001010111100100110100000000000000; // r13 <- flags
    9'h1d8: bound_op = 50'b00000000000000000010000011100010000011011100010010; // push flags
    9'h1d9: bound_op = 50'b00000000000000001001011011100001000000000000000000; // flags &= ~{IF,TF}
    9'h1da: bound_op = 50'b00100000000000001001010100100100010000000000010000; // sp <- sp-4
    9'h1db: bound_op = 50'b00000000000000000010000011100010000011101100010010; // push r14 (bound IP)
    9'h1dc: bound_op = 50'b00000000000000000010000111100010000010011100010010; // push r9 (CS)
    9'h1dd: bound_op = 50'b00100000000000001001000000000100110100000000000000; // r13 <- 4
    9'h1de: bound_op = 50'b01110000000000001001000100100100110100000000110100; // r13 <- r13+1 = 5
    9'h1df: bound_op = 50'b00010000000000001001010011000100110100000000110100; // r13 <- r13<<2 = 20
    9'h1e0: bound_op = 50'b00010000000000001010000100100100100100000000110100; // r9  <- mem[22]
    default: bound_op = 50'b10000000000000001010000100100100111100000000110100; // r15 <- mem[20], end
  endcase

  // CI S2T bisect: overlay dead-coded -- micro_o goes straight through.
  // If this build fails the comparators/decode are the trigger, not the mux.
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
  assign end_seq = micro_o[49];

  assign imm_o = var_imm == 3'd0 ? (16'h0000)
               : (var_imm == 3'd1 ? (16'h0002)
               : (var_imm == 3'd2 ? (16'h0004)
               : (var_imm == 3'd3 ? off_i
               : (var_imm == 3'd4 ? imm_i
               : (var_imm == 3'd5 ? 16'hffff
               : (var_imm == 3'd6 ? 16'b11 : 16'd1))))));

  assign off_o = var_off ? off_i : 16'h0000;

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

  assign div  = (t==3'd3 && (f_rom[2]|f_rom[1]) && !wr_rom);
  assign f    = (t==3'd6 && wr_flag || t==3'd5 && wr_rom) ? fdec : f_rom;
  assign wr_d = (t==3'd5 && f==3'd7) ? 1'b0 : wr_rom; /* CMP doesn't write */

  assign ir = { ir1, f, t, ir0, wr_d, wr_mem, wr_flag, addr_d,
                addr_c, addr_b, addr_a, addr_s };
endmodule
