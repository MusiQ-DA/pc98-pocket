#!/usr/bin/env python3
"""z86_fuzz.py -- random-program differential test: z86 vs Unicorn.

    python3 -m venv /tmp/v && /tmp/v/bin/pip install unicorn
    SIM_OUT=/tmp/z86loop bash scripts/sim_z86_loop.sh +n=1     # build tb
    N=200 LEN=60 /tmp/v/bin/python scripts/z86_fuzz.py /tmp/z86loop/loop

Programs run at 0000:1000 with DS=ES=0200 (data 2000-2FFF) and SS=0300
(stack 3000-3FFF); pointer registers only hold values that keep every
access inside those windows. The epilogue stores the registers at
0000:0600, and memory 0000-3FFF is compared with Unicorn's after the run.
A failing program is shrunk to its shortest failing prefix of blocks.

Not compared: flags an instruction leaves undefined (each such block ends
in TEST AL,0, and AF is masked at the end) and PUSH SP, where z86 pushes
the decremented SP like the 8086/V30 and Unicorn the 286's old one.
"""
import os, random, subprocess, sys, tempfile

from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR
from unicorn.x86_const import (UC_X86_REG_CS, UC_X86_REG_IP, UC_X86_REG_SS,
                               UC_X86_REG_SP, UC_X86_REG_EFLAGS)

LOOP = sys.argv[1] if len(sys.argv) > 1 else '/tmp/z86loop/loop'
# IRQ=<clocks>: tb_z86_loop raises INTR that often (vector 20h); the handler
# only counts. Results must not change. Memory below SP is fair game for an
# interrupt frame, so this mode leaves out BP-relative random accesses and
# the stack window from the comparison.
IRQ = int(os.environ.get('IRQ', '0'))

R16 = ['ax', 'cx', 'dx']
R8 = ['al', 'ah', 'cl', 'ch', 'dl', 'dh']
ALU = ['add', 'or', 'adc', 'sbb', 'and', 'sub', 'xor', 'cmp']
FL_ARITH = 0x8D5   # CF PF AF ZF SF OF
FL_LOGIC = 0x8C5   # AF undefined


def mem_operand(rng, word):
    size = 'word' if word else 'byte'
    forms = ['bx', 'si', 'di', 'bx+si', 'bx+di', 'abs']
    if not IRQ:
        forms += ['bp', 'bp+si', 'bp+di']
    form = rng.choice(forms)
    if form == 'abs':
        return f'{size} [0x{rng.randrange(0, 0x7F0):x}]'
    d = rng.choice(['', f'+{rng.randrange(0, 0x7f)}', f'+0x{rng.randrange(0x80, 0x200):x}'])
    return f'{size} [{form}{d}]'


def imm(rng, word):
    v = rng.choice([0, 1, 0x7f, 0x80, 0xff, 0x7fff, 0x8000, 0xffff, rng.randrange(0, 0x10000)])
    return v & (0xffff if word else 0xff)


def gen_block(rng, lab):
    k = rng.randrange(52)
    w = rng.random() < 0.6
    r = rng.choice(R16) if w else rng.choice(R8)
    out = []
    if k < 8:
        op = rng.choice(ALU)
        src = rng.choice(['reg', 'mem', 'imm'])
        if src == 'reg':
            s = rng.choice(R16 + ['bx', 'si', 'di', 'bp', 'sp']) if w else rng.choice(R8 + ['bl', 'bh'])
            out.append(f'{op} {r},{s}')
        elif src == 'mem':
            out.append(f'{op} {r},{mem_operand(rng, w)}' if rng.random() < 0.5
                       else f'{op} {mem_operand(rng, w)},{r}')
        else:
            out.append(f'{op} {r},0x{imm(rng, w):x}' if rng.random() < 0.5
                       else f'{op} {mem_operand(rng, w)},0x{imm(rng, w):x}')
        if rng.random() < 0.3:
            m = FL_LOGIC if op in ('and', 'or', 'xor') else FL_ARITH
            out += ['pushf', 'pop ax', f'and ax,0x{m:x}', f'mov [0x{rng.randrange(0x700, 0x7f0) & ~1:x}],ax']
    elif k < 12:
        c = rng.randrange(6)
        if c == 0: out.append(f'mov {r},{mem_operand(rng, w)}')
        elif c == 1: out.append(f'mov {mem_operand(rng, w)},{r}')
        elif c == 2: out.append(f'mov {r},0x{imm(rng, w):x}')
        elif c == 3: out.append(f'mov {mem_operand(rng, w)},0x{imm(rng, w):x}')
        elif c == 4: out.append(f'mov {"ax" if w else "al"},[0x{rng.randrange(0, 0x7f0):x}]')
        else: out.append(f'mov [0x{rng.randrange(0, 0x7f0):x}],{"ax" if w else "al"}')
    elif k < 14:
        out.append(f'{rng.choice(["inc", "dec", "neg", "not"])} {rng.choice([r, mem_operand(rng, w)])}')
    elif k < 16:
        out.append(f'test {r},{rng.choice([mem_operand(rng, w), "0x%x" % imm(rng, w)])}')
    elif k < 19:
        c = rng.randrange(4)
        if c == 0: out += [f'push {rng.choice(R16 + ["bx", "si", "di", "bp"])}', f'pop {rng.choice(R16)}']
        elif c == 1: out += [f'push 0x{imm(rng, True):x}', f'pop {rng.choice(R16)}']
        elif c == 2: out += [f'push {mem_operand(rng, True)}', f'pop {mem_operand(rng, True)}']
        else: out += ['pusha', f'mov ax,0x{imm(rng, True):x}', 'popa']
    elif k < 21:
        out.append(f'xchg {r},{rng.choice([mem_operand(rng, w), rng.choice(R16) if w else rng.choice(R8)])}')
    elif k < 22:
        out.append('xlat')
    elif k < 24:
        op = rng.choice(['shl', 'shr', 'sar', 'rol', 'ror', 'rcl', 'rcr'])
        cnt = rng.choice(['1', 'cl', str(rng.randrange(0, 20))])
        if cnt == 'cl':
            out.append('and cl,0x1f')
        out.append(f'{op} {rng.choice([r, mem_operand(rng, w)])},{cnt}')
        if cnt != '1':
            out.append('test al,0')          # OF undefined for counts other than 1
    elif k < 26:
        c = rng.randrange(5)
        if c == 0: out.append(f'mul {rng.choice(["cl", "dl", "byte [bx+3]"])}')
        elif c == 1: out.append(f'mul {rng.choice(["cx", "word [si+4]"])}')
        elif c == 2: out.append(f'imul {rng.choice(["cx", "dx", "word [di+6]"])}')
        elif c == 3: out += ['xor dx,dx', 'or cx,1', 'div cx']
        else: out += ['and ax,0x7fff', 'cwd', 'or cx,1', 'and cx,0x7fff', 'idiv cx']
        out.append('test al,0')              # MUL/DIV leave most flags undefined
    elif k < 28:
        c = rng.randrange(4)
        if c == 0: out += [f'imul {rng.choice(R16)},{rng.choice(R16 + ["word [bx+2]"])},{rng.randrange(-128, 128)}', 'test al,0']
        elif c == 1: out.append('cbw')
        elif c == 2: out.append('cwd')
        else: out.append(rng.choice(['clc', 'stc', 'cmc', 'lahf', 'sahf']))
    elif k < 31:
        out += [f'mov si,0x{rng.randrange(0x200, 0x600):x}', f'mov di,0x{rng.randrange(0x200, 0x600):x}',
                f'mov cx,{rng.randrange(0, 9)}', rng.choice(['cld', 'std'])]
        op = rng.choice(['movsb', 'movsw', 'stosb', 'stosw', 'lodsb', 'lodsw', 'cmpsb', 'cmpsw', 'scasb', 'scasw'])
        rep = rng.choice(['', 'rep ']) if op[:4] in ('movs', 'stos', 'lods') else rng.choice(['', 'repe ', 'repne '])
        # a source segment override (both prefix orders) on the forms that
        # read DS:SI -- an interrupt must resume the REP with it intact
        seg = rng.choice(['', '', 'es ', 'ss ', 'cs ']) if op[:4] in ('movs', 'lods', 'cmps') else ''
        if seg and rep and rng.random() < 0.5:
            out.append(f'{seg}{rep}{op}')
        else:
            out.append(f'{rep}{seg}{op}')
        out += ['cld', 'mov cx,0x%x' % imm(rng, True)]
    elif k < 32:
        out += ['mov bp,sp', f'enter {rng.randrange(0, 16) * 2},0', f'mov word [bp-2],0x{imm(rng, True):x}',
                f'mov {rng.choice(R16)},[bp-2]', 'leave']
    elif k < 34:
        out += [f'call {lab}s', f'jmp {lab}e', f'{lab}s:', f'mov {rng.choice(R16)},0x{imm(rng, True):x}',
                'ret', f'{lab}e:']
    elif k < 36:
        cc = rng.choice(['jz', 'jnz', 'jc', 'jnc', 'js', 'jns', 'jo', 'jno', 'jp', 'jnp',
                         'ja', 'jbe', 'jl', 'jge', 'jle', 'jg'])
        out += [f'{rng.choice(ALU)} {r},0x{imm(rng, w):x}', f'{cc} {lab}e',
                f'mov {rng.choice(R16)},0x{imm(rng, True):x}', f'{lab}e:']
    elif k < 37:
        out += [f'mov cx,{rng.randrange(1, 6)}', f'{lab}l:', f'add {rng.choice(["ax", "dx"])},cx', f'loop {lab}l']
    elif k < 38:
        out += [f'les {rng.choice(["ax", "dx"])},[bx+0x10]', 'push word 0x200', 'pop es']
    elif k < 39:
        if rng.random() < 0.5:
            out.append(f'lea {rng.choice(R16)},[bx+si+0x{rng.randrange(0, 0x100):x}]')
        else:
            # self-modifying code: patch an immediate beyond a 286's 6-byte
            # prefetch queue, then run it (the fetch buffer must see the
            # store). Closer than that is undefined on the real CPU too.
            out += [f'mov byte [cs:{lab}p+1],0x{rng.randrange(256):x}'] + ['nop'] * rng.randrange(6, 14) + \
                   [f'{lab}p:', f'mov al,0x{rng.randrange(256):x}', f'add {rng.choice(["dl", "cl"])},al']
    elif k == 40:
        out += [f'call 0:{lab}s', f'jmp {lab}e', f'{lab}s:', f'mov {rng.choice(R16)},0x{imm(rng, True):x}',
                'retf', f'{lab}e:']
    elif k == 41:
        out += [f'mov word [cs:0x200],{lab}s', 'mov word [cs:0x202],0',
                f'{rng.choice(ALU)} {r},0x{imm(rng, w):x}', 'int 0x80', f'jmp {lab}e', f'{lab}s:',
                f'mov {rng.choice(R16)},0x{imm(rng, True):x}', 'pushf', 'pop ax', 'and ax,0x8c5',
                'mov [0x7f0],ax', 'iret', f'{lab}e:']
    elif k == 42:
        out += ['push ds', 'pop es', 'push es', 'pop ds', f'mov {rng.choice(R16)},es', f'mov {r},{mem_operand(rng, w)}']
    elif k == 43:
        out += [f'mov word [0x10],{lab}s', 'call word [0x10]', f'jmp {lab}e', f'{lab}s:',
                f'add {rng.choice(R16)},0x{imm(rng, True):x}', 'ret', f'{lab}e:']
    elif k == 44:
        out += [f'mov word [bx+0x20],{lab}e', 'jmp word [bx+0x20]', f'mov {rng.choice(R16)},0x1234', f'{lab}e:']
    elif k == 45:
        out += ['push word 0x1111', 'push word 0x2222', f'call {lab}s', f'jmp {lab}e', f'{lab}s:', 'ret 4', f'{lab}e:']
    elif k == 46:
        out += [f'mov cx,{rng.randrange(0, 3)}', f'jcxz {lab}e', f'inc {rng.choice(["ax", "dx"])}', f'{lab}e:']
    elif k == 47:
        out += [f'mov cx,{rng.randrange(1, 6)}', f'{lab}l:', f'{rng.choice(["cmp", "sub"])} al,cl',
                f'{rng.choice(["loopz", "loopnz"])} {lab}l',
                'test al,0']    # Unicorn rewrites the flags on a LOOPcc exit
    elif k == 48:
        # AAA/AAS left out: z86 adjusts AH like the 8086/V30 (AH+1), Unicorn
        # like the 386 (AX+106h). DAA/DAS read AF, so define it first.
        out += [f'add al,{rng.randrange(256)}', rng.choice(['daa', 'das', 'aam', 'aad']), 'test al,0']
    elif k == 49:
        out += [f'mov word [0x14],0x{rng.randrange(0x100):x}', 'mov word [0x16],0x200',
                f'lds {rng.choice(["ax", "dx"])},[0x14]', f'mov {r},{mem_operand(rng, w)}']
    elif k == 50:
        out += [f'mov {rng.choice(R16)},sp', f'mov {rng.choice(R16)},ss', 'push ss', 'pop ss']
    else:
        out.append(f'mov {rng.choice(["bx", "si", "di"])},0x{rng.randrange(0, 0x500):x}')
    return out


ORG = 0x1000    # clear of the 0600 result block and the 0800 tb data
PRO = '''bits 16
org 0x1000
    mov ax,0x200
    mov ds,ax
    mov es,ax
    mov ax,0x300
    mov ss,ax
    mov sp,0xF00
    mov bp,0xE00
    mov word [cs:0x80],irq_h
    mov word [cs:0x82],0
    push word 0x0202
    popf
    jmp irq_e
irq_h:
    inc word [cs:0x6F0]
    iret
irq_e:
'''
EPI = '''    mov [cs:0x600],ax
    pushf
    pop ax
    mov [cs:0x616],ax
    mov [cs:0x602],cx
    mov [cs:0x604],dx
    mov [cs:0x606],bx
    mov [cs:0x608],si
    mov [cs:0x60A],di
    mov [cs:0x60C],bp
    mov [cs:0x60E],sp
    mov [cs:0x610],ss
    mov [cs:0x612],es
    mov [cs:0x614],ds
    times 8 nop
    hlt
'''
REGS = ['ax', 'cx', 'dx', 'bx', 'si', 'di', 'bp', 'sp', 'ss', 'es', 'ds', 'fl']


def build(seed, n):
    rng = random.Random(seed)
    body = [[f'mov ax,0x{rng.randrange(65536):x}', f'mov cx,0x{rng.randrange(65536):x}',
             f'mov dx,0x{rng.randrange(65536):x}', f'mov bx,0x{rng.randrange(0x500):x}',
             f'mov si,0x{rng.randrange(0x500):x}', f'mov di,0x{rng.randrange(0x500):x}']]
    for i in range(n):
        body.append(gen_block(rng, f'L{i}_'))
    return body


def asm(blocks, path):
    lines = [l for b in blocks for l in b]
    src = PRO + ''.join((l if l.endswith(':') else '    ' + l) + '\n' for l in lines) + EPI
    open(path + '.asm', 'w').write(src)
    subprocess.run(['nasm', '-f', 'bin', path + '.asm', '-o', path + '.bin'], check=True)
    return open(path + '.bin', 'rb').read()


def ref(code, wlog=None):
    mu = Uc(UC_ARCH_X86, UC_MODE_16)
    mu.mem_map(0, 0x100000)
    mu.mem_write(0, b'\x90' * 0x100000)          # tb_z86_loop's fill
    mu.mem_write(ORG, code + b'\xf4' * (4096 - len(code)))
    for i in range(256):
        mu.mem_write(0x800 + 2 * i, ((i * 0x0123 + 0x4567) & 0xffff).to_bytes(2, 'little'))
    mu.reg_write(UC_X86_REG_CS, 0)
    mu.reg_write(UC_X86_REG_IP, ORG)

    def on_int(uc, intno, _):
        # Unicorn hands real-mode INT to the host: push FLAGS, CS, IP; clear IF/TF
        ss = uc.reg_read(UC_X86_REG_SS); sp = uc.reg_read(UC_X86_REG_SP)
        fl = uc.reg_read(UC_X86_REG_EFLAGS) & 0xffff
        for v in (fl, uc.reg_read(UC_X86_REG_CS), uc.reg_read(UC_X86_REG_IP)):
            sp = (sp - 2) & 0xffff
            uc.mem_write(ss * 16 + sp, v.to_bytes(2, 'little'))
            if wlog is not None:   # API writes bypass the write hook
                wlog.extend([(ss * 16 + sp, v & 0xff, -1), (ss * 16 + sp + 1, v >> 8, -1)])
        uc.reg_write(UC_X86_REG_SP, sp)
        uc.reg_write(UC_X86_REG_EFLAGS, fl & ~0x300)
        vec = uc.mem_read(intno * 4, 4)
        uc.reg_write(UC_X86_REG_CS, int.from_bytes(vec[2:4], 'little'))
        uc.reg_write(UC_X86_REG_IP, int.from_bytes(vec[0:2], 'little'))
    mu.hook_add(UC_HOOK_INTR, on_int)
    if wlog is not None:
        from unicorn import UC_HOOK_MEM_WRITE
        def on_wr(uc, access, addr, size, value, _):
            ip = uc.reg_read(UC_X86_REG_CS) * 16 + uc.reg_read(UC_X86_REG_IP)
            for i in range(size):
                wlog.append((addr + i, (value >> (8 * i)) & 0xff, ip))
        mu.hook_add(UC_HOOK_MEM_WRITE, on_wr)
    end = ORG + len(code) - 1            # the final HLT
    try:
        # Redirecting CS:IP from the INT hook ends emu_start; resume from there.
        for _ in range(10000):
            pc = mu.reg_read(UC_X86_REG_CS) * 16 + mu.reg_read(UC_X86_REG_IP)
            if pc == end:
                break
            mu.emu_start(pc, end, count=2_000_000)
        else:
            return None
    except Exception:  # Unicorn's own gaps (some 186 forms) -- not a z86 verdict
        return None
    return bytes(mu.mem_read(0, 0x4000))


def dut(code, path, lat):
    open(path + '.hex', 'w').write(''.join(f'{b:02x}\n' for b in code))
    r = subprocess.run([LOOP, '+org=1000', f'+prog={path}.hex', f'+lat={lat}', f'+dump={path}.dump']
                       + ([f'+irq={IRQ}'] if IRQ else []) + (['+latrand'] if os.environ.get('LATRAND') else [])
                       + os.environ.get('EXTRA', '').split(),
                       capture_output=True, text=True)
    if 'TIMEOUT' in r.stdout:
        return None
    return bytes(int(l, 16) for l in open(path + '.dump')
                 if l.strip() and not l.startswith('//'))


def diff(a, b):
    out = []
    for i, name in enumerate(REGS):
        x = int.from_bytes(a[0x600 + 2 * i:0x602 + 2 * i], 'little')
        y = int.from_bytes(b[0x600 + 2 * i:0x602 + 2 * i], 'little')
        if name == 'fl':
            x &= FL_LOGIC; y &= FL_LOGIC
        if x != y:
            out.append(f'{name} ref={x:04x} z86={y:04x}')
    for lo, hi in ((0x700, 0x800), (0x2000, 0x2800)) + (() if IRQ else ((0x3000, 0x4000),)):
        for i in range(lo, hi):
            m = 0xEF if i == 0x3EFE else 0xFF   # the epilogue's PUSHF: AF undefined
            if (a[i] ^ b[i]) & m:
                out.append(f'mem {i:05x} ref={a[i]:02x} z86={b[i]:02x}')
                break
    return out


def check(blocks, path, lat):
    code = asm(blocks, path)
    a = ref(code)
    if a is None:
        return []
    b = dut(code, path, lat)
    return ['TIMEOUT'] if b is None else diff(a, b)


def why(path, lat):
    """First store where z86's write stream leaves the reference's."""
    code = open(path + '.bin', 'rb').read()
    rw = []
    ref(code, rw)
    open(path + '.hex', 'w').write(''.join(f'{b:02x}\n' for b in code))
    subprocess.run([LOOP, '+org=1000', f'+prog={path}.hex', f'+lat={lat}', f'+wlog={path}.wlog'],
                   capture_output=True, text=True)
    zw = [tuple(int(x, 16) for x in l.split()) for l in open(path + '.wlog')]
    for i, (r, z) in enumerate(zip(rw, zw)):
        if (r[0], r[1]) != z:
            print(f'write #{i}: ref {r[0]:05x}={r[1]:02x} (ip {r[2]:05x}, prog+{r[2] - ORG:x})  z86 {z[0]:05x}={z[1]:02x}')
            for j in range(max(0, i - 4), i):
                print(f'   before: {rw[j][0]:05x}={rw[j][1]:02x} ip {rw[j][2] - ORG:x}')
            return
    print(f'write streams agree ({len(rw)} ref, {len(zw)} z86)')


if __name__ == '__main__' and len(sys.argv) > 3 and sys.argv[2] == '--why':
    why(sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 1)
    sys.exit(0)

if __name__ == '__main__':
    n_prog = int(os.environ.get('N', '50'))
    length = int(os.environ.get('LEN', '60'))
    seed0 = int(os.environ.get('SEED', '1'))
    work = tempfile.mkdtemp(prefix='z86fuzz')
    bad = 0
    for s in range(seed0, seed0 + n_prog):
        blocks = build(s, length)
        for lat in ((5, 9) if os.environ.get('LATRAND') else (1, 3)):
            d = check(blocks, f'{work}/p', lat)
            if d:
                bad += 1
                lo, hi = 0, len(blocks)
                while lo < hi:
                    mid = (lo + hi) // 2
                    if check(blocks[:mid], f'{work}/q', lat):
                        hi = mid
                    else:
                        lo = mid + 1
                check(blocks[:lo], f'{work}/seed{s}', lat)   # keep the shrunk program
                print(f'seed {s} lat {lat}: {d[:3]}  ({work}/seed{s}.asm)')
                print(f'   shrunk to {lo} blocks; last: {blocks[max(0, lo - 3):lo]}', flush=True)
                break
    print(f'{bad} failing of {n_prog}')
    sys.exit(1 if bad else 0)
