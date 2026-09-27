# jtag_fdd.tcl -- floppy mount/unmount over JTAG (write slot 0x85, read slot
# 0x26; PC98_PROBE_EXTRA builds only).
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_fdd.tcl
#   env: FDCMD = eject|insert|mount|unbind|stat   FDDRV = 0|1
#
# The command word is {seq[15:8], drive[5:4], cmd[3:0]}; the firmware runs a
# command once per new seq and answers through FDD_JTSTAT, which slot 0x26
# reads back as {sectors[11:0], ok, inserted, seq, drive, cmd}. "mount" only
# binds whatever image the host dataslot already holds -- JTAG cannot supply
# the file itself -- and "unbind" forgets it until the next host rebind.

init

# --- hub select (same dance as jtag_mem.tcl) --------------------------------
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
if {($hub >> 19) & 0xff} { } else { puts "no SLD nodes"; shutdown; exit 1 }
irscan fpga.tap 0x0e
drscan fpga.tap 5 0x18 -endstate idle

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

set cmdmap {eject 1 insert 2 mount 3 unbind 4 stat 5}
set FDCMD [expr {[info exists ::env(FDCMD)] ? $env(FDCMD) : "stat"}]
set FDDRV [expr {[info exists ::env(FDDRV)] ? $env(FDDRV) : 0}]
if {![dict exists $cmdmap $FDCMD]} {
    puts "FDCMD must be one of: [dict keys $cmdmap]"
    shutdown; exit 1
}
set cmd [dict get $cmdmap $FDCMD]

# seq just needs to differ from the firmware's last-seen value, which starts
# at 0 -- bumping it each invocation is enough within one openocd session,
# and the time seed keeps it fresh across restarts.
set seq [expr {[clock seconds] % 255 + 1}]
wr 0x85 [expr {($seq << 8) | (($FDDRV & 3) << 4) | $cmd}]

set ok 0
for {set i 0} {$i < 400} {incr i} {
    set v [rd 0x26]
    if {($v >> 8) & 0xFF == $seq} { set ok 1; break }
    after 5
}
if {!$ok} { puts "fdd: no ack (seq $seq never echoed -- EXTRA build? firmware up?)"; shutdown; exit 1 }

puts [format "fdd drv%d %s: ok=%d inserted=%d sectors=%d" \
    $FDDRV $FDCMD [expr {($v >> 17) & 1}] [expr {($v >> 16) & 1}] \
    [expr {($v >> 20) & 0xFFF}]]
shutdown
exit 0
