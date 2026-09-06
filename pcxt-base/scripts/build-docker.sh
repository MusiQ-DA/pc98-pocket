#!/usr/bin/env bash
# build-docker.sh — local Quartus build via raetro/quartus:pocket (amd64/Rosetta)
#
# Copies the source tree into a FRESH temp dir per build (Docker Desktop's
# file-sharing cache can serve stale host files otherwise).
#
# Usage:
#   scripts/build-docker.sh            full compile, physical synthesis OFF (fast)
#   scripts/build-docker.sh --qor      physical synthesis ON (release quality)
#   scripts/build-docker.sh --check    analysis & synthesis only
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-raetro/quartus:pocket}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
[ -x "$DOCKER_BIN" ] || DOCKER_BIN="/Applications/Docker.app/Contents/Resources/bin/docker"

MODE="fast"
case "${1:-}" in
    --qor)   MODE="qor" ;;
    --check) MODE="check" ;;
    --fast)  MODE="fast" ;;
esac

BUILD_DIR="$(mktemp -d /tmp/pcxtbuild.XXXXXX)"
KEEP="${KEEP:-0}"

echo ">> building in $BUILD_DIR (mode: $MODE)"
mkdir -p "$BUILD_DIR/src"
# copy the whole src tree; firmware/ is referenced as ../firmware by the RTL
tar -C "$REPO/src" --exclude='fpga/output_files' --exclude='fpga/db' \
    --exclude='fpga/greybox_tmp' --exclude='fpga/incremental_db' \
    -cf - . | tar -C "$BUILD_DIR/src" -xf -

if [ "$MODE" = "fast" ]; then
    # iteration build: strip physical synthesis (expensive Fitter stage)
    python3 - "$BUILD_DIR/src/fpga/ap_core.qsf" <<'PY'
import sys
p = sys.argv[1]
lines = [l for l in open(p) if 'PHYSICAL_SYNTHESIS' not in l]
open(p, 'w').writelines(lines)
print("physical synthesis disabled (fast mode)")
PY
fi

"$DOCKER_BIN" run --rm -v "$BUILD_DIR":/work -w /work/src/fpga "$IMAGE" bash -lc '
  set -e
  Q=""
  for p in /opt/intelFPGA/quartus /opt/quartus /usr/local/quartus; do
    f=$(find "$p" -maxdepth 3 -name quartus_sh 2>/dev/null | head -1)
    if [ -n "$f" ]; then Q=$(dirname "$f"); break; fi
  done
  if [ -z "$Q" ]; then echo "ERROR: quartus_sh not found"; exit 1; fi
  echo "using quartus at $Q"
  export PATH="$Q:$PATH"
  export LD_LIBRARY_PATH="$Q:${LD_LIBRARY_PATH:-}"
  quartus_sh --version
  quartus_sh --flow compile ap_core
'

# bring artifacts back
if [ -d "$BUILD_DIR/src/fpga/output_files" ]; then
    mkdir -p "$REPO/src/fpga/output_files"
    cp -R "$BUILD_DIR/src/fpga/output_files/." "$REPO/src/fpga/output_files/" 2>/dev/null || true
    echo ">> done: $REPO/src/fpga/output_files/ap_core.rbf"
fi
