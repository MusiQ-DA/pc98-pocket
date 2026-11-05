# jtag_blackband.tcl -- read the graphics display's black-band / PRAM-timing
# witness (pc98_gvram_display dbg_band, probe slots 0x84-0x86).
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_blackband.tcl
#   env: BBN=N     samples (default 1)
#        BBMS=ms   spacing between samples (default 1000)
#
#   0x84 = {band_cnt[15:0], pram_cnt[15:0]}
#          band_cnt: frames (slave display on) whose longest run of
#                    consecutive ALL-BLACK graphics lines (all 640 dots
#                    palette index 0) was >= 8 lines
#          pram_cnt: frames during whose lines 0..399 the live slave PRAM
#                    (SAD/LEN/pitch unit, PITCH) differed from the frame's
#                    snapshot -- a SCROLL write that landed while the frame
#                    was shown, applied from the next frame
#   0x85 = {7'0, last_start[8:0], 7'0, last_max[8:0]}   last finished frame
#   0x86 = {7'0, worst_start[8:0], 7'0, worst_max[8:0]} worst frame since
#                                                       power-up
# All counters are since configuration (no reset/clear). Lines above a
# nonzero SYNC VBP offset are blank by design and count as black.
#
# SuperDepth "Clear!" wipe (68 frames): expect pram_cnt to rise by up to 68
# (one per wipe frame whose SCROLL write lands in the active display) and
# band_cnt NOT to rise across the wipe if the black band is gone. Read once
# before and once after the wipe and diff. A band_cnt rise with worst_start
# near 396-bx (the partition seam) points back at the PRAM walk; elsewhere,
# at drawing/VRAM timing.
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
if {$nnodes < 1} { puts "no SLD nodes -- is the core running?"; shutdown; exit 1 }
set mw 1
while {(1 << $mw) < $nnodes + 1} { incr mw }
set virw [expr {$mw + 4}]
proc select_node {n} {
    global virw
    irscan fpga.tap 0x0e
    drscan fpga.tap $virw [expr {($n << 4) | 8}] -endstate idle
}
select_node 1

proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}

set n 1
if {[info exists ::env(BBN)]} { set n $::env(BBN) }
set ms 1000
if {[info exists ::env(BBMS)]} { set ms $::env(BBMS) }

set t0 [clock milliseconds]
for {set i 0} {$i < $n} {incr i} {
    set c [rd 0x84]
    set l [rd 0x85]
    set w [rd 0x86]
    set band [expr {($c >> 16) & 0xffff}]
    set pram [expr {$c & 0xffff}]
    set lst  [expr {($l >> 16) & 0x1ff}]
    set lmx  [expr {$l & 0x1ff}]
    set wst  [expr {($w >> 16) & 0x1ff}]
    set wmx  [expr {$w & 0x1ff}]
    puts [format "t=%6.1f band_frames=%5d pram_late_frames=%5d | last: run=%3d @y%3d | worst: run=%3d @y%3d" \
        [expr {([clock milliseconds]-$t0)/1000.0}] \
        $band $pram $lmx $lst $wmx $wst]
    if {$i + 1 < $n} { after $ms }
}
shutdown
