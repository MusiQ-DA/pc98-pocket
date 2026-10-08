#!/usr/bin/env bash
# sim_zet_tvram.sh -- the REAL CPU->TVRAM bus path under test
# (zet + zet_cpu_bridge + BUS_ARBITER/i8288/upd71071 + READY + pc98_tvram
# + the Peripherals read-register replica). Reproduces the BIOS text
# pattern that shows "starfield" corruption on hardware:
#   rep stosw clear (char=0020, attr=00E1), ten `mov es:[di],dx` echo
#   writes interleaved with `in al,31h`, then a `rep movsw` row copy.
#
# Usage: scripts/sim_zet_tvram.sh [+speed=N] [+plusarg ...]
#   +speed=N selects the ce_generator clk_select (0=5MHz 1=10MHz 2=19.7 3=21.5)
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OUT="${TMPDIR:-/tmp}/zettvram"
mkdir -p "$OUT/fpga/core/zet"
cp fpga/core/zet/micro_rom.dat "$OUT/fpga/core/zet/"

# ---------------------------------------------------------------- program
python3 - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
d = bytearray(b"\x00" * 0x100000)
d[0xFFFF0:0xFFFF5] = bytes([0xEA, 0x00, 0x00, 0x00, 0xF8])   # JMP F800:0000

prog  = bytes([0xFA])                                       # CLI
prog += bytes([0xB8,0x00,0x00, 0x8E,0xD8, 0x8E,0xD0])       # AX=0 DS SS
prog += bytes([0xBC,0x00,0x04])                             # SP=0400
prog += bytes([0xFB])                                       # STI
prog += bytes([0xB8,0x00,0xA0, 0x8E,0xC0])                  # ES=A000
prog += bytes([0xB8,0x20,0x00])                             # AX=0020
prog += bytes([0x33,0xFF, 0xB9,0xD0,0x07, 0xF3,0xAB])       # rep stosw x2000
prog += bytes([0xB8,0x00,0xA2, 0x8E,0xC0])                  # ES=A200
prog += bytes([0xB8,0xE1,0x00])                             # AX=00E1
prog += bytes([0x33,0xFF, 0xB9,0xD0,0x07, 0xF3,0xAB])       # rep stosw x2000
prog += bytes([0xB8,0x00,0xA0, 0x8E,0xC0])                  # ES=A000
prog += bytes([0xBF,0x60,0x0E])                             # DI=0E60 (row23)
for i in range(10):                                         # '0'..'9'
    prog += bytes([0xBA,0x30+i,0x00, 0x26,0x89,0x15,        # mov es:[di],dx
                   0xE4,0x31,                               # in al,31h
                   0x83,0xC7,0x02])                         # add di,2
prog += bytes([0xB8,0x00,0xA0, 0x8E,0xD8])                  # DS=A000
prog += bytes([0xBE,0x60,0x0E, 0x33,0xFF, 0xB9,0x50,0x00])  # SI=0E60 DI=0 CX=80
prog += bytes([0xF3,0xA5])                                  # rep movsw
prog += bytes([0xBA,0x34,0x12, 0xEE, 0xEB,0xFE])            # out; jmp $
d[0xF8000:0xF8000+len(prog)] = prog
d[0xF8300] = 0xCF                                            # iret
d[0x0100:0x0104] = bytes([0x00,0x03,0x00,0xF8])              # IVT[40]=F800:0300
with open(os.path.join(out, "tv.hex"), "w") as f:
    for i in range(0, 0x100000, 16):
        f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
print("tv.hex written, prog %d bytes" % len(prog))
PY

R="$PWD"; S=fpga/core; K=$S/chipset/HDL; Z=$S/zet
SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"

verilator --binary --timing -Wno-fatal --top-module tb_zet_tvram \
    -I"$R/sim" -I"$R/$S" -I"$R/$Z" -I"$R/$K" \
    -I"$R/$K/i8288/HDL" -I"$R/$K/upd71071/HDL" \
    "$R/sim/tb_zet_tvram.sv" \
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
    "$R/$S/zet_cpu_bridge.sv" \
    "$R/$K/ce_generator.sv" "$R/$K/Bus_Arbiter.sv" \
    "$R/$K/i8288/HDL/i8288.sv" "$R/$K/Ready.sv" \
    "$R/$K/upd71071/HDL/upd71071.sv" \
    "$R/$K/upd71071/HDL/upd71071_Address_And_Count_Registers.sv" \
    "$R/$K/upd71071/HDL/upd71071_Bus_Control_Logic.sv" \
    "$R/$K/upd71071/HDL/upd71071_Priority_Encoder.sv" \
    "$R/$K/upd71071/HDL/upd71071_Timing_And_Control.sv" \
    "$R/$S/pc98_tvram.sv" \
    -o tvram --Mdir "$OUT/obj_tvram"
cd "$OUT" && exec ./obj_tvram/tvram "$@"
