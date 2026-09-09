p='/Users/hiroya/repo/pc98-pocket/scratch/gendoc.py'
s=open(p).read()
OVSRC = """OV = {
 0x0084: (None, '(0439h & 02h) | 34h'),
 0x0138: (None, '42h or 40h (42h bit5)'),
 0x02CD: (None, 'DDh or 88h (33h bit3)'),
 0x02D1: (None, '2Ch or 32h (33h bit3)'),
 0x040A: (None, '0Fh down to 00h'),
 0x040E: (None, 'from the table at F8042F'),
 0x0412: (None, 'from the table at F8042F'),
 0x0416: (None, 'from the table at F8042F'),
 0x049C: ('62h or A2h', 'byte 0 of the block = GDC command'),
 0x04D2: ('60h or A0h', 'bytes 1.. of the block = GDC parameters'),
 0x05CC: (None, 'low byte of 03E6h or 04CDh'),
 0x05D4: (None, 'high byte of 03E6h or 04CDh'),
 0x063B: (None, 'AH = 00h / 9Dh / 7xh / 9Fh'),
 0x0740: (None, 'low byte of 03E6h or 04CDh'),
 0x0748: (None, 'high byte of the same'),
 0x0763: (None, 'low byte of the divisor doubled'),
 0x076B: (None, 'high byte of the same'),
 0x092C: (None, 'CG code low byte 20h..7Fh'),
 0x0930: (None, 'CG code high byte 56h then 57h'),
 0x0C89: (None, '10h, 50h, 90h'),
 0x0C91: ('71h, 73h, 75h', 'FFh then 00h'),
 0x0C98: (None, '00h, 40h, 80h (latch)'),
 0x0C9E: ('71h, 73h, 75h', None),
 0x0CC9: (None, 'B6h (any value; master clear ignores data)'),
 0x0CD7: ('01h,03h,05h,07h,09h,0Bh,0Dh,0Fh', 'FFh then 00h'),
 0x0CDA: ('01h..0Fh', 'FFh then 00h'),
 0x0CDD: ('01h..0Fh', None),
 0x0CE0: ('01h..0Fh', None),
 0x0D03: (None, '00h then FFh'),
 0x0D17: (None, '00h then FFh'),
 0x0D63: (None, '00h'),
 0x0D7F: (None, '00h'),
 0x0D85: (None, '00h'),
 0x0F42: (None, '00h'),
 0x12F2: (None, '00h'),
 0x17AC: (None, '80h or 82h (7FDBh bit6)'),
 0x17D5: (None, '06h or 46h (0F0h bit5)'),
 0x1F68: (None, 'GDC command byte (4Ch, 49h, 20h)'),
 0x1F74: (None, 'GDC parameter byte'),
}

def iotable(ranges):"""
assert 'def iotable(ranges):' in s
s = s.replace('def iotable(ranges):', OVSRC, 1)
old = """            fn = IOPORTS.get(pnum, '') if pnum is not None else ''
            L.append('| F8%04X | %s | %s | %s | %s |' % (pc, rw, pname, v or '—', fn))"""
new = """            fn = IOPORTS.get(pnum, '') if pnum is not None else ''
            if pc in OV:
                op, ov = OV[pc]
                if op: pname = op
                if ov: v = ov
            L.append('| F8%04X | %s | `%s` | %s | %s |' % (pc, rw, pname, v or '—', fn))"""
assert old in s, 'row emitter not found'
s = s.replace(old, new, 1)
open(p,'w').write(s)
print('patched')
