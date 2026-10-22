# jtag_wildarm.tcl -- arm the run#977 freeze hunt: poll-trap + the tlog
# wild catch (stop-on-wild).
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_wildarm.tcl
#
# Env:
#   POLL=0x317A8   the BGM poll window (default the run#976 address)
#   NOTRAP=1       skip the tlog arming (poll window only)
#
# What gets armed:
#   wr 0x87 0x80317A8  slot 0x07 bit31 -- the poll-trap window (shipped
#                      0f87752 logic): the fetch cursor dwelling inside
#                      the 32-byte window for ~390 ms freezes the wedge
#                      tap (slots 0xA0-0xA9) + pc_hist + tlog.
#   wr 0x8E 0x300      slot 0x0e bit9 (tlog_trap: the FIRST fetch cursor
#                      value in a wild zone -- below 0x400, VRAM, the
#                      SCSI ROM hole, HLT with IF=0 -- stops the CPU via
#                      jtag_dbg_stop and freezes tlog + the pc_hist ring
#                      on the spot) + bit8 (tlog_all: record every
#                      fetch-cursor change with the full register set --
#                      the trail INTO 0:0000). This is the wild catch:
#                      with the CPU parked, the live slots ARE the
#                      snapshot. (A hardware wild_latch freeze-without-
#                      stop existed for two commits and retired -- CI's
#                      Quartus kept internal-erroring on it; tlog_trap
#                      provides the same catch with shipped logic.)
#
# After a fire, read:
#   0x18   live fetch cursor (0 if the trap stopped it mid-wild)
#   0x67   tlog count + frozen flag; entries via wr 0x8F index,
#          read 0x60-0x65/0x68: {pc, SS, SP, CS, DS, ES, DI..AX} --
#          the entries just before CS:IP collapses to 0000:00xx name the
#          path (game code -> wild = vector/IVT corruption; bad INTA ->
#          check 0x2F; SP wandering -> stack/IRET bug)
#   0x40-0x5F  pc_hist ring (bit25 frozen, [24:20] w, [19:0] pc)
#   0x2F   bridge INTA witness {bad_n, last_bad, cut_n, last_vec}
#   0x69-0x6B  the port-0xF0 write witness (0x0000x = the wild code
#          wrote the reset port; 0xF8xxx = the boot's own F0 write)
#   0x90   entry_branch milestones ([31:24]; itf_bank/f0_seen used to
#          mis-live here -- truncated off the metal by an over-wide
#          concat; f0_seen is readable as f0w activity instead)
#   0xA8   71071 request side (AS-BUILT layout -- the documented repack
#          S2T-crashed CI and reverted; tb_71071_dbgmask pins this):
#          [25]ctrl_dis [24]rot [23]sense [22:19]mask [18:15]req
#          [20:17→no] ff=[14:11] lock=[10:7] [31]tm3[0] [30:29]tm2
#          [28]ai3 [27]ai2 ([26]/[6:0] read 0; tm3[1] eaten by truncation)
#   0xA9   FDC execution phase at the freeze

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

wr 0x87 [expr {0x80000000 | ($poll & 0xFFFFF)}]
if {![info exists ::env(NOTRAP)] || $::env(NOTRAP) != 1} { wr 0x8e 0x300 }
puts [format "armed: poll window 0x%05x%s" $poll \
          [expr {[info exists ::env(NOTRAP)] && $::env(NOTRAP) == 1
                 ? "" : " + tlog(stop-on-wild, all-pc)"}]]
shutdown
