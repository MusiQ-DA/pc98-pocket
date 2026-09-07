#!/usr/bin/env bash
# Inner script: runs inside the pc98-sim container.
set -e
S=pcxt-base/src/fpga/core
for mode in ref mp; do
  DEF=""
  [ "$mode" = mp ] && DEF="+define+SDRAM_USE_MP"
  echo "=================== mode: $mode ==================="
  verilator --binary --timing -Wno-fatal --top-module tb_ram_ab_ph $DEF \
    -Isim -I$S -I$S/KFPC-XT/HDL -I$S/KFPC-XT/HDL/KFSDRAM/HDL \
    sim/tb_ram_ab_ph.sv sim/sdram_model.sv sim/sdram_board_model.sv \
    $S/KFPC-XT/HDL/RAM.sv $S/KFPC-XT/HDL/KFSDRAM/HDL/KFSDRAM.sv \
    $S/sdram_kf_shim.sv $S/sdram_mp.sv \
    -o r --Mdir /tmp/obj_$mode
  /tmp/obj_$mode/r
  echo
done
