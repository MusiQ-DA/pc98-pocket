# jtag_superdepth.tcl -- SuperDepth START regression over the JTAG probe.
#
#   HDIMG=testdisk/superdepth.hdm openocd -f scripts/jtag_probe.cfg -f scripts/jtag_hdload.tcl
#   P=0x07 N=40 W=45 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_superdepth.tcl
#
# Each trial: CPU speed P into slot 9, guest reset, W seconds for DOS and
# the title screen, then a START keypress (keyboard scan 1C = Enter) and
# 12 s of play. Pass = the game's MCB at 2550:0001 owns itself (2551) and
# its blitter word at DEPTH+C193 holds one of its live values -- a failed
# START leaves garbage there. P=0x07 is turbo, P=0 10 MHz.
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
proc w16 {a} { return [expr {[rdabs $a] | ([rdabs [expr {$a+1}]]<<8)}] }
set N $::env(N); set W $::env(W); set P [expr {[info exists ::env(P)] ? $::env(P) : 0}]
set fails 0
for {set it 0} {$it < $N} {incr it} {
  wr 9 $P; after 20; wr 7 0x05
  after [expr {$W*1000}]
  set pre [w16 0x25501]
  wr 1 0x1C; after 300; wr 1 0x9C
  after 12000
  set own [w16 0x25501]; set c193 [w16 [expr {0x25610+0xC193}]]
  set pc [expr {[rd 0x18] & 0xFFFFF}]
  set bad [expr {$own != 0x2551 || ($c193 != 0x20 && $c193 != 0x10 && $c193 != 0x1122)}]
  if {$bad} {incr fails}
  puts [format "it=%2d pre=%04X own=%04X c193=%04X pc=%05X %s" $it $pre $own $c193 $pc [expr {$bad ? "FAIL" : "ok"}]]
  flush stdout
}
puts "fails=$fails/$N"
shutdown
