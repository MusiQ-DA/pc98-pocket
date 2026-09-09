# PCXT configuration
set_global_assignment -name VERILOG_MACRO "SYSTEM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ROM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_VIDEO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_AUDIO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_KBD=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_CGA=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_HGC=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_OPL2=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_CMS=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_EMS=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_A000_UMB=1"
# Chipset clock rate in Hz: drives cur_rate (Verilog) and the softcore clock (firmware, /6).
set_global_assignment -name VERILOG_MACRO "CHIPSET_HZ=42954545"
# Machine layer: define MACHINE_PC98 to build the PC-98 memory map instead of
# the PC/AT one (BIOS.ROM 96KB at 0xE8000, ROM write-protect E8000-FFFFF).
# Comment it out to fall back to the PCXT build that reached POST (run#109).
set_global_assignment -name VERILOG_MACRO "MACHINE_PC98=1"

# Debug bands: paint eight RTL-driven stripes down the left edge of the picture
# so the softcore's reset chain can be read without the softcore. Remove this
# line once the PC-98 core reaches its OSD. See dbg_bits in core_top.sv.
set_global_assignment -name VERILOG_MACRO "PC98_DEBUG_BANDS=1"

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
