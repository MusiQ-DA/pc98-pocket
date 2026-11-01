#!/usr/bin/env bash
# sim_dhry.sh -- a real program's kernel, end to end on the CPU path.
#
# CPUBENCH 0.980's Dhrystone routine (sim/z86_tests/dhry_kernel.hex, out of
# testdisk/cpubench.lzh) runs LOOPS times at 2000:0000 under a timer IRQ, and
# its code+data (20000-21AFF) must end byte-identical to the Unicorn reference
# (sim/z86_tests/dhry_expect<LOOPS>.hex). Hand-optimised compiler output --
# BP frames, string moves, calls through pointers, word stores at odd offsets
# into its own data -- under every setting the CPU ships:
#
#   tb_z86_loop: free, priced (+pace), priced with a wait state (+pacew=1,
#                random memory latency), each with interrupts landing anywhere
#   tb_mem_perf: (with PERF=<binary>) the whole path core_top wires -- z86 +
#                z86_cache + bridge + 8288 + RAM.sv + SDRAM -- at 10 MHz and
#                Turbo, the cache on, a timer IRQ through the INTA cycles.
#
#   scripts/sim_dhry.sh                 # tb_z86_loop runs only
#   PERF=obj_dir/perf scripts/sim_dhry.sh
#
# Extra plusargs for both benches ride DHRY_EXTRA (e.g. "+dx=1" to replay a
# hardware-bisect revert, see core_top's slot 0x09 [28:20]).
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/dhry}"
LOOPS=50
EXP=sim/z86_tests/dhry_expect$LOOPS.hex
EXTRA="${DHRY_EXTRA:-}"
mkdir -p "$OUT"
python3 scripts/sim_dhry.py "$OUT" $LOOPS $EXP

SIM_OUT="$OUT/loop" bash scripts/sim_z86_loop.sh +n=1 > /dev/null

check() {   # <label> <dump>
  python3 - "$1" "$2" "$EXP" <<'PY'
import sys
label, dump, exp = sys.argv[1:]
d = [l for l in open(dump) if l.strip() and not l.startswith('//')]
got = bytes(int(l, 16) for l in d[0x20000:0x21B00])
want = bytes(int(l, 16) for l in open(exp) if l.strip() and not l.startswith('//'))
bad = [i for i in range(len(want)) if got[i] != want[i]]
if bad:
    print(f"FAIL {label}: {len(bad)} bytes differ, first " +
          ", ".join(f"{0x20000 + i:05x} want {want[i]:02x} got {got[i]:02x}" for i in bad[:4]))
    sys.exit(1)
print(f"ok   {label}")
PY
}

fail=0
while read -r label args; do
  r=$("$OUT/loop/loop" $args $EXTRA +org=90000 +mem="$OUT/dhry.mem" +prog="$OUT/dhry.prog" \
        +lat=4 +maxcyc=200000000 +dump="$OUT/z.dump")
  if ! grep -q "interrupts taken: [1-9]" <<< "$r" || grep -q TIMEOUT <<< "$r"; then
    echo "FAIL $label: $(grep -E 'TIMEOUT|interrupts' <<< "$r" | head -2 | tr '\n' ' ')"; fail=1; continue
  fi
  check "tb_z86_loop $label" "$OUT/z.dump" || fail=1
done <<'RUNS'
free        +irq=1009
paced       +pace +irq=3001
paced-w1    +pace +pacew=1 +irq=2003 +latrand
RUNS

if [ -n "${PERF:-}" ]; then
  for sp in 1 3; do
    "$PERF" +speed=$sp +pfdis +cache $EXTRA +img="$OUT/dhry.img" +imgref="$OUT/dhry.ref" \
        +imgstop=9002b +imglo=20000 +imghi=21b00 +imgirq=20000 > "$OUT/perf$sp.log" 2>&1 || true
    if grep -q "=== PASS tb_mem_perf img ===" "$OUT/perf$sp.log"; then
      echo "ok   tb_mem_perf speed $sp ($(grep -o 'IMG DONE.*' "$OUT/perf$sp.log"))"
    else
      echo "FAIL tb_mem_perf speed $sp"; grep -E "IMG|TIMEOUT" "$OUT/perf$sp.log" | head -10; fail=1
    fi
  done
fi
exit $fail
