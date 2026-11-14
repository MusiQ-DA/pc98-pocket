#!/usr/bin/env python3
"""gen_eu_cost.py -- the 80286 clock-count ROM for z86's paced issue gate.

fetch.sv holds each instruction's hand-off to decode until the previous one
has used up its 80286 data-sheet time (real mode, zero wait states, queue
full).  That makes register-only code run at 286 speed instead of z86's
native one-or-two chipset clocks; memory forms carry the sheet's count too
(it includes their bus cycles), and z86_cache prices the bus cycles
themselves, so an access-heavy instruction costs max(sheet, bus).

Address: {opcode[7:0], mem, reg[2:0]}
  mem  = ModRM present and mod != 11 (memory operand)
  reg  = ModRM reg field, only for the group opcodes; 0 otherwise
  opcode 0Fh stands for every two-byte opcode.
Data: clocks, 5 bits (max 31).

Taken control transfers: the sheet's "7+m" etc. is split -- this ROM carries
the part every execution pays, and fetch.sv adds TAKEN (5) when the branch
resolves taken, so Jcc = 3 / 3+5, LOOP = 4 / 4+5, JMP short = 3+5.

Not modelled: the shift/rotate count (D2/D3 charge the n=0 base, C0/C1 add
the immediate count when fetch can see it -- they cannot here, base only),
REP iterations (issue once; each iteration's bus cycles are priced by the
cache), prefixes (free).

Writes fpga/core/z86/eu_cost.hex (one 2-digit hex word per line, 4096 lines).
"""
import os

TAKEN = 5  # fetch.sv adds this on br_taken (keep the two in step)
FAR_RELOAD = 2  # INT/IRET only, see the table

def cost(op, mem, reg):
    alu = {0, 1, 2, 3, 4, 5, 7}          # ADD OR ADC SBB AND SUB XOR (row)
    hi, lo = op >> 3, op & 7
    # 00-3F ALU rows, seg push/pop, prefixes, BCD
    if op < 0x40:
        if lo <= 3:                      # r/m,r  r,r/m  (b/w)
            if hi == 7:                  # CMP
                return 6 if mem else 2
            return 7 if mem else 2
        if lo in (4, 5):                 # acc,imm
            return 3
        if op in (0x06, 0x0E, 0x16, 0x1E):
            return 3                     # PUSH sreg
        if op in (0x07, 0x17, 0x1F):
            return 5                     # POP sreg
        if op == 0x0F:
            return 10                    # two-byte (protected-mode) ops
        if op in (0x27, 0x2F, 0x37, 0x3F):
            return 3                     # DAA DAS AAA AAS
        return 0                         # prefixes 26/2E/36/3E
    if op < 0x50: return 2               # INC/DEC r16
    if op < 0x58: return 3               # PUSH r16
    if op < 0x60: return 5               # POP r16
    t = {0x60: 17, 0x61: 19, 0x62: 13, 0x63: 10, 0x68: 3, 0x6A: 3,
         0x6C: 5, 0x6D: 5, 0x6E: 5, 0x6F: 5}
    if op in t: return t[op]
    if op in (0x69, 0x6B): return 24 if mem else 21    # IMUL r,r/m,imm
    if 0x64 <= op <= 0x67: return 0
    if 0x70 <= op <= 0x7F: return 3      # Jcc (+TAKEN)
    if 0x80 <= op <= 0x83:               # group 1 r/m,imm
        if reg == 7: return 6 if mem else 3
        return 7 if mem else 3
    if op in (0x84, 0x85): return 6 if mem else 2       # TEST
    if op in (0x86, 0x87): return 5 if mem else 3       # XCHG
    if op in (0x88, 0x89): return 3 if mem else 2       # MOV r/m,r
    if op in (0x8A, 0x8B): return 5 if mem else 2       # MOV r,r/m
    if op == 0x8C: return 3 if mem else 2
    if op == 0x8D: return 3                             # LEA
    if op == 0x8E: return 5 if mem else 2
    if op == 0x8F: return 5                             # POP r/m
    if op == 0x90: return 3                             # NOP
    if op < 0x98: return 3                              # XCHG ax,r
    t = {0x98: 2, 0x99: 2, 0x9A: 13 - TAKEN + 1, 0x9B: 3, 0x9C: 3, 0x9D: 5,
         0x9E: 2, 0x9F: 2,
         0xA0: 5, 0xA1: 5, 0xA2: 3, 0xA3: 3,            # MOV acc,moffs
         0xA4: 5, 0xA5: 5, 0xA6: 8, 0xA7: 8,            # MOVS CMPS
         0xA8: 3, 0xA9: 3,                              # TEST acc,imm
         0xAA: 3, 0xAB: 3, 0xAC: 5, 0xAD: 5, 0xAE: 7, 0xAF: 7}
    if op in t: return t[op]
    if 0xB0 <= op <= 0xBF: return 2                     # MOV r,imm
    if op in (0xC0, 0xC1): return 8 if mem else 5       # shift imm (+n)
    t = {0xC2: 11 + 1 - TAKEN, 0xC3: 11 + 1 - TAKEN,    # RET near
         0xC4: 7, 0xC5: 7,                              # LES LDS
         0xC8: 11, 0xC9: 5,                             # ENTER LEAVE
         0xCA: 15 + 1 - TAKEN, 0xCB: 15 + 1 - TAKEN,    # RET far
         # INT / IRET: +FAR_RELOAD -- they always reload CS:IP and the
         # stack frame (3 words each way) also holds the prefetch back, so
         # the near-transfer split (the reload's first word priced by the
         # cache) left them short (int n + iret x4 at 0.91 of the sheet).
         0xCC: 23 + 1 - TAKEN + FAR_RELOAD, 0xCD: 23 + 1 - TAKEN + FAR_RELOAD,
         0xCE: 4, 0xCF: 17 + 1 - TAKEN + FAR_RELOAD,    # INTO IRET
         0xD4: 16, 0xD5: 14, 0xD6: 2, 0xD7: 5}          # AAM AAD SALC XLAT
    if op in t: return t[op]
    if op in (0xC6, 0xC7): return 3 if mem else 2       # MOV r/m,imm
    if op in (0xD0, 0xD1): return 7 if mem else 2       # shift 1
    if op in (0xD2, 0xD3): return 8 if mem else 5       # shift CL (+n)
    if 0xD8 <= op <= 0xDF: return 2                     # ESC (no FPU)
    if op in (0xE0, 0xE1, 0xE2, 0xE3): return 4         # LOOPx JCXZ (+TAKEN)
    if op in (0xE4, 0xE5, 0xEC, 0xED): return 5         # IN
    if op in (0xE6, 0xE7, 0xEE, 0xEF): return 3         # OUT
    if op == 0xE8: return 7 + 1 - TAKEN                 # CALL near
    if op == 0xE9: return 7 + 1 - TAKEN                 # JMP near
    if op == 0xEA: return 11 + 1 - TAKEN                # JMP far
    if op == 0xEB: return 7 + 1 - TAKEN                 # JMP short
    if op in (0xF0, 0xF2, 0xF3): return 0               # prefixes
    if op == 0xF4: return 2                             # HLT
    if op == 0xF5: return 2                             # CMC
    if op in (0xF6, 0xF7):                              # group 3
        w = op & 1
        if reg in (0, 1): return 6 if mem else 3        # TEST imm
        if reg in (2, 3): return 7 if mem else 2        # NOT NEG
        if reg == 4: return (24 if w else 16) if mem else (21 if w else 13)  # MUL
        if reg == 5: return (24 if w else 16) if mem else (21 if w else 13)  # IMUL
        if reg == 6: return (25 if w else 17) if mem else (22 if w else 14)  # DIV
        return (28 if w else 20) if mem else (25 if w else 17)               # IDIV
    if 0xF8 <= op <= 0xFD: return 2                     # flag ops
    if op in (0xFE, 0xFF):                              # group 4/5
        if reg in (0, 1): return 7 if mem else 2        # INC DEC
        if reg == 2: return (11 if mem else 7) + 1 - TAKEN   # CALL near ind
        if reg == 3: return 16 + 1 - TAKEN              # CALL far ind
        if reg == 4: return (11 if mem else 7) + 1 - TAKEN   # JMP near ind
        if reg == 5: return 15 + 1 - TAKEN              # JMP far ind
        if reg == 6: return 5                           # PUSH r/m
        return 2
    return 2

GROUPS = {0x80, 0x81, 0x82, 0x83, 0xC0, 0xC1, 0xD0, 0xD1, 0xD2, 0xD3,
          0xF6, 0xF7, 0xFE, 0xFF}

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "fpga", "core", "z86", "eu_cost.hex")
    lines = []
    for a in range(4096):
        op, mem, reg = a >> 4, (a >> 3) & 1, a & 7
        if op not in GROUPS and reg != 0:
            c = cost(op, mem, 0)     # never addressed; keep it consistent
        else:
            c = cost(op, mem, reg)
        assert 0 <= c <= 31, (hex(op), mem, reg, c)
        lines.append(f"{c:02x}")
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {out}")

if __name__ == "__main__":
    main()
