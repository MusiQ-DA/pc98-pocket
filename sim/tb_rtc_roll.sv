// tb_rtc_roll.sv -- equivalence bench for the pipelined RTC rollover.
// OLD: one-cycle nested cascade. NEW: registered rollover flags + flat muxes
// + two-cycle rtc_valid commit. Drives random BCD start dates through forced
// rtc_div ticks and compares rtc_time after every rollover boundary.
//
// NOTE: the OLD copy below is the intended-semantics version of the original
// code -- the actual original wrote `{rtc_mo, rtc_acc % 7}` where the unsized
// %7 is 32 bits, blowing the concat to 76 bits and truncating sec/min/hour
// (the load wrote {day_lo,mo} into the seconds field). The corrected
// reference uses {1'b0, m_mo, 3'(m_acc % 7)} so this bench compares the NEW
// pipeline against what the OLD code *meant* to do.
`timescale 1ns/1ps
module tb_rtc_roll;
    logic clk = 0;
    always #7 clk = ~clk;             // ~71 MHz, close enough for logic

    // ---------------- shared helpers (copied from core_top.sv) -----------
    function automatic [6:0] bcd2bin(input [7:0] b);
        bcd2bin = (b[7:4] * 7'd10) + {3'd0, b[3:0]};
    endfunction
    function automatic [7:0] bcd_inc(input [7:0] b);
        bcd_inc = (b[3:0] == 4'd9) ? {b[7:4] + 4'd1, 4'd0} : b + 8'd1;
    endfunction
    function automatic [4:0] days_in(input [3:0] mo, input logic leap);
        case (mo)
        4'd4, 4'd6, 4'd9, 4'd11: days_in = 5'd30;
        4'd2:                  days_in = leap ? 5'd29 : 5'd28;
        default:               days_in = 5'd31;
        endcase
    endfunction

    // ---------------- DUT pair -------------------------------------------
    logic        rtc_valid = 0;
    logic [31:0] rtc_date_bcd = 0, rtc_time_bcd = 0;
    logic        tick = 0;            // shared tick strobe (RTC_DIV factored out)

    // OLD implementation ---------------------------------------------------
    logic [47:0] t_old = 0;
    wire [3:0]  o_mo  = t_old[14:11];
    wire        o_lp  = (bcd2bin(t_old[7:0]) % 4) == 4'd0;
    wire [4:0]  o_dim = days_in(o_mo, o_lp);
    wire [3:0]  m_mo  = bcd2bin(rtc_date_bcd[15:8]);
    wire [4:0]  m_da  = bcd2bin(rtc_date_bcd[23:16]);
    wire [11:0] m_y   = 12'd2000 + {8'd0, bcd2bin(rtc_date_bcd[7:0])};
    wire [11:0] m_yy  = (m_mo < 4'd3) ? (m_y - 12'd1) : m_y;
    function automatic [2:0] sakamoto(input [3:0] mo);
        case (mo)
        4'd1: sakamoto=3'd0; 4'd2: sakamoto=3'd3; 4'd3: sakamoto=3'd2;
        4'd4: sakamoto=3'd5; 4'd5: sakamoto=3'd0; 4'd6: sakamoto=3'd3;
        4'd7: sakamoto=3'd5; 4'd8: sakamoto=3'd1; 4'd9: sakamoto=3'd4;
        4'd10: sakamoto=3'd6; 4'd11: sakamoto=3'd2; 4'd12: sakamoto=3'd4;
        default: sakamoto=3'd0;
        endcase
    endfunction
    wire [15:0] m_acc = 16'(m_da) + 16'(sakamoto(m_mo)) + 16'(m_yy)
                      + 16'(m_yy >> 2) + 16'd1 - 16'd15;
    logic        vq_old = 0;
    always_ff @(posedge clk) begin
        vq_old <= rtc_valid;
        if (rtc_valid && !vq_old) begin
            t_old <= {rtc_time_bcd[7:0], rtc_time_bcd[15:8], rtc_time_bcd[23:16],
                      rtc_date_bcd[23:16], {1'b0, m_mo, 3'(m_acc % 7)},
                      rtc_date_bcd[7:0]};
        end else if (tick) begin
            if (t_old[47:40] == 8'h59) begin
                t_old[47:40] <= 8'h00;
                if (t_old[39:32] == 8'h59) begin
                    t_old[39:32] <= 8'h00;
                    if (t_old[31:24] == 8'h23) begin
                        t_old[31:24] <= 8'h00;
                        t_old[10:8] <= (t_old[10:8] == 3'd6) ? 3'd0
                                       : t_old[10:8] + 3'd1;
                        if (bcd2bin(t_old[23:16]) == {2'd0, o_dim}) begin
                            t_old[23:16] <= 8'h01;
                            if (o_mo == 4'd12) begin
                                t_old[14:11] <= 4'd1;
                                t_old[7:0]   <= (t_old[7:0] == 8'h99)
                                                ? 8'h00 : bcd_inc(t_old[7:0]);
                            end else
                                t_old[14:11] <= o_mo + 4'd1;
                        end else
                            t_old[23:16] <= bcd_inc(t_old[23:16]);
                    end else
                        t_old[31:24] <= bcd_inc(t_old[31:24]);
                end else
                    t_old[39:32] <= bcd_inc(t_old[39:32]);
            end else
                t_old[47:40] <= bcd_inc(t_old[47:40]);
        end
    end

    // NEW implementation (pipelined) ---------------------------------------
    logic [47:0] t_new = 0;
    wire [3:0]  n_mo  = t_new[14:11];
    wire        n_lp  = (bcd2bin(t_new[7:0]) % 4) == 4'd0;
    wire [4:0]  n_dim = days_in(n_mo, n_lp);
    wire r_sec  = (t_new[47:40] == 8'h59);
    wire r_min  = r_sec  & (t_new[39:32] == 8'h59);
    wire r_hour = r_min  & (t_new[31:24] == 8'h23);
    wire r_day  = r_hour & (bcd2bin(t_new[23:16]) == {2'd0, n_dim});
    wire r_mo   = r_day  & (n_mo == 4'd12);
    reg        r_sec_q=0, r_min_q=0, r_hour_q=0, r_day_q=0, r_mo_q=0;
    reg  [7:0] sec_n=0, min_n=0, hr_n=0, day_n=0, yr_n=0;
    reg  [2:0] wd_n=0;
    reg [15:0] acc_q = 0;
    reg  [2:0] wdy_q = 0;
    reg  [1:0] pend  = 0;
    logic      vq_new = 0;
    always_ff @(posedge clk) begin
        r_sec_q <= r_sec;  r_min_q <= r_min;  r_hour_q <= r_hour;
        r_day_q <= r_day;  r_mo_q <= r_mo;
        sec_n <= bcd_inc(t_new[47:40]); min_n <= bcd_inc(t_new[39:32]);
        hr_n  <= bcd_inc(t_new[31:24]); day_n <= bcd_inc(t_new[23:16]);
        yr_n  <= (t_new[7:0] == 8'h99) ? 8'h00 : bcd_inc(t_new[7:0]);
        wd_n  <= (t_new[10:8] == 3'd6) ? 3'd0 : t_new[10:8] + 3'd1;
        acc_q <= m_acc;  wdy_q <= acc_q % 7;
    end
    always_ff @(posedge clk) begin
        vq_new <= rtc_valid;
        pend <= {pend[0], rtc_valid & ~vq_new};
        if (pend[1]) begin
            t_new <= {rtc_time_bcd[7:0], rtc_time_bcd[15:8], rtc_time_bcd[23:16],
                      rtc_date_bcd[23:16], {1'b0, m_mo, wdy_q},
                      rtc_date_bcd[7:0]};
        end else if (tick) begin
            t_new[47:40] <= r_sec_q ? 8'h00 : sec_n;
            if (r_sec_q)  t_new[39:32] <= r_min_q  ? 8'h00 : min_n;
            if (r_min_q)  t_new[31:24] <= r_hour_q ? 8'h00 : hr_n;
            if (r_hour_q) begin
                t_new[10:8]  <= wd_n;
                t_new[23:16] <= r_day_q ? 8'h01 : day_n;
            end
            if (r_day_q)  t_new[14:11] <= r_mo_q ? 4'd1 : n_mo + 4'd1;
            if (r_mo_q)   t_new[7:0]   <= yr_n;
        end
    end

    // ---------------- stimulus -------------------------------------------
    int errors = 0, ticks_done = 0;
    task check();
        if (t_old !== t_new) begin
            errors++;
            $display("MISMATCH @tick %0d: old=%h new=%h", ticks_done, t_old, t_new);
        end
    endtask

    // random valid-ish BCD date/time
    function automatic [31:0] rand_date();
        int mo, da, yr;
        mo = 1 + ($urandom % 12);
        da = 1 + ($urandom % 28);
        yr = $urandom % 100;
        // layout: day@[23:16], month@[15:8], year@[7:0] (top byte unused)
        rand_date = {8'h00, 8'(da/10*16 + da%10), 8'(mo/10*16 + mo%10),
                     8'(yr/10*16 + yr%10)};
    endfunction
    function automatic [31:0] rand_time();
        int h, m, s;
        h = $urandom % 24; m = $urandom % 60; s = $urandom % 60;
        // bias toward rollover boundaries
        if ($urandom % 3 == 0) s = 58 + ($urandom % 2);
        if ($urandom % 4 == 0) m = 59;
        if ($urandom % 8 == 0) h = 23;
        rand_time = {8'h00, 8'(h/10*16 + h%10), 8'(m/10*16 + m%10),
                     8'(s/10*16 + s%10)};
    endfunction

    initial begin
        int nticks, dim;
        // ---- random ticks with occasional rollovers ----------------------
        // ---- sanity: one fixed-value load first -------------------------
        rtc_date_bcd = 32'h00_05_05_66;   // day=05 mo=05 yr=66
        rtc_time_bcd = 32'h00_04_59_40;   // hh=04 mm=59 ss=40
        rtc_valid = 1;
        repeat (6) @(posedge clk);
        rtc_valid = 0;
        repeat (2) @(posedge clk);
        $display("fixed load: old=%h new=%h (want 405904055c66-ish)",
                 t_old, t_new);

        // ---- random ticks with occasional rollovers ----------------------
        for (int it = 0; it < 200; it++) begin
            // load both DUTs identically (bypasses the pend difference:
            // drive load, wait past the 2-cycle commit, then start ticking)
            rtc_date_bcd = rand_date();
            rtc_time_bcd = rand_time();
            if (it == 0)
                $display("drive date=%h time=%h valid->1", rtc_date_bcd, rtc_time_bcd);
            rtc_valid = 1;
            repeat (4) begin
                @(posedge clk);
                if (it == 0)
                    $display("  t_old=%h t_new=%h pend=%b", t_old, t_new, pend);
            end
            rtc_valid = 0;
            repeat (2) @(posedge clk);
            if (it < 4 && (t_old !== t_new))
                $display("load diff it%0d: date=%h time=%h old=%h new=%h",
                         it, rtc_date_bcd, rtc_time_bcd, t_old, t_new);
            nticks = 1 + ($urandom % 8);
            for (int t = 0; t < nticks; t++) begin
                tick = 1; @(posedge clk); tick = 0; @(posedge clk);
                ticks_done++;
                // new impl may lag one cycle only on the *load* commit; after
                // loads both are settled before ticks start. Compare now.
                check();
            end
        end

        // ---- directed: every month-end + year-end -------------------------
        for (int mo = 1; mo <= 12; mo++) begin
            for (int yr = 0; yr < 4; yr++) begin
                // last day of month, 23:59:59, weekday 0
                dim = (mo==4||mo==6||mo==9||mo==11) ? 30
                    : (mo==2 ? ((yr%4==0) ? 29 : 28) : 31);
                rtc_date_bcd = {8'h00, 8'(dim/10*16+dim%10),
                                8'(mo/10*16+mo%10), 8'(yr/10*16+yr%10)};
                rtc_time_bcd = {8'h00, 8'h23, 8'h59, 8'h59};
                rtc_valid = 1; repeat (4) @(posedge clk); rtc_valid = 0;
                repeat (2) @(posedge clk);
                tick = 1; @(posedge clk); tick = 0; @(posedge clk);
                ticks_done++; check();
                tick = 1; @(posedge clk); tick = 0; @(posedge clk);
                ticks_done++; check();
            end
        end

        // sync-load check: does {mo,wday} match old after commit settles?
        $display("ticks compared: %0d   errors: %0d", ticks_done, errors);
        if (errors == 0) $display("=== PASS ===");
        else             $display("=== FAIL (%0d) ===", errors);
        $finish;
    end
endmodule
