#!/usr/bin/env bash
# boot_flake_test.sh -- reflash the same .sof N times and classify each boot
# as OK (BIOS reached the file-count prompt / any text) or WEDGE (blank screen
# and frozen timer ticks after ~65 s). Each JTAG reflash makes the Pocket MCU
# re-run the whole slot load, so every iteration is a fresh cold boot of the
# same bitstream.
#
# Usage: scripts/boot_flake_test.sh path/to/ap_core.sof [iterations]
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOF="${1:?usage: boot_flake_test.sh ap_core.sof [N]}"
N="${2:-5}"

for i in $(seq 1 "$N"); do
    echo "===== attempt $i: flash ====="
    if ! bash scripts/jtag_flash.sh "$SOF" > "/tmp/bf_flash_$i.log" 2>&1; then
        echo "attempt $i: FLASH FAILED"; tail -3 "/tmp/bf_flash_$i.log"; continue
    fi
    echo "flashed; waiting 65 s for POST + floppy timeout"
    sleep 65

    # screen text (jtag_screen.tcl prints "|...|" rows between the
    # '---- text plane' and '---- attributes' markers)
    screen=$(openocd -f scripts/jtag_probe.cfg -f scripts/jtag_screen.tcl 2>/dev/null \
             | sed -n '/text plane/,/attributes/p' | grep '^|' \
             | tr -d '| ' | tr '\n' ' ')
    probes=$(openocd -f scripts/jtag_probe.cfg -f scripts/jtag_probe_read.tcl 2>/dev/null)
    pic1=$(echo "$probes"  | grep -E '^0x1f ' | awk '{print $2}')
    rvrfy=$(echo "$probes" | grep -E '^0x2[bcd] ' | awk '{printf "%s ", $2}')
    echo "attempt $i: PIC1=$pic1 (ticks in low byte)"
    # Clean BIOS image reads: 2B=38001C78 2C=C0003800 2D=1C78FFFF (walk==stream==file)
    echo "attempt $i: ROMVERIFY=$rvrfy"
    echo "screen: $screen"
    if echo "$screen" | grep -qiE "files|BASIC|How"; then
        echo "attempt $i: BOOT OK"
    elif [ -z "$(echo "$screen" | tr -d '0 ')" ]; then
        echo "attempt $i: WEDGE (blank screen)"
    else
        echo "attempt $i: PARTIAL (some text, not the prompt)"
    fi
    echo
done
echo "===== done ====="
