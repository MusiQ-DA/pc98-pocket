# measure_counters.tcl -- read the SDRAM arbiter perf counters over JTAG.
#
# The counter build (branch perf-sdram-counters) packs a grant tally and a
# stall tally per sdram_mp port plus a total-cycle count into read slots
# 0x01-0x0B; write slot 0x8C re-zeroes the whole set. Slots under 0x80 are
# pure reads -- a probe scan with bit7 of the address set is a WRITE to
# addr[6:0], so these slots never alias onto live write registers.
#
#   openocd -f scripts/jtag_probe.cfg -f measure_counters.tcl
#   env: WAIT_S=N   seconds between clear and readout (default 10)
#
# Output: one line per port -- grants, stalls, stall-occupancy (share of
# controller cycles where the port's request was up but not taken, i.e.
# arbitration it lost) and grant-share. Then the total-cycle count.
#
# NOTE: reading back during the window freezes nothing -- the counters
# keep counting; only the 0x8C write clears them. Read any time for a
# snapshot; clear again to retake the window.

init

irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
set nnodes [expr {($hub >> 19) & 0xff}]
set mw     1
while {(1 << $mw) < $nnodes + 1} { incr mw }
puts [format "HUB_INFO=0x%08X  nodes=%d m_width=%d" $hub $nnodes $mw]
set virw [expr {$mw + 4}]

irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle   ;# probe node 1

proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}
proc wr {addr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {(($addr << 32) | $data) & 0xFFFFFFFFFF}] -endstate idle
}

set waits [expr {[info exists ::env(WAIT_S)] ? $env(WAIT_S) : 10}]

# Re-zero the set, let the workload accumulate for the window, then dump.
wr 0x8C 0
puts [format "# cleared; accumulating %d s" $waits]
after [expr {$waits * 1000}]

# Latch order: cycles first, then the port pairs -- the counters tick
# through the dump so an early cycles read bounds every later field.
set cycles [rd 0x0B]
set names {{"A guest-cpu"} {"B font-fetch"} {"C cg-window"} {"D gvram-disp"} {"E fdd-ramimg"}}
puts [format "cycles: %u" $cycles]
for {set p 0} {$p < 5} {incr p} {
    set g [rd [expr {2*$p + 1}]]
    set s [rd [expr {2*$p + 2}]]
    set pct "-"
    set gshare "-"
    if {$cycles > 0} {
        set pct    [format "%.2f" [expr {100.0 * $s / $cycles}]]
        set gshare [format "%.2f" [expr {100.0 * $g / $cycles}]]
    }
    puts [format "port %s: grants=%u stalls=%u stall-occupancy=%s%% grant-share=%s%%" \
        [lindex $names $p] $g $s $pct $gshare]
}
puts "# done"
shutdown
exit 0
