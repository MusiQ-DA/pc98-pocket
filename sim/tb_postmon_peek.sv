//
// tb_postmon_peek -- why the POST monitor's ROM compare read BAD 0EC on
// hardware while the guest booted the same ROM fine.
//
// The peek (sdram_peek, the sdram_selftest_master) is a diagnostic window
// onto the image the LOADER wrote at a guest address. postmon_capture_rom
// peeks FD800 with the guest still held and compares against the BIOS image.
// With PC98_BOOT_ITF the machine powers up with the ITF bank selected, so
// RAM.sv's shadow overlay -- which exists to make the same guest addresses
// F8000-FFFFF hold two different ROMs -- applied to the PEEK as well: it read
// the ITF copy at physical 1FD800. The ITF image is zero padding from file
// offset 0x5800 up, so all 256 bytes came back 00, and exactly the 20 bytes
// the BIOS entry itself holds as 00 "matched": BAD 0EC, AT 000, GOT all
// zeros -- the hardware readout, reproduced here byte for byte.
//
// The two builds of this bench:
//
//   default          core_top's FIXED flag mux: the master reads the main
//                    bank. BAD must be 000.
//   +define+REPRO_OLD_SHADOW
//                    core_top's mux BEFORE the fix. BAD must be 0EC with
//                    GOT all zeros -- if it is not, this bench does not model
//                    the fault and its PASS proves nothing.
//
// Everything between the master and the DRAM is the shipped RTL: the real
// sdram_selftest_master, the real BUS_ARBITER (CPU parked on hold
// acknowledge, the way the guest-held capture runs it), the real RAM.sv with
// MACHINE_PC98's shadow, and the board-timing SDRAM model. Only the ext-port
// muxes are the bench's, and they are wired the way core_top wires them.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_postmon_peek;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    // 8088-style cadence for the arbiter's ce strobes; the CPU itself stays
    // parked (status passive), which is what SOFT_GUEST_HOLD looks like from
    // the bus side.
    logic cpu_ce_posedge = 0, cpu_ce_negedge = 0;
    int   ce_div = 0;
    always @(posedge clock) begin
        ce_div <= (ce_div == 8) ? 0 : ce_div + 1;
        cpu_ce_posedge <= (ce_div == 0);
        cpu_ce_negedge <= (ce_div == 4);
    end
    localparam logic [2:0] STATUS_PASSIVE = 3'b111;

    // ------------------------------------------------------------- the images
    //
    // bios_head: the committed firmware reference (postmon.c bios_head), which
    // is the PC-9801UX BIOS at file offset 0x15800 -- what the loader writes
    // at guest FD800 in the MAIN bank and what the panel compares against.
    logic [7:0] bios_head [0:255];
    initial $readmemh("postmon_bios_head.hex", bios_head);

    // PC98_BOOT_ITF: the machine powers up with the ITF bank selected.
    logic itf_bank = 1'b1;

    // ------------------------------------------------- the ext-port masters
    //
    // Two of them, exactly as core_top sees it: the BIOS loader (which owns
    // the port while a slot streams) and the self-test master. They never
    // overlap -- the master's grant requires ~loader_busy -- but the muxes
    // below are the shared-port wiring core_top drives, not a bypass.
    logic [19:0] ld_addr      = 20'hFFFFF;
    logic  [7:0] ld_wdata     = 8'hFF;
    logic        ld_req       = 1'b0;
    logic        ld_wr_n      = 1'b1;
    logic        ld_shadow    = 1'b0;   // bios_shadow_write: ITF words -> shadow

    logic [19:0] st_addr_v    = 20'd0;
    logic  [7:0] st_wdata_v   = 8'd0;
    logic        st_we_v      = 1'b0;
    logic        st_req_v     = 1'b0;
    wire         st_done;
    wire  [7:0]  st_rdata;
    wire         st_run, st_wr_n, st_rd_n;

    sdram_selftest_master u_master (
        .clk              (clock),
        .rst              (reset),
        .req              (st_req_v),
        .we               (st_we_v),
        .addr             (st_addr_v),
        .wdata            (st_wdata_v),
        .done             (st_done),
        .rdata            (st_rdata),
        .initilized_sdram (initilized_sdram),
        .loader_busy      (ld_req),               // ioctl_download
        .bus_granted      (address_enable_n),     // HLDA: ext owns the address mux
        .run              (st_run),
        .write_n          (st_wr_n),
        .read_n           (st_rd_n),
        .ram_rw_complete  (ram_rw_complete),
        .ext_rdata        (ram_data_out)
    );

    // core_top's ext-port muxes (see the CHIPSET instance there):
    //   .address_ext        (st_run ? st_addr : bios_access_address),
    //   .ext_access_request (st_run | bios_access_request),
    //   .data_bus_ext       (st_run ? st_wdata : bios_write_data[7:0]),
    //   .memory_write_n_ext (st_run ? st_wr_n : bios_write_n),
    //   .memory_read_n_ext  (st_rd_n),
    wire [19:0] address_ext      = st_run ? st_addr_v : ld_addr;
    wire        ext_access_req   = st_run | ld_req;
    wire  [7:0] data_bus_ext     = st_run ? st_wdata_v : ld_wdata;
    wire        memory_write_ext = st_run ? st_wr_n    : ld_wr_n;

    // The shadow-flag mux, mirroring core_top's bios_shadow_flag.
`ifdef REPRO_OLD_SHADOW
    // core_top BEFORE the fix: every reader followed the guest's bank bit.
    wire bios_shadow_flag = ld_wr_n ? itf_bank : ld_shadow;
`else
    // core_top AFTER the fix: the self-test master reads the MAIN bank. Keep
    // this line identical to the one in core_top's MACHINE_PC98 branch.
    wire bios_shadow_flag = st_run ? 1'b0 :
                           ld_wr_n ? itf_bank : ld_shadow;
`endif

    // A standing check that the fix did not move the GUEST's view: whenever
    // both masters are idle the flag is the guest's bank bit again.
    int flag_errors = 0;
    always @(posedge clock) begin
        if (!reset && !st_run && ld_wr_n && (bios_shadow_flag !== itf_bank))
            flag_errors++;
    end

    // ------------------------------------------------------------ BUS_ARBITER
    wire [19:0] address;
    wire  [7:0] internal_data_bus;
    wire        memory_read_n, memory_write_n, no_command_state;
    wire        address_direction, data_bus_direction;
    wire        io_read_n, io_write_n;
    wire        io_read_n_direction, io_write_n_direction;
    wire        memory_read_n_direction, memory_write_n_direction;
    wire        address_latch_enable, interrupt_acknowledge_n;
    wire        processor_transmit_or_receive_n, dma_wait_n;
    wire  [3:0] dma_acknowledge_n;
    wire        address_enable_n, terminal_count_n;

    BUS_ARBITER u_arb (
        .clock(clock),
        .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(cpu_ce_negedge),
        .reset(reset),
        .cpu_address(20'd0),
        .cpu_data_bus(8'd0),
        .processor_status(STATUS_PASSIVE),
        .processor_lock_n(1'b1),
        .processor_transmit_or_receive_n(processor_transmit_or_receive_n),
        .dma_ready(1'b1),
        .dma_wait_n(dma_wait_n),
        .interrupt_acknowledge_n(interrupt_acknowledge_n),
        .dma_chip_select_n(1'b1),
        .dma_page_chip_select_n(1'b1),
        .address(address),
        .address_ext(address_ext),
        .address_direction(address_direction),
        .data_bus_ext(data_bus_ext),
        .internal_data_bus(internal_data_bus),
        .data_bus_direction(data_bus_direction),
        .address_latch_enable(address_latch_enable),
        .io_read_n(io_read_n),
        .io_read_n_ext(1'b1),
        .io_read_n_direction(io_read_n_direction),
        .io_write_n(io_write_n),
        .io_write_n_ext(1'b1),
        .io_write_n_direction(io_write_n_direction),
        .memory_read_n(memory_read_n),
        .memory_read_n_ext(st_rd_n),
        .memory_read_n_direction(memory_read_n_direction),
        .memory_write_n(memory_write_n),
        .memory_write_n_ext(memory_write_ext),
        .memory_write_n_direction(memory_write_n_direction),
        .no_command_state(no_command_state),
        .ext_access_request(ext_access_req),
        .dma_request(4'd0),
        .dma_acknowledge_n(dma_acknowledge_n),
        .address_enable_n(address_enable_n),
        .terminal_count_n(terminal_count_n),
        .dbg_hold(),
        .dbg_dmac()
    );

    // ------------------------------------------------------------------- RAM
    wire  [7:0] ram_data_out;
    wire        ram_rw_complete, memory_access_ready, ram_address_select_n;
    logic       initilized_sdram;
    wire [12:0] s_a; wire [1:0] s_ba;
    wire s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [6:0] unused_map [0:3] = '{7'd0, 7'd0, 7'd0, 7'd0};

    RAM u_ram (
        .clock(clock), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(address), .internal_data_bus(internal_data_bus),
        .data_bus_out(ram_data_out),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .no_command_state(no_command_state),
        .memory_access_ready(memory_access_ready),
        .access_complete(ram_rw_complete),
        .ram_address_select_n(ram_address_select_n),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .map_ems(unused_map),
        .ems_b1(1'b0), .ems_b2(1'b0), .ems_b3(1'b0), .ems_b4(1'b0),
        .bios_protect_flag(2'b00),          // loader writes with protect clear
        .font_bank_flag(1'b0),
        .font_rd_req(1'b0), .font_rd_addr(24'd0), .font_rd_len(4'd0),
        .font_rd_ack(), .font_rd_valid(), .font_rd_data(), .font_rd_done(),
        .cg_rd_req(1'b0), .cg_rd_addr(24'd0), .cg_rd_len(4'd0),
        .cg_rd_ack(), .cg_rd_valid(), .cg_rd_data(), .cg_rd_done(),
        .bios_shadow_flag(bios_shadow_flag),
        .wait_count_clk_en(1'b1),
        .ram_read_wait_cycle(2'd0), .ram_write_wait_cycle(2'd0)
    );

    sdram_board_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                        .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clock), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ---------------------------------------------------------------- tasks
    //
    // core_top's loader OWNS the ext port for the whole slot (states 01-04 all
    // hold bios_access_request high), so BUS_ARBITER's address_enable_n stays
    // inactive and `address` follows address_ext for every byte. Dropping the
    // request between bytes lets hold_acknowledge fall, address_enable_n go
    // active and the next write go out with the CPU's (parked, zero) address
    // instead -- half the image lands on guest 0. So: take the port once per
    // image, strobe the bytes, give it back.
    task automatic loader_begin;
        ld_req = 1'b1;
        // Wait for HLDA properly: the hold chain needs up to ~27 clk (two
        // cpu_ce periods) after the request before the arbiter's address mux
        // selects address_ext. A fixed wait races it and the slot's first byte
        // goes out at the parked CPU's address.
        wait (address_enable_n);
        repeat (2) @(posedge clock);
    endtask

    task automatic loader_end;
        ld_req = 1'b0;
        repeat (8) @(posedge clock);
    endtask

    // One byte write, in core_top's own shape (state 02): hold the strobe
    // until RAM.sv reports completion, then a short settle before the next
    // byte.
    task automatic loader_write(input logic [19:0] a, input logic [7:0] d,
                                input bit shadow);
        ld_addr = a; ld_wdata = d; ld_shadow = shadow;
        ld_wr_n = 1'b0;
        forever begin
            @(posedge clock);
            if (ram_rw_complete) break;
        end
        ld_wr_n = 1'b1;
        repeat (3) @(posedge clock);
    endtask

    // sdram_peek, in the firmware's shape: set the address, trigger a read,
    // poll ST_STATUS for !busy -- here, wait for the master's done level and
    // take the byte it latched.
    task automatic st_read(input logic [19:0] a, output logic [7:0] q);
        st_addr_v = a; st_we_v = 1'b0; st_req_v = 1'b1;
        wait (st_done);
        q = st_rdata;
        st_req_v = 1'b0;
        wait (!st_done);
        repeat (8) @(posedge clock);
    endtask

    // ------------------------------------------------------------ the verdict
    int rom_bad = 0;
    int rom_first = 256;
    logic [7:0] got8 [0:7];
    logic [7:0] q;

    // What each probe should return from each bank, so the printout names the
    // bank by itself. FFFF0: the ITF's own reset vector EA 00 00 00 F8 (which
    // is why "FFFF0 came back byte-perfect" while FD800 read as empty -- both
    // were the shadow); the BIOS's patched vector is EA 00 00 80 FD. F800E0:
    // real image bytes at both file offsets.
    localparam logic [7:0] ITF_FFFF0 [0:4] = '{8'hEA, 8'h00, 8'h00, 8'h00, 8'hF8};
    localparam logic [7:0] BIOS_FFFF0[0:4] = '{8'hEA, 8'h00, 8'h00, 8'h80, 8'hFD};
    localparam logic [7:0] ITF_F800E0[0:7] = '{8'h04, 8'hB0, 8'h00, 8'hEE, 8'hBD, 8'h2F, 8'h05, 8'hB0};
    localparam logic [7:0] BIOS_F800E0[0:7]= '{8'h80, 8'h3E, 8'h20, 8'h06, 8'h03, 8'h74, 8'h72, 8'hA0};

    int errors = 0;
    logic [7:0] f0 [0:4];
    logic [7:0] e0 [0:7];

    initial begin
`ifdef REPRO_OLD_SHADOW
        $display("=== postmon ROM peek, core_top BEFORE the fix (must reproduce BAD 0EC) ===");
`else
        $display("=== postmon ROM peek, core_top AFTER the fix (must read BAD 000) ===");
`endif
        repeat (8) @(posedge clock);
        reset = 0;
        wait (initilized_sdram);
        $display("sdram initialised");

        // ---- the loader, doing what it does to the real card: BIOS.ROM's
        // FD800 window into the main bank, ITF.ROM's zero padding (file
        // offset 0x5800 up is all 00) and its reset vector into the shadow.
        loader_begin();
        for (int i = 0; i < 256; i++)
            loader_write(20'hFD800 + i, bios_head[i], 1'b0);
        for (int i = 0; i < 256; i++)
            loader_write(20'hFD800 + i, 8'h00, 1'b1);      // itf.rom @ 0x5800
        for (int i = 0; i < 5; i++) begin
            loader_write(20'hFFFF0 + i, BIOS_FFFF0[i], 1'b0); // rom_patch_reset
            loader_write(20'hFFFF0 + i, ITF_FFFF0[i],  1'b1);
        end
        for (int i = 0; i < 8; i++) begin
            loader_write(20'hF80E0 + i, BIOS_F800E0[i], 1'b0);
            loader_write(20'hF80E0 + i, ITF_F800E0[i],  1'b1);
        end
        loader_end();
        $display("images loaded: BIOS head at FD800 (main), ITF zeros at 1FD800 (shadow)");

        // ---- postmon_capture_rom, verbatim in shape: 256 peeks at FD800
        // against the firmware's table, then the first eight GOT bytes.
        for (int i = 0; i < 256; i++) begin
            st_read(20'hFD800 + i, q);
            if (q !== bios_head[i]) begin
                rom_bad++;
                if (rom_first == 256) rom_first = i;
            end
        end
        for (int i = 0; i < 8; i++)
            st_read(20'hFD800 + ((rom_first < 256) ? rom_first : 0) + i, got8[i]);

        $write("  BAD %03h AT %03h GOT", rom_bad, rom_first);   // AT 100 = none, as the panel shows
        for (int i = 0; i < 8; i++) $write(" %02h", got8[i]);
        $write("  FILE");
        for (int i = 0; i < 8; i++)
            $write(" %02h", bios_head[((rom_first < 256) ? rom_first : 0) + i]);
        $display("");

        // ---- the two probes that name the bank: whose reset vector and
        // whose code does FD800's page-mate hold?
        for (int i = 0; i < 5; i++) st_read(20'hFFFF0 + i, f0[i]);
        for (int i = 0; i < 8; i++) st_read(20'hF80E0 + i, e0[i]);
        $write("  FFFF0:");
        for (int i = 0; i < 5; i++) $write(" %02h", f0[i]);
        $write("   F800E0:");
        for (int i = 0; i < 8; i++) $write(" %02h", e0[i]);
        $display("");

`ifdef REPRO_OLD_SHADOW
        // The hardware symptom: all-zero GOT (the ITF's padding), 236
        // mismatches -- 256 minus the 20 bytes the BIOS entry holds as 00 --
        // first at 000, and both probes landing in the shadow bank.
        if (rom_bad != 236) begin
            errors++;
            $display("  expected BAD 0EC (236), got %0d", rom_bad);
        end
        if (rom_first != 0) begin
            errors++;
            $display("  expected AT 000, got %03h", rom_first);
        end
        foreach (got8[i]) if (got8[i] !== 8'h00) begin
            errors++;
            $display("  expected GOT all zeros (ITF padding), byte %0d = %02h", i, got8[i]);
        end
        foreach (f0[i]) if (f0[i] !== ITF_FFFF0[i]) begin
            errors++;
            $display("  expected the peek to hit the ITF shadow at FFFF0, byte %0d", i);
        end
        foreach (e0[i]) if (e0[i] !== ITF_F800E0[i]) begin
            errors++;
            $display("  expected the peek to hit the ITF shadow at F800E0, byte %0d", i);
        end
`else
        // The fix: the main bank. The compare passes, and the probes read the
        // BIOS image -- the loader-patched reset vector, not the ITF's.
        if (rom_bad != 0) begin
            errors++;
            $display("  expected BAD 000, got %0d (first at %03h)", rom_bad, rom_first);
        end
        foreach (f0[i]) if (f0[i] !== BIOS_FFFF0[i]) begin
            errors++;
            $display("  expected the peek to hit the main bank at FFFF0, byte %0d", i);
        end
        foreach (e0[i]) if (e0[i] !== BIOS_F800E0[i]) begin
            errors++;
            $display("  expected the peek to hit the main bank at F800E0, byte %0d", i);
        end
`endif

        // The guest's own view must be untouched by all of this: the shadow
        // still follows itf_bank whenever the master is idle.
        if (flag_errors != 0) begin
            errors++;
            $display("  bios_shadow_flag left the guest's bank view %0d cycles", flag_errors);
        end

        $display("\n=== summary ===");
        $display("  shadow-view disturbances : %0d", flag_errors);
        $display("  sdram protocol violations: %0d", sdr.u_part.violations);
        if (sdr.u_part.violations != 0) errors++;
        if (errors == 0)
`ifdef REPRO_OLD_SHADOW
            $display("  RESULT: PASS -- hardware symptom reproduced; the fault is the shadow overlay");
`else
            $display("  RESULT: PASS -- the peek reads the main bank, BAD 000");
`endif
        else
            $display("  RESULT: FAIL -- %0d errors", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("GLOBAL TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
