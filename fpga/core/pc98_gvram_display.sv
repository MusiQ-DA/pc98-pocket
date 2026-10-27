//
// pc98_gvram_display -- the graphics plane's display fetch.
//
// The text plane reaches the screen through TVRAM and the glyph row buffer;
// the graphics plane is 128 KB of guest SDRAM (four planes, B/R/G/E, 80 bytes
// per line each) and nothing read it. This module is the graphics half of the
// picture: four line buffers in BRAM hold a ring of display lines, the fill
// runs LOOKAHEAD lines ahead over the font's SDRAM port, and each line's own
// number selects the bank it is shifted out of at the dot clock.
//
// ADDRESSING. RAM.sv stores one guest byte per 16-bit word, so a line of
// eighty dots is eighty SDRAM words: five sixteen-word bursts per plane,
// twenty per line, plus the font's five -- inside the LOOKAHEAD-line window
// even when the round robin queues it behind the other masters. The plane
// bases are the hardware windows (A8000=B, B0000=R, B8000=G, and E
// at E0000, where pc98_gvram_seq keeps it). A line's byte offset inside its
// plane comes from the slave GDC's display registers the way the uPD7220
// walks them: the rasterline selects one of the four PRAM partitions by its
// LEN (lines past the last partition wrap back to the first), and the byte
// address is that partition's SAD plus the line-in-partition times PITCH --
// all word counts, shifted left one and wrapped inside the 32 KB plane.
// The registers are copied once per frame (np21w renders a frame from one
// PRAM state), so a SCROLL rewrite mid-frame applies to the next frame
// whole -- see "the frame snapshot".
//
// DOMAINS. The fetch FSM runs on the chipset clock with the port-D
// handshake; the display shift runs on the dot clock the text renderer uses.
// The two meet in the line ring; the fetch side learns the scanline through
// a gray-coded vcount (multi-bit counters tear through a plain
// synchroniser), and the display side reads each line's own bank -- no
// completion handshake crosses the boundary at all.
//
// Remaining limit: the digital-mode packed palette at 0xA8-0xAE is not
// decoded (the digital path shows the fixed eight colours), and the dot is
// an index into the palette file owned by Peripherals.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_gvram_display #(
    parameter int DOT_BITS = 10,          // hcount/vcount width
    parameter int LINES    = 400,
    parameter bit BAND_PROBE = 1'b1      // the black-band JTAG witness
) (
    input  wire        clk,               // fetch side (chipset)
    input  wire        rst,

    // The dot-clock side: the raster counters the text renderer consumes.
    input  wire        rd_clk,
    input  wire [DOT_BITS-1:0] hcount,
    input  wire [DOT_BITS-1:0] vcount,
    input  wire        disp_on,           // the slave GDC's START seen
    input  wire        disp_page,         // port 0xA4 bit 0: show page one
    input  wire        analog_mode,       // port 0x6A bit 0: plane E exists
    // The "200 line" modes on this fixed 400-line raster: each guest line
    // serves two rasterlines. Set by Peripherals from the slave's CSRFORM
    // LR field / a ~200-line SYNC AL. (mode1 bit 4 is NOT a source: np21w
    // uses it only to keep the odd rasterlines dark -- the mabiki
    // presentation, handled on the output side.)
    input  wire        dbl,
    // The slave's CSRFORM LR field, raw (np21w's `mg.lr = (para[CSRFORM] &
    // 0x1f) + 1`): rasterlines each VRAM line is held for. When software
    // signals 200 lines through SYNC AL instead (`dbl` with LR=0), the walk
    // still has to double for the fixed raster, so the effective stride is
    // two rasterlines.
    input  wire  [4:0]  lrep,

    // The slave GDC's display registers, live from pc98_gdc on this same
    // clock. They are SNAPSHOT ONCE PER FRAME (see "the frame snapshot"
    // below) and the whole frame's partition walk runs on that copy -- the
    // way np21w renders a frame from one PRAM state, so a SCROLL rewrite
    // that lands mid-frame takes effect from the next frame, never mid-walk.
    input  wire  [7:0]  pitch,            // PITCH register value
    input  wire         mhz5,             // port 0x6A clock field == 3
    input  wire  [15:0] part_sad [0:3],   // partition start, word address
    input  wire  [9:0]  part_len [0:3],   // partition length, rasterlines
    input  wire  [3:0]  part_pbyte,       // per-partition LEN[14] pitch unit
    // Rasterlines this plane sits BELOW the top of the frame -- np21w
    // dispsync's grph_vbp: the slave's SYNC VBP minus the master's,
    // floored at zero (vram/dispsync.c). Lines above the offset carry no
    // graphics at all, and the plane's bottom is clipped by the same
    // amount. Every BIOS table gives both GDCs VBP 25, so 0 is the
    // everyday value.
    input  wire  [5:0]  vshift,

    // sdram_mp port side -- the controller's port D, a read-only master of
    // its own so the twenty bursts a line never queue behind the font's five.
    output logic       p_req,
    output logic [23:0] p_addr,
    output logic [3:0]  p_len,
    input  wire         p_ack,
    input  wire         p_rvalid,
    input  wire  [15:0] p_rdata,
    input  wire         p_done,

    // One dot of graphics, aligned with hcount delayed one rd_clk (the
    // buffer read is registered); zero when the plane is off.
    output logic [3:0] gfx_dot,           // {E, R, G, B}

    // Underrun telemetry for the JTAG probe -- the counters described at
    // the bottom of the file, plus the live FSM/line state.
    output wire [63:0] dbg,
    // Black-band / PRAM-timing witness for the JTAG probe (slots 0x84-0x86,
    // scripts/jtag_blackband.tcl) -- see "black-band witness" at the bottom.
    output wire [95:0] dbg_band
);

    // ---- the scanline, gray-coded across the domains ----------------------
    //
    // vcount changes many bits at once; a binary synchroniser can tear it
    // into a wrong line number and the fetch would fill garbage for a frame.
    // Gray changes one bit per step, so any torn sample is a valid neighbour.
    function automatic [8:0] bin2gray(input [8:0] b);
        bin2gray = b ^ (b >> 1);
    endfunction
    function automatic [8:0] gray2bin(input [8:0] g);
        logic [8:0] b;
        b[8] = g[8];
        for (int i = 7; i >= 0; i = i - 1)
            b[i] = b[i+1] ^ g[i];
        gray2bin = b;
    endfunction

    wire [8:0] vcount_gray = bin2gray(vcount[8:0]);
    logic [8:0] gray_s1 = 9'd0, gray_s2 = 9'd0;
    always_ff @(posedge clk) begin
        gray_s1 <= vcount_gray;
        gray_s2 <= gray_s1;
    end
    wire [8:0] line_now = gray2bin(gray_s2);

    // disp_on arrives on rd_clk; the fetch FSM is on clk. The real slave
    // GDC scans display RAM only while STARTed (np21w gdc.c -- display
    // refresh is a START-state behaviour), so a stopped display must not
    // fetch: it would burn a fifth of the SDRAM frame on planes nobody is
    // showing. Two-flop into this domain; the walk keeps tracking while
    // off so a mid-frame START resumes on the right line.
    logic disp_s1 = 1'b0, disp_on_c = 1'b0;
    always_ff @(posedge clk) begin
        disp_s1   <= disp_on;
        disp_on_c <= disp_s1;
    end

    // The only legal moves are +1 and the 439->0 wrap. Gray codes promise
    // single-bit transitions between CONSECUTIVE values only, and the wrap
    // breaks it -- gray(439) and gray(0) differ in six bits, so the 2FF can
    // land mid-transition and line_now flashes garbage for a cycle or two
    // once a frame. A garbage line_now must never look like a new line: a
    // phantom edge would step the fetch walk an extra PITCH and every fill
    // for the rest of the frame would read shifted (wandering band edges).
    // A torn value that happens to equal the expected next line is just
    // the real edge arriving a cycle early, which is harmless -- and any
    // other garbage is rejected, then the true value lands a cycle later.
    localparam int V_LINES = 440;
    logic [8:0] line_q = 9'd0;
    wire  [8:0] line_next = (line_q == 9'(V_LINES - 1)) ? 9'd0
                                                        : line_q + 9'd1;
    wire        line_edge = (line_now == line_next);
    always_ff @(posedge clk) begin
        if (rst)
            line_q <= 9'd0;
        else if (line_edge)
            line_q <= line_now;
    end

    // ---- the buffers -------------------------------------------------------
    //
    // Four banks of four planes of eighty bytes, four memories so the display
    // can read every plane's byte in the same cycle. A packed-3D array lands
    // in registers -- the LABs do not have it -- so each plane is its own
    // flat array marked for M10K, written from its own always block the way
    // the inference template wants. Index is {line[1:0], byte-in-line} with
    // the byte counting 0..79 of a 128-wide bank slot; the tail is unused and
    // 512 bytes still sit inside one M10K, so the two extra banks are free.
    (* ramstyle = "M10K" *) logic [7:0] buf_b [0:511];
    (* ramstyle = "M10K" *) logic [7:0] buf_r [0:511];
    (* ramstyle = "M10K" *) logic [7:0] buf_g [0:511];
    (* ramstyle = "M10K" *) logic [7:0] buf_e [0:511];

    // The bank a line lives in is its own number modulo four: the fill for
    // target T writes bank T[1:0] and the display reads bank vcount[1:0].
    // With a LOOKAHEAD-line fetch the fill and the display never touch the
    // same bank, so no done/use-bank handshake is needed at all -- a skipped
    // fill simply leaves line T-4's bytes in T's bank.
    localparam int LOOKAHEAD = 3;
    logic [1:0]  fill_bank = 2'd0;        // T[1:0] of the running fill

    // The plane bases, as SDRAM word addresses (one guest byte per word, so
    // the guest-linear windows are their own indices). Page one has no guest
    // address -- RAM.sv banks it at 0x600000 + plane*0x8000, where
    // pc98_gvram_seq's access-page writes land it.
    //
    // fill_page is disp_page LATCHED AT LAUNCH: np21w reads gdcs.disp once
    // per line in makegrph, so a page flip mid-fill must not change the
    // base for the bursts still to run -- unlatched, one port-0xA4 write
    // would leave a line half from each page for a whole frame.
    logic        fill_page = 1'b0;

    // ---- the frame snapshot ------------------------------------------------
    //
    // np21w draws a frame in one go -- pccore.c screendisp() (the end of the
    // vsync flag interval, i.e. the start of display line 0) calls
    // drawscreen() -> makegrph(gdcs.disp, ...), and makegrph walks the
    // partitions straight out of gdc.s.para[GDC_SCROLL..] / [GDC_PITCH] /
    // [GDC_CSRFORM] with the page from gdcs.disp. Every displayed line of
    // that frame therefore comes from ONE PRAM state; a SCROLL write that
    // lands while the raster runs is simply seen by the next frame.
    //
    // This walk runs incrementally and LOOKAHEAD lines ahead of the raster,
    // so it copies that state once: at line SNAP_PT, a couple of lines
    // before the first fill of the frame launches (targets 0..2 launch at
    // the line edges 437..439, inside the blank). Everything the walk
    // reads -- all four SAD/LEN/pitch-unit triples, PITCH, the LR stride
    // and the 0xA4 page -- comes from the copy for the whole frame.
    //
    // Why every field and not just SAD: DEPTH.EXE's "Clear!" wipe (loop
    // 0x2E7A5, SCROLL writer 0x30B20) rewrites SAD0/LEN0/SAD1/LEN1 once a
    // frame after its GRCG drawing, i.e. at an arbitrary raster line. With
    // live LEN under an already-started walk, partition 0 ran on the old
    // SAD0 for the NEW (four-longer) LEN0 -- four lines past the VRAM's
    // 400th, then partition 1 four lines short: a seam that slid down the
    // screen with the wipe. Latching only SAD (918bd95, reverted) still
    // paired the frame-old SAD with the live LEN.
    //
    // SNAP_PT is four lines (~160 us) ahead of np21w's instant; a write that
    // lands in that window shows one frame later than np21w, never torn.
    localparam int SNAP_PT = V_LINES - LOOKAHEAD - 2;   // 435
    wire         snap_now = line_edge && (line_now == 9'(SNAP_PT));
    // SAD bits 15:14 never reach the address (np21w `LOW15(vad << 1)`), so
    // only the fourteen that do are copied.
    logic [13:0] sn_sad [0:3];
    logic [9:0]  sn_len [0:3];
    logic [3:0]  sn_pb   = 4'h0;          // per partition: pitch counts bytes
    logic [7:0]  sn_pitch = 8'd0;
    logic [4:0]  sn_lr   = 5'd1;          // mg.lr, rasterlines per vad step
    logic        sn_page = 1'b0;          // 0xA4 display page (gdcs.disp)
    // mg.lr: programmed LR+1 when CSRFORM carries it, else the doubled-mode
    // default of two rasterlines per line so the AL<256 heuristic keeps
    // fetching each line twice.
    wire  [4:0]  live_lr = (lrep != 5'd0) ? (lrep + 5'd1)
                                          : (dbl ? 5'd2 : 5'd1);
    // The pitch unit has two selectors in np21w -- makegrph.c tests the
    // partition's LEN bit 14, maketgrp.c (the text+graphics composite)
    // tests the 5MHz clock flag; either marks PITCH as counting bytes.
    wire  [3:0]  live_pb = part_pbyte | {4{mhz5}};
    always_ff @(posedge clk) begin
        if (snap_now) begin
            for (int i = 0; i < 4; i++) begin
                sn_sad[i] <= part_sad[i][13:0];
                sn_len[i] <= part_len[i];
            end
            sn_pb    <= live_pb;
            sn_pitch <= pitch;
            sn_lr    <= live_lr;
            // The 0xA4 page bit rides in the same copy: the uPD7220's page
            // follows the frame, and DEPTH.EXE flips 0xA4 mid-loop -- per-
            // line sampling tore the frame into two pages (e97d1a6). It is
            // taken HERE rather than at line 0 so the frame's first three
            // lines (fetched in the blank) use the same page as the rest.
            sn_page  <= disp_page;
        end
    end
    function automatic [23:0] plane_base(input [1:0] p);
        if (fill_page)
            plane_base = 24'h600000 + {7'd0, p, 15'd0};
        else case (p)
            2'd0:    plane_base = 24'hA8000;   // B
            2'd1:    plane_base = 24'hB0000;   // R
            2'd2:    plane_base = 24'hB8000;   // G
            default: plane_base = 24'hE0000;   // E
        endcase
    endfunction

    // ---- the fetch FSM -----------------------------------------------------
    localparam int BURST = 16;            // words per transaction
    localparam int CHUNKS = 80 / BURST;   // 5

    // The byte a line starts from: the uPD7220 never multiplies -- inside a
    // partition it just adds PITCH to the running address every LR
    // rasterlines, and running off the partition's LEN restarts from the
    // next entry's SAD. Track it the way np21w makegrph.c does: a 2-bit
    // partition pointer that wraps MOD 4 (`s_scrp = (s_scrp + 4) & 0x0c` --
    // running off partition three goes back to partition zero, not into a
    // fifth area), a rasterline counter inside it, and a `mul` stride for
    // the pitch steps. A zero LEN never ends: np21w's `remain--; if
    // (!remain)` wraps the UINT instead of firing, so the walk parks in
    // that partition forever -- an absorbing state, not a skipped one.
    //
    // The walk leads the raster by LOOKAHEAD lines: when the edge for
    // line_now fires, run_base holds the byte offset of display line
    // (line_now + LOOKAHEAD) mod V_LINES -- the line the fill launched here
    // must bring in -- and the step moves it one line further. That gives a
    // fill roughly three line times to land (~5200 chipset clocks against a
    // ~1730-clock budget that the four-port round robin can occasionally
    // overrun), and a fill that still misses just leaves a bank stale rather
    // than corrupting the walk.
    logic [1:0]  cur_part  = 2'd0;
    logic [9:0]  part_rel  = 10'd0;     // rasterlines spent in the partition
    logic [14:0] run_base  = 15'd0;     // byte offset of the walked line

    // The line the next fill must bring in, modulo the whole V_LINES raster:
    // the frame's first three lines are fetched at the edges 437..439,
    // inside the blank and AFTER the snapshot -- not at 397..399 off the
    // previous frame's state. Only targets the plane actually shows (below
    // the vshift offset, above line LINES) launch a fill or step the walk.
    wire [9:0] tgt_sum  = {1'b0, line_now} + 10'(LOOKAHEAD);
    wire [8:0] fill_tgt = (tgt_sum >= 10'(V_LINES)) ? 9'(tgt_sum - 10'(V_LINES))
                                                  : 9'(tgt_sum);
    wire       tgt_vis  = (fill_tgt < 9'(LINES)) && (fill_tgt >= {3'd0, vshift});

    // np21w vram/makegrph.c grphput_indirty0: per OUTPUT rasterline the
    // partition's remaining LEN decrements (`remain--; if (!remain)`), and
    // independently a `mul` counter steps the VRAM address by PITCH every
    // `mg.lr` rasterlines (`mul--; if (!mul) { mul = mg.lr; vad += pitch; }`).
    // PITCH counts bytes when the snapshot's pitch-unit bit is set, else
    // words doubled into bytes; both `&= 0xfe` floor it even.
    wire  [8:0]  pitch_b  = sn_pb[cur_part] ? {1'b0, sn_pitch[7:1], 1'b0}
                                            : {1'b0, sn_pitch[6:0], 1'b0};
    wire  [9:0]  cur_len  = sn_len[cur_part];
    // The next partition CYCLICALLY -- np21w's s_scrp mask wraps partition
    // three back to partition zero, so the bare `+1` index must wrap too
    // (an unmasked cur_part=3 read lands one slot past the array).
    wire  [13:0] sad_next = sn_sad[(cur_part + 2'd1) & 2'd3];
    logic [4:0]  mul_q    = 5'd1;         // rasterlines to the next vad step
    // The walk restarts at SAD0 on the edge whose target is the line just
    // above the plane's first (vshift - 1, mod V_LINES): the next edge's
    // fill then reads SAD0 for line vshift. That is line 436 + vshift, mod
    // V_LINES -- always after SNAP_PT, so the restart reads the frame's own
    // snapshot.
    wire  [8:0]  wrap_pt  = (vshift >= 6'd4) ? {3'd0, vshift} - 9'd4
                                           : {3'd0, vshift} + 9'(V_LINES - 4);
    wire         w_wrap   = (line_now == wrap_pt);
    // Advance when this rasterline was the partition's last -- a zero LEN
    // never advances (the absorbing case above), and the pointer wraps
    // mod 4 so partition three's end reopens partition zero.
    wire         w_adv    = (cur_len != 10'd0)
                       && (({1'b0, part_rel} + 11'd1) >= {1'b0, cur_len});
    wire         w_pstep  = (mul_q <= 5'd1);
    wire  [14:0] base_next = w_adv   ? {sad_next, 1'b0}
                          : w_pstep ? run_base + 15'(pitch_b)
                          :           run_base;

    always_ff @(posedge clk) begin
        if (rst) begin
            cur_part <= 2'd0;
            part_rel <= 10'd0;
            mul_q    <= 5'd1;
            run_base <= 15'd0;
        end else if (line_edge && w_wrap) begin
            cur_part <= 2'd0;
            part_rel <= 10'd0;
            mul_q    <= sn_lr;
            run_base <= {sn_sad[0], 1'b0};
        end else if (line_edge && tgt_vis) begin
            cur_part <= w_adv ? cur_part + 2'd1 : cur_part;
            part_rel <= w_adv ? 10'd0 : part_rel + 10'd1;
            mul_q    <= (w_adv || w_pstep) ? sn_lr : mul_q - 5'd1;
            run_base <= base_next;
        end
    end

    logic [2:0]  f_plane = 3'd0;
    logic [3:0]  f_chunk = 4'd0;
    logic [3:0]  f_word  = 4'd0;          // 0..15 within the burst
    logic        f_active = 1'b0;
    logic        req_q    = 1'b0;         // want a burst, dropped on ack
    logic [14:0] fill_base = 15'd0;       // byte offset of this line in-plane
    logic [8:0]  act_tgt   = 9'd0;        // display line the running fill serves

    // The buffer writes live in their own blocks, one per plane memory --
    // the M10K inference template. Byte index is {target[1:0], chunk, word}.
    wire  [8:0] w_addr = {fill_bank, f_chunk[2:0], f_word};
    wire        wr     = f_active & p_rvalid;
    always_ff @(posedge clk) if (wr && f_plane[1:0] == 2'd0) buf_b[w_addr] <= p_rdata[7:0];
    always_ff @(posedge clk) if (wr && f_plane[1:0] == 2'd1) buf_r[w_addr] <= p_rdata[7:0];
    always_ff @(posedge clk) if (wr && f_plane[1:0] == 2'd2) buf_g[w_addr] <= p_rdata[7:0];
    always_ff @(posedge clk) if (wr && f_plane[1:0] == 2'd3) buf_e[w_addr] <= p_rdata[7:0];

    // One request per burst, deasserted the cycle the arbiter acks -- the
    // font fetcher drives port B the same way, and holding req through the
    // burst lets the arbiter re-capture a stale address at p_done.
    assign p_req  = req_q;
    assign p_len  = 4'(BURST - 1);
    // The plane byte offset wraps inside the 32 KB plane the way the GDC's
    // own address counter does -- at chunk granularity here, which is exact
    // unless a line straddles the plane end between sixteen-byte marks.
    assign p_addr = plane_base(f_plane[1:0])
                 + {9'd0, (fill_base + 15'(f_chunk) * 15'(BURST)) & 15'h7FFF};

    always_ff @(posedge clk) begin
        if (rst) begin
            f_active <= 1'b0;
            f_plane  <= 3'd0;
            f_chunk  <= 4'd0;
            f_word   <= 4'd0;
            req_q    <= 1'b0;
            fill_bank <= 2'd0;
            fill_page <= 1'b0;
            act_tgt  <= 9'd0;
        end else begin
            if (p_ack) req_q <= 1'b0;
            if (!f_active) begin
                // Launch only while the display runs: STOP means no
                // display-refresh traffic on a real GDC, so no fills here
                // either. A fill already in flight finishes -- its bank is
                // simply stale. Targets above the vshift offset carry no
                // graphics at all (the plane starts lower), so no fill
                // launches for them -- the stale bank never shows because
                // the display side blanks those lines.
                if (disp_on_c && line_edge && tgt_vis) begin
                    // A new line just began: fill the one LOOKAHEAD lines
                    // out into its own bank. The walk is already positioned
                    // at that target, so run_base is its byte offset; the
                    // page is the frame snapshot's (sn_page is stable for
                    // the whole frame, fill_page just pins it per fill).
                    fill_base <= run_base;
                    fill_bank <= fill_tgt[1:0];
                    fill_page <= sn_page;
                    act_tgt   <= fill_tgt;
                    f_plane   <= 3'd0;
                    f_chunk   <= 4'd0;
                    f_active  <= 1'b1;
                    req_q     <= 1'b1;
                end
            end else begin
                if (p_rvalid) f_word <= f_word + 4'd1;
                if (p_done) begin
                    f_word <= 4'd0;
                    if (f_chunk == 4'(CHUNKS - 1)) begin
                        f_chunk <= 4'd0;
                        // A digital machine has no plane E: stop at G and
                        // save the five bursts of bus time per line.
                        if (f_plane == (analog_mode ? 3'd3 : 3'd2)) begin
                            f_plane  <= 3'd0;
                            f_active <= 1'b0;
                        end else begin
                            f_plane <= f_plane + 3'd1;
                            req_q   <= 1'b1;
                        end
                    end else begin
                        f_chunk <= f_chunk + 4'd1;
                        req_q   <= 1'b1;
                    end
                end
            end
        end
    end

    // ---- the display side --------------------------------------------------
    //
    // Byte for the NEXT dot, registered once: the arrays are BRAM. One stage
    // of address, one stage of data -- the output aligns with hcount two
    // dots later, and the merger in Peripherals delays the text pixel to
    // match.
    //
    // The bank is the line's own number, so the read address needs no
    // handshake at all: line N's bytes sit in bank N[1:0], written LOOKAHEAD
    // lines earlier. The only failure left is a fill still running at its
    // target's boundary, which shows last cycle-of-four's line.
    // vshift lines at the top carry no graphics: np21w zero-fills the
    // surface there (dispsync_renewalvertical), the analogue of the slave
    // plane simply not having started yet.
    wire visible    = (hcount < 10'd640) && (vcount < 10'd400)
                   && (vcount >= {4'd0, vshift});
    wire [6:0] n_byi = hcount[9:3];              // 0..79
    wire [2:0] n_bit = ~hcount[2:0];             // MSB is the leftmost dot

    logic [7:0] rd_b, rd_r, rd_g, rd_e;
    logic [2:0] bit_q = 3'd0;
    logic       vis_q = 1'b0;
    wire  [8:0] r_addr = {vcount[1:0], n_byi};
    always_ff @(posedge rd_clk) begin
        bit_q <= n_bit;
        vis_q <= visible;
        rd_b  <= buf_b[r_addr];
        rd_r  <= buf_r[r_addr];
        rd_g  <= buf_g[r_addr];
        rd_e  <= buf_e[r_addr];
    end

    // ---- underrun telemetry ------------------------------------------------
    //
    // skip counts a display-line edge a fill could not launch on because the
    // previous one still ran -- that edge's target keeps its cycle-of-four
    // data. late counts a fill still running when its OWN target's line edge
    // arrives -- the line reads its bank mid-write. Both put stale data on a
    // rasterline: the wandering band edge. max_fill is the worst launch->done
    // length in clk cycles; a line is ~1730 of them, so a number near 5200
    // says the deadline itself is the problem.
    logic [15:0] fill_tmr  = 16'd0;
    logic [15:0] max_fill  = 16'd0;
    logic [7:0]  skip_cnt  = 8'd0;
    logic [7:0]  late_cnt  = 8'd0;
    logic        f_active_q = 1'b0;
    wire         fill_done = f_active_q && !f_active;
    always_ff @(posedge clk) begin
        if (rst) begin
            f_active_q <= 1'b0;
            fill_tmr   <= 16'd0;
            max_fill   <= 16'd0;
            skip_cnt   <= 8'd0;
            late_cnt   <= 8'd0;
        end else begin
            f_active_q <= f_active;
            if (f_active && (fill_tmr != 16'hffff))
                fill_tmr <= fill_tmr + 16'd1;
            if (fill_done) begin
                fill_tmr <= 16'd0;
                if (fill_tmr > max_fill) max_fill <= fill_tmr;
            end
            if (disp_on_c && line_edge && tgt_vis && f_active
                && (skip_cnt != 8'hff))
                skip_cnt <= skip_cnt + 8'd1;
            if (line_edge && f_active && (act_tgt == line_now)
                && (late_cnt != 8'hff))
                late_cnt <= late_cnt + 8'd1;
        end
    end
    assign dbg = { line_now, act_tgt, f_chunk, f_plane, cur_part,
                   dbl, disp_page, disp_on_c, fill_page, f_active,
                   skip_cnt, late_cnt, max_fill };

    wire pb = rd_b[bit_q];
    wire pr = rd_r[bit_q];
    wire pg = rd_g[bit_q];
    wire pe = rd_e[bit_q] & analog_mode;
    // The four planes assemble into the palette index as {E,G,R,B}: the
    // windows in memory order are B,R,G,E and the BIOS's own palette table
    // (ITF trace F8042F) gives index 1 blue, 2 red, 4 green -- so the bit
    // the B0000 window produced is index bit 1, the B8000 window bit 2.
    assign gfx_dot = (disp_on & vis_q) ? {pe, pg, pr, pb} : 4'd0;

    // ---- black-band witness (JTAG slots 0x84-0x86) -------------------------
    //
    // Two questions the "Clear!" wipe raises on hardware, answered without a
    // frame grab:
    //  * how tall is the worst run of consecutive graphics lines whose 640
    //    dots are ALL palette index 0, and where does it start -- for the
    //    last finished frame (lmax/lstart) and the worst frame since power-
    //    up (wmax/wstart), plus how many frames carried a run >= BAND_MIN
    //    (band_cnt). Lines above a nonzero vshift are blank by design and
    //    count as black. Frames with the slave display stopped are skipped.
    //  * how many frames ran on a PRAM snapshot that the guest rewrote
    //    while the frame was being shown (pram_cnt): the live SAD/LEN/
    //    pitch-unit/PITCH differed from the frame's copy at some point
    //    during lines 0..399. Each such write is deferred to the next frame
    //    by design; a pre-snapshot model would have torn that frame there.
    // The band fields live in rd_clk and are read raw by the probe -- they
    // only move once per frame, so a torn read is a one-off, not a trend.
    // BAND_PROBE=0 drops the witness (dbg_band reads zero) if the LABs are
    // ever needed back.
    generate if (BAND_PROBE) begin : g_band
        localparam int BAND_MIN = 8;
        logic        bw_lit    = 1'b0;      // a nonzero dot on this line so far
        logic [8:0]  bw_run    = 9'd0;      // current run of black lines
        logic [8:0]  bw_fmax   = 9'd0, bw_fstart = 9'd0;
        logic [8:0]  bw_lmax   = 9'd0, bw_lstart = 9'd0;
        logic [8:0]  bw_wmax   = 9'd0, bw_wstart = 9'd0;
        logic [15:0] band_cnt  = 16'd0;
        // gfx_dot trails hcount by one rd_clk, so dots 0..639 land at hcount
        // 1..640; the line verdict is taken well after that, at hcount 700.
        wire         bw_eval   = (hcount == 10'd700);
        wire  [8:0]  bw_run1   = bw_run + 9'd1;
        always_ff @(posedge rd_clk) begin
            if (hcount == 10'd0)
                bw_lit <= 1'b0;
            else if (gfx_dot != 4'd0)
                bw_lit <= 1'b1;
            if (bw_eval && (vcount < 10'(LINES))) begin
                if (bw_lit)
                    bw_run <= 9'd0;
                else begin
                    bw_run <= bw_run1;
                    if (bw_run1 > bw_fmax) begin
                        bw_fmax   <= bw_run1;
                        bw_fstart <= vcount[8:0] - bw_run;
                    end
                end
            end
            if (bw_eval && (vcount == 10'(LINES))) begin
                bw_lmax   <= bw_fmax;
                bw_lstart <= bw_fstart;
                if (disp_on) begin
                    if ((bw_fmax >= 9'(BAND_MIN)) && (band_cnt != 16'hffff))
                        band_cnt <= band_cnt + 16'd1;
                    if (bw_fmax > bw_wmax) begin
                        bw_wmax   <= bw_fmax;
                        bw_wstart <= bw_fstart;
                    end
                end
                bw_fmax <= 9'd0;
                bw_run  <= 9'd0;
            end
        end

        logic        pc_seen  = 1'b0;
        logic [15:0] pram_cnt = 16'd0;
        wire         pram_diff =
               (live_pb != sn_pb) || (pitch != sn_pitch)
            || (part_sad[0][13:0] != sn_sad[0]) || (part_len[0] != sn_len[0])
            || (part_sad[1][13:0] != sn_sad[1]) || (part_len[1] != sn_len[1])
            || (part_sad[2][13:0] != sn_sad[2]) || (part_len[2] != sn_len[2])
            || (part_sad[3][13:0] != sn_sad[3]) || (part_len[3] != sn_len[3]);
        always_ff @(posedge clk) begin
            if (rst) begin
                pc_seen  <= 1'b0;
                pram_cnt <= 16'd0;
            end else begin
                if (disp_on_c && (line_q < 9'(LINES)) && pram_diff)
                    pc_seen <= 1'b1;
                if (line_edge && (line_now == 9'(LINES))) begin
                    if (pc_seen && (pram_cnt != 16'hffff))
                        pram_cnt <= pram_cnt + 16'd1;
                    pc_seen <= 1'b0;
                end
            end
        end
        assign dbg_band = { band_cnt, pram_cnt,
                            7'd0, bw_lstart, 7'd0, bw_lmax,
                            7'd0, bw_wstart, 7'd0, bw_wmax };
    end else begin : g_noband
        assign dbg_band = 96'd0;
    end endgenerate

endmodule

`default_nettype wire
