# jtag_hdload.tcl -- push a raw .hdm floppy image into the SDRAM carve-out and
# boot it, entirely over JTAG. No SD card, no menu mount, no firmware.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_hdload.tcl
#   env: HDIMG=path/to/img.hdm   (required -- the raw 2HD image,
#                                 77c*8s*2h*1024B = 1261568 bytes)
#        HDNORESET=1             skip the guest reset (mount only)
#        HDNOBOOT=1              upload + verify, no mount and no reset
#        HDCHUNK=bytes           bytes per drscan (default 8192)
#
# Two SLD nodes live in the image:
#   node 1 -- pc98_jtag_probe (the 40-bit {addr,data} register). Write slot
#             0x87 is fdd_ramimg's control word; slot 0x88 arms the byte-offset
#             readback probe; reads 0x35/0x36/0x37 report status.
#   node 2 -- the stream sink: every 32 TDI bits become one 32-bit word in the
#             upload FIFO, which the chipset side writes as four bytes of image
#             into the carve-out. One drscan carries a whole chunk.
#
# Hub select: the USER1 DR is {node_addr, VIR[3:0]}, VIR 8 (bit 3 set per the
# SLD spec). Its width is m_width+4, read back from HUB_INFO[7:0] -- one node
# ships m_width=1 (5-bit select), this build ships two (m_width=2, 6-bit
# select), so the width is computed, not baked.

init

# --- hub discovery + node select -------------------------------------------
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
set nnodes [expr {($hub >> 19) & 0xff}]
set mw     1
while {(1 << $mw) < $nnodes + 1} { incr mw }
puts [format "HUB_INFO=0x%08X  nodes=%d m_width=%d" $hub $nnodes $mw]
if {$nnodes < 2} {
    puts "need two SLD nodes (probe + stream) -- PC98_JTAG build with fdd_ramimg?"
    shutdown; exit 1
}
set virw [expr {$mw + 4}]

proc select_node {n} {
    global virw
    irscan fpga.tap 0x0e
    drscan fpga.tap $virw [expr {($n << 4) | 8}] -endstate idle
}

# --- node 1 (probe): the existing 40-bit {addr,data} register ---------------
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

# control word on slot 0x87: [0]en [1]flush [2]greset [3]remount [4]arm
proc ctl {v} { wr 0x87 [expr {$v & 0xFFFFFFFF}] }
# readback probe: arm slot 0x88 with an image offset, then 0x37 reports
# {pend, 0, off, byte} -- pend clears when the carve-out read landed.
proc rdback {off} {
    wr 0x88 [expr {$off & 0x1FFFFF}]
    for {set i 0} {$i < 2000} {incr i} {
        set v [rd 0x37]
        if {($v >> 31) == 0} { return [expr {$v & 0xff}] }
        after 1
    }
    puts "readback probe stuck"; return -1
}

if {![info exists ::env(HDIMG)]} {
    puts "set HDIMG to the raw .hdm image path"; shutdown; exit 1
}
# jimtcl has no `binary scan`: scripts/hdstream.py pre-packs the image into
# literal drscan lines (env HDSTREAM, or <HDIMG>.stream.tcl). Generate it
# first, e.g. through scripts/jtag_bench.sh.
set HDSTREAM [expr {[info exists ::env(HDSTREAM)] ? $env(HDSTREAM) \
                  : "$env(HDIMG).stream.tcl"}]
set IMGBYTES 1261568

# --- status before we touch anything ---------------------------------------
select_node 1
puts [format "0x35 (ramimg)  = 0x%08X  (tag 52/en/mnt/arm/flush/fsm/lba)" [rd 0x35]]

# --- clear the sink: flush high then low ------------------------------------
ctl 0x02
ctl 0x00
ctl 0x10          ;# arm the stream sink

# --- stream the image on node 2 ---------------------------------------------
# select_node leaves USER1 in the IR -- its DR is the hub's node select, not
# ours. USER0 must be reloaded before the stream scans reach the node.
select_node 2
irscan fpga.tap 0x0c
# The generated file carries the literal drscan lines plus hdimg_nby,
# hdimg_sent and hdimg_spot. Each line is one chunk of 32-bit fields --
# field 0 shifts out first, so word order in the arg list is image order.
source $HDSTREAM
set nby   $hdimg_nby
set sent  $hdimg_sent
puts [format "streamed %d words" $sent]

# --- wait for the drain to catch up -----------------------------------------
# up_off counts bytes actually written to the carve-out; words past the image
# end are dropped without advancing it, so the target is what we sent,
# clamped to the image size.
select_node 1
set drainwant [expr {$sent * 4 > $IMGBYTES ? $IMGBYTES : $sent * 4}]
set off 0
for {set i 0} {$i < 2000} {incr i} {
    set v [rd 0x36]
    set off [expr {$v & 0x1FFFFF}]
    if {$off >= $drainwant} break
    after 5
}
puts [format "drained: up_off=%d (want %d), fifo_used=%d" $off $drainwant \
    [expr {($v >> 21) & 0x1FF}]]
if {$off < $drainwant} { puts "WARNING: image did not finish landing" }

# --- verify: spot-read back through the carve-out ---------------------------
if {![info exists ::env(HDNOVERIFY)]} {
    set bad 0
    foreach {off want} $hdimg_spot {
        set got  [rdback $off]
        if {$got != $want} {
            puts [format "  MISMATCH @%d: got %02x want %02x" $off $got $want]
            incr bad
        }
    }
    puts [expr {$bad ? "verify: $bad mismatches" : "verify: clean"}]
}

if {[info exists ::env(HDNOBOOT)]} { shutdown; exit 0 }

# CPU-speed override (probe write slot 0x89): HDSPEED=0..3 forces
# 5/10/20/max regardless of the OSD setting for scripted runs;
# HDSPEED=clear hands it back.
#
#   env HDIMG=img.hdm HDSPEED=1
if {[info exists ::env(HDSPEED)]} {
    select_node 1
    if {$env(HDSPEED) eq "clear"} {
        wr 0x89 0
        puts "speed override cleared (OSD setting restored)"
    } else {
        wr 0x89 [expr {4 | ($env(HDSPEED) & 3)}]
        puts [format "speed override: clk_select=%d" $env(HDSPEED)]
    }
}

# --- mount + (optionally) reset into a boot ---------------------------------
ctl 0x01          ;# enable -> the mount pass runs
for {set i 0} {$i < 2000} {incr i} {
    set v [rd 0x35]
    if {($v >> 22) & 1} break     ;# mounted
    after 1
}
puts [format "0x35 (ramimg)  = 0x%08X  mounted=%d" $v [expr {($v >> 22) & 1}]]

if {![info exists ::env(HDNORESET)]} {
    ctl 0x05      ;# enable + greset: one pulse into reset_wire, guest boots
    puts "guest reset pulsed -- BIOS should boot drive A"
}
shutdown
exit 0
