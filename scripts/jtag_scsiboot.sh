#!/usr/bin/env bash
# jtag_scsiboot.sh -- hardware check that a SCSI HDD image boots on the
# PC-9801-55 path: read back testdisk/hdd_test.*'s results over JTAG.
#
# Before running (the HDD reaches the core through the Hard Disk data slot,
# i.e. the SD card -- there is no JTAG upload path for it):
#   1. testdisk/build_hdd.sh                (hdd_test.hdn / .nhd / .hdi)
#   2. copy them to the card's Assets/pc98/common/
#   3. on the Pocket: launch hiroya.PC9801, Core Settings -> Hard Disk ->
#      hdd_test.hdn. Picking a disk RELOADS the core from the card (the
#      pick persists, data.json 0x201), so pick BEFORE flashing -- a pick
#      after the flash would throw the JTAG image away. Eject the floppies
#      (or set OSD Boot Device = SCSI HD): the BIOS boots floppies first.
#   4. while that freshly launched core runs, flash the CI build:
#        scripts/jtag_flash.sh path/to/ap_core.sof
#      (a fresh launch is what makes APF re-stream the slots after the flash;
#      PC stuck at FFFF0 means it did not -- relaunch and flash again)
#   5. wait ~10 s, then:  scripts/jtag_scsiboot.sh --expect hdn
# Repeat 3-5 with hdd_test.nhd / hdd_test.hdi (--expect nhd / hdi).
#
# Exit 0 when the IPL reports PASS. Expected output for hdd_test.hdn:
#   SCSI_WITNESS media=1 ... posts>=8 romreads>0
#   BIOS 482=01 584=a0 4D2=c2 4B2=d2 4BA=d2 geo=19 08 80 90 totals=00006400
#   VERDICT PASS
#   ROW0 |SCSI HDD IPL OK ...|
#   ROW1 |AX=00A0 584=A0 482=01 C=0080 H=08 S=19 B=0200 ...|
#   ROW2 |CHS=00/01 LBA=00/01 WR=00/01  PASS ...|
# (.nhd: C=00C8 H=08 S=11; .hdi: C=0078 H=08 S=20 -- the header's geometry.)
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

EXPECT=""
if [ "${1:-}" = "--expect" ]; then EXPECT="$2"; fi

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
openocd -f scripts/jtag_probe.cfg -f scripts/jtag_scsiboot.tcl 2>&1 \
    | grep -E '^(SCSI_WITNESS|BIOS|RESULT|VERDICT|ROW)' | tee "$LOG"

case "$EXPECT" in
    hdn) want="C=0080 H=08 S=19" ;;
    nhd) want="C=00C8 H=08 S=11" ;;
    hdi) want="C=0078 H=08 S=20" ;;
    *)   want="" ;;
esac
if [ -n "$want" ] && ! grep -q "$want" "$LOG"; then
    echo "geometry on screen is not the $EXPECT image's ($want)"
    exit 1
fi
grep -q '^VERDICT PASS' "$LOG"
