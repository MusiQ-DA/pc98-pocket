//============================================================================
//  z86_cache -- z86's memory port with a real cache in front of the SDRAM.
//
//  Same z86-side ports as z86_wbif (ld_*, rd_*, wr_*), two ways out:
//
//   * CACHED: guest RAM 00000-9FFFF and the ROM image E8000-FFFFF. 16 KB,
//     direct mapped, 16-byte lines, tagged by the PHYSICAL address
//     {bios_shadow, addr} -- so the ITF bank at F8000 and the BIOS behind
//     it are different lines and the bank switch needs no flush. Misses
//     fill a whole line as ONE sixteen-beat burst on a dedicated sdram_mp
//     port (F); RAM.sv keeps one guest byte per SDRAM word, so a line is
//     exactly sixteen words. Writes are write-through, no allocate: the
//     line is updated on a hit and the store goes out on port F through a
//     one-entry write buffer, acknowledged to the core as soon as it is
//     buffered.
//   * UNCACHED: I/O, VRAM, the CG window, option ROMs, EMS -- everything
//     else -- runs as Zet-shaped Wishbone cycles through zet_cpu_bridge,
//     exactly the way z86_wbif did. The write buffer is drained before any
//     of them starts, so an OUT that starts a DMA never passes the store
//     that set up its buffer.
//
//  Coherency. The only other writers of the cached ranges reach the SDRAM
//  through port A (CPU-bus DMA, the ROM loader, the JTAG/firmware masters
//  on the chipset bus). Each port A write COMMIT (sdram_shim's a_wr_*) clears
//  the line it lands in. sdram_mp runs one transaction at a time, so a fill
//  either reads after the commit or its line is cleared by it -- there is
//  no window in between. The CPU's own stores update the line in place, and
//  the fetch unit already snoops them for its buffer.
//
//  Clocking. This runs on the FREE clk_chipset, not the bridge's gated CPU
//  clock, because port F and the snoop are pulses on the free clock. `ce`
//  is the bridge's zet_edge: high on the clk posedges where the gated clock
//  also ticks. Everything the core or the bridge samples is qualified by it,
//  which makes those paths behave exactly as if they ran on the gated clock:
//  a pulse from the core (rd) is taken only on a ce edge, a pulse to the
//  core (wr_ready) is held until a ce edge has seen it, and the Wishbone
//  master only moves on ce edges. Levels (rd_ready, ld_ack, the data) may
//  change on any edge; the core reads them on its next one.
//
//  I/O pacing. No blanket gap any more: the only consumer of z86_wbif's
//  IO_GAP was the ITF's PIT check (load counter 0, two JMP $+2, latch, and
//  expect the count to have moved), so the gap now applies only in front of
//  a PIT access (71/73/75/77h, 3FD9-3FDFh). OUT 5Fh is PC-98 software's own
//  I/O delay -- about 0.6 us on the machines that have it (np21w io/artic.c)
//  -- so the store is held that long before the core sees it complete.
//
//  SPDX-License-Identifier: Apache-2.0  (z86 is Apache-2.0)
//============================================================================

`default_nettype none

module z86_cache #(
    // Minimum gap, in clk, from the end of one I/O cycle to the start of a
    // PIT access (see above). 64 clk_chipset is ~1.5 us.
    parameter int PIT_GAP  = 64,
    // OUT 5Fh: ~0.6 us at 42.95 MHz.
    parameter int WAIT_5F  = 26,
    parameter int IDX_BITS = 10         // 1024 lines x 16 B = 16 KB
) (
    input  wire         clk,            // free clk_chipset
    input  wire         ce,             // the gated CPU clock ticks this edge
    input  wire         reset,          // CPU reset (synchronous)
    input  wire         cache_en,       // 0: everything takes the bus

    // ---- PC-98 map state ------------------------------------------------
    input  wire         bios_shadow,    // RAM.sv bios_shadow_flag
    input  wire         bios_protect,   // RAM.sv bios_protect_flag[1]

    // ---- z86 side: the `cache` module's ports ---------------------------
    input  wire [19:0]  ld_addr,
    input  wire         ld_req,         // toggle
    output reg          ld_ack,         // toggle, follows ld_req when done
    output reg [127:0]  ld_data,

    input  wire [19:0]  rd_addr,
    input  wire         rd,             // pulse
    output reg          rd_ready,       // idle or data ready
    output reg [15:0]   rd_data,
    input  wire         rd_io,
    input  wire         rd_word,

    input  wire [19:0]  wr_addr,
    input  wire         wr_valid,       // held until wr_ready
    output reg          wr_ready,       // pulse (held until a ce edge)
    input  wire [15:0]  wr_data,
    input  wire         wr_word,
    input  wire         wr_io,

    // ---- Wishbone master (zet_wb_master's shape) -----------------------
    output reg  [19:1]  wb_adr_o,
    output reg  [ 1:0]  wb_sel_o,
    output reg          wb_we_o,
    output reg          wb_tga_o,
    output reg  [15:0]  wb_dat_o,
    output reg          wb_stb_o,
    output wire         wb_cyc_o,
    input  wire         wb_ack_i,
    input  wire [15:0]  wb_dat_i,

    // ---- sdram_mp port F (word address, one guest byte per word) -------
    output reg          f_req,
    output reg          f_we,
    output reg  [23:0]  f_addr,
    output reg  [ 3:0]  f_len,
    output reg  [15:0]  f_wdata0,
    output reg  [15:0]  f_wdata1,
    input  wire         f_ack,
    input  wire         f_rvalid,
    input  wire [15:0]  f_rdata,
    input  wire         f_done,

    // ---- port A write commits (sdram_shim a_wr_*) ----------------------
    input  wire         sn_v,
    input  wire [23:0]  sn_addr,
    input  wire [ 3:0]  sn_len,

    output wire         busy            // something is buffered or in flight
);

    assign wb_cyc_o = wb_stb_o;

    localparam int LINES = 1 << IDX_BITS;
    localparam int TAG_BITS = 21 - 4 - IDX_BITS;

    // ------------------------------------------------------------------
    // Map
    // ------------------------------------------------------------------
    function automatic logic cacheable_a(input logic [19:0] a);
        cacheable_a = (a[19:16] < 4'hA) || (a[19:15] >= 5'b11101);
    endfunction
    function automatic logic rom_a(input logic [19:0] a);
        rom_a = (a[19:16] == 4'hF) || (a[19:15] == 5'b11101);
    endfunction
    // RAM.sv's latch_address for the cached ranges: the shadow bit only
    // ever applies to F8000-FFFFF.
    function automatic logic [20:0] phys_of(input logic [19:0] a, input logic sh);
        phys_of = {sh & (a[19:15] == 5'b11111), a};
    endfunction
    function automatic logic [IDX_BITS-1:0] idx_of(input logic [20:0] p);
        idx_of = p[4 +: IDX_BITS];
    endfunction
    function automatic logic [TAG_BITS-1:0] tag_of(input logic [20:0] p);
        tag_of = p[20 -: TAG_BITS];
    endfunction
    function automatic logic pit_port(input logic [15:0] a);
        pit_port = ((a & 16'hFFF9) == 16'h0071)
                || (a[15:3] == 13'h07FB && a[0]);   // 3FD9-3FDF odd
    endfunction

    // An access is cached when every byte of it is.
    wire [19:0] wr_a1 = wr_addr + 20'd1;
    wire [19:0] rd_a1 = rd_addr + 20'd1;
    wire [19:0] ld_a1 = ld_addr;
    wire wr_cached = cache_en && !wr_io && cacheable_a(wr_addr)
                  && (!wr_word || cacheable_a(wr_a1));

    // ------------------------------------------------------------------
    // Tag and data RAM (M10K): one read port each for the lookup, one write
    // port each. Tags are {valid, tag}.
    // ------------------------------------------------------------------
    reg  [TAG_BITS:0]    t_q;
    reg  [127:0]         d_q;

    reg                  t_we;
    reg  [IDX_BITS-1:0]  t_wa;
    reg  [TAG_BITS:0]    t_wd;
    reg                  d_we;
    reg  [IDX_BITS-1:0]  d_wa;
    reg  [15:0]          d_be;
    reg  [127:0]         d_wd;
    reg  [IDX_BITS-1:0]  look_idx;      // combinational: what to read this edge

    z86_cache_ram #(.AW(IDX_BITS), .BYTES(1), .BW(TAG_BITS + 1)) u_tags (
        .clk(clk), .we(t_we), .waddr(t_wa), .be(1'b1), .wdata(t_wd),
        .raddr(look_idx), .q(t_q));
    z86_cache_ram #(.AW(IDX_BITS), .BYTES(16), .BW(8)) u_data (
        .clk(clk), .we(d_we), .waddr(d_wa), .be(d_be), .wdata(d_wd),
        .raddr(look_idx), .q(d_q));

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    localparam [3:0] S_FLUSH = 4'd0,
                     S_IDLE  = 4'd1,
                     S_CMP   = 4'd2,    // lookup result on t_q/d_q
                     S_FILL  = 4'd3,    // waiting for a line fill
                     S_SERVE = 4'd4,    // serve from the filled line
                     S_WLD   = 4'd5,    // Wishbone line load
                     S_WRD1  = 4'd6,
                     S_WRD2  = 4'd7,
                     S_WWR1  = 4'd8,
                     S_WWR2  = 4'd9,
                     S_W5F   = 4'd10;   // OUT 5Fh delay
    reg  [3:0]  st;

    localparam [1:0] K_LD = 2'd0, K_RD = 2'd1, K_WR = 2'd2;
    reg  [1:0]  k;                      // what the lookup is for
    reg         part;                   // 0: byte at a, 1: byte at a+1 (straddle)
    reg  [19:0] c_a;                    // the access's address
    reg         c_word;
    reg  [15:0] c_wd;                   // write data
    reg  [7:0]  lo_byte;                // first half of a straddled read
    reg  [IDX_BITS-1:0] flush_i;

    // A read pulse is captured: rd may land while something else runs.
    reg         rd_pend;
    reg  [19:0] rd_a;
    reg         rd_isio, rd_isw;

    reg  [2:0]  ld_i;
    reg  [19:0] ld_base;
    reg  [7:0]  io_rec;                 // clk since the last I/O cycle, saturating
    reg  [4:0]  w5f;

    // Lookups the snoop raced: a tag write at the edge the lookup read, or
    // during the compare, of the same index makes it a miss.
    reg         kill;

    // ---- write buffer and port F --------------------------------------
    reg         wb_full;                // a store waits for port F
    reg  [20:0] wb_p0, wb_p1;           // physical address of each byte
    reg  [7:0]  wb_b0, wb_b1;
    reg         wb_two;                 // a word (two bytes)
    localparam [1:0] F_IDLE = 2'd0, F_REQ = 2'd1, F_RUN = 2'd2;
    reg  [1:0]  fs;
    reg         f_isfill;
    reg         f_wpart;                // second single-byte write of a split word
    reg  [3:0]  f_beat;
    reg  [127:0] lb;                    // the line being filled
    reg         fill_req;               // the FSM wants a fill of fill_p
    reg  [20:0] fill_p;
    reg         fill_live;              // its result is still wanted
    reg         fill_done;              // lb holds fill_p's line

    assign busy = wb_full || (fs != F_IDLE) || wb_stb_o;

    // Current lookup's address (the byte this part touches) and line.
    wire [19:0] c_ab  = part ? c_a + 20'd1 : c_a;
    wire [20:0] c_p   = phys_of(c_ab, bios_shadow);
    wire [3:0]  c_off = c_ab[3:0];
    // A word whose second byte is in the next line.
    wire        c_straddle = c_word && (c_a[3:0] == 4'hF);

    wire        hit = t_q[TAG_BITS] && (t_q[TAG_BITS-1:0] == tag_of(c_p)) && !kill;
    wire [127:0] line = (st == S_SERVE) ? lb : d_q;

    // ---- what the next edge's RAM read should address ------------------
    // IDLE picks the request (same priority as below), CMP a straddle's
    // second half. Anything else reads the current line again; harmless.
    // wr_ready is held until the ce edge the core takes it on; by the edge
    // after, wr_valid is already the core's next store (or low).
    wire wr_pend   = wr_valid && !wr_ready;
    wire ld_pend   = (ld_req ^ ld_ack);
    wire rd_now    = rd && ce;
    wire rd_any    = rd_pend || rd_now;
    wire [19:0] rd_cur_a  = rd_now ? rd_addr : rd_a;
    wire        rd_cur_io = rd_now ? rd_io   : rd_isio;
    wire        rd_cur_w  = rd_now ? rd_word : rd_isw;
    wire rd_cached = cache_en && !rd_cur_io && cacheable_a(rd_cur_a)
                  && (!rd_cur_w || cacheable_a(rd_cur_a + 20'd1));
    wire ld_cached = cache_en && cacheable_a(ld_addr);

    always @* begin
        look_idx = idx_of(c_p);
        if (st == S_IDLE) begin
            if (wr_pend)       look_idx = idx_of(phys_of(wr_addr, bios_shadow));
            else if (ld_pend)  look_idx = idx_of(phys_of(ld_addr, bios_shadow));
            else if (rd_any)   look_idx = idx_of(phys_of(rd_cur_a, bios_shadow));
        end else if ((st == S_CMP || st == S_SERVE) && c_straddle && !part)
            look_idx = idx_of(phys_of(c_a + 20'd1, bios_shadow));
    end

    // ---- snoop: clear the line(s) a port A write lands in ---------------
    // A two-word write can end in the next line; that one is cleared on the
    // following edge.
    reg         sn2_v;
    reg  [IDX_BITS-1:0] sn2_i;
    wire        sn_ours  = sn_v && (sn_addr[23:21] == 3'b000);
    wire [20:0] sn_end   = sn_addr[20:0] + {17'd0, sn_len};
    wire [IDX_BITS-1:0] sn_i0 = idx_of(sn_addr[20:0]);
    wire [IDX_BITS-1:0] sn_i1 = idx_of(sn_end);

    // Byte enables and data for a write hit at c_off (one or two bytes).
    wire        wr_both = c_word && !c_straddle && !part;
    wire [15:0] w_be   = wr_both ? (16'b11 << c_off) : (16'b1 << c_off);
    wire [7:0]  w_byte = part ? c_wd[15:8] : c_wd[7:0];
    wire [127:0] w_wd  = wr_both ? ({112'd0, c_wd} << (8 * c_off))
                                 : ({120'd0, w_byte} << (8 * c_off));

    function automatic [1:0] sel_of(input logic a0, input logic word);
        sel_of = word ? 2'b11 : (a0 ? 2'b10 : 2'b01);
    endfunction

    always @(posedge clk) begin
        t_we <= 1'b0;
        d_we <= 1'b0;
        if (ce) wr_ready <= 1'b0;
        if (io_rec != 8'hFF) io_rec <= io_rec + 8'd1;

        // ---------------- snoop (every edge, highest priority) ----------
        // t_we/d_we are registered: the write they carry lands on THIS edge,
        // and a read of the same index on this edge still sees the old
        // contents. A tag write racing the lookup makes it a miss; a data
        // write is never raced -- IDLE waits it out (below).
        kill <= t_we && (t_wa == look_idx);
        if (sn2_v) begin
            t_we <= 1'b1; t_wa <= sn2_i; t_wd <= '0;
            sn2_v <= 1'b0;
        end
        if (sn_ours) begin
            t_we <= 1'b1; t_wa <= sn_i0; t_wd <= '0;
            sn2_v <= (sn_i1 != sn_i0);
            sn2_i <= sn_i1;
        end

        // ---------------- port F engine (not reset by the CPU) ----------
        // A transaction already granted has to run to its done pulse, so
        // a CPU reset only drops the fill's result (fill_live).
        case (fs)
          F_IDLE:
            if (wb_full) begin
                f_req    <= 1'b1;
                f_we     <= 1'b1;
                f_isfill <= 1'b0;
                // A word goes as one two-word burst unless its halves are
                // not adjacent words in the same SDRAM column.
                if (!f_wpart) begin
                    f_addr   <= {3'b000, wb_p0};
                    f_wdata0 <= {8'h00, wb_b0};
                    f_wdata1 <= {8'h00, wb_b1};
                    f_len    <= (wb_two && wb_p1 == wb_p0 + 21'd1 && wb_p0[8:0] != 9'h1FF)
                              ? 4'd1 : 4'd0;
                end else begin
                    f_addr   <= {3'b000, wb_p1};
                    f_wdata0 <= {8'h00, wb_b1};
                    f_len    <= 4'd0;
                end
                fs <= F_REQ;
            end else if (fill_req) begin
                f_req    <= 1'b1;
                f_we     <= 1'b0;
                f_isfill <= 1'b1;
                f_addr   <= {3'b000, fill_p[20:4], 4'h0};
                f_len    <= 4'd15;
                f_beat   <= 4'd0;
                fill_req <= 1'b0;
                fs <= F_REQ;
            end
          F_REQ: if (f_ack) begin f_req <= 1'b0; fs <= F_RUN; end
          F_RUN: begin
            if (f_rvalid && f_isfill) begin
                lb[8*f_beat +: 8] <= f_rdata[7:0];
                f_beat <= f_beat + 4'd1;
            end
            if (f_done) begin
                fs <= F_IDLE;
                if (f_isfill) begin
                    if (fill_live) fill_done <= 1'b1;
                end else if (wb_two && !f_wpart && f_len == 4'd0) begin
                    f_wpart <= 1'b1;            // second byte next
                end else begin
                    f_wpart <= 1'b0;
                    wb_full <= 1'b0;
                end
            end
          end
          default: fs <= F_IDLE;
        endcase

        // ---------------- the request FSM -------------------------------
        if (rd_now) begin
            rd_pend  <= 1'b1;
            rd_a     <= rd_addr;
            rd_isio  <= rd_io;
            rd_isw   <= rd_word;
            rd_ready <= 1'b0;
        end

        if (reset) begin
            st        <= S_FLUSH;
            flush_i   <= '0;
            ld_ack    <= 1'b0;          // see fetch.sv's reset: both toggles to 0
            rd_ready  <= 1'b1;
            rd_pend   <= 1'b0;
            wr_ready  <= 1'b0;
            wb_stb_o  <= 1'b0;
            wb_we_o   <= 1'b0;
            wb_tga_o  <= 1'b0;
            wb_sel_o  <= 2'b00;
            wb_adr_o  <= 19'h0;
            wb_dat_o  <= 16'h0;
            fill_req  <= 1'b0;
            fill_live <= 1'b0;
            fill_done <= 1'b0;
            io_rec    <= 8'hFF;
        end else case (st)
          S_FLUSH: begin
            // Clear every tag. The snoop keeps the cache coherent on its
            // own; this only makes a reset a clean slate (and covers the
            // power-up contents in simulation).
            if (!sn_ours && !sn2_v) begin
                t_we <= 1'b1; t_wa <= flush_i; t_wd <= '0;
                flush_i <= flush_i + 1'b1;
                if (flush_i == IDX_BITS'(LINES - 1)) st <= S_IDLE;
            end
          end

          S_IDLE: begin
            part <= 1'b0;
            if (d_we) begin
                // a line patch lands this edge: look it up on the next
            end else if (wr_pend) begin
                if (wr_cached) begin
                    if (bios_protect && rom_a(wr_addr)) begin
                        // A protected ROM write goes nowhere.
                        wr_ready <= 1'b1;
                    end else if (!wb_full) begin
                        wb_full  <= 1'b1;
                        wb_p0    <= phys_of(wr_addr, bios_shadow);
                        wb_p1    <= phys_of(wr_a1, bios_shadow);
                        wb_b0    <= wr_data[7:0];
                        wb_b1    <= wr_data[15:8];
                        wb_two   <= wr_word;
                        f_wpart  <= 1'b0;
                        wr_ready <= 1'b1;
                        // ...and update the line if it is cached.
                        k      <= K_WR;
                        c_a    <= wr_addr;
                        c_word <= wr_word;
                        c_wd   <= wr_data;
                        st     <= S_CMP;
                    end
                end else if (ce && !busy
                             && !(wr_io && pit_port(wr_addr[15:0]) && io_rec < PIT_GAP[7:0])) begin
                    // Word at an odd address: the odd byte first, its data
                    // (the low byte of the word) in lane [15:8].
                    wb_adr_o <= wr_addr[19:1];
                    wb_sel_o <= sel_of(wr_addr[0], wr_word && !wr_addr[0]);
                    wb_dat_o <= wr_addr[0] ? {wr_data[7:0], 8'h00}
                              : (wr_word ? wr_data : {8'h00, wr_data[7:0]});
                    wb_we_o  <= 1'b1;
                    wb_tga_o <= wr_io;
                    wb_stb_o <= 1'b1;
                    st       <= S_WWR1;
                end
            end else if (ld_pend) begin
                if (ld_cached) begin
                    k    <= K_LD;
                    c_a  <= {ld_addr[19:4], 4'h0};
                    c_word <= 1'b0;
                    st   <= S_CMP;
                end else if (ce && !busy) begin
                    ld_base  <= {ld_addr[19:4], 4'b0};
                    ld_i     <= 3'd0;
                    wb_adr_o <= {ld_addr[19:4], 3'd0};
                    wb_sel_o <= 2'b11;
                    wb_we_o  <= 1'b0;
                    wb_tga_o <= 1'b0;
                    wb_stb_o <= 1'b1;
                    st       <= S_WLD;
                end
            end else if (rd_any) begin
                if (rd_cached) begin
                    k      <= K_RD;
                    c_a    <= rd_cur_a;
                    c_word <= rd_cur_w;
                    rd_a   <= rd_cur_a;
                    rd_isw <= rd_cur_w;
                    rd_isio <= 1'b0;
                    st     <= S_CMP;
                end else if (ce && !busy
                             && !(rd_cur_io && pit_port(rd_cur_a[15:0]) && io_rec < PIT_GAP[7:0])) begin
                    // rd may be this very edge's pulse: take its operands
                    // live, the capture above lands at the same edge.
                    wb_adr_o <= rd_cur_a >> 1;
                    wb_sel_o <= sel_of(rd_cur_a[0], rd_cur_w && !rd_cur_a[0]);
                    wb_we_o  <= 1'b0;
                    wb_tga_o <= rd_cur_io;
                    wb_stb_o <= 1'b1;
                    st       <= S_WRD1;
                end
            end
          end

          // ---------------- cached paths -------------------------------
          S_CMP, S_SERVE: begin
            if (st == S_CMP && !hit) begin
                if (k == K_WR) begin
                    // No allocate: the store is in the write buffer.
                    if (c_straddle && !part) begin part <= 1'b1; st <= S_CMP; end
                    else st <= S_IDLE;
                end else begin
                    fill_req  <= 1'b1;
                    fill_p    <= c_p;
                    fill_live <= 1'b1;
                    fill_done <= 1'b0;
                    st        <= S_FILL;
                end
            end else begin
                // A hit, or the line just filled (line = lb).
                case (k)
                  K_LD: begin
                    ld_data <= line;
                    ld_ack  <= ~ld_ack;
                    st      <= S_IDLE;
                  end
                  K_RD: begin
                    if (!part) begin
                        if (c_straddle) begin
                            lo_byte <= line[8*c_off +: 8];
                            part    <= 1'b1;
                            st      <= S_CMP;
                        end else begin
                            rd_data  <= c_word ? {line[8*(c_off+4'd1) +: 8], line[8*c_off +: 8]}
                                               : {8'h00, line[8*c_off +: 8]};
                            rd_pend  <= 1'b0;
                            rd_ready <= 1'b1;
                            st       <= S_IDLE;
                        end
                    end else begin
                        rd_data  <= {line[8*c_off +: 8], lo_byte};
                        rd_pend  <= 1'b0;
                        rd_ready <= 1'b1;
                        st       <= S_IDLE;
                    end
                  end
                  default: begin    // K_WR hit: patch the line
                    d_we <= 1'b1;
                    d_wa <= idx_of(c_p);
                    d_be <= w_be;
                    d_wd <= w_wd;
                    if (c_straddle && !part) begin part <= 1'b1; st <= S_CMP; end
                    else st <= S_IDLE;
                  end
                endcase
            end
          end

          S_FILL: if (fill_done) begin
            fill_done <= 1'b0;
            fill_live <= 1'b0;
            // Install the line unless a snoop got to it this very edge.
            d_we <= 1'b1; d_wa <= idx_of(fill_p); d_be <= 16'hFFFF; d_wd <= lb;
            if (!(sn_ours && (sn_i0 == idx_of(fill_p) || sn_i1 == idx_of(fill_p)))
                && !(sn2_v && sn2_i == idx_of(fill_p))) begin
                t_we <= 1'b1; t_wa <= idx_of(fill_p); t_wd <= {1'b1, tag_of(fill_p)};
            end
            st <= S_SERVE;
          end

          // ---------------- uncached: Wishbone, ce edges only ------------
          S_WLD: if (ce && wb_ack_i) begin
            ld_data[16*ld_i +: 16] <= wb_dat_i;
            if (ld_i == 3'd7) begin
                wb_stb_o <= 1'b0;
                ld_ack   <= ~ld_ack;
                st       <= S_IDLE;
            end else begin
                ld_i     <= ld_i + 3'd1;
                wb_adr_o <= {ld_base[19:4], ld_i + 3'd1};
            end
          end

          S_WRD1: if (ce && wb_ack_i) begin
            rd_pend <= 1'b0;
            if (wb_tga_o) io_rec <= 8'd0;
            if (rd_a[0]) begin
                rd_data[7:0] <= wb_dat_i[15:8];
                if (rd_isw) begin
                    wb_adr_o <= rd_a[19:1] + 19'd1;
                    wb_sel_o <= 2'b01;
                    st       <= S_WRD2;
                end else begin
                    rd_data[15:8] <= 8'h00;
                    wb_stb_o <= 1'b0;
                    rd_ready <= 1'b1;
                    st       <= S_IDLE;
                end
            end else begin
                rd_data  <= rd_isw ? wb_dat_i : {8'h00, wb_dat_i[7:0]};
                wb_stb_o <= 1'b0;
                rd_ready <= 1'b1;
                st       <= S_IDLE;
            end
          end

          S_WRD2: if (ce && wb_ack_i) begin
            if (wb_tga_o) io_rec <= 8'd0;
            rd_data[15:8] <= wb_dat_i[7:0];
            wb_stb_o <= 1'b0;
            rd_ready <= 1'b1;
            st       <= S_IDLE;
          end

          S_WWR1: if (ce && wb_ack_i) begin
            if (wb_tga_o) io_rec <= 8'd0;
            if (wr_addr[0] && wr_word) begin
                wb_adr_o <= wr_addr[19:1] + 19'd1;
                wb_sel_o <= 2'b01;
                wb_dat_o <= {8'h00, wr_data[15:8]};
                st       <= S_WWR2;
            end else if (wb_tga_o && wr_addr[15:0] == 16'h005F) begin
                wb_stb_o <= 1'b0;
                w5f      <= 5'd0;
                st       <= S_W5F;
            end else begin
                wb_stb_o <= 1'b0;
                wr_ready <= 1'b1;
                st       <= S_IDLE;
            end
          end

          S_WWR2: if (ce && wb_ack_i) begin
            if (wb_tga_o) io_rec <= 8'd0;
            wb_stb_o <= 1'b0;
            wr_ready <= 1'b1;
            st       <= S_IDLE;
          end

          S_W5F: begin
            w5f <= w5f + 5'd1;
            if (w5f == 5'(WAIT_5F - 1)) begin
                wr_ready <= 1'b1;
                st       <= S_IDLE;
            end
          end

          default: st <= S_IDLE;
        endcase
    end

    // Power-up state for what the CPU reset does not touch.
    initial begin
        fs = F_IDLE; f_req = 1'b0; f_we = 1'b0; wb_full = 1'b0; f_wpart = 1'b0;
        sn2_v = 1'b0; st = S_FLUSH; flush_i = '0; wr_ready = 1'b0;
    end

    wire _unused = &{1'b0, ld_a1, rd_a1};

endmodule

// Simple dual-port M10K: one write port with byte enables, one registered
// read port. Written the way Quartus's RAM template has it, as a module of
// its own, so inference sees nothing but the memory. Starts all-zero (the
// tags' valid bits).
module z86_cache_ram #(
    parameter int AW = 10,
    parameter int BYTES = 16,
    parameter int BW = 8
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [AW-1:0]         waddr,
    input  wire [BYTES-1:0]      be,
    input  wire [BYTES*BW-1:0]   wdata,
    input  wire [AW-1:0]         raddr,
    output reg  [BYTES*BW-1:0]   q
);
    (* ramstyle = "M10K, no_rw_check" *)
    reg [BYTES-1:0][BW-1:0] ram [0:(1<<AW)-1];
    integer i;
    initial for (i = 0; i < (1 << AW); i = i + 1) ram[i] = '0;
    always @(posedge clk) begin
        if (we)
            for (int b = 0; b < BYTES; b++)
                if (be[b]) ram[waddr][b] <= wdata[b*BW +: BW];
        q <= ram[raddr];
    end
endmodule

`default_nettype wire
