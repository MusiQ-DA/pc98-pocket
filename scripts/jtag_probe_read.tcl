# jtag_probe_read.tcl -- read every pc98_jtag_probe register and print a table.
#
# Verified working against Cyclone V (IDCODE 0x02b050dd) via USB Blaster.
#
# IMPORTANT: the FPGA only answers while a core is RUNNING. The Pocket MCU
# owns configuration (nCONFIG); in the menu the fabric is unconfigured and
# every USER scan returns all-ones. If MAGIC does not match, launch the core
# from the card first -- JTAG SRAM programming does not take on this machine.
#
# Protocol (Altera SLD hub + our node), verified on hardware:
#   1. USER1 (IR 0x0E), DR 64 x 0    -> select hub, arm hub-info read
#   2. USER0 (IR 0x0C), 8 x DR 4     -> HUB_INFO (LSB nibble first)
#   3. another 8 x DR 4             -> NODE1_INFO
#   4. USER1 DR 5 bits = {addr[0], VIR[3:0]}; 0x18 selects node 1
#      (addr=1 in bit 4, VIR_VALUE bit 3 must be 1 per Intel/SLD spec)
#   5. USER0 DR scans reach our node's 40-bit register. Each Capture-DR
#      loads {8'h00, probe_data[addr_q]} and TDO returns it LSB-first;
#      Update-DR latches the new address from the top byte shifted in.
#      A read therefore takes two scans: one to set the address, one to
#      capture its value.

init

# --- hub sanity: returns Altera manufacturer + node count -------------------
irscan fpga.tap 0x0e
drscan fpga.tap 64 0 -endstate idle
irscan fpga.tap 0x0c
set hub 0
for {set i 0} {$i < 8} {incr i} {
    scan [drscan fpga.tap 4 0 -endstate idle] %x nib
    set hub [expr {$hub | ($nib << (4*$i))}]
}
set nnodes [expr {($hub >> 19) & 0xff}]
puts [format "HUB_INFO=0x%08X  nodes=%d m_width=%d" $hub $nnodes [expr {$hub & 0xff}]]
if {$nnodes < 1} { puts "no SLD nodes -- is the core running?"; shutdown; exit 1 }

# --- select node 1 ----------------------------------------------------------
irscan fpga.tap 0x0e
drscan fpga.tap 5 0x18 -endstate idle

proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}

set regs {
    1   FRM_A=px_lit,nz_served
    2   FRM_B=nz_stored,fills,rb_fsm
    3   FONT=fvalid,freq
    4   TVFILL_0
    5   TVFILL_1
    6   TVRAM_CODE_0
    7   TVRAM_CODE_1
    8   TVRAM_ATTR_0
    9   TVRAM_ATTR_1
    10  TVRAM_HI_0
    11  TVRAM_HI_1
    12  GDC=unk,unkcmd,disp,sad
    13  LIVE_IP_CS
    14  DERAIL_IP_CS
    15  POST=count,prev,code
    16  LIVE_MEM_ADDR
    17  WR_LAST_ADDR
    18  TVRAM_LAST_ADDR
    19  IO_HIST_0
    20  IO_HIST_1
    255 MAGIC
}

foreach {addr name} $regs {
    puts [format "0x%02x 0x%08X  %s" $addr [rd $addr] $name]
}

shutdown
