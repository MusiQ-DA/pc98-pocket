// tb_pc98_jtag_key -- JTAG write path end to end: probe scan -> write latch
// -> clk_chipset CDC -> merged key event -> 8251 receive register.
//
// The virtual-JTAG megafunction is replaced by a package-driven stub: the
// bench wiggles tb_jtag_drv::* exactly the way the SLD hub would wiggle the
// real block's pins (capture, 40 shifts with TDI at bit 39, update).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

package tb_jtag_drv;
    logic tck = 0, tdi = 0, cdr = 0, sdr = 0, udr = 0;
endpackage

module sld_virtual_jtag_basic #(
    parameter sld_mfg_id = 0,
    parameter sld_type_id = 0,
    parameter sld_version = 0,
    parameter sld_instance_index = 0,
    parameter sld_auto_instance_index = "NO",
    parameter sld_ir_width = 1,
    parameter sld_sim_n_scan = 0,
    parameter sld_sim_action = "UNUSED",
    parameter sld_sim_total_length = 0,
    parameter lpm_type = "sld_virtual_jtag_basic",
    parameter lpm_hint = "UNUSED"
) (
    output tck,
    output tdi,
    output [sld_ir_width-1:0] ir_in,
    input  tdo,
    input  [sld_ir_width-1:0] ir_out,
    output virtual_state_cdr,
    output virtual_state_sdr,
    output virtual_state_e1dr,
    output virtual_state_pdr,
    output virtual_state_e2dr,
    output virtual_state_udr,
    output virtual_state_cir,
    output virtual_state_uir,
    output tms,
    output jtag_state_tlr,
    output jtag_state_rti,
    output jtag_state_sdrs,
    output jtag_state_cdr,
    output jtag_state_sdr,
    output jtag_state_e1dr,
    output jtag_state_pdr,
    output jtag_state_e2dr,
    output jtag_state_udr,
    output jtag_state_sirs,
    output jtag_state_cir,
    output jtag_state_sir,
    output jtag_state_e1ir,
    output jtag_state_pir,
    output jtag_state_e2ir,
    output jtag_state_uir
);
    assign tck                 = tb_jtag_drv::tck;
    assign tdi                 = tb_jtag_drv::tdi;
    assign ir_in               = {sld_ir_width{1'b0}};
    assign virtual_state_cdr   = tb_jtag_drv::cdr;
    assign virtual_state_sdr   = tb_jtag_drv::sdr;
    assign virtual_state_e1dr  = 1'b0;
    assign virtual_state_pdr   = 1'b0;
    assign virtual_state_e2dr  = 1'b0;
    assign virtual_state_udr   = tb_jtag_drv::udr;
    assign virtual_state_cir   = 1'b0;
    assign virtual_state_uir   = 1'b0;
    assign tms                 = 1'b0;
    assign jtag_state_tlr      = 1'b0;
    assign jtag_state_rti      = 1'b0;
    assign jtag_state_sdrs     = 1'b0;
    assign jtag_state_cdr      = 1'b0;
    assign jtag_state_sdr      = 1'b0;
    assign jtag_state_e1dr     = 1'b0;
    assign jtag_state_pdr      = 1'b0;
    assign jtag_state_e2dr     = 1'b0;
    assign jtag_state_udr      = 1'b0;
    assign jtag_state_sirs     = 1'b0;
    assign jtag_state_cir      = 1'b0;
    assign jtag_state_sir      = 1'b0;
    assign jtag_state_e1ir     = 1'b0;
    assign jtag_state_pir      = 1'b0;
    assign jtag_state_e2ir     = 1'b0;
    assign jtag_state_uir      = 1'b0;
endmodule

module tb_pc98_jtag_key;

    localparam real CLK_MHZ = 42.954545;
    localparam HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0;
    always #(HALF_NS) clock = ~clock;

    logic reset = 1;
    int   errors = 0;

    // ---- probe -------------------------------------------------------------
    wire [7:0]  probe_addr;
    reg  [31:0] probe_data = 32'hCAFEF00D;
    wire        wr_tog;
    wire [6:0]  wr_addr;
    wire [31:0] wr_data;
    wire        rd_adv;

    pc98_jtag_probe u_probe (
        .probe_addr_sel (probe_addr),
        .probe_data     (probe_data),
        .wr_tog         (wr_tog),
        .wr_addr        (wr_addr),
        .wr_data        (wr_data),
        .rd_adv         (rd_adv)
    );

    // The same CDC shape core_top uses: wr_tog from the tck domain becomes a
    // one-clock wr_pulse with the payload captured beside it.
    logic [2:0]  jw_sync = 3'd0;
    logic        wr_pulse;
    logic [6:0]  wr_addr_c;
    logic [31:0] wr_data_c;
    always_ff @(posedge clock) begin
        jw_sync  <= {jw_sync[1:0], wr_tog};
        wr_pulse <= jw_sync[2] != jw_sync[1];
        if (jw_sync[2] != jw_sync[1]) begin
            wr_addr_c <= wr_addr;
            wr_data_c <= wr_data;
        end
    end

    // ---- inject + physical source -------------------------------------------
    reg        kbd_stb  = 0;
    reg        kbd_make = 0;
    reg  [7:0] kbd_code = 8'h00;
    wire       key_stb, key_make;
    wire [7:0] key_code;

    pc98_key_inject u_inject (
        .clk      (clock),
        .wr_pulse (wr_pulse),
        .wr_addr  (wr_addr_c),
        .wr_data  (wr_data_c),
        .kbd_stb  (kbd_stb),
        .kbd_make (kbd_make),
        .kbd_code (kbd_code),
        .key_stb  (key_stb),
        .key_make (key_make),
        .key_code (key_code)
    );

    // ---- 8251 drain ----------------------------------------------------------
    logic       stat_rd = 0, data_rd = 0;
    wire        read_select, irq;
    wire [7:0]  read_data;

    pc98_kbd8251 u_8251 (
        .clock              (clock),
        .reset              (reset),
        .ctrl_write_strobe  (1'b0),
        .data_read_strobe   (data_rd),
        .stat_read_strobe   (stat_rd),
        .data_in            (8'h00),
        .key_stb            (key_stb),
        .key_byte           (key_code),
        .read_select        (read_select),
        .read_data          (read_data),
        .irq                (irq)
    );

    // ---- JTAG scan primitive --------------------------------------------------
    // Real timing: TDI is set before each rising tck edge; capture first,
    // then 40 shifts (bit i of val lands at shreg[i]), then update.
    task automatic vj_scan(input logic [39:0] val);
        begin
            tb_jtag_drv::cdr = 1'b1; #2;
            tb_jtag_drv::tck = 1'b1; #2; tb_jtag_drv::tck = 1'b0; #2;
            tb_jtag_drv::cdr = 1'b0;
            for (int i = 0; i < 40; i++) begin
                tb_jtag_drv::tdi = val[i];
                tb_jtag_drv::sdr = 1'b1; #2;
                tb_jtag_drv::tck = 1'b1; #2; tb_jtag_drv::tck = 1'b0; #2;
            end
            tb_jtag_drv::sdr = 1'b0;
            tb_jtag_drv::udr = 1'b1; #2;
            tb_jtag_drv::tck = 1'b1; #2; tb_jtag_drv::tck = 1'b0; #2;
            tb_jtag_drv::udr = 1'b0; #2;
        end
    endtask

    task automatic wr(input logic [6:0] a, input logic [31:0] d);
        vj_scan({1'b1, a, d});
    endtask

    task automatic rd43(output logic [7:0] b);
        begin
            @(negedge clock);
            stat_rd = 1'b1;
            @(negedge clock);
            b = read_data;
            repeat (2) @(negedge clock);
            stat_rd = 1'b0;
            @(negedge clock);
        end
    endtask

    task automatic rd41(output logic [7:0] b);
        begin
            @(negedge clock);
            data_rd = 1'b1;
            @(negedge clock);
            b = read_data;
            repeat (2) @(negedge clock);
            data_rd = 1'b0;
            @(negedge clock);
        end
    endtask

    task automatic expect_eq(input logic [7:0] got, input logic [7:0] want,
                             input string what);
        if (got !== want) begin
            errors = errors + 1;
            $display("FAIL: %s: got %02X want %02X", what, got, want);
        end
    endtask

    task automatic expect1(input logic got, input string what);
        if (got !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: %s", what);
        end
    endtask

    logic [7:0] b;
    logic       stb_seen;
    logic       adv_seen;

    initial begin
        repeat (8) @(negedge clock);
        reset = 0;
        repeat (8) @(negedge clock);

        // ---- 1: a write scan latches addr+data and toggles once -------------
        stb_seen = key_stb;
        wr(7'h01, 32'h0000_001D);            // 'A' make through slot 0x81
        expect_eq(wr_addr, 7'h01, "write addr latched");
        expect_eq(wr_data[7:0], 8'h1D, "write data latched");
        repeat (8) @(negedge clock);         // let the CDC toggle land
        if (key_stb === stb_seen) begin
            errors = errors + 1;
            $display("FAIL: injected write did not toggle key_stb");
        end
        expect1(key_make, "make flag for 0x1D");
        expect_eq(key_code, 8'h1D, "injected code");

        // ---- 2: the byte lands in the 8251 ----------------------------------
        rd43(b); expect_eq(b, 8'h87, "status after injected make");
        rd41(b); expect_eq(b, 8'h1D, "injected make byte at 0x41");

        // ---- 3: injected break ----------------------------------------------
        wr(7'h01, 32'h0000_009D);            // 'A' break
        repeat (8) @(negedge clock);
        if (key_make !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: injected break still reads as make");
        end
        rd41(b); expect_eq(b, 8'h9D, "injected break byte at 0x41");

        // ---- 4: physical event steals the code lines back -------------------
        kbd_code = 8'h34; kbd_make = 1'b1;   // SPACE make on the real path
        @(negedge clock);
        kbd_stb  = ~kbd_stb;
        repeat (6) @(negedge clock);
        expect1(key_make, "physical make flag");
        expect_eq(key_code, 8'h34, "physical code after mux steal");
        rd41(b); expect_eq(b, 8'h34, "physical byte at 0x41");

        // ---- 5: back-to-back injected events keep order ---------------------
        wr(7'h01, 32'h0000_0026);            // '3' make
        repeat (8) @(negedge clock);
        wr(7'h01, 32'h0000_00A6);            // '3' break
        repeat (8) @(negedge clock);
        rd41(b); expect_eq(b, 8'h26, "queued make");
        rd41(b); expect_eq(b, 8'hA6, "queued break");

        // ---- 6: plain read scans never trigger a write ----------------------
        stb_seen = key_stb;
        vj_scan({8'hFF, 32'h0});             // magic read: 0xFF is exempt
        expect_eq(probe_addr, 8'hFF, "read still sets probe address");
        vj_scan(40'h0);                      // dummy second scan, like rd()
        repeat (8) @(negedge clock);
        if (key_stb !== stb_seen) begin
            errors = errors + 1;
            $display("FAIL: read scan leaked a key event");
        end

        // ---- 7: write to an unrelated slot does not inject a key ------------
        stb_seen = key_stb;
        wr(7'h02, 32'hDEAD_BEEF);
        repeat (8) @(negedge clock);
        if (key_stb !== stb_seen) begin
            errors = errors + 1;
            $display("FAIL: write to slot 2 leaked a key event");
        end

        // ---- 8: a completed read of 0x1B toggles the auto-advance -----------
        // rd_adv fires on any update-DR that retires while addr_q is 0x1B --
        // i.e. once per delivered cell-read scan. Priming does not fire;
        // moving to another slot costs exactly one extra step.
        adv_seen = rd_adv;
        vj_scan({8'h1B, 32'h0});            // primes addr_q=0x1B, no advance yet
        if (rd_adv !== adv_seen) begin
            errors = errors + 1;
            $display("FAIL: priming 0x1B fired rd_adv early");
        end
        vj_scan({8'h1B, 32'h0});            // this scan read 0x1B -> advance
        if (rd_adv === adv_seen) begin
            errors = errors + 1;
            $display("FAIL: reading 0x1B did not toggle rd_adv");
        end
        vj_scan(40'h0);                     // leaving 0x1B: one last step
        adv_seen = rd_adv;
        vj_scan(40'h0);                     // now on slot 0 -> no advance
        if (rd_adv !== adv_seen) begin
            errors = errors + 1;
            $display("FAIL: rd_adv kept firing after leaving 0x1B");
        end

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
