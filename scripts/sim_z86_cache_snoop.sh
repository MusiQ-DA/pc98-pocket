#!/usr/bin/env bash
# sim_z86_cache_snoop.sh -- z86_cache's snoop port vs external commits
# (tb_z86_cache_snoop): the FDC-DMA coherency contract, read-fill ->
# sn_v commit -> re-read must see the new data.
#   scripts/sim_z86_cache_snoop.sh
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/z86csnoop}"
Z=fpga/core/z86
SYSROOT=()
[ -d /usr/include ] || SYSROOT=(-CFLAGS -isysroot -CFLAGS "$(xcrun -sdk macosx --show-sdk-path)")
CXX=()
[ -x /opt/homebrew/opt/llvm/bin/clang++ ] && CXX=(-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++)
verilator --binary --timing -Wno-fatal "${SYSROOT[@]}" "${CXX[@]}" -I$Z \
    $Z/z86_cache.sv sim/tb_z86_cache_snoop.sv \
    --top-module tb_z86_cache_snoop --Mdir "$OUT" -o csnoop > "$OUT.build.log" 2>&1 \
    || { grep -E '%Error' "$OUT.build.log" | head; exit 1; }
exec "$OUT/csnoop"
