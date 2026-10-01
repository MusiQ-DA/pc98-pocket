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

# resume landing: F800:1497 = linear F9497 -- the REAL ITF post-resume
# block (F9497-F94EC), verbatim. Port 42h answers 00h in the bench, same
# as the RTL -- so "test al,2 / jnz" is NOT taken and the CPU must chew
# through FNINIT / FWAIT+FSTSW / SMSW / LMSW before jumping to F854E.
# On real V30 hardware (and np21w) port 42h bit1 is the "CPU is a V30"
# detect, which skips this 286-only block -- our 00h lies about that.
post_resume = bytes([
    0x33, 0xC0,                    # 9497 xor ax,ax
    0x8E, 0xD8,                    # 9499 mov ds,ax
    0xE4, 0x42,                    # 949B in al,0x42        -> 00h
    0x8A, 0xE0,                    # 949D mov ah,al
    0xD0, 0xEC,                    # 949F shr ah,1
    0xD0, 0xEC,                    # 94A1 shr ah,1
    0x80, 0xE4, 0x30,              # 94A3 and ah,0x30
    0x80, 0xCC, 0x40,              # 94A6 or ah,0x40
    0xA8, 0x02,                    # 94A9 test al,0x02
    0x75, 0x08,                    # 94AB jnz 94B5
    0x80, 0xE4, 0xBF,              # 94AD and ah,0xBF
    0x80, 0x0E, 0x80, 0x04, 0x01,  # 94B0 or byte [0x0480],0x01
    0xA8, 0x20,                    # 94B5 test al,0x20
    0x74, 0x03,                    # 94B7 jz 94BC
    0x80, 0xCC, 0x80,              # 94B9 or ah,0x80
    0x80, 0x26, 0x01, 0x05, 0x07,  # 94BC and byte [0x0501],0x07
    0xB0, 0x01,                    # 94C1 mov al,0x01
    0x09, 0x06, 0x00, 0x05,        # 94C3 or [0x0500],ax
    0x80, 0x0E, 0x80, 0x04, 0x40,  # 94C7 or byte [0x0480],0x40
    0xE4, 0x42,                    # 94CC in al,0x42        -> 00h again
    0xA8, 0x02,                    # 94CE test al,0x02
    0x75, 0x13,                    # 94D0 jnz 94E5          (not taken)
    0xDB, 0xE3,                    # 94D2 fninit            (ESC, modrm 11)
    0x9B,                          # 94D4 fwait
    0xDF, 0xE0,                    # 94D5 fstsw ax          (ESC, modrm 11)
    0x0A, 0xC0,                    # 94D7 or al,al
    0x75, 0x0A,                    # 94D9 jnz 94E5
    0x0F, 0x01, 0xE0,              # 94DB smsw ax           (0F = POP CS on 186!)
    0x0C, 0x02,                    # 94DE or al,0x02
    0x0F, 0x01, 0xF0,              # 94E0 lmsw ax           (286-only)
    0xEB, 0x00,                    # 94E3 jmp short 94E5
    0x33, 0xC0,                    # 94E5 xor ax,ax
    0x8E, 0xD8,                    # 94E7 mov ds,ax
    0xBC, 0xEF, 0x14,              # 94E9 mov sp,0x14EF
    0xE9, 0x5F, 0xF0,              # 94EC jmp 0x854E
])
d[0xF9497:0xF9497+len(post_resume)] = post_resume

# If zet INVOPs opcode 0Fh into an INT6 trap, the vector at 0000:0018
# lands at 0000:0600 -- mark the trap and IRET back.
d[0x0018:0x001C] = bytes([0x00, 0x06, 0x00, 0x00])
i6 = bytes([
    0xC7, 0x06, 0x02, 0x02, 0x66, 0x06,   # mov word [0x0202],0x0666
    0xCF,                                  # iret
])
d[0x0600:0x0600+len(i6)] = i6

# jmp target F800:054E = linear F854E -- success marker, plus a push
# imm8 (6A) regression check: push byte 97h must stack FFFF-extended FF97,
# not 0097 -- the PUSHI microcode is shared by 68 and 6A.
marker = bytes([
    0x6A, 0x97,                           # push byte 0x97 (sign-extend)
    0x5F,                                 # pop di
    0x89, 0x3E, 0x02, 0x02,               # mov [0x0202],di
    # 0F 01 stub coverage: lidt word [bp+0] (mem form, disp8) / sidt / lgdt /
    # sgdt / smsw ax / lmsw ax -- all must consume modrm(+disp) and NOP
    # without trapping. If a byte desyncs the stream, execution lands on
    # garbage and the BEEF marker never appears.
    0xBD, 0x00, 0x80,                     # mov bp,0x8000  (scratch EA)
    0x0F, 0x01, 0x5E, 0x00,               # lidt word [es:bp+0]  (F8BBC form)
    0x0F, 0x01, 0x56, 0x00,               # lgdt word [es:bp+0]
    0x0F, 0x01, 0x4E, 0x00,               # sidt word [es:bp+0]
    0x0F, 0x01, 0x46, 0x00,               # sgdt word [es:bp+0]
    0x0F, 0x01, 0xE0,                     # smsw ax
    0x0F, 0x01, 0xF0,                     # lmsw ax
    0xC7, 0x06, 0x04, 0x02, 0x34, 0x12,   # mov word [0x0204],0x1234
    0xC7, 0x06, 0x00, 0x02, 0xEF, 0xBE,   # mov word [0x0200],0xBEEF
    0xF4,                                 # hlt
])
d[0xF854E:0xF854E+len(marker)] = marker

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
