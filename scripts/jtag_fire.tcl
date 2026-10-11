# fire a keystroke into slot 0x81 (keyboard matrix byte)
init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} { scan [drscan fpga.tap 4 0 -endstate idle] %x nib; set hub [expr {$hub | ($nib << (4*$i))}] }
set nnodes [expr {($hub >> 19) & 0xff}]
set mw 1
while {(1 << $mw) < $nnodes + 1} { incr mw }
set virw [expr {$mw + 4}]
irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle
proc wr {addr data} { irscan fpga.tap 0x0c; drscan fpga.tap 40 [expr {(($addr << 32) | $data) & 0xFFFFFFFFFF}] -endstate idle }
wr 1 0x34
after 80
wr 1 0xB4
after 80
puts "key fired"
shutdown
exit 0
