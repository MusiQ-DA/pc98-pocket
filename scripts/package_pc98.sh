#!/bin/bash
# package_pc98.sh <artifact_dir>
#
# Packages a MACHINE_PC98 bitstream as its own core, hiroya.PC98, with the two
# ROM slots the PC-98 machine layer needs:
#
#   id 1  bios.rom  96 KB  bridge 0x10000000  -> guest E8000-FFFFF
#   id 2  itf.rom   32 KB  bridge 0x10020000  -> guest F8000-FFFFF (shadow bank)
#
# The bridge addresses are what core_top decodes on -- the slot id is not used
# for the decision -- so they must match PC98_BIOS_BASE / PC98_ITF_BASE there.
#
# The ROMs are the user's own dumps and are NOT in this repository. Use the
# unpatched pair (docs/PC98_MACHINE_SPEC.md F3-F5); the copy circulating as
# np2's BIOS.ROM has its reset vector overwritten, and its ITF.ROM is not an
# ITF at all.
set -euo pipefail
cd "$(dirname "$0")/.."

ART="$1"
DIR="dist/pc98"
SRC="dist/testB24"

[ -f "$ART/ap_core.rbf" ] || { echo "no rbf in $ART"; exit 1; }

rm -rf "$DIR"
mkdir -p "$DIR/Cores/hiroya.PC98" "$DIR/Assets/pc98/hiroya.PC98" "$DIR/Platforms"
cp "$SRC"/Cores/hiroya.PCXTDEV/*.json "$DIR/Cores/hiroya.PC98/"
python3 - "$DIR/Platforms/pc98.json" <<'PY'
import json, sys
out = {"platform": {"category": "Computer", "name": "NEC PC-9801",
                    "year": 1982, "manufacturer": "NEC"}}
open(sys.argv[1], 'wb').write(
    (json.dumps(out, indent=2) + "\n").encode().replace(b"\n", b"\r\n"))
PY

python3 - "$DIR/Cores/hiroya.PC98" <<'PY'
import json, os, sys
d = sys.argv[1]

def rw(name, fn):
    p = os.path.join(d, name)
    raw = open(p, 'rb').read().replace(b'\r\n', b'\n')
    j = json.loads(raw)
    fn(j)
    out = json.dumps(j, indent=2).encode() + b'\n'
    open(p, 'wb').write(out.replace(b'\n', b'\r\n'))

def core(j):
    m = j['core']['metadata']
    m['shortname'] = 'PC98'
    m['description'] = 'PC-98 machine layer (P1: ITF + BIOS fetch)'
    # The Pocket looks for a core's assets under Assets/<platform_id>/<core>/,
    # so this has to match the directory the ROMs go in. Leaving it at 'pcxt'
    # while writing to Assets/pc98/ puts the ROMs somewhere nothing reads, and
    # the core comes up with no BIOS and no complaint.
    m['platform_ids'] = ['pc98']
    for c in j['core']['cores']:
        c['filename'] = 'bitstream.rbf_r'

def data(j):
    j['data']['data_slots'] = [
        {"name": "PC-98 BIOS",  "id": 1, "required": True,  "parameters": "0x203",
         "filename": "bios.rom", "extensions": ["rom", "bin"],
         "address": "0x10000000", "size_maximum": "0x18000"},
        {"name": "PC-98 ITF",   "id": 2, "required": True,  "parameters": "0x203",
         "filename": "itf.rom",  "extensions": ["rom", "bin"],
         "address": "0x10020000", "size_maximum": "0x8000"},
        {"name": "Settings",    "id": 7, "required": False, "parameters": "0x03",
         "filename": "settings.dat", "extensions": ["dat"],
         "address": "0x10030000", "size_maximum": "0x1000"},
    ]

rw('core.json', core)
rw('data.json', data)
PY

python3 - "$ART/ap_core.rbf" "$DIR/Cores/hiroya.PC98/bitstream.rbf_r" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = bytes(int(format(b, '08b')[::-1], 2) for b in range(256))
d = open(src, 'rb').read()
open(dst, 'wb').write(d.translate(t))
print("  %s: bit-reversed %d bytes" % (dst, len(d)))
PY

echo "packaged hiroya.PC98"
echo "  put bios.rom (96KB) and itf.rom (32KB) in $DIR/Assets/pc98/hiroya.PC98/"
