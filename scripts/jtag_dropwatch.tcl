# jtag_dropwatch.tcl -- poll the RAM drop witness (probe slots 0x39/0x3a)
# while the guest boots: prints each change, and the first-lost snapshot.
#
#   0x39 = RAM dbg2 = {drop_st[2:0], drop_wr, drop_addr[19:0], drops[7:0]}
#   0x3a = RAM dbg3 = {16'd0, parks[15:0]}          (old build)
#        or          = {8'd0, blocked[7:0], parks[15:0]}  (refined build)

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
puts [format "nodes=%d m_width=%d" $nnodes $mw]

irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle

proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}

set last39 -1
set last3a -1
for {set i 0} {$i < 400} {incr i} {
    set e [catch {
        set v39 [rd 0x39]
        set v3a [rd 0x3a]
    } msg]
    if {$e} { puts "t=[expr $i*50]ms JTAG-ERR: $msg"; after 50; continue }
    set drops   [expr {$v39 & 0xff}]
    set parks   [expr {$v3a & 0xffff}]
    set blocked [expr {($v3a >> 16) & 0xff}]
    if {$v39 != $last39 || $v3a != $last3a} {
        puts [format "t=%5dms 39=%08x (st=%d wr=%d addr=%05x drops=%d) 3a=%08x (blocked=%d parks=%d)" \
              [expr $i*50] $v39 [expr {($v39>>29)&7}] [expr {($v39>>28)&1}] \
              [expr {($v39>>8)&0xfffff}] $drops $v3a $blocked $parks]
        set last39 $v39; set last3a $v3a
    }
    after 50
}
puts "done"
shutdown
