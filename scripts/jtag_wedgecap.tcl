# jtag_wedgecap.tcl -- poll the bus-address probe (0x18) at high rate and, when
# the guest PC collapses into a stagnant window, dump every diagnostic slot.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_wedgecap.tcl
#   env: CAPSECS=seconds to run (default 300)
#        CAPLOG=log path (default /tmp/wedgecap.log)
#
# Stagnation rule: if the last WIN samples of 0x18 all fall inside a 0x100-byte
# range for at least STAGSECS seconds, treat as a wedge and snapshot all slots.
# (The BIOS/DOS idle loops do revisit small ranges, but only briefly; a wedge
# pins the address for tens of seconds.)

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
if {$nnodes < 1} { puts "no SLD nodes"; shutdown; exit 1 }
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

set capsecs [expr {[info exists ::env(CAPSECS)] ? $::env(CAPSECS) : 300}]
set logpath [expr {[info exists ::env(CAPLOG)] ? $::env(CAPLOG) : "/tmp/wedgecap.log"}]
set fh [open $logpath w]
puts $fh "# wedgecap start [clock format [clock seconds]]"
flush $fh

set allslots {0x18 0x19 0x1a 0x1b 0x1c 0x20 0x21 0x22 0x23 0x24 0x25 \
              0x26 0x27 0x28 0x29 0x30 0x31 0x32 0x33 0x35 0x38}

proc snapshot {tag fh} {
    global allslots
    puts $fh "=== SNAPSHOT $tag @ [expr {[clock milliseconds]/1000.0}]s ==="
    foreach s $allslots {
        set v [rd $s]
        puts $fh [format "  slot %s = %s" $s $v]
    }
    # the pc-history ring (snap if a fault banked it, else the live ring)
    for {set i 0x40} {$i <= 0x5f} {incr i} {
        set v [rd $i]
        puts $fh [format "  ring %02x = %s" $i $v]
    }
    flush $fh
}

set t0 [clock milliseconds]
set WIN 60
set STAGSECS 6
set pcs {}
set dumped 0
set stag_lo -1
set stag_hi -1
set stag_since -1

while {1} {
    set now [clock milliseconds]
    set el [expr {($now - $t0)/1000.0}]
    if {$el > $capsecs} break

    set pc [rd 0x18]
    # every ~10th sample also grab bridge+rst state
    if {[llength $pcs] % 10 == 0} {
        set b [rd 0x1b]
        set c [rd 0x1c]
        puts $fh [format "%7.2f pc=%s 1b=%s 1c=%s" $el $pc $b $c]
    } else {
        puts $fh [format "%7.2f pc=%s" $el $pc]
    }
    flush $fh

    lappend pcs $pc
    if {[llength $pcs] > $WIN} { set pcs [lrange $pcs 1 end] }

    # stagnation check over the window
    set lo 0xffffff
    set hi 0
    foreach p $pcs {
        scan $p %x pv
        if {$pv < $lo} {set lo $pv}
        if {$pv > $hi} {set hi $pv}
    }
    if {[llength $pcs] == $WIN && ($hi - $lo) < 0x100} {
        if {$stag_since < 0} { set stag_since $now }
        if {!$dumped && ($now - $stag_since) > $STAGSECS*1000} {
            snapshot "STAG lo=[format %x $lo] hi=[format %x $hi]" $fh
            set dumped 1
        }
    } else {
        set stag_since -1
        set dumped 0
    }
    after 20
}

snapshot "FINAL" $fh
puts $fh "# done"
close $fh
shutdown
