# jtag_btn.tcl -- press Analogue Pocket controller buttons over JTAG.
#
# Probe write slot 0x83 latches {cont2, cont1} held-button masks that the
# core ORs onto the settled pad words: every consumer (OSD open/dismiss,
# pad->key mapper, mouse mode) sees a set bit as a held button until it
# clears. Buttons are levels, so press=write mask, release=write 0.
#
# Usage:
#   BTN=A openocd -f scripts/jtag_probe.cfg -f scripts/jtag_btn.tcl
#   BTN=UP+A HOLD_MS=300 openocd ...      # chord
#   BTN=START ACTION=press openocd ...    # press and hold
#   ACTION=release openocd ...            # release held buttons
#   PAD=2 ...                             # drive controller 2
#
# APF bits: 0-3 D-pad up/down/left/right, 4-7 A/B/X/Y,
# 8-13 L1/R1/L2/R2/L3/R3, 14=Select, 15=Start.

array set bit {
    up 0 down 1 left 2 right 3
    a 4 b 5 x 6 y 7
    l1 8 r1 9 l2 10 r2 11 l3 12 r3 13
    select 14 start 15
}

proc wr {waddr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {((0x80 | $waddr) << 32) | ($data & 0xFFFFFFFF)}] -endstate idle
}

proc buttons {mask} {
    global PAD
    wr 3 [expr {$PAD == 2 ? ($mask << 16) : $mask}]
}

init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle        ;# arm hub (same preamble as probe read)
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
set virw [expr {($hub & 0xff) + 4}]
irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle  ;# select probe node 1

set PAD     [expr {[info exists ::env(PAD)]     ? $::env(PAD)     : 1}]
set ACTION  [expr {[info exists ::env(ACTION)]  ? $::env(ACTION)  : "tap"}]
set HOLD_MS [expr {[info exists ::env(HOLD_MS)] ? $::env(HOLD_MS) : 120}]

if {$ACTION eq "release"} {
    buttons 0
    puts "released"
} else {
    if {![info exists ::env(BTN)]} { puts "Set BTN=name (+ separated)"; shutdown; exit 1 }
    set mask 0
    foreach name [split $::env(BTN) +] {
        set k [string tolower $name]
        if {![info exists bit($k)]} { puts "Unknown button: $name"; shutdown; exit 1 }
        set mask [expr {$mask | (1 << $bit($k))}]
    }
    buttons $mask
    if {$ACTION eq "press"} {
        puts "held: $::env(BTN) (mask [format 0x%04x $mask])"
    } else {
        after $HOLD_MS
        buttons 0
        puts "pressed: $::env(BTN) (${HOLD_MS}ms)"
    }
}
shutdown
