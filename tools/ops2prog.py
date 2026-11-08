#!/usr/bin/env python3
"""ops2prog.py -- turn an np2kai np2ops capture into a z86 test program.

usage: ops2prog.py <in.ops> <out.hex> [max_ops]

The stream format is sim/golden/FORMAT.md (np2kai's np2ops recorder).
Run the result with tb_mem_perf +cursor=<out.hex> +analog4=1 [+cache].

The program (org 1000:0000, spills across segments with far jumps):
  1. GRCG off, seeds every touched plane byte (4 planes x 2 pages) with
     the capture's F value by plain writes;
  2. replays GM/GT/P/W8/W16/R8/R16 in order, comparing every read with the
     value np2kai returned;
  3. GRCG off, reads back every seeded byte and compares with a Python
     model of np21w's GRCG (TDW/RMW/TCR) run over the same ops.
A mismatch does OUT 88FCh four times: id lo, id hi, got lo, got hi;
<out.hex>.ids maps each id to its check.
Ends with OUT 88FEh,FFh ; JMP $.
"""
import sys

BASE = [0xA8000, 0xB0000, 0xB8000, 0xE0000]


def win(a):
    """(plane, offset) for a window address."""
    for p, b in enumerate(BASE):
        if b <= a < b + 0x8000:
            return p, a - b
    return None, None


ops = []
seed = {}
for line in open(sys.argv[1]):
    t = line.split()
    if not t:
        continue
    if t[0] == 'F':
        a = int(t[1], 16)
        seed[a] = int(t[2], 16)
        continue
    if t[0] == '#' and len(t) >= 3 and t[1] == 'P':
        ops.append(('P', int(t[2], 16)))
        continue
    if t[0] in ('GM', 'P'):
        ops.append((t[0], int(t[1], 16)))
    elif t[0] == 'GT':
        ops.append(('GT', int(t[1], 16), int(t[2], 16) & 0xFF))
    elif t[0] in ('W8', 'W16', 'R8', 'R16'):
        ops.append((t[0], int(t[1], 16), int(t[2], 16)))
maxn = int(sys.argv[3]) if len(sys.argv) > 3 else len(ops)
ops = ops[:maxn]

# ---- model -------------------------------------------------------------
mem = {}  # (page, plane, off) -> byte


def mget(pg, p, o):
    a = BASE[p] + o + (0x100000 if pg else 0)
    return mem.get((pg, p, o), seed.get(a, 0))


touched = set()
for op in ops:
    if op[0] in ('W8', 'W16', 'R8', 'R16'):
        n = 2 if op[0].endswith('16') else 1
        for k in range(n):
            p, o = win(op[1] + k)
            if p is not None:
                touched.add(o)

mode = 0
tiles = [0, 0, 0, 0]
tc = 0
page = 0
for op in ops:
    if op[0] == 'GM':
        mode = op[1]; tc = 0
    elif op[0] == 'GT':
        tiles[op[1]] = op[2]
    elif op[0] == 'P':
        page = op[1]
    elif op[0] in ('W8', 'W16'):
        n = 2 if op[0] == 'W16' else 1
        for k in range(n):
            a = op[1] + k
            v = (op[2] >> (8 * k)) & 0xFF
            p, o = win(a)
            if p is None:
                continue
            if mode & 0x80:
                for q in range(4):
                    if mode & (1 << q):
                        continue
                    old = mget(page, q, o)
                    new = ((old & ~v) | (v & tiles[q])) & 0xFF if mode & 0x40 else tiles[q]
                    mem[(page, q, o)] = new
            else:
                mem[(page, p, o)] = v

# ---- code --------------------------------------------------------------
code = bytearray()
SEG0 = 0x1000
segs = [SEG0]          # segment of each 32 KB chunk
CHUNK = 0x7F00


def cur_len():
    return len(code) % 0x8000


def emit(bs):
    global code
    if cur_len() + len(bs) > CHUNK:
        # far jump to the next 32 KB chunk
        nxt = len(code) - cur_len() + 0x8000
        seg = SEG0 + nxt // 16
        code += bytes([0xEA, 0, 0, seg & 0xFF, seg >> 8])
        code += bytes(nxt - len(code))
    code += bytes(bs)


def w(v):
    return [v & 0xFF, (v >> 8) & 0xFF]


cur_ds = [None]


def seg_for(a):
    s = (a >> 4) & 0xF000
    if cur_ds[0] != s:
        emit([0xB8] + w(s) + [0x8E, 0xD8])     # mov ax,s ; mov ds,ax
        cur_ds[0] = s
    return a - (s << 4)


def outb(port, v):
    emit([0xB0, v & 0xFF, 0xE6, port])         # mov al,v ; out port,al


idn = [0]
fails = []


def report_if_ne(kind):
    # after a compare: je over the report
    rep = [0x89, 0xC3,                          # mov bx,ax
           0xB8] + w(idn[0]) + [                # mov ax,id
           0xBA] + w(0x88FC) + [                # mov dx,88FC
           0xEE, 0x88, 0xE0, 0xEE,              # out dx,al ; mov al,ah ; out
           0x88, 0xD8, 0xEE, 0x88, 0xF8, 0xEE]  # mov al,bl ; out ; mov al,bh ; out
    emit([0x74, len(rep)] + rep)
    fails.append((idn[0], kind))
    idn[0] += 1


# prologue: CLI, SS:SP
emit([0xFA, 0x31, 0xC0, 0x8E, 0xD0, 0xBC] + w(0x0400))
outb(0x6A, 0x01)    # analog (sixteen-colour) mode: plane E at E0000
outb(0x7C, 0x00)
for pg in (0, 1):
    outb(0xA6, pg)
    for q in range(4):
        for o in sorted(touched):
            a = BASE[q] + o
            off = seg_for(a)
            emit([0xC6, 0x06] + w(off) + [seed.get(a + (0x100000 if pg else 0), 0)])

for op in ops:
    k = op[0]
    if k == 'GM':
        outb(0x7C, op[1])
    elif k == 'GT':
        outb(0x7E, op[2])
    elif k == 'P':
        outb(0xA6, op[1])
    elif k == 'W8':
        off = seg_for(op[1])
        emit([0xC6, 0x06] + w(off) + [op[2]])
    elif k == 'W16':
        off = seg_for(op[1])
        emit([0xC7, 0x06] + w(off) + w(op[2]))
    elif k == 'R8':
        off = seg_for(op[1])
        emit([0xA0] + w(off) + [0x30, 0xE4, 0x3D] + w(op[2]))   # mov al,[o]; xor ah,ah; cmp ax,v
        report_if_ne(('R8', op[1], op[2]))
    elif k == 'R16':
        off = seg_for(op[1])
        emit([0xA1] + w(off) + [0x3D] + w(op[2]))
        report_if_ne(('R16', op[1], op[2]))

# final read-back, GRCG off
outb(0x7C, 0x00)
for pg in (0, 1):
    outb(0xA6, pg)
    for q in range(4):
        for o in sorted(touched):
            a = BASE[q] + o
            want = mget(pg, q, o)
            off = seg_for(a)
            emit([0xA0] + w(off) + [0x30, 0xE4, 0x3D] + w(want))
            report_if_ne(('FIN', pg, a, want))

emit([0xB0, 0xFF, 0xBA] + w(0x88FE) + [0xEE, 0xEB, 0xFE])

with open(sys.argv[2], 'w') as f:
    for b in code:
        f.write('%02x\n' % b)
with open(sys.argv[2] + '.ids', 'w') as f:
    for i, kind in fails:
        f.write('%d %s\n' % (i, kind))
print('ops', len(ops), 'touched', len(touched), 'bytes', len(code), 'checks', len(fails))
