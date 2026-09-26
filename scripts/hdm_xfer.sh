#!/bin/bash
# hdm_xfer.sh -- after the core deploy finishes, wait for the card and copy
# a floppy image to the Floppy pick location, verify, eject.
#
#   hdm_xfer.sh [image] [cardname]
#     image     source .hdm path   (default ~/Desktop/pc98_test.hdm)
#     cardname  filename under Assets/pc98/common (default = basename(image))
#
# A distinct cardname (e.g. draw_test.hdm) sits alongside pc98_test.hdm in the
# Pocket's disk picker rather than replacing it.
set -u
HDM="${1:-/Users/hiroya/Desktop/pc98_test.hdm}"
CARD="/Volumes/ANALOGUE"
DEST_DIR="$CARD/Assets/pc98/common"
DEST="${2:-$(basename "$HDM")}"

say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }

[ -f "$HDM" ] || { say "no $HDM"; exit 1; }

# 1. Wait for any running deploy to finish (it owns the card when mounted).
for i in $(seq 1 720); do   # up to 3 hours
    pgrep -f deploy.sh >/dev/null || break
    sleep 15
done
pgrep -f deploy.sh >/dev/null && { say "deploy still running, giving up"; exit 1; }
say "deploy done; waiting for the card"

# 2. Wait for the mount (up to 90 min), the same patience deploy.sh has.
mounted=0
for i in $(seq 1 360); do
    [ -d "$CARD" ] && { mounted=1; break; }
    sleep 15
done
[ "$mounted" = 1 ] || { say "card never came"; exit 1; }
say "card is here"

# 3. Copy, verify, eject -- Finder's eject, the one that works here.
mkdir -p "$DEST_DIR" || { say "mkdir failed"; exit 1; }
cp "$HDM" "$DEST_DIR/$DEST" || { say "copy failed"; exit 1; }
sync
want=$(md5 -q "$HDM")
got=$(md5 -q "$DEST_DIR/$DEST")
if [ "$want" = "$got" ]; then
    say "copied $DEST to Assets/pc98/common ($got)"
else
    say "MD5 MISMATCH want $want got $got"; exit 1
fi
osascript -e 'tell application "Finder" to eject disk "ANALOGUE"' >/dev/null 2>&1 \
    && say "ejected" || say "eject failed (drag it out manually)"
