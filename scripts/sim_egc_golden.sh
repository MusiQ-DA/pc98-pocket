#!/bin/bash
# sim_egc_golden.sh -- the np21w golden-model differential bench for the
# EGC/GRCG sequencer.
#
#   scripts/sim_egc_golden.sh +stream=sim/golden/streams/egctest.ops
#   scripts/sim_egc_golden.sh +seed=12345 +nops=4000
#   scripts/sim_egc_golden.sh +seed=12345 +dump=out.ops +cmpmod=1
#
# Builds sim/golden (np21w's own egc.c/memegc.c/memvram.c behind the compat
# shim) into a static archive, links it into the Verilator bench via
# -LDFLAGS, then runs it. Every guest access goes to BOTH sides; reads and
# the final VRAM image must match np21w byte-for-byte.
set -euo pipefail
cd "$(dirname "$0")/.."

G=sim/golden
OBJ=$(mktemp -d)/golden
mkdir -p "$OBJ"
trap 'rm -rf "$(dirname "$OBJ")"' EXIT

# np21w is C89-as-C++; compile the three sources + the harness half as C so
# their semantics stay verbatim. golden_egc.c carries the extern "C" guards
# the DPI link needs even under g++.
for f in $G/np21w/egc.c $G/np21w/memegc.c $G/np21w/memvram.c $G/golden_egc.c; do
    cc -O2 -I$G/np21w_inc -I$G/np21w -c "$f" -o "$OBJ/$(basename "$f" .c).o"
done
ar rcs "$OBJ/libgolden.a" "$OBJ"/*.o

S=fpga/core
verilator --binary --timing -Wno-fatal --top-module tb_pc98_egc_golden \
    -Isim -I$S \
    sim/tb_pc98_egc_golden.sv $S/pc98_gvram_seq.sv $S/pc98_egc.sv \
    fpga/core/pc98_sdram_map.svh \
    -LDFLAGS "$OBJ/libgolden.a" \
    -o golden_sim --Mdir "$OBJ/obj"

"$OBJ/obj/golden_sim" "$@"
