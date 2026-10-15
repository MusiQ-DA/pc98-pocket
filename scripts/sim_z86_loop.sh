#!/usr/bin/env bash
# sim_z86_loop.sh -- z86 alone on a fixed-latency Wishbone memory (tb_z86_loop).
#   scripts/sim_z86_loop.sh [+n=N] [+lat=L]
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/z86loop}"
Z=fpga/core/z86
SYSROOT=()
[ -d /usr/include ] || SYSROOT=(-CFLAGS -isysroot -CFLAGS "$(xcrun -sdk macosx --show-sdk-path)")
CXX=()
[ -x /opt/homebrew/opt/llvm/bin/clang++ ] && CXX=(-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++)
verilator --binary --timing -Wno-fatal "${SYSROOT[@]}" "${CXX[@]}" -I$Z \
    $Z/z86_package.sv $Z/fetch.sv $Z/decode.sv $Z/execute.sv $Z/write_back.sv \
    $Z/regfile.sv $Z/divider.sv $Z/z86_wbif.sv $Z/z86.sv sim/tb_z86_loop.sv \
    --top-module tb_z86_loop --Mdir "$OUT" -o loop > "$OUT.build.log" 2>&1 \
    || { grep -E "%Error" "$OUT.build.log" | head; exit 1; }
exec "$OUT/loop" "$@"
