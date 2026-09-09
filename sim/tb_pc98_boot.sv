//
// tb_pc98_boot -- run the real ITF on the real 8088 core, and watch where it
// goes.
//
// The hardware says BANK 1: the ITF bank register is still at its reset value,
// so the guest has never executed OUT 043D, 12. Everything upstream of that is
// healthy -- the ROMs load, the softcore runs, the raster runs -- so the
// question is what the ITF does instead, and that is an execution question, not
// a hardware one.
//
// This is the machine reduced to what the question needs: the 8088 core, the
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

    // clk_chipset is 42.954545 MHz; clk_core is twice it, as core_top's PLL
    // makes them.
    logic clk_chipset = 1'b0;
    logic clk_core    = 1'b0;
    always #11.641 clk_chipset = ~clk_chipset;
    always  #5.820 clk_core    = ~clk_core;

    logic reset = 1'b1;

    // ---- clock enables and the CPU pin clock -------------------------------
    wire       clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire       cycle_accrate, shift_read_timing;
    wire [7:0] ccc_div, ccc_dec;
    wire [1:0] ram_rd_wait, ram_wr_wait;
    wire       biu_done;

    XT_CE_Generator u_ce (
        .clock                              (clk_chipset),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (2'b00),      // the boot default, as core_top uses
        .cpu_clk_pin                        (clk_cpu),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .cycle_accrate                      (cycle_accrate),
        .clock_cycle_counter_division_ratio  (ccc_div),
        .clock_cycle_counter_decrement_value (ccc_dec),
        .shift_read_timing                  (shift_read_timing),
        .ram_read_wait_cycle                (ram_rd_wait),
        .ram_write_wait_cycle               (ram_wr_wait)
    );

    // ---- the CPU -----------------------------------------------------------
    wire [19:0] cpu_ad_out;
    wire  [7:0] cpu_data_bus;
    wire  [7:0] din;
    wire  [2:0] processor_status;
    wire        lock_n, s6_3_mux;
    wire  [2:0] SEGMENT;

    i8088 u_cpu (
        .CORE_CLK  (clk_core),
        .CLK       (clk_cpu),
        .RESET     (reset),
        .READY     (1'b1),           // flat memory answers immediately
        .INTR      (pic1_to_cpu),
        .NMI       (1'b0),
        .ad_out    (cpu_ad_out),
        .dout      (cpu_data_bus),
        .din       (din),
        .lock_n    (lock_n),
        .s6_3_mux  (s6_3_mux),
        .s2_s0_out (processor_status),
        .SEGMENT   (SEGMENT),
        .biu_done  (biu_done),
        .cycle_accrate                       (cycle_accrate),
        .clock_cycle_counter_division_ratio  (ccc_div),
        .clock_cycle_counter_decrement_value (ccc_dec),
        .shift_read_timing                   (shift_read_timing)
    );

    // ---- bus controller and address latch ----------------------------------
    wire mem_rd_n, mem_wr_n, adv_mem_wr_n;
    wire io_rd_n,  io_wr_n,  adv_io_wr_n;
    wire inta_n, ale, en_io, en_mem, dt_r_n, den, mce, pden;

    KF8288 u_8288 (
        .clock                           (clk_chipset),
        .cpu_ce_posedge                  (cpu_ce_posedge),
        .cpu_ce_negedge                  (cpu_ce_negedge),
        .reset                           (reset),
        .address_enable_n                (1'b0),
        .command_enable                  (1'b1),
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
    // the BIOS bank, booted directly the way np2 boots it.
    logic itf_bank = 1'b0;

    function automatic logic is_rom(input logic [19:0] a);
        is_rom = (a >= 20'hE8000);
    endfunction

    function automatic logic [7:0] rom_byte(input logic [19:0] a);
        if (a >= 20'hF8000 && itf_bank) rom_byte = itf[a - 20'hF8000];
        else                            rom_byte = bios[a - 20'hE8000];
    endfunction

    // The data bus is combinational, as the chipset's is. Registering it here
    // put a chipset clock between the strobe and the byte, and the core sampled
    // stale data: the first run stalled for seventeen milliseconds in the middle
    // of one instruction's operand fetch.
    assign din = ~mem_rd_n ? (is_rom(cpu_address) ? rom_byte(cpu_address)
                                                  : ram[cpu_address])
                  : ~inta_n       ? ((~pic2_data_bus_io) ? pic2_dout : pic1_dout)
                  : pit_iocycle    ? pit_dout
                  : dma_iocycle    ? dma_dout
                  : pic1_iocycle   ? pic1_dout
                  : pic2_iocycle   ? pic2_dout
                  : kbd_data_iocycle ? 8'h60
                  : kbd_stat_iocycle ? 8'h02
                           : 8'hFF;

    // ---- I/O ---------------------------------------------------------------
    //
    // Reads answer 0xFF: nothing here is modelled, and the point is where the
    // CPU goes, not what it finds. A port that must answer to get past a spin
    // will show up as a spin, which is itself the finding.
    logic [15:0] io_port_hist [0:63];
    int          io_n = 0;
    logic        saw_043d = 1'b0;
    logic [7:0]  last_043d = 8'h00;

    logic io_wr_d = 1'b1, mem_wr_d = 1'b1, mem_rd_d = 1'b1, io_rd_d = 1'b1;
    logic [7:0] mem_wr_data_q = 8'h00;

    always_ff @(posedge clk_chipset) begin
        io_wr_d  <= io_wr_n;
        mem_wr_d <= mem_wr_n;
        mem_rd_d <= mem_rd_n;
        io_rd_d  <= io_rd_n;

        // Write data is valid throughout the command and guaranteed at its
        // END. Sampling cpu_data_bus once on the trailing edge caught the
        // bus already moving on -- the IVT write at FDA76 landed 21 02 23 FD
        // where the BIOS put BC 02 80 FD, and INT 08 went astray on exactly
        // that. Sample continuously while the cycle is live and keep the last.
        if (~mem_wr_n) mem_wr_data_q <= cpu_data_bus;

        // Memory write, on the trailing edge, and never into ROM.
        if (mem_wr_n & ~mem_wr_d & ~is_rom(cpu_address)) begin
            ram[cpu_address] <= mem_wr_data_q;
            // The first page carries the vectors; who touches 0000-0FFF and
            // with what decides whether INT xx lands where the BIOS meant.
            if (cpu_address[19:12] == 8'h00)
                $display("  %8t  RAM[%04X] <= %02X   (eu_pc %05X)",
                         $time, cpu_address[15:0], mem_wr_data_q, eu_pc);
        end

        // I/O reads matter here too: if the ModRM byte of a group opcode is
        // dispatched as an opcode, E4 becomes IN AL,imm8 and shows up as a read
        // from a port the program never names.
        if (io_rd_n & ~io_rd_d)
            $display("  %8t  IN  from %04X", $time, cpu_address[15:0]);

        // I/O write, on the trailing edge.
        if (io_wr_n & ~io_wr_d) begin
            if (io_n < 64) io_port_hist[io_n] <= cpu_address[15:0];
            io_n <= io_n + 1;
            if (cpu_address[15:0] == 16'h043D) begin
                saw_043d  <= 1'b1;
                last_043d <= cpu_data_bus;
                if      (cpu_data_bus == 8'h10) itf_bank <= 1'b1;
                else if (cpu_data_bus == 8'h12) itf_bank <= 1'b0;
                $display("  %8t  OUT 043D, %02X   -> itf_bank %0d",
                         $time, cpu_data_bus, (cpu_data_bus == 8'h12) ? 0 : 1);
            end
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

    KF8253 u_pit (
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

    // ---- 8237 stand-in ------------------------------------------------------
    //
    // The DMA register test at FD8E6 writes each odd port 01-0F twice (LSB,
    // MSB through the shared byte pointer) and reads it back the same way.
    // The real chip's current registers are read/write, so a pair of
    // write-through bytes per port answers it honestly without modelling a
    // whole 8237 the boot never puts in motion.
    logic [7:0] dma_lsb  [0:15];
    logic [7:0] dma_msb  [0:15];
    logic       dma_hi_byte = 1'b0;
    wire  [3:0] dma_reg   = cpu_address[4:1];
    wire        dma_iocycle = (~io_rd_n | ~io_wr_n) & cpu_address[0]
                            & (cpu_address[7:4] == 4'h0) & ~cpu_address[9]
                            & ~cpu_address[8];
    always_ff @(posedge clk_chipset) begin
        if (dma_iocycle) begin
            if (~io_wr_n) begin
                if (~dma_hi_byte) dma_lsb[dma_reg] <= cpu_data_bus;
                else              dma_msb[dma_reg] <= cpu_data_bus;
            end
            // The byte pointer advances on a read as well; two reads walk
            // LSB then MSB and hand it back for the next write pair.
            if (~io_wr_n | ~io_rd_n) dma_hi_byte <= ~dma_hi_byte;
        end
    end
    wire [7:0] dma_dout = dma_hi_byte ? dma_msb[dma_reg] : dma_lsb[dma_reg];

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

    wire [7:0] pic1_dout, pic2_dout;
    wire       pic1_to_cpu_buf, pic2_to_cpu;
    wire       pic1_data_bus_io, pic2_data_bus_io;
    wire [2:0] pic1_cascade_out;

    KF8259 u_pic1 (
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
        .interrupt_request({pic2_to_cpu, 6'b0, timer_out0})
    );

    KF8259 u_pic2 (
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
        .interrupt_request(8'b0)
    );

    // Latched the way PERIPHERALS latches it, on the CPU clock's falling
    // enable, so the bench sees the same edge the core will.
    logic pic1_to_cpu = 1'b0;
    always_ff @(posedge clk_chipset)
        if (cpu_ce_negedge) pic1_to_cpu <= pic1_to_cpu_buf;

    // INTA count: how many acknowledges the CPU issued. One means the first
    // interrupt reached the INTA pair; the handler ran if the EU ever stands
    // on FD80:02BC or beyond FDAB1.
    int inta_count = 0;
    logic inta_d = 1'b1;
    always_ff @(posedge clk_chipset) begin
        if (~inta_n) begin
            if (inta_count == 0) $display("  %8t  INTA #1", $time);
            if (inta_d) $display("  %8t  INTA  vector %02X", $time, din);
            inta_count <= inta_count + 1;
        end
        inta_d <= inta_n;
    end

    // Segment transfers: when CS changes, where the EU went matters more
    // than where it was. A stray vector lands the CPU in RAM.
    logic [15:0] eu_cs_d = 16'hFFFF;
    always_ff @(posedge clk_chipset) begin
        eu_cs_d <= eu_cs;
        if (eu_cs != eu_cs_d)
            $display("  %8t  CS %04X -> %04X  (pc %05X)", $time, eu_cs_d, eu_cs, eu_pc);
    end

    // ---- keyboard stand-in ---------------------------------------------------
    //
    // The keyboard check at FD95F polls 0x43 (8251 status) for bit 1 and then
    // reads 0x41 expecting the power-on keycode 0x60. Answering those two lets
    // the bench take the "keyboard present" path (short: BDA clear, no memory
    // sweep) instead of burning millions of clocks in the absent-path loop.
    wire kbd_stat_iocycle = ~io_rd_n & (cpu_address[15:0] == 16'h0043);
    wire kbd_data_iocycle = ~io_rd_n & (cpu_address[15:0] == 16'h0041);


    // ---- execution trace, from inside the CPU -------------------------------
    //
    // Bus fetches are prefetch, not execution. Every conditional in the ITF's
    // flag test is a two-byte jump to itself, so a failed test spins entirely
    // inside the prefetch queue and puts nothing on the bus: the fetch trace can
    // say where the CPU stopped FETCHING and not where it stopped EXECUTING.
    //
    // The queue's read pointer is the EU's instruction pointer, so CS:PFQ_ADDR
    // is the real program counter.
    wire [15:0] eu_ip = u_cpu.t_pfq_addr_out;
    wire [15:0] eu_cs = u_cpu.t_biu_register_cs;
    wire [19:0] eu_pc = {eu_cs, 4'd0} + {4'd0, eu_ip};

    // The microcode program counter. A stuck EU is either parked on one
    // microinstruction or going round a small ring of them, and which it is
    // decides where to look.
    wire [12:0] urom = u_cpu.EU_CORE.eu_rom_address;
    logic [12:0] urom_min = 13'h1FFF, urom_max = 13'd0;
    logic [12:0] urom_seen [0:15];
    int          urom_w = 0;
    // Once the F6 dispatch is seen, log every microinstruction. F7 has the same
    // shape in the listing and works, so the divergence is what matters.
    logic urom_log = 1'b0;
    int   urom_log_n = 0;
    logic [12:0] urom_core_d = 13'h1FFF;
    logic [12:0] urom_d = 13'h1FFF;
    always_ff @(posedge clk_core) begin
        urom_core_d <= urom;
        if (urom == 13'h01F6) urom_log <= 1'b1;
        if (urom_log && (urom != urom_core_d) && (urom_log_n < 0)) begin
            urom_log_n <= urom_log_n + 1;
            $display("    u %04X", urom);
        end
    end
    always_ff @(posedge clk_chipset) begin
        urom_d <= urom;
        if (urom != urom_d) begin
            urom_seen[urom_w[3:0]] <= urom;
            urom_w <= urom_w + 1;
            if (urom < urom_min) urom_min <= urom;
            if (urom > urom_max) urom_max <= urom;
        end
    end

    // mcl86 dispatches an x86 instruction by jumping to 0x0100 + opcode, so
    // while eu_rom_address[12:8] == 1 the low byte IS the opcode being started.
    // That gives a true x86 instruction trace, which the bus cannot.
    wire       is_dispatch = (urom[12:8] == 5'h01);
    logic [7:0] op_seen [0:63];
    int         op_w = 0;
    logic       is_dispatch_d = 1'b0;
    // Sampled on the EU's own clock. On clk_chipset the microcode PC had often
    // already advanced past the dispatch entry, and every opcode came out one
    // too high.
    always_ff @(posedge clk_core) begin
        is_dispatch_d <= is_dispatch;
        if (is_dispatch & ~is_dispatch_d) begin
            op_seen[op_w[5:0]] <= urom[7:0];
            op_w <= op_w + 1;
        end
    end

    logic [19:0] eu_pc_d = 20'hFFFFF;
    int          eu_steps = 0, eu_traced = 0;
    logic [19:0] eu_ring [0:31];
    int          eu_ring_w = 0;

    always_ff @(posedge clk_chipset) begin
        eu_pc_d <= eu_pc;
        if (eu_pc != eu_pc_d) begin
            eu_steps <= eu_steps + 1;
            eu_ring[eu_ring_w[4:0]] <= eu_pc;
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
    int i;
    initial begin
        for (i = 0; i < 1048576; i = i + 1) ram[i] = 8'h00;
        $readmemh("itf.hex",  itf);
        $readmemh("bios.hex", bios);

        $display("ITF  reset vector F8000+7FF0: %02X %02X %02X %02X %02X",
                 itf[16'h7FF0], itf[16'h7FF1], itf[16'h7FF2],
                 itf[16'h7FF3], itf[16'h7FF4]);
        $display("BIOS reset vector E8000+17FF0: %02X %02X %02X %02X %02X",
                 bios[18'h17FF0], bios[18'h17FF1], bios[18'h17FF2],
                 bios[18'h17FF3], bios[18'h17FF4]);
        $display("--- trace (first 400 distinct fetch addresses) ---");

        repeat (40) @(posedge clk_chipset);
        reset = 1'b0;

        // Long enough for a real POST to get somewhere: 40 M chipset clocks is
        // about a second of guest time. A progress line every two million says
        // whether it is moving or parked.
        for (i = 0; i < 40; i = i + 1) begin
            repeat (5_000_000) @(posedge clk_chipset);
            $display("  ... %0t  EU %05X  urom %04X  cyc %0d/%0d  ratio %0d dec %0d  zero %0d",
                     $time, eu_pc, urom,
                     u_cpu.BIU_CORE.clock_cycle_counter,
                     u_cpu.BIU_CORE.clock_cycle_counter_div,
                     ccc_div, ccc_dec, u_cpu.BIU_CORE.BIU_CLK_COUNTER_ZERO);
        end

        $display("--- done ---");
        $display("PIT gate2     %0d  (counters now %04X %04X %04X)", gate2,
                 u_pit.u_KF8253_Counter_0.count[15:0],
                 u_pit.u_KF8253_Counter_1.count[15:0],
                 u_pit.u_KF8253_Counter_2.count[15:0]);
        $display("INTA count    %0d", inta_count);
        $display("IVT 08 : %04X:%04X   IVT 18: %04X:%04X",
                 {ram[8'h23],ram[8'h22]}, {ram[8'h21],ram[8'h20]},
                 {ram[8'h63],ram[8'h62]}, {ram[8'h61],ram[8'h60]});
        $display("fetches       %0d", fetches);
        $display("distinct PCs  %0d", ring_w);
        $display("PC range      %05X .. %05X", pc_min, pc_max);
        $display("I/O writes    %0d", io_n);
        for (i = 0; i < (io_n < 64 ? io_n : 64); i = i + 1)
            $display("  io[%0d] %04X", i, io_port_hist[i]);
        $display("port 043D written: %0d  last value %02X  itf_bank %0d",
                 saw_043d, last_043d, itf_bank);
        $display("EU steps      %0d", eu_steps);
        $display("urom now      %04X   moves %0d   range %04X..%04X",
                 urom, urom_w, urom_min, urom_max);
        $display("x86 opcodes dispatched: %0d", op_w);
        for (i = (op_w > 64 ? op_w - 64 : 0); i < op_w; i = i + 1)
            $display("  op %02X", op_seen[i & 63]);
        $display("last 16 microcode addresses:");
        for (i = 0; i < 16; i = i + 1)
            $display("  %04X", urom_seen[(urom_w + i) & 15]);
        $display("last 32 EU addresses (oldest first):");
        for (i = 0; i < 32; i = i + 1)
            $display("  %05X", eu_ring[(eu_ring_w + i) & 31]);
        $finish;
    end

endmodule

`default_nettype wire
