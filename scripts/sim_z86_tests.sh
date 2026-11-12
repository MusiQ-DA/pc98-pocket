#!/usr/bin/env bash
# sim_z86_tests.sh -- z86 instruction-pair regressions on tb_z86_loop.
#
# Each sim/z86_tests/<name>.hex (assembled from the .asm beside it) leaves
# its results at 0600h; the expected bytes are below. Run at two memory
# latencies, since the hazards depend on how fast the read comes back.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SIM_OUT:-${TMPDIR:-/tmp}/z86tests}"
# Z86_EXTRA="+pace [+pacew=W]": the whole suite again with z86_cache's priced
# hits (the paced settings' timing). A paced CPU takes ~4x the tb clocks per
# instruction, so the interrupt periods stretch to match (a 500-clk IRQ there
# outruns its own handler, on the metal too) and the runaway bound widens.
EXTRA="${Z86_EXTRA:-}"
case "$EXTRA" in *pace*) IRQS="2003 3001 4999"; RIRQ=(4000 2647 5987); MAXC=+maxcyc=80000000 ;;
                 *)      IRQS="337 523 1009";  RIRQ=(500 331 997);    MAXC= ;; esac
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
raw_smc|22 33 c3 5a
raw_wcomb|00 00 58 02 f4 f4 f4 f4 ac
raw_de|00 01 00 00 01 00 00 01 00 00 01 00 00 01 00 01 5a"
fail=0
while IFS='|' read -r t want; do
  org=400; [ "$t" = raw_smc ] && org=1000
  for lat in 1 4; do
    got=$("$OUT/loop" $EXTRA +org=$org +prog=sim/z86_tests/$t.hex +lat=$lat +n=8000 \
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
  got=$("$OUT/loop" $EXTRA +org=400 +prog=sim/z86_tests/raw_pairs.hex +lat=3 +rst_at=$r | sed -n 's/^mem 0600: //p')
  [ "${got:0:${#want}}" = "$want" ] || { echo "FAIL reset at clock $r: $got"; rbad=1; }
done
[ $rbad = 0 ] && echo "ok   mid-run resets" || fail=1
# OUT 0F0h resetting the CPU before its cycle is acked (the PC-98 bus at
# 10 MHz): the write must not be replayed after the reset.
for lat in 1 4; do
  got=$("$OUT/loop" $EXTRA +org=400 +prog=sim/z86_tests/irq_f0reset.hex +lat=$lat +f0reset | sed -n 's/^mem 0600: //p')
  [ "${got:0:2}" = "77" ] && echo "ok   f0 reset before ack lat=$lat" || { echo "FAIL f0 reset before ack lat=$lat: $got"; fail=1; }
done
# Interrupt acknowledge: one INTA per handler run, none after an OUT has
# withdrawn the request (+irqclr). The vector used to outlive its injection,
# so the next INTR ran the previous handler again with no INTA at all.
ibad=0
for a in "" +irqclr; do for irq in $IRQS; do for lat in 1 4; do
  o=$("$OUT/loop" $EXTRA +org=400 +prog=sim/z86_tests/irq_withdraw.hex +lat=$lat +irq=$irq $a)
  ta=$(echo "$o" | sed -n 's/interrupts taken: \([0-9]*\) spurious.*/\1/p')
  sp=$(echo "$o" | sed -n 's/.*spurious: \([0-9]*\)$/\1/p' | head -1)
  w=$(echo "$o" | sed -n 's/^mem 0600: \(..\) \(..\) \(..\) \(..\).*/\2\1 \4\3/p')
  if [ -z "$ta" ] || [ "$sp" != 0 ] || [ "$((16#${w%% *}))" != "$ta" ] || [ "${w##* }" != 00ac ]; then
    echo "FAIL irq_withdraw $a irq=$irq lat=$lat: inta=$ta spurious=$sp mem=$w"; ibad=1; fi
done; done; done
[ $ibad = 0 ] && echo "ok   interrupt acknowledge (irq_withdraw)" || fail=1
# HLT ends on an interrupt IF admits and resumes after it; CLI; HLT stays.
for lat in 1 4; do
  o=$("$OUT/loop" $EXTRA +org=400 +prog=sim/z86_tests/irq_hlt.hex +lat=$lat +irq=2000)
  w=$(echo "$o" | sed -n 's/^mem 0600: \(.. .. .. ..\).*/\1/p')
  [ "$w" = "05 00 05 00" ] && echo "ok   hlt wakes on intr lat=$lat" || { echo "FAIL hlt wake lat=$lat: $w"; fail=1; }
done
# An IN behind a taken branch must not reach the bus: +scsiport makes 0xCC6
# a FIFO, so a leaked fall-through read shows as a skipped byte (taken LOOP
# and JCXZ leaked one; scsi_rom.asm's mode_page lost its page code to it).
for lat in 1 2 4 16; do
  got=$("$OUT/loop" $EXTRA +org=400 +prog=sim/z86_tests/raw_spec_in.hex +scsiport \
        +scsistream=sim/z86_tests/raw_spec_in.stream.hex +lat=$lat | sed -n 's/^mem 0600: //p')
  want="01 02 03 04 05 06 07"
  [ "${got:0:${#want}}" = "$want" ] && echo "ok   raw_spec_in lat=$lat" \
    || { echo "FAIL raw_spec_in lat=$lat"; echo "  want $want"; echo "  got  $got"; fail=1; }
done
# Interruptible REP (irq_rep.asm): long REP string ops -- every form, with
# segment overrides in both prefix orders, REP INS/OUTS -- must end exactly
# as they do uninterrupted, the interrupt must land between iterations
# (most handler runs return to a REP's first prefix), never inside a REP's
# bytes, and INTR must not wait for a whole REP (max latency, tb clocks).
# 0604: returns inside a REP (0), 0606: failed checks (0), 0608: AC,
# 061E: the last byte REP OUTSB wrote.
for a in "+lat=1" "+lat=4 +irq=${RIRQ[0]}" "+lat=5 +latrand +irq=${RIRQ[1]}" "+lat=3 +gate +irq=${RIRQ[2]}"; do
  o=$("$OUT/loop" $EXTRA $MAXC +org=1000 +prog=sim/z86_tests/irq_rep.hex $a)
  m=$(echo "$o" | sed -n 's/^mem 0600: //p')
  [ -n "$m" ] || { echo "FAIL irq_rep $a: $(echo "$o" | tail -1)"; fail=1; continue; }
  set -- $m
  runs=$((16#$2$1)); hits=$((16#$4$3)); chk="$5 $6 $7 $8 $9 ${31}"
  lat=$(echo "$o" | sed -n 's/^irq latency max: \([0-9]*\) clocks/\1/p')
  bad=0
  [ "$chk" = "00 00 00 00 ac 5d" ] || bad=1
  case "$a" in *irq*)
    [ "$runs" -gt 1000 ] && [ $((hits * 4)) -gt "$runs" ] && [ -n "$lat" ] && [ "$lat" -lt 400 ] || bad=1 ;;
  esac
  if [ $bad = 0 ]; then echo "ok   irq_rep $a (runs=$runs mid-rep=$hits maxlat=${lat:--})"
  else echo "FAIL irq_rep $a: runs=$runs mid-rep=$hits maxlat=$lat mem=$m"; fail=1; fi
done
# The 80286 protected-mode build (z86 PM286=1, EXT_MB=2 -- tb_z86_loop's default): raw_pm.asm runs
# LGDT/SGDT, LMSW/SMSW, descriptor loads, far CALL/RETF, extended memory and
# the hole above it, the A20 gate, and OUT 0F0h back to real mode.
if [ -z "${Z86_DEFS:-}" ]; then
  SIM_OUT="$OUT.pm" Z86_DEFS=+define+PM286 bash scripts/sim_z86_loop.sh +n=1 > /dev/null
  PMLOOP="$OUT.pm/loop"
else
  PMLOOP="$OUT/loop"
fi
want="3f 00 00 20 00 ff f1 ff 34 12 cd ab ff ff 5a a5 34 12 21 43 34 12 cc 77 f0 ff cd ab 77 f6 00"
for a in "+lat=1" "+lat=4" "+lat=3 +gate" "+lat=5 +latrand" "+lat=2 +nocache"; do
  got=$("$PMLOOP" $EXTRA +org=400 +prog=sim/z86_tests/raw_pm.hex +f0reset $a | sed -n 's/^mem 0600: //p')
  if [ "${got:0:${#want}}" = "$want" ]; then echo "ok   raw_pm $a"
  else echo "FAIL raw_pm $a"; echo "  want $want"; echo "  got  $got"; fail=1; fi
done
# raw_hma.asm: real-mode HMA access with the A20 gate open -- DS:/ES: loads
# and stores, LES + [es:bx+4] list walks, code run from FFFF:8000 (a line
# load from extended memory), then the gate closed by OUT 0F0h.
want="34 12 cd ab 5a 04 0a c3 ef be cd ab"
for a in "+lat=1" "+lat=4 +nocache" "+lat=3 +gate" "+lat=5 +latrand +nocache"; do
  got=$("$PMLOOP" $EXTRA +org=400 +prog=sim/z86_tests/raw_hma.hex +f0reset $a | sed -n 's/^mem 0600: //p')
  if [ "${got:0:${#want}}" = "$want" ]; then echo "ok   raw_hma $a"
  else echo "FAIL raw_hma $a"; echo "  want $want"; echo "  got  $got"; fail=1; fi
done
# raw_ext8.asm: the shipping 8 MB (EXT_MB=8, core_top's map -- linear
# 100000h-8FFFFFh at SDRAM 0x800000-0xFFFFFF) with A20 open: patterns at
# 100000h, 4FFFFFh and 8FFFF0h-8FFFFFh read back, the hole at 900000h reads
# FF, nothing aliases low. +extoff (the OSD's Ext Memory = None) makes all
# of it the hole. The bench fails any port-F access between the guest's
# 2 MB and the 0x800000 pool (GVRAM, the font bank, the FDD carve-out).
if [ -z "${Z86_DEFS:-}" ]; then
  SIM_OUT="$OUT.pm8" Z86_DEFS="+define+PM286 +define+EXT_MB=8" bash scripts/sim_z86_loop.sh +n=1 > /dev/null
  PM8LOOP="$OUT.pm8/loop"
  want_on="ff ff 34 12 88 77 5a 00 a5 c3 ef be 96 69 cd ab 34 12 5a"
  want_off="ff ff ff ff ff ff ff 00 ff ff ff ff ff ff cd ab ff ff 5a"
  for a in "+lat=1" "+lat=4" "+lat=3 +gate" "+lat=5 +latrand" "+lat=2 +nocache" \
           "+lat=1 +extoff" "+lat=4 +latrand +extoff" "+lat=2 +nocache +extoff"; do
    case "$a" in *extoff*) want="$want_off" ;; *) want="$want_on" ;; esac
    o=$("$PM8LOOP" $EXTRA +org=400 +prog=sim/z86_tests/raw_ext8.hex $a)
    got=$(echo "$o" | sed -n 's/^mem 0600: //p')
    span=$(echo "$o" | sed -n 's/^port F ext writes: //p')
    bad=0
    [ "${got:0:${#want}}" = "$want" ] || bad=1
    echo "$o" | grep -q "^FAIL port F" && bad=1
    case "$a" in
      *extoff*) [ -z "$span" ] || bad=1 ;;
      *)        [ "$span" = "800000-fffffe" ] || [ "$span" = "800000-ffffff" ] || bad=1 ;;
    esac
    if [ $bad = 0 ]; then echo "ok   raw_ext8 $a${span:+ (ext writes $span)}"
    else echo "FAIL raw_ext8 $a"; echo "  want $want"; echo "  got  $got"; echo "  span $span"
         echo "$o" | grep "^FAIL port F" | head -3; fail=1; fi
  done
fi
exit $fail
