# Detailed STA of the failing CPU/bus domain. The summary panel showed the
# chipset clock (ic|pll general[0], 42.97 MHz) at -27.9 ns slack with a TNS
# of -29,331. Two cuts:
#
#   1. RAW: the forty worst intra-domain paths as the tool sees them.
#   2. HONEST: the same report AFTER multicycling the CE-gated V30 core.
#      The core's registers advance on a clock-enable paced at the "5 MHz"
#      front-panel setting (46/201 of the chipset clock, worst gap 5 edges),
#      so its intra-core single-cycle reds are pacing artifacts. Whatever is
#      STILL red in the second report -- outside the core, or genuinely
#      longer than the pacing -- has names worth knowing.
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

# --- 2. HONEST: multicycle the CE-gated core, cut the phantom ROM write
# enables (a $readmemh ROM never writes; its WE registers are constants whose
# fan-out STA still traces), then report deep enough to see past them.
set core [get_keepers core_top:ic|v30_core:u_cpu*]
if {[llength $core] > 0} {
    set_multicycle_path -setup 5 -end -from $core -to $core
    set_multicycle_path -hold 4 -end -from $core -to $core
} else {
    puts "warning: no keepers matched the core pattern"
}
set we [get_keepers *u_ucrom*PORT_A_WRITE_ENABLE_REG]
if {[llength $we] > 0} {
    set_false_path -from $we
    puts "false-pathed [llength $we] ucrom WE keepers"
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
