#!/bin/bash
# build_fm.sh -- assemble fm_test.asm into a raw 2HD .hdm boot image.
# Same recipe as build.sh (draw_test): nasm boot sector, must fit in the
# 512 bytes the BIOS guarantees delivered, padded to a full 2HD image.
set -e
cd "$(dirname "$0")"

nasm -f bin -o fm_test.bin fm_test.asm

size=$(stat -f%z fm_test.bin)
if [ "$size" -gt 512 ]; then
    echo "fm_test.bin is $size bytes -- over the 512-byte boot limit" >&2
    exit 1
fi
echo "fm_test.bin: $size bytes"

python3 - <<'EOF'
img = bytearray([0xE5]) * (77 * 8 * 2 * 1024)   # 2HD: 77 cyl x 8 sect x 2 head x 1024 B
boot = open('fm_test.bin', 'rb').read()
assert len(boot) <= 1024
img[0:len(boot)] = boot
open('fm_test.hdm', 'wb').write(img)
print('fm_test.hdm:', len(img), 'bytes')
EOF
