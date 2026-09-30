// SPDX-License-Identifier: GPL-3.0-or-later
//
// fdd_sound -- a floppy drive's mechanism noise, played back from recorded
// samples of a real 5.25" PC-98 drive (this core's reference unit).
//
// Synthesis never matched the mechanism -- the seek's stepped-motor whine,
// the rattle's micro-bounce texture, the clunk's metallic ring all resist
// oscillator+noise approximations. So instead the "FDD sound" data slot
// (fddsnd.bin, scripts/fddsnd_pack.py) streams straight into this module's
// sample store via the data_loader write path, and the voices below play
// those cuts back: one-shots fire per event, loops ride gain envelopes.
//
//   STEP TICK -- step_pulse, one clk pulse per head step (floppy.v's seek
//   terms). Two tick voices ping-pong so a burst's overlapping decays are
//   not retriggered mid-ring.
//
//   HEAD-LOAD CLUNK -- rising edge of head_load.
//
//   SEEK WHINE -- the continuous loop while steps keep arriving (a ~50 ms
//   holdover re-arms on every step_pulse and releases ~50 ms after the
//   last). This is the "プープー"/ジーコジーコ band.
//
//   MEDIA HISS -- loop while xfer_active (sectors flowing under the head).
//
//   MOTOR WHIR -- loop while motor_on; quiet background.
//
// Blob layout (16-bit little-endian words in the store):
//   word 0    u16 magic low 'FD' = 0x4446 (word 1 = 'S1' = 0x3153)
//   word 2    u16 version, word 3 u16 segment count
//   words 4.. per segment: u16 word_offset, u16 word_length (bytes/2)
//   payload   s8 PCM at 24 kHz, two samples per word, low byte first
//
// Segments (index): 0 tick, 1 clunk, 2 seek, 3 read, 4 motor.
// No blob -> magic mismatch -> loaded=0 -> silence.
//
// Timing: ~48 kHz sample tick divided out of clk; voice positions advance
// every other tick (24 kHz playback, zero-order hold). Six voices fetch
// one word each across the six clks after every tick -- the store's single
// read port is ample at ~890 clk/tick. Store writes (the dataslot stream)
// share clk (data_loader's clk_memory = clk_chipset).
//
// SPDX-FileType: SOURCE
//
`default_nettype none

module fdd_sound #(
    parameter int CLK_HZ = 42_954_545,  // clk frequency (clk_chipset)
    parameter int SMP_HZ = 48_000       // sample tick rate
) (
    input  logic               clk,
    input  logic               reset,
    input  logic [1:0]         mode,      // 0=off, 1=5.25", 2=3.5"
    input  logic               step_pulse,
    input  logic               head_load,
    input  logic               xfer_active,
    input  logic               motor_on,
    // sample store write port: data_loader (dl_*) tap
    input  logic               snd_we,
    input  logic [13:0]        snd_waddr,
    input  logic [15:0]        snd_wdata,
    output logic signed [15:0] audio
);

    // ----------------------------------------------------------- the store
    localparam int WORDS = 16384;
    (* ramstyle = "M10K" *) logic [15:0] sram [0:WORDS-1];

    logic [13:0] rd_addr;
    logic [15:0] rd_data;
    always_ff @(posedge clk) begin
        if (snd_we) sram[snd_waddr] <= snd_wdata;
        rd_data <= sram[rd_addr];
    end

    // -------------------------------------------------------- header walk
    //
    // After reset, stream words {0,4..13} through the read port into the
    // segment table. rd_addr is registered, so word f(k) lands in rd_data
    // while hdr_cnt==k+2 -- the case below captures f(hdr_cnt-2).
    logic        hdr_done = 1'b0;
    logic        loaded   = 1'b0;
    logic [3:0]  hdr_cnt  = 4'd0;
    logic [13:0] seg_off [0:4];
    logic [13:0] seg_len [0:4];
    wire  [13:0] hdr_addr = (hdr_cnt == 4'd0) ? 14'd0 : 14'(hdr_cnt + 4'd3);
    always_ff @(posedge clk) begin
        if (reset) begin
            hdr_cnt  <= 4'd0;
            hdr_done <= 1'b0;
            loaded   <= 1'b0;
        end else if (!hdr_done) begin
            hdr_cnt <= hdr_cnt + 4'd1;
            if (hdr_cnt >= 4'd2)
                case (hdr_cnt)
                    4'd2:  loaded     <= (rd_data == 16'h4446);
                    4'd3:  seg_off[0] <= rd_data[13:0];
                    4'd4:  seg_len[0] <= rd_data[13:0];
                    4'd5:  seg_off[1] <= rd_data[13:0];
                    4'd6:  seg_len[1] <= rd_data[13:0];
                    4'd7:  seg_off[2] <= rd_data[13:0];
                    4'd8:  seg_len[2] <= rd_data[13:0];
                    4'd9:  seg_off[3] <= rd_data[13:0];
                    4'd10: seg_len[3] <= rd_data[13:0];
                    4'd11: seg_off[4] <= rd_data[13:0];
                    4'd12: seg_len[4] <= rd_data[13:0];
                    default: ;
                endcase
            if (hdr_cnt == 4'd12)
                hdr_done <= 1'b1;
        end
    end

    // ------------------------------------------------------------- timing
    localparam int SMP_DIV = CLK_HZ / SMP_HZ;
    logic [9:0] smp_div;
    wire        smp_ce = (smp_div == 10'(SMP_DIV - 1));
    always_ff @(posedge clk) begin
        if (reset)  smp_div <= 10'd0;
        else        smp_div <= smp_ce ? 10'd0 : smp_div + 10'd1;
    end

    wire drive_en = loaded && (mode != 2'd0);

    // ---------------------------------------------------------- voices
    //
    //   0,1 tick (one-shot, ping-pong)   2 clunk (one-shot)
    //   3 seek (loop)   4 read (loop)   5 motor (loop)
    function automatic logic [2:0] VSEG(input int v);
        case (v)
            0, 1:    return 3'd0;
            2:       return 3'd1;
            3:       return 3'd2;
            4:       return 3'd3;
            default: return 3'd4;
        endcase
    endfunction

    logic [14:0] vpos  [0:5];    // byte index within segment (len*2 can exceed 14 bits)
    logic        vact  [0:5];    // one-shots only
    logic [7:0]  vgain [0:5];    // loop voices only
    logic [15:0] vword [0:5];    // last fetched word
    logic        vlsb  [0:5];    // pos[0] latched at fetch time
    logic        ph;             // 24 kHz advance phase
    logic        tick_sel;
    logic        head_q;
    logic [12:0] step_hold;      // seek-loop holdover, ~50 ms at 48 kHz

    integer vi;
    always_ff @(posedge clk) begin
        if (reset) begin
            ph        <= 1'b0;
            tick_sel  <= 1'b0;
            head_q    <= 1'b0;
            step_hold <= 13'd0;
            for (vi = 0; vi < 6; vi = vi + 1) begin
                vact[vi]  <= 1'b0;
                vpos[vi]  <= 15'd0;
                vgain[vi] <= 8'd0;
            end
        end else begin
            head_q <= head_load;
            if (head_load && !head_q) begin
                vact[2] <= 1'b1;
                vpos[2] <= 15'd0;
            end
            if (step_pulse) begin
                step_hold      <= 13'd2400;
                vact[tick_sel] <= 1'b1;
                vpos[tick_sel] <= 15'd0;
                tick_sel       <= ~tick_sel;
            end else if (smp_ce) begin
                if (|step_hold) step_hold <= step_hold - 13'd1;
                ph <= ~ph;
                for (vi = 0; vi < 6; vi = vi + 1) begin
                    if (vi >= 3) begin
                        if (vtgt(vi) && vgain[vi] < 8'd252)
                            vgain[vi] <= vgain[vi] + 8'd3;
                        else if (!vtgt(vi) && |vgain[vi])
                            vgain[vi] <= vgain[vi] - 8'd3;
                    end
                    if (ph) begin
                        if (vi < 3) begin
                            if (vact[vi]) begin
                                if (vpos[vi] >= {1'b0, seg_len[VSEG(vi)], 1'b0} - 15'd1)
                                    vact[vi] <= 1'b0;
                                else
                                    vpos[vi] <= vpos[vi] + 15'd1;
                            end
                        end else if (vpos[vi] >= {1'b0, seg_len[VSEG(vi)], 1'b0} - 15'd1)
                            vpos[vi] <= 15'd0;
                        else
                            vpos[vi] <= vpos[vi] + 15'd1;
                    end
                end
            end
        end
    end

    function automatic logic vtgt(input int v);
        case (v)
            3:       return |step_hold;
            4:       return xfer_active;
            5:       return motor_on;
            default: return 1'b0;
        endcase
    endfunction

    // ------------------------------------------------------- sample fetch
    //
    // Right after each tick, six consecutive clks present each voice's word
    // address; the read data lands the next clk and is latched into vword.
    // vlsb keeps the byte-select bit from fetch time so it tracks the word.
    logic [2:0] fcnt = 3'd7;
    always_ff @(posedge clk) begin
        if (smp_ce)           fcnt <= 3'd0;
        else if (fcnt != 3'd7) fcnt <= fcnt + 3'd1;

        if (!hdr_done)
            rd_addr <= hdr_addr;
        else if (fcnt < 3'd6) begin
            rd_addr    <= seg_off[VSEG(fcnt)] + 14'(vpos[fcnt] >> 1);
            vlsb[fcnt] <= vpos[fcnt][0];
        end
        if (hdr_done && fcnt >= 3'd1 && fcnt <= 3'd6)
            vword[fcnt - 3'd1] <= rd_data;
    end

    function automatic logic signed [7:0] vsample(input int v);
        return vlsb[v] ? $signed(vword[v][15:8]) : $signed(vword[v][7:0]);
    endfunction

    // ------------------------------------------------------------- mixer
    // One-shots at s8<<6; loops at s8*gain/4 -- same full-scale weight.
    logic signed [18:0] mix;
    always_comb begin
        logic signed [18:0] acc;
        acc = 19'sd0;
        for (int v = 0; v < 3; v = v + 1)
            if (vact[v]) acc = acc + ($signed(vsample(v)) <<< 6);
        for (int v = 3; v < 6; v = v + 1)
            acc = acc + (($signed(vsample(v)) * $signed({1'b0, vgain[v]})) >>> 2);
        mix = acc;
    end

    // master gain ramps with the drive gate so it never pops
    logic [7:0] mgain;
    always_ff @(posedge clk) begin
        if (reset) mgain <= 8'd0;
        else if (smp_ce) begin
            if (drive_en && mgain < 8'd252) mgain <= mgain + 8'd4;
            else if (!drive_en && |mgain)   mgain <= mgain - 8'd4;
        end
    end

    wire signed [27:0] scaled = mix * $signed({1'b0, mgain});
    wire signed [19:0] mixg   = scaled[27:8];       // >>>8
    always_ff @(posedge clk) begin
        if (reset) audio <= 16'sd0;
        else if (smp_ce)
            audio <= (mixg > 20'sd32767)  ? 16'sd32767  :
                     (mixg < -20'sd32768) ? -16'sd32768 :
                      16'(mixg);
    end

endmodule

`default_nettype wire
