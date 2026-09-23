// tb_v30_fdcrd -- does the nuV30 sample the FDC read mux before it updates?
//
// The full bench (tb_pc98_v30) stages the FDC read answer three chipset
// clocks deep: rd_stb -> fdd_io_read/io_address -> io_readdata ->
// fdd_readdata.  The nuV30 BIU latches ad_i at the T2->T3 edge
// (v30u_biu.sv `TS_T2: cur_data = ad_i`), only ~2-4 clk_chipset after
// io_read_command_n falls.  If the sample lands before fdd_readdata is
// updated the CPU reads the PREVIOUS read's byte -- which is exactly the
// shape of the boot failure: the IRQ handler's `in al,dx` at FFB08 saw
// CB=0 during a live result phase and fell into the command-send helper.
//
// This bench wires v30_core + i8288 + pc98_fdc_glue + floppy exactly the
// way tb_pc98_v30 does (no v30_cpu_bridge, READY tied high, combinational
// din) and runs a BIOS-shaped SPECIFY/RECALIBRATE x4/SENSE drain, logging
// for every FDC read the byte the CPU sampled AND the byte the FDC
// presented, so a one-read-behind path shows up directly.
//
// Built via the same docker/verilator invocation as sim_v30_bridge.sh,
// with tb_v30_fdcrd as top and floppy/glue/fifo added to the file list.

`timescale 1ns/1ps

module tb_v30_fdcrd;

    logic clk = 1'b0;
    always #11.641 clk = ~clk;         // 42.954545 MHz, the chipset clock

    logic reset = 1'b1;

    // ---- CE train, same as tb_pc98_v30 ------------------------------------
    wire clk_cpu, cpu_ce_posedge, cpu_ce_negedge, peripheral_ce;
    wire cycle_accrate, shift_read_timing;
    wire [7:0] ccc_div, ccc_dec;
    wire [1:0] ram_rd_wait, ram_wr_wait;

    ce_generator u_ce (
        .clock                              (clk),
        .reset                              (reset),
        .clk_select_load                    (cpu_ce_posedge),
        .clk_select                         (2'b10),
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

    // ---- the CPU, wired the tb_pc98_v30 way: bare, READY high -------------
    wire  [2:0]  processor_status;
    wire  [19:0] ADDR_O;
    wire  [15:0] DATA_O;
    logic [15:0] DATA_I;
    wire         RD_N, UBE_N;

    v30_core u_cpu (
        .CLK       (clk),
        .CE        (cpu_ce_posedge),
        .RESET     (reset),
        .READY     (1'b1),
        .INT       (1'b0),
        .NMI       (1'b0),
        .POLL_N    (1'b1),
        .DATA_I    (DATA_I),
        .ADDR_O    (ADDR_O),
        .DATA_O    (DATA_O),
        .STATUS_O  (),
        .QS        (),
        .BS        (processor_status),
        .RD_N      (RD_N),
        .UBE_N     (UBE_N),
        .BUSLOCK_N (),
        .SS_ADDR (), .SS_WDATA (), .SS_WE (), .SS_RDATA (), .SS_ERR (),
        .SS_BUS_QUIET ()
    );

    // ---- bus controller, as tb_pc98_v30 wires it ---------------------------
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

    wire [19:0] cpu_address = ADDR_O;
    wire  [7:0] cpu_data_bus = ADDR_O[0] ? DATA_O[15:8] : DATA_O[7:0];

    // ---- memory ------------------------------------------------------------
    logic [7:0] mem [0:1048575];
    logic       mem_wr_d = 1'b1;
    always_ff @(posedge clk) begin
        mem_wr_d <= mem_wr_n;
        if (mem_wr_n & ~mem_wr_d) mem[cpu_address] <= cpu_data_bus;
    end

    // ---- the FDC pair, verbatim from tb_pc98_v30 ----------------------------
    logic prev_io_wr_n = 1'b1, prev_io_rd_n = 1'b1;
    always_ff @(posedge clk) begin
        prev_io_wr_n <= io_wr_n;
        prev_io_rd_n <= io_rd_n;
    end

    logic [15:0] io_wr_addr_q = 16'h0000;
    logic [7:0]  io_wr_data_q = 8'h00;
    always_ff @(posedge clk)
        if (~io_wr_n) io_wr_addr_q <= cpu_address[15:0];

    wire        fdc_wr_edge  = io_wr_n & ~prev_io_wr_n;
    wire [15:0] fdc_addr_eff = fdc_wr_edge ? io_wr_addr_q : cpu_address[15:0];
    wire        fdc_win_eff  = (fdc_addr_eff[15:8] == 8'h00);

    wire fdd_fifo_win = fdc_win_eff & ((fdc_addr_eff[7:0] == 8'h90)
                                     | (fdc_addr_eff[7:0] == 8'h92)
                                     | (fdc_addr_eff[7:0] == 8'hC8)
                                     | (fdc_addr_eff[7:0] == 8'hCA));
    wire fdd_ctrl_win = fdc_win_eff & ((fdc_addr_eff[7:0] == 8'h94)
                                     | (fdc_addr_eff[7:0] == 8'hCC));
    wire fdd_mode_win = fdc_win_eff &  (fdc_addr_eff[7:0] == 8'hBE);

    wire       fdc_sel_stat = fdd_fifo_win & ~fdc_addr_eff[1];
    wire       fdc_sel_data = fdd_fifo_win &  fdc_addr_eff[1];
    wire [2:0] fdc_glue_addr;
    wire       fdc_glue_write, fdc_glue_read;
    wire [7:0] fdc_glue_wdata, fdc_ctrl_rb, fdc_mode_rb;
    wire       fdc_group_live;
    wire [7:0] fdd_readdata_wire;
    wire       fdd_irq_wire;

    logic [7:0] write_to_fdd = 8'h00;
    always_ff @(posedge clk)
        if (~io_wr_n) write_to_fdd <= cpu_data_bus;

    pc98_fdc_glue u_pc98_fdc_glue (
        .clk           (clk),
        .rst           (reset),
        .sel_stat      (fdc_sel_stat),
        .sel_data      (fdc_sel_data),
        .sel_ctrl      (fdd_ctrl_win),
        .sel_mode      (fdd_mode_win),
        .port_2dd      (fdc_addr_eff[6]),
        .wr_stb        (fdc_wr_edge),
        .wr_data       (write_to_fdd),
        .rd_stb        (~io_rd_n & prev_io_rd_n & fdd_fifo_win),
        .fd_addr       (fdc_glue_addr),
        .fd_write      (fdc_glue_write),
        .fd_read       (fdc_glue_read),
        .fd_wdata      (fdc_glue_wdata),
        .fd_irq        (fdd_irq_wire),
        .ctrl_readback (fdc_ctrl_rb),
        .mode_readback (fdc_mode_rb),
        .group_live    (fdc_group_live),
        .irq_2hd       (),
        .irq_2dd       (),
        .dbg_motor_arms   (), .dbg_motor_pulses (), .dbg_chg (),
        .dbg_strb_be   (), .dbg_strb_94 (), .dbg_strb_cc (),
        .dbg_strb_dat  (), .dbg_last_ctrl ()
    );

    // Same fix as tb_pc98_v30: read side follows the glue combinationally
    // and the held byte is the FDC's combinational answer at the strobe;
    // the write side keeps its staging (write strobes arrive at cycle end).
    wire        fdd_io_read  = fdc_glue_read;
    wire  [2:0] fdd_io_addr_rd = fdc_glue_addr;
    logic       fdd_io_read_1;
    logic [2:0] fdd_io_addr_rd_q;
    logic       fdd_io_write;
    logic [2:0] fdd_io_addr_wr;
    logic [7:0] fdd_io_writedata;
    always_ff @(posedge clk) begin
        fdd_io_read_1    <= fdd_io_read;
        fdd_io_addr_rd_q <= fdc_glue_addr;
        fdd_io_write     <= fdc_glue_write;
        fdd_io_addr_wr   <= fdc_glue_addr;
        fdd_io_writedata <= fdc_glue_wdata;
    end
    wire [2:0] fdd_io_address = fdd_io_write ? fdd_io_addr_wr
                                           : fdd_io_addr_rd;

    logic [7:0] fdd_readdata = 8'hFF;
    always_ff @(posedge clk)
        if (fdd_io_read) fdd_readdata <= u_floppy.io_readdata_prepare;

    floppy #(.NOT_READY_ENDS_COMMAND (1)) u_floppy (
        .clk            (clk),
        .rst_n          (~reset),
        .dma_req        (),
        .dma_ack        (1'b0),
        .dma_tc         (1'b0),
        .dma_readdata   (8'h00), .dma_writedata (),
        .irq            (fdd_irq_wire),
        .io_address     (fdd_io_address),
        .io_read        (fdd_io_read),
        .io_readdata    (fdd_readdata_wire),
        .io_write       (fdd_io_write),
        .io_writedata   (fdd_io_writedata),
        .mgmt_address   (4'h0),
        .mgmt_fddn      (1'b0),
        .mgmt_write     (1'b0),
        .mgmt_writedata (16'h0000),
        .mgmt_read      (1'b0),
        .mgmt_readdata  (),
        .wp             (2'b00),
        .clock_rate     (28'd42_954_545),
        .request        (),
        .dbg_cmd_accepts(), .dbg_cmd_drops (), .dbg_reply_left ()
    );

    // ---- the read mux, same shape as tb_pc98_v30's din_of -------------------
    wire fdc_msr_sel  = ~io_rd_n & fdc_sel_stat;
    wire fdc_fifo_sel = ~io_rd_n & fdc_sel_data;
    wire fdc_ctrl_sel = ~io_rd_n & fdd_ctrl_win;
    wire fdc_mode_sel = ~io_rd_n & fdd_mode_win;
    wire [7:0] fdc_msr  = fdc_group_live ? fdd_readdata : 8'hFF;
    wire [7:0] fdc_fifo = fdc_group_live ? fdd_readdata : 8'hFF;

    // same din_of shape as tb_pc98_v30, evaluated at the aligned neighbours
    function automatic logic [7:0] din_of(input logic [19:0] a);
        din_of = ~mem_rd_n ? mem[a]
               : fdc_msr_sel  ? fdc_msr
               : fdc_fifo_sel ? fdc_fifo
               : fdc_ctrl_sel ? fdc_ctrl_rb
               : fdc_mode_sel ? fdc_mode_rb
               : 8'hFF;
    endfunction

    wire [7:0] din      = din_of(cpu_address);
    wire [7:0] din_even = din_of({cpu_address[19:1], 1'b0});
    wire [7:0] din_odd  = din_of({cpu_address[19:1], 1'b1});
    always_comb begin
        case (processor_status)
            3'b100, 3'b101: DATA_I = {din_odd, din_even};
            3'b000:         DATA_I = {8'h00, din_even};     // INTA: vector low
            default:        DATA_I = {din_even, din_even};  // I/O, byte-wide
        endcase
    end

    // ---- what the CPU actually latched, and when ---------------------------
    //
    // u_biu.r_cur_data is the read-data latch: it takes ad_i at the T2->T3
    // edge (v30u_biu.sv `TS_T2: cur_data = ad_i`).  For each FDC read window
    // record (a) the clk offset at which r_cur_data latched this cycle's
    // byte, (b) the offset at which fdd_readdata settled to the new byte,
    // and (c) the byte the CPU ended up with vs the byte the FDC presented.
    logic       fdc_rd_live = 1'b0;
    logic [7:0] fdc_rd_first, fdc_rd_last, fdc_rd_cpu, fdc_rd_fdd;
    int         fdc_rd_clks = 0;
    int         fdc_sample_off = -1, fdc_settle_off = -1;
    logic [15:0] cur_data_q = 16'h0000;
    logic [7:0]  fdd_readdata_q = 8'hFF;
    always_ff @(posedge clk) begin
        if (~io_rd_n & (fdc_msr_sel | fdc_fifo_sel)) begin
            if (!fdc_rd_live) begin
                fdc_rd_live     <= 1'b1;
                fdc_rd_first    <= din;
                fdc_rd_clks     <= 0;
                fdc_sample_off  <= -1;
                fdc_settle_off  <= -1;
            end else
                fdc_rd_clks <= fdc_rd_clks + 1;
            fdc_rd_last <= din;
            if (fdc_sample_off < 0
                && u_cpu.u_biu.r_cur_data !== cur_data_q) begin
                fdc_rd_cpu     <= u_cpu.u_biu.r_cur_data[7:0];
                fdc_sample_off <= fdc_rd_clks;
            end
            if (fdc_settle_off < 0 && fdd_readdata !== fdd_readdata_q) begin
                fdc_rd_fdd     <= fdd_readdata;
                fdc_settle_off <= fdc_rd_clks;
            end
        end else
            fdc_rd_live <= 1'b0;
        cur_data_q     <= u_cpu.u_biu.r_cur_data;
        fdd_readdata_q <= fdd_readdata;
    end
    // trailing edge of an FDC read
    logic io_rd_d = 1'b1;
    wire  fdc_read_cycle = fdc_msr_sel | fdc_fifo_sel;
    logic fdc_read_q = 1'b0;
    always_ff @(posedge clk) begin
        io_rd_d    <= io_rd_n;
        fdc_read_q <= fdc_read_cycle;
        if (io_rd_n & ~io_rd_d && fdc_read_q)
            $display("  %8t  RD %04X: first %02X last %02X cpu %02X @%0d fdd %02X @%0d | iord %02X left %0d",
                     $time, cpu_address[15:0], fdc_rd_first, fdc_rd_last,
                     fdc_rd_cpu, fdc_sample_off,
                     fdc_rd_fdd, fdc_settle_off,
                     u_floppy.io_readdata, u_floppy.reply_left);
        if (fdd_io_write && fdd_io_address == 3'd5)
            $display("  %8t  FDC <- %02X", $time, fdd_io_writedata);
        if (fdd_io_read_1 && fdd_io_addr_rd_q == 3'd5)
            $display("  %8t  FDC -> %02X (left %0d)", $time,
                     fdd_readdata, u_floppy.reply_left);
    end

    // ---- the program --------------------------------------------------------
    //
    //   0000 BA 94 00      mov dx,0094        ; DOR
    //   0003 B0 3C         mov al,3C
    //   0005 EE            out dx,al
    //   0006 BA 92 00      mov dx,0092        ; FIFO
    //   0009 B0 03 EE      SPECIFY
    //   000C B0 BF EE
    //   000F B0 32 EE
    //   0012 recal drv0..3: B0 07 EE B0 <n> EE
    //   002E B9 FF FF      mov cx,FFFF
    //   0031 E2 FE         loop $             ; let the seeks finish
    //   0033 ..            drain loop x4, stores bytes at 0400+
    //   ...
    task automatic poke(input int a, input logic [7:0] d);
        mem[a] = d;
    endtask

    int errors = 0;

    initial begin : program_image
        int i;
        for (i = 0; i < 1048576; i = i + 1) mem[i] = 8'h00;

        // reset vector: jmp 0000:0000
        poke(20'hFFFF0, 8'hEA); poke(20'hFFFF1, 8'h00); poke(20'hFFFF2, 8'h00);
        poke(20'hFFFF3, 8'h00); poke(20'hFFFF4, 8'h00);

        i = 0;
        // DOR: motor+irq enable, the byte the BIOS writes (3C)
        poke(i,8'hBA); poke(i+1,8'h94); poke(i+2,8'h00);  i=i+3; // mov dx,0094
        poke(i,8'hB0); poke(i+1,8'h3C);                     i=i+2; // mov al,3C
        poke(i,8'hEE);                                      i=i+1; // out dx,al
        // SPECIFY 03 BF 32
        poke(i,8'hBA); poke(i+1,8'h92); poke(i+2,8'h00);  i=i+3; // mov dx,0092
        for (int k = 0; k < 3; k++) begin
            automatic logic [7:0] v = (k==0) ? 8'h03 : (k==1) ? 8'hBF : 8'h32;
            poke(i,8'hB0); poke(i+1,v);                       i=i+2; // mov al,v
            poke(i,8'hEE);                                    i=i+1; // out dx,al
        end
        // RECALIBRATE x4: 07 <drv>
        for (int d = 0; d < 4; d++) begin
            poke(i,8'hB0); poke(i+1,8'h07);                   i=i+2; // mov al,07
            poke(i,8'hEE);                                    i=i+1; // out dx,al
            poke(i,8'hB0); poke(i+1,8'(d));                   i=i+2; // mov al,drv
            poke(i,8'hEE);                                    i=i+1; // out dx,al
        end
        // delay: mov cx,0xffff ; loop $
        poke(i,8'hB9); poke(i+1,8'hFF); poke(i+2,8'hFF);  i=i+3;
        poke(i,8'hE2); poke(i+1,8'hFE);                     i=i+2;
        // drain x4: SENSE, MSR, ST0, PCN -> [0400+d*4 ..]
        for (int d = 0; d < 4; d++) begin
            // mov dx,0092 ; mov al,08 ; out dx,al   (SENSE)
            poke(i,8'hBA); poke(i+1,8'h92); poke(i+2,8'h00); i=i+3;
            poke(i,8'hB0); poke(i+1,8'h08);                  i=i+2;
            poke(i,8'hEE);                                   i=i+1;
            // mov dx,0090 ; in al,dx ; mov [0400+d*4],al   (MSR)
            poke(i,8'hBA); poke(i+1,8'h90); poke(i+2,8'h00); i=i+3;
            poke(i,8'hEC);                                   i=i+1; // in al,dx
            poke(i,8'hA2); poke(i+1,8'(d*4)); poke(i+2,8'h04); i=i+3;
            // in al,dx again (MSR)
            poke(i,8'hEC);                                   i=i+1;
            poke(i,8'hA2); poke(i+1,8'(d*4+1)); poke(i+2,8'h04); i=i+3;
            // mov dx,0092 ; in al,dx ; store (ST0)
            poke(i,8'hBA); poke(i+1,8'h92); poke(i+2,8'h00); i=i+3;
            poke(i,8'hEC);                                   i=i+1;
            poke(i,8'hA2); poke(i+1,8'(d*4+2)); poke(i+2,8'h04); i=i+3;
            // in al,dx again (PCN)
            poke(i,8'hEC);                                   i=i+1;
            poke(i,8'hA2); poke(i+1,8'(d*4+3)); poke(i+2,8'h04); i=i+3;
        end
        // done marker + hlt
        poke(i,8'hC6); poke(i+1,8'h06); poke(i+2,8'h40);
        poke(i+3,8'h04); poke(i+4,8'h66);              i=i+5; // mov byte[0440],66
        poke(i,8'hEB); poke(i+1,8'hFE);                i=i+2; // jmp $
    end

    initial begin
        repeat (40) @(posedge clk);
        reset = 1'b0;
    end

    // any I/O write at all -> prove the CPU is executing
    logic io_wr_d2 = 1'b1;
    int   io_wr_seen = 0;
    always_ff @(posedge clk) begin
        io_wr_d2 <= io_wr_n;
        if (io_wr_n & ~io_wr_d2 && io_wr_seen < 40) begin
            io_wr_seen <= io_wr_seen + 1;
            $display("  %8t  OUT %04X <- %02X", $time,
                     io_wr_addr_q, cpu_data_bus);
        end
    end

    // wall clock + report
    initial begin
        automatic logic [7:0] want_msr [0:3] = '{8'hDE, 8'hDC, 8'hD8, 8'hD0};
        automatic logic [7:0] want_st0 [0:3] = '{8'h68, 8'h69, 8'h72, 8'h73};
        wait (mem[20'h00440] == 8'h66);
        $display("DONE.  0400+ bytes:");
        for (int d = 0; d < 4; d++) begin
            $display("  drv%0d: MSR %02X %02X  ST0 %02X  PCN %02X",
                     d, mem[20'h400+d*4], mem[20'h401+d*4],
                     mem[20'h402+d*4], mem[20'h403+d*4]);
            if (mem[20'h400+d*4] !== want_msr[d]
                || mem[20'h401+d*4] !== want_msr[d]
                || mem[20'h402+d*4] !== want_st0[d]
                || mem[20'h403+d*4] !== 8'h00) begin
                errors = errors + 1;
                $display("  FAIL drv%0d: want MSR %02X %02X ST0 %02X PCN 00",
                         d, want_msr[d], want_msr[d], want_st0[d]);
            end
        end
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL %0d", errors);
        $finish;
    end
    initial begin
        #200_000_000;
        $display("TIMEOUT: 0440=%02X", mem[20'h00440]);
        $display("  0400+: %02X %02X %02X %02X | %02X %02X %02X %02X",
                 mem[20'h400],mem[20'h401],mem[20'h402],mem[20'h403],
                 mem[20'h404],mem[20'h405],mem[20'h406],mem[20'h407]);
        $display("RESULT: FAIL timeout");
        $finish;
    end

endmodule
