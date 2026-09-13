#!/usr/bin/env python3
"""check_vkb_layout.py -- is the on-screen keyboard's table sane?

The virtual keyboard's key rectangles are hand-computed pixel coordinates in
vkb_layout.c. Two layouts live there (PC-9801 and PC/XT, selected by the
MACHINE_PC98 macro the firmware Makefile takes from config.tcl), and the PC-98
one additionally substitutes made-up Set-2 codes for keys no real keyboard has.
None of that is visible from a photograph of a handheld screen, so check it
mechanically, the way check_osd_layout.py does for the POST panel:

  * every key rect lies inside the 636x81 VKB region, and no two overlap;
  * every legend's ink (from the real font ROM image, font/font_8x8.vh) fits
    its key, and a dual legend's halves stay clear of each other;
  * scancodes are unique except where two keys share one on purpose, nothing
    emits 0x00, and the key count fits vkb_ui.c's latch bitmaps (96);
  * the PC-98-only sentinel codes are distinct and unreachable from the docked
    USB keyboard (parsed live from hid_to_ps2.sv, so the check follows the RTL);
  * the vkb_ui.c visual-row spans cover every key exactly, in order.

Prints the compiled table (label -> rect -> Set-2 code) as it goes: that list
is the Set-2 assignment the PC-98 keyboard translator has to match.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "pcxt-base/src/firmware"
CFG = ROOT / "pcxt-base/src/fpga/config.tcl"
HID = ROOT / "pcxt-base/src/fpga/core/hid_to_ps2.sv"
FONT = SRC / "font/font_8x8.vh"
VKB_W, VKB_H = 636, 81
FONT_W = 8
SEP = "\x1f"  # vkb_layout.h VKB_LBL_SEP: splits a dual legend's two halves

# Keys that may share a scancode, and why. Everything else must be unique.
SHARED_CODES = {0x5A: "RETURN and keypad ENTER (same PC-98 matrix code 0x1C)"}

# Codes with structural meaning in pocket_keyboard / Peripherals: the framer's
# E0/F0/E1/E2 bytes, the XT keyboard's 0xAA power-on self-test reply. A VKB key
# emitting one would derail the stream, so they are banned outright.
BANNED_CODES = {0x00, 0xAA, 0xE0, 0xE1, 0xE2, 0xF0}

# Scancodes reserved for button-function ids in key_bind.c (0xF1..).
MAX_CODE = 0xF0 - 1

LATCH_BITS = 96  # vkb_ui.c: latch_bits[3], one bit per key index


def config_defines():
    """The VERILOG_MACROs the firmware Makefile turns into -D flags."""
    out = {}
    for line in CFG.read_text().splitlines():
        if line.lstrip().startswith("#"):
            continue
        m = re.search(r'set_global_assignment\s+-name\s+VERILOG_MACRO\s+"(\w+)=(\w+)"', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def select_branches(text, defines):
    """Drop the #if branches the preprocessor would drop for these defines.

    Only #ifdef/#ifndef NAME is evaluated (that is all vkb_layout.c uses);
    any other conditional is kept with its nesting tracked, the same
    conservative stance check_osd_layout.py takes.
    """
    out, depth, skip_at = [], 0, None
    decided = {}  # depth -> True when this depth's #if was evaluated and taken
    for line in text.split("\n"):
        t = line.strip()
        if t.startswith("#if"):
            depth += 1
            decided[depth] = False
            m = re.match(r"#if(?:def|ndef)\s+(\w+)", t)
            if m and m.group(1) in defines:
                val = defines[m.group(1)] not in ("0", "")
                keep = val if "ndef" not in t else not val
                if keep:
                    decided[depth] = True  # the #if arm stands; an #else must go
                elif skip_at is None:
                    skip_at = depth
        elif t.startswith("#else"):
            if decided.get(depth):
                skip_at = depth  # the first arm was kept, drop the second
            elif skip_at == depth:
                skip_at = None
            out.append("")
            continue
        elif t.startswith("#endif"):
            if skip_at == depth:
                skip_at = None
            decided.pop(depth, None)
            depth -= 1
        out.append("" if skip_at is not None else line)
    return "\n".join(out)


def c_string(lit):
    """Evaluate a C string literal's inner text (the escapes the tables use)."""
    out, i = [], 0
    while i < len(lit):
        c = lit[i]
        if c == "\\" and i + 1 < len(lit):
            n = lit[i + 1]
            if n == "x":
                j = i + 2
                while j < len(lit) and lit[j] in "0123456789abcdefABCDEF":
                    j += 1
                out.append(chr(int(lit[i + 2:j], 16)))
                i = j
                continue
            out.append({"n": "\n", "t": "\t", "0": "\0", "\\": "\\", '"': '"', "'": "'"}[n])
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def split_args(s):
    """Split a macro call's argument list on top-level commas."""
    args, cur, q, depth = [], "", None, 0
    i = 0
    while i < len(s):
        c = s[i]
        if q:
            cur += c
            if c == q and (i == 0 or s[i - 1] != "\\"):
                q = None
        elif c in "\"'":
            q = c
            cur += c
        elif c == "(":
            depth += 1
            cur += c
        elif c == ")":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip():
        args.append(cur.strip())
    return args


def parse_defines(text):
    """Simple #define NAME value map (macros of the PC98K_/G_/GL_ kind)."""
    defs = {}
    for m in re.finditer(r'^\s*#define\s+(\w+)\s+(.+?)\s*$', text, re.M):
        val = re.sub(r"//.*$", "", m.group(2)).strip()  # drop any trailing comment
        defs[m.group(1)] = val
    return defs


def resolve(tok, defs):
    """Turn a macro token into its (value, string) payload."""
    seen = set()
    while tok in defs and tok not in seen:
        seen.add(tok)
        tok = defs[tok]
    tok = tok.strip()
    if len(tok) >= 2 and tok.startswith('"') and tok.endswith('"'):
        return c_string(tok[1:-1])
    try:
        return int(tok, 0)
    except ValueError:
        return None


def parse_keys(text):
    """The vkb_keys[] entries of the selected branch: (labels, x, y, w, h, code)."""
    defs = parse_defines(text)
    keys = []
    for m in re.finditer(r'^\s*(K2A|KA|K2|K)\s*\((.*?)\)\s*,?\s*(?://.*)?$', text, re.M):
        args = split_args(m.group(2))
        if len(args) != (7 if m.group(1) in ("K2", "K2A") else 6):
            continue  # not a table entry (macro definition or stray call)
        nums = [int(a, 0) for a in args[:4]]
        x, y, w, h = nums
        code = resolve(args[4], defs)
        if m.group(1) in ("K2", "K2A"):
            l1, l2 = resolve(args[5], defs), resolve(args[6], defs)
            label = l1 + SEP + l2
        else:
            label = resolve(args[5], defs)
        keys.append({"label": label, "x": x, "y": y, "w": w, "h": h, "code": code})
    return keys


def parse_vrows(text):
    """The vrows[] spans of the selected branch."""
    spans = []
    for m in re.finditer(r'^\s*\{\s*(\d+)\s*,\s*(\d+)\s*\}\s*,', text, re.M):
        spans.append((int(m.group(1)), int(m.group(2))))
    return spans


def load_font():
    """font_8x8.vh: 2048 bytes, glyph-major. Return per-glyph ink extents."""
    words = re.findall(r"[0-9a-fA-F]{2}", FONT.read_text())
    assert len(words) == 2048, f"font image has {len(words)} bytes, want 2048"
    ext = []
    for g in range(256):
        cols = set()
        for r in range(8):
            b = int(words[g * 8 + r], 16)
            for c in range(8):
                if b & (0x80 >> c):
                    cols.add(c)
        ext.append((min(cols), max(cols)) if cols else None)
    return ext


def ink_span(font, ch, x):
    e = font[ord(ch) & 0xFF]
    if e is None:
        return None
    return (x + e[0], x + e[1])


def hid_reachable():
    """Bare Set-2 codes the docked USB keyboard can put on the stream."""
    codes = set()
    t = HID.read_text()
    for m in re.finditer(r"8'h([0-9A-Fa-f]{2})\s*:\s*(?:hid2ps2|mod2ps2)\s*=\s*8'h([0-9A-Fa-f]{2})", t):
        codes.add(int(m.group(2), 16))
    return codes


def main():
    font = load_font()
    reachable = hid_reachable()
    shipping = config_defines()
    failures = 0

    # Check the configuration that will actually ship, then the other one: the
    # two tables live behind the same #ifdef, and only ever building one of them
    # is how the other quietly rots.
    flipped = dict(shipping)
    flipped["MACHINE_PC98"] = "0" if shipping.get("MACHINE_PC98", "0") not in ("0", "") else "1"
    for defines, note in ((shipping, "shipping config"), (flipped, "flipped config")):
        bad = check_layout(defines, font, reachable, verbose=defines is shipping)
        pc98 = defines.get("MACHINE_PC98", "0") not in ("0", "")
        machine = "PC-9801" if pc98 else "PC/XT"
        tag = f" ({note})" if defines is flipped else ""
        if bad:
            print(f"check_vkb_layout: {machine}{tag}: {bad} problem(s)")
            failures += 1
        else:
            print(f"check_vkb_layout: {machine}{tag}: ok")
    return 1 if failures else 0


def check_layout(defines, font, reachable, verbose):
    layout = select_branches((SRC / "vkb_layout.c").read_text(), defines)
    ui = select_branches((SRC / "vkb_ui.c").read_text(), defines)
    keys = parse_keys(layout)
    vrows = parse_vrows(ui)
    pc98 = defines.get("MACHINE_PC98", "0") not in ("0", "")
    bad = 0

    machine = "PC-9801" if pc98 else "PC/XT"
    print(f"check_vkb_layout: {machine} table, {len(keys)} keys, {len(vrows)} visual rows")

    if not keys:
        print("check_vkb_layout: no keys parsed -- the regex and the table drifted apart")
        return 1
    if len(keys) > LATCH_BITS:
        print(f"TOO MANY KEYS: {len(keys)} > {LATCH_BITS} latch bits in vkb_ui.c")
        bad += 1

    # Rect bounds and pairwise overlap.
    for i, k in enumerate(keys):
        if not (0 <= k["x"] and 0 <= k["y"] and k["x"] + k["w"] <= VKB_W and k["y"] + k["h"] <= VKB_H):
            print(f"OUT OF BOUNDS: #{i} {k['label']!r} {k['x']},{k['y']} {k['w']}x{k['h']}")
            bad += 1
        if k["w"] < 2 or k["h"] < 2:
            print(f"DEGENERATE RECT: #{i} {k['label']!r} {k['w']}x{k['h']}")
            bad += 1
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, b = keys[i], keys[j]
            if (a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"]
                    and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]):
                print(f"OVERLAP: #{i} {a['label']!r} into #{j} {b['label']!r}")
                bad += 1

    # Legend fit: ink extents against the key rect, dual halves clear of each other.
    for i, k in enumerate(keys):
        label = k["label"]
        if SEP in label:
            p, s = label.split(SEP, 1)
            if not s:
                print(f"EMPTY SECONDARY: #{i} {label!r}")
                bad += 1
                continue
            px = k["x"] + 4
            spans = []
            for n, ch in enumerate(p):
                sp = ink_span(font, ch, px + n * FONT_W)
                if sp:
                    spans.append(sp)
            sx = k["x"] + k["w"] - 3 - len(s) * FONT_W
            for n, ch in enumerate(s):
                sp = ink_span(font, ch, sx + n * FONT_W)
                if sp:
                    spans.append(sp)
            if spans:
                lo = min(sp[0] for sp in spans)
                hi = max(sp[1] for sp in spans)
                if lo < k["x"] + 1 or hi > k["x"] + k["w"] - 2:
                    print(f"LEGEND CLIPS KEY: #{i} {label!r} ink [{lo},{hi}] in "
                          f"[{k['x']},{k['x']+k['w']}]")
                    bad += 1
                pr = max((ink_span(font, ch, px + n * FONT_W) or (0, -1))[1]
                         for n, ch in enumerate(p) if ink_span(font, ch, px + n * FONT_W)) \
                    if any(ink_span(font, ch, px + n * FONT_W) for n, ch in enumerate(p)) else -1
                sl = min((ink_span(font, ch, sx + n * FONT_W)[0]
                          for n, ch in enumerate(s) if ink_span(font, ch, sx + n * FONT_W)),
                         default=k["x"] + k["w"])
                if pr >= sl:
                    print(f"DUAL LEGEND COLLIDES: #{i} {label!r} primary ink ends {pr}, "
                          f"secondary starts {sl}")
                    bad += 1
        else:
            cx = k["x"] + (k["w"] - len(label) * FONT_W) // 2
            spans = [ink_span(font, ch, cx + n * FONT_W) for n, ch in enumerate(label)]
            spans = [s for s in spans if s]
            if spans:
                lo = min(s[0] for s in spans)
                hi = max(s[1] for s in spans)
                if lo < k["x"] + 1 or hi > k["x"] + k["w"] - 2:
                    print(f"LEGEND CLIPS KEY: #{i} {label!r} ink [{lo},{hi}] in "
                          f"[{k['x']},{k['x']+k['w']}]")
                    bad += 1

    # Scancode sanity.
    seen = {}
    for i, k in enumerate(keys):
        c = k["code"]
        if not isinstance(c, int):
            print(f"UNPARSED CODE: #{i} {k['label']!r} -> {c!r}")
            bad += 1
            continue
        if c in BANNED_CODES or c > MAX_CODE:
            print(f"FORBIDDEN CODE: #{i} {k['label']!r} -> 0x{c:02X}")
            bad += 1
            continue
        if c in seen:
            why = SHARED_CODES.get(c)
            if why:
                print(f"shared 0x{c:02X}: #{seen[c]} and #{i} ({why})")
            else:
                print(f"DUPLICATE CODE: 0x{c:02X} on #{seen[c]} and #{i}")
                bad += 1
        seen[c] = i

    # PC-98 sentinel rules: distinct, and never something a docked key can send.
    if pc98:
        defs = parse_defines(layout)
        sentinels = {n: int(v, 0) for n, v in defs.items() if n.startswith("PC98K_")}
        reachable = hid_reachable()
        vals = {}
        for name, val in sorted(sentinels.items()):
            if val in vals:
                print(f"SENTINEL REUSED: {vals[val]} and {name} both 0x{val:02X}")
                bad += 1
            vals[val] = name
            if val in reachable:
                print(f"SENTINEL COLLIDES WITH DOCKED KEYBOARD: {name} 0x{val:02X} "
                      f"is a code hid_to_ps2 emits")
                bad += 1
            if val in seen and seen[val] is not None:
                pass  # it is in the table by design; the parse above printed it
        print("PC-98-only key sentinels (Set-2 code -> key):")
        for name, val in sorted(sentinels.items(), key=lambda kv: kv[1]):
            print(f"  0x{val:02X}  {name}")

    # vrows cover every key exactly once, in table order.
    covered = 0
    for n, (start, count) in enumerate(vrows):
        if start != covered:
            print(f"VROW {n} starts at {start}, expected {covered} (gap or overlap)")
            bad += 1
        covered = start + count
    if covered != len(keys):
        print(f"VROWS cover {covered} keys, table has {len(keys)}")
        bad += 1

    # The readable table itself: what the Set-2 -> PC-98 translator must match.
    if verbose:
        print(f"{'#':>3}  {'label':<14} {'rect':<20} code")
        for i, k in enumerate(keys):
            lab = k["label"].replace(SEP, "|")
            code = f"0x{k['code']:02X}" if isinstance(k["code"], int) else str(k["code"])
            print(f"{i:>3}  {lab:<14} "
                  f"{str(k['x'])+','+str(k['y'])+' '+str(k['w'])+'x'+str(k['h']):<20} {code}")

    if bad:
        print(f"check_vkb_layout: {machine}: {bad} problem(s)")
    else:
        print(f"check_vkb_layout: {len(keys)} keys, no overlaps, all legends fit")
    return bad


if __name__ == "__main__":
    sys.exit(main())
