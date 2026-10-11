#!/usr/bin/env bash
# sim_zet_iplstress.sh -- run the hardware ipl_farstress image on bare zet +
# zet_cpu_bridge over FLAT single-cycle RAM (no prefetch/SDRAM). If the stress
# passes here but diverges on hardware, the fault is in the SDRAM/prefetch
# path rather than the CPU or the guest program.
#
#   scripts/sim_zet_iplstress.sh
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/zetipl}"; mkdir -p "$OUT/fpga/core/zet"
IPL_SRC="${IPL_SRC:-sim/ipl_farstress.asm}"
IPL_BIN="$(basename "${IPL_SRC%.*}").bin"
cp fpga/core/zet/micro_rom.dat "$OUT/fpga/core/zet/"
nasm -f bin "$IPL_SRC" -o "$OUT/$IPL_BIN"
python3 - "$OUT" "$IPL_BIN" <<'PY'
import sys, os
out = sys.argv[1]
bs = open(os.path.join(out, sys.argv[2]), "rb").read()
img = bytearray(0x100000)
img[0x1FC00:0x1FC00 + len(bs)] = bs          # IPL code at phys 0x1FC00
img[0xFFFF0:0xFFFF5] = bytes([0xEA,0x00,0x00,0xC0,0x1F])  # reset -> 1FC0:0
with open(os.path.join(out, "iplstress.hex"), "w") as f:
    for b in img:
        f.write("%02x\n" % b)
PY
R="$PWD"; S=fpga/core; K=$S/chipset/HDL; Z=$S/zet
SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"
CXXMK=""
if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXXMK="-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++"
fi
verilator --binary --timing -Wno-fatal --top-module tb_zet_iplstress \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 $CXXMK $SYSROOT \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$Z" -I"$R/$K" -I"$R/$K/i8288/HDL" \
    "$R/sim/tb_zet_iplstress.sv" \
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
    -o ipl --Mdir "$OUT/obj_ipl" 2>&1 | tail -8
cp sim/ipl_farstress.asm "$OUT/" 2>/dev/null || true
cd "$OUT" && ./obj_ipl/ipl "$@"
