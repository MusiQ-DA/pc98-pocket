#!/bin/bash
# package.sh — assemble the openFPGA SD-card tree + release zip.
# Usage: bash scripts/package.sh   (requires src/fpga/output_files/ap_core.rbf)
set -eu
cd "$(dirname "$0")/.."

AUTHOR="hiroya"
CORE="PC98"
PLATFORM="pc98"
RBF="src/fpga/output_files/ap_core.rbf"
DEST="dist/Cores/${AUTHOR}.${CORE}"

[ -f "$RBF" ] || { echo "ERROR: $RBF not found (run CI build or local quartus_asm first)"; exit 1; }

mkdir -p "$DEST" "dist/Platforms" "dist/Assets/${PLATFORM}/common"

# JSONs: normalize to LF + final newline, ship as CRLF (Pocket parser convention)
for f in core.json video.json audio.json data.json input.json interact.json variants.json; do
    python3 -c "
import sys
d = open(sys.argv[1], 'rb').read().replace(b'\r\n', b'\n')
if not d.endswith(b'\n'): d += b'\n'
open(sys.argv[2], 'wb').write(d.replace(b'\n', b'\r\n'))
" "$f" "$DEST/$f"
done

# platform metadata
cp Platforms_pc98.json "dist/Platforms/${PLATFORM}.json"

# bit-reverse every byte -> bitstream.rbf_r
python3 - "$RBF" "$DEST/bitstream.rbf_r" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
table = bytes(int(format(b, '08b')[::-1], 2) for b in range(256))
data = open(src, 'rb').read()
open(dst, 'wb').write(data.translate(table))
print("bit-reversed %d bytes" % len(data))
PY

# release zip
cd dist && rm -f "${AUTHOR}.${CORE}.zip" && zip -qr "${AUTHOR}.${CORE}.zip" Cores Platforms Assets && cd ..
echo "packaged: dist/${AUTHOR}.${CORE}.zip"
echo
echo "SD card layout:"
echo "  /Cores/${AUTHOR}.${CORE}/            <- from the zip"
echo "  /Platforms/${PLATFORM}.json          <- from the zip"
echo "  /Assets/${PLATFORM}/common/bios.rom  (96KB, np2互換)"
echo "  /Assets/${PLATFORM}/common/font.rom  (np2互換 FONT.ROM)"
