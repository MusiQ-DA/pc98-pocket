#!/usr/bin/env bash
# sim_v30_bridge.sh -- the bridge bench (sim/tb_v30_bridge.sv): the nuV30 on
# the real KF8288 + READY + KF8259, through v30_cpu_bridge.
#
# Usage:
#   scripts/sim_v30_bridge.sh [+plusarg ...]        # fast memory (default)
#   scripts/sim_v30_bridge.sh +slow=12              # wait-state variant
#
# Part of CI as both variants; needs no ROMs.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
CFG="${TMPDIR:-/tmp}/pc98-dockercfg"
mkdir -p "$CFG"
python3 - "$CFG/config.json" <<'PY'
import json, sys, os
p = os.path.expanduser('~/.docker/config.json')
c = json.load(open(p)) if os.path.exists(p) else {}
c.pop('credsStore', None)
json.dump(c, open(sys.argv[1], 'w'))
PY
export DOCKER_CONFIG="$CFG"

S=pcxt-base/src/fpga/core
V=$S/v30
K=$S/KFPC-XT/HDL

# v30u_ucrom's simulation default is HEXDIR="hdl/rtl/ucore/" relative to the
# working directory -- and an empty microcode ROM is a $fatal, not a warning.
OUT="${TMPDIR:-/tmp}/pc98v30br"
mkdir -p "$OUT/hdl/rtl/ucore"
cp $V/ucrom.hex $V/ucdecode.hex "$OUT/hdl/rtl/ucore/"

docker run --rm -v "$PWD":/work -v "$OUT":/hex -w /hex \
    -e "SIMARGS=$*" pc98-sim bash -lc "
  set -e
  verilator --binary --timing -Wno-fatal \
    --top-module tb_v30_bridge \
    -I/work/sim -I/work/$S -I/work/$V -I/work/$K -I/work/$K/KF8288/HDL \
    -I/work/$K/KF8259/HDL \
    /work/$V/v30u_ss_pkg.sv \
    /work/sim/tb_v30_bridge.sv \
    /work/$S/v30_cpu_bridge.sv \
    /work/$V/v30_core.sv /work/$V/v30u_biu.sv /work/$V/v30u_eu.sv \
    /work/$V/v30u_ucrom.sv \
    /work/$K/XT_CE_Generator.sv /work/$K/KF8288/HDL/KF8288.sv \
    /work/$K/Ready.sv \
    /work/$K/KF8259/HDL/KF8259.sv /work/$K/KF8259/HDL/KF8259_Bus_Control_Logic.sv \
    /work/$K/KF8259/HDL/KF8259_Control_Logic.sv /work/$K/KF8259/HDL/KF8259_In_Service.sv \
    /work/$K/KF8259/HDL/KF8259_Interrupt_Request.sv \
    /work/$K/KF8259/HDL/KF8259_Priority_Resolver.sv \
    -o v30br --Mdir /tmp/obj_v30br
  /tmp/obj_v30br/v30br \$SIMARGS
"
