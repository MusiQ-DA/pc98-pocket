# Detailed STA of the clk_74a (APF bridge) domain. The STA summary shows
# clk_74a setup slack around -2.2 ns (Fmax ~64 MHz vs the 74.25 MHz
# requirement) with several hundred failing endpoints. The bridge logic is
# meant to be light -- debounce, dataslot latches, RTC tick -- so a
# 15+ ns intra-domain path is either an accidental deep cone or the Fitter
# spending its effort elsewhere.
set project ap_core
project_open [lindex $quartus(args) 0]
if {[catch {create_timing_netlist -model slow -speed 8 \
                                  -temperature 85 -voltage 1100} err]} {
    puts "note: explicit corner rejected ($err); retrying with defaults"
    create_timing_netlist
}
read_sdc ap_core.sdc

# --- RAW: the hundred worst clk_74a -> clk_74a setup paths, full detail ---
report_timing -nworst 100 -setup \
  -from_clock {clk_74a} -to_clock {clk_74a} \
  -file sta_74a_intra.txt

puts "STA_74A_PATHS_DONE"
