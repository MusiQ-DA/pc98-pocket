# PC-9801UX hardware manual vs. this RTL — subsystem difference report

Compares the NEC **PC-9801UX hardware manual** (OCR extract; local copy
`/tmp/ux_hw_layout.txt`, `/tmp/ux_hw.txt` — line numbers cited as `man:N`)
against the RTL in this tree at commit `aa663d6`. np21w
(`~/repo/np21w/np21w-src-rev106`) is the behavioural reference and is cited
where the OCR is unreadable or to explain what the hardware does.

**Legend:** **I** = implemented and connected; **P** = partially implemented
(what exists works, but the scope is smaller than the manual's); **M** =
missing (a repository-wide search finds no implementation); **—** = not
applicable to the UX.

**Build note (read first):** the shipped configuration is the *JTAG debug*
build — `fpga/config.tcl:23` sets `PC98_JTAG=1` while `ENABLE_OPNA` is
commented out at line 15. So the shipping bitstream has **no FM sound board
at all — only the beeper**; the OPNA material below describes what
`ENABLE_OPNA=1` builds.

## 0. Machine class

| | Manual (UX) | RTL |
|---|---|---|
| CPU | V30 (μPD70116) 8 MHz **or** i80286 10 MHz board (man:817, 2689) | V30 only (`fpga/core/v30/`), OSD-selectable 4.915 / 9.830 / 19.66 / 21.48 MHz (`fpga/core/chipset/HDL/ce_generator.sv:59-89`, `core_top.sv:287-296`) — the 9.83 MHz "10 MHz" step is cycle-paced like the real speeds |
| RAM | 640 KB | 640 KB (SDRAM, `pc98_sdram_map.svh:43-47`) |
| ROM | 96 KB BIOS + ITF | 96 KB at E8000-FFFFF; ships **the PC-9801UX ITF** + PC-9801VM BIOS (`config.tcl:25-37`) — the UX BIOS is not usable on a V30 (PUSHA/SMSW at FDA35+) |
| Graphics | 2× μPD7220A, GVRAM 256 KB, **EGC present** | 2× `pc98_gdc`, 3+1 planes, second 640×400 page → total 256 KB (`pc98_sdram_map.svh:51-71`, `Chipset.sv`), EGC modelled (`pc98_egc.sv`) but **parked out of the shipped build** (`.EGC(1'b0)` on `pc98_gvram_seq` — 873 ALMs the device could not carry) |
| Display | 640×400 and 640×200 | 640×400 fixed; 200-line modes via line-doubling |
| Sound | onboard FM source: FM×3 + SSG×3 (YM2203/OPN class) (man:270, 1349-1373) | OPNA (YM2608, the -86 board) with ADPCM-A rhythm + drive noise (`pc98_opna.sv`, `firmware/drive_sound.c`) |
| FDC | μPD765A, 1MB(2HD) and 640KB(2DD) interfaces | μPD765 model + PC-98 glue, both interfaces |
| HDD | UX41 only: internal HDD via μPD7261 HDC | none; a PC-9801-55-class SCSI board instead |
| Misc | PIC 2× PD71059C, DMA PD8237A-5, PIT PD8253-5, RTC uPD4990A, kbd/RS-232C PD8251A, printer PD8255A-5 | see below |

The core is a **V30-machine**; everything that only exists on the 80286 board
(A20 gate, protected mode, NDP) is out of scope by construction.

## 1. CPU and memory

| Feature | Manual | RTL | Status |
|---|---|---|---|
| V30 CPU | μPD70116 8 MHz | nuV30 core, 4.915 MHz default (×2/×4 steps of the 2.4576 MHz family, `fpga/core/chipset/HDL/ce_generator.sv:53-58`) | **I** — rate differs, family-accurate |
| i80286 10 MHz board | option (SW3-8) | no 286 core | **M** (out of scope — V30 machine) |
| 640 KB RAM 0-9FFFF | yes | `pc98_sdram_map.svh:43` | **I** |
| TVRAM A0000-A3FFF (8 KB code + 8 KB attr) | yes | `pc98_tvram.sv` BRAM | **I** |
| Memory switch A3FE2-A3FE9 (battery-backed, in TVRAM attr tail) | yes | pre-seeded `{48 05 04 08 01 00 00 6E}` + write-protect + cfg overrides (`pc98_tvram.sv:34-164`) | **I** |
| CG window A4000-A4FFF, code ports 0xA1/A3/A5 | yes | `Peripherals.sv:1563-1566`, `pc98_cgwindow.sv`, FONT.ROM at SDRAM 0x400000 | **I** |
| GVRAM 3 planes A8000-BFFFF (32 KB each) | yes | `pc98_sdram_map.svh:53-56` | **I** |
| 4th plane E0000-E7FFF (analog mode only) | yes | mode-6A bit-0 remap, `pc98_gdc_mode2.sv`, map `:44-49` | **I** |
| GVRAM 2nd page (256 KB total) | implied by 256 KB VRAM | access/display page bits 0xA6/0xA4, page-1 bank at SDRAM 0x600000 (`pc98_sdram_map.svh:65-71`, `Peripherals.sv:1360-1371`) | **I** |
| C0000-E7FFF option hole | expansion area | open (reads float) except EMS windows D2000 SCSI ROM and E0000 analog plane | **I** |

## 2. Interrupts — 2× PD71059C (8259)

| | Manual | RTL (`Peripherals.sv:375-529`) | Status |
|---|---|---|---|
| Master PIC ports | 0x00-0x06 even | decode `address[7:3]==0 & ~A0` (:234), `i8259` inst :423 | **I** |
| Slave PIC ports | 0x08-0x0E even | decode :491-492, inst :494 | **I** |
| Cascade | slave INT → master IRQ7 | `.interrupt_request` :463 (`interrupt2_to_cpu` on IR7 input) | **I** |
| IRQ0 timer | system timer | `timer_interrupt` :470 | **I** |
| IRQ1 keyboard | keyboard | `keybord_interrupt` (8251 RxRDY) :470, :683 | **I** |
| IRQ2 CRT | CRT vsync | `crt_vsync_irq` edge-per-frame :744 | **I** (no 0x64 clear port — flagless edge design, equivalent) |
| IRQ3 | C-bus INT0 (expansion) | `1'b0` (:466) | **P** — line exists, no source |
| IRQ4 | RS-232C | `1'b0` (:467) — consistent with the absent UART | **M** |
| IRQ5 | C-bus INT1 (expansion) | `interrupt_request[5]`, tied 0 at `core_top.sv:2299` | **P** |
| IRQ6 | C-bus INT2 (expansion) | `pc98_master_irq6 = 1'b0` (:421, :464) | **P** |
| IRQ7 | slave cascade | `interrupt2_to_cpu` :463 | **I** |
| Slave IRQ8 | — | `2'b0` :528 | **P** (unused) |
| Slave IRQ9 | C-bus INT3 = **HDC interrupt** (man:1477) | `2'b0` :528 — consistent with absent HDC | **M** |
| Slave IRQ10 | C-bus INT4 = 640 KB FDC (man:1478) | `fdc_glue_irq_2dd` :528 | **I** |
| Slave IRQ11 | 1 MB FDC interrupt (BIOS INT 13h) | `fdc_glue_irq_2hd` :528 | **I** |
| Slave IRQ12 | C-bus INT5 = sound board (man:1479) | `opna_irq` :527 (0 when OPNA off) | **I** |
| Slave IRQ13 | C-bus INT6 = bus mouse (man:1480) | `busmouse_irq` :527 | **I** |
| Slave IRQ14/15 | — | `2'b0` :527-528 | **P** (unused) |
| PIT-write IRR0 clear quirk | (np21w io/pit.c) | `pit0_write_clears_irr0` :401-414 → PIC `:448` | **I** |

## 3. DMA — PD8237A-5

| | Manual | RTL | Status |
|---|---|---|---|
| Channel regs | 0x01-0x1F odd (man row 3) | `dma_chip_select_n` :233, `upd71071` (`Bus_Arbiter.sv:195-213`) | **I** |
| Page regs | 0x21-0x2F odd (man row 5) | four 4-bit regs, `Bus_Arbiter.sv:225-240` | **I** |
| FDC DMA | FDD on ch2/ch3 (np21w: 2HD=ch2, 2DD=ch3) | `fdd_dma_ack = ~dma_acknowledge_n[2] \| ~dma_acknowledge_n[3]` (`Chipset.sv:429`) | **I** |
| SASI/HD DMA ch0 | UX41 HDC uses ch0 (np21w `SASI_DMACH=0`) | ch0 ack exists (`Bus_Arbiter.sv:266-276`) but no device raises DRQ0; vestigial DRQ0 is driven by PIT ch1 edges (`Chipset.sv:222-232`) | **P** — channel exists, no consumer |
| TC/EOP | terminal count | `terminal_count` `Bus_Arbiter.sv:199,214` | **I** |
| 0x0E05-0x0E0B bank regs | not on UX (np21w 9821-era) | absent | **—** |

## 4. Timers — PD8253-5 PIT and the relative counter (ARTIC)

| | Manual | RTL | Status |
|---|---|---|---|
| PIT ports | 0x71-0x77 odd (man row 12) | `timer_chip_select_n` :243, `i8253` inst :606 | **I** |
| PIT clock | 2.4576 MHz class | phase accumulator at exactly 2.4576 MHz :543-566 | **I** |
| PIT alias | **0x3FD9-0x3FDF odd — in the manual's own decode table** (row 27 = PD8253-5) | `timer_alias_cs` :236-242 (added in commit `2b61e5b`) | **I** |
| ARTIC 相対カウンタ | 0x5C-0x5F (data-book feature of this machine class; the manual decode table does not list it) | 24-bit counter :989-1006, read mux :2312-2316 | **P** — **rate is ~4.2× too fast**: accumulator ticks at ≈1.287 MHz (42.95 MHz × 1250/41700) but real HW/np21w run it at **≈307.2 kHz** (2.4576 MHz/8; np21w `io/artic.c` `2×baseclock/(13 or 16)`, QEMU PC-98 `TIMESTAMP_HZ 307200`). The stale comment at :984 claims 42950→1.25 MHz; games pacing off deltas (DEPTH.EXE etc.) see ~4× the real elapsed count |
| ARTIC write 0x5F | timing write | deliberately unclaimed :986-987 (same as function on HW: costs cycles only) | **I** |
| Beeper | PIT ch1 tone + port-C bit3 gate | `speaker_out = spktone & ~port_c[3]` :597-626 | **I** |

## 5. Display — GDC/CRTC, CRT modes, palette, EGC/GRCG, CG

### GDC (2× μPD7220A)

| | Manual | RTL | Status |
|---|---|---|---|
| Text GDC ports | 0x60-0x6F (status/parameter/command, CRT-int reset, light pen) | 0x60/0x62 only :774 | **P** — status/param/FIFO done; 0x64 vsync-IRQ arm/ack not decoded (flagless design doesn't need it — np21w `gdc_o64` just sets `vsyncint`); 0x66 light pen not decoded (np21w binds NULL there too; pen reads 0 via LPRD, `pc98_gdc.sv:349-352`) |
| Graphics GDC | 0xA0-0xAF + mode regs | 0xA0/0xA2 :775 | **P** (same) |
| Command set | full 7220 | RESET, SYNC on/off, START/STOP, ZOOM, PITCH, CSRW, MASK, CSRFORM, VECTW, PRAM 0x70-7F, CURD, LPRD (`pc98_gdc.sv:213-227`) | **P** |
| Drawing engine | FIGS/FIGD, TEXTE, WDAT, RDAT | VECTE/TEXTE via firmware server (`gdc_service.c`), slave only; **WDAT/RDAT absent**; TEXTE uses 16-bit pattern not 8-byte PRAM | **P** |
| SYNC params | program the raster | recorded, not obeyed (`pc98_gdc.sv:13-16`) | **P** |
| Status bits | incl. light pen, DMA | hblank/vsync real; LPEN set; DRDY draw handshake | **I** |

### CRTC / CRT modes

| | Manual | RTL | Status |
|---|---|---|---|
| CRTC text regs | 0x70-0x76 even (man row 11) | 0x70-0x7A {pl,bl,cl,ssl,sur,sdr} :1449-1463 — np21w's full 6 | **I** (superset) |
| 640×400 / 24.83 kHz | yes | `pc98_video_timing.sv` — the only raster (:25-35) | **I** |
| 640×200 | yes | line-doubling on the 400-line raster via `gdc_s_dbl` :1517-1526 (mode1 bit4 / CSRFORM LR / SYNC AL<256) — same visual result as real HW | **I** |
| 15.98 kHz raster | GDC-programmable (np21w table) | not generated — SYNC AL is read only to select doubling | **M** |
| 31 kHz | later boards | not generated | **M** (not a UX mode anyway) |
| GDC clock 5/2.5 MHz | SW2-8 | port-0x6A ext cmds → `gdc_clk`, consumed as pitch semantics `Peripherals.sv:1199` | **I** |
| Text pitch / 20-line mode | CRTC bl/cl | real — `pc98_text_render.sv:54-66` | **I** |
| Palette | 16-colour analog palette 0xA8-0xAE | :1381-1419; digital 8-colour remap **not** implemented (:1378-1380) | **I** (digital palette gap) |
| GRCG | 0x7C/0x7E | `pc98_grcg.sv` + `pc98_gvram_seq.sv` (TDW/RMW/TCR) | **I** |
| EGC | **present on UX** (man:296, decode row 19 = 0x4A0-0x4AE even) | `pc98_egc.sv` all 8 regs + ROP engine inside `pc98_gvram_seq.sv`; **parked via `.EGC(1'b0)`** in the shipped build (873 ALMs over the 1848-LAB budget); 0x4A0-0x4AF decode removed, so writes go nowhere and reads float | **I** (parked) |
| CG / fonts | ANK + JIS1/JIS2 kanji ROM | FONT.ROM loaded to SDRAM; CG window + ANK BRAM (`pc98_font_ank.sv`) | **I** |

## 6. FDC — μPD765A

| | Manual | RTL | Status |
|---|---|---|---|
| 1MB(2HD) window | 0x90/0x92 data/MSR (man row 16) | `floppy0_chip_select_n` :360-363 | **I** |
| 640KB(2DD) window | 0xC8/0xCA (man row 24) | same :360-363 | **I** |
| Control ports | 0x94/0xCC | `pc98_fdc_glue` (np21w fdc_i94 semantics — not a latch readback) :267-279 | **I** |
| Interface select "chgreg" | 0xBE (SW3-2/SW4 media) | real latch :267, `pc98_fdc_glue` | **I** |
| FDC engine | μPD765A | `floppy.v` (specify/recal/seek/read/write/format/sense; 512B 2DD + 1024B 2HD sectors; NOT_READY termination for empty drives) | **I** |
| Interrupts | slave IRQ10/IRQ11 | `fdc_glue_irq_2dd`/`_2hd`, gated by chgreg exactly like np21w `fdc_intwait` :302-303, 522-528 | **I** |
| DMA | ch2/3 + TC | `Chipset.sv:429`, `fdd_dma_tc` | **I** |
| 1.44MB 3-mode port | not on UX | `0x4BE` optional `SUPPORT_144` :315, `pc98_fdc_glue:116-119` | **I** (extension beyond UX) |
| 3.5" drive sense 0x51-0x57 | not in UX map (np21w fdd320, later machines) | absent | **—** |

Minor recorded divergences (`pc98_fdc_glue.sv:120-129`): np21w's OSASK
interrupt-on-reset workaround not reproduced; control bit 0x10 not mapped.

## 7. Storage — built-in HDC vs. the SCSI board

| | Manual | RTL | Status |
|---|---|---|---|
| Internal HDC | **UX41 only**: internal HDD via μPD7261 HDC (man:533-536, 2155-2165); I/F at **0x80/0x82** (decode row 13; np21w `cbus/sasiio.c` attaches 0x0080/0x0082) | no 0x80/0x82 decode anywhere | **M** — UX41's onboard hard disk is absent |
| SASI BIOS/DMA | HDC driven from system BIOS, DMA ch0 | none | **M** |
| SCSI option board | manual option list includes PC-9801-50 SCSI card (man:585-600) | `pc98_scsi.sv` WD33C93 window 0xCC0-0xCC6 (:1725), option ROM D2000-D2FFF (:1732-1733), commands serviced by firmware — provides a working hard disk, but as a **different card** than the UX41's native HDC | **I** (as an option card) |
| IDE | not on UX (np21w ideio is 9821-era) | none | **—** |

Impact: software written for the internal HDD (SASI BIOS) finds nothing; the
SCSI board serves the same role through its own BIOS.

## 8. Keyboard and mouse

| | Manual | RTL | Status |
|---|---|---|---|
| Keyboard USART | PD8251A 0x41/0x43 (man row 9) | `pc98_kbd8251` :1056-1073 — break-edge reset, RxRDY→IRQ1, status `status \| 0x85` (np21w `keyboard_i43`) | **I** |
| Reset-ACK | 0x60 within poll window | deliberately delayed past the ITF's window so the no-keyboard boot path runs (`pc98_kbd8251.sv:45-55`, `ACK_DELAY_TICKS`=350 ms); BIOS's INT18h reset still receives it via IRQ1 | **P** — workaround for unimplemented "keyboard arrived mid-POST" flow |
| Keyboard cmd replies | 0x9C/9D/9F → 0xFA… | not synthesised (`pc98_kbd8251.sv:62-67`) | **P** |
| Key input | matrix | PS/2-Set2 → PC-98 translator `pc98_kbd_ps2.sv`, injection port | **I** |
| Bus mouse | 8255 0x7FD9-0x7FDF + timing 0xBFDB, IRQ13 (man rows 26/28) | `pc98_busmouse` :1085-1105 — full 8255 model, latch/nibble/IRQ13 at 120-15 Hz | **I** (0x7FDF reads unclaimed, matching np21w :2327) |

## 9. Serial, printer, CMT

| | Manual | RTL | Status |
|---|---|---|---|
| RS-232C USART | PD8251A 0x30/0x32 (man row 6), modem lines on 0x33 bits 7-5, baud = PIT ch2, master IRQ4 (np21w `io/serial.c` `pic_setirq(4)`) | **no UART at all** — 0x30/0x32 unclaimed; 0x33 modem bits read 0 (:1043); PIT ch2 runs but nothing consumes it | **M** |
| RS-232C extension | 0xB0-0xBF (man row 22) | absent | **M** |
| Printer I/F | PD8255A-5 0x40-0x47 even (man row 8): 0x40 data, 0x44 control, 0x46 status | only **0x42** answered, constant 0x02 (:933, 1044) | **M** (stub only — no data/control/status ports) |
| CMT (cassette) | PD8251A 0x91-0x99 odd (man row 17) | absent | **M** |

## 10. Sound

| | Manual | RTL | Status |
|---|---|---|---|
| Beeper | PIT-driven | `speaker_out` :626 | **I** |
| Onboard FM source | YM2203-class OPN: FM×3 + SSG×3 (man:270, §2.4) | `pc98_opna` is a **YM2608 OPNA** at 0x188-0x18F + 0xA460 ext latch (:1886-1896) — in non-extended mode it answers as the 3-channel OPN the UX has, at the standard -86 board base 0x188 (the manual's own decode row assigns a "sound" window around 0x88-0x8F; OCR ambiguous, np21w only ever binds 0x188/0x288) | **P** — superset silicon, off in the shipped config |
| FM enable | — | `ENABLE_OPNA` commented out, `config.tcl:15` — shipped build has **no FM sound** | **M** (build-time) |
| Rhythm/ADPCM-A | not on OPN | rhythm voices via firmware-loaded 8 KB ADPCM-A store (`pc98_opna.sv:461-490`); instantiated `USE_ADPCM(1), USE_PCM(0)` (`Peripherals.sv:1914`) — note the stale `config.tcl` comment which still describes the slim `USE_ADPCM=0/USE_PCM=1` build | **P** (beyond-UX) |
| **DELTA-T / ADPCM-B 256 KB** | **not a UX feature** — the UX's OPN has no ADPCM at all; this is the -86 board's extra | `use_adpcmb=0` (`pc98_opna.sv:514`), `adpcmb_data` tied `8'h00` (:1931-1936) — "No fourth sdram_mp.sv port yet"; gap list at `pc98_opna.sv:548-564`: no 256 KB SDRAM window, jt12 ADPCM-B is read-only, DELTA-T regs 0x0C/0x0D/data-port 0x08 dropped (:243-250) | **M** |
| OPNA interrupt | -86 INT5 (IRQ12) | wired `opna_irq` :527 | **I** (when built) |
| Joystick port (-86 SSG IOA) | option | `opna_joy` input, gamepad "Joystick" mode (`core_top.sv:1476`) | **I** |
| -86 16-bit PCM | beyond UX | only 0xA460 bit0 decoded; 0xA460-0xA46C PCM not present (:1883-1884) | **M** |
| RSS (Sound Orchestra) | not on UX | none | **—** |

## 11. System ports, DIP switches, RTC

| | Manual | RTL | Status |
|---|---|---|---|
| 8255 sys ports | 0x31-0x37 odd | 0x31 `cfg_dipsw2` (:931,1042), 0x33 = `8'h08 \| cdat` (:945,1043), 0x35 port-C latch :904-928, 0x37 bit set/reset :920-926 | **I** |
| DIP SW2 | 8 switches (BASIC mode, boot, 80×25/20-line, GDC clk…) | byte = `cfg_dipsw2` (OSD, default 0xE3): bit1 keeps the 286-PM block skipped — V30-true; bit4 clear protects pre-seeded memory switch | **P** — fixed defaults, one OSD byte, not per-switch |
| DIP SW1 | SW1-1 24/15 kHz etc. | only bit0 reachable, via 0x33 bit3 hardwired 1 = 24 kHz (:1043, np21w `sysp_i33`) | **P** |
| DIP SW3 | FDD I/F mode, RAM size, CPU type | not exposed as a port; its effects are hardwired (640KB FDD window present, V30 truth in SW2 bit1) | **P** |
| Shutdown flag | port-C bit7 survives OUT F0h | implemented in `pc98_sysport_c` (:891-903) | **I** |
| RTC uPD4990A | 0x20 serial cmd, data out via sysport; manual also decodes 0x22 | `pc98_upd4990` — full serial model + "uPD4990 Happy" marker; cdat → 0x33 bit0 (:952-974); np21w's secondary 0x22 window **not** implemented | **I** (0x22 gap) |
| OUT F0h CPU reset | CPU port 0xF0 | `core_top.sv:2156-2189` CPU-only reset | **I** |
| ROM bank port | 0x043D: 0x10→ITF, 0x12→BIOS | `core_top.sv:2146-2154` `itf_bank` | **I** |
| CPU ports 0xF2/0xF6 | A20 gate (286 board) | absent | **—** (V30 machine) |
| NMI 0x50/0x52 | **not used on the UX** (man §2.1.4(a): NMI unused) | absent | **—** correctly absent |

## 12. Expansion — C-bus, EMS, misc boards

| | Manual | RTL | Status |
|---|---|---|---|
| C-bus slots | 3 slots (man §2.5), pins incl. IR3/5/6/9/10/12/13, DRQ | no bus model; boards are hardwired devices | **P** |
| PC-9801-50 SCSI card | in option list | `pc98_scsi` + `pc98_scsi_rom` | **I** |
| Memory/EMS board | expansion RAM options | NEC EMS board `pc98_ems98` — 0x8E1-0x8E9, four 16 KB windows C0000-CFFFF, up to 8 MB pool, IN 0x8E9 size probe (`pc98_ems98.sv:1-30`) | **I** |
| Sound board option | -26K/-86 class | OPNA model above (build-time optional) | **P** |
| GP-IB (IEEE-488) | PC-9801-29N, PD7210C at 0xC0-0xCF (man rows 25/26+4533) | none | **M** |
| CMT I/F | PC-9801-13 | none | **M** |
| Joystick I/F | PC-9801-27 | none (the -86's joystick port exists instead) | **M** |
| FDD I/F card | PC-9801-09 | covered by onboard-equivalent glue | **—** |
| Extra serial/RS-232C card | PC-9801-19 etc. | none | **M** |
| NDP 80287 | 0xF8-0xFF, 286 board option (man row 30) | none | **—** |
| 0x00E0-0x00EC | N-BASIC INP ports (man note (2)) | absent | **M** (obscure) |
| 0xE9 | np2 debug port, not real HW | absent | **—** |

## 13. Biggest compatibility gaps, ranked

1. **No RS-232C USART (0x30/0x32) and no printer (0x40-0x46)** — serial mice
   on COM1, printer output and any program talking to the modem/serial port
   find open bus. The mouse is bus-mouse only, which is period-correct for
   PC-98 games but wrong for software expecting a COM port.
2. **Built-in HDC (μPD7261, 0x80/0x82) absent** — UX41 software booted for the
   internal hard disk won't see it; the RTL substitutes a PC-9801-55 SCSI
   card (0xCC0 + D2000 ROM), so HD-capable software exists but the native
   SASI path is empty.
3. **No FM sound in the shipped build** (`ENABLE_OPNA` off); even enabled it
   is a full OPNA at 0x188 rather than the UX's plain OPN — mostly
   compatible, but the **DELTA-T/ADPCM-B 256 KB window is absent** so games
   using -86 streamed audio stay silent (gap list: `pc98_opna.sv:548-564`).
4. **Raster is fixed 640×400/24.83 kHz** — GDC SYNC parameters are recorded,
   not obeyed (`pc98_video_timing.sv:13-24`); no real 15.98 kHz/31 kHz
   retiming. Software that reprograms sync for effect (rare) gets nothing;
   640×200 works via line-doubling.
5. **GDC drawing is a subset** — VECTE/TEXTE run on the firmware server but
   **WDAT/RDAT (the 7220's own VRAM write/read commands) are missing**, so
   software that pushes pixels through GDC commands rather than the GRCG
   produces nothing; light pen always reads 0.
6. **Interrupts IRQ3-6 and slave IRQ9 unpopulated** — C-bus expansion INT0-2
   (master IRQ3/5/6), RS-232C (master IRQ4) and the HDC line (slave IRQ9)
   are grounded (`Peripherals.sv:466-467`, `core_top.sv:2299`).
7. **ARTIC counts ~4.2× too fast** — 1.287 MHz vs. the real ~307.2 kHz
   (np21w `io/artic.c`, QEMU `TIMESTAMP_HZ=307200`); software that converts
   counter deltas into real time runs off the mark
   (`Peripherals.sv:989-1006`).
8. **Keyboard ACK timing is deliberately late** (350 ms vs. the real ~10 ms)
   so the ITF takes its no-keyboard path — a known workaround
   (`pc98_kbd8251.sv:45-55`).
9. **Minor:** RTC secondary port 0x22 absent; DIP SW1/SW3 mostly hardwired;
   digital-mode palette remap absent; no GP-IB/CMT/joystick boards
   (options only).

Correctly absent (the manual doesn't have them): NMI ports, NDP/A20 ports
(V30 machine), RSS, fdd320, 0xE9 debug, 0x0E05-0x0E0B DMA bank regs.

## Appendix — verified RTL port map (what actually answers)

| I/O | Device | Where |
|---|---|---|
| 0x00-0x06 even | master PIC | Peripherals.sv:234, 423 |
| 0x08-0x0E even | slave PIC | :491-492, 494 |
| 0x01-0x1F odd | DMA | :233, Bus_Arbiter.sv:195 |
| 0x21-0x2F odd | DMA page regs | :247, Bus_Arbiter.sv:225 |
| 0x20 | RTC cmd | :950, 968-974 |
| 0x31/0x33/0x35/0x37 odd | DIP/sysport | :907-945, 1041-1045 |
| 0x41/0x43 | kbd 8251 | :1056-1073 |
| 0x42 | printer stub (0x02) | :933, 1044 |
| 0x5C-0x5F | ARTIC | :1003-1006, 2313-2316 |
| 0x60/0x62, 0xA0/0xA2 | GDC×2 | :774-775 |
| 0x68, 0x6A | GDC mode regs | :1291-1330 |
| 0x70-0x7A even | CRTC cell regs | :1449-1463 |
| 0x71-0x77 odd + **0x3FD9-0x3FDF odd** | PIT + alias | :236-244 |
| 0x7C/0x7E | GRCG | :1467-1477 |
| 0x7FD9-0x7FDF odd, 0xBFDB | bus mouse | :1085-1087 |
| 0x90/0x92/0x94, 0xC8/0xCA/0xCC, 0xBE, 0x4BE | FDC | :267-363 |
| 0xA1/0xA3/0xA5 | CG code ports | :1563-1566 |
| 0xA4/0xA6 | GVRAM pages | :1360-1371 |
| 0xA8-0xAE even | analog palette | :1381-1419 |
| 0x4A0-0x4AF | EGC (write-only) | parked — no decode in shipped build |
| 0xCC0-0xCC6 | SCSI regs | :1725 |
| D2000-D2FFF | SCSI option ROM | :1732 |
| 0x188-0x18F, 0xA460 | OPNA (if ENABLE_OPNA) | :1886-1896 |
| 0x8E1-0x8E9 | NEC EMS | pc98_ems98.sv:5-17, Chipset.sv:569-578 |
| 0x043D | ITF/BIOS bank | core_top.sv:2146-2154 |
| 0xF0 | CPU reset | core_top.sv:2177-2189 |
| A0000-A3FFF | TVRAM + memsw | pc98_tvram.sv |
| A4000-A4FFF | CG window | pc98_cgwindow.sv |
| A8000-BFFFF (+E0000 analog) | GVRAM planes | pc98_sdram_map.svh:43-71 |
