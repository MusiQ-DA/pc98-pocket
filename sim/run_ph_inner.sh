#!/usr/bin/env bash
# Inner script: runs inside the pc98-sim container. Verifies the shim's three
# build variants through the RAM.sv integration testbench.
set -e
S=fpga/core
for mode in ref mp mp_ref; do
  DEF="+define+SDRAM_USE_MP"
  [ "$mode" = ref ] && DEF=""
  [ "$mode" = mp_ref ] && DEF="+define+SDRAM_USE_MP+SDRAM_MP_REF"
  echo "=================== mode: $mode ==================="
  verilator --binary --timing -Wno-fatal --top-module tb_ram_ab $DEF \
    -Isim -I$S -I$S/chipset/HDL -I$S/chipset/HDL/sdram_single/HDL \
    sim/tb_ram_ab.sv sim/sdram_model.sv \
    $S/chipset/HDL/RAM.sv $S/chipset/HDL/sdram_single/HDL/sdram_single.sv \
    $S/sdram_shim.sv $S/sdram_mp.sv \
    -o r --Mdir /tmp/obj_$mode
  /tmp/obj_$mode/r
  echo
done
