//
// pc98_gdc -- the uPD7220's DISPLAY side. One module, instantiated twice.
//
// WHAT THIS IS AND IS NOT. The 7220 has two faces: it decides what part of
// VRAM reaches the screen, and it draws. This is the first one only --
// docs/PC98_GDC_DESIGN.md has the reasoning, and the short version is that the
// device is at 97 per cent ALMs, the drawing processor is the expensive half,
// and PC-98 software overwhelmingly draws by writing VRAM through the GRCG
// rather than by issuing GDC drawing commands. That last clause is a JUDGEMENT
// AND NOT A MEASUREMENT; the postmon-era counters that watched it are gone.
//
// NOR DOES IT GENERATE THE RASTER. pc98_video_timing already makes 640x400 at
// 24.83 kHz and the picture it produces works. The SYNC parameters are
// therefore RECORDED, not obeyed; moving the raster onto the GDC would put
// everything that currently displays at risk for no gain today.
//
// THE PORTS, from np21w io/gdc.c, because getting this backwards inverts
// every command in the machine:
//
//     0x60 / 0xA0   write -> PARAMETER      read -> STATUS
//     0x62 / 0xA2   write -> COMMAND        read -> the read-back FIFO
//     0x64 / 0xA4   write -> clear the vsync interrupt (not handled here)
//
// np21w pushes both into one FIFO and tags the command with bit 8
// (`gdc.m.fifo[cnt++] = 0x100 | dat`); the tag is what lets a command arrive
// mid-parameter-run and cut it short, which is what a real 7220 does.
//
// THE PARAMETER STORE, from np21w io/gdc_cmd.tbl -- a 256-entry table of
// {where the parameters go, how many}. Two things in it are not obvious and
// both were nearly got wrong here:
//
//   * 0x70-0x7F ARE ONE COMMAND, not two. The low nibble is the start offset
//     into a SIXTEEN-byte PRAM and the count is 16 - offset. np21w's
//     CMD_SCROLL (0x70) and CMD_TEXTW (0x78) are two names for offsets 0 and 8
//     of the same block: GDC_SCROLL is para[12] and GDC_TEXTW is para[20].
//   * ZOOM is 0x46, not 0x06. The enum in gdc_cmd.h says CMD_ZOOM = 0x06 but
//     the TABLE, which is indexed by opcode, puts {GDC_ZOOM, 1} at 0x46 and
//     nothing at 0x06.
//
// THE PRAM IS FOUR PARTITIONS OF FOUR BYTES, and the display walks them in
// turn (np21w vram/makegrex.c calls its partition walker with gpos 0 then 4,
// forever, until the screen is full):
//
//     bytes 0-1   SAD   display address = (SAD << 1) & 0x7FFF
//     bytes 2-3   LEN   lines = (LEN & 0x3FFF) >> 4
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

// MASTER/SLAVE AS A PARAMETER. The two GDCs still decode identically; the
// one thing that differs is the power-on CSRFORM. np21w's gdc_reset seeds
// the master's form to {0F C0 7B} and the slave's P1 to 1, and the BIOS
// never overwrites the difference at boot (see the reset block below), so
// the values a machine's cursor RIDES ON are per-GDC from the first frame.
module pc98_gdc #(
    parameter bit MASTER = 1'b1
) (
    input  wire        clk,
    input  wire        reset,

    // ---- the guest's side --------------------------------------------------
    input  wire        cs,            // this GDC's two ports are addressed
    input  wire        a1,            // 0 = 0x60/0xA0, 1 = 0x62/0xA2
    input  wire        io_read_n,
    input  wire        io_write_n,
    input  wire [7:0]  data_in,
    output wire [7:0]  data_out,

    // ---- what the raster is doing (status bits 6 and 5) --------------------
    // Bit 5 is np21w's gdc.vsync flag, which is NOT the sync pulse: pccore.c
    // sets it in screenvsync (end of the last display line) and clears it in
    // screendisp (start of the first) -- the whole vertical non-display
    // interval, i.e. vblank. The BIOS's "wait low / wait high" retrace polls
    // read exactly that.
    input  wire        hblank,
    input  wire        vblank,

    // ---- what the display side of the core needs ---------------------------
    output wire        disp_on,       // START seen, STOP not
    output wire [7:0]  pitch,         // words per line
    // Four partitions, in PRAM order. A screen with one area sets partition 0
    // to the whole height; the walker in the renderer then never advances.
    // RAW, not interpreted. The two GDCs read the SAME PRAM field DIFFERENTLY:
    // np21w's graphics walker takes LOW15(vad << 1) (vram/makegrex.c) and its
    // text renderer takes LOW12(...) with no shift at all (vram/maketext.c,
    // where the result indexes cells as mem[0xa0000 + edi*2]). Baking either
    // one in here would be right for one consumer and wrong for the other --
    // it was baked in as the graphics form, and that was wrong for text.
    output wire [15:0] part_sad [0:3],
    output wire [9:0]  part_len [0:3],
    // LEN bit 14 per partition: np21w vram/makegrph.c tests it on the slave's
    // LEN word to pick the PITCH unit -- CLEAR means the PITCH register
    // counts words (shift left to bytes), SET means it already counts bytes.
    // Only the graphics walk consumes it; text takes part_bend.
    output wire [3:0]  part_pbyte,
    // Row-unit boundaries for the TEXT walker: bend[k] is the first row of
    // partition k+1, i.e. floor(cum(len[0..k]) / (TEXT_LR+1)), 63 = beyond
    // the deepest row. np21w maketext.c counts LEN in emitted RASTERLINES
    // (`if (!(--scroll))` once per `y++`) and reloads esi mid-row when the
    // count lands there, so the row CONTAINING the boundary is already the
    // new partition's row 0 -- a floor, not a ceil. LEN is not comparable
    // to a row index until divided by the row height, which is why the
    // text consumers take these instead of part_len. The slave side
    // (graphics) counts emitted rasterlines -- makegrph.c decrements
    // `remain` once per output `liney++` -- and does use part_len.
    output wire [5:0]  part_bend [0:2],
    // The cursor, as CSRW and CSRFORM leave it.
    output wire [15:0] cursor_addr,
    output wire [3:0]  cursor_dot,    // dot address within the word
    output wire        cursor_en,
    output wire        cursor_blink_en,
    output wire [4:0]  cursor_top,
    output wire [4:0]  cursor_bottom,
    output wire [5:0]  cursor_rate,
    output wire [1:0]  zoom_disp,
    // CSRFORM P1's low five bits are TEXT_LR on the master (lines per text
    // row minus one) and GRPH_LR on the slave -- np21w's maketgrp walks the
    // graphics partitions one PITCH-step every GRPH_LR+1 rasterlines, which
    // is exactly the line doubling a 200-line mode runs on a 24 kHz raster.
    // The BIOS writes 1 for it (bios18.c: `gdc.s.para[GDC_CSRFORM] = 1`).
    output wire [4:0]  line_rep,
    // SYNC P6:P7 carry the programmed vertical: the low ten bits hold the
    // active-line field (np21w dispsync's `((LOADINTELWORD(para+6)-1) &
    // 0x3ff) + 1`), the top six the VBP. 200 is what the 15.98 kHz table
    // writes, 400 the 24.83 kHz one.
    output wire [9:0]  vlines,

    // ---- the drawing server (the softcore's GDC engine) ---------------------
    // EXECUTE-class commands (VECTE 0x6C, TEXTE 0x68) and completed WDAT
    // runs stop being counted as unknown and land here instead: the
    // snapshot ports hand the softcore the opcode and the whole parameter
    // file, and the done port returns the engine's final EAD (the drawing
    // cursor moves). While a snapshot is pending or the server is drawing,
    // the FIFO-empty status bit clears -- the throttle a real 7220 applies
    // through its FIFO depth, which is what software's "wait FIFO empty"
    // loops are for.
    output wire        draw_req,       // a draw awaits the server
    output wire [7:0]  draw_op,
    output wire        draw_busy,      // status: the server is drawing
    output wire        draw_timeout,   // pulse: the watchdog retired this draw
    input  wire        srv_done_stb,   // the engine finished this draw
    // The snapshot the engine reads, latched the moment the draw lands so
    // the guest cannot race it: 23 bytes = VECTW (11), CSRW (4), TEXTW (2),
    // ZOOM (1), the WRITE-mode byte (1), MASK (2), CODE (2). Served a word
    // at a time.
    output wire [31:0] draw_snap [0:5]
);

    // ------------------------------------------------------------------
    // the parameter store
    // ------------------------------------------------------------------
    // np21w's offsets, kept verbatim so the table above can be read against
    // gdc_cmd.tbl without translating.
    localparam int P_SYNC    = 0;
    localparam int P_ZOOM    = 8;
    localparam int P_CSRFORM = 9;
    localparam int P_PRAM    = 12;   // 16 bytes: four partitions of four
    localparam int P_PITCH   = 28;
    localparam int P_LPEN    = 29;   // read-back only; listed to keep the map whole
    localparam int P_VECTW   = 32;
    localparam int P_CSRW    = 43;
    localparam int P_MASK    = 46;
    localparam int P_CSRR    = 48;   // read-back staging for CSRR (np21w GDC_CSRR)
    localparam int P_WRITE   = 53;   // the last 0x20-family command byte (np21w GDC_WRITE)
    localparam int P_CODE    = 54;   // WDAT/RDAT parameter bytes (np21w GDC_CODE)
    localparam int P_LAST    = 55;

    reg [7:0] para [0:P_LAST];

    // The read-back half, np21w's {snd, ptr} pair rather than a FIFO: every
    // command assigns item->snd = gdc_cmd[data].indatas, so a NEW command
    // discards whatever a previous read-back left unread. CSRR stages five
    // bytes into para[GDC_CSRR] at command time (the three CSRW address
    // bytes, the high one masked to its two live bits, then two zeros) and
    // reads walk ptr through them; LPEN points at the pen latch and no pen
    // is fitted, so para[GDC_LPEN..+2] stays its reset zeros. A read with
    // snd == 0 returns 0xFF, np21w gdc_i62 verbatim.
    reg [2:0] rb_snd;
    reg [5:0] rb_ptr;

    // The drawing server's handshake. draw_pending latches the first EXECUTE
    // with a SNAPSHOT of everything the engine reads (the guest cannot race
    // it); the server clears the request with srv_done_stb, which also runs
    // the post-command reset the 7220 applies to the vector parameters.
    reg        draw_pending;
    reg [7:0]  draw_op_r;
    reg        draw_busy_r;
    // 23 bytes of snapshot in 24 slots: draw_snap packs four to a word, so
    // the last byte of word 5 is padding. It has to exist, or the pack below
    // indexes past the array -- which Verilator allows and Quartus rejects.
    reg [7:0]  snap [0:23];
    assign draw_req     = draw_pending;
    assign draw_timeout = draw_timeouts;
    assign draw_op      = draw_op_r;
    assign draw_busy    = draw_busy_r;
    genvar sk;
    generate
        for (sk = 0; sk < 6; sk = sk + 1) begin : g_snap
            assign draw_snap[sk] = {snap[4*sk+3], snap[4*sk+2], snap[4*sk+1], snap[4*sk]};
        end
    endgenerate

    // Where each snapshot byte comes from. The last four exist for the WDAT
    // family: MASK and the CODE parameter bytes np21w's gdcsub_write reads.
    function automatic logic [5:0] snap_src(input int k);
        if (k <= 10)     snap_src = 6'(P_VECTW + k);       // 32..42
        else if (k <= 14) snap_src = 6'(P_CSRW + k - 11);  // 43..46
        else if (k <= 16) snap_src = 6'(20 + k - 15);      // TEXTW 20..21
        else if (k == 17) snap_src = 6'(P_ZOOM);           // 8
        else if (k == 18) snap_src = 6'(P_WRITE);          // 53: the op byte
        else if (k <= 20) snap_src = 6'(P_MASK + k - 19);  // 46..47
        else if (k <= 22) snap_src = 6'(P_CODE + k - 21);  // 54..55
        else              snap_src = 6'd0;                 // 23: the pad slot
    endfunction

    wire exec_cmd = (wr_d == 8'h6C)   // VECTE
                  | (wr_d == 8'h68);  // TEXTE

    // The watchdog: if the softcore server never answers, force the retire
    // after ~4 frames of pending. A drawing server that hangs would
    // otherwise hold the FIFO-empty throttle -- and every "wait FIFO empty"
    // loop with it -- forever (docs/SOFTCORE_RTL_SPLIT.md's hang hazard).
    // The drawing is simply lost; the machine lives.
    logic [26:0] draw_watch = 27'd0;
    localparam logic [26:0] DRAW_WATCHDOG = 27'd128_000_000;  // ~3 s of 42.95 MHz
    wire draw_timeouts = draw_pending && (draw_watch == DRAW_WATCHDOG);

    // Where the next parameter goes, and how many are still expected. A new
    // command cuts a run short, which is the point of np21w's bit-8 tag.
    reg [5:0] p_dst;
    reg [4:0] p_left;
    // The run's class: a WDAT-write command (0x2x with the read/set bits
    // the way np21w's (cmd & 0xe4) == 0x20 reads them) executes when its
    // parameters complete; anything else just fills the store.
    reg       p_wdat;

    reg       disp_on_r;

    // ------------------------------------------------------------------
    // the command decode
    // ------------------------------------------------------------------
    // {destination, count}. Anything not named here takes no parameters and is
    // swallowed.
    function automatic logic [10:0] decode(input logic [7:0] c);
        logic [5:0] d;
        logic [4:0] n;
        d = 6'd0; n = 5'd0;
        if ((c & 8'h60) == 8'h20) begin
            // The drawing family (np21w gdc_work's (data&0x60)==0x20):
            // WDAT at 0x2x, RDAT at 0xAx. The command byte itself is stored
            // into GDC_WRITE by the caller; the transfer's parameter bytes
            // land in the CODE slots, 0-2 of them by the type field.
            d = P_CODE[5:0];
            n = (c[4:3] == 2'b00) ? 5'd2 :
                (c[4:3] == 2'b01) ? 5'd0 : 5'd1;
        end else casez (c)
            // RESET is {0,0,0} in np21w's table -- it takes NO parameters
            // and does not touch SYNC or the display-enable flag; the BIOS's
            // own init (ITF trace F804E5) sends bare RESET then SYNC_OFF.
            8'h00:          begin d = 6'd0;           n = 5'd0;  end // RESET
            8'h0E, 8'h0F:   begin d = P_SYNC[5:0];    n = 5'd8;  end // SYNC off/on
            8'h46:          begin d = P_ZOOM[5:0];    n = 5'd1;  end // ZOOM
            8'h47:          begin d = P_PITCH[5:0];   n = 5'd1;  end // PITCH
            8'h49:          begin d = P_CSRW[5:0];    n = 5'd3;  end // CSRW
            8'h4A:          begin d = P_MASK[5:0];    n = 5'd2;  end // MASK
            8'h4B:          begin d = P_CSRFORM[5:0]; n = 5'd3;  end // CSRFORM
            8'h4C:          begin d = P_VECTW[5:0];   n = 5'd11; end // VECTW
            8'b0111_????:   begin                                   // PRAM
                            d = 6'(P_PRAM + int'(c[3:0]));
                            n = 5'd16 - 5'(c[3:0]);
                            end
            default:        begin d = 6'd0;           n = 5'd0;  end
        endcase
        decode = {d, n};
    endfunction

    // io_write_n is a multi-cycle level on clk, so a bare cs & ~io_write_n
    // would run every byte through the block below once per clk the strobe
    // spans -- one CSRFORM parameter landed in para[9], para[10] and para[11]
    // alike, and CSRW's low byte repeated into the next slot. Latch the byte
    // while the strobe is low (where the bus holds it stable) and commit it
    // exactly once, on the strobe's rising edge -- the same dedup the FDC
    // and the system ports apply to this bus.
    logic       wr_pend;
    logic [7:0] wr_d;
    logic       wr_a1;

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_pend <= 1'b0;
            wr_d    <= 8'h00;
            wr_a1   <= 1'b0;
        end else begin
            if (cs & ~io_write_n) begin
                wr_d    <= data_in;
                wr_a1   <= a1;
                wr_pend <= 1'b1;
            end else if (io_write_n)
                wr_pend <= 1'b0;
        end
    end

    wire wr_commit = wr_pend & io_write_n;   // once, as the strobe lifts
    wire cmd_wr = wr_commit &  wr_a1;
    wire par_wr = wr_commit & ~wr_a1;

    // The read strobe's level version of the same dedup: the data-port read
    // pops the read-back byte once, as the strobe lifts.
    wire   data_rd_now = cs & a1 & ~io_read_n;
    logic  data_rd_q = 1'b0;

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            p_dst     <= 6'd0;
            p_left    <= 5'd0;
            p_wdat    <= 1'b0;
            disp_on_r <= 1'b0;
            rb_snd <= 3'd0;
            rb_ptr <= 6'd0;
            data_rd_q <= 1'b0;
            draw_pending <= 1'b0;
            draw_op_r    <= 8'h00;
            draw_busy_r  <= 1'b0;
            for (i = 0; i <= 23; i = i + 1) snap[i] <= 8'h00;
            for (i = 0; i <= P_LAST; i = i + 1) para[i] <= 8'h00;
            // np21w gdc_biosreset's other power-on seeds. SYNC is the 24 kHz
            // table this machine's raster runs (the ITF trace's SYNC_OFF
            // writes match defsyncm24/defsyncs24 byte for byte), PITCH is
            // 80 on the master and 40 on the slave, and gdc_vectreset
            // leaves the drawing registers at their post-figure state.
            if (MASTER) begin
                para[P_SYNC + 0] <= 8'h10; para[P_SYNC + 1] <= 8'h4E;
                para[P_SYNC + 2] <= 8'h07; para[P_SYNC + 3] <= 8'h25;
                para[P_SYNC + 4] <= 8'h07; para[P_SYNC + 5] <= 8'h07;
                para[P_SYNC + 6] <= 8'h90; para[P_SYNC + 7] <= 8'h65;
                para[P_PITCH]    <= 8'd80;
            end else begin
                para[P_SYNC + 0] <= 8'h06; para[P_SYNC + 1] <= 8'h26;
                para[P_SYNC + 2] <= 8'h03; para[P_SYNC + 3] <= 8'h11;
                para[P_SYNC + 4] <= 8'h83; para[P_SYNC + 5] <= 8'h07;
                para[P_SYNC + 6] <= 8'h90; para[P_SYNC + 7] <= 8'h65;
                para[P_PITCH]    <= 8'd40;
            end
            para[P_VECTW + 1]  <= 8'h00;   // DC = 0
            para[P_VECTW + 2]  <= 8'h00;
            para[P_VECTW + 3]  <= 8'h08;   // D  = 8
            para[P_VECTW + 4]  <= 8'h00;
            para[P_VECTW + 5]  <= 8'h08;   // D2 = 8
            para[P_VECTW + 6]  <= 8'h00;
            para[P_VECTW + 7]  <= 8'hFF;   // D1 = FFFF
            para[P_VECTW + 8]  <= 8'hFF;
            para[P_VECTW + 9]  <= 8'hFF;   // DM = FFFF
            para[P_VECTW + 10] <= 8'hFF;
            // The CSRFORM power-on values, and why the cursor is nothing
            // without them: the BIOS's boot sends CSRFORM as ONE byte --
            // [0x53B]|0x80, the enable with TEXT_LR -- and never sends the
            // full three, so top/bottom/blink are whatever the chip woke
            // with. np21w's gdc_reset seeds the master to {P1=0F, P2=C0,
            // P3=7B}: LR 15, top 0, bottom 15, blinking (P2 bit5 CLEAR is
            // "does blink" in np21w's inverted reading) -- a blinking full
            // block -- and the BIOS's own form table (FD80:1062, entry
            // 0x1062) opens with the same {0F, 7B} pair. The slave wakes
            // with P1=1 and nothing else. Reset-zero P3 made bottom zero:
            // the cursor a one-line sliver at the top of the right cell,
            // which is what "it blinks, but small and in the wrong place"
            // looked like on hardware.
            if (MASTER) begin
                para[P_CSRFORM + 0] <= 8'h0F;
                para[P_CSRFORM + 1] <= 8'hC0;
                para[P_CSRFORM + 2] <= 8'h7B;
            end else begin
                para[P_CSRFORM + 0] <= 8'h01;
            end
        end else begin
            // The server's completion: retire the request and, for the
            // EXECUTE ops, run the post-command reset np21w's gdc_vectreset
            // applies -- the 7220 clears the vector parameters after a
            // figure draw. WDAT leaves them alone: gdcsub_write ends with
            // DC still valid, and software that writes blocks back to back
            // reprograms nothing between them.
            if (srv_done_stb || draw_timeouts) begin
                draw_pending <= 1'b0;
                draw_watch   <= 27'd0;
                draw_busy_r  <= 1'b1;      // one-cycle hold for stability
                if ((draw_op_r == 8'h6C) | (draw_op_r == 8'h68)) begin
                    para[P_VECTW + 1]  <= 8'h00;   // DC = 0
                    para[P_VECTW + 2]  <= 8'h00;
                    para[P_VECTW + 3]  <= 8'h08;   // D  = 8
                    para[P_VECTW + 4]  <= 8'h00;
                    para[P_VECTW + 5]  <= 8'h08;   // D2 = 8
                    para[P_VECTW + 6]  <= 8'h00;
                    para[P_VECTW + 7]  <= 8'hFF;   // D1 = FFFF
                    para[P_VECTW + 8]  <= 8'hFF;
                    para[P_VECTW + 9]  <= 8'hFF;   // DM = FFFF
                    para[P_VECTW + 10] <= 8'hFF;
                end
            end else if (draw_busy_r) begin
                draw_busy_r <= 1'b0;
            end else if (draw_pending) begin
                draw_watch <= draw_watch + 27'd1;
            end

            // The read-back pop: one byte per data-port read, charged when
            // the read strobe ends (the keyboard 8251's idiom -- the byte
            // the CPU latched was the head). A command write below can
            // reassign rb_snd/rb_ptr in the same cycle; that ordering is
            // np21w's (the command's snd/ptr assignment wins).
            data_rd_q <= data_rd_now;
            if (data_rd_q && !data_rd_now && drdy) begin
                rb_snd <= rb_snd - 3'd1;
                rb_ptr <= rb_ptr + 6'd1;
            end

            if (cmd_wr) begin
                logic [10:0] dn;
                dn     = decode(wr_d);
                p_dst  <= dn[10:5];
                p_left <= dn[4:0];

                // np21w stores the drawing-family byte itself in GDC_WRITE
                // (para[53] -- vectdraw reads it as the write op), and a
                // WDAT-write variant's run is armed to fire when its
                // parameters complete. A new command rewrites both -- a run
                // cut short by the next command simply never fires.
                p_wdat <= (wr_d & 8'he4) == 8'h20;
                if ((wr_d & 8'h60) == 8'h20)
                    para[P_WRITE] <= wr_d;

                // EXECUTE-class: hand it to the drawing server. The snapshot
                // lands with the latch; further EXECUTEs while pending are
                // dropped (the FIFO-empty bit is already clear, so software
                // that polls waits) -- the scope guard, sharpened.
                if (exec_cmd && !draw_pending && !draw_busy_r) begin
                    draw_pending <= 1'b1;
                    draw_op_r    <= wr_d;
                    for (i = 0; i <= 22; i = i + 1)
                        snap[i] <= para[snap_src(i)];
                    snap[23] <= 8'h00;                 // the pad byte
                end

                // The read-back pair, np21w's `item->snd = indatas` /
                // `item->ptr = pos`: EVERY command rewrites both, so an
                // undrained CSRR is discarded by whatever command follows
                // it. CSRR stages its five bytes into para[P_CSRR] now --
                // the CSRW snapshot np21w takes at command execution, not a
                // live view the guest could race. LPEN aims ptr at the pen
                // latch, which a penless machine leaves at reset zero.
                if (wr_d == 8'hE0) begin
                    rb_snd <= 3'd5;
                    rb_ptr <= 6'(P_CSRR);
                    para[P_CSRR + 0] <= para[P_CSRW + 0];
                    para[P_CSRR + 1] <= para[P_CSRW + 1];
                    para[P_CSRR + 2] <= para[P_CSRW + 2] & 8'h03;
                    para[P_CSRR + 3] <= 8'h00;
                    para[P_CSRR + 4] <= 8'h00;
                end else if (wr_d == 8'hC0) begin
                    rb_snd <= 3'd3;
                    rb_ptr <= 6'(P_LPEN);
                end else begin
                    rb_snd <= 3'd0;
                    rb_ptr <= 6'd0;
                end

                // The immediate ones, np21w gdc_work's switch: START and
                // SYNC_ON set the display enable, STOP and SYNC_OFF clear
                // it. RESET is not in that switch -- the enable survives a
                // RESET command on np21w, so it survives here too.
                if (wr_d == 8'h0D || wr_d == 8'h6B || wr_d == 8'h0F)
                    disp_on_r <= 1'b1;
                if (wr_d == 8'h0C || wr_d == 8'h05 || wr_d == 8'h0E)
                    disp_on_r <= 1'b0;

            end else if (par_wr) begin
                if (p_left != 5'd0) begin
                    para[p_dst] <= wr_d;
                    p_dst       <= p_dst + 6'd1;
                    p_left      <= p_left - 5'd1;

                    // A WDAT-write run executes as its last parameter
                    // lands -- np21w's rcv countdown firing gdcsub_write,
                    // slave side only (the master's run is absorbed like
                    // RDAT's: parameters taken, nothing drawn, and the
                    // read-back FIFO stays empty so IN reads 0xFF either
                    // way). The byte in flight is the last CODE slot's
                    // contents, so it is merged into the snapshot instead
                    // of latched a cycle stale.
                    if ((p_left == 5'd1) && p_wdat && !MASTER
                        && !draw_pending && !draw_busy_r) begin
                        draw_pending <= 1'b1;
                        draw_op_r    <= para[P_WRITE];
                        for (i = 0; i <= 22; i = i + 1)
                            snap[i] <= (snap_src(i) == p_dst)
                                     ? wr_d : para[snap_src(i)];
                        snap[23] <= 8'h00;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // status
    // ------------------------------------------------------------------
    // np21w gdc_i60: 0x80 always, 0x40 hblank, 0x20 vsync (gdc.vsync is set
    // to 0x20 in pccore.c), 0x04 FIFO empty, 0x02 FIFO full, 0x01 data ready.
    //
    // BIT 7 IS LIGHT PEN DETECT, AND IT IS CLEAR: no light pen is fitted.
    //
    // It was 1, copied from np21w, which sets 0x80 unconditionally. np21w gets
    // away with that because it also answers the read that follows. This does
    // not, and the BIOS hangs in the gap:
    //
    //     F305E  in al,60h / test al,80h / jz 3094     no pen -> done
    //     F3064  mov cx,0Ah
    //     F3067  in al,60h / test al,04h / jnz 3071    wait for FIFO empty
    //     F3074  mov al,C0h / out 62h,al               LPRD: read the pen
    //     F307C  in al,60h / test al,01h / jnz 3086    wait for DRDY
    //     F3082  loop 307C                             ten tries
    //     F3097  mov al,4Ah / out 60h,al / jmp 305E    give up, START OVER
    //
    // Bit 0 never sets here, so the DRDY wait always times out and F3097 jumps
    // back to the top forever. That is the machine the panel was showing: the
    // last four I/O writes all port 0x60 with the count saturated, LIVE parked
    // at F3069, the screen frozen after BASIC's function key line, interrupts
    // still running (the loop is interruptible) and keys reaching the 8251 and
    // being read by the ISR while the foreground never comes back to use them.
    //
    // Clearing bit 7 is the truth about this machine and takes the exit at
    // F3062 on the first test, so LPRD is never issued. The alternative --
    // keeping bit 7 and queueing three bytes for LPRD -- answers a question
    // the hardware should not be asking.
    // np21w gdc_i60/gdc_ia0: 0x80 always, 0x40 hblank, 0x20 vsync (the
    // whole non-display interval -- pccore.c sets gdc.vsync at screenvsync
    // and clears it at screendisp), 0x04 FIFO empty, 0x02 FIFO full,
    // 0x01 data ready, and on the SLAVE 0x08 while a raster op runs
    // (gdc.s_drawing; the master's `| m_drawing` is commented out in
    // np21w). Bit 1 stays 0: np21w's cnt >= GDCCMD_MAX(32) needs a 32-byte
    // burst between command drains, and a guest that floods the command
    // port loses bytes on the real chip anyway.
    //
    // BIT 2 (FIFO EMPTY) IS ALSO THE DRAWING THROTTLE: while an EXECUTE sits
    // pending for the softcore server or the server is drawing, the bit
    // clears -- the backpressure a real 7220 applies by filling its FIFO,
    // which is exactly what software's "wait FIFO empty" loops consume.
    wire fifo_empty = ~draw_pending & ~draw_busy_r;
    // DRDY (bit 0): np21w's `if (snd) ret |= 1` -- read-back bytes pending.
    // BIT 7 IS LIGHT PEN DETECT AND IT STAYS CLEAR: no pen is fitted, and a
    // set bit walks the BIOS into the LPRD/DRDY poll at F307C that nothing
    // would ever satisfy (see the history above the status word).
    wire drdy = (rb_snd != 3'd0);
    wire drawing = ~MASTER & (draw_pending | draw_busy_r);
    wire [7:0] status = {1'b0, hblank, vblank, 1'b0, drawing,
                         fifo_empty, 1'b0, drdy};

    // The data port (0x62, a1=1) returns and pops one read-back byte per
    // read, or 0xFF when nothing is queued -- np21w gdc_i62 verbatim. The
    // STATUS port (0x60, a1=0) always returns the status.
    assign data_out = a1 ? (drdy ? para[rb_ptr] : 8'hFF) : status;

    // ------------------------------------------------------------------
    // the display registers, as the rest of the core wants them
    // ------------------------------------------------------------------
    assign disp_on = disp_on_r;
    assign pitch   = para[P_PITCH];

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : g_part
            wire [15:0] sad_raw = {para[P_PRAM + g*4 + 1], para[P_PRAM + g*4 + 0]};
            wire [15:0] len_raw = {para[P_PRAM + g*4 + 3], para[P_PRAM + g*4 + 2]};
            assign part_sad[g] = sad_raw;
            // lines = (LEN & 0x3FFF) >> 4
            assign part_len[g] = 10'((len_raw & 16'h3FFF) >> 4);
            assign part_pbyte[g] = len_raw[14];
        end
    endgenerate

    // ---- the text walker's ROW-unit boundaries ------------------------------
    // np21w maketext.c counts a partition's LEN in emitted RASTERLINES
    // (`if (!(--scroll))` once per `y++`), so which partition row R belongs
    // to depends on how many rasterlines the earlier partitions spent:
    // partition k+1 starts at row floor(S_k / P) with S_k = LEN[0..k] summed
    // and P = TEXT_LR+1. FLOOR, not ceil: the boundary can land mid-row, and
    // np21w's scroll reload then sets reloadline so the new partition's SAD
    // feeds the row's REMAINING rasters -- the boundary row IS the new
    // partition's row 0 (the head rasters still showing the old partition are
    // the part the row-granular model cannot express). Every later row is
    // exact: rel = row - bend counts the new partition's cell rows the same
    // way np21w's esi += pitch does.
    //
    // A zero LEN never ends -- the UINT countdown wraps instead of firing --
    // which reads here as "boundary 63", past the deepest row a text screen
    // has, and it swallows the partitions after it too: the ZERO-LEN
    // partition itself then owns every remaining row.
    //
    // floor(S/P) by subtraction, one boundary at a time, free-running: P is
    // 1..32 and S at most 3069, but the quotient saturates at 63 so a pass
    // costs three loads plus at most 192 subtracts -- converged long before
    // the px-domain registers sample it at vsync. The slave's boundaries
    // have no consumer (graphics walks part_len in guest lines), so the
    // divider is only built on the master.
    generate
    if (MASTER) begin : g_bend
        logic [1:0]  bd_i;      // boundary in progress
        logic [11:0] bd_cum;    // rasterlines spent by partitions 0..i
        logic [11:0] bd_rem;    // the same sum, mid-subtraction
        logic [5:0]  bd_q;      // quotient so far (saturates at 63)
        logic        bd_abs;    // a zero LEN seen -- absorbing, unreachable
        logic        bd_load;   // 1 = this cycle folds len[i] into the sum
        logic [5:0]  bend_r [0:2];
        wire  [5:0]  p_rows = {1'b0, line_rep} + 6'd1;

        always_ff @(posedge clk) begin
            if (reset) begin
                bd_i    <= 2'd0;
                bd_cum  <= 12'd0;
                bd_rem  <= 12'd0;
                bd_q    <= 6'd0;
                bd_abs  <= 1'b0;
                bd_load <= 1'b1;
                bend_r[0] <= 6'd63;
                bend_r[1] <= 6'd63;
                bend_r[2] <= 6'd63;
            end else if (bd_load) begin
                bd_rem  <= bd_cum + 12'(part_len[bd_i]);
                bd_cum  <= bd_cum + 12'(part_len[bd_i]);
                bd_abs  <= bd_abs | (part_len[bd_i] == 10'd0);
                bd_q    <= 6'd0;
                bd_load <= 1'b0;
            end else if (bd_abs || (bd_q == 6'd63)
                              || (bd_rem < {6'd0, p_rows})) begin
                // floor(S/P): bd_q already counts the whole-row crossings
                // and the mid-row remainder belongs to the NEW partition's
                // row 0 (the reload fires inside it) -- nothing to add.
                bend_r[bd_i] <= (bd_abs || (bd_q == 6'd63)) ? 6'd63 : bd_q;
                if (bd_i == 2'd2) begin
                    bd_i   <= 2'd0;
                    bd_cum <= 12'd0;
                    bd_abs <= 1'b0;
                end else begin
                    bd_i   <= bd_i + 2'd1;
                end
                bd_load <= 1'b1;
            end else begin
                bd_rem <= bd_rem - {6'd0, p_rows};
                bd_q   <= bd_q + 6'd1;
            end
        end
        assign part_bend = '{bend_r[0], bend_r[1], bend_r[2]};
    end else begin : g_bend_s
        assign part_bend = '{6'd63, 6'd63, 6'd63};
    end
    endgenerate

    // CSRW: the address is a PLAIN little-endian 16-bit word. np21w's text
    // side does LOADINTELWORD(para + GDC_CSRW) and treats it as the cell
    // index (curpos < 0x1000), and the BIOS's own driver writes AL then AH of
    // the word address directly (F49C9: out 60h,al / mov al,ah / out 60h,al --
    // two bytes, no third). The uPD7220 manual's interleaved reading
    // {EAD14-13, EAD12-5, EAD4-0} drops bits 7-5 of the first byte, which
    // scrambles the cell across the screen; with it the cursor never lands
    // where the user is looking, which is what "no reverse block, ever"
    // looked like on hardware. The dot address rides the third byte's high
    // nibble -- PC-98 never sends one, so it stays zero.
    assign cursor_addr       = {para[P_CSRW + 1], para[P_CSRW + 0]};
    assign cursor_dot        = para[P_CSRW + 2][7:4];

    // CSRFORM: display-cursor enable (P1 bit 7), top line (P2 bits 4-0) and
    // bottom line (P3 bits 7-3), as np21w's maketext reads them:
    //
    //     nowline >= (para[GDC_CSRFORM+1] & 0x1f)   <- TOP IS P2
    //     nowline <= (para[GDC_CSRFORM+2] >> 3)
    //
    // P1's low five bits are NOT the cursor top -- maketext line 163 reads
    // them as TEXT_LR, the lines-per-character-row. The BIOS agrees: [0x53B]
    // (the P1 byte its enable write ORs 0x80 onto) is 0x0F, a sixteen-line
    // row height, while [0x53D] (the P2 byte) is only ever 0x00 or 0x20 --
    // the blink bit and a top of zero. Reading the top from P1 made every
    // form say top=15 against a bottom below it: an empty slice, and "no
    // reverse block, ever" on hardware.
    //
    // BLINK IS P2 BIT 5, INVERTED: np21w treats a set bit as "does not blink"
    // (the cursor goes solid), and the BIOS's driver carries exactly that
    // bit in [0x53D] as the P2 byte of the three-byte table write. The port
    // keeps the 1-means-blink sense the renderer expects.
    wire        csr_en = para[P_CSRFORM + 0][7];
    wire [7:0]  csr_p2 = para[P_CSRFORM + 1];
    wire [7:0]  csr_p3 = para[P_CSRFORM + 2];
    assign cursor_en        = csr_en;
    assign cursor_top       = csr_p2[4:0];
    assign cursor_rate      = {csr_p3[1:0], csr_p2[7:4]};
    assign cursor_bottom    = csr_p3[7:3];
    assign cursor_blink_en  = ~csr_p2[5];

    assign zoom_disp = para[P_ZOOM][1:0];
    assign line_rep  = para[P_CSRFORM + 0][4:0];

    wire [15:0] sync_vw = {para[P_SYNC + 7], para[P_SYNC + 6]};
    assign vlines = sync_vw[9:0];

    // The light pen's three bytes are read back, never driven from here.
    wire _unused = &{1'b0, para[P_LPEN], para[P_MASK], para[P_SYNC], 1'b0};

endmodule

`default_nettype wire
