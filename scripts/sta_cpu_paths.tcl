# Detailed STA of the failing CPU/bus domain. The summary panel showed the
# chipset clock (ic|pll general[0], 42.97 MHz) at -27.9 ns slack with a TNS
# of -29,331. Two cuts:
#
#   1. RAW: the forty worst intra-domain paths as the tool sees them.
#   2. HONEST: the same report AFTER multicycling the paced cores.
#      The zet core delivers on every other clk edge, so its intra-core
#      single-cycle reds are pacing artifacts. Whatever is STILL red in the
#      second report -- outside the core, or genuinely longer than the
#      pacing -- has names worth knowing.
set project ap_core
project_open [lindex $quartus(args) 0]
if {[catch {create_timing_netlist -model slow -speed 8 \
                                  -temperature 85 -voltage 1100} err]} {
    puts "note: explicit corner rejected ($err); retrying with defaults"
    create_timing_netlist
}
read_sdc ap_core.sdc

set cpuclk {ic|pll|altera_pll_i|general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk}

# --- 1. RAW ---
report_timing -nworst 40 -setup \
  -from_clock $cpuclk -to_clock $cpuclk \
  -file sta_cpu_intra.txt

# --- 2. HONEST: multicycle the paced core, then report deep enough to see
# past the pacing artifacts.
# (read_sdc ap_core.sdc above 404s -- the file isn't generated -- so this
# report must reproduce the project constraints itself: zet at 2/1, matching
# core_constraints.sdc.)
set zcore [get_keepers core_top:ic|zet:u_cpu*]
if {[llength $zcore] > 0} {
    set_multicycle_path -setup 2 -end -from $zcore -to $zcore
    set_multicycle_path -hold 1 -end -from $zcore -to $zcore
} else {
    puts "warning: no keepers matched the zet core pattern"
}
report_timing -nworst 200 -setup \
  -from_clock $cpuclk -to_clock $cpuclk \
  -file sta_cpu_honest.txt

# The softcore crossings both ways (clk_pico is a /6 of the same VCO).
report_timing -nworst 20 -setup -from_clock $cpuclk -to_clock {clk_pico} \
  -file sta_cpu_to_pico.txt
report_timing -nworst 20 -setup -from_clock {clk_pico} -to_clock $cpuclk \
  -file sta_pico_to_cpu.txt

puts "STA_CPU_PATHS_DONE"
