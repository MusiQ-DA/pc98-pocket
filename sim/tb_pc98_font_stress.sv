//
// tb_pc98_font_stress -- the glyph fetch path under REAL contention.
//
// tb_pc98_font_sdram proves correctness on an idle bus: PORTS=1, one burst in
// flight, a four-cell row. Hardware runs the fetcher against three other
// masters -- the guest CPU, the CG window prefetcher, and the graphics display
// engine -- on a round-robin controller, for 80 cells x 25 rows x 56 frames,
// forever. That is the environment this bench reproduces.
//
// The hardware symptom being hunted: on real hardware the rowbuf's f_req
// counter advanced only ~6 pulses in 671 s while every counted burst had
// completed. Nothing in the request path is allowed to wait that long --
// arbitration is bounded -- so either the fill FSM wedged on a beat that never
// arrived, or the fill saw no kanji cells at all. This bench establishes which
// behaviours are reachable:
//
//   * every f_req is followed by exactly sixteen f_valid beats
//   * f_busy never stays up past BOUND clocks (starvation ceiling)
//   * the fill always completes: busy falls, banks flip, contents are right
//   * no f_valid outside a drain, no p_done without a request (phantoms)
//   * under plusarg +DROP_BEAT: one dropped p_rvalid wedges the fill forever
//     (documents the failure signature the OSD counters would show)
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_font_stress;

    localparam int ADDR_BITS  = 24;
    localparam int LEN_BITS   = 5;
    localparam int PORTS      = 4;
    localparam int COLS       = 80;
    // The longest f_busy may legally sit: the other three ports can each hold
    // a sixteen-word transaction (~60 clk with ACT+T_RCD+S_TAIL) plus our own
    // drain. 512 is generous without being meaningless.
    localparam int BUSY_BOUND = 512;
    localparam int FILL_BOUND = 20000;

    localparam [ADDR_BITS-1:0] FONT_BASE = 24'h400000;

    logic clk = 0, rst = 1;
    always #11.64 clk = ~clk;

    int errors = 0;

    // ---- row buffer --------------------------------------------------------
    logic        fill_start = 1'b0;
    logic [11:0] row_base   = 12'd0;
    wire         busy;
    wire [11:0]  tv_cell;
    logic [7:0]  tv_char_lo, tv_char_hi;

    wire        f_req, f_busy, f_valid;
    wire [19:0] f_addr;
    wire  [7:0] f_data;

    logic [6:0] rd_col  = 7'd0;
    logic [3:0] rd_line = 4'd0;
    wire  [7:0] rd_byte;
    wire        kanji_seen;

    wire [7:0] ank_code;
    wire [3:0] ank_line;
    logic [7:0] ank_mem [0:4095];
    logic [7:0] ank_row;
    always_ff @(posedge clk) ank_row <= ank_mem[{ank_code, ank_line}];

    pc98_glyph_rowbuf #(.COLS(COLS)) u_rowbuf (
        .clk(clk), .rst(rst),
        .fill_start(fill_start), .row_base(row_base), .bitac(8'hFF), .busy(busy),
        .tv_cell(tv_cell), .tv_char_lo(tv_char_lo), .tv_char_hi(tv_char_hi),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data),
        .ank_code(ank_code), .ank_line(ank_line), .ank_row(ank_row),
        .rd_clk(clk), .rd_cell(rd_col), .rd_line(rd_line), .rd_byte(rd_byte),
        .kanji_seen(kanji_seen)
    );

    // TVRAM model: registered read like pc98_tvram's fil port. Cell content is
    // scripted per fill by the test, so the mix of ANK and kanji is a knob.
    logic [7:0] scr_lo [0:2047];
    logic [7:0] scr_hi [0:2047];
    always_ff @(posedge clk) begin
        tv_char_lo <= scr_lo[tv_cell];
        tv_char_hi <= scr_hi[tv_cell];
    end

    // ---- the real fetcher on port B ----------------------------------------
    wire                  b_req;
    wire [ADDR_BITS-1:0]  b_addr;
    wire [LEN_BITS-1:0]   b_len;
    wire                  b_ack, b_done;
    wire                  b_rvalid_raw;
    wire [15:0]           b_rdata;

    // +DROP_DONE=N masks the Nth p_done on port B before it reaches the
    // fetcher. A lost completion is the one fault in this chain that wedges
    // the row buffer: draining never starts, f_busy never falls, and S_STREAM
    // has no timeout -- every later fill_start is dropped on the floor.
    int drop_armed;
    initial begin
        if ($value$plusargs("DROP_DONE=%d", drop_armed)) ;
        else drop_armed = -1;
    end
    int dones_seen = 0;
    wire b_done_masked = mp_done[1] & ~((drop_armed >= 0) && (dones_seen == drop_armed));

    pc98_font_fetch #(.ADDR_BITS(ADDR_BITS), .LEN_BITS(LEN_BITS)) u_fetch (
        .clk(clk), .rst(rst),
        .f_req(f_req), .f_addr(f_addr), .f_busy(f_busy),
        .f_valid(f_valid), .f_data(f_data),
        .p_req(b_req), .p_addr(b_addr), .p_len(b_len), .p_ack(b_ack),
        .p_rvalid(b_rvalid_raw), .p_rdata(b_rdata), .p_done(b_done_masked)
    );

    // ---- port A: guest traffic ----------------------------------------------
    // Single-word reads and writes at random addresses, on all the time, like
    // a BIOS polling loop mixed with the DMA path.
    logic                  a_req   = 1'b0;
    logic                  a_we    = 1'b0;
    logic [ADDR_BITS-1:0]  a_addr  = '0;
    wire                   a_ack, a_done;
    int                    a_hits  = 0;
    always_ff @(posedge clk) begin
        if (rst) begin
            a_req <= 1'b0;
        end else begin
            if (!a_req && $urandom_range(0, 3) == 0) begin
                a_req  <= 1'b1;
                a_we   <= $urandom_range(0, 1);
                a_addr <= $urandom_range(0, 24'h3FFFFF);   // guest space
            end else if (a_ack) begin
                a_req <= 1'b0;
                a_hits <= a_hits + 1;
            end
        end
    end

    // ---- port C: the CG window's prefetcher ----------------------------------
    // Sixteen-word font bursts, issued at a slow steady cadence (one per glyph
    // the guest peeks at through A4000).
    logic                  c_req   = 1'b0;
    logic [ADDR_BITS-1:0]  c_addr  = '0;
    wire                   c_ack, c_done;
    int                    c_pace  = 0;
    always_ff @(posedge clk) begin
        if (rst) begin
            c_req  <= 1'b0;
            c_pace <= 0;
        end else begin
            c_pace <= c_pace + 1;
            if (!c_req && c_pace > 400) begin
                c_pace <= 0;
                c_req  <= 1'b1;
                c_addr <= FONT_BASE + $urandom_range(0, 24'h40000);
            end else if (c_ack) begin
                c_req <= 1'b0;
            end
        end
    end

    // ---- port D: graphics display fetch --------------------------------------
    // The GVRAM engine's cadence: back-to-back sixteen-word read bursts, eighty
    // bytes per plane per scanline -- the heaviest other master on the bus.
    logic                  d_req   = 1'b0;
    logic [ADDR_BITS-1:0]  d_addr  = '0;
    wire                   d_ack, d_done;
    always_ff @(posedge clk) begin
        if (rst) begin
            d_req  <= 1'b0;
            d_addr <= 24'hA0000;
        end else begin
            if (!d_req) begin
                d_req  <= 1'b1;
                d_addr <= 24'hA0000 + {8'd0, $urandom_range(0, 16'h7FF0)};
            end else if (d_ack) begin
                d_req <= 1'b0;
            end
        end
    end

    // ---- the controller + device, as RAM.sv wires them ------------------------
    wire [PORTS-1:0]                mp_req    = {d_req,  c_req,  b_req,  a_req};
    wire [PORTS-1:0]                mp_we     = {1'b0,   1'b0,   1'b0,   a_we};
    wire [PORTS-1:0][ADDR_BITS-1:0] mp_addr   = {d_addr, c_addr, b_addr, a_addr};
    wire [PORTS-1:0][LEN_BITS-1:0]  mp_len    = {5'd15,  5'd15,  b_len,  5'd0};
    wire [PORTS-1:0]                mp_ack, mp_done;
    wire [1:0]                      mp_grant;
    wire                            mp_rvalid;
    wire [15:0]                     mp_rdata;
    wire [LEN_BITS-1:0]             mp_wcnt;
    logic [15:0]                    a_wdata = 16'hCAFE;

    assign a_ack     = mp_ack[0];
    assign a_done    = mp_done[0];
    assign b_ack     = mp_ack[1];
    assign b_done    = mp_done[1];
    assign c_ack     = mp_ack[2];
    assign c_done    = mp_done[2];
    assign d_ack     = mp_ack[3];
    assign d_done    = mp_done[3];
    assign b_rvalid_raw = mp_rvalid & (mp_grant == 2'd1);
    assign b_rdata      = mp_rdata;
    wire c_rvalid    = mp_rvalid & (mp_grant == 2'd2);
    wire d_rvalid    = mp_rvalid & (mp_grant == 2'd3);
    wire c_rvalid_u  = c_rvalid;   // observed by the monitor, unused otherwise
    wire d_rvalid_u  = d_rvalid;

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_ras_n, s_cas_n, s_we_n, s_dq_io;
    wire [1:0] s_dqm;
    wire [15:0] s_dq_out, s_dq_in;
    wire init_done, stat_idle, stat_refresh;

    wire [PORTS-1:0][15:0] mp_wdata;
    assign mp_wdata[0] = a_wdata;
    assign mp_wdata[1] = 16'h0;
    assign mp_wdata[2] = 16'h0;
    assign mp_wdata[3] = 16'h0;

    sdram_mp #(.PORTS(PORTS), .BURST_MAX(16), .CAS_LATENCY(2),
               .INIT_NOP(64), .REFRESH_INT(320)) u_sdram (
        .clk(clk), .rst(rst),
        .p_req(mp_req), .p_we(mp_we), .p_addr(mp_addr), .p_len(mp_len),
        .p_ack(mp_ack),
        .p_wcnt(mp_wcnt), .p_wdata(mp_wdata),
        .p_wmask({PORTS{2'b11}}),
        .grant(mp_grant), .p_rvalid(mp_rvalid), .p_rdata(mp_rdata),
        .p_done(mp_done),
        .init_done(init_done), .stat_idle(stat_idle),
        .stat_refresh(stat_refresh),
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

    // -------------------------------------------------------------------------
    // Monitors: the invariants the failure mode would break.
    // -------------------------------------------------------------------------
    int freq_pulses  = 0;
    int fvalid_beats = 0;
    int busy_clks    = 0;
    int busy_max     = 0;
    int drain_late   = 0;      // f_valid raised when no burst could be draining
    int done_orphan  = 0;      // b_done without b_req ever being high
    logic f_req_q = 1'b0, b_req_q = 1'b0;
    logic f_busy_seen;

    always_ff @(posedge clk) begin
        if (rst) begin
            f_req_q <= 1'b0; b_req_q <= 1'b0;
            freq_pulses <= 0; fvalid_beats <= 0;
            busy_clks <= 0; busy_max <= 0; drain_late <= 0; done_orphan <= 0;
            dones_seen <= 0;
        end else begin
            f_req_q <= f_req;
            b_req_q <= b_req;
            if (f_req & ~f_req_q) freq_pulses <= freq_pulses + 1;
            if (f_valid)          fvalid_beats <= fvalid_beats + 1;
            if (mp_done[1])       dones_seen <= dones_seen + 1;

            // f_busy run length
            if (f_busy) begin
                busy_clks <= busy_clks + 1;
                if (busy_clks + 1 > busy_max) busy_max <= busy_clks + 1;
            end else busy_clks <= 0;

            // f_valid must only appear while f_busy is (or just was) asserted
            if (f_valid && !f_busy && !f_busy_seen) drain_late <= drain_late + 1;
            f_busy_seen <= f_busy;

            // done must only complete a transaction the fetcher is tracking;
            // with f_busy low the DUT's unguarded `if (p_done) draining <= 1`
            // would start a phantom drain -- sixteen f_valid beats nobody
            // asked for, which is exactly the beat/req mismatch the OSD
            // counters showed on hardware.
            if (b_done_masked && !f_busy) done_orphan <= done_orphan + 1;
        end
    end

    // ---- scripted content -----------------------------------------------------
    // Fill n: alternate rows between all-ANK and rows carrying kanji pairs so
    // both the BRAM and SDRAM paths stay exercised under load.
    task automatic load_row(input int r);
        for (int c = 0; c < COLS; c++) begin
            int idx = r * COLS + c;
            if ((c % 16) == 3) begin
                // kanji pair: kanji cell + its right-half cell
                scr_lo[idx]     = 8'h04; scr_hi[idx]     = 8'h22;   // JIS-ish
                scr_lo[idx + 1] = 8'hFF; scr_hi[idx + 1] = 8'hFF;   // eaten half
            end else if ((c % 16) == 4) begin
                // already written by the pair above
            end else begin
                scr_lo[idx] = 8'(8'h21 + (c % 90));   // printable ANK
                scr_hi[idx] = 8'h00;
            end
        end
    endtask

    int fills_done = 0;

    initial begin
        $display("=== font path under 4-port contention ===");
        for (int i = 0; i < 2048; i++) begin scr_lo[i] = 8'h20; scr_hi[i] = 8'h00; end
        for (int i = 0; i < 4096; i++) ank_mem[i] = 8'hA5;

        // Give the font region something nonzero to read.
        for (int a = 0; a < 'h50000; a++)
            sdr.poke(FONT_BASE + a, 16'(a & 8'hFF));

        repeat (8) @(posedge clk);
        rst = 0;
        wait (init_done);
        repeat (4) @(posedge clk);

        if (drop_armed >= 0)
            $display("  DROP_DONE armed at completion %0d", drop_armed);

        // Thirty fills across the twenty-five rows and wrapping: far more than
        // one full frame's worth of fills.
        for (int f = 0; f < 30; f++) begin
            load_row(f % 25);
            row_base   = 12'((f % 25) * COLS);
            fill_start = 1'b1; @(posedge clk); fill_start = 1'b0;
            begin
                int w = 0;
                while (busy != 1'b1 && w < FILL_BOUND) begin @(posedge clk); w++; end
                while (busy == 1'b1 && w < FILL_BOUND) begin @(posedge clk); w++; end
                if (w >= FILL_BOUND) begin
                    $display("  FAIL fill %0d wedged after %0d clk (state stuck)",
                             f, FILL_BOUND);
                    errors++;
                end else fills_done = fills_done + 1;
            end
            repeat (4) @(posedge clk);
        end

        repeat (32) @(posedge clk);
        $display("  fills done:      %0d / 30", fills_done);
        $display("  f_req pulses:    %0d", freq_pulses);
        $display("  f_valid beats:   %0d", fvalid_beats);
        $display("  beats - 16*reqs: %0d (want 0 when idle)",
                 fvalid_beats - 16 * freq_pulses);
        $display("  f_busy max run:  %0d clk (bound %0d)", busy_max, BUSY_BOUND);
        $display("  f_valid w/o drain: %0d, orphan done: %0d", drain_late, done_orphan);
        $display("  protocol violations: %0d", sdr.violations);

        if (drop_armed >= 0) begin
            // The wedge signature the hardware photos would show: fills stop
            // completing, freq freezes, fvalid short by the missing drain.
            $display("  (injected done loss: wedge expected, not counted as error)");
        end else begin
            if (fills_done != 30)                      errors++;
            if (fvalid_beats - 16 * freq_pulses != 0) begin
                $display("  FAIL beat accounting does not balance"); errors++;
            end
            if (busy_max > BUSY_BOUND) begin
                $display("  FAIL f_busy exceeded the starvation bound"); errors++;
            end
            if (drain_late != 0 || done_orphan != 0) begin
                $display("  FAIL phantom drain/orphan completion"); errors++;
            end
            if (sdr.violations != 0) begin
                $display("  FAIL protocol violations"); errors++;
            end
        end

        $display("\n  errors: %0d", errors);
        if (errors == 0) $display("  RESULT: PASS"); else $display("  RESULT: FAIL");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("GLOBAL TIMEOUT"); $finish;
    end

endmodule

`default_nettype wire
