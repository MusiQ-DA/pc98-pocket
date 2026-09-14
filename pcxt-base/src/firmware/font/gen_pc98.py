#!/usr/bin/env python3
"""gen_pc98.py -- rebuild font_8x8.png from a PC-98 font.rom's 8x8 ANK bank.

The OSD font started life as CP437 because the panel code grew out of the
PC/XT build. The machine this core emulates reads JIS X 0201, so the base
image is now the real half-width ANK font out of font.rom: the "V98" ROM
layout np2kai loads (io/cgrom.c reads it through font/fontv98.c) begins with
the 8x8 ANK bank -- 256 glyphs x 8 bytes at file offset 0, MSB = leftmost
dot, 1 = dot on -- the same geometry and polarity this PNG encodes, so the
bytes drop straight in. 0x5C lands on the yen sign and 0xA1-0xDF on the
half-width katakana, as on the real screen.

The OSD's own symbols are not in the ANK, so their slots are copied from the
current PNG instead: the settings frame's box drawing (0xDA/0xBF/0xC0/0xD9/
0xC4/0xB3 sits on katakana in JIS X 0201), the cursor/submenu marker 0x10,
the arrows 0x18-0x1B, the key-picker triangles 0x1E/0x1F, the tilde 0x7E (the
@ legend prints one; ANK 0x7E is the JIS overline), the CP437 yen slot 0x9D
(the virtual keyboard's yen-over-| legend), and the custom glyphs 0x01-0x07
(G_END..G_PRTSC in vkb_layout.c), which land on the ANK's blank control-code
area. The copy is idempotent -- the preserved slots round-trip byte for byte
through this script -- so re-running it against its own output is a no-op and
redrawing a preserved glyph in the PNG survives a later regeneration.

Run as   PC98_FONT_ROM=/path/to/font.rom python3 gen_pc98.py   then re-run
gen_8x8.py to refresh font_8x8.vh (the $readmemh image the OSD GPU loads).
"""

import os
import sys
from pathlib import Path

from gen_8x8 import COLS, ROWS, SIZE, load_glyphs

from PIL import Image

HERE = Path(__file__).resolve().parent
PNG = HERE / "font_8x8.png"

ANK_OFFSET = 0x0000  # font.rom: 8x8 ANK first, then 8x16 ANK at 0x800/0x1000
ANK_BYTES = 256 * 8

# Slots kept from the existing image rather than taken from the ANK, with the
# UI reference that owns them. Anything not listed here comes from font.rom.
PRESERVE = {
    0x01: "G_END (vkb_layout.c)",
    0x02: "G_HOME",
    0x03: "G_PGUP",
    0x04: "G_PGDN",
    0x05: "G_SHIFT",
    0x06: "G_RET",
    0x07: "G_PRTSC",
    0x10: "G_MARKER (settings_ui.c cursor/submenu)",
    0x18: "GL_UP arrow",
    0x19: "GL_DOWN arrow",
    0x1A: "GL_RIGHT arrow",
    0x1B: "GL_LEFT arrow",
    0x1E: "up triangle (key picker)",
    0x1F: "down triangle (also VKB_LBL_SEP, never drawn)",
    0x7E: "tilde (ANK 0x7E is the JIS overline)",
    0x9D: "yen, CP437 slot (VKB yen-over-bar legend)",
    0xB3: "frame vertical",
    0xBF: "frame top-right",
    0xC0: "frame bottom-left",
    0xC4: "frame horizontal",
    0xD9: "frame bottom-right",
    0xDA: "frame top-left",
}


def load_ank(path):
    """The 256 8-byte glyphs of the 8x8 ANK bank at the head of font.rom."""
    rom = Path(path).read_bytes()
    if len(rom) < ANK_OFFSET + ANK_BYTES:
        raise SystemExit(f"{path}: {len(rom)} bytes, too short for the 8x8 ANK bank")
    return [list(rom[ANK_OFFSET + i * 8:ANK_OFFSET + (i + 1) * 8]) for i in range(256)]


def save_png(glyphs):
    """Render the 16x16 grid back to the 1:1 PNG gen_8x8.py decodes (black = on)."""
    img = Image.new("L", (COLS * SIZE, ROWS * SIZE), 255)
    px = img.load()
    for i, glyph in enumerate(glyphs):
        ox, oy = (i % COLS) * SIZE, (i // COLS) * SIZE
        for r, bits in enumerate(glyph):
            for c in range(SIZE):
                if bits & (0x80 >> c):
                    px[ox + c, oy + r] = 0
    img.save(PNG)


def main():
    rom = os.environ.get("PC98_FONT_ROM", str(Path.home() / ".pc98roms" / "font.rom"))
    ank = load_ank(rom)
    img_glyphs = load_glyphs(Image.open(PNG))

    glyphs = [list(g) for g in ank]  # copy: the report compares against a pure ANK
    for code in sorted(PRESERVE):
        glyphs[code] = img_glyphs[code]

    save_png(glyphs)
    changed = sum(1 for i in range(256) if ank[i] != glyphs[i])
    print(f"{PNG.name}: {256 - changed} glyphs from {rom} (8x8 ANK), "
          f"{changed} kept from the existing image")
    for code in sorted(PRESERVE):
        print(f"  kept 0x{code:02X}  {PRESERVE[code]}")
    print("now run gen_8x8.py to regenerate font_8x8.vh")


if __name__ == "__main__":
    sys.exit(main())
