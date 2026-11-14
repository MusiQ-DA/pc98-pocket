#!/usr/bin/env python3
"""sd_clearscroll.py -- reconstruct the SuperDepth Clear! scroll frames from
a scripts/jtag_sd_clearscroll.tcl log.

Per sample of probe slot 0x83 (pc98_gvram_display dbg hi word):
  line_now = v[31:23], cur_part = v[6:5], disp_page = v[3], fill_page = v[1].
cur_part is the walk's partition for display line line_now + 4 (the walk
leads the raster by LOOKAHEAD=3 and has already stepped for the edge).
0x3a = {6'0, SAD0[15:0], LEN0[9:0]}; 0x3c = {2'0, 16'0, LEN3, LEN2, LEN1}.

For each frame of the capture the script prints the observed 0->1
partition switch (bracketed in walk lines), the live PRAM, and what the
frame shows under the 918bd95 RTL: SAD0 used for frame f is the value at
line 0 of frame f-1 (part_sad_f latched at line 0, consumed at the line-396
wrap), LEN0 is live. rows = SAD0/40 .. SAD0/40 + switch - 1, then 0.. from
SAD1=0. Rows >= 400 at the seam are off-screen plane memory; a frame whose
top area ends anywhere but row 399 is torn against np2kai's picture
(np21w renders a frame from one register snapshot).
"""
import sys

LINE_US = 1e6 / (440 * 56.42)   # one rasterline, ~40.3 us (24.8 kHz)
LOOK = 4


def load(path):
    samples = []
    section = None
    for ln in open(path):
        if ln.startswith('# '):
            section = ln[2:].strip()
            continue
        if not ln.startswith('S '):
            continue
        _, t, a, v = ln.split()
        samples.append((int(t), int(a, 16), int(v, 16), section))
    return samples


def main(path):
    s = load(path)
    walk = [(t, (v >> 23) & 0x1FF, (v >> 5) & 3, (v >> 3) & 1, (v >> 1) & 1, sec)
            for t, a, v, sec in s if a == 0x83]
    pram = [(t, (v >> 10) & 0xFFFF, v & 0x3FF, sec) for t, a, v, sec in s if a == 0x3a]
    len1 = [(t, v & 0x3FF) for t, a, v, sec in s if a == 0x3c]
    for t, a, v, sec in s:
        if a == 0x82:
            print(f"# 0x82 [{sec}] skip={v >> 24} late={(v >> 16) & 0xff} max_fill={v & 0xffff}")
        if a == 0x39:
            print(f"# 0x39 [{sec}] pitch={v & 0xff} al={(v >> 8) & 0x3ff} lrep={(v >> 18) & 0x1f} "
                  f"dbl={(v >> 23) & 1} 5mhz={(v >> 24) & 1} analog={(v >> 25) & 1} "
                  f"page={(v >> 26) & 1} disp_on={(v >> 27) & 1}")
    cal = [w for w in walk if w[5] == 'CAL']
    if cal:
        parts = {}
        for w in cal:
            parts[w[2]] = parts.get(w[2], 0) + 1
        print(f"# CAL: {len(cal)} walk samples, cur_part histogram {parts}")
    cap = [w for w in walk if w[5] == 'CAPTURE']
    if not cap:
        print("# no capture")
        return

    # frame segmentation by line_now wrapping
    frames = []
    cur = []
    prev = None
    for w in cap:
        if prev is not None and w[1] < prev[1] and prev[1] - w[1] > 50:
            frames.append(cur)
            cur = []
        cur.append(w)
        prev = w
    frames.append(cur)

    def line_at(t):
        """raster line at time t, from the nearest walk sample (frame, line)."""
        best = min(range(len(cap)), key=lambda i: abs(cap[i][0] - t))
        return cap[best]

    # PRAM write events: SAD0/LEN0 changes between consecutive 0x3a samples
    caps = [p for p in pram if p[3] == 'CAPTURE']
    writes = []
    for p0, p1 in zip(caps, caps[1:]):
        if (p0[1], p0[2]) != (p1[1], p1[2]):
            tm = (p0[0] + p1[0]) / 2
            w = line_at(tm)
            ln = (w[1] + (tm - w[0]) / LINE_US) % 440
            writes.append((p0[0], p1[0], int(ln), p0[1], p0[2], p1[1], p1[2]))

    def pram_at(t):
        best = None
        for p in pram:
            if p[0] <= t:
                best = p
            else:
                break
        return best

    print(f"# capture: {len(cap)} walk samples, {len(frames)} frames, "
          f"{len(caps)} PRAM samples, {len(writes)} PRAM changes")
    print("# PRAM changes (t0..t1 us, est. raster line, SAD0/LEN0 old -> new):")
    for w in writes:
        print(f"W {w[0]}..{w[1]} line~{w[2]:3d}  SAD0 {w[3]:5d}(row {w[3] / 40:6.1f}) LEN0 {w[4]:3d}"
              f" -> SAD0 {w[5]:5d}(row {w[5] / 40:6.1f}) LEN0 {w[6]:3d}")

    print("# frames: n, t0, samples, switch bracket (walk line), live LEN0 at bracket, "
          "SAD0@line0 of this and the previous frame")
    sad_line0 = []
    torn = 0
    checked = 0
    for fi, fr in enumerate(frames):
        lo = max([w[1] + LOOK for w in fr if w[2] == 0 and w[1] < 392] or [-1])
        hi = min([w[1] + LOOK for w in fr if w[2] == 1 and w[1] < 392] or [999])
        t0 = fr[0][0] - fr[0][1] * LINE_US
        p0 = pram_at(t0)
        sad0 = p0[1] if p0 else None
        sad_line0.append(sad0)
        mid = None
        if lo >= 0 and hi < 999:
            tm = [w[0] for w in fr if w[1] + LOOK == hi][0]
            pm = pram_at(tm)
            mid = pm[2] if pm else None
        used = sad_line0[fi - 1] if fi > 0 else None
        note = ""
        if used is not None and lo >= 0 and hi < 999 and used:
            top = used // 40
            # rows shown at the seam: top + switch - 1 .. ; consistent iff switch == 400 - top
            want = 400 - top
            if not (lo < want <= hi):
                torn += 1
                note = f"  TORN: switch in ({lo},{hi}] but SAD0 used row {top} wants {want}" \
                       f" -> seam shows rows {top + lo + 1 - 1}..{top + hi - 1}"
            checked += 1
        print(f"F {fi:3d} t0={t0 / 1e6:8.3f}s n={len(fr):2d} sw=({lo},{hi}] LEN0@sw={mid} "
              f"SAD0@l0={sad0} used={used}{note}")
    print(f"# frames with a bracketed switch and a known SAD0: {checked}, torn: {torn}")


if __name__ == '__main__':
    main(sys.argv[1])
