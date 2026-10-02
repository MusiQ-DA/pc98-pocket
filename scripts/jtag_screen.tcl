# jtag_screen.tcl -- dump the PC-98 text screen through the JTAG probe.
#
# Probe write slot 0x82 sets the debug cell; every completed read of slot
# 0x1B returns {attr,hi,lo} for the current cell and steps it, so the whole
# 80x25 screen is one 40-bit scan per cell.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_screen.tcl
#
# Prints the text plane as characters (ASCII glyphs decode directly; kanji
# cells show as '#'), then a second grid of attribute bytes, then the GDC
# display-start word from register 0x0C for scroll mapping.

init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle        ;# arm hub
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
drscan fpga.tap $virw 0x18 -endstate idle  ;# select probe node 1

proc wr {waddr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {((0x80 | $waddr) << 32) | ($data & 0xFFFFFFFF)}] -endstate idle
}
proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}

# --- SAD (display start) first, for scroll mapping ---------------------------
set sadword [rd 0x0c]
puts [format "GDC 0x0C = 0x%08X (SAD in low bits)" $sadword]

# --- seek cell 0, prime the auto-advance slot --------------------------------
wr 2 0
irscan fpga.tap 0x0c
# The first scan at 0x1B only primes the address (its TDO carried the slot
# read before it); every scan after it returns one cell and auto-steps.
drscan fpga.tap 40 [expr {0x1B << 32}] -endstate idle   ;# prime addr_q=0x1B

set cells {}
for {set c 0} {$c < 2000} {incr c} {
    set raw [drscan fpga.tap 40 [expr {0x1B << 32}] -endstate idle]
    scan [string range $raw end-5 end] %x v
    lappend cells $v                        ;# {attr,hi,lo} packed in 24 bits
}

proc asci {lo hi} {
    if {$hi != 0} { return "#" }
    if {$lo >= 0x20 && $lo < 0x7F} { return [format %c $lo] }
    return " "
}

puts "---- text plane (80x25, linear TVRAM order) ----"
for {set r 0} {$r < 25} {incr r} {
    set line ""
    for {set col 0} {$col < 80} {incr col} {
        set v [lindex $cells [expr {$r*80 + $col}]]
        append line [asci [expr {$v & 0xFF}] [expr {($v >> 8) & 0xFF}]]
    }
    puts "|$line|"
}

puts "---- attributes (hex, same cell order) ----"
for {set r 0} {$r < 25} {incr r} {
    set line ""
    for {set col 0} {$col < 80} {incr col} {
        set v [lindex $cells [expr {$r*80 + $col}]]
        append line [format "%02X " [expr {($v >> 16) & 0xFF}]]
    }
    puts $line
}
shutdown
