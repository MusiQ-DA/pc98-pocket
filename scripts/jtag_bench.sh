#!/usr/bin/env bash
# jtag_bench.sh -- one scripted benchmark point on the Pocket.
#
#   scripts/jtag_bench.sh <image.hdm> <speed 0-3|clear> [marker] [timeout_s]
#
# Uploads the image into the fdd_ramimg carve-out, pins the CPU speed via
# probe slot 0x89, mounts + guest-resets, then polls the text screen with
# jtag_screen.tcl until <marker> appears (default "Execute time") or the
# timeout expires. Prints the scraped screen; the caller greps the score.
#
# Needs openocd on PATH and the Pocket on JTAG with a PC98_JTAG build.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

IMG=${1:?usage: jtag_bench.sh <hdm> <speed> [marker] [timeout]}
SPD=${2:-clear}
MARK=${3:-"Execute time"}
LIMIT=${4:-420}

echo "== upload+mount $IMG (speed=$SPD) =="
HDIMG="$IMG" HDSPEED="$SPD" openocd -f scripts/jtag_probe.cfg \
    -f scripts/jtag_hdload.tcl 2>&1 | grep -v "^Info\|clock speed\|TapName" | tail -12

echo "== waiting for '$MARK' (timeout ${LIMIT}s) =="
t0=$SECONDS
while (( SECONDS - t0 < LIMIT )); do
    scr=$(openocd -f scripts/jtag_probe.cfg -f scripts/jtag_screen.tcl 2>/dev/null \
          | sed -n '/---- screen ----/,/---- attributes/p')
    if grep -qF "$MARK" <<<"$scr"; then
        echo "== marker after $((SECONDS - t0))s =="
        grep -v "^$" <<<"$scr" | sed 's/ *|$//'
        exit 0
    fi
    sleep 20
done
echo "TIMEOUT after ${LIMIT}s -- last screen:"
grep -v "^$" <<<"$scr" | sed 's/ *|$//'
exit 1
