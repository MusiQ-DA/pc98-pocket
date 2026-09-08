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

# NOTE: this Quartus (18.1.1 Lite) has NO -post_fit flag -- post-fit is the
# default, and the usage list offers only -post_map for the other direction.
# Passing -post_fit makes it the positional <operating_conditions> argument,
# which then collides with -voltage and fails with a misleading message.
# Corner named explicitly because the tool otherwise derives an invalid one:
#   available here = 8_slow_1100mv_85c, 8_slow_1100mv_0c, MIN_fast_1100mv_*
if {[catch {create_timing_netlist -model slow -speed 8 \
                                  -temperature 85 -voltage 1100} err]} {
    puts "note: explicit corner rejected ($err); retrying with defaults"
    create_timing_netlist
}
read_sdc
update_timing_netlist

set out_ports {dram_a* dram_ba* dram_dqm* dram_dq* dram_cke dram_ras_n dram_cas_n dram_we_n}
set in_ports  {dram_dq[*]}

# get_timing_paths returns a Quartus COLLECTION, not a Tcl list. llength on it
# gives the size of its internal representation (2), and lindex hands back a
# fragment that get_path_info rejects. Use the collection API.
set n_wr [get_collection_size [get_timing_paths -to   [get_ports $out_ports] -npaths 2000 -setup]]
set n_rd [get_collection_size [get_timing_paths -from [get_ports $in_ports]  -npaths 2000 -setup]]

puts "== SDRAM interface path census =="
puts [format "  write/command -> dram_*   %5d paths" $n_wr]
puts [format "  read: dram_dq -> core     %5d paths" $n_rd]

set fail 0
if {$n_wr == 0} { puts "FAIL: no analysed paths TO the SDRAM pins"; set fail 1 }
if {$n_rd == 0} { puts "FAIL: no analysed paths FROM dram_dq";      set fail 1 }

proc worst {mode args} {
    set col [eval get_timing_paths $args -npaths 1 -$mode]
    if {[get_collection_size $col] == 0} { return "    n/a" }
    foreach_in_collection path $col {
        return [format "%7.3f" [get_path_info $path -slack]]
    }
    return "    n/a"
}

# Both edges of both directions.
#
# Setup alone is half the picture, and the two directions are COUPLED: they are
# measured against dram_clk, which is pll.v's phase_shift2 (11640 ps = 180 deg).
# Moving that phase trades margin between them 1:1 -- earlier helps the read and
# hurts the write, later the reverse -- so any phase change has to be judged on
# all four numbers at once, not on the one that was failing.
puts "== worst slack on those paths =="
puts [format "  setup:  write/command %s   read %s" \
        [worst setup -to [get_ports $out_ports]] \
        [worst setup -from [get_ports $in_ports]]]
puts [format "  hold :  write/command %s   read %s" \
        [worst hold  -to [get_ports $out_ports]] \
        [worst hold  -from [get_ports $in_ports]]]

delete_timing_netlist
project_close

if {$fail} {
    puts "check_sdram_paths: FAIL"
    exit 1
}
puts "check_sdram_paths: PASS"
exit 0
