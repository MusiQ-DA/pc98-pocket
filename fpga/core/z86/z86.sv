// z86 - A pipelined 16-bit x86 CPU.
//
// z86 uses a five stage pipeline to implement a 8086-compatible CPU with
// real-mode 80286 instructions (but no protected mode). For most instructions, it 
// z86 can finish one instruction per CPU cycle. Other more complex instructions 
// are micro-code driven and multi-cycle.
//
// To provide enough memory bandwidth, the memory interface is 32-bit wide,
// so it is possible to sustain one instruction per cycle, assuming 3 bytes
// per instruction.
//
// A cache module is included in the design, but caching is not implemented
// yet.
//
// - nand2mario, 7/2025

module z86 (
    input               clk,            // the bridge's gated CPU clock
    input               reset,
    input               clk_free,       // clk_chipset, ungated (z86_cache)
    input               ce,             // clk ticks at this clk_free edge
    input               cache_en,
    input               bios_shadow,    // RAM.sv bios_shadow_flag
    input               bios_protect,   // RAM.sv bios_protect_flag[1]

    // ---- sdram_mp port F (see z86_cache) --------------------------------
    output              f_req,
    output              f_we,
    output      [23:0]  f_addr,
    output      [ 3:0]  f_len,
    output      [15:0]  f_wdata0,
    output      [15:0]  f_wdata1,
    input               f_ack,
    input               f_rvalid,
    input       [15:0]  f_rdata,
    input               f_done,
    input               sn_v,           // port A write commits
    input       [23:0]  sn_addr,
    input       [ 3:0]  sn_len,

    // ---- Zet-shaped Wishbone master (see z86_wbif) ----------------------
    output      [19:1]  wb_adr_o,
    output      [ 1:0]  wb_sel_o,
    output              wb_we_o,
    output              wb_tga_o,       // 1 = I/O
    output      [15:0]  wb_dat_o,
    output              wb_stb_o,
    output              wb_cyc_o,
    input               wb_ack_i,
    input       [15:0]  wb_dat_i,

    // ---- interrupts, zet's protocol ------------------------------------
    // wb_tgc_i is the 8259's INTR. wb_tgc_o is the acknowledge pulse: the
    // bridge stops this clock on its rise, runs the two INTA bus cycles and
    // parks {8'h00, vector} on wb_dat_i before the next edge, which is when
    // the vector is taken.
    input               wb_tgc_i,
    output reg          wb_tgc_o,

    // ---- debug ---------------------------------------------------------
    output      [19:0]  pc,             // CS:IP of the fetch stream
    output      [15:0]  dbg_ds,
    // {FLAGS, IP, DS, SS, CS, ES, DI..AX} for the JTAG probe (PC-98 port)
    output     [223:0]  dbg_regs,
    output              dbg_halted,
    input               dbg_stop,       // JTAG: stop at an instruction boundary
    output              dbg_stopped,
    output      [15:0]  dbg_next_ip
);

import z86_package::*;

wire cpu_reset = reset;

// The debug register/memory ports of the standalone core are not wired.
wire        dbg_reg_wr  = 1'b0;
wire        dbg_reg_rd  = 1'b0;
wire [3:0]  dbg_reg_addr = 4'd0;
wire [15:0] dbg_reg_din = 16'h0;
wire [15:0] dbg_reg_dout;

// Interrupt vector handshake: decode raises inta_req once IF admitted the
// INTR; one wb_tgc_o pulse fetches the vector through the bridge.
wire        inta_req;
wire        intra;
reg  [7:0]  pic_vec_r;
reg         pic_vec_valid;
always @(posedge clk) begin
    if (reset) begin
        wb_tgc_o      <= 1'b0;
        pic_vec_valid <= 1'b0;
        pic_vec_r     <= 8'h00;
    end else begin
        wb_tgc_o <= 1'b0;
        if (wb_tgc_o) begin
            // The bridge held this clock until the vector was parked.
            pic_vec_r     <= wb_dat_i[7:0];
            pic_vec_valid <= 1'b1;
        end else if (inta_req && !pic_vec_valid && !wb_cyc_o && !wb_stb_o)
            // Only between bus cycles: the vector rides wb_dat_i, so an
            // acknowledge overlapping a read handed that read the vector
            // (POP AX after PUSHF came back 0020 under tb_z86_loop +irq).
            wb_tgc_o <= 1'b1;
        if (intra)
            pic_vec_valid <= 1'b0;
    end
end

// cache interface 
wire [19:0] ld_addr;
wire [127:0] ld_data;
wire ld_req, ld_ack;

wire rd_ready;
wire [15:0] rd_data;

wire ex_rd;      // read from EXECUTE
wire ex_rd_io;
wire [19:0] ex_rd_addr;  
wire ex_rd_word;

wire id_rd;      // read from DECODE
wire id_rd_io;
wire [19:0] id_rd_addr;
wire id_rd_word;

wire [19:0] wr_addr;   // write from EXECUTE
wire [15:0] wr_data;
wire wr_word;
wire wr_valid, wr_ready;
wire wr_io;

reg [19:0] dbg_reset_addr = 20'hFFFF0;
reg [15:0] dbg_reset_ip = 16'hFFF0;

// decode2 stage signals
wire id_ready, id_valid;
wire id_done;
wire [3:0] id_len;
wire [15:0] id_ip_after;
wire [6:0] id_prefix;
wire [7:0] id_op;
wire [7:0] id_modrm;
wire [31:0] id_disp;
wire [15:0] id_imm;
wire id_modrm_valid, id_disp_valid, id_imm_valid, id_disp8, id_disp16, id_disp32, id_imm8, id_imm16;
wire id_two_byte;
wire id_mem_read;
// wire [8:0] id_regread;
// wire id_two_cycles, id_base_index_disp;
id_instruction id_inst;

// execute
wire ex_ready /* verilator public */, ex_valid /* verilator public */;
wire [15:0] ex_ip_after /* verilator public */;
wire ex_mem_rd;
wire [15:0] ex_e_addr_val;
wire [19:0] ex_e_fulladdr;
wire [15:0] ex_e_segment;
wire [15:0] ex_g_val;
wire [7:0] ex_opcode /* verilator public */;
wire [16:0] ex_iclass;
wire [7:0] ex_modrm;
wire [15:0] ex_imm /* verilator public */;
wire [31:0] ex_disp;
wire ex_ucode_valid;
wire [8:0] ex_ucode_entry_next;
id_instruction ex_inst;
wire ex_reg;
wire [2:0] ex_reg1_raddr;
wire [15:0] ex_reg1_rdata;
wire [2:0] ex_reg2_raddr;
wire [15:0] ex_reg2_rdata;

// write-back
wire wb_reg_valid;
wire wb_reg2_valid;
wire wb_width, wb_width2;
wire [2:0] wb_reg;
wire [15:0] wb_data;
wire [2:0] wb_reg2;
wire [15:0] wb_data2;
wire [1:0] wb_flags_update_mask;
wire wb_flags_valid;
wire [15:0] wb_flags;
wire wb_seg_valid;
wire [1:0] wb_seg;
wire [15:0] wb_seg_data;
wire br_taken;
wire [19:0] br_target;
wire [15:0] br_new_cs;
wire [15:0] br_new_ip;

// Register file signals
wire [2:0] reg1_raddr;
wire [15:0] reg1_rdata;
wire [2:0] reg2_raddr;
wire [15:0] reg2_rdata;
wire [1:0] reg1_we;
wire [2:0] reg1_waddr;
wire [15:0] reg1_wdata;
wire [1:0] reg2_we;
wire [2:0] reg2_waddr;
wire [15:0] reg2_wdata;

// other registers
wire [15:0] reg_f;
wire [15:0] reg_ip;
wire [15:0] seg_ES;
wire [15:0] seg_CS;
wire [15:0] seg_SS;
wire [15:0] seg_DS;

reg [19:0] dbg_set_addr_val;
reg [15:0] dbg_set_ip_val;
reg dbg_set_addr;

// cache and memory interface serves FETCH (instruction loads), EXECUTE (memory read) and WRITE-BACK (memory write)
wire cache_busy;
z86_cache u_cache (
    .clk                (clk_free),
    .ce                 (ce),
    .reset              (reset),
    .cache_en           (cache_en),
    .bios_shadow        (bios_shadow),
    .bios_protect       (bios_protect),
    .f_req              (f_req),
    .f_we               (f_we),
    .f_addr             (f_addr),
    .f_len              (f_len),
    .f_wdata0           (f_wdata0),
    .f_wdata1           (f_wdata1),
    .f_ack              (f_ack),
    .f_rvalid           (f_rvalid),
    .f_rdata            (f_rdata),
    .f_done             (f_done),
    .sn_v               (sn_v),
    .sn_addr            (sn_addr),
    .sn_len             (sn_len),
    .busy               (cache_busy),
    .ld_addr            (ld_addr),
    .ld_req             (ld_req),
    .ld_ack             (ld_ack),
    .ld_data            (ld_data),

    .rd                 (ex_rd | id_rd),
    .rd_addr            (id_rd ? id_rd_addr : ex_rd_addr),
    .rd_io              (id_rd ? id_rd_io : ex_rd_io),
    .rd_ready           (rd_ready),
    .rd_data            (rd_data),
    .rd_word            (id_rd ? id_rd_word : ex_rd_word),

    .wr_addr            (wr_addr),
    .wr_valid           (wr_valid),
    .wr_ready           (wr_ready),
    .wr_data            (wr_data),
    .wr_word            (wr_word),
    .wr_io              (wr_io),

    .wb_adr_o           (wb_adr_o),
    .wb_sel_o           (wb_sel_o),
    .wb_we_o            (wb_we_o),
    .wb_tga_o           (wb_tga_o),
    .wb_dat_o           (wb_dat_o),
    .wb_stb_o           (wb_stb_o),
    .wb_cyc_o           (wb_cyc_o),
    .wb_ack_i           (wb_ack_i),
    .wb_dat_i           (wb_dat_i)
);

// register file
wire [127:0] dbg_gpr;
regfile u_regfile (
    .clk                (clk),
    .dbg_gpr            (dbg_gpr),
    .id_raddr1          (reg1_raddr), 
    .id_rdata1          (reg1_rdata),
    .id_raddr2          (reg2_raddr), 
    .id_rdata2          (reg2_rdata),
    .ex_raddr1          (ex_reg1_raddr), 
    .ex_rdata1          (ex_reg1_rdata),
    .ex_raddr2          (ex_reg2_raddr), 
    .ex_rdata2          (ex_reg2_rdata),

    .we1                (reg1_we), 
    .waddr1             (reg1_waddr), 
    .wdata1             (reg1_wdata),
    .we2                (reg2_we), 
    .waddr2             (reg2_waddr), 
    .wdata2             (reg2_wdata)
);

// z86 5-stage pipeline: 
//     FETCH -> DECODE1 -> DECODE2 -> EXECUTE -> WRITE-BACK

// FETCH: 32-byte instruction fetch buffer that does 16-byte loads from the cache. 
// DECODE1: calculate instruction length and decode into prefix, opcode, modrm, displacement, immediate
fetch u_fetch_decode1 (
    .clk                (clk), 
    .reset              (cpu_reset), 
    .reset_addr         (dbg_reset_addr),  // physical address to load after reset
    .reset_ip           (dbg_reset_ip),
    
    .ld_addr            (ld_addr), 
    .ld_req             (ld_req), 
    .ld_ack             (ld_ack), 
    .ld_data            (ld_data),
    .snoop_wr           (wr_valid & wr_ready & ~wr_io),
    .snoop_addr         (wr_addr),
    .snoop_word         (wr_word),

    .br_taken           (br_taken), 
    .br_target          (br_target), 
    .br_new_ip          (br_new_ip), 
    .br_new_cs          (br_new_cs),

    .id_ready           (id_ready), 
    .id_valid           (id_valid), 
    .id_len             (id_len), 
    .id_ip_after        (id_ip_after), 
    .id_prefix          (id_prefix), 
    .id_opcode          (id_op), 
    .id_modrm_valid     (id_modrm_valid), 
    .id_modrm           (id_modrm), 
    .id_disp            (id_disp), 
    .id_imm             (id_imm), 
    .id_disp_valid      (id_disp_valid), 
    .id_imm_valid       (id_imm_valid), 
    .id_disp8           (id_disp8), 
    .id_disp16          (id_disp16), 
    .id_disp32          (id_disp32),
    .id_imm8            (id_imm8), 
    .id_imm16           (id_imm16), 
    .id_two_byte        (id_two_byte),
    .id_inst            (id_inst)           // decoded instruction signals
);

// DECODE2: calculate effective address
decode u_decode2 (
    .clk                (clk), 
    .reset              (cpu_reset),

    .id_ready           (id_ready), 
    .id_valid           (id_valid),
    .id_len             (id_len), 
    .id_ip_after        (id_ip_after), 
    .id_prefix          (id_prefix), 
    .id_opcode          (id_op), 
    .id_modrm_valid     (id_modrm_valid), 
    .id_modrm           (id_modrm), 
    .id_disp            (id_disp), 
    .id_imm             (id_imm),
    .id_disp_valid      (id_disp_valid), 
    .id_imm_valid       (id_imm_valid), 
    .id_disp8           (id_disp8), 
    .id_disp16          (id_disp16), 
    .id_disp32          (id_disp32),
    .id_imm8            (id_imm8),
    .id_imm16           (id_imm16), 
    .id_two_byte        (id_two_byte),
    .id_inst            (id_inst),

    .br_taken           (br_taken),         // branch taken signal input

    .ex_ready           (ex_ready), 
    .ex_valid           (ex_valid), 
    .ex_ip_after        (ex_ip_after), 
    .ex_e_segment       (ex_e_segment),
    .ex_mem_rd          (ex_mem_rd), 
    .ex_e_addr_val      (ex_e_addr_val), 
    .ex_e_fulladdr      (ex_e_fulladdr), 
    .ex_g_val           (ex_g_val), 
    .ex_opcode          (ex_opcode), 
    .ex_iclass          (ex_iclass), 
    .ex_modrm           (ex_modrm), 
    .ex_imm             (ex_imm), 
    .ex_disp            (ex_disp),
    .ex_ucode_entry_next(ex_ucode_entry_next), 
    .ex_ucode_valid     (ex_ucode_valid), 
    .ex_inst            (ex_inst),

    .reg1_raddr         (reg1_raddr), 
    .reg1_rdata         (reg1_rdata),
    .reg2_raddr         (reg2_raddr), 
    .reg2_rdata         (reg2_rdata),

    .reg_f              (reg_f), 
    .reg_ip             (reg_ip), 
    .seg_ES             (seg_ES), 
    .seg_CS             (seg_CS), 
    .seg_SS             (seg_SS), 
    .seg_DS             (seg_DS),

    .rd                 (id_rd), 
    .rd_addr            (id_rd_addr), 
    .rd_io              (id_rd_io),
    .rd_ready           (rd_ready), 
    .rd_data            (rd_data), 
    .rd_word            (id_rd_word),

    .intr               (wb_tgc_i),
    .nmi                (1'b0),
    .pic_vec            (pic_vec_r),
    .pic_vec_valid      (pic_vec_valid),
    .inta_pending       (wb_tgc_o | pic_vec_valid),
    .dbg_stop           (dbg_stop),
    .dbg_stopped        (dbg_stopped),
    .dbg_next_ip        (dbg_next_ip),
    .inta_req           (inta_req),
    .bus_quiet          (~wr_valid & ~wb_cyc_o & ~wb_stb_o & ~cache_busy),
    .intra              (intra),

    .reg_rd             (dbg_reg_rd), 
    .reg_addr           (dbg_reg_addr),
    .reg_dout           (dbg_reg_dout)
);

// EXECUTE: execute the instruction, with hardwired logic as fast path and microcode for complex instructions
execute u_execute (
    .hlt_wake           (wb_tgc_i),
    .clk                (clk),          
    .halted             (dbg_halted),
    .reset              (cpu_reset),

    .ex_ready           (ex_ready), 
    .ex_valid           (ex_valid), 
    .ex_ip_after        (ex_ip_after), 
    .ex_e_segment       (ex_e_segment),
    .ex_mem_rd          (ex_mem_rd), 
    .ex_e_addr_val      (ex_e_addr_val), 
    .ex_e_fulladdr      (ex_e_fulladdr),
    .ex_g_val           (ex_g_val), 
    .ex_imm             (ex_imm),
    .ex_opcode          (ex_opcode), 
    .ex_iclass          (ex_iclass), 
    .ex_modrm           (ex_modrm), 
    .ex_disp            (ex_disp),
    .ex_ucode_entry_next(ex_ucode_entry_next), 
    .ex_ucode_valid     (ex_ucode_valid), 
    .ex_inst            (ex_inst),

    .br_taken           (br_taken), 
    .br_target          (br_target), 
    .br_new_cs          (br_new_cs), 
    .br_new_ip          (br_new_ip),

    .wb_reg_valid       (wb_reg_valid), 
    .wb_reg             (wb_reg), 
    .wb_data            (wb_data),
    .wb_width           (wb_width), 
    .wb_reg2_valid      (wb_reg2_valid), 
    .wb_reg2            (wb_reg2), 
    .wb_data2           (wb_data2),
    .wb_width2          (wb_width2),
    .wb_flags_valid     (wb_flags_valid), 
    .wb_flags           (wb_flags), 
    .wb_flags_update_mask(wb_flags_update_mask),
    .wb_seg_valid       (wb_seg_valid), 
    .wb_seg             (wb_seg), 
    .wb_seg_data        (wb_seg_data),

    .ex_reg             (ex_reg), 
    .reg1_raddr         (ex_reg1_raddr), 
    .reg1_rdata         (ex_reg1_rdata),
    .reg2_raddr         (ex_reg2_raddr), 
    .reg2_rdata         (ex_reg2_rdata),

    .reg_f              (reg_f), 
    .seg_ES             (seg_ES), 
    .seg_CS             (seg_CS), 
    .seg_SS             (seg_SS), 
    .seg_DS             (seg_DS),

    .rd                 (ex_rd), 
    .rd_ready           (rd_ready), 
    .rd_addr            (ex_rd_addr), 
    .rd_data            (rd_data), 
    .rd_word            (ex_rd_word),
    .rd_io              (ex_rd_io),
    .wr_valid           (wr_valid), 
    .wr_ready           (wr_ready), 
    .wr_addr            (wr_addr), 
    .wr_data            (wr_data), 
    .wr_word            (wr_word), 
    .wr_io              (wr_io),

    .reg_wr             (dbg_reg_wr), 
    .reg_addr           (dbg_reg_addr),
    .reg_din            (dbg_reg_din)
);

// WRITE-BACK: write the result to the register file or memory
write_back u_write_back (
    .clk                (clk), 
    .reset              (cpu_reset),

    .wb_reg_valid       (wb_reg_valid), 
    .wb_reg             (wb_reg), 
    .wb_data            (wb_data),
    .wb_width           (wb_width), 
    .wb_reg2_valid      (wb_reg2_valid), 
    .wb_reg2            (wb_reg2), 
    .wb_data2           (wb_data2),
    .wb_width2          (wb_width2),
    .wb_flags_valid     (wb_flags_valid), 
    .wb_flags           (wb_flags), 
    .wb_flags_update_mask(wb_flags_update_mask),
    .wb_seg_valid       (wb_seg_valid), 
    .wb_seg             (wb_seg), 
    .wb_seg_data        (wb_seg_data),

    .br_taken           (br_taken), 
    .br_target          (br_target), 
    .br_new_cs          (br_new_cs), 
    .br_new_ip          (br_new_ip),

    .reg1_we            (reg1_we), 
    .reg1_waddr         (reg1_waddr), 
    .reg1_wdata         (reg1_wdata),
    .reg2_we            (reg2_we), 
    .reg2_waddr         (reg2_waddr), 
    .reg2_wdata         (reg2_wdata),

    .reg_ip             (reg_ip), 
    .seg_ES             (seg_ES), 
    .seg_CS             (seg_CS), 
    .seg_SS             (seg_SS), 
    .seg_DS             (seg_DS),
    
    .reg_wr             (dbg_reg_wr), 
    .reg_addr           (dbg_reg_addr), 
    .reg_din            (dbg_reg_din)
);


assign pc     = {seg_CS, 4'h0} + reg_ip;
assign dbg_ds = seg_DS;
assign dbg_regs = {reg_f, reg_ip, seg_DS, seg_SS, seg_CS, seg_ES, dbg_gpr};

endmodule