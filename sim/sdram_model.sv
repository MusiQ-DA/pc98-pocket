//
// sdram_model — behavioural SDR SDRAM for simulating sdram_mp.
//
// Models enough of a 4-bank part to catch protocol mistakes: it tracks the open
// row per bank, enforces tRCD/tRP/tWR/tRFC, honours the programmed CAS latency,
// applies DQM byte masking on writes, and reports a violation rather than
// silently returning plausible data. Storage is an associative array so a 32 MB
// part costs only what the test actually touches.
//
// CS is not modelled: the Pocket does not route dram_cs, so the controller
// drives commands on RAS/CAS/WE with CS permanently asserted.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module sdram_model #(
    parameter int ROW_BITS  = 13,
    parameter int COL_BITS  = 9,
    parameter int BANK_BITS = 2,
    parameter int DQ_BITS   = 16,
    parameter int T_RCD     = 2,
    parameter int T_RP      = 2,
    parameter int T_WR      = 2,
    parameter int T_RFC     = 7,
    parameter int T_RAS     = 2,      // ACTIVATE -> PRECHARGE, same bank
    parameter int T_RC      = 3,      // ACTIVATE -> ACTIVATE, same bank
    parameter int T_REF     = 0,      // cycles a row may go unrefreshed (0 = off)
    parameter bit CHECK     = 1
) (
    input  wire                   clk,
    input  wire [ROW_BITS-1:0]    a,
    input  wire [BANK_BITS-1:0]   ba,
    input  wire                   cke,
    input  wire                   ras_n,
    input  wire                   cas_n,
    input  wire                   we_n,
    input  wire [DQ_BITS/8-1:0]   dqm,
    input  wire [DQ_BITS-1:0]     dq_out,   // driven by the controller
    input  wire                   dq_io,    // active low: controller is driving
    output logic [DQ_BITS-1:0]    dq_in     // driven to the controller
);

    localparam int BANKS     = 1 << BANK_BITS;
    localparam int MASK_BITS = DQ_BITS/8;

    logic [15:0] store [int];             // sparse; key is the flat word address

    int  open_row  [BANKS];               // -1 when the bank is precharged
    int  act_at    [BANKS];               // cycle the row was activated
    int  pre_at    [BANKS];               // cycle the bank was precharged
    int  wr_at     [BANKS];               // cycle of the last write datum
    int  ref_at;
    int  ref_count;                       // AUTO REFRESH commands seen
    int  last_ref_cyc;                    // when the refresh burst last advanced
    int  cyc;
    int  cas_lat;
    int  violations;
    int  reads_served;
    int  writes_served;

    // Read return pipeline: depth covers the largest CAS latency we program.
    localparam int PIPE = 6;
    logic [DQ_BITS-1:0] rd_data [PIPE];
    logic               rd_vld  [PIPE];

    function automatic int flat(input int bank, input int row, input int col);
        flat = (row << (BANK_BITS + COL_BITS)) | (bank << COL_BITS) | col;
    endfunction

    task automatic complain(input string what);
        if (CHECK) begin
            if (violations < 8)
                $display("[%0t] SDRAM VIOLATION: %s", $time, what);
            violations++;
        end
    endtask

    initial begin
        for (int b = 0; b < BANKS; b++) begin
            open_row[b] = -1;
            act_at[b]   = -1000;
            pre_at[b]   = -1000;
            wr_at[b]    = -1000;
        end
        ref_at        = -1000;
        ref_count     = 0;
        last_ref_cyc  = 0;
        cyc           = 0;
        cas_lat       = 3;
        violations    = 0;
        reads_served  = 0;
        writes_served = 0;
        for (int i = 0; i < PIPE; i++) rd_vld[i] = 1'b0;
    end

    wire [2:0] cmd = {ras_n, cas_n, we_n};

    always_ff @(posedge clk) begin
        cyc <= cyc + 1;

        // Advance the read return pipeline.
        for (int i = PIPE-1; i > 0; i--) begin
            rd_data[i] <= rd_data[i-1];
            rd_vld[i]  <= rd_vld[i-1];
        end
        rd_vld[0]  <= 1'b0;
        rd_data[0] <= 'x;

        if (cke) begin
            case (cmd)
            3'b000: begin // MODE REGISTER SET
                cas_lat = int'(a[6:4]);
                for (int b = 0; b < BANKS; b++)
                    if (open_row[b] != -1) complain("MRS while a row is open");
                $display("[%0t] SDRAM: mode register set, CAS latency %0d, A=%h",
                         $time, cas_lat, a);
            end

            3'b001: begin // AUTO REFRESH
                for (int b = 0; b < BANKS; b++)
                    if (open_row[b] != -1) complain("AUTO REFRESH with a row open");
                ref_at = cyc;
                // A part with 8192 rows needs one AUTO REFRESH every tREF/8192.
                // Model decay indirectly: complain if the gap ever exceeds it.
                if (T_REF != 0 && ref_count != 0 && (cyc - last_ref_cyc) > T_REF)
                    complain($sformatf("refresh interval exceeded: %0d cycles (max %0d)",
                                       cyc - last_ref_cyc, T_REF));
                last_ref_cyc = cyc;
                ref_count++;
            end

            3'b010: begin // PRECHARGE
                if (a[10]) begin
                    for (int b = 0; b < BANKS; b++) begin
                        open_row[b] = -1;
                        pre_at[b]   = cyc;
                    end
                end else begin
                    if (cyc - wr_at[ba] < T_WR)
                        complain($sformatf("tWR violated on bank %0d", ba));
                    if (open_row[ba] != -1 && cyc - act_at[ba] < T_RAS)
                        complain($sformatf("tRAS violated on bank %0d", ba));
                    open_row[ba] = -1;
                    pre_at[ba]   = cyc;
                end
            end

            3'b011: begin // ACTIVATE
                if (open_row[ba] != -1)
                    complain($sformatf("ACTIVATE on bank %0d with row %0d already open",
                                       ba, open_row[ba]));
                if (cyc - pre_at[ba] < T_RP)
                    complain($sformatf("tRP violated on bank %0d", ba));
                if (cyc - act_at[ba] < T_RC)
                    complain($sformatf("tRC violated on bank %0d", ba));
                if (cyc - ref_at < T_RFC)
                    complain("tRFC violated: ACTIVATE too soon after AUTO REFRESH");
                open_row[ba] = int'(a);
                act_at[ba]   = cyc;
            end

            3'b101: begin // READ
                if (open_row[ba] == -1)
                    complain($sformatf("READ on bank %0d with no row open", ba));
                else if (cyc - act_at[ba] < T_RCD)
                    complain($sformatf("tRCD violated on bank %0d", ba));
                else begin
                    automatic int addr = flat(int'(ba), open_row[ba], int'(a[COL_BITS-1:0]));
                    rd_data[0] <= store.exists(addr) ? store[addr] : 16'hDEAD;
                    rd_vld[0]  <= 1'b1;
                    reads_served++;
                end
                if (a[10]) complain("auto-precharge READ is not modelled");
            end

            3'b100: begin // WRITE
                if (open_row[ba] == -1)
                    complain($sformatf("WRITE on bank %0d with no row open", ba));
                else if (cyc - act_at[ba] < T_RCD)
                    complain($sformatf("tRCD violated on bank %0d", ba));
                else if (dq_io)
                    complain("WRITE issued but the controller is not driving DQ");
                else begin
                    automatic int addr = flat(int'(ba), open_row[ba], int'(a[COL_BITS-1:0]));
                    automatic logic [DQ_BITS-1:0] cur =
                        store.exists(addr) ? store[addr] : 16'h0000;
                    for (int byt = 0; byt < MASK_BITS; byt++)
                        if (!dqm[byt]) cur[byt*8 +: 8] = dq_out[byt*8 +: 8];
                    store[addr] = cur;
                    wr_at[ba] = cyc;
                    writes_served++;
                end
                if (a[10]) complain("auto-precharge WRITE is not modelled");
            end

            default: ; // NOP / command inhibit
            endcase
        end
    end

    // The part drives DQ cas_lat cycles after the READ command. Real DQ is valid
    // around the sampling edge rather than for one tidy cycle, and controllers
    // differ by a cycle in where they latch it (KFSDRAM registers dq_in
    // unconditionally and gates with its own flag), so the window spans two
    // cycles. A one-cycle window made this model reject KFSDRAM, which is known
    // good on hardware -- i.e. the model was wrong, not the controller.
    always_comb begin
        if      (rd_vld[cas_lat])                       dq_in = rd_data[cas_lat];
        else if (cas_lat+1 < PIPE && rd_vld[cas_lat+1]) dq_in = rd_data[cas_lat+1];
        else                                            dq_in = 16'hZZZZ;
    end

    // Test hooks.
    function automatic void poke(input int addr, input logic [15:0] value);
        store[addr] = value;
    endfunction
    function automatic logic [15:0] peek(input int addr);
        peek = store.exists(addr) ? store[addr] : 16'h0000;
    endfunction

endmodule

`default_nettype wire
