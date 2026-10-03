//============================================================================
//
//  next186_cpu_bridge -- put the vendored Next186 (freecores/OpenCores
//  80186-class core) on the i8288 world (8-bit bus), the same downstream
//  contract v30_cpu_bridge and zet_cpu_bridge drive.
//
//  EXPERIMENTAL (branch next186-cpu). Next186 is a real 80186: it knows
//  PUSHI/ENTER/LEAVE/PUSHA/IMUL-imm/INS/OUTS, so the ITF's F9476 `push imm16`
//  that killed the i8088 is legal for it. It is NOT a V30: no NEC extensions
//  (BRKEM, the flag quirks), and it makes no attempt at cycle accuracy.
//  nuV30 stays the shipping CPU.
//
//  THE UPSTREAM CONTRACT (core/next186/INTEGRATION_NOTES.md has the long
//  version; it was measured off the vendored RTL, not assumed):
//
//   * The unit is Next186_CPU + BIU186_32bSync_2T_DelayRead on ONE shared
//     clock enable (CPU.CE = CE186 & CE, BIU.CE = CE). There is NO
//     handshake, ready, or ack anywhere: every output is a combinational
//     function of CE-ticked registers, so the ONLY legal stall is
//     withholding CE ticks, which freezes the unit mid-state with all
//     comb outputs (requests included) held stable. The bridge throttles
//     time, not a signal.
//   * Memory -- instruction fetch and data both -- reaches the bus as a
//     32-bit fixed-1-tick-latency "SRAM" port: RAM_MREQ/RAM_RD/RAM_WR/
//     RAM_ADDR(dword)/RAM_WMASK/RAM_DOUT/RAM_DIN. A request visible during
//     interval N is REGISTERED by the tick ending N (rdi<=iread, STATE
//     advances); its read data must sit on RAM_DIN through interval N+1 and
//     is latched at the tick ending N+1 (queue[rpos]<=RAM_DIN on rdi, or
//     the CPU's DIN sample in a data-read STATE3, or exdata for a split).
//     So every request costs two unit ticks -- one to take it, one to
//     deliver -- and the bridge keeps RAM_DIN parked for the response.
//   * I/O (IORQ = &EAC) and the interrupt-acknowledge pulse (INTA) bypass
//     the BIU entirely. They matter only on intervals where CE186=1 -- the
//     tick about to land retires a CPU stage that samples DIN through the
//     PORT_DIN side of the INPORT mux ((IORQ|INTA) ? PORT_DIN : biu_dout).
//     A byte IN always reads DIN[7:0], so the port word mirrors {b,b};
//     byte OUT always drives DOUT[7:0] (soc_ref/sample_system.v reads
//     DOUT[0] at the odd port). INTA is a single comb pulse inside the
//     intr micro-stage: the i8259 needs the metal's DOUBLE acknowledge --
//     two BS_INTA byte cycles -- and the vector rides back as {8'h00,vec}.
//   * SRST<=RST is SYNCHRONOUS and needs a CE186&CE tick to land, but
//     CE186 only ticks once the queue is ~3 dwords full -- which takes
//     real serviced fetches. So reset is stretched internally until the
//     first CE186&CE tick actually arrives.
//   * ADDR/IADDR are 21 bits (the A20 commit); ad_out is 20 -> drop bit 20.
//
//  THE BRIDGE'S ANSWER:
//
//   * unit CE free-runs at the cpu_ce_posedge train rate while no request
//     is pending (the same pacing the 8288 logic and the speed generator
//     assume), plus every clk during reset so SRST can latch.
//   * When an interval announces work -- RAM_MREQ, or CE186&(IORQ|INTA) --
//     CE stops BEFORE that interval's first tick and the byte engine below
//     serves it: the dword as 4 sequential byte cycles (or 2 word_1cyc
//     bursts where the SDRAM answers), the WMASK lanes only on writes;
//     the port access as 1-2 byte cycles through the np21w io_term table;
//     the INTA as the double-acknowledge pair. Then ONE unit tick is
//     emitted, ending the interval: the BIU registers the request and,
//     on the same edge, latches whatever response was parked from the
//     interval before. The just-fetched dword is parked on RAM_DIN right
//     there, to be consumed by the tick that ends the next interval.
//   * Both requests of a shared interval (a prefetch iread in the same
//     STATE3/STATE1 interval that retires an I/O stage) are served, memory
//     first -- the concurrent memory request in an I/O stage is never a
//     data access (MREQ=0 on the CPU side there), so order cannot matter.
//
//  Byte-engine pacing is the CONSERVATIVE v30 grid: >= 3 posedge-CE ticks
//  of status, complete on processor_ready && !address_enable_n, one full
//  passive posedge of gap, re-arm through B_IDLE. The shorter grid that
//  zet_cpu_bridge runs is a later experiment, not the first landing.
//
//  SPDX-License-Identifier: LGPL-2.1-or-later (Next186 core) /
//  GPL-2.0-or-later (bridge, matching v30_cpu_bridge's bridge-side terms)
//
//============================================================================

`default_nettype none

module next186_cpu_bridge (

    // chipset domain
    input  wire         clk,                // clk_chipset
    input  wire         cpu_ce_posedge,     // the CE train the 8288 runs on
    input  wire         reset,              // reset_cpu

    // interrupt pins, as the chipset drives them
    input  wire         intr,               // interrupt_to_cpu (level)
    input  wire         nmi,                // edge-detected inside the CPU

    // the CPU-side pins, as the chipset sees them
    output reg   [2:0]  processor_status,   // S2-S0 to the i8288 / arbiter
    output reg   [19:0] ad_out,             // to the ALE address latch
    output reg   [7:0]  cpu_data_bus,       // the addressed write lane
    output wire         lock_n,

    // the 16-bit SDRAM two-lane path -- same contract as the other bridges
    input  wire         analog_mode,
    output reg          word_access,
    output reg   [7:0]  cpu_data_bus_hi,
    input  wire  [7:0]  data_bus_hi,

    input  wire  [7:0]  data_bus,
    input  wire         processor_ready,
    input  wire         address_enable_n,
    input  wire         pause_core,

    output wire         biu_done,           // one clk pulse per served interval

    // probe taps: what core_top aliases onto the V30's slot-0x18/0x1c view
    output wire  [19:0] dbg_pc,             // IADDR, the fetch cursor
    output wire  [15:0] dbg_din,            // the CPU's DIN pin
    output wire  [15:0] dbg
);

    localparam [2:0] BS_INTA = 3'b000;
    localparam [2:0] BS_IOR  = 3'b001;
    localparam [2:0] BS_IOW  = 3'b010;
    localparam [2:0] BS_HALT = 3'b011;
    localparam [2:0] BS_CODE = 3'b100;
    localparam [2:0] BS_MEMR = 3'b101;
    localparam [2:0] BS_MEMW = 3'b110;
    localparam [2:0] BS_PASV = 3'b111;

    // ------------------------------------------------------------------------
    // the unit: CPU + BIU on one gated CE, DIN mux, and the WSEL fix
    // upstream left dangling (it drives DSWAP, the odd-byte write swap).
    // ------------------------------------------------------------------------

    wire        ce186;          // BIU's CPU-tick gate for THIS interval
    wire        u_halt, u_lock, u_inta, u_iorq, u_mreq, u_wr, u_word;
    wire [20:0] u_addr, u_iaddr;
    wire [15:0] u_dout;
    wire [47:0] u_instr;
    wire  [2:0] u_isize;
    wire        u_ifetch, u_flush;
    wire [31:0] u_ram_dout;
    wire [18:0] u_ram_addr;
    wire        u_ram_mreq, u_ram_rd, u_ram_wr;
    wire  [3:0] u_ram_wmask;
    wire [15:0] biu_dout;

    reg  [31:0] ram_din;        // the parked response dword
    reg  [15:0] port_din;       // the parked I/O-read word / inta vector
    reg         unit_ce;
    wire        unit_rst;
    wire        pre_reset;      // junk-stage window: suppress CPU bus effects

    wire [15:0] cpu_din = (u_iorq | u_inta) ? port_din : biu_dout;

    Next186_CPU u_cpu (
        .ADDR   (u_addr),
        .DIN    (cpu_din),
        .DOUT   (u_dout),
        .CLK    (clk),
        .CE     (ce186 & unit_ce),
        .INTR   (intr),
        .NMI    (nmi),
        .RST    (unit_rst),
        .MREQ   (u_mreq),
        .IORQ   (u_iorq),
        .INTA   (u_inta),
        .WR     (u_wr),
        .WORD   (u_word),
        .LOCK   (u_lock),
        .IADDR  (u_iaddr),
        .INSTR  (u_instr),
        .IFETCH (u_ifetch),
        .FLUSH  (u_flush),
        .ISIZE  (u_isize),
        .HALT   (u_halt)
    );

    BIU186_32bSync_2T_DelayRead u_biu (
        .CLK        (clk),
        .INSTR      (u_instr),
        .ISIZE      (u_isize),
        .IFETCH     (u_ifetch),
        .FLUSH      (u_flush),
        .MREQ       (u_mreq & ~pre_reset),   // junk stages never reach the bus
        .WR         (u_wr),
        .WORD       (u_word),
        .ADDR       (u_addr),
        .IADDR      (u_iaddr),
        .CE186      (ce186),
        .RAM_DIN    (ram_din),
        .RAM_DOUT   (u_ram_dout),
        .RAM_ADDR   (u_ram_addr),
        .RAM_MREQ   (u_ram_mreq),
        .RAM_WMASK  (u_ram_wmask),
        .DOUT       (biu_dout),
        .DIN        (u_dout),
        .CE         (unit_ce),
        .data_bound (),
        .WSEL       ({~u_addr[0], u_addr[0]}),
        .RAM_RD     (u_ram_rd),
        .RAM_WR     (u_ram_wr)
    );

    assign lock_n  = 1'b1;      // LOCK is never presented; see the notes

    assign dbg_pc  = u_iaddr[19:0];   // drop A20, same as ad_out
    assign dbg_din = cpu_din;

    // ------------------------------------------------------------------------
    // the reset stretch: RST must be high across a CE186&CE tick for SRST to
    // latch, and CE186 ticks only exist once the queue has been filled by
    // real serviced fetches -- which can take longer than the reset pulse
    // (the train is dead through the chipset reset that holds reset_cpu).
    //
    // Two windows matter:
    //   * unit_rst stays up until the FIRST CE186&CE tick lands -- that tick
    //     samples RST into SRST. Before it, whatever junk ICODE/STAGE powered
    //     up in still EXECUTES (the else branch runs the decoded stage while
    //     it samples RST) -- on the bench that junk retires a store to 0000h.
    //   * pre_reset covers BOTH pre-SRST intervals (the junk stage and the
    //     following one whose tick finally takes the SRST branch) -- during
    //     it the BIU's MREQ pin and the port/INTA service are masked, so the
    //     junk never reaches the bus. Prefetch (internal iread) keeps
    //     running -- the queue fill is what produces CE186 ticks at all.
    // ------------------------------------------------------------------------
    reg [1:0] tick_cnt = 2'd0;    // CE186&CE ticks since reset, saturating
    always @(posedge clk) begin
        if (reset) tick_cnt <= 2'd0;
        else if (unit_ce && ce186 && (tick_cnt != 2'd3))
            tick_cnt <= tick_cnt + 2'd1;
    end
    wire unit_rst_w = reset | (tick_cnt == 2'd0);
    assign pre_reset = reset | (tick_cnt < 2'd2);
    assign unit_rst  = unit_rst_w;

    // ------------------------------------------------------------------------
    // the stall watch: the CURRENT unit interval wants bus service
    // ------------------------------------------------------------------------
    //
    // RAM_MREQ covers iread (prefetch) + RAM_RD + RAM_WR; a prefetch is a
    // code read, the rest data. The I/O/INTA term gates on CE186 -- only a
    // CPU-retiring tick samples DIN, and servicing a stage early would run
    // its port byte again at the real retiring tick (a doubled OUT is a
    // double-edge on the PIT's byte pointer, so this gate is the fix, not
    // a nicety -- the bench proved it: prefetch intervals during an IORQ
    // stage each ran the write once). INTA is comb-stable inside its stage,
    // so this cannot miss it: no tick of this interval lands until service
    // completes. pre_reset masks the powered-up junk stages entirely.
    wire req_mem = u_ram_mreq;
    wire req_io  = ce186 && (u_iorq || u_inta) && !pre_reset;
    wire stall   = req_mem || req_io;

    // ------------------------------------------------------------------------
    // the service descriptor, latched when the stall is taken
    // ------------------------------------------------------------------------
    //
    // The unit is frozen for the whole service (no tick lands), so the comb
    // outputs are stable -- the latch is a snapshot for clarity, not a race
    // fix.
    reg        sv_mem;          // a dword moves this interval
    reg        sv_mem_wr;       // RAM_WR (else read: RAM_RD or prefetch)
    reg        sv_code;         // prefetch (iread) -- BS_CODE coloring
    reg [19:0] sv_maddr;        // dword base byte address, A20 already dropped
    reg [31:0] sv_mdata;
    reg  [3:0] sv_mmask;
    reg        sv_io;           // a port access retires this interval
    reg        sv_inta;         // ... or an INTA pair
    reg        sv_io_wr;
    reg        sv_io_word;
    reg [19:0] sv_ioaddr;
    reg [15:0] sv_iodata;
    reg  [2:0] sv_io_term;      // np21w ioterminate class (word access only)
    reg  [1:0] sv_io_n;         // bytes the io side must run

    // ------------------------------------------------------------------------
    // the byte engine -- v30_cpu_bridge's conservative grid, generalised to
    // "a list of byte/word steps": the mem segment is the dword's lanes (up
    // to 4 slots, word-merged pairs where the SDRAM answers, unmasked lanes
    // skipped on writes), the io segment the port's 1-2 bytes or the INTA
    // pair. (seg,lane) names the step in flight; all step parameters are
    // combinational off the descriptor, which is frozen for the service.
    // ------------------------------------------------------------------------

    localparam [1:0] S_IDLE = 2'd0;   // free-run: unit ticks at train rate
    localparam [1:0] S_RUN  = 2'd1;   // the byte engine owns the interval
    localparam [1:0] S_TICK = 2'd2;   // emit the one interval-ending tick

    localparam [1:0] B_IDLE = 2'd0;   // nothing to do / waiting for the bus
    localparam [1:0] B_CMD  = 2'd1;   // status up: ALE, command, wait ready
    localparam [1:0] B_GAP  = 2'd2;   // status down, letting the 8288 re-arm

    reg  [1:0] state;
    reg  [1:0] bstate;
    reg        seg;            // 0 = the dword, 1 = the port/INTA pair
    reg  [2:0] lane;           // byte slot: 0..3 in the dword, 0..1 in io
    reg  [2:0] t_cnt;          // posedge-CE edges since this byte went up
    reg  [1:0] gap_cnt;
    reg        biu_done_r;

    reg [31:0] rd_dword;       // the assembled fetch/read dword
    reg [15:0] rd_port;        // the io read's {hi,lo} as bytes landed
    reg  [7:0] int_vector;

`include "pc98_sdram_map.svh"

    // Word-I/O termination -- the same np21w io/iocore.c table both other
    // bridges carry.
    localparam [2:0] TERM_NONE   = 3'd0;
    localparam [2:0] TERM_WORD   = 3'd1;
    localparam [2:0] TERM_ACTIVE = 3'd2;
    localparam [2:0] TERM_PLUS   = 3'd3;
    localparam [2:0] TERM_MINUS  = 3'd4;
    localparam [2:0] TERM_EXT08  = 3'd5;

    // Same np21w table both other bridges carry (io/iocore.c ioterminate[]).
    // Only even low ports classify; a word access anywhere else runs its two
    // bytes, and so does any odd port -- the second byte is then addr+1, the
    // even byte of the pair the odd address splits across.
    function automatic logic [2:0] io_term(input logic [19:0] a);
        if ((a[0] == 1'b0) && (a[11:10] == 2'b00))
        case (a[7:0])
          8'hf2, 8'hf6:              io_term = TERM_WORD;
          8'hd0, 8'hd2, 8'hd4, 8'hd6, 8'hd8, 8'hdc, 8'hde:
                                     io_term = TERM_ACTIVE;
          8'h30, 8'h32, 8'h34, 8'h36,
          8'h40, 8'h42, 8'h44, 8'h46:
                                     io_term = TERM_PLUS;
          8'h60, 8'h62, 8'h64, 8'h68, 8'h6a, 8'h6c,
          8'h70, 8'h72, 8'h74, 8'h76, 8'h7a, 8'h7c,
          8'ha0, 8'ha2, 8'ha4, 8'ha6, 8'ha8, 8'hac:
                                     io_term = TERM_MINUS;
          8'h20, 8'h22, 8'h24, 8'h26: io_term = TERM_EXT08;
          default:                   io_term = TERM_NONE;
        endcase
        else io_term = TERM_NONE;
    endfunction

    // ---- the current step, combinational off (seg, lane, descriptor) ------
    reg        st_valid;        // a real bus cycle for this slot
    reg  [2:0] st_bs;
    reg [19:0] st_addr;
    reg  [7:0] st_lo, st_hi;    // write data lanes
    reg        st_word1;        // run as one word_1cyc
    reg        st_pasv;         // TERM_WORD: run the slot passive
    reg  [2:0] st_adv;          // lane advance after this step

    wire [19:0] sv_maddr_lane = sv_maddr + {17'd0, lane[1:0]};

    always @* begin
        st_valid = 1'b0;
        st_bs    = BS_PASV;
        st_addr  = 20'h0;
        st_lo    = 8'h00;
        st_hi    = 8'h00;
        st_word1 = 1'b0;
        st_pasv  = 1'b0;
        st_adv   = 3'd1;

        if (seg == 1'b0) begin
            // the dword: reads touch all four lanes, writes the masked ones
            if (sv_mem && (lane < 3'd4)) begin
                if (sv_mem_wr) begin
                    if (sv_mmask[lane[1:0]]) begin
                        st_valid = 1'b1;
                        st_bs    = BS_MEMW;
                        st_addr  = sv_maddr_lane;
                        st_lo    = sv_mdata[{lane[1:0], 3'b000} +: 8];
                        // an aligned masked PAIR can go as one burst
                        if ((lane[1:0] != 2'd3) && ~lane[0]
                            && sv_mmask[lane[1:0] + 2'd1]
                            && pc98_sdram_hits(sv_maddr_lane, analog_mode)) begin
                            st_word1 = 1'b1;
                            st_hi    = sv_mdata[{lane[1:0], 3'b000} + 8 +: 8];
                            st_adv   = 3'd2;
                        end
                    end
                    // else: unmasked lane -- a bubble, lane advances in FSM
                end else begin
                    st_valid = 1'b1;
                    st_bs    = sv_code ? BS_CODE : BS_MEMR;
                    st_addr  = sv_maddr_lane;
                    if (~lane[0] && pc98_sdram_hits(sv_maddr_lane, analog_mode)) begin
                        st_word1 = 1'b1;
                        st_adv   = 3'd2;
                    end
                end
            end
        end else begin
            if (sv_inta) begin
                st_valid = (lane < 3'd2);
                st_bs    = BS_INTA;
                st_addr  = 20'h0;
            end else if (sv_io) begin
                st_valid = (lane < {1'b0, sv_io_n});
                st_bs    = sv_io_wr ? BS_IOW : BS_IOR;
                st_addr  = sv_ioaddr + {19'd0, lane[0]};
                st_lo    = lane[0] ? sv_iodata[15:8] : sv_iodata[7:0];
                st_pasv  = (sv_io_term == TERM_WORD);
            end
        end
    end

    wire  [2:0] io_n_total = sv_inta ? 3'd2
                          : (sv_io ? {1'b0, sv_io_n} : 3'd0);

    // Is there a bus step after the one in flight? On seg 0 the io segment
    // still counts; on seg 1 only its own length remains.
    wire        mem_more = sv_mem
                        && (sv_mem_wr ? (|(sv_mmask >> (lane + st_adv)))
                                      : ((lane + st_adv) < 3'd4));
    wire        io_more  = (lane + st_adv) < io_n_total;
    wire        step_last = (seg == 1'b0) ? !mem_more && (io_n_total == 3'd0)
                                        : !io_more;
    wire        seg_done  = (seg == 1'b0) ? !mem_more : 1'b1;

    wire bus_ours = (address_enable_n == 1'b0);
    wire cur_read = (st_bs == BS_INTA) || (st_bs == BS_IOR)
                 || (st_bs == BS_CODE) || (st_bs == BS_MEMR);

    assign biu_done = biu_done_r;

    // ------------------------------------------------------------------------
    // the tick gate: free-run while idle, one bridge-emitted tick per service
    // ------------------------------------------------------------------------
    wire idle_tick = (state == S_IDLE)
                  && (cpu_ce_posedge || reset)     // SRST is synchronous
                  && !stall && !pause_core;

    always @* begin
        unit_ce = idle_tick || ((state == S_TICK) && !pause_core);
    end

    // ------------------------------------------------------------------------
    // the sequencer
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state            <= S_IDLE;
            bstate           <= B_IDLE;
            seg              <= 1'b0;
            lane             <= 3'd0;
            t_cnt            <= 3'd0;
            gap_cnt          <= 2'd0;
            rd_dword         <= 32'h0;
            rd_port          <= 16'h0;
            int_vector       <= 8'h00;
            ram_din          <= 32'h0;
            port_din         <= 16'h0000;
            biu_done_r       <= 1'b0;
            sv_mem           <= 1'b0;
            sv_mem_wr        <= 1'b0;
            sv_code          <= 1'b0;
            sv_maddr         <= 20'h0;
            sv_mdata         <= 32'h0;
            sv_mmask         <= 4'h0;
            sv_io            <= 1'b0;
            sv_inta          <= 1'b0;
            sv_io_wr         <= 1'b0;
            sv_io_word       <= 1'b0;
            sv_ioaddr        <= 20'h0;
            sv_iodata        <= 16'h0;
            sv_io_term       <= TERM_NONE;
            sv_io_n          <= 2'd0;
            processor_status <= BS_PASV;
            ad_out           <= 20'h0;
            cpu_data_bus     <= 8'h00;
            word_access      <= 1'b0;
            cpu_data_bus_hi  <= 8'h00;
        end else begin
            biu_done_r <= 1'b0;
            case (state)
              // ------------- free-run: the unit ticks at the train rate ----
              S_IDLE: begin
                if (stall && !pause_core) begin
                    // snapshot the whole interval's work, then serve it
                    sv_mem    <= req_mem;
                    sv_mem_wr <= u_ram_wr;
                    sv_code   <= u_ram_mreq && !u_ram_rd && !u_ram_wr;
                    sv_maddr  <= {u_ram_addr[17:0], 2'b00};
                    sv_mdata  <= u_ram_dout;
                    sv_mmask  <= u_ram_wmask;
                    // port/INTA service ONLY when this interval's tick
                    // retires a CPU stage (ce186) -- the comb IORQ/INTA is
                    // up during every prefetch interval of the stage too.
                    sv_io     <= req_io && u_iorq && !u_inta;
                    sv_inta   <= req_io && u_inta;
                    sv_io_wr  <= u_wr;
                    sv_io_word<= u_word;
                    sv_ioaddr <= {4'h0, u_addr[15:0]};
                    sv_iodata <= u_dout;
                    sv_io_term<= io_term({4'h0, u_addr[15:0]});
                    sv_io_n   <= u_inta              ? 2'd2
                               : !u_word             ? 2'd1
                               : (u_addr[0]
                                  || (io_term({4'h0, u_addr[15:0]})
                                      == TERM_NONE)) ? 2'd2
                                                     : 2'd1;
                    seg       <= 1'b0;
                    lane      <= 3'd0;
                    bstate    <= B_IDLE;
                    state     <= S_RUN;
                end
                // no stall: idle_tick already gave the interval its train tick
              end

              // ------------- the byte engine walks the step list ------------
              S_RUN: begin
                case (bstate)
                  B_IDLE: begin
                    if (st_valid && bus_ours && !pause_core) begin
                        processor_status <= st_pasv ? BS_PASV : st_bs;
                        ad_out           <= st_addr;
                        cpu_data_bus     <= st_lo;
                        word_access      <= st_word1;
                        cpu_data_bus_hi  <= st_hi;
                        t_cnt            <= 3'd0;
                        bstate           <= B_CMD;
                    end else if (!st_valid) begin
                        // an unmasked write lane, or a segment boundary
                        if (seg == 1'b0 && !seg_done) begin
                            lane <= lane + 3'd1;   // skip the dead lane
                        end else if (seg == 1'b0) begin
                            seg  <= 1'b1;
                            lane <= 3'd0;
                        end else begin
                            state <= S_TICK;       // nothing left to serve
                        end
                    end
                    // (st_valid but the bus is granted away / paused: wait)
                  end

                  B_CMD: begin
                    if (cpu_ce_posedge)
                        t_cnt <= (t_cnt != 3'd7) ? (t_cnt + 3'd1) : 3'd7;

                    // the conservative T3: the byte retires at >= its third
                    // posedge tick, once the chipset says ready and the bus
                    // is still ours (the AEN race, v30_cpu_bridge's header)
                    if ((t_cnt >= 3'd3) && cpu_ce_posedge
                        && processor_ready && bus_ours) begin
                        if (cur_read && !st_pasv) begin
                            if (seg == 1'b0) begin
                                rd_dword[{lane[1:0], 3'b000} +: 8]
                                    <= data_bus;
                                if (st_word1)
                                    rd_dword[{lane[1:0], 3'b000} + 8 +: 8]
                                        <= data_bus_hi;
                            end else if (sv_inta) begin
                                if (lane == 3'd1) int_vector <= data_bus;
                            end else begin
                                rd_port[{lane[0], 3'b000} +: 8] <= data_bus;
                            end
                        end
                        processor_status <= BS_PASV;
                        gap_cnt          <= 2'd0;
                        bstate           <= B_GAP;
                    end
                  end

                  B_GAP: begin
                    // one full passive posedge re-arms the 8288
                    if (cpu_ce_posedge)
                        gap_cnt <= gap_cnt + 2'd1;

                    if (gap_cnt == 2'd1) begin
                        if (step_last) begin
                            // assemble what the unit's retiring tick samples:
                            // PORT_DIN for the I/O stage, ram_din's NEXT
                            // parked value is written in S_TICK itself.
                            if (sv_inta)
                                port_din <= {8'h00, int_vector};
                            else if (sv_io && !sv_io_wr) begin
                                if (!sv_io_word)
                                    port_din <= {rd_port[7:0], rd_port[7:0]};
                                else case (sv_io_term)
                                    TERM_WORD:   port_din <= 16'h2588;
                                    TERM_ACTIVE: port_din <=
                                                 {port_din[15:8],
                                                  rd_port[7:0]};
                                    TERM_PLUS:   port_din <=
                                                 {8'hFF, rd_port[7:0]};
                                    TERM_MINUS:  port_din <=
                                                 {8'h00, rd_port[7:0]};
                                    TERM_EXT08:  port_din <=
                                                 {8'h08, rd_port[7:0]};
                                    default:     port_din <= rd_port;
                                endcase
                            end
                            state <= S_TICK;
                        end else if (seg == 1'b0 && seg_done) begin
                            seg    <= 1'b1;
                            lane   <= 3'd0;
                            bstate <= B_IDLE;
                        end else begin
                            lane   <= lane + st_adv;
                            bstate <= B_IDLE;
                        end
                        word_access <= 1'b0;
                    end
                  end

                  default: bstate <= B_IDLE;
                endcase
              end

              // ------------- the interval's one tick ------------------------
              S_TICK: begin
                if (!pause_core) begin
                    // the unit samples OLD ram_din at this edge (the previous
                    // request's response); the new park lands for the next
                    // interval's ending tick.
                    if (sv_mem && !sv_mem_wr) ram_din <= rd_dword;
                    biu_done_r <= 1'b1;
                    state      <= S_IDLE;
                end
              end

              default: state <= S_IDLE;
            endcase
        end
    end

    assign dbg = {state, bstate, seg, lane[1:0], stall, unit_ce, ce186,
                  u_halt, t_cnt, gap_cnt[1:0]};

endmodule

`default_nettype wire
