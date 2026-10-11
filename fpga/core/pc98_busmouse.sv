//
// PC-98 bus mouse: the second 8255 at 0x7FD9-0x7FDF plus the interrupt
// timing port at 0xBFDB, per np21w io/mouseif.c ("マウス ver0.28").
//
// Registers
//   0x7FD9  port A   read: {L-released, 1, R-released, 0} | axis nibble
//                    write: port A latch (read back when port A is output)
//   0x7FDB  port B   read: 0x40 when input / portb latch when output
//   0x7FDD  port C   bit7 latch X/Y, bit6 axis (1=Y), bit5 nibble (1=high),
//                    bit4 IRQ mask (0 = enabled); write goes through setportc
//   0x7FDF  control  bit7 set: mode word; clear: port C bit set/reset
//   0xBFDB  timing   bits[1:0] pick the IRQ period (base/1,2,4,8)
//
// The mouse itself is the shared pc98_mouse_src stream: each m_ev step adds
// into signed 16-bit counters; a rising port C bit 7 snapshots them clamped
// to +/-127 into latch_x/latch_y and clears the counters.
//
// The interrupt is slave-PIC IRQ13 (np21w pic_setirq(0x0d)): while port C
// bit 4 is clear a down-counter fires every (clk_rate/120) << timing
// clocks -- 120, 60, 30, 15 Hz.
//

module pc98_busmouse #(
    parameter clk_rate = 28'd42954545    // chipset clock, sets the IRQ divisor
) (
    input               clk,
    input               rst,
    // guest bus -- cs is the decode of 0x7FD9/B/D/F, sel is address[2:1]
    input               cs,
    input         [1:0] sel,
    input               wr,             // ~io_write_n (raw strobe)
    input               rd,             // ~io_read_n  (raw strobe)
    input               tmr_cs,         // 0xBFDB decode (write only)
    input         [7:0] din,
    output reg    [7:0] dout,
    output              read_select,
    output              irq,
    // shared mouse stream (pc98_mouse_src, same domain)
    input  signed [15:0] m_dx,
    input  signed [15:0] m_dy,
    input               m_ev,
    input         [1:0] m_btn          // {right, left}, 1 = pressed
);

    wire w = cs & wr;
    wire r = cs & rd;

    // np21w mouseif_reset: porta 0, portb 0, portc 0xF0, mode 0x93,
    // latch_x/latch_y -1.
    reg  [7:0]        porta  = 8'h00;
    reg  [7:0]        portb  = 8'h00;
    reg  [7:0]        portc  = 8'hF0;
    reg  [7:0]        mode   = 8'h93;
    reg  [1:0]        timing = 2'd0;
    reg  signed [15:0] mx = 16'sd0, my = 16'sd0;
    reg  signed [7:0]  latch_x = -8'sd1, latch_y = -8'sd1;
    // np21w mouseif_limitcounter: for the four port A reads after a latch the
    // live counter is clamped to the signed-8 range, so a game that reads
    // past the latch cannot see a wrapped nibble and fling the cursor.
    reg  [2:0]        limitctr = 3'd0;
    reg               rd_q = 1'b0;

    // The pending step folds into both the latch snapshot and the counter
    // clear, the way np21w's calc_mousexy() applies rx before setportc
    // stores and zeroes x/y.
    wire signed [16:0] mx_n = mx + (m_ev ? m_dx : 17'sd0);
    wire signed [16:0] my_n = my + (m_ev ? m_dy : 17'sd0);

    // np21w clamps the latched snapshot to [-128, +127].
    function signed [7:0] cap8(input signed [16:0] v);
        cap8 = (v > 17'sd127) ? 8'sd127 : (v < -17'sd128) ? -8'sd128 : v[7:0];
    endfunction

    //
    // Writes. setportc(value) is shared by the port C write (sel==2) and the
    // bit set/reset half of the control port (sel==3 with bit7 clear); a mode
    // write touches only mode, exactly like np21w.
    //
    wire [7:0] bsr_val  = (portc & ~(8'h01 << din[3:1]))
                        | ({7'b0000000, din[0]} << din[3:1]);
    wire [7:0] next_pc  = (sel == 2'd2) ? din : bsr_val;
    wire       pc_write = w & ((sel == 2'd2) | ((sel == 2'd3) & ~din[7]));
    wire       latch_take = pc_write & next_pc[7] & ~portc[7];
    wire       porta_rd_level = r & (sel == 2'd0);

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            porta     <= 8'h00;
            portb     <= 8'h00;
            portc     <= 8'hF0;
            mode      <= 8'h93;
            timing    <= 2'd0;
            mx        <= 16'sd0;
            my        <= 16'sd0;
            latch_x   <= -8'sd1;
            latch_y   <= -8'sd1;
            limitctr  <= 3'd0;
            rd_q      <= 1'b0;
        end else begin
            rd_q <= porta_rd_level;
            if (w & (sel == 2'd0)) porta <= din;
            if (w & (sel == 2'd1)) portb <= din;
            if (w & (sel == 2'd3) & din[7]) mode <= din;
            if (tmr_cs & wr) timing <= din[1:0];

            if (pc_write) portc <= next_pc;
            if (latch_take) begin
                latch_x  <= cap8(mx_n);
                latch_y  <= cap8(my_n);
                mx       <= 16'sd0;
                my       <= 16'sd0;
                limitctr <= 3'd4;
            end else if (m_ev) begin
                mx <= mx + m_dx;
                my <= my + m_dy;
            end
            // A finished port A read retires one count of the post-latch
            // guard (np21w reads x, then decrements); the strobe sits high
            // for the whole bus cycle, so count its falling edge and the
            // clamp still covers the read that used it.
            if (~porta_rd_level & rd_q & mode[4] & (limitctr != 3'd0))
                limitctr <= limitctr - 3'd1;
        end
    end

    //
    // Reads -- combinational; Peripherals' mux registers the byte.
    //
    wire signed [15:0] axis_x = portc[7] ? {{8{latch_x[7]}}, latch_x} : mx;
    wire signed [15:0] axis_y = portc[7] ? {{8{latch_y[7]}}, latch_y} : my;
    wire signed [15:0] axis_r = portc[6] ? axis_y : axis_x;
    wire signed [7:0]  axis_c = cap8({axis_r[15], axis_r});
    wire signed [15:0] axis   = (limitctr != 3'd0)
                              ? {{8{axis_c[7]}}, axis_c} : axis_r;
    wire        [3:0]  nib    = portc[5] ? axis[7:4] : axis[3:0];

    // b & 0xF0 | 0x40 with b's bits 7/5 = button RELEASED (np21w mousemng
    // starts btn at 0xA0 and clears a bit while the button is down).
    wire [7:0] porta_rd = {~m_btn[0], 1'b1, ~m_btn[1], 1'b0, nib};

    // Port C read: PORTCH input masks bits 7:5 (np21w ret &= 0x1f); PORTCL
    // input replaces the low nibble with 0x08 | dipsw bits. The dipsw terms
    // sit at np21w's defaults -- dipsw[0]=0x3E and dipsw[2]=0x7B both
    // contribute zero -- so the nibble is a constant 8 here; revisit if real
    // DIP switches ever land.
    wire [7:0] portc_masked = portc & (mode[3] ? 8'h1F : 8'hFF);
    wire [7:0] portc_rd = mode[0] ? (portc_masked & 8'hF0) | 8'h08
                                  : portc_masked;

    // np21w attaches inputs to 7FD9/B/D only -- 7FDF reads float to 0xFF.
    assign read_select = r & (sel != 2'd3);

    always @* begin
        case (sel)
            2'd0:    dout = mode[4] ? porta_rd : porta;
            2'd1:    dout = mode[1] ? 8'h40 : portb;
            default: dout = portc_rd;
        endcase
    end

    //
    // IRQ timer: np21w nevent on (intrclock << timing) clocks, intrclock =
    // realclock/120. While port C bit 4 is set the counter parks at its
    // reload value, so the next enable waits a full period before the first
    // request, matching the NEVENT_ABSOLUTE arm in setportc.
    //
    localparam [17:0] IRQ_BASE = clk_rate / 120;    // 120 Hz
    reg  [20:0] irq_cnt = 21'd0;
    reg         irq_q   = 1'b0;
    wire [20:0] irq_period = ({3'd0, IRQ_BASE} << timing) - 21'd1;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            irq_cnt <= 21'd0;
            irq_q   <= 1'b0;
        end else if (portc[4]) begin
            irq_cnt <= irq_period;
            irq_q   <= 1'b0;
        end else if (irq_cnt == 21'd0) begin
            irq_cnt <= irq_period;
            irq_q   <= 1'b1;
        end else begin
            irq_cnt <= irq_cnt - 21'd1;
            irq_q   <= 1'b0;
        end
    end

    assign irq = irq_q;

endmodule
