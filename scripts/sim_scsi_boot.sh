#!/usr/bin/env bash
# sim_scsi_boot.sh -- boot the real bios.rom on z86 in tb_pc98_boot with the
# PC-9801-55 board fitted: the assembled fpga/scsi_rom.asm at D2000, the
# real pc98_scsi window at 0xCC0, and tb_scsi_target serving a test image
# laid out the way the shipped firmware mounts it (scsi_fw_host probe).
#
#   scripts/sim_scsi_boot.sh [hdn|nhd|hdi] [+plusarg ...]
#
# The image is testdisk/build_hdd.sh --sim's: hdd_test.asm as the IPL, a
# "GEO!" stamp in the last sector of the format's own C x H x S. Pass when
# the log ends in "SCSI IPL VERDICT: PASS" -- the BIOS sweep reached
# entry 0x15 with AL=0C, the IPL ran with AX=00A0, [584]=A0, [482] bit 0
# set, and INT 1Bh sense / CHS read / LBA read / write+readback all agreed
# with the image. Add +fddimg=testdisk/fdc_ipl.hdm +media=1 to check the
# boot ORDER instead: the floppy's IPL must come first ([584]=90).
#
# Not part of CI: needs bios.rom (and the run takes tens of minutes).
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FMT=hdn
case "${1:-}" in hdn|nhd|hdi) FMT=$1; shift ;; esac

OUT="${SIM_OUT:-${TMPDIR:-/tmp}/pc98scsiboot}"
mkdir -p "$OUT"
bash testdisk/build_hdd.sh --sim "$OUT/img"
SIM_OUT="$OUT" bash scripts/sim_scsi_fw.sh selftest
IMG="$(cd "$OUT/img" && pwd)/hdd_test.$FMT"     # the bench runs from $OUT/boot
GEO=$("$OUT/scsi_fw_host" probe "$IMG")
echo "firmware mounts $IMG as: $GEO"
eval "$GEO"     # base= cyl= heads= spt= sectors=

SIM_OUT="$OUT/boot" exec bash scripts/sim_pc98_boot.sh --z86 \
    +hddimg="$IMG" +hdd_base="$base" +hdd_c="$cyl" +hdd_h="$heads" \
    +hdd_s="$spt" +hdd_n="$sectors" "$@"
