#!/usr/bin/env python3
"""check_osd_layout.py -- do any two OSD fields overlap?

The PC-98 readouts have been unreadable twice for the same reason: two fields
on one row whose x extents run into each other. The panel is PANEL_W pixels of
an 8-pixel font, so every field's span is computable and so is every collision.
Eyeballing it from a photograph of a handheld screen is not a review process.

Parses the osd_draw_string / hex / dec calls in postmon.c, works out each
field's [x, x+width) on its row, and fails on any overlap or anything past the
right edge.
"""
import re, sys, pathlib, subprocess, shutil

SRC = pathlib.Path("pcxt-base/src/firmware/postmon.c")
CFG = pathlib.Path("pcxt-base/src/fpga/config.tcl")
FONT_W = 8

# Check the configuration that will actually ship, not the union of every
# branch: half the fields are behind #ifndef MACHINE_PC98 and the first version
# of this script reported them all as collisions with the ones that replace
# them. Take the macros from config.tcl, the way the firmware Makefile does.
defines = re.findall(
    r'set_global_assignment\s+-name\s+VERILOG_MACRO\s+"([^"]+)"',
    "\n".join(l for l in CFG.read_text().splitlines()
               if not l.lstrip().startswith("#")))

cc = shutil.which("clang") or shutil.which("cc")
txt = None
if cc:
    # -I the source's own directory for its local headers, and keep the
    # freestanding headers (stdint.h) that clang ships.
    r = subprocess.run([cc, "-E", "-P", "-ffreestanding", "-I", str(SRC.parent)]
                       + [f"-D{d}" for d in defines] + [str(SRC)],
                       capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip():
        txt = r.stdout
if txt is None:
    # No usable preprocessor: fall back to the raw text, which over-reports.
    txt = SRC.read_text()

m = re.search(r"#define\s+PANEL_W\s+(\d+)", SRC.read_text())
PANEL_W = int(m.group(1)) if m else 320

txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.S)
txt = re.sub(r"//[^\n]*", "", txt)


def strip_pcat_only(src):
    """Drop `#ifndef MACHINE_PC98` blocks.

    The panel draws two different machines' fields on the same rows, and the
    PC/AT ones do not exist in a PC-98 build. Counting both reported collisions
    between fields that can never be on screen together -- SEQ against the I/O
    history, MAX against LDN -- and a checker that cries wolf is one that gets
    ignored the day it is right.
    """
    out, depth, skip_at = [], 0, None
    for line in src.split("\n"):
        t = line.strip()
        if t.startswith("#if"):
            depth += 1
            if skip_at is None and t.startswith("#ifndef MACHINE_PC98"):
                skip_at = depth
        elif t.startswith("#else") and skip_at == depth:
            skip_at = None
            out.append("")
            continue
        elif t.startswith("#endif"):
            if skip_at == depth:
                skip_at = None
            depth -= 1
        if skip_at is None:
            out.append(line)
        else:
            out.append("")
    return "\n".join(out)


txt = strip_pcat_only(txt)


def val(expr):
    """Evaluate the simple arithmetic these calls use."""
    expr = expr.strip()
    if not re.fullmatch(r"[0-9\s+\-*/()]+", expr):
        return None
    try:
        return int(eval(expr))
    except Exception:
        return None


fields = []   # (row, x0, x1, label)

for mm in re.finditer(r"osd_draw_string\(&fb,\s*([^,]+),\s*([^,]+),\s*\"([^\"]*)\"", txt):
    x, y, s = val(mm.group(1)), val(mm.group(2)), mm.group(3)
    if x is None or y is None:
        continue
    fields.append((y, x, x + len(s) * FONT_W, repr(s)))

for mm in re.finditer(r"\bhex\(\s*([^,]+),\s*([^,]+),\s*(?:[^,]|\([^)]*\))+,\s*(\d+)\s*\)", txt):
    x, y, n = val(mm.group(1)), val(mm.group(2)), int(mm.group(3))
    if x is None or y is None:
        continue
    fields.append((y, x, x + n * FONT_W, f"hex{n}"))

# dec() has no fixed width; assume the worst a 16-bit counter can print.
for mm in re.finditer(r"\bdec\(\s*([^,]+),\s*([^,]+),", txt):
    x, y = val(mm.group(1)), val(mm.group(2))
    if x is None or y is None:
        continue
    fields.append((y, x, x + 5 * FONT_W, "dec(<=5)"))

# Fields that share a row because they are the two arms of a runtime if/else
# and can never both be drawn. The preprocessor cannot see that, so name them.
RUNTIME_EXCLUSIVE = ("'VEC", )

bad = 0
rows = {}
for y, x0, x1, lab in fields:
    rows.setdefault(y, []).append((x0, x1, lab))

for y in sorted(rows):
    items = sorted(rows[y])
    for i in range(len(items) - 1):
        a, b = items[i], items[i + 1]
        if a[2].startswith(RUNTIME_EXCLUSIVE) or b[2].startswith(RUNTIME_EXCLUSIVE):
            continue
        if a[1] > b[0]:
            print(f"OVERLAP row {y}: {a[2]} [{a[0]}..{a[1]}) into {b[2]} [{b[0]}..{b[1]})")
            bad += 1
    last = items[-1]
    if last[1] > PANEL_W:
        print(f"OFF-PANEL row {y}: {last[2]} ends at {last[1]}, panel is {PANEL_W}")
        bad += 1

if bad:
    print(f"check_osd_layout: {bad} problem(s)")
    sys.exit(1)
print(f"check_osd_layout: {len(fields)} fields on {len(rows)} rows, no overlaps")
