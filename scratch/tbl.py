import sys
d=open('/Users/hiroya/.pc98roms/itf.rom','rb').read()
i=int(sys.argv[1],16)
w=d[i]|(d[i+1]<<8); i+=2
cnt=w&0xFF; hi=w>>8
print("table @%04X: count=%d (CH:CL=%02X%02X) port-high=%02X"%(int(sys.argv[1],16),cnt,0,cnt,hi))
for n in range(cnt):
    w=d[i]|(d[i+1]<<8)
    print("  %04X: %04X -> OUT %02X%02X, %02X"%(i,w,hi,w>>8,w&0xFF))
    i+=2
print("continues at %04X"%i)
