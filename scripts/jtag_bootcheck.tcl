# jtag_bootcheck.tcl -- pulse guest reset, wait, then report: live PC (x2 to
# see it advance), fault slot, RAM drop witness, and kernel boundary bytes.
# Env: DWWAIT ms to watch before sampling (default 4000), DWTIMES boots.

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
proc rb {off} {
    wr 0x88 [expr {($off & 0x1FFFFF) | 0x200000}]
    for {set j 0} {$j < 2000} {incr j} {
        set v [rd 0x9c]
        if {($v >> 31) == 0} { return [expr {$v & 0xff}] }
        after 1
    }
    return -1
}

set waits [expr {[info exists ::env(DWWAIT)] ? $env(DWWAIT) : 4000}]
set times [expr {[info exists ::env(DWTIMES)] ? $env(DWTIMES) : 1}]

for {set b 0} {$b < $times} {incr b} {
    wr 0x87 0x05
    after $waits
    set pc1 [rd 0x18]
    after 200
    set pc2 [rd 0x18]
    set fault [rd 0x38]
    set v39 [rd 0x39]
    set v3a [rd 0x3a]
    set drops   [expr {$v39 & 0xff}]
    set parks   [expr {$v3a & 0xffff}]
    set blocked [expr {($v3a >> 16) & 0xff}]
    puts [format "boot %d: pc %08x -> %08x  fault=%08x  lost=%d blocked=%d parks=%d firstlost=%05x st=%d" \
          $b $pc1 $pc2 $fault $drops $blocked $parks \
          [expr {($v39>>8)&0xfffff}] [expr {($v39>>29)&7}]]
    foreach a {0x600 0x800 0xa00 0xc00 0xe00 0x1000 0x1400 0x1c00 0x2200 0x2a00} {
        puts [format "  %05x: %02x" $a [rb $a]]
    }
}
shutdown
