# jtag_memrd.tcl -- read guest RAM / ramdisk carve-out bytes over JTAG via
# fdd_ramimg's readback probe (slot 0x88 arm + slot 0x37 result).
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_memrd.tcl
#   env: MRADDR=0x1ff00   first guest-RAM byte offset (default 0x1ff80)
#        MRLEN=N          byte count (default 64)
#        MRABS=0          image carve-out space instead of absolute RAM
#
# One readback byte costs one slot write plus polls of slot 0x37.

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

proc select_node {n} {
    global virw
    irscan fpga.tap 0x0e
    drscan fpga.tap $virw [expr {($n << 4) | 8}] -endstate idle
}

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

# absolute-mode readback: byte N of guest RAM is word N of SDRAM
proc rdabs {off} {
    wr 0x88 [expr {($off & 0x1FFFFF) | 0x200000}]
    for {set i 0} {$i < 2000} {incr i} {
        set v [rd 0x37]
        if {($v >> 31) == 0} { return [expr {$v & 0xff}] }
        after 1
    }
    return -1
}
proc rdimg {off} {
    wr 0x88 [expr {$off & 0x1FFFFF}]
    for {set i 0} {$i < 2000} {incr i} {
        set v [rd 0x37]
        if {($v >> 31) == 0} { return [expr {$v & 0xff}] }
        after 1
    }
    return -1
}

select_node 1
puts [format "0x35 (ramimg)  = 0x%08X" [rd 0x35]]
puts [format "0x38 (fault)   = 0x%08X" [rd 0x38]]
puts [format "0x18 (live PC) = 0x%08X" [rd 0x18]]

set base [expr {[info exists ::env(MRADDR)] ? $env(MRADDR) : 0x1ff80}]
set len  [expr {[info exists ::env(MRLEN)]  ? $env(MRLEN)  : 64}]
set abs  [expr {[info exists ::env(MRABS)]  ? $env(MRABS)  : 1}]

set line {}
set addr $base
for {set i 0} {$i < $len} {incr i} {
    set b [expr {$abs ? [rdabs [expr {$addr + $i}]] : [rdimg [expr {$addr + $i}]]}]
    if {$b < 0} { puts "probe stuck at offset [format %x [expr {$addr+$i}]]"; break }
    lappend line [format %02x $b]
    if {[llength $line] == 16} {
        puts [format "%05x: %s" [expr {$addr + $i - 15}] [join $line " "]]
        set line {}
    }
}
if {[llength $line]} {
    puts [format "%05x: %s" [expr {$addr + $len - [llength $line]}] [join $line " "]]
}
shutdown
exit 0
