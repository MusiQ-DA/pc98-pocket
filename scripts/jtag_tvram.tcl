# jtag_tvram.tcl -- dump the PC-98 text VRAM over JTAG.
#
# Uses the tvram debug port: write slot 0x8b arms a cell index, read slot
# 0x74 returns {cell[7:0] echo, attr, char_hi, char_lo}. The read rides the
# guest read pipeline's idle cycles, so a guest access can briefly own it --
# the echo byte flags that; the read retries until the echo matches.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_tvram.tcl
#   env: TVCELLS=N   cells to dump (default 2000 = 80x25)
#
# Output lines:  "cell <idx>: <attr> <hi> <lo>" -- decode with
# scripts/tvram_decode.py.

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

irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle   ;# probe node 1

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

# Read one cell: arm it, then poll until the echoed cell number matches.
proc rdcell {c} {
    wr 0x8b $c
    for {set i 0} {$i < 50} {incr i} {
        set v [rd 0x74]
        if {[expr {($v >> 24) & 0xff}] == ($c & 0xff)} {
            return [expr {$v & 0xffffff}]
        }
        after 1
    }
    return -1
}

set ncells [expr {[info exists ::env(TVCELLS)] ? $env(TVCELLS) : 2000}]
puts "# tvram dump: $ncells cells"
set fails 0
for {set c 0} {$c < $ncells} {incr c} {
    set v [rdcell $c]
    if {$v < 0} {
        puts [format "cell %d: STUCK" $c]
        incr fails
        if {$fails > 8} { puts "too many failures, aborting"; break }
        continue
    }
    puts [format "cell %d: %02x %02x %02x" $c \
        [expr {($v >> 16) & 0xff}] [expr {($v >> 8) & 0xff}] [expr {$v & 0xff}]]
}
puts [format "# done (%d failures)" $fails]
shutdown
exit 0
