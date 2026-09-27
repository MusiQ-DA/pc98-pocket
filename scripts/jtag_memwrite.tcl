# jtag_memwrite.tcl -- JTAG guest-memory read/write over probe slot 0x84,
# which drives sdram_selftest_master (u_selftest) through the BIOS-loader
# port (HOLD/HLDA borrows the running guest's bus).
#
# Slot 0x84 write packs one whole access:
#   probe_wdata = {go(29), we(28), wdata(27:20), addr(19:0)}
#   go=1 arms a one-shot access that self-releases on st_done.
# Read slot 0x25 returns {done(14), busy(15), rdata(7:0)}.
#
# Usage (openocd):
#   MODE=selftest  -- write+readback a scratch byte to prove the path.
#   MODE=inject BIN=testdisk/draw_test.bin SEG=0x8000
#                  -- load a binary into guest RAM, then point the keyboard
#                     IRQ vector (INT 09h, IVT 0x24) at it and trigger one key.
#   MODE=peek ADDR=0x70000 / poke ADDR= DATA=

set mode [expr {[info exists ::env(MODE)] ? $::env(MODE) : "selftest"}]

init
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0e
drscan fpga.tap 5 0x18 -endstate idle

proc wr {waddr data} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {((0x80 | $waddr) << 32) | ($data & 0xFFFFFFFF)}] -endstate idle
}
proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}

# guest byte write via slot 0x84 (go=1, we=1). Wait for the previous access to
# finish (jt_st_req / busy bit14 clear) so we never overwrite addr/wdata while
# u_selftest is mid-flight.
proc wmem {addr data} {
    wr 4 [expr {(1<<29) | (1<<28) | (($data & 0xFF) << 20) | ($addr & 0xFFFFF)}]
    after 1    ;# let the request cross the CDC + the access start
    for {set i 0} {$i < 200} {incr i} {
        if {!([rd 0x25] & 0x4000)} return
    }
    puts "  wmem timeout at [format %05x $addr]"
}
# guest byte read via slot 0x84 (go=1, we=0); result from read slot 0x25.
# Poll until jt_st_done (bit15) rises, then take rdata from bits 7:0.
proc rmem {addr} {
    wr 4 [expr {(1<<29) | ($addr & 0xFFFFF)}]
    after 1    ;# let the request cross the CDC + the access start
    for {set i 0} {$i < 200} {incr i} {
        set r [rd 0x25]
        if {$r & 0x8000} { return [expr {$r & 0xFF}] }
    }
    puts "  rmem timeout at [format %05x $addr]"
    return [expr {$r & 0xFF}]
}
# inject one keystroke (slot 0x81 matrix byte)
proc key {code} { wr 1 $code; after 60 }

if {$mode eq "selftest"} {
    # prove the path: write a byte, read it back
    set a 0x70000
    wmem $a 0xA5
    after 5
    set got [rmem $a]
    puts [format "selftest: wrote 0xA5 to %05x, read 0x%02X  (%s)" $a $got [expr {$got==0xA5?"OK":"FAIL"}]]
    # and the neighbouring byte stays sane
    puts [format "  0x25 reg = 0x%08X" [rd 0x25]]
} elseif {$mode eq "inject"} {
    # Jim Tcl (openocd) has no `binary` command, so the payload is read from a
    # whitespace-separated hex text file instead of the .bin directly:
    #   od -An -v -t x1 draw_test.bin | tr -s ' ' '\n' | tr '\n' ' ' > .hex
    set hexfile [expr {[info exists ::env(HEX)] ? $::env(HEX) : "testdisk/draw_test.hex"}]
    set seg [expr {[info exists ::env(SEG)] ? $::env(SEG) : 0x8000}]
    set base [expr {$seg << 4}]
    set fp [open $hexfile r]
    set txt [read $fp]
    close $fp
    set bytes {}
    foreach tok [split $txt] { if {$tok eq ""} continue; scan $tok %x v; lappend bytes $v }
    set n [llength $bytes]
    puts "injecting $n bytes at [format %05x $base] (seg $seg)"

    # 1) write the payload
    for {set i 0} {$i < $n} {incr i} {
        wmem [expr {$base + $i}] [lindex $bytes $i]
        if {$i % 16 == 0} { after 1 }
    }
    # 2) verify first/last bytes read back
    after 5
    set b0 [rmem $base]
    set be [rmem [expr {$base + $n - 1}]]
    puts [format "readback: head=0x%02X (expect %02X)  tail=0x%02X" $b0 [lindex $bytes 0] $be]

    # 3) hijack an interrupt vector to point at seg:0000.
    #    VEC selects the vector (default 0x08 = timer IRQ0, which auto-fires at
    #    ~18.2Hz so the next tick runs draw_test -- no trigger needed). VEC=0x09
    #    is the keyboard IRQ1 and is triggered by an injected key instead.
    set vec [expr {[info exists ::env(VEC)] ? $::env(VEC) : 0x08}]
    set ivt [expr {$vec * 4}]          ;# IVT entry: IP_lo,IP_hi,CS_lo,CS_hi
    set cs_lo [expr {$seg & 0xFF}]
    set cs_hi [expr {($seg >> 8) & 0xFF}]
    wmem $ivt           0x00
    wmem [expr {$ivt+1}] 0x00
    wmem [expr {$ivt+2}] $cs_lo
    wmem [expr {$ivt+3}] $cs_hi
    puts [format "IVT 0x%02x @%02x -> %04x:0000  (read: %02x %02x %02x %02x)" \
        $vec $ivt $seg \
        [rmem $ivt] [rmem [expr {$ivt+1}]] [rmem [expr {$ivt+2}]] [rmem [expr {$ivt+3}]]]

    # 4) trigger. The timer vector fires on its own; the keyboard vector needs
    #    an injected key (IRQ1).
    if {$vec == 0x09} {
        puts "triggering via injected keystroke -> IRQ1 -> draw_test"
        key 0x34
        key 0xB4
    } else {
        puts "vector armed; next INT 0x[format %02x $vec] runs draw_test"
    }
    puts "done. draw_test should be running (check the screen)."
} elseif {$mode eq "peek"} {
    puts [format "peek %s = 0x%02X" $::env(ADDR) [rmem $::env(ADDR)]]
} elseif {$mode eq "poke"} {
    wmem $::env(ADDR) $::env(DATA)
    puts [format "poke %s <- 0x%02X ; readback 0x%02X" $::env(ADDR) $::env(DATA) [rmem $::env(ADDR)]]
}

shutdown
