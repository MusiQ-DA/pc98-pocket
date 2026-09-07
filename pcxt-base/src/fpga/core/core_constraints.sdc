#
# user core constraints
#
# Asynchronous clock-domain groups. Clocks within a group are related and timed
# normally; paths between groups are cut (their crossings are handled in RTL).
#
#   pll (system):   [0] clk_chipset 42.95   [1] clk_core 85.9 (CPU)  [2] clk_sdram_ph 42.95@180
#                   [3] clk_28_636 (CGA)    [4] clk_pix_cga 14.318   [5] clk_pix_cga_90
#   mf_audio_pll:   [0] audio_mclk 12.288   [1] audio_sclk 3.072
#   APF / bridge:   clk_74a, clk_74b, bridge_spiclk
#
# One VCO feeds the CPU, chipset and CGA video, so they are mutually synchronous and
# timed as a single group. The muxed back-end clock (clk_pix) is derived from a PLL
# output in that group, so it is intra-group too. The cut boundaries are the inherent
# Pocket bridge clocks, the audio PLL, and the gated softcore clock (clk_pico).
#
# PicoRV32 softcore clock: clk_chipset (42.95 MHz) gated to one pulse in six (~7.16 MHz),
# from softcpu_subsystem.sv. A generated clock of clk_chipset, kept in its group so the
# clk_pico <-> clk_chipset crossings are timed rather than cut.
create_generated_clock -name clk_pico -divide_by 6 \
 -source [get_pins {ic|pll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] \
 [get_nets {core_top:ic|softcpu_subsystem:u_softcpu|clk_pico}]

set_clock_groups -asynchronous \
 -group { \
   ic|pll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
   ic|pll|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
   ic|pll|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk \
   ic|pll|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk \
   ic|pll|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk \
   ic|pll|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk \
   clk_pico } \
 -group { \
   ic|audio_mixer|audio_pll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
   ic|audio_mixer|audio_pll|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { bridge_spiclk }

# clk_pico holds each value six clk_chipset cycles, so the clk_pico -> clk_chipset crossing
# has a six-cycle window (the reverse captures on clk_pico, so one cycle already suffices).
set_multicycle_path -setup -end 6 \
 -from [get_clocks clk_pico] \
 -to   [get_clocks {ic|pll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set_multicycle_path -hold -end 5 \
 -from [get_clocks clk_pico] \
 -to   [get_clocks {ic|pll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]

# ---------------------------------------------------------------------------
# SDRAM I/O TIMING  (added 2026-09-07, testB7)
# ---------------------------------------------------------------------------
# WHY THIS EXISTS. Until this block, EVERY dram_* pin was unconstrained. Proof,
# from build/artifact_54/ap_core.sta.rpt (the testB6 build):
#
#   Unconstrained Input Ports:   dram_dq[*]  "No input delay ... found"
#   Unconstrained Output Ports:  dram_a[*] dram_ba[*] dram_dqm[*] dram_clk
#                                dram_ras_n dram_cas_n dram_we_n dram_dq[*]
#
# So the SDRAM interface had ZERO analysed timing paths. Three consequences,
# and they are exactly the bug we spent three hardware builds chasing:
#
#   * the Fitter had no timing goal for these pins and placed the registers
#     that drive them wherever it liked;
#   * STA's "worst-case slack" was SILENT about the SDRAM, not clean -- every
#     "all green" report in this bisection said nothing at all about it;
#   * placement therefore changed with every recompile, so the interface was
#     marginal in a way that varied BUILD TO BUILD and that no simulation can
#     reproduce. That is the "all sims pass, hardware is black" signature.
#
# The fit-lottery shows up in the reports as well. Ranking the six bisection
# builds by the CGA-domain (general[3]) total negative slack -- a proxy for how
# hard the Fitter was struggling -- separates them perfectly by hardware result:
#
#   #49 testB3 pure KF     BOOTS   -1.30      #46 testB2 mp   black  -5.26
#   #51 testB4 KF far end  BOOTS   -1.07      #53 testB5 mp   black  -3.89
#                                             #54 testB6 mp   black  -6.35
#
# and it is not a size effect: testB4, the best-scoring build, is also the
# LARGEST (12,233 ALMs vs 12,170 for testB6).
#
# The numbers below are board+chip properties (SDRAM tAC/tOH/tSU/tHD plus trace
# flight), taken from the sibling Pocket core that runs this same part on this
# same board (../MacLC_MiSTer-derived src/fpga/core/core_constraints.sdc).
# They are not frequency dependent, so they carry over to 42.95 MHz unchanged.
#
# NOT ported: that core's `set_multicycle_path -from <chip clk> -setup -end 2`.
# It is correct for ITS controller and WRONG for ours. dram_clk here is
# clk_chipset inverted, so the part launches read data on our falling edge and
# sdram_mp/KFSDRAM both capture it on the very NEXT rising edge -- a genuine
# single-cycle transfer with a half-period (11.64 ns) window. Crediting two
# periods would hide a real violation, which is the trap this file exists to
# avoid. If these paths fail, fix the pipelining, do not relax the check.
#
# general[0] = clk_chipset 42.95      -- the controller clock
# general[2] = clk_sdram_ph 42.95@180 -- drives the dram_clk pin
#
# Both are already in the same clock group above, which is what makes the
# launch->chip relationship exist at all. Listing them as asynchronous would
# cut every path here and silently turn this whole block into a no-op.
#
# VERIFY AFTER ANY CHANGE HERE with scripts/check_sdram_paths.tcl (wired into
# CI). A healthy slack number with no paths behind it means nothing.

set dram_cont_clk "ic|pll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk"
set dram_chip_clk "ic|pll|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk"

# Read path: data launched by the SDRAM, relative to the clock the SDRAM sees.
# -max = tAC + max trace flight; -min = tOH + min trace flight.
# -add_delay on the SECOND of each min/max pair is required: without it Quartus
# REPLACES the previous delay on the port instead of adding to it.
set_input_delay -clock $dram_chip_clk -reference_pin [get_ports {dram_clk}] \
    -max 5.9 [get_ports {dram_dq[*]}]
set_input_delay -clock $dram_chip_clk -reference_pin [get_ports {dram_clk}] \
    -min 0.9 -add_delay [get_ports {dram_dq[*]}]

# Write/command path: -max = chip tSU + max flight, -min = -(chip tHD + min
# flight). dram_dq* and dram_dqm* are included because this core does SDRAM
# writes; leaving them out would repeat the same mistake on the write side.
set_output_delay -clock $dram_chip_clk -reference_pin [get_ports {dram_clk}] \
    -max 2.0 [get_ports {dram_cke dram_a[*] dram_ba[*] dram_dqm[*] dram_dq[*] \
                         dram_ras_n dram_cas_n dram_we_n}]
set_output_delay -clock $dram_chip_clk -reference_pin [get_ports {dram_clk}] \
    -min -1.0 -add_delay [get_ports {dram_cke dram_a[*] dram_ba[*] dram_dqm[*] dram_dq[*] \
                                     dram_ras_n dram_cas_n dram_we_n}]
