# jtag_type.tcl -- inject keystrokes into the running PC-98 core over JTAG.
#
# Needs the write-capable probe: a scan whose address byte has bit 7 set is
# a write; slot 0x81 pushes one PC-98 matrix byte (bit 7 = release) onto
# the key line that pc98_kbd8251 drains through ports 0x41/0x43.
#
# Usage:
#   TYPE='PRINT "HI"' openocd -f scripts/jtag_probe.cfg -f scripts/jtag_type.tcl
# or edit the line below. Trailing RETURN is sent unless NONL=1.
#
# PC-98 codes are BY POSITION on the JIS layout (see pc98_kbd_ps2.sv).
# char -> {code, needs_shift}; shift itself is 0x70.

set text [expr {[info exists ::env(TYPE)] ? $::env(TYPE) : "DEF SEG=&HA000"}]
set nonl [expr {[info exists ::env(NONL)] ? $::env(NONL) : 0}]

array set kc {
    " " 0x34  "1" 0x01  "2" 0x02  "3" 0x03  "4" 0x04  "5" 0x05
    "6" 0x06  "7" 0x07  "8" 0x08  "9" 0x09  "0" 0x0A
    "a" 0x1D  "b" 0x2D  "c" 0x2B  "d" 0x1F  "e" 0x12  "f" 0x20
    "g" 0x21  "h" 0x22  "i" 0x17  "j" 0x23  "k" 0x24  "l" 0x25
    "m" 0x2F  "n" 0x2E  "o" 0x18  "p" 0x19  "q" 0x10  "r" 0x13
    "s" 0x1E  "t" 0x14  "u" 0x16  "v" 0x2C  "w" 0x11  "x" 0x2A
    "y" 0x15  "z" 0x29
    "-" 0x0B  "^" 0x0C  ";" 0x26  ":" 0x27  "@" 0x1A  "[" 0x1B
    "]" 0x28  "," 0x30  "." 0x31  "/" 0x32  "\\" 0x0D
    "!" {0x01 1}  "\"" {0x02 1} "#" {0x03 1} "$" {0x04 1} "%" {0x05 1}
    "&" {0x06 1} "'" {0x07 1} "(" {0x08 1} ")" {0x09 1} "=" {0x0C 1}
    "~" {0x0C 1} "*" {0x27 1} "+" {0x26 1} "`" {0x1A 1} "{" {0x1B 1}
    "}" {0x28 1} "<" {0x30 1} ">" {0x31 1} "?" {0x32 1} "_" {0x33 0}
    "|" {0x0D 1}
}
# Uppercase = shift + lowercase
foreach c [split "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ""] {
    set kc($c) [list $kc([string tolower $c]) 1]
}

proc wr {waddr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {((0x80 | $waddr) << 32) | ($data & 0xFFFFFFFF)}] -endstate idle
}
proc key {code} {          ;# one event
    wr 1 $code
    after 80
}
proc tap {code} {          ;# make + break
    key $code
    key [expr {$code | 0x80}]
}
proc tap_shift {code} {
    key 0x70               ;# shift down
    tap $code
    key 0xF0               ;# shift up (0x70 | 0x80)
}

init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle        ;# arm hub (same preamble as probe read)
irscan fpga.tap 0x0e
drscan fpga.tap 5 0x18 -endstate idle      ;# select probe node 1

foreach ch [split $text ""] {
    if {![info exists kc($ch)]} {
        puts "no mapping for '$ch' -- skipped"
        continue
    }
    set spec $kc($ch)
    set code [lindex $spec 0]
    set sh   [expr {[llength $spec] > 1 ? [lindex $spec 1] : 0}]
    if {$sh} { tap_shift $code } else { tap $code }
}
if {!$nonl} { tap 0x1C }                   ;# RETURN
puts "typed: $text"
shutdown
