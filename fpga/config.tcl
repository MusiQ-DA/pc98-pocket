# PC-98 configuration
# SYNTHESIS: the vendored nuV30 guards its simulation-only blocks (plusargs,
# $display traces) behind `ifndef SYNTHESIS`, and Quartus does not define the
# macro by itself for .sv inputs -- without this the PC-98 build dies
# elaborating $test$plusargs (Error 10174).
set_global_assignment -name VERILOG_MACRO "SYNTHESIS=1"

set_global_assignment -name VERILOG_MACRO "CHIPSET_HZ=42954545"

# The PC-9801-86 sound board's YM2608 at 0x188-0x18F (pc98_opna.sv). Slim
# configuration -- USE_ADPCM=0, USE_PCM=1 in Peripherals.sv: 6-channel
# stereo FM + SSG, no ADPCM-A (use_pcm=1 is the only stereo FM path jt12
# has without ADPCM; use_pcm=0 falls back to the YM2203 mono accumulator).
# The EGC raster engine is fitted again (.EGC(1'b1) on pc98_gvram_seq) and
# the device could not carry it next to the ADPCM engines (~720 ALMs):
# rhythm voices and the drive-mechanism kit that borrowed them stay silent
# -- OMGMT_CAPS bit0 reads 0, which is what the firmware loaders key on.
# USE_ADPCM=1 brings the whole path back unchanged once floor space exists.
set_global_assignment -name VERILOG_MACRO "ENABLE_OPNA=1"

# JTAG debug build. OFF for the current fit: the SLD hub, the probe mux,
# the write-pipe and key injection together cost enough ALMs to put the
# fit over the 1848-LAB edge (the run that included them needed
# 1888-1917). scripts/jtag_probe.cfg, jtag_probe_read.tcl and the
# *_jtag_* benches still work -- enable this macro again when a debug
# session needs the probe, and expect to park something big (USE_ADPCM=0
# is already taken; the EGC is the ~870-ALM lever now).
#
# ON for the zet-cpu debug build: the Zet swap frees the headroom the V30
# build could not afford (slot 0x33 = last guest I/O write + count).
set_global_assignment -name VERILOG_MACRO "PC98_JTAG=1"

# Boot the ITF, not the BIOS.
#
# The core has powered on into the BIOS since the retrobios ITF was found to
# be a 386 image that cannot reach its own hand-over on a V30. The ITF now
# shipped is the PC-9801UX one: no 32-bit instructions anywhere in it, a
# 70116 (V30) branch, and a checksum that passes. In simulation it runs the
# text VRAM test, sizes memory 128 KB at a time up to MEMORY 640KB OK, and
# hands over through port 0x043D.
#
# The BIOS stays the PC-9801VM one -- reconstructed byte for byte from the
# MAME chip dumps and 8086 throughout. The UX BIOS is not usable here: its
# POST uses PUSHA at FDA35 and SMSW/LGDT/LIDT after it.
set_global_assignment -name VERILOG_MACRO "PC98_BOOT_ITF=1"

# EXPERIMENTAL CPU SWAP (zet-cpu branch): build with the Zet 80186-class
# core instead of nuV30. Zet has the full 186 instruction set -- the ITF's
# `push imm16` that derailed the old i8088 is legal for it -- but it is not
# cycle-accurate and carries none of the V30's NEC extensions. nuV30 stays
# the shipping CPU; this exists to measure the ~5.6k-ALM headroom claim.
set_global_assignment -name VERILOG_MACRO "PC98_ZET=1"
# The real floppy controller, not the constant-returning stub.
#
# This was off because floppy0_chip_select_n decoded the AT's 0x3F0-0x3F7,
# which a PC-98 never writes: floppy.v was instantiated, cost 885 ALMs, and
# could not be reached by the guest at all. The PC-98 ports were answered by
# fdd_stub_data with canned values, so the machine has had no working floppy.
#
# What kept it off was that the PC-98 control port is not a Digital Output
# Register and floppy.v needs one. pc98_fdc_glue makes that translation and
# tb_pc98_fdc_glue pins it -- which is the bench the PERIPHERALS comment asked
# for before this switch was allowed to move.
# IT WAS DISABLED TWICE, and both reasons are now fixed. The first: switching
# it on stopped the boot at MEMORY 640KB OK.
#
# The panel named it: the last four I/O writes were 00BE 00CC 00CC, the
# 2HD/2DD mode port and the 2DD control port, so the guest was inside the FDC
# code; and LVL read 41, which is the timer line plus bit 6 -- floppy.v's
# interrupt, asserted and never cleared. The stub that used to answer those
# ports has no interrupt line at all, which is why the boot got past here for
# as long as it did.
#
# THE INTERRUPT CONTRACT IS SETTLED AND IMPLEMENTED. What was found:
#
#   * The routing was wrong, not the acknowledge. A PC-98's FDC interrupt is a
#     SLAVE line -- IRQ11 (INT 13h) for the 2HD register window, IRQ10 (INT 12h)
#     for the 2DD one -- never master IRQ6, which is the AT's floppy line and
#     on this machine is INT3, an expansion interrupt with no handler. np21w
#     io/fdc.c:46-51 picks between pic_setirq(0x0b) and pic_setirq(0x0a) on
#     chgreg bit 0; the BIOS gates each of its own entry points on the SLAVE
#     mask (FF4B3 `in al,0x0A / test al,0x08` for 2HD, FF438 `test al,0x04` for
#     2DD) and refuses the call with AH=40h when masked; the ITF programs the
#     slave with ICW2 = 0x10 at F85C9, which puts those two on INT 12h/13h --
#     the vectors of the two handlers at FFAF6 and FFB69. LVL 41 was floppy.v
#     shouting down a wire the machine does not have.
#   * The acknowledge is a read of the result phase from the data port
#     (0x92/0xCA) and nothing else -- floppy.v lowers irq on exactly
#     `io_read && io_address == 5`, which is what both branches of the BIOS's
#     handler do. No acknowledge port, and the control port does not clear it.
#   * 0xBE had to become a real latch (the BIOS steers ITSELF with the readback)
#     and 0x94/0xCC np21w's fdc_i94 constants rather than a readback of the write.
#
# All of that is implemented in pc98_fdc_glue.sv and wired in Peripherals.sv,
# and sim/tb_pc98_fdc_glue now closes the loop against the real floppy.v: the
# BIOS's own sequence -- enable, RECALIBRATE, read the MSR, SENSE INTERRUPT
# STATUS, read ST0 -- raises the interrupt on IRQ11 and puts it down again, and
# a second command raises a fresh one.
#
# WHAT USED TO STOP IT, and no longer does: floppy.v with NO DISK IN THE DRIVE
# -- this core's normal state -- hung. Each of the three commands that need
# media had a *_hang_at_start wire named after what it did: accept the command
# (command_first has already set CB) and then answer nothing, being in neither
# enter_result_phase nor raise_interrupt, so the MSR parked at 0x90 for good.
# The BIOS's FFA0B will not send another command until CB clears and FF966
# spins 40*65536 polls for the interrupt, so one IPL probe of an empty drive --
# issued right after MEMORY 640KB OK -- cost every later FDC call an AH=0x90
# timeout at FFA57. The hand-tuned stub answered the same probe with seven
# bytes meaning "no drive", which is the only reason the machine ever booted.
#
# floppy.v now ends those commands properly, under a new NOT_READY_ENDS_COMMAND
# parameter that Peripherals.sv sets -- a PC-98's 2HD/2DD
# drives drive a real READY line, the upstream model's do not (pin 34 is DISK CHANGE), so
# the constant parameter folds the added wires away.
# What an empty PC-98 drive answers instead comes
# from np21w: READ/WRITE DATA and FORMAT go through FDC_DriveCheck (io/fdc.c:
# 176-182) to ST0 = FDCRLT_IC0|FDCRLT_NR|(hd<<2)|us = 0x48, ST1 = ST2 = 0,
# C/H/R/N echoed, seven bytes and an interrupt (fdcsend_error7, io/fdc.c:
# 97-117); READ ID (io/fdc.c:646-650) gives IC0|ND, ST0 = 0x40 / ST1 = 0x04.
# The BIOS's own result decoder at FF98F reads that back the way it is meant
# to: ST0 & 0xC0 nonzero -> FF9A1, EC (0x10) tested FIRST -> AH=0x40, then NR
# (0x08) -> AH=0x60, "drive not ready" -- the answer the IPL can carry on from.
#
# sim/tb_pc98_fdc_glue proves it against the real floppy.v behind the real
# glue: an empty-drive READ DATA interrupts on IRQ11, offers MSR 0xD0, hands
# back 48 00 00 00 00 01 02 and leaves CB CLEAR, a second one behaves the same,
# READ ID and FORMAT likewise, and a disk put back in still takes the old path.
# Every one of those checks was mutation-tested: with the parameter at 0 the
# new section fails 20 ways and the MSR reads 0x90, the old hang, for all three
# commands. (That also corrected the previous note here, which recorded READ ID
# as "fine" -- it had been measured against a drive that still had the earlier
# section's disk in it, because media_present has no reset in floppy.v.)
#
# PC98_FDC_REAL is gone with the stub it used to select against: the real
# floppy.v behind pc98_fdc_glue is the only FDC now.

# SDRAM runs through sdram_mp (via sdram_shim): the only controller in the
# tree -- the single-port reference and the MP_REF bisection far end were
# retired 2026-09-29 once the machine shipped on mp.

#   One V30 word memory access becomes one bus cycle where the SDRAM answers
#   (pc98_sdram_map.svh): RAM.sv keeps one guest byte per 16-bit SDRAM word,
#   so bytes N and N+1 are consecutive SDRAM words and the pair is a single
#   burst of two (452ad85 measured the path at 1.5-1.7x). It is the only
#   configuration now -- PC98_WORD_MEM was removed once nothing else shipped.
