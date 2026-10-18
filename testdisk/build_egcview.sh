#!/usr/bin/env bash
# build_egcview.sh -- pack FreeDOS(98) + EGCVIEW into a PC-98 2HD raw floppy.
#
#   egcview.hdm  raw 2HD image: 77 cyl x 8 spt x 2 head x 1024 B = 1,261,568 B,
#                FAT12 with 1024-byte sectors (N=3), booting FreeDOS(98)
#
# The boot sector and KERNEL.SYS / COMMAND.COM are lifted out of the committed
# neon125.hdm (itself a FreeDOS(98) disk); that boot code walks the root dir for
# "KERNEL  SYS" and follows the FAT chain, so a freshly laid-out filesystem
# boots the same. EGCVIEW (Natori Takayasu, Vector se017791 -- an EGC drawing
# demo needs EGC-equipped PC-9801 + MS-DOS 3.x) is fetched from Vector and
# dropped in beside DOS, and AUTOEXEC.BAT launches EGCVIEW.EXE; ESC quits back
# to the A:\> prompt (per EGCVIEW.DOC).
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -f egcview.lzh ]; then
    curl -fsSL -o egcview.lzh "https://ftp.vector.co.jp/01/77/369/egcview.lzh"
fi
7z x -y -o"$work" egcview.lzh > /dev/null

EGCDIR="$work" python3 - <<'PY'
import os, struct

SECTOR = 1024
CYL, HEADS, SPT = 77, 2, 8
TOTAL = CYL * HEADS * SPT * SECTOR            # 1,261,568 bytes of raw 2HD
ROOT_ENTRIES, FAT_SECTORS, N_FATS = 192, 2, 2
ROOT_SECTORS = ROOT_ENTRIES * 32 // SECTOR    # 6
FIRST_DATA = 1 + N_FATS * FAT_SECTORS + ROOT_SECTORS  # sector 11 == cluster 2

img = open("neon125.hdm", "rb").read()
assert len(img) == TOTAL, "neon125.hdm is not raw 2HD"

# --- pull KERNEL.SYS / COMMAND.COM out of neon125.hdm's FAT12 -----------------
def fat12_chain(fat, first):
    out, c = [], first
    while 2 <= c < 0xFF0:
        out.append(c)
        e = c + c // 2
        w = fat[e] | (fat[e + 1] << 8)
        c = (w >> 4) & 0xFFF if c & 1 else w & 0xFFF
    return out

fat = img[SECTOR:SECTOR * (1 + FAT_SECTORS)]
root = img[SECTOR * (1 + N_FATS * FAT_SECTORS):SECTOR * FIRST_DATA]
def grab(name):
    for i in range(0, len(root), 32):
        e = root[i:i + 32]
        if e[0] == 0x00:
            break
        if e[0] == 0xE5 or (e[11] & 0x18):
            continue                    # deleted, dir or volume label
        if e[:11] == name.encode("ascii"):
            first, size = struct.unpack_from("<H", e, 0x1A)[0], \
                          struct.unpack_from("<I", e, 0x1C)[0]
            data = b"".join(img[(FIRST_DATA + c - 2) * SECTOR:
                                (FIRST_DATA + c - 1) * SECTOR]
                            for c in fat12_chain(fat, first))
            return data[:size]
    raise SystemExit(f"{name} not in neon125.hdm")

kernel, command = grab("KERNEL  SYS"), grab("COMMAND COM")

egcdir = os.environ["EGCDIR"]
files = [
    ("KERNEL  SYS", kernel),
    ("COMMAND COM", command),
    ("AUTOEXECBAT", b"@ECHO OFF\r\nECHO EGCVIEW -- ESC quits to DOS; EGCVIEW /? shows options\r\nEGCVIEW\r\n"),
    ("EGCVIEW EXE", open(os.path.join(egcdir, "EGCVIEW.EXE"), "rb").read()),
    ("EGCVIEW DOC", open(os.path.join(egcdir, "EGCVIEW.DOC"), "rb").read()),
    ("EGCVIEW SPE", open(os.path.join(egcdir, "EGCVIEW.SPE"), "rb").read()),
]
assert all(len(n) == 11 for n, _ in files)

# --- lay out a fresh FAT12 ----------------------------------------------------
out = bytearray(b"\xE5" * TOTAL)
out[:SECTOR] = img[:SECTOR]                   # boot sector, BPB included
assert struct.unpack_from("<H", out, 0x0B)[0] == SECTOR
assert out[0x0D] == 1                         # one 1024-byte sector per cluster

nfat = bytearray(FAT_SECTORS * SECTOR)
nfat[0:3] = b"\xFE\xFF\xFF"                   # media descriptor + reserved
nroot = bytearray(ROOT_SECTORS * SECTOR)

# DOS date 1995-04-29 (EGCVIEW's own stamp), time 12:00
stamp = struct.pack("<HH", 0, ((1995 - 1980) << 9) | (4 << 5) | 29)
cluster = 2
for slot, (name, data) in enumerate(files):
    n = max(1, -(-len(data) // SECTOR))
    size = len(data)
    data = data + b"\x00" * (n * SECTOR - size)
    for k in range(n):
        c, val = cluster + k, 0xFFF if k == n - 1 else cluster + k + 1
        e = c + c // 2
        if c & 1:   # odd entry: high nibble of byte e, all of byte e+1
            nfat[e] = (nfat[e] & 0x0F) | ((val << 4) & 0xF0)
            nfat[e + 1] = (val >> 4) & 0xFF
        else:       # even entry: all of byte e, low nibble of byte e+1
            nfat[e] = val & 0xFF
            nfat[e + 1] = (nfat[e + 1] & 0xF0) | ((val >> 8) & 0x0F)
        dst = (FIRST_DATA + c - 2) * SECTOR
        out[dst:dst + SECTOR] = data[k * SECTOR:(k + 1) * SECTOR]
    e = nroot[slot * 32:(slot + 1) * 32]
    e[0:11] = name.encode("ascii")
    e[11] = 0x20                              # archive
    e[22:26] = stamp
    struct.pack_into("<H", e, 0x1A, cluster)
    struct.pack_into("<I", e, 0x1C, size)
    nroot[slot * 32:(slot + 1) * 32] = e
    cluster += n

for f in range(N_FATS):
    base = (1 + f * FAT_SECTORS) * SECTOR
    out[base:base + len(nfat)] = nfat
out[(1 + N_FATS * FAT_SECTORS) * SECTOR:FIRST_DATA * SECTOR] = nroot

open("egcview.hdm", "wb").write(out)
print("egcview.hdm: %d bytes, %d files, %d clusters used"
      % (len(out), len(files), cluster - 2))
PY
