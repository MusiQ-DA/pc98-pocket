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
# The project's constraints: apf_constraints.sdc derives the PLL clocks and
# pulls in core/core_constraints.sdc (clk_pico, the multicycles). Reading a
# nonexistent ap_core.sdc left every report below unconstrained and made the
# clk_pico reports fail outright.
read_sdc apf/apf_constraints.sdc
update_timing_netlist

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

# Hold on the softcore crossings: every recent build carries clk_pico hold
# violations, and the softcore serves the SCSI disk the guest reads from.
report_timing -nworst 30 -hold -to_clock {clk_pico} \
  -detail full_path -file sta_pico_hold_in.txt
report_timing -nworst 30 -hold -from_clock {clk_pico} \
  -detail full_path -file sta_pico_hold_out.txt
foreach f {sta_pico_hold_in.txt sta_pico_hold_out.txt} {
    if {[file exists $f]} {
        set fh [open $f]; set n 0
        while {[gets $fh line] >= 0 && $n < 200} {
            if {[regexp {^; (Slack|From Node|To Node|Launch Clock|Latch Clock) } $line]} { puts "$f: $line"; incr n }
        }
        close $fh
    }
}

puts "STA_CPU_PATHS_DONE"
