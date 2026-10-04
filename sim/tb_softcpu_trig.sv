// tb_softcpu_trig — drive the REAL softcpu_subsystem (picorv32 + firmware
// sprom + service-launch block) with a hand-assembled micro-program that
// stores to the service registers at 0x5000_0000/4/8, and observe exactly
// what the launch logic captures.
//
// The mystery on the metal: slot 0x31's arm ctx said a WDAT write armed
// RAW even though the firmware only ever stores 1/2 to the trigger. The
// 0x3f probe slot reads the launched {addr,wdata,req,we,raw} straight off
// these wires; this bench exercises the same launch logic it watches:
//
//   * ST_WDATA = 0xFF then ST_TRIG = 1 — if the trigger launch could ever
//     see the previous store's data, this is where st_raw would show it
//     (bit 2 of 0xFF is the raw flag itself; the wdata-lag theory).
//   * ST_TRIG = 5 — sanity that raw CAN be latched when actually stored.
//
// Expected launches (addr=0x4008 throughout):
//   1: we=1 raw=0 wdata=AA
//   2: we=0 raw=0 wdata=AA   (read trigger)
//   3: we=1 raw=0 wdata=FF   (the bleed-through probe)
//   4: we=1 raw=1 wdata=FF   (explicit raw)
//   5: we=1 raw=0 wdata=FF
//
`timescale 1ns/1ps

module tb_softcpu_trig;

    reg clk_sys = 0;
    reg reset   = 1;

    // 50 MHz sys clock; the subsystem divides it to clk_pico internally.
    always #10 clk_sys = ~clk_sys;

    // Firmware write port — injects the micro-program into the ROM.
    reg        fw_wr_en   = 0;
    reg [13:0] fw_wr_addr = 0;
    reg [31:0] fw_wr_data = 0;

    // st_done model: a service op "runs" for six clk_pico cycles.
    reg        st_done_r  = 0;
    reg  [3:0] dcnt       = 0;
    reg  [7:0] st_rdata_r = 8'h5A;

    wire clk_pico;
    wire        st_req, st_we, st_raw;
    wire [19:0] st_addr;
    wire  [7:0] st_wdata;

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
        .target_dataslot_read  (),
        .target_dataslot_write (),
        .target_dataslot_id    (),
        .target_dataslot_slotoffset (),
        .target_dataslot_bridgeaddr (),
        .target_dataslot_length (),
        .target_dataslot_ack  (1'b0),
        .target_dataslot_done (1'b0),
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
        .gdc_draw_req   (2'b00),
        .gdc_draw_busy  (2'b00),
        .gdc_draw_ops   (16'd0),
        .gdc_draw_snaps (384'd0),
        .gdc_srv_done_levels (),
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

    // Micro-program, word-indexed (fw_wr_addr is a WORD address into the
    // 14-bit ROM). Assembled by hand; RV32I, no compressed, no IRQs.
    task fw_word(input [13:0] a, input [31:0] d);
        begin
            @(posedge clk_sys);
            fw_wr_addr <= a;
            fw_wr_data <= d;
            fw_wr_en   <= 1;
            @(posedge clk_sys);
            fw_wr_en   <= 0;
        end
    endtask

    integer nlaunch = 0;
    integer errors  = 0;
    reg st_req_q = 0;

    // {we, raw, wdata} expected per launch, packed for a case-index
    // compare. The launch's raw/we come from the trigger byte; wdata is
    // the operand register (set by the 0x5000_0004 store). Launch 3 is the
    // wdata-lag probe: 0xFF in the operand register means ANY bleed into
    // the trigger's launch shows up as raw=1.
    //
    // st_wdata is also the witness-park wire: when an op's st_done lands
    // the subsystem copies st_tbyte (the byte cpu_mem_wdata carried at
    // the launch) into it, so a launch made WITHOUT a fresh operand
    // store reads the PREVIOUS launch's trigger byte back. Launches
    // 2/4/5 therefore expect 0x01/0x01/0x05 -- and launch 5 seeing 0x05
    // is itself the proof that the park path surfaces a raw trigger.
    function automatic [9:0] exp_launch(input integer n);
        case (n)
            1: exp_launch = {1'b1, 1'b0, 8'hAA}; // trig=1, operand AA
            2: exp_launch = {1'b0, 1'b0, 8'h01}; // trig=2; parks L1's byte
            3: exp_launch = {1'b1, 1'b0, 8'hFF}; // operand FF then trig=1
            4: exp_launch = {1'b1, 1'b1, 8'h01}; // trig=5; parks L3's byte
            5: exp_launch = {1'b1, 1'b0, 8'h05}; // trig=1; parks L4's byte
            default: exp_launch = 10'd0;
        endcase
    endfunction

    // Log every service launch (rising edge of st_req), plus the fall, and
    // every CPU store into the 0x5xxxxxxx window with its wdata -- the
    // actual bus view behind the wdata-lag theory.
    always @(posedge clk_pico) begin
        reg [9:0] exp;
        st_req_q <= st_req;
        if (st_req && !st_req_q) begin
            nlaunch <= nlaunch + 1;
            exp = exp_launch(nlaunch + 1);
            $display("%0t LAUNCH %0d: addr=%05x wdata=%02x we=%0d raw=%0d",
                     $time, nlaunch + 1, st_addr, st_wdata, st_we, st_raw);
            if (st_addr !== 20'h04008 ||
                {st_we, st_raw, st_wdata} !== exp) begin
                errors <= errors + 1;
                $display("%0t   ^^ MISMATCH: expected we=%0d raw=%0d wdata=%02x",
                         $time, exp[9], exp[8], exp[7:0]);
            end
        end
        if (!st_req && st_req_q)
            $display("%0t   st_req fell (st_done)", $time);
        if (dut.cpu_mem_valid && |dut.cpu_mem_wstrb &&
            dut.cpu_mem_addr[31:24] == 8'h50)
            $display("%0t   store: addr=%08x wdata=%08x wstrb=%b ready=%b trig=%b",
                     $time, dut.cpu_mem_addr, dut.cpu_mem_wdata,
                     dut.cpu_mem_wstrb, dut.cpu_mem_ready, dut.st_trig);
        else if (dut.cpu_mem_valid)
            $display("%0t   xfer : addr=%08x instr=%b wstrb=%b ready=%b state=%0d do=%b%b%b%b",
                     $time, dut.cpu_mem_addr, dut.cpu_mem_instr,
                     dut.cpu_mem_wstrb, dut.cpu_mem_ready,
                     dut.pico.mem_state,
                     dut.pico.mem_do_prefetch, dut.pico.mem_do_rinst,
                     dut.pico.mem_do_rdata, dut.pico.mem_do_wdata);
        if ($time > 9250000 && $time < 12000000 && !dut.cpu_mem_valid)
            $display("%0t   idle : cstate=%0d mstate=%0d valid=%b ready=%b do=%b%b%b%b trap=%b pc=%08x",
                     $time, dut.pico.cpu_state, dut.pico.mem_state,
                     dut.cpu_mem_valid, dut.cpu_mem_ready,
                     dut.pico.mem_do_prefetch, dut.pico.mem_do_rinst,
                     dut.pico.mem_do_rdata, dut.pico.mem_do_wdata,
                     dut.cpu_trap, dut.pico.reg_pc);
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

    initial begin
        reg [31:0] prog [0:63];
        integer i;
        // Hand-assembled; see header for expected launches.
        prog[ 0] = 32'h50000FB7; // lui  t6,0x50000
        prog[ 1] = 32'h000042B7; // lui  t0,0x4
        prog[ 2] = 32'h00828293; // addi t0,t0,8
        prog[ 3] = 32'h005FA023; // sw   t0,0(t6)    ST_ADDR=0x4008
        prog[ 4] = 32'h0AA00293; // li   t0,0xAA
        prog[ 5] = 32'h005FA223; // sw   t0,4(t6)    ST_WDATA=0xAA
        prog[ 6] = 32'h00100313; // li   t1,1
        prog[ 7] = 32'h006FA423; // sw   t1,8(t6)    TRIG=1
        prog[ 8] = 32'h01000393; // li   t2,60
        prog[ 9] = 32'hFFF38393; // addi t2,t2,-1
        prog[10] = 32'hFE039EE3; // bne  t2,x0,-4
        prog[11] = 32'h00200313; // li   t1,2
        prog[12] = 32'h006FA423; // sw   t1,8(t6)    TRIG=2 (read)
        prog[13] = 32'h01000393;
        prog[14] = 32'hFFF38393;
        prog[15] = 32'hFE039EE3;
        prog[16] = 32'h0FF00293; // li   t0,0xFF
        prog[17] = 32'h005FA223; // sw   t0,4(t6)    ST_WDATA=0xFF
        prog[18] = 32'h00100313; // li   t1,1
        prog[19] = 32'h006FA423; // sw   t1,8(t6)    TRIG=1 (bleed probe)
        prog[20] = 32'h01000393;
        prog[21] = 32'hFFF38393;
        prog[22] = 32'hFE039EE3;
        prog[23] = 32'h00500313; // li   t1,5
        prog[24] = 32'h006FA423; // sw   t1,8(t6)    TRIG=5 (explicit raw)
        prog[25] = 32'h01000393;
        prog[26] = 32'hFFF38393;
        prog[27] = 32'hFE039EE3;
        prog[28] = 32'h00100313; // li   t1,1
        prog[29] = 32'h006FA423; // sw   t1,8(t6)    TRIG=1
        prog[30] = 32'h01000393;
        prog[31] = 32'hFFF38393;
        prog[32] = 32'hFE039EE3;
        prog[33] = 32'h0000006F; // j    .

        for (i = 34; i < 64; i = i + 1)
            prog[i] = 32'h00000013; // nop

        // Hold reset while the image loads.
        repeat (4) @(posedge clk_sys);
        for (i = 0; i < 64; i = i + 1)
            fw_word(i[13:0], prog[i]);
        repeat (8) @(posedge clk_sys);

        reset <= 0;

        // Let the program run to completion; the launch monitor prints.
        repeat (30000) @(posedge clk_sys);

        $display("DONE: %0d launches, %0d mismatches", nlaunch, errors);
        $display("final: raw=%0d we=%0d addr=%05x wdata=%02x",
                 st_raw, st_we, st_addr, st_wdata);
        if (nlaunch != 5 || errors != 0)
            $display("RESULT: FAIL");
        else
            $display("RESULT: PASS");
        $finish;
    end

endmodule
