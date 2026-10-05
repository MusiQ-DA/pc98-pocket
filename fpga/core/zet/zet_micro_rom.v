/*
 *  Microcode ROM for Zet
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

// altera message_off 10030
//  get rid of the warning about
//  not initializing the ROM

module zet_micro_rom #(
    // The .dat lives next to the RTL; the two tools run from different
    // working directories (same problem as v30u_ucrom's HEXDIR):
    //   Quartus resolves $readmemb from the project dir -> fpga/
    //   the sim benches run from the repo root.
`ifdef SYNTHESIS
    parameter DATDIR = "core/zet/"
`else
    parameter DATDIR = "fpga/core/zet/"
`endif
  ) (
    input [`MICRO_ADDR_WIDTH-1:0] addr,
    output [`MICRO_DATA_WIDTH-1:0] q
  );

  // Registers, nets and parameters
  // The microcode space grew a 10th address bit for SALC (10'h200) but a
  // flat 1024-deep x 50-bit $readmemb array trips a Quartus Lite S2T
  // internal error (tsm/s2t/s2t_sgate_tdb_map.cpp:395) in the full ap_core
  // map -- the 512-deep shape is what has always shipped.  The entire high
  // page holds exactly one micro-op, so keep the table at 512 entries and
  // decode the high page structurally: 10'h200 -> SALC, any other high
  // address -> the same end-of-sequence NOP the pad entries carried.
  reg [`MICRO_DATA_WIDTH-1:0] rom[0:511];

  localparam [`MICRO_DATA_WIDTH-1:0] SALC_UOP =
      50'b10000000000000010001110000100100000000000000000000;
  localparam [`MICRO_DATA_WIDTH-1:0] TAIL_NOP =
      {1'b1, {(`MICRO_DATA_WIDTH-1){1'b0}}};

  // Assignments
  assign q = addr[`MICRO_ADDR_WIDTH-1]
           ? (addr[`MICRO_ADDR_WIDTH-2:0] == 0 ? SALC_UOP : TAIL_NOP)
           : rom[addr[`MICRO_ADDR_WIDTH-2:0]];

  // Behaviour
  initial $readmemb({DATDIR, "micro_rom.dat"}, rom);
endmodule
