#!/usr/bin/env bash
# build_hdd.sh -- assemble hdd_test.asm and pack it into SCSI HDD test images
# for the Hard Disk dataslot, one per format the firmware mounts
# (firmware/scsi_service.c, scsi_probe -- np21w fdd/sxsihdd.c's set):
#
#   hdd_test.hdn  flat, no header: np21w's -55 geometry 8 heads x 25 spt,
#                 128 cylinders                        (25600 sectors, 12.5 MB)
#   hdd_test.nhd  T98-Next: 512-byte header, 200 cyl x 8 heads x 17 spt
#                                                      (27200 sectors, 13.3 MB)
#   hdd_test.hdi  Anex86: 4096-byte header, 120 cyl x 8 heads x 32 spt
#                                                      (30720 sectors, 15 MB)
#
# Each image carries the IPL (hdd_test.bin, up to two sectors at LBA 0 --
# scsi_rom.asm loads 1024 bytes to 1FC0:0000), a "GEO!" + LBA stamp in the
# LAST sector of its C x H x S, and scratch at LBA 2 the IPL writes and puts
# back. The three geometries differ on purpose: the IPL's CHS read of
# C-1/H-1/S-1 only finds the stamp when the ROM uses the image's own
# geometry, which is the header path the flat-only firmware used to lack.
#
#   testdisk/build_hdd.sh            the three images above, in testdisk/
#   testdisk/build_hdd.sh --sim DIR  small ones for scripts/sim_scsi_boot.sh
#                                    (the bench holds 8 MB of image)
#
# On the Pocket: copy one to Assets/pc98/common/ on the SD card, pick it in
# the core's menu -> Hard Disk, and see scripts/jtag_scsiboot.sh for the
# check. Proof on screen: row 0 "SCSI HDD IPL OK", row 2 ending "PASS".
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OUT=.
SIM=0
if [ "${1:-}" = "--sim" ]; then
    SIM=1
    OUT="$2"
    mkdir -p "$OUT"
fi

nasm -f bin -o "$OUT/hdd_test.bin" hdd_test.asm

SIM="$SIM" OUT="$OUT" python3 - <<'PY'
import os, struct
out, sim = os.environ["OUT"], os.environ["SIM"] == "1"
code = open(os.path.join(out, "hdd_test.bin"), "rb").read()
assert len(code) <= 1024, "IPL over two sectors"

def body(c, h, s):
    n = c * h * s
    img = bytearray(n * 512)
    img[:len(code)] = code
    img[2*512:2*512+4] = b"SCR!"
    last = n - 1
    img[last*512:last*512+8] = b"GEO!" + struct.pack("<I", last)
    return img

def emit(name, data):
    p = os.path.join(out, name)
    open(p, "wb").write(data)
    print("%-14s %9d bytes" % (name, len(data)))

# Sizes: full images for the card, a few MB each for the bench.
flat_c, nhd, hdi = (20, (40, 8, 17), (24, 8, 32)) if sim else \
                   (128, (200, 8, 17), (120, 8, 32))

emit("hdd_test.hdn", body(flat_c, 8, 25))

c, h, s = nhd
hdr = bytearray(512)
hdr[0:15] = b"T98HDDIMAGE.R0\0"
hdr[0x10:0x10+28] = b"PC-98 Pocket SCSI test image"
struct.pack_into("<IIHHH", hdr, 0x110, 512, c, h, s, 512)
emit("hdd_test.nhd", bytes(hdr) + body(c, h, s))

c, h, s = hdi
b = body(c, h, s)
hdr = bytearray(4096)
struct.pack_into("<8I", hdr, 0, 0, 0, 4096, len(b), 512, s, h, c)
emit("hdd_test.hdi", bytes(hdr) + b)
PY
