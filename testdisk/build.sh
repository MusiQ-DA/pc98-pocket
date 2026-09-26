#!/usr/bin/env bash
# build.sh -- assemble draw_test.asm and pack it into a PC-98 2HD raw floppy.
#
#   draw_test.bin  the boot sector (sector 0, <= 1024 bytes)
#   draw_test.hdm  raw 2HD image: 77 cyl x 8 spt x 2 head x 1024 B = 1,261,568 B
#
# The core serves a raw image straight off the card (fdd_service.c) and the
# boot sim reads it byte-for-byte through +fddimg=<path>. 2HD sectors are
# 1024 bytes, so the code lives in the first sector and the rest is filler.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

nasm -f bin -o draw_test.bin draw_test.asm

size=$(stat -f%z draw_test.bin)
# The BIOS hands the boot sector to 1FE0:0000 via one FDC/DMA read. Only the
# low 512 bytes are guaranteed to land (the read's transfer count), so the
# whole program -- code, the plane table and the strings -- must fit there.
# 2HD sectors are 1024 bytes but a guest that relies on bytes past 0x200 would
# silently run on an image the BIOS never fully delivered.
if [ "$size" -gt 512 ]; then
    echo "draw_test.bin is $size bytes -- over the 512-byte IPL window" >&2
    exit 1
fi

python3 - <<'PY'
SECTOR = 1024
TOTAL  = 77 * 8 * 2 * SECTOR            # 1,261,568 bytes of raw 2HD
code = open("draw_test.bin", "rb").read()
img  = bytearray(b"\xE5" * TOTAL)       # unwritten sectors read as 0xE5
img[:len(code)] = code
open("draw_test.hdm", "wb").write(img)
print("draw_test.hdm: %d bytes (code %d)" % (len(img), len(code)))
PY
