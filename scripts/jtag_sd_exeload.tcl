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
# must be in RAM. STALE62 = file sector 62's bytes (e2f08bda...) there
# instead: DOS re-read LBA 297 (C18 H1 R2) for every later sector of the
# file. Root cause found on hardware (2026-10-31, #1030): NOT the disk path --
# the FAT the card's image carries has entry 288 = 0x120 (a self-loop; the
# pristine testdisk/superdepth.hdm has 0x121), so FreeDOS's cluster walk
# never leaves cluster 288 = LBA 297. The image on the SD card had been
# rewritten by earlier sessions (its root dir also shows DEPTH.SCR resaved),
# the JTAG RAM image is always the pristine file, hence "SD only".
# Each trial therefore also prints the FAT buffer's DEPTH.EXE chain
# (clusters 226..295 -> EOF): fat=ok, or fat=BAD@<n>-><next>.
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
# FreeDOS's FAT buffer: the kernel's buffers sit at 05AA:k*0x414 on this
# disk ({next, prev, unit, flag, blkno[4], ...} then 0x400 bytes from +0x14).
# Find the one holding LBA 1 (the first FAT sector) and walk DEPTH.EXE's
# chain, which on the pristine image is contiguous 226..295 then EOF.
proc fatchain {} {
  for {set k 0} {$k < 8} {incr k} {
    set h [expr {0x5AA0 + $k*0x414}]
    if {[w16 [expr {$h+6}]] == 1 && [w16 [expr {$h+8}]] == 0} {
      set f [expr {$h + 0x14}]
      for {set n 226} {$n <= 295} {incr n} {
        set o [expr {$f + ($n*3)/2}]
        set v [w16 $o]
        set e [expr {($n & 1) ? ($v >> 4) : ($v & 0xFFF)}]
        set want [expr {$n == 295 ? 0xFFF : $n + 1}]
        if {$e != $want && !($n == 295 && $e >= 0xFF8)} {
          return [format "BAD@%d->%03X" $n $e]
        }
      }
      return ok
    }
  }
  return nobuf
}
# SD-floppy DEPTH.EXE load check: guest reset WITHOUT the RAM image (slot 7
# bit2 only), wait W s, compare DEPTH.EXE file sector 66 at 0x35C10.
set N $::env(N); set W $::env(W); set P [expr {[info exists ::env(P)] ? $::env(P) : 0}]
if {[info exists ::env(SLOTS)]} { wr 0x0c 1 }
set fails 0
puts [format "start 0x2a=%08X" [rd 0x2a]]
for {set it 0} {$it < $N} {incr it} {
  wr 9 $P; after 20; wr 7 0x04
  after [expr {$W*1000}]
  set s ""
  for {set i 0} {$i < 8} {incr i} { append s [format "%02x" [rdabs [expr {0x35C10+$i}]]] }
  set own [w16 0x25501]
  if {$s eq "204d6f726920616e"} { set r ok } elseif {$s eq "e2f08bdaf7dbf7db"} { set r STALE62 } else { set r OTHER; incr fails }
  if {$r eq "STALE62"} { incr fails }
  puts [format "it=%2d own=%04X s66=%s %s fat=%s pc=%05X" $it $own $s $r [fatchain] [expr {[rd 0x18] & 0xFFFFF}]]
  flush stdout
}
puts "fails=$fails/$N"
wr 9 0
shutdown
