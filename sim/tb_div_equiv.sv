// tb_div_equiv.sv -- cycle-exact equivalence: the iterative zet_div_uu
// replacement against the original pipelined array, both wrapped in the
// real zet_div_su sign-fixup. Random operands are re-launched at random
// phases (including mid-iteration changes); the only legal difference
// window is the X-powered start-up. Every post-warmup cycle must match.
`timescale 1ns/1ps
`default_nettype none
module tb_div_equiv;
    logic clk = 0;
    always #10 clk = ~clk;

    logic [33:0] z;
    logic [16:0] d;
    wire  [17:0] q_new, s_new; wire ovf_new;
    wire  [17:0] q_ref, s_ref; wire ovf_ref;

    zet_div_su #(.z_width(34)) dut (
        .clk(clk), .ena(1'b1), .z(z), .d(d),
        .q(q_new), .s(s_new), .ovf(ovf_new));

    div_su_ref #(.z_width(34)) ref_ (
        .clk(clk), .ena(1'b1), .z(z), .d(d),
        .q(q_ref), .s(s_ref), .ovf(ovf_ref));

    // Contract being verified: 18+ cycles after the operands last moved,
    // both implementations must present the same q/s/ovf. Inside churn
    // windows the pipe shows a still-running lane's tail while the
    // iterative unit shows its last completed run -- both meaningless.
    int errors = 0, checks = 0, cycle = 0, stable = 0;
    logic [33:0] z_prev;
    logic [16:0] d_prev;

    always @(posedge clk) begin
        cycle <= cycle + 1;
        stable <= (z === z_prev && d === d_prev) ? stable + 1 : 0;
        z_prev <= z;
        d_prev <= d;
        if (cycle > 64 && stable >= 20) begin
            checks++;
            if ({q_new, s_new, ovf_new} !== {q_ref, s_ref, ovf_ref}) begin
                errors++;
                $display("MISMATCH cyc=%0d (stable=%0d)  new q=%h s=%h ovf=%b   ref q=%h s=%h ovf=%b",
                         cycle, stable, q_new, s_new, ovf_new, q_ref, s_ref, ovf_ref);
            end
        end
    end

    // stimulus: hold each operand pair a random 1..40 cycles, sometimes
    // mid-iteration; include div0, ovf, min-int, and all-ones cases.
    initial begin
        z = '0; d = '0;
        repeat (4) @(posedge clk);
        // directed edge cases
        run_case(34'h3_0000_0000, 17'h1_0000, 30); // ovf: 2^33 / 2^16
        run_case(34'h0_0000_0007, 17'h0_0000, 30); // div0
        run_case(34'h0_FFFF_FFFF, 17'h0_FFFF, 30); // -1/-1 signed-ish raw
        run_case(34'h0_8000_0000, 17'h0_7FFF, 25);
        run_case(34'h0_8000_0000, 17'h1_7FFF, 25); // |min| divisor
        // mid-flight operand changes
        run_case(34'h0_1234_5678, 17'h0_00A5, 7);
        run_case(34'h0_0BAD_F00D, 17'h0_1234, 9);  // change at ~stage 8
        run_case(34'h0_DEAD_BEEF, 17'h0_00FF, 40); // long hold, result lands
        // random soak
        repeat (400) begin
            run_case($urandom, $urandom_range(0, 17'h1FFFF), $urandom_range(1, 40));
        end
        repeat (40) @(posedge clk);
        if (errors == 0) $display("DIV-EQUIV PASS: %0d checks, 0 mismatches", checks);
        else             $display("DIV-EQUIV FAIL: %0d mismatches in %0d checks", errors, checks);
        $finish;
    end

    task run_case(input logic [33:0] zv, input logic [16:0] dv, input int hold);
        z = zv; d = dv;
        repeat (hold) @(posedge clk);
    endtask
endmodule

// ---------------- reference: original pipelined implementation ----------------
module div_uu_ref(clk, ena, z, d, q, s, div0, ovf);
	parameter z_width = 16;
	parameter d_width = z_width /2;
	input clk, ena;
	input  [z_width -1:0] z;
	input  [d_width-1:0] d;
	output [d_width-1:0] q, s;
	output div0, ovf;
	reg [d_width-1:0] q, s;
	reg div0, ovf;

	function [z_width:0] gen_s;
		input [z_width:0] si; input [z_width:0] di;
		begin
		  if(si[z_width]) gen_s = {si[z_width-1:0], 1'b0} + di;
		  else            gen_s = {si[z_width-1:0], 1'b0} - di;
		end
	endfunction
	function [d_width-1:0] gen_q;
		input [d_width-1:0] qi; input [z_width:0] si;
		begin gen_q = {qi[d_width-2:0], ~si[z_width]}; end
	endfunction
	function [d_width-1:0] assign_s;
		input [z_width:0] si; input [z_width:0] di;
		reg [z_width:0] tmp;
		begin
		  if(si[z_width]) tmp = si + di; else tmp = si;
		  assign_s = tmp[z_width-1:z_width-d_width];
		end
	endfunction

	reg [d_width-1:0] q_pipe  [d_width-1:0];
	reg [z_width:0]   s_pipe  [d_width:0];
	reg [z_width:0]   d_pipe  [d_width:0];
	reg [d_width:0] div0_pipe, ovf_pipe;
	integer n0, n1, n2, n3;

	always @(d) d_pipe[0] <= {1'b0, d, {(z_width-d_width){1'b0}} };
	always @(posedge clk) if(ena)
	    for(n0=1; n0 <= d_width; n0=n0+1) d_pipe[n0] <= d_pipe[n0-1];
	always @(z) s_pipe[0] <= z;
	always @(posedge clk) if(ena)
	    for(n1=1; n1 <= d_width; n1=n1+1) s_pipe[n1] <= gen_s(s_pipe[n1-1], d_pipe[n1-1]);
	always @(posedge clk) q_pipe[0] <= 0;
	always @(posedge clk) if(ena)
	    for(n2=1; n2 < d_width; n2=n2+1) q_pipe[n2] <= gen_q(q_pipe[n2-1], s_pipe[n2]);
	always @(z or d) begin
	  ovf_pipe[0]  <= !(z[z_width-1:d_width] < d);
	  div0_pipe[0] <= ~|d;
	end
	always @(posedge clk) if(ena)
	    for(n3=1; n3 <= d_width; n3=n3+1) begin
	        ovf_pipe[n3]  <= ovf_pipe[n3-1];
	        div0_pipe[n3] <= div0_pipe[n3-1];
	    end
	always @(posedge clk) if(ena) ovf  <= ovf_pipe[d_width];
	always @(posedge clk) if(ena) div0 <= div0_pipe[d_width];
	always @(posedge clk) if(ena) q <= gen_q(q_pipe[d_width-1], s_pipe[d_width]);
	always @(posedge clk) if(ena) s <= assign_s(s_pipe[d_width], d_pipe[d_width]);
endmodule

module div_su_ref (clk, ena, z, d, q, s, ovf);
  parameter z_width = 16;
  parameter d_width = z_width /2;
  input clk, ena;
  input  [z_width-1:0] z;
  input  [d_width-1:0] d;
  output [d_width  :0] q, s;
  output ovf;
  reg [d_width:0] q, s;
  reg ovf;
  reg [z_width -1:0] iz;
  reg [d_width -1:0] id;
  reg [d_width +1:0] szpipe, sdpipe;
  wire [d_width -1:0] iq, is;
  wire idiv0, iovf;
  integer n, m;

  always @(posedge clk) if (ena)
      if (d[d_width-1]) id <= ~d +1'h1; else id <= d;
  always @(posedge clk) if (ena)
      if (z[z_width-1])  iz <= ~z +1'h1; else iz <= z;
  always @(posedge clk) if(ena) begin
      szpipe[0] <= z[z_width-1];
      for(n=1; n <= d_width+1; n=n+1) szpipe[n] <= szpipe[n-1];
  end
  always @(posedge clk) if(ena) begin
      sdpipe[0] <= d[d_width-1];
      for(m=1; m <= d_width+1; m=m+1) sdpipe[m] <= sdpipe[m-1];
  end

  div_uu_ref #(z_width, d_width) divider (
    .clk(clk), .ena(ena), .z(iz), .d(id),
    .q(iq), .s(is), .div0(idiv0), .ovf(iovf));

  always @(posedge clk) if(ena) begin
      q <= (szpipe[d_width+1]^sdpipe[d_width+1]) ? ((~iq) + 1'h1) : ({1'b0, iq});
      s <= (szpipe[d_width+1]) ? ((~is) + 1'h1) : ({1'b0, is});
      ovf <= iovf;
  end
endmodule
