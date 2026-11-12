#!/usr/bin/env bash
# sim_ems.sh -- the EMS bank registers (pc98_ems98, np21w io/emsio.c) through
# the real memory path: tb_mem_perf built with +define+TB_PM286 (z86 PM286,
# EXT_MB=8, z86_cache, cpu_bus_bridge, RAM.sv, sdram_mp) running
# sim/z86_tests/ems_np21w.hex. Checks that a byte stored through the C0000
# window at t=1 page 0 reads back at linear 100000h (A20 open) and vice
# versa, page & 0FCh, t=0 unmapping, t=9 dropped, IN 08E9h = 00 for t=1..8
# and FF for t=0/9/15, and with +extoff (Ext Memory None) that all of it
# reads FF.
#
# In the pc98-sim docker image (local Verilator mis-schedules --timing
# benches); CI runs the same commands natively (build.yml).
#   scripts/sim_ems.sh
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${IN_DOCKER:-}" ]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
  export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
  CFG="${TMPDIR:-/tmp}/pc98-dockercfg"
  mkdir -p "$CFG"
  python3 - "$CFG/config.json" <<'PY'
import json, os, sys
c = json.load(open(os.path.expanduser('~/.docker/config.json')))
c.pop('credsStore', None)
json.dump(c, open(sys.argv[1], 'w'))
PY
  export DOCKER_CONFIG="$CFG"
  exec docker run --rm -e IN_DOCKER=1 -e EMS_ONLY -v "$PWD":/work -w /work pc98-sim \
    bash scripts/sim_ems.sh "$@"
fi

S=fpga/core; K=$S/chipset/HDL; Z8=$S/z86
M=${EMS_MDIR:-/tmp/obj_ems}
verilator --binary --timing -Wno-fatal --top-module tb_mem_perf \
  --threads 4 -MAKEFLAGS OPT_FAST=-O2 +define+TB_PM286 \
  -Isim -I$S -I$S/common -I$Z8 -I$K -I$K/i8288/HDL \
  sim/tb_mem_perf.sv \
  $K/RAM.sv $K/Ready.sv $K/ce_generator.sv $K/i8288/HDL/i8288.sv \
  $S/sdram_shim.sv $S/sdram_mp.sv \
  $S/pc98_gvram_seq.sv $S/pc98_grcg.sv $S/pc98_egc.sv $S/pc98_ems98.sv \
  $S/pc98_gdc_mode2.sv \
  $S/pc98_gvram_display.sv $S/pc98_video_timing.sv \
  sim/sdram_board_model.sv sim/sdram_model.sv \
  $Z8/z86_package.sv $Z8/fetch.sv $Z8/decode.sv \
  $Z8/execute.sv $Z8/write_back.sv $Z8/regfile.sv \
  $Z8/divider.sv $Z8/z86_cache.sv $Z8/z86.sv \
  $S/cpu_bus_bridge.sv \
  --Mdir "$M" -o ems 2>&1 | grep -v "%Warning" | grep -v "^ " | tail -5 || true

want_on="ff 11 11 5a a5 3c 3c ff 5a 5a 00 00 00 00 00 00 00 00 ff ff 5a"
want_off="ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff 5a"
fail=0
[ -n "${EMS_ONLY:-}" ] && { "$M/ems" +ems=sim/z86_tests/ems_np21w.hex $EMS_ONLY; exit 0; }
for a in "" "+cache" "+speed=3" "+cache +speed=1" "+cache +speed=3 +GRANT" "+extoff" "+cache +extoff"; do
  o=$("$M/ems" +ems=sim/z86_tests/ems_np21w.hex $a 2>&1)
  got=$(echo "$o" | sed -n 's/^EMS: //p')
  pk=$(echo "$o" | sed -n 's/^EMS PEEK 900000=//p')
  case "$a" in *extoff*) want="$want_off" ;; *) want="$want_on" ;; esac
  bad=0
  [ "$got" = "$want" ] || bad=1
  case "$a" in *extoff*) [ "$pk" != "77" ] || bad=1 ;; *) [ "$pk" = "77" ] || bad=1 ;; esac
  if [ $bad = 0 ]; then echo "ok   ems_np21w ${a:-(default)} (900000=$pk)"
  else echo "FAIL ems_np21w ${a:-(default)}"; echo "  want $want"; echo "  got  $got"
       echo "  peek 900000=$pk"; echo "$o" | grep -E "TIMEOUT|BAD|FAIL" | head -5 || true; fail=1; fi
done
[ $fail = 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL"; exit 1; }
