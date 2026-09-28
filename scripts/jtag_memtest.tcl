# jtag_memtest.tcl -- write/read-verify a pattern in guest RAM via the JTAG
# memory master (probe slot 0x84/0x25; PC98_PROBE_EXTRA builds only).
#
#   MEMADDR=0x60000 MEMLEN=256 PAT=walk \
#     openocd -f scripts/jtag_probe.cfg -f scripts/jtag_memtest.tcl
#
# PAT: walk = (i*37+11)&0xFF, aa55 = alternating, ff00 = halves.
# Prints a diff count and the first few mismatches {addr exp got}.

init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle        ;# arm hub
irscan fpga.tap 0x0e
drscan fpga.tap 5 0x18 -endstate idle      ;# select probe node 1

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
proc memwr {a d} {
    wr 0x84 [expr {0x30000000 | (($d & 0xFF) << 20) | ($a & 0xFFFFF)}]
    for {set t 0} {$t < 400} {incr t} {
        set s [rd 0x25]
        if {$s & 0x8000} { return 1 }
        after 2
    }
    puts "memwr timeout at [format %05x $a]"
    return -1
}

set MEMADDR [expr {[info exists ::env(MEMADDR)] ? $env(MEMADDR) : 0x60000}]
set MEMLEN  [expr {[info exists ::env(MEMLEN)]  ? $env(MEMLEN)  : 256}]
if {[info exists ::env(PAT)]} { set PAT $env(PAT) } else { set PAT walk }

proc pat {i} {
    global PAT
    switch $PAT {
        walk { return [expr {($i * 37 + 11) & 0xFF}] }
        aa55 { return [expr {($i & 1) ? 0x55 : 0xAA}] }
        ff00 { return [expr {($i & 1) ? 0x00 : 0xFF}] }
        inv  { return [expr {~($i & 0xFF) & 0xFF}] }
        default { return [expr {$i & 0xFF}] }
    }
}

for {set i 0} {$i < $MEMLEN} {incr i} {
    memwr [expr {$MEMADDR + $i}] [pat $i]
}
puts "wrote $MEMLEN bytes at [format %05X $MEMADDR]"

set errs 0
for {set i 0} {$i < $MEMLEN} {incr i} {
    set got [memrd [expr {$MEMADDR + $i}]]
    set exp [pat $i]
    if {$got != $exp} {
        if {$errs < 12} {
            puts [format "  DIFF %05x: exp %02x got %02x (xor %02x)" \
                  [expr {$MEMADDR + $i}] $exp $got [expr {$exp ^ $got}]]
        }
        incr errs
    }
}
puts "verify: $MEMLEN bytes, $errs diffs"
shutdown
