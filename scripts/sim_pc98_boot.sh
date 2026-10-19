#!/usr/bin/env bash
# sim_pc98_boot.sh -- run the real ITF on the real CPU core, in simulation:
# the z86 + cpu_bus_bridge pair core_top ships, on tb_pc98_boot's machine.
#
#   scripts/sim_pc98_boot.sh [+plusarg ...]
#   scripts/sim_pc98_boot.sh --synth    # hand-written ITF, no ROMs needed
#   scripts/sim_pc98_boot.sh --realmem  # ... on the REAL memory path
#
# Not part of CI: it needs bios.rom and itf.rom, which are not in the tree,
# unless --synth.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SYNTH=0
REALMEM=0
while [ $# -gt 0 ]; do
    case "$1" in
        --synth) SYNTH=1; shift ;;
        --realmem) REALMEM=1; shift ;;
        *) break ;;
    esac
done

ROMS="${PC98_ROMS:-$HOME/.pc98roms}"
[ "$SYNTH" = 1 ] || { [ -f "$ROMS/itf.rom" ] && [ -f "$ROMS/bios.rom" ] ; } \
    || { echo "need itf.rom and bios.rom in $ROMS (or --synth)"; exit 1; }

OUT="${SIM_OUT:-${TMPDIR:-/tmp}/pc98boot}"
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
Z8=$S/z86

# +repint pokes this IPL straight into guest RAM and jumps the reset vector
# at it; the bench $readmemh's it from $OUT like the ROM hexes.
cp sim/ipl_repint.hex "$OUT/ipl_repint.hex"
# +hddimg turns the SCSI board on (scripts/sim_scsi_boot.sh); its option
# ROM image rides along always.
cp fpga/core/scsi_rom.hex "$OUT/scsi_rom.hex"

R="$PWD"
SIM_OPT="${SIM_OPT:--O2}"
SIM_THREADS="${SIM_THREADS:-4}"

CPU_DEF=""
[ "$REALMEM" = 1 ] && CPU_DEF="+define+REALMEM"
[ -n "${EXTRA_DEF:-}" ] && CPU_DEF="$CPU_DEF $EXTRA_DEF"
Z86FILES="$R/$Z8/z86_package.sv $R/$Z8/fetch.sv $R/$Z8/decode.sv \
    $R/$Z8/execute.sv $R/$Z8/write_back.sv $R/$Z8/regfile.sv \
    $R/$Z8/divider.sv $R/$Z8/z86_cache.sv $R/$Z8/z86.sv -I$R/$Z8"

if [ "$REALMEM" = 1 ]; then
    MEMFILES="$K/RAM.sv $K/Ready.sv $S/sdram_shim.sv $S/sdram_mp.sv \
        $S/pc98_gvram_seq.sv $S/pc98_grcg.sv $S/pc98_egc.sv \
        sim/sdram_board_model.sv sim/sdram_model.sv"
else
    MEMFILES=""
fi

SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"
CXXFLAGS_MK=""
if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXXFLAGS_MK="-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++"
fi

set -x
verilator --binary --timing -Wno-fatal --top-module tb_pc98_boot $CPU_DEF \
    --threads $SIM_THREADS -MAKEFLAGS OPT_FAST=$SIM_OPT \
    $CXXFLAGS_MK \
    $SYSROOT \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$K" \
    -I"$R/$K/i8288/HDL" -I"$R/$K/i8253/HDL" -I"$R/$K/i8259/HDL" \
    $Z86FILES \
    "$R/sim/tb_pc98_boot.sv" \
    $MEMFILES \
    $R/$S/cpu_bus_bridge.sv \
    $R/$S/pc98_fdc_glue.sv $R/$S/common/floppy.v $R/$S/common/simple_fifo.v \
    $R/sim/tb_fdd_dma_model.sv $R/$S/pc98_kbd8251.sv \
    $R/$S/pc98_scsi.sv $R/sim/tb_scsi_target.sv \
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
