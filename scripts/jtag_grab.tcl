# jtag_grab.tcl -- dump guest conventional RAM via fdd_ramimg absolute
# readback (slot 0x88 bit21). Requires the image mounted state only for
# the FSM's idle cycles -- reads steal arbiter slots between FDC serves.
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
proc grb {a} {
    wr 0x88 [expr {0x200000 | ($a & 0x1FFFFF)}]
    for {set i 0} {$i < 4000} {incr i} {
        set v [rd 0x9c]
        if {($v >> 31) == 0} { return [expr {$v & 0xff}] }
        after 1
    }
    return -1
}
proc dump {base n {label ""}} {
    if {$label ne ""} { puts "== $label (base [format %05x $base]) ==" }
    for {set i 0} {$i < $n} {incr i 16} {
        set line {}
        for {set j 0} {$j < 16 && $i + $j < $n} {incr j} {
            lappend line [format %02x [grb [expr {$base + $i + $j}]]]
        }
        puts [format "%06x: %s" [expr {$base + $i}] [join $line " "]]
    }
}
# Forensic set: IVT, BIOS work area, cursor var, IPL+stack, IPL vars
dump 0x0000 0x100 {ivt}
dump 0x1FC00 0x40 {ipl at 1fc00}
dump 0x1FE00 0x40 {ipl at 1fe00}
dump 0x0170 0x10  {cursor ptr 0x174}
dump 0x0400 0x200 {bioswork}
dump 0x1E800 0x100 {IPL stack}
dump 0x1FDC0 0x60 {IPL vars}
shutdown
