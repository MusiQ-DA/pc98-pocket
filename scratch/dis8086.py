#!/usr/bin/env python3
"""Minimal 8086/8088 disassembler, good enough for a PC-98 ITF ROM image.

Usage:
  dis8086.py <romfile> <base_addr_hex> <start_addr_hex> [count]
  dis8086.py <romfile> --range <start_hex> <end_hex>
"""
import sys

REG8  = ['AL','CL','DL','BL','AH','CH','DH','BH']
REG16 = ['AX','CX','DX','BX','SP','BP','SI','DI']
REG32 = ['EAX','ECX','EDX','EBX','ESP','EBP','ESI','EDI']
SREG  = ['ES','CS','SS','DS']
RM16  = ['BX+SI','BX+DI','BP+SI','BP+DI','SI','DI','BP','BX']

CC = ['O','NO','B','NB','Z','NZ','BE','NBE','S','NS','P','NP','L','NL','LE','NLE']
# more idiomatic names
CCN = ['O','NO','C','NC','Z','NZ','BE','A','S','NS','PE','PO','L','GE','LE','G']

ARITH = ['ADD','OR','ADC','SBB','AND','SUB','XOR','CMP']
SHIFT = ['ROL','ROR','RCL','RCR','SHL','SHR','SAL','SAR']
GRP3  = ['TEST','TEST','NOT','NEG','MUL','IMUL','DIV','IDIV']

def h(v, w=None):
    if w == 1:
        s = '%02X' % (v & 0xFF)
    elif w == 2:
        s = '%04X' % (v & 0xFFFF)
    else:
        s = '%X' % v
    if s[0] in 'ABCDEF':
        s = '0' + s
    return s + 'h'

class Dis:
    def __init__(self, data, base):
        self.d = data
        self.base = base  # linear address of data[0]

    def b(self, i):
        return self.d[i - self.base]

    def w(self, i):
        return self.d[i - self.base] | (self.d[i - self.base + 1] << 8)

    def modrm(self, i, wbit, segpfx, R16=REG16):
        m = self.b(i)
        mod = m >> 6
        reg = (m >> 3) & 7
        rm = m & 7
        i += 1
        pfx = (segpfx + ':') if segpfx else ''
        if mod == 3:
            ea = (R16 if wbit else REG8)[rm]
        elif mod == 0 and rm == 6:
            disp = self.w(i); i += 2
            ea = '%s[%s]' % (pfx, h(disp, 2))
        else:
            if mod == 1:
                d8 = self.b(i); i += 1
                if d8 & 0x80:
                    off = '-' + h(0x100 - d8, 1)
                else:
                    off = '+' + h(d8, 1)
            elif mod == 2:
                d16 = self.w(i); i += 2
                off = '+' + h(d16, 2)
            else:
                off = ''
            ea = '%s[%s%s]' % (pfx, RM16[rm], off)
        return i, mod, reg, rm, ea

    def decode(self, addr):
        """returns (nextaddr, text, info) ; info = dict for analysis"""
        i = addr
        segpfx = None
        rep = ''
        lock = ''
        osz = False
        asz = False
        info = {}
        while True:
            op = self.b(i)
            if op in (0x26, 0x2E, 0x36, 0x3E):
                segpfx = SREG[(op >> 3) & 3]; i += 1; continue
            if op == 0xF2:
                rep = 'REPNE '; i += 1; continue
            if op == 0xF3:
                rep = 'REP '; i += 1; continue
            if op == 0xF0:
                lock = 'LOCK '; i += 1; continue
            if op == 0x66:
                osz = True; i += 1; continue
            if op == 0x67:
                asz = True; i += 1; continue
            break
        i += 1
        pre = lock + rep
        R16 = REG32 if osz else REG16
        IW = (lambda ii: (self.w(ii) | (self.w(ii+2) << 16), ii + 4)) if osz else (lambda ii: (self.w(ii), ii + 2))
        HW = 8 if osz else 4
        if osz:
            info['osz'] = True
        R = lambda t: (i, pre + t, info)

        # 00-3F arithmetic block
        if op < 0x40 and (op & 7) < 6:
            aop = ARITH[op >> 3]
            f = op & 7
            wbit = f & 1
            if f in (0, 1, 2, 3):
                i, mod, reg, rm, ea = self.modrm(i, wbit, segpfx, R16)
                r = (R16 if wbit else REG8)[reg]
                if f in (0, 1):
                    return R('%s %s,%s' % (aop, ea, r))
                return R('%s %s,%s' % (aop, r, ea))
            if f == 4:
                imm = self.b(i); i += 1
                return R('%s AL,%s' % (aop, h(imm, 1)))
            imm = self.w(i); i += 2
            return R('%s AX,%s' % (aop, h(imm, 2)))
        if op == 0x60: return R('PUSHA' + ('D' if osz else ''))
        if op == 0x61: return R('POPA' + ('D' if osz else ''))
        if op == 0x62:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            return R('BOUND %s,%s' % (R16[reg], ea))
        if op == 0x63:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, REG16)
            return R('ARPL %s,%s' % (ea, REG16[reg]))
        if op == 0x68:
            imm, i = IW(i); return R('PUSH %s' % h(imm, HW))
        if op == 0x6A:
            imm = self.b(i); i += 1
            v = imm - 256 if imm & 0x80 else imm
            return R('PUSH %s' % h(v & 0xFFFF, 4))
        if op == 0x69:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            imm, i = IW(i)
            return R('IMUL %s,%s,%s' % (R16[reg], ea, h(imm, HW)))
        if op == 0x6B:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            imm = self.b(i); i += 1
            v = imm - 256 if imm & 0x80 else imm
            return R('IMUL %s,%s,%s' % (R16[reg], ea, h(v & 0xFFFF, 4)))
        if op in (0x6C, 0x6D):
            info['io'] = ('INS', 'DX', op & 1)
            return R('INS' + (('D' if osz else 'W') if op & 1 else 'B'))
        if op in (0x6E, 0x6F):
            info['io'] = ('OUTS', 'DX', op & 1)
            return R('OUTS' + (('D' if osz else 'W') if op & 1 else 'B'))
        if op in (0x06, 0x0E, 0x16, 0x1E):
            return R('PUSH ' + SREG[(op >> 3) & 3])
        if op in (0x07, 0x17, 0x1F):
            return R('POP ' + SREG[(op >> 3) & 3])
        if op == 0x0F:
            op2 = self.b(i); i += 1
            if 0x80 <= op2 <= 0x8F:
                d, i2 = IW(i); i = i2
                sgn = d - (1 << (32 if osz else 16)) if d >> ((32 if osz else 16) - 1) else d
                t = i + sgn
                info['branch'] = t; info['cond'] = True
                return R('J%-3s %s (near)' % (CCN[op2 & 15], h(t & 0xFFFF, 4)))
            if 0x90 <= op2 <= 0x9F:
                i, mod, reg, rm, ea = self.modrm(i, 0, segpfx, R16)
                return R('SET%s %s' % (CCN[op2 & 15], ea))
            if op2 in (0xB6, 0xB7, 0xBE, 0xBF):
                i, mod, reg, rm, ea = self.modrm(i, op2 & 1, segpfx, R16)
                return R('MOV%sX %s,%s' % ('S' if op2 >= 0xBE else 'Z', R16[reg], ea))
            if op2 == 0x01:
                i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, REG16)
                return R('%s %s' % (['SGDT','SIDT','LGDT','LIDT','SMSW','?','LMSW','INVLPG'][reg], ea))
            if op2 == 0x00:
                i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, REG16)
                return R('%s %s' % (['SLDT','STR','LLDT','LTR','VERR','VERW','?','?'][reg], ea))
            if op2 in (0x20, 0x22):
                m = self.b(i); i += 1
                cr = 'CR%d' % ((m >> 3) & 7)
                rr = REG32[m & 7]
                return R('MOV %s,%s' % ((rr, cr) if op2 == 0x20 else (cr, rr)))
            if op2 == 0xA2: return R('CPUID')
            return R('DB 0Fh,%s' % h(op2, 1))
        if op == 0x27: return R('DAA')
        if op == 0x2F: return R('DAS')
        if op == 0x37: return R('AAA')
        if op == 0x3F: return R('AAS')
        if 0x40 <= op <= 0x47: return R('INC ' + R16[op & 7])
        if 0x48 <= op <= 0x4F: return R('DEC ' + R16[op & 7])
        if 0x50 <= op <= 0x57: return R('PUSH ' + R16[op & 7])
        if 0x58 <= op <= 0x5F: return R('POP ' + R16[op & 7])
        if 0x70 <= op <= 0x7F:
            d = self.b(i); i += 1
            t = i + (d - 256 if d & 0x80 else d)
            info['branch'] = t; info['cond'] = True
            return R('J%-3s %s' % (CCN[op & 15], h(t & 0xFFFF, 4)))
        if op in (0x80, 0x81, 0x82, 0x83):
            wbit = op & 1
            i, mod, reg, rm, ea = self.modrm(i, wbit, segpfx, R16)
            if op in (0x80, 0x82):
                imm = self.b(i); i += 1; s = h(imm, 1)
            elif op == 0x81:
                imm, i = IW(i); s = h(imm, HW)
            else:
                imm = self.b(i); i += 1
                v = imm - 256 if imm & 0x80 else imm
                s = h(v & 0xFFFF, 2)
            if mod != 3 and not ea.endswith(('AX','CX','DX','BX','SP','BP','SI','DI')):
                ea = ('WORD PTR ' if wbit else 'BYTE PTR ') + ea
            info['imm'] = imm
            return R('%s %s,%s' % (ARITH[reg], ea, s))
        if op in (0x84, 0x85):
            wbit = op & 1
            i, mod, reg, rm, ea = self.modrm(i, wbit, segpfx, R16)
            return R('TEST %s,%s' % (ea, (R16 if wbit else REG8)[reg]))
        if op in (0x86, 0x87):
            wbit = op & 1
            i, mod, reg, rm, ea = self.modrm(i, wbit, segpfx, R16)
            return R('XCHG %s,%s' % (ea, (R16 if wbit else REG8)[reg]))
        if 0x88 <= op <= 0x8B:
            wbit = op & 1
            i, mod, reg, rm, ea = self.modrm(i, wbit, segpfx, R16)
            r = (R16 if wbit else REG8)[reg]
            if op < 0x8A:
                return R('MOV %s,%s' % (ea, r))
            return R('MOV %s,%s' % (r, ea))
        if op == 0x8C:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            return R('MOV %s,%s' % (ea, SREG[reg & 3]))
        if op == 0x8E:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            return R('MOV %s,%s' % (SREG[reg & 3], ea))
        if op == 0x8D:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            return R('LEA %s,%s' % (R16[reg], ea))
        if op == 0x8F:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            return R('POP %s' % ea)
        if op == 0x90: return R('NOP')
        if 0x91 <= op <= 0x97: return R('XCHG %s,%s' % (R16[0], R16[op & 7]))
        if op == 0x98: return R('CWDE' if osz else 'CBW')
        if op == 0x99: return R('CDQ' if osz else 'CWD')
        if op == 0x9A:
            o = self.w(i); s = self.w(i + 2); i += 4
            info['farcall'] = (s, o)
            return R('CALL FAR %s:%s' % (h(s, 4), h(o, 4)))
        if op == 0x9B: return R('WAIT')
        if op == 0x9C: return R('PUSHF')
        if op == 0x9D: return R('POPF')
        if op == 0x9E: return R('SAHF')
        if op == 0x9F: return R('LAHF')
        if 0xA0 <= op <= 0xA3:
            a = self.w(i); i += 2
            pfx = (segpfx + ':') if segpfx else ''
            m = '%s[%s]' % (pfx, h(a, 4))
            r = R16[0] if (op & 1) else 'AL'
            if op < 0xA2:
                return R('MOV %s,%s' % (r, m))
            return R('MOV %s,%s' % (m, r))
        if op in (0xA4, 0xA5):
            return R('MOVS' + (('D' if osz else 'W') if op & 1 else 'B'))
        if op in (0xA6, 0xA7):
            return R('CMPS' + (('D' if osz else 'W') if op & 1 else 'B'))
        if op in (0xA8, 0xA9):
            if op == 0xA8:
                imm = self.b(i); i += 1; info['imm'] = imm
                return R('TEST AL,%s' % h(imm, 1))
            imm, i = IW(i); info['imm'] = imm
            return R('TEST %s,%s' % (R16[0], h(imm, HW)))
        if op in (0xAA, 0xAB): return R('STOS' + (('D' if osz else 'W') if op & 1 else 'B'))
        if op in (0xAC, 0xAD):
            s = ('CS:' if segpfx == 'CS' else (segpfx + ':' if segpfx else ''))
            return R('%sLODS%s' % (s, ('D' if osz else 'W') if op & 1 else 'B'))
        if op in (0xAE, 0xAF): return R('SCAS' + (('D' if osz else 'W') if op & 1 else 'B'))
        if 0xB0 <= op <= 0xB7:
            imm = self.b(i); i += 1; info['imm'] = imm
            return R('MOV %s,%s' % (REG8[op & 7], h(imm, 1)))
        if 0xB8 <= op <= 0xBF:
            imm, i = IW(i); info['imm'] = imm
            return R('MOV %s,%s' % (R16[op & 7], h(imm, HW)))
        if op in (0xC0, 0xC1):
            wbit = op & 1
            i, mod, reg, rm, ea = self.modrm(i, wbit, segpfx, R16)
            cnt = self.b(i); i += 1
            if mod != 3:
                ea = (('DWORD PTR ' if osz else 'WORD PTR ') if wbit else 'BYTE PTR ') + ea
            return R('%s %s,%s' % (SHIFT[reg], ea, h(cnt, 1)))
        if op == 0xC2:
            imm = self.w(i); i += 2
            info['ret'] = True
            return R('RET %s' % h(imm, 4))
        if op == 0xC3:
            info['ret'] = True
            return R('RET')
        if op in (0xC4, 0xC5):
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            return R('%s %s,%s' % ('LES' if op == 0xC4 else 'LDS', R16[reg], ea))
        if op in (0xC6, 0xC7):
            wbit = op & 1
            i, mod, reg, rm, ea = self.modrm(i, wbit, segpfx, R16)
            if wbit:
                imm, i = IW(i); s = h(imm, HW)
            else:
                imm = self.b(i); i += 1; s = h(imm, 1)
            info['imm'] = imm
            if mod != 3:
                ea = ('WORD PTR ' if wbit else 'BYTE PTR ') + ea
            return R('MOV %s,%s' % (ea, s))
        if op == 0xC8:
            imm = self.w(i); i += 2; n = self.b(i); i += 1
            return R('ENTER %s,%s' % (h(imm, 4), h(n, 1)))
        if op == 0xC9:
            return R('LEAVE')
        if op == 0xCA:
            imm = self.w(i); i += 2
            info['ret'] = True
            return R('RETF %s' % h(imm, 4))
        if op == 0xCB:
            info['ret'] = True
            return R('RETF')
        if op == 0xCC: return R('INT 3')
        if op == 0xCD:
            imm = self.b(i); i += 1
            return R('INT %s' % h(imm, 1))
        if op == 0xCE: return R('INTO')
        if op == 0xCF:
            info['ret'] = True
            return R('IRET')
        if 0xD0 <= op <= 0xD3:
            wbit = op & 1
            i, mod, reg, rm, ea = self.modrm(i, wbit, segpfx, R16)
            if mod != 3:
                ea = (('DWORD PTR ' if osz else 'WORD PTR ') if wbit else 'BYTE PTR ') + ea
            cnt = 'CL' if op >= 0xD2 else '1'
            return R('%s %s,%s' % (SHIFT[reg], ea, cnt))
        if op == 0xD4:
            i += 1; return R('AAM')
        if op == 0xD5:
            i += 1; return R('AAD')
        if op == 0xD7: return R('XLAT')
        if 0xD8 <= op <= 0xDF:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            return R('ESC %d,%s' % (op & 7, ea))
        if 0xE0 <= op <= 0xE3:
            d = self.b(i); i += 1
            t = i + (d - 256 if d & 0x80 else d)
            info['branch'] = t; info['cond'] = True
            n = ['LOOPNE', 'LOOPE', 'LOOP', 'JCXZ'][op & 3]
            return R('%s %s' % (n, h(t & 0xFFFF, 4)))
        if op in (0xE4, 0xE5):
            p = self.b(i); i += 1
            info['io'] = ('IN', p, op & 1)
            return R('IN %s,%s' % (R16[0] if op & 1 else 'AL', h(p, 1)))
        if op in (0xE6, 0xE7):
            p = self.b(i); i += 1
            info['io'] = ('OUT', p, op & 1)
            return R('OUT %s,%s' % (h(p, 1), R16[0] if op & 1 else 'AL'))
        if op == 0xE8:
            d = self.w(i); i += 2
            t = i + (d - 65536 if d & 0x8000 else d)
            info['call'] = t
            return R('CALL %s' % h(t & 0xFFFF, 4))
        if op == 0xE9:
            d = self.w(i); i += 2
            t = i + (d - 65536 if d & 0x8000 else d)
            info['branch'] = t; info['jmp'] = True
            return R('JMP %s' % h(t & 0xFFFF, 4))
        if op == 0xEA:
            o = self.w(i); s = self.w(i + 2); i += 4
            info['farjmp'] = (s, o); info['jmp'] = True
            return R('JMP FAR %s:%s' % (h(s, 4), h(o, 4)))
        if op == 0xEB:
            d = self.b(i); i += 1
            t = i + (d - 256 if d & 0x80 else d)
            info['branch'] = t; info['jmp'] = True
            return R('JMP SHORT %s' % h(t & 0xFFFF, 4))
        if op in (0xEC, 0xED):
            info['io'] = ('IN', 'DX', op & 1)
            return R('IN %s,DX' % (R16[0] if op & 1 else 'AL'))
        if op in (0xEE, 0xEF):
            info['io'] = ('OUT', 'DX', op & 1)
            return R('OUT DX,%s' % (R16[0] if op & 1 else 'AL'))
        if op == 0xF4: info['jmp'] = True; return R('HLT')
        if op == 0xF5: return R('CMC')
        if op in (0xF6, 0xF7):
            wbit = op & 1
            i, mod, reg, rm, ea = self.modrm(i, wbit, segpfx, R16)
            nm = GRP3[reg]
            if mod != 3:
                ea = ('WORD PTR ' if wbit else 'BYTE PTR ') + ea
            if reg in (0, 1):
                if wbit:
                    imm, i = IW(i); s = h(imm, HW)
                else:
                    imm = self.b(i); i += 1; s = h(imm, 1)
                info['imm'] = imm
                return R('TEST %s,%s' % (ea, s))
            return R('%s %s' % (nm, ea))
        if op == 0xF8: return R('CLC')
        if op == 0xF9: return R('STC')
        if op == 0xFA: return R('CLI')
        if op == 0xFB: return R('STI')
        if op == 0xFC: return R('CLD')
        if op == 0xFD: return R('STD')
        if op == 0xFE:
            i, mod, reg, rm, ea = self.modrm(i, 0, segpfx, R16)
            if mod != 3: ea = 'BYTE PTR ' + ea
            return R(('INC ' if reg == 0 else 'DEC ') + ea)
        if op == 0xFF:
            i, mod, reg, rm, ea = self.modrm(i, 1, segpfx, R16)
            names = ['INC', 'DEC', 'CALL', 'CALL FAR', 'JMP', 'JMP FAR', 'PUSH', '?']
            if reg in (4, 5):
                info['jmp'] = True; info['indirect'] = ea
            if reg in (2, 3):
                info['indirectcall'] = ea
            if mod != 3 and reg in (0, 1, 6):
                ea = 'WORD PTR ' + ea
            return R('%s %s' % (names[reg], ea))
        return R('DB %s' % h(op, 1))

def main():
    a = sys.argv
    rom = open(a[1], 'rb').read()
    base = int(a[2], 16)
    d = Dis(rom, base)
    if a[3] == '-r':
        start = int(a[4], 16); end = int(a[5], 16)
        pc = start
        while pc < end:
            try:
                n, t, info = d.decode(pc)
            except IndexError:
                break
            raw = ''.join('%02X' % x for x in rom[pc - base:n - base])
            print('F8%04X  %-16s %s' % (pc, raw, t))
            pc = n
    else:
        start = int(a[3], 16); cnt = int(a[4]) if len(a) > 4 else 40
        pc = start
        for _ in range(cnt):
            n, t, info = d.decode(pc)
            raw = ''.join('%02X' % x for x in rom[pc - base:n - base])
            print('F8%04X  %-16s %s' % (pc, raw, t))
            pc = n

main()
