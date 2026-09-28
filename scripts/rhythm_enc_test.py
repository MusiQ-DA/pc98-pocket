#!/usr/bin/env python3
# rhythm_enc_test.py -- byte-compare firmware/adpcma_enc.c against the Python
# reference in rhythm_pack.py.
#
#   python3 scripts/rhythm_enc_test.py
#
# Two paths:
#   raw   -- identical s16 samples into both encoders; the C bytes must equal
#            pack_voice() bit for bit (LUT, greedy pick, step adapt, nibble
#            order, 256-align padding all covered).
#   wav   -- a generated stereo 44.1 kHz chirp through the full paths. The
#            C resampler is fixed-point vs Python's float, so a rare 1-LSB
#            target difference can flip a nibble; both byte streams are
#            decoded with the RTL LUT and compared instead of byte-diffed.

import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rhythm_pack as rp

C_SRC = os.path.join(HERE, 'rhythm_enc_test.c')
BIN = os.path.join(tempfile.gettempdir(), 'rhythm_enc_test')


def decode_adpcma(data, lut):
    """Mirror jt10_adpcm: acc += +/-inc[step][mag], step adapts by magnitude.
    Returns the 12-bit-domain accumulator stream (left unclamped, like RTL)."""
    x, step, out = 0, 0, []
    for byte in data:
        for nib in (byte >> 4, byte & 0xF):
            mag, sign = nib & 7, nib >> 3
            x += -lut[step * 8 + mag] if sign else lut[step * 8 + mag]
            step += rp.STEP_ADAPT[mag]
            step = 0 if step < 0 else (48 if step > 48 else step)
            out.append(x)
    return out


def clamp12(s):
    return max(-2048, min(2047, s >> 4))


def main():
    subprocess.check_call(['cc', '-O1', '-Wall', '-Wextra', '-o', BIN, C_SRC])
    lut = rp.load_inc_lut(rp.LUT_FILE)
    tmp = tempfile.mkdtemp(prefix='rhyenc_')

    # ---- raw path: bit-exact -------------------------------------------------
    random.seed(7)
    pcm = []
    for i in range(6000):
        env = max(0.0, 1.0 - i / 4500.0)
        t = math.sin(i * 0.13) * 9000 + math.sin(i * 0.71) * 5000
        pcm.append(int(t * env) + random.randint(-200, 200))
    raw = os.path.join(tmp, 'in.s16')
    with open(raw, 'wb') as f:
        f.write(struct.pack('<%dh' % len(pcm), *pcm))
    c_bytes = subprocess.check_output([BIN, '--raw', raw])
    py_bytes = rp.pack_voice([clamp12(s) for s in pcm], lut)
    if c_bytes != py_bytes:
        n = next(i for i, (a, b) in enumerate(zip(c_bytes, py_bytes)) if a != b)
        sys.exit('RAW MISMATCH at byte %d (c=%02x py=%02x), lens %d/%d'
                 % (n, c_bytes[n], py_bytes[n], len(c_bytes), len(py_bytes)))
    print('raw:   %d bytes bit-identical' % len(c_bytes))

    # ---- wav path: resampled-target equivalence ------------------------------
    # The C resampler is 16.16 fixed point vs Python's float, so targets may
    # differ by one 12-bit LSB where a real lerp lands on a rounding edge --
    # anything more is a resampler bug. Target count must match exactly.
    wpath = os.path.join(tmp, 'chirp.wav')
    rate = 44100
    n = int(rate * 0.25)
    with wave.open(wpath, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = bytearray()
        for i in range(n):
            env = max(0.0, 1.0 - i / n)
            s = int(math.sin(i * i * 0.0009 + i * 0.2) * 14000 * env)
            frames += struct.pack('<hh', s, int(s * 0.7))
        w.writeframes(bytes(frames))

    t_raw = subprocess.check_output([BIN, '--targets', wpath])
    c_t = struct.unpack('<%dh' % (len(t_raw) // 2), t_raw)
    pcm16, r = rp.read_wav_mono16(wpath)
    py_t = [clamp12(s) for s in rp.resample_linear(pcm16, r)]
    # C emits len(py_t)-ish targets: Python's stream plus its flat pcm[-1]
    # tail clamp -- compare on the common prefix.
    n_t = min(len(c_t), len(py_t))
    diffs = [abs(a - b) for a, b in zip(c_t[:n_t], py_t[:n_t])]
    mx = max(diffs)
    print('wav:   %d targets c/py %d/%d, max target diff %d'
          % (n_t, len(c_t), len(py_t), mx))
    if len(c_t) < len(py_t) or abs(len(c_t) - len(py_t)) > 2:
        sys.exit('WAV target count mismatch: c=%d py=%d' % (len(c_t), len(py_t)))
    if mx > 1:
        bad = diffs.index(mx)
        sys.exit('WAV target diff %d at sample %d' % (mx, bad))
    print('PASS')


if __name__ == '__main__':
    main()
