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
# BISECTION RUNG 1 (2026-09-07, testB4): SDRAM_MP_KF_REF swaps the far end of
# the shim to the STOCK KFSDRAM (translated to sdram_mp's interface) while the
# glue stays this file's. testB2 (sdram_mp) fails on hardware and testB3 (pure
# KFSDRAM) boots, both passing every simulation, so this build decides:
#   boots  -> failure is inside sdram_mp
#   fails  -> failure is in the shim glue / RAM.sv-facing handshake
set_global_assignment -name VERILOG_MACRO "SDRAM_USE_MP=1"
set_global_assignment -name VERILOG_MACRO "SDRAM_MP_KF_REF"
