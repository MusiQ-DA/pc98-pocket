//
// tb_scsi_target -- a bench stand-in for the softcore's SCSI service
// (firmware/scsi_service.c), driving pc98_scsi's management ports exactly as
// Peripherals' mailbox does: it sees cmd_req toggle, reads the CDB out of the
// control file at index 3, answers from an image file and posts auxstatus
// bit 7 plus a status byte.
//
// The firmware itself is tested on the host (scripts/sim_scsi_fw.sh runs the
// shipped C against a model of these same ports); this model only has to be
// faithful enough to let the REAL BIOS and the REAL option ROM boot on the
// RTL window. The image's layout comes in as plusargs computed by that host
// build (`scsi_fw_host probe`), so the bench serves the same base offset and
// geometry the firmware would:
//   +hddimg=FILE +hdd_base=N +hdd_c=N +hdd_h=N +hdd_s=N +hdd_n=SECTORS
//
// Commands: TEST UNIT READY, REQUEST SENSE, FORMAT/REZERO/SEEK (no-ops),
// INQUIRY, MODE SENSE(6) pages 3/4/3F, READ CAPACITY, READ(10), WRITE(10)
// -- the set scsi_rom.asm issues.
//
`default_nettype none
`timescale 1ns/1ps

module tb_scsi_target #(
    parameter int MAX_BYTES = 8 * 1024 * 1024,
    parameter int LATENCY   = 400           // clocks from request to work
) (
    input  wire        clk,
    input  wire        cmd_req,

    output logic [4:0]  reg_addr,
    output logic        reg_we,
    output logic [7:0]  reg_wdata,
    input  wire  [7:0]  reg_rdata,

    output logic [12:0] buf_addr,
    output logic        buf_we,
    output logic [7:0]  buf_wdata,
    input  wire  [7:0]  buf_rdata,

    output logic [7:0]  aux,
    output logic        aux_we,
    output logic [7:0]  status,
    output logic        status_we,
    output logic        rdptr_clr,
    output logic        wrptr_clr,

    output int          n_cmds
);

    logic [7:0] img [0:MAX_BYTES-1];
    int img_len = 0;
    int base = 0, cyls = 0, heads = 0, spt = 0, sectors = 0;
    bit present = 0;
    logic [7:0] sense_key = 0, asc = 0;

    initial begin
        string p;
        int fd;
        if ($value$plusargs("hddimg=%s", p)) begin
            fd = $fopen(p, "rb");
            if (fd != 0) begin
                img_len = $fread(img, fd);
                $fclose(fd);
            end
            void'($value$plusargs("hdd_base=%d", base));
            void'($value$plusargs("hdd_c=%d", cyls));
            void'($value$plusargs("hdd_h=%d", heads));
            void'($value$plusargs("hdd_s=%d", spt));
            void'($value$plusargs("hdd_n=%d", sectors));
            present = (img_len > 0) && (sectors > 0)
                   && (base + sectors * 512 <= img_len);
            $display("SCSI target: %s %0d bytes, base %0d, C/H/S %0d/%0d/%0d, %0d sectors%s",
                     p, img_len, base, cyls, heads, spt, sectors,
                     present ? "" : "  -- NOT MOUNTED");
        end
    end

    // ---- one mgmt access per falling edge; the RTL samples on the rising
    task automatic tick();
        @(negedge clk);
        reg_we = 0; buf_we = 0; aux_we = 0; status_we = 0;
        rdptr_clr = 0; wrptr_clr = 0;
    endtask

    task automatic get_ctrl(input int a, output logic [7:0] v);
        @(negedge clk);
        reg_we = 0; buf_we = 0;
        reg_addr = 5'(a);
        @(negedge clk);              // the RTL registered ctrl[a] on the rise
        v = reg_rdata;
    endtask

    int wp;                          // our write pointer into the buffer
    task automatic put(input logic [7:0] v);
        @(negedge clk);
        buf_addr = 13'(wp); buf_wdata = v; buf_we = 1;
        wp++;
    endtask

    task automatic get_buf(input int a, output logic [7:0] v);
        @(negedge clk);
        buf_we = 0;
        buf_addr = 13'(a);
        @(negedge clk);
        v = buf_rdata;
    endtask

    task automatic begin_reply();
        @(negedge clk); wrptr_clr = 1;
        tick();
        wp = 0;
    endtask

    task automatic complete(input logic [7:0] st);
        tick();
        rdptr_clr = 1;               // the guest reads from 0
        tick();
        status = st; status_we = 1;
        tick();
        aux = 8'h80; aux_we = 1;     // INT: finished, collect status
        tick();
    endtask

    task automatic fail(input logic [7:0] key, input logic [7:0] code);
        sense_key = key; asc = code;
        complete(8'h02);
    endtask

    task automatic ok();
        sense_key = 0; asc = 0;
        complete(8'h00);
    endtask

    task automatic mode_sense(input logic [7:0] cdb1, input logic [7:0] page,
                              input int alloc);
        bit p3, p4;
        int bdl, n, blocks;
        logic [7:0] b [0:59];
        p3 = (page == 8'h03) || (page == 8'h3F);
        p4 = (page == 8'h04) || (page == 8'h3F);
        if (!p3 && !p4 && page != 0) begin
            fail(8'h05, 8'h24);
            return;
        end
        for (int i = 0; i < 60; i++) b[i] = 0;
        bdl = cdb1[3] ? 0 : 8;
        blocks = sectors > 32'hFFFFFF ? 32'hFFFFFF : sectors;
        n = 4;
        b[1] = 0; b[2] = 0; b[3] = 8'(bdl);
        if (bdl != 0) begin
            b[5] = 8'(blocks >> 16); b[6] = 8'(blocks >> 8); b[7] = 8'(blocks);
            b[10] = 8'h02;
            n = 12;
        end
        if (p3) begin
            b[n] = 8'h03; b[n+1] = 8'h16;
            b[n+10] = 8'(spt >> 8); b[n+11] = 8'(spt);
            b[n+12] = 8'h02; b[n+15] = 8'h01; b[n+20] = 8'h40;
            n += 24;
        end
        if (p4) begin
            b[n] = 8'h04; b[n+1] = 8'h16;
            b[n+2] = 8'(cyls >> 16); b[n+3] = 8'(cyls >> 8); b[n+4] = 8'(cyls);
            b[n+5] = 8'(heads);
            n += 24;
        end
        b[0] = 8'(n - 1);
        begin_reply();
        for (int i = 0; i < n && i < alloc; i++) put(b[i]);
        ok();
    endtask

    logic [7:0] cdb [0:11];
    int lba, cnt;

    always begin
        logic ack;
        ack = 0;
        reg_addr = 0; reg_we = 0; reg_wdata = 0;
        buf_addr = 0; buf_we = 0; buf_wdata = 0;
        aux = 0; aux_we = 0; status = 0; status_we = 0;
        rdptr_clr = 0; wrptr_clr = 0;
        n_cmds = 0;
        forever begin
            @(negedge clk);
            if (cmd_req !== ack) begin
                ack = cmd_req;
                repeat (LATENCY) @(negedge clk);
                for (int i = 0; i < 12; i++) get_ctrl(3 + i, cdb[i]);
                n_cmds++;
                case (cdb[0])
                    8'h00: if (present) ok(); else fail(8'h02, 8'h3A);
                    8'h01, 8'h04, 8'h0B, 8'h15, 8'h1B, 8'h2B: ok();
                    8'h03: begin
                        logic [7:0] k, a;
                        k = sense_key; a = asc;
                        begin_reply();
                        for (int i = 0; i < 18; i++)
                            if (i < cdb[4] || cdb[4] == 0)
                                put(i == 0 ? 8'h70 : i == 2 ? k : i == 7 ? 8'd10
                                    : i == 12 ? a : 8'h00);
                        sense_key = 0; asc = 0;
                        complete(8'h00);
                    end
                    8'h12: begin
                        begin_reply();
                        for (int i = 0; i < 36; i++)
                            put(i == 2 ? 8'h01 : i == 3 ? 8'h01 : i == 4 ? 8'd31 : 8'h20);
                        ok();
                    end
                    8'h1A: mode_sense(cdb[1], cdb[2] & 8'h3F, int'(cdb[4]));
                    8'h25: if (!present) fail(8'h02, 8'h3A);
                           else begin
                               begin_reply();
                               put(8'((sectors - 1) >> 24)); put(8'((sectors - 1) >> 16));
                               put(8'((sectors - 1) >> 8));  put(8'(sectors - 1));
                               put(0); put(0); put(8'h02); put(0);
                               ok();
                           end
                    8'h28, 8'h2A: begin
                        lba = {cdb[2], cdb[3], cdb[4], cdb[5]};
                        cnt = {cdb[7], cdb[8]};
                        if (cnt > 16) cnt = 16;
                        if (!present) fail(8'h02, 8'h3A);
                        else if (lba + cnt > sectors) fail(8'h05, 8'h21);
                        else if (cdb[0] == 8'h28) begin
                            begin_reply();
                            for (int i = 0; i < cnt * 512; i++)
                                put(img[base + lba * 512 + i]);
                            ok();
                        end else begin
                            for (int i = 0; i < cnt * 512; i++) begin
                                logic [7:0] v;
                                get_buf(i, v);
                                img[base + lba * 512 + i] = v;
                            end
                            @(negedge clk); wrptr_clr = 1;
                            ok();
                        end
                    end
                    default: fail(8'h05, 8'h20);
                endcase
                $display("  %0t  SCSI cmd %02X %02X %02X %02X %02X %02X -> status %02X",
                         $time, cdb[0], cdb[1], cdb[2], cdb[3], cdb[4], cdb[5], status);
            end
        end
    end

endmodule

`default_nettype wire
