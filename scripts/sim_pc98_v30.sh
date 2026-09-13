#!/usr/bin/env bash
# sim_pc98_v30.sh -- the full-machine V30 boot: real ROMs, real nuV30 core,
# real PIT/PIC/TVRAM/FDC models, to the BASIC banner.
#
# This is the bench the boot work actually runs in (sim/tb_pc98_v30.sv). It was
# driven by hand-assembled docker invocations until now; every one of them was
# lost with the container and the /tmp hex directory, so it lives here instead.
#
# Usage:
#   scripts/sim_pc98_v30.sh [+plusarg ...]          # foreground
#   SIM_NAME=pitfix scripts/sim_pc98_v30.sh -d ...  # detached container
#
# Useful plusargs: +nopitseed  +golden=<file>  +nokbd  +basicvec
#
# Not part of CI: it needs bios.rom and itf.rom, which are not in the tree.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DETACH=0
[ "${1:-}" = "-d" ] && { DETACH=1; shift; }

ROMS="${PC98_ROMS:-$HOME/.pc98roms}"
[ -f "$ROMS/itf.rom" ] && [ -f "$ROMS/bios.rom" ] \
    || { echo "need itf.rom and bios.rom in $ROMS"; exit 1; }

# The UX BIOS set, md5-pinned the same way deploy_pc98.sh pins it: a
# Franken-ROM here costs a thirty-minute run before it says anything wrong.
if [ "${PC98_ANY_ROMS:-0}" != "1" ]; then
    want_bios=3af0ae018c5710eec6e2891064814138
    want_itf=1d295699ffeab0f0e24e09381299259d
    got_bios=$(md5 -q "$ROMS/bios.rom"); got_itf=$(md5 -q "$ROMS/itf.rom")
    [ "$got_bios" = "$want_bios" ] || { echo "bios.rom md5 $got_bios != $want_bios (PC98_ANY_ROMS=1 to override)"; exit 1; }
    [ "$got_itf"  = "$want_itf"  ] || { echo "itf.rom md5 $got_itf != $want_itf (PC98_ANY_ROMS=1 to override)"; exit 1; }
fi

OUT="${TMPDIR:-/tmp}/pc98v30"
mkdir -p "$OUT"

python3 - "$ROMS" "$OUT" <<'PY'
import sys, os
roms, out = sys.argv[1], sys.argv[2]
for name, size in (("itf", 0x8000), ("bios", 0x18000)):
    d = open(os.path.join(roms, name + ".rom"), "rb").read()
    d = d[:size] + b"\xff" * max(0, size - len(d))
    with open(os.path.join(out, name + ".hex"), "w") as f:
        for i in range(0, size, 16):
            f.write(" ".join("%02x" % b for b in d[i:i+16]) + "\n")
    print("%-5s %6d bytes -> %s.hex" % (name, len(d), name))
PY

# v30u_ucrom's simulation default is HEXDIR="hdl/rtl/ucore/", relative to the
# working directory -- and an empty microcode ROM is a $fatal, not a warning.
mkdir -p "$OUT/hdl/rtl/ucore"
cp pcxt-base/src/fpga/core/v30/ucrom.hex pcxt-base/src/fpga/core/v30/ucdecode.hex "$OUT/hdl/rtl/ucore/"

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
K=$S/KFPC-XT/HDL
V=$S/v30

# Verilator's own default is OPT_FAST=-Os -- the generated model compiled for
# SIZE, on a run that is pure CPU time. A make-command-line override wins over
# verilated.mk, and -O2 is worth a large multiple here. It has to stay ONE
# token: verilator splits -MAKEFLAGS on whitespace, so "-O2 -march=native"
# reaches make as a variable plus a stray option and the build dies.
# SIM_THREADS splits the eval across cores (the box has 20, the run used one).
#
# NOT --x-assign fast / --x-initial fast: they are a speed win everywhere else,
# but here they changed the boot. With them the ITF parks in a two-instruction
# loop at F8448/F8476 that the default X handling walks straight through, so
# something in this machine still depends on an uninitialised value reading
# as X rather than 0. Measured, run keys2.
SIM_OPT="${SIM_OPT:--O2}"
SIM_THREADS="${SIM_THREADS:-4}"

BUILD_AND_RUN="
  set -e
  verilator --binary --timing -Wno-fatal -j 0 +define+V30_BACKDOOR \
    --threads $SIM_THREADS -MAKEFLAGS OPT_FAST=$SIM_OPT \
    --top-module tb_pc98_v30 \
    -I/work/sim -I/work/$S -I/work/$V -I/work/$K -I/work/$K/KF8288/HDL \
    -I/work/$K/KF8253/HDL -I/work/$K/KF8259/HDL \
    /work/$V/v30u_ss_pkg.sv \
    /work/sim/tb_pc98_v30.sv \
    /work/$V/v30_core.sv /work/$V/v30u_biu.sv /work/$V/v30u_eu.sv \
    /work/$V/v30u_ucrom.sv \
    /work/$S/pc98_tvram.sv /work/$K/pc98_fdc.sv \
    /work/$K/XT_CE_Generator.sv /work/$K/KF8288/HDL/KF8288.sv \
    /work/$K/KF8253/HDL/KF8253.sv /work/$K/KF8253/HDL/KF8253_Counter.sv \
    /work/$K/KF8253/HDL/KF8253_Control_Logic.sv \
    /work/$K/KF8259/HDL/KF8259.sv /work/$K/KF8259/HDL/KF8259_Bus_Control_Logic.sv \
    /work/$K/KF8259/HDL/KF8259_Control_Logic.sv /work/$K/KF8259/HDL/KF8259_In_Service.sv \
    /work/$K/KF8259/HDL/KF8259_Interrupt_Request.sv \
    /work/$K/KF8259/HDL/KF8259_Priority_Resolver.sv \
    -o v30boot --Mdir /tmp/obj_v30
  /tmp/obj_v30/v30boot \$SIMARGS
"

if [ "$DETACH" = 1 ]; then
    NAME="${SIM_NAME:-pc98v30}"
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" -v "$PWD":/work -v "$OUT":/hex -w /hex \
        -e "SIMARGS=$*" pc98-sim bash -lc "$BUILD_AND_RUN"
    echo "detached: docker logs -f $NAME"
else
    docker run --rm -v "$PWD":/work -v "$OUT":/hex -w /hex \
        -e "SIMARGS=$*" pc98-sim bash -lc "$BUILD_AND_RUN"
fi
