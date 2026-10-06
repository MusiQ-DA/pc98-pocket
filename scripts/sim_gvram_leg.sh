#!/bin/bash
# sim_gvram_leg.sh -- the sequencer's wait states against the REAL RAM.sv.
#
# Guards the completion-ownership fix: RAM.sv's posted-write queue can pulse
# access_complete for a draining write while the sequencer holds a read
# strobe, and an unqualified S_RDW used to take that foreign pulse as its
# own -- dropping mem_rd before the read ran and capturing whatever byte
# data_bus_out_reg last held. sim/tb_gvram_ram_leg.sv drives a posted
# write pair and a same-address expanded read through the real SDRAM FSM
# and checks both the witness (a foreign done inside S_RDW) and the data
# the walk must still land.
set -euo pipefail
cd "$(dirname "$0")/.."

S=fpga/core
verilator --binary --timing -Wno-fatal --top-module tb_gvram_ram_leg \
    -Isim -I$S -I$S/chipset/HDL \
    sim/tb_gvram_ram_leg.sv sim/sdram_model.sv \
    $S/chipset/HDL/RAM.sv $S/sdram_shim.sv $S/sdram_mp.sv \
    $S/pc98_gvram_seq.sv $S/pc98_egc.sv \
    -o legt --Mdir obj_legt

./obj_legt/legt "$@"
