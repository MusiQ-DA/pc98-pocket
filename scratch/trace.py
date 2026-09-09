#!/usr/bin/env python3
"""Recursive-descent code walker over the ITF ROM using dis8086."""
import sys, importlib.util
spec = importlib.util.spec_from_file_location("d8", "/Users/hiroya/repo/pc98-pocket/scratch/dis8086.py")
# dis8086 runs main() on import; instead exec its source minus main()
src = open('/Users/hiroya/repo/pc98-pocket/scratch/dis8086.py').read().replace('\nmain()\n','\n')
g = {'__name__':'d8'}
exec(compile(src,'dis8086.py','exec'), g)
Dis = g['Dis']

rom = open('/Users/hiroya/.pc98roms/itf.rom','rb').read()
d = Dis(rom, 0)

seeds = [int(x,16) for x in sys.argv[1:]] or [0]
seen = {}
work = list(seeds)
unresolved = []
calls = set()
while work:
    pc = work.pop()
    while True:
        if pc in seen or pc >= 0x8000: break
        try:
            n,t,info = d.decode(pc)
        except IndexError:
            break
        seen[pc]=(n,t,info)
        if 'branch' in info:
            tgt = info['branch']&0xFFFF
            if tgt < 0x8000 and tgt not in seen: work.append(tgt)
        if 'call' in info:
            tgt = info['call']&0xFFFF
            calls.add(tgt)
            if tgt < 0x8000 and tgt not in seen: work.append(tgt)
        if 'indirect' in info or 'indirectcall' in info or 'farjmp' in info or 'farcall' in info:
            unresolved.append((pc,t))
        if info.get('jmp') or info.get('ret'):
            break
        pc = n

out=[]
for a in sorted(seen):
    n,t,info = seen[a]
    raw=''.join('%02X'%x for x in rom[a:n])
    out.append((a,raw,t))
prev_end=None
for a,raw,t in out:
    if prev_end is not None and a!=prev_end:
        print('---- gap %04X..%04X (%d bytes) ----'%(prev_end,a,a-prev_end))
    print('F8%04X  %-16s %s'%(a,raw,t))
    prev_end = a+len(raw)//2
sys.stderr.write("\n== unresolved indirect/far transfers ==\n")
for a,t in unresolved:
    sys.stderr.write('F8%04X  %s\n'%(a,t))
sys.stderr.write("bytes covered: %d\n"%sum(len(r)//2 for _,r,_ in out))
