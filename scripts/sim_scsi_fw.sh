#!/usr/bin/env bash
# sim_scsi_fw.sh -- build the shipped firmware/scsi_service.c for the host
# (sim/host/scsi_fw_host.cpp models the pc98_scsi window and the dataslot
# engine around it) and run its selftest: image-format probe (flat / NHD /
# HDI / VHD / refused), MODE SENSE pages 3 and 4, READ CAPACITY and the
# READ10/WRITE10 header offset.
#
#   scripts/sim_scsi_fw.sh               selftest
#   scripts/sim_scsi_fw.sh probe IMG     what the firmware would mount IMG as
#
# The binary lands in ${SIM_OUT:-$TMPDIR/pc98scsi}/scsi_fw_host.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OUT="${SIM_OUT:-${TMPDIR:-/tmp}/pc98scsi}"
mkdir -p "$OUT"
c++ -std=c++17 -O1 -Wall -Wno-unused-function -o "$OUT/scsi_fw_host" \
    sim/host/scsi_fw_host.cpp

if [ $# -eq 0 ]; then
    exec "$OUT/scsi_fw_host" selftest
fi
exec "$OUT/scsi_fw_host" "$@"
