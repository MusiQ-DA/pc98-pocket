#!/usr/bin/env python3
"""Validate an np2kai op-stream (.ops) file.

Format (hex digits, lowercase, no 0x prefix):
    E <rg> <vv>         EGC register byte write  rg: 0..f   vv: 00..ff
    GT <p> <vvvv>       GRCG tile write          p:  0..3   vvvv: duplicated byte
    GM <vv>             GRCG mode register byte  (port 0x7C)
    W8  <a> <vv>        guest VRAM write 8-bit
    W16 <a> <vvvv>      guest VRAM write 16-bit
    R8  <a> <vv>        guest VRAM read 8-bit  (value returned)
    R16 <a> <vvvv>      guest VRAM read 16-bit (value returned)
    M <n>               engine selection: 0 normal, 1 GRCG, 2 EGC
    X                   end of stream
    # ...               comment line (ignored)

Addresses are the raw 'address' argument handed to np2kai's memvram/memrmw/
memtdw/memegc handlers -- i.e. VRAM-window-relative flat offsets such as
0xA8000..0xAFFFF for page 0, NOT a <32K offset.  GRCG/EGC internally mask to
LOW15, so identical records map onto the same 32K page either way.
"""
import re
import sys
from collections import Counter

HEX8 = re.compile(r"^[0-9a-f]{1,2}$")
HEX16 = re.compile(r"^[0-9a-f]{1,4}$")
ADDR = re.compile(r"^[0-9a-f]{1,8}$")
REG = re.compile(r"^[0-9a-f]{1,2}$")


def fail(lineno, msg):
    print(f"line {lineno}: {msg}", file=sys.stderr)
    sys.exit(1)


def check_int(s, lo, hi, lineno, what):
    try:
        v = int(s, 16)
    except ValueError:
        fail(lineno, f"{what}: bad hex {s!r}")
    if not (lo <= v <= hi):
        fail(lineno, f"{what}: 0x{s} out of range [{lo:#x},{hi:#x}]")
    return v


def main(path):
    counts = Counter()
    saw_x = False
    engine = None
    bad_after_x = []
    with open(path) as fp:
        for lineno, raw in enumerate(fp, 1):
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            f = line.split()
            op = f[0]
            if saw_x:
                bad_after_x.append(lineno)
            if op == "E":
                if len(f) != 3:
                    fail(lineno, f"E: expected 2 fields, got {len(f)-1}")
                if not REG.match(f[1]):
                    fail(lineno, f"E: bad reg {f[1]!r}")
                check_int(f[1], 0, 0xF, lineno, "E reg")
                if not HEX8.match(f[2]):
                    fail(lineno, f"E: bad val {f[2]!r}")
            elif op == "GT":
                if len(f) != 3:
                    fail(lineno, "GT: expected 2 fields")
                check_int(f[1], 0, 3, lineno, "GT plane")
                if not HEX16.match(f[2]):
                    fail(lineno, f"GT: bad tile {f[2]!r}")
            elif op == "GM":
                if len(f) != 2:
                    fail(lineno, "GM: expected 1 field")
                if not HEX8.match(f[1]):
                    fail(lineno, f"GM: bad mode {f[1]!r}")
            elif op in ("W8", "R8"):
                if len(f) != 3:
                    fail(lineno, f"{op}: expected 2 fields")
                if not ADDR.match(f[1]):
                    fail(lineno, f"{op}: bad addr {f[1]!r}")
                if not HEX8.match(f[2]):
                    fail(lineno, f"{op}: bad val {f[2]!r}")
            elif op in ("W16", "R16"):
                if len(f) != 3:
                    fail(lineno, f"{op}: expected 2 fields")
                if not ADDR.match(f[1]):
                    fail(lineno, f"{op}: bad addr {f[1]!r}")
                if not HEX16.match(f[2]):
                    fail(lineno, f"{op}: bad val {f[2]!r}")
            elif op == "M":
                if len(f) != 2:
                    fail(lineno, "M: expected 1 field")
                check_int(f[1], 0, 2, lineno, "M engine")
                engine = int(f[1], 16)
            elif op == "X":
                if len(f) != 1:
                    fail(lineno, "X: expected no fields")
                saw_x = True
            else:
                fail(lineno, f"unknown op {op!r}")
            counts[op] += 1

    if bad_after_x:
        fail(bad_after_x[0], "records found after X marker")
    if not saw_x:
        fail(0, "no X end-of-stream marker")

    print(f"{path}: OK")
    for k in ("M", "E", "GM", "GT", "W8", "W16", "R8", "R16", "X"):
        if counts[k]:
            print(f"  {k:3s} {counts[k]}")
    return counts


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
