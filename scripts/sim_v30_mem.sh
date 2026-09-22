#!/usr/bin/env bash
# sim_v30_mem.sh -- the V30 against the real memory path (tb_v30_mem).
#
#   scripts/sim_v30_mem.sh              # byte-at-a-time, as the machine is now
#   scripts/sim_v30_mem.sh --word       # with PC98_WORD_MEM: word = one burst
#
# Needs no ROMs: the program is poked into the part's storage by the bench.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORD=0
PRISTINE=0
PR_RAM=0
PR_BRIDGE=0
while :; do
  case "${1:-}" in
    --word)     WORD=1; shift ;;
    # --pristine: build against the f3aa15c copies of RAM.sv, the shim and the
    # bridge, extracted into /tmp/pristine. The control for "did this bench find
    # a bug that was already there, or one I just introduced?".
    --pristine) PRISTINE=1; shift ;;
    # Per-file, to say WHICH change carries a result.
    --pristine-ram)    PR_RAM=1;    shift ;;
    --pristine-bridge) PR_BRIDGE=1; shift ;;
    *) break ;;
  esac
done

S=fpga/core
K=$S/chipset/HDL
V=$S/v30

DEF="+define+CPU_V30+V30_BACKDOOR+MACHINE_PC98+SDRAM_USE_MP"
[ "$WORD" = 1 ] && DEF="$DEF+PC98_WORD_MEM"

OUT="${TMPDIR:-/tmp}/v30mem"
mkdir -p "$OUT/hdl/rtl/ucore"
cp $V/ucrom.hex $V/ucdecode.hex "$OUT/hdl/rtl/ucore/"

cp /tmp/pristine/*.sv "$OUT/" 2>/dev/null || true
if [ "$PRISTINE" = 1 ]; then PR_RAM=1; PR_BRIDGE=1; fi
[ "$PR_BRIDGE" = 1 ] && BR="$OUT/v30_cpu_bridge.sv" || BR="/work/$S/v30_cpu_bridge.sv"
if [ "$PR_RAM" = 1 ]; then
    RAMF="$OUT/RAM.sv $OUT/sdram_shim.sv"
else
    RAMF="/work/$K/RAM.sv /work/$S/sdram_shim.sv"
fi
RTL="$BR $RAMF"

NAME="${SIM_NAME:-v30mem}"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run --rm --name "$NAME" -v "$PWD":/work -w "$OUT" \
    -v "$OUT":"$OUT" -e "SIMARGS=${SIMARGS:-}$*" -e "RTL=$RTL" pc98-sim bash -lc "
  set -e
  cd $OUT
  verilator --binary --timing -Wno-fatal --top-module tb_v30_mem $DEF \
    -O2 -I/work/sim -I/work/$S -I/work/$V -I/work/$K -I/work/$K/i8288/HDL \
    /work/sim/tb_v30_mem.sv \
    /work/$V/v30u_ss_pkg.sv /work/$V/v30_core.sv /work/$V/v30u_biu.sv \
    /work/$V/v30u_eu.sv /work/$V/v30u_ucrom.sv \
    \$RTL \
    /work/$S/sdram_mp.sv \
    /work/sim/sdram_board_model.sv /work/sim/sdram_model.sv \
    /work/$K/Ready.sv /work/$K/ce_generator.sv \
    /work/$K/i8288/HDL/i8288.sv \
    -o v30mem --Mdir $OUT/obj
  $OUT/obj/v30mem \$SIMARGS
" 
