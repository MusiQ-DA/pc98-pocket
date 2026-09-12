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

module tb_pc98_v30;

    // clk_chipset is 42.954545 MHz. The V30 core runs on it gated by the CE
    // train, which is how the core is meant to be clocked on fast fabric.
    logic clk_chipset = 1'b0;
    always #11.641 clk_chipset = ~clk_chipset;

    logic pic1_to_cpu = 1'b0;   // forward: the PIC models below drive it

    logic reset = 1'b1;
    // OUT 0F0h resets the CPU and nothing else: memory keeps its contents and
    // the ROM bank keeps its selection, which is what the ITF's resume needs.
    logic       f0_prev_wr_n = 1'b1;
    logic       soft_reset_cpu = 1'b0;
    logic [7:0] soft_reset_count = 8'h00;
    wire        cpu_reset_w = reset | soft_reset_cpu;

    // ---- clock enables and the CPU pin clock -------------------------------
    wire       clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire       cycle_accrate, shift_read_timing;
    wire [7:0] ccc_div, ccc_dec;
    wire [1:0] ram_rd_wait, ram_wr_wait;

    XT_CE_Generator u_ce (
        .clock                              (clk_chipset),
        .reset                              (reset),
        // A bus-cycle boundary, which is what the 8088's biu_done used to
        // stand in for; the select itself is constant here.
        .clk_select_load                    (cpu_ce_posedge),
        // 9.54 MHz -- what the shipped firmware now boots with, and 2x the
        // old 4.77 default. The memory test is CPU-bound, so this halves the
        // chipset edges the same guest progress costs: the boot that took 40
        // wall minutes to reach the reset at 18.5 s of guest time should take
        // twenty. Timer-fed delays still take their full guest time, which is
        // the honest trade: the machine itself is faster, not the clocks.
        .clk_select                         (2'b10),      // 9.54 MHz, the firmware default
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

    // ---- the CPU: nuV30, the real part -------------------------------------
    //
    // De-muxed bus view. ADDR_O is the owning cycle's linear address for the
    // whole cycle; DATA_I must be valid before the READY sample at T3 (flat
    // memory answers combinationally); DATA_O carries the write word with
    // byte lanes selected by A0 and UBE_N -- the same protocol hdl's
    // nec_bus.sv drives the silicon with.
    // din is declared with din_of below, where the models' answers are muxed
    wire  [2:0] processor_status;    // v30 BS == the 8288's S2-S0
    wire        RD_N, UBE_N, BUSLOCK_N;

    wire [19:0] ADDR_O;
    wire [15:0] DATA_O;
    wire  [1:0] QS;
    wire  [3:0] STATUS_O;
    wire [223:0] dbg_regs;
    logic [15:0] DATA_I;

    logic        bkd_load = 1'b0;
    logic [223:0] bkd_regs = '0;
    logic [47:0] bkd_queue = '0;
    logic  [2:0] bkd_qlen = '0;
    logic [15:0] bkd_fetch_ip = '0;
    logic        scr_en = 1'b0;
    logic  [1:0] scr_qop = '0;

    v30_core u_cpu (
        .CLK       (clk_chipset),
        .CE        (cpu_ce_posedge),
        .RESET     (cpu_reset_w),
        .READY     (1'b1),           // flat memory answers immediately
        .INT       (pic1_to_cpu),
        .NMI       (1'b0),
        .POLL_N    (1'b1),
        .DATA_I    (DATA_I),
        .ADDR_O    (ADDR_O),
        .DATA_O    (DATA_O),
        .STATUS_O  (STATUS_O),
        .QS        (QS),
        .BS        (processor_status),
        .RD_N      (RD_N),
        .UBE_N     (UBE_N),
        .BUSLOCK_N (BUSLOCK_N),
        .SS_ADDR (), .SS_WDATA (), .SS_WE (), .SS_RDATA (), .SS_ERR (),
        .SS_BUS_QUIET (),
        .bkd_load (bkd_load), .bkd_regs (bkd_regs), .bkd_queue (bkd_queue),
        .bkd_qlen (bkd_qlen), .bkd_fetch_ip (bkd_fetch_ip),
        .scr_en (scr_en), .scr_qop (scr_qop),
        .dbg_regs  (dbg_regs), .dbg_first_pop (), .dbg_pend ()
    );

    // The live register view: {psw,ip,ds,ss,cs,es,di,si,bp,sp,bx,dx,cx,ax},
    // retired-instruction granularity. The old bench reached into mcl86 for
    // these; the V30 core publishes them on a port.
    wire [15:0] dbg_ax = dbg_regs[15:0];
    wire [15:0] dbg_cx = dbg_regs[31:16];
    wire [15:0] dbg_dx = dbg_regs[47:32];
    wire [15:0] dbg_bx = dbg_regs[63:48];
    wire [15:0] dbg_sp = dbg_regs[79:64];
    wire [15:0] dbg_si = dbg_regs[111:96];
    wire [15:0] dbg_di = dbg_regs[127:112];
    wire [15:0] dbg_cs = dbg_regs[159:144];
    wire [15:0] dbg_ss = dbg_regs[175:160];

    // ---- bus controller ----------------------------------------------------
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

    // The core registers the owning cycle's address itself; the models sample
    // it at command trailing edges, where it is stable.
    wire [19:0] cpu_address = ADDR_O;

    // The eight-bit data bus the models see: the lane the cycle actually
    // addresses. PC-98 devices live on the low byte; an odd port reaches them
    // through the upper lane, exactly as the board's transceivers steer it.
    wire [7:0] cpu_data_bus = ADDR_O[0] ? DATA_O[15:8] : DATA_O[7:0];

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

    // The data bus is combinational, as the chipset's is. Registering it here
    // put a chipset clock between the strobe and the byte, and the core sampled
    // stale data: the first run stalled for seventeen milliseconds in the middle
    // of one instruction's operand fetch.
    //
    // A function so the V30 front can ask for BOTH bytes of the aligned word
    // it fetches, while every model below still speaks eight bits.
    //
    // A0000-A3FFF is the REAL pc98_tvram, not flat RAM: the machine's run#191
    // drew every letter through the two-byte path because the high bytes of
    // the message cells still held the VRAM test's 0x55 -- the mov-word write
    // that should have cleared them never landed in the hardware banks. This
    // bench modelled the plane as flat memory, so the write path that failed
    // had no coverage at all.
    logic [7:0]  tvram_q;
    logic        tvram_fil_dummy;
    logic [7:0]  tvram_lo_dummy, tvram_hi_dummy;
    logic [11:0] tvram_fil_cell = 12'd0;
    // The memory switch (A3FE0-A3FFF, tvram cells 0xFF0-0xFFF) is register
    // territory on real hardware: the ITF's VRAM test deliberately stops at
    // 0x3FDF to avoid it, and np2 re-asserts its config after every clear.
    // The POST clear (FECBB) sweeps the full 16 KB and would stomp it to
    // 0xE1 -- so guest attr writes into those cells are dropped here and the
    // pre-seeded switch values survive the whole boot.
    wire memsw_cell = (cpu_address[13:2] >= 12'hFF8);           // 0x3FE0-0x3FFF
    wire tvram_wren = ~mem_wr_n
                    & (cpu_address[19:14] == 6'b101000)
                    & ~(memsw_cell & cpu_address[13]);
    pc98_tvram u_tvram (
        .clk          (clk_chipset),
        // Loads the memory switch registers with the np2 defaults while the
        // machine is in reset -- the RTL owns the pre-seed now, the way the
        // real fix carries it into the FPGA.
        .rst          (reset),
        .cpu_addr     (cpu_address[13:0]),
        .cpu_wren     (tvram_wren),
        .cpu_wdata    (cpu_data_bus),
        .cpu_q        (tvram_q),
        .fil_clk      (clk_chipset),
        .fil_cell     (tvram_fil_cell),
        .fil_char_lo  (tvram_lo_dummy),
        .fil_char_hi  (tvram_hi_dummy),
        .vid_clk      (clk_chipset),
        .vid_cell     (12'd0),
        .vid_attr     (tvram_fil_dummy)
    );

    function automatic logic [7:0] din_of(input logic [19:0] a);
        din_of = ~mem_rd_n    ? (is_rom(a) ? rom_byte(a)
                              : ((a[19:14] == 6'b101000) ? tvram_q : ram[a]))
               : ~inta_n      ? ((~pic2_data_bus_io) ? pic2_dout : pic1_dout)
               : pit_iocycle  ? pit_dout
               : dma_iocycle  ? dma_dout
               : pic1_iocycle ? pic1_dout
               : pic2_iocycle ? pic2_dout
               : kbd_data_iocycle ? 8'h60
               : kbd_stat_iocycle ? kbd_status
               : gdc_stat_iocycle ? gdc_status_mock
               : cc_ioread   ? (cc_latch | 8'h30)
               : fdc_msr_sel ? fdc_msr
               : fdc_fifo_sel ? fdc_fifo
               : sysport_sel ? sysport_data
               : 8'hFF;
    endfunction

    wire [7:0] din = din_of(cpu_address);
    // Reads: memory and code fetches want the aligned WORD; I/O and INTA are
    // byte affairs, served on both lanes. mem8_of() is the old bench's whole
    // din mux, evaluated at the aligned neighbours.
    wire [7:0] din_even = din_of({cpu_address[19:1], 1'b0});
    wire [7:0] din_odd  = din_of({cpu_address[19:1], 1'b1});
    always_comb begin
        case (processor_status)
            3'b100, 3'b101: begin
                // The SS override: any word read from the POST stack during
                // BASIC's entry returns the forced value instead. The POP SS
                // at F7D80 reads two bytes from [SS:SP] through here.
                if (ss_override_val >= 0 && basic_trace
                    && cpu_address >= 20'h003F0 && cpu_address <= 20'h003FF)
                    DATA_I = {ss_override_val[15:8], ss_override_val[7:0]};
                else
                    DATA_I = {din_odd, din_even};
            end
            3'b000:         DATA_I = {8'h00, din_even};     // INTA: vector low
            default:        DATA_I = {din_even, din_even};  // I/O, byte-wide
        endcase
    end


    // True when the read above fell through to the FF default -- i.e. nothing
    // here answered it. Used to name the port once, in the trace.
    wire din_is_default = ~(~mem_rd_n | ~inta_n | pit_iocycle | dma_iocycle
                          | pic1_iocycle | pic2_iocycle | kbd_data_iocycle
                          | kbd_stat_iocycle | gdc_stat_iocycle | cc_ioread
                          | fdc_msr_sel | fdc_fifo_sel | sysport_sel);

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
    // 0xBE: the FDC's drive/media register (np2 io/fdc.c, fdc_ibe): reads
    // (chgreg & 3) | 8 | 0xF0, so F8 with no drive selected. The 00 this
    // bench answered made the disk-boot attempt's retry flow diverge, and
    // the register context BASIC's strap saw at int 1E was garbage -- its
    // rep movsb "IPL copy" then ran from DS:BX=04E0, ROM-pointing segment
    // registers followed, and the timer vector ended up in an uncopied part
    // of the RAM image: the tick the interpreter waits on never ticks.
    wire sysport_be_sel = ~io_rd_n & (cpu_address[15:0] == 16'h00BE);
    logic [7:0] fdc_be_chgreg = 8'h00;
    logic       be_wr_d = 1'b1;
    wire        be_wr = ~io_wr_n & (cpu_address[15:0] == 16'h00BE);
    always_ff @(posedge clk_chipset) begin
        be_wr_d <= be_wr;
        if (be_wr & ~be_wr_d) fdc_be_chgreg <= cpu_data_bus;
    end
    // 0x31 = DIP switch 2 (np2's sysp_i31 returns pccore.dipsw[1]; np2's
    // default set is 3E E3 7B). Bit0 is the boot order: SET means int 1F is
    // skipped and the machine goes straight to int 1E -- which is how a
    // stock machine avoids IVT[1F]'s D800:2A00, an entry for a BASIC card
    // nothing here has. Bit4 asks the ROM to initialise the memory switch --
    // but np2 keeps it CLEAR (0xE3) and instead pre-writes the switch bytes
    // {48,05,04,...} into A3FE2+4i at every reset (pccore_reset), because
    // the ROM's own writer tops out at FEA=2 (512 KB class) while the real
    // 640 KB value is FEA=4. Answer 0xE3: bit0 boot-first, bit4 no-init.
    wire sysport_31_bootfirst = 1'b1;
    wire sysport_sel    = sysport_31_sel | sysport_33_sel
                        | sysport_35_sel | sysport_42_sel | sysport_be_sel;
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
        if (io_wr_n & ~f0_prev_wr_n & (cpu_address[15:0] == 16'h00F0)
            || (force_pass1_reset && soft_reset_count == 8'h00)) begin
            soft_reset_cpu   <= 1'b1;
            soft_reset_count <= 8'hFF;
            if (!force_pass1_reset)
                $display("  %8t  OUT 00F0 -- CPU reset requested (eu_pc %05X)", $time, eu_pc);
            force_pass1_reset <= 1'b0;
        end else if (soft_reset_count != 8'h00)
            soft_reset_count <= soft_reset_count - 8'h01;
        else
            soft_reset_cpu <= 1'b0;
    end

    wire [7:0] sysport_data = sysport_35_sel ? sysport_c
                            : sysport_31_sel ? (sysport_31_bootfirst ? 8'hE3 : 8'hE2)
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
                            : sysport_be_sel ? (fdc_be_chgreg[1:0] | 8'h08 | 8'hF0)
                            : sysport_42_sel ? 8'h02
                            :                  8'h00;

    logic saw_high_write = 1'b0;
    logic din_default_q = 1'b0;
    logic unanswered_seen [0:255];
    initial for (int q = 0; q < 256; q = q + 1) unanswered_seen[q] = 1'b0;

    logic io_wr_d = 1'b1, mem_wr_d = 1'b1, mem_rd_d = 1'b1, io_rd_d = 1'b1;
    logic [7:0] mem_wr_data_q = 8'h00;
    logic [15:0] mem_wr_word_q = 16'h0000;

    // One committed byte of a memory write, with every watcher that used to
    // sit inline on the eight-bit bus: the sweep ranges, the ITF's
    // reset-resume save window, and the text-plane snoop.
    task automatic commit_mem_byte(input logic [19:0] a, input logic [7:0] d);
        if (~is_rom(a)) begin
            // The real tvram module owns A0000-A3FFF; flat RAM must not also
            // take the writes, or the read mux above would be reading a
            // different store than the machine does.
            if (a[19:14] != 6'b101000)
                ram[a] <= d;
            // Where the writes are going, chunk by chunk. The hardware's LIVE
            // readout is the same quantity, and "sweeping upward through the
            // memory test" and "going round a small ring" look identical on a
            // 20 fps display but not at all alike here.
            if (a >= 20'h20000 && a < 20'hA0000 && ~saw_high_write) begin
                saw_high_write <= 1'b1;
                $display("  %8t  first write above 128 KB: %05X (eu_pc %05X)",
                         $time, a, eu_pc);
            end
            if (a < wr_lo_chunk) wr_lo_chunk <= a;
            if (a > wr_hi_chunk) wr_hi_chunk <= a;
            wr_n_chunk <= wr_n_chunk + 1;
            // The ITF's CPU-reset resume state lives at 0000:03F0-040F: the
            // pushed far return F800:1497 at 03FA/03FC, the saved SS:SP at
            // 0404/0406. There are only a handful of writes into this window
            // in a whole boot, and the one that clobbers it names itself here.
            if (a >= 20'h003F0 && a <= 20'h0040F)
                $display("  %8t  SAVE[%04X] <= %02X   (eu_pc %05X)",
                         $time, a[15:0], d, eu_pc);
            // The vector slots around the boot decision: INT 1E (disk boot)
            // and INT 1F (ROM BASIC) live at 0078/007C. The run of
            // 2026-09-12 vectored the BASIC entry to D800:0A05 instead of
            // E800:0A07, so who writes these four bytes and with what is now
            // a named question.
            if (a >= 20'h0070 && a <= 20'h0083)
                $display("  %8t  IVT[%04X] <= %02X   (eu_pc %05X)",
                         $time, a[15:0], d, eu_pc);
            // The extension-ROM scan state: [0x4AC] the far-call pointer,
            // [0x4AE] the segment under test. And the low-RAM stub page the
            // boot decision jumps through -- where 0000:0A05 keeps turning
            // up as the derailment target.
            if (a >= 20'h004A0 && a <= 20'h004B0)
                $display("  %8t  FAR[%04X] <= %02X   (eu_pc %05X)",
                         $time, a[15:0], d, eu_pc);
            if (a >= 20'h00A00 && a <= 20'h00A20)
                $display("  %8t  STUB[%04X] <= %02X   (eu_pc %05X)",
                         $time, a[15:0], d, eu_pc);
            // The BASIC hook area: any write whose 16-bit offset lands in
            // 0x15B0-0x15D0, once the machine reached the crash site. The
            // writer of the bogus 0FB0:BAD9 pointer names itself here.
            if (hook_watch && a[15:0] >= 16'h15B0 && a[15:0] <= 16'h15D0)
                $display("  %8t  HOOK[%04X:%04X] <= %02X   (eu_pc %05X)",
                         $time, a[19:16], a[15:0], d, eu_pc);
            // The text plane: the memory-count display lands here. Keep the
            // first row of cells (code + attribute) for the final dump.
            if (a >= 20'hA0000 && a < 20'hA4000) begin
                if (a < 20'hA0200)
                    tvram_code[a[8:0]]  <= d;
                else if (a >= 20'hA2000 && a < 20'hA2200)
                    tvram_attr[a[8:0]]  <= d;
                tvram_wr_count <= tvram_wr_count + 1;
                // The first forty writes (the clear, and what shape it has),
                // and after that every PRINTABLE byte into the code plane --
                // which is the memory count, if the BIOS ever writes one. The
                // clear itself is 20487 writes of 00 and E1 and says nothing.
                if (tvram_wr_count < 40
                 || (a < 20'hA2000 && d >= 8'h20 && d < 8'h7F))
                    $display("  %8t  TVRAM[%04X] <= %02X %s  (eu_pc %05X)",
                             $time, a[15:0], d,
                             (d >= 8'h20 && d < 8'h7F)
                                 ? string'({"'", d, "'"}) : "   ",
                             eu_pc);
            end
        end
    endtask
    logic [7:0] tvram_code [0:511];   // A0000-A01FF, first row of cells
    logic [7:0] tvram_attr [0:511];   // A2000-A21FF
    int          tvram_wr_count = 0;

    // The two GDC status ports, named here because the trace below has to
    // recognise them long before the mock that answers them is declared.
    wire  gdc_stat_port  = (cpu_address[15:0] == 16'h0060)
                         | (cpu_address[15:0] == 16'h00A0);
    logic gdc_poll_seen  = 1'b0;

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
    wire [15:0] eu_cx = dbg_cx;
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
        // END. The V30 drives a word; the lane the cycle addresses comes from
        // A0 (even, DATA_O[7:0]) and UBE_N (odd, DATA_O[15:8]). PC-98 guests
        // write bytes, which is one lane high; a word write lights both.
        if (~mem_wr_n) begin
            mem_wr_data_q <= cpu_data_bus;      // the addressed lane, for the models
            mem_wr_word_q <= DATA_O;
        end

        // Memory write, on the trailing edge, and never into ROM. One commit
        // per live lane, so a word write lands as its two bytes and every
        // watcher below sees each of them.
        if (mem_wr_n & ~mem_wr_d) begin
            if (cpu_address[0] == 1'b0)
                commit_mem_byte(cpu_address, mem_wr_word_q[7:0]);
            if (UBE_N == 1'b0)
                commit_mem_byte({cpu_address[19:1], 1'b1}, mem_wr_word_q[15:8]);
        end

        // The hook operands' FETCH addresses: the gate at [0x15B5] and the
        // pointer at [0x15C6]. The full 20-bit address names the segment the
        // CPU was actually using -- the register view lags retirement and
        // cannot be trusted at the crash site.
        if (hook_watch & ~mem_rd_n & ~is_rom(cpu_address)
            && ((cpu_address[15:0] == 16'h15B5) | (cpu_address[15:0] == 16'h15C6)
             || (cpu_address[15:0] == 16'h15C7) || (cpu_address[15:0] == 16'h15C8)
             || (cpu_address[15:0] == 16'h15C9)))
            $display("  %8t  HOOKFETCH %05X => %02X   (eu_pc %05X)", $time,
                     cpu_address, ram[cpu_address], eu_pc);

        // The interval timer and the PICs, every write named. BASIC's entry
        // at 21.3 s was the last moment the timer interrupt fired; its wait
        // loop has spun since on a tick counter nobody increments. Whoever
        // reprogrammed what, the OUT sequence says so.
        if (io_wr_n & ~io_wr_d) begin
            if (cpu_address[15:0] == 16'h0077 || cpu_address[15:0] == 16'h0071
             || cpu_address[15:0] == 16'h0073 || cpu_address[15:0] == 16'h0075)
                $display("  %8t  OUT PIT %04X, %02X   (eu_pc %05X)", $time,
                         cpu_address[15:0], mem_wr_data_q, eu_pc);
            if (cpu_address[15:0] == 16'h0000 || cpu_address[15:0] == 16'h0002
             || cpu_address[15:0] == 16'h0004 || cpu_address[15:0] == 16'h0006)
                $display("  %8t  OUT PIC %04X, %02X   (eu_pc %05X)", $time,
                         cpu_address[15:0], mem_wr_data_q, eu_pc);
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

        if (io_rd_n & ~io_rd_d) begin
            if (gdc_stat_port) begin
                if (~gdc_poll_seen) begin
                    $display("  %8t  IN  from %04X  (poll begins, eu_pc %05X)",
                             $time, cpu_address[15:0], eu_pc);
                    gdc_poll_seen <= 1'b1;
                end
            end else begin
                gdc_poll_seen <= 1'b0;
                $display("  %8t  IN  from %04X", $time, cpu_address[15:0]);
            end
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
    logic timer_out0;
    wire  [7:0] pit_dout;
    wire pit_iocycle = (~io_rd_n | ~io_wr_n) & cpu_address[0]
                     & (cpu_address[7:4] == 4'h7) & ~cpu_address[9] & ~cpu_address[8];
    always_ff @(posedge clk_chipset)
        if (peripheral_ce) timer_clock <= ~timer_clock;

    // (The power-on mode injection lived here; see the git history for the
    // three timings that each broke a different ROM expectation -- the FD866
    // counter test demands the power-on mode, and a running mode-3 counter
    // races the IVT install through the FDAC2 unmask window.)

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

    // The interval timer's interrupt, generated the way np2 schedules it
    // (NEVENT_ITIMER): periodic at the rate the BIOS's last reload of
    // counter 0 implies, independent of the 8253 model's output pin. The
    // FDA9A reload writes 0x80,0x80 (MSB only per the reset RL state) --
    // 0x8000 counts at the PIT clock. The PIT clock here is timer_clock
    // (peripheral_ce toggling, ~8.59 MHz / 2). One full period at mode 3
    // = the reload value; the interrupt fires on each output transition.
    logic       pit_timer_irq = 1'b0;
    logic [1:0] pit_irq_state = 2'b00;
    int         pit_irq_divider = 0;
    // Period: reload 0x8000 at timer_clock/2 rate.  We just toggle every
    // 16384 timer_clock edges (half of 0x8000) which approximates the mode-3
    // square wave for interrupt purposes.  BIOS reload value observed: 0x80.
    always_ff @(posedge clk_chipset) begin
        if (peripheral_ce) begin
            pit_irq_divider <= pit_irq_divider + 1;
            if (pit_irq_divider >= 16384) begin
                pit_irq_divider <= 0;
                pit_timer_irq  <= ~pit_timer_irq;
            end
        end
    end

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

    // VSYNC stand-in: the machine's raster raises IRQ2 once per frame, and
    // the BIOS's FED23 sequence unmasks it (port 0x02, bit 2) then waits at
    // FED44 for the handler it installed on INT 0x0A. The GDC status waits
    // at FDBB3/FDC3E poll the same flag, so the pulse is held for a real
    // retrace's worth of clocks -- a 3-clock blip is too narrow for the
    // BIOS's polling loop to ever see.
    logic [19:0] crt_period_cnt = 20'd0;
    logic [15:0] crt_pulse_cnt  = 16'd0;
    logic        crt_vsync_mock = 1'b0;
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
            end
        end
    end

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
        // np2 generates the timer interrupt as a scheduled event keyed to
        // the counter's reload value, NOT from the 8253's output pin
        // (io/pit.c: systimer / setsystimerevent). Our KF8253's mode-3
        // output has a stuck-output bug this boot exposes; until that is
        // fixed, the honest model is np2's: the interrupt fires at the
        // period the ROM programmed, every time.
        .interrupt_request({pic2_to_cpu, 4'b0, crt_vsync_mock, 1'b0, pit_timer_irq})
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
        .interrupt_request({4'b0, fdc_irq3, cc_irq2 | fdc_irq2, 2'b0})
    );

    // Latched the way PERIPHERALS latches it, on the CPU clock's falling
    // enable, so the bench sees the same edge the core will.
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

    // The PIC1-direct interrupt autopsy: around the timer's first (and only)
    // acknowledge, trace inta_n, the PIC's INT line, its control state and
    // in-service register every chipset clock. The cascaded interrupts get
    // two clean INTA pulses; this one got a single pulse, no vector taken,
    // and the in-service bit stuck -- everything the timer needed to die.
    // Print the PIC1 state around every INTA pulse for the first five
    // acknowledges -- the cascaded pairs and the timer's lone pulse.
    logic inta_seen_n = 1'b1;
    int  inta_pulse_log = 0;
    always_ff @(posedge clk_chipset) begin
        inta_seen_n <= inta_n;
        if (~inta_n && inta_pulse_log < 40) begin
            inta_pulse_log <= inta_pulse_log + 1;
            $display("  %8t  PIC inta=%b intLAT=%b st=%s irr=%02X isr=%02X imr=%02X",
                     $time, pic1_to_cpu_buf, pic1_to_cpu,
                     u_pic1.u_Control_Logic.control_state,
                     u_pic1.interrupt_request_register,
                     u_pic1.in_service_register,
                     u_pic1.interrupt_mask);
        end
        // Any transition of the LATCHED INT line near an acknowledge: the
        // V30 aborts its two-cycle INTA if INT dips between the pulses, and
        // the latch re-samples every falling CPU enable -- a one-clock
        // dropout there is invisible everywhere else.
        if (inta_pulse_log > 0 && inta_pulse_log < 40 && pic1_to_cpu != pic1_to_cpu_d)
            $display("  %8t  INTLAT %b -> %b   (inta_n=%b, eu_pc %05X)", $time,
                     pic1_to_cpu_d, pic1_to_cpu, inta_n, eu_pc);
        pic1_to_cpu_d <= pic1_to_cpu;
    end
    logic pic1_to_cpu_d = 1'b0;

    // At the boot decision, dump the POST stack area -- the words POP SS
    // will load during BASIC's init come from whatever the POST left there.
    always_ff @(posedge clk_chipset)
        if (eu_pc == 20'hFE1FD) begin
        $display("  %8t  BOOTDEC stack: F0:%02X%02X F2:%02X%02X F4:%02X%02X F6:%02X%02X F8:%02X%02X FA:%02X%02X FC:%02X%02X FE:%02X%02X",
                 $time,
                 ram[20'h003F1],ram[20'h003F0], ram[20'h003F3],ram[20'h003F2],
                 ram[20'h003F5],ram[20'h003F4], ram[20'h003F7],ram[20'h003F6],
                 ram[20'h003F9],ram[20'h003F8], ram[20'h003FB],ram[20'h003FA],
                 ram[20'h003FD],ram[20'h003FC], ram[20'h003FF],ram[20'h003FE]);
        // The memory switch lives in the tvram module's dedicated registers
        // (A3FE2+4i); neither the flat ram[] nor the attribute BRAM carries
        // it -- writes there are dropped, so only memsw[] holds the truth.
        $display("  %8t  WORK: [06EA]=%04X [06EC]=%04X [186A]=%04X  memsw FE2=%02X FE6=%02X FEA=%02X",
                 $time,
                 {ram[20'h006EB],ram[20'h006EA]}, {ram[20'h006ED],ram[20'h006EC]},
                 {ram[20'h0186B],ram[20'h0186A]},
                 u_tvram.memsw[0], u_tvram.memsw[1], u_tvram.memsw[2]);
        end

    // Value-change watch on the two bytes that become the POP SS word:
    // [0030:00FC] and [0030:00FD]. Edge-triggered on the ARRAY VALUE, so
    // word writes and both bus lanes are caught regardless of the
    // address/data latching.
    logic [7:0] stkfc_q = 8'hxx, stkfd_q = 8'hxx;
    always_ff @(posedge clk_chipset) begin
        if (ram[20'h003FC] !== stkfc_q) begin
            $display("  %8t  FCWATCH [03FC] %02X -> %02X  (eu_pc %05X)", $time,
                     stkfc_q, ram[20'h003FC], eu_pc);
            stkfc_q <= ram[20'h003FC];
        end
        if (ram[20'h003FD] !== stkfd_q) begin
            $display("  %8t  FDWATCH [03FD] %02X -> %02X  (eu_pc %05X)", $time,
                     stkfd_q, ram[20'h003FD], eu_pc);
            stkfd_q <= ram[20'h003FD];
        end
    end

    // [0x3F8]/[0x3F9] watches: the int-1E frame's IP lands here; the POPSS
    // dump showed {07,0A} where the ROM's own int at FD80:6205 would push
    // {07,62} -- the 0x0A's writer is the last unknown.
    logic [7:0] stkf8_q = 8'h00, stkf9_q = 8'h00;
    always_ff @(posedge clk_chipset) begin
        if (ram[20'h003F8] !== stkf8_q) begin
            $display("  %8t  F8WATCH [03F8] %02X -> %02X  (eu_pc %05X)", $time,
                     stkf8_q, ram[20'h003F8], eu_pc);
            stkf8_q <= ram[20'h003F8];
        end
        if (ram[20'h003F9] !== stkf9_q) begin
            $display("  %8t  F9WATCH [03F9] %02X -> %02X  (eu_pc %05X)", $time,
                     stkf9_q, ram[20'h003F9], eu_pc);
            stkf9_q <= ram[20'h003F9];
        end
    end

    // Keyboard I/O + [0x500] trace: the BIOS keyboard test should set
    // [0x500].bit7 on a successful 8251 echo; our machine never gets it,
    // so the second extension-ROM scan runs and leaves [0030:00F8]=0x0F --
    // the word BASIC's entry stub later consumes as ES.
    logic [7:0] kbd500_q = 8'h00;
    wire kbd_io_sel = ~io_rd_n & ((cpu_address[15:0] == 16'h0041)
                                | (cpu_address[15:0] == 16'h0043));
    wire kbd32_io   = ~io_wr_n & (cpu_address[15:0] == 16'h0032);
    wire kbd43_io   = ~io_wr_n & (cpu_address[15:0] == 16'h0043);
    always_ff @(posedge clk_chipset) begin
        if (kbd_io_sel & io_rd_d)
            $display("  %8t  KBD RD %04X => %02X  (eu_pc %05X)", $time,
                     cpu_address[15:0], (kbd_ack_armed ? 8'h60 : 8'h00), eu_pc);
        if (kbd32_io | kbd43_io)
            $display("  %8t  KBD WR %04X <= %02X  (eu_pc %05X)", $time,
                     cpu_address[15:0], cpu_data_bus, eu_pc);
        if (ram[20'h00500] !== kbd500_q) begin
            $display("  %8t  K500 [0500] %02X -> %02X  (eu_pc %05X)", $time,
                     kbd500_q, ram[20'h00500], eu_pc);
            kbd500_q <= ram[20'h00500];
        end
    end

    // One-shot park dump: the first HOOKFETCH = the machine entering the
    // final wait. Dump the loop's own code bytes and the register state.
    logic park_dumped = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (!park_dumped && basic_trace && eu_pc == 20'h115C4) begin
            park_dumped <= 1'b1;
            $display("  %8t  PARK: cs=%04X ip~%04X ds=%04X es=%04X ss=%04X sp=%04X psw=%04X",
                     $time, dbg_cs, dbg_regs[207:192], dbg_regs[191:176],
                     dbg_regs[143:128], dbg_ss, dbg_sp, dbg_regs[223:208]);
            $display("  PARK code at 0x115B0-0x115E0:");
            for (int q = 0; q < 12; q++)
                $display("    %05X: %02X %02X %02X %02X", 20'h115B0 + q*4,
                         ram[20'h115B0+q*4], ram[20'h115B1+q*4],
                         ram[20'h115B2+q*4], ram[20'h115B3+q*4]);
        end
    end

    // IF-transition trace: psw[9] = the interrupt flag. The machine ends
    // parked in a BASIC wait loop with IF=0 -- catch the last few CLI/STI
    // that led there.
    logic if_q = 1'b1;
    int if_drops = 0;
    always_ff @(posedge clk_chipset) begin
        if (basic_trace && dbg_regs[217] != if_q) begin
            if_q <= dbg_regs[201];
            if (!dbg_regs[217]) begin
                if_drops <= if_drops + 1;
                if (if_drops < 40 || if_drops % 500 == 0)
                    $display("  %8t  IF->0 (CLI) #%0d  (eu_pc %05X psw %04X)", $time,
                             if_drops, eu_pc, dbg_regs[207:192]);
            end else if (if_drops > 0 && if_drops % 500 == 1)
                $display("  %8t  IF->1 (STI) after #%0d  (eu_pc %05X)", $time, if_drops, eu_pc);
        end
    end

    // Command-queue + work-limit watches: the FE24 block (which sets the
    // work-area words [0x1862..]) is gated on [0x6A4] < [0x6A6] and uses
    // BX=[0x1406]. Nobody populates any of them on this machine -- who
    // does on a real one is the open question.
    logic [15:0] q6a4_q = 16'h0000, q6a6_q = 16'h0000, w1406_q = 16'h0000;
    always_ff @(posedge clk_chipset) begin
        if ({ram[20'h006A5],ram[20'h006A4]} !== q6a4_q) begin
            $display("  %8t  QUEUE [06A4] %04X -> %04X  (eu_pc %05X)", $time,
                     q6a4_q, {ram[20'h006A5],ram[20'h006A4]}, eu_pc);
            q6a4_q <= {ram[20'h006A5],ram[20'h006A4]};
        end
        if ({ram[20'h006A7],ram[20'h006A6]} !== q6a6_q) begin
            $display("  %8t  QUEUE [06A6] %04X -> %04X  (eu_pc %05X)", $time,
                     q6a6_q, {ram[20'h006A7],ram[20'h006A6]}, eu_pc);
            q6a6_q <= {ram[20'h006A7],ram[20'h006A6]};
        end
        if ({ram[20'h01407],ram[20'h01406]} !== w1406_q) begin
            $display("  %8t  LIMIT [1406] %04X -> %04X  (eu_pc %05X)", $time,
                     w1406_q, {ram[20'h01407],ram[20'h01406]}, eu_pc);
            w1406_q <= {ram[20'h01407],ram[20'h01406]};
        end
    end

    // Work-area word watches: the entry stub at F7EF3-F7F16 branches on
    // [0x1862]/[0x1866]/[0x186C]/[0x1860]; ours are all zero and the wrong
    // branch reaches the F000:7D80 POP SS. Catch every writer.
    logic [15:0] wa60_q = 16'h0000, wa62_q = 16'h0000,
                 wa66_q = 16'h0000, wa6c_q = 16'h0000;
    always_ff @(posedge clk_chipset) begin
        if ({ram[20'h01861],ram[20'h01860]} !== wa60_q) begin
            $display("  %8t  WA [1860] %04X -> %04X  (eu_pc %05X)", $time,
                     wa60_q, {ram[20'h01861],ram[20'h01860]}, eu_pc);
            wa60_q <= {ram[20'h01861],ram[20'h01860]};
        end
        if ({ram[20'h01863],ram[20'h01862]} !== wa62_q) begin
            $display("  %8t  WA [1862] %04X -> %04X  (eu_pc %05X)", $time,
                     wa62_q, {ram[20'h01863],ram[20'h01862]}, eu_pc);
            wa62_q <= {ram[20'h01863],ram[20'h01862]};
        end
        if ({ram[20'h01867],ram[20'h01866]} !== wa66_q) begin
            $display("  %8t  WA [1866] %04X -> %04X  (eu_pc %05X)", $time,
                     wa66_q, {ram[20'h01867],ram[20'h01866]}, eu_pc);
            wa66_q <= {ram[20'h01867],ram[20'h01866]};
        end
        if ({ram[20'h0186D],ram[20'h0186C]} !== wa6c_q) begin
            $display("  %8t  WA [186C] %04X -> %04X  (eu_pc %05X)", $time,
                     wa6c_q, {ram[20'h0186D],ram[20'h0186C]}, eu_pc);
            wa6c_q <= {ram[20'h0186D],ram[20'h0186C]};
        end
    end

    // At the int 1E (FD80:6205 = phys FE205): dump EVERYTHING the BASIC
    // entry will inherit -- registers, the work-area words, and the key
    // pointers. Pass 1 vs pass 2 comparison happens here.
    logic int1e_dumped = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (eu_pc == 20'hFE205 && !int1e_dumped) begin
            int1e_dumped <= 1'b1;
            $display("  %8t  INT1E: ax=%04X bx=%04X cx=%04X dx=%04X si=%04X di=%04X bp=%04X sp=%04X",
                     $time, dbg_ax, dbg_bx, dbg_cx, dbg_dx, dbg_si, dbg_di, dbg_regs[95:80], dbg_sp);
            $display("  %8t  INT1E: es=%04X cs=%04X ss=%04X ds=%04X  [1406]=%04X [6A4]=%04X [6A6]=%04X [6EA]=%04X",
                     $time, dbg_regs[143:128], dbg_cs, dbg_ss, dbg_regs[191:176],
                     {ram[20'h01407],ram[20'h01406]},
                     {ram[20'h006A5],ram[20'h006A4]}, {ram[20'h006A7],ram[20'h006A6]},
                     {ram[20'h006EB],ram[20'h006EA]});
            $display("  %8t  INT1E: [1860]=%04X [1862]=%04X [1866]=%04X [186C]=%04X [186A]=%04X [500]=%02X",
                     $time,
                     {ram[20'h01861],ram[20'h01860]}, {ram[20'h01863],ram[20'h01862]},
                     {ram[20'h01867],ram[20'h01866]}, {ram[20'h0186D],ram[20'h0186C]},
                     {ram[20'h0186B],ram[20'h0186A]}, ram[20'h00500]);
        end
        // re-arm for the next pass after a reset
        if (eu_pc == 20'hFD805 && int1e_dumped) int1e_dumped <= 1'b0;
    end

    // At the POP SS (F7D80): the stack word it pops becomes BASIC's work
    // segment. Dump the whole POST stack and SP at that moment.
    logic popss_dumped = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (!popss_dumped && eu_pc == 20'hF7D80) begin
            popss_dumped <= 1'b1;
            $display("  %8t  POPSS: sp=%04X  stk F0:%02X%02X F2:%02X%02X F4:%02X%02X F6:%02X%02X F8:%02X%02X FA:%02X%02X FC:%02X%02X FE:%02X%02X",
                     $time, dbg_sp,
                     ram[20'h003F1],ram[20'h003F0], ram[20'h003F3],ram[20'h003F2],
                     ram[20'h003F5],ram[20'h003F4], ram[20'h003F7],ram[20'h003F6],
                     ram[20'h003F9],ram[20'h003F8], ram[20'h003FB],ram[20'h003FA],
                     ram[20'h003FD],ram[20'h003FC], ram[20'h003FF],ram[20'h003FE]);
        end
    end

    // Catch the value that POP SS at F7D80 will load: watch every write
    // to the POST stack (segment 0x0030) while BASIC is initialising. The
    // B-trace showed SS going from 0030 to F202 at that POP; something in
    // the entry code pushes F202, and on a real machine it pushes a RAM
    // segment instead.
    always_ff @(posedge clk_chipset) begin
        if (cpu_address >= 20'h003F0
            && cpu_address <= 20'h003FF && ~is_rom(cpu_address)) begin
            if (mem_wr_n & ~mem_wr_d)
                $display("  %8t  STK[%04X] <= %02X   (eu_pc %05X)  sp=%04X",
                         $time, cpu_address[15:0], mem_wr_data_q, eu_pc, dbg_sp);
        end
    end

    // Pre-seed the stack word the POP SS at F7D80 will load. On a real
    // 640 KB machine this word holds a RAM segment for BASIC's work area;
    // on ours it holds 0xF202 (a ROM segment) because the work area value
    // [06EA] is nobody's job on a BIOS-direct boot and the ITF doesn't set
    // it either. 0x8000 = 512 KB paragraph is the middle of user RAM.
    // +ssfix=NNNN: when the POP SS at eu_pc F7D80 executes, force SS to
    // NNNN instead of whatever the stack holds. This bypasses the mystery
    // of who pushes 0xF202 and tests whether BASIC runs with a correct
    // work-area segment.
    int ss_override_val = -1;
    logic [15:0] work_ea_val = 16'h0000;
    // +golden=<file>: seed work-area words from a file right before the
    // int 1E (the RAM test would zero them at t=0). The np2 golden-state
    // measurement writes this file. One "ADDR VALUE" hex pair per line.
    string golden_file;
    int golden_fd, golden_cnt, golden_r;
    logic [19:0] g_addr;
    logic [15:0] g_val;
    logic golden_seeded = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (!golden_seeded && eu_pc == 20'hFE1FD) begin
            golden_seeded <= 1'b1;
            if ($value$plusargs("golden=%s", golden_file)) begin
                golden_fd = $fopen(golden_file, "r");
                if (golden_fd != 0) begin
                    golden_cnt = 0;
                    forever begin
                        golden_r = $fscanf(golden_fd, "%h %h\n", g_addr, g_val);
                        if (golden_r != 2) break;
                        ram[g_addr]   = g_val[7:0];
                        ram[g_addr+1] = g_val[15:8];
                        golden_cnt++;
                    end
                    $fclose(golden_fd);
                    $display("  %8t  GOLDEN: seeded %0d words from %s (at FE1FD)", $time, golden_cnt, golden_file);
                end else
                    $display("  %8t  GOLDEN: file %s not found", $time, golden_file);
            end
        end
    end
    // np2's pccore_reset writes the memory switch into the text VRAM at
    // 0xA3FE2+4i BEFORE the ROM runs, from cfg {48 05 04 08 01 00 00 6E}.
    // The ROM never initialises it (DIP bit4 clear), so these bytes ARE the
    // machine's memory configuration: FEA=4 is 640 KB -- the value the whole
    // BIOS/BASIC work-area arithmetic is built around. Without it the guest
    // computes 512 KB-class values and BASIC stacks itself into ROM.
    // pc98_tvram pre-seeds these on reset itself now (its memsw registers,
    // with writes to cells 0xFF0-0xFFF dropped), so the bench inherits the
    // fix through the module rather than poking u_tvram.attr as it used to.
    // The ROM's two-pass boot: pass 1 (keyboard not yet ready) installs
    // IVT[1E]={E800,0A07} at FDB26 and enters BASIC dirty; BASIC's init
    // resets the CPU; pass 2 (keyboard ready, bit7=1) skips the install AND
    // the second ext-ROM scan and boots BASIC with the clean stack. Our
    // keyboard ACK answers on pass 1, so we pre-seed the pass-1 products:
    // IVT[1E] as FDB26 would have written it (table entry 31 = 0A07,
    // CS=E800).
    initial begin
        ram[20'h0078] = 8'h07;   // IVT[1E].IP low
        ram[20'h0079] = 8'h0A;   // IVT[1E].IP high
        ram[20'h007A] = 8'h00;   // IVT[1E].CS low
        ram[20'h007B] = 8'hE8;   // IVT[1E].CS high
        $display("IVT[1E] pre-seeded: E800:0A07");
    end
    initial begin
        int v;
        if ($value$plusargs("ssfix=%d", v)) ss_override_val = v;
        if ($value$plusargs("workEA=%d", v)) work_ea_val = v[15:0];
    end
    // Pre-seed the work area: on a real machine this is set by the ITF's
    //  the BIOS's POST inherits it. Ours has neither, so provide it.
    initial if (work_ea_val != 0) begin
        ram[20'h006EA] = work_ea_val[7:0];
        ram[20'h006EB] = work_ea_val[15:8];
        ram[20'h006E8] = work_ea_val[7:0];
        ram[20'h006E9] = work_ea_val[15:8];
        $display("WORK EA pre-seeded to %04X", work_ea_val);
    end

    // Rolling PC history: the last 64 retirement eu_pcs. Dumped when the
    // machine first falls into low RAM (< 0x10000, excluding the POST's own
    // low-RAM execution) -- answers "which instruction jumped to RAM" once.
    logic       pchist_dump_done = 1'b0;
    logic [19:0] pchist [0:63];
    int pchist_n = 0;
    logic pchist_armed = 1'b0;
    initial pchist_armed = 1'b1;   // armed until the first BASIC entry
    always_ff @(posedge clk_chipset) begin
        if (eu_pc >= 20'hE8000 && eu_pc <= 20'hFFFFF) pchist_armed <= 1'b1;
        if (pchist_armed && eu_pc != 20'h0) begin
            pchist[pchist_n % 64] <= eu_pc;
            pchist_n <= pchist_n + 1;
        end
        if (pchist_armed && eu_pc < 20'h10000 && eu_pc >= 20'h00100
            && !pchist_dump_done) begin
            pchist_dump_done <= 1'b1;
            $display("  %8t  PCFALL: eu_pc=%05X int=%b pic1_irrg=%02X pic1_imr=%02X IVT08=%04X:%04X IVT09=%04X:%04X",
                     $time, eu_pc, pic1_to_cpu,
                     u_pic1.interrupt_request_register, u_pic1.interrupt_mask,
                     {ram[20'h0021],ram[20'h0020]}, {ram[20'h0023],ram[20'h0022]},
                     {ram[20'h0025],ram[20'h0024]}, {ram[20'h0027],ram[20'h0026]});
            $display("  %8t  PCFALL: last 64 ROM retirements:", $time);
            for (int k = 0; k < 64; k++) begin
                int idx;
                idx = (pchist_n + k) % 64;
                $display("    PC[%2d] %05X", k, pchist[idx]);
            end
        end
    end

    // Rolling bus log for derailment forensics
    logic [19:0] buslog_addr [0:19];
    logic [7:0]  buslog_data [0:19];
    logic        buslog_wr   [0:19];
    int          buslog_n = 0;
    logic        derailed_dumped = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (~mem_rd_n || (~mem_wr_n && ~is_rom(cpu_address))) begin
            buslog_addr[buslog_n % 20] <= cpu_address;
            buslog_data[buslog_n % 20] <= ~mem_wr_n ? din_of(cpu_address) : mem_wr_data_q;
            buslog_wr[buslog_n % 20]   <= ~mem_wr_n;
            buslog_n <= buslog_n + 1;
        end
        if (basic_trace && !derailed_dumped && eu_pc < 20'h10000 && eu_pc != 20'h00000) begin
            derailed_dumped <= 1'b1;
            $display("  %8t  DERAIL: eu_pc=%05X  last 20 bus cycles:", $time, eu_pc);
            for (int k = 0; k < 20; k++) begin
                int idx;
                idx = (buslog_n + k) % 20;
                $display("    [%2d] %s %05X data=%02X", k, buslog_wr[idx] ? "RD" : "WR",
                         buslog_addr[idx], buslog_data[idx]);
            end
        end
    end

    // Memory-switch write watch: every write ATTEMPT into tvram cells
    // 0xFF0-0xFFF (A3FE0-A3FFF) gets logged. The POST clear at FECBB sweeps
    // the whole 16 KB, so these are the writes that must be dropped for the
    // pre-seeded switch to survive. Both the bench's tvram_wren gate and the
    // module's own protection drop them now, so this watches the RAW bus
    // cycle -- u_tvram.cpu_wren is long since 0 by the time it would have
    // been interesting.
    always_ff @(posedge clk_chipset) begin
        if (~mem_wr_n && (cpu_address[19:14] == 6'b101000)
            && (cpu_address[13:2] >= 12'hFF8)) begin
            $display("  %8t  MSWW [cell %03X] <= %02X (dropped)  (eu_pc %05X)", $time,
                     cpu_address[12:1], cpu_data_bus, eu_pc);
        end
    end

    // IVT-read watch: during BASIC, any fetch from 0x00000-0x003FF is an
    // interrupt vector load. The fatal derailment lands at 0x067C7 --
    // {IP=67C7, CS=0000} -- so some IVT[n] held that pointer. Find n.
    logic [19:0] ivt_watch_last = 20'hFFFFF;
    always_ff @(posedge clk_chipset) begin
        if (basic_trace && ~mem_rd_n && cpu_address < 20'h00400
            && cpu_address != ivt_watch_last) begin
            ivt_watch_last <= cpu_address;
            $display("  %8t  IVTRD [%05X] => %02X%02X  (eu_pc %05X)", $time,
                     cpu_address, ram[{cpu_address[19:1],1'b1}], ram[{cpu_address[19:1],1'b0}],
                     eu_pc);
        end else if (cpu_address >= 20'h00400) begin
            ivt_watch_last <= 20'hFFFFF;
        end
    end

    // BASIC's wait loop, checked for interrupt readiness: the tick this
    // loop waits on is delivered through INT 0x08, and both the CPU's IF
    // and the PIC's ISR0 state decide whether the next tick arrives.
    logic waitloop_seen = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (eu_pc == 20'h115C2 && !waitloop_seen) begin
            waitloop_seen <= 1'b1;
            $display("  %8t  WAITLOOP: IF=%b psw=%04X isr=%02X imr=%02X int=%b",
                     $time, dbg_regs[217], dbg_regs[223:208],
                     u_pic1.in_service_register,
                     u_pic1.interrupt_mask, pic1_to_cpu_buf);
        end
    end

    // After the last timer edge, report the stuck state once: the output
    // froze, and the reason lives in the counter's own registers.
    int  stuck_count = 0;
    logic stuck_reported = 1'b0;
    always_ff @(posedge clk_chipset) begin
        if (timer_edges > 3 && timer_out0 == timer_out0_d) begin
            if (stuck_count < 1000000) stuck_count <= stuck_count + 1;
            else if (!stuck_reported) begin
                stuck_reported <= 1'b1;
                $display("  %8t  TIMER STUCK after edge #%0d: out=%b", $time, timer_edges, timer_out0);
                $display("        Read the pit: %02X at port 0x71 last write trace above", 0);
            end
        end else if (timer_out0 != timer_out0_d) begin
            stuck_count <= 0;
        end
    end

    // Timer output edges: mode 3 should toggle forever. If the count stops
    // at 2, the counter loaded once and never reloaded -- the mode-3
    // auto-reload is broken in the KF8253's single-byte load path.
    int timer_edges = 0;
    logic timer_out0_d = 1'b0;
    always_ff @(posedge clk_chipset) begin
        timer_out0_d <= timer_out0;
        if (timer_out0 != timer_out0_d) begin
            timer_edges <= timer_edges + 1;
            if (timer_edges < 12)
                $display("  %8t  TIMER EDGE #%0d  out=%b  (eu_pc %05X)", $time,
                         timer_edges, timer_out0, eu_pc);
        end
    end

    // INTA count: how many acknowledges the CPU issued. One means the first
    // interrupt reached the INTA pair; the handler ran if the EU ever stands
    // on FD80:02BC or beyond FDAB1.
    int inta_count = 0;
    int inta_vec08_count = 0;
    logic inta_d = 1'b1;
    always_ff @(posedge clk_chipset) begin
        if (~inta_n) begin
            if (inta_d && din == 8'h08) inta_vec08_count <= inta_vec08_count + 1;
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
    int k;
    always_ff @(posedge clk_chipset) begin
        eu_cs_d <= eu_cs;
        if (eu_cs != eu_cs_d) begin
            $display("  %8t  CS %04X -> %04X  (pc %05X)", $time, eu_cs_d, eu_cs, eu_pc);
            $display("        IVT 60: %02X %02X %02X %02X  70: %02X %02X %02X %02X  78: %02X %02X %02X %02X  80: %02X %02X %02X %02X",
                     ram[20'h0060], ram[20'h0061], ram[20'h0062], ram[20'h0063],
                     ram[20'h0070], ram[20'h0071], ram[20'h0072], ram[20'h0073],
                     ram[20'h0078], ram[20'h0079], ram[20'h007A], ram[20'h007B],
                     ram[20'h007C], ram[20'h007D], ram[20'h007E], ram[20'h007F],
                     ram[20'h0080], ram[20'h0081], ram[20'h0082], ram[20'h0083]);
            $display("        IVT 84: %02X %02X %02X %02X",
                     ram[20'h0084], ram[20'h0085], ram[20'h0086], ram[20'h0087]);
            $display("        FAR 4AC: %02X %02X %02X %02X   STUB A00: %02X %02X %02X %02X %02X %02X %02X %02X",
                     ram[20'h004AC], ram[20'h004AD], ram[20'h004AE], ram[20'h004AF],
                     ram[20'h00A00], ram[20'h00A01], ram[20'h00A02], ram[20'h00A03],
                     ram[20'h00A04], ram[20'h00A05], ram[20'h00A06], ram[20'h00A07]);
            // Every segment transfer in this boot is worth its full context:
            // there are five of them in ninety seconds, and one of them is the
            // machine leaving the ROM for good.
            for (k = 0; k < 48; k = k + 1)
                $display("        %05X  op %02X",
                         disp_pc[(disp_w + 64 - 48 + k) % 64],
                         byte_at(disp_pc[(disp_w + 64 - 48 + k) % 64]));
        end
    end

    // ---- keyboard: the 8251 at 0x41/0x43, present, like the machine's --------
    //
    // The BIOS's FD930 block resets the keyboard and waits for its 0x60 ACK
    // before it will set bit 7 of [0x0500] -- and without that bit the
    // vector installer at FDB1E writes the no-keyboard defaults into INT
    // 1E/1F: BASIC at D800:2A00, an option-ROM slot nothing occupies on this
    // machine. Every run so far vectored there and derailed in empty RAM;
    // the hardware does the same, because nothing answers 0x41/0x43 there
    // either. A command write to 0x43 arms one 0x60; status bit 1 says a
    // byte is waiting; reading 0x41 takes it.
    logic       kbd_ack_armed = 1'b0;
    logic       kbd_wr_d = 1'b1;
    logic       kbd_rd_d = 1'b1;
    logic       soft_reset_cpu_d = 1'b0;
    logic       force_pass1_reset = 1'b0;
    wire        kbd_wr = ~io_wr_n & ((cpu_address[15:0] == 16'h0043)
                               |    (cpu_address[15:0] == 16'h0073));
    wire        kbd_rd = ~io_rd_n & (cpu_address[15:0] == 16'h0041);
    // Arm on a command write, take on the read: the keyboard ACKs its reset.
    // With the ACK always offered, the ITF's first probe (before ANY command
    // write) also sees 0x60 and the ITF skips its whole test sequence --
    // which is not what a cold machine does.
    logic       kbd_disabled = 1'b0;
    int         cpu_reset_count = 0;
    initial begin
        if ($test$plusargs("nokbd")) kbd_disabled = 1'b1;
        // Default: the keyboard answers from the second boot pass on --
        // the real one is still powering up during the first POST.
        if (!$test$plusargs("kbdpass1")) kbd_disabled = 1'b1;
    end
    wire [7:0]  kbd_status = kbd_disabled ? 8'h00 :
                             kbd_ack_armed ? 8'h02 : 8'h00;

    // Pass-1 cut: the dirty pass-1 BASIC can't reach its own reset (the
    // F202 stack breaks it first). The real pass 1 waits for the keyboard
    // and reboots; we pulse the same reset on first BASIC entry.
    logic pass1_reset_fired = 1'b0;
    logic basic_seen_q = 1'b0;
    always_ff @(posedge clk_chipset) begin
        basic_seen_q <= basic_trace;
        if (basic_trace && !basic_seen_q && !pass1_reset_fired
            && cpu_reset_count == 0) begin
            pass1_reset_fired <= 1'b1;
            force_pass1_reset <= 1'b1;
            $display("  %8t  PASS1: BASIC entered dirty -- forcing CPU reset for pass 2", $time);
        end
    end

    // The real keyboard answers its reset command in ~10-30 ms; the BIOS's
    // boot test polls for ~1-2 ms and TIMES OUT -- that failure is the
    // machine's normal path ([0x500].bit7 stays clear, FDB1E installs
    // IVT[1E], BASIC is entered). The ACK arrives for the LATER polls.
    // An instant ACK here makes the boot test pass, skips the vector
    // install, and crashes the machine -- so answer late.
    int kbd_ack_delay = 0;
    always_ff @(posedge clk_chipset) begin
        kbd_wr_d <= kbd_wr;
        kbd_rd_d <= kbd_rd;
        if (kbd_wr & ~kbd_wr_d) kbd_ack_delay <= 3436364; // ~80 ms at 42.95 MHz
        else if (kbd_ack_delay > 0) begin
            kbd_ack_delay <= kbd_ack_delay - 1;
            if (kbd_ack_delay == 1) kbd_ack_armed <= 1'b1;
        end
        soft_reset_cpu_d <= soft_reset_cpu;
        if (kbd_rd_d & ~kbd_rd) kbd_ack_armed <= 1'b0;
    end

    wire kbd_stat_iocycle = ~io_rd_n & (cpu_address[15:0] == 16'h0043);
    wire kbd_data_iocycle = ~kbd_disabled &
                             ~io_rd_n & (cpu_address[15:0] == 16'h0041) & kbd_ack_armed;

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
    // session and every one of them had to be fixed twice by hand; the second
    // copy is gone. See pc98_fdc.sv.
    wire       fdc_base_sel, fdc_msr_sel, fdc_fifo_sel;
    wire [7:0] fdc_msr, fdc_fifo;
    wire       fdc_irq3, fdc_irq2;

    pc98_fdc u_pc98_fdc (
        .clock            (clk_chipset),
        .reset            (reset),
        .address          (cpu_address[15:0]),
        .address_enable_n (1'b0),
        .io_read_n        (io_rd_n),
        .io_write_n       (io_wr_n),
        .data_in          (cpu_data_bus),
        .base_select      (fdc_base_sel),
        .msr_select       (fdc_msr_sel),
        .fifo_select      (fdc_fifo_sel),
        .msr              (fdc_msr),
        .fifo             (fdc_fifo),
        .irq_int          (fdc_irq3),
        .irq_2dd          (fdc_irq2)
    );

    // The conversation, one line per byte, reached into the instance. The
    // status polling is what floods and is not logged, so this stays small.
    always_ff @(posedge clk_chipset) begin
        if (u_pc98_fdc.fdc_wr_pulse)
            $display("  %8t  FDC <- %02X   (%s, writes_left %0d, results_left %0d)",
                     $time, u_pc98_fdc.fdc_wr_data,
                     (u_pc98_fdc.fdc_writes_left == 4'd0) ? "cmd" : "param",
                     u_pc98_fdc.fdc_writes_left, u_pc98_fdc.fdc_results_left);
        if (u_pc98_fdc.fdc_rd_pulse && u_pc98_fdc.fdc_in_result)
            $display("  %8t  FDC -> %02X   (result %0d of %0d)",
                     $time, fdc_fifo, u_pc98_fdc.fdc_result_idx,
                     u_pc98_fdc.fdc_results_left);
        if (u_pc98_fdc.fdc_cmd_done)
            $display("  %8t  FDC done cmd %02X  results_left %0d  pend %01X",
                     $time, u_pc98_fdc.fdc_cmd, u_pc98_fdc.fdc_results_left,
                     u_pc98_fdc.fdc_seek_pend);
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
    // is the real program counter.
    wire [15:0] eu_ip = dbg_regs[207:192];   // retired-instruction IP
    wire [15:0] eu_cs = dbg_cs;
    wire [19:0] eu_pc = {eu_cs, 4'd0} + {4'd0, eu_ip};

    // Instruction retirement: dbg_regs updates as each instruction retires,
    // so watching eu_pc move gives the x86 trace the old bench read out of
    // mcl86's microcode dispatch. Only the discontinuities are kept -- a
    // delay loop is one branch taken 65536 times, and collapsed, 64 entries
    // cover a whole 1.4-second ITF cycle.
    logic basic_trace = 1'b0;
    int   basic_n = 0;
    int   itf_ck_n = 0;
    int   m;
    logic [19:0] disp_pc [0:63];
    int          disp_w = 0;
    logic [19:0] disp_rec  = 20'hFFFFF;

    function automatic logic [7:0] byte_at(input logic [19:0] a);
        byte_at = is_rom(a) ? rom_byte(a) : ram[a];
    endfunction

    always_ff @(posedge clk_chipset) begin
        if (eu_pc != eu_pc_retired_d) begin
            if ((eu_pc < eu_pc_retired_d || eu_pc > eu_pc_retired_d + 20'd8)
                && eu_pc != disp_rec) begin
                disp_pc[disp_w % 64] <= eu_pc;
                disp_rec <= eu_pc;
                if (disp_w < 400000)
                    $display("    J%0d %05X op %02X", disp_w, eu_pc, byte_at(eu_pc));
                disp_w <= disp_w + 1;
            end
            if (eu_cs == 16'hE800) basic_trace <= 1'b1;
            // The BASIC crash site: F3ACE gates an indirect far call on
            // [DS:0x15B5] and calls through [DS:0x15C6]. Neither is ever
            // written by the ROM -- on a real machine the whole area reads
            // zero and the gate stays shut. Our run called 0FB0:BAD9. Catch
            // the moment: dump the registers, the work area, and every write
            // into offset 0x15B0-0x15D0 from here on.
            if (eu_cs == 16'hE800 && !hook_watch) hook_watch <= 1'b1;
            // (the din_of override below answers the POP SS directly)
            if (eu_pc == 20'hF3ACE) begin
                $display("  %8t  HOOK SITE: cs=%04X ss=%04X ds=%04X", $time,
                         dbg_cs, dbg_ss, dbg_regs[191:176]);
                $display("        [15B0]: %02X %02X %02X %02X %02X %02X %02X %02X  [15C0]: %02X %02X %02X %02X %02X %02X %02X %02X",
                         ram[{dbg_ss,4'd0}+20'h15B0], ram[{dbg_ss,4'd0}+20'h15B1],
                         ram[{dbg_ss,4'd0}+20'h15B2], ram[{dbg_ss,4'd0}+20'h15B3],
                         ram[{dbg_ss,4'd0}+20'h15B4], ram[{dbg_ss,4'd0}+20'h15B5],
                         ram[{dbg_ss,4'd0}+20'h15B6], ram[{dbg_ss,4'd0}+20'h15B7],
                         ram[{dbg_ss,4'd0}+20'h15C0], ram[{dbg_ss,4'd0}+20'h15C1],
                         ram[{dbg_ss,4'd0}+20'h15C2], ram[{dbg_ss,4'd0}+20'h15C3],
                         ram[{dbg_ss,4'd0}+20'h15C4], ram[{dbg_ss,4'd0}+20'h15C5],
                         ram[{dbg_ss,4'd0}+20'h15C6], ram[{dbg_ss,4'd0}+20'h15C7]);
            end
            // The ITF's memory sizing, at the two points where it has just
            // verified a 64 KB pair: BX is the segment it tested, DH the
            // running block count, and CF says whether the compare held.
            if (eu_pc == 20'hF9678 && itf_ck_n < 2) begin
                itf_ck_n <= itf_ck_n + 1;
                $display("  %8t  SIZE DISPLAY  dx %04X  bx %04X", $time,
                         dbg_dx, dbg_bx);
                tvram_row0_dump;
                for (m = 0; m < 48; m = m + 1)
                    $display("        %05X  op %02X",
                             disp_pc[(disp_w + 64 - 48 + m) % 64],
                             byte_at(disp_pc[(disp_w + 64 - 48 + m) % 64]));
            end
            if (eu_pc == 20'hF8880 || eu_pc == 20'hF8B1E
             || eu_pc == 20'hF889A || eu_pc == 20'hF8B38) begin
                $display("  %8t  MEMSIZE at %05X  bx %04X dx %04X ax %04X  CF=%0d",
                         $time, eu_pc, dbg_bx, dbg_dx, dbg_ax, dbg_regs[208]);
            end
            // Re-arm a 1000-entry window when a FRESH BASIC entry happens
            // (back in the E800 ROM after having exhausted the cap before).
            if (basic_trace && basic_n >= 50000
                && (eu_pc >= 20'hE8000) && (eu_pc <= 20'hFFFFF))
                basic_n <= 49000;
            if (basic_trace && basic_n < 50000) begin
                basic_n <= basic_n + 1;
                $display("    B%0d  %05X  op %02X  ax %04X bx %04X cx %04X dx %04X si %04X di %04X  ss %04X ds %04X es %04X sp %04X",
                         basic_n, eu_pc, byte_at(eu_pc),
                         dbg_ax, dbg_bx, dbg_cx, dbg_dx, dbg_si, dbg_di,
                         dbg_ss, dbg_regs[191:176], dbg_regs[143:128], dbg_sp);
            end
        end
        eu_pc_retired_d <= eu_pc;
    end
    logic [19:0] eu_pc_retired_d = 20'hFFFFF;
    logic        hook_watch = 1'b0;

    // The renderer's eye on row 0: present each cell to the real tvram's fill
    // port and record what a glyph_addr would make of it. is_kanji on a cell
    // the guest wrote as plain ANK is the run#191 symptom -- the letter goes
    // to the two-byte path and the screen shows a dense wrong glyph with its
    // neighbour swallowed as the right half.
    task automatic tvram_row0_dump;
        int k;
        begin
            $write("        row0 decode:");
            for (k = 0; k < 16; k = k + 1) begin
                // fil_* are registered: present, wait a clock, then read.
                tvram_fil_cell = 12'(k);
                @(posedge clk_chipset); @(posedge clk_chipset);
                $write(" %02X%02X%s", tvram_fil_hi_q, tvram_fil_lo_q,
                       (tvram_fil_hi_q != 8'h00) ? "*" : " ");
            end
            $display("   (* = kanji-flagged)");
            tvram_fil_cell = 12'd0;
        end
    endtask
    logic [7:0]  tvram_fil_lo_q, tvram_fil_hi_q;
    always_ff @(posedge clk_chipset) begin
        tvram_fil_lo_q <= tvram_lo_dummy;
        tvram_fil_hi_q <= tvram_hi_dummy;
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
    wire [19:0] resume_stack = {dbg_ss, 4'd0}
                             + {4'd0, dbg_sp};
    always_ff @(posedge clk_chipset) begin
        if (eu_pc == 20'hF9475 && save_seen < 4) begin
            save_seen <= save_seen + 1;
            $display("  %8t  SAVE entry: ss=%04X sp=%04X  [0404]=%02X%02X [0406]=%02X%02X",
                     $time, dbg_ss,
                     dbg_sp,
                     ram[20'h405], ram[20'h404], ram[20'h407], ram[20'h406]);
        end
        if (eu_pc == 20'hF8069 && resume_seen < 4) begin
            resume_seen <= resume_seen + 1;
            $display("  %8t  RESUME retf: ss=%04X sp=%04X  [0404]=%02X%02X [0406]=%02X%02X",
                     $time, dbg_ss,
                     dbg_sp,
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
    initial begin
        for (i = 0; i < 1048576; i = i + 1) ram[i] = 8'h00;
        $readmemh("itf.hex",  itf);
        $readmemh("bios.hex", bios);
        // WORKAROUND: the 0x66 prefix at E800:0001 (file 0x0001) makes the
        // following short jump land at FFDA instead of FFE1 on nuV30. The
        // real V30's 66+18 77 d5 decodes as a 4-byte prefix+SBB and the
        // stream continues to mov si,bx / rep movsb / jmp FFE1. Replace the
        // prefix with NOP so the intended path runs (the SBB itself is a
        // harmless work-area RMW).
        if (bios[1] == 8'h66) bios[1] = 8'h90;  // only patch if present

        // +basicvec=1: pre-seed INT 1F with the N88-BASIC entry, the way a
        // machine whose boot has already established it would hold it. The
        // ROM's own installer writes D800:xxxx there (the option-ROM slot),
        // and whose job the E800 vector is on a bare VM is still open -- but
        // whether BASIC itself runs on this CPU is the question this answers.
        if ($test$plusargs("basicvec")) begin
            ram[20'h0007C] = 8'h07; ram[20'h0007D] = 8'h0A;
            ram[20'h0007E] = 8'h00; ram[20'h0007F] = 8'hE8;
            $display("IVT[1F] pre-seeded with E800:0A07");
        end

        $display("ITF  reset vector F8000+7FF0: %02X %02X %02X %02X %02X",
                 itf[16'h7FF0], itf[16'h7FF1], itf[16'h7FF2],
                 itf[16'h7FF3], itf[16'h7FF4]);
        $display("BIOS reset vector E8000+17FF0: %02X %02X %02X %02X %02X",
                 bios[18'h17FF0], bios[18'h17FF1], bios[18'h17FF2],
                 bios[18'h17FF3], bios[18'h17FF4]);
        $display("--- trace (first 400 distinct fetch addresses) ---");

        repeat (40) @(posedge clk_chipset);
        reset = 1'b0;

        // One chunk is 5M chipset clocks, which is 116 ms of guest time --
        // NOT one second, and the two runs that read it that way stopped at
        // 4.7 and 2.7 seconds and proved nothing. The machine has to be met
        // AFTER the screen clear, and the clear alone took 8 seconds, so the
        // run needs the full 780 chunks (90 s) the sweep run used, and then
        // some: the memory test was still going at 280 KB when that one ended.
        for (i = 0; i < 1200; i = i + 1) begin
            repeat (5_000_000) @(posedge clk_chipset);
            $display("  ... %0t  EU %05X  op %02X  wr %05X-%05X n %0d  tvw %0d",
                     $time, eu_pc, byte_at(eu_pc),
                     wr_lo_chunk, wr_hi_chunk, wr_n_chunk, tvram_wr_count);
            $write("        cx %04X min %04X  ax %04X bx %04X dx %04X  pc:",
                   eu_cx, cx_min_chunk,
                   dbg_ax, dbg_bx,
                   dbg_dx);
            for (j = 0; j < 16; j = j + 1)
                $write(" %05X", pc_ring[(pc_ring_w + j) % 16]);
            $display("");
            wr_clear_tog = ~wr_clear_tog;
        end

        $display("--- done ---");
        $display("PIT gate2     %0d  (counters now %04X %04X %04X)", gate2,
                 u_pit.u_KF8253_Counter_0.count[15:0],
                 u_pit.u_KF8253_Counter_1.count[15:0],
                 u_pit.u_KF8253_Counter_2.count[15:0]);
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
        $finish;
    end

endmodule

`default_nettype wire
