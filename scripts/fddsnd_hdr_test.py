#!/usr/bin/env python3
# fddsnd_hdr_test.py -- end-to-end check of the fddsnd.bin header path the
# firmware loader walks: synthesise a 48 kHz source long enough to cover
# every window in fddsnd_pack.CUTS, run the real packer, then parse the
# blob's header with the firmware's own fddsnd_hdr.h (via
# fddsnd_hdr_test.c) and compare the segment table against the offsets the
# packer printed. A corrupted magic must be rejected.
#
#   python3 scripts/fddsnd_hdr_test.py

import math
import os
import re
import struct
import subprocess
import sys
import tempfile
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fddsnd_pack as fp

C_SRC = os.path.join(HERE, 'fddsnd_hdr_test.c')
BIN = os.path.join(tempfile.gettempdir(), 'fddsnd_hdr_test')


def parse_c(f):
    out = subprocess.check_output([BIN, f]).decode()
    return [tuple(map(int, ln.split())) for ln in out.splitlines()]


def main():
    subprocess.check_call(['cc', '-O1', '-Wall', '-Wextra', '-o', BIN, C_SRC])
    tmp = tempfile.mkdtemp(prefix='fddsnd_')

    # The CUTS windows reach 64.2 s into the source; synthesise 65 s of mono
    # tone bursts so every segment is non-silent.
    rate = fp.FSRC
    n = rate * 65
    wpath = os.path.join(tmp, 'src.wav')
    with wave.open(wpath, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = bytearray()
        for i in range(n):
            t = i / rate
            env = 0.5 + 0.5 * math.sin(t * 0.3)
            s = int(math.sin(2 * math.pi * (180 + (i % rate) * 0.02) * t)
                    * 9000 * env)
            frames += struct.pack('<h', s)
        w.writeframes(bytes(frames))

    blob = os.path.join(tmp, 'fddsnd.bin')
    out = subprocess.check_output(
        [sys.executable, os.path.join(HERE, 'fddsnd_pack.py'), wpath, blob],
        text=True)
    print(out.strip())

    # The packer prints "off=%d len=%d" per segment in CUTS order.
    expect = [(int(o), int(l))
              for o, l in re.findall(r'off=(\d+) len=(\d+)', out)]
    if len(expect) != fp.SEG_NAMES.__len__():
        sys.exit('packer printed %d offsets' % len(expect))

    got = parse_c(blob)
    if got != expect:
        sys.exit('header parse mismatch: c=%s packer=%s' % (got, expect))
    print('header: %d segments parsed identically to the packer' % len(got))

    # A corrupt magic must be rejected, not silently decoded.
    bad = os.path.join(tmp, 'bad.bin')
    with open(blob, 'rb') as f:
        data = bytearray(f.read())
    data[0] ^= 0xFF
    with open(bad, 'wb') as f:
        f.write(bytes(data))
    if subprocess.call([BIN, bad]) == 0:
        sys.exit('corrupt magic accepted')
    print('reject:  bad magic correctly refused')

    print('PASS')


if __name__ == '__main__':
    main()
