# check_sdram_paths.tcl -- prove the SDRAM interface is actually being ANALYSED.
#
# Run under quartus_sta on a fitted project:
#     quartus_sta -t ../../../scripts/check_sdram_paths.tcl ap_core
#
# WHY. Until 2026-09-07 every dram_* pin in this core was unconstrained, so STA
# reported a healthy worst-case slack while analysing ZERO SDRAM paths. The
# Fitter had no goal for those pins, placement changed every build, and the
# interface was marginal in a build-dependent way that simulation cannot see --
# the "all sims pass, hardware is black" bug in docs/HANDOVER.md.
#
# A good slack number with no paths behind it means nothing. This script fails
# the build if the path count is zero, so that particular silence cannot return.
#
# SPDX-License-Identifier: GPL-3.0-or-later

project_open [lindex $quartus(args) 0]
create_timing_netlist -post_fit
read_sdc
update_timing_netlist

set fail 0

proc count_paths {label args} {
    set n [llength [eval get_timing_paths $args -npaths 1000 -detail summary]]
    puts [format "  %-28s %5d paths" $label $n]
    return $n
}

puts "== SDRAM interface path census =="
set n_wr [count_paths "write/command -> dram_*" -to   [get_ports {dram_a* dram_ba* dram_dqm* dram_dq* dram_cke dram_ras_n dram_cas_n dram_we_n}]]
set n_rd [count_paths "read: dram_dq[*] -> core" -from [get_ports {dram_dq[*]}]]

if {$n_wr == 0} { puts "FAIL: no analysed paths TO the SDRAM pins";   set fail 1 }
if {$n_rd == 0} { puts "FAIL: no analysed paths FROM dram_dq";        set fail 1 }

# Report the real margin on those paths, per corner, for the record.
foreach op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    set wr [get_timing_paths -to   [get_ports {dram_a* dram_ba* dram_dqm* dram_dq* dram_cke dram_ras_n dram_cas_n dram_we_n}] -npaths 1 -setup]
    set rd [get_timing_paths -from [get_ports {dram_dq[*]}] -npaths 1 -setup]
    set wrs [expr {[llength $wr] ? [get_path_info [lindex $wr 0] -slack] : "n/a"}]
    set rds [expr {[llength $rd] ? [get_path_info [lindex $rd 0] -slack] : "n/a"}]
    puts [format "  %-40s setup: write %8s  read %8s" $op $wrs $rds]
}

delete_timing_netlist
project_close

if {$fail} {
    puts "check_sdram_paths: FAIL"
    exit 1
}
puts "check_sdram_paths: PASS"
exit 0
