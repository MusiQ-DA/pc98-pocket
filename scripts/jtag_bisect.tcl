# jtag_bisect.tcl -- arm the +3 ms POST-kill bisect flags (probe write slot
# 0x84 bit31) on PC98_PROBE_EXTRA debug builds.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_bisect.tcl
#   env: MODE -- "holdonly+early" (default), "early", "holdonly", "clear"
#
# bit31 arms flags from [21:20] instead of issuing an access:
#   bit21 early     -> the auto walk fires at ~3 ms (one-shot) not ~6.2 s
#   bit20 hold_only -> master borrows the bus ~46 ms, never strobes
#
# Then press Reset PC on the Pocket: the armed shot fires during the POST.
# Read result with jtag_probe_read.tcl / jtag_screen.tcl.

init

# --- hub select (same dance as jtag_probe_read.tcl) -------------------------
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
if {($hub >> 19) & 0xff} { } else { puts "no SLD nodes"; shutdown; exit 1 }
set virw [expr {($hub & 0xff) + 4}]
irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle

proc wr {addr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {(($addr << 32) | $data) & 0xFFFFFFFFFF}] -endstate idle
}

set MODE [expr {[info exists ::env(MODE)] ? $env(MODE) : "holdonly+early"}]
switch -- $MODE {
    "early"          { set cmd 0x80200000 }
    "holdonly"       { set cmd 0x80100000 }
    "holdonly+early" { set cmd 0x80300000 }
    "clear"          { set cmd 0x80000000 }
    default          { puts "unknown MODE $MODE"; shutdown; exit 1 }
}
wr 0x84 $cmd
puts [format "armed MODE=%s (0x%08X) -- now press Reset PC" $MODE $cmd]
shutdown
