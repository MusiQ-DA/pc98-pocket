# Notices and Credits

This project is a PC-98 (PC-9801VX-class) machine core for the Analogue
Pocket's openFPGA, distributed under the GNU General Public License v3.0
(see `LICENSE`).

It is derived from and incorporates work by the following projects and
authors. Each component retains its own license as noted; the license text
for a vendored component ships beside it or in its file headers.

## Upstream port base

**desaster/openfpga-PCXT** — <https://github.com/desaster/openfpga-PCXT>
GPL-3.0 (`LICENSE.upstream`). The openFPGA framework integration, the
PicoRV32 disk-service softcore, the OSD/virtual-keyboard machinery and the
pocket_keyboard path descend from this port, which itself ported the MiSTer
PCXT core (spark2k06, MicroCoreLabs, kitune-san and others) to the Pocket.

## Vendored cores

**nuV30** — <https://github.com/wickerwaka/nuV30>, GPL-2.0
(`fpga/core/v30/LICENSE.nuV30`). Cycle-accurate NEC V30 CPU recreation,
verified against real die hardware; the `ucrom.hex`/`ucdecode.hex` tables
carry the V30's extracted microcode (VCFed extraction lineage; see
`fpga/core/v30/README.md` for provenance). NOTE: nuV30 declares GPL-2.0
without an explicit "or later" grant in its file headers. This project
ships the combined work as GPL-3.0 following the common MiSTer/openFPGA
community practice; anyone with a stricter reading of GPL-2.0-only should
be aware of this when redistributing.

**JT12/JT49** — <https://github.com/jotego/jt12>, GPL-3.0
(`fpga/core/sound/jt12/LICENSE`). The YM2608 (OPNA) implementation.

**kitune-san's chipset cores** — MIT
(`fpga/core/chipset/**/LICENSE` files): 8253 PIT, 8259 PIC, 8288 bus
controller, uPD71071 DMAC, KFPS2KB PS/2 keyboard.

**floppy.v** (`fpga/core/common/floppy.v`) — BSD-2
(c) Aleksander Osman 2014, (c) Alexey Melnikov 2020; the uPD765-class FDC,
from the MiSTer PCXT core.

**PicoRV32** (`fpga/core/picorv32.v`) — ISC, (c) Claire Xenia Wolf / YosysHQ.

**sync_fifo.v, data_loader.v, sound_i2s.v** — MIT, (c) Adam Gastineau
(openFPGA template lineage).

**audio filters** (`fpga/core/audio/filters/`) — GPL-3.0-or-later and MIT,
(c) OpenGateware / Marcus Andrade; SPDX headers per file.

**sprom.v** — GPL-3.0-or-later, (c) Markus Lavin.

**Analogue Pocket Framework** (`fpga/apf/`) — Analogue Enterprises'
APF Software License Agreement / EULA (<https://www.analogue.link/pocket-eula>);
header block in each file. `pll.v`, `audio_pll.v`, `pll_video_pc98.v` and
the `mf_*` blocks are Quartus-generated megafunctions (Intel FPGA IP).

## Behavioral references (no code copied)

- **np21w** (NP21/W 0.86 rev106) — the authoritative PC-98 behavioral
  reference used throughout; source comments cite it as `np21w <path>`.
- **np2kai** — used only as the runnable headless harness for host-side
  comparison (`docs/NP2KAI_HARNESS.md`).

## Not distributed

The NEC PC-98 BIOS, IPLware/ITF and font ROM are copyrighted NEC data and
are NOT in this repository or the release zip. The Pocket loads them as
user-placed data slots (`bios.rom`, `itf.rom`, `font.rom` under
`Assets/pc98/hiroya.PC9801/`). The OSD font glyphs drawn for this core
(the settings frame, VKB symbols, arrows) are original work; the ANK bank
is staged at boot from the user's own `font.rom` — see the header comment
in `firmware/osd_font.c`.
