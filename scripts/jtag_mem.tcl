# jtag_mem.tcl -- read/write live guest RAM through the JTAG memory master
# (probe write slot 0x84, read slot 0x25; PC98_PROBE_EXTRA builds only).
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_mem.tcl
#   env: MEMADDR (hex start), MEMLEN (bytes), MEMVAL (write byte, optional),
#        MEMFILE (optional: path -> writes file bytes starting at MEMADDR)
#
# Write slot packs {go,we,wdata[7:0],addr[19:0]} into the 32-bit payload;
# read slot 0x25 returns {done(bit15), busy(bit14), rdata[7:0]}.

init

# --- hub select (same dance as jtag_probe_read.tcl) -------------------------
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
if {($hub >> 19) & 0xff} { } else { puts "no SLD nodes"; shutdown; exit 1 }
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

proc memrd {a} {
    wr 0x84 [expr {0x20000000 | ($a & 0xFFFFF)}]
    for {set i 0} {$i < 400} {incr i} {
        set v [rd 0x25]
        if {$v & 0x8000} { return [expr {$v & 0xFF}] }
        after 2
    }
    puts "memrd timeout at [format %05x $a]"
    return -1
}
proc memwr {a d} {
    wr 0x84 [expr {0x30000000 | (($d & 0xFF) << 20) | ($a & 0xFFFFF)}]
    for {set i 0} {$i < 400} {incr i} {
        set v [rd 0x25]
        if {$v & 0x8000} { return 1 }
        after 2
    }
    puts "memwr timeout at [format %05x $a]"
    return -1
}

set MEMADDR [expr {[info exists ::env(MEMADDR)] ? $env(MEMADDR) : 0x1FE00}]
set MEMLEN  [expr {[info exists ::env(MEMLEN)]  ? $env(MEMLEN)  : 128}]

if {[info exists ::env(MEMFILE)]} {
    set fp [open $env(MEMFILE) rb]
    set data [read $fp]
    close $fp
    for {set i 0} {$i < [string length $data]} {incr i} {
        binary scan [string index $data $i] cu b
        memwr [expr {$MEMADDR + $i}] $b
    }
    puts [format "wrote %d bytes at 0x%05X" [string length $data] $MEMADDR]
} elseif {[info exists ::env(MEMVAL)]} {
    memwr $MEMADDR $env(MEMVAL)
    puts [format "wrote 0x%02X at 0x%05X" $env(MEMVAL) $MEMADDR]
} else {
    for {set row 0} {$row < $MEMLEN} {incr row 16} {
        set a [expr {$MEMADDR + $row}]
        set line {}
        for {set i 0} {$i < 16 && $row + $i < $MEMLEN} {incr i} {
            lappend line [format "%02x" [memrd [expr {$a + $i}]]]
        }
        puts [format "%05x: %s" $a [join $line " "]]
    }
}
shutdown
