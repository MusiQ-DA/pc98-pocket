//
// pc98_gdc -- the uPD7220's DISPLAY side. One module, instantiated twice.
//
// WHAT THIS IS AND IS NOT. The 7220 has two faces: it decides what part of
// VRAM reaches the screen, and it draws. This is the first one only --
// docs/PC98_GDC_DESIGN.md has the reasoning, and the short version is that the
// device is at 97 per cent ALMs, the drawing processor is the expensive half,
// and PC-98 software overwhelmingly draws by writing VRAM through the GRCG
// rather than by issuing GDC drawing commands. That last clause is a JUDGEMENT
// AND NOT A MEASUREMENT, so the unimplemented commands are counted and
// reported (unk_cmd / unk_count) instead of being silently swallowed: if the
// ROM issues one, the judgement is wrong and the readout says so.
//
// NOR DOES IT GENERATE THE RASTER. pc98_video_timing already makes 640x400 at
// 24.83 kHz and the picture it produces works. The SYNC parameters are
// therefore RECORDED, not obeyed; moving the raster onto the GDC would put
// everything that currently displays at risk for no gain today.
//
// THE PORTS, from np2kai io/gdc.c, because getting this backwards inverts
// every command in the machine:
//
//     0x60 / 0xA0   write -> PARAMETER      read -> STATUS
//     0x62 / 0xA2   write -> COMMAND        read -> the read-back FIFO
//     0x64 / 0xA4   write -> clear the vsync interrupt (not handled here)
//
// np2kai pushes both into one FIFO and tags the command with bit 8
// (`gdc.m.fifo[cnt++] = 0x100 | dat`); the tag is what lets a command arrive
// mid-parameter-run and cut it short, which is what a real 7220 does.
//
// THE PARAMETER STORE, from np2kai io/gdc_cmd.tbl -- a 256-entry table of
// {where the parameters go, how many}. Two things in it are not obvious and
// both were nearly got wrong here:
//
//   * 0x70-0x7F ARE ONE COMMAND, not two. The low nibble is the start offset
//     into a SIXTEEN-byte PRAM and the count is 16 - offset. np2kai's
//     CMD_SCROLL (0x70) and CMD_TEXTW (0x78) are two names for offsets 0 and 8
//     of the same block: GDC_SCROLL is para[12] and GDC_TEXTW is para[20].
//   * ZOOM is 0x46, not 0x06. The enum in gdc_cmd.h says CMD_ZOOM = 0x06 but
//     the TABLE, which is indexed by opcode, puts {GDC_ZOOM, 1} at 0x46 and
//     nothing at 0x06.
//
// THE PRAM IS FOUR PARTITIONS OF FOUR BYTES, and the display walks them in
// turn (np2kai vram/makegrex.c calls its partition walker with gpos 0 then 4,
// forever, until the screen is full):
//
//     bytes 0-1   SAD   display address = (SAD << 1) & 0x7FFF
//     bytes 2-3   LEN   lines = (LEN & 0x3FFF) >> 4
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

// MASTER/SLAVE AS A PARAMETER. The two GDCs still decode identically; the
// one thing that differs is the power-on CSRFORM. np2kai's gdc_reset seeds
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
    input  wire        hblank,
    input  wire        vsync,

    // ---- what the display side of the core needs ---------------------------
    output wire        disp_on,       // START seen, STOP not
    output wire [7:0]  pitch,         // words per line
    // Four partitions, in PRAM order. A screen with one area sets partition 0
    // to the whole height; the walker in the renderer then never advances.
    // RAW, not interpreted. The two GDCs read the SAME PRAM field DIFFERENTLY:
    // np2kai's graphics walker takes LOW15(vad << 1) (vram/makegrex.c) and its
    // text renderer takes LOW12(...) with no shift at all (vram/maketext.c,
    // where the result indexes cells as mem[0xa0000 + edi*2]). Baking either
    // one in here would be right for one consumer and wrong for the other --
    // it was baked in as the graphics form, and that was wrong for text.
    output wire [15:0] part_sad [0:3],
    output wire [9:0]  part_len [0:3],
    // The cursor, as CSRW and CSRFORM leave it.
    output wire [15:0] cursor_addr,
    output wire [3:0]  cursor_dot,    // dot address within the word
    output wire        cursor_en,
    output wire        cursor_blink_en,
    output wire [4:0]  cursor_top,
    output wire [4:0]  cursor_bottom,
    output wire [5:0]  cursor_rate,
    // How many CSRW/CSRFORM commands arrived -- the panel's cursor field
    // reads it, because "the registers look right but nothing draws" and
    // "the BIOS never sent a form at all" are different faults.
    output reg  [7:0]  csr_wr_count,
    // What actually followed the LAST CSRFORM command: the first three
    // parameter bytes in order, and how many bytes arrived before another
    // command cut the run short (saturating at 15). The BIOS writes CSRFORM
    // as one byte (its cursor ON/OFF) and as three (the table form); which
    // of those the metal actually sent, and whether the bytes landed where
    // the capture puts them, is the question the panel's CT word answers.
    output wire [31:0] csr_trace,
    output wire [1:0]  zoom_disp,

    // ---- what the post monitor needs ---------------------------------------
    // The drawing processor is not here. If the ROM asks for it, this says so.
    output reg  [7:0]  unk_cmd,
    output reg  [7:0]  unk_count,
    // ---- the drawing server (the softcore's GDC engine) ---------------------
    // EXECUTE-class commands (VECTE 0x6C, TEXTE 0x68) stop being counted as
    // unknown and land here instead: the snapshot ports hand the softcore the
    // opcode and the whole parameter file, and the done port returns the
    // engine's final EAD (the drawing cursor moves). While a snapshot is
    // pending or the server is drawing, the FIFO-empty status bit clears --
    // the throttle a real 7220 applies through its FIFO depth, which is what
    // software's "wait FIFO empty" loops are for.
    output wire        draw_req,       // an EXECUTE awaits the server
    output wire [7:0]  draw_op,
    output wire        draw_busy,      // status: the server is drawing
    input  wire        srv_done_stb,   // the engine finished this EXECUTE
    // The snapshot the engine reads, latched the moment the EXECUTE lands so
    // the guest cannot race it: 19 bytes = VECTW (11), CSRW (4), TEXTW (2),
    // ZOOM (1), the WRITE-mode byte (1). Served a word at a time.
    output wire [31:0] draw_snap [0:4]
);

    // ------------------------------------------------------------------
    // the parameter store
    // ------------------------------------------------------------------
    // np2kai's offsets, kept verbatim so the table above can be read against
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
    localparam int P_LAST    = 55;

    reg [7:0] para [0:P_LAST];

    // The read-back FIFO: CSRR queues five bytes off CSRW (np2kai gdc.c's
    // fill: the three address bytes, the high one masked to its two live
    // bits, then two zeros), LPEN queues the latched pen position -- and no
    // pen is fitted, so that is three zero bytes. What the queue buys is the
    // contract: software that issues either command and polls DRDY gets its
    // bytes and DRDY falls, instead of timing out against a silent port.
    reg [7:0] rb_fifo [0:7];
    reg [2:0] rb_wr = 3'd0, rb_rd = 3'd0;

    // The CSRFORM trace, as csr_trace reports it.
    reg [7:0] csr_tr0, csr_tr1, csr_tr2;
    reg [3:0] csr_n;
    reg       csr_live;
    assign csr_trace = {4'b0000, csr_n, csr_tr0, csr_tr1, csr_tr2};

    // The drawing server's handshake. draw_pending latches the first EXECUTE
    // with a SNAPSHOT of everything the engine reads (the guest cannot race
    // it); the server clears the request with srv_done_stb, which also runs
    // the post-command reset the 7220 applies to the vector parameters.
    reg        draw_pending;
    reg [7:0]  draw_op_r;
    reg        draw_busy_r;
    reg [7:0]  snap [0:18];
    assign draw_req  = draw_pending;
    assign draw_op   = draw_op_r;
    assign draw_busy = draw_busy_r;
    genvar sk;
    generate
        for (sk = 0; sk < 5; sk = sk + 1) begin : g_snap
            assign draw_snap[sk] = {snap[4*sk+3], snap[4*sk+2], snap[4*sk+1], snap[4*sk]};
        end
    endgenerate

    // Where each snapshot byte comes from.
    function automatic logic [5:0] snap_src(input int k);
        if (k <= 10)     snap_src = 6'(P_VECTW + k);      // 32..42
        else if (k <= 14) snap_src = 6'(P_CSRW + k - 11);  // 43..46
        else if (k <= 16) snap_src = 6'(20 + k - 15);      // TEXTW 20..21
        else if (k == 17) snap_src = 6'(P_ZOOM);           // 8
        else              snap_src = 6'd53;                // the WRITE mode
    endfunction

    wire exec_cmd = (data_in == 8'h6C)   // VECTE
                  | (data_in == 8'h68);  // TEXTE

    // The watchdog: if the softcore server never answers, force the retire
    // after ~4 frames of pending. A drawing server that hangs would
    // otherwise hold the FIFO-empty throttle -- and every "wait FIFO empty"
    // loop with it -- forever (docs/SOFTCORE_RTL_SPLIT.md's hang hazard).
    // The drawing is simply lost; the machine lives.
    logic [26:0] draw_watch = 27'd0;
    localparam logic [26:0] DRAW_WATCHDOG = 27'd128_000_000;  // ~3 s of 42.95 MHz
    wire draw_timeouts = draw_pending && (draw_watch == DRAW_WATCHDOG);

    // Where the next parameter goes, and how many are still expected. A new
    // command cuts a run short, which is the point of np2kai's bit-8 tag.
    reg [5:0] p_dst;
    reg [4:0] p_left;

    reg       disp_on_r;

    // ------------------------------------------------------------------
    // the command decode
    // ------------------------------------------------------------------
    // {destination, count}. Anything not named here takes no parameters and is
    // counted as unimplemented -- see unk_cmd.
    function automatic logic [10:0] decode(input logic [7:0] c);
        logic [5:0] d;
        logic [4:0] n;
        d = 6'd0; n = 5'd0;
        casez (c)
            8'h00:          begin d = P_SYNC[5:0];    n = 5'd8;  end // RESET
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

    // Commands this module implements with no parameters, so an unknown one
    // can be told apart from a known zero-parameter one. VECTE and TEXTE are
    // EXECUTE-class: known, and handed to the drawing server instead.
    function automatic logic known_noparam(input logic [7:0] c);
        known_noparam = (c == 8'h05) || (c == 8'h0C)       // STOP
                     || (c == 8'h0D) || (c == 8'h6B)       // START
                     || (c == 8'h6E) || (c == 8'h6F)       // SLAVE / MASTER
                     || (c == 8'h6C) || (c == 8'h68)       // VECTE / TEXTE
                     || (c == 8'hE0) || (c == 8'hC0);      // CSRR / LPEN
    endfunction

    wire cmd_wr = cs & ~io_write_n &  a1;
    wire par_wr = cs & ~io_write_n & ~a1;

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            p_dst     <= 6'd0;
            p_left    <= 5'd0;
            disp_on_r <= 1'b0;
            unk_cmd   <= 8'h00;
            unk_count <= 8'h00;
            csr_wr_count <= 8'h00;
            rb_wr <= 3'd0;
            rb_rd <= 3'd0;
            draw_pending <= 1'b0;
            draw_op_r    <= 8'h00;
            draw_busy_r  <= 1'b0;
            for (i = 0; i <= 18; i = i + 1) snap[i] <= 8'h00;
            csr_tr0 <= 8'h00; csr_tr1 <= 8'h00; csr_tr2 <= 8'h00;
            csr_n <= 4'd0; csr_live <= 1'b0;
            for (i = 0; i <= P_LAST; i = i + 1) para[i] <= 8'h00;
            // The CSRFORM power-on values, and why the cursor is nothing
            // without them: the BIOS's boot sends CSRFORM as ONE byte --
            // [0x53B]|0x80, the enable with TEXT_LR -- and never sends the
            // full three, so top/bottom/blink are whatever the chip woke
            // with. np2kai's gdc_reset seeds the master to {P1=0F, P2=C0,
            // P3=7B}: LR 15, top 0, bottom 15, blinking (P2 bit5 CLEAR is
            // "does blink" in np2's inverted reading) -- a blinking full
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
            // The server's completion: retire the request and run the
            // post-command reset np2's gdc_vectreset applies -- the 7220
            // clears the vector parameters after every EXECUTE. Independent
            // of the command port: the engine finishes on its own clock.
            if (srv_done_stb || draw_timeouts) begin
                draw_pending <= 1'b0;
                draw_watch   <= 23'd0;
                draw_busy_r  <= 1'b1;      // one-cycle hold for stability
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
            end else if (draw_busy_r) begin
                draw_busy_r <= 1'b0;
            end else if (draw_pending) begin
                draw_watch <= draw_watch + 23'd1;
            end

            if (cmd_wr) begin
                logic [10:0] dn;
                dn     = decode(data_in);
                p_dst  <= dn[10:5];
                p_left <= dn[4:0];

                // The trace follows only the CSRFORM command.
                csr_live <= (data_in == 8'h4B);
                csr_n    <= 4'd0;

                // CSRW/CSRFORM arrivals, saturating, for the panel.
                if ((data_in == 8'h49 || data_in == 8'h4B)
                        && csr_wr_count != 8'hFF)
                    csr_wr_count <= csr_wr_count + 8'd1;

                // EXECUTE-class: hand it to the drawing server. The snapshot
                // lands with the latch; further EXECUTEs while pending are
                // counted unknown (the FIFO-empty bit is already clear, so
                // software that polls waits) -- the scope guard, sharpened.
                if (exec_cmd && !draw_pending && !draw_busy_r) begin
                    draw_pending <= 1'b1;
                    draw_op_r    <= data_in;
                    for (i = 0; i <= 18; i = i + 1)
                        snap[i] <= para[snap_src(i)];
                end else if (exec_cmd) begin
                    unk_cmd <= data_in;
                    if (unk_count != 8'hFF)
                        unk_count <= unk_count + 8'd1;
                end

                // CSRR: five bytes off CSRW, np2's fill verbatim -- the
                // three address bytes (the high one masked to two bits) and
                // two zeros. LPEN: the pen latch, and no pen is fitted.
                // Both queue only when there is room; a guest that reissues
                // without draining loses the new bytes, which is what a
                // five-deep FIFO on a real chip would do to it too.
                if (data_in == 8'hE0 && (3'd7 - (rb_wr - rb_rd)) >= 3'd4) begin
                    rb_fifo[rb_wr]           <= para[P_CSRW + 0];
                    rb_fifo[rb_wr + 3'd1]    <= para[P_CSRW + 1];
                    rb_fifo[rb_wr + 3'd2]    <= para[P_CSRW + 2] & 8'h03;
                    rb_fifo[rb_wr + 3'd3]    <= 8'h00;
                    rb_fifo[rb_wr + 3'd4]    <= 8'h00;
                    rb_wr <= rb_wr + 3'd5;
                end
                if (data_in == 8'hC0 && (3'd7 - (rb_wr - rb_rd)) >= 3'd2) begin
                    rb_fifo[rb_wr]        <= 8'h00;   // no pen: the latch reads zero
                    rb_fifo[rb_wr + 3'd1] <= 8'h00;
                    rb_fifo[rb_wr + 3'd2] <= 8'h00;
                    rb_wr <= rb_wr + 3'd3;
                end


                // The immediate ones.
                if (data_in == 8'h0D || data_in == 8'h6B) disp_on_r <= 1'b1;
                if (data_in == 8'h0C || data_in == 8'h05) disp_on_r <= 1'b0;
                if (data_in == 8'h00) begin
                    // RESET stops the display and takes SYNC parameters; it
                    // does NOT clear the PRAM (np2kai does not either).
                    disp_on_r <= 1'b0;
                end

                // Unimplemented: no destination, no count, and not one of the
                // zero-parameter commands this module does handle. Saturating,
                // because "how many" matters less than "at all".
                if (dn[4:0] == 5'd0 && !known_noparam(data_in)) begin
                    unk_cmd <= data_in;
                    if (unk_count != 8'hFF) unk_count <= unk_count + 8'd1;
                end
            end else if (par_wr) begin
                if (p_left != 5'd0) begin
                    para[p_dst] <= data_in;
                    p_dst       <= p_dst + 6'd1;
                    p_left      <= p_left - 5'd1;
                end
                // The trace records every 0x60 byte while the last command
                // was CSRFORM, landed in the capture or not.
                if (csr_live) begin
                    if (csr_n == 4'd0)      csr_tr0 <= data_in;
                    else if (csr_n == 4'd1) csr_tr1 <= data_in;
                    else if (csr_n == 4'd2) csr_tr2 <= data_in;
                    if (csr_n != 4'hF) csr_n <= csr_n + 4'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // status
    // ------------------------------------------------------------------
    // np2kai gdc_i60: 0x80 always, 0x40 hblank, 0x20 vsync (gdc.vsync is set
    // to 0x20 in pccore.c), 0x04 FIFO empty, 0x02 FIFO full, 0x01 data ready.
    // Nothing here queues read-back data yet, so empty is true and full and
    // ready are false.
    //
    // BIT 7 IS LIGHT PEN DETECT, AND IT IS CLEAR: no light pen is fitted.
    //
    // It was 1, copied from np2kai, which sets 0x80 unconditionally. np2 gets
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
    // np2kai gdc_i60: 0x80 always, 0x40 hblank, 0x20 vsync (gdc.vsync is set
    // to 0x20 in pccore.c), 0x04 FIFO empty, 0x02 FIFO full, 0x01 data ready.
    // BIT 2 (FIFO EMPTY) IS ALSO THE DRAWING THROTTLE: while an EXECUTE sits
    // pending for the softcore server or the server is drawing, the bit
    // clears -- the backpressure a real 7220 applies by filling its FIFO,
    // which is exactly what software's "wait FIFO empty" loops consume.
    wire fifo_empty = ~draw_pending & ~draw_busy_r;
    // DRDY (bit 0): the read-back FIFO holds CSRR/LPEN results. BIT 7 IS
    // LIGHT PEN DETECT AND IT STAYS CLEAR: no pen is fitted, and a set bit
    // walks the BIOS into the LPRD/DRDY poll at F307C that nothing would
    // ever satisfy (see the history above the status word).
    wire drdy = (rb_wr != rb_rd);
    wire [7:0] status = {1'b0, hblank, vsync, 1'b0, 1'b0, fifo_empty, 1'b0, drdy};

    // The data port answers with the read-back head while DRDY is set, and
    // with the status otherwise -- np2's gdc_i60/gdc_i62 split: the STATUS
    // port (0x60, a1=0) always returns the status, whose bit 0 says data is
    // ready, and the DATA port (0x62, a1=1) returns and pops one byte per
    // read. The pop happens after the read strobe ends, the keyboard 8251's
    // idiom, so the byte the CPU latched is the head.
    wire data_rd_now = cs & a1 & ~io_read_n;
    logic data_rd_q = 1'b0;
    always_ff @(posedge clk) begin
        data_rd_q <= data_rd_now;
        if (data_rd_q && !data_rd_now && drdy)
            rb_rd <= rb_rd + 3'd1;
    end

    assign data_out = a1 ? rb_fifo[rb_rd] : status;

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
        end
    endgenerate

    // CSRW: the address is a PLAIN little-endian 16-bit word. np2kai's text
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
    // bottom line (P3 bits 7-3), as np2kai's maketext reads them:
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
    // BLINK IS P2 BIT 5, INVERTED: np2 treats a set bit as "does not blink"
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

    // The light pen's three bytes are read back, never driven from here.
    wire _unused = &{1'b0, para[P_LPEN], para[P_MASK], para[P_SYNC], 1'b0};

endmodule

`default_nettype wire
