#!/usr/bin/env python3
# tvram_decode.py -- render a jtag_tvram.tcl dump as an 80x25 screen.
#
#   openocd -f scripts/jtag_probe.cfg -f scripts/jtag_tvram.tcl | python3 scripts/tvram_decode.py
#   python3 scripts/tvram_decode.py < dump.txt
#
# Cell format (pc98_glyph_addr.sv): char_hi & bitac -> kanji, stored as
# char_lo = JIS ku, char_hi = JIS ten; otherwise ANK in char_lo.

import re
import sys

COLS = 80


def jis_to_char(ku, ten):
    """JIS X 0208 ku/ten (0x21-0x7E each) -> unicode char."""
    try:
        if ku & 1:
            lo = ten + 0x20 if ten >= 0x60 else ten + 0x1F
        else:
            lo = ten + 0x7E
        hi = ((ku - 0x21) >> 1) + (0x81 if ku <= 0x5E else 0xC1)
        return bytes([hi, lo]).decode("shift_jis")
    except Exception:
        return "?"


def ank_char(b):
    if b in (0x00, 0x20):
        return " "
    try:
        return bytes([b]).decode("shift_jis")
    except Exception:
        return "."


def main():
    cells = {}
    pat = re.compile(r"^cell (\d+): ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2})")
    for line in sys.stdin:
        m = pat.match(line)
        if m:
            cells[int(m.group(1))] = tuple(int(m.group(i), 16) for i in (2, 3, 4))
    if not cells:
        print("no cells parsed", file=sys.stderr)
        sys.exit(1)

    last = max(cells)
    right_half = False
    for c in range(last + 1):
        attr, hi, lo = cells.get(c, (0, 0, 0))
        if right_half:
            right_half = False
            continue  # second cell of a kanji: its glyph spans both
        if hi:
            ch = jis_to_char(lo & 0x7F, hi & 0x7F)
            right_half = True
        else:
            ch = ank_char(lo)
        sys.stdout.write(ch)
        if (c + 1) % COLS == 0:
            sys.stdout.write("\n")
    if (last + 1) % COLS:
        sys.stdout.write("\n")


if __name__ == "__main__":
    main()
