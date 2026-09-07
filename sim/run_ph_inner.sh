#!/usr/bin/env bash
# Inner script: runs inside the pc98-sim container. Verifies the shim's three
# build variants through the RAM.sv integration testbench.
set -e
S=pcxt-base/src/fpga/core
for mode in ref mp mp_kfref; do
  DEF="+define+SDRAM_USE_MP"
  [ "$mode" = ref ] && DEF=""
  [ "$mode" = mp_kfref ] && DEF="+define+SDRAM_USE_MP+SDRAM_MP_KF_REF"
  echo "=================== mode: $mode ==================="
  verilator --binary --timing -Wno-fatal --top-module tb_ram_ab $DEF \
    -Isim -I$S -I$S/KFPC-XT/HDL -I$S/KFPC-XT/HDL/KFSDRAM/HDL \
    sim/tb_ram_ab.sv sim/sdram_model.sv \
    $S/KFPC-XT/HDL/RAM.sv $S/KFPC-XT/HDL/KFSDRAM/HDL/KFSDRAM.sv \
    $S/sdram_kf_shim.sv $S/sdram_mp.sv \
    -o r --Mdir /tmp/obj_$mode
  /tmp/obj_$mode/r
  echo
done
