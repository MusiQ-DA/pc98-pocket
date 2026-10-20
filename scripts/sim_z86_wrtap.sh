#!/usr/bin/env bash
# sim_z86_wrtap.sh -- z86_cache's port-F write witness vs a port-F model
# (tb_z86_wrtap): the tap core_top's write watchpoint matches for cached
# stores, which never reach the chipset bus.
#   scripts/sim_z86_wrtap.sh
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/z86wrtap}"
Z=fpga/core/z86
SYSROOT=()
[ -d /usr/include ] || SYSROOT=(-CFLAGS -isysroot -CFLAGS "$(xcrun -sdk macosx --show-sdk-path)")
CXX=()
[ -x /opt/homebrew/opt/llvm/bin/clang++ ] && CXX=(-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++)
verilator --binary --timing -Wno-fatal "${SYSROOT[@]}" "${CXX[@]}" -I$Z \
    $Z/z86_package.sv $Z/fetch.sv $Z/decode.sv $Z/execute.sv $Z/write_back.sv \
    $Z/regfile.sv $Z/divider.sv $Z/z86_cache.sv sim/tb_z86_wrtap.sv \
    --top-module tb_z86_wrtap --Mdir "$OUT" -o wrtap > "$OUT.build.log" 2>&1 \
    || { grep -E '%Error' "$OUT.build.log" | head; exit 1; }
exec "$OUT/wrtap"
