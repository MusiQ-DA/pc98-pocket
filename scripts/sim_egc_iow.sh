#!/bin/bash
# sim_egc_iow.sh -- the guest's write strobe on the EGC register file,
# delivered end to end through the real BUS_ARBITER and PERIPHERALS.
#
# Guards the release-edge decode bug: egc_cs qualified on iorq made egc_wr
# unreachable (iorq falls when io_write_n rises), so every guest write to
# 0x4A0-0x4AF evaporated on hardware while the sequencer-level benches --
# which drive egc_wr directly -- passed. sim/tb_pc98_egc_iow.sv checks the
# 0x6A arm, byte and word-shaped register writes, and the negative cases.
#
# The bench instantiates PERIPHERALS, so it needs the same file list and
# feature macros as lint_core.sh -- pulled from ap_core.qsf/config.tcl the
# same way, rather than from a hand-kept copy.
set -euo pipefail
cd "$(dirname "$0")/.."

S=fpga/core
LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT

python3 - "$LIST" <<'PY'
import re, sys
qsf = open('fpga/ap_core.qsf').read()
files = re.findall(r'set_global_assignment -name (?:VERILOG_FILE|SYSTEMVERILOG_FILE) "?([^"\n]+?)"?$', qsf, re.M)
files = ['fpga/' + f for f in files if f.endswith(('.v', '.sv')) and '/apf/' not in f]
files.append('fpga/apf/common.v')
open(sys.argv[1], 'w').write('\n'.join(files))
PY

DEFINES=$(sed -n 's/^[[:space:]]*set_global_assignment.*VERILOG_MACRO "\(.*\)"/\1/p' fpga/config.tcl \
          | tr '\n' ' ' | sed 's/ /+/g')

# shellcheck disable=SC2086
verilator --binary --timing -Wno-fatal --top-module tb_pc98_egc_iow \
  +define+$DEFINES \
  -Isim -I$S -I$S/chipset/HDL -I$S/zet \
  -I$S/chipset/HDL/i8288/HDL -I$S/chipset/HDL/i8253/HDL -I$S/chipset/HDL/i8259/HDL \
  -I$S/chipset/HDL/upd71071/HDL \
  -I$S/chipset/HDL/ps2_keyboard/HDL -I$S/common -I$S/audio \
  -I$S/sound/jt12/hdl -I$S/sound/jt12/hdl/adpcm -I$S/sound/jt12/jt49/hdl \
  sim/tb_pc98_egc_iow.sv $(cat "$LIST") \
  sim/stub_altsyncram.sv sim/stub_vhdl.sv sim/stub_pll.sv \
  sim/stub_dcfifo.sv sim/stub_sld_virtual_jtag.sv \
  -o egc_iow --Mdir obj_egc_iow

./obj_egc_iow/egc_iow
