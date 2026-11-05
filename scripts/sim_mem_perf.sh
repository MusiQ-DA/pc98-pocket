#!/usr/bin/env bash
# sim_mem_perf.sh -- cycle-attribution bench for guest memory writes.
#
# Runs tb_mem_perf (z86 + bridge + 8288 + READY + gvram_seq + RAM + sdram_mp
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
  mkdir -p /tmp/obj_perf
  cd /tmp/obj_perf
  R=/work; S=fpga/core; K=$S/chipset/HDL; Z8=$S/z86
  verilator --binary --timing -Wno-fatal --top-module tb_mem_perf \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$Z8" -I"$R/$K" \
    -I"$R/$K/i8288/HDL" \
    "$R/sim/tb_mem_perf.sv" \
    "$R/$K/RAM.sv" "$R/$K/Ready.sv" "$R/$K/ce_generator.sv" \
    "$R/$K/i8288/HDL/i8288.sv" \
    "$R/$S/sdram_shim.sv" "$R/$S/sdram_mp.sv" \
    "$R/$S/pc98_gvram_seq.sv" "$R/$S/pc98_grcg.sv" "$R/$S/pc98_egc.sv" \
    "$R/$S/pc98_gdc_mode2.sv" \
    "$R/$S/pc98_gvram_display.sv" "$R/$S/pc98_video_timing.sv" \
    "$R/sim/sdram_board_model.sv" "$R/sim/sdram_model.sv" \
    $R/$Z8/z86_package.sv $R/$Z8/fetch.sv $R/$Z8/decode.sv \
    $R/$Z8/execute.sv $R/$Z8/write_back.sv $R/$Z8/regfile.sv \
    $R/$Z8/divider.sv $R/$Z8/z86_cache.sv $R/$Z8/z86.sv \
    "$R/$S/cpu_bus_bridge.sv" \
    -o perf 2>&1 | grep -v "%Warning" | tail -40
  ./obj_dir/perf "$@"
' -- "$@"
