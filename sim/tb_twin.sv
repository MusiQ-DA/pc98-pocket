`default_nettype none
`timescale 1ns/1ps
module tb_twin;
    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    logic [19:0] address = '0;
    logic [7:0]  internal_data_bus = '0;
    logic [7:0]  data_bus_out;
    logic        memory_read_n = 1, memory_write_n = 1;
    logic        no_command_state = 1;
    logic        memory_access_ready, access_complete, ram_address_select_n;
    logic        initilized_sdram;

    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};

    RAM dut (
        .clock(clock), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(address), .internal_data_bus(internal_data_bus),
        .data_bus_out(data_bus_out),
        .analog_mode(1'b0), .prefetch_len   (4'd0),
        .pf_beat_v      (),
        .pf_beat_dat    (),
        .word_access(1'b0),
        .internal_data_bus_hi(8'h00), .data_bus_out_hi(),
        .gvram_page1_flag(1'b0),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .no_command_state(no_command_state),
        .memory_access_ready(memory_access_ready),
        .access_complete(access_complete),
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
        .gv_rd_req(1'b0), .gv_rd_addr(24'd0), .gv_rd_len(4'd0),
        .gv_rd_ack(), .gv_rd_valid(), .gv_rd_data(), .gv_rd_done(),
        .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0), .vram_rd_wait_cycle(4'h0), .vram_wr_wait_cycle(4'h0),
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

    int last = -1;
    always @(negedge clock) begin
        int st;
        st = dut.state;
        if (st != last || dut.wc_pend || memory_write_n == 0 || memory_read_n == 0 || memory_access_ready) begin
            $display("%8t st=%0d nst=%0d wc=%b rc=%b pend=%b alw=%b alr=%b om=%b nws=%b rdy=%b wrq=%b wfl=%b wadr=%05h wdat=%02h",
                     $time, st, dut.next_state, dut.write_command, dut.read_command,
                     dut.wc_pend, dut.accept_live_wr, dut.accept_live_rd,
                     dut.write_strobe_match, dut.new_write_strobe,
                     memory_access_ready, dut.write_request, dut.write_flag,
                     dut.accept_address, dut.accept_data);
            last = st;
        end
    end

    initial begin
        repeat (8) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);
        $display("init done");
        // write FF to target so we can see if the write lands
        address = 20'h20600; internal_data_bus = 8'hFF;
        no_command_state = 0; memory_write_n = 0;
        repeat (4) @(posedge clock);
        while (!memory_access_ready) @(posedge clock);
        memory_write_n = 1; no_command_state = 1;
        repeat (4) @(posedge clock);
        $display("--- pre-dirty done, now read-then-held-write ---");
        // read
        address = 20'h1FE00; internal_data_bus = 8'h00;
        no_command_state = 0; memory_read_n = 0;
        repeat (4) @(posedge clock);
        while (!memory_access_ready) @(posedge clock);
        // swap to write inside the read's COMPLETE
        address = 20'h20600; internal_data_bus = 8'h77;
        memory_read_n = 1; memory_write_n = 0;
        begin int g; g = 0;
        while (!memory_access_ready && g < 400) begin
            @(posedge clock); g++;
        end
        $display("write strobe released after %0d clocks", g); end
        memory_write_n = 1; no_command_state = 1;
        repeat (8) @(posedge clock);
        // readback
        address = 20'h20600; internal_data_bus = 8'h00;
        no_command_state = 0; memory_read_n = 0;
        repeat (4) @(posedge clock);
        while (!memory_access_ready) @(posedge clock);
        $display("readback @20600 = %02h (want 77)", data_bus_out);
        memory_read_n = 1; no_command_state = 1;
        repeat (8) @(posedge clock);
        $finish;
    end
endmodule
