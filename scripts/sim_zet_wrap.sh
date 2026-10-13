#!/usr/bin/env bash
# sim_zet_wrap.sh -- an odd word at offset FFFFh must wrap to offset 0000h of
# the same segment (8086/V30 BIU), not spill onto the next 64 KB. See
# sim/tb_zet_wrap.sv.
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/zetwrap}"; mkdir -p "$OUT/fpga/core/zet"
cp fpga/core/zet/micro_rom.dat "$OUT/fpga/core/zet/"
python3 - "$OUT" <<'PY'
import sys
out = sys.argv[1]
prog = bytes([
    0xB8, 0x00, 0x30, 0x8E, 0xD8,              # mov ax,3000h ; mov ds,ax
    0xC7, 0x06, 0xFF, 0xFF, 0x20, 0x58,        # mov word [FFFFh],5820h
    0x8B, 0x1E, 0xFF, 0xFF,                    # mov bx,[FFFFh]
    0x88, 0xD8, 0xE6, 0x10,                    # mov al,bl ; out 10h,al
    0x88, 0xF8, 0xE6, 0x11,                    # mov al,bh ; out 11h,al
    0xB8, 0x00, 0x50, 0x8E, 0xD0,              # mov ax,5000h ; mov ss,ax
    0xBC, 0x01, 0x00,                          # mov sp,1
    0xB8, 0xB2, 0xA1, 0x50,                    # mov ax,A1B2h ; push ax (SS:FFFF)
    0x59,                                      # pop cx
    0x88, 0xC8, 0xE6, 0x12,                    # mov al,cl ; out 12h,al
    0x88, 0xE8, 0xE6, 0x13,                    # mov al,ch ; out 13h,al
    0xBA, 0x01, 0x01, 0xEE,                    # mov dx,0101h ; out dx,al
    0xF4, 0xEB, 0xFD,                          # hlt ; jmp $-1
])
with open(out + "/smoke.hex", "w") as f:
    for i, b in enumerate(prog):
        f.write("@%05X %02X\n" % (0xF8000 + i, b))
    for i, b in enumerate([0xEA, 0x00, 0x00, 0x00, 0xF8]):   # JMP F800:0000
        f.write("@%05X %02X\n" % (0xFFFF0 + i, b))
PY
R="$PWD"; S=fpga/core; K=$S/chipset/HDL; Z=$S/zet
verilator --binary --timing -Wno-fatal --top-module tb_zet_wrap \
    -I"$R/sim" -I"$R/$S" -I"$R/$Z" -I"$R/$K" -I"$R/$K/i8288/HDL" \
    "$R/sim/tb_zet_wrap.sv" $R/$Z/*.v \
    $R/$S/zet_cpu_bridge.sv $R/$K/i8288/HDL/i8288.sv \
    -o wraprun --Mdir "$OUT/obj_wrap" 2>&1 | tail -3
cd "$OUT" && ./obj_wrap/wraprun | tee wrap.log | grep -E "RAM|RESULT|TIMEOUT"
grep -q "RESULT: PASS" wrap.log
