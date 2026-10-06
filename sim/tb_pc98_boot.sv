//
// tb_pc98_boot -- run the real ITF on the real CPU core, and watch where it
// goes.
//
// The CPU is the Zet through zet_cpu_bridge. The same flat memory and the
// same I/O models see the bridge's bus cycles, so this is the end-to-end
// dress rehearsal of the hardware CPU path (i8288 + 8-bit bus + real ROMs +
// 8251) before the bitstream.
//
// The hardware says BANK 1: the ITF bank register is still at its reset value,
// so the guest has never executed OUT 043D, 12. Everything upstream of that is
// healthy -- the ROMs load, the softcore runs, the raster runs -- so the
// question is what the ITF does instead, and that is an execution question, not
// a hardware one.
//
// This is the machine reduced to what the question needs: the CPU core, the
// clock-enable generator and the bus controller exactly as core_top wires them,
// the address latch, and one flat megabyte of memory with the two ROM images in
// it. No chipset, no peripherals, no SDRAM -- every one of those has its own
// bench, and none of them decides where the CPU goes.
//
// The bank switch is modelled the way core_top models it (port 0x043D, 0x10 ->
// ITF, 0x12 -> BIOS, reset value 1) because that is the thing being explained.
//
// Not a CI test: it needs bios.rom and itf.rom, which are not in the tree. Run
// it with scripts/sim_pc98_boot.sh, which converts them and invokes verilator.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_boot;

    // clk_chipset is 42.954545 MHz, as core_top's PLL makes it.
    logic clk_chipset = 1'b0;
    // DERIVED, not a rounded literal. 11.641 drifts 0.0016 ns per cycle against
    // sdram_board_model's CLK_MHZ-derived device clock -- a whole period by
    // cycle 14800 -- and under REALMEM that manufactures read failures that are
    // not in the RTL. It did exactly that once, on the old V30 mem bench.
    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    always #(HALF_NS) clk_chipset = ~clk_chipset;

    logic reset = 1'b1;
    // OUT 0F0h resets the CPU and nothing else: memory keeps its contents and
    // the ROM bank keeps its selection, which is what the ITF's resume needs.
    logic       f0_prev_wr_n = 1'b1;
    logic       f0_prev_rd_n = 1'b1;
    logic       soft_reset_cpu = 1'b0;
    logic [7:0] soft_reset_count = 8'h00;
    // Under REALMEM the controller needs its init sequence (about 233 us) before
    // it can answer a fetch, so the CPU is held past it the way core_top holds
    // it behind initilized_sdram. `reset` itself must be released for the
    // controller to start, so this is a separate hold, not a longer reset.
`ifdef REALMEM
    wire        cpu_reset_w = reset | soft_reset_cpu | ~sdram_up;
    logic       sdram_up = 1'b0;
    always_ff @(posedge clk_chipset)
        if (initilized_sdram_w) sdram_up <= 1'b1;
`else
    wire        cpu_reset_w = reset | soft_reset_cpu;
`endif

    // ---- clock enables and the CPU pin clock -------------------------------
    wire       cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire [1:0] ram_rd_wait, ram_wr_wait;
    wire       biu_done;

    // +speed=N overrides the firmware-default CE rate (2'b10). Speed 0 is
    // the ~4.9 MHz setting the real hardware wedges on in cold POST.
    logic [1:0] clk_select_r = 2'b10;
    initial if ($value$plusargs("speed=%d", clk_select_r))
        $display("clk_select override: %d", clk_select_r);

    ce_generator u_ce (
        .clock                              (clk_chipset),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        // 9.54 MHz -- what the shipped firmware now boots with, and 2x the
        // old 4.77 default. The memory test is CPU-bound, so this halves the
        // chipset edges the same guest progress costs: the boot that took 40
        // wall minutes to reach the reset at 18.5 s of guest time should take
        // twenty. Timer-fed delays still take their full guest time, which is
        // the honest trade: the machine itself is faster, not the clocks.
        .clk_select                         (clk_select_r), // the firmware default (PC-98: 19.66 MHz)
        .cpu_clk_pin                        (),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .cycle_accrate                      (),
        .clock_cycle_counter_division_ratio  (),
        .clock_cycle_counter_decrement_value (),
        .shift_read_timing                  (),
        .ram_read_wait_cycle                (ram_rd_wait),
        .ram_write_wait_cycle               (ram_wr_wait), .vram_wait_en()
    );

    // ---- the CPU -----------------------------------------------------------
    wire [19:0] cpu_ad_out;
    wire  [7:0] cpu_data_bus;
    wire  [7:0] cpu_data_bus_hi;
    wire        cpu_word_access;
    wire  [7:0] din;
    wire  [2:0] processor_status;
    wire        lock_n;

    // bus-hold injection signals -- declared here because the bridge consumes
    // test_aen above the machinery that produces it.
    logic        freeze_req = 1'b0;
    logic        frz_ff1 = 1'b0, frz_ff2 = 1'b0;
    logic        test_aen = 1'b0;      // granted-to-hold, like the arbiter's
    logic        dma_wait_b = 1'b0;
    logic        cpu_rst_d = 1'b1;
    logic [39:0] clk_since_rst = 40'd0;
    logic [39:0] frz_start_clk = 40'd0, frz_end_clk = 40'd0;

    // The CPU + bridge, wired the way core_top wires them.
    wire [223:0] dbg_regs;
    wire        dbg_first_pop, dbg_pend;

    wire        zet_clk;
    wire [15:0] zwb_dat_i, zwb_dat_o;
    wire [19:1] zwb_adr;
    wire        zwb_we, zwb_tga, zwb_stb, zwb_cyc, zwb_ack;
    wire [ 1:0] zwb_sel;
    wire        zwb_inta, zwb_nmia;
    wire [19:0] zet_pc;
    wire        zet_fault;
    wire [7:0]  zet_opc;
    wire [15:0] zbridge_dbg;

    zet_cpu_bridge u_bridge (
        .clk               (clk_chipset),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .fast_pace         (clk_select_r[1]),
        .reset             (cpu_reset_w),
        .zet_clk           (zet_clk),
        .wb_dat_o          (zwb_dat_o),
        .wb_dat_i          (zwb_dat_i),
        .wb_adr_o          (zwb_adr),
        .wb_we_o           (zwb_we),
        .wb_tga_o          (zwb_tga),
        .wb_sel_o          (zwb_sel),
        .wb_stb_o          (zwb_stb),
        .wb_cyc_o          (zwb_cyc),
        .wb_ack_i          (zwb_ack),
        .wb_tgc_o          (zwb_inta),
        .nmia              (zwb_nmia),
        .processor_status  (processor_status),
        .ad_out            (cpu_ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (lock_n),
        .analog_mode       (1'b0),
        .word_access       (cpu_word_access),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (din_hi),
        .data_bus          (din),
        .processor_ready   (bench_ready),
        .address_enable_n  (test_aen),
        .pause_core        (1'b0),
        .biu_done          (biu_done),
        .dbg               (zbridge_dbg)
    );

    zet u_cpu (
        .wb_clk_i  (zet_clk),
        .wb_rst_i  (cpu_reset_w),
        .wb_dat_i  (zwb_dat_i),
        .wb_dat_o  (zwb_dat_o),
        .wb_adr_o  (zwb_adr),
        .wb_we_o   (zwb_we),
        .wb_tga_o  (zwb_tga),
        .wb_sel_o  (zwb_sel),
        .wb_stb_o  (zwb_stb),
        .wb_cyc_o  (zwb_cyc),
        .wb_ack_i  (zwb_ack),
        .wb_tgc_i  (pic1_to_cpu),
        .wb_tgc_o  (zwb_inta),
        .nmi       (1'b0),
        .nmia      (zwb_nmia),
        .pc        (zet_pc),
        .dbg_fault (zet_fault),
        .dbg_opc   (zet_opc)
    );

    // End-to-end readback: every acked Wishbone memory read must equal the
    // architectural byte the guest was meant to see (mirror/ROM model). A
    // stale-byte or dropped-command completion in the bridge path shows up
    // here even when the cycle looked protocol-clean from outside. C0000-
    // E7FFF is open bus on the machine, so it is outside the check.
`ifdef REALMEM
    // Graphics-path state, declared ahead of in_e2e_check (declared later at
    // the datapath it drives).
    logic       pc98_analog_q = 1'b0;
    logic       access_page_q = 1'b0;
    wire        grcg_active;
`endif
    int          ack_rd_mismatches = 0;
    logic [19:0] ack_bad_addr = 20'h0;
    function automatic logic [7:0] expected_byte(input logic [19:0] a);
        if (is_rom(a))       expected_byte = rom_byte(a);
        else if (is_xrom(a)) expected_byte = xrom_byte(a);
        else                 expected_byte = ram[a];
    endfunction
    function automatic logic in_e2e_check(input logic [19:0] a);
`ifdef REALMEM
        // A graphics-window read the sequencer expanded answers with a
        // transform (TCR/EGC), not the stored byte -- uncheckable flat.
        logic in_gv;
        in_gv = (a[19:15] == 5'b10101) | (a[19:16] == 4'hB)
              | (pc98_analog_q & (a[19:15] == 5'b11100));
        in_e2e_check = ((a < 20'hC0000) | (a >= 20'hE8000))
                     & ~(in_gv & (grcg_active | access_page_q));
`else
        in_e2e_check = (a < 20'hC0000) | (a >= 20'hE8000);
`endif
    endfunction
    always_ff @(posedge clk_chipset) begin
        if (zwb_ack && !zwb_we && !zwb_tga) begin
            if (zwb_sel[0] && in_e2e_check({zwb_adr, 1'b0})
                && zwb_dat_i[7:0] !== expected_byte({zwb_adr, 1'b0})) begin
                ack_rd_mismatches++;
                ack_bad_addr <= {zwb_adr, 1'b0};
                if (ack_rd_mismatches <= 20)
                    $display("  %8t  E2E lo [%05X] gave %02X, want %02X  (zet_pc %05X)",
                             $time, {zwb_adr, 1'b0}, zwb_dat_i[7:0],
                             expected_byte({zwb_adr, 1'b0}), zet_pc);
            end
            if (zwb_sel[1] && in_e2e_check({zwb_adr, 1'b1})
                && zwb_dat_i[15:8] !== expected_byte({zwb_adr, 1'b1})) begin
                ack_rd_mismatches++;
                ack_bad_addr <= {zwb_adr, 1'b1};
                if (ack_rd_mismatches <= 20)
                    $display("  %8t  E2E hi [%05X] gave %02X, want %02X  (zet_pc %05X)",
                             $time, {zwb_adr, 1'b1}, zwb_dat_i[15:8],
                             expected_byte({zwb_adr, 1'b1}), zet_pc);
            end
        end
    end

    // The decode-side witness core_top ships to probe slot 0x38: log the
    // first INVOP/INTD with the PC it faulted on and the byte it decoded,
    // so a sim corruption event is directly comparable to the JTAG read.
    int zet_fault_count = 0;
    always_ff @(posedge clk_chipset)
        if (zet_fault) begin
            zet_fault_count++;
            if (zet_fault_count <= 10)
                $display("  %8t  ZET FAULT #%0d  pc=%05X opc=%02X (rom %02X)",
                         $time, zet_fault_count, zet_pc, zet_opc,
                         expected_byte(zet_pc));
        end

    // Zet has no dbg_regs: the trace fields read 0, eu_pc below reads the
    // core's real linear-PC debug pin instead.
    assign dbg_regs = '0;
    assign dbg_first_pop = 1'b0;
    assign dbg_pend = 1'b0;

    // ---- the register view: one local name per quantity --------------------
    // (the core's dbg_regs view, retired-instruction granularity)
    wire [15:0] eu_ax = dbg_regs[15:0];
    wire [15:0] eu_bx = dbg_regs[63:48];
    wire [15:0] eu_dx = dbg_regs[47:32];
    wire [15:0] eu_si = dbg_regs[111:96];
    wire [15:0] eu_di = dbg_regs[127:112];
    wire [15:0] eu_sp = dbg_regs[79:64];
    wire [15:0] eu_ss = dbg_regs[175:160];
    wire        eu_cf = dbg_regs[208];

    // ---- bus-hold injection ------------------------------------------------
    //
    // The verifier walk's hold, faithfully: +freeze_start_us / +freeze_len_us
    // pick the window, measured in chipset clocks from cpu_reset_w falling
    // (the bench's reset_wire). The grant reproduces BUS_ARBITER's chain --
    // ff_1 needs a passive CPU status on a posedge CE, ff_2 a following
    // negedge, and aen registers hold_acknowledge on the next posedge -- so
    // the hold lands at exactly the cycle boundary hardware would grant it,
    // never mid-beat. Meaningful under REALMEM only: the flat memory has no
    // READY to stall.
    logic [39:0] frz_period_clk = 40'd0;
    initial begin
        int v;
        if ($value$plusargs("freeze_start_us=%d", v))
            frz_start_clk = 40'(v * 43);            // ~CLK_MHZ, close enough
        if ($value$plusargs("freeze_len_us=%d", v))
            frz_end_clk = frz_start_clk + 40'(v * 43);
        if ($value$plusargs("freeze_period_us=%d", v))
            frz_period_clk = 40'(v * 43);
    end

    // +freeze_period_us turns the one-shot window into a sawtooth: the same
    // length, re-armed every period, sweeping the hold across every byte
    // phase a long boot can present. With no period the window is one-shot.
    wire [39:0] frz_len_clk = frz_end_clk - frz_start_clk;
    wire [39:0] frz_phase   = (frz_period_clk != 40'd0)
                          ? ((clk_since_rst - frz_start_clk) % frz_period_clk)
                          : (clk_since_rst - frz_start_clk);
    wire        frz_in_win  = (clk_since_rst != 40'd0)
                           && (clk_since_rst >= frz_start_clk)
                           && ((frz_period_clk != 40'd0)
                               ? (frz_phase < frz_len_clk)
                               : (clk_since_rst < frz_end_clk));

    wire frz_hlda = freeze_req ? frz_ff2 : 1'b0;   // hold_acknowledge
    always_ff @(posedge clk_chipset) begin
        cpu_rst_d <= cpu_reset_w;
        if (cpu_rst_d & ~cpu_reset_w) begin
            clk_since_rst <= 40'd1;
            $display("  %8t  FREEZE: cpu_reset_w fell at %0t", $time, $time);
        end else if (clk_since_rst != 40'd0)
            clk_since_rst <= clk_since_rst + 40'd1;
        freeze_req <= frz_in_win;
        if (cpu_ce_posedge) begin
            frz_ff1    <= processor_status[0] & processor_status[1] & lock_n & freeze_req;
            test_aen   <= frz_hlda;
            dma_wait_b <= test_aen;
        end
        if (cpu_ce_negedge) begin
            if (~freeze_req)   frz_ff2 <= 1'b0;
            else if (frz_ff2)  frz_ff2 <= 1'b1;
            else               frz_ff2 <= frz_ff1;
        end
    end

    logic frz_seen = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (freeze_req & ~frz_seen)
            $display("  %8t  FREEZE: requesting hold (clk_since_rst %0d)",
                     $time, clk_since_rst);
        if (test_aen & ~frz_seen) begin
            frz_seen <= 1'b1;
            $display("  %8t  FREEZE: bus granted (eu_pc %05X, %0d clk after rst)",
                     $time, eu_pc, clk_since_rst);
        end else if (~test_aen & frz_seen) begin
            frz_seen <= 1'b0;
            $display("  %8t  FREEZE: released (eu_pc %05X)", $time, eu_pc);
        end
    end

    // ---- bus controller and address latch ----------------------------------
    wire mem_rd_n, mem_wr_n, adv_mem_wr_n;
    wire io_rd_n,  io_wr_n,  adv_io_wr_n;
    wire inta_n, ale, en_io, en_mem, dt_r_n, den, mce, pden;

    i8288 u_8288 (
        .clock                           (clk_chipset),
        .cpu_ce_posedge                  (cpu_ce_posedge),
        .cpu_ce_negedge                  (cpu_ce_negedge),
        .reset                           (reset),
        .address_enable_n                (test_aen),
        .command_enable                  (~test_aen),
        .io_bus_mode                     (1'b0),
        .processor_status                (processor_status),
        .enable_io_command               (en_io),
        .advanced_io_write_command_n     (adv_io_wr_n),
        .io_write_command_n              (io_wr_n),
        .io_read_command_n               (io_rd_n),
        .interrupt_acknowledge_n         (inta_n),
        .enable_memory_command           (en_mem),
        .advanced_memory_write_command_n (adv_mem_wr_n),
        .memory_write_command_n          (mem_wr_n),
        .memory_read_command_n           (mem_rd_n),
        .direction_transmit_or_receive_n (dt_r_n),
        .data_enable                     (den),
        .master_cascade_enable           (mce),
        .peripheral_data_enable_n        (pden),
        .address_latch_enable            (ale)
    );

    logic [19:0] cpu_address = 20'h0;
    always_ff @(posedge clk_chipset)
        if (ale) cpu_address <= cpu_ad_out;

    // ---- memory ------------------------------------------------------------
    //
    // One flat megabyte. F8000-FFFFF is the switched window: the ITF at
    // power-on, the top of BIOS.ROM after the guest selects it. Both images are
    // kept whole so the switch is a source change, not a copy.
    logic [7:0] ram  [0:1048575];
    logic [7:0] itf  [0:32767];      // 0x8000, mapped at F8000
    logic [7:0] bios [0:98303];      // 0x18000, mapped at E8000

    // core_top's reset value, now that the ITF turned out to be a 386 image:
    // the BIOS bank, booted directly the way np21w boots it.
    // Power-on bank. Zero -- the BIOS -- is what the core does by default,
    // because a previous session watched the ITF stall at F80388 waiting on
    // the GDC's vertical retrace. That wait is answered now, so +itf=1 is
    // here to ask the question again rather than assume the old answer.
    logic itf_bank = 1'b0;
    initial begin
        int v;
        if ($value$plusargs("itf=%d", v)) itf_bank = (v != 0);
    end

    function automatic logic is_rom(input logic [19:0] a);
        is_rom = (a >= 20'hE8000);
    endfunction

    function automatic logic [7:0] rom_byte(input logic [19:0] a);
        if (a >= 20'hF8000 && itf_bank) rom_byte = itf[a - 20'hF8000];
        else                            rom_byte = bios[a - 20'hE8000];
    endfunction

    // ---- the built-in 3-mode FDD option ROM at D0000 ------------------
    // Mirrors Chipset.sv's decode (address[19:8] == D00): the POST scans
    // D0000-DFFFF for AA55h at offset 9. xrom.hex is generated from
    // fpga/xrom.asm; the tail past the image stays FFh like the
    // open bus does.
    logic [7:0] xrom [0:255];
    initial begin
        for (int i = 0; i < 256; i = i + 1) xrom[i] = 8'hFF;
        $readmemh("xrom.hex", xrom);
    end

    function automatic logic is_xrom(input logic [19:0] a);
        is_xrom = (a[19:8] == 12'hD00);
    endfunction

    function automatic logic [7:0] xrom_byte(input logic [19:0] a);
        xrom_byte = xrom[a[7:0]];
    endfunction

    // The data bus is combinational, as the chipset's is. Registering it here
    // put a chipset clock between the strobe and the byte, and the core sampled
    // stale data: the first run stalled for seventeen milliseconds in the middle
    // of one instruction's operand fetch.
    assign din = ~mem_rd_n ? mem_read_byte
                  : ~inta_n       ? ((~pic2_data_bus_io) ? pic2_dout : pic1_dout)
                  : pit_iocycle    ? pit_dout
                  : dma_iocycle    ? dma_dout
                  : pic1_iocycle   ? pic1_dout
                  : pic2_iocycle   ? pic2_dout
                  : kbd_data_iocycle ? kbd8251_read_data
                  : kbd_stat_iocycle ? kbd8251_read_data
                  : gdc_stat_iocycle ? gdc_status_mock
                  : cc_ioread       ? (cc_latch | 8'h30)
                  : fdc_msr_sel     ? fdc_msr
                  : fdc_fifo_sel    ? fdc_fifo
                  : fdc_ctrl_sel    ? fdc_ctrl_rb
                  : fdc_mode_sel    ? fdc_mode_rb
                  : sysport_sel     ? sysport_data
                           : 8'hFF;

    // ---- the real memory path (+define+REALMEM) ----------------------------
    //
    // The flat array above is a model of memory; this is the memory. RAM.sv on
    // sdram_shim on sdram_mp on the part, with the board's half-period clock
    // skew -- what core_top instantiates. This runs the REAL ITF through it,
    // which is the only way to ask whether the machine's memory test fails for
    // a reason that lives in the memory path.
    //
    // ram[] stays, as a MIRROR: every guest write still lands in it, so every
    // monitor in this file keeps working and -- more useful -- the mirror is
    // what the guest believes it wrote. mem_mirror_check compares the two on
    // every read RAM.sv answers, so a memory-path fault is named the moment it
    // happens rather than inferred from where the CPU ended up.
`ifdef REALMEM
    wire [7:0]  ram_dout, ram_dout_hi;
    wire        memory_access_ready, ram_address_select_n;
    wire        ram_ready_w;
    wire        initilized_sdram_w, access_complete_w;
    wire [12:0] s_a;  wire [1:0] s_ba;
    wire        s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [10:0] ems98_unused [0:3] = '{11'h0, 11'h0, 11'h0, 11'h0};

    // ---- the graphics path, as core_top wires it --------------------------
    //
    // pc98_gvram_seq sits between the guest strobes and RAM.sv exactly the
    // way Chipset.sv has it: pass-through when no charger is armed, one
    // SDRAM op per live plane when the GRCG/EGC is on. The ITF's f87d5 test
    // (analog on, RMW fill both pages, TCR verify) exercises the real
    // expand path here -- without this the bench's flat A8000 window passes
    // the verify vacuously, by storing and returning the same bytes.
    //
    // The charger registers the POST programs: 0x7C mode (and tile-count
    // reset), 0x7E tile bytes, 0xA6 access page, 0x6A bit0 the E0000 plane.
    wire        io_w_active = ~io_wr_n & ~test_aen & (cpu_address[15:8] == 8'h00);
    always_ff @(posedge clk_chipset) begin
        if (io_w_active) begin
            if (cpu_address[7:0] == 8'h6A) pc98_analog_q <= cpu_data_bus[0];
            if (cpu_address[7:0] == 8'hA6) access_page_q <= cpu_data_bus[0];
        end
    end

    wire        grcg_rmw;
    wire [3:0]  grcg_mask;
    wire [7:0]  grcg_tile [0:3];
    pc98_grcg u_grcg (
        .clk(clk_chipset), .reset(reset),
        .cs_mode(io_w_active & (cpu_address[7:0] == 8'h7C)),
        .cs_tile(io_w_active & (cpu_address[7:0] == 8'h7E)),
        .io_read_n(io_rd_n), .io_write_n(io_wr_n),
        .io_data_in(cpu_data_bus), .io_data_out(),
        .active(grcg_active), .rmw(grcg_rmw), .plane_mask(grcg_mask),
        .tile_o(grcg_tile),
        .cpu_wdata(8'h00),
        .plane_rdata('{8'h00, 8'h00, 8'h00, 8'h00}),
        .plane_wdata(), .plane_we(), .cpu_rdata()
    );

    wire [19:0] seq_mem_addr;
    wire [7:0]  seq_mem_wdata, seq_cpu_rdata, seq_cpu_rdata_hi;
    wire        seq_mem_word, seq_mem_rd, seq_mem_wr, seq_mem_page1;
    wire [7:0]  dbg_gvram;
    pc98_gvram_seq #(.EGC(1'b1)) u_gvram_seq (
        .clk(clk_chipset), .reset(reset),
        .cpu_gvram(~ram_address_select_n),
        .cpu_rd(~mem_rd_n), .cpu_wr(~mem_wr_n),
        .cpu_word(cpu_word_access),
        .cpu_addr(cpu_address), .cpu_wdata(cpu_data_bus),
        .cpu_wdata_hi(cpu_data_bus_hi),
        .cpu_rdata(seq_cpu_rdata), .cpu_rdata_hi(seq_cpu_rdata_hi),
        .cpu_ready(memory_access_ready),
        .grcg_active(grcg_active), .grcg_rmw(grcg_rmw),
        .grcg_mask(grcg_mask), .grcg_tile(grcg_tile),
        .analog_mode(pc98_analog_q),
        .access_page(access_page_q), .mem_page1(seq_mem_page1),
        .egc_active(1'b0), .egc_wr(1'b0), .egc_rg(4'h0), .egc_d(8'h0),
        .svc_req(1'b0), .svc_we(1'b0), .svc_raw(1'b0),
        .svc_addr(20'h0), .svc_wdata(8'h0),
        .svc_done(), .svc_rdata(),
        .dbg(dbg_gvram),
        .mem_addr(seq_mem_addr), .mem_wdata(seq_mem_wdata),
        .mem_word(seq_mem_word),
        .mem_rd(seq_mem_rd), .mem_wr(seq_mem_wr),
        .mem_rdata(ram_dout), .mem_rdata_hi(ram_dout_hi),
        .mem_done(access_complete_w),
        .mem_ready(ram_ready_w)
    );

    RAM u_ram (
        .clock(clk_chipset), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram_w),
        .gvram_page1_flag(seq_mem_page1),
        .address(seq_mem_addr), .internal_data_bus(seq_mem_wdata),
        .data_bus_out(ram_dout),
        .analog_mode(pc98_analog_q),
        .word_access(seq_mem_word),
        .internal_data_bus_hi(cpu_data_bus_hi),
        .data_bus_out_hi(ram_dout_hi),
        .memory_read_n(~seq_mem_rd), .memory_write_n(~seq_mem_wr),
        .no_command_state(mem_rd_n & mem_wr_n & io_rd_n & io_wr_n),
        .memory_access_ready(ram_ready_w),
        .access_complete(access_complete_w),
        .ram_address_select_n(ram_address_select_n),
        .dbg_watch_addr(20'hFFFFF),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .ems98_map(ems98_unused),
        // The ITF window is the SHADOW, the way RAM.sv does it on hardware:
        // F8000-FFFFF redirected to 1F8000 while the flag is set. itf_bank is
        // this bench's copy of core_top's, so the images are loaded once and
        // the switch is an address bit, not a copy.
        .bios_protect_flag(2'b10), .bios_shadow_flag(itf_bank),
        .font_bank_flag(1'b0),
        .font_rd_req(fontb_req), .font_rd_addr(fontb_addr),
        .font_rd_len(fontb_len),
        .font_rd_ack(fontb_ack), .font_rd_valid(fontb_rvalid),
        .font_rd_data(fontb_rdata), .font_rd_done(fontb_done),
        .cg_rd_req(1'b0), .cg_rd_addr(24'h0), .cg_rd_len(4'h0),
        .cg_rd_ack(), .cg_rd_valid(), .cg_rd_data(), .cg_rd_done(),
        .gv_rd_req(gv_req), .gv_rd_addr(gv_addr), .gv_rd_len(gv_len),
        .gv_rd_ack(gv_ack), .gv_rd_valid(gv_rvalid),
        .gv_rd_data(gv_rdata), .gv_rd_done(gv_done),
        .wait_count_clk_en(cpu_ce_negedge),
        .ram_read_wait_cycle(ram_rd_wait), .ram_write_wait_cycle(ram_wr_wait), .vram_rd_wait_cycle(4'h0), .vram_wr_wait_cycle(4'h0),
        .ramimg_req(ramimg_req_t), .ramimg_we(1'b0),
        .ramimg_addr(ramimg_addr_t),
        .ramimg_len(ramimg_len_t), .ramimg_wdata(16'h0000),
        .ramimg_ack(ramimg_ack_t), .ramimg_rvalid(ramimg_rvalid_t),
        .ramimg_rdata(), .ramimg_done(ramimg_done_t)
    );

    sdram_board_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                        .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clk_chipset), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ---- the video-side ports: the REAL display fetch on D ---------------
    //
    // This is the client the multiport controller exists for, and the bench
    // historically left it tied off -- which made every port-A latency this
    // bench measured a best case, not the machine's case. Peripherals wires
    // pc98_gvram_display to port D; here it is instantiated with the real
    // pc98_video_timing on a halved chipset clock for the dot domain
    // (21.48 MHz against the part's 21.05 -- 2% fast, i.e. conservative by
    // the same amount on line rate).
    //
    // The slave-GDC registers are constants shaped like the 640x400 default:
    // one partition of LEN 400 at SAD 0, PITCH 40 words (mhz5 clear, so the
    // display module doubles it to the 80-byte line). disp_on is a plusarg
    // -- +disp=0 leaves port D silent so the same binary measures baseline
    // vs loaded. +analog4=1 adds the fourth plane (E0000), which is what
    // sixteen-colour games pay.
    logic        disp_on_r = 1'b1;
    logic        analog4_r = 1'b0;
    logic        disp_page_r = 1'b0;
    logic        dbl_r = 1'b0;
    logic [15:0] disp_sad [0:3] = '{16'd0, 16'd0, 16'd0, 16'd0};
    logic [9:0]  disp_len [0:3] = '{10'd400, 10'd0, 10'd0, 10'd0};
    initial begin
        int v;
        if ($value$plusargs("disp=%d", v))    disp_on_r  = (v != 0);
        if ($value$plusargs("analog4=%d", v)) analog4_r  = (v != 0);
        if ($value$plusargs("disppage=%d", v)) disp_page_r = (v != 0);
        if ($value$plusargs("dbl=%d", v))     dbl_r      = (v != 0);
    end

    logic        dot_clk = 1'b0;
    always_ff @(posedge clk_chipset) dot_clk <= ~dot_clk;
    wire  [9:0] vid_h, vid_v;
    wire        vid_hs, vid_vs, vid_hb, vid_vb, vid_de, vid_fs;
    pc98_video_timing u_vtiming (
        .clk(dot_clk), .ce(1'b1), .rst(1'b0),
        .hcount(vid_h), .vcount(vid_v), .hsync(vid_hs), .vsync(vid_vs),
        .hblank(vid_hb), .vblank(vid_vb), .de(vid_de), .frame_start(vid_fs)
    );

    wire        gv_req, gv_ack, gv_rvalid, gv_done;
    wire [23:0] gv_addr;
    wire  [3:0] gv_len;
    wire [15:0] gv_rdata;
    wire  [3:0] gv_dot_unused;
    pc98_gvram_display u_gvram_disp (
        .clk(clk_chipset), .rst(reset),
        .rd_clk(dot_clk), .hcount(vid_h), .vcount(vid_v),
        .disp_on(disp_on_r), .disp_page(disp_page_r),
        .analog_mode(analog4_r), .dbl(dbl_r),
        .pitch(8'd40), .mhz5(1'b0), .lrep(5'd0),
        .part_sad(disp_sad), .part_len(disp_len),
        .part_pbyte(4'h0),
        .p_req(gv_req), .p_addr(gv_addr), .p_len(gv_len),
        .p_ack(gv_ack), .p_rvalid(gv_rvalid), .p_rdata(gv_rdata),
        .p_done(gv_done), .gfx_dot(gv_dot_unused)
    );

    // ---- optional synthetic pressure on ports B and E ----------------------
    //
    // Port B is the kanji font fetcher -- quiet while the screen is ASCII
    // (ANK glyphs live in BRAM). +fontb=N issues one 16-word burst every N
    // chipset clocks: the glyph rowbuf's worst case is 80 cells per text row
    // (16 lines), i.e. 5 per scanline -- fontb=340 approximates a fully
    // kanji screen.
    // Port E is fdd_ramimg's carve-out: 16-word sector-read bursts while it
    // serves a RAM-image floppy. +porte=N does the same there. Both default
    // off: the honest answer comes from the ports that actually run.
    logic        fontb_req = 1'b0;
    logic [23:0] fontb_addr = 24'h400000;
    logic  [3:0] fontb_len = 4'd15;
    wire         fontb_ack, fontb_rvalid, fontb_done;
    wire [15:0]  fontb_rdata;
    int          fontb_per = 0, fontb_cnt = 0;

    logic        ramimg_req_t = 1'b0;
    logic [23:0] ramimg_addr_t = 24'h620000;
    logic  [3:0] ramimg_len_t = 4'd15;
    wire         ramimg_ack_t, ramimg_rvalid_t, ramimg_done_t;
    int          porte_per = 0, porte_cnt = 0;
    initial begin
        int v;
        if ($value$plusargs("fontb=%d", v)) fontb_per = v;
        if ($value$plusargs("porte=%d", v)) porte_per = v;
    end
    always_ff @(posedge clk_chipset) begin
        if (reset) begin
            fontb_req <= 1'b0; fontb_cnt <= 0;
            ramimg_req_t <= 1'b0; porte_cnt <= 0;
        end else begin
            if (fontb_req) begin
                if (fontb_ack) begin
                    fontb_req  <= 1'b0;
                    fontb_addr <= fontb_addr + 24'd16;
                end
            end else if (fontb_per > 0) begin
                fontb_cnt <= fontb_cnt + 1;
                if (fontb_cnt >= fontb_per) begin
                    fontb_cnt <= 0; fontb_req <= 1'b1;
                end
            end
            if (ramimg_req_t) begin
                if (ramimg_ack_t) begin
                    ramimg_req_t  <= 1'b0;
                    ramimg_addr_t <= ramimg_addr_t + 24'd16;
                end
            end else if (porte_per > 0) begin
                porte_cnt <= porte_cnt + 1;
                if (porte_cnt >= porte_per) begin
                    porte_cnt <= 0; ramimg_req_t <= 1'b1;
                end
            end
        end
    end

    // ---- SDRAM occupancy monitor (sim only, hierarchical taps) ------------
    //
    // Everything the arbiter knows, counted per port, printed per chunk by
    // the run loop (the OCC line) and summed at the end. "own" cycles are
    // the number of clocks the port's transaction occupies the controller
    // (grant held while the FSM is anywhere but IDLE/refresh); "wait" cycles
    // are req-up-not-yet-acked -- the arbitration queue depth, per port.
    //
    // sdram_mp state encoding (must match sdram_mp.sv's state_t order):
    //   0..3 init, 4 IDLE, 5 ACT, 6 RW, 7 RD_GAP, 8 TAIL, 9 REF_PRE,
    //   10 REF, 11 PRE_MISS.
    localparam int MP_S_IDLE = 4;
    localparam int MP_S_RW   = 6;
    // grant-owned states: the port's transaction is on the device.
    wire        mp_busy   = (u_ram.u_sdram.u_mp.state > MP_S_IDLE)
                        & (u_ram.u_sdram.u_mp.state != 4'd9)
                        & (u_ram.u_sdram.u_mp.state != 4'd10);
    wire [2:0]  mp_grant  = u_ram.u_sdram.u_mp.grant;
    wire [4:0]  mp_reqs   = u_ram.u_sdram.u_mp.p_req;
    wire [4:0]  mp_acks   = u_ram.u_sdram.u_mp.p_ack;
    wire [4:0]  mp_dones  = u_ram.u_sdram.u_mp.p_done;
    wire        mp_rvalid = u_ram.u_sdram.u_mp.p_rvalid;
    wire        mp_wrbeat = mp_busy & u_ram.u_sdram.u_mp.cur_we
                        & (u_ram.u_sdram.u_mp.state == MP_S_RW);
    wire        mp_refresh= u_ram.u_sdram.u_mp.stat_refresh;
    wire        mp_initd  = u_ram.u_sdram.u_mp.init_done;
    wire        mp_act    = (u_ram.u_sdram.u_mp.state == 4'd5)
                        | (u_ram.u_sdram.u_mp.state == 4'd11);

    longint unsigned occ_cyc      = 0;   // cycles since init_done
    longint unsigned occ_refresh  = 0;
    longint unsigned occ_own  [0:4] = '{0,0,0,0,0};
    longint unsigned occ_wait [0:4] = '{0,0,0,0,0};
    longint unsigned occ_trans[0:4] = '{0,0,0,0,0};
    longint unsigned occ_rd   [0:4] = '{0,0,0,0,0};
    longint unsigned occ_wr   [0:4] = '{0,0,0,0,0};
    longint unsigned occ_act        = 0;  // cycles paying ACT/PRE-miss
    longint unsigned occ_actp [0:4] = '{0,0,0,0,0}; // same, per port
    // port A latency, per transaction: a_w = req-up cycles before ack,
    // a_d = grant-to-done cycles, hist over the sum.
    int unsigned     a_w = 0, a_d = 0;
    logic            a_flight = 1'b0, a_acked = 1'b0;
    longint unsigned a_wait_sum = 0, a_wait_max = 0, a_wait_n = 0;
    longint unsigned a_lat_sum  = 0, a_lat_max  = 0;
    // port A latency buckets: 0-9,10-19,20-39,40-79,80+
    longint unsigned a_lat_hist [0:4] = '{0,0,0,0,0};
    // display fetch vs raster phase: D grant cycles inside vs outside hblank
    longint unsigned d_in_hb = 0, d_in_vis = 0, d_in_vb = 0;
    // CPU-visible stall: zet wishbone pending cycles + RAM FSM busy cycles
    longint unsigned cpu_wb_pend = 0, cpu_wb_ack = 0;
    longint unsigned ramfsm_busy = 0, ramfsm_done = 0;
    longint unsigned guest_stall = 0;  // cmd up, ready down
    // gvram sequencer occupancy: cycles an expansion owns the port-A path
    longint unsigned seq_busy = 0, seq_legs = 0;
    int            seq_leg_d = 0;

    always_ff @(posedge clk_chipset) begin
        if (mp_initd) begin
            occ_cyc <= occ_cyc + 1;
            if (mp_refresh) occ_refresh <= occ_refresh + 1;
            if (mp_act)     occ_act     <= occ_act + 1;
            for (int p = 0; p < 5; p++) begin
                if (mp_busy & (mp_grant == 3'(p)))   occ_own[p]  <= occ_own[p] + 1;
                if (mp_reqs[p] & ~mp_acks[p])        occ_wait[p] <= occ_wait[p] + 1;
                if (mp_acks[p])                      occ_trans[p]<= occ_trans[p] + 1;
                if (mp_rvalid & (mp_grant == 3'(p))) occ_rd[p]   <= occ_rd[p] + 1;
                if (mp_wrbeat & (mp_grant == 3'(p))) occ_wr[p]   <= occ_wr[p] + 1;
                if (mp_act & mp_busy & (mp_grant == 3'(p)))
                    occ_actp[p] <= occ_actp[p] + 1;
            end
            // port A transaction latency: req edge to done pulse. The shim
            // drops its req at ack, so the wait half and the granted half are
            // tracked separately and summed at done.
            if (!a_flight && mp_reqs[0]) begin
                a_flight <= 1'b1; a_acked <= 1'b0; a_w <= 0; a_d <= 0;
            end else if (a_flight) begin
                if (mp_acks[0]) begin
                    a_acked    <= 1'b1;
                    a_wait_n   <= a_wait_n + 1;
                    a_wait_sum <= a_wait_sum + a_w;
                    if (a_w > a_wait_max) a_wait_max <= a_w;
                end else if (!a_acked) a_w <= a_w + 1;
                else                   a_d <= a_d + 1;
                if (mp_dones[0]) begin
                    a_flight  <= 1'b0;
                    a_lat_sum <= a_lat_sum + a_w + a_d + 1;
                    if ((a_w + a_d + 1) > a_lat_max)
                        a_lat_max <= a_w + a_d + 1;
                    a_lat_hist[(a_w + a_d + 1) < 10 ? 0
                        : (a_w + a_d + 1) < 20 ? 1
                        : (a_w + a_d + 1) < 40 ? 2
                        : (a_w + a_d + 1) < 80 ? 3 : 4]
                      <= a_lat_hist[(a_w + a_d + 1) < 10 ? 0
                        : (a_w + a_d + 1) < 20 ? 1
                        : (a_w + a_d + 1) < 40 ? 2
                        : (a_w + a_d + 1) < 80 ? 3 : 4] + 1;
                end
            end
            // D's grant cycles against the raster phase.
            if (mp_busy & (mp_grant == 3'd3)) begin
                if (vid_vb)      d_in_vb  <= d_in_vb + 1;
                else if (vid_hb) d_in_hb  <= d_in_hb + 1;
                else             d_in_vis <= d_in_vis + 1;
            end
            if (zwb_stb & ~zwb_ack) cpu_wb_pend <= cpu_wb_pend + 1;
            if (zwb_stb & zwb_ack)  cpu_wb_ack  <= cpu_wb_ack + 1;
            if (u_ram.state != u_ram.IDLE) ramfsm_busy <= ramfsm_busy + 1;
            if (u_ram.state == u_ram.COMPLETE_RAM_RW)
                ramfsm_done <= ramfsm_done + 1;
            if ((~mem_rd_n | ~mem_wr_n) & ~ram_ready_w)
                guest_stall <= guest_stall + 1;
            if (u_gvram_seq.st != 3'd0) begin
                seq_busy <= seq_busy + 1;
                seq_leg_d <= seq_leg_d + 1;
            end else if (seq_leg_d != 0) begin
                seq_legs  <= seq_legs + seq_leg_d;
                seq_leg_d <= 0;
            end
        end
    end

    task automatic occ_report;
        real busy_tot;
        $display("  OCC cyc=%0d ref=%0d(%0d%%) | act/pre=%0d",
                 occ_cyc, occ_refresh,
                 occ_cyc ? int'(occ_refresh * 100 / occ_cyc) : 0, occ_act);
        for (int p = 0; p < 5; p++)
            $display("    port %0d: trans=%0d rd=%0d wr=%0d own=%0d(%0d%%) wait=%0d act=%0d",
                     p, occ_trans[p], occ_rd[p], occ_wr[p], occ_own[p],
                     occ_cyc ? int'(occ_own[p] * 100 / occ_cyc) : 0,
                     occ_wait[p], occ_actp[p]);
        $display("    portA req->ack avg %0d max %0d n=%0d | req->done avg %0d max %0d",
                 a_wait_n ? int'(a_wait_sum / a_wait_n) : 0, a_wait_max,
                 a_wait_n,
                 occ_trans[0] ? int'(a_lat_sum / occ_trans[0]) : 0, a_lat_max);
        $display("    portA lat hist <10:%0d 10-19:%0d 20-39:%0d 40-79:%0d 80+:%0d",
                 a_lat_hist[0], a_lat_hist[1], a_lat_hist[2],
                 a_lat_hist[3], a_lat_hist[4]);
        $display("    D grant phase: vis=%0d hb=%0d vb=%0d",
                 d_in_vis, d_in_hb, d_in_vb);
        $display("    ramfsm busy=%0d done=%0d | guest stall cyc=%0d | seq busy=%0d legs=%0d",
                 ramfsm_busy, ramfsm_done, guest_stall, seq_busy, seq_legs);
        $display("    zwb pending=%0d ack=%0d avg_lat=%0d",
                 cpu_wb_pend, cpu_wb_ack,
                 cpu_wb_ack ? int'(cpu_wb_pend / cpu_wb_ack) : 0);
    endtask

    // Chipset.sv: io_channel_ready & memory_access_ready.
    wire bench_ready;
    READY u_ready (
        .clock               (clk_chipset),
        .cpu_ce_posedge      (cpu_ce_posedge),
        .cpu_ce_negedge      (cpu_ce_negedge),
        .reset               (reset),
        .processor_ready     (bench_ready),
        .dma_ready           (),
        .dma_wait_n          (~dma_wait_b),
        .io_channel_ready    (memory_access_ready),
        .io_read_n           (io_rd_n),
        .io_write_n          (io_wr_n),
        .memory_read_n       (mem_rd_n),
        .dma0_acknowledge_n  (1'b1),
        .address_enable_n    (test_aen)
    );

    // RAM.sv answers where it is selected; the mirror answers the rest
    // (A0000-A7FFF and C0000-E7FFF are not in its select). The sequencer's
    // cpu_rdata/cpu_rdata_hi are what the guest lanes see, pass-through or
    // transformed -- same mux Chipset.sv drives onto internal_data_bus_ram.
    wire [7:0] mem_read_byte = ~ram_address_select_n ? seq_cpu_rdata
                            : is_xrom(cpu_address)   ? xrom_byte(cpu_address)
                                                     : ram[cpu_address];
    // The odd lane of a one-cycle word read; the SDRAM serves those, the
    // option ROM serves its own.
    wire [7:0] din_hi = (~mem_rd_n & ~ram_address_select_n) ? seq_cpu_rdata_hi
                      : (~mem_rd_n & is_xrom(cpu_address))  ? xrom_byte(cpu_address | 20'h1)
                                                            : 8'hFF;

    // The mirror check. On the trailing edge of a read RAM.sv answered, what
    // it gave against what the guest put there. A read the sequencer expanded
    // (charger armed, or the page bit banking the window) returns a
    // transform -- the TCR match mask or the EGC pipeline byte -- not the
    // raw mirror byte, so those are skipped.
    logic       mrd_d = 1'b1;
    logic [7:0] mrd_live;
    int         mem_mismatches = 0;
    always_ff @(posedge clk_chipset) begin
        mrd_d <= mem_rd_n;
        if (~mem_rd_n) mrd_live <= mem_read_byte;
        if (mem_rd_n & ~mrd_d & ~ram_address_select_n
          & ~(grcg_active | access_page_q)) begin
            logic [7:0] want_b;
            want_b = is_rom(cpu_address) ? rom_byte(cpu_address)
                                         : ram[cpu_address];
            if (mrd_live !== want_b) begin
                mem_mismatches++;
                if (mem_mismatches <= 20)
                    $display("  %8t  MEMPATH [%05X] gave %02X, guest wrote %02X  (eu_pc %05X)",
                             $time, cpu_address, mrd_live, want_b, eu_pc);
            end
        end
    end
`else
    wire [7:0] mem_read_byte = is_rom(cpu_address)  ? rom_byte(cpu_address)
                             : is_xrom(cpu_address) ? xrom_byte(cpu_address)
                                                    : ram[cpu_address];
    wire bench_ready = 1'b1;          // flat memory answers immediately
    // The flat array is byte-wide but still answers a word's odd lane at
    // addr|1 -- the word path is unconditional, so a one-cycle read at an
    // SDRAM-map address asks for it.
    wire [7:0] mem_read_byte_hi = is_rom(cpu_address | 20'h1)
                                  ? rom_byte(cpu_address | 20'h1)
                                : is_xrom(cpu_address | 20'h1)
                                  ? xrom_byte(cpu_address | 20'h1)
                                : ram[cpu_address | 20'h1];
    wire [7:0] din_hi = ~mem_rd_n ? mem_read_byte_hi : 8'hFF;
`endif

    // True when the read above fell through to the FF default -- i.e. nothing
    // here answered it. Used to name the port once, in the trace.
    wire din_is_default = ~(~mem_rd_n | ~inta_n | pit_iocycle | dma_iocycle
                          | pic1_iocycle | pic2_iocycle | kbd_data_iocycle
                          | kbd_stat_iocycle | gdc_stat_iocycle | cc_ioread
                          | fdc_msr_sel | fdc_fifo_sel | fdc_ctrl_sel
                          | fdc_mode_sel | sysport_sel);

    // ---- I/O ---------------------------------------------------------------
    //
    // Reads answer 0xFF: nothing here is modelled, and the point is where the
    // CPU goes, not what it finds. A port that must answer to get past a spin
    // will show up as a spin, which is itself the finding.
    logic [15:0] io_port_hist [0:63];
    int          io_n = 0;
    logic        saw_043d = 1'b0;
    logic [7:0]  last_043d = 8'h00;

    // 0x35 and 0x42, answered exactly as PERIPHERALS answers them.
    //
    // The default 8'hFF here is not neutral. The ITF reads 0x42 at F8117 and
    // tests bit 1; with the bit set it writes 0B to 0x37 and 00 to 0xF0 -- the
    // shutdown port -- and stops on JMP $ at F8129. So the bench's "nothing is
    // modelled, answer FF" was ordering the machine to shut down, and the ITF
    // was never given a chance to run at all.
    //
    // 0x35 is the 8255's port C: the BIOS's second instruction is
    // IN AL,35h / TEST AL,80h / JNZ, and bits 7 and 5 have to read 1.
    wire sysport_31_sel = ~io_rd_n & (cpu_address[15:0] == 16'h0031);
    wire sysport_33_sel = ~io_rd_n & (cpu_address[15:0] == 16'h0033);
    wire sysport_35_sel = ~io_rd_n & (cpu_address[15:0] == 16'h0035);
    wire sysport_42_sel = ~io_rd_n & (cpu_address[15:0] == 16'h0042);
    wire sysport_sel    = sysport_31_sel | sysport_33_sel
                        | sysport_35_sel | sysport_42_sel;
    // 0x33 is 8255 port B, an INPUT on a PC-98: bit 3 a DIP switch inverted,
    // bits 7-5 the RS-232C modem status, bit 0 the calendar clock, and the
    // rest zero. Bit 2 is one of the zeroes, and the UX ITF reads it at F889C
    // as PARITY ERROR -- which is what FF gave it, and what it printed.
    // 0x31 is DIP switch 2, and bit 4 tells the ITF to initialise the memory
    // switch: the twenty bytes at A3FE0 that hold the machine's configuration,
    // A3FEA among them, whose low three bits are how many 128 KB units of RAM
    // to count -- 0 for 128 KB, 4 for 640 KB.
    //
    // On a real PC-98 that area is battery-backed text VRAM and survives a
    // power cycle, so the ITF only rewrites it when the switch asks. Here it
    // is ordinary VRAM and comes up cleared every time, so the answer is
    // always "please initialise": bit 4 set. With it clear, the ITF skipped
    // the whole block, read A3FEA as zero, and counted 128 KB -- which is
    // exactly what MEMORY 128KB OK was reporting on a 640 KB machine.
    // 0x35 is a latch here too, resetting to F9 and answering the 0x37 bit
    // set/reset -- bit 7 is the shutdown flag the ITF clears before OUT 0F0h.
    logic [7:0] sysport_c = 8'hF9;
    logic       sysp_prev_wr_n = 1'b1;
    logic [7:0] sysp_wr_data = 8'h00;
    wire sysp_wr35 = ~io_wr_n & (cpu_address[15:0] == 16'h0035);
    wire sysp_wr37 = ~io_wr_n & (cpu_address[15:0] == 16'h0037);
    always_ff @(posedge clk_chipset) begin
        sysp_prev_wr_n <= io_wr_n;
        if (sysp_wr35 | sysp_wr37) sysp_wr_data <= cpu_data_bus;
        if (io_wr_n & ~sysp_prev_wr_n) begin
            if (cpu_address[15:0] == 16'h0035)
                sysport_c <= sysp_wr_data;
            else if (cpu_address[15:0] == 16'h0037 && sysp_wr_data[7:4] == 4'h0)
                sysport_c[sysp_wr_data[3:1]] <= sysp_wr_data[0];
        end
    end

    // OUT 0F0h resets the CPU and nothing else -- the ITF's way out of its
    // memory test. Held for a while, like the core's own reset release.
    always_ff @(posedge clk_chipset) begin
        f0_prev_wr_n <= io_wr_n;
        f0_prev_rd_n <= io_rd_n;
        if (io_wr_n & ~f0_prev_wr_n & (cpu_address[15:0] == 16'h00F0)) begin
            soft_reset_cpu   <= 1'b1;
            soft_reset_count <= 8'hFF;
            $display("  %8t  OUT 00F0 -- CPU reset requested (eu_pc %05X)", $time, eu_pc);
        end else if (soft_reset_count != 8'h00)
            soft_reset_count <= soft_reset_count - 8'h01;
        else
            soft_reset_cpu <= 1'b0;
    end

    // Keyboard flow: the 0x43 command writes, the 0x41 reads, and the state
    // of [0x500] -- the byte whose bit 7 the ITF sets when it reads its 0x60
    // and the BIOS branches on at FD897. This is the story the 8251 model is
    // on trial for. (The 0x41 log samples the data mux WHILE the read is
    // live: after the strobe ends the module's read_data falls back to the
    // status word, which made the first run's log say "IN 41 -> 87".)
    logic [7:0] kbd500_q  = 8'h00;
    logic [7:0] kbd41_q   = 8'h00;
    always_ff @(posedge clk_chipset) begin
        if (kbd8251_en & ~io_rd_n & (cpu_address[15:0] == 16'h0041))
            kbd41_q <= kbd8251_read_data;
        if (kbd8251_en & (io_wr_n & ~f0_prev_wr_n)
                       & (cpu_address[15:0] == 16'h0043))
            $display("  %8t  KBD OUT 43 <- %02X  (eu_pc %05X)",
                     $time, cpu_data_bus, eu_pc);
        if (kbd8251_en & (io_rd_n & ~f0_prev_rd_n)
                       & (cpu_address[15:0] == 16'h0041))
            $display("  %8t  KBD IN  41 -> %02X  (eu_pc %05X)",
                     $time, kbd41_q, eu_pc);
        if (ram[20'h00500] !== kbd500_q) begin
            $display("  %8t  [0500] %02X -> %02X  (eu_pc %05X)",
                     $time, kbd500_q, ram[20'h00500], eu_pc);
            kbd500_q <= ram[20'h00500];
        end
        // The option ROM: first guest read inside the window, first
        // registration write to the XROM dispatch table.
        if (~mem_rd_n & is_xrom(cpu_address) & ~xrom_rd_seen) begin
            xrom_rd_seen <= 1'b1;
            $display("  %8t  XROM first read  [%05X]  (eu_pc %05X)",
                     $time, cpu_address, eu_pc);
        end
        if ((ram[20'h004B3] !== 8'h00) & ~xrom_reg_seen) begin
            xrom_reg_seen <= 1'b1;
            $display("  %8t  XROM registered: 4B3=%02X 5AE=%02X 5F8=%02X:%02X%02X  (eu_pc %05X)",
                     $time, ram[20'h004B3], ram[20'h005AE],
                     {ram[20'h5FB], ram[20'h5FA]},
                     ram[20'h5F9], ram[20'h5F8], eu_pc);
        end
    end
    logic xrom_rd_seen = 1'b0, xrom_reg_seen = 1'b0;

    wire [7:0] sysport_data = sysport_35_sel ? sysport_c
                            : sysport_31_sel ? 8'h10
    // 0x42 bit 1: this machine has no protected mode.
    //
    // The UX ITF tests it at F8B95 and, with the bit CLEAR, walks into
    //
    //     F8BBC  lidt [es:bp+0]
    //     F8BC4  lgdt [es:bp+0]
    //
    // to size memory above 1 MB. Those are 286 instructions, and on an 8086
    // 0F is POP CS -- so the machine popped a word off the stack into CS and
    // left the ROM. That is the CS f800 -> 0000 jump that ended every run
    // right after MEMORY 640KB OK was printed.
    //
    // With the bit SET the ITF branches to F8FA2 and skips the whole
    // protected-mode block, which is the truth about this CPU rather than a
    // way around the symptom. The BIOS never looks at bit 1 -- it tests bits
    // 0, 3, 4, 5 and 6 of the same port -- so nothing else changes.
                            : sysport_33_sel ? 8'h00
                            : sysport_42_sel ? 8'h02
                            :                  8'h00;

    logic saw_high_write = 1'b0;
    logic din_default_q = 1'b0;
    logic unanswered_seen [0:255];
    initial for (int q = 0; q < 256; q = q + 1) unanswered_seen[q] = 1'b0;

    logic io_wr_d = 1'b1, mem_wr_d = 1'b1, mem_rd_d = 1'b1, io_rd_d = 1'b1;
    logic in_1b_region = 1'b0;
    logic [7:0] mem_wr_data_q = 8'h00;
    // The odd lane and the word flag of a one-cycle write, sampled with the
    // same continuously-held discipline as mem_wr_data_q.
    logic [7:0] mem_wr_hi_q   = 8'h00;
    logic       mem_wr_word_q = 1'b0;
    logic [7:0] io_wr_data_q  = 8'h00;
    logic [7:0] tvram_code [0:511];   // A0000-A01FF, first row of cells
    logic [7:0] tvram_attr [0:511];   // A2000-A21FF
    int          tvram_wr_count = 0;

    // The two GDC status ports, named here because the trace below has to
    // recognise them long before the mock that answers them is declared.
    wire  gdc_stat_port  = (cpu_address[15:0] == 16'h0060)
                         | (cpu_address[15:0] == 16'h00A0);
    logic gdc_poll_seen  = 1'b0;
    logic [7:0] io60_live = 8'h00;
    int         gdc60_n   = 0;

    // The last sixteen DISTINCT execution addresses.
    //
    // "eu_pc is in the FF72F wait" is not enough to tell one long loop from a
    // caller that keeps re-entering it: both park most samples on the same
    // eight bytes. The ring shows the whole cycle, and the addresses either
    // side of the loop are the ones that say who is retrying it.
    logic [19:0] pc_ring [0:15];
    int          pc_ring_w = 0;
    logic [19:0] pc_ring_d = 20'hFFFFF;
    always_ff @(posedge clk_chipset) begin
        // Only the DISCONTINUITIES. eu_pc is the prefetch queue's read
        // pointer, so it walks a byte at a time and a ring of every value is
        // sixteen bytes of one straight line. A jump is what says where the
        // control flow went, so keep the targets and drop the walking.
        if (eu_pc != pc_ring_d) begin
            pc_ring_d <= eu_pc;
            if (eu_pc < pc_ring_d || eu_pc > pc_ring_d + 20'd4) begin
                pc_ring[pc_ring_w[3:0]] <= eu_pc;
                pc_ring_w <= pc_ring_w + 1;
            end
        end
    end

    // CX, at its lowest in the chunk.
    //
    // The wait at FF72F is LOOPNE with CX zeroed on entry, so it has 65536
    // tries -- about 0.4 seconds -- and then it MUST fall through. It does
    // not, on the hardware or here, and the execution range says the loop is
    // never left at all. Either the count is not counting or something is
    // putting it back. One number decides it: if the low-water mark of CX
    // walks down to zero the loop is completing and being re-entered; if it
    // never gets near zero, CX is being reset under the loop's feet.
    wire [15:0] eu_cx = dbg_regs[31:16];
    logic [15:0] cx_min_chunk = 16'hFFFF;

    // Reset by the progress loop after every chunk it prints -- through a
    // toggle rather than by assigning them there, because a variable written
    // both blocking and non-blocking is one Verilator gets to reorder.
    logic [19:0] wr_lo_chunk = 20'hFFFFF, wr_hi_chunk = 20'h00000;
    int          wr_n_chunk  = 0;
    logic        wr_clear_tog = 1'b0, wr_clear_d = 1'b0;

    always_ff @(posedge clk_chipset) begin
        wr_clear_d <= wr_clear_tog;
        if (wr_clear_tog != wr_clear_d) begin
            wr_lo_chunk  <= 20'hFFFFF;
            wr_hi_chunk  <= 20'h00000;
            wr_n_chunk   <= 0;
            cx_min_chunk <= 16'hFFFF;
        end else if (eu_cx < cx_min_chunk)
            cx_min_chunk <= eu_cx;

        io_wr_d  <= io_wr_n;
        mem_wr_d <= mem_wr_n;
        mem_rd_d <= mem_rd_n;
        io_rd_d  <= io_rd_n;

        // Write data is valid throughout the command and guaranteed at its
        // END. Sampling cpu_data_bus once on the trailing edge caught the
        // bus already moving on -- the IVT write at FDA76 landed 21 02 23 FD
        // where the BIOS put BC 02 80 FD, and INT 08 went astray on exactly
        // that. Sample continuously while the cycle is live and keep the last.
        if (~mem_wr_n) begin
            mem_wr_data_q <= cpu_data_bus;
            // A one-cycle word write carries its odd byte on the _hi lane;
            // the flat array takes it too, so the mirror stays complete
            // (under REALMEM this block is the mirror, not the storage).
            mem_wr_hi_q   <= cpu_data_bus_hi;
            mem_wr_word_q <= cpu_word_access;
        end
        // Same trailing-edge hazard as the memory write: the I/O write data
        // is live only while io_wr_n is low, so latch it here.
        if (~io_wr_n) io_wr_data_q <= cpu_data_bus;

        // Memory write, on the trailing edge, and never into ROM.
        if (mem_wr_n & ~mem_wr_d & ~is_rom(cpu_address)) begin
            ram[cpu_address] <= mem_wr_data_q;
            if (mem_wr_word_q) ram[cpu_address | 20'h1] <= mem_wr_hi_q;
            // The ITF's reset-resume state (0000:03F0-0410): every write here
            // is part of the OUT-0F0h dance, and a save that goes missing is
            // the difference between a resume and a derail.
            if (cpu_address >= 20'h003F0 && cpu_address <= 20'h00410)
                $display("  %8t  RESUME-state write %05X <- %02X  (eu_pc %05X)",
                         $time, cpu_address, mem_wr_data_q, eu_pc);
            // Where the writes are going, chunk by chunk. The hardware's LIVE
            // readout is the same quantity, and "sweeping upward through the
            // memory test" and "going round a small ring" look identical on a
            // 20 fps display but not at all alike here.
            if (cpu_address >= 20'h20000 && cpu_address < 20'hA0000
                && ~saw_high_write) begin
                saw_high_write <= 1'b1;
                $display("  %8t  first write above 128 KB: %05X (eu_pc %05X)",
                         $time, cpu_address, eu_pc);
            end
            if (cpu_address < wr_lo_chunk) wr_lo_chunk <= cpu_address;
            if (cpu_address > wr_hi_chunk) wr_hi_chunk <= cpu_address;
            wr_n_chunk <= wr_n_chunk + 1;
            // The ITF's CPU-reset resume state lives at 0000:03F0-040F: the
            // pushed far return F800:1497 at 03FA/03FC, the saved SS:SP at
            // 0404/0406. The run of 2026-09-11 RETFed to 0000:0069 instead,
            // so one of those words is not what the save left behind. There
            // are only a handful of writes into this window in a whole boot,
            // and the one that clobbers it names itself here.
            if (cpu_address >= 20'h003F0 && cpu_address <= 20'h0040F)
                $display("  %8t  SAVE[%04X] <= %02X   (eu_pc %05X)",
                         $time, cpu_address[15:0], mem_wr_data_q, eu_pc);
            // The first page carries the vectors; who touches 0000-0FFF and
            // with what decides whether INT xx lands where the BIOS meant.
            // (Display off -- the memory test writes there for a living and
            // the log grew to half a gigabyte. The IVT dump at the end
            // still tells the story.)
            // $display("  %8t  RAM[%04X] <= %02X   (eu_pc %05X)", ...)
            // The text plane: the memory-count display lands here. Keep the
            // first row of cells (code + attribute) for the final dump.
            if (cpu_address >= 20'hA0000 && cpu_address < 20'hA4000) begin
                if (cpu_address < 20'hA0200)
                    tvram_code[cpu_address[8:0]]  <= mem_wr_data_q;
                else if (cpu_address >= 20'hA2000 && cpu_address < 20'hA2200)
                    tvram_attr[cpu_address[8:0]]  <= mem_wr_data_q;
                tvram_wr_count <= tvram_wr_count + 1;
                // The first forty writes (the clear, and what shape it has),
                // and after that every PRINTABLE byte into the code plane --
                // which is the memory count, if the BIOS ever writes one. The
                // clear itself is 20487 writes of 00 and E1 and says nothing.
                if (tvram_wr_count < 40
                 || (cpu_address < 20'hA2000
                     && mem_wr_data_q >= 8'h20 && mem_wr_data_q < 8'h7F))
                    $display("  %8t  TVRAM[%04X] <= %02X %s  (eu_pc %05X)",
                             $time, cpu_address[15:0], mem_wr_data_q,
                             (mem_wr_data_q >= 8'h20 && mem_wr_data_q < 8'h7F)
                                 ? string'({"'", mem_wr_data_q, "'"}) : "   ",
                             eu_pc);
            end
        end

        // I/O reads matter here too: if the ModRM byte of a group opcode is
        // dispatched as an opcode, E4 becomes IN AL,imm8 and shows up as a read
        // from a port the program never names.
        // GDC status (0x60/0xA0) is polled in a tight loop for a whole frame
        // at a time -- eleven thousand lines of it in the last run, which
        // buried everything else and cost more than the simulation did. The
        // first read of each visit is the one that says the loop was entered;
        // the rest say only that a frame is long.
        // Every port this bench does not model answers FF, and FF is NEVER
        // neutral: the ITF read 0x42 as an order to shut down and 0x33 as a
        // parity error, and each cost a run to find. Name them the first time
        // they are read, so the next one costs a line of log instead.
        // Sampled WHILE the cycle is live: at the trailing edge every select
        // has already dropped, so din_is_default reads true for every port
        // and the first version of this named all of them.
        if (~io_rd_n) din_default_q <= din_is_default;
        if (io_rd_n & ~io_rd_d && din_default_q
            && ~unanswered_seen[cpu_address[7:0]]) begin
            unanswered_seen[cpu_address[7:0]] <= 1'b1;
            $display("  %8t  UNMODELLED PORT %04X read -- answering FF (eu_pc %05X)",
                     $time, cpu_address[15:0], eu_pc);
        end

        if (~io_rd_n & gdc_stat_port) io60_live <= din;
        if (io_rd_n & ~io_rd_d) begin
            if (gdc_stat_port) begin
                if (~gdc_poll_seen) begin
                    $display("  %8t  IN  from %04X  (poll begins, eu_pc %05X)",
                             $time, cpu_address[15:0], eu_pc);
                    gdc_poll_seen <= 1'b1;
                end
                if (gdc60_n < 48) begin
                    $display("  %8t  IN60 -> %02X  (vsync %b, pc %05X)", $time,
                             io60_live, crt_vsync_mock, eu_pc);
                    gdc60_n <= gdc60_n + 1;
                end
            end else begin
                gdc_poll_seen <= 1'b0;
                $display("  %8t  IN  from %04X", $time, cpu_address[15:0]);
            end
        end

        // Boot-path vector fetches: a read of IVT[1B]/[1E]/[1F] names both the
        // call site (eu_pc) and the handler the call lands on -- a resident
        // handler, an int-0xC6 stub and a dead far jump all look identical in
        // the port log without this.
        if (~mem_rd_n && (cpu_address == 20'h0006C
                      ||  cpu_address == 20'h00078
                      ||  cpu_address == 20'h0007C))
            $display("  %8t  INT vector[%02X] = %02X%02X:%02X%02X  (eu_pc %05X)",
                     $time, cpu_address[6:0] >> 2,
                     ram[cpu_address + 3], ram[cpu_address + 2],
                     ram[cpu_address + 1], ram[cpu_address], eu_pc);

        // Whether an int-0x1b call even reaches the resident handler. The FDC
        // service block runs FF2C0-FF7FF; entry and exit get one line each,
        // and a call that never lands here leaves exactly the no-I/O gap the
        // last run's IPL window showed.
        if (eu_pc >= 20'hFF2C0 && eu_pc <= 20'hFF7FF) begin
            if (~in_1b_region) begin
                in_1b_region <= 1'b1;
                $display("  %8t  int1b region <- pc %05X  ax %04X bx %04X dx %04X",
                         $time, eu_pc, eu_ax, eu_bx, eu_dx);
            end
        end else if (in_1b_region) begin
            in_1b_region <= 1'b0;
            $display("  %8t  int1b region -> pc %05X  ax %04X",
                     $time, eu_pc, eu_ax);
        end

        // I/O write, on the trailing edge.
        if (io_wr_n & ~io_wr_d) begin
            if (io_n < 64) io_port_hist[io_n] <= cpu_address[15:0];
            io_n <= io_n + 1;
            if (cpu_address[15:0] == 16'h043D) begin
                saw_043d  <= 1'b1;
                last_043d <= cpu_data_bus;
                if      (cpu_data_bus == 8'h10) itf_bank <= 1'b1;
                else if (cpu_data_bus == 8'h12) itf_bank <= 1'b0;
                // What the low-RAM bank-switch stub actually contains.
                //
                // The ITF cannot switch the ROM out from under its own
                // fetches, so it runs the switch from a copy in segment 0 --
                // the bench sees CS go F800 -> 0000 with the PC at 0x008D6,
                // the SAME offset the routine has in the ROM (F88D6). Whether
                // that copy is there is the whole question: after the switch
                // the CPU executes zeros from 0x00000 and wraps the segment
                // forty-eight times before the machine restarts.
                //
                // Printed at the OUT rather than at the jump, so it shows the
                // memory as the stub itself saw it.
                $write("  %8t  stub 008D0:", $time);
                for (int sb = 0; sb < 32; sb++) $write(" %02X", ram[20'h008D0 + sb]);
                $write("\n             ROM  F88D0:");
                for (int sb = 0; sb < 32; sb++) $write(" %02X", rom_byte(20'hF88D0 + sb));
                $write("\n");
                $display("  %8t  OUT 043D, %02X   -> itf_bank %0d",
                         $time, cpu_data_bus, (cpu_data_bus == 8'h12) ? 0 : 1);
            end
            // FDC window: the byte stream the firmware panel shows on
            // hardware, so the sim's sequence can be diffed against it.
            if (cpu_address[15:8] == 8'h00
                && (cpu_address[7:0] == 8'h90 || cpu_address[7:0] == 8'h92
                 || cpu_address[7:0] == 8'h94 || cpu_address[7:0] == 8'h96
                 || cpu_address[7:0] == 8'hBE || cpu_address[7:0] == 8'hC8
                 || cpu_address[7:0] == 8'hCA || cpu_address[7:0] == 8'hCC
                 || cpu_address[7:0] == 8'hCE))
                $display("  %8t  FDC <- %04X, %02X  (eu_pc %05X)",
                         $time, io_wr_addr_q, write_to_fdd, eu_pc);
            // GDC command/parameter stream, both heads -- the cursor bug
            // lives in what the BIOS actually writes to 60/62/A0/A2, not in
            // what we think it writes. CMD marks the a1=1 (command) port.
            if (cpu_address[15:0] == 16'h0060 || cpu_address[15:0] == 16'h0062
             || cpu_address[15:0] == 16'h00A0 || cpu_address[15:0] == 16'h00A2)
                $display("  %8t  GDC %s <- %02X  (eu_pc %05X)",
                         $time,
                         (cpu_address[15:0] == 16'h0060) ? "m.par"
                       : (cpu_address[15:0] == 16'h0062) ? "m.CMD"
                       : (cpu_address[15:0] == 16'h00A0) ? "s.par"
                       : "s.CMD",
                         io_wr_data_q, eu_pc);
        end
    end

    // ---- 8253, as the chipset wires it --------------------------------------
    //
    // The counter test at FD873 is the first thing in this BIOS that demands
    // an ANSWER rather than a port write: load FF, latch, read, and halt if
    // the read matches the load -- the signature of a counter that never
    // counts. So the bench carries the real chip model, with counter 2's gate
    // as a plusarg: +gate2=0 is the AT wiring the machine died on (gate from
    // 8255 port B bit 0, which the BIOS has not written at that point); the
    // default 1 is the PC-98 wiring the fix restores.
    logic gate2 = 1'b1;
    initial begin
        int v;
        if ($value$plusargs("gate2=%d", v)) gate2 = (v != 0);
    end

    logic timer_clock = 1'b0;
    always_ff @(posedge clk_chipset)
        if (peripheral_ce) timer_clock <= ~timer_clock;

    wire [7:0] pit_dout;
    wire pit_iocycle = (~io_rd_n | ~io_wr_n) & cpu_address[0]
                     & (cpu_address[7:4] == 4'h7) & ~cpu_address[9] & ~cpu_address[8];

    logic timer_out0;

    i8253 u_pit (
        .clock            (clk_chipset),
        .reset            (reset),
        .chip_select_n    (~pit_iocycle),
        .read_enable_n    (io_rd_n),
        .write_enable_n   (io_wr_n),
        .address          (cpu_address[2:1]),
        .data_bus_in      (cpu_data_bus),
        .data_bus_out     (pit_dout),

        .counter_0_clock  (timer_clock), .counter_0_gate (1'b1),
        .counter_0_out    (timer_out0),
        .counter_1_clock  (timer_clock), .counter_1_gate (1'b1),
        .counter_1_out    (),
        .counter_2_clock  (timer_clock), .counter_2_gate (gate2),
        .counter_2_out    ()
    );

    // ---- the DMA controller -------------------------------------------------
    //
    // tb_fdd_dma_model carries the guest-visible surface of the uPD71071:
    // the DMA register test at FD8E6 writes each odd port 01-0F twice (LSB,
    // MSB through the shared byte pointer) and reads it back the same way,
    // and the BIOS's per-read channel setup (mode, address, count, page,
    // unmask) lands in registers that actually move a byte per FDC DRQ --
    // the path the HDM boot lives on.
    // Odd 0x01-0x1F, the whole uPD71071 map -- matching PERIPHERALS'
    // dma_chip_select_n, which reaches all sixteen registers. The page
    // window is the odd 0x21-0x2F the arbiter decodes.
    wire        dma_iocycle = (~io_rd_n | ~io_wr_n) & cpu_address[0]
                            & (cpu_address[7:5] == 3'h0) & ~cpu_address[9]
                            & ~cpu_address[8];
    wire        dma_page_iocycle = (~io_rd_n | ~io_wr_n) & cpu_address[0]
                            & (cpu_address[7:4] == 4'h2) & ~cpu_address[9]
                            & ~cpu_address[8];

    // tb_fdd_dma_model: the stub grown into a transfer engine -- the BIOS's
    // mode/address/count/page/unmask writes land in real registers, and an
    // unmasked channel moves one byte per DRQ, TC on the last. The sector
    // feeder inside it is fdd_poll()/push_sector() in miniature.
    wire       fdc_dreq_w, fdc_ack_p, fdc_tc_p;
    wire       fdc_dmae_w;   // the glue's 0x94 bit-4 (DMAE) DRQ gate
    wire [7:0] fdc_dma_w, fdc_dma_r;
    wire [1:0] fdd_req_w;
    wire [15:0] fdd_mgmt_rdata;
    wire        feed_wr_m, feed_rd_m;
    wire  [3:0] feed_addr_m;
    wire [15:0] feed_wdata_m;
    wire [14:0] feed_lba;
    int         feed_idx;
    wire        dma_mem_wr;
    wire [19:0] dma_mem_addr;
    wire  [7:0] dma_mem_wd;

    logic        media_1024 = 1'b0;
    logic  [7:0] fdd_img [0:1572863];
    int          fdd_img_len = -1;
    initial begin
        string p; int fd;
        if ($value$plusargs("fddimg=%s", p)) begin
            fd = $fopen(p, "rb");
            if (fd) fdd_img_len = $fread(fdd_img, fd);
            $fclose(fd);
            $display("fdd image %s: %0d bytes", p, fdd_img_len);
        end
    end
    wire [7:0] feed_byte = (fdd_img_len > 0
                            && (feed_lba * (media_1024 ? 1024 : 512) + feed_idx) < fdd_img_len)
                          ? fdd_img[feed_lba * (media_1024 ? 1024 : 512) + feed_idx] : 8'hE5;

    always_ff @(posedge clk_chipset)
        if (dma_mem_wr) ram[dma_mem_addr] <= dma_mem_wd;

    wire [7:0] dma_dout;
    tb_fdd_dma_model u_dma (
        .clk        (clk_chipset),
        .io_wr      ((dma_iocycle | dma_page_iocycle) & ~io_wr_n),
        .io_rd      (dma_iocycle & ~io_rd_n),
        .io_addr    (cpu_address[7:0]),
        .io_wdata   (cpu_data_bus),
        .io_rdata   (dma_dout),
        .drq        (fdc_dreq_w & fdc_dmae_w),
        .dack       (fdc_ack_p),
        .tc         (fdc_tc_p),
        .ddata_i    (fdc_dma_w),
        .ddata_o    (fdc_dma_r),
        .mem_wr     (dma_mem_wr),
        .mem_addr   (dma_mem_addr),
        .mem_wdata  (dma_mem_wd),
        .mem_rdata  (ram[dma_mem_addr]),
        .feed_en    (1'b1),
        .sec_req    (fdd_req_w),
        .mgmt_wr    (feed_wr_m),
        .mgmt_addr  (feed_addr_m),
        .mgmt_wdata (feed_wdata_m),
        .mgmt_rd    (feed_rd_m),
        .mgmt_rdata (fdd_mgmt_rdata),
        .media_1024 (media_1024),
        .feed_lba   (feed_lba),
        .feed_idx   (feed_idx),
        .feed_byte  (feed_byte)
    );

    // ---- 8259 pair, as the chipset wires them -------------------------------
    //
    // Master at 0000-0007 even, slave at 0008-000F even, the slave's INT on
    // the master's IRQ7 (the BIOS programs ICW3 0x80 / slave ID 7), the timer
    // on IRQ0, and the cascade lines closed so an acknowledge can pull the
    // vector from the right chip. The IMR test at FDA4F writes 0 and FF to
    // both chips and reads both back; the interrupt test at FDAA9 unmask IRQ0,
    // loads counter 0 with 0x20, and waits for the handler at FD80:02BC to
    // raise AH -- INT 08, end to end.
    wire pic1_iocycle = (~io_rd_n | ~io_wr_n) & ~cpu_address[0]
                      & (cpu_address[7:3] == 5'b00000) & ~cpu_address[9]
                      & ~cpu_address[8];
    wire pic2_iocycle = (~io_rd_n | ~io_wr_n) & ~cpu_address[0]
                      & cpu_address[3] & (cpu_address[7:4] == 4'h0)
                      & ~cpu_address[9] & ~cpu_address[8];

    // VSYNC stand-in: the machine's raster raises IRQ2 once per frame, and
    // the BIOS's FED23 sequence unmasks it (port 0x02, bit 2) then waits at
    // FED44 for the handler it installed on INT 0x0A. The GDC status waits
    // at FDBB3/FDC3E poll the same flag, so the pulse is held for a real
    // retrace's worth of clocks -- a 3-clock blip is too narrow for the
    // BIOS's polling loop to ever see.
    logic [19:0] crt_period_cnt = 20'd0;
    logic [15:0] crt_pulse_cnt  = 16'd0;
    logic        crt_vsync_mock = 1'b0;
    logic        vsync_mock_d   = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (crt_pulse_cnt == 16'd0) begin
            crt_period_cnt <= crt_period_cnt + 20'd1;
            if (crt_period_cnt >= 20'd760_000) begin
                crt_vsync_mock  <= 1'b1;
                crt_pulse_cnt   <= 16'd1;
                crt_period_cnt  <= 20'd0;
            end
        end else begin
            crt_pulse_cnt <= crt_pulse_cnt + 16'd1;
            if (crt_pulse_cnt >= 16'd20_000) begin   // ~460 us, like a retrace
                crt_vsync_mock <= 1'b0;
                crt_pulse_cnt  <= 16'd0;
                $display("  %8t  VSYNC low", $time);
            end
        end
        if (crt_vsync_mock & ~vsync_mock_d)
            $display("  %8t  VSYNC high", $time);
        vsync_mock_d <= crt_vsync_mock;
    end

    wire [7:0] pic1_dout, pic2_dout;
    wire       pic1_to_cpu_buf, pic2_to_cpu;
    wire       pic1_data_bus_io, pic2_data_bus_io;
    wire [2:0] pic1_cascade_out;

    i8259 u_pic1 (
        .clock            (clk_chipset),
        .reset            (reset),
        .chip_select_n    (~pic1_iocycle),
        .read_enable_n    (io_rd_n),
        .write_enable_n   (io_wr_n),
        .address          (cpu_address[1]),
        .data_bus_in      (cpu_data_bus),
        .data_bus_out     (pic1_dout),
        .data_bus_io      (pic1_data_bus_io),
        .cascade_in       (3'b000),
        .cascade_out      (pic1_cascade_out),
        .cascade_io       (),
        .slave_program_n  (1'b1),
        .interrupt_acknowledge_n (inta_n),
        .interrupt_to_cpu (pic1_to_cpu_buf),
        .external_irr_clear (8'h00),
        .interrupt_request({pic2_to_cpu, 4'b0, crt_vsync_mock, 1'b0, timer_out0})
    );

    i8259 u_pic2 (
        .clock            (clk_chipset),
        .reset            (reset),
        .chip_select_n    (~pic2_iocycle),
        .read_enable_n    (io_rd_n),
        .write_enable_n   (io_wr_n),
        .address          (cpu_address[1]),
        .data_bus_in      (cpu_data_bus),
        .data_bus_out     (pic2_dout),
        .data_bus_io      (pic2_data_bus_io),
        .cascade_in       (pic1_cascade_out),
        .cascade_out      (),
        .cascade_io       (),
        .slave_program_n  (1'b0),
        .interrupt_acknowledge_n (inta_n),
        .interrupt_to_cpu (pic2_to_cpu),
        .external_irr_clear (8'h00),
        .interrupt_request({4'b0, fdc_irq3, cc_irq2 | fdc_irq2, 2'b0})
    );

    // Latched the way PERIPHERALS latches it, on the CPU clock's falling
    // enable, so the bench sees the same edge the core will.
    logic pic1_to_cpu = 1'b0;
    always_ff @(posedge clk_chipset)
        if (cpu_ce_negedge) pic1_to_cpu <= pic1_to_cpu_buf;

    // How far the CRT interrupt gets: edge seen, INT raised, INTR delivered.
    int  crt_edges = 0, int_rises = 0;
    logic irr2_prev = 1'b0, int_prev = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (u_pic1.interrupt_request_register[2] & ~irr2_prev) crt_edges <= crt_edges + 1;
        if (pic1_to_cpu_buf & ~int_prev)                        int_rises <= int_rises + 1;
        irr2_prev <= u_pic1.interrupt_request_register[2];
        int_prev  <= pic1_to_cpu_buf;
    end

    // INTA count: how many acknowledges the CPU issued. One means the first
    // interrupt reached the INTA pair; the handler ran if the EU ever stands
    // on FD80:02BC or beyond FDAB1.
    int inta_count = 0;
    logic inta_d = 1'b1;
    always_ff @(posedge clk_chipset) begin
        if (~inta_n) begin
            if (inta_count == 0) $display("  %8t  INTA #1", $time);
            if (inta_d) $display("  %8t  INTA  vector %02X  pic2_int=%b irrg=%02X isrg=%02X imr=%02X casc=%b",
                                 $time, din, pic2_to_cpu,
                                 u_pic1.interrupt_request_register,
                                 u_pic1.in_service_register,
                                 u_pic1.interrupt_mask,
                                 pic1_cascade_out);
            inta_count <= inta_count + 1;
        end
        inta_d <= inta_n;
    end

    // Segment transfers: when CS changes, where the EU went matters more
    // than where it was. A stray vector lands the CPU in RAM.
    logic [15:0] eu_cs_d = 16'hFFFF;
    int cs_tr_n = 0;
    always_ff @(posedge clk_chipset) begin
        eu_cs_d <= eu_cs;
        if (eu_cs != eu_cs_d && cs_tr_n < 2000) begin
            cs_tr_n <= cs_tr_n + 1;
            if (cs_tr_n < 400)
                $display("  %8t  CS %04X -> %04X  (pc %05X)", $time, eu_cs_d, eu_cs, eu_pc);
        end
    end

    // ---- keyboard: the real 8251 model, the shipped RTL -----------------------
    //
    // pc98_kbd8251.sv is the model PERIPHERALS instantiates; running it here
    // puts the actual RTL against the actual ROM sequence. Default OFF keeps
    // the no-keyboard machine this bench has always been; +kbd8251=1 wires
    // it in with its shipped ~10 ms ACK delay.
    logic kbd8251_en = 1'b0;
    initial begin
        int v;
        if ($value$plusargs("kbd8251=%d", v)) kbd8251_en = (v != 0);
    end

    logic       kbd8251_read_select;
    logic [7:0] kbd8251_read_data;
    wire        kbd8251_irq;

    pc98_kbd8251 u_kbd8251 (
        .clock              (clk_chipset),
        .reset              (reset),
        .ctrl_write_strobe  (kbd8251_en & ~io_wr_n & (cpu_address[15:0] == 16'h0043)),
        .data_read_strobe   (kbd8251_en & ~io_rd_n & (cpu_address[15:0] == 16'h0041)),
        .stat_read_strobe   (kbd8251_en & ~io_rd_n & (cpu_address[15:0] == 16'h0043)),
        .data_in            (cpu_data_bus),
        .read_select        (kbd8251_read_select),
        .read_data          (kbd8251_read_data),
        .irq                (kbd8251_irq)
    );

    wire kbd_stat_iocycle = kbd8251_read_select & (cpu_address[15:0] == 16'h0043);
    wire kbd_data_iocycle = kbd8251_read_select & (cpu_address[15:0] == 16'h0041);

    // Watch the model's innards: whether the edge armed, when the ACK lands.
    logic kbd_rx_full_d = 1'b0;
    always_ff @(posedge clk_chipset) begin
        kbd_rx_full_d <= u_kbd8251.rx_full;
        if (u_kbd8251.rx_full & ~kbd_rx_full_d)
            $display("  %8t  KBD ACK landed (rx_full -> 1)", $time);
    end
    // And its state at every chunk line: cmd_q/ack_timer tell whether the
    // break edge was even seen.
    task automatic kbd_state_dump;
        begin
            if (kbd8251_en)
                $display("        kbd8251: cmd %02X  timer %0d  rx_full %b  rx %02X",
                         u_kbd8251.cmd_q, u_kbd8251.ack_timer,
                         u_kbd8251.rx_full, u_kbd8251.rx_q);
        end
    endtask

    // ---- 2DD drive control (0xCC) and a minimal FDC --------------------------
    //
    // The same shapes PERIPHERALS models, so the bench walks the machine's
    // FDD sequence: the 0xCC latch with its motor bit and XTMASK timer into
    // the slave's IRQ2, and a uPD765 that counts command bytes, answers
    // "no drive", and interrupts the slave's IRQ3 on RECALIBRATE. The timer
    // is shortened for the bench -- the real 100 ms costs 4.3 M clocks a
    // trigger, and the BIOS only cares that the interrupt comes eventually.
    // +ccms=N stretches it back toward the real thing.
    logic [7:0] cc_latch  = 8'h00;
    logic       cc_trig_q = 1'b0;
    logic [22:0] cc_timer = 23'd0;
    logic       cc_armed  = 1'b0;
    logic       cc_irq2   = 1'b0;
    int         cc_ticks  = 86_000;
    initial begin
        int ms;
        if ($value$plusargs("ccms=%d", ms)) cc_ticks = ms * 42_955;
    end
    wire cc_iowrite = ~io_wr_n & (cpu_address[15:0] == 16'h00CC);
    wire cc_ioread  = ~io_rd_n & (cpu_address[15:0] == 16'h00CC);
    always_ff @(posedge clk_chipset) begin
        cc_trig_q <= cc_latch[0];
        if (cc_iowrite) cc_latch <= cpu_data_bus;
        if (cc_latch[0] & ~cc_trig_q) begin
            cc_armed <= 1'b1;
            cc_timer <= 23'd0;
        end
        if (cc_armed) begin
            if (cc_timer >= cc_ticks[22:0]) begin
                cc_armed <= 1'b0;
                cc_irq2  <= cc_latch[2];
            end else
                cc_timer <= cc_timer + 23'd1;
        end else if (cc_irq2)
            cc_irq2 <= 1'b0;
    end

    // The floppy controller: THE one from the chipset, instantiated, not a
    // copy of it living here. Four defects came out of this model in one
    // session and every one of them had to be fixed twice by hand.
    wire       fdc_irq3, fdc_irq2;

    // THE REAL PAIR, not the stub: pc98_fdc_glue in front of floppy.v, wired
    // the way PERIPHERALS wires them -- the write decoded from a port latched
    // while the write is on the bus, the read strobed at the start of the
    // read, the address/strobe/byte to floppy.v all registered together. The
    // stub answered a shape of its own and could not have shown any of the
    // four defects the hardware panel has cost us this week.
    logic prev_io_wr_n = 1'b1, prev_io_rd_n = 1'b1;
    always_ff @(posedge clk_chipset) begin
        prev_io_wr_n <= io_wr_n;
        prev_io_rd_n <= io_rd_n;
    end

    logic [15:0] io_wr_addr_q = 16'h0000;
    always_ff @(posedge clk_chipset)
        if (~io_wr_n) io_wr_addr_q <= cpu_address[15:0];

    wire        fdc_wr_edge  = io_wr_n & ~prev_io_wr_n;
    wire [15:0] fdc_addr_eff = fdc_wr_edge ? io_wr_addr_q : cpu_address[15:0];
    wire        fdc_win_eff  = (fdc_addr_eff[15:8] == 8'h00);

    wire fdd_fifo_win = fdc_win_eff & ((fdc_addr_eff[7:0] == 8'h90)
                                     |  (fdc_addr_eff[7:0] == 8'h92)
                                     |  (fdc_addr_eff[7:0] == 8'hC8)
                                     |  (fdc_addr_eff[7:0] == 8'hCA));
    wire fdd_ctrl_win = fdc_win_eff & ((fdc_addr_eff[7:0] == 8'h94)
                                     |  (fdc_addr_eff[7:0] == 8'hCC));
    wire fdd_mode_win = fdc_win_eff &  (fdc_addr_eff[7:0] == 8'hBE);

    wire       fdc_sel_stat = fdd_fifo_win & ~fdc_addr_eff[1];
    wire       fdc_sel_data = fdd_fifo_win &  fdc_addr_eff[1];
    wire [2:0] fdc_glue_addr;
    wire       fdc_glue_write, fdc_glue_read;
    wire [7:0] fdc_glue_wdata, fdc_ctrl_rb, fdc_mode_rb;
    wire       fdc_group_live;
    wire [7:0] fdd_readdata_wire;
    wire       fdd_irq_wire;
    wire       fdd_busy_wire;

    logic [7:0] write_to_fdd = 8'h00;
    always_ff @(posedge clk_chipset)
        if (~io_wr_n) write_to_fdd <= cpu_data_bus;

    pc98_fdc_glue u_pc98_fdc_glue (
        .clk           (clk_chipset),
        .rst           (reset),
        .sel_stat      (fdc_sel_stat),
        .sel_data      (fdc_sel_data),
        .sel_ctrl      (fdd_ctrl_win),
        .sel_mode      (fdd_mode_win),
        .sel_mode144   (1'b0),
        .port_2dd      (fdc_addr_eff[6]),
        .wr_stb        (fdc_wr_edge),
        .wr_data       (write_to_fdd),
        .rd_stb        (~io_rd_n & prev_io_rd_n & fdd_fifo_win),
        .fd_addr       (fdc_glue_addr),
        .fd_write      (fdc_glue_write),
        .fd_read       (fdc_glue_read),
        .fd_wdata      (fdc_glue_wdata),
        .fd_irq        (fdd_irq_wire),
        .fd_busy       (fdd_busy_wire),
        .ctrl_readback (fdc_ctrl_rb),
        .mode_readback (fdc_mode_rb),
        .reg144_readback (),
        .group_live    (fdc_group_live),
        .irq_2hd       (fdc_irq3),
        .irq_2dd       (fdc_irq2),
        .dma_enable    (fdc_dmae_w)
    );

    // Read side follows the glue combinationally and the held byte is the
    // FDC's combinational answer captured at the strobe -- the byte has to
    // be on the bus before the CPU's read-data latch, not three clocks
    // after the strobe (on the old nuV30 bench the core's T2->T3 sample
    // raced the staged path and every other read came back one byte
    // stale).  The write path keeps its staging: write strobes arrive at
    // cycle end and need the registered address.
    wire        fdd_io_read  = fdc_glue_read;
    wire  [2:0] fdd_io_addr_rd = fdc_glue_addr;
    logic       fdd_io_read_1;
    logic [2:0] fdd_io_addr_rd_q;
    logic       fdd_io_write;
    logic [2:0] fdd_io_addr_wr;
    logic [7:0] fdd_io_writedata;
    always_ff @(posedge clk_chipset) begin
        fdd_io_read_1    <= fdd_io_read;
        fdd_io_addr_rd_q <= fdc_glue_addr;
        fdd_io_write     <= fdc_glue_write;
        fdd_io_addr_wr   <= fdc_glue_addr;
        fdd_io_writedata <= fdc_glue_wdata;
    end
    wire [2:0] fdd_io_address = fdd_io_write ? fdd_io_addr_wr
                                           : fdd_io_addr_rd;

    logic [7:0] fdd_readdata = 8'hFF;
    always_ff @(posedge clk_chipset)
        if (fdd_io_read) fdd_readdata <= u_floppy.io_readdata_prepare;

    // +media inserts a 2HD disk in drive 0 through the same mgmt port the
    // core's file loader uses. media_present has no reset in floppy.v, so
    // the write lands after reset and just stays.
    logic        mgmt_wr = 1'b0;
    logic [3:0]  mgmt_addr = 4'd0;
    logic [15:0] mgmt_wdata = 16'd0;
    initial begin
        int v;
        if ($value$plusargs("media=%d", v) && v != 0) begin
            @(negedge reset);
            repeat (20) @(negedge clk_chipset);
            mgmt_addr = 4'd0; mgmt_wdata = 16'd1;    mgmt_wr = 1'b1; @(negedge clk_chipset); mgmt_wr = 1'b0; @(negedge clk_chipset);
            mgmt_addr = 4'd2; mgmt_wdata = 16'd77;   mgmt_wr = 1'b1; @(negedge clk_chipset); mgmt_wr = 1'b0; @(negedge clk_chipset);
            mgmt_addr = 4'd3; mgmt_wdata = 16'd8;    mgmt_wr = 1'b1; @(negedge clk_chipset); mgmt_wr = 1'b0; @(negedge clk_chipset);
            mgmt_addr = 4'd4; mgmt_wdata = 16'd1232; mgmt_wr = 1'b1; @(negedge clk_chipset); mgmt_wr = 1'b0; @(negedge clk_chipset);
            mgmt_addr = 4'd5; mgmt_wdata = 16'd2;    mgmt_wr = 1'b1; @(negedge clk_chipset); mgmt_wr = 1'b0; @(negedge clk_chipset);
            mgmt_addr = 4'd6; mgmt_wdata = 16'd1;    mgmt_wr = 1'b1; @(negedge clk_chipset); mgmt_wr = 1'b0;
            media_1024 = 1'b1;
        end
    end

    // The feeder shares the mgmt port with the +media insert: the insert
    // is long done by the time a sector request can exist.
    wire        mgmt_wr_m    = feed_wr_m | mgmt_wr;
    wire  [3:0] mgmt_addr_m  = feed_wr_m ? feed_addr_m : (feed_rd_m ? feed_addr_m : mgmt_addr);
    wire [15:0] mgmt_wdata_m = feed_wr_m ? feed_wdata_m : mgmt_wdata;
    wire        mgmt_rd_m    = feed_rd_m;

    floppy #(.NOT_READY_ENDS_COMMAND (1)) u_floppy (
        .clk            (clk_chipset),
        .rst_n          (~reset),
        .dma_req        (fdc_dreq_w), .dma_ack (fdc_ack_p), .dma_tc (fdc_tc_p),
        .dma_readdata   (fdc_dma_r), .dma_writedata (fdc_dma_w),
        .irq            (fdd_irq_wire),
        .busy           (fdd_busy_wire),
        .io_address     (fdd_io_address),
        .io_read        (fdd_io_read),
        .io_readdata    (fdd_readdata_wire),
        .io_write       (fdd_io_write),
        .io_writedata   (fdd_io_writedata),
        .mgmt_address   (mgmt_addr_m),
        .mgmt_fddn      (1'b0),
        .mgmt_write     (mgmt_wr_m),
        .mgmt_writedata (mgmt_wdata_m),
        .mgmt_read      (mgmt_rd_m),
        .mgmt_readdata  (fdd_mgmt_rdata),
        .wp             (2'b00),
        .clock_rate     (28'd42_954_545),
        .turbo          (1'b0),
        .request        (fdd_req_w),
        .dbg_cmd_accepts(), .dbg_cmd_drops (), .dbg_reply_left (), .dbg_xfer ()
    );

    // What the guest sees on a read: the live window answers from floppy.v,
    // the dead one 0xFF, and 0x94/0xCC/0xBE answer out of the glue.
    wire fdc_msr_sel  = ~io_rd_n & fdc_sel_stat;
    wire fdc_fifo_sel = ~io_rd_n & fdc_sel_data;
    wire fdc_ctrl_sel = ~io_rd_n & fdd_ctrl_win;
    wire fdc_mode_sel = ~io_rd_n & fdd_mode_win;
    wire [7:0] fdc_msr  = fdc_group_live ? fdd_readdata : 8'hFF;
    wire [7:0] fdc_fifo = fdc_group_live ? fdd_readdata : 8'hFF;

    // The conversation, one line per byte, plus every interrupt edge.
    logic fdd_irq_q = 1'b0;
    always_ff @(posedge clk_chipset) begin
        fdd_irq_q <= fdd_irq_wire;
        if (fdd_io_write && fdd_io_address == 3'd5)
            $display("  %8t  FDC <- %02X", $time, fdd_io_writedata);
        if (fdd_io_write && fdd_io_address == 3'd2)
            $display("  %8t  FDC DOR %02X", $time, fdd_io_writedata);
        if (fdd_io_read_1 && fdd_io_addr_rd_q == 3'd5)
            $display("  %8t  FDC -> %02X", $time, fdd_readdata);
        if (fdd_irq_wire & ~fdd_irq_q)
            $display("  %8t  FDC IRQ up   (MSR %02X)", $time, u_floppy.io_readdata);
    end

    // Text GDC status at 0x60, shaped exactly like PERIPHERALS' gdc_status:
    // bit 5 rides the vertical retrace (the FDBB3 wait), bit 2 is a constant
    // one (the FDE00C parameter-path wait passes instantly), bit 0 one too.
    wire gdc_stat_iocycle = ~io_rd_n & ((cpu_address[15:0] == 16'h0060)
                                      |  (cpu_address[15:0] == 16'h00A0));
    wire [7:0] gdc_status_mock = 8'h05 | (crt_vsync_mock ? 8'h20 : 8'h00);


    // ---- execution trace, from inside the CPU -------------------------------
    //
    // Bus fetches are prefetch, not execution. Every conditional in the ITF's
    // flag test is a two-byte jump to itself, so a failed test spins entirely
    // inside the prefetch queue and puts nothing on the bus: the fetch trace can
    // say where the CPU stopped FETCHING and not where it stopped EXECUTING.
    //
    // The queue's read pointer is the EU's instruction pointer, so CS:PFQ_ADDR
    // is the real program counter. The dbg_regs view
    // ({psw,ip,ds,ss,cs,es,di,si,bp,sp,bx,dx,cx,ax}, retired-instruction
    // granularity) is the same one the old V30 bench traced. Zet exposes no
    // dbg_regs, so eu_pc reads the core's linear-PC pin directly.
    wire [15:0] eu_cs = zet_pc[19:4];   // for the CS-change trace only
    wire [19:0] eu_pc = zet_pc;

    // First-cycles bus trace: what the Zet actually asked for and got.
    int zet_tr_n = 0;
    always_ff @(posedge clk_chipset) begin
        if (zet_tr_n < 200) begin
            if (mem_rd_d & ~mem_rd_n) begin
                $display("  %8t  ZRD %05X -> %02X (wb adr %05x sel %b ack %b)",
                         $time, cpu_address, din, {zwb_adr,1'b0}, zwb_sel, zwb_ack);
                zet_tr_n <= zet_tr_n + 1;
            end
            if (mem_wr_n & ~mem_wr_d) begin
                $display("  %8t  ZWR %05X <- %02X", $time, cpu_address, mem_wr_data_q);
                zet_tr_n <= zet_tr_n + 1;
            end
            if (io_rd_d & ~io_rd_n) begin
                $display("  %8t  ZIRD %04X -> %02X", $time, cpu_address[15:0], din);
                zet_tr_n <= zet_tr_n + 1;
            end
            if (io_wr_n & ~io_wr_d) begin
                $display("  %8t  ZIWR %04X <- %02X", $time, cpu_address[15:0], io_wr_data_q);
                zet_tr_n <= zet_tr_n + 1;
            end
        end
    end
    always_ff @(posedge clk_chipset)
        if (zwb_inta && zet_tr_n < 300) begin
            $display("  %8t  ZINTA asserted (vec on wb_dat_i %04X)", $time, zwb_dat_i);
            zet_tr_n <= zet_tr_n + 1;
        end

    // Wishbone settle trace: while stb is up, watch the master's tracked
    // outputs converge to the exec stage's combinational operands.
    int zwb_tr_n = 0;
    always_ff @(posedge zet_clk) begin
        if (!cpu_reset_w && zwb_stb && zwb_tr_n < 600) begin
            $display("  %8t  ZWB %s adr %05x sel %b dat_o %04x c_dat %04x c_adr %05x age %0d",
                     $time, zwb_we ? "WR" : "RD", {zwb_adr,1'b0}, zwb_sel,
                     zwb_dat_o, u_cpu.cpu_dat_o, u_cpu.cpu_adr_o,
                     u_bridge.req_age);
            zwb_tr_n <= zwb_tr_n + 1;
        end
        if (!cpu_reset_w && zwb_stb && zwb_ack && !zwb_we && zwb_tr_n < 1200) begin
            $display("  %8t  ZAK RD adr %05x sel %b dat_i %04x c_dat_i %04x rdw %04x imm_l %04x",
                     $time, {zwb_adr,1'b0}, zwb_sel, zwb_dat_i,
                     u_cpu.cpu_dat_i, u_bridge.rd_word, u_cpu.core.fetch.imm_l);
            zwb_tr_n <= zwb_tr_n + 1;
        end
    end

    // Arm trace: what the byte engine actually latched for each byte.
    int zarm_tr_n = 0;
    always_ff @(posedge clk_chipset) begin
        if (!cpu_reset_w && u_bridge.bstate == 0 && u_bridge.srv_any
            && zarm_tr_n < 600) begin
            $display("  %8t  ARM bs %0d adr %05x dat %04x idx %0d -> bus %02x ad_out %05x",
                     $time, u_bridge.srv_bs, u_bridge.srv_addr,
                     u_bridge.srv_data, u_bridge.byte_idx,
                     u_bridge.srv_byte_data, u_bridge.srv_byte_addr);
            zarm_tr_n <= zarm_tr_n + 1;
        end
    end


    logic [19:0] eu_pc_d = 20'hFFFFF;
    int          eu_steps = 0, eu_traced = 0;
    logic [19:0] eu_ring [0:127];
    int          eu_ring_w = 0;

    // ---- the CPU-reset resume, watched end to end ---------------------------
    //
    // The ITF saves its return state (F9475: push cs; push 1497; [0406]=ss;
    // [0404]=sp), asks the CPU to reset itself through port 0F0h, and on the
    // way back in reloads SS:SP from those words and RETFs (F8069). One-shot
    // dumps at the save and at the retf, so what the four words held at both
    // ends of the reset is in the log.
    int  save_seen = 0, resume_seen = 0;
    wire [19:0] resume_stack = {eu_ss[15:0], 4'd0}
                             + {4'd0, eu_sp[15:0]};
    always_ff @(posedge clk_chipset) begin
        if (eu_pc == 20'hF9475 && save_seen < 4) begin
            save_seen <= save_seen + 1;
            $display("  %8t  SAVE entry: ss=%04X sp=%04X  [0404]=%02X%02X [0406]=%02X%02X",
                     $time, eu_ss,
                     eu_sp,
                     ram[20'h405], ram[20'h404], ram[20'h407], ram[20'h406]);
        end
        if (eu_pc == 20'hF8069 && resume_seen < 4) begin
            resume_seen <= resume_seen + 1;
            $display("  %8t  RESUME retf: ss=%04X sp=%04X  [0404]=%02X%02X [0406]=%02X%02X",
                     $time, eu_ss,
                     eu_sp,
                     ram[20'h405], ram[20'h404], ram[20'h407], ram[20'h406]);
            $display("        stack: %02X %02X %02X %02X   03F0: %02X..%02X  03F8: %02X..%02X  0400: %02X..%02X  0408: %02X..%02X",
                     ram[resume_stack],     ram[resume_stack + 20'd1],
                     ram[resume_stack + 20'd2], ram[resume_stack + 20'd3],
                     ram[20'h3F0], ram[20'h3F7], ram[20'h3F8], ram[20'h3FF],
                     ram[20'h400], ram[20'h407], ram[20'h408], ram[20'h40F]);
        end
    end

    always_ff @(posedge clk_chipset) begin
        eu_pc_d <= eu_pc;
        if (eu_pc != eu_pc_d) begin
            eu_steps <= eu_steps + 1;
            eu_ring[eu_ring_w[6:0]] <= eu_pc;
            eu_ring_w <= eu_ring_w + 1;
            if (eu_traced < 0) begin
                eu_traced <= eu_traced + 1;
                $display("  %8t  EU %05X", $time, eu_pc);
            end
        end
    end

    // ---- bus fetch trace ---------------------------------------------------
    //
    // Code fetches only, and only when the address moves, so a trace reads as a
    // path rather than as one line per bus cycle. A tight loop shows up as the
    // same few addresses repeating, which is exactly what needs to be seen.
    logic [19:0] last_fetch = 20'hFFFFF;
    int          fetches = 0;
    int          traced  = 0;
    logic [19:0] pc_min = 20'hFFFFF, pc_max = 20'h00000;

    // Where it settles: the last 32 distinct fetch addresses, as a ring.
    logic [19:0] ring [0:31];
    int          ring_w = 0;

    always_ff @(posedge clk_chipset) begin
        if (~mem_rd_n & mem_rd_d & (processor_status == 3'b100)) begin
            fetches <= fetches + 1;
            if (cpu_address != last_fetch) begin
                last_fetch <= cpu_address;
                ring[ring_w[4:0]] <= cpu_address;
                ring_w <= ring_w + 1;
                if (cpu_address < pc_min) pc_min <= cpu_address;
                if (cpu_address > pc_max) pc_max <= cpu_address;
                if (traced < 0) begin
                    traced <= traced + 1;
                    $display("  %8t  fetch %05X  %02X",
                             $time, cpu_address,
                             is_rom(cpu_address) ? rom_byte(cpu_address)
                                                 : ram[cpu_address]);
                end
            end
        end
    end

    // ---- run ---------------------------------------------------------------
    int i, j;
    int chunks = 1200;              // +chunks=N cuts the run short
    initial begin
        for (i = 0; i < 1048576; i = i + 1) ram[i] = 8'h00;
        $readmemh("itf.hex",  itf);
        $readmemh("bios.hex", bios);
        // WORKAROUND (see docs/NUV30_66_VERIFICATION.md
        // and docs/FRANKEN_ROM_LESSON.md): the 0x66 at BIOS.ROM+1 is
        // mid-instruction data in a mixed-generation image. nuV30 executes
        // it silicon-accurately as a 2-byte ModR/M-consuming NOP, which
        // sends the following JA down the wrong path for THIS image's
        // intent; a NOP in its place runs the intended stream. Only patch
        // if present, so a fixed ROM needs no bench edit.
        if (bios[1] == 8'h66) bios[1] = 8'h90;

        $display("ITF  reset vector F8000+7FF0: %02X %02X %02X %02X %02X",
                 itf[16'h7FF0], itf[16'h7FF1], itf[16'h7FF2],
                 itf[16'h7FF3], itf[16'h7FF4]);
        $display("BIOS reset vector E8000+17FF0: %02X %02X %02X %02X %02X",
                 bios[18'h17FF0], bios[18'h17FF1], bios[18'h17FF2],
                 bios[18'h17FF3], bios[18'h17FF4]);
`ifdef REALMEM
        // The images go into the PART, at the addresses RAM.sv maps them to:
        // the BIOS at E8000-FFFFF, the ITF in the shadow at 1F8000 that
        // bios_shadow_flag selects. One guest byte per 16-bit word, which is how
        // RAM.sv stores everything (access_data_in is {8'h00, byte}).
        for (i = 0; i < 98304;  i = i + 1)
            sdr.u_part.poke(20'hE8000 + i, {8'h00, bios[i]});
        for (i = 0; i < 32768;  i = i + 1)
            sdr.u_part.poke(24'h1F8000 + i, {8'h00, itf[i]});
        // The mirror carries the ROM too, so MEMPATH can compare against it.
        $display("REALMEM: images loaded into the part");
`endif

        $display("--- trace (first 400 distinct fetch addresses) ---");

        // +roff=N: hold reset N extra chipset clocks. The CE accumulator is
        // not touched by the CPU reset, so this shifts which edge the first
        // bus cycle lands on -- a cold-boot phase sweep for the speed-0
        // wedge that hardware hits only some of the time.
        begin
            int roff;
            if ($value$plusargs("roff=%d", roff)) repeat (40 + roff) @(posedge clk_chipset);
            else                                 repeat (40) @(posedge clk_chipset);
        end
        reset = 1'b0;

        // One chunk is 5M chipset clocks, which is 116 ms of guest time --
        // NOT one second, and the two runs that read it that way stopped at
        // 4.7 and 2.7 seconds and proved nothing. The machine has to be met
        // AFTER the screen clear, and the clear alone took 8 seconds, so the
        // run needs the full 780 chunks (90 s) the sweep run used, and then
        // some: the memory test was still going at 280 KB when that one ended.
        // +chunks=N cuts it short when the question lives early (the keyboard
        // probe answers inside the first two).
        begin
            int v;
            if ($value$plusargs("chunks=%d", v)) chunks = v;
        end
        for (i = 0; i < chunks; i = i + 1) begin
            repeat (5_000_000) @(posedge clk_chipset);
            $display("  ... %0t  EU %05X  wr %05X-%05X n %0d  tvw %0d",
                     $time, eu_pc,
                     wr_lo_chunk, wr_hi_chunk, wr_n_chunk, tvram_wr_count);
            kbd_state_dump;
            $write("        cx %04X min %04X  ax %04X bx %04X dx %04X  pc:",
                   eu_cx, cx_min_chunk,
                   eu_ax, eu_bx,
                   eu_dx);
            for (j = 0; j < 16; j = j + 1)
                $write(" %05X", pc_ring[(pc_ring_w + j) % 16]);
            $display("");
            // The BIOS equipment/boot bytes the hardware panel cannot reach:
            // [0x480] 2HD flag, [0x55C]/[0x55D] the per-drive tables,
            // [0x494] DISK-EQUIP2, [0x584] DISK_BOOT (the live DAZUA).
            $display("        disk: 480=%02X 485=%02X 492=%02X 493=%02X 494=%02X 55C=%02X 55D=%02X 55E=%02X 584=%02X 4b7=%02X 4b9=%02X 501=%02X 5ae=%02X 5f8=%02X%02X:%02X%02X",
                     ram[20'h480], ram[20'h485], ram[20'h492], ram[20'h493],
                     ram[20'h494], ram[20'h55C], ram[20'h55D], ram[20'h55E],
                     ram[20'h584], ram[20'h4B7], ram[20'h4B9], ram[20'h501],
                     ram[20'h5AE], ram[20'h5FB], ram[20'h5FA],
                     ram[20'h5F9], ram[20'h5F8]);
            $display("        ivt: 1b=%04X:%04X 12=%04X:%04X 13=%04X:%04X 1e=%04X:%04X 1f=%04X:%04X 4b0=%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
                     {ram[20'h6F],ram[20'h6E]}, {ram[20'h6D],ram[20'h6C]},
                     {ram[20'h4B],ram[20'h4A]}, {ram[20'h49],ram[20'h48]},
                     {ram[20'h4F],ram[20'h4E]}, {ram[20'h4D],ram[20'h4C]},
                     {ram[20'h7B],ram[20'h7A]}, {ram[20'h79],ram[20'h78]},
                     {ram[20'h7F],ram[20'h7E]}, {ram[20'h7D],ram[20'h7C]},
                     ram[20'h4B0], ram[20'h4B1], ram[20'h4B2], ram[20'h4B3],
                     ram[20'h4B4], ram[20'h4B5], ram[20'h4B6], ram[20'h4B7],
                     ram[20'h4B8], ram[20'h4B9], ram[20'h4BA], ram[20'h4BB],
                     ram[20'h4BC], ram[20'h4BD], ram[20'h4BE], ram[20'h4BF]);
`ifdef REALMEM
            occ_report();
`endif
            wr_clear_tog = ~wr_clear_tog;
        end

        $display("--- done ---");
        $display("E2E ack reads %0d mismatches (last bad %05X)", ack_rd_mismatches, ack_bad_addr);
        $display("ZET faults    %0d", zet_fault_count);
`ifdef REALMEM
        occ_report();
`endif
        $display("PIT gate2     %0d  (counters now %04X %04X %04X)", gate2,
                 u_pit.u_i8253_Counter_0.count[15:0],
                 u_pit.u_i8253_Counter_1.count[15:0],
                 u_pit.u_i8253_Counter_2.count[15:0]);
        $display("INTA count    %0d", inta_count);
        $display("CRT edges seen %0d, INT rises %0d", crt_edges, int_rises);
        $display("PIC1 irr=%02X isr=%02X imr=%02X int=%b | PIC2 irr=%02X imr=%02X",
                 u_pic1.interrupt_request_register, u_pic1.in_service_register,
                 u_pic1.interrupt_mask, pic1_to_cpu,
                 u_pic2.interrupt_request_register, u_pic2.interrupt_mask);
        $display("[0x53C]=%02X  [0x0542]=%04X:%04X  IVT0A=%04X:%04X",
                 ram[8'h3C],
                 {ram[9'h543],ram[9'h542]}, {ram[9'h545],ram[9'h544]},
                 {ram[9'h2B],ram[9'h2A]}, {ram[9'h2D],ram[9'h2C]});
        $display("IVT 08 : %04X:%04X   IVT 18: %04X:%04X",
                 {ram[8'h23],ram[8'h22]}, {ram[8'h21],ram[8'h20]},
                 {ram[8'h63],ram[8'h62]}, {ram[8'h61],ram[8'h60]});
        $display("TVRAM writes %0d; first row, code words:", tvram_wr_count);
        for (i = 0; i < 16; i = i + 1)
            $display("  cell %02d: code %04X  attr %04X", i,
                     {tvram_code[i*2+1], tvram_code[i*2]},
                     {tvram_attr[i*2+1], tvram_attr[i*2]});
        $display("fetches       %0d", fetches);
        $display("distinct PCs  %0d", ring_w);
        $display("PC range      %05X .. %05X", pc_min, pc_max);
        $display("I/O writes    %0d", io_n);
        for (i = 0; i < (io_n < 64 ? io_n : 64); i = i + 1)
            $display("  io[%0d] %04X", i, io_port_hist[i]);
        $display("port 043D written: %0d  last value %02X  itf_bank %0d",
                 saw_043d, last_043d, itf_bank);
        $display("EU steps      %0d", eu_steps);
        $display("last 128 EU addresses (oldest first):");
        for (i = 0; i < 128; i = i + 1)
            $display("  %05X", eu_ring[(eu_ring_w + i) & 127]);
        // The device-init interpreter's state and the patch program it
        // built: [0x10C4-0x10E6] counters/cursors, [0x10E6-] wait entries,
        // [0x1110-] the device-present bitmap it walks.
        $display("init interp state:");
        for (i = 0; i < 16; i = i + 1)
            $display("  %05X: %02X %02X %02X %02X %02X %02X %02X %02X",
                     20'h10C0+i*16,
                     ram[20'h10C0+i*16+0], ram[20'h10C0+i*16+1],
                     ram[20'h10C0+i*16+2], ram[20'h10C0+i*16+3],
                     ram[20'h10C0+i*16+4], ram[20'h10C0+i*16+5],
                     ram[20'h10C0+i*16+6], ram[20'h10C0+i*16+7],
                     ram[20'h10C0+i*16+8], ram[20'h10C0+i*16+9],
                     ram[20'h10C0+i*16+10], ram[20'h10C0+i*16+11],
                     ram[20'h10C0+i*16+12], ram[20'h10C0+i*16+13],
                     ram[20'h10C0+i*16+14], ram[20'h10C0+i*16+15]);
        $display("disk work area 0x480-0x5A0:");
        for (i = 0; i < 18; i = i + 1)
            $display("  %05X: %02X %02X %02X %02X %02X %02X %02X %02X",
                     20'h480+i*8,
                     ram[20'h480+i*8+0], ram[20'h480+i*8+1],
                     ram[20'h480+i*8+2], ram[20'h480+i*8+3],
                     ram[20'h480+i*8+4], ram[20'h480+i*8+5],
                     ram[20'h480+i*8+6], ram[20'h480+i*8+7]);
        $finish;
    end

endmodule

`default_nettype wire
