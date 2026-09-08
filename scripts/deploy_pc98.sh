#!/bin/bash
# deploy_pc98.sh [--run N]
#
# Like deploy.sh, but for the PC-98 core: it has to create the whole core
# directory (hiroya.PC98) rather than drop a bitstream into an existing one,
# and it has to place two ROMs the core cannot boot without.
#
# The ROMs are the user's own dumps and are not in this repository. Point
# PC98_ROMS at a directory holding bios.rom and itf.rom -- use the UNPATCHED
# pair (docs/PC98_MACHINE_SPEC.md F3-F5); the copy circulating as np2's
# BIOS.ROM has its reset vector overwritten and its ITF.ROM is not an ITF.
set -uo pipefail
cd "$(dirname "$0")/.."

RUN=""
VOL="/Volumes/ANALOGUE"
ROMS="${PC98_ROMS:-}"
POLL=45; SD_POLL=15; MAX_WAIT=5400

while [ $# -gt 0 ]; do
    case "$1" in
        --run)  RUN="$2"; shift 2 ;;
        --roms) ROMS="$2"; shift 2 ;;
        --vol)  VOL="$2";  shift 2 ;;
        *) echo "unknown option: $1"; exit 2 ;;
    esac
done

say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

[ -n "$ROMS" ] || { say "set PC98_ROMS (or --roms) to a dir with bios.rom and itf.rom"; exit 2; }
for f in bios.rom itf.rom font.rom; do
    [ -f "$ROMS/$f" ] || { say "missing $ROMS/$f"; exit 2; }
done

# Refuse the patched dumps outright rather than spending a hardware run on them.
# A real system BIOS has EA 00 00 80 FD at FFFF0 and a real ITF has
# EA 00 00 00 F8; the circulating patch puts CD 19 over the first two bytes.
check_vec() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys
p, off, want = sys.argv[1], int(sys.argv[2], 16), bytes.fromhex(sys.argv[3])
d = open(p, 'rb').read()
got = d[off:off+len(want)]
print("ok" if got == want else got.hex(' '))
PY
}
v=$(check_vec "$ROMS/bios.rom" 0x17FF0 "ea000080fd")
[ "$v" = "ok" ] || { say "bios.rom reset vector is '$v', want ea 00 00 80 fd -- this is a patched dump"; exit 1; }
v=$(check_vec "$ROMS/itf.rom" 0x7FF0 "ea000000f8")
[ "$v" = "ok" ] || { say "itf.rom reset vector is '$v', want ea 00 00 00 f8 -- this is not an ITF"; exit 1; }
say "ROMs look genuine"

# ---- 1. wait for the run ---------------------------------------------------
if [ -z "$RUN" ]; then
    HEAD_SHA=$(python3 -c "
import sys; sys.path.insert(0,'scripts/tools'); import ghlib
print(ghlib.gh('/repos/MusiQ-DA/pc98-pocket/commits/main')['sha'])")
    say "remote main is at ${HEAD_SHA:0:10}"
    waited=0
    while :; do
        RUN=$(python3 -c "
import sys; sys.path.insert(0,'scripts/tools'); import ghlib
for r in ghlib.gh('/repos/MusiQ-DA/pc98-pocket/actions/runs?per_page=20')['workflow_runs']:
    if r['head_sha'] == '$HEAD_SHA':
        print(r['run_number']); break
else: print('none')")
        [ "$RUN" != "none" ] && break
        [ $waited -ge 600 ] && { say "no run appeared"; exit 1; }
        sleep 20; waited=$((waited + 20))
    done
    say "watching run#$RUN"
fi

waited=0
while :; do
    read -r st cc <<<"$(python3 -c "
import sys; sys.path.insert(0,'scripts/tools'); import ghlib
for r in ghlib.gh('/repos/MusiQ-DA/pc98-pocket/actions/runs?per_page=20')['workflow_runs']:
    if r['run_number'] == $RUN:
        print(r['status'], r['conclusion'] or ''); break
else: print('missing', '')")"
    [ "$st" = "completed" ] && { say "run#$RUN completed/$cc"; break; }
    [ $waited -ge $MAX_WAIT ] && { say "gave up on run#$RUN"; exit 1; }
    sleep $POLL; waited=$((waited + POLL))
done

# The firmware job can be red while the bitstream is fine; only quartus matters.
qok=$(python3 -c "
import sys; sys.path.insert(0,'scripts/tools'); import ghlib
R='/repos/MusiQ-DA/pc98-pocket'
rid=[r['id'] for r in ghlib.gh(R+'/actions/runs?per_page=20')['workflow_runs'] if r['run_number']==$RUN][0]
j=[x for x in ghlib.gh(f'{R}/actions/runs/{rid}/jobs')['jobs'] if x['name']=='quartus'][0]
print('yes' if j['conclusion']=='success' else 'no')")
[ "$qok" = "yes" ] || { say "the quartus job did not succeed -- nothing worth flashing"; exit 1; }

# ---- 2. fetch and package --------------------------------------------------
ART="build/artifact_$RUN"
if [ ! -f "$ART/ap_core.rbf" ]; then
    say "fetching artifact"
    python3 scripts/tools/getartifact.py "$RUN" "$ART" --allow-failed >/dev/null || {
        say "artifact download failed"; exit 1; }
fi
say "have $(stat -f%z "$ART/ap_core.rbf") bytes of bitstream"

bash scripts/package_pc98.sh "$ART" || exit 1
cp "$ROMS/bios.rom" "$ROMS/itf.rom" "$ROMS/font.rom" dist/pc98/Assets/pc98/hiroya.PC98/
# The softcore's firmware rides along as a slot, so a change to an on-screen
# readout is a file copy rather than a Quartus compile. Built here rather than
# assumed present: firmware.bin is gitignored, being a build product.
make -C pcxt-base/src/firmware >/dev/null || { say "firmware build failed"; exit 1; }
cp pcxt-base/src/firmware/firmware.bin dist/pc98/Assets/pc98/hiroya.PC98/
say "packaged with ROMs"

# ---- 3. write --------------------------------------------------------------
say "waiting for $VOL -- put the Pocket into USB access mode"
waited=0
while [ ! -d "$VOL" ]; do
    [ $waited -ge $MAX_WAIT ] && { say "card never appeared"; exit 1; }
    sleep $SD_POLL; waited=$((waited + SD_POLL))
done
say "card is here"

mkdir -p "$VOL/Cores/hiroya.PC98" "$VOL/Assets/pc98/hiroya.PC98" "$VOL/Platforms"
cp dist/pc98/Cores/hiroya.PC98/* "$VOL/Cores/hiroya.PC98/"
cp dist/pc98/Assets/pc98/hiroya.PC98/* "$VOL/Assets/pc98/hiroya.PC98/"
cp dist/pc98/Platforms/* "$VOL/Platforms/" 2>/dev/null || true
sync

# Verify everything that was written, not just the bitstream. The first run of
# this script reported "written and verified" while the ROMs sat in a directory
# nothing reads: core.json still said platform_ids ["pcxt"] and the Pocket looks
# for assets under Assets/<platform_id>/<core>/. A core with no BIOS comes up
# with no complaint, so the check has to cover the assets and the path.
PLAT=$(python3 -c "
import json
d=json.load(open('dist/pc98/Cores/hiroya.PC98/core.json'.strip()))
print(d['core']['metadata']['platform_ids'][0])")
if [ "$PLAT" != "pc98" ]; then
    say "core.json says platform '$PLAT' but the assets went to pc98 -- stopping"
    exit 1
fi

fail=0
for f in Cores/hiroya.PC98/bitstream.rbf_r Cores/hiroya.PC98/core.json \
         Cores/hiroya.PC98/data.json Assets/pc98/hiroya.PC98/bios.rom \
         Assets/pc98/hiroya.PC98/itf.rom Assets/pc98/hiroya.PC98/font.rom \
         Assets/pc98/hiroya.PC98/firmware.bin Platforms/pc98.json; do
    if cmp -s "dist/pc98/$f" "$VOL/$f"; then
        say "  ok  $f"
    else
        say "  BAD $f"; fail=1
    fi
done
[ $fail -eq 0 ] || { say "VERIFY FAILED"; exit 1; }
say "written and verified to hiroya.PC98"

diskutil eject "$VOL" >/dev/null 2>&1 && say "ejected -- ready to test" \
                                      || say "written; eject by hand"
