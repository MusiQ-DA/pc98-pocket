#!/usr/bin/env bash
# build-docker.sh — local Quartus build via raetro/quartus:pocket (amd64/Rosetta)
#
# NOTE: copies the source tree into a FRESH temp dir for every build — Docker
# Desktop's file-sharing cache can serve stale host files otherwise.
#
# Usage:
#   scripts/build-docker.sh            full compile
#   scripts/build-docker.sh --check    analysis & synthesis only
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-raetro/quartus:pocket}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
[ -x "$DOCKER_BIN" ] || DOCKER_BIN="/Applications/Docker.app/Contents/Resources/bin/docker"
# --fast (default): disable physical synthesis in the build-dir copy of the
# qsf (big Fitter speedup, slight QoR cost). Use --qor to keep it (releases).
MODE="${1:-fast}"
QOR=0
[ "$MODE" = "--qor" ] && QOR=1
FAST=1
[ "$MODE" = "--qor" ] && FAST=0

BUILD_DIR="$(mktemp -d /tmp/pcxtbuild.XXXXXX)"
KEEP="${KEEP:-0}"
cleanup() { [ "$KEEP" = "1" ] || rm -rf "$BUILD_DIR"; }
trap cleanup EXIT
mkdir -p "$BUILD_DIR/src"
# copy the whole src tree; firmware/ is referenced as ../firmware by the RTL
tar -C "$REPO/src" --exclude='fpga/output_files' --exclude='fpga/db' \
    --exclude='fpga/greybox_tmp' --exclude='fpga/incremental_db' \
    -cf - . | tar -C "$BUILD_DIR/src" -xf -

if [ "$FAST" = "1" ]; then
    # iteration build: strip physical synthesis (expensive Fitter stage)
    python3 - "$BUILD_DIR/src/fpga/ap_core.qsf" <<'PY'
import sys
p = sys.argv[1]
lines = [l for l in open(p) if 'PHYSICAL_SYNTHESIS' not in l]
open(p, 'w').writelines(lines)
print("physical synthesis disabled (fast mode)")
PY
fi

echo ">> building in $BUILD_DIR ($FLOW)"
"$DOCKER_BIN" run --rm -v "$BUILD_DIR":/work -w /work/src/fpga "$IMAGE" bash -lc '
  set -e
  Q=""
  for p in /opt/intelFPGA/quartus /opt/quartus /usr/local/quartus; do
    f=$(find "$p" -maxdepth 3 -name quartus_sh 2>/dev/null | head -1)
    if [ -n "$f" ]; then Q=$(dirname "$f"); break; fi
  done
  if [ -z "$Q" ]; then echo "ERROR: quartus_sh not found"; exit 1; fi
  export PATH="$Q:$PATH"; export LD_LIBRARY_PATH="$Q:${LD_LIBRARY_PATH:-}"
  quartus_sh --version
  case '"$FLOW"' in
    compile) quartus_sh --flow compile ap_core ;;
    *)       quartus_map --read_settings_files=on --write_settings_files=off ap_core -c ap_core ;;
  esac
'

# bring artifacts back
if [ -d "$BUILD_DIR/src/fpga/output_files" ]; then
    mkdir -p "$REPO/src/fpga/output_files"
    cp -R "$BUILD_DIR/src/fpga/output_files/." "$REPO/src/fpga/output_files/" 2>/dev/null || true
    echo ">> done: $REPO/src/fpga/output_files/ap_core.rbf"
fi
