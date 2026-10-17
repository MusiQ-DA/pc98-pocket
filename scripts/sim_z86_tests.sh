#!/usr/bin/env bash
# sim_z86_tests.sh -- z86 instruction-pair regressions on tb_z86_loop.
#
# Each sim/z86_tests/<name>.hex (assembled from the .asm beside it) leaves
# its results at 0600h; the expected bytes are below. Run at two memory
# latencies, since the hazards depend on how fast the read comes back.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/z86tests}"
SIM_OUT="$OUT" bash scripts/sim_z86_loop.sh +n=1 > /dev/null
# A combinational loop in z86 builds and even fits, then wedges on hardware;
# Verilator names it at build time (d2a9707: id_ucode_valid -> hazard -> emit).
if grep -q 'UNOPTFLAT' "$OUT.build.log"; then
  grep -A3 'UNOPTFLAT' "$OUT.build.log" | head -8
  echo "FAIL combinational loop in z86"; exit 1
fi
# bash 3 (macOS) has no associative arrays: name|expected bytes
TESTS="raw_xlat|5a 77 33 44 55 66 77
raw_microcode|ff ff 12 00 03 00 4f 5e 22 22 34 12 fe 07 fa 07 ff ff ff ff 7b 7a 15 00 04 03 02 01 02 01
raw_pairs|34 12 f2 07 11 5c 6d f4 ef be 22 33 cd ab 57 13 01 55 55 44 d6 04 01
raw_smc|22 33 c3 5a"
fail=0
while IFS='|' read -r t want; do
  org=400; [ "$t" = raw_smc ] && org=1000
  for lat in 1 4; do
    got=$("$OUT/loop" +org=$org +prog=sim/z86_tests/$t.hex +lat=$lat +n=8000 \
          | sed -n 's/^mem 0600: //p')
    if [ "${got:0:${#want}}" = "$want" ]; then echo "ok   $t lat=$lat"
    else echo "FAIL $t lat=$lat"; echo "  want $want"; echo "  got  $got"; fail=1; fi
  done
done <<< "$TESTS"
# A CPU reset mid-run (OUT 0F0h on the PC-98) at every phase of a load or
# micro-op: the restarted program must still finish with the same results.
want="34 12 f2 07 11 5c 6d f4 ef be 22 33 cd ab 57 13 01 55 55 44 d6 04 01"
rbad=0
for r in $(seq 100 37 2000); do
  got=$("$OUT/loop" +org=400 +prog=sim/z86_tests/raw_pairs.hex +lat=3 +rst_at=$r | sed -n 's/^mem 0600: //p')
  [ "${got:0:${#want}}" = "$want" ] || { echo "FAIL reset at clock $r: $got"; rbad=1; }
done
[ $rbad = 0 ] && echo "ok   mid-run resets" || fail=1
exit $fail
