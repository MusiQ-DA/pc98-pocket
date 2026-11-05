# Detailed STA of the failing CPU/bus domain. The summary panel showed the
# chipset clock (ic|pll general[0], 42.97 MHz) at -27.9 ns slack with a TNS
# of -29,331. Two cuts:
#
#   1. RAW: the forty worst intra-domain paths as the tool sees them.
#   2. HONEST: the same report on the current core -- z86 runs full-rate
#      on the gated clock, so no multicycle is owed; whatever is red
#      outside the core has names worth knowing.
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

# --- 2. HONEST: the core runs full-rate (z86 on the gated zet_clk), and
# core_constraints.sdc applies NO intra-core multicycle any more -- the
# old half-rate zet needed 2/1 here, zet->z86 removed it. So this report
# is the same cut as RAW, just deeper (200 paths) to look past the
# pacing artifacts the summary panel shows.
set zcore [get_keepers core_top:ic|z86:u_cpu*]
if {[llength $zcore] == 0} {
    puts "warning: no keepers matched the z86 core pattern"
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

# Hold inside the CPU domain at the fast corner -- where the summary's
# worst hold slack is. The z86 sits on the gated zet_clk, so a hold red
# here is a clk -> zet_clk skew path; print its endpoints into the log.
delete_timing_netlist
if {[catch {create_timing_netlist -model fast -temperature 0 -voltage 1100} err]} {
    puts "note: fast corner rejected ($err)"
    create_timing_netlist -model fast
}
read_sdc apf/apf_constraints.sdc
update_timing_netlist
report_timing -nworst 20 -hold -to_clock $cpuclk \
  -detail full_path -file sta_cpu_hold_fast.txt
if {[file exists sta_cpu_hold_fast.txt]} {
    set fh [open sta_cpu_hold_fast.txt]; set n 0
    while {[gets $fh line] >= 0 && $n < 120} {
        if {[regexp {^; (Slack|From Node|To Node|Launch Clock|Latch Clock|Clock Skew|Data Arrival Time) } $line]} { puts "cpu_hold: $line"; incr n }
    }
    close $fh
}

puts "STA_CPU_PATHS_DONE"
