# jtag_rstwitness.tcl -- the spontaneous-reboot witness: arm, watch, read.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_rstwitness.tcl
#
# Env:
#   READ=1        skip arming, dump the witnesses once and exit
#   POLL_S=2      watch cadence (READ unset only)
#   TIMEOUT_S=0   0 = watch forever (READ unset only); default 0
#   N=16          tlog entries to dump (newest last)
#
# The catch this drives (core_top, tb_rst_witness pins it):
#   * the reset-source witness -- eight sticky bits, one per term that can
#     restart the guest (reset_wire's seven + OUT 0F0h), cleared by
#     wr 0x8A 0x01 after boot so the first bit that lights during a game
#     IS the spontaneous reboot's trigger:
#       [7] OUT 0F0h      (guest code, or the ITF's own POST shutdown)
#       [6] ri_greset     (fdd_ramimg probe pulse; NOTE probe slot 0x07
#                          is shared with the poll-trap arm word -- a
#                          POLL address with bit2 set reboots the machine
#                          by construction, see core_top's witness block)
#       [5] soft_guest_hold (the softcore's settings-apply path)
#       [4] guest_hold_sync2 (boot hold, power-on only)
#       [3] interact_reset  (OSD "Reset & Apply")
#       [2] ~bios_ever_loaded (first-BIOS gate, power-on only)
#       [1] load_active  (APF re-streaming a slot)
#       [0] RESET        (a PLL lost lock -- the one source that also
#                         re-inits the SDRAM and re-maps the ITF bank,
#                         i.e. explains a cold ITF POST on its own)
#   * the reboot freeze -- z86 holds CS:IP=F000:FFF0 through a reset, so
#     the moment any reset path fires, tlog and pc_hist freeze with the
#     pre-reboot trail intact and the FFF0 fetch as the LAST entry (the
#     seam).  The ITF POST that follows records NOTHING: for the first
#     time the 64 branches ending at the seam are the trigger's own
#     footsteps, not the POST tail F9A2A's OUT 0F0h used to leave behind.
#   * a reboot with the witness DARK is not a reset -- the guest walked
#     to FFF0 (wild jump / reset-vector call); the frozen trail names
#     the code instead.  rst_boot_itf (0xAB bit18) says which bank the
#     "reboot" landed in: ITF POST with the bit clear = a guest 043D
#     bank switch, not a cold reset.
#
# Arming writes (after the machine is up and the game loaded):
#   wr 0x88 0x01   wedge taps + the reboot latch re-arm
#   wr 0x8A 0x01   the reset-source witness clear
#   wr 0x85 0x01   pc_hist ring re-arm (slot 5, data ignored)
#   wr 0x86 0x800FFFF0  tlog clear + trigger on the reset vector
#   wr 0x8E 0x300  tlog mode: all-branches + trap
#
# Fire condition while watching: 0xAB bit19 (reboot latch), 0x67 bit31
# (tlog frozen) or any 0xAA latch -- then the dump below reads:
#   0xAB   {rst_seen[31:24], rst_last[23:20], boot_latch[19], boot_itf[18]}
#   0xAC   the tick the named source rose (age vs a second read)
#   0x67   {tlog_frozen[31], tlog_n[15:0]}
#   tlog   entries via wr 0x8E <idx>, read 0x60-0x65 + 0x68:
#          pc = 0x68[3:0]:0x65[15:0], SS=0x65[31:16], SP=0x64[31:16],
#          CS=0x64[15:0], DS=0x63[31:16], ES=0x63[15:0], DI=0x62[31:16],
#          SI=0x62[15:0], DX=0x61[31:16], CX=0x61[15:0], BX=0x60[31:16],
#          AX=0x60[15:0]
#   0x69-0x6B  the port-0xF0 write witness (0xF8xxx = the boot's own)
#   0xAA   {wedge, poll, fdq latch, poll_static}
#
# SPDX-License-Identifier: GPL-3.0-or-later

if {![info exists POLL_S]}    { set POLL_S 2 }
if {![info exists TIMEOUT_S]} { set TIMEOUT_S 0 }
if {![info exists N]}         { set N 16 }

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

set srcname(0) "PLL-unlock (RESET)"
set srcname(1) "load_active (APF slot stream)"
set srcname(2) "~bios_ever_loaded (power-on only)"
set srcname(3) "interact_reset (OSD Reset & Apply)"
set srcname(4) "guest_hold_sync2 (boot hold)"
set srcname(5) "soft_guest_hold (softcore apply path)"
set srcname(6) "ri_greset (fdd_ramimg probe pulse)"
set srcname(7) "OUT 0F0h (CPU-only reset)"

proc decode_sources {v} {
    global srcname
    set out {}
    for {set i = 0} {$i < 8} {incr i} {
        if {($v >> $i) & 1} { lappend out $srcname($i) }
    }
    if {[llength $out] == 0} { return "(dark -- no reset source rose)" }
    return [join $out ", "]
}

proc dump {} {
    global srcname N
    set ab [rd 0xab]
    set seen [expr {($ab >> 24) & 0xFF}]
    set last [expr {($ab >> 20) & 0xF}]
    set boot [expr {($ab >> 19) & 1}]
    set itf  [expr {($ab >> 18) & 1}]
    set tick [rd 0xac]
    puts [format "witness 0xAB=%08X 0xAC=%08X" $ab $tick]
    puts [format "  sources risen : %s" [decode_sources $seen]]
    if {$last & 8} {
        puts [format "  last rise     : idx %d (%s)" \
                  [expr {$last & 7}] $srcname([expr {$last & 7}])]
    } else {
        puts "  last rise     : none since clear"
    }
    puts [format "  reboot latch  : %d (1 = the cursor read FFF0; rings froze there)" $boot]
    puts [format "  bank at reboot: %s" \
              [expr {$boot ? ($itf ? "ITF (cold-POST shape)" : "BIOS (a walk, not a reset)")
                           : "n/a (no reboot caught)"}]]

    set g [rd 0x67]
    set n [expr {$g & 0xFFFF}]
    puts [format "tlog 0x67=%08X frozen=%d entries=%d" $g [expr {$g >> 31}] $n]
    if {$n > 0} {
        set first [expr {$n > $N ? $n - $N : 0}]
        puts "  --- tlog trail, oldest first; the LAST line is the seam ---"
        for {set i $first} {$i < $n} {incr i} {
            wr 0x8e [expr {$i & 0x3F}]
            set pc60 [rd 0x60]; set pc61 [rd 0x61]; set pc62 [rd 0x62]
            set pc63 [rd 0x63]; set pc64 [rd 0x64]; set pc65 [rd 0x65]
            set pc68 [rd 0x68]
            set pc [expr {((($pc68 & 0xF) << 16) | ($pc65 & 0xFFFF)) & 0xFFFFF}]
            puts [format "  [%3d] pc=%05X CS=%04X IP-regs SS=%04X SP=%04X DS=%04X ES=%04X DI=%04X SI=%04X DX=%04X CX=%04X BX=%04X AX=%04X" \
                      [expr {$i - $first}] $pc \
                      [expr {$pc64 & 0xFFFF}] \
                      [expr {$pc65 >> 16}] [expr {$pc64 >> 16}] \
                      [expr {$pc63 >> 16}] [expr {$pc63 & 0xFFFF}] \
                      [expr {$pc62 >> 16}] [expr {$pc62 & 0xFFFF}] \
                      [expr {$pc61 >> 16}] [expr {$pc61 & 0xFFFF}] \
                      [expr {$pc60 >> 16}] [expr {$pc60 & 0xFFFF}]]
        }
    }

    set f0a [rd 0x69]
    puts [format "F0 witness 0x69=%08X (%s)" $f0a \
              [expr {($f0a & 0xF0000) == 0xF8000 ? "the boot's own OUT 0F0h"
                                                  : "a non-ITF F0 writer"}]]
    set aa [rd 0xaa]
    puts [format "taps 0xAA=%08X wedge=%d poll=%d fdq=%d poll_static=0x%X" $aa \
              [expr {($aa >> 31) & 1}] [expr {($aa >> 30) & 1}] \
              [expr {($aa >> 29) & 1}] [expr {$aa & 0xFFFFFF}]]
}

if {[info exists ::env(READ)] && $::env(READ) == 1} {
    dump
    shutdown
    return
}

wr 0x88 0x01
wr 0x8a 0x01
wr 0x85 0x01
wr 0x86 0x800FFFF0
wr 0x8e 0x300
puts "armed: witness clear, taps re-armed, tlog all+trap, pc_hist rolling"
puts "watching for a reboot (0xAB bit19 / 0x67 bit31 / 0xAA latches)..."

set t0 [clock seconds]
while {1} {
    after [expr {$POLL_S * 1000}]
    set ab [rd 0xab]
    set g  [rd 0x67]
    set aa [rd 0xaa]
    if {(($ab >> 19) & 1) || ($g >> 31) || (($aa >> 29) & 7)} {
        puts "*** caught something: dumping ***"
        dump
        shutdown
        return
    }
    if {$TIMEOUT_S > 0 && [clock seconds] - $t0 > $TIMEOUT_S} {
        puts "timeout: nothing fired"
        shutdown
        return
    }
}
