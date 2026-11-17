#!/bin/bash
# build_fm.sh -- assemble fmch_test.asm into a raw 2HD .hdm boot image.
# Same recipe as build.sh (draw_test): nasm boot sector, must fit in the
# 512 bytes the BIOS guarantees delivered, padded to a full 2HD image.
set -e
cd "$(dirname "$0")"

nasm -f bin -o fmch_test.bin fmch_test.asm

size=$(stat -f%z fmch_test.bin)
if [ "$size" -gt 512 ]; then
    echo "fmch_test.bin is $size bytes -- over the 512-byte boot limit" >&2
    exit 1
fi
echo "fmch_test.bin: $size bytes"

python3 - <<'EOF'
img = bytearray([0xE5]) * (77 * 8 * 2 * 1024)   # 2HD: 77 cyl x 8 sect x 2 head x 1024 B
boot = open('fmch_test.bin', 'rb').read()
assert len(boot) <= 1024
img[0:len(boot)] = boot
open('fmch_test.hdm', 'wb').write(img)
print('fmch_test.hdm:', len(img), 'bytes')
EOF
