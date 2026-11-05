#!/usr/bin/env bash
# sim_perf.sh — build & run tb_mem_perf inside the pc98-sim docker image,
# with the exact CI invocation (.github/workflows/build.yml, perf step).
#
#   scripts/sim_perf.sh              # default pace
#   scripts/sim_perf.sh "+speed=3 +GRANT"
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

ARGS="${*:-}"
docker run --rm -v "$PWD":/work -w /work pc98-sim bash -lc "
  set -e
  S=fpga/core; K=\$S/chipset/HDL; Z8=\$S/z86
  verilator --binary --timing -Wno-fatal --top-module tb_mem_perf \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 \
    -Isim -I\$S -I\$S/common -I\$Z8 -I\$K -I\$K/i8288/HDL \
    sim/tb_mem_perf.sv \
    \$K/RAM.sv \$K/Ready.sv \$K/ce_generator.sv \$K/i8288/HDL/i8288.sv \
    \$S/sdram_shim.sv \$S/sdram_mp.sv \
    \$S/pc98_gvram_seq.sv \$S/pc98_grcg.sv \$S/pc98_egc.sv \
    \$S/pc98_gdc_mode2.sv \
    \$S/pc98_gvram_display.sv \$S/pc98_video_timing.sv \
    sim/sdram_board_model.sv sim/sdram_model.sv \
    \$Z8/z86_package.sv \$Z8/fetch.sv \$Z8/decode.sv \
    \$Z8/execute.sv \$Z8/write_back.sv \$Z8/regfile.sv \
    \$Z8/divider.sv \$Z8/z86_cache.sv \$Z8/z86.sv \
    \$S/cpu_bus_bridge.sv \
    -o perf
  ./obj_dir/perf $ARGS
"
