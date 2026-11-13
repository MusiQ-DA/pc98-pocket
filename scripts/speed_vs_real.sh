#!/usr/bin/env bash
# speed_vs_real.sh -- rerun the measurable rows of docs/SPEED_VS_REAL.md and
# print each one against its real-machine reference (ratio = core / real).
#
#   scripts/speed_vs_real.sh            full: cycle table at 8/10/12/Turbo,
#                                       tb_speed_fw (GDC + SCSI + FDD + the
#                                       cross-service rows), APF at 1 us and
#                                       1 ms per dataslot transfer (~4 min)
#   scripts/speed_vs_real.sh --quick    cycle table at 10 MHz only and the
#                                       GDC rows of tb_speed_fw (~2 min)
#
# Both benches are Verilator --timing, so per AGENTS.md they run in the
# pc98-sim docker image (docker build -t pc98-sim sim/). Set NO_DOCKER=1 to
# use the host's verilator anyway (Homebrew 5.05x mis-schedules some
# --timing benches; tb_speed_fw's waits are plain edge loops and have not
# shown it, but CI's 5.020 is the reference).
#
# Output: ${SIM_OUT:-.simout/speed_vs_real}/{cycle.txt,fw_*.log,report.txt}.
# Nothing here changes RTL or firmware; it reads the committed firmware.vh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1
OUT_REL="${SIM_OUT:-.simout/speed_vs_real}"
mkdir -p "$OUT_REL"
OUT="$(cd "$OUT_REL" && pwd)"
case "$OUT" in "$ROOT"/*) ;; *) echo "SIM_OUT must sit inside the repo (docker mounts it)"; exit 2 ;; esac
REL="${OUT#"$ROOT"/}"

run() {   # run a command line in the sim image (or on the host)
  if [ -n "${NO_DOCKER:-}" ]; then bash -c "$1"
  else docker run --rm -v "$ROOT":/work -w /work pc98-sim bash -c "$1"; fi
}
W() { if [ -n "${NO_DOCKER:-}" ]; then echo "$ROOT"; else echo /work; fi; }

# ---- 1. CPU / memory / VRAM / I/O: the existing cycle table ---------------
SPEEDS="0 1 2 3"; [ $QUICK = 1 ] && SPEEDS="1"
echo "== cycle table (speeds $SPEEDS)"
run "SIM_OUT=$(W)/$REL/cycle bash scripts/sim_cycle_table.sh $SPEEDS" | tee "$OUT/cycle.txt"

# ---- 2. firmware services: tb_speed_fw on the real softcpu + firmware.vh --
S=fpga/core
echo "== building tb_speed_fw"
run "verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 \
  --top-module tb_speed_fw -Isim -I$S -I$S/common -Ifpga/apf \
  sim/tb_speed_fw.sv sim/stub_altsyncram.sv sim/stub_vhdl.sv sim/stub_pll.sv fpga/apf/common.v \
  $S/softcpu_subsystem.sv $S/picorv32.v $S/sprom.v $S/softcpu_fdd_bridge.sv \
  -o spd --Mdir $(W)/$REL/obj > $(W)/$REL/build.log 2>&1 || { grep -A3 %Error $(W)/$REL/build.log | head -30; exit 1; }"
# the sprom loads ../firmware/firmware.vh relative to the cwd: run from fpga/
if [ $QUICK = 1 ]; then
  run "cd $(W)/fpga && $(W)/$REL/obj/spd +quick" > "$OUT/fw_apf1us.log"
  run "cd $(W)/fpga && $(W)/$REL/obj/spd +quick +svclat=30" > "$OUT/fw_svc30.log"
else
  run "cd $(W)/fpga && $(W)/$REL/obj/spd" > "$OUT/fw_apf1us.log" &
  run "cd $(W)/fpga && $(W)/$REL/obj/spd +tdslat=43000" > "$OUT/fw_apf1ms.log" &
  run "cd $(W)/fpga && $(W)/$REL/obj/spd +quick +svclat=30" > "$OUT/fw_svc30.log" &
  wait
fi
for f in "$OUT"/fw_*.log; do
  grep -q "RESULT: DONE" "$f" || { echo "FAIL: $f did not finish"; tail -5 "$f"; exit 1; }
done

# ---- 3. the report: core vs real ------------------------------------------
python3 - "$OUT" "$QUICK" <<'PY' | tee "$OUT/report.txt"
import re, sys, os, glob
out, quick = sys.argv[1], sys.argv[2] == "1"

def spd(path):
    d = {}
    if not os.path.exists(path): return d
    for l in open(path):
        m = re.match(r"SPD (\S+) (.*)", l)
        if m:
            kv = dict(re.findall(r"(\w+)=(-?[\d.]+)", m.group(2)))
            d[m.group(1)] = {k: float(v) for k, v in kv.items()}
    return d

def flag(r):
    return "  <-- 遅い" if r > 1.2 else ("  <-- 速い" if r < 0.8 else "")

# -- CPU rows: core clocks per iteration vs the 286 data sheet (+np21w waits)
print("## CPU / メモリ / VRAM / I/O (scripts/sim_cycle_table.sh)")
print("同クロック実機比 = 測定 CPU クロック / (80286 データシート + np21w ウェイト)")
print("Turbo 時間比 = (Turbo 21.48 MHz での時間) / (10 MHz 実機の時間)")
F = {"8MHz": 8.013908, "10MHz": 9.830393, "12MHz": 11.967435, "Turbo": 21.477273}
lines = open(os.path.join(out, "cycle.txt")).read().splitlines()
hdr = next((l for l in lines if l.startswith("ph ")), None)
if hdr:
    cols = hdr.split()[4:]
    names = cols[0::2]
    for l in lines:
        m = re.match(r"([0-9A-F]{2})\s+(\S+)\s+(.{28})\s+(\d+)\s+(.*)", l)
        if not m: continue
        v = m.group(5).split()
        row = f"{m.group(1)} {m.group(2):5} {m.group(3).strip():28}"
        ref10 = None
        for i, n in enumerate(names):
            cyc, r = float(v[2*i]), float(v[2*i+1])
            row += f"  {n} {r:4.2f}"
            if n == "10MHz": ref10 = cyc / r
        if "Turbo" in names and ref10:
            i = names.index("Turbo")
            cyc = float(v[2*i])
            tr = (cyc / F["Turbo"]) / (ref10 / F["10MHz"])
            row += f"  Turbo時間比 {tr:4.2f}"
        print(row)

# -- firmware services
fw = spd(os.path.join(out, "fw_apf1us.log"))
fwms = spd(os.path.join(out, "fw_apf1ms.log"))
s30 = spd(os.path.join(out, "fw_svc30.log"))
print("\n## ファームウェア処理 (sim/tb_speed_fw.sv, 実 firmware.vh)")
# np21w gdc_sub.c calc_gdcslavewait: dots * 27648 / 15625 base clocks
# (2.4576 MHz) + 30 base clocks -> 0.71998 us a dot + 12.21 us a command.
def gdc_ref(dots): return dots * 27648 / 15625 / 2.4576 + 30 / 2.4576
print(f"{'行':26} {'コア完了 us':>12} {'np21w us':>10} {'比':>8}  (DRAWING 立下りまで)")
for k in ["gdc_dot", "gdc_line100", "gdc_line400h", "gdc_line640h", "gdc_line100_grcg",
          "gdc_line100_dash", "gdc_arc_r7", "gdc_arc_r100", "gdc_rect100x50",
          "gdc_vectt16", "gdc_texte8x8", "gdc_wdat1", "gdc_wdat40", "gdc_wdat1000"]:
    if k not in fw: continue
    t, dots = fw[k]["done_us"], fw[k].get("dots", 1)
    ref = gdc_ref(dots)
    print(f"{k:26} {t:12.1f} {ref:10.1f} {t/ref:8.1f}{flag(t/ref)}")
if "gdc_line100" in s30 and "gdc_line100" in fw:
    print(f"  svc 応答 30 pico clk 時の line100: {s30['gdc_line100']['done_us']:.1f} us "
          f"(既定 6: {fw['gdc_line100']['done_us']:.1f} us)")

# FDD: real 2HD = 360 rpm, 8 x 1024 B a track -> 20.83 ms a sector slot
# (16.38 ms of it data at 500 kbps), average rotational wait 83.3 ms.
# np21w fdc.c: the result interrupt 512 CPU clocks after the command, DMA
# moves the sector at once.
FDD_SEQ = 166.667 / 8 * 1000
NP_FDC = 512 / 9.8304
if any(k.startswith("fdd_") for k in fw):
    print(f"\n{'行':26} {'コア us':>10} {'実機 us':>10} {'比':>6} {'np21w us':>9}  (要求→FIFO 満杯、APF 1us/転送)")
    for k in ["fdd_rd_cold", "fdd_rd_seq", "fdd_rd_rand", "fdd_rd_same_trk"]:
        if k not in fw: continue
        t = fw[k]["done_us"]
        ref = FDD_SEQ + (83333 if k in ("fdd_rd_rand",) else 0)
        print(f"{k:26} {t:10.1f} {ref:10.1f} {t/ref:6.2f} {NP_FDC:9.1f}{flag(t/ref)}")
        if k in fwms:
            print(f"{'  (APF 1ms/転送)':26} {fwms[k]['done_us']:10.1f}")

# SCSI: real -55 + a 1990 drive (ESTIMATE): ~1 MB/s -> 0.5 ms a block,
# ~1 ms command overhead, +25 ms average seek+rotation on a random access.
# np21w scsiio.c: each phase interrupt 4000 CPU clocks (407 us at 10 MHz).
def scsi_ref(blocks): return 1000 + 512 * blocks
if any(k.startswith("scsi_") for k in fw):
    print(f"\n{'行':26} {'コア us':>10} {'実機推定':>9} {'比':>6} {'np21w us':>9}  (要求→STATUS、APF 1us/転送)")
    for k, b in [("scsi_tur", 0), ("scsi_read10_1", 1), ("scsi_read10_8", 8),
                 ("scsi_read10_16", 16), ("scsi_write10_1", 1), ("scsi_write10_8", 8),
                 ("scsi_inquiry", 0)]:
        if k not in fw: continue
        t = fw[k]["done_us"]; ref = scsi_ref(b)
        print(f"{k:26} {t:10.1f} {ref:9.1f} {t/ref:6.2f} {4000/9.8304:9.1f}{flag(t/ref)}")
        if k in fwms:
            print(f"{'  (APF 1ms/転送)':26} {fwms[k]['done_us']:10.1f}")

print("\n## レイテンシ / サービス間干渉")
for k in ["boot_release", "irq_tick_osd_closed", "irq_tick_osd_open", "gdc_idle_claim",
          "gdc_idle_claim_mounted", "scsi_idle_claim_mounted", "gdc_line400h_osdopen",
          "gdc_dot_behind_scsi16", "scsi_tur_behind_line640", "fdd_rd_behind_line640",
          "gdc_dot_behind_fdd_cold", "scsi_tur_after_gdc_dot", "fdd_rd_after_gdc_dot",
          "fdd_mount"]:
    if k in fw:
        v = fw[k]
        print(f"{k:26} " + " ".join(f"{a}={b:g}" for a, b in v.items()))
PY
echo "report: $OUT/report.txt"
