#!/bin/bash
# sim_crt_irq.sh -- the GDC CRT interrupt's np21w vsyncint lifecycle,
# exercised through the whole PERIPHERALS block: the real 8259 pair, the
# real raster off pc98_video_timing, the real 0x64 arm decode, and the real
# vector path during INTA. sim/tb_crt_irq.sv checks arm -> vblank ->
# INT 0x0A, service-consumes, re-arm, and the masked cancel-and-retry.
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
verilator --binary --timing -Wno-fatal --top-module tb_crt_irq \
  +define+$DEFINES \
  -Isim -I$S -I$S/chipset/HDL -I$S/v30 -I$S/zet \
  -I$S/chipset/HDL/i8288/HDL -I$S/chipset/HDL/i8253/HDL -I$S/chipset/HDL/i8259/HDL \
  -I$S/chipset/HDL/upd71071/HDL \
  -I$S/chipset/HDL/ps2_keyboard/HDL -I$S/common -I$S/audio \
  -I$S/sound/jt12/hdl -I$S/sound/jt12/hdl/adpcm -I$S/sound/jt12/jt49/hdl \
  sim/tb_crt_irq.sv $(cat "$LIST") \
  sim/stub_altsyncram.sv sim/stub_vhdl.sv sim/stub_pll.sv \
  sim/stub_dcfifo.sv sim/stub_sld_virtual_jtag.sv \
  -o crt_sim --Mdir obj_crt

./obj_crt/crt_sim
