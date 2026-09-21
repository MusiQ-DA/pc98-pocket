// pc98_fdc.sv -- the machine's floppy controller, as much of a uPD765 as the
// BIOS's power-on sequence asks for.
//
// This lives in its own file because it was written twice -- once here in the
// chipset and once in sim/tb_pc98_boot.sv -- and every fix had to be made
// twice, identically, by hand. Four separate defects came out of this model in
// one session, and a copy that drifts is a bench that proves nothing about the
// bitstream. One module, two instances.
//
// What the BIOS needs from it, in the order it asks:
//
//   FFC00  MSR & D0 == 80   idle, ready for a command byte
//   FFA26  MSR & C0 == 80   ready for a parameter byte (busy masked off)
//   FFC16  MSR & D0 == D0   ready to hand back a result (CB included)
//
// and, after RECALIBRATE on each of units 0-3, one interrupt per unit with a
// SENSE INTERRUPT that names it. Anything less and the BIOS spends 65536
// status reads per command finding out.

module pc98_fdc (
    input  logic        clock,
    input  logic        reset,

    // The guest bus, as the chipset presents it.
    input  logic [15:0] address,
    input  logic        address_enable_n,
    input  logic        io_read_n,
    input  logic        io_write_n,
    input  logic [7:0]  data_in,

    // Which of its ports this cycle names, if any.
    output logic        base_select,
    output logic        msr_select,
    output logic        fifo_select,

    // What it answers with, and the seek-end interrupt.
    output logic [7:0]  msr,
    output logic [7:0]  fifo,
    // Two interrupt lines, because there are two interfaces behind these
    // registers. The BIOS puts the 2HD handler on INT 13 (slave IRQ3, via
    // FF531) and the 2DD handler on INT 12 (slave IRQ2, via FF5FC), and a
    // seek on one interface reported to the other's handler sets no bits at
    // all -- which is the second eleven seconds of the FDD probe.
    output logic        irq_int,       // 2HD, ports 90-93: slave IRQ3
    output logic        irq_2dd        // 2DD, ports C8-CB: slave IRQ2
);

    // 0x90-0x93 (2HD) and 0xC8-0xCB (2DD), the two interfaces this BIOS
    // probes. Even address is the status register, address[1] the data port.
    wire iorq            = ~io_read_n | ~io_write_n;
    wire fdc_io_exact    = iorq & ~address_enable_n & (address[15:8] == 8'h00);
    wire fdc_base_select = fdc_io_exact
                         & ((address[7:2] == 6'h24) | (address[7:2] == 6'h32));
    assign base_select   = fdc_base_select;
    assign msr_select    = fdc_base_select & ~address[1];
    assign fifo_select   = fdc_base_select &  address[1];

    // C8-CB is the 2DD interface, 90-93 the 2HD one. Latched with the command
    // byte, so the seek that completes later still knows where it came from.
    wire cmd_is_2dd = (address[7:2] == 6'h32);

    // Which commands END WITH AN INTERRUPT.
    //
    // On a uPD765 every command with an execution phase raises INT when that
    // phase finishes, and the handler collects the result bytes. Only the
    // three that answer immediately -- SPECIFY, SENSE DRIVE STATUS, SENSE
    // INTERRUPT -- do not. Treating RECALIBRATE and SEEK as the only ones left
    // READ ID sitting in the result phase with seven bytes nobody came for,
    // CB set for good, and the BIOS at FFA1D waiting for CB to clear before it
    // could send anything else.
    function automatic logic cmd_ends_with_int(input logic [7:0] c);
        case (c)
            8'h03, 8'h04, 8'h08: cmd_ends_with_int = 1'b0;
            default:             cmd_ends_with_int = 1'b1;
        endcase
    endfunction

    logic [7:0] fdc_cmd;
    logic [3:0] fdc_writes_left;
    logic [3:0] fdc_results_left;
    logic [3:0] fdc_result_idx;
    logic [7:0] fdc_result0, fdc_result1;
    logic       fdc_in_result;
    logic       fdc_cmd_done;     // high for one clock when a command completes
    // Four milliseconds: shorter than any real recalibrate, and far
    // longer than the handful of instructions the BIOS puts between
    // issuing the seek and clearing its flags.
    localparam int SEEK_CLOCKS = 172_000;
    logic [17:0] seek_timer;
    logic        fdc_want_unit;
    // Which interface the command in flight was written to. They are driven
    // one at a time through POST, so one latch is enough to route the answer.
    logic        seek_is_2dd;

    // One event per ACCESS, not one per clock.
    //
    // fdc_fifo_select is a LEVEL: iorq is asserted for the whole bus cycle,
    // which at 42.95 MHz against a 4.77 MHz CPU is around eighteen chipset
    // clocks. The state machine below consumes a byte every clock it sees the
    // select, so one command byte was consumed eighteen times -- writes_left
    // counted through zero and wrapped to fifteen, cmd_done fired on a command
    // the BIOS had not finished writing, and the model parked in the result
    // phase. MSR then reads C0 for good, and the BIOS sits at FFA26 waiting
    // for 80: the FFA26-FFA2D range the hardware readout came back with.
    //
    // Every other device in this file already takes the prev_io_*_n edges for
    // exactly this reason; the FDC was the one that did not. The address hit
    // is computed without iorq because the strobe has already gone by at the
    // edge being used, and the write byte is latched while the cycle is live
    // -- the bus moves on before the edge, which is the same reason the
    // memory-write path here samples continuously and keeps the last value.
    logic       fdc_prev_wr_n, fdc_prev_rd_n;
    logic [7:0] fdc_wr_data;
    wire fdc_addr_hit  = ~address_enable_n & (address[15:8] == 8'h00)
                       & ((address[7:2] == 6'h24) | (address[7:2] == 6'h32));
    wire fdc_fifo_addr = fdc_addr_hit & address[1];
    wire fdc_wr_pulse  = fdc_fifo_addr & io_write_n & ~fdc_prev_wr_n;
    wire fdc_rd_pulse  = fdc_fifo_addr & io_read_n & ~fdc_prev_rd_n;

    // SENSE INTERRUPT's answer, honestly shaped.
    //
    // The bench read one result byte and stopped, and the model sat on the
    // second one for ever. That is the BIOS behaving correctly: this returned
    // ST0 = 80, and 80 is IC = "invalid command / no interrupt pending", the
    // one case where a uPD765 hands back ONE byte instead of two. The BIOS
    // took its byte and left; the model still wanted to give another.
    //
    // So say what actually happened. A RECALIBRATE or SEEK here finds no
    // drive, which is a real, describable outcome: IC = abnormal termination,
    // SE (seek end) and EC (equipment check) both set, unit in the low two
    // bits -- 70 | unit -- followed by PCN 0. That is two bytes, and the BIOS
    // reads two. With no interrupt pending it is 80 and one byte, as before.
    logic [1:0] fdc_unit;
    logic [3:0] fdc_seek_pend;

    // A seek-end per unit, not one flag for all of them.
    //
    // The BIOS recalibrates units 0, 1, 2 and 3 back to back and then waits
    // for all four bits of its drive map at 055E. Each RECALIBRATE ends with
    // its own interrupt, and the handler drains them: SENSE INTERRUPT until
    // the chip answers 80. The bench showed four commands producing exactly
    // two senses -- one unit, then "nothing pending" -- because this kept a
    // single pending flag and a single unit. Three of the four units were
    // never reported, three of the four bits never got set, and the wait ran
    // its full 65536 tries sixteen times over: eleven seconds for the 2HD
    // probe and eleven more for the 2DD one.
    //
    // So keep a bit per unit and hand them back lowest first. ST0 is 20 | unit
    // -- seek end, normal termination -- which is a drive that recalibrated to
    // track 0. Whether it has a DISK in it is a question for the read that
    // follows, not for the seek.
    wire       fdc_any_pend  = |fdc_seek_pend;
    wire [1:0] fdc_next_unit = fdc_seek_pend[0] ? 2'd0
                             : fdc_seek_pend[1] ? 2'd1
                             : fdc_seek_pend[2] ? 2'd2 : 2'd3;

    // Command shape: bytes still to write after the first, and results.
    //
    // Of the byte ARRIVING, not of fdc_cmd. fdc_cmd still holds the PREVIOUS
    // command at the moment the counts are loaded -- it is assigned in the
    // same non-blocking block -- so every command was set up with its
    // predecessor's byte count, and the model desynchronised on the second
    // command it ever saw.
    //
    // What that looks like from the BIOS: SENSE INTERRUPT (0x08, no parameter
    // bytes, two results) is followed by SPECIFY (0x03, two parameter bytes,
    // no results). SPECIFY loaded 0x08's shape -- zero writes, two results --
    // so the model declared itself finished on the command byte alone and
    // went into the result phase. MSR then reads C0 (RQM with DIO set: "read
    // me"), and the BIOS, waiting at FFA26 for MSR & C0 == 80 before it may
    // write a parameter, spins out its whole CX -- 65536 reads, most of a
    // second -- and gives up. Every FDC command after the first cost a full
    // timeout, which is the "IN from 0090 x65538, IN from 00c8 x45172" in the
    // bench trace and the frozen I/O write count on the hardware.
    function automatic logic [7:0] fdc_shape(input logic [7:0] c);
        case (c)
        8'h03: fdc_shape = {4'd2, 4'd0};
        8'h04: fdc_shape = {4'd1, 4'd1};
        8'h07: fdc_shape = {4'd1, 4'd0};
        8'h08: fdc_shape = {4'd0, 4'd2};
        8'h0F: fdc_shape = {4'd2, 4'd0};
        8'h0A, 8'h4A: fdc_shape = {4'd1, 4'd7};
        8'h05, 8'h06, 8'h45, 8'h46, 8'h65, 8'h66, 8'hE5, 8'hE6:
               fdc_shape = {4'd8, 4'd7};
        8'h4D, 8'hCD: fdc_shape = {4'd5, 4'd7};
        default: fdc_shape = {4'd0, 4'd2};
        endcase
    endfunction
    // Sliced off a wire, not off the call: indexing a function's
    // result directly is a syntax error to both Verilator and Quartus.
    wire [7:0] fdc_shape_now   = fdc_shape(fdc_wr_data);
    wire [3:0] fdc_new_writes  = fdc_shape_now[7:4];
    wire [3:0] fdc_new_results = fdc_shape_now[3:0];

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            fdc_cmd         <= 8'h00;
            fdc_writes_left <= 4'd0;
            fdc_results_left<= 4'd0;
            fdc_result_idx  <= 4'd0;
            fdc_result0     <= 8'h00;
            fdc_result1     <= 8'h00;
            fdc_in_result   <= 1'b0;
            fdc_cmd_done    <= 1'b0;
            irq_int        <= 1'b0;
            irq_2dd        <= 1'b0;
            seek_is_2dd    <= 1'b0;
            fdc_unit        <= 2'd0;
            fdc_seek_pend   <= 4'd0;
            seek_timer      <= 18'd0;
            fdc_want_unit   <= 1'b0;
            fdc_prev_wr_n   <= 1'b1;
            fdc_prev_rd_n   <= 1'b1;
            fdc_wr_data     <= 8'h00;
        end else begin
            fdc_prev_wr_n <= io_write_n;
            fdc_prev_rd_n <= io_read_n;
            // The byte, sampled while the cycle is live: at the trailing
            // edge the bus has already moved on.
            if (fifo_select & ~io_write_n) fdc_wr_data <= data_in;
            fdc_cmd_done <= 1'b0;
            if (fdc_wr_pulse) begin
                if (fdc_writes_left == 4'd0) begin
                    // First byte: it IS the command.
                    fdc_cmd        <= fdc_wr_data;
                    fdc_result_idx <= 4'd0;
                    case (fdc_wr_data)
                        8'h04: fdc_result0 <= 8'h00;
                        8'h08: begin
                            // Lowest unit still owed a report, then PCN.
                            fdc_result0 <= fdc_any_pend
                                         ? {2'b00, 1'b1, 3'b000, fdc_next_unit}
                                         : 8'h80;
                            fdc_result1 <= 8'h00;
                            if (fdc_any_pend) fdc_seek_pend[fdc_next_unit] <= 1'b0;
                        end
                        default: begin fdc_result0 <= 8'h80; fdc_result1 <= 8'h00; end
                    endcase
                    fdc_want_unit    <= (fdc_new_writes != 4'd0);
                    fdc_writes_left  <= fdc_new_writes;
                    fdc_results_left <= (fdc_wr_data == 8'h08)
                                      ? (fdc_any_pend ? 4'd2 : 4'd1)
                                      : fdc_new_results;
                    if (fdc_new_writes == 4'd0)
                        fdc_cmd_done <= 1'b1;      // single-byte command
                end else begin
                    fdc_writes_left <= fdc_writes_left - 4'd1;
                // The unit is the first parameter of RECALIBRATE and
                // SEEK, and it is what ST0 has to name afterwards.
                if ((fdc_cmd == 8'h07 && fdc_writes_left == 4'd1)
                 || (fdc_cmd == 8'h0F && fdc_writes_left == 4'd2))
                    fdc_unit <= fdc_wr_data[1:0];
                    if (fdc_writes_left == 4'd1)
                        fdc_cmd_done <= 1'b1;      // that was the last byte
                end
            end else begin
                // Reading results hands them out one by one; the last one
                // returns the chip to idle.
                if (fdc_rd_pulse && fdc_in_result) begin
                    fdc_result_idx <= fdc_result_idx + 4'd1;
                    if (fdc_result_idx + 4'd1 >= fdc_results_left) begin
                        fdc_in_result    <= 1'b0;
                        fdc_results_left <= 4'd0;
                    end
                end
            end
            if (fdc_cmd_done) begin
                if (fdc_results_left != 4'd0)
                    fdc_in_result <= 1'b1;
                // An execution phase that found no disk: abnormal termination,
                // and ST1 says why -- no address mark, which is what an empty
                // drive gives. The unit comes from the parameter, so ST0 names
                // the drive the BIOS asked about.
                if (cmd_ends_with_int(fdc_cmd) && fdc_cmd != 8'h07
                                               && fdc_cmd != 8'h0F) begin
                    fdc_result0 <= {2'b01, 4'b0000, fdc_unit};
                    fdc_result1 <= 8'h01;
                end
                if (cmd_ends_with_int(fdc_cmd)) begin
                    seek_timer  <= SEEK_CLOCKS;
                    seek_is_2dd <= cmd_is_2dd;
                end
                if (fdc_cmd == 8'h07 || fdc_cmd == 8'h0F) begin
                    // Seek end is RECORDED here and SIGNALLED later.
                    //
                    // The BIOS issues RECALIBRATE for all four units, then
                    // CLEARS its drive map at 055E, and only then waits for the
                    // interrupts to fill it back in -- FF57A, FF57D, FF587, in
                    // that order. That is only safe because a real head takes
                    // milliseconds to step to track 0. Raising the interrupt one
                    // clock after the command -- 23 ns -- ran the handler BEFORE
                    // the clear, so all four bits were set and then wiped, and
                    // the wait that followed had nothing left to wait for:
                    // sixteen retries of a zeroed CX, eleven seconds, once for
                    // the 2HD probe at port 90 and once for the 2DD one at C8.
                    fdc_seek_pend[fdc_unit] <= 1'b1;
                end
            end
            // The seek's interrupt, once the head would have got there.
            if (seek_timer != 18'd0) begin
                seek_timer <= seek_timer - 18'd1;
                if (seek_timer == 18'd1) begin
                    if (seek_is_2dd) irq_2dd <= 1'b1;
                    else             irq_int <= 1'b1;
                end
            end
            if (irq_int) irq_int <= 1'b0;
            if (irq_2dd) irq_2dd <= 1'b0;
        end
    end
    // MSR, with the busy bit the BIOS actually tests.
    //
    // FFC16 is the BIOS's result-phase wait:
    //
    //     in al,dx / and al,D0 / cmp al,D0 / loopne FFC16
    //
    // RQM and DIO are not enough -- it wants bit 4, CB, the chip's "a command
    // is in progress" flag, which on a uPD765 is set from the first command
    // byte until the last result byte has been read. This model answered C0 in
    // the result phase, CB clear, so the BIOS could never take the two bytes
    // that SENSE INTERRUPT (08) had waiting, the model stayed in the result
    // phase, and the next command's wait at FFA26 -- MSR & C0 == 80 -- spun
    // out its whole CX. That is the FA26-FA2D the hardware readout named.
    //
    // The other two waits agree with modelling CB properly: FFC00 wants
    // D0 == 80, CB CLEAR, before the first command byte, and FFA26 masks CB
    // off entirely for the parameter bytes that follow.
    wire fdc_busy = fdc_in_result | (fdc_writes_left != 4'd0);
    assign msr = fdc_in_result ? 8'hD0     // RQM + DIO + CB: read me
                       : fdc_busy      ? 8'h90     // RQM + CB: next parameter
                       :                 8'h80;    // RQM: idle, send a command
    assign fifo = (fdc_result_idx == 4'd0) ? fdc_result0
                : (fdc_result_idx == 4'd1) ? fdc_result1
                :                            8'h00;


endmodule
