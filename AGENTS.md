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
  regenerates `firmware.vh` + `firmware.bin` — the Quartus build consumes the
  COMMITTED `firmware.vh`, so rebuild and commit it after ANY source edit.
  CI runs `nodiv-verify`: compiles, links and disassembles to prove the
  image has no div/rem (the softcore is mul-only: `-march=rv32i_zmmul`,
  so a stray `/` is a link error, not a silent trap).
- Full bitstream: GitHub Actions `build.yml` (`quartus` job — Quartus Lite
  in the `raetro/quartus:pocket` docker image, no license, no Windows
  runner) on push to `main` or `workflow_dispatch`. The CI artifact
  carries both `.sof` and `.rbf` — JTAG flashes take the CI `.sof`
  directly.

## Forbidden: local full-project Quartus builds

NEVER run `quartus_sh --flow compile`, `quartus_fit`, `quartus_asm` or any
full-project Quartus stage against `fpga/ap_core` locally — directly, via
`docker run`, or via `docker exec` into a container that has this repo
mounted. Reasons: emulated x86 Quartus takes hours, the incremental db
(`fpga/db`, `fpga/incremental_db`, `fpga/output_files`) is shared state a
second compile corrupts, and the result is throwaway anyway since CI is
the shipping bitstream. Fit/resource questions go through a CI run; if a
number is needed before pushing, use `scripts/measure_core.sh <top>
<files>` — it synthesises ONE module in a scratch dir under /tmp, never
touches `fpga/db`, and is the only sanctioned local Quartus invocation.

## Deploying to hardware

- Prefer `scripts/jtag_flash.sh <path/to/ap_core.sof>` — it programs the
  Cyclone V directly over JTAG and does NOT touch the SD card. Pass the CI
  artifact `.sof` (from the `bitstream` artifact of a `build`
  run; the artifact carries `output_files/ap_core.sof`). Docker converts
  .sof→.svf, openocd plays it. A core must be RUNNING on the Pocket for
  the bitstream to take (the menu leaves the fabric unconfigured).
- `scripts/deploy.sh` (the deploy skill's path) builds the full
  `hiroya.PC9801` core directory onto the SD card — use it only when the
  SD card route is explicitly wanted, e.g. when data-slot assets changed.
  Do not deploy via the card by default.

### Local sim toolchain caveat

CI's sim job runs Verilator 5.020 (Debian apt). Homebrew's newer Verilator
(5.052 observed) mis-schedules `while(cond) @(posedge clk)` wait loops under
`--timing` — `tb_pc98_font_stress` reports false "wedged" fills locally while
the identical files pass in CI. For an authoritative local run of a
`--timing` bench, use the `pc98-sim` docker image (`docker build -t pc98-sim
sim/`, then the CI invocation from `.github/workflows/build.yml`). Lint and
non-`--timing` benches are unaffected.
