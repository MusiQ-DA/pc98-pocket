#!/usr/bin/env bash
# build-std.sh — local Quartus Prime Standard 18.1 build via quartus-wine:18.1
# (Quartus for Windows under Wine, amd64 through Rosetta).
#
# Unlike the raetro/quartus:pocket Lite image this edition is licensed: the
# FlexLM host ID inside the container is its eth0 MAC, so the run pins
# --mac-address and the license's HOSTID must match it. The stock license.dat
# ships with the HOSTID=XXXXXXXXXXXX placeholder; when the file still has it,
# a rewritten copy (HOSTID = the pinned MAC) is generated under $TMPDIR and
# mounted instead -- the source file is never modified.
#
# Usage:
#   bash scripts/build-std.sh        full compile -> output_files/*.sof,*.rbf
#   QUARTUS_LICENSE=/path/to/license.dat bash scripts/build-std.sh
#   QUARTUS_MAC_HEX=0242AC110002 bash scripts/build-std.sh   (override NIC ID)
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fpga"

IMAGE="${IMAGE:-quartus-wine:18.1}"
LICENSE_FILE="${QUARTUS_LICENSE:-$HOME/Downloads/Quartus Prime 18.1/license.dat}"
MAC_HEX="$(echo "${QUARTUS_MAC_HEX:-0242AC110002}" | tr -d ':' | tr a-f A-F)"
DOCKER_BIN="${DOCKER_BIN:-docker}"
[ -x "$DOCKER_BIN" ] || DOCKER_BIN="/Applications/Docker.app/Contents/Resources/bin/docker"
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.docker/run/docker.sock}"

[ -f "$LICENSE_FILE" ] || { echo "ERROR: license file not found: $LICENSE_FILE"; exit 1; }

if LC_ALL=C grep -qE 'HOSTID=[0-9A-Fa-f]{12}' "$LICENSE_FILE"; then
    # A real 12-hex HOSTID is already in the file: pin the container to it
    # (genuine node-locked licenses land here too).
    MAC_HEX="$(LC_ALL=C grep -oE 'HOSTID=[0-9A-Fa-f]{12}' "$LICENSE_FILE" | head -1 | cut -d= -f2 | tr a-f A-F)"
    LIC_MOUNT="$LICENSE_FILE"
else
    LIC_MOUNT="${TMPDIR:-/tmp}/quartus-license-$MAC_HEX.dat"
    python3 - "$LICENSE_FILE" "$LIC_MOUNT" "$MAC_HEX" <<'PY'
import re, sys
src = open(sys.argv[1], 'rb').read().decode('latin-1')
open(sys.argv[2], 'w', newline='').write(
    re.sub(r'HOSTID=\S+', 'HOSTID=' + sys.argv[3], src))
PY
    echo ">> license HOSTID placeholder -> $MAC_HEX ($LIC_MOUNT)"
fi
MAC="$(echo "$MAC_HEX" | sed 's/\(..\)/\1:/g; s/:$//' | tr A-F a-f)"

echo ">> $IMAGE  license: $LICENSE_FILE  container MAC: $MAC"
exec "$DOCKER_BIN" run --rm --platform linux/amd64 --mac-address "$MAC" \
  -v "$PWD":/work \
  -v "$LIC_MOUNT":/license.dat:ro \
  -e LM_LICENSE_FILE='Z:\license.dat' \
  -e ALTERAD_LICENSE_FILE='Z:\license.dat' \
  -w /work \
  "$IMAGE" 'C:\intelFPGA\18.1\quartus\bin64\quartus_sh.exe' --flow compile ap_core
