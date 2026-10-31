# jtag_sd_exeload.tcl -- SD-floppy DEPTH.EXE load regression over the probe.
#
#   N=40 W=50 P=0x07 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_sd_exeload.tcl
#
# Unlike jtag_superdepth.tcl this does NOT use the RAM image: each trial is a
# plain guest reset (slot 7 bit2 only), so DOS and DEPTH.EXE come off the SD
# card through the firmware FDD service, the disk bridge and the APF target
# dataslot reads. Floppy A must be superdepth.hdm (or superdepth_tr.hdm) and
# the slots must have been streamed: launch the core fresh on the Pocket,
# then JTAG-flash, then run this (SLOTS=1 also declares them present).
#
# Check: DEPTH.EXE file sector 66 (" Mori and Yasuo" text, linear 0x35C10)
# must be in RAM. The failure this guards (DEPTH.EXE LBA 298-304 delivered
# as LBA 297 because the APF reported reads done before their data landed)
# leaves file sector 62's bytes (e2f08bda...) there instead -- STALE62.
# Slot 0x6C is the bridge's landing gate {early completions, read commands}.
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
# SD-floppy DEPTH.EXE load check: guest reset WITHOUT the RAM image (slot 7
# bit2 only), wait W s, compare DEPTH.EXE file sector 66 at 0x35C10.
set N $::env(N); set W $::env(W); set P [expr {[info exists ::env(P)] ? $::env(P) : 0}]
if {[info exists ::env(SLOTS)]} { wr 0x0c 1 }
set fails 0
puts [format "start 0x6c=%08X 0x2a=%08X" [rd 0x6c] [rd 0x2a]]
for {set it 0} {$it < $N} {incr it} {
  wr 9 $P; after 20; wr 7 0x04
  after [expr {$W*1000}]
  set s ""
  for {set i 0} {$i < 8} {incr i} { append s [format "%02x" [rdabs [expr {0x35C10+$i}]]] }
  set own [w16 0x25501]
  if {$s eq "204d6f726920616e"} { set r ok } elseif {$s eq "e2f08bdaf7dbf7db"} { set r STALE62 } else { set r OTHER; incr fails }
  if {$r eq "STALE62"} { incr fails }
  puts [format "it=%2d own=%04X s66=%s %s 0x6c=%08X pc=%05X" $it $own $s $r [rd 0x6c] [expr {[rd 0x18] & 0xFFFFF}]]
  flush stdout
}
puts "fails=$fails/$N"
wr 9 0
shutdown
