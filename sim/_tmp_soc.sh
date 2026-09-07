S=pcxt-base/src/fpga/core
H=$S/KFPC-XT/HDL
INC=$(find $S -type d | sed 's/^/-I/' | tr '\n' ' ')
verilator --binary --timing -Wno-fatal -Wno-PROCASSWIRE -O3 --top-module tb_selftest_soc \
  $INC -Isim -Ipcxt-base/src/fpga/apf \
  sim/tb_selftest_soc.sv sim/stub_altsyncram.sv sim/stub_vhdl.sv \
  sim/sdram_board_model.sv sim/sdram_model.sv \
  $S/softcpu_subsystem.sv $S/softcpu_fdd_bridge.sv $S/picorv32.v \
  $S/sdram_selftest_master.sv \
  pcxt-base/src/fpga/apf/common.v $(find $S -name 'sprom*' | tr '\n' ' ') \
  $H/RAM.sv $H/KFSDRAM/HDL/KFSDRAM.sv $S/sdram_kf_shim.sv $S/sdram_mp.sv \
  +define+SDRAM_USE_MP -o soc --Mdir /tmp/soc 2>&1 | grep -E "%Error" | head -6
cd /work/pcxt-base/src/fpga && /tmp/soc/soc 2>&1 | tail -16
