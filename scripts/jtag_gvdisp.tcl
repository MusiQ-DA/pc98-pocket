# jtag_gvdisp.tcl -- read the graphics display-fetch underrun telemetry
# (probe slots 0x40/0x41) in a loop while a game runs.
#
#   0x40 = {skip_cnt[7:0], late_cnt[7:0], max_fill[15:0]}   -- since reset
#   0x41 = {line_now[8:0], act_tgt[8:0], f_chunk[3:0], f_plane[2:0],
#           cur_part[1:0], dbl, disp_page, disp_on_c, fill_page, f_active}
#
# skip = a line edge wanted a fill but the previous one still ran.
# late = a fill still ran when its own target line displayed.
# max_fill = worst launch->done, in chipset clocks (~1730 per line; the
# launch deadline is LOOKAHEAD=3 lines ~= 5200).
#
# Usage: openocd -f scripts/jtag_gvdisp.tcl    (while the core is running)

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

set t0 [clock milliseconds]
for {set i 0} {$i < 200} {incr i} {
    set lo [rd 0x40]
    set hi [rd 0x41]
    set skip [expr {($lo >> 24) & 0xff}]
    set late [expr {($lo >> 16) & 0xff}]
    set maxf [expr {$lo & 0xffff}]
    set line [expr {($hi >> 23) & 0x1ff}]
    set tgt  [expr {($hi >> 14) & 0x1ff}]
    set chunk [expr {($hi >> 10) & 0xf}]
    set plane [expr {($hi >> 7) & 0x7}]
    set part [expr {($hi >> 5) & 0x3}]
    set dbl  [expr {($hi >> 4) & 1}]
    set dpg  [expr {($hi >> 3) & 1}]
    set don  [expr {($hi >> 2) & 1}]
    set fpg  [expr {($hi >> 1) & 1}]
    set act  [expr {$hi & 1}]
    puts [format "t=%6.1f skip=%3d late=%3d maxfill=%5d | line=%3d tgt=%3d ch/pl/pt=%d/%d/%d dbl=%d dpg=%d don=%d fpg=%d act=%d" \
        [expr {([clock milliseconds]-$t0)/1000.0}] \
        $skip $late $maxf $line $tgt $chunk $plane $part $dbl $dpg $don $fpg $act]
    after 500
}
shutdown
