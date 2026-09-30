#!/usr/bin/env bash
# sim_pc98_boot.sh -- run the real ITF on the real CPU core, in simulation.
#
# The hardware readout says BANK 1: the guest never executes OUT 043D, 12. Where
# it goes instead is an execution question, and execution questions are far
# cheaper to answer here than on a fifteen-minute bitstream.
#
#   scripts/sim_pc98_boot.sh [+plusarg ...]        # the nuV30 + v30_cpu_bridge
#   scripts/sim_pc98_boot.sh --realmem ...         # ... on the REAL memory path
#
# Not part of CI: it needs bios.rom and itf.rom, which are not in the tree.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SYNTH=0
REALMEM=0
while [ $# -gt 0 ]; do
    case "$1" in
        --synth) SYNTH=1; shift ;;
        # --realmem: run the ITF through the REAL memory path -- RAM.sv on
        # sdram_shim on sdram_mp on the part, with the board's clock skew --
        # instead of the flat array. The word path is unconditional either
        # way: the flat model answers the odd lane at addr|1.
        --realmem) REALMEM=1; shift ;;
        *) break ;;
    esac
done
# Anything left over goes straight to the simulator binary (e.g. +gate2=0).

ROMS="${PC98_ROMS:-$HOME/.pc98roms}"
[ -f "$ROMS/itf.rom" ] && [ -f "$ROMS/bios.rom" ] \
    || { echo "need itf.rom and bios.rom in $ROMS"; exit 1; }

OUT="${SIM_OUT:-${TMPDIR:-/tmp}/pc98boot}"
mkdir -p "$OUT"

python3 - "$ROMS" "$OUT" "$SYNTH" <<'PY'
import sys, os
roms, out, synth = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

if synth:
    # A hand-written ITF, to separate "the core is wrong" from "the model is
    # wrong". Each step writes a distinct port before moving on, so the I/O
    # trace says exactly how far the core got. Same instructions the real ITF
    # uses at the point it stops.
    # The real ITF's opening sequence, instruction for instruction, with a
    # checkpoint OUT between every step. Each conditional jump there is a
    # two-byte jump to itself, so a failed test spins inside the prefetch queue
    # and puts nothing on the bus -- which is why the fetch trace could say
    # where the CPU stopped fetching but not where it stopped executing.
    #
    # MOV DX,imm and OUT DX,AL touch no flags, so the checkpoints do not perturb
    # what is being tested.
    def ck(n):
        return bytes([0xBA, n, 0x01, 0xEE])          # MOV DX,01nn ; OUT DX,AL
    # Is it the F6 group specifically, or every group opcode? 0x80 and 0xD0 have
    # the same shape in the microcode (CALC_EA_BYTE, FETCH_EA_BYTE, Jump-Type6),
    # so if they consume correctly and F6 does not, the fault is F6's alone.
    prog = (bytes([0xFA]) + ck(0x00)
        + bytes([0x80, 0xC0, 0x01]) + ck(0x01)       # 0x80 group: ADD AL,1
        + bytes([0xD0, 0xE0])       + ck(0x02)       # 0xD0 group: SHL AL,1
        + bytes([0xFE, 0xC0])       + ck(0x03)       # 0xFE group: INC AL
        + bytes([0xF7, 0xE3])       + ck(0x04)       # 0xF7 group: MUL BX
        + bytes([0xF6, 0xE4])       + ck(0x05)       # 0xF6 group: MUL AH
        + bytes([0xF4]))                             # HLT
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
V=$S/v30

# v30u_ucrom's simulation default is HEXDIR="hdl/rtl/ucore/" relative to the
# working directory -- and an empty microcode ROM is a $fatal, not a warning.
mkdir -p "$OUT/hdl/rtl/ucore"
cp $V/ucrom.hex $V/ucdecode.hex "$OUT/hdl/rtl/ucore/"

R="$PWD"
CPU_DEF="+define+V30_BACKDOOR"
[ "$REALMEM" = 1 ] && CPU_DEF="$CPU_DEF+REALMEM"

# The V30 build is pure CPU time in Verilator: compile the model for speed
# (-O2, same reasoning as sim_pc98_v30.sh) and split the eval across cores.
# NOT --x-assign/--x-initial fast: sim_pc98_v30.sh measured those changing
# the boot.
SIM_OPT="${SIM_OPT:--O2}"
SIM_THREADS="${SIM_THREADS:-4}"

if [ "$REALMEM" = 1 ]; then
    MEMFILES="$K/RAM.sv $K/Ready.sv $S/sdram_shim.sv $S/sdram_mp.sv sim/sdram_board_model.sv sim/sdram_model.sv"
else
    MEMFILES=""
fi

# Native Verilator -- several times faster than the amd64 image was under
# Rosetta. The bench's cwd is $OUT (where the .hex images and hdl/rtl/ucore
# live). clang needs an explicit sysroot on some CLT installs or 'cstddef'
# is not found.
SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"
# The CLT here lost its C++ headers ('cstddef' not found) -- use Homebrew's
# clang++, which carries its own libcxx, whenever it exists.
CXXFLAGS_MK=""
if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXXFLAGS_MK="-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++"
fi

set -x
verilator --binary --timing -Wno-fatal --top-module tb_pc98_boot $CPU_DEF \
    --threads $SIM_THREADS -MAKEFLAGS OPT_FAST=$SIM_OPT \
    $CXXFLAGS_MK \
    $SYSROOT \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$V" -I"$R/$K" \
    -I"$R/$K/i8288/HDL" -I"$R/$K/i8253/HDL" -I"$R/$K/i8259/HDL" \
    "$R/sim/tb_pc98_boot.sv" \
    $R/$V/v30u_ss_pkg.sv \
    $R/$V/v30_core.sv $R/$V/v30u_biu.sv $R/$V/v30u_eu.sv \
    $R/$V/v30u_ucrom.sv $R/$S/v30_cpu_bridge.sv \
    $MEMFILES \
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
