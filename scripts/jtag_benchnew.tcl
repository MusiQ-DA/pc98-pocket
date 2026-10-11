# jtag_benchnew.tcl -- one benchmark point without a screen probe:
#   1) pin clk_select via probe slot 0x89  (SPD=0..3, or "clear")
#   2) pulse guest reset via fdd_ramimg ctl 0x87=0x05 (image stays mounted)
#   3) sample the live bus-address node (slot 0x18) at ~20 Hz for SECS
#      seconds; prints "ms pc" for the host to bracket the 0x4xxxx window.
#
#   SPD=1 SECS=240 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_benchnew.tcl

init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
if {($hub >> 19) & 0xff < 1} { puts "no SLD nodes -- core running?"; shutdown; exit 1 }
set nnodes [expr {($hub >> 19) & 0xff}]
set mw 1
while {(1 << $mw) < $nnodes + 1} { incr mw }
set virw [expr {$mw + 4}]
irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle

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

# 1) speed
set spd [expr {[info exists ::env(SPD)] ? $::env(SPD) : -1}]
if {$spd eq "clear"} {
    wr 0x89 0
    puts "speed override cleared"
} elseif {$spd >= 0} {
    wr 0x89 [expr {4 | ($spd & 3)}]
    puts [format "speed override: clk_select=%d" $spd]
}

# 2) guest reset (enable + greset pulse)
wr 0x87 0x05
puts "guest reset pulsed"

# 3) sample
set secs [expr {[info exists ::env(SECS)] ? $::env(SECS) : 420}]
set per  [expr {[info exists ::env(MS)]   ? $::env(MS)   : 50}]
set t0 [clock milliseconds]
set n [expr {$secs * 1000 / $per}]
for {set i 0} {$i < $n} {incr i} {
    set pc [rd 0x18]
    set now [expr {[clock milliseconds] - $t0}]
    puts [format "%d %s" $now [string range $pc 1 end]]
    after $per
}
shutdown
