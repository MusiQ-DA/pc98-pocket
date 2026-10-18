# jtag_superdepth.tcl -- SuperDepth START regression over the JTAG probe.
#
#   HDIMG=testdisk/superdepth.hdm openocd -f scripts/jtag_probe.cfg -f scripts/jtag_hdload.tcl
#   P=0x07 N=40 W=45 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_superdepth.tcl
#
# Each trial: CPU speed P into slot 9, guest reset, W seconds for DOS and
# the title screen, then a START keypress (keyboard scan 1C = Enter) and
# 12 s of play. Pass = the game's MCB at 2550:0001 owns itself (2551) and
# its blitter word at DEPTH+C193 holds one of its live values -- a failed
# START leaves garbage there. P=0x07 is turbo, P=0x05 10 MHz (P=0 keeps the
# OSD speed, which a JTAG-loaded image never set).
# PLAY=<s> then plays on with random keys and fails any disk-BIOS interrupt
# timeout (see below).
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
set PLAY [expr {[info exists ::env(PLAY)] ? $::env(PLAY) : 0}]
# After a JTAG reflash APF does not re-stream the slots; declare them
# present (core_top slot 0x0c) so the guest leaves reset.
wr 0x0c 1
set fails 0
for {set it 0} {$it < $N} {incr it} {
  wr 9 $P; after 20; wr 7 0x05
  after [expr {$W*1000}]
  set pre [w16 0x25501]
  wr 1 0x1C; after 300; wr 1 0x9C
  after 12000
  set own [w16 0x25501]; set c193 [w16 [expr {0x25610+0xC193}]]
  # the game must still be running: of up to 60 PC samples over 3 s, none
  # at the reset vector and at least two different ones in the game's code
  # (it spends much of its time in a BIOS loop at FF97C; a crashed CPU never
  # comes back to two places in the game)
  # (the MCB/blitter words survive a crash, and a wedged or reset CPU
  # passed on them alone)
  set pcs {}
  set alive 1
  set ingame {}
  for {set round 0} {$round < 3 && [llength [lsort -unique $ingame]] < 2} {incr round} {
    for {set q 0} {$q < 20} {incr q} {
      set p [expr {[rd 0x18] & 0xFFFFF}]
      lappend pcs $p
      if {$p == 0xFFFF0} { set alive 0 }
      if {$p >= 0x25500 && $p < 0x40000} { lappend ingame $p }
      after 47
    }
  }
  set pc [lindex $pcs 0]
  if {[llength [lsort -unique $ingame]] < 2} { set alive 0 }
  set quick_bad [expr {!$alive || $own != 0x2551}]
  # PLAY=<s>: keep playing with random left/right / Z / X / space / return
  # presses (never up/down: after a game over the title menu takes them, and
  # up/down + Z picks its EXIT entry -- a legitimate return to DOS) and
  # count the disk BIOS giving up on an interrupt (FFA57, the timeout exit
  # of its FF97C wait -- the game polls the empty 2HD drive, and a lost FDC
  # interrupt costs ~40 s of frozen screen per call). Any timeout fails.
  set tmo 0
  if {$PLAY > 0 && !$quick_bad} {
    wr 6 [expr {0x80000000 | 0xFFA57}]
    set t0 [clock milliseconds]
    set keys {0x3B 0x3C 0x34 0x1C 0x29 0x2A}
    while {[clock milliseconds] - $t0 < $PLAY*1000} {
      set k [lindex $keys [expr {int(rand()*[llength $keys])}]]
      wr 1 $k; after [expr {60 + int(rand()*400)}]; wr 1 [expr {$k | 0x80}]
      after [expr {20 + int(rand()*200)}]
    }
    set tmo [expr {[rd 0x67] & 0xFFFF}]
    wr 6 0x0FFFF0
    set ingame {}
    set pcs2 {}
    for {set q 0} {$q < 60 && [llength [lsort -unique $ingame]] < 2} {incr q} {
      set p [expr {[rd 0x18] & 0xFFFFF}]
      lappend pcs2 $p
      if {$p == 0xFFFF0} { set alive 0 }
      if {$p >= 0x25500 && $p < 0x40000} { lappend ingame $p }
      after 47
    }
    if {[llength [lsort -unique $ingame]] < 2} { set alive 0 }
  }
  set bad [expr {!$alive || $own != 0x2551 || ($c193 != 0x20 && $c193 != 0x10 && $c193 != 0x1122) || $tmo != 0}]
  if {$bad} {incr fails}
  # floppy.v's command-byte counters: a byte the chip dropped (it arrived
  # busy) turns the rest of that command into garbage
  set fd [rd 0x26]
  puts [format "it=%2d pre=%04X own=%04X c193=%04X pc=%05X tmo=%d fdc_acc=%d drop=%d %s" $it $pre $own $c193 $pc $tmo [expr {($fd >> 15) & 0xFF}] [expr {($fd >> 23) & 0xFF}] [expr {$bad ? "FAIL" : "ok"}]]
  if {$bad} { set l ""; foreach p $pcs { append l [format " %05X" $p] }; puts "   pcs:$l" }
  if {$bad && [info exists pcs2]} { set l ""; foreach p [lrange [lsort -unique $pcs2] 0 30] { append l [format " %05X" $p] }; puts "   post:$l" }
  if {[info exists pcs2]} { unset pcs2 }
  # STOPFAIL=1: leave a failed trial on screen for inspection
  if {$bad && [info exists ::env(STOPFAIL)]} break
  flush stdout
}
puts "fails=$fails/$N"
# Hand the speed back to the OSD: a P override left in slot 9 outlives the
# run and pins whoever plays next to the tested speed.
wr 9 0
shutdown
