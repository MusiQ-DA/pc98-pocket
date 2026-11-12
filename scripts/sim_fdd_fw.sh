#!/usr/bin/env bash
# sim_fdd_fw.sh -- build the shipped firmware/fdd_service.c + disk_tds.c for
# the host (sim/host/fdd_fw_host.cpp models floppy.v's mgmt registers, the
# bridge RAM and the dataslot engine around them) and run it.
#
#   scripts/sim_fdd_fw.sh                    selftest: a synthetic 2HD D88 and
#                                            its raw twin, every LBA read back
#   scripts/sim_fdd_fw.sh IMG [FLAT]         mount IMG and compare every LBA
#                                            with FLAT (raw C/H/R order)
#
# The binary lands in ${SIM_OUT:-$TMPDIR/pc98fdd}/fdd_fw_host.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OUT="${SIM_OUT:-${TMPDIR:-/tmp}/pc98fdd}"
mkdir -p "$OUT"
c++ -std=c++17 -O1 -Wall -Wno-unused-function -o "$OUT/fdd_fw_host" \
    sim/host/fdd_fw_host.cpp

if [ $# -eq 0 ]; then
    exec "$OUT/fdd_fw_host" selftest
fi
exec "$OUT/fdd_fw_host" "$@"
