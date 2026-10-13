# jtag_dotcap.tcl -- read the presented picture back, dot by dot, through
# the dot-capture probe (write slot 0x8C, reads 0x42-0x44 in core_top).
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_dotcap.tcl
#   env: DCV="100 200"   raster lines to capture (default 100)
#        DCH0=0 DCH1=640 dot range, captured 32 dots per arm
#
# One row per 32 dots: T = the composite took the text pixel, # = a graphics
# dot that is not black, . = black graphics. A text mask that leaks shows
# as #/. inside a run of T. h is pocket_video's rb_h, the coordinate the
# scaler is handed; calibrate against a known edge (a left text mask ends
# at its 32nd dot) rather than trusting an absolute offset.
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

set vs [expr {[info exists ::env(DCV)]  ? $::env(DCV)  : 100}]
set h0 [expr {[info exists ::env(DCH0)] ? $::env(DCH0) : 0}]
set h1 [expr {[info exists ::env(DCH1)] ? $::env(DCH1) : 640}]
foreach v $vs {
    for {set h $h0} {$h < $h1} {incr h 32} {
        wr 0x0c [expr {($v << 16) | $h}]
        set st 0
        for {set k 0} {$k < 200} {incr k} {
            set st [rd 0x44]
            if {($st >> 31) & 1} break
            after 1
        }
        set t [rd 0x42]
        set n [rd 0x43]
        set s ""
        for {set i 0} {$i < 32} {incr i} {
            if {($t >> $i) & 1}     { append s T } \
            elseif {($n >> $i) & 1} { append s # } \
            else                    { append s . }
        }
        puts [format "v=%3d h=%3d %s rgb@h=%05X%s" $v $h $s \
            [expr {$st & 0x3FFFF}] [expr {(($st >> 31) & 1) ? "" : " (no capture)"}]]
    }
}
shutdown
