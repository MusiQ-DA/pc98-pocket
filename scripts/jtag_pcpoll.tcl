# jtag_pcpoll.tcl -- sample the live bus-address node (slot 0x18) at ~20 Hz
# in ONE openocd session. Prints "ms pc" lines so a host log can bracket
# the CPUBENCH 0x4xxxx execution window without paying per-sample init.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_pcpoll.tcl
# Env: PCSECS (duration, default 420), PCMS (period ms, default 50)

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

set secs  [expr {[info exists ::env(PCSECS)] ? $::env(PCSECS) : 420}]
set per   [expr {[info exists ::env(PCMS)]   ? $::env(PCMS)   : 50}]
set t0 [clock milliseconds]
set n [expr {$secs * 1000 / $per}]
for {set i 0} {$i < $n} {incr i} {
    set pc [rd 0x18]
    set now [expr {[clock milliseconds] - $t0}]
    puts [format "%d %s" $now [string range $pc 1 end]]
}
shutdown
