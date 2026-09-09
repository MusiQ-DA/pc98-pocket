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
DST="$VOL/Assets/pc98/hiroya.PC9801"

# Apple's clang cannot assemble start.S -- it rejects the cc1as flag its own
# driver passes for -march=rv32im -- so build with Homebrew's LLVM when it is
# installed. ld.lld/llvm-objcopy come from there anyway.
for d in /opt/homebrew/opt/llvm/bin /usr/local/opt/llvm/bin; do
    [ -x "$d/clang" ] && { PATH="$d:$PATH"; break; }
done
make -C pcxt-base/src/firmware >/dev/null
echo "built $(stat -f%z pcxt-base/src/firmware/firmware.bin) bytes"

# Same check the deploy makes: firmware.vh is committed and CI verifies it
# against its sources, so a binary that disagrees with it is stale.
python3 - <<'PY' || { echo "firmware.bin is stale against firmware.vh"; exit 1; }
import sys
b = open('pcxt-base/src/firmware/firmware.bin', 'rb').read()
v = open('pcxt-base/src/firmware/firmware.vh').read().split()
vb = bytearray()
for w in v:
    vb += int(w, 16).to_bytes(4, 'little')
sys.exit(0 if b == bytes(vb[:len(b)]) else 1)
PY

python3 scripts/check_osd_layout.py

[ -d "$DST" ] || { echo "no $DST -- put the Pocket into USB access mode"; exit 1; }
cp pcxt-base/src/firmware/firmware.bin "$DST/"
sync
cmp -s pcxt-base/src/firmware/firmware.bin "$DST/firmware.bin" \
    && echo "copied and verified" || { echo "VERIFY FAILED"; exit 1; }
diskutil eject "$VOL" >/dev/null 2>&1 && echo "ejected -- ready to test" \
                                      || echo "copied; eject by hand"
