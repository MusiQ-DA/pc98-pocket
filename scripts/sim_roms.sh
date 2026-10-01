#!/bin/bash
# sim_roms.sh -- build and run the option-ROM decode benches against the
# real CHIPSET.
#
# tb_xrom and tb_scsi_rom drive guest-memory reads straight at the Chipset's
# cpu_address/memory_read_n_ext pins and check both data lanes, so they
# elaborate the whole core. That is a heavier compile than the other sims,
# which is why they get a script of their own: the file list and the ENABLE_*
# macros come from the real project files (ap_core.qsf / config.tcl), the
# same way lint_core.sh derives them, so a new RTL file or macro is picked
# up without editing this script.
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

# The project macros minus SYNTHESIS: it picks the fpga/-relative readmemh
# paths and gates v30's simulation-only blocks, neither of which a bench
# wants.
DEFINES=$(sed -n 's/^[[:space:]]*set_global_assignment.*VERILOG_MACRO "\(.*\)"/\1/p' fpga/config.tcl \
          | grep -v '^SYNTHESIS=' | tr '\n' ' ' | sed 's/ /+/g')

for TB in tb_xrom tb_scsi_rom; do
    # shellcheck disable=SC2086
    verilator --binary --timing -Wno-fatal --top-module "$TB" \
      +define+$DEFINES \
      -Isim -I$S -I$S/chipset/HDL -I$S/v30 -I$S/zet \
      -I$S/chipset/HDL/i8288/HDL -I$S/chipset/HDL/i8253/HDL -I$S/chipset/HDL/i8259/HDL \
      -I$S/chipset/HDL/upd71071/HDL \
      -I$S/common -I$S/audio \
      -I$S/sound/jt12/hdl -I$S/sound/jt12/hdl/adpcm -I$S/sound/jt12/jt49/hdl \
      "sim/$TB.sv" $(cat "$LIST") \
      sim/stub_altsyncram.sv sim/stub_vhdl.sv sim/stub_pll.sv \
      sim/stub_dcfifo.sv sim/stub_sld_virtual_jtag.sv \
      -o "$TB" --Mdir "obj_$TB"
    "./obj_$TB/$TB" | tee "$TB.log"
    grep -q 'PASS' "$TB.log"
done
