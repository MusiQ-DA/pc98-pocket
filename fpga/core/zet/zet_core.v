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
  wire [1:0]         spec;

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
    .spec     (spec),
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
  // anywhere -- crashed Quartus' S2T timing-map stage, so the marker
  // comes out of decode as a dedicated spec flag, latched while the
  // front-end is decoding (exec_st low): every overlay select below is
  // a single register bit -- no comparators anywhere in this path.
  reg [1:0] spec_r;
  always @(posedge clk)
    if (rst) spec_r <= 2'd0;
    else if (!exec_st) spec_r <= spec;
  wire is_salc  = spec_r[0];
  wire is_bound = spec_r[1];  // implies bound was dispatched, so
                              // seq_addr is inside the borrowed range

  // SALC: al <- al - al - cf, flags preserved (t=1 addsub f=4 sbb,
  // byte op via ir1=23h).
  localparam [`IR_SIZE-1:0] SALC_IR =
      {7'h23, 3'd4, 3'd1, 2'b00, 1'b1, 1'b0, 1'b0,
       4'd0, 4'd0, 4'd0, 4'd0, 2'd0};

  // BOUND's 20 micro-ops as a packed lookup: the seq_addr-keyed case
  // table this replaces was the last S2T-crashing structure standing,
  // so the ops live in a plain reg array indexed by seq_addr[4:0]
  // (PUSHA=9'h1ce aliases to slot 14; ops wrap to slots 0,1).
  // Entry: {end, off_sel, b_sel, a_sel[1:0], s_sel, imm[15:0],
  //         ir1,f,t,ir0,wr_d,wr_mem,wr_flag,d,c,b,a,s}
  // *_sel picks the live decode value (base/index/seg/dst) for the EA
  // read and compare ops; everything else is stored verbatim.
  reg [57:0] bound_rom [0:31];
  initial begin : bound_fill
    integer i;
    for (i = 0; i < 32; i = i + 1) bound_rom[i] = 58'd0;
    // op +0..+19 sit at seq_addr[4:0] = 14..31,0,1
    bound_rom[14] = {1'b0,1'b1,1'b1,2'b01,1'b1,16'd0,7'h04,3'd0,3'd7,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd0,2'd0};  // r13 <- mem[EA]
    bound_rom[15] = {1'b0,1'b0,1'b0,2'b10,1'b0,16'd0,7'h00,3'd5,3'd5,2'b00,1'b0,1'b0,1'b1,4'd0,4'd0,4'd13,4'd0,2'd0}; // dst - r13
    bound_rom[16] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd1,7'h12,3'd0,3'd0,2'b01,1'b0,1'b0,1'b0,4'd12,4'd0,4'd12,4'd0,2'd0}; // jl -> r12=1
    bound_rom[17] = {1'b0,1'b1,1'b1,2'b01,1'b1,16'd0,7'h04,3'd1,3'd7,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd0,2'd0};  // r13 <- mem[EA+2]
    bound_rom[18] = bound_rom[15];                                                                                  // dst - r13
    bound_rom[19] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd1,7'h12,3'd0,3'd0,2'b01,1'b0,1'b0,1'b0,4'd12,4'd0,4'd15,4'd0,2'd0}; // jg -> r12=1
    bound_rom[20] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd0,7'h12,3'd5,3'd5,2'b00,1'b0,1'b0,1'b1,4'd0,4'd0,4'd0,4'd12,2'd0};  // zf <- (r12==0)
    bound_rom[21] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd0,7'h02,3'd3,3'd2,2'b00,1'b1,1'b0,1'b0,4'd12,4'd0,4'd0,4'd0,2'd0};  // r12<-0, exit if zf
    bound_rom[22] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd2,7'h12,3'd5,3'd1,2'b00,1'b1,1'b0,1'b0,4'd4,4'd0,4'd0,4'd4,2'd0};   // sp <- sp-2
    bound_rom[23] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd0,7'h12,3'd5,3'd7,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd0,2'd0};  // r13 <- flags
    bound_rom[24] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd0,7'h04,3'd0,3'd7,2'b00,1'b0,1'b1,1'b0,4'd0,4'd13,4'd12,4'd4,2'd2}; // push flags
    bound_rom[25] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd0,7'h12,3'd6,3'd7,2'b00,1'b0,1'b0,1'b1,4'd0,4'd0,4'd0,4'd0,2'd0};   // flags &= ~{IF,TF}
    bound_rom[26] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd4,7'h12,3'd5,3'd1,2'b00,1'b1,1'b0,1'b0,4'd4,4'd0,4'd0,4'd4,2'd0};   // sp <- sp-4
    bound_rom[27] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd0,7'h04,3'd0,3'd7,2'b00,1'b0,1'b1,1'b0,4'd0,4'd14,4'd12,4'd4,2'd2}; // push r14 (bound IP)
    bound_rom[28] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd0,7'h04,3'd1,3'd7,2'b00,1'b0,1'b1,1'b0,4'd0,4'd9,4'd12,4'd4,2'd2};  // push r9 (CS)
    bound_rom[29] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd4,7'h12,3'd0,3'd0,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd0,2'd0};  // r13 <- 4
    bound_rom[30] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd1,7'h12,3'd1,3'd1,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd13,2'd0}; // r13 <- r13+1
    bound_rom[31] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd2,7'h12,3'd4,3'd6,2'b00,1'b1,1'b0,1'b0,4'd13,4'd0,4'd0,4'd13,2'd0}; // r13 <- r13<<2
    bound_rom[ 0] = {1'b0,1'b0,1'b0,2'b00,1'b0,16'd2,7'h14,3'd1,3'd1,2'b00,1'b1,1'b0,1'b0,4'd9,4'd0,4'd0,4'd13,2'd0};  // r9 <- mem[22]
    bound_rom[ 1] = {1'b1,1'b0,1'b0,2'b00,1'b0,16'd0,7'h14,3'd1,3'd1,2'b00,1'b1,1'b0,1'b0,4'd15,4'd0,4'd0,4'd13,2'd0}; // r15 <- mem[20],end
  end

  wire [57:0] bword = bound_rom[seq_addr[4:0]];
  wire [ 3:0] bnd_b = bword[55] ? index : bword[9:6];
  wire [ 3:0] bnd_a = (bword[54:53] == 2'b01) ? base
                    : (bword[54:53] == 2'b10) ? dst : bword[5:2];
  wire [ 1:0] bnd_s = bword[52] ? seg : bword[1:0];
  wire [`IR_SIZE-1:0] bound_ir = {bword[35:10], bnd_b, bnd_a, bnd_s};

  assign ir_ov   = is_salc ? SALC_IR
                 : is_bound ? bound_ir : rom_ir;
  assign div     = (is_salc | is_bound) ? 1'b0 : div_rom;
  // end/off/imm all ride table bits now -- no seq_addr compares left
  assign end_seq = is_salc ? 1'b1
                 : is_bound ? bword[57] : end_seq_rom;
  assign off     = is_bound ? (bword[56] ? off_l : 16'h0000) : off_rom;

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
  assign imm   = exec_st ? (is_bound ? bword[51:36] : imm_d) : imm_f;
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
