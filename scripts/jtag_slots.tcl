# jtag_slots.tcl -- read the PC-98 JTAG probe slots (0x31 gvram seq,
# 0x32 draw server, 0x33 io writes, 0x38 first fault) once.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_slots.tcl

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
set mw     1
while {(1 << $mw) < $nnodes + 1} { incr mw }
puts [format "HUB_INFO=0x%08X  nodes=%d m_width=%d" $hub $nnodes $mw]
set virw [expr {$mw + 4}]

proc select_node {n} {
    global virw
    irscan fpga.tap 0x0e
    drscan fpga.tap $virw [expr {($n << 4) | 8}] -endstate idle
}

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

select_node 1
puts [format "0x31 (gvram seq) = 0x%08X" [rd 0x31]]
puts [format "0x32 (draw srv)  = 0x%08X" [rd 0x32]]
puts [format "0x33 (io writes) = 0x%08X" [rd 0x33]]
puts [format "0x18 (live PC)   = 0x%08X" [rd 0x18]]
puts [format "0x38 (fault)     = 0x%08X" [rd 0x38]]
puts [format "0x34 (in35)      = 0x%08X" [rd 0x34]]
puts [format "0x39 (parks)     = 0x%08X" [rd 0x39]]
puts [format "0x3a (uncov)     = 0x%08X" [rd 0x3a]]
puts [format "0x3b (acc0)      = 0x%08X" [rd 0x3b]]
puts [format "0x3c (acc1)      = 0x%08X" [rd 0x3c]]
puts [format "0x3d (acc2)      = 0x%08X" [rd 0x3d]]
puts [format "0x3e (acc_cnt)   = 0x%08X" [rd 0x3e]]
puts [format "0x3f (svc ops)   = 0x%08X" [rd 0x3f]]
puts [format "0x60 (trig wd)   = 0x%08X" [rd 0x60]]
puts [format "0x68 (uncov)     = 0x%08X" [rd 0x68]]
puts [format "0x69 (uncov2)    = 0x%08X" [rd 0x69]]
puts [format "0x6e (acc0)      = 0x%08X" [rd 0x6e]]
puts [format "0x6f (acc1)      = 0x%08X" [rd 0x6f]]
puts [format "0x70 (acc2)      = 0x%08X" [rd 0x70]]
puts [format "0x71 (acc_cnt)   = 0x%08X" [rd 0x71]]
shutdown
exit 0
