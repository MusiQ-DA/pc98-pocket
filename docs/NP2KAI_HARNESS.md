# np2kai headless golden-reference harness

The behavioral reference for the FPGA core. np2kai runs the exact same
bios.rom/itf.rom/font.rom as the sim and the deploy card, so any value
it computes at boot is what the real machine computes.

## Build (one-time)

```sh
# libretro core (headless-capable), needs C++17 for the ymfm parts
cd ~/NP2kai/sdl
make -f Makefile.libretro -j8 CXX_VER="-std=c++17"
# stub for the unused SDL1 TTF include (font rendering is compiled out)
# -> sdl/libretro/SDL/SDL_ttf.h  (empty file, see git-less notes below)
```

The core compiled by this Makefile is np21 (i386c unified core). The
i286c core is not in the source list. The watch hook lives in
`i386c/ia32/cpu.c` `exec_allstep()` (NOT exec_1step -- that one only
runs for trap/dmac modes).

## Watch hook (applied to NP2kai, keep it)

`exec_allstep()` prints `NP2W` lines at:
  0xE8EB2 (int 0x80 site), 0xF8B2C (handler entry), 0xF8C5C, 0xF8C62
  (call F7DAE), 0xF7DAE (shared epilogue), 0xF0EB4 (post-INT return),
  0xF8B60 (screen clear), 0xF8B5E (jmp $), 0xF8B80, 0xFE1FD (boot
  decision)
plus a NP2BEAT heartbeat every 10M instructions (shows PC, CPU_TYPE,
12 code bytes) so a stuck machine is visible immediately.

## Driver

```sh
mkdir -p /tmp/np2run/np2kai
cp /tmp/pc98roms_deploy/{bios,itf,font}.rom /tmp/np2run/np2kai/
cd /tmp/np2run
cc -O2 -o np2run np2run.c \
   -I"$HOME/NP2kai/sdl/libretro/libretro-common/include" -ldl
cp "$HOME/NP2kai/sdl/np2kai_libretro.dylib" .
rm -f np2kai/np2kai.cfg        # config otherwise overrides the model
./np2run 5400                  # 90 s of emulated time
```

The driver answers the core options: np2kai_model=PC-9801VM,
clk_base=2.4576 MHz, system dir = CWD (ROMs under ./np2kai/).

## Findings (2026-09-12)

* `pc_model = VM` IS applied through the variable answer (cfg shows it).
* CPU_TYPE stays 0 unless `dipsw[2] & 0x80` -- np2's default dipsw[2]=0x7B
  keeps the V30 flag OFF; the VM BIOS boots fine that way.
* **pccore_reset() pre-writes the memory switch into VRAM:**
  `mem[0xa3fe2 + i*4] = np2cfg.memsw[i]` for i=0..7, defaults
  `{48 05 04 08 01 00 00 6E}`. FEA=4 (640 KB).
* The default DIP set {3E E3 7B} answers port 0x31 with 0xE3: bit4
  CLEAR means neither ITF nor BIOS runs its own memory-switch writer
  (that writer's maximum is FEA=2, the 512 KB class).
* Port 0x42 (prt_i42 in io/printif.c): 0x84 | 0x02(V30) | ... -- only
  consulted by the ROM writer we now bypass.

## Headless benchmark runs (cpubench)

`tools/np2run/np2run.c` is a minimal libretro driver: `retro_load_game`
mounts an .hdm as FDD0, guest RAM is read via `dlsym("mem")` (the 2MB
flat array -- RETRO_MEMORY_SYSTEM_RAM only covers CPU_EXTMEM which is
NULL on the 640KB VM), and the 80x25 text layer at 0xA0000 is decoded to
ASCII. `-mark STR` exits early when the string hits the screen; `-dump`
writes raw RAM for grep.

```sh
cc -O2 -o np2run tools/np2run/np2run.c -ldl
mkdir -p /tmp/np2run/np2kai && cp np2run ~/NP2kai/sdl/np2kai_libretro.dylib /tmp/np2run/
cp ~/.pc98roms/{bios,itf,font}.rom /tmp/np2run/np2kai/
cd /tmp/np2run && rm -f np2kai/np2kai.cfg
./np2run 7200 ../repo/pc98-pocket-zet/testdisk/cpubench.hdm
```

testdisk/build_cpubench.sh packs FreeDOS(98) + CPUBENCH 0.980 +
`CPUBENCH -p > RESULT.TXT`, so the score lands both on screen and inside
the image (FAT file -- readable back from a RAM-resident copy via JTAG).

Gotchas observed 2026-10:

* The i386c core ignores any notion of V30 pace: default mult=4 gives
  Ratio 36.17 (~486DX/33 class); `NP2_CLK_MULT=1` gives 1.79. np2kai is
  an upper bound only -- real V30@10MHz is ~3.11 (CPURACE.TXT).
* Numbers move ~5x under host load (other emulators/agents running
  concurrently dilate virtual time). Bench on an idle machine.
* CAUTION when editing ~/NP2kai: a leftover debug hook in bios.c once
  retargeted INT 1Eh to FD80:0A05 and silently derailed every disk boot
  (ITF -> 0000:04F8 -> garbage). If DOS never boots, `git diff bios/` there.
