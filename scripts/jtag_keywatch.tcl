# jtag_keywatch.tcl -- watch the keystroke counter while buttons are pressed.
#
# Probe register 0x1d = {16'h0, key_count, key_last}; key_count increments on
# every pc98_key_stb event and key_last is {make, PC-98 matrix code[6:0]} --
# i.e. AFTER the Set-2 -> PC-98 translation, so it is exactly what the 8251
# hands the guest. Pressing a controller button should bump the count once for
# the make and once for the break.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_keywatch.tcl
#
# Prints a line each time the register changes. Useful readings:
#   count climbs on press AND release -> button -> 8251 path works; look
#     downstream (guest context / BIOS).
#   count stays flat -> the button is being gated (overlay still up, button
#     masked, or Gamepad Mode != Keyboard).

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

proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}

set secs [expr {[info exists ::env(SECS)] ? $::env(SECS) : 60}]
set last -1
set iters [expr {$secs * 20}]              ;# ~50 ms per poll
puts "watching key_count/key_last (reg 0x1d) for ${secs}s -- press buttons"
for {set i 0} {$i < $iters} {incr i} {
    set v [rd 0x1d]
    if {$v != $last} {
        set last $v
        set cnt [expr {($v >> 8) & 0xFF}]
        set mk  [expr {($v >> 7) & 1}]
        set cd  [expr {$v & 0x7F}]
        puts [format "count=%3d  last=%s 0x%02X" $cnt [expr {$mk ? "make" : "brk "}] $cd]
    }
    after 50
}
shutdown
