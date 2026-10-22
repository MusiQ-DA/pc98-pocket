#!/bin/bash
# sim_fdc_si_stall.sh -- build and run tb_fdc_si_stall, the third-deadlock
# bench: the uPD71071 losing a register write when the next bus cycle
# preempts the write strobe's tail (the lost 0x15 unmask that parks the
# DMAC in SI with the FDC's DRQ pending -- SuperDepth's in-game freeze).
#
# Runs the full matrix by default: both write-tail shapes (well-formed
# hold, and the bridge's preempting tail), both FDC transfer modes, all
# four CPU speeds. Plusargs pass straight through.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

S=fpga/core
H=$S/chipset/HDL
U=$H/upd71071/HDL

verilator --binary --timing -Wno-fatal --top-module tb_fdc_si_stall \
  -I$H -I$U \
  sim/tb_fdc_si_stall.sv \
  $H/Bus_Arbiter.sv \
  $U/upd71071.sv $U/upd71071_Bus_Control_Logic.sv \
  $U/upd71071_Priority_Encoder.sv \
  $U/upd71071_Address_And_Count_Registers.sv \
  $U/upd71071_Timing_And_Control.sv \
  $H/i8288/HDL/i8288.sv \
  $H/Ready.sv $H/ce_generator.sv \
  -o tsi --Mdir "${TMPDIR:-/tmp}/obj_fdc_si_stall"

rc=0
for tail in 0 1; do
  for sp in 0 1 2 3; do
    for md in 46 06; do
      printf 'TAIL=%s SPEED=%s MODE=%s: ' "$tail" "$sp" "$md"
      if ! "${TMPDIR:-/tmp}/obj_fdc_si_stall/tsi" \
           +ITERS=4 +SPEED="$sp" +MODE="$md" +TAIL="$tail" \
           | tee "/tmp/fdc_si_${tail}_${sp}_${md}.log" | grep -q \
           'RESULT: PASS tb_fdc_si_stall'; then
        echo FAIL
        rc=1
      else
        echo PASS
      fi
    done
  done
done
exit $rc
