//
// tb_pc98_pipeline -- the whole text path, every real module, nothing faked
// between the guest bus and the pixel pin.
//
// The unit benches prove each stage in isolation; the boot bench proves the
// BIOS put bytes on the bus. What neither proves is that the bytes the bus
// carried end up as lit pixels when the path is the REAL one: the real TVRAM
// (with its two clock domains and its memory-switch write gate), the real
// row buffer fed by the real raster tick through the real pulse_cdc, the real
// ANK BRAM, the real font fetcher on the real multiport SDRAM, and the real
// renderer run by the real h/v counters.
//
// On hardware the symptom being chased is a black text plane with a live
// fetch counter. If this bench draws the cells the bus wrote, the RTL is
// exonerated end to end and the fault lives below RTL: Quartus, pin timing,
// the SDRAM part. If it does not, the failing stage can be bisected by the
// monitors in here.
//
// What is checked, in order of the pipeline:
//
//   * a guest write presented with AEN high lands NOWHERE (the real decode
//     drops it, the way a HOLD window drops it on the board)
//   * writes that do land produce a fill that reads back the same cells
//   * ANK and kanji glyphs reach the row buffer through their own paths
//   * the renderer turns them into the right pixels at the right dot
//   * an attribute of zero hides the cell (the hardware-black-screen shape)
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_pipeline;

    // Chipset clock ~43 MHz, dot clock ~21 MHz. The exact ratio is beside the
    // point; the CDC is exercised either way.
    logic clk = 0;      always #12 clk = ~clk;
    logic clk_dot = 0;  always #23 clk_dot = ~clk_dot;

    logic rst = 1'b1;

    // ------------------------------------------------------ guest bus model
    //
    // The decode is the one RAM.sv computes: the text window is A0000-A3FFF,
    // and a bus write only becomes a RAM write while the DMA/HOLD arbiter is
    // NOT holding the bus (address_enable_n low is the held state).
    logic [19:0] address          = 20'h0;
    logic        iorq             = 1'b1;
    logic        address_enable_n = 1'b0;
    logic        memory_write_n   = 1'b1;
    logic  [7:0] internal_data_bus = 8'h00;

    wire tvram_mem_select = ~iorq && ~address_enable_n
                          && (address[19:14] == 6'b101000);

    // ---------------------------------------------------------- the raster
    wire [9:0] pc98_h, pc98_v;
    wire       pc98_hs, pc98_vs, pc98_hb, pc98_vb, pc98_de, pc98_fs;

    pc98_video_timing u_timing (
        .clk(clk_dot), .ce(1'b1), .rst(1'b0),
        .hcount(pc98_h), .vcount(pc98_v),
        .hsync(pc98_hs), .vsync(pc98_vs),
        .hblank(pc98_hb), .vblank(pc98_vb),
        .de(pc98_de), .frame_start(pc98_fs)
    );

    // The row-fill trigger, copied field-for-field from Peripherals.sv: a tick
    // at the top dot of each text row, a registered edge detect, then the
    // toggle CDC into the chipset domain.
    wire  pc98_row_tick = pc98_de && (pc98_h == 10'd0) && (pc98_v[3:0] == 4'd0);
    logic pc98_row_tick_q = 1'b0;
    always_ff @(posedge clk_dot) pc98_row_tick_q <= pc98_row_tick;
    wire  pc98_row_start = pc98_row_tick & ~pc98_row_tick_q;

    wire pc98_row_fill;
    pulse_cdc u_rowsync (
        .src_clk(clk_dot), .src_rst(rst), .src_pulse(pc98_row_start),
        .src_busy(),
        .dst_clk(clk), .dst_rst(rst), .dst_pulse(pc98_row_fill)
    );

    wire [4:0]  next_row = (pc98_v[8:4] == 5'd24) ? 5'd0 : pc98_v[8:4] + 5'd1;
    wire [11:0] row_base = {1'b0, next_row, 6'd0} + {3'd0, next_row, 4'd0};

    // ------------------------------------------------------------- TVRAM
    wire [11:0] fil_cell;
    wire  [7:0] fil_char_lo, fil_char_hi;
    wire [11:0] vid_cell;
    wire  [7:0] vid_attr;
    wire  [7:0] tvram_cpu_q;

    pc98_tvram u_tvram (
        .clk(clk), .rst(rst),
        .cpu_addr (address[13:0]),
        .cpu_wren (tvram_mem_select & ~memory_write_n),
        .cpu_wdata(internal_data_bus),
        .cpu_q    (tvram_cpu_q),
        .fil_clk  (clk),      .fil_cell(fil_cell),
        .fil_char_lo(fil_char_lo), .fil_char_hi(fil_char_hi),
        .vid_clk  (clk_dot),  .vid_cell(vid_cell), .vid_attr(vid_attr)
    );

    // ------------------------------------------------------- row buffer
    wire        f_req, f_busy, f_valid;
    wire [19:0] f_addr;
    wire  [7:0] f_data;
    wire  [7:0] ank_code;
    wire  [3:0] ank_line;
    wire  [7:0] ank_row;
    wire [11:0] rd_cell_w;
    wire  [3:0] rd_line_w;
    wire  [7:0] rd_byte;
    wire        kanji_seen;
    wire        fill_busy;

    pc98_glyph_rowbuf u_rowbuf (
        .clk(clk), .rst(rst),
        .fill_start(pc98_row_fill), .row_base(row_base),
        .bitac(8'hFF), .busy(fill_busy),
        .tv_cell(fil_cell), .tv_char_lo(fil_char_lo), .tv_char_hi(fil_char_hi),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data),
        .ank_code(ank_code), .ank_line(ank_line), .ank_row(ank_row),
        .rd_clk(clk_dot), .rd_cell(rd_cell_w[6:0]), .rd_line(rd_line_w),
        .rd_byte(rd_byte), .kanji_seen(kanji_seen)
    );

    // ------------------------------------------------------------ ANK BRAM
    // Loaded through its write port exactly the way data_loader does it.
    logic        ank_wr_en = 1'b0;
    logic [10:0] ank_wr_addr = '0;
    logic [15:0] ank_wr_data = '0;

    pc98_font_ank u_ank (
        .wr_clk(clk), .wr_en(ank_wr_en),
        .wr_addr(ank_wr_addr), .wr_data(ank_wr_data),
        .rd_clk(clk), .code(ank_code), .line(ank_line), .row(ank_row)
    );

    // ------------------------------------------------ SDRAM font path
    localparam int ADDR_BITS = 24;
    localparam int LEN_BITS  = 4;
    localparam [ADDR_BITS-1:0] FONT_BASE = 24'h400000;

    wire                 p_req;
    wire [ADDR_BITS-1:0] p_addr;
    wire [LEN_BITS-1:0]  p_len;
    wire                 p_ack, p_rvalid, p_done;
    wire [15:0]          p_rdata;

    pc98_font_fetch #(.ADDR_BITS(ADDR_BITS), .LEN_BITS(LEN_BITS)) u_fetch (
        .clk(clk), .rst(rst),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data),
        .p_req(p_req), .p_addr(p_addr), .p_len(p_len), .p_ack(p_ack),
        .p_rvalid(p_rvalid), .p_rdata(p_rdata), .p_done(p_done)
    );

    wire [12:0] s_a;  wire [1:0] s_ba;
    wire        s_cke, s_ras_n, s_cas_n, s_we_n, s_dq_io;
    wire  [1:0] s_dqm;
    wire [15:0] s_dq_out, s_dq_in;
    wire        init_done;
    wire  [0:0] grant;

    sdram_mp #(.PORTS(1), .BURST_MAX(16), .CAS_LATENCY(2),
               .INIT_NOP(64), .REFRESH_INT(320)) u_sdram (
        .clk(clk), .rst(rst),
        .p_req(p_req), .p_we(1'b0), .p_addr(p_addr), .p_len(p_len),
        .p_ack(p_ack),
        .p_wcnt(), .p_wdata(16'd0), .p_wmask(2'b11),
        .grant(grant), .p_rvalid(p_rvalid), .p_rdata(p_rdata), .p_done(p_done),
        .init_done(init_done), .stat_idle(), .stat_refresh(),
        .sdram_a(s_a), .sdram_ba(s_ba), .sdram_cke(s_cke),
        .sdram_ras_n(s_ras_n), .sdram_cas_n(s_cas_n), .sdram_we_n(s_we_n),
        .sdram_dqm(s_dqm), .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out),
        .sdram_dq_io(s_dq_io)
    );

    sdram_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                  .PHYSICAL_DQ(1'b1),
                  .T_RAS(2), .T_RC(3), .T_REF(0)) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ---------------------------------------------------------- renderer
    wire  [6:0] font_cell;
    wire  [3:0] font_line;
    wire  [7:0] font_row = rd_byte;
    wire  [2:0] grb;
    wire        pixel;

    assign rd_cell_w = {5'd0, font_cell};
    assign rd_line_w = font_line;

    pc98_text_render u_render (
        .clk(clk_dot), .pix_ce(1'b1),
        .hcount(pc98_h), .vcount(pc98_v), .blink_on(1'b1),
        .gdc_on(1'b0), .gdc_pitch(8'd0), .gdc_sad(16'd0),
        .cur_addr(16'hFFFF), .cur_en(1'b0), .cur_blink(1'b0),
        .cur_top(5'd0), .cur_bot(5'd0),
        .tv_cell(vid_cell), .tv_attr(vid_attr),
        .font_cell(font_cell), .font_line(font_line), .font_row(font_row),
        .grb(grb), .pixel(pixel)
    );

    // ------------------------------------------------- what is on screen
    // Capture every displayed pixel of text row 0 (vcount 0-15, hcount 0-63)
    // during the sample frame, then compare with the glyphs that were poked.
    logic [7:0] screen [0:15][0:7];   // [line][cell] = the 8 dots drawn

    int sample_frame = 0;
    always_ff @(posedge clk_dot) begin
        if (pc98_fs) sample_frame <= sample_frame + 1;
        if (sample_frame == 2 && pc98_de && pc98_v < 16 && pc98_h < 64)
            screen[pc98_v[3:0]][pc98_h[5:3]][pc98_h[2:0]] <= pixel;
    end

    // -------------------------------------------------------------- bus
    task automatic bus_write(input [19:0] addr, input [7:0] data,
                             input bit aen_high = 1'b0);
        @(negedge clk);
        address          = addr;
        internal_data_bus = data;
        iorq             = 1'b0;
        address_enable_n = aen_high ? 1'b1 : 1'b0;
        memory_write_n   = 1'b0;
        repeat (6) @(negedge clk);     // a real write strobe is several clocks
        memory_write_n   = 1'b1;
        address_enable_n = 1'b0;
        iorq             = 1'b1;
        @(negedge clk);
    endtask

    // Cell helper: code plane at A0000+cell*2, attribute at A2000+cell*2.
    task automatic put_char(input int cc, input [15:0] code,
                            input [7:0] attr);
        bus_write(20'hA0000 + 20'(cc*2),     code[7:0]);
        bus_write(20'hA0000 + 20'(cc*2) + 1, code[15:8]);
        bus_write(20'hA2000 + 20'(cc*2),     attr);
    endtask

    // ------------------------------------------------------------ checks
    int errors = 0;

    // screen[l][c] is indexed by dot number, so bit 0 is the LEFTMOST pixel;
    // the font byte is MSB-leftmost. A correctly drawn line compares as the
    // bit-reverse of the font byte -- which is why the 'A' glyph, palindromic
    // on every line, cannot catch a reversal and the kanji can.
    function automatic [7:0] bitrev(input [7:0] v);
        for (int i = 0; i < 8; i++) bitrev[7-i] = v[i];
    endfunction

    task automatic expect_line(input int cc, input int line,
                               input [7:0] want, input string what);
        if (screen[line][cc] !== bitrev(want)) begin
            $display("  FAIL %s: line %0d got %08b want %08b (drawn order)",
                     what, line, screen[line][cc], bitrev(want));
            errors++;
        end
    endtask

    // Counters on the fetch handshake, same shape as the post-monitor's.
    int freq_count = 0, fvalid_count = 0;
    logic f_req_q = 1'b0;
    always_ff @(posedge clk) begin
        f_req_q <= f_req;
        if (f_req && !f_req_q) freq_count <= freq_count + 1;
        if (f_valid)           fvalid_count <= fvalid_count + 1;
    end

    logic [7:0] want [0:65535];

    initial begin
        $display("=== the whole text path, real modules ===");

        for (int b = 0; b < 65536; b++) want[b] = 8'h00;

        // The font slice: FONT.ROM bytes into the SDRAM model, and the ANK
        // window of the same file into the ANK BRAM through its write port.
        begin
            int fh, waddr, wval, lines;
            fh = $fopen("sim/font_slice.hex", "r");
            if (fh == 0) begin
                $display("  FAIL cannot open sim/font_slice.hex");
                $fatal;
            end
            lines = 0;
            while ($fscanf(fh, "%h %h\n", waddr, wval) == 2) begin
                sdr.poke(FONT_BASE + waddr*2,     16'(wval & 8'hFF));
                sdr.poke(FONT_BASE + waddr*2 + 1, 16'((wval >> 8) & 8'hFF));
                want[waddr*2]     = 8'(wval & 8'hFF);
                want[waddr*2 + 1] = 8'((wval >> 8) & 8'hFF);
                lines++;
            end
            $fclose(fh);
            $display("  preloaded %0d font words", lines);
        end

        // ANK 0x0800-0x17FF, packed two bytes a word as the loader writes it.
        for (int w = 0; w < 2048; w++) begin
            @(negedge clk);
            ank_wr_en   = 1'b1;
            ank_wr_addr = 11'(w);
            ank_wr_data = {want[16'h0800 + w*2 + 1], want[16'h0800 + w*2]};
        end
        @(negedge clk);
        ank_wr_en = 1'b0;

        repeat (20) @(posedge clk);
        rst = 0;
        wait (init_done);
        $display("  sdram up at %0t", $time);

        // ---- the guest writes -------------------------------------------
        // The BIOS's own clear writes 0x00 codes and 0xE1 attributes across
        // the whole plane; do that first so every undriven cell is a
        // printable-looking blank, not an X.
        for (int c = 0; c < 80; c++) begin
            bus_write(20'hA0000 + 20'(c*2),     8'h00);
            bus_write(20'hA0000 + 20'(c*2) + 1, 8'h00);
            bus_write(20'hA2000 + 20'(c*2),     8'hE1);
        end

        // Cell 0: ANK 'A'. Cells 1-2: the kanji pair tb_pc98_font_sdram
        // measures (left {hi=22,lo=04} -> FONT.ROM 0x3C40, right 0x3C50).
        // Cell 3: ANK 'A'. Cell 4: written while the bus is HELD -- it must
        // not land. Cell 5: attr 0 -- present but secret, must draw nothing.
        put_char(0, 16'h0041, 8'hE1);
        put_char(1, 16'h2204, 8'hE1);
        put_char(2, 16'hFFFF, 8'hE1);
        put_char(3, 16'h0041, 8'hE1);

        // A write inside a HOLD window: the arbiter dropped the bus, so this
        // cell must stay whatever the clear left it.
        bus_write(20'hA0000 + 20'd12,    8'h41, .aen_high(1'b1));   // cell 6 lo
        bus_write(20'hA2000 + 20'd12,    8'h00, .aen_high(1'b1));   // cell 6 attr
        // Cell 5: written normally but with a zero attribute -- secret.
        put_char(5, 16'h0041, 8'h00);

        // Readback through the CPU port proves the writes landed in the
        // bank the renderer will read.
        repeat (4) @(posedge clk);
        if (u_tvram.char_lo[0] !== 8'h41) begin
            $display("  FAIL char_lo[0] %02h want 41", u_tvram.char_lo[0]);
            errors++;
        end
        if (u_tvram.char_hi[1] !== 8'h22) begin
            $display("  FAIL char_hi[1] %02h want 22", u_tvram.char_hi[1]);
            errors++;
        end
        if (u_tvram.attr[0] !== 8'hE1) begin
            $display("  FAIL attr[0] %02h want E1", u_tvram.attr[0]);
            errors++;
        end
        if (u_tvram.char_lo[6] !== 8'h00) begin
            $display("  FAIL AEN-high write landed: char_lo[6] %02h want 00",
                     u_tvram.char_lo[6]);
            errors++;
        end
        if (u_tvram.attr[6] !== 8'hE1) begin
            $display("  FAIL AEN-high attr write landed: attr[6] %02h want E1",
                     u_tvram.attr[6]);
            errors++;
        end

        $display("  writes done at %0t -- running frames", $time);

        // The raster runs itself; two full frames is the steady state (the
        // buffer read during row 0 was filled by the row-24 tick).
        wait (sample_frame == 3);

        // ---- what the pixels say ----------------------------------------
        for (int l = 0; l < 16; l++) begin
            expect_line(0, l, want[16'h0C10 + l], "cell0 'A'");
            expect_line(1, l, want[16'h3C40 + l], "cell1 kanji left");
            expect_line(2, l, want[16'h3C50 + l], "cell2 kanji right");
            expect_line(3, l, want[16'h0C10 + l], "cell3 'A'");
            expect_line(4, l, 8'h00,              "cell4 blank");
            expect_line(5, l, 8'h00,              "cell5 secret");
            expect_line(6, l, 8'h00,              "cell6 AEN-dropped");
        end

        $display("  fetch requests: %0d, beats: %0d", freq_count, fvalid_count);
        if (freq_count == 0) begin
            $display("  FAIL no font requests -- the kanji cells were missed");
            errors++;
        end

        $display("");
        $display("  errors: %0d", errors);
        $display("  RESULT: %s", errors == 0 ? "PASS" : "FAIL");
        $finish;
    end

    // The raster is the metronome; if it ever stops the wait above hangs, so
    // bound the whole run at ~4 frames of dot clocks.
    initial begin
        repeat (1_700_000) @(posedge clk_dot);
        $display("  TIMEOUT: never reached frame 3");
        $display("  RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
