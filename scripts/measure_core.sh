#!/usr/bin/env bash
# measure_core.sh -- how many ALMs does one core cost, on its own?
#
#   scripts/measure_core.sh <top_module> <file> [file ...]
#
# Runs Analysis & Synthesis only (quartus_map) against the Pocket's device with
# the core as the top level, and prints the estimated ALM count. Standalone
# numbers are not the same as in-design numbers -- nothing is shared with the
# rest of the core and nothing is optimised away across the boundary -- so use
# it to COMPARE cores against each other, and calibrate against a core whose
# in-design figure is already known from a fit report.
#
# Needs the CI's Quartus image: docker pull raetro/quartus:pocket
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TOP="$1"; shift
DEFS="${MEASURE_DEFS:-}"
SEARCH="${MEASURE_SEARCH:-}"

# MEASURE_TAG keeps two runs of the same top from sharing a directory -- the
# second one's rm -rf took the first one's log with it.
OUT="${TMPDIR:-/tmp}/measure_$TOP${MEASURE_TAG:+_$MEASURE_TAG}"
rm -rf "$OUT"; mkdir -p "$OUT"

{
    echo "set_global_assignment -name FAMILY \"Cyclone V\""
    echo "set_global_assignment -name DEVICE 5CEBA4F23C8"
    echo "set_global_assignment -name TOP_LEVEL_ENTITY $TOP"
    for d in $DEFS;   do echo "set_global_assignment -name VERILOG_MACRO \"$d\""; done
    for p in $SEARCH; do echo "set_global_assignment -name SEARCH_PATH \"$p\""; done
    for f in "$@"; do
        case "$f" in
            *.vhd) echo "set_global_assignment -name VHDL_FILE \"$f\"" ;;
            *.sv)  echo "set_global_assignment -name SYSTEMVERILOG_FILE \"$f\"" ;;
            *)     echo "set_global_assignment -name VERILOG_FILE \"$f\"" ;;
        esac
    done
} > "$OUT/m.qsf"
echo "PROJECT_REVISION = \"m\"" > "$OUT/m.qpf"

# $readmemh paths in the RTL are relative to the PROJECT directory, so mirror
# the real project's rtl/ (the symlinked microcode tables) next to the scratch
# qsf. Without it v30u_ucrom fails elaboration rather than reporting an area.
# MEASURE_COPY: a directory whose contents belong next to the scratch qsf
# (data files a core $readmem's from its project directory).
if [ -n "${MEASURE_COPY:-}" ]; then cp -RL "$MEASURE_COPY"/. "$OUT/"; fi
if [ -d fpga/rtl ]; then
    mkdir -p "$OUT/rtl"
    cp -RL fpga/rtl/. "$OUT/rtl/"
fi

export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"

docker run --rm -v "$PWD":/work -v "$OUT":/proj -w /proj raetro/quartus:pocket bash -lc '
  for p in /opt/intelFPGA/quartus /opt/quartus /usr/local/quartus; do
      [ -x "$p/bin/quartus_map" ] && { export PATH="$p/bin:$PATH"; break; }
  done
  cd /work && quartus_map --read_settings_files=on /proj/m 2>&1 | tee /proj/map.log | tail -5
' || true

R="$OUT/output_files/m.map.rpt"
[ -f "$R" ] || R="$(find "$OUT" -name 'm.map.rpt' | head -1)"
if [ -f "$R" ]; then
    echo "--- $TOP ---"
    LC_ALL=C grep -aE "Estimated ALUTs|ALMs|Total combinational functions|Total registers|Total logic elements|Total block memory bits" "$R" | head -6
else
    echo "no map report; the errors were:"
    LC_ALL=C grep -aE "^Error" "$OUT/map.log" 2>/dev/null | head -8
    echo "(full log: $OUT/map.log)"
fi
