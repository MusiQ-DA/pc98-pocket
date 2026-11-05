# jtag_scsiboot.tcl -- read back a SCSI HDD boot of testdisk/hdd_test.* over
# the JTAG probe: the board witness, the BIOS bytes the -55 ROM sets, the
# IPL's result block at 0x40000, and the first three text rows.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_scsiboot.tcl
#   (scripts/jtag_scsiboot.sh wraps this with a verdict)
#
# Read-only: no slot it touches changes guest state (slot 0x88 arms
# fdd_ramimg's readback probe, slot 0x82 seeks the text-cell debug read).
#
# Prints, one per line, the fields the wrapper greps:
#   SCSI_WITNESS media=M ack=A req=R mgrd=N posts=N romreads=N
#   BIOS 482=xx 584=xx 4D2=xx 4B2=xx 4BA=xx geo=xx xx xx xx totals=xxxxxxxx
#   RESULT <48 bytes hex>
#   VERDICT PASS|FAIL|NORESULT
#   ROW0..ROW2 |text|

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
irscan fpga.tap 0x0e
drscan fpga.tap $virw [expr {(1 << 4) | 8}] -endstate idle   ;# probe node 1

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
# byte N of guest RAM (jtag_memrd.tcl's absolute mode)
proc rdabs {off} {
    wr 0x88 [expr {($off & 0x1FFFFF) | 0x200000}]
    for {set i 0} {$i < 2000} {incr i} {
        set v [rd 0x9c]
        if {($v >> 31) == 0} { return [expr {$v & 0xff}] }
        after 1
    }
    return -1
}

# ---- slot 0x30: {media, ack, req, mgmt reads[4:0], posts[7:0], ROM reads[15:0]}
set w [rd 0x30]
puts [format "SCSI_WITNESS media=%d ack=%d req=%d mgrd=%d posts=%d romreads=%d" \
      [expr {($w >> 31) & 1}] [expr {($w >> 30) & 1}] [expr {($w >> 29) & 1}] \
      [expr {($w >> 24) & 0x1F}] [expr {($w >> 16) & 0xFF}] [expr {$w & 0xFFFF}]]

# ---- the BIOS work bytes the ROM owns
set b482 [rdabs 0x482]
set b584 [rdabs 0x584]
set b4d2 [rdabs 0x4D2]
set b4b2 [rdabs 0x4B2]
set b4ba [rdabs 0x4BA]
set geo {}
for {set i 0} {$i < 4} {incr i} { lappend geo [format %02x [rdabs [expr {0x5A0 + $i}]]] }
set tot 0
for {set i 3} {$i >= 0} {incr i -1} { set tot [expr {($tot << 8) | [rdabs [expr {0x5A6 + $i}]]}] }
puts [format "BIOS 482=%02x 584=%02x 4D2=%02x 4B2=%02x 4BA=%02x geo=%s totals=%08x" \
      $b482 $b584 $b4d2 $b4b2 $b4ba [join $geo " "] $tot]

# ---- hdd_test.asm's result block
set res {}
for {set i 0} {$i < 48} {incr i} { lappend res [rdabs [expr {0x40000 + $i}]] }
set hex {}
foreach b $res { lappend hex [format %02x $b] }
puts "RESULT [join $hex { }]"
if {[lindex $res 47] != 0xA5} {
    puts "VERDICT NORESULT"
} elseif {[lindex $res 46] == 0x50} {
    puts "VERDICT PASS"
} else {
    puts "VERDICT FAIL"
}

# ---- text rows 0-2 (jtag_screen.tcl's cell walk)
wr 0x82 0
irscan fpga.tap 0x0c
drscan fpga.tap 40 [expr {0x36 << 32}] -endstate idle
for {set r 0} {$r < 3} {incr r} {
    set line ""
    for {set c 0} {$c < 80} {incr c} {
        set raw [drscan fpga.tap 40 [expr {0x36 << 32}] -endstate idle]
        scan [string range $raw end-5 end] %x v
        set lo [expr {$v & 0xFF}]
        set hi [expr {($v >> 8) & 0xFF}]
        if {$hi != 0} { append line "#" } elseif {$lo >= 0x20 && $lo < 0x7F} {
            append line [format %c $lo] } else { append line " " }
    }
    puts "ROW$r |$line|"
}
shutdown
