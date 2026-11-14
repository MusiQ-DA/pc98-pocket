# jtag_gvram.tcl -- dump the graphics VRAM planes through the JTAG probe.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_gvram.tcl
#   OUT=gvram.bin START=A8000 LEN=40000 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_gvram.tcl
#
# Uses the debug cell's guest-memory read (write slot 8 = address with
# bit 0x200000, poll slot 0x9c until bit31 clears, low byte = data), the
# same path hwlog_pm/mem401.tcl uses. Default dump: the three 200-line
# plane banks A8000, B0000, B8000 (16 KB each, first half of each bank)
# concatenated into OUT (default /tmp/gvram.bin). Set START/LEN to read
# any other region instead.

proc toint {s} {
    if {[string match "0x*" $s] || [string is integer $s]} { return [expr {$s}] }
    return [expr {"0x$s"}]
}
if {![info exists ::env(OUT)]}   { set OUT /tmp/gvram.bin }   else { set OUT $::env(OUT) }
if {![info exists ::env(START)]} { set START 0 }             else { set START [toint $::env(START)] }
# default LEN=0 -> the three plane banks
if {![info exists ::env(LEN)]}   { set LEN 0 }               else { set LEN [toint $::env(LEN)] }

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
        if {($v >> 31) == 0} { return [expr {$v & 0xff}] }
        after 1
    }
    return -1
}
wr 0x0c 1

# regions: {name offset len}
if {$LEN > 0} {
    set regions [list [list region $START $LEN]]
} else {
    set regions [list \
        [list A8000 0xA8000 0x4000] \
        [list B0000 0xB0000 0x4000] \
        [list B8000 0xB8000 0x4000]]
}

set fh [open $OUT w]
fconfigure $fh -translation binary
set t0 [clock seconds]
foreach reg $regions {
    lassign $reg name off len
    puts ">> $name : $off len $len"
    set chunk {}
    for {set i 0} {$i < $len} {incr i} {
        set b [rdabs [expr {$off + $i}]]
        if {$b < 0} { puts "!! read timeout at [format %X [expr {$off+$i}]]"; set b 0 }
        puts -nonewline $fh [format %c $b]
        if {[expr {$i & 0xFFF}] == 0xFFF} {
            set el [expr {[clock seconds]-$t0}]
            puts "   $name [expr {$i+1}]/$len (${el}s)"
        }
    }
}
close $fh
puts ">> wrote $OUT ([file size $OUT] bytes) in [expr {[clock seconds]-$t0}]s"
shutdown
