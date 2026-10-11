#!/usr/bin/env bash
# sim_mem_perf.sh -- cycle-attribution bench for guest memory writes.
#
# Runs tb_mem_perf (zet + bridge + 8288 + READY + gvram_seq + RAM + sdram_mp
# + board model, display fetch on port D) in the pc98-sim docker image --
# local Verilator 5.052 mis-schedules --timing benches.
#
#   scripts/sim_mem_perf.sh [+plusargs]     e.g.  +speed=0 +disp=1
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
CFG="${TMPDIR:-/tmp}/pc98-dockercfg"
mkdir -p "$CFG"
python3 - "$CFG/config.json" <<'PY'
import json, os, sys
c = json.load(open(os.path.expanduser('~/.docker/config.json')))
c.pop('credsStore', None)
json.dump(c, open(sys.argv[1], 'w'))
PY
export DOCKER_CONFIG="$CFG"

docker run --rm -v "$PWD":/work -w /work pc98-sim bash -lc '
  set -e
  mkdir -p /tmp/obj_perf/fpga/core/zet
  cp fpga/core/zet/micro_rom.dat /tmp/obj_perf/fpga/core/zet/
  cd /tmp/obj_perf
  R=/work; S=fpga/core; K=$S/chipset/HDL; Z=$S/zet
  verilator --binary --timing -Wno-fatal --top-module tb_mem_perf \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$Z" -I"$R/$K" \
    -I"$R/$K/i8288/HDL" \
    "$R/sim/tb_mem_perf.sv" \
    "$R/$K/RAM.sv" "$R/$K/Ready.sv" "$R/$K/ce_generator.sv" \
    "$R/$K/i8288/HDL/i8288.sv" \
    "$R/$S/sdram_shim.sv" "$R/$S/sdram_mp.sv" \
    "$R/$S/pc98_gvram_seq.sv" "$R/$S/pc98_grcg.sv" "$R/$S/pc98_egc.sv" \
    "$R/$S/pc98_gdc_mode2.sv" \
    "$R/$S/pc98_gvram_display.sv" "$R/$S/pc98_video_timing.sv" \
    "$R/sim/sdram_board_model.sv" "$R/sim/sdram_model.sv" \
    $R/$Z/zet.v $R/$Z/zet_core.v $R/$Z/zet_fetch.v $R/$Z/zet_decode.v \
    $R/$Z/zet_exec.v $R/$Z/zet_memory_regs.v $R/$Z/zet_micro_data.v \
    $R/$Z/zet_micro_rom.v $R/$Z/zet_regfile.v $R/$Z/zet_wb_master.v \
    $R/$Z/zet_addsub.v $R/$Z/zet_alu.v $R/$Z/zet_arlog.v \
    $R/$Z/zet_bitlog.v $R/$Z/zet_conv.v $R/$Z/zet_div_su.v \
    $R/$Z/zet_div_uu.v $R/$Z/zet_fulladd16.v $R/$Z/zet_jmp_cond.v \
    $R/$Z/zet_muldiv.v $R/$Z/zet_mux8_1.v $R/$Z/zet_mux8_16.v \
    $R/$Z/zet_next_or_not.v $R/$Z/zet_nstate.v $R/$Z/zet_opcode_deco.v \
    $R/$Z/zet_othop.v $R/$Z/zet_rxr8.v $R/$Z/zet_rxr16.v \
    $R/$Z/zet_shrot.v $R/$Z/zet_signmul17.v \
    "$R/$S/zet_cpu_bridge.sv" \
    -o perf 2>&1 | grep -v "%Warning" | tail -40
  ./obj_dir/perf "$@"
' -- "$@"
