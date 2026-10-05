/*
 *  Zet processor core
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

module zet_core (
    input clk,
    input rst,

    // interrupts
    input  intr,
    output inta,
    input  nmi,
    output nmia,

    // interface to wishbone
    output [19:0] cpu_adr_o,
    input  [15:0] iid_dat_i,
    input  [15:0] cpu_dat_i,
    output [15:0] cpu_dat_o,
    output        cpu_byte_o,
    input         cpu_block,
    output        cpu_mem_op,
    output        cpu_m_io,
    output        cpu_we_o,

    output [19:0] pc,  // for debugging purposes
    output        dbg_fault, // seq_addr enters INVOP or INTD (1-zet_clk pulse)
    output [7:0]  dbg_opc,   // opcode being decoded when dbg_fault fired
    output        exec_st_o  // 1 while executing (0 => bus op is instr fetch)
  );

  // Net declarations
  wire [`IR_SIZE-1:0] ir;
  wire [15:0] off;
  wire [15:0] imm;
  wire        wr_ip0;

  wire [15:0] cs;
  wire [15:0] ip;
  wire        of;
  wire        zf;
  wire        ifl;
  wire        iflm;
  wire        tfl;
  wire        tflm;
  wire        iflss;
  wire        wr_ss;
  wire        cx_zero;
  wire        div_exc;

  wire [19:0] addr_exec;
  wire        byte_fetch;
  wire        byte_exec;

  // wire decode - microcode
  wire [`MICRO_ADDR_WIDTH-1:0] seq_addr;
  wire [3:0] src;
  // seq_addr is combinational on the live fetch byte while state==opcod_st,
  // so a stale byte sitting on data[7:0] during a bus stall decodes to INVOP
  // transiently without ever being committed.  Only report dispatched faults.
  assign dbg_fault = exec_st & ((seq_addr == `INVOP) | (seq_addr == `INTD));

  // First fault wins: the byte that decoded to INVOP/INTD is the evidence --
  // comparing it against the image at pc tells fetch corruption from a real
  // bad opcode.
  reg [7:0] opc_fault = 8'h00;
  reg       opc_seen  = 1'b0;
  always @(posedge clk)
    if (rst) begin
      opc_fault <= 8'h00;
      opc_seen  <= 1'b0;
    end else if (dbg_fault && !opc_seen) begin
      opc_fault <= opcode;
      opc_seen  <= 1'b1;
    end
  assign dbg_opc = opc_seen ? opc_fault : opcode;
  wire [3:0] dst;
  wire [3:0] base;
  wire [3:0] index;
  wire [1:0] seg;
  wire       end_seq;
  wire [2:0] fdec;
  wire       div;

  // wires fetch - decode
  wire [7:0] opcode;
  wire [7:0] modrm;
  wire       rep;
  wire       f0f;
  wire       exec_st;
  wire       ld_base;
  wire [2:0] sop_l;

  wire need_modrm;
  wire need_off;
  wire need_imm;
  wire off_size;
  wire imm_size;
  wire ext_int;

  // wires fetch - microcode
  wire [15:0] off_l;
  wire [15:0] imm_l;
  wire [15:0] imm_d;
  wire [`IR_SIZE-1:0] rom_ir;
  wire [5:0] ftype;

  // wires fetch - exec
  wire [15:0] imm_f;

  // raw micro_data outputs before the bound/salc overlay
  wire             div_rom;
  wire             end_seq_rom;
  wire [15:0]      off_rom;
  wire [`IR_SIZE-1:0] ir_ov;

  // wires and regs for hlt
  wire block_or_hlt;
  wire hlt_op;
  wire hlt_in;
  wire hlt_out;

  reg hlt_op_old;
  reg hlt;

  // regs for nmi
  reg nmir;
  reg nmi_old;
  reg nmia_old;

  // Module instantiations
  zet_fetch fetch (
    .clk  (clk),
    .rst  (rst),

    // to decode
    .opcode  (opcode),
    .modrm   (modrm),
    .rep     (rep),
    .f0f     (f0f),
    .exec_st (exec_st),
    .ld_base (ld_base),
    .sop_l   (sop_l),

    // from decode
    .need_modrm (need_modrm),
    .need_off   (need_off),
    .need_imm   (need_imm),
    .off_size   (off_size),
    .imm_size   (imm_size),
    .ext_int    (ext_int),
    .end_seq    (end_seq),

    // to microcode
    .off_l (off_l),
    .imm_l (imm_l),

    // from microcode
    .ftype (ftype),

    // to exec
    .imm_f  (imm_f),
    .wr_ip0 (wr_ip0),

    // from exec
    .cs      (cs),
    .ip      (ip),
    .of      (of),
    .zf      (zf),
    .iflm    (iflm),
    .tflm    (tflm),
    .iflss   (iflss),
    .cx_zero (cx_zero),
    .div_exc (div_exc),

    // to wb
    .data          (cpu_dat_i),
    .pc            (pc),
    .bytefetch     (byte_fetch),
    .block         (block_or_hlt),
    .intr          (intr),
    .nmir          (nmir)
  );

  zet_decode decode (
    .clk (clk),
    .rst (rst),

    .opcode  (opcode),
    .modrm   (modrm),
    .rep     (rep),
    .f0f     (f0f),
    .block   (block_or_hlt),
    .exec_st (exec_st),
    .div_exc (div_exc),
    .ld_base (ld_base),
    .div     (div),
    .tfl     (tfl),
    .tflm    (tflm),

    .need_modrm (need_modrm),
    .need_off   (need_off),
    .need_imm   (need_imm),
    .off_size   (off_size),
    .imm_size   (imm_size),

    .sop_l   (sop_l),
    .intr    (intr),
    .ifl     (ifl),
    .iflm    (iflm),
    .inta    (inta),
    .ext_int (ext_int),
    .nmir    (nmir),
    .nmia    (nmia),
    .wr_ss   (wr_ss),
    .iflss   (iflss),

    .seq_addr (seq_addr),
    .src      (src),
    .dst      (dst),
    .base     (base),
    .index    (index),
    .seg      (seg),
    .f        (fdec),

    .end_seq  (end_seq)
  );

  zet_micro_data micro_data (
    // from decode
    .n_micro (seq_addr),
    .off_i   (off_l),
    .imm_i   (imm_l),
    .src     (src),
    .dst     (dst),
    .base    (base),
    .index   (index),
    .seg     (seg),
    .fdec    (fdec),
    .div     (div_rom),
    .end_seq (end_seq_rom),

    // to exec
    .ir    (rom_ir),
    .off_o (off_rom),
    .imm_o (imm_d)
  );

  // ROM-overlay for instructions the 512x50 microcode table cannot
  // hold.  Decode flags SALC (0xD6) as NOP with src=dst=4'hF and BOUND
  // (0x62) as PUSHA with src=4'hF (dst carries the reg operand) -- both
  // operand pairs are impossible for native decodes.  The substitution
  // lives HERE, on the exec_st mux boundary, because every variant that
  // put it inside zet_micro_data (a mux on the ROM q net, or on the
  // assembled ir) crashed Quartus Lite's S2T map in the full ap_core
  // build -- tsm/s2t/s2t_sgate_tdb_map.cpp:395 -- while this exec_st
  // mux has shipped since the core was vendored.
  // src/dst/seq_addr are combinational decode-cone outputs (the whole
  // 256-entry opcode case sits behind them).  Every build that let a
  // comparator on them drive consumed logic -- on the ROM q net, on ir,
  // anywhere -- crashed Quartus' S2T timing-map stage, so the marker is
  // latched into a flop while the front-end is decoding (exec_st low):
  // the mux selects below then hang off clean register outputs only.
  reg [1:0] spec_r;
  always @(posedge clk)
    if (rst) spec_r <= 2'd0;
    else if (!exec_st)
      spec_r <= (src == 4'hF && dst == 4'hF) ? 2'd1   // salc
              : (src == 4'hF)                  ? 2'd2   // bound
                                               : 2'd0;
  wire is_salc  = (spec_r == 2'd1);
  wire is_bound = (spec_r == 2'd2);  // spec_r==2 implies bound was
                                     // dispatched, so seq_addr is
                                     // already inside the borrowed range

  // SALC: al <- al - al - cf, flags preserved (t=1 addsub f=4 sbb,
  // byte op via ir1=23h).  BOUND ops are the 50-bit micro-words
  // pre-expanded into the {ir1,f,t,ir0,wr_d,wr_mem,wr_flag,d,c,b,a,s}
  // vector with var_* resolved against base/index/seg/dst; +9..+19
  // mirror the INT dispatch tail (flags, IF/TF clear, push bound IP
  // from r14, push CS, vector through IVT[5]).
  localparam [`IR_SIZE-1:0] SALC_IR =
      {7'h23, 3'd4, 3'd1, 2'b00, 1'b1, 1'b0, 1'b0,
       4'd0, 4'd0, 4'd0, 4'd0, 2'd0};
  reg [`IR_SIZE-1:0] bound_ir;
  always @(*) case (seq_addr)
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

  // immediate constants the overlaid ops consume (the native ops
  // underneath would hand exec the wrong value)
  reg [15:0] bound_imm;
  always @(*) case (seq_addr)
    9'h1d0, 9'h1d3: bound_imm = 16'd1; // condition-met write data
    9'h1d6: bound_imm = 16'd2;         // sp -= 2
    9'h1da, 9'h1dd: bound_imm = 16'd4; // sp -= 4 / r13 <- 4
    9'h1de: bound_imm = 16'd1;         // r13 += 1
    9'h1df, 9'h1e0: bound_imm = 16'd2; // r13 <<= 2 / read offset
    default: bound_imm = 16'd0;
  endcase

  assign ir_ov   = is_salc ? SALC_IR
                 : is_bound ? bound_ir : rom_ir;
  assign div     = (is_salc | is_bound) ? 1'b0 : div_rom;
  assign end_seq = is_salc ? 1'b1
                 : is_bound ? (seq_addr == `PUSHA + 9'd19)
                            : end_seq_rom;
  // bound's two EA reads (low/high bound) take the displacement;
  // every other overlaid op works on registers only
  assign off     = is_bound ? ((seq_addr == 9'h1ce || seq_addr == 9'h1d1)
                              ? off_l : 16'h0000) : off_rom;

  zet_exec exec (
    .clk     (clk),
    .rst     (rst),

    // from fetch
    .ir      (ir),
    .off     (off),
    .imm     (imm),
    .wrip0   (wr_ip0),

    // to fetch
    .cs      (cs),
    .ip      (ip),
    .of      (of),
    .zf      (zf),
    .ifl     (ifl),
    .tfl     (tfl),
    .cx_zero (cx_zero),
    .div_exc (div_exc),

    .wr_ss   (wr_ss),

    // from wb
    .memout  (iid_dat_i),
    .wr_data (cpu_dat_o),
    .addr    (addr_exec),
    .we      (cpu_we_o),
    .m_io    (cpu_m_io),
    .byteop  (byte_exec),
    .block   (block_or_hlt)
  );

  // Assignments
  assign exec_st_o  = exec_st;
  assign cpu_adr_o  = exec_st ? addr_exec : pc;
  assign cpu_byte_o = exec_st ? byte_exec : byte_fetch;
  assign cpu_mem_op = ir[`MEM_OP];

  assign ir    = exec_st ? ir_ov : `ADD_IP;
  assign imm   = exec_st ? (is_bound ? bound_imm : imm_d) : imm_f;
  assign ftype = ir_ov[28:23];

  assign hlt_op = ((opcode == `OP_HLT) && exec_st); 
  assign hlt_in = (hlt_op && !hlt_op_old && !hlt_out);
  assign hlt_out = (intr & ifl) | nmir;
  assign block_or_hlt = cpu_block | hlt | hlt_in;

  // Behaviour
  always @(posedge clk)
    if (rst)
      hlt_op_old <= 1'b0;
    else
      if (hlt_op)
        hlt_op_old <= 1'b1;
      else
        hlt_op_old <= 1'b0;

  always @(posedge clk)
    if (rst)
      hlt <= 1'b0;
    else
      if (hlt_in)
        hlt <= 1'b1;
      else if (hlt_out)
        hlt <= 1'b0;

  always @(posedge clk)
    if (rst)
    begin
      nmir <= 1'b0;
      nmi_old <= 1'b0;
      nmia_old <= 1'b0;
    end
    else
    begin
      nmi_old <= nmi;
      nmia_old <= nmia; 
      if (nmi & ~nmi_old)
        nmir <= 1'b1;
      else if (nmia_old)
        nmir <= 1'b0;
    end

endmodule
