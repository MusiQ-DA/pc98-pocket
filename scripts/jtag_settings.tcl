# jtag_settings.tcl -- dump every OSD setting (probe slots 0xB0-0xB7, four
# bytes each in settings_ui.c's SET_* order). Values are option indices.
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_settings.tcl
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

set names {{CPU Speed} {BIOS Write} {Audio Boost} {Speaker Vol} {Stereo Mix} {Display} {FDD Turbo} {200-Line Mode} {D-Pad} {Gamepad} {Disk LED} {EMS} {Drive Sound} {Text Rows} {Text Cols} {Boot Order} {Boot Device} {RAM Size} {DEL=BS} {Ext ROM} {CPU Cache}}
for {set g 0} {$g < 6} {incr g} {
  set w [rd [expr {0xB0 + $g}]]
  for {set b 0} {$b < 4} {incr b} {
    set i [expr {$g*4 + $b}]
    if {$i >= [llength $names]} break
    puts [format "%2d %-14s %d" $i [lindex $names $i] [expr {($w >> (8*$b)) & 0xFF}]]
  }
}
shutdown
