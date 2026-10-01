#!/usr/bin/env bash
# sim_zet_resume.sh -- directed replay of the ITF shutdown/resume handshake
# on the Zet CPU (see tb_zet_resume.sv for the annotated sequence).
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OUT="${SIM_OUT:-${TMPDIR:-/tmp}/pc98zetresume}"
mkdir -p "$OUT/fpga/core/zet"
cp fpga/core/zet/micro_rom.dat "$OUT/fpga/core/zet/"

python3 - "$OUT" <<'PY'
import sys, os
out = sys.argv[1]
d = bytearray(0x100000)

# reset vector FFFF0: jmp F800:0000
d[0xFFFF0:0xFFFF5] = bytes([0xEA, 0x00, 0x00, 0x00, 0xF8])

prog = bytes([
    0xFA,                          # F8000 cli
    0xBC, 0x30, 0x00,              # F8001 mov sp,0x0030
    0x8E, 0xD4,                    # F8004 mov ss,sp         -> SS=0030
    0xBC, 0xFE, 0x00,              # F8006 mov sp,0x00FE
    0xB0, 0x0E,                    # F8009 mov al,0x0E
    0xE6, 0x37,                    # F800B out 0x37,al       (ITF's PC7 clear)
    0x0E,                          # F800D push cs           (F800)
    0x68, 0x97, 0x14,              # F800E push word 0x1497  (resume IP)
    0x8C, 0x16, 0x06, 0x04,        # F8011 mov [0x0406],ss
    0x89, 0x26, 0x04, 0x04,        # F8015 mov [0x0404],sp
    0xEB, 0x06,                    # F8019 jmp short resume_entry (F8021)
    # F801B fail:
    0xC7, 0x06, 0x00, 0x02, 0xAD, 0xDE,   # mov word [0x0200],0xDEAD
    # F8021 resume_entry (post-"reset" re-entry):
    0xE4, 0x35,                    #        in al,0x35      (bench: 0x79)
    0xA8, 0x80,                    #        test al,0x80
    0x75, 0xF4,                    #        jnz fail        (F801B)
    0x8E, 0x16, 0x06, 0x04,        #        mov ss,[0x0406]
    0x8B, 0x26, 0x04, 0x04,        #        mov sp,[0x0404]
    0xCB,                          #        retf            -> F800:1497
    0xF4,                          # F8030  hlt (should not reach)
])
d[0xF8000:0xF8000+len(prog)] = prog

# resume landing: F800:1497 = linear F9497
d[0xF9497:0xF9497+7] = bytes([
    0xC7, 0x06, 0x00, 0x02, 0xEF, 0xBE,   # mov word [0x0200],0xBEEF
    0xF4,                                 # hlt
])

with open(os.path.join(out, "resume.hex"), "w") as f:
    for i in range(0, 0x100000, 16):
        f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
print("resume.hex written")
PY

R="$PWD"; S=fpga/core; K=$S/chipset/HDL; Z=$S/zet
SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"
CXXMK=""
if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXXMK="-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++"
fi
verilator --binary --timing -Wno-fatal --top-module tb_zet_resume \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 $CXXMK $SYSROOT \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$Z" -I"$R/$K" -I"$R/$K/i8288/HDL" \
    "$R/sim/tb_zet_resume.sv" \
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
    -o resume --Mdir "$OUT/obj_resume" 2>&1 | tail -6
cd "$OUT" && ./obj_resume/resume
