#!/usr/bin/env bash
# sim_pc98_boot.sh -- run the real ITF on the real 8088 core, in simulation.
#
# The hardware readout says BANK 1: the guest never executes OUT 043D, 12. Where
# it goes instead is an execution question, and execution questions are far
# cheaper to answer here than on a fifteen-minute bitstream.
#
# Not part of CI: it needs bios.rom and itf.rom, which are not in the tree.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SYNTH=0
[ "${1:-}" = "--synth" ] && { SYNTH=1; shift; }
# Anything left over goes straight to the simulator binary (e.g. +gate2=0).

ROMS="${PC98_ROMS:-$HOME/.pc98roms}"
[ -f "$ROMS/itf.rom" ] && [ -f "$ROMS/bios.rom" ] \
    || { echo "need itf.rom and bios.rom in $ROMS"; exit 1; }

OUT="${TMPDIR:-/tmp}/pc98boot"
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

export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
CFG="${TMPDIR:-/tmp}/pc98-dockercfg"
mkdir -p "$CFG"
python3 - "$CFG/config.json" <<'PY'
import json, sys
c = json.load(open('/Users/hiroya/.docker/config.json'))
c.pop('credsStore', None)
json.dump(c, open(sys.argv[1], 'w'))
PY
export DOCKER_CONFIG="$CFG"

S=pcxt-base/src/fpga/core
K=$S/KFPC-XT/HDL
docker run --rm -v "$PWD":/work -v "$OUT":/hex -w /hex -e "SIMARGS=$*" pc98-sim bash -lc "
  set -e
  verilator --binary --timing -Wno-fatal --top-module tb_pc98_boot \
    -I/work/sim -I/work/$S -I/work/$S/8088 -I/work/$K -I/work/$K/KF8288/HDL \
    -I/work/$K/KF8253/HDL -I/work/$K/KF8259/HDL \
    /work/sim/tb_pc98_boot.sv \
    /work/$S/8088/i8088.v /work/$S/8088/biu_max.v \
    /work/$S/8088/mcl86_eu_core.v /work/$S/8088/eu_rom.v \
    /work/$K/pc98_fdc.sv \
    /work/$K/XT_CE_Generator.sv /work/$K/KF8288/HDL/KF8288.sv \
    /work/$K/KF8253/HDL/KF8253.sv /work/$K/KF8253/HDL/KF8253_Counter.sv \
    /work/$K/KF8253/HDL/KF8253_Control_Logic.sv \
    /work/$K/KF8259/HDL/KF8259.sv /work/$K/KF8259/HDL/KF8259_Bus_Control_Logic.sv \
    /work/$K/KF8259/HDL/KF8259_Control_Logic.sv /work/$K/KF8259/HDL/KF8259_In_Service.sv \
    /work/$K/KF8259/HDL/KF8259_Interrupt_Request.sv \
    /work/$K/KF8259/HDL/KF8259_Priority_Resolver.sv \
    -o boot --Mdir /tmp/obj_boot
  cp /work/$S/8088/microcode.mem /hex/
  /tmp/obj_boot/boot \$SIMARGS
"
