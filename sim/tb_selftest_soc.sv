//
// tb_selftest_soc -- run the REAL firmware against the REAL self-test master.
//
// The last unverified stretch. tb_ext_access and tb_ext_arbiter proved the path
// from the ext port through BUS_ARBITER to RAM.sv works for both controllers,
// yet three hardware builds showed nothing on screen -- including a CGA VRAM
// write that never touches the SDRAM. So the fault is between the firmware and
// that port: the MMIO window in softcpu_subsystem, sdram_selftest_master, or
// the clk_pico/clk_sys handshake between them.
//
// This runs picorv32 out of the committed firmware.vh, so the C, the MMIO
// decode, the master and RAM.sv are all the shipped article. What it watches
// for is simply whether an access ever reaches the memory bus at all.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_selftest_soc;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clk_sys = 0, reset = 1;
    always #(HALF_NS) clk_sys = ~clk_sys;

    logic clk_74a = 0;  always #6.7 clk_74a = ~clk_74a;
    logic clk_pix = 0;  always #17.5 clk_pix = ~clk_pix;

    wire        clk_pico;
    wire [19:0] st_addr;
    wire  [7:0] st_wdata;
    wire        st_we, st_req;
    wire        st_done;
    wire  [7:0] st_rdata;
    wire        soft_guest_hold;

    // ---- the shipped softcore, running the committed firmware image
    softcpu_subsystem u_soft (
        .clk_sys(clk_sys), .clk_74a(clk_74a), .reset(reset), .clk_pico(clk_pico),
        .fdd_request(2'd0), .ide0_request(3'd0),
        .fdd0_disk_size(32'd0), .fdd1_disk_size(32'd0),
        .datatable_addr(), .datatable_data(), .datatable_wren(),
        .datatable_q(32'd0),
        .fdd0_rebind(1'b0), .fdd1_rebind(1'b0),
        .mgmt_addr(), .mgmt_dout(), .mgmt_wr(), .mgmt_rd(), .mgmt_din(16'd0),
        .bridge_wr(1'b0), .bridge_addr(32'd0), .bridge_wr_data(32'd0),
        .target_dataslot_read(), .target_dataslot_write(),
        .target_dataslot_id(), .target_dataslot_slotoffset(),
        .target_dataslot_bridgeaddr(), .target_dataslot_length(),
        .target_dataslot_ack(1'b1), .target_dataslot_done(1'b1),
        .target_dataslot_err(3'd0), .bridge_rd_data_out(),
        .clk_pix(clk_pix), .osd_hcnt(osd_hcnt), .osd_vcnt(osd_vcnt),
        .osd_palette_idx(osd_palette_idx), .osd_in_area(osd_in_area),
        .cont1_key(16'd0), .dock_key_code(8'd0), .dock_key_ext(1'b0),
        .dock_key_stb(1'b0), .credits_active(1'b0), .osd_open_req(1'b0),
        .raster_w(osd_raster_w), .raster_h(osd_raster_h),
        .dataslots_ready(1'b1),           // pretend APF finished the load
        .soft_guest_hold(soft_guest_hold),
        .st_addr(st_addr), .st_wdata(st_wdata), .st_we(st_we), .st_req(st_req),
        .st_done(st_done), .st_rdata(st_rdata),
        .osd_active(), .osd_credits_req(), .osd_video_req(),
        .vkb_key(), .vkb_stb(), .osd_palette(), .osd_cpu_speed(),
        .osd_bios_wr(), .osd_opl2(), .osd_boost(), .osd_spk_vol(), .osd_stereo(),
        .osd_cms(), .osd_composite(), .osd_ems(), .osd_ems_frame(), .osd_a000(),
        .osd_joy1(), .osd_joy2(), .osd_swapjoy(), .osd_syncjoy(),
        .osd_video_1st(), .osd_cga_gfx(), .osd_hgc_gfx(), .osd_splash(),
        .osd_gamepad(), .key_cfg_flat()
    );

    // ---- the shipped master
    wire        st_run, st_wr_n, st_rd_n;
    wire        ram_rw_complete;
    wire  [7:0] ram_data_out;
    logic       initilized_sdram;

    sdram_selftest_master u_master (
        .clk(clk_sys), .rst(reset),
        .req(st_req), .we(st_we), .addr(st_addr), .wdata(st_wdata),
        .done(st_done), .rdata(st_rdata),
        .initilized_sdram(initilized_sdram),
        .loader_busy(1'b0),
        .run(st_run), .write_n(st_wr_n), .read_n(st_rd_n),
        .ram_rw_complete(ram_rw_complete), .ext_rdata(ram_data_out)
    );

    // ---- RAM.sv, driven the way core_top wires the ext port
    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [6:0] unused_map [0:3] = '{7'd0, 7'd0, 7'd0, 7'd0};
    wire        memory_access_ready, ram_address_select_n;

    RAM u_ram (
        .clock(clk_sys), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(st_addr), .internal_data_bus(st_wdata),
        .data_bus_out(ram_data_out),
        .memory_read_n(st_rd_n), .memory_write_n(st_wr_n),
        .no_command_state(st_rd_n & st_wr_n),
        .memory_access_ready(memory_access_ready),
        .access_complete(ram_rw_complete),
        .ram_address_select_n(ram_address_select_n),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .map_ems(unused_map),
        .ems_b1(1'b0), .ems_b2(1'b0), .ems_b3(1'b0), .ems_b4(1'b0),
        .bios_protect_flag(2'b00), .tandy_bios_flag(1'b0),
        .enable_a000h(1'b1), .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0)
    );

    sdram_board_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                        .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clk_sys), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ---- the real compositor, closing the last unsimulated link
    //
    // testB12 reported through the OSD with every input to the mix verified,
    // and hardware still showed nothing. pocket_video's final step is what is
    // left, so put it in the loop: it generates osd_hcnt/osd_vcnt itself from
    // the raster, softcpu_subsystem answers with osd_in_area/palette, and the
    // question is simply whether video_rgb ever carries an overlay colour.
    //
    // The raster is a plain 640x200 CGA-like frame; the picture behind it is
    // deliberately black so any non-black output pixel is the overlay.
    wire  [9:0] osd_hcnt, osd_vcnt;
    wire  [9:0] osd_raster_w, osd_raster_h;
    wire  [3:0] osd_palette_idx;
    wire        osd_in_area;
    wire [23:0] video_rgb;
    wire        video_de;

    localparam int H_ACT = 640, H_TOT = 800;
    localparam int V_ACT = 200, V_TOT = 262;
    int hc = 0, vc = 0;
    logic hb = 0, vb = 0, hs = 0, vs = 0;
    always @(posedge clk_pix) begin
        hc <= (hc == H_TOT-1) ? 0 : hc + 1;
        if (hc == H_TOT-1) vc <= (vc == V_TOT-1) ? 0 : vc + 1;
        hb <= (hc >= H_ACT);
        vb <= (vc >= V_ACT);
        hs <= (hc >= H_ACT+16) && (hc < H_ACT+80);
        vs <= (vc >= V_ACT+8)  && (vc < V_ACT+12);
    end

    pocket_video u_video (
        .clk_pix(clk_pix), .clk_pix_90(clk_pix), .RESET(reset),
        .r(6'd0), .g(6'd0), .b(6'd0),          // black picture: overlay only
        .HSync(hs), .VSync(vs), .HBlank(hb), .VBlank(vb),
        .palette_cfg(3'd0), .credits_mode_pix(1'b0),
        .pix_sel(1'b0), .vid_blank(1'b0),
        .osd_active(u_soft.osd_active_r),
        .osd_palette_idx(osd_palette_idx), .osd_in_area(osd_in_area),
        .osd_hcnt(osd_hcnt), .osd_vcnt(osd_vcnt),
        .osd_raster_w(osd_raster_w), .osd_raster_h(osd_raster_h),
        .video_rgb(video_rgb), .video_de(video_de),
        .video_hs(), .video_vs(), .video_skip(),
        .video_rgb_clock(), .video_rgb_clock_90()
    );

    int lit_pixels = 0, in_area_cycles = 0, shown_pixels = 0;
    always @(posedge clk_pix) begin
        if (osd_in_area) begin
            in_area_cycles++;
            if (osd_palette_idx != 4'd0) lit_pixels++;
        end
        // The thing that actually reaches the screen.
        if (video_de && (video_rgb != 24'd0)) shown_pixels++;
    end

    // ---- observation
    int  reqs = 0, accesses = 0;
    logic st_req_d = 0, st_run_d = 0;
    always @(posedge clk_sys) begin
        st_req_d <= st_req;
        st_run_d <= st_run;
        if (st_req & ~st_req_d) begin
            reqs++;
            if (reqs <= 8)
                $display("[%0t] REQ #%0d  we=%0d addr=%05h wdata=%02h",
                         $time, reqs, st_we, st_addr, st_wdata);
        end
        if (st_run & ~st_run_d) accesses++;
    end

    // Where is the softcore? Sample the fetch address so a stall shows up as a
    // PC that stops moving, and record the highest one reached.
    logic [31:0] pc_last = 0, pc_max = 0;
    int stuck = 0;
    always @(posedge clk_pico) begin
        if (u_soft.cpu_mem_valid && u_soft.cpu_mem_instr) begin
            pc_last <= u_soft.cpu_mem_addr;
            if (u_soft.cpu_mem_addr > pc_max) pc_max <= u_soft.cpu_mem_addr;
        end
        // Any access into the self-test region at all, even one that does not
        // trigger: tells us whether the decode or the code is at fault.
        if (u_soft.cpu_mem_valid && (u_soft.cpu_mem_addr[31:28] == 4'h5))
            region5++;
    end
    int region5 = 0;

    initial begin
        for (int t = 0; t < 24; t++) begin
            #2_000_000;
            $display("[%0t] pc=%08h pc_max=%08h  region5=%0d  st_req=%0d",
                     $time, pc_last, pc_max, region5, st_req);
        end
    end

    initial begin
        repeat (20) @(posedge clk_sys);
        reset = 0;
        $display("released reset; waiting for the firmware to drive the window");

        // Let the firmware get through its startup and into the self-test.
        // The BSS clear in start.S alone is ~1363 byte stores at roughly 700 ns
        // an instruction (picorv32 on clk_pico, which is clk_sys/6), so nothing
        // interesting happens for the first ~4 ms. An earlier 4.2 ms run stopped
        // inside that loop and looked like a hang.
        #48_000_000;  // 48 ms

        $display("\n=== summary ===");
        $display("  soft_guest_hold : %0d (1 = still holding, as this build should)",
                 soft_guest_hold);
        $display("  st_req  rising edges : %0d", reqs);
        $display("  st_run  rising edges : %0d", accesses);
        $display("  region-5 bus cycles  : %0d", region5);
        $display("  last fetch pc        : %08h (max %08h)", pc_last, pc_max);
        $display("  osd_active           : %0d", u_soft.osd_active_r);
        $display("  osd in-area cycles   : %0d", in_area_cycles);
        $display("  osd LIT pixels       : %0d", lit_pixels);
        $display("  pixels ON SCREEN     : %0d  <-- what the panel would show",
                 shown_pixels);
        if (shown_pixels == 0)
            $display("  RESULT: FAIL -- nothing reaches the screen");
        else if (lit_pixels == 0)
            $display("  RESULT: FAIL -- the overlay never produced a lit pixel");
        else if (reqs == 0)
            $display("  RESULT: FAIL -- the firmware never drove the MMIO window");
        else if (accesses == 0)
            $display("  RESULT: FAIL -- requests arrive but the master never runs");
        else
            $display("  RESULT: PASS -- %0d accesses reached the bus", accesses);
        $finish;
    end

endmodule

`default_nettype wire
