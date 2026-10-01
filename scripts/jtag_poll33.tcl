# poll probe slots repeatedly to see the live PC range + last IO write
init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
if {($hub >> 19) & 0xff < 1} { puts "no SLD nodes"; shutdown; exit 1 }
irscan fpga.tap 0x0e
drscan fpga.tap 5 0x18 -endstate idle
proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}
for {set i 0} {$i < 90} {incr i} {
    puts [format "pc=%08x  brg=%08x  io=%08x  ad=%08x" [rd 0x18] [rd 0x1b] [rd 0x33] [rd 0x1c]]
    after 120
}
shutdown
