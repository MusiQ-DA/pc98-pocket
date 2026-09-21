/*
 * Copyright (C) 2018-2020 Markus Lavin (https://www.zzzconsulting.se/)
 *
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

// 20250301 - Changed combinational read to registered read to infer block RAM - desaster
//
// 2026-09-09 - Added a write port so the image can be replaced from an SD data
// slot at boot. The $readmemh contents remain the default, so a core with no
// firmware file behaves exactly as before; a slot simply overwrites it. That
// turns a firmware-only change from a fifteen-to-twenty minute Quartus
// compile into copying a file onto the card.

module sprom(clk, rst, ce, oe, addr, dout, wr_clk, wr_en, wr_addr, wr_data);
	//
	// Default address and data buses width (1024*32)
	//
	parameter aw = 10; //number of address-bits
	parameter dw = 32; //number of data-bits
	parameter numwords = (1 << aw); //ROM depth, for a non-power-of-two size
	parameter MEM_INIT_FILE = "";

	//
	// Generic synchronous single-port ROM interface
	//
	input           clk;  // Clock, rising edge
	input           rst;  // Reset, active high
	input           ce;   // Chip enable input, active high
	input           oe;   // Output enable input, active high
	input  [aw-1:0] addr; // address bus inputs
	output reg [dw-1:0] dout;   // output data bus

	input           wr_clk;  // write port, for loading an image at boot
	input           wr_en;
	input  [aw-1:0] wr_addr;
	input  [dw-1:0] wr_data;

	//
	// Module body
	//

	reg [dw-1:0] mem [numwords-1:0];
	reg [aw-1:0] ra;
	reg oe_r;

	always @(posedge wr_clk)
		if (wr_en)
			mem[wr_addr] <= wr_data;

	always @(posedge clk)
		oe_r <= oe;

	always @(posedge clk)
		if (oe_r)
			dout <= mem[ra];

	// read operation
	always @(posedge clk)
	  if (ce)
	    ra <= addr;     // read address needs to be registered to read clock

	initial begin
		/* verilator lint_off WIDTH */
		if (MEM_INIT_FILE != "") begin
		/* verilator lint_on WIDTH */
			$readmemh(MEM_INIT_FILE, mem);
		end
	end

endmodule
