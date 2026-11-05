`default_nettype none
// tb_gvram_depth_wipe -- SuperDepth's stage "Clear!" wipe against the
// graphics display fetch, scored line by line against np21w's frame model.
//
// The wipe (DEPTH.EXE loop 0x2E7A5..0x2E81E) runs bx = 399, 395, .. 127 --
// 68 frames -- and per frame, after its GRCG drawing and BEFORE its vsync
// wait, calls 0x30B20, which sends the slave GDC SCROLL (0x70) with eight
// PRAM bytes:
//     SAD0 = bx*40          LEN0 = (400-bx) | [0xBB6]<<8
//     SAD1 = 0              LEN1 = bx       | [0xBB6]<<8
// The write therefore lands at whatever raster line the drawing finished
// on. This bench replays exactly that byte sequence at chosen raster lines
// W (fixed per pass, or random per frame), decodes the bytes the way
// pc98_gdc does, and checks every displayed line's SOURCE (the plane byte
// offset its fill read) against the reference:
//
//   np21w pccore.c screendisp() -> drawscreen() -> makegrph() renders the
//   whole frame at the start of display line 0 from gdc.s.para as it is at
//   that instant, walking grphput_indirty0 (remain/mul/vad) per partition.
//
// So the reference for frame f is the walk over the PRAM captured at
// (v=0,h=0) of that frame. The fake SDRAM answers plane B with a nonzero
// byte for offsets below 32000 (VRAM lines 0..399) and zero above, so a
// line fetched from past the 400th VRAM line shows black: the bench also
// measures each frame's longest all-black run, the hardware symptom.
//
// Compile with -DNEW_RTL for the frame-snapshot RTL (it also checks the
// module's own black-band / PRAM-timing witness against the bench's).
module tb_gvram_depth_wipe;
    logic clk = 0; always #11 clk = ~clk;
    logic rd_clk = 0; always #23 rd_clk = ~rd_clk;

    logic rst = 1;
    logic [9:0] h = 0, v = 0;
    logic disp_on = 1, disp_page = 0, analog_m = 1;
    logic dbl = 0;
    logic [4:0] lrep = 5'd0;
    logic       mhz5 = 1'b0;
    logic [7:0] pitch = 8'd40;
    logic [5:0] vshift = 6'd0;

    // The slave GDC's PRAM bytes 0..15 (SCROLL area), decoded the way
    // pc98_gdc.sv's g_part generate does.
    // One packed vector, byte i at [8i+7:8i]: Verilator 5.020 (CI) does not
    // wake continuous assigns on a task's write to an unpacked element.
    logic [127:0] pram = '0;
    logic [15:0] part_sad [0:3];
    logic [9:0]  part_len [0:3];
    logic [3:0]  part_pbyte;
    // Continuous assigns, not an always_comb over the array: Verilator
    // 5.020 (CI) does not re-run such a block on an element write.
    for (genvar g = 0; g < 4; g++) begin : g_dec
        wire [15:0] lr = pram[(g*4+2)*8 +: 16];
        assign part_sad[g]   = pram[(g*4)*8 +: 16];
        assign part_len[g]   = 10'((lr & 16'h3FFF) >> 4);
        assign part_pbyte[g] = lr[14];
    end

    logic        p_req, p_ack = 0, p_rvalid = 0, p_done = 0;
    logic [23:0] p_addr;
    logic [3:0]  p_len;
    logic [15:0] p_rdata = 0;
    logic [3:0]  gfx_dot;
`ifdef NEW_RTL
    wire  [95:0] dbg_band;
`endif

    pc98_gvram_display #(.BAND_PROBE(1'b1)) dut (
        .clk(clk), .rst(rst), .rd_clk(rd_clk),
        .hcount(h), .vcount(v), .disp_on(disp_on),
        .disp_page(disp_page), .analog_mode(analog_m),
        .pitch(pitch), .mhz5(mhz5), .dbl(dbl), .lrep(lrep),
        .part_sad(part_sad), .part_len(part_len),
        .part_pbyte(part_pbyte), .vshift(vshift),
        .p_req(p_req), .p_addr(p_addr), .p_len(p_len),
        .p_ack(p_ack), .p_rvalid(p_rvalid), .p_rdata(p_rdata), .p_done(p_done),
`ifdef NEW_RTL
        .dbg_band(dbg_band),
`endif
        .gfx_dot(gfx_dot), .dbg()
    );

    // raster: 848 dots x 440 lines on rd_clk (400 shown, 40 blank)
    always_ff @(posedge rd_clk) begin
        if (h == 10'd847) begin h <= 0; v <= (v == 10'd439) ? 10'd0 : v + 10'd1; end
        else h <= h + 10'd1;
    end

    // Port model: plane B (A8000 / page one plane 0) answers 0x81 for every
    // byte of VRAM lines 0..399 and 0x00 past them; R/G/E answer zero.
    function automatic [7:0] pbyte(input int a);
        int off;
        off = a & 32'h7FFF;
        if (a >= 24'h600000) return (((a >> 15) & 3) == 0 && off < 32000) ? 8'h81 : 8'h00;
        if (a[19:15] == 5'b10101) return (off < 32000) ? 8'h81 : 8'h00;
        return 8'h00;
    endfunction

    int burst_addr, burst_len, beat;
    logic in_burst = 0;
    always_ff @(posedge clk) begin
        p_ack <= 0; p_done <= 0; p_rvalid <= 0;
        if (p_req && !in_burst) begin
            p_ack <= 1;
            burst_addr <= p_addr; burst_len <= p_len + 1; in_burst <= 1;
        end else if (in_burst) begin
            p_rvalid <= 1;
            p_rdata  <= {8'h00, pbyte(burst_addr + beat)};
            if (beat == burst_len - 1) begin
                p_done <= 1; in_burst <= 0; beat <= 0;
            end else beat <= beat + 1;
        end
    end

    // ---- what each displayed line actually showed --------------------------
    // Every fill launch records its target's byte offset; when the raster
    // reaches line y the latest record for y is the one this frame shows
    // (the next frame's fill for y launches ~437 lines later).
    int  rec_base [0:511];
    int  shown    [0:399];
    logic fa_q = 0;
    always_ff @(posedge clk) begin
        fa_q <= dut.f_active;
        if (dut.f_active && !fa_q) rec_base[dut.act_tgt] <= int'(dut.fill_base);
    end

    // ---- the np21w reference ----------------------------------------------
    // Frame f is drawn whole from the PRAM as of (v=0,h=0): grphput_indirty0
    // with mg.lr = 1, partitions cycling 0..3.
    logic [15:0] r_sad [0:3];
    logic [9:0]  r_len [0:3];
    logic [3:0]  r_pb;
    logic [7:0]  r_pitch;
    function automatic int ref_base(input int L);
        int p, rel, vad, pb;
        p = 0; rel = 0;
        vad = (r_sad[0] * 2) & 32'h7FFF;
        for (int i = 0; i < L; i++) begin
            rel = rel + 1;
            if (r_len[p] != 0 && rel >= int'(r_len[p])) begin
                p = (p + 1) & 3; rel = 0;
                vad = (r_sad[p] * 2) & 32'h7FFF;
            end else begin
                pb  = (r_pb[p] | mhz5) ? (r_pitch & 8'hFE) : ((r_pitch << 1) & 8'hFE);
                vad = (vad + pb) & 32'h7FFF;
            end
        end
        return vad;
    endfunction

    // ---- per-frame scoring --------------------------------------------------
    logic scoring = 0;
    int   frames_scored = 0, frames_bad = 0, lines_bad = 0;
    int   frames_band = 0, worst_run = 0, worst_run_start = 0, worst_frame = -1;
    int   seam_lines = 0;          // shown lines whose source is past VRAM line 399
    int   moves = 0;               // scored frames whose SAD0 differs from the last
    logic [15:0] prev_sad0 = 16'd0;
    int   frame_no = 0;
    int   example_printed = 0;
    logic line_lit = 0;
    int   run = 0, fmax = 0, fstart = 0;
    always_ff @(posedge rd_clk) begin
        if (v == 10'd0 && h == 10'd0) begin
            for (int i = 0; i < 4; i++) begin
                r_sad[i] = part_sad[i]; r_len[i] = part_len[i];
            end
            r_pb = part_pbyte; r_pitch = pitch;
            frame_no <= frame_no + 1;
            run = 0; fmax = 0; fstart = 0;
        end
        if (v < 10'd400 && h == 10'd1) shown[v] = rec_base[v];
        // black-line run, from the module's own dots
        if (h == 10'd0) line_lit = 1'b0;
        else if (gfx_dot != 4'd0) line_lit = 1'b1;
        if (v < 10'd400 && h == 10'd700) begin
            if (line_lit) run = 0;
            else begin
                run = run + 1;
                if (run > fmax) begin fmax = run; fstart = int'(v) - run + 1; end
            end
        end
        if (v == 10'd400 && h == 10'd2 && scoring) begin
            int bad, seam, first_bad;
            bad = 0; seam = 0; first_bad = -1;
            for (int y = 0; y < 400; y++) begin
                if (shown[y] != ref_base(y)) begin
                    bad++;
                    if (first_bad < 0) first_bad = y;
                end
                if (shown[y] >= 32000) seam++;
            end
            frames_scored++;
            if (r_sad[0] != prev_sad0) moves++;
            prev_sad0 = r_sad[0];
            lines_bad  += bad;
            seam_lines += seam;
            if (bad != 0) frames_bad++;
            if (fmax >= 8) frames_band++;
            if (fmax > worst_run) begin
                worst_run = fmax; worst_run_start = fstart; worst_frame = frames_scored;
            end
            if (bad != 0 && example_printed < 2) begin
                example_printed++;
                $display("   example frame: SAD0=%0d LEN0=%0d LEN1=%0d (bx=%0d); %0d lines differ, first at y=%0d",
                         r_sad[0], r_len[0], r_len[1], r_sad[0] / 40, bad, first_bad);
                for (int y = (first_bad > 3 ? first_bad - 3 : 0);
                     y < first_bad + 10 && y < 400; y++)
                    $display("     y=%3d shows VRAM line %3d%s   np21w: line %3d",
                             y, shown[y] / 80, (shown[y] >= 32000) ? " (past 399: black)" : "",
                             ref_base(y) / 80);
            end
        end
    end

    // ---- the guest's SCROLL write -------------------------------------------
    task automatic gdc_param(input int idx, input logic [7:0] b);
        pram[idx*8 +: 8] = b;
        repeat (200) @(posedge clk);     // ~4.4 us between OUTs
    endtask

    // 0x30B20 verbatim: SAD0 lo/hi, LEN0 lo/hi(+[BB6]), SAD1 lo/hi, LEN1 lo/hi.
    task automatic scroll_write(input int bx, input logic [7:0] bb6);
        int sad, l0;
        sad = bx * 40; l0 = 400 - bx;
        @(posedge clk);
        gdc_param(0, 8'(sad));
        gdc_param(1, 8'(sad >> 8));
        gdc_param(2, 8'(l0 << 4));
        gdc_param(3, 8'((l0 >> 4)) + bb6);
        gdc_param(4, 8'h00);
        gdc_param(5, 8'h00);
        gdc_param(6, 8'(bx << 4));
        gdc_param(7, 8'((bx >> 4)) + bb6);
    endtask

    task automatic wait_line(input int line);
        @(posedge rd_clk);
        while (!(v == 10'(line) && h == 10'd0)) @(posedge rd_clk);
    endtask

    int total_fail = 0;
`ifdef NEW_RTL
    int pc0, pc1, bc0, bc1;
`endif

    // One pass: the picture at rest (SAD0=0, LEN0=400), then the 68-frame
    // wipe with the write at raster line W (W < 0: random per frame, kept
    // clear of the 435..439 snapshot window), then two settling frames.
    task automatic run_pass(input string name, input int W, input logic [7:0] bb6);
        int wl, n_active;
        n_active = 0;
        pram = '0;
        pram[2*8 +: 8] = 8'(400 << 4); pram[3*8 +: 8] = 8'((400 >> 4)) + bb6;
        wait_line(10); wait_line(10);
        frames_scored = 0; frames_bad = 0; lines_bad = 0; frames_band = 0;
        worst_run = 0; worst_run_start = 0; worst_frame = -1; seam_lines = 0;
        moves = 0; prev_sad0 = 16'd0;
        example_printed = 0;
`ifdef NEW_RTL
        pc0 = int'(dbg_band[79:64]); bc0 = int'(dbg_band[95:80]);
`endif
        scoring = 1;
        for (int bx = 399; bx > 127; bx -= 4) begin
            wl = (W >= 0) ? W : $urandom_range(0, 433);
            wait_line(434);
            if (wl < 400) n_active++;
            wait_line(wl);
            scroll_write(bx, bb6);
        end
        wait_line(5); wait_line(5); wait_line(401);
        scoring = 0;
        $display("%-12s frames=%0d sad_steps=%0d bad_frames=%0d bad_lines=%0d seam_lines=%0d band_frames(>=8)=%0d worst_black_run=%0d@y%0d",
                 name, frames_scored, moves, frames_bad, lines_bad, seam_lines,
                 frames_band, worst_run, worst_run_start);
        // every one of the 68 SCROLL writes must have reached a frame --
        // otherwise the bench compared a frozen PRAM against itself
        if (frames_bad != 0 || frames_band != 0 || moves != 68) total_fail++;
`ifdef NEW_RTL
        pc1 = int'(dbg_band[79:64]); bc1 = int'(dbg_band[95:80]);
        $display("             witness: pram_cnt +%0d (writes landing in lines 0..399: %0d), band_cnt +%0d, last {start,max}=%0d,%0d worst=%0d",
                 pc1 - pc0, n_active, bc1 - bc0, dbg_band[56:48], dbg_band[40:32], dbg_band[8:0]);
        if (pc1 - pc0 != n_active || bc1 != bc0) total_fail++;
`endif
    endtask

    initial begin
        pram = '0;
        repeat (10) @(posedge clk); rst = 0;
        wait_line(0); wait_line(0); wait_line(0);

        // [0xBB6]=0: LEN bit14 clear -> PITCH 40 counts words (80 bytes)
        run_pass("W=37",   37,  8'h00);   // early in the active display
        run_pass("W=200",  200, 8'h00);   // mid-screen
        run_pass("W=396",  396, 8'h00);   // on the old RTL's wrap edge
        run_pass("W=420",  420, 8'h00);   // in the blank, after vsync start
        run_pass("W=rand", -1,  8'h00);
        // [0xBB6]=0x40: LEN bit14 set -> PITCH counts bytes, so 80
        pitch = 8'd80;
        run_pass("W=rand/b14", -1, 8'h40);

        if (total_fail == 0)
            $display("PASS tb_gvram_depth_wipe");
        else
            $display("FAIL tb_gvram_depth_wipe (%0d passes off the np21w frame model)", total_fail);
        $finish;
    end
endmodule
`default_nettype wire
