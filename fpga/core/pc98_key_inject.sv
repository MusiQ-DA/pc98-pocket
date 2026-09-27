// pc98_key_inject -- merge JTAG-written keystrokes into the keyboard event
// line that feeds pc98_kbd8251.
//
// pc98_jtag_probe exposes a write port: every scan whose address byte has
// bit 7 set is a write, carried upstream as a one-clock wr_pulse in this
// module's clock domain with {wr_addr, wr_data} holding the payload. A write
// to slot 0x81 (wr_addr == 1) carries a PC-98 matrix byte in wr_data[7:0]
// (bit 7 = release). Each such write lands exactly one more toggle on the
// shared key_stb line, so the 8251 cannot tell an injected event from a
// tapped one.
//
// src_jtag keeps key_make/key_code coherent: they belong to whichever side
// produced the most recent event. The physical strobe goes through kbd_stb_q
// so that a real edge and the src_jtag clear commit on the same clock -- the
// 8251 then sees the strobe toggle and the new owner of key_code together,
// never a physical toggle sampled against a stale injected byte. A same-cycle
// kbd edge and JTAG write cancels in the XOR (one event lost); both sources
// pace their events far wider than a clock, so the collision is theoretical.

`default_nettype none

module pc98_key_inject (
    input  wire        clk,
    input  wire        wr_pulse,
    input  wire [6:0]  wr_addr,
    input  wire [31:0] wr_data,
    input  wire        kbd_stb,
    input  wire        kbd_make,
    input  wire [7:0]  kbd_code,
    output wire        key_stb,
    output wire        key_make,
    output wire [7:0]  key_code
);
    logic       jtag_stb = 1'b0;
    logic [7:0] jtag_byte = 8'h00;
    logic       src_jtag = 1'b0;
    logic       kbd_stb_q = 1'b0;

    always_ff @(posedge clk) begin
        kbd_stb_q <= kbd_stb;
        if (kbd_stb != kbd_stb_q)
            src_jtag <= 1'b0;
        if (wr_pulse) begin
            jtag_byte <= wr_data[7:0];
            if (wr_addr == 7'h01) begin
                jtag_stb <= ~jtag_stb;
                src_jtag <= 1'b1;
            end
        end
    end

    assign key_stb  = kbd_stb_q ^ jtag_stb;
    assign key_make = src_jtag ? ~jtag_byte[7] : kbd_make;
    assign key_code = src_jtag ? jtag_byte     : kbd_code;
endmodule

`default_nettype wire
