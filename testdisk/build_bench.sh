#!/usr/bin/env bash
# build_bench.sh -- assemble bench.asm and pack it into a PC-98 2HD raw floppy.
#
#   bench.bin  flat image: 1024 B stage1 (sector C0/H0/R1, landed at
#              1FE0:0000 by the BIOS) + stage2 (sectors C0/H0/R2..R8,
#              loaded by stage1 through INT 1Bh to 0x2000:0000)
#   bench.hdm  raw 2HD image: 77 cyl x 8 spt x 2 head x 1024 B = 1,261,568 B
#
# bench.hdm is a build artifact -- do NOT commit it.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NASM=/opt/homebrew/bin/nasm
[ -x "$NASM" ] || NASM=nasm

"$NASM" -f bin -o bench.bin bench.asm

size=$(stat -f%z bench.bin)
# stage1 must fit the 512-byte window the BIOS actually delivers; the check
# below is on the full sector (1024 B) because only the low 512 bytes are
# guaranteed -- bench.asm enforces that itself via bench_done at 0x100.
# stage2 lives in sectors R2..R8 -> max 7*1024 bytes past the first sector.
if [ "$size" -gt 8192 ]; then
    echo "bench.bin is $size bytes -- over the 7168+1024 stage limit" >&2
    exit 1
fi
if [ "$size" -lt 1025 ]; then
    echo "bench.bin is $size bytes -- missing the stage2 section" >&2
    exit 1
fi

python3 - <<'PY'
SECTOR = 1024
TOTAL  = 77 * 8 * 2 * SECTOR            # 1,261,568 bytes of raw 2HD
code = open("bench.bin", "rb").read()
img  = bytearray(b"\xE5" * TOTAL)       # unwritten sectors read as 0xE5
img[:len(code)] = code
open("bench.hdm", "wb").write(img)
print("bench.hdm: %d bytes (code %d)" % (len(img), len(code)))
PY
