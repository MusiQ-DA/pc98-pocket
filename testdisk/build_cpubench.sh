#!/usr/bin/env bash
# build_cpubench.sh -- pack FreeDOS(98) + CPUBENCH 0.980 into a PC-98 2HD raw
# floppy.  Same proven layout as build_egcview.sh: donor boot sector+BPB from
# neon125.hdm verbatim, 192-entry root, 0xE5 fill.
#
#   ./build_cpubench.sh   -> cpubench.hdm
#
# AUTOEXEC.BAT runs "CPUBENCH -p".  Result prints on screen:
#   "Ratio to the first PC9801 :  N.NN"  (V30@10MHz ~= 3.11, V30@5MHz ~= 1.34)
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ ! -f cpubench.lzh ]; then
    curl -fsSL -o cpubench.lzh "https://ftp.vector.co.jp/00/03/369/cpubench.lzh"
fi
7z x -y -o"$work" cpubench.lzh > /dev/null

CBDIR="$work" python3 - <<'PY'
import os, struct

SECTOR = 1024
CYL, HEADS, SPT = 77, 2, 8
TOTAL = CYL * HEADS * SPT * SECTOR
ROOT_ENTRIES, FAT_SECTORS, N_FATS = 192, 2, 2
ROOT_SECTORS = ROOT_ENTRIES * 32 // SECTOR    # 6
FIRST_DATA = 1 + N_FATS * FAT_SECTORS + ROOT_SECTORS  # sector 11 == cluster 2

img = open("neon125.hdm", "rb").read()
assert len(img) == TOTAL, "neon125.hdm is not raw 2HD"

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
            continue
        if e[:11] == name.encode("ascii"):
            first, size = struct.unpack_from("<H", e, 0x1A)[0], \
                          struct.unpack_from("<I", e, 0x1C)[0]
            data = b"".join(img[(FIRST_DATA + c - 2) * SECTOR:
                                (FIRST_DATA + c - 1) * SECTOR]
                            for c in fat12_chain(fat, first))
            return data[:size]
    raise SystemExit(f"{name} not in neon125.hdm")

kernel, command = grab("KERNEL  SYS"), grab("COMMAND COM")

cbdir = os.environ["CBDIR"]
files = [
    ("KERNEL  SYS", kernel),
    ("COMMAND COM", command),
    ("AUTOEXECBAT", b"@ECHO OFF\r\nCPUBENCH -p > RESULT.TXT\r\nTYPE RESULT.TXT\r\n"),
    ("CPUBENCHEXE", open(os.path.join(cbdir, "CPUBENCH.EXE"), "rb").read()),
    ("CPUBENCHDOC", open(os.path.join(cbdir, "CPUBENCH.DOC"), "rb").read()),
    ("CPURACE TXT", open(os.path.join(cbdir, "CPURACE.TXT"), "rb").read()),
]
assert all(len(n) == 11 for n, _ in files)

out = bytearray(b"\xE5" * TOTAL)
out[:SECTOR] = img[:SECTOR]
assert struct.unpack_from("<H", out, 0x0B)[0] == SECTOR
assert out[0x0D] == 1

nfat = bytearray(FAT_SECTORS * SECTOR)
nfat[0:3] = b"\xFE\xFF\xFF"
nroot = bytearray(ROOT_SECTORS * SECTOR)

stamp = struct.pack("<HH", 0, ((2026 - 1980) << 9) | (10 << 5) | 2)
cluster = 2
for slot, (name, data) in enumerate(files):
    n = max(1, -(-len(data) // SECTOR))
    size = len(data)
    data = data + b"\x00" * (n * SECTOR - size)
    for k in range(n):
        c, val = cluster + k, 0xFFF if k == n - 1 else cluster + k + 1
        e = c + c // 2
        if c & 1:
            nfat[e] = (nfat[e] & 0x0F) | ((val << 4) & 0xF0)
            nfat[e + 1] = (val >> 4) & 0xFF
        else:
            nfat[e] = val & 0xFF
            nfat[e + 1] = (nfat[e + 1] & 0xF0) | ((val >> 8) & 0x0F)
        dst = (FIRST_DATA + c - 2) * SECTOR
        out[dst:dst + SECTOR] = data[k * SECTOR:(k + 1) * SECTOR]
    e = nroot[slot * 32:(slot + 1) * 32]
    e[0:11] = name.encode("ascii")
    e[11] = 0x20
    e[22:26] = stamp
    struct.pack_into("<H", e, 0x1A, cluster)
    struct.pack_into("<I", e, 0x1C, size)
    nroot[slot * 32:(slot + 1) * 32] = e
    cluster += n

for f in range(N_FATS):
    base = (1 + f * FAT_SECTORS) * SECTOR
    out[base:base + len(nfat)] = nfat
out[(1 + N_FATS * FAT_SECTORS) * SECTOR:FIRST_DATA * SECTOR] = nroot

open("cpubench.hdm", "wb").write(out)
print("cpubench.hdm: %d bytes, %d files, %d clusters used"
      % (len(out), len(files), cluster - 2))
PY
ls -la cpubench.hdm
