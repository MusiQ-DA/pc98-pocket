// tb_draw_boot -- does draw_test.asm's GDC traffic leave the chips in the
// state the display needs? Replays the exact bytes the boot sector writes,
// through the same ~11-cycle io_write_n the real bus produces, and checks the
// registers the raster actually reads:
//
//   slave GDC  (graphics) : PITCH, SCROLL partition, START -> a linear
//                           640x400 map where plane offset = line*80 + x/8.
//   master GDC (text)     : CSRFORM + CSRW -> an enabled full-block cursor.
//
// This is the byte-level check; the framebuffer it feeds is exercised by the
// boot benches. Not CI -- a bring-up helper for the test disk.
module tb_draw_boot;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;
    logic reset = 1'b1;

    // Two channels, one per GDC. Each sees its own cs/a1.
    logic        cs_s = 0, a1_s = 0;      // slave (graphics)
    logic        cs_m = 0, a1_m = 0;      // master (text)
    logic        io_write_n = 1'b1, io_read_n = 1'b1;
    logic [7:0]  data_in = 8'h00;
    wire  [7:0]  dout_s, dout_m;

    wire        s_disp_on, m_disp_on;
    wire [7:0]  s_pitch,  m_pitch;
    wire [15:0] s_sad [0:3], m_sad [0:3];
    wire [9:0]  s_len [0:3], m_len [0:3];
    wire [15:0] s_caddr, m_caddr;
    wire        m_cen, m_cblink;
    wire [4:0]  m_ctop, m_cbot;

    pc98_gdc #(.MASTER(0)) gs (
        .clk(clk), .reset(reset),
        .cs(cs_s), .a1(a1_s), .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(dout_s), .hblank(1'b0), .vsync(1'b0),
        .disp_on(s_disp_on), .pitch(s_pitch), .part_sad(s_sad), .part_len(s_len),
        .cursor_addr(s_caddr), .cursor_dot(), .cursor_en(), .cursor_blink_en(),
        .cursor_top(), .cursor_bottom(), .cursor_rate(), .zoom_disp(),
        .csr_wr_count(), .csr_trace(), .draw_req(), .draw_op(), .draw_busy(),
        .srv_done_stb(1'b0), .draw_snap(), .unk_cmd(), .unk_count());
    pc98_gdc #(.MASTER(1)) gm (
        .clk(clk), .reset(reset),
        .cs(cs_m), .a1(a1_m), .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(dout_m), .hblank(1'b0), .vsync(1'b0),
        .disp_on(m_disp_on), .pitch(m_pitch), .part_sad(m_sad), .part_len(m_len),
        .cursor_addr(m_caddr), .cursor_dot(), .cursor_en(m_cen),
        .cursor_blink_en(m_cblink), .cursor_top(m_ctop), .cursor_bottom(m_cbot),
        .cursor_rate(), .zoom_disp(),
        .csr_wr_count(), .csr_trace(), .draw_req(), .draw_op(), .draw_busy(),
        .srv_done_stb(1'b0), .draw_snap(), .unk_cmd(), .unk_count());

    int errors = 0;
    task automatic want(input string w, input int g, input int e);
        if (g !== e) begin
            $display("FAIL %-38s got %0d (0x%04x) want %0d", w, g, g, e);
            errors++;
        end else $display("ok   %-38s %0d (0x%04x)", w, g, g);
    endtask

    // one bus write, ~11 low cycles like the hardware strobe
    task automatic wr(input logic slave, input logic a1, input logic [7:0] d);
        @(posedge clk);
        cs_s = slave; cs_m = ~slave; a1_s = a1; a1_m = a1;
        data_in = d; io_write_n = 1'b0;
        repeat (11) @(posedge clk);
        io_write_n = 1'b1; cs_s = 0; cs_m = 0;
        @(posedge clk);
    endtask
    task automatic sc(input logic [7:0] c); wr(1'b1,1'b1,c); endtask
    task automatic sp(input logic [7:0] p); wr(1'b1,1'b0,p); endtask
    task automatic mc(input logic [7:0] c); wr(1'b0,1'b1,c); endtask
    task automatic mp(input logic [7:0] p); wr(1'b0,1'b0,p); endtask

    initial begin
        repeat (8) @(posedge clk);
        reset = 1'b0;
        repeat (4) @(posedge clk);

        // ---------- the exact draw_test.asm graphics sequence -------------
        // (the 0x6A analogue/clock writes live in pc98_gdc_mode2, not here)
        sc(8'h47); sp(8'd80);                 // PITCH = 80 bytes
        sc(8'h70);                            // SCROLL -> PRAM
        sp(8'h00); sp(8'h00);                 // part0 SAD = 0 (word)
        sp(8'h00); sp(8'h19);                 // part0 LEN raw 0x1900 -> 400
        repeat (12) sp(8'h00);                // partitions 1-3 empty
        sc(8'h6B);                            // START
        repeat (4) @(posedge clk);

        want("slave PITCH=80",        s_pitch,   80);
        want("slave part0 SAD=0",     s_sad[0],  16'h0000);
        want("slave part0 LEN=400",   s_len[0],  10'd400);
        want("slave disp_on",         s_disp_on, 1);

        // ---------- the exact draw_test.asm cursor sequence ---------------
        mc(8'h4B); mp(8'h8F);                 // CSRFORM: enable + 16-line rows
        mc(8'h49); mp(8'hE0); mp(8'h01); mp(8'h00); // CSRW cell 480
        repeat (4) @(posedge clk);

        want("cursor enabled",        m_cen,    1);
        want("cursor blinks",         m_cblink, 1);
        want("cursor top 0",          m_ctop,   0);
        want("cursor bottom 15",      m_cbot,   15);
        want("cursor cell 480",       m_caddr,  16'd480);

        if (errors == 0) $display("PASS tb_draw_boot");
        else             $display("FAIL tb_draw_boot (%0d)", errors);
        $finish;
    end
endmodule
