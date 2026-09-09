#!/usr/bin/env python3
"""Walker with tiny constant-propagation so `MOV BP,imm ; JMP sub` / `JMP BP` resolves."""
import sys
src = open('/Users/hiroya/repo/pc98-pocket/scratch/dis8086.py').read().replace('\nmain()\n','\n')
g={'__name__':'d8'}; exec(compile(src,'dis8086.py','exec'), g)
Dis=g['Dis']
rom=open('/Users/hiroya/.pc98roms/itf.rom','rb').read()
d=Dis(rom,0)
TRACK=['AX','CX','DX','BX','SP','BP','SI','DI']

import re
def step(pc,st):
    n,t,info=d.decode(pc)
    st=dict(st)
    m=re.match(r'^MOV (AX|CX|DX|BX|SP|BP|SI|DI),([0-9A-F]+h)$',t)
    if m:
        st[m.group(1)]=int(m.group(2)[:-1],16)
    else:
        # kill any register that appears as a destination
        m2=re.match(r'^[A-Z]+ ([A-Z][A-Z]),',t)
        if m2 and m2.group(1) in TRACK: st.pop(m2.group(1),None)
        for r in ('AX','CX','DX','BX','SP','BP','SI','DI'):
            if re.match(r'^(INC|DEC|POP|XCHG|LEA|LDS|LES|MUL|IMUL|DIV|IDIV|NOT|NEG) '+r+r'\b',t): st.pop(r,None)
        if re.match(r'^(MOV|ADD|SUB|XOR|OR|AND|ADC|SBB) (AL|AH),',t): st.pop('AX',None)
        if re.match(r'^(MOV|ADD|SUB|XOR|OR|AND|ADC|SBB) (BL|BH),',t): st.pop('BX',None)
        if re.match(r'^(MOV|ADD|SUB|XOR|OR|AND|ADC|SBB) (CL|CH),',t): st.pop('CX',None)
        if re.match(r'^(MOV|ADD|SUB|XOR|OR|AND|ADC|SBB) (DL|DH),',t): st.pop('DX',None)
        if 'LODS' in t or 'STOS' in t or 'MOVS' in t or 'SCAS' in t or 'CMPS' in t:
            st.pop('SI',None); st.pop('DI',None); st.pop('CX',None)
        if t.startswith('MUL') or t.startswith('DIV') or t.startswith('IMUL') or t.startswith('IDIV'):
            st.pop('AX',None); st.pop('DX',None)
        if t.startswith('LOOP') or t=='JCXZ': pass
        if t.startswith('CALL') or t.startswith('PUSH') or t.startswith('POP') or t.startswith('RET'):
            st.pop('SP',None)
    return n,t,info,st

seeds=[(int(x,16),{}) for x in sys.argv[1:]] or [(0,{})]
seen={}
visited=set()
work=list(seeds)
unresolved=[]
edges=[]
tables=[]
while work:
    pc,st=work.pop()
    while True:
        if pc>=0x8000: break
        key=(pc,st.get('BP'),st.get('SI'),st.get('SP'),st.get('DI'),st.get('BX'))
        if key in visited: break
        visited.add(key)
        if pc==0xD3 and 'SI' in st:
            a=st['SI']; w=rom[a]|(rom[a+1]<<8); a+=2
            cnt=w&0xFF; hi=w>>8; ents=[]
            for k in range(cnt):
                ww=rom[a]|(rom[a+1]<<8); ents.append((a,(hi<<8)|(ww>>8),ww&0xFF)); a+=2
            tables.append((pc,st['SI'],ents,a))
            st=dict(st); st.pop('SI',None); st.pop('CX',None); st.pop('DX',None); st.pop('AX',None)
            pc=a; continue
        try: n,t,info,nst=step(pc,st)
        except IndexError: break
        seen[pc]=(n,t)
        if 'branch' in info:
            tg=info['branch']&0xFFFF
            if tg in (0xD0,0xD3) and 'SI' in st:
                a=st['SI']; w=rom[a]|(rom[a+1]<<8); a+=2
                cnt=w&0xFF; hi=w>>8
                ents=[]
                for k in range(cnt):
                    ww=rom[a]|(rom[a+1]<<8)
                    ents.append((a,(hi<<8)|(ww>>8),ww&0xFF)); a+=2
                tables.append((pc,st['SI'],ents,a))
                ns=dict(nst); ns.pop('SI',None); ns.pop('CX',None); ns.pop('DX',None); ns.pop('AX',None)
                work.append((a,ns))
            elif tg<0x8000: work.append((tg,dict(nst)))
        if 'call' in info:
            tg=info['call']&0xFFFF
            if tg<0x8000: work.append((tg,dict(nst)))
        if 'indirect' in info:
            r=info['indirect']
            if r in TRACK and r in st:
                tg=st[r]
                edges.append((pc,t,tg))
                if tg<0x8000: work.append((tg,dict(nst)))
            else:
                unresolved.append((pc,t))
        if 'indirectcall' in info or 'farjmp' in info or 'farcall' in info:
            unresolved.append((pc,t))
        if info.get('jmp') or info.get('ret'): break
        pc=n; st=nst

outl=sorted(seen)
prev=None
lines=[]
for a in outl:
    n,t=seen[a]
    if prev is not None and a!=prev:
        lines.append('---- gap %04X..%04X (%d) ----'%(prev,a,a-prev))
    raw=''.join('%02X'%x for x in rom[a:n])
    lines.append('F8%04X  %-16s %s'%(a,raw,t))
    prev=n
print('\n'.join(lines))
sys.stderr.write('== port tables ==\n')
for pc,a,ents,e in sorted(set((p,a,tuple(x),e) for p,a,x,e in tables)):
    sys.stderr.write('walker call at F8%04X table@%04X (%d entries), resumes %04X\n'%(pc,a,len(ents),e))
    for ea,port,val in ents: sys.stderr.write('   %04X: OUT %04X, %02X\n'%(ea,port,val))
sys.stderr.write('== resolved register-indirect jumps ==\n')
for a,t,tg in sorted(set(edges)): sys.stderr.write('F8%04X %s -> %04X\n'%(a,t,tg))
sys.stderr.write('== UNRESOLVED ==\n')
for a,t in sorted(set(unresolved)): sys.stderr.write('F8%04X %s\n'%(a,t))
sys.stderr.write('bytes covered %d\n'%sum(seen[a][0]-a for a in seen))
