#!/usr/bin/env bash
# run_ph.sh — tb_ram_ab_ph (board-timing model) for both controllers, in Docker.
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

docker run --rm -v "$PWD":/work -w /work pc98-sim bash /work/sim/run_ph_inner.sh
