#!/usr/bin/env bash
# sim_cycle_table.sh -- what one instruction costs on the real CPU path,
# set against the 80286 data sheet.
#
# Runs tb_mem_perf's instruction-cost probes (phases 20-37, +cyconly) through
# the whole path core_top wires -- z86 + z86_cache (priced at the paced
# settings) + cpu_bus_bridge + 8288 + READY + RAM.sv + SDRAM + the GRCG
# sequencer -- at the paced speeds, and prints one row per probe:
#
#   measured CPU clocks per loop iteration (body + the loop's own
#   DEC BP / JZ / JMP NEAR)
#   the 80286 data-sheet count for the same iteration (real mode, no wait
#   states, queue full; m = 1 for a branch target; the loop part is 13)
#   ratio = measured / data sheet   (<1: faster than a 286, >1: slower)
#
# The loop is counted in, not subtracted: an empty-loop baseline carries
# fetch refills that a longer body hides behind its own execution, so
# subtracting it under-counts exactly the rows that overlap best.
#
# The data-sheet column is the floor a real VX2/VX21/RX can never beat; its
# DRAM waits and I/O recovery only add to it. Rows marked VRAM / I/O depend on
# PC-98 wait states: those carry np21w's per-access VRAM/GRCG waits
# (pccore.c np2cfg.wait), averaged over the frame.
#
# Regression guard: with --check, every row's ratio must stay within 25% of
# sim/cycle_table_baseline.txt (speed, phase, ratio). A deliberate timing
# change updates the baseline with --update.
#
#   scripts/sim_cycle_table.sh [--check|--update] [speeds...]   (default: 0 1 2)
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE=show
case "${1:-}" in --check) MODE=check; shift ;; --update) MODE=update; shift ;; esac
SPEEDS="${*:-0 1 2}"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/cycle_table}"
mkdir -p "$OUT"

S=fpga/core; K=$S/chipset/HDL; Z8=$S/z86
if [ ! -x "$OUT/obj/perf" ] || [ -n "${REBUILD:-}" ]; then
  verilator --binary --timing -Wno-fatal --top-module tb_mem_perf \
    --threads 4 -MAKEFLAGS OPT_FAST=-O2 --Mdir "$OUT/obj" \
    -Isim -I$S -I$S/common -I$Z8 -I$K -I$K/i8288/HDL \
    sim/tb_mem_perf.sv \
    $K/RAM.sv $K/Ready.sv $K/ce_generator.sv $K/i8288/HDL/i8288.sv \
    $S/sdram_shim.sv $S/sdram_mp.sv \
    $S/pc98_gvram_seq.sv $S/pc98_grcg.sv $S/pc98_egc.sv \
    $S/pc98_gdc_mode2.sv \
    $S/pc98_gvram_display.sv $S/pc98_video_timing.sv \
    sim/sdram_board_model.sv sim/sdram_model.sv \
    $Z8/z86_package.sv $Z8/fetch.sv $Z8/decode.sv \
    $Z8/execute.sv $Z8/write_back.sv $Z8/regfile.sv \
    $Z8/divider.sv $Z8/z86_cache.sv $Z8/z86.sv \
    $S/cpu_bus_bridge.sv -o perf > "$OUT/build.log" 2>&1 \
    || { grep -E "%Error" "$OUT/build.log" | head; exit 1; }
fi

for sp in $SPEEDS; do
  [ -n "${NORUN:-}" ] && continue
  # +pfdis: the bridge prefetch window off, as the paced settings ship;
  # +cache: z86_cache on (priced at speeds 0-2), as core_top runs it.
  "$OUT/obj/perf" +speed="$sp" +pfdis +cache +cyconly > "$OUT/s$sp.log" 2>&1
  grep -q "=== all phases done ===" "$OUT/s$sp.log" \
    || { echo "FAIL speed $sp: probes did not finish"; tail -5 "$OUT/s$sp.log"; exit 1; }
done

python3 - "$MODE" "$OUT" $SPEEDS <<'PY'
import re, sys, os
mode, out, speeds = sys.argv[1], sys.argv[2], sys.argv[3:]
# Graphics VRAM waits, np21w/np2kai's model (pccore.c np2cfg.wait =
# {1,1, 6,1, 8,1}: TRAM, VRAM, GRCG -- active display, vblank), charged per
# guest access on top of the data sheet (mem/memvram.c MEMWAIT_*). Averaged
# over a 24.8 kHz frame, 400 of 440 lines active.
ACT = 400 / 440
VRAMW = round(6 * ACT + 1 * (1 - ACT))      # 6
GRCG  = round(8 * ACT + 1 * (1 - ACT))      # 7
# phase: (class, body, 80286 data-sheet clocks per iteration)
SHEET = {
 0x21: ("EU",   "add r16,r16 x8",            8*2),
 0x22: ("EU",   "mov r16,r16 x8",            8*2),
 0x23: ("EU",   "inc r16 x8",                8*2),
 0x24: ("EU",   "shl r16,1 x8",              8*2),
 0x25: ("EU",   "shl r16,cl (cl=4) x8",      8*(5+4)),
 0x26: ("EU",   "mul r16 x4",                4*21),
 0x27: ("EU",   "div r16 x4",                4*22),
 0x28: ("EU",   "jc not taken x8",           8*3),
 0x29: ("EU",   "jmp short x8",              8*(7+1)),
 0x2A: ("MEM",  "mov ax,[m16] x8",           8*5),
 0x2B: ("MEM",  "mov [m16],ax x8",           8*3),
 0x2C: ("MEM",  "add [m16],ax x8",           8*7),
 0x2D: ("MEM",  "push r16 + pop r16 x4",     4*(3+5)),
 0x2E: ("MEM",  "call near + ret x4",        4*((7+1)+(11+1))),
 0x2F: ("MEM",  "int n + iret x4",           4*((23+1)+(17+1))),
 0x30: ("I/O",  "mov dx + in al,dx x4",      2+4*5),
 0x31: ("I/O",  "mov dx + out dx,al x4",     2+4*3),
 0x32: ("MEM",  "rep stosw 256",             2+2+4+3*256),
 0x33: ("MEM",  "rep movsw 256",             2+2+2+5+4*256),
 0x34: ("VRAM", "rep stosw 256 GRCG TDW",    2+2+4+(3+GRCG)*256),
 0x35: ("VRAM", "mov es:[m16],ax TDW x8",    8*(3+GRCG)),
 0x36: ("VRAM", "rep stosw 256 GRCG RMW",    2+2+4+(3+GRCG)*256),
 0x37: ("VRAM", "rep stosw 256 plain VRAM",  2+2+4+(3+VRAMW)*256),
}
LOOP = 2 + 3 + (7 + 1)   # dec bp / jz not taken / jmp near taken
SHEET = {k: (c, b, r + LOOP) for k, (c, b, r) in SHEET.items()}
SHEET[0x20] = ("loop", "empty loop (dec/jz/jmp near)", LOOP)
NAMES = {"0": "8MHz", "1": "10MHz", "2": "12MHz", "3": "Turbo"}
res = {}
for sp in speeds:
    cyc = {}
    for l in open(os.path.join(out, f"s{sp}.log"), errors="ignore"):
        m = re.match(r"CYC (\w\w) iters=(\d+) cpu=(\d+)", l)
        if m: cyc[int(m.group(1), 16)] = (int(m.group(2)), int(m.group(3)))
    for ph, (it, c) in cyc.items():
        if ph in SHEET:
            res[(sp, ph)] = c / it
hdr = f"{'ph':3} {'class':5} {'body':28} {'286':>6}" + "".join(
      f" {NAMES.get(s, s):>8} {'ratio':>6}" for s in speeds)
print(hdr); print("-" * len(hdr))
for ph, (cls, body, ref) in sorted(SHEET.items()):
    row = f"{ph:02X}  {cls:5} {body:28} {ref:6d}"
    for sp in speeds:
        v = res.get((sp, ph))
        row += f" {v:8.1f} {v/ref:6.2f}" if v is not None else f" {'-':>8} {'-':>6}"
    print(row)
print("\nratio <1: faster than the reference, >1: slower. Reference: 80286 data "
      "sheet, plus np21w's VRAM/GRCG waits on the VRAM rows (I/O rows: none).")

bl = "sim/cycle_table_baseline.txt"
if mode == "update":
    with open(bl, "w") as f:
        f.write("# speed phase ratio -- scripts/sim_cycle_table.sh --update\n")
        for (sp, ph), v in sorted(res.items()):
            f.write(f"{sp} {ph:02X} {v/SHEET[ph][2]:.3f}\n")
    print(f"wrote {bl}")
elif mode == "check":
    bad = 0
    for l in open(bl):
        if l.startswith("#") or not l.strip(): continue
        sp, ph, r0 = l.split(); ph = int(ph, 16); r0 = float(r0)
        if sp not in speeds: continue
        v = res.get((sp, ph))
        if v is None:
            print(f"FAIL {NAMES.get(sp, sp)} {ph:02X}: no result"); bad += 1; continue
        r = v / SHEET[ph][2]
        if abs(r - r0) > 0.25 * r0:
            print(f"FAIL {NAMES.get(sp, sp)} {ph:02X} {SHEET[ph][1]}: "
                  f"ratio {r:.2f}, baseline {r0:.2f} (beyond +-25%)"); bad += 1
    print("cycle table: " + ("PASS" if not bad else f"{bad} row(s) moved"))
    sys.exit(1 if bad else 0)
PY
