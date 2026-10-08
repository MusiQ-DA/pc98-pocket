//
// PC-98 RAM (grown out of the MiSTer PCXT base)
// Ported by @spark2k06
//
// Based on chipset written by @kitune-san
//
module RAM (
    input   logic           clock,
    input   logic           reset,
    input   logic           enable_sdram,
    output  logic           initilized_sdram,
    // I/O Ports
    input   logic   [19:0]  address,
    input   logic   [7:0]   internal_data_bus,
    output  logic   [7:0]   data_bus_out,
    // Sixteen-bit CPU access. This machine keeps ONE GUEST BYTE PER 16-BIT
    // SDRAM WORD (see access_data_in below), so the guest's byte N and byte
    // N+1 sit in consecutive SDRAM words: a V30 word cycle is one burst of
    // two, not two bus cycles. word_access says the cycle is a word, and the
    // _hi pair carries its odd half. Held low, everything below behaves
    // byte-at-a-time.
    // Sixteen-colour mode (port 0x6A bit 0). It moves the memory map: the
    // fourth graphics plane at E0000-E7FFF exists only while this is set.
    input   logic           analog_mode,
    input   logic           word_access,
    input   logic   [7:0]   internal_data_bus_hi,
    output  logic   [7:0]   data_bus_out_hi,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    input   logic           no_command_state,
    // Prefetch burst (Pocket): nonzero while the bus cycle on the pins is the
    // CPU bridge's prefetch fill -- the read then moves prefetch_len SDRAM
    // words in one transaction instead of access_words. Held the whole
    // command phase, like word_access. The beat stream comes back on
    // pf_beat_*: pf_beat_v pulses once per returned word with that word's
    // byte on pf_beat_dat.
    input   logic   [4:0]   prefetch_len,
    output  logic           pf_beat_v,
    output  logic   [7:0]   pf_beat_dat,
    output  logic           memory_access_ready,
    // Graphics VRAM page one (Pocket): set only by pc98_gvram_seq, for its
    // own plane walks -- the page has no guest address, so this banks the
    // byte at 0x600000 where neither the guest nor EMS can follow. Must stay
    // first in the latch priority: the sequencer's addresses are plain
    // window addresses and would otherwise be remapped again.
    input   logic           gvram_page1_flag,
    // ROM-load (Pocket): read-only tap on the write/read completion state.
    output  logic           access_complete,
    // A COMPLETE_RAM_RW that belongs to the strobe on the pins RIGHT NOW:
    // the same own-access tests memory_access_ready applies, minus the
    // wait-cycle counts. Bare access_complete pulses for ANY finishing
    // access -- including a parked write draining ahead of a conflicting
    // read -- so a waiter that just needs "my access ended" must qualify
    // with this or it eats a foreign completion (pc98_gvram_seq's legs did:
    // the parked-write drains of a posted queue fed S_RDW garbage and the
    // real read never ran -- the EGC's write-then-RMW-read stream is
    // exactly the traffic that parks writes).
    output  logic           access_own,
    output  logic           ram_address_select_n,
    // JTAG probe (PC98_JTAG): the FSM's own view of a stalled access --
    // {parked write, refresh busy, read in flight, completing-is-read,
    //  completing-is-write, state[2:0]}. Unconsumed it synthesises away.
    output  logic   [7:0]   dbg,
    // dbg2 = 0 (the old lost_ev witness is superseded by dbg4/dbg5's
    //         universal coverage), dbg3 = parked-write count.
    output  logic   [31:0]  dbg2,
    output  logic   [31:0]  dbg3,
    output  logic   [31:0]  dbg4,
    output  logic   [31:0]  dbg5,
    output  logic   [103:0] dbg6,
    output  logic   [55:0]  dbg7,
    input   logic   [19:0]  dbg_watch_addr,
    // SDRAM
    output  logic   [12:0]  sdram_address,
    output  logic           sdram_cke,
    output  logic           sdram_cs,
    output  logic           sdram_ras,
    output  logic           sdram_cas,
    output  logic           sdram_we,
    output  logic   [1:0]   sdram_ba,
    input   logic   [15:0]  sdram_dq_in,
    output  logic   [15:0]  sdram_dq_out,
    output  logic           sdram_dq_io,
    output  logic           sdram_ldqm,
    output  logic           sdram_udqm,
     // EMS board (pc98_ems98): {mapped, SDRAM word[23:14]} per window of
     // C0000-CFFFF. The V30's bus stops at 0xFFFFF, so banked windows like
     // this are the only way the guest ever reaches SDRAM past its megabyte
     // -- this board's pool is 0x800000-0xFFFFFF, 8 MB of word space. An
     // empty entry leaves the window to the map's hole.
     input   logic   [10:0]  ems98_map[0:3],
     // BIOS
     input  logic    [1:0]  bios_protect_flag,
    // Font bank: while set, guest addresses are redirected above the machine's
    // megabyte so the loader can write FONT.ROM somewhere the guest cannot see.
    // The same trick as the ITF shadow, one bit further up.
     input  logic           font_bank_flag,
    // Video-side read port, straight through to the controller's port B.
     input  logic           font_rd_req,
     input  logic   [23:0]  font_rd_addr,
     input  logic    [3:0]  font_rd_len,
     output logic           font_rd_ack,
     output logic           font_rd_valid,
     output logic   [15:0]  font_rd_data,
     output logic           font_rd_done,
    // Second video-side reader: the character generator window.
     input  logic           cg_rd_req,
     input  logic   [23:0]  cg_rd_addr,
     input  logic    [3:0]  cg_rd_len,
     output logic           cg_rd_ack,
     output logic           cg_rd_valid,
     output logic   [15:0]  cg_rd_data,
     output logic           cg_rd_done,
    // Third video-side reader: the graphics planes' display fetch.
     input  logic           gv_rd_req,
     input  logic   [23:0]  gv_rd_addr,
     input  logic    [3:0]  gv_rd_len,
     output logic           gv_rd_ack,
     output logic           gv_rd_valid,
     output logic   [15:0]  gv_rd_data,
     output logic           gv_rd_done,
    // fdd_ramimg's carve-out port (controller port E): writes while a JTAG
    // upload fills the image, read bursts while it serves sectors.
     input  logic           ramimg_req,
     input  logic           ramimg_we,
     input  logic   [23:0]  ramimg_addr,
     input  logic    [3:0]  ramimg_len,
     input  logic   [15:0]  ramimg_wdata,
     output logic           ramimg_ack,
     output logic           ramimg_rvalid,
     output logic   [15:0]  ramimg_rdata,
     output logic           ramimg_done,
     input  logic           bios_shadow_flag,
    // Wait mode
    input   logic           wait_count_clk_en,
    input   logic   [1:0]   ram_read_wait_cycle,
    input   logic   [1:0]   ram_write_wait_cycle,
    // The MEMWAIT_VRAM share, resolved by Chipset on the guest address:
    // extra CPU cycles owed for a graphics-plane access while the GDC's
    // refresh owns that memory. Zero on a main-RAM address and at the
    // speeds that do not model the contention.
    input   logic   [3:0]   vram_rd_wait_cycle,
    input   logic   [3:0]   vram_wr_wait_cycle
);

    typedef enum {IDLE, RAM_WRITE_1, RAM_WRITE_2, RAM_READ_1, RAM_READ_2, COMPLETE_RAM_RW, WAIT} state_t;

    state_t         state;
    state_t         next_state;
    // 24 bits of word address now: the NEC EMS's pool at 0x800000-0xFFFFFF
    // needs bit 23, which the old 23-bit latch could not carry.
    logic   [23:0]  latch_address;
    logic   [7:0]   latch_data;
    logic   [7:0]   latch_data_hi;
    logic           write_command;
    logic           read_command;
    logic           prev_no_command_state;
    logic           enable_refresh;
    logic           write_protect;
    logic           bios_shadow_select;

    // Pending-write slot, depth one. The FSM was built for the CPU, whose
    // write strobe stays up until memory_access_ready ends its cycle; a
    // strobe that lands while a write or read is in flight -- the uPD71071's
    // memory_write_n arriving during the previous byte's COMPLETE_RAM_RW --
    // sees ready for a write nobody started and is gone by the next IDLE.
    // On the disk that is the periodic ~1-in-9 dropped byte of a sector DMA
    // fill, proved on hardware with an 0xFF pre-dirty: misses came back
    // stale, never as injected data. The slot parks the command with its
    // address and data so the next IDLE can serve it; parked traffic goes
    // first so guest-visible write order holds.
    //
    // accept_* snapshots the operands of every write at acceptance, from the
    // slot or from the bus: RAM_WRITE_1/2 otherwise consume latch_* and the
    // live data bus, which a pulse-width strobe can legally release -- and
    // change -- before write_flag confirms the request.
    logic           wc_pend;
    logic           wc_pend2;
    logic           wc_pend3;
    logic           accept_live_wr;
    logic           accept_live_rd;
    logic   [23:0]  pend_address;
    logic   [7:0]   pend_data;
    logic   [7:0]   pend_data_hi;
    logic           pend_word;
    logic   [23:0]  pend2_address;
    logic   [7:0]   pend2_data;
    logic   [7:0]   pend2_data_hi;
    logic           pend2_word;
    logic   [23:0]  pend3_address;
    logic   [7:0]   pend3_data;
    logic   [7:0]   pend3_data_hi;
    logic           pend3_word;
    // cap: the tail capture register -- a write strobe with no other
    // capture path lands here (see new_cap). Always the queue tail.
    logic           cap_valid;
    logic   [23:0]  cap_address;
    logic   [7:0]   cap_data;
    logic   [7:0]   cap_data_hi;
    logic           cap_word;
    logic   [23:0]  accept_address;
    logic   [7:0]   accept_data;
    logic   [7:0]   accept_data_hi;
    logic           accept_word;

    // Two counters per direction: the two-bit base keeps its original
    // floor behaviour (it drains while the transaction runs), and the
    // graphics-region share is ADDITIVE -- np21w charges MEMWAIT_VRAM on
    // top of the access, so its count only starts once the FSM sits in
    // COMPLETE_RAM_RW holding the strobe's READY.
    logic   [1:0]   read_wait_count;
    logic   [1:0]   write_wait_count;
    logic   [3:0]   vram_rd_wait_count;
    logic   [3:0]   vram_wr_wait_count;
    logic           access_ready;

    //
    // RAM Address Select (0x00000-0xAFFFF and 0xC0000-0xFFFFF)
    //
    // The machine this BIOS comes from has 640 KB of RAM and empty
    // C0000-E7FFF slots, and its POST decides how much memory to test by
    // probing them. With SDRAM answering there it saw an "expansion" that
    // does not exist and swept on into D0000, where it stopped (LIVE DA9EA,
    // N frozen). So the SDRAM answers 00000-BFFFF only: the main RAM, plus
    // the A8000-BFFFF window the GVRAM probe writes through. A0000-A7FFF is
    // still excluded -- text VRAM and the CG window answer from elsewhere.
    //
    // E8000-FFFFF stays SELECTED on purpose: the BIOS image lives in the
    // SDRAM (the loader writes it there, the guest fetches it from there),
    // and taking it out of the select -- which one revision did -- starved
    // the loader into DROP 38190 and left BAD 0F2 on the compare.
    // The predicate itself lives in pc98_sdram_map.svh, because zet_cpu_bridge
    // needs the same answer one step earlier -- see that file.
`include "pc98_sdram_map.svh"

    // The EMS windows sit in C0000-DFFFF, which the flat map leaves open on
    // purpose -- so a claimed window has to select the SDRAM by itself.
    wire ems98_win = (address[19:16] == 4'hC)
                  && ems98_map[address[15:14]][10];
    assign ram_address_select_n = ~(enable_sdram && (gvram_page1_flag
                                         || pc98_sdram_hits(address, analog_mode)
                                         || ems98_win));
	 

    // The ITF bank. F8000-FFFFF, 32 KB, mapped to the shadow copy at 1F8000
    // through latch_address's spare bit -- the same bit and the same mechanism
    // the BIOS shadow uses.
    //
    // Set: the guest sees the ITF (power-on, and after port 0x043D gets 0x10).
    // Clear: it sees the system BIOS's own F8000-FFFFF (after 0x043D gets 0x12).
    // core_top owns the flag; during the ITF load it is driven by the loader so
    // the image is written into the shadow instead of over the BIOS.
    assign bios_shadow_select    = bios_shadow_flag & (address[19:15] == 5'b11111);


    //
    // Write protect
    //
    // PC-98's ROM is E8000-FFFFF (96 KB), not a 64 KB F0000-FFFFF page plus the
    // EC00 option-ROM window. bios_protect_flag[1] covers the whole of it.
    assign write_protect = bios_protect_flag[1] & ((address[19:16] == 4'b1111)
                                                |  (address[19:15] == 5'b11101));


    //
    // I/O Ports
    //
    // Address
    always_comb begin
        if (gvram_page1_flag)
            // GVRAM page one: 0x600000 upward. The sequencer hands a
            // seventeen-bit plane-and-offset; the guest's own map, every EMS
            // window, and the font bank all stay out of the way.
            latch_address   = 24'h600000 + {7'h00, address[16:0]};
        else if (ems98_win)
            // The EMS board's window claims C0000-CFFFF; its map entry is
            // the page's top ten word bits, so the low fourteen come from
            // the guest.
            latch_address   = {ems98_map[address[15:14]][9:0], address[13:0]};
        else if (font_bank_flag)
            // 0x400000 upward: past EMS, which owns bit 21.
            latch_address   = {1'b0, 1'b1, 2'b00, address};
        else
            latch_address   = {3'b000, bios_shadow_select, address};
    end

    // Data
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            latch_data      <= 0;
            latch_data_hi   <= 0;
        end
        else begin
            latch_data      <= internal_data_bus;
            latch_data_hi   <= internal_data_bus_hi;
        end
    end

    // Write Command
    assign write_command = ~ram_address_select_n & ~memory_write_n & ~write_protect;

    // Read Command
    assign read_command  = ~ram_address_select_n & ~memory_read_n;

    // Generate refresh timing
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_no_command_state   <= 1'b0;
        end
        else begin
            prev_no_command_state   <= no_command_state;
        end
    end

    assign  enable_refresh  = no_command_state & ~prev_no_command_state;


    //
    // SDRAM Controller
    //
    logic   [24:0]  access_address;
    logic   [9:0]   access_num;
    logic   [15:0]  access_data_in;
    logic   [15:0]  access_data_in_hi;
    logic   [15:0]  access_data_out;
    logic   [15:0]  access_data_out_hi;

    // A word access is two words where the far end can burst: with
    // word_access up, a guest word becomes one two-word SDRAM transaction.
    wire            word_now = word_access;
    wire    [9:0]   access_words = word_now ? 10'h002 : 10'h001;
    // A prefetch fill overrides the shape: prefetch_len words in one burst,
    // whether or not word_access is up (it never is -- the fill runs as a
    // byte-style cycle so the pair ends after one strobe).
    wire    [9:0]   read_words = (prefetch_len != 5'd0)
                               ? {5'b00000, prefetch_len} : access_words;
    logic           write_request;
    logic           read_request;
    logic           write_flag;
    logic           read_flag;
    logic           idle;
    logic           refresh_mode;
    logic   [15:0]  pf_beat_w;
    assign  pf_beat_dat = pf_beat_w[7:0];

    // sdram_shim wraps sdram_mp, the multi-port controller: port A is this
    // guest path, B the font fetch, C the CG window, D the graphics display,
    // E fdd_ramimg's image carve-out.
    // See docs/P0_SDRAM_DESIGN.md.
    sdram_shim u_sdram (
        .sdram_clock        (clock),
        .sdram_reset        (reset),
        .address            (access_address),
        .access_num         (access_num),
        .data_in            (access_data_in),
        .data_out           (access_data_out),
        .data_in_hi         (access_data_in_hi),
        .data_out_hi        (access_data_out_hi),
        .a_rvalid           (pf_beat_v),
        .a_beat             (pf_beat_w),
        .write_request      (write_request),
        .read_request       (read_request),
        .enable_refresh     (enable_refresh),
        .write_flag         (write_flag),
        .read_flag          (read_flag),
        .idle               (idle),
        .refresh_mode       (refresh_mode),
        .sdram_address      (sdram_address),
        .sdram_cke          (sdram_cke),
        .sdram_cs           (sdram_cs),
        .sdram_ras          (sdram_ras),
        .sdram_cas          (sdram_cas),
        .sdram_we           (sdram_we),
        .sdram_ba           (sdram_ba),
        .sdram_dq_in        (sdram_dq_in),
        .sdram_dq_out       (sdram_dq_out),
        .sdram_dq_io        (sdram_dq_io),
        .b_req              (font_rd_req),
        .b_addr             (font_rd_addr),
        .b_len              (font_rd_len),
        .b_ack              (font_rd_ack),
        .b_rvalid           (font_rd_valid),
        .b_rdata            (font_rd_data),
        .b_done             (font_rd_done),
        .c_req              (cg_rd_req),
        .c_addr             (cg_rd_addr),
        .c_len              (cg_rd_len),
        .c_ack              (cg_rd_ack),
        .c_rvalid           (cg_rd_valid),
        .c_rdata            (cg_rd_data),
        .c_done             (cg_rd_done),
        .d_req              (gv_rd_req),
        .d_addr             (gv_rd_addr),
        .d_len              (gv_rd_len),
        .d_ack              (gv_rd_ack),
        .d_rvalid           (gv_rd_valid),
        .d_rdata            (gv_rd_data),
        .d_done             (gv_rd_done),
        .e_req              (ramimg_req),
        .e_we               (ramimg_we),
        .e_addr             (ramimg_addr),
        .e_len              (ramimg_len),
        .e_wdata            (ramimg_wdata),
        .e_ack              (ramimg_ack),
        .e_rvalid           (ramimg_rvalid),
        .e_rdata            (ramimg_rdata),
        .e_done             (ramimg_done)
    );


    //
    // State machine
    //
    always_comb begin
        next_state = state;
        casez (state)
            IDLE: begin
                // Posted writes made the parked queue the normal case, so a
                // non-conflicting read may pass it: write order is only owed
                // where the address ranges actually collide (rd_conflicts).
                // A live write strobe still wins -- matching the master-side
                // ordering this FSM always had.
                if (write_command)
                    next_state = RAM_WRITE_1;
                else if (read_command & ~rd_conflicts)
                    next_state = RAM_READ_1;
                else if (wc_pend)
                    next_state = RAM_WRITE_1;
                else if (read_command)
                    next_state = RAM_READ_1;
            end
            // Once a write is accepted it must complete: an early
            // ~write_command (a pulse shorter than the accept handshake) used
            // to drop the request on the floor here, which is the same class
            // of miss as a strobe landing in COMPLETE_RAM_RW's window.
            RAM_WRITE_1: begin
                if (write_flag)
                    next_state = RAM_WRITE_2;
            end
            RAM_WRITE_2: begin
                if (~write_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            RAM_READ_1: begin
                if (~read_command)
                    next_state = WAIT;
                if (read_flag)
                    next_state = RAM_READ_2;
            end
            RAM_READ_2: begin
                if (~read_command)
                    next_state = WAIT;
                if (~read_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            COMPLETE_RAM_RW: begin
                // A live strobe holds the exit only when it belongs to the
                // access just served: for a write that is the operand match
                // (the served strobe or its identical parked twin), for a
                // read the accept_live_rd flag. A parked access has no
                // strobe to wait on, and a strobe for someone else's next
                // transfer must not strand the FSM here.
                if ((~write_command | ~accept_live_wr | ~write_strobe_match)
                    & (~read_command | ~accept_live_rd | ~read_strobe_match))
                    next_state = IDLE;
            end
            WAIT: begin
                if (idle)
                    next_state = IDLE;
            end
        endcase
    end

    // Read-bypass ranges (mapped/latch space): a read with no pending-write
    // overlap may pass the parked-write queue -- program order only matters
    // where the addresses actually collide. A word access covers two SDRAM
    // words, so both ranges carry their own length; a prefetch fill covers
    // prefetch_len and must wait behind any parked write it would fetch
    // ahead of.
    wire [24:0] rd_beg = {1'b0, latch_address};
    wire [24:0] rd_end = rd_beg + {15'b0, read_words};
    wire [24:0] p1_beg = {1'b0, pend_address};
    wire [24:0] p1_end = p1_beg + (pend_word ? 25'd2 : 25'd1);
    wire [24:0] p2_beg = {1'b0, pend2_address};
    wire [24:0] p2_end = p2_beg + (pend2_word ? 25'd2 : 25'd1);
    wire [24:0] p3_beg = {1'b0, pend3_address};
    wire [24:0] p3_end = p3_beg + (pend3_word ? 25'd2 : 25'd1);
    wire [24:0] cp_beg = {1'b0, cap_address};
    wire [24:0] cp_end = cp_beg + (cap_word ? 25'd2 : 25'd1);
    wire        rd_conflicts = (wc_pend  & (rd_beg < p1_end) & (rd_end > p1_beg))
                             | (wc_pend2 & (rd_beg < p2_end) & (rd_end > p2_beg))
                             | (wc_pend3 & (rd_beg < p3_end) & (rd_end > p3_beg))
                             | (cap_valid & (rd_beg < cp_end) & (rd_end > cp_beg));

    // "Is this strobe new" is decided by operands, not by edges or by a
    // served flag: back-to-back strobes can hold write_command across a
    // master switch with no falling edge at all, and the strobe whose copy
    // is in the pending slot is itself held while its twin runs -- taking
    // !live_served as proof of newness re-parked that twin forever and the
    // guest wedged. An operand match against the access in flight means
    // this strobe is satisfied by it: it waits held and the COMPLETE below
    // releases it. Only different operands are a new transfer to park.
    // The high byte lane only counts for a word access: on a held byte
    // write the master may drive anything up there (the next pipelined
    // word, a turnaround byte), and comparing it could un-match the twin
    // -- held forever with its copy already landed, a real wedge.
    wire write_strobe_match = (latch_address      == accept_address)
                            & (internal_data_bus    == accept_data)
                            & (word_now             == accept_word)
                            & (~accept_word
                               | (internal_data_bus_hi == accept_data_hi));
    wire read_strobe_match  = (latch_address == accept_address)
                            & (word_now      == accept_word);
    // Parked-operand matches: a held strobe whose copy already sits in a
    // slot must neither re-park nor count as blocked/lost when it falls.
    // The hi lane only counts on word writes (same caveat as the match
    // against the in-flight access).
    wire parked_match  = (latch_address        == pend_address)
                       & (internal_data_bus    == pend_data)
                       & (word_now             == pend_word)
                       & (~pend_word
                          | (internal_data_bus_hi == pend_data_hi));
    wire parked2_match = (latch_address        == pend2_address)
                       & (internal_data_bus    == pend2_data)
                       & (word_now             == pend2_word)
                       & (~pend2_word
                          | (internal_data_bus_hi == pend2_data_hi));
    wire parked3_match = (latch_address        == pend3_address)
                       & (internal_data_bus    == pend3_data)
                       & (word_now             == pend3_word)
                       & (~pend3_word
                          | (internal_data_bus_hi == pend3_data_hi));
    wire cap_match     = (latch_address        == cap_address)
                       & (internal_data_bus    == cap_data)
                       & (word_now             == cap_word)
                       & (~cap_word
                          | (internal_data_bus_hi == cap_data_hi));

    // Already covered? Only a match against a register that is actually
    // live counts: the in-flight accept while it is being served, and the
    // parked slots while occupied. A stale-register match used to block
    // the park for a cycle -- fine for a held strobe, fatal for a pulse.
    wire cov_inflight = write_strobe_match & accept_live_wr & (state != IDLE);
    wire cov_pend1    = parked_match  & wc_pend;
    wire cov_pend2    = parked2_match & wc_pend2;
    wire cov_pend3    = parked3_match & wc_pend3;
    wire cov_cap      = cap_match     & cap_valid;
    wire dup_covered  = cov_inflight | cov_pend1 | cov_pend2 | cov_pend3
                      | cov_cap;

    // The live strobe takes the accept directly at IDLE only when the
    // queue is empty; anything else must park or capture.
    wire wr_accept_live = write_command & (state == IDLE) & ~wc_pend;

    wire new_write_strobe = write_command && state != IDLE && !wc_pend
        && !dup_covered;
    // Second-depth capture: a strobe arriving while the first slot is full
    // parks here too -- the uPD71071's early-released pulses are gone before
    // either slot could free, and capture-on-arrival is what survives them.
    wire new_write_strobe2 = write_command && state != IDLE && wc_pend
        && !wc_pend2 && !dup_covered;
    // Third-depth capture: with posted writes the queue sits full far more
    // often -- the shared READY line can release a strobe on a pulse that
    // belonged to a different access, so a strobe arriving while both
    // shallower slots are taken still needs somewhere durable to land.
    wire new_write_strobe3 = write_command && state != IDLE && wc_pend
        && wc_pend2 && !wc_pend3 && !dup_covered;
    // The IDLE&&wc_pend blind spot: the accept edge takes the parked head
    // and shifts the FIFO down, freeing the deepest occupied slot -- a
    // live strobe may drop straight into it in the same cycle. Without
    // this, a strobe arriving on exactly this cycle had no capture path
    // at all (the case dbg_uncov was built to expose).
    wire idle_park = write_command && (state == IDLE) && wc_pend
        && (next_state == RAM_WRITE_1) && !dup_covered;
    // Tail capture: whatever has no other place to go lands in cap -- the
    // shared READY chain can end a strobe on a pulse that belonged to a
    // different access entirely, so capture cannot wait for a park slot
    // to exist. cap is the queue tail: it promotes into pend3 when the
    // shift frees a slot.
    wire new_cap = write_command && !cap_valid && !dup_covered
        && !wr_accept_live && !new_write_strobe && !new_write_strobe2
        && !new_write_strobe3 && !idle_park;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            state             <= IDLE;
            wc_pend           <= 1'b0;
            wc_pend2          <= 1'b0;
            wc_pend3          <= 1'b0;
            accept_live_wr    <= 1'b0;
            accept_live_rd    <= 1'b0;
            pend_address      <= 24'd0;
            pend_data         <= 8'd0;
            pend_data_hi      <= 8'd0;
            pend_word         <= 1'b0;
            pend2_address     <= 24'd0;
            pend2_data        <= 8'd0;
            pend2_data_hi     <= 8'd0;
            pend2_word        <= 1'b0;
            pend3_address     <= 24'd0;
            pend3_data        <= 8'd0;
            pend3_data_hi     <= 8'd0;
            pend3_word        <= 1'b0;
            cap_valid         <= 1'b0;
            cap_address       <= 24'd0;
            cap_data          <= 8'd0;
            cap_data_hi       <= 8'd0;
            cap_word          <= 1'b0;
            accept_address    <= 24'd0;
            accept_data       <= 8'd0;
            accept_data_hi    <= 8'd0;
            accept_word       <= 1'b0;
        end
        else begin
            state <= next_state;
            if (state == IDLE && next_state == RAM_WRITE_1) begin
                // Accept: operands snapshot either from the slot (parked
                // traffic wins, so write order holds) or off the live bus.
                // accept_live_wr now means "the completing access is a
                // write" -- the live-twin test itself is write_strobe_match.
                accept_live_wr <= 1'b1;
                accept_live_rd <= 1'b0;
                if (wc_pend) begin
                    accept_address <= pend_address;
                    accept_data    <= pend_data;
                    accept_data_hi <= pend_data_hi;
                    accept_word    <= pend_word;
                    // Depth-3 FIFO: the queue shifts down one as the head
                    // is accepted, so parked order is preserved. The tail
                    // slot the shift frees takes the live strobe when one
                    // is waiting (idle_park) -- capture-on-arrival even at
                    // the one cycle where the old depth-1 scheme had no
                    // place to put it.
                    pend_address   <= pend2_address;
                    pend_data      <= pend2_data;
                    pend_data_hi   <= pend2_data_hi;
                    pend_word      <= pend2_word;
                    wc_pend        <= wc_pend2;
                    pend2_address  <= pend3_address;
                    pend2_data     <= pend3_data;
                    pend2_data_hi  <= pend3_data_hi;
                    pend2_word     <= pend3_word;
                    wc_pend2       <= wc_pend3;
                    pend3_address  <= cap_address;
                    pend3_data     <= cap_data;
                    pend3_data_hi  <= cap_data_hi;
                    pend3_word     <= cap_word;
                    wc_pend3       <= cap_valid;
                    cap_valid      <= 1'b0;
                    if (idle_park) begin
                        // The live strobe takes the deepest slot the shift
                        // freed: cap if one promoted out, else the deepest
                        // occupied slot's vacancy.
                        if (cap_valid) begin
                            cap_address <= latch_address;
                            cap_data    <= internal_data_bus;
                            cap_data_hi <= internal_data_bus_hi;
                            cap_word    <= word_now;
                            cap_valid   <= 1'b1;
                        end
                        else if (wc_pend3) begin
                            pend3_address <= latch_address;
                            pend3_data    <= internal_data_bus;
                            pend3_data_hi <= internal_data_bus_hi;
                            pend3_word    <= word_now;
                            wc_pend3      <= 1'b1;
                        end
                        else if (wc_pend2) begin
                            pend2_address <= latch_address;
                            pend2_data    <= internal_data_bus;
                            pend2_data_hi <= internal_data_bus_hi;
                            pend2_word    <= word_now;
                            wc_pend2      <= 1'b1;
                        end
                        else begin
                            pend_address <= latch_address;
                            pend_data    <= internal_data_bus;
                            pend_data_hi <= internal_data_bus_hi;
                            pend_word    <= word_now;
                            wc_pend      <= 1'b1;
                        end
                    end
                end
                else begin
                    accept_address <= latch_address;
                    accept_data    <= internal_data_bus;
                    accept_data_hi <= internal_data_bus_hi;
                    accept_word    <= word_now;
                    wc_pend <= 1'b0;
                end
            end
            else if (state == IDLE && next_state == RAM_READ_1) begin
                // Snapshot the read's operands too: a different-address
                // read strobe held across this access's COMPLETE must not
                // see its ready (it would release early and be orphaned
                // with this access's data, same class as the write drops).
                accept_live_rd <= read_command;
                accept_live_wr <= 1'b0;
                accept_address <= latch_address;
                accept_word    <= word_now;
            end
            if (new_write_strobe) begin
                wc_pend      <= 1'b1;
                pend_address <= latch_address;
                pend_data    <= internal_data_bus;
                pend_data_hi <= internal_data_bus_hi;
                pend_word    <= word_now;
            end
            else if (new_write_strobe2) begin
                wc_pend2      <= 1'b1;
                pend2_address <= latch_address;
                pend2_data    <= internal_data_bus;
                pend2_data_hi <= internal_data_bus_hi;
                pend2_word    <= word_now;
            end
            else if (new_write_strobe3) begin
                wc_pend3      <= 1'b1;
                pend3_address <= latch_address;
                pend3_data    <= internal_data_bus;
                pend3_data_hi <= internal_data_bus_hi;
                pend3_word    <= word_now;
            end
            else if (new_cap) begin
                cap_valid     <= 1'b1;
                cap_address   <= latch_address;
                cap_data      <= internal_data_bus;
                cap_data_hi   <= internal_data_bus_hi;
                cap_word      <= word_now;
            end
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            initilized_sdram <= 1'b0;
        else if (idle)
            initilized_sdram <= 1'b1;
        else
            initilized_sdram <= initilized_sdram;
    end


    //
    // Output SDRAM Control Signals
    //
    always_comb begin
        casez (state)
            IDLE: begin
                // A parked write goes first, so the direct fast-path may not
                // fire a live strobe here: with wc_pend set the accepted
                // write in RAM_WRITE_1 uses the parked operands, and a live
                // request out of IDLE would run one slot ahead of it.
                access_address  = {1'b0, latch_address};
                access_num      = read_words;
                access_data_in  = {8'h00, latch_data};
                access_data_in_hi = {8'h00, latch_data_hi};
                write_request   = (write_command & ~wc_pend) ? 1'b1 : 1'b0;
                read_request    = (read_command & ~wc_pend)  ? 1'b1 : 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_1: begin
                access_address  = {1'b0, accept_address};
                access_num      = accept_word ? 10'h002 : 10'h001;
                access_data_in  = {8'h00, accept_data};
                access_data_in_hi = {8'h00, accept_data_hi};
                write_request   = 1'b1;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_2: begin
                access_address  = {1'b0, accept_address};
                access_num      = accept_word ? 10'h002 : 10'h001;
                access_data_in  = {8'h00, accept_data};
                access_data_in_hi = {8'h00, accept_data_hi};
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_1: begin
                access_address  = {1'b0, latch_address};
                access_num      = read_words;
                access_data_in  = 16'h0000;
                access_data_in_hi = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b1;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_2: begin
                access_address  = {1'b0, latch_address};
                access_num      = access_words;
                access_data_in  = 16'h0000;
                access_data_in_hi = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            COMPLETE_RAM_RW: begin
                access_address  = 25'h0000000;
                access_num      = access_words;
                access_data_in  = 16'h0000;
                access_data_in_hi = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            WAIT: begin
                access_address  = 25'h0000000;
                access_num      = access_words;
                access_data_in  = 16'h0000;
                access_data_in_hi = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b1;
                sdram_udqm      = 1'b1;
            end
        endcase
    end


    //
    // Databus Out
    //
    logic   [7:0]   data_bus_out_reg;
    logic   [7:0]   data_bus_out_hi_reg;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            data_bus_out_reg    <= 0;
            data_bus_out_hi_reg <= 0;
        end
        else if (read_flag) begin
            data_bus_out_reg    <= access_data_out[7:0];
            data_bus_out_hi_reg <= access_data_out_hi[7:0];
        end
        else begin
            data_bus_out_reg    <= data_bus_out_reg;
            data_bus_out_hi_reg <= data_bus_out_hi_reg;
        end
    end

    assign  data_bus_out = ~read_command ? 0 : ~read_flag ? data_bus_out_reg : access_data_out[7:0];
    // The odd half, on exactly the same terms. Both beats of a two-word read
    // land before read_flag drops, so the same latch-while-flag rule holds.
    assign  data_bus_out_hi = ~read_command ? 0
                            : ~read_flag    ? data_bus_out_hi_reg
                                            : access_data_out_hi[7:0];


    //
    // Ready/Wait Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            access_ready <= 1'b0;
        else if (state == COMPLETE_RAM_RW)
            access_ready <= 1'b1;
        else if (state == IDLE)
            access_ready <= idle;
        else if ((write_command) && (refresh_mode))
            access_ready <= 1'b0;
        else if ((read_command)  && (refresh_mode))
            access_ready <= 1'b0;
        else
            access_ready <= access_ready;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            read_wait_count     <= 0;
            vram_rd_wait_count  <= 0;
        end else if (~read_command) begin
            read_wait_count     <= ram_read_wait_cycle;
            vram_rd_wait_count  <= vram_rd_wait_cycle;
        end else if (wait_count_clk_en) begin
            if (read_wait_count != 0)
                read_wait_count     <= read_wait_count - 1;
            else if ((vram_rd_wait_count != 0) && (state == COMPLETE_RAM_RW))
                vram_rd_wait_count  <= vram_rd_wait_count - 1;
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            write_wait_count    <= 0;
            vram_wr_wait_count  <= 0;
        end else if (~write_command) begin
            write_wait_count    <= ram_write_wait_cycle;
            vram_wr_wait_count  <= vram_wr_wait_cycle;
        end else if (wait_count_clk_en) begin
            if (write_wait_count != 0)
                write_wait_count    <= write_wait_count - 1;
            else if ((vram_wr_wait_count != 0) && (state == COMPLETE_RAM_RW))
                vram_wr_wait_count  <= vram_wr_wait_count - 1;
        end
    end

    // Ready comes from the STATE, not from the access_ready register.
    //
    // access_ready is a clock behind the command: it is latched from `idle` in
    // the IDLE state, so for the first one or two chipset clocks after a
    // command rises it still reads 1 while read_flag is still 0 and
    // data_bus_out is THE PREVIOUS ACCESS'S BYTE. Measured on the old V30
    // memory bench:
    //
    //   st=3 rdcmd=1 rdflag=0 ardy=1 prdy=1 dout=10   <- command up, stale
    //   st=4 rdcmd=1 rdflag=1 ardy=1 prdy=1 dout=10   <- a CE edge lands here
    //   st=4 rdcmd=1 rdflag=1 ardy=0 prdy=0 dout=10   <- ready finally drops
    //   st=4 ...                               dout=8b <- the real byte
    //
    // The CPU never fell in: it samples READY once, deep in T3, a whole CPU
    // clock (nine chipset cycles at 4.77 MHz) after the command. zet_cpu_bridge
    // samples at EVERY posedge CE from its third T state on, and the 8288
    // raises the command around that same edge -- so the byte engine could
    // complete in the stale window and latch the previous byte. It did: the
    // first instruction fetch after a taken branch came back wrong, the CPU ran
    // into zeros, and it never recovered. On the machine that is the ITF's
    // memory test, which is a loop, reporting 000KB and starting over.
    //
    // COMPLETE_RAM_RW is reached only when the transaction has genuinely
    // finished -- it is what access_complete already means for the ROM loader
    // -- and data_bus_out_reg holds the captured byte by then. Saying ready
    // there and nowhere else makes this a real handshake for any master,
    // however it samples. The CPU sees ready no earlier than it did; it just
    // no longer sees it before the data.
    // Ready answers only for the strobe whose access was actually served:
    // a write must match the operands captured at acceptance (the served
    // strobe and an identical held twin are the same transfer; the slot's
    // copy finishing releases it), a read must be the flagged live strobe.
    // A strobe that arrived while the FSM was busy used to see this
    // COMPLETE and drop its transfer before anyone ran it -- the orphaned
    // writes the parking slot now also catches.
    //
    // Posted-write early release: a write strobe may also let go once its
    // operands are COVERED -- accepted live, parked in a slot, captured at
    // the IDLE promotion edge, or matching the access in flight or an
    // already-parked twin. The write then drains in the background while
    // the guest moves on; a conflicting read still waits behind the
    // matching parked write (rd_conflicts).
    // The operand matches (cov_*) are only valid while their registers
    // are -- they are defined next to the park wires where dup_covered
    // guards every capture path.
    wire wr_cov_now   = wr_accept_live | new_write_strobe | new_write_strobe2
                      | new_write_strobe3 | idle_park | new_cap
                      | cov_inflight | cov_pend1 | cov_pend2 | cov_pend3
                      | cov_cap;

    // The release must be REGISTERED, not combinational: wr_cov_now means
    // "the capture commits at this edge" -- accept takes the strobe or a
    // park slot fills -- but a ready asserted in that same cycle lets the
    // master drop the strobe BEFORE the edge, and the registering logic
    // then sees write_command already low and captures nothing (the
    // tb_ram_dma_wr UNCOV falls). One clock later the park/accept is a
    // fact, so the covered flag -- not the coverage condition -- gates the
    // release. The cost is one extra held cycle per write.
    logic        wr_covered;
    // Operands that were covered -- a different strobe appearing on the
    // bus without a write_command gap must not inherit this coverage. The
    // hi byte has to match too: a word write whose lo byte coincides with
    // the covered operands but whose hi byte differs is a different write.
    logic [23:0] cov_addr;
    logic  [7:0] cov_data;
    logic  [7:0] cov_data_hi;
    logic        cov_word;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            wr_covered <= 1'b0;
        else if (~write_command)
            wr_covered <= 1'b0;
        else if (wr_cov_now) begin
            wr_covered  <= 1'b1;
            cov_addr    <= latch_address;
            cov_data    <= internal_data_bus;
            cov_data_hi <= internal_data_bus_hi;
            cov_word    <= word_now;
        end
    end

    wire cov_same = (latch_address == cov_addr)
                  & (internal_data_bus == cov_data)
                  & (word_now == cov_word)
                  & (~cov_word | (internal_data_bus_hi == cov_data_hi));

    // Ready suppression while a write strobe is up but not yet durably
    // captured. io_channel_ready feeds READY.sv, whose dma_ready pulses on
    // ANY memory_access_ready rise -- a completing read's pulse releases the
    // uPD71071's current write strobe whether or not that strobe was ever
    // captured (the NOCOV falls in tb_ram_dma_fill: park slots full, cap
    // holding the previous early-released byte, drdy=1). Posting makes those
    // pulses far more frequent, so a strobe that has nowhere to go yet must
    // not see any ready until its operands are registered.
    //
    // Deadlock: impossible on this bus. Only one master's strobes are on
    // the pins at a time (the arbiter grants the bus exclusively), so a
    // held-until-ready read cannot coexist with an uncovered write strobe.
    // The completing access's strobe drops on access_complete / the
    // fixed-width fgn pulse regardless of this line, the FSM keeps cycling,
    // a park/cap slot frees, the strobe captures, and the gate opens.
    wire wr_strobe_open = write_command
                        & ~(wr_covered & cov_same)
                        & ~((state == COMPLETE_RAM_RW)
                            & accept_live_wr & write_strobe_match);

    assign  memory_access_ready = ((~ram_address_select_n) && ((~memory_read_n) || (~memory_write_n)))
                                        ? (~wr_strobe_open & (((state == COMPLETE_RAM_RW) & (
                                              (write_command & accept_live_wr & write_strobe_match & (write_wait_count == 0) & (vram_wr_wait_count == 0))
                                            | (read_command  & accept_live_rd & read_strobe_match  & (read_wait_count  == 0) & (vram_rd_wait_count == 0))))
                                           | (write_command & wr_covered & cov_same))) : 1'b1;

    // ROM-load (Pocket): a clean per-access "done" pulse for core_top's BIOS
    // loader. COMPLETE_RAM_RW is reached only after the SDRAM write truly
    // finishes (refresh-safe) and is independent of the CPU-bus wait throttle.
    assign  access_complete = (state == COMPLETE_RAM_RW);
    assign  access_own      = (state == COMPLETE_RAM_RW)
                            & ((write_command & accept_live_wr
                                               & write_strobe_match)
                             | (read_command & accept_live_rd
                                               & read_strobe_match));

    assign  dbg = {wc_pend, refresh_mode, read_flag,
                   accept_live_rd, accept_live_wr, state[2:0]};

    // Drop witness (PC98_JTAG). Two kinds of event matter here:
    //
    //   blocked -- a NEW write strobe rises while BOTH park slots are full
    //   (busy & wc_pend & wc_pend2, operands matching nothing in flight or
    //   parked). It is not lost yet: a strobe the master holds parks as
    //   soon as a slot frees. It is the precursor population.
    //
    //   lost -- a blocked strobe FALLS while still unaccepted. That byte is
    //   gone for good: it never reached the FSM, never parked, and the
    //   master has moved on. A held strobe never produces this; the
    //   uPD71071's early-released write pulse does.
    //
    // A parked twin's own fall is NOT a loss -- its operands are already
    // safe in pend_*/pend2_*, which is exactly why it may release early.
    // parked_match/parked2_match keep it out of the count.
    logic        write_command_d;
    logic [15:0] dbg_parks;

    wire write_strobe_fell = write_command_d & ~write_command;
    wire write_strobe_rose = ~write_command_d & write_command;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            write_command_d <= 1'b0;
            dbg_parks       <= 16'd0;
        end else begin
            write_command_d <= write_command;
            if ((new_write_strobe | new_write_strobe2 | new_write_strobe3
                 | idle_park | new_cap) && (dbg_parks != 16'hFFFF))
                dbg_parks <= dbg_parks + 16'd1;
        end
    end

    // Universal coverage: a write strobe is covered when the FSM accepts
    // it live (IDLE with nothing parked), it lands in a park slot, or its
    // operands match the access in flight / already parked (a held twin).
    // A strobe falling while uncovered is a TRUE loss -- and unlike
    // lost_ev it does not need both park slots full: a strobe arriving on
    // the exact IDLE&&wc_pend cycle (park wins the accept, live cannot
    // park because state==IDLE) then falling early escapes that counter
    // completely. byte0-of-fill writes are prime suspects: they arrive
    // right as the previous grant's tail retires.
    logic [15:0] dbg_uncov;
    logic [23:0] dbg_uncov_addr;    // first loss, full mapped address
    logic  [7:0] dbg_uncov_data;
    logic  [2:0] dbg_uncov_st;
    logic [23:0] dbg_uncov_addr2;   // most recent loss
    logic  [7:0] dbg_uncov_data2;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            dbg_uncov        <= 16'd0;
            dbg_uncov_addr   <= 24'd0;
            dbg_uncov_data   <= 8'd0;
            dbg_uncov_st     <= 3'd0;
            dbg_uncov_addr2  <= 24'd0;
            dbg_uncov_data2  <= 8'd0;
        end else begin
            if (write_strobe_fell & ~(wr_covered & cov_same)) begin
                if (dbg_uncov != 16'hFFFF)
                    dbg_uncov <= dbg_uncov + 16'd1;
                if (dbg_uncov == 16'd0) begin
                    dbg_uncov_addr <= latch_address;
                    dbg_uncov_data <= internal_data_bus;
                    dbg_uncov_st   <= state;
                end
                dbg_uncov_addr2 <= latch_address;
                dbg_uncov_data2 <= internal_data_bus;
            end
        end
    end

    // Sink-side record: the operands of the last three writes the FSM
    // actually accepted -- the arbiter logs the bus side, this logs what
    // RAM committed to serve. A fill's byte-0 that goes missing shows up
    // here with a stale/mapped-away operand, or not at all.
    logic  [7:0]  acc_cnt;
    logic  [31:0] acc_ring [0:2];
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            acc_cnt <= 8'd0;
            acc_ring[0] <= 32'd0;
            acc_ring[1] <= 32'd0;
            acc_ring[2] <= 32'd0;
        end else if (state == IDLE && next_state == RAM_WRITE_1) begin
            acc_ring[2] <= acc_ring[1];
            acc_ring[1] <= acc_ring[0];
            // {2'b0, was-parked, word, addr[19:0], data}
            acc_ring[0] <= {2'b00, wc_pend,
                            (wc_pend ? pend_word    : word_now),
                            (wc_pend ? pend_address[19:0]
                                     : latch_address[19:0]),
                            (wc_pend ? pend_data    : internal_data_bus)};
            if (acc_cnt != 8'hFF)
                acc_cnt <= acc_cnt + 8'd1;
        end
    end

    // Watch-accept witnesses, keyed on the arbiter's watchpoint address:
    //   wseen  -- write_command cycles whose (mapped) address is the watch
    //             point. If the arbiter's watch count exceeds this, writes
    //             reached the bus but never became a write_command here --
    //             swallowed upstream (sequencer expansion) or sel-missed.
    //   wacc   -- accepts whose mapped operand equals the watch point, and
    //             the sticky {pend,word,addr,data} of the last one. A mapped
    //             redirect shows here as addr != watch point (and no count).
    logic  [7:0]  wseen_cnt;
    logic  [7:0]  wacc_cnt;
    logic  [31:0] wacc_rec;
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            wseen_cnt <= 8'd0;
            wacc_cnt  <= 8'd0;
            wacc_rec  <= 32'd0;
        end else begin
            // Count strobe RISES at the watch address so this compares
            // one-for-one with the arbiter's watch count (strobe falls).
            if (write_strobe_rose && (latch_address[19:0] == dbg_watch_addr)
                && (wseen_cnt != 8'hFF))
                wseen_cnt <= wseen_cnt + 8'd1;
            if (state == IDLE && next_state == RAM_WRITE_1
                && ((wc_pend ? pend_address[19:0] : latch_address[19:0])
                    == dbg_watch_addr)) begin
                wacc_rec <= {2'b01, wc_pend,
                             (wc_pend ? pend_word    : word_now),
                             (wc_pend ? pend_address[19:0]
                                      : latch_address[19:0]),
                             (wc_pend ? pend_data    : internal_data_bus)};
                if (wacc_cnt != 8'hFF)
                    wacc_cnt <= wacc_cnt + 8'd1;
            end
        end
    end

    assign  dbg2 = 32'd0;                   // drop witness removed -- uncov covers it
    assign  dbg3 = {24'd0, dbg_parks};       // parked count only
    assign  dbg4 = {dbg_uncov[7:0], dbg_uncov_addr}; // {cnt, first addr24}
    assign  dbg5 = {dbg_uncov_data2, dbg_uncov_addr2[15:0],
                    dbg_uncov_data};          // {last d, last addr, first d}
    assign  dbg6 = {acc_cnt, acc_ring[2], acc_ring[1], acc_ring[0]};
    assign  dbg7 = {8'h00, wseen_cnt, wacc_cnt, wacc_rec};

endmodule
