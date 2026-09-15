# PCXT configuration
# SYNTHESIS: the vendored nuV30 guards its simulation-only blocks (plusargs,
# $display traces) behind `ifndef SYNTHESIS`, and Quartus does not define the
# macro by itself for .sv inputs -- without this the PC-98 build dies
# elaborating $test$plusargs (Error 10174).
set_global_assignment -name VERILOG_MACRO "SYNTHESIS=1"
set_global_assignment -name VERILOG_MACRO "SYSTEM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ROM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_VIDEO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_AUDIO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_KBD=0"
# CGA/OPL2/CMS are the PC/XT's hardware; the PC-98 needs none of them
# (the CGA write path is architecturally dead under MACHINE_PC98, and
# the sound is the OPNA/beep line). The nuV30's LABs need the room:
# run#230 was 2042 LABs against the device's 1848.
set_global_assignment -name VERILOG_MACRO "ENABLE_CGA=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_HGC=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_OPL2=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_CMS=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_EMS=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_A000_UMB=1"

# PC/XT peripherals a PC-98 ROM cannot reach, and the device is at 97 per cent
# ALMs with the GDC and the GRCG still to come. The fit report puts the
# MC146818 at 0x02C0 at 349 ALMs and the two 16550s at 0x3F8/0x2F8 at 412; a
# PC-98's clock is a uPD4990A at 0x20/0x22/0x33 and its serial an 8251 at 0x30,
# so neither is addressable here -- they were synthesised only because nothing
# gated them.
#
# The XT IDE pair stays: no PC-98 storage path is written yet, and keeping the
# one that exists reachable is worth its 216 ALMs.
set_global_assignment -name VERILOG_MACRO "ENABLE_XT_RTC=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_XT_UART=0"
# Chipset clock rate in Hz: drives cur_rate (Verilog) and the softcore clock (firmware, /6).
set_global_assignment -name VERILOG_MACRO "CHIPSET_HZ=42954545"
# Machine layer: define MACHINE_PC98 to build the PC-98 memory map instead of
# the PC/AT one (BIOS.ROM 96KB at 0xE8000, ROM write-protect E8000-FFFFF).
# Comment it out to fall back to the PCXT build that reached POST (run#109).
set_global_assignment -name VERILOG_MACRO "MACHINE_PC98=1"

# The keyboard 8251 at 0x41/0x43 (pc98_kbd8251.sv). On by default: without it
# nobody answers the keyboard, the ITF's probe times out on every pass,
# [0x0500] bit 7 never gets set, and BASIC has no input at all. The first
# version of the model blanked the ITF by arming ACKs on writes that were
# not the 8251's (0x73 is the beep port); the model now arms only on the
# break edge, exactly as np2 does, so it can stay on. Comment it out to
# bisect a suspect keyboard interaction on hardware.
set_global_assignment -name VERILOG_MACRO "PC98_KBD_8251=1"

# PC98_DEBUG_BANDS replaces the picture with a free-running probe. It did its
# job: it proved the softcore, the ROM load, the raster and the OSD chain were
# all healthy, which left the CPU as the only suspect and sent the search to
# simulation, where the microcode ROM's out-of-range read turned up. Off now --
# the machine has a picture to show.
# set_global_assignment -name VERILOG_MACRO "PC98_DEBUG_BANDS=1"

# A 16x16 white square at the OSD's coordinate origin, to prove osd_hcnt and
# osd_vcnt reach the window at all. Its own comment said to remove it once the
# OSD was up; the OSD has been up for a while and the square has been sitting
# in the top-left corner of every build since, reading as a double-width tofu
# because that is exactly the size of one. It is first in pocket_video's
# overlay mux, so it covers whatever the guest draws there.
# set_global_assignment -name VERILOG_MACRO "PC98_OSD_MARK=1"

# Boot the ITF, not the BIOS.
#
# The core has powered on into the BIOS since the retrobios ITF was found to
# be a 386 image that cannot reach its own hand-over on an 8088. The ITF now
# shipped is the PC-9801UX one: no 32-bit instructions anywhere in it, a
# 70116 (V30) branch, and a checksum that passes. In simulation it runs the
# text VRAM test, sizes memory 128 KB at a time up to MEMORY 640KB OK, and
# hands over through port 0x043D.
#
# The BIOS stays the PC-9801VM one -- reconstructed byte for byte from the
# MAME chip dumps and 8086 throughout. The UX BIOS is not usable here: its
# POST uses PUSHA at FDA35 and SMSW/LGDT/LIDT after it.
set_global_assignment -name VERILOG_MACRO "PC98_BOOT_ITF=1"
# The real floppy controller, not the constant-returning stub.
#
# This was off because floppy0_chip_select_n decoded the PC/XT's 0x3F0-0x3F7,
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
#     for the 2DD one -- never master IRQ6, which is the PC/XT's floppy line and
#     on this machine is INT3, an expansion interrupt with no handler. np2kai
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
#     and 0x94/0xCC np2's fdc_i94 constants rather than a readback of the write.
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
# parameter that Peripherals.sv sets from MACHINE_PC98 -- a PC-98's 2HD/2DD
# drives drive a real READY line, a PC/AT's do not (pin 34 is DISK CHANGE), so
# the PC/XT build passes 0, every wire the change adds constant-folds away and
# its behaviour is unchanged. What an empty PC-98 drive answers instead comes
# from np2kai: READ/WRITE DATA and FORMAT go through FDC_DriveCheck (io/fdc.c:
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
set_global_assignment -name VERILOG_MACRO "PC98_FDC_REAL=1"

# Route SDRAM through sdram_mp (via sdram_kf_shim) instead of KFSDRAM.
# RAM.sv tests this with `ifdef, so setting it to 0 would still select the shim
# -- COMMENT THE LINE OUT to fall back to the stock controller for a hardware A/B.
#
# Bisection status (2026-09-07):
#   testB2 (sdram_mp)              FAIL  -- splash then black
#   testB3 (pure KFSDRAM)          PASS  -- tree + KFSDRAM path healthy
#   testB4 (shim glue + KFSDRAM)   PASS  -- glue exonerated; failure inside sdram_mp
#   testB5 (sdram_mp, width-cast timer constants + 233 us wait)  FAIL
#   testB6 (sdram_mp, negedge DQ capture)                        FAIL -- a
#          regression; the antiphase clock puts mid-window on the POSEDGE
#   testB7/7b (sdram_mp, posedge restored, dram_* finally constrained)
#
#   testB7ref (#59, measurement only): pure KFSDRAM against the new SDRAM
#          constraints. ANSWERED the question it was built for -- KFSDRAM, which
#          boots this board, reports the SAME read-path violation as sdram_mp
#          (-2.357 / TNS -17.784 vs -2.408 / TNS -17.914). So the -2.4 ns is a
#          property of the constraint values, not of sdram_mp, and the read path
#          is NOT the culprit. See docs/HANDOVER.md 1.8.
set_global_assignment -name VERILOG_MACRO "SDRAM_USE_MP=1"

#   ---- DIAGNOSTIC BUILD: SDRAM_SELFTEST -----------------------------------
#   Turns the core into an SDRAM test rig: the softcore walks guest memory with
#   the 8088 held in reset and leaves the first mismatching address on the OSD,
#   then stops. It NEVER releases the guest, so that build does not boot.
#
#   OFF now: it did its job. testB14 reported PILOT A5/A5, PILOT2 5A/5A (bank 1)
#   and PASS 64K on hardware, which proved the SDRAM was never the problem and
#   pointed at the CPU handshake instead -- see docs/HANDOVER.md and
#   sim/tb_cpu_timing.sv.
#
#   The firmware Makefile reads its -D flags out of this file, so this one macro
#   arms both the RTL and the C. Comment it out to get a normal core back, and
#   REBUILD THE FIRMWARE (firmware.vh is committed, CI does not rebuild it).
#   Re-enable to turn the core back into a test rig. Rebuild the firmware after
#   flipping it (firmware.vh is committed; CI checks it against the sources but
#   does not regenerate it).
# set_global_assignment -name VERILOG_MACRO "SDRAM_SELFTEST=1"

#   ---- DIAGNOSTIC: POST_MONITOR -------------------------------------------
#   Puts the guest's POST progress (I/O port 0x80) on a strip at the top of the
#   screen, with the last guest memory address and the last eight codes. The
#   core still boots normally; this only observes. See docs/HANDOVER.md 1.5 for
#   the POST map -- the build under investigation is expected to stop at 04,
#   the base 64 KB memory test at F000:E11A.
set_global_assignment -name VERILOG_MACRO "POST_MONITOR=1"
