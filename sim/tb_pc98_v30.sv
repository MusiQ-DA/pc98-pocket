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
    function automatic logic [7:0] din_of(input logic [19:0] a);
        din_of = ~mem_rd_n    ? (is_rom(a) ? rom_byte(a) : ram[a])
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
            3'b100, 3'b101: DATA_I = {din_odd, din_even};   // CODE, MEMR
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
        if (io_wr_n & ~f0_prev_wr_n & (cpu_address[15:0] == 16'h00F0)) begin
            soft_reset_cpu   <= 1'b1;
            soft_reset_count <= 8'hFF;
            $display("  %8t  OUT 00F0 -- CPU reset requested (eu_pc %05X)", $time, eu_pc);
        end else if (soft_reset_count != 8'h00)
            soft_reset_count <= soft_reset_count - 8'h01;
        else
            soft_reset_cpu <= 1'b0;
    end

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
    logic [7:0] mem_wr_data_q = 8'h00;
    logic [15:0] mem_wr_word_q = 16'h0000;

    // One committed byte of a memory write, with every watcher that used to
    // sit inline on the eight-bit bus: the sweep ranges, the ITF's
    // reset-resume save window, and the text-plane snoop.
    task automatic commit_mem_byte(input logic [19:0] a, input logic [7:0] d);
        if (~is_rom(a)) begin
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
        .interrupt_request({pic2_to_cpu, 4'b0, crt_vsync_mock, 1'b0, timer_out0})
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
    logic       kbd_ack_armed = 1'b1;
    logic       kbd_wr_d = 1'b1;
    wire        kbd_wr = ~io_wr_n & ((cpu_address[15:0] == 16'h0043)
                               |    (cpu_address[15:0] == 16'h0073));
    wire        kbd_rd = ~io_rd_n & (cpu_address[15:0] == 16'h0041);
    // Always ready, always the ACK: the handshakes read one byte and compare
    // it, and a keyboard that has just been reset obliges. Arming only on a
    // command write lost the ITF's first probe, whose init writes go to a
    // port this image never touches.
    wire [7:0]  kbd_status = 8'h02;

    always_ff @(posedge clk_chipset) begin
        kbd_wr_d <= kbd_wr;
        if (kbd_wr & ~kbd_wr_d) kbd_ack_armed <= 1'b1;
        if (kbd_rd)             kbd_ack_armed <= 1'b1;
    end

    wire kbd_stat_iocycle = ~io_rd_n & (cpu_address[15:0] == 16'h0043);
    wire kbd_data_iocycle = ~io_rd_n & (cpu_address[15:0] == 16'h0041) & kbd_ack_armed;

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
                if (disp_w < 4000)
                    $display("    J%0d %05X op %02X", disp_w, eu_pc, byte_at(eu_pc));
                disp_w <= disp_w + 1;
            end
            if (eu_cs == 16'hE800) basic_trace <= 1'b1;
            // The ITF's memory sizing, at the two points where it has just
            // verified a 64 KB pair: BX is the segment it tested, DH the
            // running block count, and CF says whether the compare held.
            if (eu_pc == 20'hF9678 && itf_ck_n < 2) begin
                itf_ck_n <= itf_ck_n + 1;
                $display("  %8t  SIZE DISPLAY  dx %04X  bx %04X", $time,
                         dbg_dx, dbg_bx);
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
            if (basic_trace && basic_n < 600) begin
                basic_n <= basic_n + 1;
                $display("    B%0d  %05X  op %02X  ax %04X bx %04X cx %04X dx %04X si %04X di %04X",
                         basic_n, eu_pc, byte_at(eu_pc),
                         dbg_ax, dbg_bx, dbg_cx, dbg_dx, dbg_si, dbg_di);
            end
        end
        eu_pc_retired_d <= eu_pc;
    end
    logic [19:0] eu_pc_retired_d = 20'hFFFFF;

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
