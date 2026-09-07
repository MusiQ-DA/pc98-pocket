# check_sdram_paths.tcl -- prove the SDRAM interface is actually being ANALYSED,
# and report the real margin on it.
#
# Run under quartus_sta on a fitted project, from the project directory:
#     quartus_sta -t <this script> ap_core
#
# WHY. Until 2026-09-07 every dram_* pin in this core was unconstrained, so STA
# reported a healthy worst-case slack while analysing ZERO SDRAM paths. The
# Fitter had no goal for those pins, placement changed every build, and the
# interface was marginal in a build-dependent way that simulation cannot see --
# the "all sims pass, hardware is black" bug in docs/HANDOVER.md.
#
# A good slack number with no paths behind it means nothing. This script fails
# the build if the path count is zero, so that silence cannot come back.
#
# SPDX-License-Identifier: GPL-3.0-or-later

project_open [lindex $quartus(args) 0]

# Quartus wants an explicit corner here on some versions and derives an invalid
# one on others; fall back rather than failing the build on flag spelling.
if {[catch {create_timing_netlist -post_fit -model slow -speed 8 \
                                  -temperature 85 -voltage 1100} err]} {
    puts "note: explicit corner rejected ($err); retrying with defaults"
    create_timing_netlist -post_fit
}
read_sdc
update_timing_netlist

set out_ports {dram_a* dram_ba* dram_dqm* dram_dq* dram_cke dram_ras_n dram_cas_n dram_we_n}
set in_ports  {dram_dq[*]}

set n_wr [llength [get_timing_paths -to   [get_ports $out_ports] -npaths 2000 -setup]]
set n_rd [llength [get_timing_paths -from [get_ports $in_ports]  -npaths 2000 -setup]]

puts "== SDRAM interface path census =="
puts [format "  write/command -> dram_*   %5d paths" $n_wr]
puts [format "  read: dram_dq -> core     %5d paths" $n_rd]

set fail 0
if {$n_wr == 0} { puts "FAIL: no analysed paths TO the SDRAM pins"; set fail 1 }
if {$n_rd == 0} { puts "FAIL: no analysed paths FROM dram_dq";      set fail 1 }

proc worst {args} {
    set p [eval get_timing_paths $args -npaths 1 -setup]
    if {[llength $p] == 0} { return "n/a" }
    return [format "%7.3f" [get_path_info [lindex $p 0] -slack]]
}
puts "== worst setup slack on those paths =="
puts [format "  write/command %s   read %s" \
        [worst -to [get_ports $out_ports]] [worst -from [get_ports $in_ports]]]

delete_timing_netlist
project_close

if {$fail} {
    puts "check_sdram_paths: FAIL"
    exit 1
}
puts "check_sdram_paths: PASS"
exit 0
