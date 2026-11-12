#!/usr/bin/env bash
# build_puyo2_hdd.sh -- a bootable FreeDOS(98) SCSI hard disk carrying
# Puyo Puyo 2 (ぷよぷよ通, Compile 1995, "PC-9821 / PC AT" edition).
#
#   testdisk/build_puyo2_hdd.sh <PUYO2 game dir> [out.nhd]
#
# The game (~6 MB, 402 files) is far past a 1.2 MB floppy, so it rides on the
# Hard Disk slot instead. The game files are the user's own and are NEVER
# committed: pass the directory, the image lands outside the repo by default
# (testdisk/*.nhd / *.hdn are gitignored in case it is pointed here).
#
# Disk: T98-Next NHD, 512-byte sectors, 410 cyl x 8 heads x 25 spt
# (82,000 sectors, 41,984,000 bytes + 512-byte header). 8 x 25 is np21w's
# flat .hdn geometry, so the same body is also written as <out>.hdn: np2kai
# mounts .hdn as a SCSI disk (DA/UA A0h), the path the core's -55 ROM serves,
# and the core mounts either (firmware/scsi_service.c scsi_probe).
#
#   LBA 0      btnpart IPL (public domain)       -> loads the partition IPL
#   LBA 1      PC-98 partition table, entry 0 = FreeDOS(98) FAT16, cyl 1..409
#   LBA 200    FreeDOS(98) FAT16 HD loader (GPL) -> KERNEL.SYS by LBA
#
# Pieces come from the FreeDOS(98) release disk (github.com/lpproj/fdkernel,
# release test-20220120-cherrypick, fd98_hd_250m_20220123.zip, GPL-2.0;
# the btnpart IPL is sava/LP-Project's, public domain) -- fetched once into
# testdisk/.cache and pinned by sha256. testdisk/mkpc98hdd.py does the layout.
#
# CONFIG.SYS has a boot menu (3 s, default 1):
#   1  80286: FDXMS286 only -- the PC-98 Pocket core (a 286, no EMS)
#   2  386+:  HIMEMX + EMM386 (EMS) -- what the game actually needs
# AUTOEXEC.BAT: CD \PUYO2, PP2 /98 /TF (PC-9821 mode, no RS-232C link).
# PUYO2_MENU=2 makes entry 2 the default (np2kai with a 386 CPU).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

game="${1:?usage: $0 <PUYO2 dir> [out.nhd]}"
out="${2:-${CLAUDE_JOB_DIR:-/tmp}/puyo2.nhd}"
[ -f "$game/PP2.COM" ] || { echo "$game: no PP2.COM -- not the PUYO2 dir" >&2; exit 1; }
menu="${PUYO2_MENU:-1}"

zip_url=https://github.com/lpproj/fdkernel/releases/download/test-20220120-cherrypick/fd98_hd_250m_20220123.zip
zip_sha=5df59f6a5823e3b51f08f7ccc59de5220219df9b580afcd7fd269abba60a77c9
cache="$here/.cache"
zip="$cache/fd98_hd_250m_20220123.zip"
mkdir -p "$cache"
if [ ! -f "$zip" ]; then
    curl -fL -o "$zip.part" "$zip_url"
    mv "$zip.part" "$zip"
fi
echo "$zip_sha  $zip" | shasum -a 256 -c - >/dev/null || {
    echo "$zip: sha256 mismatch" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/CONFIG.SYS" <<EOF
MENU
MENU   PC-98 Pocket: Puyo Puyo 2 HDD (FreeDOS(98))
MENU
MENU    1   80286  XMS only (PC-98 Pocket core; no EMS)
MENU    2   386+   XMS + EMM386 EMS (PC-9821 / np21)
MENU
MENUDEFAULT=$menu,3
FILES=30
BUFFERS=20
LASTDRIVE=Z
DOS=HIGH
1?DEVICE=\\FDOS\\BIN\\FDXMS286.SYS
2?DEVICE=\\FDOS\\BIN\\HIMEMX.EXE
2?DEVICE=\\FDOS\\BIN\\EMM386.EXE RAM FRAME=C000
SHELL=\\COMMAND.COM \\ /E:512 /P
EOF

cat > "$work/AUTOEXEC.BAT" <<'EOF'
@ECHO OFF
SET DOSDIR=\FDOS
PATH \FDOS\BIN
CD \PUYO2
PP2 /98 /TF
EOF

hdn="${out%.*}.hdn"
python3 -I "$here/mkpc98hdd.py" --fd98-zip "$zip" --system freedos \
    --cyls 410 --heads 8 --spt 25 \
    --nhd "$out" --hdn "$hdn" \
    --text CONFIG.SYS="$work/CONFIG.SYS" \
    --text AUTOEXEC.BAT="$work/AUTOEXEC.BAT" \
    --tree "$game"=PUYO2 \
    --part-name "FreeDOS(98)"
