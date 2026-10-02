# jtag_pctrail.tcl -- dump the frozen pc_hist ring (slots 0x40-0x5f) in
# chronological order plus live pc/bridge/io for context.
init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
if {($hub >> 19) & 0xff < 1} { puts "no SLD nodes -- core running?"; shutdown; exit 1 }
set virw [expr {($hub & 0xff) + 4}]
irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle
proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}
puts [format "live pc   = 0x%08X" [rd 0x18]]
puts [format "bridge    = 0x%08X" [rd 0x1b]]
puts [format "last io   = 0x%08X" [rd 0x33]]
set first [rd 0x40]
set frozen [expr {($first >> 24) & 1}]
set w      [expr {($first >> 20) & 0x1f}]
puts [format "ring: frozen=%d wr_ptr=%d (entries 0x40+i, oldest first below)" $frozen $w]
set hist {}
for {set i 0} {$i < 32} {incr i} {
    lappend hist [expr {[rd [expr {0x40+$i}]] & 0xfffff}]
}
# chronological order: oldest entry is at index w (first overwritten), newest w-1
for {set k 0} {$k < 32} {incr k} {
    set idx [expr {($w + $k) % 32}]
    puts [format "  %2d: f%05x" $k [lindex $hist $idx]]
}
shutdown
