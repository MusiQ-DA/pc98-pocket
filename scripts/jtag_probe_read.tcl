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

# Slots 0x01-0x24 were the POST panel's census and snoop words; they left
# with postmon and read DEAD <addr> now. Current map (PC98_JTAG builds):
#   0x10-0x16  v30 dbg_regs, MSW-first: psw:pc, sreg3:sreg2, sreg1:sreg0,
#              then gpr7:gpr6 down to gpr1:gpr0
#   0x17       retired-instruction counter (frozen = wedged)
#   0x18       current bus-cycle address
#   0x19       {arbiter: hlda,aen_n,dma_hold,ext_req,drq3..0,  RAM FSM:
#               wc_pend,refresh,read_flag,acc_rd,acc_wr,state[2:0]}
#   0x1a       {proc_ready, mem_acc_ready, dma_ready, dack_n3..0, no_cmd}
#   0x1b       {bridge: parked,cyc_active,bstate,wr_cnt,byte_idx,t_cnt,gap,cur_bs,
#               cpu_ce edge counter} -- ce_count frozen = the clock enable died
#   0x1c       {cpu_ad_out[19:0], v30_bs, pause, reset_cpu, reset_chipset,
#               reset, soft_reset_cpu, cpu_ce_posedge}
#   0x1d       keyboard count:last
#   0x20       {v30_data_i[15:0], dbg_core}: the byte pair last fed to the
#              core + {halted,q_ripe,ripe_lead_n,q_cnt,eu_bs,eu_pop,eu_flush,
#              eu_susp,eu_halt,rd_done_n,wr_done_n} -- EU/BIU interlock state
#   0x1e       {cont2, cont1} pad words as the softcore sees them (settled|jtag)
#   0x1f       {jtag_btn2, jtag_btn1} held-button inject mask -- a stuck bit
#              here means that pad bit reads held forever (no edge for fw)
set regs {
    16  V30_PSW_PC
    17  V30_SREG3_SREG2
    18  V30_SREG1_SREG0
    19  V30_GPR7_GPR6
    20  V30_GPR5_GPR4
    21  V30_GPR3_GPR2
    22  V30_GPR1_GPR0
    23  V30_RETIRED
    24  V30_ADDR
    25  ARB_HOLD+RAM_FSM
    26  READY_CHAIN
    27  BRIDGE+CE_CNT
    28  ALE_ADDR+BS+RST
    29  KEYS=count,last
    30  PADS=cont2,cont1
    31  JTAGBTN=held2,held1
    32  V30_DIN+EU_BIU
    33  EU_POST_ADDR
    34  BIU_LAUNCH
    35  EU_STALL
    36  QMEM0-3
    37  QMEM4-5+FPTR
    255 MAGIC
}

foreach {addr name} $regs {
    puts [format "0x%02x 0x%08X  %s" $addr [rd $addr] $name]
}

shutdown
