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
  reg [`MICRO_DATA_WIDTH-1:0] rom[0:2**`MICRO_ADDR_WIDTH-1];

  // Assignments
  assign q = rom[addr];

  // Behaviour
  initial $readmemb({DATDIR, "micro_rom.dat"}, rom);
endmodule
