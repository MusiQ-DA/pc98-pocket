//
// tb_v30_dmac -- does a REAL V30 'out' land on the REAL uPD71071?
//
// tb_pc98_dma_decode drives the arbiter's external-strobe port with a hand
// clocked model; on metal the BIOS's writes arrive through the i8288's
// advanced write command and a cpu_address that is already moving to the
// prefetch behind the OUT. This bench runs a real nuV30 core through the
// real bridge + i8288 + READY, and puts the real upd71071 on the bus with
// exactly the chip select PERIPHERALS computes and the strobe path
// BUS_ARBITER builds for it (ab_io_write_n = AIOWC, muxed with the DMAC's
// own output).
//
// The program is the BIOS's channel-2 setup verbatim: byte-pointer clear,
// mode 46h (single, I/O->mem, ch2), base 0200h, count 3, then the unmask
// at 15h. Afterwards the bench raises DRQ2 and watches hold_request, DACK2
// and the memory-write pulses the transfer should produce.
//
// What it answers:
//   * if mask_register[2] never clears, the out at 15h does not land on the
//     real bus timing and the hardware failure is explained;
//   * if it clears but hold_request stays low, the request path inside the
//     encoder is broken under real CE pacing;
//   * if the transfer runs, the 71071 is healthy on the real bus and the
//     hunt moves to the BIOS flow / arbiter hold handshake.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_v30_dmac;

    // clk_chipset is 42.954545 MHz.
    logic clk = 1'b0;
    always #11.641 clk = ~clk;

    logic reset = 1'b1;

    // ---- the CE train, as core_top makes it -------------------------------
    wire  clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire  cycle_accrate, shift_read_timing;
    wire  [7:0] ccc_div, ccc_dec;
    wire  [1:0] ram_rd_wait, ram_wr_wait;
    logic biu_done;

    ce_generator u_ce (
        .clock                              (clk),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (2'b10),      // 9.54 MHz
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

    // ---- the CPU: nuV30 ----------------------------------------------------
    wire  [2:0]  v30_bs;
    wire  [19:0] v30_addr;
    wire  [15:0] v30_data_o, v30_data_i;
    wire         v30_ube_n, v30_ce, v30_ready;

    v30_core u_cpu (
        .CLK        (clk),
        .CE         (v30_ce),
        .RESET      (reset),
        .READY      (v30_ready),
        .INT        (1'b0),
        .NMI        (1'b0),
        .POLL_N     (1'b1),
        .DATA_I     (v30_data_i),
        .ADDR_O     (v30_addr),
        .DATA_O     (v30_data_o),
        .STATUS_O   (),
        .QS         (),
        .BS         (v30_bs),
        .RD_N       (),
        .UBE_N      (v30_ube_n),
        .BUSLOCK_N  (),
        .SS_ADDR    ('0),
        .SS_WDATA   ('0),
        .SS_WE      (1'b0),
        .SS_RDATA   (),
        .SS_ERR     (),
        .SS_BUS_QUIET ()
    );

    // ---- the bridge ---------------------------------------------------------
    wire [2:0] processor_status;
    wire [19:0] ad_out;
    wire [7:0]  cpu_data_bus;
    wire        lock_n;

    v30_cpu_bridge u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .reset             (reset),
        .v30_bs            (v30_bs),
        .v30_addr          (v30_addr),
        .v30_ube_n         (v30_ube_n),
        .v30_data_o        (v30_data_o),
        .v30_data_i        (v30_data_i),
        .v30_ready         (v30_ready),
        .v30_ce            (v30_ce),
        .processor_status  (processor_status),
        .ad_out            (ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (lock_n),
        .analog_mode       (1'b0),
        .word_access       (),
        .cpu_data_bus_hi   (),
        .data_bus_hi       (8'hFF),
        .data_bus          (din),
        .processor_ready   (processor_ready),
        .address_enable_n  (aen_n),
        .pause_core        (1'b0),
        .biu_done          (biu_done)
    );

    // ---- the bus controller, as the chipset wires it -----------------------
    wire mem_rd_n, mem_wr_n, adv_mem_wr_n;
    wire io_rd_n,  io_wr_n,  adv_io_wr_n;
    wire inta_n, ale, en_io, en_mem, dt_r_n, den, mce, pden;

    i8288 u_8288 (
        .clock                           (clk),
        .cpu_ce_posedge                  (cpu_ce_posedge),
        .cpu_ce_negedge                  (cpu_ce_negedge),
        .reset                           (reset),
        .address_enable_n                (aen_n),
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

    // core_top's address latch
    logic [19:0] cpu_address = 20'h0;
    always_ff @(posedge clk)
        if (ale) cpu_address <= ad_out;

    // ---- the READY module ---------------------------------------------------
    wire processor_ready;
    READY u_ready (
        .clock               (clk),
        .cpu_ce_posedge      (cpu_ce_posedge),
        .cpu_ce_negedge      (cpu_ce_negedge),
        .reset               (reset),
        .processor_ready     (processor_ready),
        .dma_ready           (),
        .dma_wait_n          (dma_wait_n),
        .io_channel_ready    (1'b1),
        .io_read_n           (io_rd_n),
        .io_write_n          (io_wr_n),
        .memory_read_n       (mem_rd_n),
        .dma0_acknowledge_n  (1'b1),
        .address_enable_n    (aen_n)
    );

    // ---- the real uPD71071, wired as BUS_ARBITER wires it --------------------
    //
    // Chip select: PERIPHERALS' expression verbatim -- iorq is the strobe
    // qualified decode, and the DMAC window is the odd 0x01-0x1F ports.
    // The strobe the chip sees is ab_io_write_n: the 8288's advanced write
    // command merged with the DMAC's own io write output (idle here).
    wire        dmac_ior_out_n, dmac_iow_out_n;
    wire        ab_io_write_n = ~((~adv_io_wr_n & en_io) | ~dmac_iow_out_n);
    wire        ab_io_read_n  = ~((~io_rd_n      & en_io) | ~dmac_ior_out_n);
    wire        iorq          = ~ab_io_read_n | ~ab_io_write_n;
    // aen_n mirrors BUS_ARBITER's address_enable_n: it follows HLDA, so it
    // reads 1 while the DMAC owns the bus. The CS window is gated on ~aen_n
    // (CPU owns), exactly like pc98_io in PERIPHERALS.
    wire        aen_n         = hlda;
    wire        pc98_io       = iorq & ~aen_n & ~cpu_address[9] & ~cpu_address[8];
    wire        dmac_cs_n     = ~(pc98_io &  cpu_address[0]
                                       & ~cpu_address[7] & ~cpu_address[6]
                                       & ~cpu_address[5]);

    // What the 71071 sees on the metal is PERIPHERALS' fdd_dma_req, not the
    // floppy's raw line: the glue drops it for the whole width of every ack,
    // so each byte is a fresh request edge. That edge is what re-arms the
    // single-mode request lock (~dma_request_ff & ~dma_acknowledge_internal)
    // -- hold DRQ high instead and one byte is all a channel ever serves,
    // which is what the first version of this bench measured.
    logic [3:0] dreq = 4'b0000;
    logic       want_drq = 1'b0;
    always_ff @(posedge clk) begin
        if (reset)
            dreq <= 4'b0000;
        else if (!dack_n[2])
            dreq[2] <= 1'b0;
        else if (want_drq)
            dreq[2] <= 1'b1;
    end
    wire        hrq;
    wire  [3:0] dack_n;
    wire  [7:0] dmac_dout;
    wire [15:0] dmac_addr_out;
    wire        dmac_memrd_n, dmac_memwr_n;

    // The arbiter's hold handshake, flattened: grant the moment the 71071
    // asks, on the cpu_ce edge like the real synchroniser.
    logic       hlda = 1'b0;
    wire        dma_wait_n = 1'b1;
    always_ff @(posedge clk) begin
        if (reset)
            hlda <= 1'b0;
        else if (cpu_ce_posedge)
            hlda <= hrq;
    end

    upd71071 u_dmac (
        .clock                              (clk),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .chip_select_n                      (dmac_cs_n),
        .ready                              (1'b1),
        .hold_acknowledge                   (hlda),
        .dma_request                        (dreq),
        .data_bus_in                        (cpu_data_bus),
        .data_bus_out                       (dmac_dout),
        .io_read_n_in                       (ab_io_read_n),
        .io_read_n_out                      (dmac_ior_out_n),
        .io_read_n_io                       (),
        .io_write_n_in                      (ab_io_write_n),
        .io_write_n_out                     (dmac_iow_out_n),
        .io_write_n_io                      (),
        .end_of_process_n_in                (1'b1),
        .end_of_process_n_out               (),
        .address_in                         (cpu_address[4:1]),
        .address_out                        (dmac_addr_out),
        .output_highst_address              (),
        .hold_request                       (hrq),
        .dma_acknowledge                    (dack_n),
        .address_enable                     (),
        .address_strobe                     (),
        .memory_read_n                      (dmac_memrd_n),
        .memory_write_n                     (dmac_memwr_n),
        .dbg                                (dbg_dmac)
    );

    wire [31:0] dbg_dmac;

    // ---- memory + bus --------------------------------------------------------
    logic [7:0] mem [0:1048575];

    wire [7:0] din = ~mem_rd_n ? mem[cpu_address]
                    : (~dmac_cs_n & ~ab_io_read_n) ? dmac_dout
                                : 8'hFF;

    logic mem_wr_d = 1'b1;
    logic io_wr_d  = 1'b1;
    always_ff @(posedge clk) begin
        mem_wr_d <= mem_wr_n;
        io_wr_d  <= io_wr_n;
        if (mem_wr_n & ~mem_wr_d) mem[cpu_address] <= cpu_data_bus;
    end

    // The DMA transfer's memory side: while the DMAC owns the bus it reads the
    // peripheral (io_read_n_out) and writes memory (memory_write_n). The
    // peripheral's byte is emulated as a fixed pattern on data_bus_in's wire
    // -- the 71071 does not carry the byte itself, the bus does; for the
    // counting below the address + strobe edges are what matter.
    int memw_pulses = 0;
    logic dmac_memwr_d = 1'b0;
    logic [19:0] dmac_last_addr;
    always_ff @(posedge clk) begin
        dmac_memwr_d <= dmac_memwr_n;
        if (~dmac_memwr_n & dmac_memwr_d) begin
            memw_pulses  <= memw_pulses + 1;
            dmac_last_addr <= {4'h0, dmac_addr_out};
        end
    end

    int errors = 0;
    task automatic check(input bit cond, input string name);
        if (!cond) begin
            errors++;
            $display("FAIL: %s", name);
        end
    endtask

    // ---- the program ---------------------------------------------------------
    //
    // The BIOS's ch2 setup (FFA70/FFDEF): clear byte pointer, mode 46h,
    // base 0200h, count 3, unmask ch2 -- then a marker and HLT.
    //
    //   B0 00 E6 19    mov al,00 / out 19h,al   clear byte pointer
    //   B0 46 E6 17    mov al,46 / out 17h,al   mode: single, write, ch2
    //   B0 00 E6 09    mov al,00 / out 09h,al   ch2 base low
    //   B0 02 E6 09    mov al,02 / out 09h,al   ch2 base high -> 0200h
    //   B0 03 E6 0B    mov al,03 / out 0Bh,al   ch2 count low
    //   B0 00 E6 0B    mov al,00 / out 0Bh,al   ch2 count high -> 3 (4 bytes)
    //   B0 02 E6 15    mov al,02 / out 15h,al   unmask ch2
    //   C6 06 40 02 AA mov byte [0240],AA       marker
    //   F4             hlt
    //
    task automatic poke(input int a, input logic [7:0] d);
        mem[a] = d;
    endtask

    initial begin : program_image
        int i;
        for (i = 0; i < 1048576; i = i + 1) mem[i] = 8'h00;

        poke(20'hFFFF0, 8'hEA); poke(20'hFFFF1, 8'h00); poke(20'hFFFF2, 8'h00);
        poke(20'hFFFF3, 8'h00); poke(20'hFFFF4, 8'h00);

        i = 0;
        // clear byte pointer
        poke(i, 8'hB0); i++; poke(i, 8'h00); i++;
        poke(i, 8'hE6); i++; poke(i, 8'h19); i++;
        // mode: single transfer, write (I/O->mem), channel 2
        poke(i, 8'hB0); i++; poke(i, 8'h46); i++;
        poke(i, 8'hE6); i++; poke(i, 8'h17); i++;
        // base address 0x0200
        poke(i, 8'hB0); i++; poke(i, 8'h00); i++;
        poke(i, 8'hE6); i++; poke(i, 8'h09); i++;
        poke(i, 8'hB0); i++; poke(i, 8'h02); i++;
        poke(i, 8'hE6); i++; poke(i, 8'h09); i++;
        // count = 3 (four bytes)
        poke(i, 8'hB0); i++; poke(i, 8'h03); i++;
        poke(i, 8'hE6); i++; poke(i, 8'h0B); i++;
        poke(i, 8'hB0); i++; poke(i, 8'h00); i++;
        poke(i, 8'hE6); i++; poke(i, 8'h0B); i++;
        // unmask channel 2
        poke(i, 8'hB0); i++; poke(i, 8'h02); i++;
        poke(i, 8'hE6); i++; poke(i, 8'h15); i++;
        // done marker, then park
        poke(i, 8'hC6); i++; poke(i, 8'h06); i++;
        poke(i, 8'h40); i++; poke(i, 8'h02); i++; poke(i, 8'hAA); i++;
        poke(i, 8'hF4); i++;
        poke(i, 8'hEB); i++; poke(i, 8'hFE); i++;
    end

    // ---- run -----------------------------------------------------------------
    initial begin
        int guard = 0;
        repeat (40) @(posedge clk);
        reset = 1'b0;

        // Wait for the program to finish its writes.
        guard = 0;
        while (mem[20'h00240] != 8'hAA && guard < 400000) begin
            @(posedge clk); guard++;
        end
        check(guard < 400000, "program ran to the marker");

        // Did the writes land?  mask_register should be 1011 (ch2 clear) and
        // the mode register should hold 46h on channel 2.
        $display("  after setup: mask=%b req_state=%b encoded=%b",
                 u_dmac.u_Priority_Encoder.mask_register,
                 u_dmac.u_Priority_Encoder.dma_request_state,
                 u_dmac.u_Priority_Encoder.encoded_dma);
        check(u_dmac.u_Priority_Encoder.mask_register == 4'b1011,
              "out 15h,02 cleared mask_register[2]");
        check(u_dmac.u_Timing_And_Control.transfer_mode[2] == 2'b01,
              "out 17h,46 set ch2 mode = single");

        // The POSTMON word reports the same state the probes do: mask at
        // [31:28], the single-mask write's sticky at bit 7, and a nonzero
        // write count at [11:8].
        check(dbg_dmac[31:28] == 4'b1011, "dbg carries mask_register");
        check(dbg_dmac[7], "dbg sticky: single-mask reg written");
        check(dbg_dmac[11:8] != 4'h0, "dbg counts the writes");

        // Readback over the bus: current address LSB of ch2 should be 00h.
        // (the program ended, so do it hierarchically -- the bus read path is
        // exercised by the data phase anyway)

        // Raise DRQ2 and watch the machine run: HRQ, DACK2 low, four memory
        // writes, then idle again.
        want_drq = 1'b1;
        guard = 0;
        while (~hrq && guard < 20000) begin
            @(posedge clk); guard++;
        end
        check(hrq, "hold_request asserted after DRQ2 with ch2 unmasked");

        guard = 0;
        while (dack_n[2] && guard < 20000) begin
            @(posedge clk); guard++;
        end
        check(!dack_n[2], "DACK2 asserted");

        // Four bytes at 0x0200..0x0203; the fourth runs with the word count
        // at zero, which is where the 8237 raises terminal count.
        guard = 0;
        while (memw_pulses < 4 && guard < 100000) begin
            @(posedge clk); guard++;
        end
        check(memw_pulses == 4, "four memory-write pulses for count=3");
        check(dmac_last_addr == 20'h00203, "last byte written at 0x0203");
        $display("  memw_pulses=%0d last_addr=%05x", memw_pulses, dmac_last_addr);

        // Drop DRQ; the engine should fall back to idle.
        want_drq = 1'b0;
        repeat (2000) @(posedge clk);
        check(hrq == 1'b0, "hold_request released after drain");
        check(tc_hits != 0, "terminal count asserted on the fourth byte");

        // The 8237's own rule (PC-9800 hardware data book): EOP re-sets the
        // channel's mask bit when it was not programmed for
        // autoinitialization -- mode 46h has bit 4 clear, so ch2 must be
        // masked again now. This is why the BIOS re-issues the 15h unmask
        // before every command.
        check(u_dmac.u_Priority_Encoder.mask_register[2],
              "ch2 re-masked on EOP (no autoinit)");

        if (errors == 0)
            $display("PASS tb_v30_dmac");
        else
            $display("FAIL tb_v30_dmac (%0d errors)", errors);
        $finish;
    end

    // Terminal count must assert during the fourth byte's S4 -- the word
    // count reaches zero on the third decrement, so the byte that runs with
    // count==0 is the one that raises TC.
    int tc_hits = 0;
    always @(posedge clk)
        if (u_dmac.u_Timing_And_Control.terminal_count)
            tc_hits <= tc_hits + 1;

    // Watchdog
    initial begin
        #200_000_000;
        $display("FAIL tb_v30_dmac (timeout: mask=%b hrq=%b dack=%b memw=%0d)",
                 u_dmac.u_Priority_Encoder.mask_register, hrq, dack_n,
                 memw_pulses);
        $finish;
    end

endmodule
