# jtag_lodecheck.tcl -- where did Lord Monarch (lodemnc) stop? Read-only.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_lodecheck.tcl
#
# Run it after the image has booted for ~20 s (np2kai shows "PRESENTED by
# Falcom" at ~2.5 s and the display-select menu at ~5 s). Reads guest RAM
# over probe slot 0x9c (rdabs) and prints what the reference holds at the
# menu (np2kai, same bios/itf/font):
#   IVT 00 1000:073C  08 FD80:01FC  09 1000:07E0  0A 1000:0755
#       13 1000:0873  14 1000:0D52  15 1000:08B6   (the game's handlers)
#   0:3C1A  saved BIOS INT 13h   0:32DA  VSYNC down-counter (moves every frame)
#   0:055C  DISK_EQUIP (0003)    0:3286  display type (00 analog / 01 LCD)
#   1000:0000.. PROG.BIN  58268 bytes, byte sum 7155167 (unchanged at the menu)
#   0:FE00  zero in the reference (the hardware had 5C 05 repeated: stack wrap)
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
proc hexdump {a n} {
    set s [format "%05X:" $a]
    for {set i 0} {$i < $n} {incr i} { append s [format " %02X" [rdabs [expr {$a+$i}]]] }
    puts $s
}
foreach v {0x00 0x05 0x06 0x08 0x09 0x0A 0x13 0x14 0x15} {
    puts [format "IVT %02X %04X:%04X" $v [w16 [expr {$v*4+2}]] [w16 [expr {$v*4}]]]
}
puts [format "3C1A %04X:%04X  055C %04X  3286 %02X" [w16 0x3C1C] [w16 0x3C1A] [w16 0x55C] [rdabs 0x3286]]
set c0 [w16 0x32DA]; after 1000; set c1 [w16 0x32DA]
puts [format "32DA %04X -> %04X after 1 s (VSYNC ISR alive if it moved)" $c0 $c1]
hexdump 0x1FC00 16
hexdump 0x10000 16
hexdump 0x00F00 256
hexdump 0x0FE00 64
if {[info exists ::env(SUM)]} {
    set s 0
    for {set i 0} {$i < 58268} {incr i} { incr s [rdabs [expr {0x10000 + $i}]] }
    puts "PROG.BIN sum $s (reference 7155167)"
}
shutdown
