//
// USB HID to PS/2 Set-2 scancode converter
//
// Converts an Analogue Pocket docked USB keyboard (6 concurrent HID usage codes
// + a modifier byte, packed into cont3_*) into ps2_key events
// {strobe, pressed, ext, code[7:0]}. The HID-usage -> Set-2 mapping follows the
// public USB HID Keyboard and PS/2 Set-2 specifications.
//
// Within one report, modifier makes are emitted before key makes and key breaks
// before modifier breaks, so a chord holds its modifier around the key.
//

module hid_to_ps2
(
	input             clk,
	input             reset,
	input      [31:0] joy,     // cont3_joy
	input      [15:0] trig,    // cont3_trig
	input       [7:0] mods,    // modifier byte
	output reg [10:0] ps2_key  // {strobe, pressed, ext, code[7:0]}
);

reg [47:0] prev_raw;
reg  [7:0] prev_mods;

wire [47:0] curr_raw = {joy, trig};
wire data_changed = (curr_raw != prev_raw) || (mods != prev_mods);

reg [47:0] scan_curr, scan_prev;
reg  [7:0] scan_mcurr, scan_mprev;

function automatic [7:0] slot_code;
	input [47:0] pdata;
	input [2:0]  idx;
	case (idx)
		0: slot_code = pdata[47:40];
		1: slot_code = pdata[39:32];
		2: slot_code = pdata[31:24];
		3: slot_code = pdata[23:16];
		4: slot_code = pdata[15:8];
		5: slot_code = pdata[7:0];
		default: slot_code = 8'h00;
	endcase
endfunction

function automatic code_in;
	input [7:0]  code;
	input [47:0] pdata;
	code_in = (code != 8'h00) && (
		code == pdata[47:40] || code == pdata[39:32] ||
		code == pdata[31:24] || code == pdata[23:16] ||
		code == pdata[15:8]  || code == pdata[7:0]);
endfunction

// HID usage code to PS/2 Set-2 scancode, plus the E0-extension flag: the
// table is a 256x9 block ROM ({ext, code}) read through two registered
// ports -- port A looks up the CURRENT report's slot byte, port B the
// previous report's. The ~150-entry case table it replaced cost ALMs a
// hardware scan this size cannot spare; the ROM costs one M10K, which is
// the resource the fit has headroom in.
//
// The price is one clock of latency: map[...] lands in roma_q/romb_q the
// cycle AFTER slot presents the byte, so every scan state runs one beat
// past its last slot while slot_q/c_at_q/p_at_q/mc_q/mp_q drain -- the
// press/release decisions evaluate the registered copies, never the live
// slot. state_q guards the boundary so a lookup issued by the previous
// state cannot emit in this one.
(* ramstyle = "M10K" *) reg [8:0] map [0:255];

`ifdef SYNTHESIS
	// Quartus resolves $readmemh against the project directory (fpga/).
	initial $readmemh("core/hid2ps2.hex", map);
`else
	// The benches run Verilator from the repository root.
	initial $readmemh("fpga/core/hid2ps2.hex", map);
`endif

reg [8:0] roma_q, romb_q;   // {ext, code} for the curr / prev slot bytes
reg [7:0] c_at_q,  p_at_q;  // those bytes themselves, aligned with the ROM
reg [2:0] slot_q;
reg [2:0] state_q;
reg       mc_q, mp_q;       // modifier byte bits for slot_q

function automatic [7:0] mod2ps2;
	input [2:0] idx;
	case (idx)
		3'd0: mod2ps2 = 8'h14; // lctrl
		3'd1: mod2ps2 = 8'h12; // lshift
		3'd2: mod2ps2 = 8'h11; // lalt
		3'd3: mod2ps2 = 8'h00; // lgui
		3'd4: mod2ps2 = 8'h14; // rctrl
		3'd5: mod2ps2 = 8'h59; // rshift
		3'd6: mod2ps2 = 8'h11; // ralt
		3'd7: mod2ps2 = 8'h00; // rgui
	endcase
endfunction

// Right Ctrl / Right Alt are E0-extended.
function automatic mod_ext;
	input [2:0] idx;
	mod_ext = (idx == 3'd4) || (idx == 3'd6);
endfunction

// slot is 4 bits so the drain beat can count one past the last index; every
// consumer below wants the low 3 -- at slot==8 that wraps to slot 0, which is
// exactly the re-present the drain beat relies on.
wire [7:0] curr_at   = slot_code(scan_curr, slot[2:0]);
wire [7:0] prev_at   = slot_code(scan_prev, slot[2:0]);

always @(posedge clk) begin
	roma_q  <= map[curr_at];
	romb_q  <= map[prev_at];
	c_at_q  <= curr_at;
	p_at_q  <= prev_at;
	mc_q    <= scan_mcurr[slot[2:0]];
	mp_q    <= scan_mprev[slot[2:0]];
	slot_q  <= slot[2:0];
	state_q <= state;
end

wire [7:0] ps2_curr  = roma_q[7:0];
wire       curr_ext  = roma_q[8];
wire [7:0] ps2_prev  = romb_q[7:0];
wire       prev_ext  = romb_q[8];
wire [7:0] ps2_mod   = mod2ps2(slot_q);
wire       mod_ext_w = mod_ext(slot_q);

wire is_new_press   = (c_at_q != 8'h00) && (ps2_curr != 8'h00)
                    && !code_in(c_at_q, scan_prev);
wire is_new_release = (p_at_q != 8'h00) && (ps2_prev != 8'h00)
                    && !code_in(p_at_q, scan_curr);
wire is_mod_press   = mc_q && !mp_q && (ps2_mod != 8'h00);
wire is_mod_release = !mc_q && mp_q && (ps2_mod != 8'h00);

// A phantom-rollover report (ErrorRollOver 0x01 in the key slots) is ignored so held
// keys are not spuriously released when more keys are down than the keyboard can report.
wire rollover = code_in(8'h01, curr_raw);

localparam S_IDLE     = 3'd0,
           S_MPRESS   = 3'd1,
           S_PRESS    = 3'd2,
           S_RELEASE  = 3'd3,
           S_MRELEASE = 3'd4;

reg [2:0] state;
reg [3:0] slot;   // 0..8: the drain beat presents one past the last slot

always @(posedge clk) begin
	if (reset) begin
		state     <= S_IDLE;
		slot      <= 0;
		ps2_key   <= 0;
		prev_raw  <= 0;
		prev_mods <= 0;
			end else begin
		case (state)

		S_IDLE: begin
			if (data_changed && !rollover) begin
				scan_curr  <= curr_raw;
				scan_prev  <= prev_raw;
				scan_mcurr <= mods;
				scan_mprev <= prev_mods;
				prev_raw   <= curr_raw;
				prev_mods  <= mods;
				state      <= S_MPRESS;
				slot       <= 0;
			end
		end

		// Each scan state presents one slot's addresses per beat and emits
		// the PREVIOUS beat's decision -- the map ROM reads a cycle late.
		// `slot` therefore walks one step past the last real index: the
		// drain beat evaluates slot count-1 while presenting slot 0 again,
		// and `state_q == <state>` blocks the pipeline tail the previous
		// state left behind on the entry beat.
		S_MPRESS: begin
			if (state_q == S_MPRESS && is_mod_press)
				ps2_key <= {~ps2_key[10], 1'b1, mod_ext_w, ps2_mod};
			if (slot == 4'd8) begin
				state <= S_PRESS;
				slot  <= 0;
			end else
				slot <= slot + 1'd1;
		end

		S_PRESS: begin
			if (state_q == S_PRESS && is_new_press)
				ps2_key <= {~ps2_key[10], 1'b1, curr_ext, ps2_curr};
			if (slot == 4'd6) begin
				state <= S_RELEASE;
				slot  <= 0;
			end else
				slot <= slot + 1'd1;
		end

		S_RELEASE: begin
			if (state_q == S_RELEASE && is_new_release)
				ps2_key <= {~ps2_key[10], 1'b0, prev_ext, ps2_prev};
			if (slot == 4'd6) begin
				state <= S_MRELEASE;
				slot  <= 0;
			end else
				slot <= slot + 1'd1;
		end

		S_MRELEASE: begin
			if (state_q == S_MRELEASE && is_mod_release)
				ps2_key <= {~ps2_key[10], 1'b0, mod_ext_w, ps2_mod};
			if (slot == 4'd8)
				state <= S_IDLE;
			else
				slot <= slot + 1'd1;
		end

		default: state <= S_IDLE;

		endcase
	end
end

endmodule
