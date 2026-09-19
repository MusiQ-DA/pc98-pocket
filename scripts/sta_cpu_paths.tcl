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
  -file sta_cpu_intra.txt -detail full

# Crossings each way with the softcore (clk_pico is a /6 of the same VCO, so
# these are timed transfers, not false paths).
report_timing -nworst 20 -setup -from_clock $cpuclk -to_clock {clk_pico} \
  -file sta_cpu_to_pico.txt -detail full
report_timing -nworst 20 -setup -from_clock {clk_pico} -to_clock $cpuclk \
  -file sta_pico_to_cpu.txt -detail full

# The softcore's own-domain failures.
report_timing -nworst 20 -setup -from_clock {clk_pico} -to_clock {clk_pico} \
  -file sta_pico_intra.txt -detail full

# And the antiphase sibling (the SDRAM's 180-degree clock).
report_timing -nworst 20 -setup -from_clock $cpuclk \
  -to_clock {ic|pll|altera_pll_i|general\[2\].gpll~PLL_OUTPUT_COUNTER|divclk} \
  -file sta_cpu_to_sdram.txt -detail full
report_timing -nworst 20 -setup \
  -from_clock {ic|pll|altera_pll_i|general\[2\].gpll~PLL_OUTPUT_COUNTER|divclk} \
  -to_clock $cpuclk \
  -file sta_sdram_to_cpu.txt -detail full

puts "STA_CPU_PATHS_DONE"
