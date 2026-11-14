# jtag_sd_clearscroll.tcl -- log the SuperDepth "Clear!" scroll as the
# hardware's display walk sees it, for the stage-transition black band.
#
#   HDIMG=testdisk/superdepth_tr.hdm HDSPEED=3 \
#       openocd -f scripts/jtag_probe.cfg -f scripts/jtag_hdload.tcl
#   W=45 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_sd_clearscroll.tcl > log
#   python3 scripts/sd_clearscroll.py log
#
# The transition (DEPTH 0x2E7A5..0x2E81E) calls 0x30B20 once per frame:
# GDC SCROLL 0x70 rewrites PRAM {SAD0=bx*40, LEN0=400-bx, SAD1=0, LEN1=bx},
# bx 399 -> 127 in steps of 4 (68 frames), each write landing mid-frame
# (after the step's GRCG box fills, before the port-0x60 VSYNC wait).
# superdepth_tr.hdm forces it ~36-76 s into stage 1 by itself.
#
# Without a dot probe in the image, the evidence is the walk itself:
# slot 0x83 {line_now, cur_part, disp_page, ...} sampled back to back,
# with the live PRAM (0x3a {SAD0,LEN0}, 0x3c {LEN3,LEN2,LEN1}) interleaved.
# The picture of a frame follows from where cur_part flips 0->1 against
# that frame's SAD0 -- sd_clearscroll.py does the reconstruction.
#
# env: W=<s> seconds from now to the START press (0 = game already running,
#      no keypress), T=<s> max wait for the scroll (default 120),
#      CAL=<n> calibration samples of 0x83 before the wait (default 400).
# Output lines: "S <t_us> <addr> <hex>" raw samples, "# ..." comments.
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
set T0 [clock microseconds]
proc S {a} {
    set v [rd $a]
    puts [format "S %d %02X %08X" [expr {[clock microseconds] - $::T0}] $a $v]
    return $v
}
set W   [expr {[info exists ::env(W)]   ? $::env(W)   : 0}]
set T   [expr {[info exists ::env(T)]   ? $::env(T)   : 120}]
set CAL [expr {[info exists ::env(CAL)] ? $::env(CAL) : 400}]

if {$W > 0} {
    after [expr {$W * 1000}]
    wr 1 0x1C; after 300; wr 1 0x9C
    puts "# START pressed"
    after 3000
}
foreach a {0x18 0x39 0x3a 0x3b 0x3c 0x82} { S $a }

# calibration: the walk on ordinary gameplay frames (SAD0=0, one area)
puts "# CAL"
for {set i 0} {$i < $CAL} {incr i} {
    S 0x83
    if {($i & 7) == 0} { S 0x3a }
}

# wait for the scroll: SAD0 leaves 0
puts "# WAIT"
set t_end [expr {[clock milliseconds] + $T * 1000}]
set hit 0
set k 0
while {[clock milliseconds] < $t_end} {
    set v [rd 0x3a]
    if {(($v >> 10) & 0xFFFF) != 0} { set hit 1; break }
    if {(([incr k]) & 255) == 0} { S 0x18 }
}
if {!$hit} {
    puts "# no scroll within $T s"
    foreach a {0x18 0x3a 0x82} { S $a }
    shutdown
}
puts "# CAPTURE"
S 0x82
# 0x83 every iteration, PRAM every other one, PC every 16th; stop 1.5 s
# after SAD0 has gone back to 0 (end of the scroll), or after 10 s.
set zero_since 0
set cap_end [expr {[clock milliseconds] + 10000}]
set i 0
while {[clock milliseconds] < $cap_end} {
    S 0x83
    if {($i & 1) == 0} {
        set v [S 0x3a]
        if {(($v >> 10) & 0xFFFF) == 0} {
            if {$zero_since == 0} { set zero_since [clock milliseconds] }
            if {[clock milliseconds] - $zero_since > 1500} break
        } else { set zero_since 0 }
    } else { S 0x3c }
    if {($i & 15) == 15} { S 0x18 }
    incr i
}
puts "# END"
foreach a {0x82 0x39 0x3b 0x18} { S $a }
shutdown
