#!/usr/bin/env python3
"""ops2prog.py -- turn an np2kai np2ops capture into a z86 test program.

usage: ops2prog.py <in.ops> <out.hex> [max_ops] [--phase N] [--ref]

The stream format is sim/golden/FORMAT.md (np2kai's np2ops recorder).
Run the result with tb_mem_perf +cursor=<out.hex> +analog4=1 [+cache].

The program (org 1000:0000, spills across segments with far jumps):
  1. GRCG off, seeds every touched plane byte (4 planes x 2 pages) with
     the capture's F value by plain writes;
  2. replays GM/GT/P/W8/W16/R8/R16 in order, comparing every read with the
     value np2kai returned;
  3. GRCG off, reads back every seeded byte and compares with a Python
     model of np21w's GRCG (TDW/RMW/TCR) run over the same ops.
--phase N brackets step 2 with tb_mem_perf's phase markers (OUT 88FEh,N /
N|80h), so the bench prints the replay's own CPU clock count (ce_pos);
--ref also prints np21w's price for the bracketed code (80286 data-sheet
clocks plus np21w's per-access VRAM/GRCG waits and I/O bus clocks, the
same model as scripts/sim_cycle_table.sh) at 8/10/12 MHz.
A mismatch does OUT 88FCh four times: id lo, id hi, got lo, got hi;
<out.hex>.ids maps each id to its check.
Ends with OUT 88FEh,FFh ; JMP $.
"""
import sys

argv = [a for a in sys.argv[1:]]
phase = None
want_ref = False
if '--phase' in argv:
    i = argv.index('--phase')
    phase = int(argv[i + 1], 0)
    del argv[i:i + 2]
if '--ref' in argv:
    argv.remove('--ref')
    want_ref = True
sys.argv[1:] = argv

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
    if t[0] == 'PH':
        ops.append(('PH', int(t[1], 16)))
    elif t[0] in ('GM', 'P'):
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
    # after a compare: je over "mov dx,id ; int 60h" (the handler reports)
    emit([0x74, 5, 0xBA] + w(idn[0]) + [0xCD, 0x60])
    fails.append((idn[0], kind))
    idn[0] += 1


# prologue: CLI, SS:SP
emit([0xFA, 0x31, 0xC0, 0x8E, 0xD0, 0xBC] + w(0x0400))
# INT 60h = the mismatch report: OUT 88FCh x4 = id lo/hi (DX), got lo/hi (AX)
emit([0x8E, 0xD8,                                   # mov ds,ax (0)
      0xC7, 0x06] + w(0x180) + w(0x0000) + [         # IVT[60h].off (patched)
      0xC7, 0x06] + w(0x182) + w(SEG0))             # IVT[60h].seg
patch = len(code) - 8                                # the .off immediate
handler = ([0x50, 0x52, 0x89, 0xC3, 0x89, 0xD0,     # push ax/dx ; mov bx,ax ; mov ax,dx
            0xBA] + w(0x88FC) + [0xEE, 0x88, 0xE0, 0xEE,  # out id lo, hi
            0x88, 0xD8, 0xEE,                             # out got lo
            0x88, 0xF8, 0xEE, 0x5A, 0x58, 0xCF])          # out got hi ; pop ; iret
emit([0xEB, len(handler)])                           # jmp over the handler
code[patch:patch + 2] = bytes(w(len(code)))
emit(handler)
outb(0x6A, 0x01)    # analog (sixteen-colour) mode: plane E at E0000
outb(0x7C, 0x00)
for pg in (0, 1):
    outb(0xA6, pg)
    for q in range(4):
        for o in sorted(touched):
            a = BASE[q] + o
            off = seg_for(a)
            emit([0xC6, 0x06] + w(off) + [seed.get(a + (0x100000 if pg else 0), 0)])
# the model (and np2kai's capture) starts on access page 0: leave the
# seeding on page 1 and the first ops would land there
outb(0xA6, 0x00)

# np21w price of the replay below (see --ref): data-sheet clocks per emitted
# instruction plus pccore.c's VRAM/GRCG waits (averaged over the frame like
# sim_cycle_table.sh) and iocore.busclock per port access.
ACT = 400 / 440
VRAMW = round(6 * ACT + 1 * (1 - ACT))
GRCGW = round(8 * ACT + 1 * (1 - ACT))
ref = {'base': 0, 'io': 0}
ref_cls = {}


def charge(cls, clk, io=0):
    ref['base'] += clk
    ref['io'] += io
    c = ref_cls.setdefault(cls, [0, 0, 0])
    c[0] += 1
    c[1] += clk
    c[2] += io


cur_ph = [phase if phase is not None else 0x41]
ref_ph = []
if phase is not None:
    emit([0xB0, phase & 0x7F, 0xBA] + w(0x88FE) + [0xEE])
rmode = 0
for op in ops:
    k = op[0]
    pre = cur_ds[0]
    if k in ('W8', 'W16', 'R8', 'R16'):
        p_, o_ = win(op[1])
        wt = 0 if p_ is None else (GRCGW if (rmode & 0x80) and not (
            k[0] == 'R' and rmode & 0x40) else VRAMW)
    if k == 'GM':
        rmode = op[1]
        charge('OUT 7C', 2 + 3, 1)
    elif k == 'GT':
        charge('OUT 7E', 2 + 3, 1)
    elif k == 'P':
        charge('OUT A6', 2 + 3, 1)
    elif k == 'W8':
        charge(('GRCG ' if rmode & 0x80 else 'plain ') + k, 3 + wt)
    elif k == 'W16':
        charge(('GRCG ' if rmode & 0x80 else 'plain ') + k, 3 + wt)
    elif k == 'R8':
        charge(('TCR ' if (rmode & 0xC0) == 0x80 else 'plain ') + k, 5 + wt + 2 + 3 + 8)
    elif k == 'R16':
        charge(('TCR ' if (rmode & 0xC0) == 0x80 else 'plain ') + k, 5 + wt + 3 + 8)
    if k in ('W8', 'W16', 'R8', 'R16') and ((op[1] >> 4) & 0xF000) != pre:
        charge('ds reload', 4)
    if k == 'PH':
        # a sub-phase of its own: close the open one, open op[1]
        emit([0xB0, (cur_ph[0] & 0x7F) | 0x80, 0xBA] + w(0x88FE) + [0xEE])
        emit([0xB0, op[1] & 0x7F, 0xBA] + w(0x88FE) + [0xEE])
        cur_ph[0] = op[1]
        ref_ph.append((op[1], dict(ref)))
    elif k == 'GM':
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

if phase is not None or ref_ph:
    emit([0xB0, (cur_ph[0] & 0x7F) | 0x80, 0xBA] + w(0x88FE) + [0xEE])
    charge('phase markers', 0)
if want_ref and ref_ph:
    marks = ref_ph + [(None, dict(ref))]
    for (n, r0), (_, r1) in zip(marks, marks[1:]):
        print('np21w ref phase %02X: 10MHz %d  12MHz %d clocks' % (
            n, (r1['base'] - r0['base']) + (r1['io'] - r0['io']) * 4,
            (r1['base'] - r0['base']) + (r1['io'] - r0['io']) * 5))
if want_ref:
    for sp, iow in (('8MHz', 4), ('10MHz', 4), ('12MHz', 5)):
        print('np21w ref %s: %d clocks' % (sp, ref['base'] + ref['io'] * iow))
    for cls, (n, clk, io) in sorted(ref_cls.items()):
        print('  ref %-14s n=%7d  %7.2f clk/op @10MHz' % (cls, n, (clk + io * 4) / max(n, 1)))

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
