// tb_softcpu_hdd -- boot the REAL firmware.vh inside the real
// softcpu_subsystem and prove the hard disk (slot 5) follows the floppy
// model: it mounts only on a dataslot-update bind, re-mounts on a re-bind
// (even at an unchanged size), and drops the image on a re-bind with no file.
//
// The trap this guards: the Pocket persists the Hard Disk pick (data.json
// bit9) and refills slot 5's DATATABLE entry at every launch without any
// update event. The firmware once mounted from that entry, so an image
// picked in an earlier session booted with the slot shown empty. Here the
// datatable carries exactly that stale entry (id 5, 1 MiB) from reset.
//
// Phases (hdd0_disk_bytes / hdd0_rebind model core_top's event latches):
//   A  no bind:            no slot-5 transfer, scsi_media stays 0
//   B  bind 1 MiB:         slot-5 header reads, scsi_media rises
//   C  same-size re-bind:  scsi_media falls, new slot-5 reads, rises again
//   E  OSD eject:          open the settings OSD, Hardware > Hard Disk, A:
//                          scsi_media falls, TEST UNIT READY answers CHECK
//                          CONDITION with sense NOT READY / 3A, and nothing
//                          re-mounts (no slot-5 reads) while no re-bind comes
//   F  re-bind after eject: a fresh pick mounts again, TUR answers GOOD
//   D  re-bind, no file:   scsi_media falls and stays 0, no slot-5 reads
//
// Mount evidence is the firmware's own SOFT_SCSI_MEDIA flag (scsi_media),
// which scsi_mount sets from the classified sector count and scsi_unmount
// clears; the image served is all-zero, which the probe classifies flat.
// Guest commands go through a model of Peripherals' 0xF4 mgmt window (the
// request/ack toggle, the auto-incrementing control index the CDB is read
// through, the buffer pointer REQUEST SENSE writes through, the status).
//
`timescale 1ns/1ps

module tb_softcpu_hdd;

    reg clk_sys = 0;
    reg reset   = 1;
    always #10 clk_sys = ~clk_sys;

    reg  [1:0]   draw_req  = 2'b00;
    reg  [1:0]   draw_busy = 2'b00;
    reg  [15:0]  draw_ops  = 16'h0000;
    reg  [383:0] draw_snap = 384'd0;

    reg  [15:0] pad        = 16'd0;  // cont1 buttons (BTN_* in softcpu_regs.h)
    reg         osd_open   = 1'b0;   // interact "Extra Options"
    reg  [31:0] hdd_bytes  = 32'd0;
    reg         hdd_rebind = 1'b0;

    // APF datatable model: two words per slot (id, size). Entry 0 is the
    // persisted Hard Disk pick, entry 1 the Settings slot. Port A reads one
    // clk_pico after the address, as the altsyncram does.
    wire        clk_pico;
    wire  [9:0] dt_addr;
    reg  [31:0] dt_q = 32'd0;
    always @(posedge clk_pico) begin
        case (dt_addr)
            10'd0:   dt_q <= 32'd5;
            10'd1:   dt_q <= 32'h0010_0000;
            10'd2:   dt_q <= 32'd7;
            10'd3:   dt_q <= 32'd512;
            default: dt_q <= 32'd0;
        endcase
    end

    // Dataslot engine model: ack the request, write the 512-byte sector
    // into the bridge RAM over bridge_wr (zeros, never the poison the
    // header read plants), then a one-cycle done. Counts slot-5 reads.
    wire        tds_rd, tds_wr;
    wire [15:0] tds_id;
    wire [31:0] tds_baddr;
    reg         tds_ack  = 0, tds_done = 0;
    reg  [8:0]  tds_cnt  = 0;
    reg         br_wr    = 0;
    reg  [31:0] br_addr  = 0;
    integer     hdd_reads = 0;
    always @(posedge clk_sys) begin
        tds_ack <= tds_rd | tds_wr;
        br_wr   <= 1'b0;
        tds_done <= 1'b0;
        if (tds_cnt != 0) begin
            tds_cnt <= tds_cnt - 1;
            if (tds_cnt > 9'd4) begin
                br_wr   <= 1'b1;
                br_addr <= tds_baddr + {21'd0, (9'd132 - tds_cnt), 2'b00};
            end
            tds_done <= (tds_cnt == 9'd2);
        end else if (tds_ack && (tds_rd | tds_wr)) begin
            tds_cnt <= 9'd132;
            if (tds_rd && tds_id == 16'd5)
                hdd_reads <= hdd_reads + 1;
        end
    end

    wire scsi_media;

    // Peripherals' pc98_scsi mgmt window (mgmt chip-select 0xF4), modelled
    // combinationally: the bridge captures mgmt_din on the mgmt_rd cycle.
    wire [15:0] mgmt_addr, mgmt_dout;
    wire        mgmt_wr, mgmt_rd;
    reg         sc_req = 0, sc_ack = 0;
    reg  [4:0]  sc_idx = 0;
    reg  [12:0] sc_bptr = 0;
    reg  [7:0]  sc_op  = 8'h00;      // CDB byte 0 of the posted command
    reg  [7:0]  sc_status = 8'hFF;
    integer     sc_done = 0;         // STATUS writes seen
    reg  [7:0]  sc_sense [0:17];
    wire        sc_cs  = mgmt_addr[15:8] == 8'hF4;
    wire [3:0]  sc_reg = mgmt_addr[3:0];
    reg  [15:0] sc_din;
    always @* begin
        sc_din = 16'd0;
        if (sc_cs) begin
            case (sc_reg)
                4'd0: sc_din = {8'h20, 7'd0, sc_req ^ sc_ack};
                4'd2: sc_din = {8'd0, (sc_idx == 5'd3) ? sc_op : 8'h00};
                default: ;
            endcase
        end
    end
    always @(posedge clk_sys) begin
        if (sc_cs && mgmt_wr) begin
            case (sc_reg)
                4'd0: if (mgmt_dout[0]) sc_ack <= sc_req;
                4'd1: sc_idx  <= mgmt_dout[4:0];
                4'd2: sc_idx  <= sc_idx + 5'd1;
                4'd3: sc_bptr <= mgmt_dout[12:0];
                4'd4: begin
                    if (sc_bptr < 13'd18) sc_sense[sc_bptr] <= mgmt_dout[7:0];
                    sc_bptr <= sc_bptr + 13'd1;
                end
                4'd6: begin sc_status <= mgmt_dout[7:0]; sc_done <= sc_done + 1; end
                default: ;
            endcase
        end
        if (sc_cs && mgmt_rd && (sc_reg == 4'd2))
            sc_idx <= sc_idx + 5'd1;
    end

    softcpu_subsystem dut (
        .clk_sys (clk_sys),
        .clk_74a (clk_sys),
        .reset   (reset),
        .fw_wr_clk  (clk_sys),
        .fw_wr_en   (1'b0),
        .fw_wr_addr (14'd0),
        .fw_wr_data (32'd0),
        .clk_pico (clk_pico),
        .fdd_request   (2'b00),
        .fdd0_disk_size(32'd0),
        .fdd1_disk_size(32'd0),
        .hdd0_disk_bytes(hdd_bytes),
        .datatable_addr (dt_addr),
        .datatable_data (),
        .datatable_wren (),
        .datatable_q    (dt_q),
        .fdd0_rebind (1'b0),
        .fdd1_rebind (1'b0),
        .hdd0_rebind (hdd_rebind),
        .mgmt_addr (mgmt_addr), .mgmt_dout (mgmt_dout),
        .mgmt_wr (mgmt_wr), .mgmt_rd (mgmt_rd),
        .mgmt_din  (sc_din),
        .bridge_wr      (br_wr),
        .bridge_addr    (br_addr),
        .bridge_wr_data (32'd0),
        .target_dataslot_read  (tds_rd),
        .target_dataslot_write (tds_wr),
        .target_dataslot_id    (tds_id),
        .target_dataslot_slotoffset (),
        .target_dataslot_bridgeaddr (tds_baddr),
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
        .cont1_key    (pad),
        .dock_key_code(8'd0),
        .dock_key_ext (1'b0),
        .dock_key_stb (1'b0),
        .osd_open_req (osd_open),
        .raster_w     (10'd640),
        .raster_h     (10'd400),
        .dataslots_ready (1'b1),
        .soft_guest_hold (),
        .soft_vid_blank  (),
        .scsi_media      (scsi_media),
        .gdc_draw_req   (draw_req),
        .gdc_draw_busy  (draw_busy),
        .gdc_draw_ops   (draw_ops),
        .gdc_draw_snaps (draw_snap),
        .gdc_srv_done_levels (),
        .st_req   (),
        .st_we    (),
        .st_raw   (),
        .st_addr  (),
        .st_wdata (),
        .st_done  (1'b0),
        .st_rdata (8'd0),
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
        .key_cfg_idx (4'd0), .key_cfg_q (), .key_cfg_diag ()
    );

    integer errors = 0;
    integer falls  = 0;
    reg     media_q = 0;
    always @(posedge clk_sys) begin
        media_q <= scsi_media;
        if (media_q && !scsi_media)
            falls <= falls + 1;
        if (dut.cpu_trap)
            $display("%0t   CPU TRAP", $time);
    end

    task check(input cond, input [8*64-1:0] what);
        if (!cond) begin
            errors = errors + 1;
            $display("%0t   FAIL: %0s", $time, what);
        end else
            $display("%0t   ok:   %0s", $time, what);
    endtask

    // Wait up to `n` clk_sys for scsi_media to read `v`.
    task wait_media(input v, input integer n);
        integer i;
        for (i = 0; i < n && scsi_media !== v; i = i + 1)
            @(posedge clk_sys);
    endtask

    // Post one guest command (CDB byte 0 = op, the rest zero) and wait for
    // the firmware's STATUS write.
    task scsi_cmd(input [7:0] op);
        integer i, d0;
        d0 = sc_done;
        sc_op  <= op;
        @(posedge clk_sys);
        sc_req <= ~sc_req;
        for (i = 0; i < 2000000 && sc_done == d0; i = i + 1)
            @(posedge clk_sys);
    endtask

    // One button press through vkb_ui_tick: the word must hold BTN_SETTLE
    // (~10 ms of clk_pico, ~430k clk_sys) before it counts, and the release
    // the same; the margin covers the IRQ's panel repaint.
    localparam integer HOLD = 900000;
    task press(input [15:0] m);
        pad <= m;
        repeat (HOLD) @(posedge clk_sys);
        pad <= 16'd0;
        repeat (HOLD) @(posedge clk_sys);
    endtask
    localparam [15:0] BTN_DOWN = 16'h0002, BTN_A = 16'h0010, BTN_B = 16'h0020;

    integer reads0, falls0;

    initial begin
        repeat (8) @(posedge clk_sys);
        reset <= 0;

        // A: boot through the poll loop with the stale datatable entry only.
        repeat (4000000) @(posedge clk_sys);
        $display("%0t pc=%08x: boot runway done, slot-5 reads=%0d media=%0d",
                 $time, dut.pico.reg_pc, hdd_reads, scsi_media);
        check(hdd_reads == 0, "A: no bind -> no slot-5 transfer");
        check(scsi_media == 0, "A: no bind -> no mount");

        // B: the user picks an image -- the update event latches its size.
        hdd_bytes  <= 32'h0010_0000;
        hdd_rebind <= ~hdd_rebind;
        wait_media(1'b1, 2000000);
        $display("%0t B: slot-5 reads=%0d media=%0d", $time, hdd_reads, scsi_media);
        check(hdd_reads > 0, "B: bind -> header read off slot 5");
        check(scsi_media == 1, "B: bind -> mounted");
        scsi_cmd(8'h00);
        check(sc_status == 8'h00, "B: TEST UNIT READY -> GOOD");

        // C: a swap at the same size; only the toggle says anything changed.
        repeat (200000) @(posedge clk_sys);
        reads0 = hdd_reads;
        falls0 = falls;
        hdd_rebind <= ~hdd_rebind;
        wait_media(1'b0, 2000000);
        wait_media(1'b1, 2000000);
        $display("%0t C: slot-5 reads=%0d falls=%0d media=%0d",
                 $time, hdd_reads, falls, scsi_media);
        check(falls == falls0 + 1, "C: re-bind -> old image dropped");
        check(hdd_reads > reads0, "C: re-bind -> new image probed");
        check(scsi_media == 1, "C: re-bind -> remounted");

        // E: eject through the OSD. Extra Options opens Settings at row 0;
        // Hardware is main row 2, Hard Disk is Hardware row 2.
        repeat (200000) @(posedge clk_sys);
        falls0 = falls;
        osd_open <= 1'b1;
        repeat (HOLD) @(posedge clk_sys);
        osd_open <= 1'b0;
        press(BTN_DOWN);
        press(BTN_DOWN);
        press(BTN_A);       // into Hardware
        press(BTN_DOWN);
        press(BTN_DOWN);
        check(scsi_media == 1, "E: navigating the OSD leaves the disk in");
        press(BTN_A);       // Hard Disk: eject
        wait_media(1'b0, 2000000);
        reads0 = hdd_reads;
        press(BTN_B);       // back to main
        press(BTN_B);       // close the panel
        $display("%0t E: falls=%0d media=%0d", $time, falls, scsi_media);
        check(falls == falls0 + 1 && scsi_media == 0, "E: OSD eject -> unmounted");
        scsi_cmd(8'h00);
        check(sc_status == 8'h02, "E: TEST UNIT READY -> CHECK CONDITION");
        scsi_cmd(8'h03);
        check(sc_status == 8'h00 && sc_sense[2] == 8'h02 && sc_sense[12] == 8'h3A,
              "E: REQUEST SENSE -> NOT READY / medium not present");
        repeat (1000000) @(posedge clk_sys);
        scsi_cmd(8'h00);
        check(sc_status == 8'h02 && scsi_media == 0, "E: stays ejected without a re-bind");
        check(hdd_reads == reads0, "E: ejected -> no slot-5 reads");

        // F: the user picks the image again in the Pocket menu.
        reads0 = hdd_reads;
        hdd_rebind <= ~hdd_rebind;
        wait_media(1'b1, 2000000);
        $display("%0t F: slot-5 reads=%0d media=%0d", $time, hdd_reads, scsi_media);
        check(scsi_media == 1 && hdd_reads > reads0, "F: re-bind after eject -> mounted");
        scsi_cmd(8'h00);
        check(sc_status == 8'h00, "F: TEST UNIT READY -> GOOD");

        // D: a re-bind that carries no file leaves the drive empty.
        repeat (200000) @(posedge clk_sys);
        hdd_bytes  <= 32'd0;
        hdd_rebind <= ~hdd_rebind;
        wait_media(1'b0, 2000000);
        reads0 = hdd_reads;
        repeat (1000000) @(posedge clk_sys);
        $display("%0t D: slot-5 reads=%0d media=%0d", $time, hdd_reads, scsi_media);
        check(scsi_media == 0, "D: empty re-bind -> unmounted");
        check(hdd_reads == reads0, "D: empty re-bind -> no further reads");

        $display("DONE: %0d errors", errors);
        if (errors != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
