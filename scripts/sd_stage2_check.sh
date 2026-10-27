#!/usr/bin/env bash
# sd_stage2_check.sh -- one-command SuperDepth stage-2 speed / BGM check on
# the Pocket over JTAG (no SD card, no human play).
#
#   scripts/sd_stage2_check.sh [turbo|10|8|12|0xNN] [--nocache]
#
# Loads testdisk/superdepth_tr.hdm (DEPTH -P810 -H9, stage 1 force-cleared
# ~36 s into play -> the game's own Clear transition -> stage 2) through
# jtag_hdload.tcl, presses START, and runs scripts/jtag_sd_stage2.tcl, which
# measures per stage over a fixed wall-clock window:
#   * game speed: VSYNCs per game frame (the main loop waits [0DD0h] >= 5;
#     the value it leaves the wait with is read from the tlog ring at the
#     loop's `mov [0DD0h],0`), steady frames only (deaths/Ready excluded)
#     -> speed% = 5 / mean * 100, plus the raw game-frame rate;
#   * BGM tempo: IRQ0 ISR entries per second (the ISR reloads PIT ch0 every
#     tick; ticks lost while interrupts are held off slow the music);
#   * Clear-transition black band: probe slots 0x84-0x86, only when the
#     build has BAND_PROBE=1 (pc98_gvram_display.sv); otherwise "n/a".
# Reference: np2kai (np2prof harness, tools/np2run on sd-stage2-profile,
# PC-9801VM, same image, 20 s windows):
#   stage 1: 5.00 VSYNC/frame (11.28 fps), IRQ0 1434.4 Hz (tempo word 180)
#   stage 2: 5.00 VSYNC/frame (steady; 9.8-10.5 fps raw incl. deaths),
#            IRQ0 1126.4 Hz (tempo 140); S2/S1 IRQ0 ratio 0.786
#            (1420.8/1118.3 Hz with the 1.9968 MHz clock -- same ratio)
# Verdict (stage 2): game speed = steady fps / 11.28; BGM = (S2/S1 IRQ0
# ratio) / 0.786.  speed >= 95% and BGM >= 97% PASS, >= 80% / >= 90% WARN,
# else FAIL.  Exit 0 on PASS, 1 FAIL, 2 WARN, 3 no data.
#
# env: W (title wait, s), T1 / T2 (window seconds per stage), NOLOAD=1 (image
# already loaded -- skips the ~1 min upload), LOG=<file>.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

SPD=${1:-turbo}
case "$SPD" in
    turbo) P=0x07 ;;
    12)    P=0x06 ;;
    10)    P=0x05 ;;
    8)     P=0x04 ;;
    0x*)   P=$SPD ;;
    *) echo "speed: turbo|12|10|8|0xNN"; exit 3 ;;
esac
[ "${2:-}" = "--nocache" ] && P=$(printf '0x%X' $(( P | 0x800 )))

IMG=testdisk/superdepth_tr.hdm
[ -f "$IMG" ] || { echo "$IMG missing: testdisk/build_superdepth_tr.sh"; exit 3; }
LOG=${LOG:-$(mktemp -t sd_stage2.XXXXXX)}

if [ -z "${NOLOAD:-}" ]; then
    echo "== upload $IMG =="
    python3 scripts/hdstream.py "$IMG" "$IMG.stream.tcl"
    HDIMG="$IMG" HDSTREAM="$IMG.stream.tcl" openocd \
        -f scripts/jtag_probe.cfg -f scripts/jtag_hdload.tcl 2>&1 \
        | grep -E "verify|mounted|stuck|never|WARNING" || true
fi

echo "== run (slot9=$P) =="
[ "$SPD" = turbo ] && WDEF=45 || WDEF=70
P=$P W=${W:-$WDEF} T1=${T1:-10} T2=${T2:-15} openocd \
    -f scripts/jtag_probe.cfg -f scripts/jtag_sd_stage2.tcl 2>&1 \
    | grep -v "^Info\|^Warn\|clock speed\|TapName\|^Open On\|^Licensed\|openocd.org\|DEPRECATED\|^shutdown" \
    | tee "$LOG"

python3 - "$LOG" "$P" <<'PY'
import sys
r = {}
for line in open(sys.argv[1]):
    if line.startswith("R ") and "=" in line:
        k, v = line[2:].strip().split("=", 1)
        r[k] = v
# np2kai, superdepth_tr.hdm, PC-9801VM x4: steady frames take 5 VSYNCs
# (56.42/5 = 11.28 fps) in both stages; IRQ0 at tempo word 180 (stage 1) /
# 140 (stage 2) = 1434.4 / 1126.4 Hz on the 2.4576 MHz clock, 1420.8 / 1118.3
# on 1.9968 MHz -- the stage-2/stage-1 ratio 0.786 is clock-independent.
NOM_FPS = 56.4247 / 5
REF_IRQ = {"s1": 1434.4, "s2": 1126.4}
REF_RAW = {"s1": 11.25, "s2": 9.9}
REF_S2S1 = 0.786
print("\n== SuperDepth stage check (slot9=%s) vs np2kai ==" % sys.argv[2])
if "verdict" in r:
    print("VERDICT", r["verdict"]); sys.exit(3)
for s in ("s1", "s2"):
    if s + "_steady_fps" not in r:
        continue
    sf = float(r[s+"_steady_fps"]); irq = float(r.get(s+"_irq0_hz", 0))
    print("%s: game %.2f fps steady = %5.1f%% of %.2f (%s VSYNC/frame, VSYNC IRQ %s Hz, %s frames) | "
          "raw %s fps (np2 ~%.1f) | IRQ0 %.1f Hz (np2 %.1f, tempo %s)"
          % (s, sf, 100*sf/NOM_FPS, NOM_FPS, r.get(s+"_vpf"), r.get(s+"_vsync_hz"),
             r.get(s+"_steady"), r.get(s+"_fps"), REF_RAW[s], irq, REF_IRQ[s], r.get(s+"_tempo")))
print("Clear-transition black band:", r.get("band", "?"),
      "(n/a = BAND_PROBE=0 build)" if r.get("band") == "n/a" else "(new frames with a >=8-line black run)")
need = ("s1_irq0_hz", "s2_irq0_hz", "s2_steady_fps")
if not all(k in r for k in need):
    print("VERDICT NODATA"); sys.exit(3)
spd = 100 * float(r["s2_steady_fps"]) / NOM_FPS
s1i, s2i = float(r["s1_irq0_hz"]), float(r["s2_irq0_hz"])
# BGM: stage 2's tick rate against stage 1's on the same machine (stage 1
# never holds interrupts off long), scaled by np2kai's stage-2/stage-1 ratio
bgm = 100 * (s2i / s1i) / REF_S2S1 if s1i else 0
if spd >= 95 and bgm >= 97:   v, rc = "PASS", 0
elif spd >= 80 and bgm >= 90: v, rc = "WARN", 2
else:                         v, rc = "FAIL", 1
print("VERDICT %s  stage-2 game speed %.1f%%  BGM tempo %.1f%% (S2/S1 IRQ0 %.3f vs np2 %.3f)"
      "  [PASS >=95/97, WARN >=80/90]" % (v, spd, bgm, s2i / s1i if s1i else 0, REF_S2S1))
sys.exit(rc)
PY
