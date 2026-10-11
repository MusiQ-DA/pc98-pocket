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
#   4. USER1 DR (m_width+4) bits = {node[m_width-1:0], VIR[3:0]}; 0x18 selects
#      node 1 (node addr 1 above the VIR nibble, VIR_VALUE bit 3 must be 1
#      per Intel/SLD spec). m_width comes from HUB_INFO[7:0] -- 1 on a
#      one-node build, 2 once the ramimg stream sink joins.
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
set nnodes [expr {($hub >> 19) & 0xff}]
set mw 1
while {(1 << $mw) < $nnodes + 1} { incr mw }
set virw [expr {$mw + 4}]

# --- select node 1 ----------------------------------------------------------
irscan fpga.tap 0x0e
drscan fpga.tap $virw 0x18 -endstate idle

proc rd {addr} {
    irscan fpga.tap 0x0c
    drscan fpga.tap 40 [expr {($addr << 32) & 0xFFFFFFFFFF}] -endstate idle
    set raw [drscan fpga.tap 40 0 -endstate idle]
    return 0x[string range $raw end-7 end]
}

# Slots 0x01-0x24 were the POST panel's census and snoop words; they left
# with postmon and read DEAD <addr> now. Current map (PC98_JTAG builds):
#   0x10-0x16  were the nuV30's dbg_regs (psw:pc, sregs, gprs) -- Zet has no
#              equivalent tap, so they read 0 now
#   0x17       nuV30 retired-instruction counter -- reads 0 on the Zet build
#   0x18       zet_pc, the core's current linear PC
#   0x19       {arbiter: hlda,aen_n,dma_hold,ext_req,drq3..0,  RAM FSM:
#               wc_pend,refresh,read_flag,acc_rd,acc_wr,state[2:0]}
#   0x1a       {proc_ready, mem_acc_ready, dma_ready, dack_n3..0, no_cmd}
#   0x1b       {bridge: parked,cyc_active,bstate,wr_cnt,byte_idx,t_cnt,gap,cur_bs,
#               cpu_ce edge counter} -- ce_count frozen = the clock enable died
#   0x1c       {cpu_ad_out[19:0], processor_status, pause, reset_cpu,
#               reset_chipset, reset, soft_reset_cpu, cpu_ce_posedge}
#   0x1d       keyboard count:last
#   0x20       {zwb_dat_i[15:0], dbg_core}: the byte pair last fed to the
#              core; the low half was the nuV30 EU/BIU interlock and reads 0
#   0x1e       {cont2, cont1} pad words as the softcore sees them (settled|jtag)
#   0x1f       {jtag_btn2, jtag_btn1} held-button inject mask -- a stuck bit
#              here means that pad bit reads held forever (no edge for fw)
#   0x26       fdc_dbg[31:0]  = {reply_left[0], cmd_drops[7:0],
#              cmd_accepts[7:0], dbg_xfer[14:0]: state[3:0]@14..11 +
#              fifo_count[10:0]} -- parked state says which wait died
#   0x27       fdc_dbg[63:32] = {4'b0, drive[1:0], lba[14:0], busy, irq,
#              dma_enable, dma_tc, dma_ack, dma_req, request[1:0],
#              reply_left[3:1]} -- the LBA the in-flight request named
#   0x28/0x29  live FDC command register: {op, unit, C, H | R, N, EOT, GPL}
#              -- the transaction the engine is parked on or last rejected
#   0x31       GVRAM sequencer {svc_req, svc_done, svc_hold, fsm[2:0],
#              plane[1:0]} -- a stalled GDC draw names its stage
#   0x32       {gdc_draw_ops[15:0] (slave op in the high byte),
#               egc_flag_seen (054D bit6 written = EGC flag up),
#               draw_to_seen[1:0] {s,m} (watchdog fired = the old stall),
#               gdc_draw_busy[1:0], gdc_draw_req[1:0], accel_status[3:0]
#               = {page, EGC, RMW, GRCG armed}}
#   0x36       TVRAM debug cell {attr,char_hi,char_lo} -- each read steps
#              the cell; write slot 0x82 re-seeks (jtag_screen.tcl)
#   0x37       the TVRAM debug cell index itself
#   0x38       guest-mem read: {busy, svc_addr[19:0], rdata} -- write slot
#              0x84 launches an address, each read launches the next
#              (jtag_gvram.tcl)
#   0x39       slave GDC display regs, low: {disp_on, page-0xA4, analogue,
#              5MHz clk, doubled-200, CSRFORM LR[4:0], SYNC AL[9:0],
#              PITCH[7:0]}
#   0x3a       slave GDC display regs, high: {SAD0[15:0], LEN0[9:0]}
#
#   write 0x85 re-arms the PC-history snapshot: clears pc_hist_frozen and
#              pc_snap_valid so the NEXT freeze trigger (F0 write, errhalt
#              PC, or zet_fault) captures a fresh trail. Needed because the
#              boot-time F0 write otherwise consumes the snapshot before
#              any guest fault can.
set regs {
    16  NUV30_PSW_PC=0
    17  NUV30_SREG3_SREG2=0
    18  NUV30_SREG1_SREG0=0
    19  NUV30_GPR7_GPR6=0
    20  NUV30_GPR5_GPR4=0
    21  NUV30_GPR3_GPR2=0
    22  NUV30_GPR1_GPR0=0
    23  NUV30_RETIRED=0
    24  ZET_PC
    25  ARB_HOLD+RAM_FSM
    26  READY_CHAIN
    27  BRIDGE+CE_CNT
    28  ALE_ADDR+BS+RST
    29  KEYS=count,last
    30  PADS=cont2,cont1
    31  JTAGBTN=held2,held1
    32  ZWB_DIN (+nuV30 EU_BIU=0)
    33  NUV30_POST_ADDR=0
    34  NUV30_BIU_LAUNCH=0
    35  NUV30_EU_STALL=0
    36  NUV30_QMEM0-3=0
    37  NUV30_QMEM4-5+FPTR=0
    38  FDC_XFER+ACC/DROP
    39  FDC_REQ+LBA+DMA
    40  FDC_CMD_LO=EOT/GPL/N/R
    41  FDC_CMD_HI=op/unit/C/H
    48  SCSI=mg_rd,post,rom_rd
    49  GVRAMSEQ=req,done,hold,fsm,pl
    50  GDC_DRAW=ops,flag,to,busy,req
    54  TVRAM_CELL=attr,hi,lo
    55  TVRAM_CELL_IDX
    56  GVRAM_RD=busy,addr,data
    255 MAGIC
}

foreach {addr name} $regs {
    puts [format "0x%02x 0x%08X  %s" $addr [rd $addr] $name]
}

shutdown
