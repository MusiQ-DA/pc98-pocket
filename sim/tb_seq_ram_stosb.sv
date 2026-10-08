`default_nettype none
`timescale 1ns/1ps

// tb_seq_ram_stosb -- measure per-byte guest-write cost through the REAL
// pc98_gvram_seq + RAM.sv + sdram_model, the way rep stosb to the A8000
// graphics window exercises them. GRCG/EGC off, page 0: the seq passes the
// write straight through (expand=0), so cpu_ready is RAM's own
// memory_access_ready (with the posted-write gate on the new RAM).
//
// Prints one line per byte: "byte <i> +<cycles>". Also prints the min/
// max/mean after NBYTES. Baseline-vs-new comparison shows exactly where
// the posted-write change moved the per-access wall time.

module tb_seq_ram_stosb;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    localparam int  NBYTES  = 256;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    // ---- guest side ------------------------------------------------
    logic        cpu_rd = 0, cpu_wr = 0, cpu_gvram = 0, cpu_word = 0;
    logic [19:0] cpu_addr = 0;
    logic [7:0]  cpu_wdata = 0;
    wire  [7:0]  cpu_rdata, cpu_rdata_hi;
    wire         cpu_ready;

    // ---- seq <-> RAM ------------------------------------------------
    wire [19:0]  mem_addr;
    wire [7:0]   mem_wdata;
    wire         mem_word;
    wire         mem_rd, mem_wr;
    wire [7:0]   mem_rdata, mem_rdata_hi;
    wire         mem_done, mem_ready;

    // ---- RAM <-> SDRAM ---------------------------------------------
    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    wire        initilized_sdram;
    wire        memory_access_ready, access_complete, ram_address_select_n;

    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};

    // ---- display fetch on port D (gv_rd_req) -------------------------
    // +gvf=N: issue an 8-word gv read every N cycles, 0 = off. Models the
    // video beam's graphics-plane fetches sharing the SDRAM port with the
    // guest's write drains.
    int gvf_period = 0;
    int  gvf_cnt = 0;
    logic        gv_req = 0;
    logic [23:0] gv_addr = 24'h180000;
    wire         gv_ack, gv_rvalid, gv_done;
    wire [15:0]  gv_rdata;
    initial begin
        if (!$value$plusargs("gvf=%d", gvf_period)) gvf_period = 0;
    end
    always @(posedge clock) begin
        if (reset || gvf_period == 0) begin
            gv_req  <= 1'b0;
            gv_addr <= 24'h180000;
            gvf_cnt <= 0;
        end else if (gv_req && gv_done) begin
            gv_req  <= 1'b0;
            gv_addr <= gv_addr + 24'h10;
            gvf_cnt <= 0;
        end else if (!gv_req) begin
            gvf_cnt <= gvf_cnt + 1;
            if (gvf_cnt >= gvf_period) begin
                gvf_cnt <= 0;
                gv_req  <= 1'b1;
            end
        end
    end

    pc98_gvram_seq #(.EGC(1'b0)) seq (
        .clk(clock), .reset(reset),
        .cpu_gvram(cpu_gvram), .cpu_rd(cpu_rd), .cpu_wr(cpu_wr),
        .cpu_pf_len(4'd0),
        .cpu_word(cpu_word),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_wdata_hi(8'h00),
        .cpu_rdata(cpu_rdata), .cpu_rdata_hi(cpu_rdata_hi),
        .cpu_ready(cpu_ready),
        .grcg_active(1'b0), .grcg_rmw(1'b0),
        .grcg_mask(4'h0),
        .grcg_tile('{8'h0, 8'h0, 8'h0, 8'h0}),
        .analog_mode(1'b0),
        .access_page(1'b0), .mem_page1(),
        .egc_active(1'b0), .egc_wr(1'b0), .egc_rg(4'h0), .egc_d(8'h0),
        .svc_req(1'b0), .svc_we(1'b0), .svc_raw(1'b0), .svc_addr(20'h0),
        .svc_wdata(8'h0), .svc_done(), .svc_rdata(),
        .dbg(),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_pf_len(),
        .mem_word(mem_word),
        .mem_rd(mem_rd), .mem_wr(mem_wr),
        .mem_rdata(mem_rdata), .mem_rdata_hi(mem_rdata_hi),
        .mem_done(mem_done), .mem_ready(mem_ready)
    );

    RAM dut (
        .clock(clock), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(mem_addr), .internal_data_bus(mem_wdata),
        .data_bus_out(mem_rdata),
        .analog_mode(1'b0), .prefetch_len   (4'd0),
        .pf_beat_v      (),
        .pf_beat_dat    (),
        .word_access(mem_word),
        .internal_data_bus_hi(8'h00), .data_bus_out_hi(mem_rdata_hi),
        .gvram_page1_flag(1'b0),
        .memory_read_n(~mem_rd), .memory_write_n(~mem_wr),
        .no_command_state(1'b1),
        .memory_access_ready(mem_ready),
        .access_complete(mem_done),
        .ram_address_select_n(ram_address_select_n),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .ems98_map(ems98_unused),
        .bios_protect_flag(2'b00), .bios_shadow_flag(1'b0),
        .font_bank_flag(1'b0),
        .font_rd_req(1'b0), .font_rd_addr(24'd0), .font_rd_len(4'd0),
        .font_rd_ack(), .font_rd_valid(), .font_rd_data(), .font_rd_done(),
        .cg_rd_req(1'b0), .cg_rd_addr(24'd0), .cg_rd_len(4'd0),
        .cg_rd_ack(), .cg_rd_valid(), .cg_rd_data(), .cg_rd_done(),
        .gv_rd_req(gv_req), .gv_rd_addr(gv_addr), .gv_rd_len(4'd8),
        .gv_rd_ack(gv_ack), .gv_rd_valid(gv_rvalid), .gv_rd_data(gv_rdata),
        .gv_rd_done(gv_done),
        .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0),
        .vram_rd_wait_cycle(4'h0), .vram_wr_wait_cycle(4'h0),
        .ramimg_req(1'b0), .ramimg_we(1'b0), .ramimg_addr(24'h0),
        .ramimg_len(4'h0), .ramimg_wdata(16'h0000),
        .ramimg_ack(), .ramimg_rvalid(), .ramimg_rdata(), .ramimg_done()
    );

    sdram_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                  .T_RAS(2), .T_RC(3), .T_REF(335)
                  ,.PHYSICAL_DQ(1'b1)
                  ) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ---- driver: guest write strobe held until cpu_ready -----------
    int lat[$];
    task automatic wr_byte(input [19:0] a, input [7:0] d);
        int t0;
        begin
            @(posedge clock);
            cpu_gvram <= 1'b1; cpu_addr <= a; cpu_wdata <= d; cpu_wr <= 1'b1;
            t0 = $time;
            // like the zet bridge: the rise only counts after the dip that
            // marks this access having started (saw_low).
            do @(posedge clock); while (cpu_ready);
            do @(posedge clock); while (!cpu_ready);
            cpu_wr <= 1'b0; cpu_gvram <= 1'b0;
            lat.push_back(($time - t0) / int'(1000.0/CLK_MHZ));
        end
    endtask

    int mn = 100000, mx = 0, sum = 0, i;
    initial begin
        cpu_wr = 0; cpu_rd = 0; cpu_gvram = 0;
        repeat (10) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);
        repeat (20) @(posedge clock);

        for (i = 0; i < NBYTES; i = i + 1) begin
            wr_byte(20'hA8000 + i[13:0], i[7:0]);
            repeat (2) @(posedge clock);   // inter-byte gap like rep stosb
        end

        foreach (lat[k]) begin
            if (lat[k] < mn) mn = lat[k];
            if (lat[k] > mx) mx = lat[k];
            sum += lat[k];
        end
        $display("=== seq+RAM stosb: n=%0d min=%0d max=%0d mean=%0d cyc/byte ===",
                 NBYTES, mn, mx, sum/NBYTES);
        // histogram of the tail
        begin
            int over30 = 0, over60 = 0, over100 = 0;
            foreach (lat[k]) begin
                if (lat[k] > 30)  over30++;
                if (lat[k] > 60)  over60++;
                if (lat[k] > 100) over100++;
            end
            $display("    >30: %0d  >60: %0d  >100: %0d", over30, over60, over100);
        end
        $finish;
    end

    initial begin
        #20ms;
        $display("TIMEOUT");
        $finish;
    end
endmodule
`default_nettype wire
