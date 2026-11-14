// pc98_gdc_draw -- the slave GDC's figures, drawn in hardware.
//
// One engine, one shared gdcpset (np21w io/gdc_pset.c: the pattern, the
// clip, the plane address, the write path) fed by a figure walker that
// produces np21w io/gdc_sub.c's dot sequence:
//
//   FIG_LINE  gdcsub_vectl (and gdcsub_vectp: DC forced 0, one dot)
//               for (i = 0; i <= dc; i++) {
//                   step = (((d1 * i) / dc) + 1) >> 1;
//                   gdcpset(major/minor of (x, y) per octant, step)
//               }
//   FIG_RECT  gdcsub_vectr: D dots along vectdir (x, y), D2 along (x2, y2),
//             D back, D2 back -- every dot a gdcpset, the pattern running on.
//
// The firmware (gdc_service.c) still decodes the command: it splits CSRW
// into np21w's x/y (a divide by 40) and picks the write path from the
// charger state; everything else -- DC, D, D2, D1, the octant, TEXTW, the
// WRITE mode, the plane -- is latched here straight out of the slave's
// drawing snapshot when the launch word lands (the snapshot is static
// until the draw retires). The softcore runs ~1 us an instruction, so
// every field it does not have to touch is time the guest's DRAWING bit is
// not waiting.
//
// LINE's floor(d1*i/dc) is carried, not divided: after each dot the
// remainder takes d1 and gives back dc as many times as it holds it, one
// subtraction a clock, each one a quotient step. A real line has d1 <= 2*dc
// (D1 is twice the minor axis), so that is at most two clocks a dot;
// nonsense parameters only cost time (about d1 clocks a line), never
// exactness.
//
// Every guest byte goes out on the service channel exactly as the
// firmware's vr_read8/vr_write8 sent it (the softcpu_subsystem muxes this
// engine onto st_* while it runs), so the GVRAM sequencer's charger, line
// buffer and write-back see the same traffic shape:
//
//   MODE_PLAIN  no charger: read-modify-write of the addressed plane byte,
//               np21w's _replace0/_replace1/_complemnt/_clear/_set.
//   MODE_RMW    GRCG RMW: one charger write whose operand is the dot mask
//               (np21w withrmw).
//   MODE_WORD   GRCG TDW / EGC: a word write as two bytes, the dot mask in
//               the addressed lane (np21w withtdw/withegc), one per dot.
//
// PLAIN and RMW keep the byte the figure is on in a one-byte write-back
// holder: consecutive dots in one byte modify it in place and it goes out
// when the figure leaves the byte (or ends). Each dot's effect on a byte is
// a per-bit operation, so folding a run of them into one access leaves the
// same VRAM as np21w's dot-by-dot stores. An off dot of COMPLEMENT/CLEAR/
// SET (np21w _nop) and every off dot through a charger touch nothing.
//
// Register window (softcpu_subsystem, word stores, ready-qualified):
//   +0x0  {y[15:0], x[15:0]}            np21w pset.x/pset.y
//   +0xC  go: {abort[31], fig[12:10], dot_only[9], mode[8:7]}; the rest
//         from the snapshot (dot_only: np21w's vectp, one gdcpset at (x, y))
//   read +0xC: {31'b0, busy}

module pc98_gdc_draw (
    input  wire        clk,
    input  wire        reset,
    input  wire        wr,        // one-cycle store into the window
    input  wire [1:0]  wr_sel,    // word index
    input  wire [31:0] wr_data,
    input  wire [255:0] snap,     // the slave's drawing snapshot, byte i at [8i +: 8]
    output wire        busy,

    output reg         st_req,
    output reg         st_we,
    output wire [19:0] st_addr,
    output wire [7:0]  st_wdata,
    input  wire        st_done,
    input  wire [7:0]  st_rdata
);
    localparam MODE_PLAIN = 2'd0, MODE_RMW = 2'd1, MODE_WORD = 2'd2;
    localparam FIG_LINE = 3'd0, FIG_RECT = 3'd1, FIG_VECTT = 3'd2, FIG_TEXT = 3'd3;
    localparam BIT_TEXT_CMD = 13;  // go word: the TEXTE flavour -- dot/line/
                                   // rect draw with para[27] doubled

    localparam S_IDLE = 3'd0, S_DOT = 3'd1, S_RD = 3'd2, S_FL = 3'd3,
               S_W2A = 3'd4, S_W2B = 3'd5, S_W2C = 3'd6;

    reg [2:0]  s;
    reg [15:0] x, y, pat, d1;
    reg [16:0] q1;                // floor(d1*i/dc) + 1, so the step is q1/2
    reg [16:0] r;                 // d1*i mod dc, plus the d1 not yet given back
    reg [13:0] dc, cnt;
    reg [2:0]  oct;
    reg [2:0]  fig;
    reg [1:0]  ph;                // RECT: the side being drawn
    reg        sl;                // TEXT: VECTW's SL bit picks vectdir[8..15]
    reg        tx;                // TEXTE flavour: figures draw with para[27] doubled
    reg [15:0] ox, oy;            // VECTT/TEXT: the row's origin (np21w pset.x/y)
    reg [3:0]  zm, mcnt, rcnt;    // ZOOM, and the mulx / muly counters
    reg [7:0]  tb;                // TEXT: this row's pattern byte
    reg [2:0]  pn;                // TEXT: patnum[2:0] -- np21w's pat[patnum & 7]
    reg [1:0]  op, plane, mode;
    reg        last;              // every dot evaluated; only the flush left
    reg        hold;              // the write-back byte is live
    reg [14:0] haddr;
    reg [7:0]  hdata;

    assign busy = (s != S_IDLE);

    // ---- this dot: np21w's coordinates for (x, y, step) ------------------
    wire [15:0] step  = q1[16:1];
    // Octants 0/3/4/7 walk y and put the step on x; 1/2/5/6 the reverse.
    // The step adds for 0/1/3/6 and subtracts for 2/4/5/7.
    wire        maj_y = (oct == 3'd0) | (oct == 3'd3) | (oct == 3'd4) | (oct == 3'd7);
    wire        s_sub = (oct == 3'd2) | (oct == 3'd4) | (oct == 3'd5) | (oct == 3'd7);
    wire [15:0] mbase = maj_y ? x : y;
    wire [15:0] mstep = s_sub ? (mbase - step) : (mbase + step);
    wire        f_line = (fig == FIG_LINE);
    wire        f_rect = (fig == FIG_RECT);
    wire        f_char = (fig == FIG_VECTT) | (fig == FIG_TEXT);   // the 2-D walkers
    wire [15:0] px    = (f_line & maj_y) ? mstep : x;
    wire [15:0] py    = (f_line & ~maj_y) ? mstep : y;

    // np21w's vectdir[oct]: {x, y} then {x2, y2}, each -1/0/+1 (2-bit
    // two's complement). RECT walks side ph: dir, dir2, -dir, -dir2.
    reg  [7:0]  vdir;
    always @* case ({sl, oct})
        4'd0:  vdir = {2'b00, 2'b01, 2'b01, 2'b00};
        4'd1:  vdir = {2'b01, 2'b01, 2'b01, 2'b11};
        4'd2:  vdir = {2'b01, 2'b00, 2'b00, 2'b11};
        4'd3:  vdir = {2'b01, 2'b11, 2'b11, 2'b11};
        4'd4:  vdir = {2'b00, 2'b11, 2'b11, 2'b00};
        4'd5:  vdir = {2'b11, 2'b11, 2'b11, 2'b01};
        4'd6:  vdir = {2'b11, 2'b00, 2'b00, 2'b01};
        4'd7:  vdir = {2'b11, 2'b01, 2'b01, 2'b01};
        4'd8:  vdir = {2'b00, 2'b01, 2'b01, 2'b01};   // SL
        4'd9:  vdir = {2'b01, 2'b01, 2'b01, 2'b00};
        4'd10: vdir = {2'b01, 2'b00, 2'b01, 2'b11};
        4'd11: vdir = {2'b01, 2'b11, 2'b00, 2'b11};
        4'd12: vdir = {2'b00, 2'b11, 2'b11, 2'b11};
        4'd13: vdir = {2'b11, 2'b11, 2'b11, 2'b00};
        4'd14: vdir = {2'b11, 2'b00, 2'b11, 2'b01};
        default: vdir = {2'b11, 2'b01, 2'b00, 2'b01};
    endcase
    // VECTT/TEXT: a row ends (cnt = 0) by stepping the origin along (x2, y2)
    wire        rowchg = f_char & (cnt == 14'd0);
    wire [1:0]  rdx0  = (ph[0] | rowchg) ? vdir[3:2] : vdir[7:6];
    wire [1:0]  rdy0  = (ph[0] | rowchg) ? vdir[1:0] : vdir[5:4];
    // negate a -1/0/+1: 11 <-> 01, 00 stays
    wire [1:0]  rdx   = ph[1] ? {rdx0[0] & ~rdx0[1], rdx0[0]} : rdx0;
    wire [1:0]  rdy   = ph[1] ? {rdy0[0] & ~rdy0[1], rdy0[0]} : rdy0;
    // LINE: the major axis steps by one (up for 0/1/2/7, down for 3/4/5/6)
    wire        l_dn  = oct[2] ^ (oct[1] & oct[0]);
    wire [1:0]  ddx   = f_line ? (maj_y ? 2'b00 : {l_dn, 1'b1}) : rdx;
    wire [1:0]  ddy   = f_line ? (maj_y ? {l_dn, 1'b1} : 2'b00) : rdy;
    // y * 80 + x / 8; the plane bases (E0000/A8000/B0000/B8000) have their
    // low fifteen bits clear, so the plane is just the top five.
    wire [15:0] off16 = {1'b0, py[8:0], 6'd0} + {3'd0, py[8:0], 4'd0} + {9'd0, px[9:3]};
    wire [14:0] off   = off16[14:0];
    // gdcpset's clip on the 16-bit coordinates: y > 409, x >= 640, and on
    // row 409 x >= 384 -- which is exactly y * 80 + x / 8 >= 0x8000 (the
    // rows above it end at 408 * 80 + 79 < 0x8000).
    wire        clip  = (py > 16'd409) | (px >= 16'd640) | off16[15];
    wire [7:0]  bitm  = 8'h80 >> px[2:0];
    wire [4:0]  ptop  = (plane == 2'd0) ? 5'b11100 : (plane == 2'd1) ? 5'b10101
                      : (plane == 2'd2) ? 5'b10110 : 5'b10111;
    // VECTT/TEXT prepare the pset with pattern FFFF (every gdcpset is an on
    // dot) and draw only where the figure's own pattern bit is set.
    wire        cbit  = (fig == FIG_TEXT) ? tb[0] : pat[0];
    wire        dot   = f_char | pat[0];
    wire        want  = ~f_char | cbit;
    wire        eff   = want & ~clip & (dot | ((mode == MODE_PLAIN) & (op == 2'd0)));
    wire        hit   = hold & (haddr == off);

    // The byte after this dot: np21w's psettbl[op][dot], or the RMW mask.
    wire [7:0]  mbyte = (s == S_RD) ? st_rdata : hdata;
    reg  [7:0]  nbyte;
    always @* begin
        if (mode != MODE_PLAIN)
            nbyte = (hit ? hdata : 8'h00) | bitm;
        else case (op)
            2'd0:    nbyte = dot ? (mbyte | bitm) : (mbyte & ~bitm);
            2'd1:    nbyte = mbyte ^ bitm;
            2'd2:    nbyte = mbyte & ~bitm;
            default: nbyte = mbyte | bitm;
        endcase
    end

    // ---- the service op on the pins ----------------------------------------
    // S_FL: the held byte. S_RD: this dot's byte. S_W2A/B: the dot's word,
    // even lane first (addr[0] is x[3]).
    wire        w2    = (s == S_W2B) | (s == S_W2C);
    wire        odd   = off[0];
    assign st_addr  = (s == S_FL) ? {ptop, haddr}
                    : (s == S_RD) ? {ptop, off}
                    : {ptop, off[14:1], w2};
    assign st_wdata = (s == S_FL) ? hdata
                    : ((w2 == odd) ? bitm : 8'h00);

    // np21w's next-dot bookkeeping: pattern rotates every dot, the major
    // axis steps, the carried quotient moves on.
    wire [17:0] rsd   = {1'b0, r} - {4'd0, dc};
    // A step that is not a dot: LINE's quotient catching up (r >= dc), RECT
    // moving on to its next side when this one is spent, VECTT/TEXT moving
    // on to the next row.
    wire        norm  = ~last & (f_line ? ~rsd[17] : (cnt == 14'd0));
    // the walk's next position: from the row origin on a row change
    wire [15:0] xn    = (rowchg ? ox : x) + {{14{ddx[1]}}, ddx};
    wire [15:0] yn    = (rowchg ? oy : y) + {{14{ddy[1]}}, ddy};
    // VECTT/TEXT's D: sx = min(D, 768), with D == 0 wrapping round to 768
    // (np21w: ((D - 1) & 3FFF) + 1, at most 768); TEXT's DC:
    // sy = min(DC, 767) (np21w: (DC & 3FFF) + 1, at most 768, kept as sy - 1
    // in r). Both are folded into the GO edge below: Verilator 5.020 (the CI
    // sim's pinned version) fails to re-evaluate derived combinational blocks
    // -- always @* regs and concatenation assigns -- after the snapshot input
    // changes, so every value read out of snap is read directly inside the
    // clocked block, the way the RECT/LINE paths already did.
    wire [15:0] tw    = snap[135:120];
    wire [15:0] twrev;
    genvar gi;
    generate for (gi = 0; gi < 16; gi = gi + 1) begin : g_rev
        assign twrev[gi] = tw[15 - gi];
    end endgenerate
    // np21w's textdraw reads the FULL 8-byte TEXTW area: pat[i] =
    // para[20 + i], so the pattern register is snapshot bytes 15..16
    // (para[20..21]) and 24..29 (para[22..27]) stitched big-endian by
    // pattern index, pat[7] first (patnum starts at 0 and pre-decrements).
    // Loaded on the GO edge (see above): byte-select muxes fed from a wire
    // concatenation of snap part-selects keep their time-zero value under
    // the CI sim's pinned verilator 5.020; here pat8[63:56] is pat[7] =
    // para[27] = snap byte 29.
    reg  [63:0] pat8;
    wire        done_op = st_req & st_done;
    reg         adv;
    always @* begin
        adv = 1'b0;
        case (s)
            S_DOT: if (!last && !st_req && !norm) begin
                       if (!eff)                        adv = 1'b1;
                       else if (mode == MODE_PLAIN)     adv = hit;
                       else if (mode == MODE_RMW)       adv = hit | ~hold;
                   end
            S_RD:  adv = done_op;
            S_W2C: adv = done_op;
            default: ;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            s      <= S_IDLE;
            st_req <= 1'b0;
            st_we  <= 1'b0;
            hold   <= 1'b0;
            last   <= 1'b0;
        end else begin
            if (wr && !busy) begin
                case (wr_sel)
                    2'd0: begin x <= wr_data[15:0]; y <= wr_data[31:16]; end
                    2'd3: if (!wr_data[31]) begin
                        // np21w's vectdraw fields: VECTW ope / DC / D1,
                        // CSRW's plane bits, TEXTW, the WRITE mode
                        oct   <= snap[2:0];
                        fig   <= wr_data[12:10];
                        ph    <= 2'd0;
                        sl    <= (wr_data[12:10] == FIG_TEXT) & snap[7];
                        tx    <= wr_data[BIT_TEXT_CMD];
                        zm    <= snap[139:136];
                        mcnt  <= snap[139:136];
                        rcnt  <= snap[139:136];
                        ox    <= x;
                        oy    <= y;
                        pn    <= 3'd7;           // np21w patnum-- from 0: pat[7]
                        // pat8: one assignment per byte -- a single
                        // concatenation of snap part-selects here kept its
                        // time-zero value under Verilator 5.020
                        pat8[63:56] <= snap[239:232];
                        pat8[55:48] <= snap[231:224];
                        pat8[47:40] <= snap[223:216];
                        pat8[39:32] <= snap[215:208];
                        pat8[31:24] <= snap[207:200];
                        pat8[23:16] <= snap[199:192];
                        pat8[15:8]  <= snap[135:128];
                        pat8[7:0]   <= snap[127:120];
                        tb    <= snap[239:232];  // pat[7] -- pat8 lands next edge
                        if (wr_data[12:10] == FIG_VECTT || wr_data[12:10] == FIG_TEXT) begin
                            // sx = min(D, 768), D == 0 -> 768; sy1 = min(DC, 767)
                            dc  <= (snap[37:24] == 14'd0 || snap[37:24] >= 14'd768)
                                 ? 14'd768 : snap[37:24];
                            cnt <= (snap[37:24] == 14'd0 || snap[37:24] >= 14'd768)
                                 ? 14'd768 : snap[37:24];
                            r   <= {7'd0, (snap[21:8] >= 14'd767)
                                 ? 10'd767 : snap[17:8]};
                        end else if (wr_data[12:10] == FIG_RECT) begin
                            // D in dc, D2 in d1 (VECTW bytes 3-4, 5-6)
                            dc  <= snap[37:24];
                            cnt <= snap[37:24];
                            d1  <= {2'b00, snap[53:40]};
                        end else begin
                            // DC = 0 is one dot, after which last stops the
                            // quotient; any nonzero divisor keeps r = 0 from
                            // stepping it before that dot.
                            dc  <= (wr_data[9] || snap[21:8] == 14'd0) ? 14'h3FFF : snap[21:8];
                            cnt <= wr_data[9] ? 14'd0 : snap[21:8];
                            d1  <= snap[71:56];
                        end
                        plane <= snap[103:102];
                        // VECTT's SL runs the pattern backwards (GDCPATREVERSE);
                        // TEXTE's figures run with para[27] doubled instead
                        // (np21w textdraw's textw) -- read straight from snap
                        pat   <= wr_data[BIT_TEXT_CMD] ? {snap[239:232], snap[239:232]}
                               : ((wr_data[12:10] == FIG_VECTT) & snap[7]) ? twrev : tw;
                        op    <= snap[145:144];
                        mode  <= wr_data[8:7];
                        q1    <= 17'd1;
                        if (wr_data[12:10] != FIG_VECTT && wr_data[12:10] != FIG_TEXT)
                            r <= 17'd0;
                        hold  <= 1'b0;
                        last  <= 1'b0;
                        s     <= S_DOT;
                    end
                    default: ;
                endcase
            end else if (wr && wr_sel == 2'd3 && wr_data[31]) begin
                // abort: the firmware gave up waiting on a wedged channel
                s      <= S_IDLE;
                st_req <= 1'b0;
                hold   <= 1'b0;
            end else begin
                if (done_op)
                    st_req <= 1'b0;
                case (s)
                    S_DOT: if (!st_req) begin
                        if (norm && f_line) begin
                            r  <= rsd[16:0];
                            q1 <= q1 + 17'd1;
                        end else if (norm && f_char) begin
                            // the next row: origin += (x2, y2), back to its
                            // first column; muly rows, TEXT's sy of them
                            x    <= xn;  y  <= yn;
                            ox   <= xn;  oy <= yn;
                            cnt  <= dc;
                            mcnt <= zm;
                            if (rcnt != 4'd0) begin
                                rcnt <= rcnt - 4'd1;
                                tb   <= pat8[{pn, 3'b000} +: 8];
                            end else if (fig == FIG_TEXT && r[9:0] != 10'd0) begin
                                // np21w's patnum--: the next row's byte,
                                // wrapping mod 8 back to pat[7]
                                r    <= r - 17'd1;
                                rcnt <= zm;
                                pn   <= pn - 3'd1;
                                tb   <= pat8[{pn - 3'd1, 3'b000} +: 8];
                            end else
                                last <= 1'b1;
                        end else if (norm) begin
                            // RECT: the next side (D, D2, D, D2), then done
                            ph  <= ph + 2'd1;
                            cnt <= ph[0] ? dc : d1[13:0];
                            if (ph == 2'd3)
                                last <= 1'b1;
                        end else if (last) begin
                            if (hold) begin
                                st_req <= 1'b1; st_we <= 1'b1; s <= S_FL;
                            end else
                                s <= S_IDLE;
                        end else if (eff) begin
                            if (mode == MODE_WORD) begin
                                st_req <= 1'b1; st_we <= 1'b1; s <= S_W2A;
                            end else if (hold && !hit) begin
                                st_req <= 1'b1; st_we <= 1'b1; s <= S_FL;
                            end else if (hit || mode == MODE_RMW) begin
                                hdata <= nbyte;
                                haddr <= off;
                                hold  <= 1'b1;
                            end else begin
                                st_req <= 1'b1; st_we <= 1'b0; s <= S_RD;
                            end
                        end
                    end
                    S_RD: if (done_op) begin
                        hdata <= nbyte;
                        haddr <= off;
                        hold  <= 1'b1;
                        s     <= S_DOT;
                    end
                    S_FL: if (done_op) begin
                        hold <= 1'b0;
                        s    <= S_DOT;
                    end
                    S_W2A: if (done_op) s <= S_W2B;
                    S_W2B: if (!st_req) begin
                        st_req <= 1'b1; st_we <= 1'b1; s <= S_W2C;
                    end
                    S_W2C: if (done_op) s <= S_DOT;
                    default: ;
                endcase
                if (adv) begin
                    x   <= xn;
                    y   <= yn;
                    if (f_char) begin
                        // one mulx step; the column's last one moves the
                        // figure pattern on (np21w rotates it per column)
                        if (mcnt == 4'd0) begin
                            mcnt <= zm;
                            cnt  <= cnt - 14'd1;
                            if (fig == FIG_TEXT) tb  <= {tb[0], tb[7:1]};
                            else                 pat <= {pat[0], pat[15:1]};
                        end else
                            mcnt <= mcnt - 4'd1;
                    end else begin
                        pat <= {pat[0], pat[15:1]};
                        r   <= r + {1'b0, d1};
                        if (cnt == 14'd0)
                            last <= 1'b1;     // LINE: the dc + 1'th dot
                        else
                            cnt <= cnt - 14'd1;
                    end
                end
            end
        end
    end
endmodule
