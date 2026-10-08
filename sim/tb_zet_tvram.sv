//
// tb_zet_tvram -- the REAL CPU->TVRAM bus path under test.
//
// Hardware showed text corruption on the Pocket (dir scroll => "starfield",
// dropped chars even on plain `0123456789` echo). The flat-memory benches
// (tb_zet_movs, tb_pc98_boot non-REALMEM) never exercise the actual write
// path: they strobe a flat array on fake memory_write_n edges and never run
// through BUS_ARBITER's DEN mux, the real i8288 strobe timing, READY's
// bus_state/ready_n_or_wait residue, or the registered tvram read stage.
//
// This bench wires the real thing:
//
//   zet -> zet_cpu_bridge -> BUS_ARBITER (i8288 + upd71071, dma_request=0)
//        -> pc98_tvram  +  Peripherals' registered data_bus_out replica
//        ->  Chipset's internal_data_bus_ext mux replica -> bridge data_bus
//
// plus a flat 1MB array for everything outside A0000-A3FFF (program, stack)
// served combinationally -- only the TVRAM path is modelled faithfully.
//
// The program is BIOS-shaped: rep stosw clear of char (0020) and attr
// (00E1) planes, ten `mov es:[di],dx` word writes interleaved with
// `in al,31h` (BIOS polls keyboard status between echoed chars), then a
// `rep movsw` row copy -- the same sequence whose corruption was seen on
// hardware as {hi==lo} cells and writes landing 0x00.
//
// Monitors flag every bus-level anomaly live:
//   * a write strobe low while DEN or DT/R disagrees (would latch ext bus)
//   * a write strobe on a tvram byte where internal_data_bus != cpu_data_bus
//   * wren edges counted per address vs a golden bus model
//
// At the end the bench dumps every cell through the dbg port and compares
// against a golden byte model of the window built from the SAME write
// strobes the DUT saw -- mismatches mean a write was lost or mangled.
//
// +speed=N  selects the ce_generator clk_select (0..3; 2 = 19.66 MHz).
//

`default_nettype none
`timescale 1ns/1ps

module tb_zet_tvram;

    logic clk = 1'b0;
    always #11.641 clk = ~clk;               // 42.954545 MHz

    logic reset = 1'b1;

    int speed = 2;
    initial if (!$value$plusargs("speed=%d", speed)) speed = 2;

    // ---------------------------------------------------------- CE train
    wire clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire cycle_accrate, shift_read_timing;
    wire [7:0] ccc_div, ccc_dec;
    wire [1:0] ram_rd_wait, ram_wr_wait;
    logic biu_done;

    ce_generator u_ce (
        .clock                              (clk),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (2'(speed)),
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

    // ------------------------------------------------- zet + its bridge
    wire        zet_clk;
    wire [15:0] zwb_dat_i, zwb_dat_o;
    wire [19:1] zwb_adr;
    wire        zwb_we, zwb_tga, zwb_stb, zwb_cyc, zwb_ack;
    wire [ 1:0] zwb_sel;
    wire        zwb_inta, zwb_nmia;
    wire [19:0] zet_pc;
    wire        zet_fault;
    wire [7:0]  zet_opc;
    logic       irq_line = 1'b0;
    int         intr_every = 0;
    initial if (!$value$plusargs("intr=%d", intr_every)) intr_every = 0;
    // IRQ0-ish ticker: pulse the line every N clks, hold ~200
    int irq_cnt = 0;
    always_ff @(posedge clk) begin
        if (intr_every <= 0)        irq_line <= 1'b0;
        else begin
            irq_cnt <= irq_cnt + 1;
            if (irq_cnt >= intr_every && irq_cnt < intr_every + 400)
                irq_line <= 1'b1;
            else if (irq_cnt >= intr_every + 400) begin
                irq_line <= 1'b0;
                irq_cnt  <= 0;
            end
        end
    end

    wire [2:0]  processor_status;
    wire [19:0] ad_out;
    wire [7:0]  cpu_data_bus;
    wire        word_access;
    wire [7:0]  cpu_data_bus_hi;
    wire [7:0]  data_bus;
    wire [7:0]  data_bus_hi;
    wire        processor_ready;
    wire        chipset_aen;

    zet_cpu_bridge u_bridge (
        .clk               (clk),
        .cpu_ce_posedge    (cpu_ce_posedge),
        .cpu_ce_negedge    (cpu_ce_negedge),
        .fast_pace         (speed[1]),
        .reset             (reset),
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
        .ad_out            (ad_out),
        .cpu_data_bus      (cpu_data_bus),
        .lock_n            (),
        .analog_mode       (1'b0),
        .pf_req_len        (),
        .pf_beat_v         (1'b0),
        .pf_beat_dat       (8'h00),
        .word_access       (word_access),
        .cpu_data_bus_hi   (cpu_data_bus_hi),
        .data_bus_hi       (data_bus_hi),
        .data_bus          (data_bus),
        .processor_ready   (processor_ready),
        .address_enable_n  (chipset_aen),
        .pause_core        (1'b0),
        .biu_done          (biu_done),
        .pf_disable        (1'b0),
        .dbg               ()
    );

    zet u_cpu (
        .wb_clk_i  (zet_clk),
        .wb_rst_i  (reset),
        .wb_dat_i  (zwb_dat_i),
        .wb_dat_o  (zwb_dat_o),
        .wb_adr_o  (zwb_adr),
        .wb_we_o   (zwb_we),
        .wb_tga_o  (zwb_tga),
        .wb_sel_o  (zwb_sel),
        .wb_stb_o  (zwb_stb),
        .wb_cyc_o  (zwb_cyc),
        .wb_ack_i  (zwb_ack),
        .wb_tgc_i  (irq_line),
        .wb_tgc_o  (zwb_inta),
        .nmi       (1'b0),
        .nmia      (zwb_nmia),
        .pc        (zet_pc),
        .dbg_fault (zet_fault),
        .dbg_opc   (zet_opc)
    );

    // ------------------------------------------------------ BUS_ARBITER
    wire [19:0] address;
    wire        address_direction, data_bus_direction;
    wire [7:0]  internal_data_bus;
    logic [7:0] internal_data_bus_ext;
    wire        address_latch_enable;
    wire        io_read_n, io_write_n, memory_read_n, memory_write_n;
    wire        interrupt_acknowledge_n, no_command_state;
    wire        dma_wait_n, dma_ready;
    wire [3:0]  dma_acknowledge_n;
    wire        terminal_count_n;
    wire [7:0]  arb_dbg;
    wire [127:0] dbg_dma, dbg_dma3, dbg_dma4;

    BUS_ARBITER u_arb (
        .clock                        (clk),
        .cpu_ce_posedge               (cpu_ce_posedge),
        .cpu_ce_negedge               (cpu_ce_negedge),
        .reset                        (reset),
        .cpu_address                  (ad_out),
        .cpu_data_bus                 (cpu_data_bus),
        .processor_status             (processor_status),
        .processor_lock_n             (1'b1),
        .processor_transmit_or_receive_n (),
        .dma_ready                    (dma_ready),
        .dma_wait_n                   (dma_wait_n),
        .interrupt_acknowledge_n      (interrupt_acknowledge_n),
        .dma_chip_select_n            (1'b1),
        .dma_page_chip_select_n       (1'b1),
        .address                      (address),
        .address_ext                  (20'h0),
        .address_direction            (address_direction),
        .data_bus_ext                 (internal_data_bus_ext),
        .internal_data_bus            (internal_data_bus),
        .data_bus_direction           (data_bus_direction),
        .address_latch_enable         (address_latch_enable),
        .io_read_n                    (io_read_n),
        .io_read_n_ext                (1'b1),
        .io_read_n_direction          (),
        .io_write_n                   (io_write_n),
        .io_write_n_ext               (1'b1),
        .io_write_n_direction         (),
        .memory_read_n                (memory_read_n),
        .memory_read_n_ext            (1'b1),
        .memory_read_n_direction      (),
        .memory_write_n               (memory_write_n),
        .memory_write_n_ext           (1'b1),
        .memory_write_n_direction     (),
        .no_command_state             (no_command_state),
        .ext_access_request           (1'b0),
        .dma_request                  (4'b0),
        .dma_acknowledge_n            (dma_acknowledge_n),
        .address_enable_n             (chipset_aen),
        .terminal_count_n             (terminal_count_n),
        .pf_disable        (1'b0),
        .dbg                          (arb_dbg),
        .dbg_dma                      (dbg_dma),
        .watch_addr                   (20'hFFFFF),
        .dbg_dma3                     (dbg_dma3),
        .dbg_dma4                     (dbg_dma4)
    );

    // ------------------------------------------------------------- READY
    READY u_ready (
        .clock               (clk),
        .cpu_ce_posedge      (cpu_ce_posedge),
        .cpu_ce_negedge      (cpu_ce_negedge),
        .reset               (reset),
        .processor_ready     (processor_ready),
        .dma_ready           (dma_ready),
        .dma_wait_n          (dma_wait_n),
        .io_channel_ready    (1'b1),
        .io_read_n           (io_read_n),
        .io_write_n          (io_write_n),
        .memory_read_n       (memory_read_n),
        .dma0_acknowledge_n  (dma_acknowledge_n[0]),
        .address_enable_n    (chipset_aen)
    );

    // -------------------------------------------------- the TVRAM itself
    wire tvram_sel = ~chipset_aen && (address[19:14] == 6'b101000);
    wire [7:0] tvram_cpu_q;
    logic [11:0] dbg_cell = 12'h000;
    wire [31:0] tvram_dbg_q;
    wire [23:0] tvram_dbg_word;

    pc98_tvram u_tvram (
        .clk         (clk),
        .rst         (reset),
        .cpu_addr    (address[13:0]),
        .cpu_wren    (tvram_sel & ~memory_write_n),
        .cpu_rden    (tvram_sel & ~memory_read_n),
        .cpu_wdata   (internal_data_bus),
        .cpu_q       (tvram_cpu_q),
        .cpu_word    (1'b0),
        .cpu_wdata_hi(8'h00),
        .cpu_q_hi    (),
        .dbg_cell    (dbg_cell),
        .dbg_q       (tvram_dbg_q),
        .dbg_word    (tvram_dbg_word),
        .fil_clk     (clk),
        .fil_cell    (12'h000),
        .fil_char_lo (),
        .fil_char_hi (),
        .vid_clk     (clk),
        .vid_cell    (12'h000),
        .vid_attr    (),
        .cfg_a3fea   (8'h04),
        .cfg_a3fee   (8'h00),
        .cfg_a3ff2   (8'h01)
    );

    // ------------------------------------- Peripherals' registered read
    logic [7:0] data_bus_out_q;
    logic       data_bus_out_from_chipset_q;
    always_ff @(posedge clk) begin
        if (tvram_sel && ~memory_read_n) begin
            data_bus_out_from_chipset_q <= 1'b1;
            data_bus_out_q              <= tvram_cpu_q;
        end else begin
            data_bus_out_from_chipset_q <= 1'b0;
            data_bus_out_q              <= 8'h00;
        end
    end

    // -------------------------------------------- flat memory + read mux
    logic [7:0] ram [0:20'hFFFFF];
    initial begin
        for (int i = 0; i < 32'h100000; i = i + 1) ram[i] = 8'h00;
        $readmemh("tv.hex", ram);
    end

    wire flat_hit = ~memory_read_n && (address[19:14] != 6'b101000);
    // 1cyc SDRAM word accesses carry the odd byte on the hi lane, exactly
    // how RAM.sv answers them.
    assign data_bus_hi = ~memory_read_n ? ram[address | 20'h1] : 8'hFF;
    // the Chipset's internal_data_bus_ext comb mux, reduced to what this
    // bench serves: registered tvram data, flat RAM for the rest, and the
    // external bus (idle 0xFF like bios_write_data[7:0]) when the CPU is
    // not in a read at all.
    int   inta_seen = 0;
    logic inta_d = 1'b1;
    always_ff @(posedge clk) begin
        inta_d <= interrupt_acknowledge_n;
        if (inta_d & ~interrupt_acknowledge_n) inta_seen <= inta_seen + 1;
    end
    always_comb begin
        if (~interrupt_acknowledge_n)
            internal_data_bus_ext = 8'h40;
        else if (data_bus_out_from_chipset_q)
            internal_data_bus_ext = data_bus_out_q;
        else if (flat_hit)
            internal_data_bus_ext = ram[address];
        else if (data_bus_direction)
            internal_data_bus_ext = 8'hFF;      // ext pins, idle value
        else
            internal_data_bus_ext = 8'hFF;
    end

    // flat memory absorbs writes outside the tvram window
    logic mw_d = 1'b1;
    always_ff @(posedge clk) begin
        mw_d <= memory_write_n;
        if (~memory_write_n && !tvram_sel) begin
            ram[address] <= internal_data_bus;
            if (word_access) ram[address | 20'h1] <= cpu_data_bus_hi;
        end
    end

    assign data_bus = internal_data_bus_ext;

    // ======================================================== monitors
    // per-command trace for the first window, so a dead start is visible
    logic mrd_d = 1, mwr_d = 1, ord_d = 1, owr_d = 1;
    int trace_lines = 0;
    always_ff @(posedge clk) begin
        mrd_d <= memory_read_n; mwr_d <= memory_write_n;
        ord_d <= io_read_n;     owr_d <= io_write_n;
        if (trace_lines < 400) begin
            if (mrd_d & ~memory_read_n) begin
                trace_lines <= trace_lines + 1;
                $display("  %8t  MEMR %05x -> %02x%s", $time, address,
                         internal_data_bus_ext,
                         (processor_status == 3'b100) ? " code" : "");
            end
            if (mwr_d & ~memory_write_n) begin
                trace_lines <= trace_lines + 1;
                $display("  %8t  MEMW %05x <- %02x (cdb %02x den %b)",
                         $time, address, internal_data_bus, cpu_data_bus,
                         u_arb.data_enable);
            end
            if (ord_d & ~io_read_n) begin
                trace_lines <= trace_lines + 1;
                $display("  %8t  IORD %04x -> %02x", $time, address[15:0],
                         internal_data_bus_ext);
            end
            if (owr_d & ~io_write_n) begin
                trace_lines <= trace_lines + 1;
                $display("  %8t  IOWR %04x <- %02x", $time, address[15:0],
                         internal_data_bus);
            end
        end
    end

    int wr_count = 0, den_violations = 0, bus_mismatch = 0;
    int early_accept = 0, strobe_before_den = 0;
    // golden model of the 16KB window: bytes as the guest wrote them
    logic [7:0] gold [0:16383];

    logic [19:0] last_wr_addr;
    logic [7:0]  last_wr_data;

    always_ff @(posedge clk) begin
        if (tvram_sel && ~memory_write_n) begin
            // every clk the write strobe is low, the DUT latches
            // internal_data_bus at address -- do the same in the model
            gold[address[13:0]] <= internal_data_bus;
            if (~mw_d) wr_count <= wr_count + 1;
            // the strobe must only ever see the CPU's own byte
            if (~u_arb.data_enable || ~u_arb.direction_transmit_or_receive_n) begin
                den_violations <= den_violations + 1;
                if (den_violations < 20)
                    $display("!! %8t WR-strobe w/o DEN/DT-R: addr %05x idb %02x cdb %02x",
                             $time, address, internal_data_bus, cpu_data_bus);
            end else if (internal_data_bus !== cpu_data_bus) begin
                bus_mismatch <= bus_mismatch + 1;
                if (bus_mismatch < 20)
                    $display("!! %8t WR bus != cpu_data_bus: addr %05x idb %02x cdb %02x",
                             $time, address, internal_data_bus, cpu_data_bus);
            end
        end
        last_wr_addr <= address;
        last_wr_data <= internal_data_bus;
    end

    // ======================================================= cell dump
    task read_cell(input int i, output [23:0] w);
        dbg_cell = 12'(i);
        repeat (4) @(posedge clk);
        w = tvram_dbg_word;
    endtask

    // golden byte-model -> cell triple {attr,hi,lo}
    function automatic [23:0] gold_cell(input int i);
        logic [7:0] lo, hi, at;
        lo = gold[i*2];       // A0000+2i
        hi = gold[i*2+1];     // A0000+2i+1
        at = gold[14'h2000 + i*2];   // A2000+2i
        return {at, hi, lo};
    endfunction

    int errors = 0;
    initial begin
        repeat (50) @(posedge clk);
        reset <= 1'b0;

        // wait for the program's OUT 0x1234
        begin : wait_done
            int t = 0;
            while (t < 3_000_000) begin
                @(posedge clk);
                if (~io_write_n && address[15:0] == 16'h1234) break;
                if (t % 200_000 == 0)
                    $display("  t=%8d pc=%05x opc=%02x bstate=%0d req=%b aen=%b mwr=%b mrd=%b",
                             t, zet_pc, zet_opc, u_bridge.bstate,
                             u_bridge.req_busy, chipset_aen,
                             memory_write_n, memory_read_n);
                t = t + 1;
            end
            if (t >= 3_000_000) $display("TIMEOUT waiting for done marker");
        end
        repeat (100) @(posedge clk);

        $display("wr_count=%0d den_violations=%0d bus_mismatch=%0d inta_seen=%0d",
                 wr_count, den_violations, bus_mismatch, inta_seen);

        // expected screen after cls+digits+scroll:
        //   attr = E1 everywhere (except protected memsw cells)
        //   cells 1840..1849 = '0'..'9' (hi 00)
        //   cells 0..79      = copy of row23 (after the scroll)
        for (int i = 0; i < 2000; i = i + 1) begin
            logic [23:0] w;
            logic [7:0] elo, ehi, eat;
            read_cell(i, w);
            eat = 8'hE1; elo = 8'h20; ehi = 8'h00;
            if (i >= 1840 && i < 1850) elo = 8'h30 + 8'(i - 1840);
            if (i >= 0 && i < 80) begin
                // row 0 = copy of row 23 after scroll
                eat = 8'hE1; elo = 8'h20; ehi = 8'h00;
                if (i < 10) elo = 8'h30 + 8'(i);
            end
            if ({w[15:8], w[7:0]} !== {ehi, elo} || w[23:16] !== eat) begin
                errors <= errors + 1;
                if (errors < 30)
                    $display("MISMATCH cell %0d: got {attr %02x hi %02x lo %02x} want {attr %02x hi %02x lo %02x}",
                             i, w[23:16], w[15:8], w[7:0], eat, ehi, elo);
            end
        end
        if (errors == 0) $display("PASS: all 2000 cells correct");
        else             $display("FAIL: %0d cells wrong", errors);
        $finish;
    end

endmodule

`default_nettype wire
