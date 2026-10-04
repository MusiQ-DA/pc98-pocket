# jtag_pcsnap.tcl -- re-arm the PC-history snapshot and/or read it.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_pcsnap.tcl
#
#   env:
#     REARM=1     write slot 0x85 first (resume recording + arm snapshot)
#     (always)    dump slots 0x40-0x5F -- frozen pc_snap if valid, else the
#                 live pc_hist ring. w= write pointer; entries after w are
#                 the oldest.
init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0e
drscan fpga.tap 5 0x18 -endstate idle
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
if {[info exists ::env(REARM)] && $::env(REARM)} {
    wr 5 0
    puts "re-armed: pc_hist_frozen=0 pc_snap_valid=0"
}
set w 0
for {set i 0x40} {$i <= 0x5f} {incr i} {
    set v [rd $i]
    set pc [expr {$v & 0xfffff}]
    set wp [expr {($v >> 20) & 0x1f}]
    set frz [expr {($v >> 25) & 1}]
    set w $wp
    lappend pcs $pc
    puts [format "  ring[%02d] = %05x" [expr {$i - 0x40}] $pc]
}
puts [format "valid/frozen=%d w=%d -- chronological order:" $frz $w]
set out ""
for {set k 0} {$k < 32} {incr k} {
    set idx [expr {($w + $k) % 32}]
    append out [format "%05x " [lindex $pcs $idx]]
    if {($k % 8) == 7} { append out "\n" }
}
puts $out
shutdown
