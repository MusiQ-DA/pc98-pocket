#!/usr/bin/env bash
# sim_zet_smoke.sh -- bare zet + zet_cpu_bridge on a flat byte memory
# (zet-cpu branch). Builds in seconds, so the Wishbone->8288 contract --
# including the INTA freeze path -- is debuggable on a program of a dozen
# instructions instead of the full ITF bench.
#
# The program arms vectors 40h/02h, STIs, and spins on inc word [0202h].
# The bench raises INTR once the loop is live (fake 8259 answers ACK2 with
# 40h), checks the handler's BEEFh marker + post-IRET progress, then does
# the same for NMI (vector 2, no bus cycle). PASS needs exactly 2 INTA
# pulses and both markers.
#
#   scripts/sim_zet_smoke.sh
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/zetsmoke}"; mkdir -p "$OUT/fpga/core/zet"
cp fpga/core/zet/micro_rom.dat "$OUT/fpga/core/zet/"
python3 - "$OUT" <<'PY'
import sys, os
out = sys.argv[1]
d = bytearray(b"\x00" * 0x100000)
d[0xFFFF0:0xFFFF5] = bytes([0xEA, 0x00, 0x00, 0x00, 0xF8])   # JMP F800:0000
def ck(n):
    return bytes([0xBA, n, 0x01, 0xEE])          # MOV DX,01nn ; OUT DX,AL
prog = (
    bytes([0xFA])                                # CLI
    + bytes([0xB8, 0x00, 0x00])                  # MOV AX,0
    + bytes([0x8E, 0xD8, 0x8E, 0xD0])            # MOV DS,AX ; MOV SS,AX
    + bytes([0xBC, 0x00, 0x04])                  # MOV SP,0400h
    + ck(0x00)                                   # OUT 0100h,AL (AL=0)
    + bytes([0x80, 0xC0, 0x01]) + ck(0x01)       # ADD AL,1 ; OUT (AL=1)
    + bytes([0xD0, 0xE0])       + ck(0x02)       # SHL AL,1 ; OUT (AL=2)
    + bytes([0xF7, 0xE3])       + ck(0x04)       # MUL BX   ; OUT (AL=0)
    + bytes([0x68, 0x34, 0x12])                  # PUSH 1234h
    + bytes([0xC7, 0x06, 0x00, 0x01, 0x00, 0x01])# MOV WORD [0100h],0100h
    + bytes([0xC7, 0x06, 0x02, 0x01, 0x00, 0xF8])# MOV WORD [0102h],F800h
    + bytes([0xC7, 0x06, 0x08, 0x00, 0x00, 0x02])# MOV WORD [0008h],0200h
    + bytes([0xC7, 0x06, 0x0A, 0x00, 0x00, 0xF8])# MOV WORD [000Ah],F800h
    + bytes([0xFB])                              # STI
    + bytes([0xFF, 0x06, 0x02, 0x02])            # loop: INC WORD [0202h]
    + bytes([0xEB, 0xFA]))                       # JMP SHORT loop
# INTR handler (vector 40h -> F800:0100): mark [0200h]=BEEFh, IRET
hnd40 = bytes([0xC7, 0x06, 0x00, 0x02, 0xEF, 0xBE,
               0xBA, 0x40, 0x01, 0xEE,           # OUT 0140h,AL
               0xCF])                            # IRET
# NMI handler (vector 2 -> F800:0200): mark [0204h]=CAFEh, IRET
hnd02 = bytes([0xC7, 0x06, 0x04, 0x02, 0xFE, 0xCA,
               0xBA, 0x41, 0x01, 0xEE,           # OUT 0141h,AL
               0xCF])                            # IRET
d[0xF8000:0xF8000+len(prog)] = prog
d[0xF8100:0xF8100+len(hnd40)] = hnd40
d[0xF8200:0xF8200+len(hnd02)] = hnd02
with open(os.path.join(out, "smoke.hex"), "w") as f:
    for i in range(0, 0x100000, 16):
        f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
print("smoke.hex written, prog %d bytes" % len(prog))
PY
R="$PWD"; S=fpga/core; K=$S/chipset/HDL; Z=$S/zet
SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"
CXXMK=""
if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXXMK="-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++"
fi
verilator --binary --timing -Wno-fatal --top-module tb_zet_smoke \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 $CXXMK $SYSROOT \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$Z" -I"$R/$K" -I"$R/$K/i8288/HDL" \
    "$R/sim/tb_zet_smoke.sv" \
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
    -o smoke --Mdir "$OUT/obj_smoke" 2>&1 | tail -6
cd "$OUT" && ./obj_smoke/smoke
