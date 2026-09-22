#!/bin/bash
# lint_core.sh -- elaborate the whole core with Verilator and fail on the two
# mistakes that only Quartus otherwise catches: an undeclared identifier and an
# implicit net.
#
# Why this exists: core_top.sv carries `default_nettype none`, so Quartus turns
# a name with no declaration into a hard error -- but Verilator only warns
# (%Warning-IMPLICIT) and infers a 1-bit wire, and the v30 testbench assembles
# its own machine without core_top or the CHIPSET at all, so the sims never
# compile the files where this happens.  Two Quartus runs died at line 2461
# and line 1298 in core_top for exactly this before this script did.
#
# The file list and the feature macros come from the real project files
# (ap_core.qsf and config.tcl), not from a hand-kept copy, so a new RTL file or
# a new ENABLE_* is picked up without editing this script.
#
# The APF-side files are excluded (apf_top and the megafunctions need the
# Quartus IP world); the core-side files that instantiate altera_pll and
# mf_datatable are linted against the behavioural stubs in sim/, and the
# only errors ignored are those that name those stubs' real counterparts.
set -uo pipefail
cd "$(dirname "$0")/.."

S=fpga/core
LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT

python3 - "$LIST" <<'PY'
import re, sys
qsf = open('fpga/ap_core.qsf').read()
files = re.findall(r'set_global_assignment -name (?:VERILOG_FILE|SYSTEMVERILOG_FILE) "?([^"\n]+?)"?$', qsf, re.M)
files = ['fpga/' + f for f in files if f.endswith(('.v', '.sv')) and '/apf/' not in f]
# common.v defines synch_3, which the core files instantiate all over; it is
# not in the .qsf (it arrives via apf.qip) but it is plain Verilog.
files.append('fpga/apf/common.v')
open(sys.argv[1], 'w').write('\n'.join(files))
PY

# The ENABLE_* set, read the same way the firmware Makefile reads it: anchored
# to the start of the line so a commented-out macro stays commented out.
DEFINES=$(sed -n 's/^[[:space:]]*set_global_assignment.*VERILOG_MACRO "\(.*\)"/\1/p' fpga/config.tcl \
          | tr '\n' ' ' | sed 's/ /+/g')

OUT=$(mktemp)
trap 'rm -f "$LIST" "$OUT"' EXIT

# shellcheck disable=SC2086
verilator --lint-only --timing -Wno-fatal --top-module core_top \
  +define+$DEFINES \
  -Isim -I$S -I$S/chipset/HDL -I$S/v30 \
  -I$S/chipset/HDL/i8288/HDL -I$S/chipset/HDL/i8253/HDL -I$S/chipset/HDL/i8259/HDL \
  -I$S/chipset/HDL/upd71071/HDL -I$S/chipset/HDL/sdram_single/HDL \
  -I$S/chipset/HDL/ps2_keyboard/HDL -I$S/common -I$S/audio \
  -I$S/sound/jt12/hdl -I$S/sound/jt12/hdl/adpcm -I$S/sound/jt12/jt49/hdl \
  $(cat "$LIST") \
  sim/stub_altsyncram.sv sim/stub_vhdl.sv sim/stub_saa1099.sv sim/stub_pll.sv \
  sim/stub_dcfifo.sv \
  >"$OUT" 2>&1

STATUS=0

# Implicit nets: the exact thing Quartus refuses (default_nettype none).
if grep -E '%Warning-IMPLICIT' "$OUT" | grep -v 'Exiting due to' >/dev/null; then
    echo "implicit net(s) -- Quartus will refuse these:"
    grep -E '%Warning-IMPLICIT' "$OUT" | head -20
    STATUS=1
fi

# Real errors, minus the ones the megafunction stubs cannot model (they are
# parameter checks inside the stub, not in the core).
if grep -E '%Error' "$OUT" \
   | grep -vE 'mf_datatable|altera_pll|audio_pll\.v|pll\.v|pll_video|stub_pll|Exiting due to' >/dev/null; then
    echo "lint errors:"
    grep -E '%Error' "$OUT" \
      | grep -vE 'mf_datatable|altera_pll|audio_pll\.v|pll\.v|pll_video|stub_pll|Exiting due to' | head -20
    STATUS=1
fi

if [ "$STATUS" = 0 ]; then
    echo "core lint: no implicit nets, no undeclared identifiers"
fi
exit $STATUS
