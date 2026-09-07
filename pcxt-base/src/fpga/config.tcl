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
#   then stops. It NEVER releases the guest, so this build does not boot -- that
#   is the point. See docs/P0_SELFTEST_SPEC.md.
#
#   The firmware Makefile reads its -D flags out of this file, so this one macro
#   arms both the RTL and the C. Comment it out to get a normal core back, and
#   REBUILD THE FIRMWARE (firmware.vh is committed, CI does not rebuild it).
set_global_assignment -name VERILOG_MACRO "SDRAM_SELFTEST=1"
