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
# TEMPORARILY COMMENTED OUT (2026-09-07): hardware regression build. testB2 (run#46,
# both bug fixes) still fails to reach BIOS on hardware while all sims pass.
# This build isolates: current tree + stock KFSDRAM. If it boots, the failure is
# inside sdram_mp/shim on real hardware; if not, the integration path regressed.
# set_global_assignment -name VERILOG_MACRO "SDRAM_USE_MP=1"
