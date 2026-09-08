#!/bin/bash
# push_firmware.sh -- rebuild the softcore firmware and copy it to the card.
#
# The whole point of the firmware data slot: a change to an on-screen readout
# costs a file copy instead of a fifteen-to-twenty minute Quartus compile.
# Nothing here touches the bitstream.
#
# The core reads the slot at boot and overwrites the image built into the
# bitstream. If the file is absent it runs the built-in one, so removing it is
# always a safe way back.
set -euo pipefail
cd "$(dirname "$0")/.."

VOL="${1:-/Volumes/ANALOGUE}"
DST="$VOL/Assets/pc98/hiroya.PC98"

make -C pcxt-base/src/firmware >/dev/null
echo "built $(stat -f%z pcxt-base/src/firmware/firmware.bin) bytes"

python3 scripts/check_osd_layout.py

[ -d "$DST" ] || { echo "no $DST -- put the Pocket into USB access mode"; exit 1; }
cp pcxt-base/src/firmware/firmware.bin "$DST/"
sync
cmp -s pcxt-base/src/firmware/firmware.bin "$DST/firmware.bin" \
    && echo "copied and verified" || { echo "VERIFY FAILED"; exit 1; }
diskutil eject "$VOL" >/dev/null 2>&1 && echo "ejected -- ready to test" \
                                      || echo "copied; eject by hand"
