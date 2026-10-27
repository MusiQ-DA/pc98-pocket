# jtag_sd_stage2.tcl -- SuperDepth stage-1 / stage-2 game speed + BGM tempo
# over the JTAG probe, no human play.  Driven by scripts/sd_stage2_check.sh.
#
#   (image already loaded: HDIMG=testdisk/superdepth_tr.hdm ... jtag_hdload.tcl)
#   P=0x07 openocd -f scripts/jtag_probe.cfg -f scripts/jtag_sd_stage2.tcl
#
# superdepth_tr.hdm runs `DEPTH -P810 -H9` and force-clears stage 1 ~36 s
# into play through the game's own Clear path, so one unattended run gives
# stage 1, the Clear transition and stage 2.
#
# Addresses are DEPTH.EXE module offsets; the load base is found at run
# time from the game's IRQ2 (INT 0Ah) vector, whose handler sits at module
# 0xBB42 (np2kai: 2569:BB42), and cross-checked against the IRQ0 (INT 08h)
# vector = module 0xD81A.  DGROUP = base + 0xFD40.
#   [DG:0x1818] stage, [DG:0x0DD2] 56.4 Hz VSYNC tick (monotonic)
#   [DG:0x0DD0] VSYNCs since the last game frame: the main loop (module
#       0x1F81 stage 1, 0x37F5 stage 2) waits for >= [1820h]=5, then
#       `mov word [0DD0h],0` -- AX there = VSYNCs that frame took.
#   [DG:0x1852] BGM tempo word (the ISR derives the PIT reload from it)
#   module 0xD81A: IRQ0 ISR entry (reloads PIT ch0 each tick; BGM tempo).
# Counting uses the slot-6 trigger + the tlog ring (core_top.sv): every
# hit logs {PC, regs} and bumps tlog_n (slot 0x67).  Each window first
# collects game frames (write watchpoint on [0DD0h]), then counts ISR
# entries (fetch-PC trigger on the ISR entry).
# Game speed is judged in wall-clock terms: steady fps = serviced VSYNC
# IRQs per second / mean VSYNCs per steady frame -- a VSYNC IRQ lost while
# interrupts are held off stretches the frame in real time without
# changing the count the game sees.
#
# env: P   slot-9 word (0x07 turbo, 0x05 286 10 MHz; |0x800 = cache off)
#      W   seconds from reset to the START keypress (default 45)
#      T1  stage-1 window seconds, frames and ISR each (default 10)
#      T2  stage-2 window seconds, frames and ISR each (default 15)
#      S2MAX seconds to wait for stage 2 after stage 1 starts (default 150)
# Output: "R key=value" result lines for the wrapper, the rest is log.
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
proc wr {waddr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {((0x80 | $waddr) << 32) | ($data & 0xFFFFFFFF)}] -endstate idle
}
proc rd {a} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {$a << 32}] -endstate idle
    set r [drscan fpga.tap 40 0 -endstate idle]
    scan [string range $r end-7 end] %x v
    return $v
}
proc rdabs {off} {
    wr 8 [expr {($off & 0x1FFFFF) | 0x200000}]
    for {set i 0} {$i < 2000} {incr i} {
        set v [rd 0x9c]
        if {($v >> 31) == 0} { return [expr {$v & 0xff}] }
        after 1
    }
    return -1
}
proc w16 {a} { return [expr {[rdabs $a] | ([rdabs [expr {$a+1}]]<<8)}] }
proc ms {} { return [clock milliseconds] }
proc R {k v} { puts "R $k=$v"; flush stdout }
proc envd {k d} { return [expr {[info exists ::env($k)] ? $::env($k) : $d}] }

set P  [expr {[envd P 0x07]}]
set W  [envd W 45]
set T1 [envd T1 10]
set T2 [envd T2 15]
set S2MAX [envd S2MAX 150]

# Arm the trigger on a linear fetch PC (slot 0x06 {en,..,addr}); clears tlog_n.
# z86's `pc` is the fetch stream's CS:IP, which only lands exactly on an
# address at a redirect (branch target, interrupt entry) -- fine for the
# ISR entry, useless for a straight-line instruction like the main loop's
# `mov [0DD0h],0`.  Game frames are therefore caught with the WRITE
# watchpoint (bits 28+27: bus + write-only, both the chipset strobe and
# z86_cache's port-F commit) on [DG:0DD0h].
proc arm  {pc} { wr 6 [expr {0x80000000 | ($pc & 0xFFFFF)}] }
proc armw {a}  { wr 6 [expr {0x98000000 | ($a & 0xFFFFF)}] }
proc tlog_n {} { return [expr {[rd 0x67] & 0xFFFF}] }
proc tlog_frozen {} { return [expr {([rd 0x67] >> 31) & 1}] }
# {AX, PC[15:0]} of tlog entry i (slot 0x60 low word, slot 0x65 high word)
proc tlog_ent {i} {
    wr 0x0e [expr {$i & 63}]
    return [list [expr {[rd 0x60] & 0xFFFF}] [expr {[rd 0x65] >> 16}]]
}

# Game frames over T seconds.  Every write to [0DD0h] is logged: the VSYNC
# handler's `inc` (fetch PC = handler entry, module 0xBB42) and the main
# loop's per-frame `mov [0DD0h],0`, whose logged AX is the VSYNC count the
# frame waited for (the loop just did `mov ax,[0DD0h] / cmp ax,[1820h]`).
# Harvested from the 64-entry ring every ~0.3 s.
proc frames_window {tag T dg base} {
    set hpc [expr {($base + 0xBB42) & 0xFFFF}]
    set dd0 [w16 [expr {$dg + 0xDD2}]]
    armw [expr {$dg + 0xDD0}]
    set t0 [ms]
    set seen 0
    set vs {}
    set nv 0
    set lost 0
    array unset pcs
    while {1} {
        set done [expr {[ms] - $t0 >= $T*1000}]
        set n [tlog_n]
        if {$done} { set t1 [ms]; set dd1 [w16 [expr {$dg + 0xDD2}]] }
        if {$n - $seen > 56} { incr lost [expr {$n - $seen - 56}]; set seen [expr {$n - 56}] }
        for {} {$seen < $n} {incr seen} {
            lassign [tlog_ent $seen] ax pc
            if {$pc == $hpc} { incr nv } else {
                lappend vs $ax
                if {[info exists pcs($pc)]} { incr pcs($pc) } else { set pcs($pc) 1 }
            }
        }
        if {$done} break
        after 300
    }
    set fr [tlog_frozen]
    set dt [expr {($t1 - $t0) / 1000.0}]
    set vsync [expr {(($dd1 - $dd0) & 0xFFFF) / $dt}]
    # frames = all logged writes minus the VSYNC increments (exact even if
    # the harvest fell behind); steady = frames that left the wait with a
    # plausible count (death / Ready presentations reset [0DD0h] elsewhere
    # or after 30+ VSYNCs)
    set nfr [expr {$n - (($dd1 - $dd0) & 0xFFFF)}]
    set sn 0; set ss 0
    array unset hist
    foreach v $vs {
        if {$v >= 1 && $v <= 15} { incr sn; incr ss $v }
        if {[info exists hist($v)]} { incr hist($v) } else { set hist($v) 1 }
    }
    set mean [expr {$sn ? double($ss) / $sn : 0}]
    set sfps [expr {$mean > 0 ? $vsync / $mean : 0}]
    set h ""; foreach k [lsort -integer [array names hist]] { append h " $k:$hist($k)" }
    set p ""; foreach k [lsort [array names pcs]] { append p [format " %04X:%d" $k $pcs($k)] }
    puts [format "%s frames: %d in %.2f s (%.2f fps raw), VSYNC IRQs serviced %.2f Hz, steady %d x %.3f VSYNC -> %.2f fps, lost=%d frozen=%d" \
          $tag $nfr $dt [expr {$nfr / $dt}] $vsync $sn $mean $sfps $lost $fr]
    puts "$tag VSYNC/frame histogram:$h  (reset sites:$p)"
    R ${tag}_fps [format %.2f [expr {$nfr / $dt}]]
    R ${tag}_vsync_hz [format %.2f $vsync]
    R ${tag}_vpf [format %.3f $mean]
    R ${tag}_steady $sn
    R ${tag}_steady_fps [format %.2f $sfps]
    R ${tag}_frozen $fr
}
proc isr_window {tag pc T} {
    arm $pc
    set t0 [ms]
    after [expr {$T * 1000}]
    set n [tlog_n]
    set t1 [ms]
    set fr [tlog_frozen]
    set dt [expr {($t1 - $t0) / 1000.0}]
    puts [format "%s IRQ0 ISR: %d entries in %.2f s = %.1f Hz frozen=%d" $tag $n $dt [expr {$n / $dt}] $fr]
    R ${tag}_irq0_hz [format %.1f [expr {$n / $dt}]]
}
proc band {tag} {
    set a [rd 0x84]; set b [rd 0x85]; set c [rd 0x86]
    puts [format "%s band: band_cnt=%d pram_cnt=%d last={%d,%d} worst={%d,%d}" $tag \
          [expr {$a >> 16}] [expr {$a & 0xFFFF}] [expr {($b >> 16) & 0x1FF}] [expr {$b & 0x1FF}] \
          [expr {($c >> 16) & 0x1FF}] [expr {$c & 0x1FF}]]
    return [list [expr {$a >> 16}] [expr {$a & 0xFFFF}]]
}

# --- boot -------------------------------------------------------------------
# After a JTAG reflash APF does not re-stream the slots; declare them
# present (core_top slot 0x0c) so the guest leaves reset.
wr 0x0c 1
wr 9 $P; after 20; wr 7 0x05
puts [format "slot9=0x%X reset; START in %d s" $P $W]
after [expr {$W*1000}]
wr 1 0x1C; after 300; wr 1 0x9C

# --- locate DEPTH ---------------------------------------------------------
set base -1
for {set i 0} {$i < 40 && $base < 0} {incr i} {
    set v2 [expr {[w16 0x28] + 16 * [w16 0x2A]}]
    set v0 [expr {[w16 0x20] + 16 * [w16 0x22]}]
    set b [expr {$v2 - 0xBB42}]
    if {$v0 == $b + 0xD81A} { set base $b } else { after 500 }
}
if {$base < 0} {
    puts [format "DEPTH not found (INT0A->%05X INT08->%05X)" $v2 $v0]
    R verdict NOGAME; wr 9 0; shutdown; exit 1
}
set dg [expr {$base + 0xFD40}]
puts [format "DEPTH base=%05X DGROUP=%05X ISR=%05X" $base $dg [expr {$base + 0xD81A}]]
R base [format %05X $base]

proc stage {} { return [w16 [expr {$::dg + 0x1818}]] }
set t0 [ms]
while {[stage] != 1 && [ms] - $t0 < 30000} { after 250 }
if {[stage] != 1} { puts "stage 1 never started (START not taken?)"; R verdict NOSTART; wr 9 0; shutdown; exit 1 }
set ts1 [ms]
puts "stage 1 running"
set b0 [band s1]
after 3000
R s1_tempo [w16 [expr {$dg + 0x1852}]]
frames_window s1 $T1 $dg $base
isr_window s1 [expr {$base + 0xD81A}] $T1

while {[stage] < 2 && [ms] - $ts1 < $S2MAX*1000} { after 250 }
if {[stage] < 2} { puts "stage 2 never reached"; R verdict NOS2; wr 9 0; shutdown; exit 1 }
puts [format "stage 2 after %.1f s of stage 1" [expr {([ms] - $ts1) / 1000.0}]]
after 5000
set b1 [band s2]
set dband [expr {[lindex $b1 0] - [lindex $b0 0]}]
set dpram [expr {[lindex $b1 1] - [lindex $b0 1]}]
if {$dpram == 0 && [lindex $b1 0] == 0 && [lindex $b1 1] == 0} {
    puts "clear transition band: probe not in this build (BAND_PROBE=0) -- unchecked"
    R band n/a
} else {
    puts "clear transition band: +$dband black-band frames, +$dpram mid-frame PRAM frames"
    R band $dband
}
R s2_tempo [w16 [expr {$dg + 0x1852}]]
frames_window s2 $T2 $dg $base
isr_window s2 [expr {$base + 0xD81A}] $T2
R stage_end [stage]
# park the trigger back on the reset vector (its power-up arm) and hand
# the speed back to the OSD
wr 6 [expr {0x80000000 | 0xFFFF0}]
wr 9 0
shutdown
