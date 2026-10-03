# jtag_faultwatch.tcl -- reboot the guest at a chosen speed, poll slot 0x38
# (zet fault witness: {3'b0, seen, opc, pc}) until a fault lands or TRYSECS
# elapse; then dump every diagnostic slot and the pc-history ring.
#
#   SPD=0 TRIES=6 TRYSECS=240 CAPLOG=/tmp/faultwatch.log \
#       openocd -f scripts/jtag_probe.cfg -f scripts/jtag_faultwatch.tcl

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
proc wr {addr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {(($addr << 32) | $data) & 0xFFFFFFFFFF}] -endstate idle
}

set spd     [expr {[info exists ::env(SPD)]     ? $::env(SPD)     : 0}]
set tries   [expr {[info exists ::env(TRIES)]   ? $::env(TRIES)   : 6}]
set trysecs [expr {[info exists ::env(TRYSECS)] ? $::env(TRYSECS) : 240}]
set logpath [expr {[info exists ::env(CAPLOG)]  ? $::env(CAPLOG)  : "/tmp/faultwatch.log"}]
set fh [open $logpath w]
puts $fh "# faultwatch start [clock format [clock seconds]]  SPD=$spd"
flush $fh

set allslots {0x18 0x19 0x1a 0x1b 0x1c 0x20 0x21 0x22 0x23 0x24 0x25 \
              0x26 0x27 0x28 0x29 0x30 0x31 0x32 0x33 0x34 0x35 0x38}

proc snapshot {tag fh} {
    global allslots
    puts $fh "=== SNAPSHOT $tag @ [expr {[clock milliseconds]/1000.0}]s ==="
    foreach s $allslots {
        set v [rd $s]
        puts $fh [format "  slot %s = %s" $s $v]
    }
    for {set i 0x40} {$i <= 0x5f} {incr i} {
        set v [rd $i]
        puts $fh [format "  ring %02x = %s" $i $v]
    }
    flush $fh
}

for {set t 1} {$t <= $tries} {incr t} {
    # speed override + guest reset
    wr 0x89 [expr {4 | ($spd & 3)}]
    wr 0x87 0x05
    puts $fh "# try $t: speed=$spd reset pulsed"
    flush $fh

    set t0 [clock milliseconds]
    set faulted 0
    while {1} {
        after 400
        set now [clock milliseconds]
        set el [expr {($now - $t0)/1000.0}]
        if {$el > $trysecs} break
        set s38 [rd 0x38]
        scan $s38 %x v
        if {$v & 0x100000} {
            set opc [expr {($v >> 20) & 0xff}]
            set fpc [expr {$v & 0xfffff}]
            puts $fh [format "  t=%6.1fs  FAULT opc=%02x pc=%05x" $el $opc $fpc]
            snapshot "FAULT try=$t" $fh
            set faulted 1
            break
        }
        if {[expr {int($el) % 30}] == 0} {
            set pc [rd 0x18]
            puts $fh [format "  t=%6.1fs  pc=%s (38=%s)" $el $pc $s38]
            flush $fh
            after 1000
        }
    }
    if {$faulted} break
    puts $fh "# try $t survived ${trysecs}s -- rebooting"
    flush $fh
}
puts $fh "# done"
close $fh
shutdown
