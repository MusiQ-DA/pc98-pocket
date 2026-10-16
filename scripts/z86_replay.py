#!/usr/bin/env python3
"""z86_replay.py -- replay a stopped hardware state on tb_z86_loop and Unicorn.

    z86_replay.py LOOP ram.bin regs.txt bios.rom [workdir]

ram.bin   guest RAM 00000-9FFFF dumped over JTAG while z86 sat in the
          debug stop (core_top write slot 0x0f).
regs.txt  "AX=.... BX=.... CX=.... DX=.... SI=.... DI=.... BP=.... SP=....
           DS=.... ES=.... SS=.... CS=.... IP=.... FL=...."
bios.rom  the 96 KB BIOS at E8000.

Both sides start from that state (a stub at C000:0000 loads the registers
and IRETs into CS:IP) and run until execution first leaves the stopped
code's segment through an IRET/RETF -- for a DOS call, the return to the
caller. Registers and memory are then compared, and the first store where
the two write streams part is printed.
"""
import os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import z86_fuzz as f
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_CODE, UC_HOOK_MEM_WRITE, UC_HOOK_INTR
from unicorn.x86_const import *

LOOP, RAM, REGS, BIOS, DISK = sys.argv[1:6]
WORK = sys.argv[6] if len(sys.argv) > 6 else '/tmp/z86replay'
disk = open(DISK, 'rb').read()      # 2HD .hdm: 77 cyl x 2 heads x 8 x 1024
os.makedirs(WORK, exist_ok=True)
STUB = 0xC0000

r = {k: int(v, 16) for k, v in re.findall(r'(\w\w)=([0-9A-Fa-f]{4})', open(REGS).read())}

mem = bytearray(b'\x00' * 0x100000)
ram = open(RAM, 'rb').read()
mem[0:len(ram)] = ram
bios = open(BIOS, 'rb').read()
mem[0x100000 - len(bios):] = bios

# --- INT 1Bh: neither Unicorn nor tb_z86_loop has an FDC. Phase 1 serves
# the disk BIOS from the image in Python and records each call; phase 2
# replaces IVT[1Bh] with a stub at D000:0000 that replays the recorded
# results in order, so both CPUs run the identical machine.
calls = []
def disk_bios(uc):
    ax = uc.reg_read(UC_X86_REG_AX); bx = uc.reg_read(UC_X86_REG_BX)
    cx = uc.reg_read(UC_X86_REG_CX); dx = uc.reg_read(UC_X86_REG_DX)
    es = uc.reg_read(UC_X86_REG_ES); bp = uc.reg_read(UC_X86_REG_BP)
    cmd = (ax >> 8) & 0x0f
    data = b''
    if cmd in (0x06, 0x02):                     # read data / read diagnostic
        c, h, sct = cx & 0xff, dx >> 8, dx & 0xff
        lba = (c * 2 + h) * 8 + (sct - 1)
        data = disk[lba * 1024: lba * 1024 + (bx or 0x10000)]
        uc.mem_write(es * 16 + bp, data)
    calls.append((ax, bx, cx, dx, es, bp, data))
    # return AH=0, CF=0 through the IRET frame
    uc.reg_write(UC_X86_REG_AX, ax & 0x00ff)
    ss = uc.reg_read(UC_X86_REG_SS); sp = uc.reg_read(UC_X86_REG_SP)
    ip = int.from_bytes(uc.mem_read(ss * 16 + sp, 2), 'little')
    cs = int.from_bytes(uc.mem_read(ss * 16 + sp + 2, 2), 'little')
    fl = int.from_bytes(uc.mem_read(ss * 16 + sp + 4, 2), 'little') & ~1
    uc.reg_write(UC_X86_REG_SP, (sp + 6) & 0xffff)
    uc.reg_write(UC_X86_REG_EFLAGS, fl)
    uc.reg_write(UC_X86_REG_CS, cs); uc.reg_write(UC_X86_REG_IP, ip)
DISK_VEC = (mem[0x6e] | mem[0x6f] << 8) * 16 + (mem[0x6c] | mem[0x6d] << 8)

# stub: SS:SP-6 <- IP, CS, FLAGS; load GPRs and DS/ES; IRET
sp6 = (r['SP'] - 6) & 0xffff
stub = f"""bits 16
org 0
    cli
    mov ax,0x{r['SS']:04x}
    mov ss,ax
    mov sp,0x{sp6:04x}
    mov bp,sp
    mov word [ss:bp],0x{r['IP']:04x}
    mov word [ss:bp+2],0x{r['CS']:04x}
    mov word [ss:bp+4],0x{r['FL']:04x}
    mov ax,0x{r['DS']:04x}
    mov ds,ax
    mov ax,0x{r['ES']:04x}
    mov es,ax
    mov ax,0x{r['AX']:04x}
    mov bx,0x{r['BX']:04x}
    mov cx,0x{r['CX']:04x}
    mov dx,0x{r['DX']:04x}
    mov si,0x{r['SI']:04x}
    mov di,0x{r['DI']:04x}
    mov bp,0x{r['BP']:04x}
    iret
"""
open(f'{WORK}/stub.asm', 'w').write(stub)
subprocess.run(['nasm', '-f', 'bin', f'{WORK}/stub.asm', '-o', f'{WORK}/stub.bin'], check=True)
sb = open(f'{WORK}/stub.bin', 'rb').read()

# --- Unicorn: run from CS:IP until an IRET/RETF leaves the segment ----------
mu = Uc(UC_ARCH_X86, UC_MODE_16)
mu.mem_map(0, 0x100000)
mu.mem_write(0, bytes(mem))
for reg, k in ((UC_X86_REG_AX, 'AX'), (UC_X86_REG_BX, 'BX'), (UC_X86_REG_CX, 'CX'), (UC_X86_REG_DX, 'DX'),
               (UC_X86_REG_SI, 'SI'), (UC_X86_REG_DI, 'DI'), (UC_X86_REG_BP, 'BP'), (UC_X86_REG_SP, 'SP'),
               (UC_X86_REG_DS, 'DS'), (UC_X86_REG_ES, 'ES'), (UC_X86_REG_SS, 'SS'), (UC_X86_REG_CS, 'CS'),
               (UC_X86_REG_IP, 'IP')):
    mu.reg_write(reg, r[k])
mu.reg_write(UC_X86_REG_EFLAGS, r['FL'])
seg0 = r['CS']
# the INT 21h frame sits at SS:SP on entry: run until it is returned to
fa = r['SS'] * 16 + r['SP']
ret_ip = mem[fa] | mem[fa + 1] << 8
ret_cs = mem[fa + 2] | mem[fa + 3] << 8
RET = ret_cs * 16 + ret_ip
print(f'return address {ret_cs:04X}:{ret_ip:04X}')
stop = {}
trace = []
iptrace = []
writes = []

def on_code(uc, addr, size, _):
    if addr == DISK_VEC:
        disk_bios(uc)
        uc.emu_stop()
        return
    trace.append(addr)
    iptrace.append((uc.reg_read(UC_X86_REG_CS), uc.reg_read(UC_X86_REG_IP)))
    if len(trace) > 3_000_000:
        stop['limit'] = True
        uc.emu_stop()
    if addr == RET and 'at' not in stop:
        stop['at'] = addr
        uc.emu_stop()

def on_int(uc, intno, _):
    ss = uc.reg_read(UC_X86_REG_SS); sp = uc.reg_read(UC_X86_REG_SP)
    fl = uc.reg_read(UC_X86_REG_EFLAGS) & 0xffff
    for v in (fl, uc.reg_read(UC_X86_REG_CS), uc.reg_read(UC_X86_REG_IP)):
        sp = (sp - 2) & 0xffff
        uc.mem_write(ss * 16 + sp, v.to_bytes(2, 'little'))
        writes.extend([(ss * 16 + sp, v & 0xff, -1), (ss * 16 + sp + 1, v >> 8, -1)])
    uc.reg_write(UC_X86_REG_SP, sp)
    uc.reg_write(UC_X86_REG_EFLAGS, fl & ~0x300)
    vec = uc.mem_read(intno * 4, 4)
    uc.reg_write(UC_X86_REG_CS, int.from_bytes(vec[2:4], 'little'))
    uc.reg_write(UC_X86_REG_IP, int.from_bytes(vec[0:2], 'little'))

def on_wr(uc, access, addr, size, value, _):
    for i in range(size):
        writes.append((addr + i, (value >> (8 * i)) & 0xff, trace[-1] if trace else 0))

mu.hook_add(UC_HOOK_CODE, on_code)
mu.hook_add(UC_HOOK_MEM_WRITE, on_wr)
mu.hook_add(UC_HOOK_INTR, on_int)
try:
    for _ in range(100000):          # an INT redirect ends emu_start: resume
        if 'at' in stop or 'limit' in stop:
            break
        pc = mu.reg_read(UC_X86_REG_CS) * 16 + mu.reg_read(UC_X86_REG_IP)
        mu.emu_start(pc, 0x100000, count=5_000_000)
except Exception as e:
    print('unicorn stopped:', e, hex(trace[-1]) if trace else '')
if 'at' not in stop:
    from collections import Counter
    print('Unicorn did not return within 3M instructions; hottest addresses:')
    for a, n in Counter(trace[-200000:]).most_common(12):
        print(f'   {a:05X} x{n}')
    sys.exit(1)
stop_pc = stop['at']
with open(f'{WORK}/ref.trace', 'w') as fh:
    fh.write(''.join(f'{c:04X}:{i:04X}\n' for c, i in iptrace))
ref_regs = {k: mu.reg_read(v) for k, v in (('AX', UC_X86_REG_AX), ('BX', UC_X86_REG_BX), ('CX', UC_X86_REG_CX),
            ('DX', UC_X86_REG_DX), ('SI', UC_X86_REG_SI), ('DI', UC_X86_REG_DI), ('BP', UC_X86_REG_BP),
            ('SP', UC_X86_REG_SP), ('DS', UC_X86_REG_DS), ('ES', UC_X86_REG_ES), ('FL', UC_X86_REG_EFLAGS))}
ref_mem = bytes(mu.mem_read(0, 0xA0000))
print(f'Unicorn: {len(calls)} disk calls {[hex(c[0]) for c in calls]}, {len(trace)} instructions, leaves at {stop_pc:05X}; AX={ref_regs["AX"]:04X} FL={ref_regs["FL"] & 0xfff:03X}')

# --- z86 on tb_z86_loop: image + stub at C0000, stop at the same PC --------
mem[STUB:STUB + len(sb)] = sb
# Phase 2 disk BIOS: D000:0000 replays the recorded INT 1Bh results in
# order -- copy the recorded data to ES:BP, AH=0, CF=0 in the IRET frame.
DSEG = 0xD000
tbl = []
data_off = 0x400
blob = bytearray()
for (ax, bx, cx, dx, es, bp, data) in calls:
    tbl.append((data_off + len(blob), len(data)))
    blob += data
dstub = '''bits 16
org 0
    push bp
    push si
    push di
    push cx
    push ds
    mov si,cs
    mov ds,si
    mov si,[0x3FE]             ; call index
    inc word [0x3FE]
    shl si,2
    mov cx,[si+0x302]          ; length
    mov si,[si+0x300]          ; source offset in this segment
    mov di,bp                  ; ES:BP is the caller's buffer
    cld
    rep movsb
    pop ds
    pop cx
    pop di
    pop si
    mov bp,sp
    and byte [bp+6],0xFE       ; CF=0 in the frame
    pop bp
    mov ah,0
    iret
'''
open(f'{WORK}/dstub.asm', 'w').write(dstub)
subprocess.run(['nasm', '-f', 'bin', f'{WORK}/dstub.asm', '-o', f'{WORK}/dstub.bin'], check=True)
ds_bin = open(f'{WORK}/dstub.bin', 'rb').read()
base = DSEG * 16
mem[base:base + len(ds_bin)] = ds_bin
for i, (off, ln) in enumerate(tbl):
    mem[base + 0x300 + 4 * i: base + 0x304 + 4 * i] = off.to_bytes(2, 'little') + ln.to_bytes(2, 'little')
mem[base + 0x3FE: base + 0x400] = b'\0\0'
mem[base + data_off: base + data_off + len(blob)] = blob
mem[0x6C:0x70] = (0).to_bytes(2, 'little') + DSEG.to_bytes(2, 'little')
with open(f'{WORK}/mem.hex', 'w') as fh:
    fh.write(''.join(f'{b:02x}\n' for b in mem))
with open(f'{WORK}/prog.hex', 'w') as fh:
    fh.write(''.join(f'{b:02x}\n' for b in sb))
res = subprocess.run([LOOP, f'+mem={WORK}/mem.hex', '+org=c0000', f'+prog={WORK}/prog.hex', '+lat=3',
                      f'+stop_pc={stop_pc:05x}', f'+dump={WORK}/z.dump', f'+wlog={WORK}/z.wlog'],
                     capture_output=True, text=True)
print('tb:', ' '.join(l for l in res.stdout.splitlines() if 'STOP' in l or 'TIMEOUT' in l))
zr = re.findall(r'REGS (.*)', res.stdout)
print('z86 regs:', zr[0] if zr else '?')
print('ref regs:', ' '.join(f'{k}={v & 0xffff:04X}' for k, v in ref_regs.items()))
zmem = bytes(int(l, 16) for l in open(f'{WORK}/z.dump') if l.strip() and not l.startswith('//'))
diffs = [a for a in range(0, 0xA0000) if zmem[a] != ref_mem[a] and not (STUB <= a < STUB + 0x100)]
print(f'memory differences in 00000-9FFFF: {len(diffs)}', [hex(a) for a in diffs[:8]])
zw = [tuple(int(x, 16) for x in l.split()) for l in open(f'{WORK}/z.wlog')]
# the stub's own frame stores come first on z86
zw = [w for w in zw if not (w[0] >> 4 == ((r['SS'] * 16 + sp6) >> 4) and len(zw) and zw.index(w) < 6)]
for i, (a, b) in enumerate(zip(writes, zw)):
    if (a[0], a[1]) != (b[0], b[1]):
        print(f'first differing store #{i}: Unicorn {a[0]:05X}={a[1]:02X} (at {a[2]:05X})  z86 {b[0]:05X}={b[1]:02X}')
        for j in range(max(0, i - 5), i):
            print(f'   before: {writes[j][0]:05X}={writes[j][1]:02X} at {writes[j][2]:05X}')
        break
else:
    print(f'write streams agree ({len(writes)} Unicorn, {len(zw)} z86)')
