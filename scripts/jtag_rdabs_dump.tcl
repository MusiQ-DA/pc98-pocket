# jtag_rdabs_dump.tcl -- dump guest RAM regions via the probe's absolute-read
# slot (0x9c). Primitives copied from scripts/jtag_superdepth.tcl:1-48 (the
# file itself runs trials when sourced, so only the procs are reusable here).
#
# Usage:
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_rdabs_dump.tcl
# Env: REGIONS="0x30E80:0xC0 0x31120:0x60 ..."  (start:len hex pairs)

# --- hub / primitive setup (jtag_superdepth.tcl:14-28) ---
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
set mw 1
while {(1 << $mw) < $nnodes + 1} { incr mw }
set virw [expr {$mw + 4}]
irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle

proc wr {waddr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {((0x80 | $waddr) << 32) | ($data & 0xFFFFFFFF)}] -endstate idle
}
proc rd {a} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {$a << 32}] -endstate idle
    set r [drscan fpga.tap 40 0 -endstate idle]
    scan [string range $r end-7 end] %x v
    return $v
}
proc rdabs {off} {
    wr 8 [expr {($off & 0x1FFFFF) | 0x200000}]
    for {set i 0} {$i < 2000} {incr i} {
        set v [rd 0x9c]
        if {[expr {$v & 0x80000000}] == 0} { return [expr {$v & 0xff}] }
    }
    return -1
}

# --- dump loop ---
set regions $::env(REGIONS)
foreach spec $regions {
    scan $spec %x:%x start len
    puts [format "REGION %05X LEN %X" $start $len]
    set line ""
    for {set o 0} {$o < $len} {incr o} {
        set b [rdabs [expr {$start + $o}]]
        append line [format "%02X " $b]
        if {($o % 16) == 15} { puts [format "%05X: %s" [expr {$start + $o - 15}] $line]; set line "" }
    }
    if {$line ne ""} { puts [format "%05X: %s" [expr {$start + $len - [string length $line] / 3}] $line] }
    flush stdout
}
shutdown
