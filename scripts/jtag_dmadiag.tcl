# jtag_dmadiag.tcl -- one-shot dump of every DMA/byte0 diagnostic slot.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_dmadiag.tcl
#   env: WATCH=0x1e000   also arm the Bus_Arbiter watchpoint (slot 0x8a)
#        RESET=1         pulse guest reset via fdd_ramimg slot 0x87 bit2 first
#
# Entry format (all the *_log rings): {cpu, dma, mux-mismatch, io_wr,
#                                      addr[19:0], data[7:0]}.

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

proc ent {v} {
    # decode a watch/head entry: cpu dma mm iow addr data
    return [format "{f=%x addr=%05x data=%02x}" \
        [expr {($v >> 28) & 0xf}] [expr {($v >> 8) & 0xfffff}] [expr {$v & 0xff}]]
}
proc acc {v} {
    # accept-ring entry: {2'b0,pend,word,addr[19:0],data}
    return [format "{pend=%d w=%d addr=%05x data=%02x}" \
        [expr {($v >> 29) & 1}] [expr {($v >> 28) & 1}] \
        [expr {($v >> 8) & 0xfffff}] [expr {$v & 0xff}]]
}

select_node 1

if {[info exists ::env(WATCH)]} {
    wr 0x8a [expr {$env(WATCH) & 0xFFFFF}]
    puts [format "watch armed at %05x" [expr {$env(WATCH) & 0xFFFFF}]]
}
if {[info exists ::env(RESET)] && $env(RESET)} {
    wr 0x87 5            ;# en + greset pulse
    after 50
    wr 0x87 1
    after 200
    puts "guest reset pulsed"
}

puts [format "0x18 live PC    = 0x%08X" [rd 0x18]]
puts [format "0x35 ramimg    = 0x%08X" [rd 0x35]]
puts [format "0x38 fault     = 0x%08X" [rd 0x38]]
puts [format "0x39 ram dbg2  = 0x%08X  (retired)"                  [rd 0x39]]
puts [format "0x3a ram dbg3  = 0x%08X  {parks}"                    [rd 0x3a]]

set s3e [rd 0x3e]
puts [format "-- head_log (DMA-stream breaks / CPU writes in ack window) --"]
puts [format "breaks=%d grants=%d ackwr=%d" \
    [expr {($s3e >> 24) & 0xff}] [expr {($s3e >> 16) & 0xff}] [expr {$s3e & 0xffff}]]
puts [format "  newest  %s" [ent [rd 0x3b]]]
puts [format "          %s"          [ent [rd 0x3c]]]
puts [format "  oldest  %s" [ent [rd 0x3d]]]

puts "-- first-4 sticky watch hits --"
puts [format "  #0 %s" [ent [rd 0x6a]]]
puts [format "  #1 %s" [ent [rd 0x6b]]]
puts [format "  #2 %s" [ent [rd 0x6c]]]
puts [format "  #3 %s" [ent [rd 0x6d]]]

puts "-- watch ring (slot 0x8a target) --"
puts [format "  watch_cnt=%d" [expr {[rd 0x67] >> 24}]]
puts [format "  newest  %s" [ent [rd 0x64]]]
puts [format "          %s" [ent [rd 0x65]]]
puts [format "  oldest  %s" [ent [rd 0x66]]]

set s68 [rd 0x68]
set s69 [rd 0x69]
puts "-- RAM uncovered-write witness --"
puts [format "  uncov_cnt=%d  first_addr=%06x" \
    [expr {($s68 >> 24) & 0xff}] [expr {$s68 & 0xffffff}]]
puts [format "  first_data=%02x  last_addr[15:0]=%04x  last_data=%02x" \
    [expr {$s69 & 0xff}] [expr {($s69 >> 8) & 0xffff}] [expr {$s69 >> 24}]]

puts "-- RAM accept ring (sink side, mapped addrs) --"
puts [format "  acc_cnt=%d" [expr {[rd 0x71] & 0xff}]]
puts [format "  newest  %s" [acc [rd 0x6e]]]
puts [format "          %s" [acc [rd 0x6f]]]
puts [format "  oldest  %s" [acc [rd 0x70]]]

set s72 [rd 0x72]
set s73 [rd 0x73]
puts "-- RAM watch-address sink side --"
puts [format "  wseen=%d  wacc=%d" \
    [expr {($s73 >> 8) & 0xff}] [expr {$s73 & 0xff}]]
puts [format "  last accepted %s" [acc $s72]]

shutdown
