#!/usr/bin/env bash
# sim_zet_ios.sh -- bare zet + zet_cpu_bridge on a flat byte memory.
# Exercises the 80186 string-I/O opcodes (6C-6F): outsb/outsw, rep outsw,
# insb/insw, rep insw, DF=1, ES: override, and rep-ins/outsb -> INVOP.
#
#   scripts/sim_zet_ios.sh
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/zetios}"; mkdir -p "$OUT/fpga/core/zet"
cp fpga/core/zet/micro_rom.dat "$OUT/fpga/core/zet/"
python3 - "$OUT" <<'PY'
import sys, os
out = sys.argv[1]
d = bytearray(b"\x00" * 0x100000)
d[0xFFFF0:0xFFFF5] = bytes([0xEA, 0x00, 0x00, 0x00, 0xF8])   # JMP F800:0000

prog = bytes([
    0xFA,                          # cli
    0xB8, 0x00, 0x00, 0x8E, 0xD8,  # mov ax,0 ; mov ds,ax
    0xC7, 0x06, 0x18, 0x00, 0x00, 0x04,   # mov word [0x18],0x0400 (int6 ip)
    0xC7, 0x06, 0x1A, 0x00, 0x00, 0xF8,   # mov word [0x1A],0xF800 (int6 cs)
    0xB8, 0x00, 0x20, 0x8E, 0xD8,  # mov ax,0x2000 ; mov ds,ax
    0xB8, 0x00, 0x30, 0x8E, 0xC0,  # mov ax,0x3000 ; mov es,ax
    0x31, 0xF6, 0x31, 0xFF,        # xor si,si ; xor di,di
    0xBA, 0xA0, 0x05,              # mov dx,0x5A0
    0x6E,                          # outsb       -> IOWR A0
    0x6F,                          # outsw       -> IOWR A1 A2
    0x6C,                          # insb        -> [30000]
    0x6D,                          # insw        -> [30001..2]
    0xB9, 0x03, 0x00,              # mov cx,3
    0xF3, 0x6F,                    # rep outsw   -> IOWR A3..A8
    0xBE, 0x08, 0x00,              # mov si,8
    0xFD,                          # std
    0x6E,                          # outsb       -> IOWR A8 (si=8)
    0xFC,                          # cld
    0xB8, 0x00, 0x50, 0x8E, 0xC0,  # mov ax,0x5000 ; mov es,ax
    0xBE, 0x02, 0x00,              # mov si,2
    0x26, 0x6E,                    # es:outsb    -> IOWR 77
    0xF3, 0x6C,                    # rep insb    -> INVOP -> int6 (once)
    0xF3, 0x6D,                    # rep insw    -> INVOP -> int6 (once)
    0xBA, 0xA1, 0x05,              # mov dx,0x5A1
    0xB0, 0x42,                    # mov al,0x42
    0xEE,                          # out dx,al   -> completion
    0xF4,                          # hlt
])
# int6 handler: standard x86 frame [sp+0]=IP (zet pushes ip0=rep-prefix
# address, so +1 resumes at the bare opcode). NOTE: use ss:[si] addressing -
# [bp]-relative addressing does not hit the stack segment correctly here.
hnd = bytes([0x89, 0xE6,                          # mov si,sp
             0x36, 0x83, 0x04, 0x01,              # add word ss:[si],1
             0xFE, 0x06, 0x10, 0x03,              # inc byte [0x0310]
             0xCF])                               # iret
d[0xF8000:0xF8000+len(prog)] = prog
d[0xF8400:0xF8400+len(hnd)] = hnd
# source data A0..A8 at 20000..20008, es-override source 0x77 at 0x50002
for i in range(9):
    d[0x20000+i] = 0xA0 + i
d[0x50002] = 0x77
with open(os.path.join(out, "ios.hex"), "w") as f:
    for i in range(0, 0x100000, 16):
        f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
print("ios.hex written, prog %d bytes" % len(prog))
PY
R="$PWD"; S=fpga/core; K=$S/chipset/HDL; Z=$S/zet
SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"
CXXMK=""
if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXXMK="-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++"
fi
verilator --binary --timing -Wno-fatal --top-module tb_zet_ios \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 $CXXMK $SYSROOT \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$Z" -I"$R/$K" -I"$R/$K/i8288/HDL" \
    "$R/sim/tb_zet_ios.sv" \
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
    -o iosrun --Mdir "$OUT/obj_ios" 2>&1 | tail -6
cd "$OUT" && ./obj_ios/iosrun
