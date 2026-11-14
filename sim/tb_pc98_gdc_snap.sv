// tb_pc98_gdc_snap -- the drawing snapshot's byte map, tested through the
// real guest port.
//
// The engine benches (tb_softcpu_gdcdraw, sim_gdc_draw.sh) write draw_snap
// DIRECTLY -- they never run pc98_gdc's latch, so a wrong snap_src maps the
// engine perfectly while the machine ships para[k + 2] where np21w reads
// para[k] (exactly what happened: TEXTW[2..7] rode bytes 24..29 as
// para[26..31] while every bench stayed green). This bench drives the slave
// GDC's ports the way Peripherals does -- command strobes on a1, parameters
// on a0, dedup on the strobe's rising edge -- fills every PRAM field the
// snapshot reads, drops a VECTE, and checks all eight snapshot words against
// the np21w byte map:
//
//   snap k    para                    np21w reader
//   0..10     32..42   VECTW          vectdraw (DC, D, D2, D1, ope)
//   11..13    43..45   CSRW low 3     gdcsub_x/y from the EAD dword
//   14        46       MASK lo        np21w reads the CSRW dword's 4th byte
//   15..16    20..21   TEXTW[0..1]    vectdraw's vectt pattern
//   17        8        ZOOM           gdcsub_zoom (multiple)
//   18        53       WRITE          the drawing-family command byte
//   19..20    46..47   MASK           gdcsub_write
//   21..22    54..55   CODE           gdcsub_write
//   23        0        SYNC[0]        pad -- nothing reads it (it carries
//                                     the SLAVE reset seed 06, so a 00 here
//                                     would mean the latch zeroed instead)
//   24..29    22..27   TEXTW[2..7]    textdraw's pat[2..7] (8-byte area)
//   30..31    --       pad
//
// Then the retire: srv_done_stb runs np21w's gdc_vectreset on the live PRAM
// (VECTW+1..10 cleared to the post-draw constants) and a SECOND VECTE
// latches the reset values -- DC=0, D=8, D2=8, D1=DM=FFFF -- while TEXTW,
// CSRW, ZOOM, MASK and CODE ride through untouched, and WDAT's completion
// latch (masked into para only when its run actually finishes) stays dark
// because no WDAT was armed.
`default_nettype none

module tb_pc98_gdc_snap;
    localparam time TCLK = 20ns;
    logic clk = 0;
    always #(TCLK/2) clk = ~clk;

    logic reset = 1'b1;
    logic cs = 1'b0, a1 = 1'b0, io_write_n = 1'b1, io_read_n = 1'b1;
    logic [7:0] data_in = 8'h00;
    logic srv_done_stb = 1'b0;

    logic [7:0] data_out;
    logic disp_on; logic [7:0] pitch;
    logic [15:0] part_sad [0:3]; logic [9:0] part_len [0:3];
    logic [3:0] part_pbyte; logic [5:0] part_bend [0:2];
    logic [15:0] cursor_addr; logic [3:0] cursor_dot;
    logic cursor_en, cursor_blink_en; logic [4:0] cursor_top, cursor_bottom;
    logic [5:0] cursor_rate; logic [1:0] zoom_disp; logic [4:0] line_rep;
    logic [9:0] vlines; logic [5:0] vbp;
    logic draw_req, draw_busy, draw_timeout;
    logic [7:0] draw_op;
    logic [31:0] draw_snap [0:7];

    pc98_gdc #(.MASTER(1'b0)) dut (
        .clk(clk), .reset(reset),
        .cs(cs), .a1(a1), .io_read_n(io_read_n), .io_write_n(io_write_n),
        .data_in(data_in), .data_out(data_out),
        .hblank(1'b0), .vblank(1'b0),
        .disp_on(disp_on), .pitch(pitch),
        .part_sad(part_sad), .part_len(part_len), .part_pbyte(part_pbyte),
        .part_bend(part_bend), .cursor_addr(cursor_addr),
        .cursor_dot(cursor_dot), .cursor_en(cursor_en),
        .cursor_blink_en(cursor_blink_en), .cursor_top(cursor_top),
        .cursor_bottom(cursor_bottom), .cursor_rate(cursor_rate),
        .zoom_disp(zoom_disp), .line_rep(line_rep),
        .vlines(vlines), .vbp(vbp),
        .draw_req(draw_req), .draw_op(draw_op), .draw_busy(draw_busy),
        .draw_timeout(draw_timeout), .srv_done_stb(srv_done_stb),
        .draw_snap(draw_snap)
    );

    // One guest byte: latch through the strobe's low cycle, commit once as
    // it lifts -- the dedup pc98_gdc.sv itself documents.
    task automatic gdc_wr(input logic a1v, input logic [7:0] v);
        begin
            @(negedge clk);
            cs <= 1'b1; a1 <= a1v; io_write_n <= 1'b0; data_in <= v;
            repeat (2) @(negedge clk);
            io_write_n <= 1'b1; cs <= 1'b0;
            @(negedge clk);
        end
    endtask

    task automatic cmd(input logic [7:0] v);  gdc_wr(1'b1, v); endtask
    task automatic par(input logic [7:0] v);  gdc_wr(1'b0, v); endtask

    integer k, errors;
    logic [7:0] exp [0:31];

    // The snapshot as np21w's readers say it must look, given what this
    // bench wrote into each PRAM field (fill byte = 0x80 | para index, so a
    // wrong snap_src names the para it grabbed).
    function automatic logic [7:0] expect_byte(input int k);
        begin
            if      (k <= 10) expect_byte = 8'h80 + 6'(32 + k);       // VECTW
            else if (k <= 13) expect_byte = 8'h80 + 6'(43 + k - 11);   // CSRW
            else if (k == 14) expect_byte = 8'h80 + 6'd46;             // MASK lo
            else if (k <= 16) expect_byte = 8'h80 + 6'(20 + k - 15);   // TEXTW lo
            else if (k == 17) expect_byte = 8'h12;                     // ZOOM
            else if (k == 18) expect_byte = 8'h20;                     // WRITE
            else if (k <= 20) expect_byte = 8'h80 + 6'(46 + k - 19);   // MASK
            else if (k <= 22) expect_byte = 8'h80 + 6'(54 + k - 21);   // CODE
            else if (k == 23) expect_byte = 8'h06;                     // SYNC[0] seed (pad)
            else if (k <= 29) expect_byte = 8'h80 + 6'(20 + k - 22);   // TEXTW hi
            else              expect_byte = 8'h00;                     // pad
        end
    endfunction

    task automatic check_snap(input string tag);
        begin
            for (k = 0; k < 32; k = k + 1) begin
                exp[k] = expect_byte(k);
                if (draw_snap[k/4][8*(k%4) +: 8] !== exp[k]) begin
                    errors = errors + 1;
                    $display("%s: snap byte %0d = %02x, want %02x (para[%0d]",
                             tag, k, draw_snap[k/4][8*(k%4) +: 8], exp[k],
                             (k <= 10) ? 32 + k :
                             (k <= 13) ? 43 + k - 11 :
                             (k == 14) ? 46 :
                             (k <= 16) ? 20 + k - 15 :
                             (k == 17) ? 8 :
                             (k == 18) ? 53 :
                             (k <= 20) ? 46 + k - 19 :
                             (k <= 22) ? 54 + k - 21 :
                             (k <= 29) ? 20 + k - 22 : 0);
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        repeat (4) @(negedge clk);
        reset <= 1'b0;
        repeat (2) @(negedge clk);

        // Fill every field the snapshot reads.
        cmd(8'h46); par(8'h12);                                  // ZOOM para[8]
        cmd(8'h78);                                              // TEXTW 8 bytes
        for (k = 0; k < 8; k = k + 1) par(8'h80 + 6'(20 + k));   // para[20..27]
        cmd(8'h4C);                                              // VECTW 11 bytes
        for (k = 0; k < 11; k = k + 1) par(8'h80 + 6'(32 + k));  // para[32..42]
        cmd(8'h49);                                              // CSRW 3 bytes
        for (k = 0; k < 3; k = k + 1) par(8'h80 + 6'(43 + k));   // para[43..45]
        cmd(8'h4A); par(8'h80 + 6'd46); par(8'h80 + 6'd47);      // MASK
        cmd(8'h20); par(8'h80 + 6'd54); par(8'h80 + 6'd55);      // WDAT + CODE
        // WDAT's LAST parameter completion raises its own draw request --
        // np21w's gdc_write_psetl with para done -- so retire it (no
        // vectreset: 0x20 is not an EXECUTE op) before the VECTE below can
        // latch anything.
        if (!draw_req || draw_op !== 8'h20) begin
            errors = errors + 1;
            $display("WDAT did not raise draw_req/draw_op=20 (req=%0d op=%02x)",
                     draw_req, draw_op);
        end
        srv_done_stb <= 1'b1; @(negedge clk); srv_done_stb <= 1'b0;
        repeat (4) @(negedge clk);
        if (draw_req) begin
            errors = errors + 1;
            $display("WDAT draw_req did not drop after srv_done_stb");
        end

        // VECTE: the snapshot latches.
        cmd(8'h6C);
        repeat (4) @(negedge clk);
        if (!draw_req) begin
            errors = errors + 1;
            $display("VECTE did not raise draw_req");
        end
        if (draw_op !== 8'h6C) begin
            errors = errors + 1;
            $display("draw_op = %02x, want 6c", draw_op);
        end
        check_snap("first draw");

        // The retire: gdc_vectreset clears the live VECTW, and the next
        // VECTE latches the reset constants -- bytes 1..10 change, the rest
        // ride. np21w gdc.c vectdraw's epilogue.
        srv_done_stb <= 1'b1; @(negedge clk); srv_done_stb <= 1'b0;
        repeat (4) @(negedge clk);
        if (draw_req) begin
            errors = errors + 1;
            $display("draw_req did not drop after srv_done_stb");
        end
        cmd(8'h6C);
        repeat (4) @(negedge clk);
        for (k = 0; k < 32; k = k + 1) begin
            exp[k] = expect_byte(k);
            case (k)
                1, 2:    exp[k] = 8'h00;   // DC = 0
                3:       exp[k] = 8'h08;   // D  = 8
                4:       exp[k] = 8'h00;
                5:       exp[k] = 8'h08;   // D2 = 8
                6:       exp[k] = 8'h00;
                7:       exp[k] = 8'hFF;   // D1 = FFFF
                8:       exp[k] = 8'hFF;
                9:       exp[k] = 8'hFF;   // DM = FFFF
                10:      exp[k] = 8'hFF;
                default: ;
            endcase
            if (draw_snap[k/4][8*(k%4) +: 8] !== exp[k]) begin
                errors = errors + 1;
                $display("after vectreset: snap byte %0d = %02x, want %02x",
                         k, draw_snap[k/4][8*(k%4) +: 8], exp[k]);
            end
        end

        if (errors == 0) $display("PASS tb_pc98_gdc_snap");
        else             $display("FAIL tb_pc98_gdc_snap: %0d errors", errors);
        $finish;
    end
endmodule

`default_nettype wire
