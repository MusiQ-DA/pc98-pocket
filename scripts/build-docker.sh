#!/usr/bin/env bash
# Phase-1 build: dockerized Quartus (raetro/quartus:pocket, amd64 emulation)
# Usage: bash scripts/build-docker.sh [--check]
#   --check : Analysis & Synthesis only (fast sanity pass)
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/src/fpga"

IMAGE="${IMAGE:-raetro/quartus:pocket}"
FLOW="compile"
[ "${1:-}" = "--check" ] && FLOW="analyze"

# platform note: image is amd64; Docker Desktop runs it via Rosetta/QEMU.
echo ">> building with $IMAGE (flow: $FLOW)"
exec docker run --rm -v "$PWD":/work -w /work "$IMAGE" bash -lc '
  for p in /opt/quartus /usr/local/quartus /opt/intelFPGA_lite /opt/altera; do
    if [ -x "$p/bin64/quartus_sh" ]; then export PATH="$p/bin64:$PATH"; break; fi
    f=$(find "$p" -maxdepth 3 -name quartus_sh 2>/dev/null | head -1) && [ -n "$f" ] && export PATH="$(dirname "$f"):$PATH" && break
  done
  command -v quartus_sh >/dev/null || { echo "ERROR: quartus_sh not found in image"; exit 1; }
  quartus_sh --flow '"$FLOW"' ap_core
'
