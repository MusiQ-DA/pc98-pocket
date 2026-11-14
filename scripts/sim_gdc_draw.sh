#!/usr/bin/env bash
# sim_gdc_draw.sh -- the shipped firmware/gdc_service.c driving the Verilated
# pc98_gdc_draw engine, checked line by line against np21w's gdcsub_vectl
# (sim/host/gdc_draw_host.cpp). No --timing: any Verilator 5 will do.
#
#   scripts/sim_gdc_draw.sh [n] [seed] [kinds]   default 100000 draws of "lpr"
#   scripts/sim_gdc_draw.sh bench [lat_rd [lat_rmw [lat_tdw]]]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/pc98gdcdraw}"
mkdir -p "$OUT"
verilator --cc --exe --build -O3 -Wno-fatal --top-module pc98_gdc_draw \
    -CFLAGS "-O2 -std=c++17 -Wno-unused-function" \
    --Mdir "$OUT/obj" -o gdc_draw_host \
    fpga/core/pc98_gdc_draw.sv "$PWD/sim/host/gdc_draw_host.cpp" >"$OUT/build.log" 2>&1 \
    || { tail -40 "$OUT/build.log"; exit 1; }
if [ "${1:-}" = bench ]; then exec "$OUT/obj/gdc_draw_host" "$@"; fi
exec "$OUT/obj/gdc_draw_host" "${1:-100000}" "${2:-1}" ${3:+"$3"}
