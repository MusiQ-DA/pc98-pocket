#!/usr/bin/env bash
# build-docker.sh — local Quartus build via raetro/quartus:pocket (amd64,
# run through Rosetta/QEMU by Docker Desktop on Apple Silicon).
# Usage:
#   bash scripts/build-docker.sh           full compile -> output_files/*.rbf
#   bash scripts/build-docker.sh --check   Analysis & Synthesis only
# Requires: docker daemon running + raetro/quartus:pocket image pulled.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/src/fpga"

IMAGE="${IMAGE:-raetro/quartus:pocket}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
[ -x "$DOCKER_BIN" ] || DOCKER_BIN="/Applications/Docker.app/Contents/Resources/bin/docker"
FLOW="compile"
[ "${1:-}" = "--check" ] && FLOW="analyze"

echo ">> building with $IMAGE (flow: $FLOW)"
exec "$DOCKER_BIN" run --rm -v "$PWD":/work -w /work "$IMAGE" bash -lc '
  set -e
  Q=""
  for p in /opt/intelFPGA/quartus /opt/quartus /usr/local/quartus /opt/intelFPGA_lite /opt/altera; do
    if [ -x "$p/bin/quartus_sh" ]; then Q="$p/bin"; break; fi
    if [ -x "$p/bin64/quartus_sh" ]; then Q="$p/bin64"; break; fi
    f=$(find "$p" -maxdepth 3 -name quartus_sh 2>/dev/null | head -1)
    if [ -n "$f" ]; then Q=$(dirname "$f"); break; fi
  done
  if [ -z "$Q" ]; then echo "ERROR: quartus_sh not found in image"; exit 1; fi
  echo "using quartus at $Q"
  export PATH="$Q:$PATH"
  export LD_LIBRARY_PATH="$Q:${LD_LIBRARY_PATH:-}"
  quartus_sh --version
  quartus_sh --flow compile ap_core
'
