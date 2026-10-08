`default_nettype none
// tb_pc98_gvram_display -- pixel check of the graphics display fetch.
//
// A fake SDRAM port answers every burst with a byte that names its plane
// and its offset, then every dot of several frames is compared against the
// address the slave GDC's SAD/PITCH/partition registers imply. Phases:
// A BIOS-linear, B scrolled (SAD), C split screen (two partitions),
// D short pitch, E page one, F digital mode (no plane E).
module tb_pc98_gvram_display;
    logic clk = 0; always #11 clk = ~clk;
    logic rd_clk = 0; always #23 rd_clk = ~rd_clk;

    logic rst = 1;
    logic [9:0] h = 0, v = 0;
    logic disp_on = 1, disp_page = 0, analog_m = 1;
    logic dbl = 0;

    logic [7:0]  pitch = 8'd40;
    logic        mhz5  = 1'b0;
    logic [4:0]  lrep  = 5'd0;
    logic [15:0] part_sad [0:3] = '{16'd0, 16'd0, 16'd0, 16'd0};
    logic [9:0]  part_len [0:3] = '{10'd400, 10'd0, 10'd0, 10'd0};
    logic [3:0]  part_pbyte = 4'h0;
    logic [5:0]  vshift = 6'd0;

    logic        p_req, p_ack = 0, p_rvalid = 0, p_done = 0;
    logic [23:0] p_addr;
    logic [3:0]  p_len;
    logic [15:0] p_rdata = 0;
    logic [3:0]  gfx_dot;

    pc98_gvram_display dut (
        .clk(clk), .rst(rst), .rd_clk(rd_clk),
        .hcount(h), .vcount(v), .disp_on(disp_on),
        .disp_page(disp_page), .analog_mode(analog_m),
        .pitch(pitch), .mhz5(mhz5), .dbl(dbl), .lrep(lrep),
        .part_sad(part_sad), .part_len(part_len),
        .part_pbyte(part_pbyte), .vshift(vshift),
        .p_req(p_req), .p_addr(p_addr), .p_len(p_len),
        .p_ack(p_ack), .p_rvalid(p_rvalid), .p_rdata(p_rdata), .p_done(p_done),
        .gfx_dot(gfx_dot), .dbg()
    );

    // raster: 848 dots x 440 lines on rd_clk
    always_ff @(posedge rd_clk) begin
        if (h == 10'd847) begin h <= 0; v <= (v == 10'd439) ? 10'd0 : v + 10'd1; end
        else h <= h + 10'd1;
    end

    // port model: byte = plane_tag*0x40 + byte-offset-in-plane.
    function automatic [7:0] pbyte(input int a);
        int pl;
        if (a >= 24'h600000)         pl = 4;
        else if (a[19:15] == 5'b10101) pl = 0;
        else if (a[19:15] == 5'b11100) pl = 3;
        else pl = a[15] ? 2 : 1;
        return 8'(pl * 8'h40) + 8'(a & 24'h7FFF);
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

    // The same partition walk the DUT applies, written the way np21w
    // makegrph.c's grphput_indirty0 does it: per emitted RASTERLINE the
    // partition's `remain` decrements, and a `mul` counter strides the
    // address by pitch every lr rasterlines. Three np21w rules:
    //   * a ZERO LEN is absorbing -- `remain--; if (!remain)` wraps the UINT
    //     to 0xFFFFFFFF instead of firing, so the walk parks in that
    //     partition forever rather than skipping it;
    //   * the pointer is CYCLIC -- `s_scrp = (s_scrp + 4) & 0x0c` runs
    //     partition three back to partition zero, so a screen taller than
    //     the summed LENs repeats the whole quartet (each partition from
    //     its own SAD);
    //   * PITCH counts bytes when the partition's LEN bit14 is set
    //     (makegrph) or the 5MHz clock flag is (maketgrp), else words
    //     doubled into bytes -- either way floored even (`&= 0xfe`).
    function automatic int pitch_bytes(input int p);
        return (((part_pbyte[p] | mhz5) ? pitch : (pitch << 1)) & 8'hFE);
    endfunction
    function automatic int mul_reload();
        return (lrep != 0) ? lrep + 1 : (dbl ? 2 : 1);
    endfunction
    function automatic int line_base(input int L);
        int p, rel, mul, vad;
        p = 0; rel = 0; mul = mul_reload();
        vad = (part_sad[p] * 2) & 32'h7FFF;
        for (int i = 0; i < L; i++) begin
            // the bookkeeping np21w runs after emitting rasterline i
            rel = rel + 1;                                   // remain--
            if (part_len[p] != 0 && rel >= int'(part_len[p])) begin
                p = (p + 1) & 3; rel = 0;
                vad = (part_sad[p] * 2) & 32'h7FFF;
                mul = mul_reload();
            end else begin
                mul = mul - 1;
                if (mul == 0) begin
                    mul = mul_reload();
                    vad = (vad + pitch_bytes(p)) & 32'h7FFF;
                end
            end
        end
        return vad;
    endfunction

    // expected dot for displayed line L, dot d: byte i=d/8, bit 7-(d%8).
    // With vshift the raster carries VRAM line L-vshift, and the top vshift
    // lines carry nothing at all (np21w zero-fills that surface band).
    function automatic logic [3:0] exp_dot(input int L, input int d, input int pg);
        int i, base;
        i = d / 8;
        if (L < int'(vshift)) return 4'd0;
        base = line_base(L - int'(vshift));
        begin
            logic [3:0] dd;
            for (int pl = 0; pl < 4; pl++) begin
                logic [23:0] pa;
                if (pg) pa = 24'h600000 + 24'(pl) * 24'h8000 + 24'(base + i);
                else case (pl)
                    0: pa = 24'hA8000 + 24'(base + i);
                    1: pa = 24'hB0000 + 24'(base + i);
                    2: pa = 24'hB8000 + 24'(base + i);
                    default: pa = 24'hE0000 + 24'(base + i);
                endcase
                begin
                    logic [7:0] pb;
                    pb = pbyte(int'(pa));
                    dd[pl] = pb[7 - (d % 8)];
                end
            end
            // palette index is {E,G,R,B}: plane1=R -> bit1, plane2=G -> bit2
            return {dd[3] & 1'(analog_m), dd[2], dd[1], dd[0]};
        end
    endfunction

    int errors = 0, checked = 0;
    int frames = 0;
    logic quiet = 1'b0;   // mute checks for the rest of a rewritten frame
    // The DUT walks the partitions incrementally like the uPD7220: SAD and
    // PITCH are latched when a partition starts, so a mid-frame rewrite
    // only takes effect at the next frame -- and the walk itself only
    // anchors its phase at the first wrap. Frame 0 and the remainder of a
    // rewrite frame are therefore legitimately "old" data: don't score it.
    // (v,h) starts at (0,0), so the frames counter ticks once at time zero
    // -- wait for the SECOND wrap to be sure a whole frame has run.
    always_ff @(posedge rd_clk) begin
        if (v == 10'd0 && h == 10'd0) begin
            frames <= frames + 1;
            quiet  <= 1'b0;
        end
        if (!rst && frames >= 2 && !quiet && v >= 10 && v < 390
         && h > 10 && h < 400) begin
            logic [3:0] exp;
            exp = exp_dot(int'(v), int'(h) - 1, disp_page ? 1 : 0);
            checked++;
            if (gfx_dot !== exp) begin
                errors++;
                if (errors < 20)
                    $display("FAIL v=%0d h=%0d dot=%b exp=%b", v, h, gfx_dot, exp);
            end
        end
    end

    task settle(input int frames);
        repeat (848 * 440 * frames) @(posedge rd_clk);
    endtask

    initial begin
        repeat (10) @(posedge clk); rst = 0;

        settle(3);   // A: linear screen, SAD=0 PITCH=40 LEN=400 (BIOS shape)
        $display("A: linear  checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // B: scroll -- SAD=200 words = +400 B
        part_sad[0] = 16'd200;
        settle(3);
        $display("B: sad=200 checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // C: split -- two 200-line partitions
        part_sad[0] = 16'h1000; part_len[0] = 10'd200;
        part_sad[1] = 16'd0;    part_len[1] = 10'd200;
        settle(3);
        $display("C: split   checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // D: half pitch -- 40-byte lines
        part_sad[0] = 16'd0; part_len[0] = 10'd400;
        part_sad[1] = 16'd0; part_len[1] = 10'd0;
        pitch = 8'd20;
        settle(3);
        $display("D: pitch20 checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // E: page one
        pitch = 8'd40; disp_page = 1;
        settle(3);
        $display("E: page1   checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // F: digital -- plane E skipped/masked
        disp_page = 0; analog_m = 0;
        settle(3);
        $display("F: digital checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // G: 5MHz clock -- PITCH is bytes now, and
        analog_m = 1; mhz5 = 1;    //    21 floors to 20 (np21w's & 0xfe)
        pitch = 8'd21;
        settle(3);
        $display("G: mhz5/21 checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // H: the BIOS high-res shape -- clock=3,
        pitch = 8'd80;             //    PITCH=80, the same 80-byte line as A
        settle(3);
        $display("H: mhz5/80 checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // I: 200-line doubling -- LEN counts
        dbl = 1'b1;                //    rasterlines now, so 400 of them
        mhz5 = 1'b0; pitch = 8'd40;//    show 200 guest lines, each twice
        part_len[0] = 10'd400;
        settle(3);
        $display("I: doubled checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // J: a ZERO middle LEN absorbs -- np21w's
        dbl = 1'b0;                //    UINT countdown wraps instead of
        part_sad[0] = 16'h0000; part_len[0] = 10'd100;   // firing, so lines
        part_sad[1] = 16'h0800; part_len[1] = 10'd0;     // 100+ are all
        part_sad[2] = 16'h2000; part_len[2] = 10'd80;    // partition one's,
        part_sad[3] = 16'h0000; part_len[3] = 10'd0;     // never two's
        settle(3);
        $display("J: zeroLEN checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // K: cyclic -- the four LENs sum to 180,
        part_sad[0] = 16'h0000; part_len[0] = 10'd50;    // so the walk wraps
        part_sad[1] = 16'h0800; part_len[1] = 10'd60;    // partition three
        part_sad[2] = 16'h2000; part_len[2] = 10'd40;    // back to partition
        part_sad[3] = 16'h3000; part_len[3] = 10'd30;    // zero at line 180
        settle(3);
        $display("K: cyclic  checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // L: doubled split -- LENs count
        dbl = 1'b1;                //    RASTERLINES (makegrph), so a 200-
        part_sad[0] = 16'h0000; part_len[0] = 10'd200;   // LEN partition ends
        part_sad[1] = 16'h0800; part_len[1] = 10'd200;   // at rasterline 200,
        part_sad[2] = 16'h0000; part_len[2] = 10'd0;     // not guest line 200
        part_sad[3] = 16'h0000; part_len[3] = 10'd0;
        settle(3);
        $display("L: dblsplit checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // M: LEN bit14 set -- PITCH is bytes
        dbl = 1'b0;                //    (makegrph): 21 floors to 20, where
        part_pbyte = 4'h1;         //    the word reading would give 42
        pitch = 8'd21;
        part_sad[0] = 16'h0000; part_len[0] = 10'd400;
        part_sad[1] = 16'h0000; part_len[1] = 10'd0;
        settle(3);
        $display("M: pbyte   checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // N: CSRFORM LR=3 -- each VRAM line is
        part_pbyte = 4'h0;         //    held for four rasterlines (mul
        pitch = 8'd40;             //    stride), a 100-guest-line frame
        lrep = 5'd3; dbl = 1'b1;
        part_len[0] = 10'd400;
        settle(3);
        $display("N: lrep3   checked=%0d errors=%0d", checked, errors);

        quiet = 1'b1;              // O: VBP delta -- slave VBP 20 lines over
        lrep = 5'd0; dbl = 1'b0;   //    the master's (np21w grph_vbp): the
        vshift = 6'd20;            //    plane drops 20 lines, blank above,
        part_sad[0] = 16'h0000; part_len[0] = 10'd400;
        settle(3);                 //    bottom 20 clipped
        $display("O: vshift  checked=%0d errors=%0d", checked, errors);

        if (errors == 0 && checked > 200000)
            $display("PASS tb_pc98_gvram_display (%0d dots)", checked);
        else
            $display("FAIL tb_pc98_gvram_display (%0d errors)", errors);
        $finish;
    end
endmodule
`default_nettype wire
