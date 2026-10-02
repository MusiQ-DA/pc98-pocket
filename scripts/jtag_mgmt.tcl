# jtag_mgmt.tcl -- direct JTAG->CHIPSET management-bus writes (probe write
# slot 0x86) plus the bus witness on read slot 0x27. PC98_PROBE_EXTRA only.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_mgmt.tcl
#
#   env:
#     MGADDR=0xF2DD MGDATA=0xXXXX   one write: {addr,data} -> 0x86
#     MGFILE=path                   stream each byte to MGADDR (FIFO = 0xF20F)
#     MGWATCH=n                     print slot 0x27 n times, 100 ms apart
#     MGSECT=path SECTOFF=n MGLEN=n wait for fdd_request (0x27 bits 5:4) to
#                                 deassert then assert, push MGLEN bytes of
#                                 the file starting at SECTOFF into 0xF20F
#
# Address encoding: {8'hF2, drive, 3'b000, reg[3:0]} -- F2 = floppy target,
# bit 7 the drive, reg 0 present / 2 cyls / 3 spt / 4 total / 5 heads /
# 6 sector-size / F fifo push.
#
# Slot 0x27 readback is {wr_seen[31:24], last_addr[23:8], 0,0,
# fdd_request[7:6], 0,0, fdd_present[1:0]}.

init

irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
if {($hub >> 19) & 0xff} { } else { puts "no SLD nodes"; shutdown; exit 1 }
set virw [expr {($hub & 0xff) + 4}]
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
proc mgmt {addr data} { wr 0x86 [expr {($addr << 16) | ($data & 0xFFFF)}] }
proc show27 {{tag ""}} {
    set v [rd 0x27]
    puts [format "0x27 %s= %08X  wr_seen=%d last=%04X req=%d%d present=%02d" \
        $tag $v [expr {($v >> 24) & 0xFF}] [expr {($v >> 8) & 0xFFFF}] \
        [expr {($v >> 5) & 1}] [expr {($v >> 4) & 1}] [expr {$v & 3}]]
    return $v
}

show27 before

if {[info exists ::env(MGWATCH)]} {
    for {set i 0} {$i < $env(MGWATCH)} {incr i} {
        after 100
        show27 $i
    }
    shutdown; exit 0
}

# MGMOUNT: run fdd_mount()'s own write sequence for a 2HD image (77 cyl,
# 8 spt, 2 heads, 1024 B -- is_1024=1) on drive $FDDRV (default 0). An eject
# is just "MGADDR=0xF200 MGDATA=0" (present clear).
if {[info exists ::env(MGMOUNT)]} {
    set drv [expr {[info exists ::env(FDDRV)] ? ($env(FDDRV) & 1) : 0}]
    set base [expr {0xF200 | ($drv << 7)}]
    mgmt [expr {$base | 0}] 0      ;# present clear -- media change edge
    mgmt [expr {$base | 2}] 77     ;# cylinders
    mgmt [expr {$base | 3}] 8      ;# sectors/track
    mgmt [expr {$base | 4}] 1232   ;# total sectors
    mgmt [expr {$base | 5}] 2      ;# heads
    mgmt [expr {$base | 6}] 1      ;# sector size: 512<<1 = 1024
    mgmt [expr {$base | 1}] 0      ;# writable
    mgmt [expr {$base | 0}] 1      ;# present
    show27 mounted
    shutdown; exit 0
}

# MGSECT: pump one sector's bytes while the FDC data-request is up. The stub
# resets the controller on entry, so first wait for the request to drop (the
# old pending read dies) and then for a fresh assert.
if {[info exists ::env(MGSECT)]} {
    # Jim Tcl has no `binary`; read a whitespace-separated hex text file:
    #   od -An -v -t x1 img | tr -s ' ' '\n' | tr '\n' ' ' > img.hex
    set fh [open $env(MGSECT) r]
    set txt [read $fh]
    close $fh
    set vals {}
    foreach tok [split $txt] { if {$tok eq ""} continue; scan $tok %x v; lappend vals $v }
    set off [expr {[info exists ::env(SECTOFF)] ? $env(SECTOFF) : 0}]
    set len [expr {[info exists ::env(MGLEN)] ? $env(MGLEN) : 1024}]
    set base [expr {0xF20F | ([info exists ::env(FDDRV)] ? ($env(FDDRV) & 1) << 7 : 0)}]

    if {![info exists ::env(MGNOWAIT)]} {
        for {set i 0} {$i < 4000} {incr i} {
            if {[expr {([rd 0x27] >> 4) & 3}] == 0} break
        }
        puts "req low after $i polls"
        for {set i 0} {$i < 4000} {incr i} {
            if {[expr {([rd 0x27] >> 4) & 3}] != 0} break
        }
        puts "req high after $i polls"
    }

    set n 0
    for {set i $off} {$i < $off + $len} {incr i} {
        mgmt $base [lindex $vals $i]
        incr n
        if {($n % 128) == 0} { show27 "push$n" }
    }
    show27 "push-done($n)"
    shutdown; exit 0
}

if {[info exists ::env(MGFILE)]} {
    set fh [open $env(MGFILE) rb]
    set bytes [read $fh]
    close $fh
    set addr [expr {[info exists ::env(MGADDR)] ? $env(MGADDR) : 0xF20F}]
    binary scan $bytes cu* vals
    set n 0
    foreach b $vals {
        mgmt $addr $b
        incr n
        if {($n % 64) == 0} { show27 "push$n" }
    }
    show27 "push-done($n)"
    shutdown; exit 0
}

if {[info exists ::env(MGADDR)] && [info exists ::env(MGDATA)]} {
    mgmt $env(MGADDR) $env(MGDATA)
    show27 after
    shutdown; exit 0
}

puts "nothing to do -- set MGADDR+MGDATA, MGFILE, or MGWATCH"
shutdown
exit 0
