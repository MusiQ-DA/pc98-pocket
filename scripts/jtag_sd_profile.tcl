# jtag_sd_profile.tcl -- time-series PC profile of SuperDepth under random play.
#
#   HDIMG=testdisk/superdepth.hdm openocd -f scripts/jtag_probe.cfg -f scripts/jtag_hdload.tcl
#   P=0x0F M=8 W=45 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_sd_profile.tcl
#
# START the game, then for M minutes: ~18 s of random keys (same set as the
# regression's PLAY), then a batch of 24 PC samples (slot 0x18, 47 ms apart)
# printed as one line. Offline: histogram the batches per time window --
# stage transitions show up as the hot clusters moving, and the heavy
# stage's hot loop is where its samples pile up.
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
set P [expr {[info exists ::env(P)] ? [expr {$::env(P)}] : 0}]
set W [expr {[info exists ::env(W)] ? $::env(W) : 45}]
set M [expr {[info exists ::env(M)] ? $::env(M) : 8}]
wr 0x0c 1
wr 9 $P; after 20; wr 7 0x05
after [expr {$W*1000}]
wr 1 0x1C; after 300; wr 1 0x9C
after 2000
set keys {0x3B 0x3C 0x34 0x1C 0x29 0x2A}
set t0 [clock milliseconds]
while {[clock milliseconds] - $t0 < $M*60*1000} {
    set tp [clock milliseconds]
    while {[clock milliseconds] - $tp < 18000} {
        set k [lindex $keys [expr {int(rand()*[llength $keys])}]]
        wr 1 $k; after [expr {60 + int(rand()*400)}]; wr 1 [expr {$k | 0x80}]
        after [expr {20 + int(rand()*200)}]
    }
    set pcs {}
    for {set q 0} {$q < 24} {incr q} {
        lappend pcs [expr {[rd 0x18] & 0xFFFFF}]
        after 47
    }
    set tsec [expr {([clock milliseconds] - $t0) / 1000}]
    set l ""; foreach p $pcs { append l [format " %05X" $p] }
    puts [format "t=%4d pcs:$l" $tsec]
    flush stdout
}
wr 9 0
shutdown
