# pc98-pocket

A PC-9801 core for the Analogue Pocket (openFPGA, Cyclone V), grown out of
the MiSTer PCXT base. It runs NEC's own ITF BIOS plus the bundled ROM set,
boots real PC-98 floppy and hard-disk images, and keeps the host plumbing
(disk images, settings, controller bindings) on the Pocket's dataslots and
OSD.

## The machine it is

A V30-class PC-9801: the VX/UV-era machine, not a 9821. Concretely:

- **CPU**: NEC V30 (μPD70116), real-mode, 20-bit bus. Implemented by the
  v30 soft core with an SDRAM-backed memory bridge.
- **Memory**: 640 KB conventional (00000h-9FFFFh backed by SDRAM), text
  VRAM A0000h-A3FFFh, the CG window A4000h-A4FFFh, graphics VRAM
  (analog GVRAM for 16-colour modes) and the BIOS shadow in the SDRAM map.
- **Extended memory**: an EMS board in the PC-98 style -- page registers
  at 08E1h/08E3h/08E5h/08E7h bank four 16 KB windows at C0000h-CFFFFh into
  an SDRAM pool (0x800000-0xFFFFFF), with the fitted size reported through
  08E9h. Capacity is a Settings option: None / 2 / 4 / 8 MB (default 8 MB).
  On a V30 banked EMS is the only kind of extended memory that exists, so
  this is what PC-98 software that wants "extended memory" actually uses.
- **Video**: the μPD7220 GDC pair -- master for text, slave for graphics --
  with GRCG, the EGC raster-op pipeline and 8-/16-colour modes. Output is
  a fixed 640x400 panel: 200-line graphics modes are line-doubled to fill
  it.
- **Sound**: OPNA (YM2608, the PC-9801-86 board): FM + SSG + ADPCM.
- **Floppy**: two drives, images mounted from Pocket dataslots, with a
  built-in 3-mode option ROM so 1.44 MB media boot like the real BIOS
  expects.
- **Hard disk**: a PC-9801-55-class SCSI board at 0CC0h-0CC7h backed by
  hdi/nhd images. (The disk-BIOS INT 1Bh ROM that makes it bootable is in
  progress; images already work with software that drives 0CC0h.)
- **Input**: PC-98 keyboard interface (8251 at 41h/43h) driven from the
  Pocket's buttons -- remappable in Settings -- plus an on-screen
  keyboard, and the PC-98 bus mouse.
- **RTC / misc**: μPD4990 real-time clock, system control ports, beeper.

## Required ROMs

The core needs NEC's own firmware -- three files from a **PC-9801UX**
dump, placed at `Assets/pc98/hiroya.PC9801/` on the SD card (the
dataslots pin these filenames):

| File | Size | md5 | Role |
|---|---|---|---|
| `bios.rom` | 98,304 B | `3af0ae018c5710eec6e2891064814138` | system BIOS at E8000h |
| `itf.rom` | 32,768 B | `1d295699ffeab0f0e24e09381299259d` | power-on self-test firmware at F8000h |
| `font.rom` | 288,768 B | `4133b0be0d470920da60b9ed28d2614f` | ANK + kanji glyphs |

The generation matters. The machine is VX/UV-era: a V30, which cannot
run 9821-era firmware (its ITF uses post-8086 instructions), and a BIOS
with the common `INT 19h` reset-vector patch (CD 19h at FFFF0h, where a
genuine dump has EA 00 00 80 FDh) is refused by `scripts/deploy.sh`,
which also pins the three md5s. A coherent UX set is the only one known
to POST correctly here; `docs/PC98_MACHINE_SPEC.md` F1-F5 has the byte
level analysis (including why the ITF cannot be sliced out of bios.rom:
it is a separate chip banked over the same F8000h window, so bios.rom's
tail is BIOS code, not an ITF). The ROMs are copyrighted NEC data --
dump them from your own machine or source them yourself; they are not
distributed with the core.

Other generations' sets are not refused by the hardware -- the slots
load whatever is placed -- but none are verified: older VX-family dumps
are the nearest candidates, and `PC98_ANY_ROMS=1 scripts/deploy.sh`
skips the md5 pin for an experiment (the reset-vector check still
applies). Expect a generation mismatch to need per-set fixes, not just
a file swap.

`firmware.bin` in the same directory is the softcore's firmware overlay
and comes from the build (`scripts/push_firmware.sh` or a deploy), not
from a NEC dump.

## Using it

- Disk images go in the Pocket's data slots (fdd A/B, SCSI HDD); the
  firmware shuttles sectors between the slots and the chipset.
- The Settings overlay (per-gamepad button) configures CPU speed, BIOS
  write protection, sound/stereo, display colour set, the 200-line
  presentation (Double or hardware-style line Skip), FDD Turbo
  (authentic seek/sector pacing or ~8x), the drive-mechanism sound
  (Off, 5.25" or 3.5"), EMS capacity, the disk-access lamp and the
  controller bindings, and persists them per mounted image.
- Default pad mapping: A = Return, B = NFER, X = Space, Y = Ctrl,
  D-pad = cursor arrows, Select = Settings (Start and R1 are unbound; all
  of it is remappable in Settings). The binding names are the keys the
  PC-98 guest receives -- docked Alt arrives as NFER/XFER and right-Ctrl
  as GRPH, the way the real keyboard labels them.
- Disk activity shows as an amber lamp in the top-right of the screen
  (the Pocket's physical LED is not reachable from the core).

## Building

The bitstream is built by GitHub Actions in a Dockerised Quartus Lite
image (`raetro/quartus:pocket`); local full-project Quartus builds are not
the supported path -- see `AGENTS.md` for the workflow, the firmware build
requirements (`firmware.vh` is committed and regenerated by
`firmware/Makefile`), and the simulation benches that gate each push.
`scripts/deploy_jtag.sh` flashes a CI bitstream over JTAG.

## License

GPL-3.0 (`LICENSE`), incorporating work under GPL-2.0, MIT, BSD-2, ISC and
Analogue's APF licence -- `NOTICE.md` has the per-component breakdown. The
NEC BIOS, IPLware and font ROMs are copyrighted NEC data and are not
distributed; the core reads them from the user-placed data slots.
