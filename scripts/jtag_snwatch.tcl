# jtag_snwatch.tcl -- the port-A write-commit snoop witnesses, live.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_snwatch.tcl
#   env: WATCH=0x373A3   the watched guest address (slot 0x06's trig_addr,
#                        kill-counted by z86_cache; default = SuperDepth's
#                        high-score date byte)
#        LOOPS=10        poll cycles (default 10)
#        GAP=2000        ms between polls (default 2000)
#
# Slots (see core_top's probe case; 0x6c-0x70 landed with the snoop taps):
#   0x6c sn_v_cnt      every port-A write commit, any master -- 16-bit
#                      FREE-RUNNING: read as deltas mod 65536 (a saturating
#                      count would pin during the ITF memory test alone)
#   0x6d sn_dma_cnt    commits while AEN (DMA/loader owns the bus), same
#   0x6e {len,4'b0,addr[23:0]}   newest commit, any master
#   0x6f {len,4'b0,addr[23:0]}   newest AEN-window commit
#   0x70 {16'h0, z86 kills of the watched line}   (armed via slot 0x86;
#                      free-running too, one clk behind the kill)
#   0x3e {breaks[7:0],grants[7:0],ack_wr_cnt[15:0]}  bus-side FDC strobes
#
# Reading it: start this BEFORE the game's disk load (or while it runs).
# Delta columns (+N) are the verdict -- absolute values wrap.
#   sn_v deltas always 0
#                           the whole snoop feed is dead -- nothing on the
#                           metal ever pulses a_wr_v (or the wire is lost).
#   sn_v moving but sn_dma deltas 0
#                           port A commits, but none inside the DMA window --
#                           the FDC's bytes are not the commits being counted.
#   both moving, 0x6f's addr walking the fill buffer and 0x3e's ackwr
#   climbing in step        sn_v DOES fire for FDC DMA commits -- the feed
#                           is fine and the stale read is a cache-side
#                           window, not a missing invalidation.
#   0x70 frozen while 0x6d climbs into the watched buffer
#                           the commits reach core_top but the cache never
#                           kills the watched line -- sn_ours/index trouble.

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
proc wr {addr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {(($addr << 32) | $data) & 0xFFFFFFFFFF}] -endstate idle
}

select_node 1

set watch 0x373A3
if {[info exists ::env(WATCH)]} { set watch [expr {$env(WATCH) & 0xFFFFF}] }
set loops 10
if {[info exists ::env(LOOPS)]} { set loops $env(LOOPS) }
set gap 2000
if {[info exists ::env(GAP)]} { set gap $env(GAP) }

# Arm the watched address only: bit31 (trig_en) stays 0 so the trigger,
# freeze and watchpoint machinery all stay disarmed -- only trig_addr
# (and z86_cache's kill counter) pick the value up.
wr 0x86 $watch
puts [format "watched address armed at %05x (trigger itself disarmed)" $watch]

set pv 0; set pd 0; set pk 0; set pa 0
for {set i 0} {$i < $loops} {incr i} {
    set v  [rd 0x6c]
    set d  [rd 0x6d]
    set la [rd 0x6e]
    set da [rd 0x6f]
    set k  [rd 0x70]
    set sw [rd 0x3e]
    puts [format "sn_v=%-6u (+%-6u) sn_dma=%-6u (+%-6u) last=%06x/%d dma_last=%06x/%d kills=%u (+%u) ackwr=%u grants=%u" \
        $v [expr {$v - $pv}] $d [expr {$d - $pd}] \
        [expr {$la & 0xffffff}] [expr {($la >> 28) & 0xf}] \
        [expr {$da & 0xffffff}] [expr {($da >> 28) & 0xf}] \
        $k [expr {$k - $pk}] \
        [expr {$sw & 0xffff}] [expr {($sw >> 16) & 0xff}]]
    set pv $v; set pd $d; set pk $k
    if {$i < $loops - 1} { after $gap }
}

shutdown
