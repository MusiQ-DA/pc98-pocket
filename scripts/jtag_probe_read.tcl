# jtag_probe_read.tcl -- read every pc98_jtag_probe register and print a table.
#
# Protocol (Altera SLD hub + our node):
#   USER1 (IR 0x0E) DR is 9 bits: {8-bit node addr in MSBs, 1-bit VIR in LSBs}.
#   USER0 (IR 0x0C) DR scans go to the selected node: 40 bits, value bit 0
#   shifts onto TDI first and lands at shreg[0] after the scan; TDO returns
#   captured bit 0 first, so the returned integer is the register itself.
#   Capture grabs the data for the previously selected address, so a read is
#   two scans: set the address, then any scan returns its value.

init

# USER1: select node 1 (first user node; node 0 is the hub), VIR=1.
irscan fpga.tap 0x0e
drscan fpga.tap 9 0x3
# USER0: data-register access on the selected node from here on.
irscan fpga.tap 0x0c

set regs {
    1  FRM_A=px_lit,nz_served
    2  FRM_B=nz_stored,fills,rb_fsm
    3  FONT=fvalid,freq
    4  TVFILL_0
    5  TVFILL_1
    6  TVRAM_CODE_0
    7  TVRAM_CODE_1
    8  TVRAM_ATTR_0
    9  TVRAM_ATTR_1
    10 TVRAM_HI_0
    11 TVRAM_HI_1
    12 GDC=unk,unkcmd,disp,sad
    13 LIVE_IP_CS
    14 DERAIL_IP_CS
    15 POST=count,prev,code
    16 LIVE_MEM_ADDR
    17 WR_LAST_ADDR
    18 TVRAM_LAST_ADDR
    19 IO_HIST_0
    20 IO_HIST_1
    255 MAGIC
}

foreach {addr name} $regs {
    drscan fpga.tap 40 [expr {wide($addr) << 32}]
    set ret [drscan fpga.tap 40 0]
    puts [format "0x%02x 0x%08X  %s" $addr $ret $name]
}

shutdown
