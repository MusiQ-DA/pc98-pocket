//
// tb_fdc_si_stall -- the third deadlock: the uPD71071 parks in SI with the
// FDC's DRQ pending and never takes a byte (SuperDepth in-game freeze,
// JTAG tap 0xA0: state=SI, hrq=0, drq pins pending, RAM path idle).
//
// The metal's exact topology around the DMAC, real RTL only:
//
//   BUS_ARBITER (the real one: the 92/201 dce divider clocks the real
//   upd71071, the real hold-grant chain, the real page registers, the real
//   strobe merge) <- READY.sv (real) closes dma_ready exactly as Chipset
//   wires it. The DRQ path is Peripherals' verbatim: fdd_dma_req is held
//   low for the whole DACK window and re-asserted only at the next
//   cpu_ce_negedge, gated by the 0x94 DMAE bit; floppy.v's dma_req is a
//   LEVEL while the sector FIFO holds data (the sector is pre-filled --
//   within a sector the real 765's microsecond DRQ dips do not exist in
//   this model), dipping one clk at each ack-fall, dropping at TC.
//   dma_request[] carries the metal's tie-off: ch0/ch1 pins permanently
//   "requesting" (they idle through the sense bit), ch2/ch3 inverted
//   sources of fdd_dma_req. The command register is programmed 0x40 (DREQ
//   sense active-low) the way the ITF does at boot -- nothing else in the
//   guest stack ever writes port 0x11.
//
// The bench CPU performs the BIOS's own arm sequence through the real
// register bus (byte-pointer clear, mode, address, count-1, page, unmask),
// then streams sectors and re-arms per sector like the BIOS's FDC INT
// handler. Scoreboard: every byte must land in the sink memory at the
// right address. The witness this hunts: DRQ pending, state==SI, and no
// DACK edge for a watchdog window -> dump the whole priority-encoder
// state (mask/lock/request/disable) that only this bench can see.
//
// Plusargs:
//   +MODE=mm   mode register byte (default 0x46 = single, FDC read, ch2;
//              try 0x06 = demand)
//   +SPEED=s   ce_generator clk_select 0..3 (8.0 / 9.83 / 11.97 / 21.5 MHz)
//   +ITERS=n   sectors to stream (default 4)
//   +TCAT=n    force the DMA count to n bytes (default: sector size) --
//              TC mid-FIFO, the "count < sector" shape
//   +TRACE=1   per-byte line
//
// Build: see scripts/sim_fdc_si_stall.sh (real Bus_Arbiter + real READY +
// the ce_generator, same --timing shape as the other DMA benches).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_fdc_si_stall;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic reset = 1'b1;

    int mode_byte = 8'h46;
    int speed_sel = 0;
    int iters     = 4;
    int tc_at     = 0;      // 0 = count = sector size
    int trace     = 0;
    initial begin
        int v;
        if ($value$plusargs("MODE=%h", v))  mode_byte = v;
        if ($value$plusargs("SPEED=%d", v)) speed_sel = v;
        if ($value$plusargs("ITERS=%d", v)) iters = v;
        if ($value$plusargs("TCAT=%d", v))  tc_at = v;
        if ($value$plusargs("TRACE=%d", v)) trace = v;
    end

    // ---- the CPU clock train (the metal's own CE generator) ----------------
    logic [1:0] clk_sel;
    initial begin clk_sel = 2'd0; end
    always_comb clk_sel = 2'(speed_sel);
    wire  clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire  cycle_accrate, shift_read_timing;
    wire  [7:0] ccc_div, ccc_dec;
    wire  [1:0] ram_rd_wait, ram_wr_wait;
    logic biu_done = 1'b1;

    ce_generator u_ce (
        .clock                              (clk),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (clk_sel),
        .cpu_clk_pin                        (clk_cpu),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .cycle_accrate                      (cycle_accrate),
        .clock_cycle_counter_division_ratio (ccc_div),
        .clock_cycle_counter_decrement_value(ccc_dec),
        .shift_read_timing                  (shift_read_timing),
        .ram_read_wait_cycle                (ram_rd_wait),
        .ram_write_wait_cycle               (ram_wr_wait),
        .vram_wait_en                       ()
    );

    // ---- the bench CPU master (V30-shaped status into the real 8288) -------
    // Status encodings per i8288.sv: 001 = IO read, 010 = IO write,
    // 111 = passive. A cycle holds its status across several CEs like the
    // V30 does; the 8288 turns it into ALE + IORC/IOWC + DEN.
    logic [19:0] cpu_address  = 20'h0;
    logic [7:0]  cpu_data_bus = 8'h00;
    logic [2:0]  processor_status = 3'b111;
    wire         processor_lock_n = 1'b1;

    // ---- the real BUS_ARBITER ----------------------------------------------
    wire  [19:0] address;
    wire         address_direction, address_latch_enable;
    wire  [7:0]  internal_data_bus;
    wire         data_bus_direction;
    wire         io_read_n, io_read_n_direction;
    wire         io_write_n, io_write_n_direction;
    wire         memory_read_n, memory_read_n_direction;
    wire         memory_write_n, memory_write_n_direction;
    wire         no_command_state, interrupt_acknowledge_n;
    wire         processor_transmit_or_receive_n;
    wire         dma_wait_n;
    wire  [7:0]  dbg_hold;
    wire [127:0] dbg_dma_w, dbg_dma3_w;
    wire [15:0]  dbg_w_w;
    wire         dma_ready;

    // The metal's tie-off: dma_request top-level input = 0 and DRQ0 = 0, so
    // the 71071 sees ch0/ch1 pins permanently low ("requesting" through the
    // active-low sense) and ch2/ch3 as ~fdd_dma_req.
    logic        fdd_dma_req;
    wire  [3:0]  dma_request_in = {~(fdd_dma_req | 1'b0), ~fdd_dma_req,
                                   ~1'b0, ~1'b0};

    wire  [3:0]  dma_acknowledge_n;
    wire         address_enable_n, terminal_count_n;

    // Peripherals' chip-select equations, verbatim (loose upper bits and
    // all -- the aliases are part of the machine).
    wire pc98_io = (~io_read_n | ~io_write_n) & ~address_enable_n
                 & ~address[9] & ~address[8];
    wire dma_chip_select_n      = ~(pc98_io & address[0] & ~address[7]
                                    & ~address[6] & ~address[5]);
    wire dma_page_chip_select_n = ~(pc98_io & address[0]
                                    & (address[7:4] == 4'h2));

    // The external bus side: idle, except the FDC's byte during a DACK'd
    // IO read (Peripherals drives data_bus_out = fdd_dma_readdata while
    // fdd_dma_ack & ~IOW).
    wire  [19:0] address_ext = 20'h0;
    wire  [7:0]  fdc_byte_bus;
    wire  [7:0]  data_bus_ext = fdc_byte_bus;
    wire         io_read_n_ext = 1'b1, io_write_n_ext = 1'b1;
    wire         memory_read_n_ext = 1'b1, memory_write_n_ext = 1'b1;

    BUS_ARBITER u_arb (
        .clock                              (clk),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .cpu_address                        (cpu_address),
        .cpu_data_bus                       (cpu_data_bus),
        .processor_status                   (processor_status),
        .processor_lock_n                   (processor_lock_n),
        .processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .address                            (address),
        .address_ext                        (address_ext),
        .address_direction                  (address_direction),
        .data_bus_ext                       (data_bus_ext),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_direction                 (data_bus_direction),
        .address_latch_enable               (address_latch_enable),
        .io_read_n                          (io_read_n),
        .io_read_n_ext                      (io_read_n_ext),
        .io_read_n_direction                (io_read_n_direction),
        .io_write_n                         (io_write_n),
        .io_write_n_ext                     (io_write_n_ext),
        .io_write_n_direction               (io_write_n_direction),
        .memory_read_n                      (memory_read_n),
        .memory_read_n_ext                  (memory_read_n_ext),
        .memory_read_n_direction            (memory_read_n_direction),
        .memory_write_n                     (memory_write_n),
        .memory_write_n_ext                 (memory_write_n_ext),
        .memory_write_n_direction           (memory_write_n_direction),
        .no_command_state                   (no_command_state),
        .ext_access_request                 (1'b0),
        .dma_request                        (dma_request_in),
        .dma_acknowledge_n                  (dma_acknowledge_n),
        .address_enable_n                   (address_enable_n),
        .terminal_count_n                   (terminal_count_n),
        .dbg                                (dbg_hold),
        .dbg_dma                            (dbg_dma_w),
        .watch_addr                         (20'h0),
        .dbg_dma3                           (dbg_dma3_w),
        .dbg_w                              (dbg_w_w)
    );

    // ---- the real READY (dma_ready for the DMAC's SW exit) -----------------
    // io_channel_ready tied ready: an instant memory sink. The metal's
    // memory_access_ready is the fast case for DMA writes; the slow case is
    // what tb_ram_dma_fill covers -- this bench hunts the DRQ path.
    wire  processor_ready_unused;
    READY u_ready (
        .clock                              (clk),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .processor_ready                    (processor_ready_unused),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .io_channel_ready                   (1'b1),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .dma0_acknowledge_n                 (dma_acknowledge_n[0]),
        .address_enable_n                   (address_enable_n),
        .dbg                                ()
    );

    // ---- the FDC side, Peripherals' equations verbatim ---------------------
    // One sector FIFO, pre-filled (floppy.v semantics: dma_req is a LEVEL
    // while the FIFO holds data; one pop per ack-fall pulse; drops for good
    // at TC = dma_has_terminated).
    localparam int SEC = 1024;

    int  fifo_cnt = 0;
    int  fifo_base = 0;            // sector index, for data patterns
    logic dma_has_terminated = 1'b0;
    logic fdc_dma_enable = 1'b0;   // 0x94 bit4 (DMAE)

    // The glue's 0x94 control latch: DMAE (bit 4) gates the DRQ line.
    logic prev_iow_94 = 1'b1;
    always_ff @(posedge clk) begin
        prev_iow_94 <= io_write_n;
        if (!reset && prev_iow_94 && !io_write_n && !address_enable_n
            && address[7:0] == 8'h94)
            fdc_dma_enable <= internal_data_bus[4];
    end

    wire fdd_dma_ack = ~dma_acknowledge_n[2] | ~dma_acknowledge_n[3];
    logic prev_fdd_dma_ack = 1'b0;
    always_ff @(posedge clk) prev_fdd_dma_ack <= fdd_dma_ack;
    wire fdd_dma_rw_ack = prev_fdd_dma_ack & ~fdd_dma_ack;

    // floppy.v's dma_req shape (execution phase, DMA mode, IRQ enabled):
    // level while the FIFO is non-empty, low for the one-clk ack pulse,
    // low for good after TC.
    wire fdd_dma_req_wire = ~dma_has_terminated & ~fdd_dma_rw_ack
                          & (fifo_cnt != 0);

    // Peripherals.sv:2636-2648 verbatim.
    always_ff @(posedge clk) begin
        if (fdd_dma_ack)
            fdd_dma_req <= 1'b0;
        else if (cpu_ce_negedge)
            fdd_dma_req <= fdd_dma_req_wire & fdc_dma_enable;
    end

    // Peripherals.sv:2527-2543 verbatim (TC latch + delivery).
    logic fdd_dma_tc = 1'b0;
    wire  terminal_count = terminal_count_n;   // active-high, as Chipset wires it
    always_ff @(posedge clk) begin
        if (fdd_dma_ack) begin
            if (fdd_dma_tc == 1'b0)
                fdd_dma_tc <= terminal_count;
        end else
            fdd_dma_tc <= 1'b0;
    end
    wire fdd_dma_tc_pulse = fdd_dma_tc & fdd_dma_rw_ack;

    // The FIFO itself: fills per "command", pops once per ack-fall.
    always_ff @(posedge clk) begin
        if (reset) begin
            fifo_cnt <= 0;
            dma_has_terminated <= 1'b0;
        end else begin
            if (fdd_dma_rw_ack && fifo_cnt != 0)
                fifo_cnt <= fifo_cnt - 1;
            if (fdd_dma_tc_pulse)
                dma_has_terminated <= 1'b1;
        end
    end

    // The FDC's byte on the external bus during the DACK'd read window.
    // Address-correlated like tb_ram_dma_fill's, so a missed beat shows up
    // as a data mismatch rather than an index slip.
    localparam logic [19:0] FILL_BASE = 20'h04000;
    wire [7:0] fifo_head_byte = 8'hA5 ^ (FILL_BASE[7:0] + 8'(SEC - fifo_cnt));
    assign fdc_byte_bus = (fdd_dma_ack & io_write_n) ? fifo_head_byte : 8'hFF;

    // ---- the memory sink + scoreboard --------------------------------------
    logic [7:0] sink [0:65535];
    int dack_edges = 0;
    int bytes_seen = 0;
    logic prev_dack2 = 1'b1;
    always_ff @(posedge clk) begin
        if (reset) begin
            dack_edges <= 0;
            prev_dack2 <= 1'b1;
        end else begin
            prev_dack2 <= dma_acknowledge_n[2];
            if (prev_dack2 & ~dma_acknowledge_n[2])
                dack_edges <= dack_edges + 1;
        end
    end

    // capture the DMAC's memory writes (it owns the bus: AEN high)
    logic prev_memwr = 1'b1;
    always_ff @(posedge clk) begin
        prev_memwr <= memory_write_n;
        if (!reset && prev_memwr && !memory_write_n && address_enable_n) begin
            sink[address[15:0]] <= data_bus_ext;
            bytes_seen <= bytes_seen + 1;
            if (trace)
                $display("[%0t] DMA wr %05x <= %02x (fifo %0d)",
                         $time, address, data_bus_ext, fifo_cnt);
        end
    end

    // ---- bench CPU bus cycles ----------------------------------------------
    // One bus master, two drivers (the main sequence and the MSR poll
    // loop): cpu_busy serializes them, poll_run parks the poll loop while
    // the main sequence runs an arm/disarm.
    //
    // TAIL selects the write-cycle tail's shape:
    //   0 "hold"   -- the address/data stay up until the IOWC has retired
    //                 (the 8086/V30 contract the 71071 was written for);
    //   1 "bridge" -- the NEXT cycle's address/data load while the IOWC is
    //                 still low, ~1 CE before its rise -- the metal's
    //                 cpu_bus_bridge does exactly this: the pair releases,
    //                 B_IDLE arms the next access, and ad_out/cpu_data_bus
    //                 switch inside the 8288's strobe tail. The 71071
    //                 latches the register/data continuously while IOW is
    //                 low and decodes from a 1-clk-delayed stable_address
    //                 at the rise -- the tail can feed it the NEXT cycle's
    //                 address/data, and the write lands on the wrong
    //                 register (or none). The 6-36 s SuperDepth wedge.
    int  tail_shape = 1;
    int  tail_lead = 1;      // clks after passive before the pins switch
    logic [19:0] next_addr = 20'h7C0F0;   // a plausible next fetch
    logic [7:0]  next_data = 8'h90;
    initial begin
        int v;
        if ($value$plusargs("TAIL=%d", v)) tail_shape = v;
        if ($value$plusargs("LEAD=%d", v)) tail_lead = v;
    end

    logic poll_run = 1'b0;
    logic cpu_busy = 1'b0;

    task cpu_out(input [7:0] port, input [7:0] val);
        int waited;
        begin
            while (cpu_busy) @(posedge clk);
            cpu_busy = 1'b1;
            cpu_address   = {12'h0, port};
            cpu_data_bus  = val;
            // Present the write status and hold it for four CE posedges
            // (the 8288 needs the whole machine cycle), then go passive --
            // but KEEP address+data up until the IOWC has retired: the V30
            // holds the address through T4, and the 71071 latches the
            // register select on the IOW rise.
            @(posedge clk);
            processor_status = 3'b010;
            waited = 0;
            while (waited < 8) begin
                @(posedge clk);
                if (cpu_ce_posedge) waited = waited + 1;
            end
            processor_status = 3'b111;
            if (tail_shape != 0) begin
                // bridge shape: the next access's operands load inside
                // the strobe tail, tail_lead clks after the pair goes
                // passive and before the command retires
                for (waited = 0; waited < tail_lead; waited = waited + 1)
                    @(posedge clk);
                cpu_address = next_addr;
                cpu_data_bus = next_data;
                waited = 0;
                while (waited < 3) begin
                    @(posedge clk);
                    if (cpu_ce_posedge) waited = waited + 1;
                end
            end else begin
                waited = 0;
                while (waited < 4) begin
                    @(posedge clk);
                    if (cpu_ce_posedge) waited = waited + 1;
                end
            end
            cpu_address      = 20'h0;
            cpu_data_bus     = 8'h00;
            cpu_busy         = 1'b0;
        end
    endtask

    task cpu_in(input [7:0] port, output [7:0] val);
        int waited;
        begin
            while (cpu_busy) @(posedge clk);
            cpu_busy = 1'b1;
            cpu_address   = {12'h0, port};
            @(posedge clk);
            processor_status = 3'b001;
            waited = 0;
            while (waited < 8) begin
                @(posedge clk);
                if (cpu_ce_posedge) waited = waited + 1;
            end
            processor_status = 3'b111;
            val = internal_data_bus;
            waited = 0;
            while (waited < 4) begin
                @(posedge clk);
                if (cpu_ce_posedge) waited = waited + 1;
            end
            cpu_address      = 20'h0;
            cpu_busy         = 1'b0;
        end
    endtask

    // The BIOS's arm sequence for a 2HD FDC read (bios.rom 0xF7A70 cluster):
    // byte-pointer clear, mode, ch2 address lo/hi, page, count lo/hi (n-1),
    // unmask ch2. The disarm (0xF7C36) masks ch2 again.
    task arm_dma(input [15:0] fill_addr, input [15:0] count_m1);
        begin
            cpu_out(8'h11, 8'h40);          // ITF's command: DREQ active-low
            cpu_out(8'h19, 8'h00);          // byte pointer clear
            cpu_out(8'h17, mode_byte[7:0]); // mode
            cpu_out(8'h09, fill_addr[7:0]);
            cpu_out(8'h09, fill_addr[15:8]);
            cpu_out(8'h23, FILL_BASE[19:16]);
            cpu_out(8'h0B, count_m1[7:0]);
            cpu_out(8'h0B, count_m1[15:8]);
            cpu_out(8'h94, 8'h1E);          // 0x94: DMAE + the motor bits
            cpu_out(8'h15, 8'h02);          // unmask ch2
        end
    endtask

    task disarm_dma;
        begin
            cpu_out(8'h15, 8'h06);          // mask ch2
        end
    endtask

    // FDC "command": refill the FIFO, clear dma_has_terminated -- the wire
    // goes back up the next cpu_ce_negedge the way Peripherals samples it.
    task fdc_command;
        begin
            dma_has_terminated = 1'b0;
            fifo_base = fifo_base + 1;
            fifo_cnt  = SEC;
        end
    endtask

    // ---- the SI-stall witness ----------------------------------------------
    // DRQ pending (fdd_dma_req up, FIFO non-empty), no DACK edge for 40us
    // (a byte takes ~1-2us at the slowest pairing) -> the machine is dead.
    int  stall_clks = 0;
    logic wedged = 1'b0;
    wire state_si = (dbg_w_w[2:0] == 3'd0);   // upd71071 dbg: {state,dma_select,hrq,tc,eop}
    always_ff @(posedge clk) begin
        if (reset) begin
            stall_clks <= 0;
            wedged     <= 1'b0;
        end else if (fifo_cnt != 0 && !dma_has_terminated && fdd_dma_req) begin
            if (dma_acknowledge_n[2] && dma_acknowledge_n[3])
                stall_clks <= stall_clks + 1;
            else
                stall_clks <= 0;
            if (stall_clks > 42.95 * 40.0)   // ~40 us with no DACK
                wedged <= 1'b1;
        end else begin
            stall_clks <= 0;
        end
    end

    // ---- the run ------------------------------------------------------------
    logic [7:0] rb;
    int  i, mism;
    initial begin
        for (i = 0; i < 65536; i = i + 1) sink[i] = 8'h00;
        // program the count: default full sector, +TCAT overrides
        if (tc_at == 0) tc_at = SEC;

        reset = 1'b1;
        repeat (10) @(posedge clk);
        reset = 1'b0;
        repeat (50) @(posedge clk);

        // ITF-style init: master clear (all masks set), command 0x40.
        cpu_out(8'h1B, 8'h00);
        cpu_out(8'h11, 8'h40);
        // 0x94 with DMAE set (the BIOS arms the drive before any command)
        cpu_out(8'h94, 8'h1E);

        // The BIOS's fill wait, running in parallel with the DMA the way
        // the real driver does: a tight MSR poll (in al,0x90 / and c0 /
        // cmp c0 / loopne) plus a timer-interrupt-shaped INTA pair every
        // ~55 us -- the OPNA BGM timer storm the game runs while the
        // sector streams. poll_run runs from the command to the drain.
        poll_run = 1'b1;
        fork
            begin : msr_poll
                logic [7:0] junk;
                int w;
                while (1) begin
                    if (!poll_run) begin
                        // idle passive when no command is in flight
                        @(posedge clk);
                    end else begin
                        cpu_in(8'h90, junk);
                        // the loopne retry is back-to-back; a pinch of
                        // passive idle keeps the cadence realistic
                        w = 0;
                        while (w < 4) begin @(posedge clk); w++; end
                    end
                end
            end
            begin : irq_storm
                int t;
                while (1) begin
                    t = 0;
                    while (t < 2362) begin @(posedge clk); t++; end
                    if (poll_run) begin
                        // INTA: two status-000 cycles, vector read off the
                        // bus, then passive again -- the 8259's dance.
                        processor_status = 3'b000;
                        t = 0;
                        while (t < 8) begin @(posedge clk); t++; end
                        processor_status = 3'b111;
                        t = 0;
                        while (t < 4) begin @(posedge clk); t++; end
                    end
                end
            end
        join_none

        for (i = 0; i < iters; i = i + 1) begin
            poll_run = 1'b0;               // the arm runs uninterrupted
            arm_dma(FILL_BASE[15:0] + 16'(i * SEC), 16'(tc_at - 1));
            fdc_command;
            poll_run = 1'b1;               // then the BIOS waits, polling
            // one look at the machine right after the arm
            repeat (2000) @(posedge clk);
            $display("[%0t] ARMED fifo=%0d fdd_req=%b state=%0d mask=%b lock=%b ff=%b en=%b dack2=%b bytes=%0d",
                     $time, fifo_cnt, fdd_dma_req, dbg_w_w[2:0],
                     u_arb.u_upd71071.u_Priority_Encoder.mask_register,
                     u_arb.u_upd71071.u_Priority_Encoder.dma_request_lock,
                     u_arb.u_upd71071.u_Priority_Encoder.dma_request_ff,
                     fdc_dma_enable, dma_acknowledge_n[2], bytes_seen);
            // wait for the fill: fifo drains or the wedge fires
            begin : wait_fill
                int guard = 0;
                while (fifo_cnt != 0 && !dma_has_terminated
                       && !wedged && guard < 3_000_000) begin
                    @(posedge clk);
                    guard++;
                end
            end

            if (wedged) begin
                $display("== SI STALL at sector %0d after %0d bytes (fifo %0d) ==",
                         i, bytes_seen, fifo_cnt);
                $display("  dmac dbg_w        = %016b", dbg_w_w);
                $display("  state=%0d dma_select=%0d hrq=%0d tc=%0d eop=%0d",
                         dbg_w_w[2:0], dbg_w_w[4:3], dbg_w_w[5],
                         dbg_w_w[6], dbg_w_w[7]);
                $display("  arbiter: dce_pin=%b hrq_ff1=%b hrq_ff2=%b",
                         dbg_w_w[15], dbg_w_w[14], dbg_w_w[13]);
                $display("  priority encoder internals:");
                $display("    mask_register     = %04b", u_arb.u_upd71071.u_Priority_Encoder.mask_register);
                $display("    dma_request_lock  = %04b", u_arb.u_upd71071.u_Priority_Encoder.dma_request_lock);
                $display("    dma_request_ff    = %04b", u_arb.u_upd71071.u_Priority_Encoder.dma_request_ff);
                $display("    request_register  = %04b", u_arb.u_upd71071.u_Priority_Encoder.request_register);
                $display("    controller_disable= %b",   u_arb.u_upd71071.u_Priority_Encoder.controller_disable);
                $display("    dreq_sense_low    = %b",   u_arb.u_upd71071.u_Priority_Encoder.dreq_sense_active_low);
                $display("  timing engine:");
                $display("    dma_ack_internal  = %04b", u_arb.u_upd71071.u_Timing_And_Control.dma_acknowledge_internal);
                $display("    fdd_dma_req=%b fdd_dma_ack=%b tc_pulse=%b fifo=%0d",
                         fdd_dma_req, fdd_dma_ack, fdd_dma_tc_pulse, fifo_cnt);
                $display("    prev_wen=%b write_flag=%b write_addr=%b wdata=%02x",
                         u_arb.u_upd71071.u_Bus_Control_Logic.prev_write_enable_n,
                         u_arb.u_upd71071.u_Bus_Control_Logic.write_flag,
                         u_arb.u_upd71071.u_Bus_Control_Logic.write_address,
                         u_arb.u_upd71071.u_Bus_Control_Logic.internal_data_bus);
                $display("RESULT: FAIL tb_fdc_si_stall (SI stall, DRQ pending)");
                $fatal;
            end

            disarm_dma;
            // the BIOS-style settle before the next command
            repeat (200) @(posedge clk);
        end
        poll_run = 1'b0;

        // scoreboard: every byte at the right place?
        mism = 0;
        for (i = 0; i < iters * tc_at; i = i + 1) begin
            if (sink[FILL_BASE + i] !== (8'hA5 ^ 8'(i))) begin
                if (mism < 8)
                    $display("  mismatch @%05x: got %02x want %02x",
                             FILL_BASE + i, sink[FILL_BASE + i], 8'hA5 ^ 8'(i));
                mism = mism + 1;
            end
        end
        $display("iters=%0d mode=%02x speed=%0d bytes=%0d dacks=%0d mism=%0d",
                 iters, mode_byte, speed_sel, bytes_seen, dack_edges, mism);
        if (mism != 0) begin
            $display("RESULT: FAIL tb_fdc_si_stall (data mismatch)");
            $fatal;
        end
        $display("RESULT: PASS tb_fdc_si_stall");
        $finish;
    end

    // ---- debug: watch the CPU write strobes reach the DMAC -----------------
    logic prev_io_wr_dbg = 1'b1;
    int dbg_en = 0;
    initial begin int v; if ($value$plusargs("DBG=%d", v)) dbg_en = v; end
    always_ff @(posedge clk) begin
        prev_io_wr_dbg <= io_write_n;
        if (dbg_en && prev_io_wr_dbg && !io_write_n)
            $display("[%0t] IOW addr=%04x cs_n=%b data=%02x int_bus=%02x status=%03b",
                     $time, address[15:0], dma_chip_select_n, cpu_data_bus,
                     internal_data_bus, processor_status);
        if (dbg_en && address[7:0] == 8'h15)
            $display("[%0t] w15: iow=%b cs=%b prev=%b wflag=%b saddr=%b ibus=%02b",
                     $time, io_write_n, dma_chip_select_n,
                     u_arb.u_upd71071.u_Bus_Control_Logic.prev_write_enable_n,
                     u_arb.u_upd71071.u_Bus_Control_Logic.write_flag,
                     u_arb.u_upd71071.u_Bus_Control_Logic.write_address,
                     u_arb.u_upd71071.u_Bus_Control_Logic.internal_data_bus);
    end

    // periodic monitor (+MON=1): one line per 100us of sim time
    int mon = 0;
    initial begin
        int v; if ($value$plusargs("MON=%d", v)) mon = v;
    end
    initial forever begin
        #2320;   // ~100us at 42.95MHz
        if (mon)
            $display("[%0t] MON fifo=%0d fdd_req=%b has_term=%b state=%0d mask=%b lock=%b ff=%b ackint=%b en=%b dram_req=%b dack=%b/%b",
                     $time, fifo_cnt, fdd_dma_req, dma_has_terminated,
                     dbg_w_w[2:0],
                     u_arb.u_upd71071.u_Priority_Encoder.mask_register,
                     u_arb.u_upd71071.u_Priority_Encoder.dma_request_lock,
                     u_arb.u_upd71071.u_Priority_Encoder.dma_request_ff,
                     u_arb.u_upd71071.u_Timing_And_Control.dma_acknowledge_internal,
                     fdc_dma_enable, dma_request_in[2],
                     dma_acknowledge_n[2], dma_acknowledge_n[3]);
    end

    // global watchdog: 20 ms per sector (a byte takes ~2.5 us at the slowest
    // pairing; a sector is ~2.6 ms, plus the arm sequence's margin)
    initial begin
        #((20000000.0 * iters) * 1ns);
        $display("RESULT: FAIL tb_fdc_si_stall (global timeout)");
        $fatal;
    end

endmodule

`default_nettype wire
