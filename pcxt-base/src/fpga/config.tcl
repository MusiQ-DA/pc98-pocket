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
#   ---- MEASUREMENT BUILD, 2026-09-07: testB7ref ----------------------------
#   SDRAM_USE_MP is commented out ON PURPOSE for one build. This is NOT a
#   hardware test and must not be flashed; it exists to read one number.
#
#   Constraining the dram_* pins (they had been unconstrained for the whole
#   project history) finally made STA analyse the SDRAM, and it reports the
#   read path at -2.408 ns. IO-cell packing does not move that, so it is not
#   routing. What we cannot tell from the sdram_mp build alone is whether the
#   number is specific to sdram_mp or common to the interface:
#
#     KFSDRAM also ~= -2.408  -> the 5.9 ns input delay is pessimistic for this
#                                part/board; the read path is not the culprit
#     KFSDRAM positive        -> sdram_mp's read path really is worse, and that
#                                is the bug
#
#   KFSDRAM boots this board, so it is the only valid yardstick. Re-enable the
#   macro below immediately after this build.
# set_global_assignment -name VERILOG_MACRO "SDRAM_USE_MP=1"
