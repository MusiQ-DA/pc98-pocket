# jtag_wedgehunt.tcl -- the wedge tap: run the machine until the frozen
# post-mortem latches, then decode it.
#
# The core detects the wedge itself (retired_cnt static for ~390 ms while
# the CPU runs unpause/unreset/unstopped) and FREEZES the whole memory
# path's state into probe slots 0xA0-0xA7 -- the machine may walk into its
# reset loop afterwards, the snapshot does not move until write slot 0x08
# clears it.
#
# Usage:
#   openocd -f scripts/jtag_probe.cfg -c "set HDIMG .../superdepth_tr.hdm" \
#           -f scripts/jtag_hdload.tcl          (image + reboot, as usual)
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_wedgehunt.tcl
# Env:
#   TIMEOUT_S  give up polling after this many seconds (default 240)
#   UNSTICK=1  after the snapshot: pulse the RAM.sv escape hatch
#              (write slot 0x08 bit1) and report whether the CPU revives
#   CLEAR=1    clear the latch before hunting (default: yes)
#
# Write slots used here:
#   wr 0x88 0x01 -- clear the wedge latch, re-arm the snapshot
#   wr 0x88 0x02 -- pulse RAM.sv's unstick (parked queue dropped, IDLE)
#   wr 0x88 0x03 -- both

if {![info exists TIMEOUT_S]} { set TIMEOUT_S 240 }

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

set ram_st {IDLE W1 W2 R1 R2 COMPLETE WAIT}
set dma_st {SI S0 S1 S2 S3 SW S4 ?}

proc decode {} {
    global ram_st dma_st
    set a0 [rd 0xa0]; set a1 [rd 0xa1]; set a2 [rd 0xa2]; set a3 [rd 0xa3]
    set a4 [rd 0xa4]; set a5 [rd 0xa5]; set a6 [rd 0xa6]; set a7 [rd 0xa7]

    puts [format "latch=%d  retired=%06x  pc=%05x" \
        [expr {($a6 >> 31) & 1}] [expr {$a6 & 0xFFFFFF}] [expr {$a7 & 0xFFFFF}]]

    # -- 0xA0: arbiter/DMA + READY + hold byte
    set dce   [expr {($a0 >> 31) & 1}]
    set hrq1  [expr {($a0 >> 30) & 1}]
    set hrq2  [expr {($a0 >> 29) & 1}]
    set dmad  [expr {($a0 >> 16) & 0xFF}]
    set dst   [expr {($dmad >> 5) & 0x7}]    set dsel  [expr {($dmad >> 3) & 0x3}]
    puts [format "arbiter: dce_pin=%d hrq_ff1=%d hrq_ff2=%d | dma: state=%s ch=%d HRQ=%d TC=%d EOP=%d" \
        $dce $hrq1 $hrq2 [lindex $dma_st $dst] $dsel \
        [expr {($dmad >> 2) & 1}] [expr {($dmad >> 1) & 1}] [expr {$dmad & 1}]]
    puts [format "ready  : wait=%d prev_wait=%d Qn=%d prev_bus=%d bus=%d | proc_rdy=%d mem_rdy=%d dma_rdy=%d dack=%x nocs=%d" \
        [expr {($a0 >> 15) & 1}] [expr {($a0 >> 14) & 1}] \
        [expr {($a0 >> 13) & 1}] [expr {($a0 >> 12) & 1}] \
        [expr {($a0 >> 11) & 1}] \
        [expr {($a5 >> 15) & 1}] [expr {($a5 >> 14) & 1}] \
        [expr {($a5 >> 13) & 1}] [expr {($a5 >> 9) & 0xF}] \
        [expr {($a5 >> 8) & 1}]]
    puts [format "hold   : HLDA=%d AEN=%d dma_hrq=%d ext_req=%d drq=%d%d%d%d (pin-low=request)" \
        [expr {($a0 >> 7) & 1}] [expr {($a0 >> 6) & 1}] \
        [expr {($a0 >> 5) & 1}] [expr {($a0 >> 4) & 1}] \
        [expr {($a0 >> 3) & 1}] [expr {($a0 >> 2) & 1}] \
        [expr {($a0 >> 1) & 1}] [expr {$a0 & 1}]]

    # -- 0xA1: RAM.sv
    puts [format "RAM    : st=%s park={%d%d%d%d} rd_conf=%d alw=%d alr=%d rwc=%d wwc=%d vrw=%d vww=%d age=%d" \
        [lindex $ram_st [expr {($a1 >> 14) & 0x7}]] \
        [expr {($a1 >> 23) & 1}] [expr {($a1 >> 22) & 1}] \
        [expr {($a1 >> 21) & 1}] [expr {($a1 >> 20) & 1}] \
        [expr {($a1 >> 19) & 1}] [expr {($a1 >> 18) & 1}] \
        [expr {($a1 >> 17) & 1}] \
        [expr {($a1 >> 12) & 0x3}] [expr {($a1 >> 10) & 0x3}] \
        [expr {($a1 >> 9) & 1}] [expr {($a1 >> 8) & 1}] \
        [expr {$a1 & 0xFF}]]

    # -- 0xA2/0xA3: shim + controller
    set req_age  [expr {$a3 & 0xFF}]
    set busy_age [expr {($a2 >> 24) & 0xFF}]
    set preq     [expr {($a2 >> 18) & 0x3F}]
    set mpst     [expr {($a2 >> 14) & 0xF}]
    puts [format "shim   : req_age=%d busy_age=%d p_req{F,E,D,C,B,A}=%06b | mp: st=%d rr=%d rfdue=%d pg=%d idle=%d have_req=%d grant=%d busy=%d req=%d we=%d" \
        $req_age $busy_age $preq $mpst \
        [expr {($a2 >> 11) & 0x7}] [expr {($a2 >> 10) & 1}] \
        [expr {($a2 >> 9) & 1}] [expr {($a2 >> 8) & 1}] \
        [expr {($a2 >> 7) & 1}] [expr {($a2 >> 4) & 0x7}] \
        [expr {($a2 >> 3) & 1}] [expr {($a2 >> 2) & 1}] [expr {($a2 >> 1) & 1}]

    # -- 0xA4: bridge engine
    puts [format "bridge : cur={pf=%d fillm=%d dq=%d inta=%d} fill_ok=%d released=%d rd_own=%d saw_low=%d wrq=%d hit_q=%d pf_dead=%d cmd_age=%d" \
        [expr {($a4 >> 23) & 1}] [expr {($a4 >> 22) & 1}] \
        [expr {($a4 >> 21) & 1}] [expr {($a4 >> 20) & 1}] \
        [expr {($a4 >> 19) & 1}] [expr {($a4 >> 18) & 1}] \
        [expr {($a4 >> 17) & 1}] [expr {($a4 >> 16) & 1}] \
        [expr {($a4 >> 13) & 0x7}] [expr {($a4 >> 11) & 0x3}] \
        [expr {($a4 >> 9) & 0x3}] [expr {$a4 & 0xFF}]]

    # -- 0xA5 high: sequencer
    puts [format "seq    : expand=%d mem_rd=%d mem_wr=%d svc_gap=%d is_rd=%d is_word=%d half=%d wbatch=%d age=%d" \
        [expr {($a5 >> 31) & 1}] [expr {($a5 >> 30) & 1}] \
        [expr {($a5 >> 29) & 1}] [expr {($a5 >> 28) & 1}] \
        [expr {($a5 >> 27) & 1}] [expr {($a5 >> 26) & 1}] \
        [expr {($a5 >> 25) & 1}] [expr {($a5 >> 24) & 1}] \
        [expr {($a5 >> 16) & 0xFF}]]
}

# Fresh hunt: clear any stale latch from a previous run.
wr 0x88 0x01
after 200

puts "hunting (timeout ${TIMEOUT_S}s): poll 0x17/0x18 until the CPU stops..."
set t0 [clock seconds]
set last17 -1; set last18 -1; set static_n 0
while {[expr {[clock seconds] - $t0}] < $TIMEOUT_S} {
    after 400
    set r17 [rd 0x17]
    set r18 [rd 0x18]
    if {$r17 == $last17 && $r18 == $last18} {
        incr static_n
    } else {
        set static_n 0
    }
    set last17 $r17; set last18 $r18
    if {$static_n >= 8} {
        after 600   ;# let the ~390 ms freeze window close over the wedge
        puts [format "CPU static: retired=%06x pc_cursor=%05x" \
              [expr {$r17 & 0xFFFFFF}] [expr {$r18 & 0xFFFFF}]]
        break
    }
}

if {[expr {[rd 0xa6] >> 31}] & 1} {
    puts "=== WEDGE SNAPSHOT (frozen) ==="
    decode
} else {
    puts "no wedge within the timeout (latch not set); current state:"
    decode
}

if {[info exists env(UNSTICK)] && $env(UNSTICK) == 1} {
    puts "pulsing the RAM unstick (wr 0x88 0x02)..."
    wr 0x88 0x02
    after 300
    wr 0x88 0x01   ;# re-arm the tap for the next run
    set t1 [clock seconds]
    while {[expr {[clock seconds] - $t1}] < 10} {
        after 400
        set r17 [rd 0x17]
        puts [format "  after-unstick retired=%06x pc=%05x" \
              [expr {$r17 & 0xFFFFFF}] [expr {[rd 0x18] & 0xFFFFF}]]
        if {$r17 != $last17} { puts "  -> CPU RETIRED again (unstick recovered)"; break }
    }
}
shutdown
