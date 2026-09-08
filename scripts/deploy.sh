#!/bin/bash
#
# deploy.sh -- wait for CI, fetch the bitstream, and put it on the card.
#
# The loop this automates was the whole shape of a night's work: poll the build,
# download the artifact, bit-reverse it into the Pocket's rbf_r format, wait for
# the card to appear, copy, verify, eject. Doing it by hand meant the build sat
# finished while nobody was looking, and the card sat mounted while nobody was
# copying.
#
#   scripts/deploy.sh                     latest run -> the PCXTDEV core
#   scripts/deploy.sh --core PCXTA        ... into a named core directory
#   scripts/deploy.sh --run 87            a specific run number
#   scripts/deploy.sh --no-eject          leave the card mounted
#
# Safe to background: it polls, it does not hold anything open, and every step
# is verified before the next one.
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -uo pipefail
cd "$(dirname "$0")/.."

CORE="PCXTDEV"
RUN=""
EJECT=1
VOL="/Volumes/ANALOGUE"
POLL=45          # seconds between CI checks
SD_POLL=15       # seconds between card checks
MAX_WAIT=5400    # give up after 90 minutes rather than spin forever

while [ $# -gt 0 ]; do
    case "$1" in
        --core)      CORE="$2"; shift 2 ;;
        --run)       RUN="$2";  shift 2 ;;
        --no-eject)  EJECT=0;   shift ;;
        --vol)       VOL="$2";  shift 2 ;;
        *) echo "unknown option: $1"; exit 2 ;;
    esac
done

say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---- 1. wait for the run to finish -----------------------------------------
latest_run() {
    python3 - <<'PY'
import sys
sys.path.insert(0, 'scripts/tools')
import ghlib
r = ghlib.gh('/repos/MusiQ-DA/pc98-pocket/actions/runs?per_page=1')['workflow_runs'][0]
print(r['run_number'], r['status'], r['conclusion'])
PY
}

run_state() {
    python3 - "$1" <<'PY'
import sys
sys.path.insert(0, 'scripts/tools')
import ghlib
want = int(sys.argv[1])
for r in ghlib.gh('/repos/MusiQ-DA/pc98-pocket/actions/runs?per_page=20')['workflow_runs']:
    if r['run_number'] == want:
        print(r['status'], r['conclusion'])
        break
else:
    print('missing none')
PY
}

# Did the Quartus job itself succeed? A red gate or a red sim job after a good
# compile still leaves a usable bitstream, and that distinction cost real time
# to work out by hand.
quartus_ok() {
    python3 - "$1" <<'PY'
import sys
sys.path.insert(0, 'scripts/tools')
import ghlib
want = int(sys.argv[1])
R = '/repos/MusiQ-DA/pc98-pocket'
run = next(r for r in ghlib.gh(f'{R}/actions/runs?per_page=20')['workflow_runs']
           if r['run_number'] == want)
jobs = ghlib.gh(f"{R}/actions/runs/{run['id']}/jobs")['jobs']
q = [j for j in jobs if j['name'] == 'quartus']
print('yes' if q and q[0]['conclusion'] == 'success' else 'no')
PY
}

if [ -z "$RUN" ]; then
    read -r RUN _ _ <<<"$(latest_run)"
    say "watching run#$RUN"
fi

waited=0
while :; do
    read -r status conclusion <<<"$(run_state "$RUN")"
    if [ "$status" = "completed" ]; then
        say "run#$RUN completed/$conclusion"
        break
    fi
    [ $waited -ge $MAX_WAIT ] && { say "gave up waiting for run#$RUN"; exit 1; }
    sleep $POLL; waited=$((waited + POLL))
done

if [ "$(quartus_ok "$RUN")" != "yes" ]; then
    say "the quartus job did not succeed -- nothing worth flashing"
    exit 1
fi
[ "$conclusion" != "success" ] && \
    say "note: run is red, but the compile succeeded; taking the bitstream"

# ---- 2. fetch --------------------------------------------------------------
ART="build/artifact_$RUN"
if [ ! -f "$ART/ap_core.rbf" ]; then
    say "fetching artifact"
    python3 scripts/tools/getartifact.py "$RUN" "$ART" --allow-failed >/dev/null || {
        say "artifact download failed"; exit 1; }
fi
say "have $(stat -f%z "$ART/ap_core.rbf") bytes of bitstream"

# ---- 3. convert ------------------------------------------------------------
# The Pocket wants the bits within each byte reversed. NOT xor 0xFF: that
# mistake produced a Load error and cost a hardware round trip once already.
STAGE="build/deploy_$RUN.rbf_r"
python3 - "$ART/ap_core.rbf" "$STAGE" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = bytes(int(format(b, '08b')[::-1], 2) for b in range(256))
open(dst, 'wb').write(open(src, 'rb').read().translate(t))
PY
head=$(xxd -l 134 -s 128 -p "$STAGE" | tr -d '\n' | cut -c1-12)
if [ "$head" != "565656566c2f" ]; then
    say "converted image does not start like a Pocket core ($head) -- stopping"
    exit 1
fi
say "converted, header looks right"

# ---- 4. wait for the card --------------------------------------------------
DEST="$VOL/Cores/hiroya.$CORE"
waited=0
while [ ! -d "$DEST" ]; do
    if [ $waited -eq 0 ]; then
        say "waiting for $DEST -- put the Pocket into USB access mode"
    fi
    [ $waited -ge $MAX_WAIT ] && { say "card never appeared"; exit 1; }
    sleep $SD_POLL; waited=$((waited + SD_POLL))
done
say "card is here"

# ---- 5. copy, verify, eject ------------------------------------------------
cp "$STAGE" "$DEST/bitstream.rbf_r" || { say "copy failed"; exit 1; }
sync
if ! cmp -s "$DEST/bitstream.rbf_r" "$STAGE"; then
    say "VERIFY FAILED -- the card does not match what was written"
    exit 1
fi
say "written and verified to hiroya.$CORE"

if [ $EJECT -eq 1 ]; then
    # macOS caches writes; ejecting is what guarantees the Pocket reads them.
    # It occasionally needs the device rather than the mount point.
    diskutil eject "$VOL" >/dev/null 2>&1 || \
    diskutil eject "$(diskutil info "$VOL" 2>/dev/null | awk '/Device Node/{print $NF}')" >/dev/null 2>&1 || \
        { say "eject failed -- eject it in Finder before testing"; exit 1; }
    say "ejected -- ready to test"
fi
