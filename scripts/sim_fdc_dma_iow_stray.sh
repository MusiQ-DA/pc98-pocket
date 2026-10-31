#!/bin/bash
# sim_fdc_dma_iow_stray.sh -- build and run tb_fdc_dma_iow_stray: a guest
# I/O write parked in the 8288 across a DMA grant must not fire while the
# 71071's DACK is still out (the floppy-write 0x20 byte). Runs all four CPU
# speeds over a few seeds. Plusargs after the script pass straight through.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

S=fpga/core
H=$S/chipset/HDL
U=$H/upd71071/HDL
OBJ="${TMPDIR:-/tmp}/obj_fdc_dma_iow_stray"

verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
  --top-module tb_fdc_dma_iow_stray \
  -I$S -I$H -I$U \
  sim/tb_fdc_dma_iow_stray.sv \
  $S/cpu_bus_bridge.sv \
  $H/Bus_Arbiter.sv \
  $U/upd71071.sv $U/upd71071_Bus_Control_Logic.sv \
  $U/upd71071_Priority_Encoder.sv \
  $U/upd71071_Address_And_Count_Registers.sv \
  $U/upd71071_Timing_And_Control.sv \
  $H/i8288/HDL/i8288.sv \
  $H/Ready.sv $H/ce_generator.sv \
  -o t --Mdir "$OBJ" >/dev/null

rc=0
for sp in 0 1 2 3; do
  for seed in 1 2; do
    printf 'SPEED=%s SEED=%s: ' "$sp" "$seed"
    if "$OBJ/t" +SPEED="$sp" +SEED="$seed" +ITERS=2 "$@" \
         > "${TMPDIR:-/tmp}/fdc_iow_${sp}_${seed}.log" 2>&1 \
       && grep -q 'RESULT: PASS tb_fdc_dma_iow_stray' \
            "${TMPDIR:-/tmp}/fdc_iow_${sp}_${seed}.log"; then
      grep 'strays=' "${TMPDIR:-/tmp}/fdc_iow_${sp}_${seed}.log" | tr -d '\n'
      echo " : PASS"
    else
      echo FAIL
      grep -E 'strays=|sector|under DACK|RESULT' \
        "${TMPDIR:-/tmp}/fdc_iow_${sp}_${seed}.log" | head -12 || true
      rc=1
    fi
  done
done
exit $rc
