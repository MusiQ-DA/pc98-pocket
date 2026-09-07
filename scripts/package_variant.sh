#!/bin/bash
# package_variant.sh <artifact_dir> <letter> <description>
#
# Packages one bitstream as its OWN core, so several variants can sit on the
# card at once and be picked from the Pocket's menu instead of swapped by hand.
# The core's identity is the directory name plus core.json's shortname; assets
# live under a matching directory, so both are rewritten per variant.
set -euo pipefail
cd "$(dirname "$0")/.."

ART="$1"; L="$2"; DESC="$3"
SHORT="PCXT$L"
DIR="dist/variant_$L"
SRC="dist/testB24"          # a known-good tree to copy the JSON/boot.bin from

[ -f "$ART/ap_core.rbf" ] || { echo "no rbf in $ART"; exit 1; }

rm -rf "$DIR"
mkdir -p "$DIR/Cores/hiroya.$SHORT" "$DIR/Assets/pcxt/hiroya.$SHORT" "$DIR/Platforms"
cp "$SRC"/Cores/hiroya.PCXTDEV/*.json "$DIR/Cores/hiroya.$SHORT/"
cp "$SRC"/Assets/pcxt/hiroya.PCXTDEV/boot.bin "$DIR/Assets/pcxt/hiroya.$SHORT/"
cp "$SRC"/Platforms/pcxt.json "$DIR/Platforms/" 2>/dev/null || true

python3 - "$DIR/Cores/hiroya.$SHORT/core.json" "$SHORT" "$DESC" <<'PY'
import json, sys
p, short, desc = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(p, 'rb').read().replace(b'\r\n', b'\n')
d = json.loads(raw)
d['core']['metadata']['shortname'] = short
d['core']['metadata']['description'] = desc
out = json.dumps(d, indent=2).encode() + b'\n'
open(p, 'wb').write(out.replace(b'\n', b'\r\n'))
PY

python3 - "$ART/ap_core.rbf" "$DIR/Cores/hiroya.$SHORT/bitstream.rbf_r" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = bytes(int(format(b, '08b')[::-1], 2) for b in range(256))
d = open(src, 'rb').read()
open(dst, 'wb').write(d.translate(t))
print("  %s: bit-reversed %d bytes" % (dst, len(d)))
PY
echo "packaged variant $L ($SHORT): $DESC"
