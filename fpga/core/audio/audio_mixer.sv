//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
// SPDX-FileType: SOURCE
// SPDX-FileCopyrightText: (c) 2023, OpenGateware authors and contributors
//------------------------------------------------------------------------------
//
// Analogue Pocket Audio Mixer
//
// Copyright (c) 2023, Marcus Andrade <marcus@opengateware.org>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//------------------------------------------------------------------------------

`default_nettype none

module audio_mixer #(
    parameter DW     = 16,  //! Audio Data Width
    // parameter MUTE_PAUSE = 1,   //! Mute on Pause
    parameter STEREO = 1    //! Stereo Audio
) (
    // Clocks and Reset
    input  logic          clk_74b,     //! Clock 74.25Mhz
    input  logic          clk_audio,
    input  logic          reset,       //! Reset
    // Controls
    // input  logic [   3:0] afilter_sw,  //! Predefined Audio Filter Switch
    input  logic [   3:0] vol_att,     //! Volume ([0] Max | [7] Min)
    input  logic [   1:0] mix,         //! [0] No Mix | [1] 25% | [2] 50% | [3] 100% (mono)
    // input  logic          pause_core,  //! Mute Audio
    // Audio From Core
    input  logic          is_signed,   //! Signed Audio
    input  logic [DW-1:0] core_l,      //! Left  Channel Audio from Core
    input  logic [DW-1:0] core_r,      //! Right Channel Audio from Core
    // Pocket I2S
    output logic          audio_mclk,  //! Serial Master Clock
    output logic          audio_lrck,  //! Left/Right clock
    output logic          audio_dac    //! Serialized data
);

  //! ------------------------------------------------------------------------
  //! Audio Clocks
  //! MCLK: 12.288MHz (256*Fs, where Fs = 48000)
  //! SCLK:  3.072mhz (MCLK/4)
  //! ------------------------------------------------------------------------
  wire audio_sclk;

  audio_pll audio_pll (
      .refclk  (clk_74b),
      .rst     (0),
      .outclk_0(audio_mclk),
      .outclk_1(audio_sclk)
  );

  //! ------------------------------------------------------------------------
  //! Pad core_l/core_r with zeros to maintain a consistent size of 16 bits,
  //! then feed the output path. The drive-noise tap that used to sum in
  //! here is gone: mechanism samples now play on the OPNA's own ADPCM-A
  //! voices, so they arrive inside core_l/core_r already mixed.
  //! ------------------------------------------------------------------------
  logic [15:0] core_al, core_ar;

  always_comb begin
    core_al = DW == 16 ? core_l : {core_l, {16 - DW{1'b0}}};
    core_ar = STEREO ? DW == 16 ? core_r : {core_r, {16 - DW{1'b0}}} : core_al;
  end

  //! ------------------------------------------------------------------------
  //! Low Pass Filter
  //! ------------------------------------------------------------------------
  // The MiSTer 3-tap IIR + DC blocker chain (audio_filters) was the largest
  // single block in the audio path -- ~500-700 ALMs of 40-bit datapath --
  // while this core's OPNA/SSG/beep mix barely exercises what it buys. It
  // was removed for fit headroom (jt12 OPNA), keeping only the lightweight
  // audio_mix crossfeed+attenuation stage below.

  //! ------------------------------------------------------------------------
  //! Synchronization
  //! ------------------------------------------------------------------------

  logic [15:0] core_al_s, core_ar_s;

  sync_fifo #(
      .WIDTH(32)
  ) sync_fifo (
      .clk_write(clk_audio),
      .clk_read (audio_mclk),

      .write_en(write_en),
      .data({core_al, core_ar}),
      .data_s({core_al_s, core_ar_s})
  );

  reg write_en = 0;
  reg [15:0] prev_left;
  reg [15:0] prev_right;

  // Mark write when necessary
  always @(posedge clk_audio) begin
    prev_left  <= core_al;
    prev_right <= core_ar;

    write_en   <= 0;

    if (core_al != prev_left || core_ar != prev_right) begin
      write_en <= 1;
    end
  end

  //! ------------------------------------------------------------------------
  //! Crossfeed + attenuation (was the tail of audio_filters)
  //! ------------------------------------------------------------------------
  logic [15:0] audio_l, audio_r;

  wire [15:0] din_l = {~is_signed ^ core_al_s[15], core_al_s[14:0]};
  wire [15:0] din_r = {~is_signed ^ core_ar_s[15], core_ar_s[14:0]};

  wire [15:0] audio_l_pre;
  audio_mix audmix_l
            (
                .clk         ( audio_mclk  ),
                .ce          ( 1'b1        ),
                .att         ( {1'b0, vol_att} ),
                .mix         ( mix         ),

                .core_audio  ( din_l       ),
                .pre_in      ( audio_r_pre ),

                .pre_out     ( audio_l_pre ),
                .out         ( audio_l     )
            );

  wire [15:0] audio_r_pre;
  audio_mix audmix_r
            (
                .clk         ( audio_mclk  ),
                .ce          ( 1'b1        ),
                .att         ( {1'b0, vol_att} ),
                .mix         ( mix         ),

                .core_audio  ( din_r       ),
                .pre_in      ( audio_l_pre ),

                .pre_out     ( audio_r_pre ),
                .out         ( audio_r     )
            );

  //! ------------------------------------------------------------------------
  //! Pocket I2S Output
  //! ------------------------------------------------------------------------

  sound_i2s sound_i2s (
      .audio_sclk(audio_sclk),

      .audio_l(audio_l),
      .audio_r(audio_r),

      .audio_lrck(audio_lrck),
      .audio_dac (audio_dac)
  );

endmodule
