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
#     GVFILE=path      write bytes here as continuous hex text
#                      (convert with: xxd -r -p file > file.bin)

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

# Every completed scan answers {addr,data} for one byte and launches the
# next address's read; the walk is strictly +1 per scan but the first
# captures can straddle the seek, so bytes are recorded BY their address
# echo rather than by position.
array set got {}
set scans 0
set maxscans [expr {$len + 64}]
while {[array size got] < $len && $scans < $maxscans} {
    incr scans
    set raw [drscan fpga.tap 40 [expr {0x38 << 32}] -endstate idle]
    scan [string range $raw end-7 end] %x v
    set busy [expr {($v >> 31) & 1}]
    set addr [expr {($v >> 8) & 0xFFFFF}]
    if {$busy || $addr < $base || $addr >= $base+$len} { continue }
    set got($addr) [expr {$v & 0xFF}]
}
# Gap fill: scans whose capture straddled a seek lose a byte. Re-seek to
# (missing-1); the next scan's advance then lands the read on the gap.
set missing {}
for {set i 0} {$i < $len} {incr i} {
    set a [expr {$base + $i}]
    if {![info exists got($a)]} { lappend missing $a }
}
foreach a $missing {
    wr 4 [expr {$a - 1}]
    after 2
    for {set r 0} {$r < 8} {incr r} {
        set raw [drscan fpga.tap 40 [expr {0x38 << 32}] -endstate idle]
        scan [string range $raw end-7 end] %x v
        set busy [expr {($v >> 31) & 1}]
        set addr [expr {($v >> 8) & 0xFFFFF}]
        if {!$busy && $addr == $a} {
            set got($a) [expr {$v & 0xFF}]
            break
        }
    }
}
set bytes {}
for {set i 0} {$i < $len} {incr i} {
    set a [expr {$base + $i}]
    lappend bytes [expr {[info exists got($a)] ? $got($a) : -1}]
}
puts [format "captured %d of %d bytes in %d scans" [array size got] $len $scans]

# --- hex dump ---------------------------------------------------------------
puts [format "---- guest memory %05X..%05X ----" $base [expr {$base+$len-1}]]
for {set i 0} {$i < $len} {incr i 16} {
    set line [format "%05X: " [expr {$base+$i}]]
    for {set j 0} {$j < 16 && $i+$j < $len} {incr j} {
        set b [lindex $bytes [expr {$i+$j}]]
        append line [expr {$b < 0 ? "?? " : ""}]
        if {$b >= 0} { append line [format "%02X " $b] }
    }
    puts $line
}

if {[info exists ::env(GVFILE)]} {
    set f [open $::env(GVFILE) w]
    set hex ""
    foreach b $bytes {
        if {$b < 0} { append hex "00" } else { append hex [format "%02x" $b] }
    }
    puts $f $hex
    close $f
    puts [format "wrote %d bytes as hex to %s (xxd -r -p to decode)" $len $::env(GVFILE)]
}
shutdown
