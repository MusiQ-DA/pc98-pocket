//
// pc98_scsi -- the PC-9801-55's SCSI register window, and nothing else.
//
// WHAT THIS IS. The board is a WD33C93 behind four I/O ports, and the
// controller is addressed INDIRECTLY: 0xCC0 selects a register, 0xCC2 reads or
// writes the selected one and post-increments the index. 0xCC6 is a byte port
// onto a data buffer with its own read and write pointers. That is the whole
// hardware interface, and it is what this module implements.
//
// WHAT THIS IS NOT. It does not interpret a single SCSI command. Writing the
// CMD register (index 0x18) raises cmd_req and hands the byte over; the
// softcore's firmware reads the CDB out of the register file, does the work
// against the disk image on the SD card, fills the data buffer and writes the
// status back. That is the same split np2kai uses -- its scsibios.res is `CB 90 90`
// entries plus a `55 AA` signature, about a kilobyte of nothing, with every
// command handled on the host side.
//
// Doing it the other way -- a command interpreter in RTL -- would cost far
// more than the device has. np2's model alone carries reg[0x30], a phase
// machine, a 64 KB buffer and two 8 KB BIOS banks.
//
// REFERENCE. np2kai cbus/scsiio.c (the four port handlers) and cbus/scsiio.tbl
// (the register indices), read as behaviour, not copied as code.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

`default_nettype none

module pc98_scsi #(
    // Bytes in the data buffer. np2 masks its pointers to 0x7FFF; 8 KB is
    // sixteen 512-byte sectors, enough for the multi-sector reads the disk
    // BIOS issues, and one M10K row less than a power of two would waste.
    parameter int DATA_BYTES = 8192,
    parameter int DATA_AW    = 13
) (
    input  wire        clk,
    input  wire        rst,

    // ---- guest side -------------------------------------------------------
    // cs is the decode for 0xCC0-0xCC7; a1a2 picks the port within it:
    //   00 -> 0xCC0   01 -> 0xCC2   10 -> 0xCC4   11 -> 0xCC6
    input  wire        cs,
    input  wire  [1:0] a1a2,
    input  wire        io_read_n,
    input  wire        io_write_n,
    input  wire  [7:0] data_in,
    output logic [7:0] data_out,
    output wire        read_select,

    // ---- softcore side ----------------------------------------------------
    // cmd_req TOGGLES per command, the mailbox idiom the rest of this core
    // uses (pc98_kbd_ps2's key_stb, the OSD's vkb_stb): a level would have to
    // be acknowledged in a second place and a pulse can be missed across the
    // clock domains the firmware polls in.
    output logic       cmd_req,
    output logic [7:0] cmd_byte,

    // The firmware's window on the same state. reg_addr selects a control
    // register (0x00-0x19); buf_* is the data buffer.
    input  wire  [4:0] mg_reg_addr,
    input  wire        mg_reg_we,
    input  wire  [7:0] mg_reg_wdata,
    output logic [7:0] mg_reg_rdata,

    input  wire [DATA_AW-1:0] mg_buf_addr,
    input  wire        mg_buf_we,
    input  wire  [7:0] mg_buf_wdata,
    output logic [7:0] mg_buf_rdata,

    // Status the firmware drives back at the guest, and the pointers it has
    // to be able to rewind before filling the buffer for a read.
    input  wire  [7:0] mg_auxstatus,
    input  wire        mg_auxstatus_we,
    input  wire  [7:0] mg_scsistatus,
    input  wire        mg_scsistatus_we,
    input  wire        mg_rdptr_clr,
    input  wire        mg_wrptr_clr
);

    // ---- the indirect index ----------------------------------------------
    logic [7:0] idx;

    // Control registers 0x00-0x19. 0x03-0x0E double as the CDB (SCSICTR_CDB is
    // 0x03 in np2's table), which is why the auto-increment matters: the BIOS
    // writes a whole command descriptor block by writing 0xCC2 repeatedly.
    logic [7:0] ctrl [0:25];

    // The registers outside that range that answer at all (np2 scsiio_icc2).
    logic [7:0] membank;   // 0x30 -- bit 6 picks which 8 KB BIOS bank is at D2000
    logic [7:0] memwnd;    // 0x31
    logic [7:0] resent;    // 0x33
    logic [7:0] datmap;    // 0x3F, written as bit set/reset

    logic [7:0] auxstatus; // 0xCC0 read, and reading CLEARS it
    logic [7:0] scsistatus;// 0xCC2 read at index 0x17

    localparam [7:0] IDX_STATUS  = 8'h17;
    localparam [7:0] IDX_CMD     = 8'h18;
    localparam [7:0] IDX_MEMBANK = 8'h30;
    localparam [7:0] IDX_MEMWND  = 8'h31;
    localparam [7:0] IDX_RESENT  = 8'h33;
    localparam [7:0] IDX_TWOCARD = 8'h36;  // "2 boards installed?" -- always 0
    localparam [7:0] IDX_DATMAP  = 8'h3F;

    wire sel_cc0 = cs & (a1a2 == 2'b00);
    wire sel_cc2 = cs & (a1a2 == 2'b01);
    wire sel_cc4 = cs & (a1a2 == 2'b10);
    wire sel_cc6 = cs & (a1a2 == 2'b11);

    wire wr = ~io_write_n;
    wire rd = ~io_read_n;

    // Commit on the trailing edge of the strobe, with the byte sampled while
    // it is low. The address bus is still moving at the start of a cycle --
    // the same hazard the sysport latch and post_monitor's I/O history are
    // written around -- and an index latched early selects the wrong register.
    logic       wr_q;
    logic [7:0] wr_data_q;
    logic [1:0] wr_port_q;
    logic       rd_q;
    logic [1:0] rd_port_q;

    // ---- the data buffer --------------------------------------------------
    (* ramstyle = "M10K" *) logic [7:0] dbuf [0:DATA_BYTES-1];
    logic [DATA_AW-1:0] wrptr, rdptr;
    logic [7:0] dbuf_q;      // guest read port, registered
    logic [7:0] mg_buf_q;    // firmware read port, registered

    always_ff @(posedge clk) begin
        if (sel_cc6 && wr)                      dbuf[wrptr]      <= wr_data_q;
        else if (mg_buf_we)                     dbuf[mg_buf_addr] <= mg_buf_wdata;
        dbuf_q   <= dbuf[rdptr];
        mg_buf_q <= dbuf[mg_buf_addr];
    end
    assign mg_buf_rdata = mg_buf_q;

    // ---- control registers ------------------------------------------------
    always_ff @(posedge clk) begin
        if (mg_reg_we)                       ctrl[mg_reg_addr] <= mg_reg_wdata;
        else if (wr_q && ~wr && (wr_port_q == 2'b01) && (idx <= 8'h19))
                                             ctrl[idx[4:0]]    <= wr_data_q;
        mg_reg_rdata <= ctrl[mg_reg_addr];
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            idx        <= 8'h00;
            membank    <= 8'h00;
            memwnd     <= 8'h00;
            resent     <= 8'h00;
            datmap     <= 8'h00;
            auxstatus  <= 8'h00;
            scsistatus <= 8'h00;
            wrptr      <= '0;
            rdptr      <= '0;
            cmd_req    <= 1'b0;
            cmd_byte   <= 8'h00;
            wr_q       <= 1'b0;
            rd_q       <= 1'b0;
            wr_data_q  <= 8'h00;
            wr_port_q  <= 2'b00;
            rd_port_q  <= 2'b00;
        end else begin
            wr_q <= cs & wr;
            rd_q <= cs & rd;
            if (cs & wr) begin
                wr_data_q <= data_in;
                wr_port_q <= a1a2;
            end
            if (cs & rd)
                rd_port_q <= a1a2;

            // The firmware's writes. Taken before the guest's so a status
            // landing on the same cycle as a read does not lose the update.
            if (mg_auxstatus_we)  auxstatus  <= mg_auxstatus;
            if (mg_scsistatus_we) scsistatus <= mg_scsistatus;
            if (mg_rdptr_clr)     rdptr      <= '0;
            if (mg_wrptr_clr)     wrptr      <= '0;

            // ---- guest writes, on the trailing edge ----------------------
            if (wr_q && ~wr) begin
                case (wr_port_q)
                    2'b00: idx <= wr_data_q;            // 0xCC0: select
                    2'b01: begin                        // 0xCC2: the register
                        if (idx <= 8'h19) begin
                            idx <= idx + 8'd1;
                            // Writing CMD is what starts a command. The byte
                            // goes with the toggle so the firmware does not
                            // have to race the register file for it.
                            if (idx == IDX_CMD) begin
                                cmd_byte <= wr_data_q;
                                cmd_req  <= ~cmd_req;
                            end
                        end
                        else begin
                            case (idx)
                                IDX_MEMBANK: membank <= wr_data_q;
                                IDX_MEMWND:  memwnd  <= wr_data_q;
                                IDX_RESENT:  resent  <= wr_data_q;
                                // np2 scsiio_occ2 case 0x3f: bit set/reset,
                                // value bit 3 is the direction and bits 2-0
                                // the bit number.
                                IDX_DATMAP:
                                    if (wr_data_q[3])
                                        datmap[wr_data_q[2:0]] <= 1'b1;
                                    else
                                        datmap[wr_data_q[2:0]] <= 1'b0;
                                default: ;
                            endcase
                        end
                    end
                    2'b10: ;                            // 0xCC4: np2 discards
                    2'b11: wrptr <= wrptr + 1'b1;       // 0xCC6: buffer
                endcase
            end

            // ---- guest reads, on the trailing edge -----------------------
            // Reading advances state; the DATA the guest sees is combinational
            // below, off the pre-increment index.
            if (rd_q && ~rd) begin
                case (rd_port_q)
                    2'b00: auxstatus <= 8'h00;          // 0xCC0 read clears it
                    2'b01: if (idx <= 8'h19 || idx == IDX_STATUS)
                               idx <= idx + 8'd1;
                    2'b11: rdptr <= rdptr + 1'b1;       // 0xCC6: buffer
                    default: ;
                endcase
            end
        end
    end

    assign read_select = cs & rd;

    always_comb begin
        case (a1a2)
            2'b00: data_out = auxstatus;
            2'b01: begin
                case (idx)
                    IDX_STATUS:  data_out = scsistatus;
                    IDX_MEMBANK: data_out = membank;
                    IDX_MEMWND:  data_out = memwnd;
                    IDX_RESENT:  data_out = resent;
                    IDX_TWOCARD: data_out = 8'h00;
                    default:     data_out = (idx <= 8'h19) ? mg_ctrl_q : 8'hFF;
                endcase
            end
            2'b10: data_out = 8'h00;                    // np2 scsiio_icc4
            2'b11: data_out = dbuf_q;
        endcase
    end

    // The guest's view of the control file, registered off idx the same way
    // the buffer's is off rdptr, so both read ports are real M10K ports.
    logic [7:0] mg_ctrl_q;
    always_ff @(posedge clk)
        mg_ctrl_q <= ctrl[idx[4:0]];

endmodule

`default_nettype wire
