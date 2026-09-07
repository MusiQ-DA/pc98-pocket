#!/usr/bin/env bash
# run.sh — simulate the SDRAM controller with Verilator inside the pc98-sim image.
#
# The host's system DNS is broken but Docker Desktop resolves for containers, so
# the image (see Dockerfile) can be built and refreshed locally regardless.
#   docker build -t pc98-sim sim/
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
# The desktop credential helper needs an unlocked GUI keychain, which an SSH
# session does not have; a config without credsStore avoids it entirely.
CFG="${TMPDIR:-/tmp}/pc98-dockercfg"
mkdir -p "$CFG"
python3 - "$CFG/config.json" <<'PY'
import json, sys
c = json.load(open('/Users/hiroya/.docker/config.json'))
c.pop('credsStore', None)
json.dump(c, open(sys.argv[1], 'w'))
PY
export DOCKER_CONFIG="$CFG"

TB="${1:-tb_sdram_mp}"
docker run --rm -v "$PWD":/work -w /work pc98-sim bash -lc "
  set -e
  verilator --binary --timing -Wno-fatal -Wall \
    --top-module $TB \
    -Isim -Ipcxt-base/src/fpga/core \
    sim/${TB}.sv sim/sdram_model.sv pcxt-base/src/fpga/core/sdram_mp.sv \
    -o ${TB}_sim --Mdir /tmp/obj_${TB}
  /tmp/obj_${TB}/${TB}_sim
"
