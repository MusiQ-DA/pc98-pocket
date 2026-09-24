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

    logic [7:0]  pitch = 8'd40;
    logic [15:0] part_sad [0:3] = '{16'd0, 16'd0, 16'd0, 16'd0};
    logic [9:0]  part_len [0:3] = '{10'd400, 10'd0, 10'd0, 10'd0};

    logic        p_req, p_ack = 0, p_rvalid = 0, p_done = 0;
    logic [23:0] p_addr;
    logic [3:0]  p_len;
    logic [15:0] p_rdata = 0;
    logic [3:0]  gfx_dot;

    pc98_gvram_display dut (
        .clk(clk), .rst(rst), .rd_clk(rd_clk),
        .hcount(h), .vcount(v), .disp_on(disp_on),
        .disp_page(disp_page), .analog_mode(analog_m),
        .pitch(pitch), .part_sad(part_sad), .part_len(part_len),
        .p_req(p_req), .p_addr(p_addr), .p_len(p_len),
        .p_ack(p_ack), .p_rvalid(p_rvalid), .p_rdata(p_rdata), .p_done(p_done),
        .gfx_dot(gfx_dot)
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

    // The same partition walk the DUT applies: line -> (sad + rel*pitch)*2.
    function automatic int line_base(input int L);
        int total, rel, wa;
        total = part_len[0] + part_len[1] + part_len[2] + part_len[3];
        rel   = (total != 0) ? L % total : L;
        if      (rel < part_len[0]) wa = part_sad[0] + rel * pitch;
        else if (rel < part_len[0] + part_len[1])
            wa = part_sad[1] + (rel - part_len[0]) * pitch;
        else if (rel < part_len[0] + part_len[1] + part_len[2])
            wa = part_sad[2] + (rel - part_len[0] - part_len[1]) * pitch;
        else
            wa = part_sad[3] + (rel - part_len[0] - part_len[1] - part_len[2]) * pitch;
        return (wa * 2) & 32'h7FFF;
    endfunction

    // expected dot for displayed line L, dot d: byte i=d/8, bit 7-(d%8).
    function automatic logic [3:0] exp_dot(input int L, input int d, input int pg);
        int i, base;
        i = d / 8;
        base = line_base(L);
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

        if (errors == 0 && checked > 200000)
            $display("PASS tb_pc98_gvram_display (%0d dots)", checked);
        else
            $display("FAIL tb_pc98_gvram_display (%0d errors)", errors);
        $finish;
    end
endmodule
`default_nettype wire
