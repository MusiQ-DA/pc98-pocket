//
// tb_pc98_dma_decode -- the BIOS-visible uPD71071 window, decoded and driven
// end to end.
//
// The bug this guards: PERIPHERALS decoded the DMA controller at odd
// 0x01-0x0F only (~address[4] in dma_chip_select_n), so the chip's upper
// registers -- single mask 0x15, mode 0x17, byte-pointer clear 0x19, master
// clear 0x1B, mask clear 0x1D, mask write 0x1F -- never saw a chip select.
// mask_register resets all-masked, so channel 2 stayed masked forever: the
// BIOS's "out 0x15, 0x02" vanished, DRQ2 was never honoured, and every
// floppy READ DATA stalled waiting for a DMA transfer that could not start.
// The 71071 itself was wired right -- address_in = address[4:1] covers all
// sixteen registers on odd ports 0x01-0x1F, which is the PC-98 map.
//
// This bench puts the real PERIPHERALS decode in front of the real
// BUS_ARBITER (real upd71071 + page registers + i8288) and drives
// guest-visible io cycles exactly the way the arbiter passes them while the
// CPU owns the bus: the port on cpu_address, the byte on data_bus_ext, the
// strobe on io_*_n_ext -- the ext strobes pass straight through whenever the
// internal side is idle, and address_enable_n stays low because nothing
// holds the bus.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none
`timescale 1ns/1ps

module tb_pc98_dma_decode;

    localparam real CLK_MHZ = 42.954545;
    localparam real HALF_NS = 500.0 / CLK_MHZ;

    logic clock = 0, reset = 1;
    always #(HALF_NS) clock = ~clock;

    logic cpu_ce_posedge = 0, cpu_ce_negedge = 0;
    int   ce_div = 0;
    always @(posedge clock) begin
        ce_div <= (ce_div == 8) ? 0 : ce_div + 1;
        cpu_ce_posedge <= (ce_div == 0);
        cpu_ce_negedge <= (ce_div == 4);
    end

    // ---- guest bus, driven the way a parked-CPU arbiter sees it -----------
    logic [19:0] cpu_address  = 20'd0;
    logic  [7:0] cpu_data_bus = 8'd0;
    logic  [2:0] processor_status = 3'b111;   // passive -- no 8288 cycle
    logic        io_rd_ext = 1'b1, io_wr_ext = 1'b1;
    logic [19:0] ext_addr  = 20'd0;
    logic  [7:0] ext_wdata = 8'd0;
    logic        ext_req   = 1'b0;

    // The floppy asks like the integration does: PERIPHERALS forces
    // fdd_dma_req low while its ack is held, because the 71071's
    // dma_request_lock only re-arms once DREQ has dropped back. A constant
    // high here buys exactly one transfer, then the channel locks.
    // CHIPSET drives fdd_dma_req onto both request 2 (2HD) and request 3
    // (2DD); the bench does the same so either window's transfer runs.
    //
    // The pins are bus-level: DRQx is active-low on the PC-98 (the data
    // book names them DRQ3O..DRQ0O) and the BIOS programs command bit6 to
    // match, so a request drives its pin LOW -- exactly what CHIPSET now
    // does by inverting its internal active-high sources.  Idle pins sit
    // high, and the fdd_want term below is the pre-inversion logic level.
    logic        fdd_want  = 1'b0;
    logic        fdd_req_r = 1'b0;
    always_ff @(posedge clock)
        fdd_req_r <= fdd_want & dma_acknowledge_n[2] & dma_acknowledge_n[3];
    wire   [3:0] dma_request = ~{fdd_req_r, fdd_req_r, 2'b00};

    wire [19:0] address;
    wire  [7:0] internal_data_bus;
    wire        io_read_n, io_write_n;
    wire        memory_read_n, memory_write_n, no_command_state;
    wire        address_enable_n, terminal_count_n;
    wire  [3:0] dma_acknowledge_n;
    wire        dma_cs_n, dma_page_cs_n;
    wire        address_direction, data_bus_direction;
    wire        io_read_n_direction, io_write_n_direction;
    wire        memory_read_n_direction, memory_write_n_direction;
    wire        address_latch_enable, interrupt_acknowledge_n;
    wire        processor_transmit_or_receive_n, dma_wait_n;

    // The real decode under test. Only the ports this bench observes are
    // wired; the rest of the machine is not what is being measured.
    /* verilator lint_off PINMISSING */
    /* verilator lint_off PINCONNECTEMPTY */
    PERIPHERALS u_per (
        .clock                  (clock),
        .cpu_ce_negedge         (cpu_ce_negedge),
        .clk_select             (2'b00),
        .reset                  (reset),
        .interrupt_acknowledge_n(interrupt_acknowledge_n),
        .clk_pc98_dot            (1'b0),
        .font_rd_ack            (1'b0),
        .font_rd_valid          (1'b0),
        .font_rd_data           (16'd0),
        .font_rd_done           (1'b0),
        .cg_rd_ack              (1'b0),
        .cg_rd_valid            (1'b0),
        .cg_rd_data             (16'd0),
        .cg_rd_done             (1'b0),
        .font_wr_clk            (1'b0),
        .font_wr_en             (1'b0),
        .font_wr_addr           (11'd0),
        .font_wr_data           (16'd0),
        .address                (address),
        .internal_data_bus      (internal_data_bus),
        .interrupt_request      (8'd0),
        .io_read_n              (io_read_n),
        .io_write_n             (io_write_n),
        .memory_read_n          (memory_read_n),
        .memory_write_n         (memory_write_n),
        .address_enable_n       (address_enable_n),
        .kb_byte                (8'd0),
        .kb_valid               (1'b0),
        .gdc_srv_done_levels    (2'b00),
        .ems_enabled            (1'b0),
        .ems_address            (2'b00),
        .mgmt_address           (16'd0),
        .mgmt_read              (1'b0),
        .mgmt_write             (1'b0),
        .mgmt_writedata         (16'd0),
        .floppy_wp              (2'b00),
        .rtc_time               (48'd0),
        .fdd_dma_ack            (1'b0),
        // The arbiter's terminal_count_n is misnamed: it is ~EOP_n, an
        // active-high pulse -- exactly what CHIPSET feeds here.
        .terminal_count         (terminal_count_n),
        .pc98_key_stb           (1'b0),
        .pc98_key_byte          (8'd0),
        .dma_chip_select_n      (dma_cs_n),
        .dma_page_chip_select_n (dma_page_cs_n),
        .dbg_fdc_dma            ()
    );
    /* verilator lint_on PINCONNECTEMPTY */
    /* verilator lint_on PINMISSING */

    BUS_ARBITER u_arb (
        .clock(clock),
        .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(cpu_ce_negedge),
        .reset(reset),
        .cpu_address(cpu_address),
        .cpu_data_bus(cpu_data_bus),
        .processor_status(processor_status),
        .processor_lock_n(1'b1),
        .processor_transmit_or_receive_n(processor_transmit_or_receive_n),
        .dma_ready(1'b1),
        .dma_wait_n(dma_wait_n),
        .interrupt_acknowledge_n(interrupt_acknowledge_n),
        .dma_chip_select_n(dma_cs_n),
        .dma_page_chip_select_n(dma_page_cs_n),
        .address(address),
        .address_ext(ext_addr),
        .address_direction(address_direction),
        .data_bus_ext(ext_wdata),
        .internal_data_bus(internal_data_bus),
        .data_bus_direction(data_bus_direction),
        .address_latch_enable(address_latch_enable),
        .io_read_n(io_read_n),
        .io_read_n_ext(io_rd_ext),
        .io_read_n_direction(io_read_n_direction),
        .io_write_n(io_write_n),
        .io_write_n_ext(io_wr_ext),
        .io_write_n_direction(io_write_n_direction),
        .memory_read_n(memory_read_n),
        .memory_read_n_ext(1'b1),
        .memory_read_n_direction(memory_read_n_direction),
        .memory_write_n(memory_write_n),
        .memory_write_n_ext(1'b1),
        .memory_write_n_direction(memory_write_n_direction),
        .no_command_state(no_command_state),
        .ext_access_request(ext_req),
        .dma_request(dma_request),
        .dma_acknowledge_n(dma_acknowledge_n),
        .address_enable_n(address_enable_n),
        .terminal_count_n(terminal_count_n),
        .dbg_hold(),
        .dbg_dmac(dbg_dmac)
    );

    wire [31:0] dbg_dmac;

    int errors = 0;
    task automatic check(input bit cond, input string name);
        if (!cond) begin
            errors++;
            $display("FAIL: %s", name);
        end
    endtask

    // One guest io write: address parked on cpu_address, byte on the ext data
    // input (the mux hands data_bus_ext to the chip while the 8288 is idle),
    // strobe on io_write_n_ext. The 71071 latches the register on the strobe's
    // rising edge while the select is live.
    task automatic io_write(input logic [19:0] port, input logic [7:0] data);
        @(negedge clock);
        cpu_address = port;
        ext_wdata   = data;
        @(negedge clock);
        io_wr_ext = 1'b0;
        repeat (4) @(negedge clock);
        io_wr_ext = 1'b1;
        repeat (4) @(negedge clock);
        cpu_address = 20'd0;
        repeat (2) @(negedge clock);
    endtask

    task automatic io_read(input logic [19:0] port, output logic [7:0] data);
        @(negedge clock);
        cpu_address = port;
        @(negedge clock);
        io_rd_ext = 1'b0;
        repeat (4) @(negedge clock);
        data = internal_data_bus;
        io_rd_ext = 1'b1;
        repeat (4) @(negedge clock);
        cpu_address = 20'd0;
        repeat (2) @(negedge clock);
    endtask

    // Decode probe: park the port, drop the read strobe, look at the select.
    task automatic probe(input logic [19:0] port,
                         output bit sel, output bit psel);
        @(negedge clock);
        cpu_address = port;
        io_rd_ext   = 1'b0;
        repeat (3) @(negedge clock);
        sel  = ~dma_cs_n;
        psel = ~dma_page_cs_n;
        io_rd_ext   = 1'b1;
        cpu_address = 20'd0;
        repeat (2) @(negedge clock);
    endtask

    bit sel, psel;
    logic [7:0] rd;
    int  memw_count = 0;
    bit  tc_seen = 1'b0;
    bit  ior_seen = 1'b0;

    // DMA activity counters: MEMW pulses are the byte transfers, IOR pulses
    // are the peripheral-side reads of the same transfer.
    always @(negedge memory_write_n) memw_count++;
    always @(negedge terminal_count_n) tc_seen = 1'b1;
    always @(negedge io_read_n) if (address_enable_n) ior_seen = 1'b1;

    initial begin
        repeat (40) @(posedge clock);
        reset = 0;
        repeat (40) @(posedge clock);

        $display("=== decode coverage ===");
        probe(20'h00001, sel, psel); check(sel && !psel, "0x01 selects DMAC");
        probe(20'h00009, sel, psel); check(sel && !psel, "0x09 ch2 address");
        probe(20'h0000F, sel, psel); check(sel && !psel, "0x0F ch3 count");
        // The ports the BIOS actually needs -- all above the old decode's
        // ceiling at 0x0F:
        probe(20'h00011, sel, psel); check(sel && !psel, "0x11 command/status");
        probe(20'h00013, sel, psel); check(sel && !psel, "0x13 request");
        probe(20'h00015, sel, psel); check(sel && !psel, "0x15 single mask");
        probe(20'h00017, sel, psel); check(sel && !psel, "0x17 mode");
        probe(20'h00019, sel, psel); check(sel && !psel, "0x19 byte-ptr clear");
        probe(20'h0001B, sel, psel); check(sel && !psel, "0x1B master clear");
        probe(20'h0001D, sel, psel); check(sel && !psel, "0x1D mask clear");
        probe(20'h0001F, sel, psel); check(sel && !psel, "0x1F mask write");
        // ...and nothing outside 0x01-0x1F odd:
        probe(20'h00000, sel, psel); check(!sel && !psel, "0x00 is not DMAC");
        probe(20'h00002, sel, psel); check(!sel && !psel, "0x02 is not DMAC");
        probe(20'h00010, sel, psel); check(!sel && !psel, "0x10 even");
        probe(20'h00020, sel, psel); check(!sel && !psel, "0x20 even");
        probe(20'h00021, sel, psel); check(!sel && psel, "0x21 is page, not DMAC");
        probe(20'h00023, sel, psel); check(!sel && psel, "0x23 is page, not DMAC");
        probe(20'h0002F, sel, psel); check(!sel && psel, "0x2F is page, not DMAC");
        probe(20'h00031, sel, psel); check(!sel && !psel, "0x31 sysport, not DMAC");
        probe(20'h00041, sel, psel); check(!sel && !psel, "0x41 kbd, not DMAC");
        probe(20'h00115, sel, psel); check(!sel && !psel, "0x115 out of range");

        $display("=== BIOS channel-2 setup, exactly as FFA70/FFDEF drives it ===");
        // The BIOS selects active-low DREQ sensing (command 0x11 bit6) to
        // match the bus's DRQxO pins; without this the bench would exercise
        // a polarity combination hardware never uses.
        io_write(20'h00011, 8'h40);
        // Masked at reset: a request must not produce a status bit yet.
        fdd_want = 1'b1;
        repeat (8) @(posedge clock);
        io_read(20'h00011, rd);
        check(rd[6] == 1'b0, "status bit6 clear while masked");

        // 0x19: clear byte pointer; 0x17: mode 0x46 (single, write, ch2);
        // 0x09: ch2 address = 0x0200; 0x23: page = 0x1; 0x0B: count = 3
        // (four bytes); 0x15: unmask ch2.
        io_write(20'h00019, 8'h00);
        io_write(20'h00017, 8'h46);
        io_write(20'h00009, 8'h00);
        io_write(20'h00009, 8'h02);
        io_write(20'h00023, 8'h01);
        io_write(20'h0000B, 8'h03);
        io_write(20'h0000B, 8'h00);

        // The program registers must be readable back -- the address
        // register decrements live, so read the count instead.
        io_read(20'h0000B, rd);
        check(rd == 8'h03, "ch2 count LSB reads back");

        // Unmask last, like the BIOS does, then watch the transfer run.
        io_write(20'h00015, 8'h02);

        // The DMAC now owns the request: hold-ack comes up on its own, DACK2
        // drops, and single-mode cycles run one byte at a time until count.
        begin : wait_ack
            int guard = 0;
            while (dma_acknowledge_n[2] && guard < 4000) begin
                @(posedge clock); guard++;
            end
            check(guard < 4000, "DACK2 asserted after unmask");
        end
        $display("  mask=%b ack=%b (unmask landed, ch2 live)",
                 u_arb.u_upd71071.u_Priority_Encoder.mask_register,
                 dma_acknowledge_n);

        // The POSTMON word has to carry the same story the hierarchical
        // probes do: mask at [31:28], the single-mask write's sticky at
        // bit 7, its register index at [15:12], and a nonzero count.
        check(dbg_dmac[31:28] == 4'b1011, "dbg carries mask_register");
        check(dbg_dmac[7], "dbg sticky: single-mask reg written");
        check(dbg_dmac[15:12] == 4'hA, "dbg last write is reg 0xA");
        check(dbg_dmac[11:8] != 4'h0, "dbg counts the writes");

        begin : wait_tc
            int guard = 0;
            while (!tc_seen && guard < 20000) begin
                @(posedge clock); guard++;
            end
            check(tc_seen, "terminal count after 4 bytes");
        end
        repeat (40) @(posedge clock);
        check(memw_count == 4, "four MEMW pulses (count 3 + 1)");
        check(ior_seen, "DMA-cycle IOR pulses seen");
        fdd_want = 1'b0;

        $display("=== 2DD channel-3 setup, the 0xC8 window's path ===");
        // The BIOS's other DMA route: dl!=0x90 -> ch3 -- address at 0x0D,
        // count at 0x0F, page register 2 at 0x25, unmask 0x03 at 0x15.
        // The 71071 does not mask a channel at terminal count, so ch2 is
        // masked again first -- as the BIOS does between operations.
        fdd_want = 1'b0;
        repeat (40) @(posedge clock);
        io_write(20'h00015, 8'h06);   // mask ch2
        io_write(20'h00019, 8'h00);
        io_write(20'h00017, 8'h47);   // single, write, ch3
        io_write(20'h0000D, 8'h00);
        io_write(20'h0000D, 8'h04);
        io_write(20'h00025, 8'h02);
        io_write(20'h0000F, 8'h01);
        io_write(20'h0000F, 8'h00);
        io_write(20'h00015, 8'h03);   // unmask ch3
        fdd_want = 1'b1;

        memw_count = 0; tc_seen = 1'b0;
        begin : wait_ack3
            int guard = 0;
            while (dma_acknowledge_n[3] && guard < 4000) begin
                @(posedge clock); guard++;
            end
            check(guard < 4000, "DACK3 asserted after unmask");
        end
        begin : wait_tc3
            int guard = 0;
            while (!tc_seen && guard < 20000) begin
                @(posedge clock); guard++;
            end
            check(tc_seen, "ch3 terminal count after 2 bytes");
        end
        fdd_want = 1'b0;
        repeat (60) @(posedge clock);
        $display("  ch3 memw_count=%0d", memw_count);
        check(memw_count == 2, "two MEMW pulses on ch3");

        $display("=== mask re-set ===");
        // Mask-all write at 0x1F must also land -- the same upper window.
        // Park the requester first so the write meets an idle bus.
        io_write(20'h00015, 8'h07);   // mask ch3
        io_write(20'h0001F, 8'h0F);
        fdd_want = 1'b1;
        tc_seen = 1'b0; memw_count = 0;
        repeat (200) @(posedge clock);
        check(dma_acknowledge_n[2] == 1'b1, "DACK2 stays off once masked");
        check(dma_acknowledge_n[3] == 1'b1, "DACK3 stays off once masked");
        check(!tc_seen, "no terminal count while masked");

        // 0x1D clears every mask bit; a pending request must be serviced.
        io_write(20'h0001D, 8'h00);
        begin : wait_ack2
            int guard = 0;
            while (dma_acknowledge_n[2] && guard < 4000) begin
                @(posedge clock); guard++;
            end
            check(guard < 4000, "DACK2 asserts after clear-mask 0x1D");
        end
        fdd_want = 1'b0;
        repeat (200) @(posedge clock);

        if (errors == 0) $display("PASS: all checks");
        else             $display("FAIL: %0d check(s)", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: global timeout");
        $finish;
    end

endmodule
