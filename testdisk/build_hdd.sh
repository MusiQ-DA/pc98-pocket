#!/usr/bin/env bash
# build_hdd.sh -- assemble hdd_test.asm and pack it into a raw SCSI HDD
# test image for the Hard Disk dataslot.
#
#   hdd_test.bin  the IPL (<= 512 bytes; scsi_rom.asm loads two sectors at
#                 LBA 0 to 1FC0:0000 and executes offset 0)
#   hdd_test.hdd  raw image: 256 cyl x 8 heads x 25 spt x 512 B = 26,214,400 B
#
# The SCSI service (firmware/scsi_service.c) serves the file as flat
# 512-byte sectors -- lba*512 straight into target-dataslot reads, with no
# .hdi/.nhd header parsing. The option ROM reports 8 surfaces x 25 spt and
# cylinders = sectors/200 (and ignores images under 200 sectors), so the
# size here is a whole number of cylinders: READ CAPACITY answers 51199.
#
# Mount requires only a non-empty slot (main.c: sectors = slot_bytes(5)/512).
# On the Pocket, copy hdd_test.hdd to Assets/pc98/common/ and pick it via
# the framework menu -> Hard Disk; the pick reloads the core and the ROM's
# POST probe then mounts and boots it. Proof on screen: "SCSI HDD IPL OK".
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

nasm -f bin -o hdd_test.bin hdd_test.asm

size=$(stat -f%z hdd_test.bin)
# scsi_rom.asm post_boot lands TWO sectors (0x400 bytes) at 1FC0:0000, but
# keeping the IPL inside the first 512 bytes means nothing depends on the
# second sector arriving.
if [ "$size" -gt 512 ]; then
    echo "hdd_test.bin is $size bytes -- over the 512-byte IPL budget" >&2
    exit 1
fi

python3 - <<'PY'
SECTOR = 512
CYL, HEADS, SPT = 256, 8, 25
TOTAL = CYL * HEADS * SPT * SECTOR          # 26,214,400 bytes = 51,200 sectors
code = open("hdd_test.bin", "rb").read()
img  = bytearray(TOTAL)                     # unwritten sectors read as 0
img[:len(code)] = code
open("hdd_test.hdd", "wb").write(img)
print("hdd_test.hdd: %d bytes (%d cyl x %d heads x %d spt, code %d)"
      % (len(img), CYL, HEADS, SPT, len(code)))
PY
