#!/usr/bin/env python3
"""Pack FDD mechanism-noise samples into fddsnd.bin for the FDD sound dataslot.

The blob is streamed by the APF dataslot loader into fdd_sound's sample RAM
(16K x 16-bit words; bytes land little-endian, two s8 samples per word).
Layout:

    word 0-1  u32 magic 'FDS1' (0x31534446, word 0 reads 0x4446)
    word 2    u16 version (1)
    word 3    u16 segment count (5)
    words 4.. per segment: u16 word_offset, u16 word_length (bytes/2)
    payload   s8 PCM at 24 kHz, each segment 128-word aligned

Segments, in order: step tick (one-shot), head-load clunk (one-shot),
seek whine (loop), media xfer hiss (loop), motor idle whir (loop).
The windows below are cuts from a recording of a real 5.25" PC-98 drive;
transients inside loop cuts are crushed with a fast limiter so the discrete
one-shot voices own the percussive edge, then the ends are crossfaded so the
loop wraps without a click.
"""
import struct, sys, wave, math

SEG_NAMES = ["tick", "clunk", "seek", "read", "motor"]

# (start_s, end_s, one_shot, gain) -- windows into the 48 kHz mono source WAV.
CUTS = {
    "tick":  (34.383, 34.425, True,  1.00),
    "clunk": (56.970, 57.150, True,  1.00),
    "seek":  (27.450, 28.000, False, 1.00),
    "read":  (63.850, 64.200, False, 0.85),
    "motor": (45.050, 45.350, False, 0.90),
}

FSRC = 48000
FDST = 24000
XWORD_ALIGN = 128
MAX_WORDS = 16384
MAGIC = 0x31534446  # 'FDS1' little-endian


def load_mono(path):
    w = wave.open(path)
    sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
    d = struct.unpack("<%dh" % (n * ch), w.readframes(n))
    if sr != FSRC:
        sys.exit(f"{path}: want {FSRC} Hz source, got {sr}")
    return [d[i * ch] for i in range(n)]


def limiter(seg, rate, ratio=1.2):
    """Crush peaks above ratio*RMS: instant attack, ~10 ms release."""
    rms = math.sqrt(sum(x * x for x in seg) / len(seg))
    thr = rms * ratio
    env, g, out = 0.0, 1.0, []
    rr = 1 - math.exp(-1 / (0.010 * rate))
    for x in seg:
        env = max(abs(x), env * (1 - rr))
        need = thr / max(env, 1e-9)
        g = need if need < g else min(1.0, g + (1 - g) * 0.002)
        out.append(int(x * g))
    return out


def decimate(seg):
    return [(seg[i] + seg[i + 1]) // 2 for i in range(0, len(seg) - 1, 2)]


def to_s8(raw, vol):
    pk = max(abs(v) for v in raw) or 1
    g = vol * 127 / pk * 0.9
    return [max(-128, min(127, int(v * g))) for v in raw]


def loop_splice(buf, xf_ms=15):
    x = int(xf_ms * FDST / 1000)
    head, tail, mid = buf[:x], buf[-x:], buf[x:len(buf) - x]
    lp = mid[:]
    for j in range(x):
        lp[j] = int(head[j] * (j / x) + tail[j] * (1 - j / x))
    return lp


def main():
    src = load_mono(sys.argv[1] if len(sys.argv) > 1 else "/tmp/pc98fdd.wav")
    buf = bytearray(64)
    offs = []
    for name in SEG_NAMES:
        t0, t1, oneshot, vol = CUTS[name]
        raw = decimate(src[int(t0 * FSRC):int(t1 * FSRC)])
        if not oneshot:
            raw = limiter(raw, FDST)
        data = to_s8(raw, vol)
        if not oneshot:
            data = loop_splice(data)
        while len(buf) % (XWORD_ALIGN * 2):
            buf.append(0)
        offs.append((len(buf) // 2, (len(data) + 1) // 2))
        buf += bytes(v & 0xFF for v in data)
        if len(data) % 2:
            buf.append(0)
    if len(buf) // 2 > MAX_WORDS:
        sys.exit(f"blob {len(buf)}B exceeds {MAX_WORDS * 2}B store")
    hdr = struct.pack("<IHH", MAGIC, 1, len(SEG_NAMES))
    for o, l in offs:
        hdr += struct.pack("<HH", o, l)
    buf[:64] = hdr + b"\0" * (64 - len(hdr))
    out = sys.argv[2] if len(sys.argv) > 2 else "fddsnd.bin"
    open(out, "wb").write(bytes(buf))
    print(out, len(buf), "bytes;",
          {n: f"off={o} len={l}" for n, (o, l) in zip(SEG_NAMES, offs)})


if __name__ == "__main__":
    main()
