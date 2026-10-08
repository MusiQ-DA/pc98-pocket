#!/usr/bin/env bash
# sim_zet_retf.sh -- far-transfer/stack stress on bare zet + zet_cpu_bridge.
# Builds the flat image with nasm, then loops `call far`/`retf`,
# `call far [mem]`, `int`/`iret`, `pusha`/`popa` and a push-frame `retf`
# while the bench raises INTR (vector 40h) at random intervals. A stack or
# CS-restore imbalance diverges the stream and the port-0x20 markers stall.
#
#   scripts/sim_zet_retf.sh
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/zetretf}"; mkdir -p "$OUT/fpga/core/zet"
cp fpga/core/zet/micro_rom.dat "$OUT/fpga/core/zet/"
nasm -f bin sim/reft_test.asm -o "$OUT/reft_test.bin"
python3 - "$OUT" <<'PY'
import sys, os
out = sys.argv[1]
d = open(os.path.join(out, "reft_test.bin"), "rb").read()
with open(os.path.join(out, "reft_test.hex"), "w") as f:
    for i in range(0, len(d), 16):
        f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
PY
R="$PWD"; S=fpga/core; K=$S/chipset/HDL; Z=$S/zet
SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"
CXXMK=""
if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXXMK="-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++"
fi
verilator --binary --timing -Wno-fatal --top-module tb_zet_retf \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 $CXXMK $SYSROOT \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$Z" -I"$R/$K" -I"$R/$K/i8288/HDL" \
    "$R/sim/tb_zet_retf.sv" \
    $R/$Z/zet.v $R/$Z/zet_core.v $R/$Z/zet_fetch.v $R/$Z/zet_decode.v \
    $R/$Z/zet_exec.v $R/$Z/zet_memory_regs.v $R/$Z/zet_micro_data.v \
    $R/$Z/zet_micro_rom.v $R/$Z/zet_regfile.v $R/$Z/zet_wb_master.v \
    $R/$Z/zet_addsub.v $R/$Z/zet_alu.v $R/$Z/zet_arlog.v \
    $R/$Z/zet_bitlog.v $R/$Z/zet_conv.v $R/$Z/zet_div_su.v \
    $R/$Z/zet_div_uu.v $R/$Z/zet_fulladd16.v $R/$Z/zet_jmp_cond.v \
    $R/$Z/zet_muldiv.v $R/$Z/zet_mux8_1.v $R/$Z/zet_mux8_16.v \
    $R/$Z/zet_next_or_not.v $R/$Z/zet_nstate.v $R/$Z/zet_opcode_deco.v \
    $R/$Z/zet_othop.v $R/$Z/zet_rxr8.v $R/$Z/zet_rxr16.v \
    $R/$Z/zet_shrot.v $R/$Z/zet_signmul17.v \
    $R/$S/zet_cpu_bridge.sv \
    $R/$K/i8288/HDL/i8288.sv \
    -o retf --Mdir "$OUT/obj_retf" 2>&1 | tail -8
cp sim/reft_test.asm "$OUT/" 2>/dev/null || true
cd "$OUT" && ./obj_retf/retf
