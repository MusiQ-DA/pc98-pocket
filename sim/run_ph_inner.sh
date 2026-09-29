#!/usr/bin/env bash
# Inner script: runs inside the pc98-sim container. Verifies the shim through
# the RAM.sv integration testbench at board timing.
set -e
S=fpga/core
verilator --binary --timing -Wno-fatal --top-module tb_ram_ab \
  -Isim -I$S -I$S/chipset/HDL \
  sim/tb_ram_ab.sv sim/sdram_model.sv \
  $S/chipset/HDL/RAM.sv $S/sdram_shim.sv $S/sdram_mp.sv \
  -o r --Mdir /tmp/obj_ram_ab
/tmp/obj_ram_ab/r
