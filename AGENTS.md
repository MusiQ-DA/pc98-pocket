# PC-98 Pocket — agent notes

## Implementation reference

The behavioral reference for PC-98 hardware is **np21w** (NP21/W
`0.86 rev106`), NOT np2kai. np21w is the more accurate, still-maintained NP2
source; np2kai remains only as the runnable headless harness
(`docs/NP2KAI_HARNESS.md`, `np2kai_libretro.dylib`) since np21w ships Windows
binaries only.

- np21w source is extracted locally at
  `~/repo/np21w/np21w-src-rev106/` (from the `np21w-src-rev106.zip`
  bundled inside the `np21w-0.86-rev106beta1` binary distribution).
- Comments cite it as `np21w <path>` (e.g. `np21w io/fdc.c (fdc_intwait)`,
  `np21w cbus/board86.c`). The file layout matches the old np2kai citations
  (`io/`, `cbus/`, `mem/`, `vram/`, `sound/`, `diskimage/`, `font/`).
- When a doc/comment claims behavior derived from np2kai and it disagrees with
  np21w, trust np21w and re-verify.

## Verification

- RTL: `bash scripts/lint_core.sh` — elaborates `core_top` with Verilator and
  fails on implicit nets / undeclared identifiers / unconnected input pins.
- `python3 scripts/check_unconnected.py` — dangling softcpu/core inputs.
- Firmware: build with Homebrew LLVM (Apple clang lacks rv32):
  `cd firmware && PATH="/opt/homebrew/opt/llvm/bin:$PATH" make`
  regenerates `firmware.vh` + `firmware.srchash`. CI verifies the committed
  `firmware.srchash` matches the sources — rebuild after ANY source edit
  (comments included, they change the hash).
- Full bitstream: GitHub Actions `build.yml` (`quartus-win` job, native
  Windows Quartus) on push to `main` or `workflow_dispatch`. The local
  Docker Quartus scripts were removed (unreliable under wine/Rosetta);
  the CI artifact carries both `.sof` and `.rbf` — JTAG flashes take the
  CI `.sof` directly.
