// tb_pc98_jtag_trig -- the write-watchpoint's JTAG arming path end to end:
// probe scan -> write latch -> clk_chipset CDC -> slot-0x06 trigger word ->
// readback at slot 0x06 -> bus/port-F tap hit -> frozen.
//
// Pins the trap that ate the arming on hardware: pc98_jtag_probe.sv only
// treats a scan as a WRITE when the address byte has bit 7 set (0x86 arms
// slot 6, 0x8e sets the tlog mode).  The freeze script sent bare slot
// numbers -- pure reads -- so the trigger sat disarmed while the positive
// control wrote away and nothing ever fired.  The CDC, decode, readback and
// tap compare below mirror core_top's (probe write slot 0x06, the trig_*
// always_ff, read slots 0x06/0x0e and the trig_w_* compares); keep the
// shapes in sync when core_top's move.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

package tb_jtag_trig_drv;
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
    assign tck                 = tb_jtag_trig_drv::tck;
    assign tdi                 = tb_jtag_trig_drv::tdi;
    assign ir_in               = {sld_ir_width{1'b0}};
    assign virtual_state_cdr   = tb_jtag_trig_drv::cdr;
    assign virtual_state_sdr   = tb_jtag_trig_drv::sdr;
    assign virtual_state_e1dr  = 1'b0;
    assign virtual_state_pdr   = 1'b0;
    assign virtual_state_e2dr  = 1'b0;
    assign virtual_state_udr   = tb_jtag_trig_drv::udr;
    assign virtual_state_cir   = 1'b0;
    assign virtual_state_uir   = 1'b0;
    assign tms                 = 1'b0;
    assign jtag_state_tlr      = 1'b0;
    assign jtag_state_rti      = 1'b0;
    assign jtag_state_sdrs     = 1'b0;
    assign jtag_state_cdr      = 1'b0;
    assign jtag_state_sdr      = 1'b0;
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

module tb_pc98_jtag_trig;

    localparam real CLK_MHZ = 42.954545;
    localparam HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0;
    always #(HALF_NS) clock = ~clock;

    logic reset = 1;
    int   errors = 0;

    // ---- probe -------------------------------------------------------------
    wire [7:0]  probe_addr;
    wire [31:0] probe_data;
    wire        wr_tog;
    wire [6:0]  wr_addr;
    wire [31:0] wr_data;

    pc98_jtag_probe u_probe (
        .probe_addr_sel (probe_addr),
        .probe_data     (probe_data),
        .wr_tog         (wr_tog),
        .wr_addr        (wr_addr),
        .wr_data        (wr_data),
        .rd_adv         (),
        .rd_adv_gv      ()
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

    // ---- the slot-0x06 trigger word (mirrors core_top's decode) ------------
    reg [19:0] trig_addr   = 20'hFFFF0;
    reg        trig_en     = 1'b1;
    reg        trig_freeze = 1'b0;
    reg        trig_delay  = 1'b0;
    reg        trig_bus    = 1'b0;
    reg        trig_wronly = 1'b0;
    reg        trig_ds     = 1'b0;
    always_ff @(posedge clock) begin
        if (wr_pulse && wr_addr_c == 7'h06) begin
            trig_addr   <= wr_data_c[19:0];
            trig_en     <= wr_data_c[31];
            trig_freeze <= wr_data_c[30];
            trig_delay  <= wr_data_c[29];
            trig_bus    <= wr_data_c[28];
            trig_wronly <= wr_data_c[27];
            trig_ds     <= wr_data_c[26];
        end
    end

    // tlog mode word (slot 0x0e) and the hit bookkeeping: the entry ring
    // itself is core_top's, the count and the freeze flag are what the
    // freeze script polls (read slot 0x67).
    reg  [5:0]  tlog_ri = 6'd0;
    reg         tlog_all = 1'b0, tlog_trap = 1'b0, tlog_frozen = 1'b0;
    reg  [15:0] tlog_n = 16'd0;
    reg         trig_hit_d = 1'b0;

    // Bus/port-F tap stimulus (driven below, compared as core_top does).
    reg         chipset_memory_write_n = 1'b1;
    reg  [19:0] chipset_address = 20'd0;
    reg         cpu_word_access = 1'b0;
    reg         chipset_aen = 1'b0;
    reg         z86_pf_wr_v = 1'b0;
    reg         z86_pf_wr_two = 1'b0;
    reg  [19:0] z86_pf_wr_a0 = 20'd0;

    wire        bus_mem_wr  = ~chipset_memory_write_n;
    wire        bus_wr_word = bus_mem_wr && cpu_word_access && ~chipset_aen;
    wire        trig_w_bus = bus_mem_wr &&
                             ((chipset_address[19:0] == trig_addr) ||
                              (bus_wr_word &&
                               (chipset_address[19:0] + 20'd1) == trig_addr));
    wire        trig_w_pf  = z86_pf_wr_v &&
                             ((z86_pf_wr_a0 == trig_addr) ||
                              (z86_pf_wr_two &&
                               (z86_pf_wr_a0 + 20'd1) == trig_addr));
    wire        trig_w_hit = trig_bus && trig_wronly && (trig_w_bus || trig_w_pf);
    // (the PC/DS compare branches of core_top's trig_hit are omitted here;
    // this bench only arms the bus+wronly write-watch mode)
    wire        trig_hit   = trig_en && (trig_bus && trig_wronly ? trig_w_hit
                                                                 : 1'b0);
    wire        tlog_ev    = tlog_all ? 1'b0 : (trig_hit && !trig_hit_d);
    always_ff @(posedge clock) begin
        trig_hit_d <= trig_hit;
        if (wr_pulse && wr_addr_c == 7'h06) begin
            tlog_n     <= 16'd0;
            tlog_frozen <= 1'b0;
        end else if (tlog_ev && !tlog_frozen)
            tlog_n <= tlog_n + 16'd1;
        if ((trig_hit && trig_freeze && !trig_delay) && !tlog_frozen)
            tlog_frozen <= 1'b1;
        if (wr_pulse && wr_addr_c == 7'h0e) begin
            tlog_ri   <= wr_data_c[5:0];
            tlog_all  <= wr_data_c[8];
            tlog_trap <= wr_data_c[9];
        end
    end

    // Readback: the new core_top read slots, same layout as the writes.
    wire [31:0] rd_trig = {trig_en, trig_freeze, trig_delay,
                           trig_bus, trig_wronly, trig_ds, 6'b0, trig_addr};
    wire [31:0] rd_tmode = {22'b0, tlog_trap, tlog_all, 2'b0, tlog_ri};

    // ---- JTAG scan primitive (as in tb_pc98_jtag_key) ------------------------
    task automatic vj_scan(input logic [39:0] val);
        begin
            tb_jtag_trig_drv::cdr = 1'b1; #2;
            tb_jtag_trig_drv::tck = 1'b1; #2; tb_jtag_trig_drv::tck = 1'b0; #2;
            tb_jtag_trig_drv::cdr = 1'b0;
            for (int i = 0; i < 40; i++) begin
                tb_jtag_trig_drv::tdi = val[i];
                tb_jtag_trig_drv::sdr = 1'b1; #2;
                tb_jtag_trig_drv::tck = 1'b1; #2; tb_jtag_trig_drv::tck = 1'b0; #2;
            end
            tb_jtag_trig_drv::sdr = 1'b0;
            tb_jtag_trig_drv::udr = 1'b1; #2;
            tb_jtag_trig_drv::tck = 1'b1; #2; tb_jtag_trig_drv::tck = 1'b0; #2;
            tb_jtag_trig_drv::udr = 1'b0; #2;
        end
    endtask

    task automatic expect32(input logic [31:0] got, input logic [31:0] want,
                            input string what);
        if (got !== want) begin
            errors = errors + 1;
            $display("FAIL: %s: got %08X want %08X", what, got, want);
        end
    endtask

    logic tog_seen;

    initial begin
        repeat (8) @(negedge clock);
        reset = 0;
        repeat (8) @(negedge clock);

        // ---- 1: a BARE 0x06 scan is a read, never an arm -------------------
        tog_seen = wr_tog;
        vj_scan({8'h06, 32'hD803_6BAE});       // bit 7 clear: read slot 6
        repeat (8) @(negedge clock);
        if (wr_tog !== tog_seen) begin
            errors = errors + 1;
            $display("FAIL: bare 0x06 scan toggled a write");
        end
        expect32(rd_trig, {1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                           6'b0, 20'hFFFF0}, "default trigger word intact");
        expect32({tlog_frozen, 15'h0, tlog_n}, 32'h0,
                 "nothing logged from a read scan");

        // ---- 2: 0x86 arms the write watchpoint ----------------------------
        vj_scan({8'h86, 32'hD803_6BAE});       // en|freeze|bus|wronly @36BAE
        repeat (8) @(negedge clock);
        expect32(rd_trig, 32'hD803_6BAE, "armed trigger word");
        if (trig_hit !== 1'b0) begin           // no write to 36BAE yet
            errors = errors + 1;
            $display("FAIL: trigger hit with no watched write");
        end

        // ---- 3: a port-F tap store (cached CPU store) fires and freezes ---
        @(negedge clock);
        z86_pf_wr_v = 1'b1; z86_pf_wr_two = 1'b0; z86_pf_wr_a0 = 20'h36BAE;
        @(negedge clock);
        z86_pf_wr_v = 1'b0;
        repeat (4) @(negedge clock);
        if (tlog_frozen !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: port-F store at the watched addr did not freeze");
        end
        if (tlog_n !== 16'd1) begin
            errors = errors + 1;
            $display("FAIL: hit count %0d, want 1", tlog_n);
        end

        // ---- 4: re-arm clears; an odd byte of a word store still hits -----
        vj_scan({8'h86, 32'hD803_73A2});       // watch the odd byte 0x373A3
        repeat (8) @(negedge clock);
        if (tlog_frozen !== 1'b0 || tlog_n !== 16'd0) begin
            errors = errors + 1;
            $display("FAIL: slot-0x06 write did not re-arm the log");
        end
        // the second lane of a word write: base 0x373A2, two bytes
        @(negedge clock);
        z86_pf_wr_v = 1'b1; z86_pf_wr_two = 1'b1; z86_pf_wr_a0 = 20'h373A2;
        @(negedge clock);
        z86_pf_wr_v = 1'b0;
        repeat (4) @(negedge clock);
        if (tlog_frozen !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: word store's odd byte at 0x373A3 did not hit");
        end

        // ---- 5: the chipset-bus tap (uncached store / DMA fill) -----------
        vj_scan({8'h86, 32'hD803_73A3});
        repeat (8) @(negedge clock);
        @(negedge clock);
        chipset_memory_write_n = 1'b0; chipset_address = 20'h373A3;
        repeat (3) @(negedge clock);           // strobe is a level on purpose
        chipset_memory_write_n = 1'b1;
        repeat (4) @(negedge clock);
        if (tlog_frozen !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: chipset-bus write at the watched addr did not hit");
        end
        if (tlog_n !== 16'd1) begin
            errors = errors + 1;
            $display("FAIL: level strobe logged %0d hits, want 1", tlog_n);
        end

        // ---- 6: bare 0x0e is a read; 0x8e sets the tlog mode --------------
        vj_scan({8'h0e, 32'h0000_0100});       // bit 7 clear: read slot 0x0e
        repeat (8) @(negedge clock);
        if (tlog_all !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: bare 0x0e scan set tlog_all");
        end
        vj_scan({8'h8e, 32'h0000_0100});       // tlog=all, index 0
        repeat (8) @(negedge clock);
        expect32(rd_tmode, 32'h0000_0100, "tlog mode word");

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire
