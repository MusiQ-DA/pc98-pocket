#!/usr/bin/env python3
# rhythm_pack.py -- pack the six OPNA rhythm WAVs into rhythm.bin, the blob the
# firmware (firmware/rhythm.c) streams into pc98_opna's ADPCM-A sample store.
#
#   scripts/rhythm_pack.py [-o rhythm.bin] <dir with 2608_*.wav>
#
# The six files are the same set np21w loads (sound/rhythmc.c:11-20):
#   2608_bd.wav  2608_sd.wav  2608_top.wav  2608_hh.wav  2608_tom.wav  2608_rim.wav
#
# Each voice is resampled to the ADPCM-A playback rate (phi_M/432 ~= 18.5 kHz),
# encoded as YM 4-bit ADPCM-A using the exact increment LUT the RTL decodes
# with (parsed out of jt10_adpcma_lut.v, so the two can never drift apart),
# then placed in the store on 256-byte boundaries -- the start/end registers
# quantise to 256 bytes. The trailer samples pad to the boundary by encoding
# silence, so the voice decays to DC instead of stepping off a cliff.
#
# rhythm.bin layout (what firmware/rhythm.c parses):
#   +0  u32 'RYA1'
#   +4  u32 payload offset (32)
#   +8  6 x u32 {start256, end256} little-endian, in 256-byte units
#   +32 ADPCM-A bytes, two samples per byte, high nibble first
#
# Copy the result to Assets/pc98/common/rhythm.bin on the card.

import argparse
import os
import re
import struct
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
LUT_FILE = os.path.join(REPO, 'fpga/core/sound/jt12/hdl/adpcm/jt10_adpcma_lut.v')

VOICES = ['bd', 'sd', 'top', 'hh', 'tom', 'rim']
ADPCM_RATE = 8e6 / 432          # ~18.52 kHz, the fixed ADPCM-A voice rate
ADPCM_NUM, ADPCM_DIV = 8000000, 432   # integer form; the C encoder uses these
RHY_BYTES = 16384               # pc98_opna's store is 32KB, but firmware's
                                # RHY_STORE_BYTES gives the rhythm voices the
                                # lower 16KB only -- the upper half belongs to
                                # drive_sound.c's mechanism samples.
MAGIC = b'RYA1'
HDR_BYTES = 32

# Step-index adaptation per magnitude nibble, mirroring jt10_adpcm.v's
# step_next case (0-3 -> -1, then +2/+5/+7/+9), clamped to 0..48.
STEP_ADAPT = (-1, -1, -1, -1, 2, 5, 7, 9)


def load_inc_lut(path):
    """Parse the octal lut[..] = .. lines out of jt10_adpcma_lut.v into a
    392-entry (49 steps x 8 magnitudes) table of 12-bit increments."""
    lut = {}
    pat = re.compile(r"lut\[9'o(\d+)_(\d)\]\s*=\s*12'o(\d+)")
    for line in open(path):
        for m in pat.finditer(line):
            step, mag, val = int(m.group(1), 8), int(m.group(2)), int(m.group(3), 8)
            lut[step * 8 + mag] = val   # a few addresses repeat; last wins, as in Verilog
    if len(lut) != 49 * 8:
        sys.exit('rhythm_pack: expected 392 LUT entries in %s, got %d' % (path, len(lut)))
    return [lut[i] for i in range(49 * 8)]


def read_wav_mono16(path):
    """16-bit signed mono PCM list + sample rate. Downmixes stereo, promotes
    8-bit unsigned PCM; anything fancier than integer PCM is refused."""
    w = wave.open(path, 'rb')
    rate, ch, sw, n = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
    raw = w.readframes(n)
    w.close()
    if sw == 2:
        d = struct.unpack('<%dh' % (len(raw) // 2), raw)
    elif sw == 1:
        d = [(b - 128) << 8 for b in raw]
    else:
        sys.exit('rhythm_pack: %s: %d-byte samples unsupported' % (path, sw))
    if ch == 2:
        d = [(d[2 * i] + d[2 * i + 1]) // 2 for i in range(len(d) // 2)]
    elif ch != 1:
        sys.exit('rhythm_pack: %s: %d channels unsupported' % (path, ch))
    return list(d), rate


def resample_linear(pcm, src_rate):
    """Streaming linear resampler to the ADPCM-A rate -- the bit-exact mirror
    of firmware/adpcma_enc.c (16.16 fixed-point positions, integer lerp,
    flat-tail clamp at EOF), so rhythm_enc_test can byte-compare the two
    implementations. Returns the resampled int16 list."""
    if len(pcm) < 2:
        return list(pcm)
    ratio = (int(src_rate) << 16) * ADPCM_DIV // ADPCM_NUM
    if ratio == 0x10000:            # source already at the voice rate
        return list(pcm)
    out = []
    pos = 0
    n = len(pcm)
    while (pos >> 16) < n - 1:      # outputs serviceable inside [j, j+1]
        j = pos >> 16
        frac = pos & 0xFFFF
        out.append(pcm[j] + ((pcm[j + 1] - pcm[j]) * frac >> 16))
        pos += ratio
    while (pos >> 16) <= n - 1:     # flat tail clamped to the last sample
        out.append(pcm[-1])
        pos += ratio
    return out


def adpcm_encode(pcm12, inc_lut, tail_samples=0):
    """Greedy YM ADPCM-A encoder tracking the jt10 decoder bit for bit:
    x += +/-inc[step][mag], then step adapts by magnitude. Returns a nibble
    list; tail_samples of zeros are appended so the decay lands inside the
    256-byte block instead of leaving the accumulator mid-flight."""
    pcm12 = list(pcm12) + [0] * tail_samples
    x, step = 0, 0
    nibbles = []
    for target in pcm12:
        best = None
        for mag in range(8):
            inc = inc_lut[step * 8 + mag]
            for sign, cand in ((0, x + inc), (1, x - inc)):
                err = abs(cand - target)
                if best is None or err < best[0]:
                    best = (err, sign, mag, cand)
        _, sign, mag, x = best
        step += STEP_ADAPT[mag]
        if step < 0:
            step = 0
        elif step > 48:
            step = 48
        nibbles.append((sign << 3) | mag)
    return nibbles


def pack_voice(pcm12, inc_lut):
    """Encode one voice and 256-align it: the padding stretch encodes silence
    so the accumulator settles at zero. Returns (adpcm bytes, start256, end256)
    is left to the caller; this returns the byte list only."""
    # The padding stretch encodes silence so the accumulator settles at zero.
    # Pad samples count to a whole number of 256-byte blocks.
    n0 = (len(pcm12) + 1) // 2
    pad_samples = ((-n0) % 256) * 2 + (2 - len(pcm12) % 2) % 2
    nib = adpcm_encode(pcm12, inc_lut, tail_samples=pad_samples)
    out = bytearray()
    for i in range(0, len(nib), 2):
        out.append((nib[i] << 4) | nib[i + 1])
    return bytes(out)


def emit_lut(path):
    """Write the parsed LUT as firmware/adpcma_lut.h, the table the on-chip
    encoder (firmware/adpcma_enc.c) runs against. Same source as the packer,
    so the C encoder and the RTL decoder share one truth."""
    lut = load_inc_lut(LUT_FILE)
    with open(path, 'w') as f:
        f.write('/* Generated by scripts/rhythm_pack.py --emit-lut from\n')
        f.write(' * fpga/core/sound/jt12/hdl/adpcm/jt10_adpcma_lut.v -- do not\n')
        f.write(' * edit by hand. 49 step indexes x 8 magnitudes, 12-bit\n')
        f.write(' * increments, exactly what jt10_adpcm.v adds to acc. */\n')
        f.write('#include <stdint.h>\n\n')
        f.write('static const uint16_t ADPCMA_INC[49 * 8] = {\n')
        for i in range(0, 49 * 8, 8):
            f.write('    ' + ', '.join('%4d' % v for v in lut[i:i + 8]) + ',\n')
        f.write('};\n')
    print('%s: %d entries' % (path, len(lut)))


def main():
    ap = argparse.ArgumentParser(description='pack 2608_*.wav rhythm voices into rhythm.bin')
    ap.add_argument('indir', nargs='?', help='directory holding 2608_bd.wav etc.')
    ap.add_argument('-o', '--out', default='rhythm.bin')
    ap.add_argument('--emit-lut', metavar='H',
                    help='write firmware/adpcma_lut.h and exit')
    args = ap.parse_args()

    if args.emit_lut:
        emit_lut(args.emit_lut)
        return
    if not args.indir:
        ap.error('indir is required unless --emit-lut is given')

    inc_lut = load_inc_lut(LUT_FILE)

    payload = bytearray()
    pairs = []
    for i, name in enumerate(VOICES):
        path = os.path.join(args.indir, '2608_%s.wav' % name)
        pcm, rate = read_wav_mono16(path)
        pcm = resample_linear(pcm, rate)
        pcm12 = [max(-2048, min(2047, s >> 4)) for s in pcm]
        data = pack_voice(pcm12, inc_lut)
        # start256/end256 index the STORE (the payload lands at store offset
        # 0), so they do not include the file's 32-byte header.
        start256 = len(payload) // 256
        end256 = (len(payload) + len(data) - 1) // 256
        pairs.append((start256, end256))
        payload += data
        print('  %-3s %6.1f kHz->%5.1f kHz  %6d samples -> %5d bytes  store [%#05x..%#05x]'
              % (name, rate / 1000.0, ADPCM_RATE / 1000.0, len(pcm12), len(data),
                 start256 * 256, end256 * 256 + 255))

    if len(payload) > RHY_BYTES:
        sys.exit('rhythm_pack: payload %d bytes exceeds the %d-byte store' %
                 (len(payload), RHY_BYTES))

    hdr = bytearray()
    hdr += MAGIC
    hdr += struct.pack('<I', HDR_BYTES)
    for s, e in pairs:
        hdr += struct.pack('<HH', s, e)
    assert len(hdr) == HDR_BYTES

    with open(args.out, 'wb') as f:
        f.write(hdr + payload)
    print('%s: %d bytes (%d payload)' % (args.out, HDR_BYTES + len(payload), len(payload)))


if __name__ == '__main__':
    main()
