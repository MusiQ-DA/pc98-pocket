/////////////////////////////////////////////////////////////////////
////                                                             ////
////  Non-restoring unsigned divider                             ////
////                                                             ////
////  Author: Richard Herveille                                  ////
////          richard@asics.ws                                   ////
////          www.asics.ws                                       ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2002 Richard Herveille                        ////
////                    richard@asics.ws                         ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////

//  CVS Log
//
//  $Id: div_uu.v,v 1.3 2003/09/17 13:08:53 rherveille Exp $
//
//  $Date: 2003/09/17 13:08:53 $
//  $Revision: 1.3 $
//  $Author: rherveille $
//  $Locker:  $
//  $State: Exp $
//
// Change History:
//               $Log: div_uu.v,v $
//               Revision 1.3  2003/09/17 13:08:53  rherveille
//               Fixed a bug in the remainder output. Changed a hard value into the required parameter.
//               Fixed a bug in the testbench.
//
//               Revision 1.2  2002/10/31 13:54:58  rherveille
//               Fixed a bug in the remainder output of div_su.v
//
//               Revision 1.1.1.1  2002/10/29 20:29:10  rherveille
//
//
//

//synopsys translate_off
`timescale 1ns/10ps
//synopsys translate_on

module zet_div_uu(clk, ena, z, d, q, s, div0, ovf);

	//
	// parameters
	//
	parameter z_width = 16;
	parameter d_width = z_width /2;
	
	//
	// inputs & outputs
	//
	input clk;               // system clock
	input ena;               // clock enable

	input  [z_width -1:0] z; // divident
	input  [d_width -1:0] d; // divisor
	output [d_width -1:0] q; // quotient
	output [d_width -1:0] s; // remainder
	output div0;
	output ovf;
	reg [d_width-1:0] q;
	reg [d_width-1:0] s;
	reg div0;
	reg ovf;

	//	
	// functions
	//
	function [z_width:0] gen_s;
		input [z_width:0] si;
		input [z_width:0] di;
	begin
	  if(si[z_width])
	    gen_s = {si[z_width-1:0], 1'b0} + di;
	  else
	    gen_s = {si[z_width-1:0], 1'b0} - di;
	end
	endfunction

	function [d_width-1:0] gen_q;
		input [d_width-1:0] qi;
		input [z_width:0] si;
	begin
	  gen_q = {qi[d_width-2:0], ~si[z_width]};
	end
	endfunction

	function [d_width-1:0] assign_s;
		input [z_width:0] si;
		input [z_width:0] di;
		reg [z_width:0] tmp;
	begin
	  if(si[z_width])
	    tmp = si + di;
	  else
	    tmp = si;

	  assign_s = tmp[z_width-1:z_width-d_width];
	end
	endfunction

	//
	// variables
	//
	// Iterative re-implementation of the original d_width-stage pipelined
	// array: the pipe accepted new operands every clock but the microcode
	// only ever launches one divide and waits a fixed div_cnt==18 window,
	// so ~1.5k pipeline registers bought throughput that is never used.
	// One gen_s/gen_q stage is reused per clock instead; a launch happens
	// on any operand change (exactly what the comb stage-0 of the pipe
	// observed), and the result registers land on the same cycle the pipe
	// tail would have produced them, holding their value afterwards.
	//
	reg  [z_width:0]   s_r;    // running remainder   (s_pipe[n])
	reg  [z_width:0]   d_r;    // shifted divisor     (d_pipe[n], constant)
	reg  [d_width-1:0] q_r;    // quotient in flight  (q_pipe[n])
	reg  [z_width-1:0] z_cap;  // operands this run was launched with
	reg  [d_width-1:0] d_cap;
	reg  [4:0]         cnt;    // completed stages, 1..d_width
	reg                ovf_r, div0_r;

	wire [z_width:0] s_nxt = gen_s(s_r, d_r);

	//
	// perform parameter checks
	//
	// synopsys translate_off
	initial
	begin
	  if(d_width !== z_width / 2)
	    $display("div.v parameter error (d_width != z_width/2).");
	end
	// synopsys translate_on

	always @(posedge clk)
	  if(ena)
	    begin
	      // operand change -> launch (the pipe's comb stage-0 equivalent)
	      if(z !== z_cap || d !== d_cap)
	        begin
	          s_r   <= gen_s({1'b0, z}, {1'b0, d, {(z_width-d_width){1'b0}}});
	          d_r   <= {1'b0, d, {(z_width-d_width){1'b0}}};
	          q_r   <= {d_width{1'b0}};
	          z_cap <= z;
	          d_cap <= d;
	          cnt   <= 5'd1;
	          ovf_r <= !(z[z_width-1:d_width] < d);
	          div0_r <= ~|d;
	        end
	      else if(cnt >= 5'd1 && cnt < d_width[4:0])
	        begin
	          // q_pipe[n] <= gen_q(q_pipe[n-1], s_pipe[n]): the quotient
	          // bit comes from the CURRENT stage, not the next one.
	          q_r <= gen_q(q_r, s_r);
	          s_r <= s_nxt;
	          cnt <= cnt + 5'd1;
	        end
	      else if(cnt == d_width[4:0])
	        begin
	          // tail taps: q <= gen_q(q_pipe[d-1], s_pipe[d]),
	          //            s <= assign_s(s_pipe[d], d_pipe[d])
	          q    <= gen_q(q_r, s_r);
	          s    <= assign_s(s_r, d_r);
	          ovf  <= ovf_r;
	          div0 <= div0_r;
	          cnt  <= 5'd0;
	        end
	    end
endmodule



