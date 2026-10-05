//
// fdd_ramimg -- a RAM-disk floppy server: an image pushed in over JTAG,
// parked in an SDRAM carve-out, and served to floppy.v with no SD card, no
// menu mount and no firmware in the loop.
//
// WHY IT EXISTS. The only floppy path this machine had runs through the APF
// dataslots: the Pocket menu binds a file on the SD card, the firmware
// (fdd_service.c) walks the controller's request bits and moves every sector
// with four stores per byte through the bridge RAM. Nothing in that chain
// works without a card in the slot and a file picked by hand. This module is
// the whole path in hardware instead: a JTAG streamer drops a raw image into
// a reserved corner of SDRAM, a mount pass declares the 2HD geometry to
// floppy.v the way fdd_mount does, and the sector server answers the
// controller's read requests straight out of the carve-out. A probe write
// afterwards pulses the guest reset and the BIOS boots drive A hands-free.
//
// THE CARVE-OUT. The SDRAM map is word-addressed with one byte per 16-bit
// word (RAM.sv's convention: access_data_in is {8'h00, byte}), so the image
// needs one word per byte -- a 2HD disk is 77 cyl * 8 spt * 2 heads of
// 1024-byte sectors = 1232 sectors = 1,261,568 words. The base is 0x620000,
// the first word nothing else can reach: the guest's megabyte plus the ITF
// shadow end at 0x1FFFFF, the font bank owns 0x400000-0x4FFFFF, GVRAM page
// one ends at 0x61FFFF (RAM.sv's 0x600000 + 0x1FFFF), and the EMS pool
// (pc98_ems98.sv) starts at 0x800000 -- "nothing else in the map reaches past
// 0x61FFFF". 0x620000-0x753FFF holds the whole disk.
//
// THE JTAG SIDE -- two halves.
//
//   * A second SLD node (sld_instance_index 1 = hub NODE2, USER1 select
//     drscan 6'h28 once the hub sees two nodes). A raw bit sink: the DR
//     shift register packs TDI into 32-bit words and pushes each into a
//     512-deep dcfifo the moment it completes, so one drscan carries as much
//     image as it has bits -- the upload runs at close to TCK/8 bytes a
//     second instead of one word per USB round trip.
//
//   * Control on node one's existing write channel. Slot 0x87 carries the
//     control word (enable, flush, guest-reset, remount, stream-arm); slot
//     0x88 arms a readback probe point for verify. Status comes back on read
//     slots 0x35-0x37 (the dbg_* packings at the bottom).
//
// THE FLOPPY SIDE. While `own` is high the management bus is this module's:
// core_top's mux drops the softcore's strobes that name the floppy window
// (8'hF2) and masks the request bits the firmware bridge sees, so fdd_poll
// parks -- the SCSI/OPNA management targets keep working on the cycles this
// module is not strobing. Enable asserts own continuously; a disable holds
// it just long enough to eject drive A and hand the bus back.
//
// The mount is fdd_mount()'s order against the register file: eject (the
// change line registers it), a gap, cylinders, sectors/track, total sectors,
// heads, the 1024-byte-sector flag, write-protect SET -- the image is
// read-only in v1 -- and present last. Drive B is emptied first so the
// machine's floppy state is deterministic for as long as this server owns
// the bus: A is the uploaded image, B is out.
//
// A read request is served the way fdd_poll serves it: management register 0
// reports the in-flight command's {drive, lba}; the sector's 1024 bytes come
// out of the carve-out as 1024 single-word reads on sdram_shim's port E,
// each rvalid beat pushed straight into the controller's FIFO at 0xF2_0F.
// Sixteen-word bursts were the original form, but on hardware every beat of
// a full-rate port-E burst samples the NEXT word -- the boundary hazard
// sdram_mp's S_RD_GAP comment describes ("the new word wins early, both
// beats present the same data"), which sdram_mp only papers over for port 0.
// The guest saw exactly that signature: each burst delivered bytes 1..15
// followed by a repeat of byte 15. Single-word reads have no in-burst
// neighbour and are the same path the byte-exact readback probe takes, so
// the serve uses them; ~8-10 clocks a byte still outruns the FIFO drain.
// Write and format requests are drained and dropped --
// media_writeprotected already makes the controller
// refuse them at command start, so the drain is a safety net only.
//
// The FIFO discipline is exactly the firmware's: a read push is always a
// whole 1024-byte sector (fifo_full trips at sector_len and moves the
// controller to the drain wait), and a write drain pops until the request
// drops, bounded so a wedged command cannot wedge this FSM.
//
// Register 0's drive bit is ignored on serve: while this module is mounted,
// drive B is empty and any request in flight can only belong to drive A --
// a stray B request left over from a firmware mount would get RAM-image
// bytes, which is as good an answer as the eject it was seeing anyway.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module fdd_ramimg #(
    // Where the image lives: see the header. One SDRAM word per image byte.
    parameter logic [23:0] CARVE_BASE = 24'h620000,
    parameter int          IMG_BYTES  = 32'd1261568   // 77*8*2*1024
) (
    input  wire        clk,          // clk_chipset: the FDC/mgmt/SDRAM clock
    input  wire        reset,        // chipset reset -- aborts in-flight work
    input  wire        power_reset,  // reset_sdram: clears enable and offsets

    // floppy.v's raw request bits -- the firmware's masked view is upstream.
    input  wire  [1:0] fdd_request,

    // Management master. core_top muxes this onto the shared bus while own
    // is high; the read data input is the bus's combinational answer.
    output logic [15:0] mgmt_addr,
    output logic [15:0] mgmt_dout,
    output logic        mgmt_wr,
    output logic        mgmt_rd,
    input  wire [15:0]  mgmt_din,
    // The firmware's un-fenced strobes, one cycle ahead of the mux: high on
    // any cycle the softcore drives a non-F2 window (its F2 hits are fenced
    // in core_top and never reach the bus, so they need no yield). We never
    // strobe over it -- a management write has no acknowledge, a collision
    // would drop the firmware's byte silently, and SCSI/OPNA service must
    // keep working while this server owns the floppy.
    input  wire         fw_busy,

    // sdram_shim's port E: single words for writes and the readback probe,
    // sixteen-word bursts for sector fills.
    output logic        sd_req,
    output logic        sd_we,
    output logic [23:0] sd_addr,
    output logic  [3:0] sd_len,
    output logic [15:0] sd_wdata,
    input  wire         sd_ack,
    input  wire         sd_rvalid,
    input  wire [15:0]  sd_rdata,
    input  wire         sd_done,

    // The probe's write channel, already edge-synced into this domain.
    input  wire         ctl_pulse,
    input  wire  [6:0]  ctl_addr,
    input  wire [31:0]  ctl_data,

    output wire         own,             // the management bus is mine
    output wire         guest_reset_req, // one-clock pulse into reset_wire
    output wire [31:0]  dbg0,
    output wire [31:0]  dbg1,
    output wire [31:0]  dbg2
);

    // ------------------------------------------------------------------
    // JTAG stream sink: SLD node index 1. The DR is a raw 32-bit packer --
    // bits walk in through TDI on sdr, every completed word pushes into the
    // dcfifo, and cdr re-aligns the bit count so each scan starts on a word
    // boundary. up_rbk shifts the push counter out on TDO so a probe scan
    // can tell this node apart from dead air; disarmed scans push nothing,
    // which is what the arm bit is for.
    // ------------------------------------------------------------------
    wire  up_tck, up_tdi, up_cdr, up_sdr;
    logic up_tdo;

    sld_virtual_jtag_basic #(
        .sld_mfg_id             (11'h0),
        .sld_type_id            (8'h73),        // 's' -- the stream node
        .sld_version            (5'd1),
        .sld_instance_index     (1),
        .sld_auto_instance_index("YES"),
        .sld_ir_width           (1),
        .sld_sim_n_scan         (0),
        .sld_sim_action         ("UNUSED"),
        .sld_sim_total_length   (0)
    ) u_vjtag_up (
        .tck                (up_tck),
        .tdi                (up_tdi),
        .ir_in              (),
        .tdo                (up_tdo),
        .ir_out             (1'b0),
        .virtual_state_cdr  (up_cdr),
        .virtual_state_sdr  (up_sdr),
        .virtual_state_e1dr (),
        .virtual_state_pdr  (),
        .virtual_state_e2dr (),
        .virtual_state_udr  (),
        .virtual_state_cir  (),
        .virtual_state_uir  (),
        .tms                (),
        .jtag_state_tlr     (),
        .jtag_state_rti     (),
        .jtag_state_sdrs    (),
        .jtag_state_cdr     (),
        .jtag_state_sdr     (),
        .jtag_state_e1dr    (),
        .jtag_state_pdr     (),
        .jtag_state_e2dr    (),
        .jtag_state_udr     (),
        .jtag_state_sirs    (),
        .jtag_state_cir     (),
        .jtag_state_sir     (),
        .jtag_state_e1ir    (),
        .jtag_state_pir     (),
        .jtag_state_e2ir    (),
        .jtag_state_uir     ()
    );

    logic        up_arm;                       // ctl bit 4: shifts only push
    logic [31:0] up_stg  = 32'h0;              // while armed
    logic  [5:0] up_cnt  = 6'd0;
    logic [31:0] up_wcnt = 32'h0;              // words pushed, out on TDO
    logic [31:0] up_rbk  = 32'h0;

    wire        up_push      = up_sdr & (up_cnt == 6'd31) & up_arm;
    wire [31:0] up_push_word = {up_tdi, up_stg[31:1]};

    always_ff @(posedge up_tck) begin
        if (up_cdr) begin
            up_cnt <= 6'd0;
            up_rbk <= up_wcnt;
        end else if (up_sdr) begin
            up_stg <= {up_tdi, up_stg[31:1]};
            up_cnt <= (up_cnt == 6'd31) ? 6'd0 : up_cnt + 6'd1;
            up_rbk <= {1'b0, up_rbk[31:1]};
        end
        if (up_push)
            up_wcnt <= up_wcnt + 32'd1;
    end

    always_comb up_tdo = up_rbk[0];

    // ------------------------------------------------------------------
    // The upload FIFO. Four image bytes per word; the chipset side pops and
    // writes them one SDRAM word each. Flush is a level off the control
    // slot: held, it clears the FIFO and the byte offset, so "flush then
    // stream" restarts a botched upload without touching anything else.
    // ------------------------------------------------------------------
    logic        flush_lvl;
    wire         up_aclr = flush_lvl | power_reset;
    wire         up_empty;
    wire         up_wrfull;
    wire [31:0]  up_q;
    wire  [8:0]  up_usedw;
    logic        up_rdreq;

    dcfifo dcfifo_upload (
        .data    (up_push_word),
        .wrclk   (up_tck),
        .wrreq   (up_push & ~up_wrfull),
        .rdclk   (clk),
        .rdreq   (up_rdreq),
        .q       (up_q),
        .rdempty (up_empty),
        .wrfull  (up_wrfull),
        .wrusedw (up_usedw),
        .aclr    (up_aclr),
        .wrempty (),
        .rdfull  (),
        .rdusedw (),
        .eccstatus()
    );
    defparam dcfifo_upload.clocks_are_synchronized = "FALSE",
        dcfifo_upload.intended_device_family = "Cyclone V",
        dcfifo_upload.lpm_numwords = 512, dcfifo_upload.lpm_showahead = "OFF",
        dcfifo_upload.lpm_type = "dcfifo", dcfifo_upload.lpm_width = 32,
        dcfifo_upload.lpm_widthu = 9,
        dcfifo_upload.overflow_checking = "OFF",
        dcfifo_upload.rdsync_delaypipe = 5,
        dcfifo_upload.underflow_checking = "OFF",
        dcfifo_upload.use_eab = "ON", dcfifo_upload.wrsync_delaypipe = 5;

    // ------------------------------------------------------------------
    // fdd_mount()'s row order (firmware/fdd_service.c): eject first so the
    // change line registers the insert, geometry next, write-protect (the
    // image is read-only in v1), present last. Drive B is emptied so the
    // machine's state is deterministic while this server owns the bus.
    // ------------------------------------------------------------------
    function automatic logic [31:0] mnt_row(input logic [3:0] i);
        case (i)
            4'd0:    mnt_row = {16'hF280, 16'd0};     // B: present = 0
            4'd1:    mnt_row = {16'hF200, 16'd0};     // A: present = 0
            // (the gap runs between rows 1 and 2)
            4'd2:    mnt_row = {16'hF202, 16'd77};    // cylinders
            4'd3:    mnt_row = {16'hF203, 16'd8};     // sectors per track
            4'd4:    mnt_row = {16'hF204, 16'd1232};  // total sectors
            4'd5:    mnt_row = {16'hF205, 16'd2};     // heads
            4'd6:    mnt_row = {16'hF206, 16'd1};     // N=3: 1024 B sectors
            4'd7:    mnt_row = {16'hF201, 16'd1};     // write-protected
            default: mnt_row = {16'hF200, 16'd1};     // A: present = 1
        endcase
    endfunction

    // ------------------------------------------------------------------
    // State. Everything clocked lives in ONE block so no register has two
    // drivers. `power_reset` clears the persistent half (en, arm, offsets);
    // `reset` aborts in-flight work only -- the RAM disk must ride out the
    // guest reset that boots from it.
    // ------------------------------------------------------------------
    typedef enum logic [4:0] {
        S_IDLE     = 5'd0,
        S_MNT      = 5'd1,   // a mount-table write per clock
        S_MNT_GAP  = 5'd2,   // the eject/insert separation
        S_UMNT     = 5'd3,   // the disable-time eject
        S_RD_LBA   = 5'd4,   // management read of request register 0
        S_RD_REQ   = 5'd5,   // issue a one-word carve-out read
        S_RD_BEAT  = 5'd6,   // an rvalid beat pushes one FIFO byte
        S_WR_DR    = 5'd7,   // drain a write/format FIFO, drop the bytes
        S_UP_POP   = 5'd8,
        S_UP_CAP   = 5'd9,
        S_UP_WREQ  = 5'd10,  // one SDRAM write per byte of the popped word
        S_UP_WDONE = 5'd11,
        S_RB_REQ   = 5'd12,
        S_RB_CAP   = 5'd13
    } state_t;

    state_t      st;
    logic        en, mounted;
    logic        mount_pending, unmount_pending;
    logic        greset_req;
    logic  [3:0] mnt_idx;
    logic  [7:0] gap_cnt;
    logic [14:0] req_lba;
    logic [10:0] beat_cnt;   // bytes received this sector, 0..1024
    logic [20:0] up_off;     // image byte offset the next word lands at
    logic [31:0] up_word;
    logic  [1:0] up_bi;
    logic        up_wpend;   // a popped word still owes SDRAM writes
    logic [20:0] rb_off;
    logic        rb_abs;
    logic        rb_pend;
    logic  [7:0] rb_byte;
    logic [14:0] last_lba;
    logic  [7:0] serve_cnt;
    logic [15:0] wd;         // watchdog -- no wait outlives ~1.5 ms

    assign own             = en | unmount_pending;
    assign guest_reset_req = greset_req;

    // fw_busy is kept on the port list for the mux contract, but nothing here
    // defers to it anymore: the only strobe that cannot wait is the rvalid
    // push, which must fire on the beat's own cycle -- it wins the mux by
    // construction (ri_stb), and the firmware's fenced F2 traffic is the side
    // that can be safely dropped.
    wire _unused_fw = fw_busy;

    // Slot 0x87 (ctl_addr 7'h07), one 32-bit word:
    //   [0] enable   -- level; the rising edge mounts, a fall ejects
    //   [1] flush    -- level; held, clears the upload FIFO and byte offset
    //   [2] greset   -- writing 1 pulses guest_reset_req into reset_wire
    //   [3] remount  -- writing 1 while enabled re-runs the mount pass
    //   [4] arm      -- stream-sink push enable for the second SLD node
    // Slot 0x88 (ctl_addr 7'h08): rb_off[20:0] -- a byte offset into the
    // image, read back through dbg2 for upload verify. Bit 21 switches the
    // readback to absolute SDRAM word space, so the same probe can inspect
    // conventional guest RAM (byte N == word N) -- vectors, work area, a
    // result mailbox -- not just the carve-out.
    wire ctl_wr  = ctl_pulse && (ctl_addr == 7'h07);
    wire ctl_rba = ctl_pulse && (ctl_addr == 7'h08);

    wire [31:0] mnt_row_v = mnt_row(mnt_idx);
    wire  [7:0] up_byte   = up_word[8*up_bi +: 8];
    // The carve-out address of the word being burst-read: the byte offset is
    // lba*1024 + beat_cnt, and byte-per-word makes that the word address.
    wire [23:0] sec_word  = CARVE_BASE + (24'(req_lba) << 10)
                          + 24'(beat_cnt);

    always_ff @(posedge clk or posedge power_reset) begin
        if (power_reset) begin
            en              <= 1'b0;
            mounted         <= 1'b0;
            mount_pending   <= 1'b0;
            unmount_pending <= 1'b0;
            flush_lvl       <= 1'b0;
            up_arm          <= 1'b0;
            greset_req      <= 1'b0;
            up_off          <= 21'd0;
            up_word         <= 32'd0;
            up_bi           <= 2'd0;
            up_wpend        <= 1'b0;
            rb_off          <= 21'd0;
            rb_abs          <= 1'b0;
            rb_pend         <= 1'b0;
            rb_byte         <= 8'd0;
            last_lba        <= 15'd0;
            serve_cnt       <= 8'd0;
            st              <= S_IDLE;
            mnt_idx         <= 4'd0;
            gap_cnt         <= 8'd0;
            req_lba         <= 15'd0;
            beat_cnt        <= 11'd0;
            wd              <= 16'd0;
        end else if (reset) begin
            // Abort in-flight work; the configuration -- en, mounted, the
            // upload offset, a half-written word's debt -- survives.
            st          <= S_IDLE;
            mnt_idx     <= 4'd0;
            gap_cnt     <= 8'd0;
            req_lba     <= 15'd0;
            beat_cnt    <= 11'd0;
            wd          <= 16'd0;
            up_bi       <= 2'd0;
            greset_req  <= 1'b0;
        end else begin
            greset_req <= 1'b0;                     // one clock per write

            // Control writes land here, not in the FSM, so they hold their
            // meaning while the engine is busy.
            if (ctl_wr) begin
                if (ctl_data[0] & ~en)          mount_pending <= 1'b1;
                if (ctl_data[0] & ctl_data[3])  mount_pending <= 1'b1;
                if (~ctl_data[0] & en)          unmount_pending <= 1'b1;
                en        <= ctl_data[0];
                flush_lvl <= ctl_data[1];
                up_arm    <= ctl_data[4];
                if (ctl_data[1]) begin
                    up_off   <= 21'd0;          // flush: restart the stream
                    up_wpend <= 1'b0;
                end
                if (ctl_data[2]) greset_req <= 1'b1;
            end
            if (ctl_rba) begin
                rb_off  <= ctl_data[20:0];
                rb_abs  <= ctl_data[21];
                rb_pend <= 1'b1;
            end

            case (st)
                // Priorities: mount before requests, requests before the
                // readback probe, the probe before the upload drain -- a
                // sector in flight never waits behind JTAG housekeeping.
                S_IDLE: begin
                    wd <= 16'd0;
                    if (mount_pending && en) begin
                        st      <= S_MNT;
                        mnt_idx <= 4'd0;
                    end else if (unmount_pending) begin
                        st <= S_UMNT;
                    end else if (mounted && fdd_request[0]) begin
                        st <= S_RD_LBA;
                    end else if (mounted && fdd_request[1]) begin
                        st <= S_WR_DR;
                    end else if (rb_pend) begin
                        st <= S_RB_REQ;
                    end else if (up_wpend && !flush_lvl) begin
                        st    <= S_UP_WREQ;
                        up_bi <= 2'd0;
                    end else if (!up_empty && !flush_lvl) begin
                        // The upload runs enabled or not: the image lands
                        // before the mount either way, and an enable does not
                        // stop a stream's tail from writing through.
                        st <= S_UP_POP;
                    end
                end

                S_MNT: begin
                    // mgmt_wr is high this cycle (comb below); the row lands
                    // at this edge. The gap splits the eject from the insert.
                    if (mnt_idx == 4'd8) begin
                        mounted       <= 1'b1;
                        mount_pending <= 1'b0;
                        st            <= S_IDLE;
                    end else if (mnt_idx == 4'd1) begin
                        mnt_idx <= mnt_idx + 4'd1;
                        gap_cnt <= 8'hFF;
                        st      <= S_MNT_GAP;
                    end else begin
                        mnt_idx <= mnt_idx + 4'd1;
                    end
                end

                S_MNT_GAP: begin
                    if (gap_cnt == 8'd0) st <= S_MNT;
                    else                 gap_cnt <= gap_cnt - 8'd1;
                end

                S_UMNT: begin
                    mounted         <= 1'b0;
                    unmount_pending <= 1'b0;
                    mount_pending   <= 1'b0;
                    st              <= S_IDLE;
                end

                // ---- a sector read -------------------------------------
                S_RD_LBA: begin
                    // mgmt_readdata is a combinational decode of the held
                    // address (floppy.v's assign), so the {drive, lba} pair
                    // is valid on THIS cycle while the strobe keeps
                    // mgmt_addr at F200 -- it is gone a state later.
                    req_lba    <= mgmt_din[14:0];
                    last_lba   <= mgmt_din[14:0];
                    beat_cnt   <= 11'd0;
                    wd         <= 16'd0;
                    st         <= S_RD_REQ;
                end
                S_RD_REQ: begin
                    wd <= wd + 16'd1;
                    if (sd_ack) begin
                        wd <= 16'd0;
                        st <= S_RD_BEAT;
                    end else if (&wd || !fdd_request[0]) begin
                        st <= S_IDLE;
                    end
                end
                S_RD_BEAT: begin
                    wd <= wd + 16'd1;
                    if (sd_rvalid) begin
                        // One word per request: this beat IS the whole
                        // transaction -- push it, then either stop at 1024
                        // or ask for the next word.
                        wd       <= 16'd0;
                        beat_cnt <= beat_cnt + 11'd1;
                        if (beat_cnt == 11'd1023) begin
                            if (serve_cnt != 8'hFF)
                                serve_cnt <= serve_cnt + 8'd1;
                            st <= S_IDLE;
                        end else begin
                            st <= S_RD_REQ;
                        end
                    end
                    if (!fdd_request[0] || &wd) st <= S_IDLE;
                end

                // ---- a write or format: drain the FIFO, drop it --------
                S_WR_DR: begin
                    wd <= wd + 16'd1;
                    // mgmt_rd held high pops a byte a clock until the
                    // controller sees the FIFO empty and drops the request;
                    // the watchdog bounds a wedged command at 32K pops.
                    if (!fdd_request[1] || wd[15]) st <= S_IDLE;
                end

                // ---- the upload stream ---------------------------------
                S_UP_POP: begin
                    st <= S_UP_CAP;
                end
                S_UP_CAP: begin
                    up_word <= up_q;
                    up_bi   <= 2'd0;
                    wd      <= 16'd0;
                    // A word that would spill past the image is dropped --
                    // the stream carrier is padding-tolerant.
                    if (up_off + 21'd4 <= 21'(IMG_BYTES)) begin
                        up_wpend <= 1'b1;
                        st       <= S_UP_WREQ;
                    end else begin
                        st <= S_IDLE;
                    end
                end
                S_UP_WREQ: begin
                    wd <= wd + 16'd1;
                    if (sd_ack) st <= S_UP_WDONE;
                    else if (&wd) begin
                        // A dead SDRAM must not hold this FSM; the word is
                        // lost, loudly (up_off no longer tracks the stream).
                        up_wpend <= 1'b0;
                        st       <= S_IDLE;
                    end
                end
                S_UP_WDONE: begin
                    wd <= wd + 16'd1;
                    if (sd_done) begin
                        wd <= 16'd0;
                        if (up_bi == 2'd3) begin
                            up_wpend <= 1'b0;
                            up_off   <= up_off + 21'd4;
                            st       <= S_IDLE;
                        end else begin
                            up_bi <= up_bi + 2'd1;
                            st    <= S_UP_WREQ;
                        end
                    end else if (&wd) begin
                        up_wpend <= 1'b0;
                        st       <= S_IDLE;
                    end
                end

                // ---- the readback probe --------------------------------
                S_RB_REQ: begin
                    wd <= wd + 16'd1;
                    if (sd_ack) st <= S_RB_CAP;
                    else if (&wd) begin
                        rb_pend <= 1'b0;
                        st      <= S_IDLE;
                    end
                end
                S_RB_CAP: begin
                    wd <= wd + 16'd1;
                    if (sd_rvalid) begin
                        rb_byte <= sd_rdata[7:0];
                        rb_pend <= 1'b0;
                        st      <= S_IDLE;
                    end else if (&wd) begin
                        rb_pend <= 1'b0;
                        st      <= S_IDLE;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Combinational drives: the management strobes, the SDRAM request, the
    // FIFO pop. The FIFO push in S_RD_BEAT must fire ON the rvalid cycle --
    // the next beat's word lands on the data bus one clock later.
    // ------------------------------------------------------------------
    always_comb begin
        mgmt_addr = 16'h0000;
        mgmt_dout = 16'h0000;
        mgmt_wr   = 1'b0;
        mgmt_rd   = 1'b0;
        sd_req    = 1'b0;
        sd_we     = 1'b0;
        sd_addr   = 24'h000000;
        sd_len    = 4'd0;
        sd_wdata  = 16'h0000;
        up_rdreq  = 1'b0;
        case (st)
            S_MNT: begin
                mgmt_addr = mnt_row_v[31:16];
                mgmt_dout = mnt_row_v[15:0];
                mgmt_wr   = 1'b1;
            end
            S_UMNT: begin
                mgmt_addr = 16'hF200;   // drive A, register 0: present = 0
                mgmt_dout = 16'd0;
                mgmt_wr   = 1'b1;
            end
            S_RD_LBA: begin
                mgmt_addr = 16'hF200;   // register 0: {drive, lba}
                mgmt_rd   = 1'b1;
            end
            S_RD_REQ: begin
                sd_req  = 1'b1;
                sd_addr = sec_word;
                sd_len  = 4'd0;         // one word -- see the header on why
            end
            S_RD_BEAT: begin
                if (sd_rvalid) begin
                    mgmt_addr = 16'hF20F;
                    mgmt_dout = {8'h00, sd_rdata[7:0]};
                    mgmt_wr   = 1'b1;
                end
            end
            S_WR_DR: begin
                mgmt_addr = 16'hF20F;   // held: pops one byte per clock
                mgmt_rd   = 1'b1;
            end
            S_UP_POP: begin
                up_rdreq = 1'b1;
            end
            S_UP_WREQ: begin
                sd_req   = 1'b1;
                sd_we    = 1'b1;
                sd_addr  = CARVE_BASE + 24'(up_off) + 24'(up_bi);
                sd_wdata = {8'h00, up_byte};
            end
            S_UP_WDONE: begin
                // sdram_mp samples the write data combinationally during the
                // WRITE beat, which lands between ack and done -- the data
                // must stay on the pins for the whole transaction.
                sd_we    = 1'b1;
                sd_wdata = {8'h00, up_byte};
                sd_addr  = CARVE_BASE + 24'(up_off) + 24'(up_bi);
            end
            S_RB_REQ: begin
                sd_req  = 1'b1;
                sd_addr = rb_abs ? {3'b000, rb_off} : CARVE_BASE + 24'(rb_off);
            end
            default: ;
        endcase
    end

    // ------------------------------------------------------------------
    // Probe readback (slots 0x35/0x36/0x37 in core_top). The 0x52 tag makes
    // "feature built in" readable before anything else is trusted -- an
    // undecoded slot answers 8'hDEAD00xx, which cannot collide with it.
    // ------------------------------------------------------------------
    assign dbg0 = {8'h52, en, mounted, up_arm, flush_lvl, st, last_lba};
    assign dbg1 = {2'b00, up_usedw, up_off};
    assign dbg2 = {rb_pend, 2'b00, rb_off, rb_byte};

endmodule

`default_nettype wire
