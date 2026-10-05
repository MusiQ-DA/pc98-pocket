#!/usr/bin/env bash
# sim_zet_286chk.sh -- probe Zet's 80286-visible semantics directly.
# The generated program writes a result byte per check to ports 110h+;
# comparing the IOWR transcript against real-286 expectations tells us
# which semantics the core currently implements.
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R="$PWD"
OUT=$(mktemp -d /tmp/zet286chk.XXXXXX)
mkdir -p "$OUT/fpga/core/zet"
cp fpga/core/zet/micro_rom.dat "$OUT/fpga/core/zet/"
cd "$OUT"
python3 - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
d = bytearray(b"\x00" * 0x100000)
d[0xFFFF0:0xFFFF5] = bytes([0xEA, 0x00, 0x00, 0x00, 0xF8])   # JMP F800:0000
def ck(n):
    return bytes([0xBA, n, 0x01, 0xEE])          # MOV DX,01nn ; OUT DX,AL
prog = bytearray()
prog += bytes([0xFA])                            # CLI
prog += bytes([0xB8, 0x00, 0x00])                # MOV AX,0
prog += bytes([0x8E, 0xD8, 0x8E, 0xD0])          # MOV DS,AX ; MOV SS,AX
prog += bytes([0xBC, 0x00, 0x04])                # MOV SP,0400h

# ---- T1: PUSH SP  (286: pushes pre-decrement SP; 8086/V30: decremented) ----
prog += bytes([0xBC, 0x00, 0x05])                # MOV SP,0500h
prog += bytes([0x54])                            # PUSH SP
prog += bytes([0x58])                            # POP AX
prog += ck(0x10)                                 # OUT 0110 = AL (286:00 / 86:FE)

# ---- T2: PUSHF high nibble  (286 real mode: flags[15:12]=0) ----
prog += bytes([0x9C])                            # PUSHF
prog += bytes([0x58])                            # POP AX
prog += bytes([0x8A, 0xC4])                      # MOV AL,AH
prog += bytes([0x24, 0xF0])                      # AND AL,F0h
prog += ck(0x11)                                 # OUT 0111 = AL

# ---- T3: PUSH SP again, different value ----
prog += bytes([0xBC, 0x10, 0x04])                # MOV SP,0410h
prog += bytes([0x54])                            # PUSH SP
prog += bytes([0x5B])                            # POP BX
prog += bytes([0x88, 0xD8])                      # MOV AL,BL
prog += ck(0x12)                                 # OUT 0112 = AL (286:10 / 86:0E)

# ---- T4: BOUND (62h) ----
# int5 handler at F800:0200 -> OUT 11B=50h, fix pushed IP +=4, iret
# int6 handler at F800:0300 -> OUT 11C=60h, fix pushed IP +=1, iret
prog += bytes([0xC7, 0x06, 0x14, 0x00, 0x00, 0x02])# MOV WORD [0014],0200h (int5 IP)
prog += bytes([0xC7, 0x06, 0x16, 0x00, 0x00, 0xF8])# MOV WORD [0016],F800h (int5 CS)
prog += bytes([0xC7, 0x06, 0x18, 0x00, 0x00, 0x03])# MOV WORD [0018],0300h (int6 IP)
prog += bytes([0xC7, 0x06, 0x1A, 0x00, 0x00, 0xF8])# MOV WORD [001A],F800h (int6 CS)
prog += bytes([0xC7, 0x06, 0x00, 0x03, 0x00, 0x00])# MOV WORD [0300],0      ; lo bound
prog += bytes([0xC7, 0x06, 0x02, 0x03, 0x0A, 0x00])# MOV WORD [0302],10     ; hi bound
prog += bytes([0xB8, 0x05, 0x00])                  # MOV AX,5
prog += bytes([0x62, 0x06, 0x00, 0x03])            # BOUND AX,[0300h] in-range
prog += bytes([0xB0, 0xB1]) + ck(0x13)             # OUT 0113 = B1 (survived)
prog += bytes([0xB8, 0x32, 0x00])                  # MOV AX,50
prog += bytes([0x62, 0x06, 0x00, 0x03])            # BOUND AX,[0300h] out-of-range -> int5
prog += bytes([0xB0, 0xB2]) + ck(0x14)             # OUT 0114 = B2 (resumed after int5)

# ---- T5: 0xD6 (SALC on Intel silicon / XLAT on V30) ----
prog += bytes([0xF9])                            # STC
prog += bytes([0xD6])                            # SALC -> AL=FF
prog += ck(0x15)                                 # OUT 0115 = AL
prog += bytes([0xF8])                            # CLC
prog += bytes([0xD6])                            # SALC -> AL=00
prog += ck(0x16)                                 # OUT 0116 = AL

# ---- T6: int6 pushed-IP check ----
# int6 handler records low byte of pushed IP to port 11D, bumps IP+1, iret.
# Execute FF FF (invalid) at a known point; report tells us fault-IP behaviour.
prog += bytes([0xFF, 0xFF])                      # FF /7 -> int6
prog += bytes([0xB0, 0xB3]) + ck(0x17)           # OUT 0117 = B3 if resumed

prog += bytes([0xEB, 0xFE])                      # JMP $ (done)

# int5 handler: OUT 11B=50h ; BP-frame fix: [bp+2]+=4 ; iret
hnd5 = (bytes([0xB0, 0x50]) + ck(0x1B)
      + bytes([0x55])                            # PUSH BP
      + bytes([0x8B, 0xEC])                      # MOV BP,SP
      + bytes([0x83, 0x46, 0x02, 0x04])          # ADD WORD [BP+2],4
      + bytes([0x5D])                            # POP BP
      + bytes([0xCF]))                           # IRET
# int6 handler: OUT 11C=60h ; report pushed IP low byte to 11D ; [bp+2]+=1 ; iret
hnd6 = (bytes([0xB0, 0x60]) + ck(0x1C)
      + bytes([0x55])                            # PUSH BP
      + bytes([0x8B, 0xEC])                      # MOV BP,SP
      + bytes([0x8B, 0x46, 0x02])                # MOV AX,[BP+2] (pushed IP)
      + ck(0x1D)                                 # OUT 011D = IP low byte
      + bytes([0x83, 0x46, 0x02, 0x01])          # ADD WORD [BP+2],1
      + bytes([0x5D])                            # POP BP
      + bytes([0xCF]))                           # IRET

d[0xF8000:0xF8000+len(prog)] = prog
d[0xF8200:0xF8200+len(hnd5)] = hnd5
d[0xF8300:0xF8300+len(hnd6)] = hnd6
with open(os.path.join(out, "chk.hex"), "w") as f:
    for i in range(0, 0x100000, 16):
        f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
print("chk.hex written, prog %d bytes" % len(prog))
PY
S=fpga/core; K=$S/chipset/HDL; Z=$S/zet
SYSROOT=""
[ -d /usr/include ] || SYSROOT="-CFLAGS -isysroot -CFLAGS $(xcrun -sdk macosx --show-sdk-path)"
CXXMK=""
if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
    CXXMK="-MAKEFLAGS CXX=/opt/homebrew/opt/llvm/bin/clang++ -MAKEFLAGS LINK=/opt/homebrew/opt/llvm/bin/clang++"
fi
verilator --binary --timing -Wno-fatal --top-module tb_zet_286chk \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 $CXXMK $SYSROOT \
    -I"$R/sim" -I"$R/$S" -I"$R/$S/common" -I"$R/$Z" -I"$R/$K" -I"$R/$K/i8288/HDL" \
    "$R/sim/tb_zet_286chk.sv" \
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
    -o chk --Mdir "$OUT/obj_chk" 2>&1 | tail -6
cd "$OUT" && ./obj_chk/chk
