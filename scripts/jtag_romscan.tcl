# jtag_romscan.tcl -- scan the guest BIOS window and diff against the
# reference image, to catch per-boot load corruption.
#
#   MEMADDR=0xF8000 MEMLEN=4096 REF=dist/pc98/Assets/pc98/hiroya.PC9801/bios.rom REFOFF=0x10000 \
#     openocd -f scripts/jtag_probe.cfg -f scripts/jtag_romscan.tcl
#
# Prints each diff {addr got ref xor} and a summary count.
# NOTE: reads the guest-visible view -- bios_shadow_flag decides which bank
# F8000-FFFFF is. Verify the flag state before comparing against bios.rom.

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
proc memrd {a} {
    wr 0x84 [expr {0x20000000 | ($a & 0xFFFFF)}]
    for {set t 0} {$t < 400} {incr t} {
        set s [rd 0x25]
        if {$s & 0x8000} { return [expr {$s & 0xFF}] }
        after 2
    }
    puts "memrd timeout at [format %05x $a]"
    return -1
}

set MEMADDR [expr {[info exists ::env(MEMADDR)] ? $env(MEMADDR) : 0xF8000}]
set MEMLEN  [expr {[info exists ::env(MEMLEN)]  ? $env(MEMLEN)  : 4096}]
set REFOFF  [expr {[info exists ::env(REFOFF)]  ? $env(REFOFF)  : 0x10000}]
if {[info exists ::env(REF)]} { set REF $env(REF) } else { set REF dist/pc98/Assets/pc98/hiroya.PC9801/bios.rom }

set fp [open $REF rb]
fconfigure $fp -translation binary
seek $fp $REFOFF
set refdata [read $fp $MEMLEN]
close $fp

set errs 0
for {set i 0} {$i < $MEMLEN} {incr i} {
    set got [memrd [expr {$MEMADDR + $i}]]
    scan [string index $refdata $i] %c rc
    set exp [expr {$rc & 0xFF}]
    if {$got != $exp} {
        puts [format "  DIFF %05x: got %02x ref %02x (xor %02x)" \
              [expr {$MEMADDR + $i}] $got $exp [expr {($exp ^ $got) & 0xFF}]]
        incr errs
    }
}
puts "romscan: $MEMLEN bytes at [format %05X $MEMADDR], $errs diffs"
shutdown
