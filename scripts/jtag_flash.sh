#!/usr/bin/env bash
# jtag_flash.sh -- program the Pocket's Cyclone V over JTAG, no SD card.
#
# The Pocket's MCU owns nCONFIG, so a bitstream can only take while a core
# is RUNNING (the menu leaves the fabric unconfigured). While it runs, the
# official Quartus JTAG sequence configures the part and the MCU notices
# the reconfiguration and re-initializes the core -- assets, dataslot and
# all -- exactly as if it had been loaded from the card.
#
# openFPGALoader's own Cyclone V sequence never reaches user mode on this
# machine; what works is the SVF Quartus itself generates from the .sof
# (quartus_cpf). Docker does the conversion, openocd plays it back.
#
# Usage:
#   scripts/jtag_flash.sh [path/to/ap_core.sof]
# Default: fpga/output_files/ap_core.sof. Local Quartus builds are retired;
# pass a CI artifact .sof downloaded from the build workflow's
# quartus-win-bitstream artifact (output_files/ap_core.sof).

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOF="${1:-fpga/output_files/ap_core.sof}"
SOF="$(cd "$(dirname "$SOF")" && pwd)/$(basename "$SOF")"
[ -f "$SOF" ] || { echo "no such .sof: $SOF"; exit 1; }
case "$SOF" in "$PWD"/*) SOF="${SOF#"$PWD"/}" ;; *) echo ".sof must live under $PWD"; exit 1 ;; esac

DOCKER_BIN="${DOCKER_BIN:-docker}"
[ -x "$DOCKER_BIN" ] || DOCKER_BIN="/Applications/Docker.app/Contents/Resources/bin/docker"
IMAGE="${IMAGE:-raetro/quartus:pocket}"

SVF_DIR=build/svf_jtag
mkdir -p "$SVF_DIR"
SVF="$SVF_DIR/$(basename "${SOF%.sof}").svf"

echo ">> generating SVF from $SOF"
"$DOCKER_BIN" run --rm -v "$PWD":/work -w /work "$IMAGE" bash -lc '
  set -e
  Q=""
  for p in /opt/intelFPGA/quartus /opt/quartus /usr/local/quartus /opt/intelFPGA_lite /opt/altera; do
    if [ -x "$p/bin/quartus_sh" ]; then Q="$p/bin"; break; fi
    if [ -x "$p/bin64/quartus_sh" ]; then Q="$p/bin64"; break; fi
    f=$(find "$p" -maxdepth 3 -name quartus_sh 2>/dev/null | head -1)
    if [ -n "$f" ]; then Q=$(dirname "$f"); break; fi
  done
  export PATH="$Q:$PATH" LD_LIBRARY_PATH="$Q:${LD_LIBRARY_PATH:-}"
  quartus_cpf -c -q 6MHz -g 3.3 -n v "$0" "$1"
' "$SOF" "$SVF"

echo ">> programming over JTAG (core must be running)"
openocd -f scripts/jtag_probe.cfg -c "
  init
  svf $SVF -tap fpga.tap -quiet
  irscan fpga.tap 0x07
  set u [drscan fpga.tap 32 0 -endstate idle]
  puts \"USERCODE=0x\$u (expect the .sof's usercode)\"
  shutdown" 2>&1 | grep -v 'Info\|Warn\|Open On\|Licensed\|DEPRECATED' | tail -8
