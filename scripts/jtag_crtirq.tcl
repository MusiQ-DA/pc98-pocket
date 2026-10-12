# jtag_crtirq.tcl -- decode the CRT interrupt (IRQ2) telemetry, probe slots
# 0x2D/0x2E (Peripherals dbg_crt): the master PIC's IMR/ISR/IRR, the 0x64
# arm/pending flags and the event counters.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_crtirq.tcl
#   env: CRTN=N      samples (default 1)
#        CRTMS=ms    spacing between samples (default 1000)
#
# A guest that counts frames off INT 0Ah hangs for good once IRQ2 stops.
# The counters say how: arm_n stalls while isr_n caught up with it = the
# arm was consumed and the handler that re-arms (OUT 64h) never ran;
# fire_n ahead of isr_n with ISR bit 2 set = in-service never EOI'd;
# lost_n = a pulse that fell on the PIC's acknowledge freeze; spur_n =
# INTAs answered with IRQ7's spurious vector. Slot 0x2F (the bridge's
# INTA witness): bad = ACK2 bytes outside 08-17, cut = DMA grants
# (AEN rising) splitting an acknowledge pair.
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

proc rd {a} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {$a << 32}] -endstate idle
    set r [drscan fpga.tap 40 0 -endstate idle]
    scan [string range $r end-7 end] %x v
    return $v
}

set n  [expr {[info exists ::env(CRTN)]  ? $::env(CRTN)  : 1}]
set ms [expr {[info exists ::env(CRTMS)] ? $::env(CRTMS) : 1000}]
for {set k 0} {$k < $n} {incr k} {
    set lo [rd 0x2d]
    set hi [rd 0x2e]
    puts [format "IMR=%02X ISR=%02X IRR=%02X armed=%d pend=%d int=%d | fire=%3d isr=%3d arm=%3d lost=%2d cancel=%2d spur=%2d | pc=%05X" \
        [expr {($lo >> 24) & 0xff}] [expr {($lo >> 16) & 0xff}] [expr {($lo >> 8) & 0xff}] \
        [expr {($lo >> 1) & 1}] [expr {($lo >> 2) & 1}] [expr {$lo & 1}] \
        [expr {($hi >> 24) & 0xff}] [expr {($hi >> 16) & 0xff}] [expr {($hi >> 8) & 0xff}] \
        [expr {($hi >> 4) & 0xf}] [expr {$hi & 0xf}] [expr {($lo >> 4) & 0xf}] \
        [expr {[rd 0x18] & 0xFFFFF}]]
    set iw [rd 0x2f]
    puts [format "  INTA: bad=%d last_bad=%02X cut=%d last_vec=%02X" \
        [expr {($iw >> 24) & 0xff}] [expr {($iw >> 16) & 0xff}] \
        [expr {($iw >> 8) & 0xff}] [expr {$iw & 0xff}]]
    if {$k + 1 < $n} { after $ms }
}
shutdown
