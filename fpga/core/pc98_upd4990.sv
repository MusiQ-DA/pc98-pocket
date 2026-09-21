// The uPD4990 calendar, ported line-for-line from np2kai io/upd4990.c.
//
// A PC-98 reads the date through THIS chip's one-bit serial line: commands
// go to port 0x20 (STB/CLK/DATA phases packed into one byte), the data comes
// back as bit 0 of port 0x33. FD80's own reader -- the loop at file 0x15D3C
// that stalled the whole boot when the port answered open-bus FF -- issues
// the read command and clocks 48 bits out, six bytes, LSB first, seconds
// first. Until this module the port was a constant 0x08 (clock line
// resting): the boot passed with a zero date. Now the Pocket's bridge RTC
// feeds the real thing.
//
// The state machine follows np2 exactly, including its quirks:
//   - the serial command shifts in through bit 5 of DATA writes when the
//     parallel command is 7, one CLK at a time;
//   - both the READ and WRITE paths address cell (~pos)&7 of the byte
//     (np2 spells the read side ">> ((~pos)&7)" and the write side
//     "0x80 >> (pos&7)" -- the same bit, written twice);
//   - "time read" also plants 0x01 in reg[1], np2's "uPD4990 Happy" marker
//     that the BIOS accepts as the day-of-week register.
//
// REGLEN is 8 (io/upd4990.h): time lands in reg[7:2], the happy marker in
// reg[1], reg[0] stays zero.
module pc98_upd4990
#(
    parameter int REGLEN = 8
)(
    input  wire        clk,
    input  wire        rst,

    // A write to port 0x20, strobed once at the end of the bus cycle with
    // the byte the guest put on it.
    input  wire        wr_stb,
    input  wire [7:0]  wr_data,

    // The time, laid out the way np2's date2bcd fills reg[REGLEN-6..]:
    //   [7:0]   year, BCD (00-99)
    //   [15:8]  (month << 4) | weekday, binary nibbles (np2 packs it this way)
    //   [23:16] day, BCD
    //   [31:24] hour, BCD
    //   [39:32] minute, BCD
    //   [47:40] second, BCD
    input  wire [47:0] time_in,

    // Bit 0 of port 0x33 -- the calendar's serial output.
    output logic       cdat
);

    logic [7:0] last;
    logic [2:0] parallel;
    logic [4:0] serial;
    logic       regsft;
    logic [$clog2(REGLEN*8)-1:0] pos;
    logic [7:0] regs [REGLEN];

    logic [7:0] mod;
    assign mod = wr_data ^ last;

    logic [3:0] cmd;
    assign cmd = (parallel == 3'd7) ? serial[3:0] : {1'b0, parallel};

    // cdat's new value on a CLK edge, from the CURRENT pos before it moves.
    wire [$clog2(REGLEN)-1:0] pos_byte = pos[$clog2(REGLEN*8)-1:3];
    wire [2:0] pos_rd_bit = ~pos[2:0];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            last    <= 8'h00;
            parallel <= 3'd0;
            serial  <= 5'd0;
            regsft  <= 1'b0;
            pos     <= '0;
            cdat    <= 1'b0;
            for (int i = 0; i < REGLEN; i++) regs[i] <= 8'h00;
        end else if (wr_stb) begin
            last <= wr_data;
            if (wr_data[3]) begin                              // STB
                if (mod[3]) begin
                    case (cmd)
                    4'd0: regsft <= 1'b0;                      // register hold
                    4'd1: begin                                // register shift
                        regsft <= 1'b1;
                        pos    <= REGLEN*8 - 1;
                        cdat   <= regs[REGLEN-1][0];
                    end
                    4'd2: regsft <= 1'b0;                      // time set hold
                    4'd3: begin                                // time read
                        regsft <= 1'b0;
                        for (int i = 0; i < REGLEN; i++) regs[i] <= 8'h00;
                        regs[REGLEN-6] <= time_in[7:0];
                        regs[REGLEN-5] <= time_in[15:8];
                        regs[REGLEN-4] <= time_in[23:16];
                        regs[REGLEN-3] <= time_in[31:24];
                        regs[REGLEN-2] <= time_in[39:32];
                        regs[REGLEN-1] <= time_in[47:40];
                        regs[REGLEN-7] <= 8'h01;               // "Happy"
                        cdat <= time_in[40];                   // seconds' bit 0
                    end
                    default: ;                                 // TP/int/test: unused
                    endcase
                end
            end else if (wr_data[4]) begin                     // CLK
                if (mod[4]) begin
                    if (parallel == 3'd7)
                        serial <= serial >> 1;
                    if (regsft && pos != '0)
                        pos <= pos - 1'b1;
                    cdat <= regs[pos_byte][pos_rd_bit];
                end
            end else begin                                     // DATA
                parallel <= wr_data[2:0];
                if (parallel == 3'd7)
                    serial <= {wr_data[5], serial[3:0]};
                if (wr_data[5])
                    regs[pos_byte][~pos[2:0]] <= 1'b1;         // 0x80 >> (pos&7)
                else
                    regs[pos_byte][~pos[2:0]] <= 1'b0;
            end
        end
    end

endmodule
