# jtag_wildarm.tcl -- arm the run#977 freeze hunt: poll-trap + wild-fetch
# trigger + the tlog register trail.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_wildarm.tcl
#
# Env:
#   POLL=0x317A8   the BGM poll window (default the run#976 address)
#   NOTLOG=1       skip the tlog arming (freeze-through without the
#                  stop-on-wild -- the wild trigger alone freezes the
#                  wedge tap + ring while the machine keeps running, so
#                  the run can also watch the F0 write / device resets
#                  the wild code performs)
#
# What gets armed:
#   wr 0x87 0xC00317A8  slot 0x07 bit31 (poll) + bit30 (wild-fetch) -- the
#                       wild trigger latches ~390ms after the fetch cursor
#                       enters a zone no legal execution lives in (below
#                       0x400, VRAM, the SCSI ROM hole, HLT with IF=0),
#                       freezing slots 0xA0-0xAA + pc_hist + tlog at the
#                       wild instant, BEFORE the guest state is destroyed.
#   wr 0x8E 0x300       slot 0x0e bit9 (tlog_trap: stop the CPU + freeze
#                       the log on the same wild condition) + bit8
#                       (tlog_all: record every fetch-cursor change with
#                       the full register set -- the trail INTO 0:0000).
#
# After a fire, read:
#   0xAA   which latch (bit31 wedge / bit30 poll / bit29 fdq / bit28 wild),
#          [27]=itf_bank, [26]=f0_seen (a port-0xF0 write happened),
#          [25]=z86 halted, [24]=IF (25=1&24=0: unwakeable HLT)
#   0xA7   the frozen fetch cursor (snap_pc) -- where it parked
#   0xA8   71071 request side AT THE FREEZE (layout: [31]ctrl_dis [30]rot
#          [29]sense [28:25]mask [24:21]req [20:17]ff [16:13]lock
#          [12:11]tm3 [10:9]tm2 [8]ai3 [7]ai2)
#   0xA9   FDC execution phase at the freeze
#   0x2F   bridge INTA witness {bad_n, last_bad, cut_n, last_vec}
#   0x69-0x6B  the port-0xF0 write witness (if the wild code reset the box)
#   0x40-0x5F  pc_hist ring (25=bit frozen, [24:20] w, [19:0] pc)
#   0x67/0x60-0x68  tlog count + entries (pc, SS, SP, CS, DS, ES, DI..AX)

if {![info exists ::env(POLL)]} { set poll 0x317A8 } else { set poll $::env(POLL) }

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

proc wr {addr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {(($addr << 32) | $data) & 0xFFFFFFFFFF}] -endstate idle
}

if {![info exists ::env(NOTLOG)] || $::env(NOTLOG) != 1} { wr 0x8e 0x300 }
wr 0x87 [expr {0xC0000000 | ($poll & 0xFFFFF)}]
puts [format "armed: poll window 0x%05x + wild-fetch trigger%s" $poll \
          [expr {[info exists ::env(NOTLOG)] && $::env(NOTLOG) == 1
                 ? " (no tlog)" : " + tlog(stop-on-wild, all-pc)"}]]
shutdown
