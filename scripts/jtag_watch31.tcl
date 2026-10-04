# jtag_watch31.tcl -- watch the GVRAM sequencer's service channel live.
#
# Polls slot 0x32 until the draw server's req or busy bit is nonzero, then
# dumps slot 0x31 {req,done,hold,st,gp} and 0x32 in a tight loop so a
# mid-draw sample sequence lands on stdout.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_watch31.tcl
#   env: WPRE=seconds to keep waiting for a draw (default 30)
#        WN=number of samples after triggering (default 300)

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
set mw     1
while {(1 << $mw) < $nnodes + 1} { incr mw }
puts [format "HUB_INFO=0x%08X  nodes=%d m_width=%d" $hub $nnodes $mw]
set virw [expr {$mw + 4}]

proc select_node {n} {
    global virw
    irscan fpga.tap 0x0e
    drscan fpga.tap $virw [expr {($n << 4) | 8}] -endstate idle
}

proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}

select_node 1

set pre [expr {[info exists ::env(WPRE)] ? $env(WPRE) : 30}]
set n   [expr {[info exists ::env(WN)]   ? $env(WN)   : 300}]

# wait for a draw in flight: slot 0x32 bits[13:10] = {busy,req}
set hit 0
for {set i 0} {$i < [expr {$pre * 100}]} {incr i} {
    set v [rd 0x32]
    if {(($v >> 10) & 0xF) != 0} { set hit 1; break }
    after 10
}
if {!$hit} {
    puts "no draw seen within $pre s"
    puts [format "0x32 = 0x%08X" [rd 0x32]]
    puts [format "0x31 = 0x%08X" [rd 0x31]]
    shutdown; exit 1
}
puts [format "TRIGGER 0x32 = 0x%08X" $v]
for {set i 0} {$i < $n} {incr i} {
    set a [rd 0x31]
    set b [rd 0x32]
    puts [format "%3d: 0x31=%08X 0x32=%08X" $i $a $b]
}
shutdown
exit 0
