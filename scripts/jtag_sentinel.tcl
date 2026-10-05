# jtag_sentinel.tcl -- pulse guest reset, then poll guest RAM 0x70000 for the
# 0xAA sentinel written by DONE.COM (AUTOEXEC tail). Reports elapsed time to
# sentinel plus the RAM drop-witness counters.
# Env: SENWAIT ms timeout (default 300000).

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
proc rb {off} {
    wr 0x88 [expr {($off & 0x1FFFFF) | 0x200000}]
    for {set j 0} {$j < 2000} {incr j} {
        set v [rd 0x37]
        if {($v >> 31) == 0} { return [expr {$v & 0xff}] }
        after 1
    }
    return -1
}

# clear the sentinel bytes (slot 0x84 selftest master: go|we|data|addr)
proc wmem {addr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {((0x80 | 4) << 32) | (1<<29) | (1<<28) | (($data & 0xFF) << 20) | ($addr & 0xFFFFF)}] -endstate idle
    after 2
    for {set i 0} {$i < 200} {incr i} {
        if {[rd 0x25] & 0x4000} break      ;# wait for busy to assert
    }
    for {set i 0} {$i < 400} {incr i} {
        if {!([rd 0x25] & 0x4000)} { return }   ;# then for it to clear
    }
    puts "wmem timeout"
}
if {[info exists ::env(SENSPD)]} {
    wr 0x89 [expr {4 | ($env(SENSPD) & 3)}]
    puts [format "speed override clk_select=%d" [expr {$env(SENSPD) & 3}]]
}
wr 0x87 0x01    ;# clear greset first so the next write makes a clean edge
after 20
wr 0x87 0x05
# While the guest is in early reset/POST the bus is idle and HOLD grants
# easily -- clear the magic area now; POST itself only writes uniform
# patterns (00/FF/AA/55), never DEAD/BEEF.
foreach a {0x70010 0x70011 0x70012 0x70013} {
    for {set t 0} {$t < 6} {incr t} {
        wmem $a 0x00
        if {[rb $a] == 0x00} break
    }
}
puts [format "post-reset magic: %02x %02x %02x %02x" \
      [rb 0x70010] [rb 0x70011] [rb 0x70012] [rb 0x70013]]
set t0 [clock milliseconds]
puts "reset pulsed, watching magics 0x70010=DEAD (bench start) / 0x70012=BEEF (done)"

set limit [expr {[info exists ::env(SENWAIT)] ? $env(SENWAIT) : 300000}]
set tmark -1
set tdone -1
while {[clock milliseconds] - $t0 < $limit} {
    if {$tmark < 0 && [rb 0x70010] == 0xAD && [rb 0x70011] == 0xDE} {
        set tmark [expr {[clock milliseconds] - $t0}]
        puts [format "MARKER hit at %dms (boot+autoexec done)" $tmark]
    }
    if {[rb 0x70012] == 0xEF && [rb 0x70013] == 0xBE} {
        set tdone [expr {[clock milliseconds] - $t0}]
        break
    }
    after 500
}
set v39 [rd 0x39]; set v3a [rd 0x3a]
puts [format "sentinel=%s bench=%dms total=%dms  lost=%d blocked=%d parks=%d firstlost=%05x st=%d" \
      [expr {$tdone >= 0 ? "HIT" : "TIMEOUT"}] \
      [expr {$tmark >= 0 && $tdone >= 0 ? $tdone - $tmark : -1}] $tdone \
      [expr {$v39 & 0xff}] [expr {($v3a >> 16) & 0xff}] [expr {$v3a & 0xffff}] \
      [expr {($v39>>8)&0xfffff}] [expr {($v39>>29)&7}]]
shutdown
