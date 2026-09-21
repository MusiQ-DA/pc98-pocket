#!/usr/bin/env bash
# Inner script: runs inside the pc98-sim container. MACHINE_PC98 selects the
# shadow-bank logic in RAM.sv / BUS_ARBITER; SDRAM_USE_MP is the shipped
# controller config (config.tcl).
set -e
S=fpga/core
FILES="sim/tb_postmon_peek.sv sim/sdram_model.sv \
  $S/chipset/HDL/RAM.sv $S/chipset/HDL/Bus_Arbiter.sv \
  $S/chipset/HDL/KFSDRAM/HDL/KFSDRAM.sv \
  $S/sdram_kf_shim.sv $S/sdram_mp.sv $S/sdram_selftest_master.sv \
  $S/chipset/HDL/KF8288/HDL/KF8288.sv \
  $S/chipset/HDL/KF8237/HDL/KF8237.sv \
  $S/chipset/HDL/KF8237/HDL/KF8237_Address_And_Count_Registers.sv \
  $S/chipset/HDL/KF8237/HDL/KF8237_Bus_Control_Logic.sv \
  $S/chipset/HDL/KF8237/HDL/KF8237_Priority_Encoder.sv \
  $S/chipset/HDL/KF8237/HDL/KF8237_Timing_And_Control.sv"
INC="-Isim -I$S -I$S/chipset/HDL -I$S/chipset/HDL/KFSDRAM/HDL \
  -I$S/chipset/HDL/KF8237/HDL -I$S/chipset/HDL/KF8288/HDL"

for variant in fixed repro; do
  DEF="+define+MACHINE_PC98+SDRAM_USE_MP"
  [ "$variant" = repro ] && DEF="+define+MACHINE_PC98+SDRAM_USE_MP+REPRO_OLD_SHADOW"
  echo "=================== variant: $variant ==================="
  verilator --binary --timing -Wno-fatal --top-module tb_postmon_peek $DEF \
    $INC $FILES -o r --Mdir /tmp/obj_peek_$variant
  (cd sim && /tmp/obj_peek_$variant/r)
  echo
done
