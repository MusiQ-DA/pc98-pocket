#!/usr/bin/env bash
# sim_pc98_zet_boot.sh -- the ITF boot bench on the EXPERIMENTAL Zet CPU
# (zet-cpu branch). Identical machine to sim_pc98_boot.sh; only the CPU
# pair differs (zet + zet_cpu_bridge for v30_core + v30_cpu_bridge).
#
#   scripts/sim_pc98_zet_boot.sh [+plusarg ...]
#
# Not part of CI: it needs bios.rom and itf.rom, which are not in the tree.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SYNTH=0
while [ $# -gt 0 ]; do
    case "$1" in
        --synth) SYNTH=1; shift ;;
        *) break ;;
    esac
done

ROMS="${PC98_ROMS:-$HOME/.pc98roms}"
[ "$SYNTH" = 1 ] || { [ -f "$ROMS/itf.rom" ] && [ -f "$ROMS/bios.rom" ] ; } \
    || { echo "need itf.rom and bios.rom in $ROMS (or --synth)"; exit 1; }

OUT="${SIM_OUT:-${TMPDIR:-/tmp}/pc98zetboot}"
mkdir -p "$OUT"

python3 - "$ROMS" "$OUT" "$SYNTH" <<'PY'
import sys, os
roms, out, synth = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

if synth:
    def ck(n):
        return bytes([0xBA, n, 0x01, 0xEE])          # MOV DX,01nn ; OUT DX,AL
    prog = (bytes([0xFA]) + ck(0x00)
        + bytes([0x80, 0xC0, 0x01]) + ck(0x01)
        + bytes([0xD0, 0xE0])       + ck(0x02)
        + bytes([0xFE, 0xC0])       + ck(0x03)
        + bytes([0xF7, 0xE3])       + ck(0x04)
        + bytes([0xF6, 0xE4])       + ck(0x05)
        + bytes([0x68, 0x34, 0x12]) + ck(0x06)       # PUSH imm16 -- the ITF's
        + bytes([0xF4]))                             #   F9476 that killed i8088
    d = bytearray(b"\xff" * 0x8000)
    d[0:len(prog)] = prog
    d[0x7FF0:0x7FF5] = bytes([0xEA, 0x00, 0x00, 0x00, 0xF8])
    with open(os.path.join(out, "itf.hex"), "w") as f:
        for i in range(0, 0x8000, 16):
            f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
    d = bytearray(b"\xff" * 0x18000)
    with open(os.path.join(out, "bios.hex"), "w") as f:
        for i in range(0, 0x18000, 16):
            f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
    print("synthetic ITF: %d bytes" % len(prog))
    raise SystemExit

for name, size in (("itf", 0x8000), ("bios", 0x18000)):
    d = open(os.path.join(roms, name + ".rom"), "rb").read()
    d = d[:size] + b"\xff" * max(0, size - len(d))
    with open(os.path.join(out, name + ".hex"), "w") as f:
        for i in range(0, size, 16):
            f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
    print("%-5s %6d bytes -> %s.hex" % (name, len(d), name))
PY

S=fpga/core
K=$S/chipset/HDL
Z=$S/zet

# zet_micro_rom's simulation default is DATDIR="fpga/core/zet/" relative to
# the bench's cwd ($OUT) -- mirror it the way the V30's ucore hexes are.
mkdir -p "$OUT/fpga/core/zet"
cp $Z/micro_rom.dat "$OUT/fpga/core/zet/"

R="$PWD"
SIM_OPT="${SIM_OPT:--O2}"
SIM_THREADS="${SIM_THREADS:-4}"

SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"
CXXFLAGS_MK=""
if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXXFLAGS_MK="-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++"
fi

set -x
verilator --binary --timing -Wno-fatal --top-module tb_pc98_boot \
    +define+ZET_CPU \
    --threads $SIM_THREADS -MAKEFLAGS OPT_FAST=$SIM_OPT \
    $CXXFLAGS_MK \
    $SYSROOT \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$Z" -I"$R/$K" \
    -I"$R/$K/i8288/HDL" -I"$R/$K/i8253/HDL" -I"$R/$K/i8259/HDL" \
    "$R/sim/tb_pc98_boot.sv" \
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
    $R/$S/pc98_fdc_glue.sv $R/$S/common/floppy.v $R/$S/common/simple_fifo.v \
    $R/sim/tb_fdd_dma_model.sv $R/$S/pc98_kbd8251.sv \
    $R/$K/ce_generator.sv $R/$K/i8288/HDL/i8288.sv \
    $R/$K/i8253/HDL/i8253.sv $R/$K/i8253/HDL/i8253_Counter.sv \
    $R/$K/i8253/HDL/i8253_Control_Logic.sv \
    $R/$K/i8259/HDL/i8259.sv $R/$K/i8259/HDL/i8259_Bus_Control_Logic.sv \
    $R/$K/i8259/HDL/i8259_Control_Logic.sv $R/$K/i8259/HDL/i8259_In_Service.sv \
    $R/$K/i8259/HDL/i8259_Interrupt_Request.sv \
    $R/$K/i8259/HDL/i8259_Priority_Resolver.sv \
    -o boot --Mdir "$OUT/obj_boot"
set +x
cd "$OUT" && exec ./obj_boot/boot "$@"
