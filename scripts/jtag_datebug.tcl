# jtag_datebug.tcl -- the SuperDepth date-byte (0x373A3) triage, in one run.
#
# Arms the WRITE watchpoint (slot 0x06, bits 27+28: chipset-bus AND
# z86_cache port-F taps -- the two cover every master that can write guest
# RAM) on WA (default 0x373A3, the high-score date byte), then WAITS for
# the hit while the game boots. On the hit it dumps:
#   * the frozen z86 register view (slots 0x10-0x16 -- trig_hit latches
#     z86_snap_held, so these read the registers AT the culprit store)
#   * the trigger ring (0x60-0x64, count/frozen in 0x67)
#   * the watched bytes themselves (guest RAM via the fdd_ramimg probe)
#
# The one-scan arm proof: read slot 0x06 back and compare (a bare slot
# number is a READ -- writes need addr bit 7, i.e. 0x86).
#
#   HDIMG=/path/superdepth.hdm openocd -f scripts/jtag_probe.cfg -f scripts/jtag_hdload.tcl
#   WA=0x373A3 BASE=0x373A0 LEN=8 WAIT=60000 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_datebug.tcl
#
# Verdicts (see the report):
#   store fired, data path shows 0x38 ... 0x38 stored, then something ELSE
#       wrote 0xA1 later -- re-run with AFTER=1 to keep watching past the
#       first hit.
#   store fired with AX/DL = A1 .... the game READ a stale byte: read-side;
#       dump the DOS disk buffer band (BASE=0x62C0 LEN=32) right after.
#   no store to 0x373A3 at all . the copy skipped the byte -- stale CODE
#       (fetch path); the tlog ring's last PCs are the copy loop.
init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {$i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
set nnodes [expr {($hub >> 19) & 0xff}]
set mw 1
while {(1 << $mw) < $nnodes + 1} { incr mw }
set virw [expr {$mw + 4}]
irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle

proc wr {addr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {(($addr << 32) | $data) & 0xFFFFFFFFFF}] -endstate idle
}
proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}
proc guestbyte {off} {
    wr 0x88 [expr {0x200000 | ($off & 0x1FFFFF)}]
    while {1} {
        set v [rd 0x9c]
        if {($v & 0x80000000) == 0} { return [expr {$v & 0xFF}] }
    }
}

set wa   0x373A3
set base 0x373A0
set len  8
set waitms 60000
if {[info exists ::env(WA)]}    { set wa [expr $::env(WA)] }
if {[info exists ::env(BASE)]}  { set base [expr $::env(BASE)] }
if {[info exists ::env(LEN)]}   { set len [expr $::env(LEN)] }
if {[info exists ::env(WAIT)]}  { set waitms [expr $::env(WAIT)] }

# {en,freeze,delay,bus,wronly,ds,addr}: en+freeze+bus+wronly
set word [expr {0xB0000000 | ($wa & 0xFFFFF)}]
wr 0x86 $word
set echo [rd 0x06]
if {$echo != $word} {
    puts [format "ARM FAILED: wrote %08x, slot reads %08x" $word $echo]
    shutdown
}
puts [format "armed: watch write %05x (word %08x)" $wa $word]

set t0 [clock milliseconds]
set hit 0
while {[expr {[clock milliseconds] - $t0}] < $waitms} {
    set s67 [rd 0x67]
    if {($s67 & 0xFFFF) != 0} { set hit 1; break }
    after 500
}
if {!$hit} {
    puts "NO HIT within ${waitms} ms -- no write to the watched byte at all"
} else {
    puts [format "HIT after %d ms (tlog_n=%d frozen=%d)" \
              [expr {[clock milliseconds] - $t0}] [expr {[rd 0x67] & 0xFFFF}] \
              [expr {([rd 0x67] >> 31) & 1}]]
    # the frozen register view: psw:pc, sregs, gprs (slots 0x10-0x16)
    puts [format "snap psw:pc = %08x" [rd 0x10]]
    puts [format "snap sregs    = %08x %08x" [rd 0x11] [rd 0x12]]
    puts [format "snap gprs hi  = %08x %08x" [rd 0x13] [rd 0x14]]
    puts [format "snap gprs lo  = %08x %08x" [rd 0x15] [rd 0x16]]
    puts [format "live pc/next  = %08x %08x" [rd 0x18] [rd 0x66]]
    # the ring: last few entries, count is capped at 64. Entry layout,
    # MSB first (see the tlog write): {12'0, pc[19:0], SS, SP, CS, DS, ES,
    # DI, SI, DX, CX, BX, AX}; read slots 0x60-0x65 are words [31:0]..
    # [191:160], 0x68 is [207:192] (the pc's top nibble).
    set n [rd 0x67]
    set n [expr {($n & 0xFFFF) > 64 ? 64 : ($n & 0xFFFF)}]
    set first [expr {$n > 6 ? $n - 6 : 0}]
    for {set i $first} {$i < $n} {incr i} {
        wr 0x8e [expr {$i & 0x3F}]
        set v60 [rd 0x60]; set v61 [rd 0x61]; set v62 [rd 0x62]
        set v63 [rd 0x63]; set v64 [rd 0x64]; set v65 [rd 0x65]
        set v68 [rd 0x68]
        puts [format "tlog[%2d] pc=%05x ss:sp=%04x:%04x cs=%04x ds=%04x es=%04x di=%04x si=%04x dx=%04x cx=%04x bx=%04x ax=%04x" $i \
                  [expr {(($v68 & 0xF) << 16) | (($v65 >> 16) & 0xFFFF)}] \
                  [expr {$v65 & 0xFFFF}] [expr {($v64 >> 16) & 0xFFFF}] \
                  [expr {$v64 & 0xFFFF}] [expr {($v63 >> 16) & 0xFFFF}] \
                  [expr {$v63 & 0xFFFF}] [expr {($v62 >> 16) & 0xFFFF}] \
                  [expr {$v62 & 0xFFFF}] [expr {($v61 >> 16) & 0xFFFF}] \
                  [expr {$v61 & 0xFFFF}] [expr {($v60 >> 16) & 0xFFFF}] \
                  [expr {$v60 & 0xFFFF}]]
    }
}

# the bytes themselves, last look
set line ""
for {set i 0} {$i < $len} {incr i} {
    append line [format "%02X " [guestbyte [expr {$base + $i}]]]
}
puts [format "%06X: %s" $base $line]
shutdown
