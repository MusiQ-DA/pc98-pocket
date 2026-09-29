# jtag_regs.tcl -- V30 register dump over probe slots 0x32-0x38 + INT pin.
#   0x32={pc,cs} 0x33={psw,ss} 0x34={sp,bp} 0x35={ds,es}
#   0x36={ax,bx} 0x37={cx,dx} 0x38={si,di}  0x21 bit16 = interrupt_to_cpu
init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
drscan fpga.tap 4 0 -endstate idle
irscan fpga.tap 0x0e
drscan fpga.tap 5 0x18 -endstate idle
proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}
for {set i 0} {$i < 3} {incr i} {
    set r32 [rd 0x32]; set r33 [rd 0x33]; set r34 [rd 0x34]; set r35 [rd 0x35]
    set r36 [rd 0x36]; set r37 [rd 0x37]; set r38 [rd 0x38]
    set pc  [expr {$r32 >> 16}]; set cs [expr {$r32 & 0xFFFF}]
    set psw [expr {$r33 >> 16}]; set ss [expr {$r33 & 0xFFFF}]
    set sp  [expr {$r34 >> 16}]; set bp [expr {$r34 & 0xFFFF}]
    set ds  [expr {$r35 >> 16}]; set es [expr {$r35 & 0xFFFF}]
    set ax  [expr {$r36 >> 16}]; set bx [expr {$r36 & 0xFFFF}]
    set cx  [expr {$r37 >> 16}]; set dx [expr {$r37 & 0xFFFF}]
    set si  [expr {$r38 >> 16}]; set di [expr {$r38 & 0xFFFF}]
    set lin [expr {($cs << 4) + $pc}]
    puts [format "sample %d: CS:IP=%04x:%04x (phys %05x) PSW=%04x IF=%d" $i $cs $pc $lin $psw [expr {($psw >> 9) & 1}]]
    puts [format "  SS:SP=%04x:%04x (phys %05x) BP=%04x DS=%04x ES=%04x" $ss $sp [expr {($ss << 4) + $sp}] $bp $ds $es]
    puts [format "  AX=%04x BX=%04x CX=%04x DX=%04x SI=%04x DI=%04x" $ax $bx $cx $dx $si $di]
    puts [format "  irq21=%08x pic1=%08x pic2=%08x wedge2f=%08x" [rd 0x21] [rd 0x1f] [rd 0x20] [rd 0x2f]]
    after 400
}
shutdown
