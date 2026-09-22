//
// tb_v30_mem -- the V30 against the REAL memory path.
//
// WHY THIS EXISTS. Two benches cover the CPU and neither covers this:
//
//   * tb_pc98_boot runs the real ITF on the real core and reaches N88-BASIC,
//     but its own header says what it is standing on -- "one flat megabyte of
//     memory with the two ROM images in it. No chipset, no peripherals, no
//     SDRAM". Zero wait states, byte-wide, answers instantly.
//   * tb_v30_bridge proves the bridge against the real i8288, the real READY
//     and a real 8259, but its memory is again a flat array.
//
// So the path the hardware actually runs -- v30_cpu_bridge -> i8288 ->
// READY -> RAM.sv -> sdram_shim -> sdram_mp -> the part, with the board's
// half-period clock skew -- has never been simulated with a V30 on the front
// of it. The machine's symptom lives exactly there: the ITF reaches its memory
// test, reports 000KB, and restarts, while every bench is green.
//
// WHAT IT ASSERTS. A short program in ROM (which is SDRAM here, as it is on
// the machine: RAM.sv selects E8000-FFFFF) exercises the shapes the bridge
// has to get right against a controller that makes it wait:
//
//   T1  word store then an immediate word load of the same address -- the
//       write queue's program order, which is the one the ITF's memory test
//       depends on and the one a flat memory cannot fail.
//   T2  byte stores at an even and an odd address, then a word load across
//       them -- lane steering both ways.
//   T3  word store, then byte loads of each half.
//   T4  a 256-word fill-and-verify sweep: the memory test in miniature.
//
// The program reports through port 0xE0 and parks; the bench then reads the
// part's own storage and checks it independently of the CPU's opinion.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_v30_mem;

    // clk_chipset is 42.954545 MHz -- DERIVED, not a rounded literal.
    //
    // tb_v30_bridge writes `always #11.641`, which is fine there because it
    // has no SDRAM model. Here the part's clock comes from sdram_board_model's
    // CLK_MHZ (half period 11.64021 ns), and 11.641 against that drifts 0.0016
    // ns per cycle -- a whole period by cycle 14800. The device clock is meant
    // to sit half a period behind this one; let it drift and it eventually sits
    // a period and a half behind, the read data comes back one cycle later than
    // the controller's tag expects, and the bench manufactures a data-capture
    // bug that is not in the RTL. It did: the first version of this bench
    // "reproduced" the hardware's memory-test failure at cycle 13982, which is
    // exactly where the accumulated drift crosses a period.
    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;
    logic clk = 1'b0;
    always #(HALF_NS) clk = ~clk;

    logic reset = 1'b1;

    // +speed=N picks the CE generator's index. The handshake between the byte
    // engine and RAM.sv is a phase relationship, so one speed is one sample of
    // it; a race that hides at 9.54 MHz can be exposed at 4.77 or at the
    // chipset clock itself.
    int spd = 2;
    initial if (!$value$plusargs("speed=%d", spd)) spd = 2;
    wire [1:0] clk_sel = 2'(spd);

    // ---- the CE train, as core_top makes it -------------------------------
    wire  clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire  cycle_accrate, shift_read_timing;
    wire  [7:0] ccc_div, ccc_dec;
    wire  [1:0] ram_rd_wait, ram_wr_wait;
    // The bridge drives this; do NOT also assign it procedurally. Leaving a
    // stray `biu_done = 0` in an initial block fought the module's driver, the
    // CE generator's speed_change went X, and no CE edge was ever produced --
    // the CPU sat still and the bench reported "program never reported".
    wire  biu_done;

    ce_generator u_ce (
        .clock                              (clk),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (clk_sel), // core_top's default index
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

    // ---- the CPU ----------------------------------------------------------
    wire  [2:0]  v30_bs;
    wire  [19:0] v30_addr;
    wire  [15:0] v30_data_o, v30_data_i;
    wire         v30_ube_n, v30_ce, v30_ready;

    // The CPU is held in reset until the controller has finished its init
    // sequence, the way core_top holds it behind initilized_sdram: a fetch
    // issued during INIT_NOP is not a case this bench is about.
    logic cpu_reset = 1'b1;

    v30_core u_cpu (
        .CLK        (clk),
        .CE         (v30_ce),
        .RESET      (cpu_reset),
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

    // ---- the bridge -------------------------------------------------------
    wire [2:0]  processor_status;
    wire [19:0] ad_out;
    wire [7:0]  cpu_data_bus;
    wire [7:0]  cpu_data_bus_hi;
    wire        cpu_word_access;
    wire        lock_n;

    v30_cpu_bridge u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .reset             (cpu_reset),
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
        .word_access       (cpu_word_access),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (din_hi),
        .data_bus          (din),
        .processor_ready   (processor_ready),
        .address_enable_n  (1'b0),
        .pause_core        (1'b0),
        .biu_done          (biu_done)
    );

    // ---- the bus controller ----------------------------------------------
    wire mem_rd_n, mem_wr_n, adv_mem_wr_n;
    wire io_rd_n,  io_wr_n,  adv_io_wr_n;
    wire inta_n, ale, en_io, en_mem, dt_r_n, den, mce, pden;

    i8288 u_8288 (
        .clock                           (clk),
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

    // core_top's address latch
    logic [19:0] cpu_address = 20'h0;
    always_ff @(posedge clk)
        if (ale) cpu_address <= ad_out;

    // ---- READY, wired the way Chipset.sv wires it -------------------------
    //
    // Chipset.sv: .io_channel_ready(io_channel_ready & memory_access_ready
    // & tandy_snd_rdy). memory_access_ready is RAM.sv's, and it is the whole
    // point of this bench: the bridge's byte cycles must stretch on it.
    wire processor_ready;
    wire memory_access_ready;

    READY u_ready (
        .clock               (clk),
        .cpu_ce_posedge      (cpu_ce_posedge),
        .cpu_ce_negedge      (cpu_ce_negedge),
        .reset               (reset),
        .processor_ready     (processor_ready),
        .dma_ready           (),
        .dma_wait_n          (1'b1),
        .io_channel_ready    (memory_access_ready),
        .io_read_n           (io_rd_n),
        .io_write_n          (io_wr_n),
        .memory_read_n       (mem_rd_n),
        .dma0_acknowledge_n  (1'b1),
        .address_enable_n    (1'b0)
    );

    // ---- the memory: the real RAM.sv on the real controller ---------------
    wire [7:0]  ram_dout, ram_dout_hi;
    wire        access_complete, ram_address_select_n, initilized_sdram;
    wire [12:0] s_a;  wire [1:0] s_ba;
    wire        s_cke, s_cs, s_ras, s_cas, s_we, s_dq_io, s_ldqm, s_udqm;
    wire [15:0] s_dq_out, s_dq_in;
    logic [6:0] map [0:3] = '{7'd0, 7'd0, 7'd0, 7'd0};

    RAM u_ram (
        .clock(clk), .reset(reset),
        .enable_sdram(1'b1), .initilized_sdram(initilized_sdram),
        .address(cpu_address), .internal_data_bus(cpu_data_bus),
        .data_bus_out(ram_dout),
        .analog_mode(1'b0),
        .word_access(cpu_word_access),
        .internal_data_bus_hi(cpu_data_bus_hi),
        .data_bus_out_hi(ram_dout_hi),
        .memory_read_n(mem_rd_n), .memory_write_n(mem_wr_n),
        .no_command_state(mem_rd_n & mem_wr_n & io_rd_n & io_wr_n),
        .memory_access_ready(memory_access_ready),
        .access_complete(access_complete),
        .ram_address_select_n(ram_address_select_n),
        .sdram_address(s_a), .sdram_cke(s_cke), .sdram_cs(s_cs),
        .sdram_ras(s_ras), .sdram_cas(s_cas), .sdram_we(s_we), .sdram_ba(s_ba),
        .sdram_dq_in(s_dq_in), .sdram_dq_out(s_dq_out), .sdram_dq_io(s_dq_io),
        .sdram_ldqm(s_ldqm), .sdram_udqm(s_udqm),
        .map_ems(map), .ems_b1(1'b0), .ems_b2(1'b0), .ems_b3(1'b0), .ems_b4(1'b0),
        .bios_protect_flag(2'b00), .tandy_bios_flag(1'b0),
        .font_bank_flag(1'b0),
        .font_rd_req(1'b0), .font_rd_addr(24'h0), .font_rd_len(4'h0),
        .font_rd_ack(), .font_rd_valid(), .font_rd_data(), .font_rd_done(),
        .cg_rd_req(1'b0), .cg_rd_addr(24'h0), .cg_rd_len(4'h0),
        .cg_rd_ack(), .cg_rd_valid(), .cg_rd_data(), .cg_rd_done(),
        .wait_count_clk_en(cpu_ce_negedge),
        .ram_read_wait_cycle(ram_rd_wait), .ram_write_wait_cycle(ram_wr_wait)
    );

    // The board's half-period skew and pin flight times, not the controller's
    // own clock: a controller that only works in phase fails here the way it
    // fails on the board.
    sdram_board_model #(.T_RCD(1), .T_RP(2), .T_WR(2), .T_RFC(4),
                        .T_RAS(2), .T_RC(3), .T_REF(335)) sdr (
        .clk(clk), .a(s_a), .ba(s_ba), .cke(s_cke),
        .ras_n(s_ras), .cas_n(s_cas), .we_n(s_we), .dqm({s_udqm, s_ldqm}),
        .dq_out(s_dq_out), .dq_io(s_dq_io), .dq_in(s_dq_in)
    );

    // ---- what the CPU reads ----------------------------------------------
    // Memory answers from RAM.sv; everything else reads FF, as an empty
    // chipset would.
    wire [7:0] din    = (~mem_rd_n & ~ram_address_select_n) ? ram_dout    : 8'hFF;
    // The odd lane of a one-cycle word read. Only ever consulted when the
    // bridge asked for a word, and only the SDRAM serves those.
    wire [7:0] din_hi = (~mem_rd_n & ~ram_address_select_n) ? ram_dout_hi : 8'hFF;

    // ---- tracing ----------------------------------------------------------
    //
    // +trace=N prints the first N completed 8288 command cycles. Direction and
    // data are sampled WHILE the command is live: at its trailing edge the
    // command is already gone.
    int trace_n = 0;
    int traced  = 0;
    initial if (!$value$plusargs("trace=%d", trace_n)) trace_n = 0;

    logic        mem_rd_q = 1'b1, mem_wr_q = 1'b1;
    logic [7:0]  live_wdata;
    logic [7:0]  live_rdata;
    always_ff @(posedge clk) begin
        mem_rd_q <= mem_rd_n;
        mem_wr_q <= mem_wr_n;
        if (~mem_wr_n) live_wdata <= cpu_data_bus;
        if (~mem_rd_n) live_rdata <= din;
        if (traced < trace_n) begin
            if (mem_wr_n & ~mem_wr_q) begin
                $display("%0t  WR %05x = %02x", $time, cpu_address, live_wdata);
                traced++;
            end else if (mem_rd_n & ~mem_rd_q) begin
                $display("%0t  RD %05x = %02x", $time, cpu_address, live_rdata);
                traced++;
            end
        end
    end

    // +probe: a periodic dump of the CE train and the two state machines, for
    // when nothing at all is happening and the question is which stage is
    // asleep.
    int probe_on = 0;
    initial if (!$value$plusargs("probe=%d", probe_on)) probe_on = 0;
    int ce_count = 0;
    always_ff @(posedge clk) if (cpu_ce_posedge) ce_count++;
    initial begin
        if (probe_on != 0) forever begin
            repeat (probe_on) @(posedge clk);
            $display("%0t  ce=%0d bs=%b st=%b ce_gate=%b rdy=%b memrd=%b memwr=%b ale=%b addr=%05x rst=%b init=%b",
                     $time, ce_count, v30_bs, processor_status, v30_ce,
                     processor_ready, mem_rd_n, mem_wr_n, ale, cpu_address,
                     cpu_reset, initilized_sdram);
        end
    end

    // Controller clock cycles, so "the data was one clock late" is a number
    // rather than a subtraction of picosecond stamps.
    int cyc = 0;
    always_ff @(posedge clk) cyc++;

    function automatic string cmd_name();
        if (s_cs) return "-   ";
        case ({s_ras, s_cas, s_we})
            3'b011: return "ACT ";
            3'b101: return "READ";
            3'b100: return "WRIT";
            3'b010: return "PRE ";
            3'b001: return "REF ";
            default: return "nop ";
        endcase
    endfunction

    // +cmdfrom=N +cmdto=M: decode the SDRAM command bus over a time window, in
    // nanoseconds. "Did the controller precharge before it activated the other
    // row?" is not answerable from the CPU's side of the bus.
    int cmd_from = 0, cmd_to = 0;
    initial begin
        if (!$value$plusargs("cmdfrom=%d", cmd_from)) cmd_from = 0;
        if (!$value$plusargs("cmdto=%d",   cmd_to))   cmd_to   = 0;
    end
    always_ff @(posedge clk) begin
        if (cmd_to != 0 && $time >= cmd_from && $time <= cmd_to && !s_cs) begin
            case ({s_ras, s_cas, s_we})
                3'b011: $display("%0t  SDR ACT   ba=%0d row=%0d", $time, s_ba, s_a);
                3'b101: $display("%0t  SDR READ  ba=%0d col=%0d", $time, s_ba, s_a[8:0]);
                3'b100: $display("%0t  SDR WRITE ba=%0d col=%0d", $time, s_ba, s_a[8:0]);
                3'b010: $display("%0t  SDR PRE   ba=%0d all=%b", $time, s_ba, s_a[10]);
                3'b001: $display("%0t  SDR REF", $time);
                default: ;
            endcase
        end
    end

    // Every SDRAM read the CPU completes, checked against the part's own
    // storage. A read that disagrees with what was stored is the bug, and the
    // address it actually came from is the diagnosis.
    int rd_errors = 0;
    logic mem_rd_qq = 1'b1;
    always_ff @(posedge clk) begin
        mem_rd_qq <= mem_rd_n;
        if (mem_rd_n & ~mem_rd_qq & ~ram_address_select_n && rd_errors < 6) begin
            logic [15:0] want_w;
            want_w = sdr.u_part.peek(int'(cpu_address));
            // Unwritten cells read back 0xDEAD from the part and 0x0000 from
            // peek; that disagreement is the bench's, not the core's.
            if (sdr.u_part.store.exists(int'(cpu_address))
                    && live_rdata !== want_w[7:0]) begin
                $display("%0t  BADREAD [%05x] gave %02x, stored %02x",
                         $time, cpu_address, live_rdata, want_w[7:0]);
                rd_errors++;
            end
        end
    end

    // +ramfrom/+ramto: RAM.sv's handshake, per clock, over a window. The
    // question this answers is whether the byte engine's completing sample
    // saw a ready that RAM.sv had not yet withdrawn.
    // Triggered on an address rather than a time: $time is in ps here and a
    // 32-bit window comparison silently wrapped.
    int ram_at = -1, ram_len = 0, ram_run = 0, ram_skip = 0;
    logic ram_armed = 1'b1;
    logic ram_seen  = 1'b0;
    initial begin
        if (!$value$plusargs("ramat=%h", ram_at))     ram_at   = -1;
        if (!$value$plusargs("ramlen=%d", ram_len))   ram_len  = 60;
        // +ramskip=N: ignore the first N visits. An address the program fetches
        // more than once is usually wrong only on a later pass.
        if (!$value$plusargs("ramskip=%d", ram_skip)) ram_skip = 0;
    end
    always_ff @(posedge clk) begin
        ram_seen <= (cpu_address == 20'(ram_at)) & ~mem_rd_n;
        if (ram_armed && ram_at >= 0 && cpu_address == 20'(ram_at) && ~mem_rd_n
                && !ram_seen) begin
            if (ram_skip != 0) ram_skip <= ram_skip - 1;
            else begin
                ram_armed <= 1'b0;
                ram_run   <= ram_len;
            end
        end else if (ram_run != 0)
            ram_run <= ram_run - 1;
    end
    always_ff @(posedge clk) begin
        if (ram_at >= 0 && ram_run != 0)
            $display("cyc=%0d %0t  cmd=%s rvalid=%b rdata=%04x dq_in=%04x dout=%02x",
                     cyc, $time, cmd_name(), u_ram.u_sdram_single.p_rvalid,
                     u_ram.u_sdram_single.p_rdata, s_dq_in, ram_dout);
    end

    // How many cycles actually ran as ONE word. Without this the word path
    // could fall back to byte pairs and the bench would still pass -- slower
    // and silent, which is the failure mode worth naming.
    int  word_cycles = 0;
    logic wa_q = 1'b0;
    always_ff @(posedge clk) begin
        wa_q <= cpu_word_access;
        if (cpu_word_access & ~wa_q) word_cycles++;
    end

    // ---- the result port --------------------------------------------------
    logic [7:0] port_e0 = 8'h00;
    logic       io_wr_d = 1'b1;
    always_ff @(posedge clk) begin
        io_wr_d <= io_wr_n;
        if (io_wr_n & ~io_wr_d && cpu_address[15:0] == 16'h00E0)
            port_e0 <= cpu_data_bus;
    end

    // ---- the program ------------------------------------------------------
    //
    // Poked straight into the part's storage. RAM.sv keeps ONE GUEST BYTE PER
    // 16-BIT WORD -- access_data_in is {8'h00, byte} -- so the word address is
    // the guest's byte address and the high byte is zero. That layout is what
    // makes a word access two consecutive words, which is what PC98_WORD_MEM
    // turns into a burst; this bench is the place it has to hold.
    int pc;
    task automatic emit(input logic [7:0] b);
        sdr.u_part.poke(pc, {8'h00, b});
        pc = pc + 1;
    endtask
    task automatic emit16(input logic [15:0] w);
        emit(w[7:0]); emit(w[15:8]);
    endtask
    task automatic zero(input int a);
        sdr.u_part.poke(a, 16'h0000);
    endtask

    localparam int CODE = 20'hF0100;     // inside RAM.sv's E8000-FFFFF select

    int fill_top, check_top;

    // One 128 KB-block half, the way the ITF writes it: REP STOSW to fill,
    // REPE SCASW to verify. Stores 0000 at `res` if the compare stayed equal
    // (0001 if not) and the final DI at res+2 -- 2000 when all 1000h words
    // matched, the mismatch offset otherwise.
    task automatic memblk(input logic [15:0] seg, input logic [15:0] res);
        emit(8'hB8); emit16(16'hAA55);          // mov ax,AA55  (lanes differ)
        emit(8'hBB); emit16(seg);               // mov bx,seg
        emit(8'h8E); emit(8'hC3);               // mov es,bx
        emit(8'h31); emit(8'hFF);               // xor di,di
        emit(8'hB9); emit16(16'h1000);          // mov cx,1000  (8 KB)
        emit(8'hFC);                            // cld
        emit(8'hF3); emit(8'hAB);               // rep stosw
        emit(8'h8E); emit(8'hC3);               // mov es,bx
        emit(8'h31); emit(8'hFF);               // xor di,di
        emit(8'hB9); emit16(16'h1000);          // mov cx,1000
        emit(8'hF3); emit(8'hAF);               // repe scasw
        emit(8'hB0); emit(8'h00);               // mov al,0
        emit(8'h74); emit(8'h02);               // jz  +2
        emit(8'hB0); emit(8'h01);               // mov al,1
        emit(8'hA2); emit16(res);               // mov [res],al
        emit(8'h89); emit(8'h3E); emit16(res + 16'd2);  // mov [res+2],di
    endtask

    initial begin : program_image
        int i;

        // the guest RAM this test touches, cleared
        for (i = 20'h00200; i < 20'h01400; i = i + 1) zero(i);

        // reset vector at FFFF0: jmp F000:0100
        pc = 20'hFFFF0;
        emit(8'hEA); emit16(16'h0100); emit16(16'hF000);

        pc = CODE;
        emit(8'hB8); emit16(16'h0000);          // mov ax,0000
        emit(8'h8E); emit(8'hD8);               // mov ds,ax
        emit(8'h8E); emit(8'hC0);               // mov es,ax
        emit(8'hFC);                            // cld

        // T1: word store, then load the same address straight back. With a
        // write queue this is the ordering test; with a flat memory it cannot
        // fail, which is why no existing bench catches it.
        emit(8'hC7); emit(8'h06); emit16(16'h0200); emit16(16'h1234);
        emit(8'hA1); emit16(16'h0200);          // mov ax,[0200]
        emit(8'hA3); emit16(16'h0300);          // mov [0300],ax

        // T2: byte store even, byte store odd, word load across them.
        emit(8'hC6); emit(8'h06); emit16(16'h0202); emit(8'hAA);
        emit(8'hC6); emit(8'h06); emit16(16'h0203); emit(8'hBB);
        emit(8'hA1); emit16(16'h0202);          // mov ax,[0202]
        emit(8'hA3); emit16(16'h0302);          // mov [0302],ax   -> BBAA

        // T3: word store, byte loads of each half.
        emit(8'hC7); emit(8'h06); emit16(16'h0204); emit16(16'h5678);
        emit(8'hA0); emit16(16'h0204);          // mov al,[0204]
        emit(8'h8A); emit(8'h26); emit16(16'h0205); // mov ah,[0205]
        emit(8'hA3); emit16(16'h0304);          // mov [0304],ax   -> 5678

        // T4: fill 256 words at 1000 with their own address, then verify.
        emit(8'hB9); emit16(16'h0100);          // mov cx,0100
        emit(8'hBF); emit16(16'h1000);          // mov di,1000
        fill_top = pc;
        emit(8'h8B); emit(8'hC7);               // mov ax,di
        emit(8'h89); emit(8'h05);               // mov [di],ax
        emit(8'h83); emit(8'hC7); emit(8'h02);  // add di,2
        emit(8'hE2); emit(8'(fill_top - (pc + 1)));   // loop fill

        emit(8'hB9); emit16(16'h0100);          // mov cx,0100
        emit(8'hBF); emit16(16'h1000);          // mov di,1000
        emit(8'h31); emit(8'hDB);               // xor bx,bx
        check_top = pc;
        emit(8'h8B); emit(8'h05);               // mov ax,[di]
        emit(8'h39); emit(8'hF8);               // cmp ax,di
        emit(8'h74); emit(8'h01);               // je +1  (skip the inc)
        emit(8'h43);                            // inc bx
        emit(8'h83); emit(8'hC7); emit(8'h02);  // add di,2
        emit(8'hE2); emit(8'(check_top - (pc + 1)));  // loop check
        emit(8'h89); emit(8'h1E); emit16(16'h0306);   // mov [0306],bx -> 0000

        // T5-T7: the ITF's OWN instruction shape, at the ITF's OWN addresses.
        //
        // T4 is a hand-rolled LOOP over 256 words at 01000. The ITF's memory
        // test is neither: F9544 fills with REP STOSW and F9561 verifies with
        // REPE SCASW -- back-to-back word accesses at the maximum rate the bus
        // will take, with no instruction fetch in between to space them out.
        // That shape has never been run against the real memory path, and it
        // is the shape the machine fails on.
        //
        // The addresses matter too. The ITF sweeps in 128 KB blocks: block 1
        // is ES=0000 then ES=1000, block 2 is ES=2000 then ES=3000. The
        // hardware prints MEMORY 128KB OK, which is block 1 passing and the
        // sweep ending -- so block 2 is where to look. Run 8 KB of the real
        // shape in each of three segments and record, per segment, whether
        // REPE SCASW came out equal and where DI stopped.
        memblk(16'h1000, 16'h0310);
        memblk(16'h2000, 16'h0314);
        memblk(16'h3000, 16'h0318);

        // T8: DIV, the instruction the ITF's MEMORY line is printed with.
        //
        // F9678 converts the 64 KB block count to decimal and it is the only
        // place that conversion happens:
        //
        //     F9682  xor al,al      ax = dh<<8
        //     F9684  shr ax,1 / shr ax,1    ax = dh*64, the KB figure
        //     F9688  mov cx,0Ah / xor dx,dx
        //     F968D  div cx
        //     F968F  or dl,30h      the remainder is the digit
        //
        // A DIV that returns zero prints exactly "000KB", which is what the
        // machine shows while [0501] says it counted the full 640 KB -- the
        // count never goes through DIV and the display is nothing but DIV.
        emit(8'hB8); emit16(16'd640);           // mov ax,640
        emit(8'h31); emit(8'hD2);               // xor dx,dx
        emit(8'hB9); emit16(16'd10);            // mov cx,10
        emit(8'hF7); emit(8'hF1);               // div cx      -> ax=64 dx=0
        emit(8'hA3); emit16(16'h0320);          // mov [0320],ax
        emit(8'h89); emit(8'h16); emit16(16'h0322);  // mov [0322],dx

        emit(8'hB8); emit16(16'd64);            // mov ax,64
        emit(8'h31); emit(8'hD2);               // xor dx,dx
        emit(8'hF7); emit(8'hF1);               // div cx      -> ax=6 dx=4
        emit(8'hA3); emit16(16'h0324);          // mov [0324],ax
        emit(8'h89); emit(8'h16); emit16(16'h0326);  // mov [0326],dx

        // A dividend with a nonzero high half, which a 16-bit-only divider
        // gets wrong in a different way: 10000h/3 = 5555h r 1.
        emit(8'hB8); emit16(16'h0000);          // mov ax,0000
        emit(8'hBA); emit16(16'h0001);          // mov dx,0001
        emit(8'hB9); emit16(16'd3);             // mov cx,3
        emit(8'hF7); emit(8'hF1);               // div cx      -> ax=5555 dx=0001
        emit(8'hA3); emit16(16'h0328);          // mov [0328],ax
        emit(8'h89); emit(8'h16); emit16(16'h032A);  // mov [032A],dx

        // The byte form, and MUL, which the same routines lean on (F8B66
        // mul ah, F9668 mul ah).
        emit(8'hB8); emit16(16'h00C8);          // mov ax,00C8 (200)
        emit(8'hB3); emit(8'd7);                // mov bl,7
        emit(8'hF6); emit(8'hF3);               // div bl      -> al=28 ah=4
        emit(8'hA3); emit16(16'h032C);          // mov [032C],ax

        emit(8'hB0); emit(8'd5);                // mov al,5
        emit(8'hB4); emit(8'hA0);               // mov ah,A0
        emit(8'hF6); emit(8'hE4);               // mul ah      -> ax=0320
        emit(8'hA3); emit16(16'h032E);          // mov [032E],ax

        emit(8'hB0); emit(8'hA5);               // mov al,A5
        emit(8'hE6); emit(8'hE0);               // out E0,al
        emit(8'hEB); emit(8'hFE);               // jmp $
    end

    // ---- run --------------------------------------------------------------
    function automatic logic [15:0] rdw(input int a);
        logic [15:0] lo, hi;
        lo = sdr.u_part.peek(a);
        hi = sdr.u_part.peek(a + 1);
        rdw = {hi[7:0], lo[7:0]};
    endfunction

    int errors = 0;
    task automatic want(input int a, input logic [15:0] v, input string what);
        logic [15:0] got = rdw(a);
        if (got !== v) begin
            $display("FAIL %-28s [%05x] = %04x, want %04x", what, a, got, v);
            errors++;
        end else begin
            $display("ok   %-28s [%05x] = %04x", what, a, got);
        end
    endtask

    int guard;

    initial begin
        repeat (20) @(posedge clk);
        reset = 1'b0;

        // let the controller finish its init before the CPU fetches
        guard = 0;
        while (!initilized_sdram && guard < 2000000) begin
            @(posedge clk); guard++;
        end
        if (!initilized_sdram) begin
            $display("FAIL controller never initialised");
            $finish;
        end
        $display("controller initialised at %0t", $time);
        repeat (20) @(posedge clk);
        cpu_reset = 1'b0;

        guard = 0;
        while (port_e0 !== 8'hA5 && guard < 40000000) begin
            @(posedge clk); guard++;
        end

        if (port_e0 !== 8'hA5) begin
            $display("FAIL program never reported (port E0 = %02x) after %0d clocks",
                     port_e0, guard);
            $display("     last guest address %05x", cpu_address);
            errors++;
        end else begin
            $display("program reported at %0t (%0d clocks)", $time, guard);
            want(20'h00300, 16'h1234, "T1 word store/load");
            want(20'h00302, 16'hBBAA, "T2 byte lanes -> word");
            want(20'h00304, 16'h5678, "T3 word store, byte loads");
            want(20'h00306, 16'h0000, "T4 sweep mismatches");
            // and the stored patterns themselves, read from the part
            want(20'h00200, 16'h1234, "T1 in memory");
            want(20'h00202, 16'hBBAA, "T2 in memory");
            want(20'h00204, 16'h5678, "T3 in memory");
            want(20'h01000, 16'h1000, "T4 first word");
            want(20'h011FE, 16'h11FE, "T4 last word");
            want(20'h00310, 16'h0000, "T5 ES=1000 repe scasw equal");
            want(20'h00312, 16'h2000, "T5 ES=1000 end DI");
            want(20'h00314, 16'h0000, "T6 ES=2000 repe scasw equal");
            want(20'h00316, 16'h2000, "T6 ES=2000 end DI");
            want(20'h00318, 16'h0000, "T7 ES=3000 repe scasw equal");
            want(20'h0031A, 16'h2000, "T7 ES=3000 end DI");
            want(20'h00320, 16'd64,    "T8 640/10 quotient");
            want(20'h00322, 16'd0,     "T8 640/10 remainder");
            want(20'h00324, 16'd6,     "T8 64/10 quotient");
            want(20'h00326, 16'd4,     "T8 64/10 remainder");
            want(20'h00328, 16'h5555,  "T8 10000h/3 quotient");
            want(20'h0032A, 16'h0001,  "T8 10000h/3 remainder");
            want(20'h0032C, 16'h041C,  "T8 200/7 byte {ah=rem,al=quot}");
            want(20'h0032E, 16'h0320,  "T8 5 * A0 (mul ah)");
            want(20'h10000, 16'hAA55, "T5 first word in memory");
            want(20'h11FFE, 16'hAA55, "T5 last word in memory");
            want(20'h20000, 16'hAA55, "T6 first word in memory");
            want(20'h21FFE, 16'hAA55, "T6 last word in memory");
            want(20'h30000, 16'hAA55, "T7 first word in memory");
            want(20'h31FFE, 16'hAA55, "T7 last word in memory");
        end

        $display("one-cycle word accesses: %0d", word_cycles);
`ifdef PC98_WORD_MEM
        if (word_cycles == 0) begin
            $display("FAIL PC98_WORD_MEM is defined but no word cycle ran");
            errors++;
        end
`else
        if (word_cycles != 0) begin
            $display("FAIL word cycles ran without PC98_WORD_MEM");
            errors++;
        end
`endif

        if (errors == 0) $display("PASS tb_v30_mem");
        else             $display("FAILED tb_v30_mem: %0d", errors);
        $finish;
    end

    initial begin
        #500000000;
        $display("FAILED tb_v30_mem: timeout");
        $finish;
    end

endmodule

`default_nettype wire
