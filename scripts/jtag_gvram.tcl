# jtag_gvram.tcl -- read guest memory/VRAM through the JTAG probe.
#
# Probe write slot 0x84 launches a byte read of a guest address on the
# GVRAM sequencer's service channel; every completed read of slot 0x38
# returns {busy, addr, data} and launches the next address, so a range
# dumps at one 40-bit scan per byte.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_gvram.tcl
#
#   env:
#     GVADDR=0xA8000   first guest byte address (default A8000 = plane B)
#     GVLEN=640        bytes to dump (default 640 = one row pair)
#     GVFILE=path      write raw bytes here too

init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle        ;# arm hub
irscan fpga.tap 0x0e
drscan fpga.tap 5 0x18 -endstate idle      ;# select probe node 1

proc wr {waddr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {((0x80 | $waddr) << 32) | ($data & 0xFFFFFFFF)}] -endstate idle
}

if {![info exists ::env(GVADDR)]} { set ::env(GVADDR) 0xA8000 }
if {![info exists ::env(GVLEN)]}  { set ::env(GVLEN) 640 }

set base [expr {$::env(GVADDR)}]
set len  [expr {$::env(GVLEN)}]

# --- launch the first read, prime the auto-advance slot ----------------------
wr 4 $base
after 5                                       ;# let the service read land
irscan fpga.tap 0x0c
drscan fpga.tap 40 [expr {0x38 << 32}] -endstate idle   ;# prime addr_q=0x38

set bytes {}
set cur $base
for {set i 0} {$i < $len} {incr i} {
    set raw [drscan fpga.tap 40 [expr {0x38 << 32}] -endstate idle]
    scan [string range $raw end-7 end] %x v
    set busy [expr {($v >> 28) & 1}]
    set addr [expr {($v >> 8) & 0xFFFFF}]
    set data [expr {$v & 0xFF}]
    if {$busy || $addr != $cur} {
        # The service read had not landed when this scan captured -- take
        # one more scan without advancing expectations.
        puts [format "  retry addr %05x (busy=%d addr=%05x)" $cur $busy $addr]
        incr i -1
        continue
    }
    lappend bytes $data
    incr cur
}

# --- hex dump ---------------------------------------------------------------
puts [format "---- guest memory %05X..%05X ----" $base [expr {$base+$len-1}]]
for {set i 0} {$i < $len} {incr i 16} {
    set line [format "%05X: " [expr {$base+$i}]]
    for {set j 0} {$j < 16 && $i+$j < $len} {incr j} {
        append line [format "%02X " [lindex $bytes [expr {$i+$j}]]]
    }
    puts $line
}

if {[info exists ::env(GVFILE)]} {
    set f [open $::env(GVFILE) w]
    fconfigure $f -translation binary
    puts -nonewline $f [binary format c* $bytes]
    close $f
    puts [format "wrote %d bytes to %s" $len $::env(GVFILE)]
}
shutdown
