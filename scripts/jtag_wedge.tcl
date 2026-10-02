# jtag_wedge.tcl -- read the wedge-PC taps (needs PC98_PROBE_EXTRA build).
#   0x2F = {cyc_cnt[31:24], processor_status[23:21], io_wr[20], fetch_addr[19:0]}
#   0x30 = {ior_cnt[31:24], iow_cnt[23:16], io_port[15:0]}
#   0x31 = {mem_cnt[31:24], 3'b0[23:21], mem_wr[20], mem_addr[19:0]}
# processor_status: 0=INTA 1=IOR 2=IOW 3=HALT 4=CODE 5=MEMR 6=MEMW 7=PASV
init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
set virw [expr {($hub & 0xff) + 4}]
irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle
proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}
set names {0 inta 1 iord 2 iowr 3 halt 4 code 5 memr 6 memw 7 pasv}
proc dump {tag} {
    global names
    set w2f [rd 0x2f]; set w30 [rd 0x30]; set w31 [rd 0x31]
    set cyc [expr {($w2f >> 24) & 0xFF}]
    set ps  [expr {($w2f >> 21) & 0x7}]
    set iow [expr {($w2f >> 20) & 0x1}]
    set fa  [expr {$w2f & 0xFFFFF}]
    set ior [expr {($w30 >> 24) & 0xFF}]
    set iowc [expr {($w30 >> 16) & 0xFF}]
    set iop [expr {$w30 & 0xFFFF}]
    set mc  [expr {($w31 >> 24) & 0xFF}]
    set mw  [expr {($w31 >> 20) & 0x1}]
    set ma  [expr {$w31 & 0xFFFFF}]
    puts [format "%s cyc=%02x ps=%s iowr=%d fetch=%05x | ior=%02x iow=%02x port=%04x | mem=%02x mwr=%d maddr=%05x" \
        $tag $cyc [lindex $names $ps] $iow $fa $ior $iowc $iop $mc $mw $ma]
}
dump "t0"
after 500
dump "t0.5"
after 500
dump "t1.0"
foreach a {0x1f 0x20 0x21 0x26 0x27 0x28 0x2e} {
    puts [format "  %s = %08x" $a [rd $a]]
}
dump "t2"
shutdown
