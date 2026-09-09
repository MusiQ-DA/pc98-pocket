p='gendoc.py'
s=open(p).read()
reps = [
 ("(0x0001,'AH=D5h -> SF NF? set: SF,ZF? -- flag pattern for SAHF'),",
  "(0x0001,'D5h = SF,ZF,AF,PF,CF all set'),"),
 ("(0x000D,'AAS must leave CF=0'),",
  "(0x000D,'AF is still 1, so AAS must SET CF'),"),
 ("(0x0024,'AAS must keep CF=1'),",
  "(0x0024,'AF is now 0, so AAS must CLEAR CF'),"),
 ("(0x0018,'AX=0 clears flags via SAHF'),",
  "(0x0018,'AH=0 -> SAHF clears SF,ZF,AF,PF,CF'),"),
 ("(0x00E0,'OUT DX,AL'),",
  "(0x00E0,'DX = DH:DL = the 16-bit port'),"),
]
for a,b in reps:
    assert a in s, a
    s = s.replace(a,b,1)
open(p,'w').write(s)
print('ok')
