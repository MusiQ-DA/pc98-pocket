#!/bin/bash
# package.sh <artifact_dir>
#
# Packages a MACHINE_PC98 bitstream as its own core, hiroya.PC9801, with the two
# ROM slots the PC-98 machine layer needs:
#
#   id 1  bios.rom  96 KB  bridge 0x10000000  -> guest E8000-FFFFF
#   id 2  itf.rom   32 KB  bridge 0x10020000  -> guest F8000-FFFFF (shadow bank)
#   id 3  font.rom 282 KB  bridge 0x10100000  -> the 8x16 ANK set at file offset
#                                                0x0800-0x17FF goes to BRAM;
#                                                the kanji is not read yet
#   id 4  firmware.bin 24 KB bridge 0x10040000 -> overwrites the softcore's ROM.
#                                                OPTIONAL: without it the core
#                                                runs the image built into the
#                                                bitstream.
#
# The bridge addresses are what core_top decodes on -- the slot id is not used
# for the decision -- so they must match PC98_BIOS_BASE / PC98_ITF_BASE there.
#
# The directory is hiroya.PC9801, not hiroya.PC98. The Pocket registers a core
# against the platform its core.json declared the FIRST time it saw it, and a
# wrong declaration sticks -- it leaves the empty asset dir behind and
# correcting core.json afterwards does not move the association. A new
# directory name is a new core to the Pocket, which is the only reliable way
# back from that.
#
# The ROMs are the user's own dumps and are NOT in this repository. The
# deploy set is the coherent PC-9801UX trio (deploy.sh pins it by md5);
# the copy circulating as np21w's BIOS.ROM has its reset vector overwritten,
# its ITF.ROM is not an ITF at all, and the P1-P4 set was mixed-generation.
set -euo pipefail
cd "$(dirname "$0")/.."

ART="$1"
DIR="dist/pc98"
[ -f "$ART/ap_core.rbf" ] || { echo "no rbf in $ART"; exit 1; }

rm -rf "$DIR"
mkdir -p "$DIR/Cores/hiroya.PC9801" "$DIR/Assets/pc98/hiroya.PC9801" "$DIR/Platforms"

# The core's definition files come from the REPOSITORY ROOT, not from a stale
# build directory. They used to be copied from dist/testB24's upstream core,
# which is how the packaged input.json kept the PC/AT era's button names long after
# the machine layer was PC-98 only. The Python below patches core/data/video/
# interact/input on top of these; audio and variants are shipped as they are.
for j in core.json data.json video.json audio.json input.json interact.json variants.json; do
    cp "$j" "$DIR/Cores/hiroya.PC9801/$j"
done
python3 - "$DIR/Platforms/pc98.json" <<'PY'
import json, sys
out = {"platform": {"category": "Computer", "name": "NEC PC-9801",
                    "year": 1982, "manufacturer": "NEC"}}
open(sys.argv[1], 'wb').write(
    (json.dumps(out, indent=2) + "\n").encode().replace(b"\n", b"\r\n"))
PY

python3 - "$DIR/Cores/hiroya.PC9801" <<'PY'
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
    # MUST match the part of the directory name after the dot. Every core on
    # the card follows that (author.NAME/NAME) -- and renaming the directory
    # while leaving this at PC98 got "Load in core general error" until it was
    # fixed.
    m['shortname'] = 'PC9801'
    m['description'] = 'PC-98 machine layer (P1: ITF + BIOS fetch)'
    # The Pocket looks for a core's assets under Assets/<platform_id>/<core>/,
    # so this has to match the directory the ROMs go in. Pointing it at any
    # platform but 'pc98' while writing to Assets/pc98/ puts the ROMs somewhere
    # nothing reads, and the core comes up with no BIOS and no complaint.
    m['platform_ids'] = ['pc98']
    for c in j['core']['cores']:
        c['filename'] = 'bitstream.rbf_r'

def data(j):
    # THE ROOT data.json IS THE SLOT TABLE. This function no longer writes
    # one -- it verifies the one that was copied in. It used to REPLACE
    # data_slots with a second hardcoded table (leftover from when the root
    # file was the inherited PC/AT one), and the copy drifted: root had been
    # bumped to 48 KB for the firmware slot and 16 KB for the rhythm store
    # while the packaged table still said 0x8000/0x2000, so every packaged
    # install refused its own firmware.bin -- the "error in framework file
    # id [12] too large" the old comment warned about. One table plus
    # assertions kills the drift path; what each check encodes was a real
    # failure once:
    #
    #  * The disk ids are the firmware's slot map (softcpu_regs.h) and
    #    core_top's dataslot_update decode: 3/4 are the floppy drives, 5 is
    #    the SCSI image. The bridge addresses, not the ids, route the ROM
    #    streams -- a dataslot_update for id 3 is read as "floppy A's size",
    #    which is why the ROMs moved to 1/2/11/12.
    #  * Parameters bit 0 is "user-reloadable in the Core UI". It once sat
    #    on the BIOS/ITF/Font/Firmware/Settings slots and the settings list
    #    offered to swap the BIOS by hand; it belongs only on the browsed
    #    disk slots (0x201 = bit0 + bit9 persist-browsed-filename -- without
    #    bit9 a picked image unbinds on the pick-triggered core reload).
    #  * A picker slot carries at most FOUR extensions: a longer list made
    #    the Pocket browse the first four only, and .hdm was never
    #    selectable while it sat seventh.
    #  * deferload slots are BOUND, not streamed: filename + size land in
    #    the datatable and the firmware pulls bytes with tds_transfer
    #    (rhythm.bin, the 2608_*.wav voices, fddsnd.bin). An `address` on a
    #    deferload slot is dead weight -- it streamed to 0x10200000 once,
    #    an address nothing in core_top decodes -- and a non-deferload slot
    #    without one has nowhere to go.
    #  * Bit 1 of parameters resolves a pinned filename in the core's own
    #    Assets/<platform>/<core>/ dir; clear means Assets/<platform>/common/.
    #  * A slot's size_maximum must cover the file actually shipped -- the
    #    framework refuses the file outright when it does not.
    slots = j['data']['data_slots']
    by_id = {s['id']: s for s in slots}
    want = {1, 2, 3, 4, 5, 7, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20}
    missing = sorted(want - by_id.keys())
    assert not missing, f"data_slots is missing ids {missing}"

    def pnum(s):
        p = s.get('parameters', 0)
        return int(p, 0) if isinstance(p, str) else p

    def smax(s):
        m = s.get('size_maximum')
        return None if m is None else (
            int(m, 0) if isinstance(m, str) else m)

    for s in slots:
        sid = s['id']
        assert len(s.get('extensions', ())) <= 4, \
            f"slot {sid}: {len(s.get('extensions', ()))} extensions -- " \
            "the picker browses four at most"
        if pnum(s) & 1:
            assert s.get('deferload'), \
                f"slot {sid}: bit0 user picker on a boot-stream slot"
        assert ('address' in s) != bool(s.get('deferload')), \
            f"slot {sid}: deferload slots bind, streamed slots need an " \
            "address -- exactly one of the two"

    # Files this repo ships must fit their declared cap, checked against the
    # real file rather than a remembered number. Optional assets are checked
    # only when present.
    shipped = {
        'firmware.bin': 'firmware/firmware.bin',
        'fddsnd.bin':   'assets/fddsnd.bin',
        'rhythm.bin':   'assets/rhythm.bin',
    }
    for v in ('bd', 'sd', 'top', 'hh', 'tom', 'rim'):
        shipped[f'2608_{v}.wav'] = f'assets/wavs/2608_{v}.wav'
    for s in slots:
        fn, mx = s.get('filename'), smax(s)
        p = shipped.get(fn or '')
        if p and os.path.exists(p) and mx is not None:
            sz = os.path.getsize(p)
            assert sz <= mx, \
                f"{p} is {sz} bytes but slot {s['id']} caps at {mx} -- " \
                "the framework will refuse it at load"
    # And the firmware cap itself must fit the softcore ROM window -- the
    # RTL's fw_dl_hit drops writes at >= 0xC000, so a larger declared cap
    # would accept a file that then silently truncates.
    assert smax(by_id[12]) <= 0xC000, \
        "Firmware slot's size_maximum exceeds the 48 KB ROM window"

def video(j):
    # The PC-98 raster is 640x400 (pc98_video_timing.sv, from np21w's clock
    # table). The inherited file declares the PC/AT pair -- CGA 640x200 and the
    # Hercules 720x350 canvas -- so the scaler was told to expect two hundred
    # lines and handed four hundred. There is one mode here because the machine
    # has one.
    # Aspect is 8:5, not 4:3: the PC-98 pixel is square. NEC's own Graphic BIOS
    # draws circles on that assumption, the 98NOTE LCDs are 640x400 native, and
    # the 24kHz CRTs letterboxed the raster to 16:10 -- the 4:3 fill people
    # remember was monitors stretching to fill, not the design.
    j['video']['scaler_modes'] = [
        {"width": 640, "height": 400, "aspect_w": 8, "aspect_h": 5,
         "rotation": 0, "mirror": 0},
    ]

def interact(j):
    # What the Pocket's Core Settings menu shows for this core. Both addresses
    # are decoded in core_top's bridge block: 0x50 resets the guest, 0x6C is
    # the floppy write-protect pair wired to floppy.v.
    #
    # THERE IS NO "Settings (OSD)" ACTION ON PURPOSE. One existed (0x54, still
    # decoded in the RTL) until it turned out to be a trap: selecting it opens
    # the core's OSD, but the Pocket's own menu -- which is the framework's UI,
    # and no bridge command can close it -- sits on top, so the choice was
    # "press B once" versus "press SELECT and never open this menu at all".
    # SELECT is the one path now; the OSD opens white-on-black over the machine
    # with no framework menu involved.
    j['interact']['variables'] = [
        {"name": "Write Protect", "id": 3, "type": "list",
         "enabled": True, "persist": True, "writeonly": True,
         "address": "0x6C", "defaultval": 0,
         "options": [
             {"value": 0, "name": "None"},
             {"value": 1, "name": "Floppy A"},
             {"value": 2, "name": "Floppy B"},
             {"value": 3, "name": "A & B"},
         ]},
        {"name": "Reset PC", "id": 1, "type": "action",
         "enabled": True, "writeonly": True,
         "address": "0x50", "value": 1},
    ]

def input_map(j):
    # The framework's Controls menu: which PHYSICAL button feeds each of the
    # core's logical pad inputs. The pad-to-PC-98-key half is the OSD's
    # Controls menu (key_bind.c); the names here are that menu's DEFAULTS, so
    # a user sees what each button does out of the box. X, Y and R were absent
    # from the inherited list, so those three could not be remapped at all.
    j['input']['controllers'] = [
        {"type": "default", "mappings": [
            # The names mirror the firmware's binding roller (keybind_cycle in
            # settings_ui.c): PC-98 destination names, not host-key names --
            # docked L-Alt arrives as NFER, so B says NFER, not Alt.
            {"id": 0, "name": "A: Return", "key": "pad_btn_a"},
            {"id": 1, "name": "B: NFER",   "key": "pad_btn_b"},
            {"id": 2, "name": "X: Space",  "key": "pad_btn_x"},
            {"id": 3, "name": "Y: Ctrl",   "key": "pad_btn_y"},
            {"id": 4, "name": "L: Virtual Keyboard", "key": "pad_trig_l"},
            {"id": 5, "name": "R: unmapped",         "key": "pad_trig_r"},
            {"id": 6, "name": "Start: unmapped",     "key": "pad_btn_start"},
            {"id": 7, "name": "Select: Settings",    "key": "pad_btn_select"},
        ]},
    ]

rw('core.json', core)
rw('data.json', data)
rw('video.json', video)
rw('interact.json', interact)
rw('input.json', input_map)
PY

python3 - "$ART/ap_core.rbf" "$DIR/Cores/hiroya.PC9801/bitstream.rbf_r" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = bytes(int(format(b, '08b')[::-1], 2) for b in range(256))
d = open(src, 'rb').read()
open(dst, 'wb').write(d.translate(t))
print("  %s: bit-reversed %d bytes" % (dst, len(d)))
PY

echo "packaged hiroya.PC9801"
echo "  put bios.rom, itf.rom and font.rom in $DIR/Assets/pc98/hiroya.PC9801/"
