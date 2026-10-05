// tb_softcpu_fw — boot the REAL firmware.vh inside the real
// softcpu_subsystem and drive one slave-channel WDAT op through the
// gdc_draw_* handshake, watching every store the CPU emits to the
// service-trigger address 0x5000_0008.
//
// The question this answers on the bench: can the shipped firmware ever
// present a byte other than 1/2 to the trigger? The parked hardware
// witness (slot 0x3f) says the last op launched raw; disassembly shows
// every trigger store is `sw s5,0x0(t6)` (=2, read) or `sw s8,0x0(t6)`
// (=1, write) with both registers re-loaded after each in-loop excursion.
// If a dirty byte shows up here it is a picorv32/mem-path anomaly; if not,
// the search moves downstream.
//
// Snapshot layout for the slave (ch1) channel is snaps[383:192], little
// endian across six words; ops[15:8] is the opcode, req[1] the request,
// done_levels[1] the retire pulse.
//
// Op under test: WDAT 0x20, CSRW EAD=0x4008 (B plane, byte 0x10), DC=1
// (leng=2 words), mask=FFFF, code=FFFF -> two word writes. Expect 8
// launches: read/read/write/write twice, all clean.
//
`timescale 1ns/1ps

module tb_softcpu_fw;

    reg clk_sys = 0;
    reg reset   = 1;
    always #10 clk_sys = ~clk_sys;

    reg        fw_wr_en   = 0;
    reg [13:0] fw_wr_addr = 0;
    reg [31:0] fw_wr_data = 0;

    reg        st_done_r  = 0;
    reg  [3:0] dcnt       = 0;
    reg  [7:0] st_rdata_r = 8'h5A;

    reg  [1:0]   draw_req  = 2'b00;
    reg  [1:0]   draw_busy = 2'b00;
    reg  [15:0]  draw_ops  = 16'h0000;
    reg  [383:0] draw_snap = 384'd0;

    // Boot-time dataslot model: the firmware polls TDS_STATUS for
    // done/ack around every transfer (font load, mounts). Answer every
    // request with ack then a one-cycle done so boot reaches the poll
    // loop.
    wire tds_rd, tds_wr;
    reg  tds_ack = 0, tds_done = 0;
    reg  [7:0] tds_cnt = 0;
    always @(posedge clk_sys) begin
        tds_ack <= tds_rd | tds_wr;
        if (tds_cnt != 0) begin
            tds_cnt  <= tds_cnt - 1;
            tds_done <= (tds_cnt == 8'd2);
        end else begin
            tds_done <= 1'b0;
            if (tds_ack && (tds_rd | tds_wr))
                tds_cnt <= 8'd20;
        end
    end

    wire clk_pico;
    wire        st_req, st_we, st_raw;
    wire [19:0] st_addr;
    wire  [7:0] st_wdata;
    wire  [1:0] done_lv;

    softcpu_subsystem dut (
        .clk_sys (clk_sys),
        .clk_74a (clk_sys),
        .reset   (reset),
        .fw_wr_clk  (clk_sys),
        .fw_wr_en   (fw_wr_en),
        .fw_wr_addr (fw_wr_addr),
        .fw_wr_data (fw_wr_data),
        .clk_pico (clk_pico),
        .fdd_request   (2'b00),
        .fdd0_disk_size(32'd0),
        .fdd1_disk_size(32'd0),
        .datatable_addr (),
        .datatable_data (),
        .datatable_wren (),
        .datatable_q    (32'd0),
        .fdd0_rebind (1'b0),
        .fdd1_rebind (1'b0),
        .mgmt_addr (), .mgmt_dout (), .mgmt_wr (), .mgmt_rd (),
        .mgmt_din  (16'd0),
        .bridge_wr      (1'b0),
        .bridge_addr    (32'd0),
        .bridge_wr_data (32'd0),
        .target_dataslot_read  (tds_rd),
        .target_dataslot_write (tds_wr),
        .target_dataslot_id    (),
        .target_dataslot_slotoffset (),
        .target_dataslot_bridgeaddr (),
        .target_dataslot_length (),
        .target_dataslot_ack  (tds_ack),
        .target_dataslot_done (tds_done),
        .target_dataslot_err  (3'd0),
        .bridge_rd_data_out (),
        .clk_pix   (clk_sys),
        .osd_hcnt  (10'd0),
        .osd_vcnt  (10'd0),
        .osd_palette_idx (),
        .osd_in_area     (),
        .cont1_key    (16'd0),
        .dock_key_code(8'd0),
        .dock_key_ext (1'b0),
        .dock_key_stb (1'b0),
        .osd_open_req (1'b0),
        .raster_w     (10'd640),
        .raster_h     (10'd400),
        .dataslots_ready (1'b1),
        .soft_guest_hold (),
        .soft_vid_blank  (),
        .scsi_media      (),
        .gdc_draw_req   (draw_req),
        .gdc_draw_busy  (draw_busy),
        .gdc_draw_ops   (draw_ops),
        .gdc_draw_snaps (draw_snap),
        .gdc_srv_done_levels (done_lv),
        .st_req   (st_req),
        .st_we    (st_we),
        .st_raw   (st_raw),
        .st_addr  (st_addr),
        .st_wdata (st_wdata),
        .st_done  (st_done_r),
        .st_rdata (st_rdata_r),
        .accel_status (8'd0),
        .osd_active   (),
        .osd_disk_led (),
        .osd_extmem   (),
        .osd_dbl_skip (),
        .osd_fdd_turbo (),
        .osd_dipsw2 (), .osd_a3fea (), .osd_a3fee (), .osd_a3ff2 (),
        .vkb_key (), .vkb_stb (),
        .osd_palette  (), .osd_cpu_speed (), .osd_bios_wr (),
        .osd_boost    (), .osd_spk_vol   (), .osd_stereo (),
        .osd_gamepad  (),
        .key_cfg_flat ()
    );

    // Slave-channel (ch1) WDAT snapshot; snap byte i sits at
    // snaps[192 + i*8 +: 8].
    task set_snap(input integer i, input [7:0] b);
        draw_snap[192 + i*8 +: 8] = b;
    endtask

    integer nlaunch = 0;
    integer errors  = 0;
    reg st_req_q = 0;

    // Every launch is interesting: print it, and flag any trigger-store
    // fingerprint that is not the clean sw-1/sw-2 pair -- that is the
    // byte the launch logic sampled at the accept edge.
    always @(posedge clk_pico) begin
        st_req_q <= st_req;
        if (st_req && !st_req_q) begin
            nlaunch <= nlaunch + 1;
            $display("%0t LAUNCH %0d: addr(fp)=%05x wdata(byte)=%02x we=%0d raw=%0d",
                     $time, nlaunch + 1, st_addr, st_wdata, st_we, st_raw);
            if (st_raw) begin
                errors <= errors + 1;
                $display("%0t   ^^ RAW ARM: fingerprint=%05x byte=%02x",
                         $time, st_addr, st_wdata);
            end
        end
        // Bus-level truth: flag any store INTO the trigger address whose
        // wdata is not the clean 1/2 the firmware is supposed to write.
        if (dut.cpu_mem_valid && |dut.cpu_mem_wstrb &&
            dut.cpu_mem_addr == 32'h5000_0008 &&
            !(dut.cpu_mem_wdata == 32'd1 || dut.cpu_mem_wdata == 32'd2)) begin
            errors <= errors + 1;
            $display("%0t   ^^ DIRTY TRIG STORE: wdata=%08x wstrb=%b pc=%08x",
                     $time, dut.cpu_mem_wdata, dut.cpu_mem_wstrb,
                     dut.pico.reg_pc);
        end
        if (dut.cpu_trap)
            $display("%0t   CPU TRAP", $time);
    end

    // st_done model: pulse six clk_pico after the request lands.
    always @(posedge clk_pico) begin
        if (reset || !st_req) begin
            dcnt      <= 0;
            st_done_r <= 0;
        end else begin
            st_done_r <= (dcnt == 4'd5);
            if (dcnt != 4'd5)
                dcnt <= dcnt + 1;
        end
    end

    task clear_snap;
        integer i;
        for (i = 0; i < 24; i = i + 1)
            set_snap(i, 8'd0);
    endtask

    // Drive one slave op and wait for its retire pulse.
    task run_op(input [7:0] opcode);
        integer i;
        begin
            draw_ops  <= {opcode, 8'h00};
            draw_req  <= 2'b10;
            for (i = 0; i < 20000000; i = i + 1) begin
                @(posedge clk_sys);
                if (done_lv[1]) begin
                    $display("%0t   op %02x retired; %0d launches",
                             $time, opcode, nlaunch);
                    draw_req <= 2'b00;
                    i = 20000000;
                end
            end
            repeat (2000) @(posedge clk_sys);
        end
    endtask

    initial begin
        integer i;
        clear_snap;
        repeat (8) @(posedge clk_sys);
        reset <= 0;

        // Boot runway: osd/font/mount init through the TDS model, then the
        // poll loop. The op sequence mirrors a mixed guest workload:
        // WDAT -> vectl (the drawing op whose loops own s5/s8) -> WDAT.
        // A dirty-exit bug shows up as a non-1/2 trigger store in the
        // second WDAT's launches.
        repeat (4000000) @(posedge clk_sys);
        $display("%0t pc=%08x: boot runway done", $time, dut.pico.reg_pc);

        // Op 1: WDAT 0x20, CSRW 0x4008 (B plane @0x10), leng=2, mask/code FF.
        clear_snap;
        set_snap(1, 8'h01);       // dc -> leng 2
        set_snap(11, 8'h08);      // csrw = 0x4008
        set_snap(12, 8'h40);
        set_snap(18, 8'h20);      // write_mode = 0x20
        set_snap(19, 8'hFF);      // mask = FFFF
        set_snap(20, 8'hFF);
        set_snap(21, 8'hFF);      // code = FFFF
        set_snap(22, 8'hFF);
        run_op(8'h20);

        // Op 2: VECTE 0x6C, ope bit3 -> vectl, a short line that rides the
        // s5=len / s8=planes excursions inside gdc_poll.
        clear_snap;
        set_snap(0, 8'h08);       // ope: bit3 = vectl
        set_snap(1, 8'h04);       // dc -> dir/len small
        set_snap(3, 8'h10);       // d
        set_snap(11, 8'h08);      // csrw = 0x4008
        set_snap(12, 8'h40);
        set_snap(18, 8'h6C);      // write_mode = VECTE cmd byte
        run_op(8'h6C);

        // Op 3: the same WDAT again -- if the draw op left s5/s8 dirty,
        // these trigger stores carry the leftovers.
        clear_snap;
        set_snap(1, 8'h01);
        set_snap(11, 8'h08);
        set_snap(12, 8'h40);
        set_snap(18, 8'h20);
        set_snap(19, 8'hFF);
        set_snap(20, 8'hFF);
        set_snap(21, 8'hFF);
        set_snap(22, 8'hFF);
        run_op(8'h20);

        $display("DONE: %0d launches, %0d errors", nlaunch, errors);
        if (errors != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
