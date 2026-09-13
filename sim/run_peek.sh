#!/usr/bin/env bash
# run_peek.sh — tb_postmon_peek (the postmon ROM-peek shadow-bank bench) in Docker.
#
# Two builds of the same bench, and BOTH must pass:
#   fixed  core_top's current flag mux: the peek reads the main bank, BAD 000
#   repro  the mux WITHOUT the st_run override: must come back BAD 0EC / GOT
#          all zeros -- the hardware readout. If the repro build does not
#          reproduce the symptom, the bench is not modelling the fault and its
#          PASS on the fixed build proves nothing.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
CFG="${TMPDIR:-/tmp}/pc98-dockercfg"; mkdir -p "$CFG"
python3 - "$CFG/config.json" <<'PY'
import json, sys
c = json.load(open('/Users/hiroya/.docker/config.json'))
c.pop('credsStore', None)
json.dump(c, open(sys.argv[1], 'w'))
PY
export DOCKER_CONFIG="$CFG"

docker run --rm -v "$PWD":/work -w /work pc98-sim bash /work/sim/run_peek_inner.sh
