#!/usr/bin/env bash
# build_adrive_hdd.sh -- a bootable SCSI hard disk from a backup of a PC-98
# A: drive that carries its own NEC MS-DOS 5/6 (IO.SYS / MSDOS.SYS /
# COMMAND.COM in the root).
#
#   testdisk/build_adrive_hdd.sh <adrive dir> [out.nhd]
#
# The drive's files are the user's own (and their own licensed MS-DOS); they
# are NEVER committed and nothing is downloaded but the FreeDOS(98) release
# disk the IPL / partition loader come from. Images land outside the repo by
# default (testdisk/adrive*.nhd / *.hdn are gitignored anyway).
#
# Disk: T98-Next NHD, 512-byte sectors, 3600 cyl x 8 heads x 17 spt -- np21w's
# hddsize2CHS tier for a 240 MB disk (C = MB x 15, 8 x 17) -- 489,600 sectors,
# 250,675,200 bytes + 512-byte header; FAT16 with 4 KB clusters. The same body
# is also written as <out>.hdd (Virtual98 VHD): np2kai mounts .hdd as a SCSI
# disk (DA/UA A0h), the class the core's -55 ROM serves. The core takes both.
#
#   LBA 0      btnpart IPL (public domain)
#   LBA 1      PC-98 partition table, entry 0 = the DOS partition, cyl 1..3599
#   LBA 136    FreeDOS(98) FAT16 HD loader (GPL) with its file name patched to
#              "IO      SYS": it loads IO.SYS to 0060:0000 and enters it with
#              SI = the boot partition's table offset, the NEC DOS 5+ hand-off
#              (IO.SYS stores SI at its init, then matches it against the table)
#
# IO.SYS, MSDOS.SYS, COMMAND.COM go in first (root entries 1-3, contiguous from
# cluster 2, IO.SYS / MSDOS.SYS read-only+hidden+system), as SYS.COM places them.
# The backup's CONFIG.SYS loads C:\WINDOWS\HIMEM / EMM386 / NECCDM, which are not
# on this disk and EMM386 needs a 386 (the core is a 286): it is kept as
# CONFIG.ORG, and a minimal 286-safe CONFIG.SYS + AUTOEXEC.BAT (the backup had
# only AUTOEXEC.BAK) boot to an A:\> prompt with the DOS tools on PATH.
# .DS_Store / ._* / @eaDir and other NAS metadata are left out; long Windows 95
# names keep VFAT entries (DOS sees the ~N alias).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

src="${1:?usage: $0 <adrive dir> [out.nhd]}"
out="${2:-${CLAUDE_JOB_DIR:-/tmp}/adrive.nhd}"
for f in IO.SYS MSDOS.SYS COMMAND.COM; do
    [ -f "$src/$f" ] || { echo "$src: no $f -- not a DOS system drive" >&2; exit 1; }
done

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

cat > "$work/CONFIG.SYS" <<'EOF'
REM PC-98 Pocket (80286): minimal CONFIG.SYS. The original is CONFIG.ORG.
FILES=30
BUFFERS=20
LASTDRIVE=Z
SHELL=A:\COMMAND.COM A:\ /P /E:1024
REM XMS + HMA on the 286 (needs extended memory fitted):
REM DEVICE=A:\DOS\HIMEM.SYS
REM DOS=HIGH
EOF

cat > "$work/AUTOEXEC.BAT" <<'EOF'
@ECHO OFF
REM PC-98 Pocket: minimal AUTOEXEC.BAT. The old one is AUTOEXEC.BAK.
PATH A:\DOS;A:\DOSUTL;A:\DOSUTL\TOOL;A:\MS-C\BIN
SET TEMP=A:\TEMP
SET TMP=A:\TEMP
PROMPT $P$G
VER
EOF

renames=()
[ -f "$src/CONFIG.SYS" ] && renames+=(--rename CONFIG.SYS=CONFIG.ORG)
[ -f "$src/AUTOEXEC.BAT" ] && renames+=(--rename AUTOEXEC.BAT=AUTOEXEC.ORG)
for f in CONFIG.ORG AUTOEXEC.ORG; do
    [ ! -e "$src/$f" ] || { echo "$src/$f exists -- would clash" >&2; exit 1; }
done

python3 -I "$here/mkpc98hdd.py" --fd98-zip "$zip" --system msdos \
    --cyls 3600 --heads 8 --spt 17 \
    --nhd "$out" --vhd "${out%.*}.hdd" \
    --tree "$src"=/ "${renames[@]}" \
    --text CONFIG.SYS="$work/CONFIG.SYS" \
    --text AUTOEXEC.BAT="$work/AUTOEXEC.BAT" \
    --part-name "MS-DOS 6.20" --label ADRIVE --comment "PC-98 Pocket A: drive"
