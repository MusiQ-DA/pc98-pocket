# Detailed STA of the failing CPU/bus domain: the summary panel showed the
# chipset clock (ic|pll general[0], 42.97 MHz) at -27.9 ns slack with a TNS
# of -29,331 -- thousands of paths the metal cannot close, and the metal is
# the only place the boot derails. These reports name them.
project_open [lindex $quartus(args) 0]
if {[catch {create_timing_netlist -model slow -speed 8 \
                                  -temperature 85 -voltage 1100} err]} {
    puts "note: explicit corner rejected ($err); retrying with defaults"
    create_timing_netlist
}
read_sdc ap_core.sdc

set cpuclk {ic|pll|altera_pll_i|general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk}

# Intra-CPU-domain: the true on-clock violations.
report_timing -nworst 40 -setup \
  -from_clock $cpuclk -to_clock $cpuclk \
  -file sta_cpu_intra.txt

# Crossings each way with the softcore (clk_pico is a /6 of the same VCO, so
# these are timed transfers, not false paths).
report_timing -nworst 20 -setup -from_clock $cpuclk -to_clock {clk_pico} \
  -file sta_cpu_to_pico.txt
report_timing -nworst 20 -setup -from_clock {clk_pico} -to_clock $cpuclk \
  -file sta_pico_to_cpu.txt

# The softcore's own-domain failures.
report_timing -nworst 20 -setup -from_clock {clk_pico} -to_clock {clk_pico} \
  -file sta_pico_intra.txt

# And the antiphase sibling (the SDRAM's 180-degree clock).
report_timing -nworst 20 -setup -from_clock $cpuclk \
  -to_clock {ic|pll|altera_pll_i|general\[2\].gpll~PLL_OUTPUT_COUNTER|divclk} \
  -file sta_cpu_to_sdram.txt
report_timing -nworst 20 -setup \
  -from_clock {ic|pll|altera_pll_i|general\[2\].gpll~PLL_OUTPUT_COUNTER|divclk} \
  -to_clock $cpuclk \
  -file sta_sdram_to_cpu.txt

# The sharpest cut: single-cycle paths in the CPU domain that are NOT inside
# the V30 core. The core's registers are CE-gated (the "5 MHz" front-panel
# setting paces them at ~4.4 chipset clocks), so its intra-core reds are
# multicycle artifacts until constrained -- but everything AROUND the core
# (bridge, FDC glue, floppy.v, PICs) clocks every chipset edge for real.
report_timing -nworst 40 -setup   -from_clock $cpuclk -to_clock $cpuclk   -from [get_keepers *] -to [get_keepers *]   -xpaths [get_keepers core_top:ic|v30_core:u_cpu*]   -file sta_cpu_excluding_core.txt

# And the core's intra paths with the CE multicycle applied, to see what is
# left when the pacing is honest. 5 edges covers the worst accumulator gap
# at the default 46/201 rate.
set_multicycle_path -setup 5 -end \
  -from [get_keepers core_top:ic|v30_core:u_cpu*] \
  -to   [get_keepers core_top:ic|v30_core:u_cpu*]
set_multicycle_path -hold 4 -end \
  -from [get_keepers core_top:ic|v30_core:u_cpu*] \
  -to   [get_keepers core_top:ic|v30_core:u_cpu*]
report_timing -nworst 40 -setup   -from_clock $cpuclk -to_clock $cpuclk \
  -from [get_keepers core_top:ic|v30_core:u_cpu*] \
  -to   [get_keepers core_top:ic|v30_core:u_cpu*] \
  -file sta_core_multicycle.txt

puts "STA_CPU_PATHS_DONE"
