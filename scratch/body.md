# NEC PC-98 ITF ROM — static analysis

Image: `~/.pc98roms/itf.rom`, 32768 bytes, mapped at guest physical `F8000`–`FFFFF`.
File offset *N* is address `F8000+N`; execution starts at `F800:0000`
(the reset vector at `FFFF0` is `EA 00 00 00 F8`).

Addresses below are written **`F8oooo`** where `oooo` is the 16-bit offset inside
the segment `F800` — i.e. `F8343A` means `F800:343A`, linear `FB43A`. Branch
targets inside the listings are printed as bare 16-bit offsets, so `JZ 012Bh`
means "jump to `F8012B`".

The ROM identifies itself at `F81CE3`:

    Initial Test Firmware       (C) NEC 1988

and can print `Processor is 80386` / `Processor is 70116 (V30)` and
`CPU Clock is 20MHz / 16MHz / 8MHz`, so this is a 386-generation PC-9801
(RA class) ITF.

## 0. How this was produced, and its limits

There is no disassembler on this machine, so one was written for the job:
`scratch/dis8086.py` (a table-driven 8086 decoder) plus `scratch/trace2.py`,
a recursive-descent walker with just enough constant propagation to resolve
this ROM's `MOV BP,imm ; JMP sub` / `JMP BP` calling convention and to expand
the port-table walker. Verification against the two stretches given by hand:

    F80000  FA             CLI
    F80001  B4D5           MOV AH,0D5h
    F80003  9E             SAHF
    F80004  79FE           JNS  0004h        (JNS $-2)
    ...
    F800D0  BEE500         MOV SI,00E5h
    F800D3  FC             CLD
    F800D4  32ED           XOR CH,CH
    F800D6  2EAD           CS:LODSW

Both match. The walker reaches 5106 bytes from the reset vector and 2468 more
from the shadow-ROM continuation at `F80B70`; everything else in the image is
data (GDC parameter blocks, the palette table, the message strings, a 4992-byte
floppy format table) or the protected-mode fragments noted below.

**Two honest caveats.**

1. The brief said "8086/8088 code only". That is not true of this image. The
   ITF uses 386 instructions in several places — `66`-prefixed `REP STOSD` /
   `REP SCASD` / `SHL EAX,16` in the memory tests (`F807EC`, `F81897`,
   `F818BE`), `PUSH imm16` (`F817ED`), `SHL AL,imm8` (`F817BC`), and
   `LGDT`/`LIDT`/`SGDT`/`SIDT`/`SMSW`/`LMSW` in the protected-mode block at
   `F80EC6`–`F80F5B`. The disassembler was extended to cover them. Anything
   decoded as an 8086-only opcode where a 186+/386 opcode exists (`C0`/`C1`,
   `C8`/`C9`, `6x`) is decoded with the 386 meaning.

2. Three transfers are **not resolved**:
   * `F80F5E  EA 64 10 38 00   JMP FAR 38h:1064h` — entry to the protected-mode
     extended-memory test. Selector `38h` is built at `F80F11`–`F80F30` from the
     descriptor template at `F80FE3`; the code at offset `1064h` inside that
     segment was not followed. It returns to real mode by resetting the CPU
     (`OUT 0F0h`) and coming back through `0000:0404`, landing at `F8126C`.
   * `F8130E  EA 9D 15 38 00   JMP FAR 38h:159Dh` — the same, second entry,
     returning to `F81716`.
   * `F81892  EA F8 04 00 00   JMP FAR 0000:04F8` — this one *is* resolved,
     because the ITF writes the six bytes at `0000:04F8` itself three
     instructions earlier; see §4.

   Everything else, including every `JMP BP` / `JMP SP` / `JMP SI` return, is
   resolved and named.

One cosmetic wrinkle: the listings below are linear over each range, and the
ROM has a few one-byte alignment fillers that the control-flow walker skips
(`F801E1`, `F80241`, `F8025B`, `F80285`, `F80321`, `F80683`, `F806E4`,
`F8087E`, `F80905`, `F80917`, `F80BBA`, `F80BC8`, `F80BCE`, `F80BE6`,
`F80BEC`, `F80C08`, `F80C0E`, `F8177F`, `F81AC5`, `F81B15`, `F81F1A`). All of
those are `90h` and decode as `NOP`, so they are harmless. The single
exception is `F806D4`, which holds `74h`; decoded linearly it swallows the
`3E` segment prefix of the real instruction at `F806D5` and shows as
`JZ 0714h`. The listing resynchronises at `F806D8`.

## 1. Annotated disassembly of the initialisation path

### 1.1 `F80000`–`F8004E` — CPU flag and register self-test

No I/O at all. Every conditional jump here is `J** $-2`: if the CPU does not
produce exactly the expected flag, the ROM spins on that instruction forever.
Then a walking-pattern test through `DS/SS/ES/SP/BP/SI/DI` with the four
patterns `FFFF`, `AAAA`, `5555`, `0000`.

```
{{dis:0000-004F}}
```

### 1.2 `F8004F`–`F80089` — port `0439h` probe, PPI and keyboard-USART reset

`0439h` is the system-control register. It is read twice (the first read is a
dummy). **If it reads zero** the ROM assumes a genuine cold start and resets the
8255 system port and the keyboard 8251; if not, it skips straight to `F8007F`.
Either way it finishes by writing `(old & 02h) | 34h` back to `0439h`.

```
{{dis:004F-0085}}
```

### 1.3 `F80085`–`F800BB` — restart-mode dispatch on PPI port C

This is the PC-98 "shutdown flag" dispatch, and it is the first place a
re-implementation can lose the machine.

* `IN AL,35h` reads 8255 #1 port C (the SHUT0/SHUT1 latch that `F80062` set
  to `FFh` on a cold start).
* **bit 7 == 0** → the ITF assumes it was re-entered by a deliberate CPU reset
  and returns to the caller through `SS:SP` loaded from `0000:0406`/`0000:0404`
  followed by `RETF`. The ITF itself uses this twice (`F80F54` and `F817EA`).
* **bit 7 == 1 and bit 5 == 0** → prints `SYSTEM SHUTDOWN` and hangs at `F800BA`.
* **bit 7 == 1 and bit 5 == 1** → normal cold start at `F800BC`.

```
{{dis:0085-00BC}}
```

### 1.4 `F800BC`–`F800E4` — PIT channel 1 park, and the port-table walker

```
{{dis:00BC-00E5}}
```

The walker at `F800D3`: `SI` points at a table; the first word gives the entry
count in its low byte and the *high* byte of every port in its high byte; each
following word gives the data in its low byte and the *low* byte of the port in
its high byte. When `CX` runs out, `JMP SI` continues execution at the first
byte past the table. It is used three times in this ROM (tables at `00E5`,
`03EE`, `05E6`).

**Table at `F800E5`, decoded:**

```
{{tbl:00E5}}
```

### 1.5 `F80101`–`F8013B` — board control, hardware-configuration gate

```
{{dis:0101-013C}}
```

`IN AL,42h` reads the printer 8255's port B, which on PC-98 doubles as a
hardware-configuration/DIP read. **Bit 1 must read 0**; if it is set the ITF
sets PPI-C bit 5 and writes port `0F0h`, which resets the CPU, then spins
waiting for the reset. Bit 5 then chooses `43Fh := 42h` or `43Fh := 40h`.

### 1.6 `F8013C`–`F8042E` — display (twin µPD7220) initialisation

Called with the return address in `BP` (here `057Fh`). It is one long straight
line of "load a GDC parameter block, wait, load the next", punctuated by DIP-switch
reads that choose between two CRT timings. `AH` selects which GDC the block goes
to: bit 7 = 0 → text GDC (command `62h`, parameters `60h`), bit 7 = 1 → graphic
GDC (command `A2h`, parameters `A0h`); bit 6 = 1 skips the FIFO wait.

```
{{dis:013C-0230}}
```

```
{{dis:0230-0330}}
```

```
{{dis:0330-03EE}}
```

**The `F80388` block is where a machine with no working video timing stops.**
`IN AL,60h ; TEST AL,20h` polls the text GDC's status port for the vertical
sync/blank bit and requires it to go **low, then high, then low**, twice
(`CX = 2`); then the same three-edge sequence on the graphic GDC status port
`A0h`, three times. See §3.

**Second port table, at `F803EE`:**

```
{{tbl:03EE}}
```

```
{{dis:03FA-042F}}
```

Palette table consumed by the loop above (16 × 3 bytes, G/R/B):

```
{{data:042F-045F}}
```

### 1.7 `F8045F`–`F804E4` — the GDC parameter-block writer, and the retrace wait

```
{{dis:045F-04E5}}
```

The parameter blocks it walks (`count`, then `count` bytes: the first goes to
the command port, the rest to the parameter port):

```
{{blocks}}
```

Decoded as µPD7220 commands: `00`=RESET, `0E`/`0F`=SYNC(DE=0/1),
`6E`/`6F`=VSYNC(slave/master), `46`=ZOOM, `47`=PITCH, `49`=CSRW, `4B`=CCHAR,
`4C`=FIGS, `20`=WDAT, `70`/`78`=PRAM load, `0C`/`0D`=BCTRL (display off/on).

### 1.8 `F8057F`–`F805DF` — ROM checksum and the 8253 setup

```
{{dis:057F-05E0}}
```

The checksum sums the 16384 words of the ROM into `DL` (even bytes) and `DH`
(odd bytes); **`DX` must come out `0000`** or the ROM spins at `F80595` with no
message, because the display is not up yet. The supplied image passes:
even-byte sum `00`, odd-byte sum `00`.

### 1.9 `F805E0`–`F80620` — third port table, then the 8259 pair

```
{{dis:05E0-05E6}}
```

```
{{tbl:05E6}}
```

```
{{dis:05FC-0621}}
```

Master 8259 (`00h`/`02h`): ICW1 `11h`, ICW2 `08h` (vectors 08–0F), ICW3 `80h`
(slave on IR7), ICW4 `1Dh`. Slave 8259 (`08h`/`0Ah`): ICW1 `11h`, ICW2 `10h`
(vectors 10–17), ICW3 `07h`, ICW4 `09h`.

### 1.10 `F80621`–`F80713` — keyboard 8251 primitives and the power-on key scan

```
{{dis:0621-0672}}
```

```
{{dis:0672-0714}}
```

Six polls of the keyboard receiver, `3000h` iterations each. Whatever make
codes arrive are folded into `AH`: `60h`→bit 7, `71h`(CAPS)→bit 1,
`72h`(KANA)→bit 2, `73h`(GRPH)→bit 3, `74h`(CTRL)→bit 4, `70h`(SHIFT)→bit 0.
If nothing arrives (the normal case) `AH` stays `00h` and the ROM takes the
full-test path. A keyboard interface that is simply absent — status `43h`
reading `00h` (never ready) *or* `FFh` (always ready, data `FFh`) — both give
`AH = 0`, which is the safe outcome.

### 1.11 `F80714`–`F807EB` — boot beep, or the two shortcut paths

```
{{dis:0714-076F}}
```

```
{{dis:0770-07EC}}
```

* `AH` bit 7 clear (nothing held): two-tone beep on PIT channel 1 through
  PPI-C bit 3, then on to the VRAM tests at `F807EC`.
* `AH` == `91h` after masking (STOP + SHIFT + CTRL): **ITF service mode** at
  `F81F8E` — this is the floppy-based ITF/BIOS updater, and it is the *only*
  path that touches the FDC and the DMA controller. Off the normal boot path.
* otherwise (STOP held alone, etc.): clear the BIOS work area and jump straight
  to the final configuration at `F8174B`, skipping every RAM and VRAM test.

### 1.12 `F807EC`–`F80A95` — VRAM, CG, memory-switch and base-RAM tests

```
{{dis:07EC-087F}}
```

```
{{dis:087F-08F1}}
```

```
{{dis:08F1-09FA}}
```

```
{{dis:09FA-0A96}}
```

### 1.13 `F80A96`–`F80B6F` — the ROM-shadow stub, executed from RAM at `0000:0000`

`F80A88` copies `200h` bytes from `CS:0A96` down to `0000:0000` and
`JMP FAR 0000:0000`. The stub must run from RAM because its first act is to
unmap the ITF ROM.

```
{{dis:0A96-0B70}}
```

It runs twice (`SP` is the pass counter): pass 1 checksums the real BIOS ROM at
`F8000` and `E8000`, copies both into the shadow RAM at `98000` and `88000`,
optionally copies `D7000`→`97000`, and re-enters; pass 2 re-checksums with the
shadow active. Any bad checksum sets CF and exits to `F80B5F`, which maps the
ITF back in (`043Dh := 10h`) and far-jumps to `F800:0B70`, where CF selects the
`ROM SUM ERROR` message.

### 1.14 `F80B70`–`F80D93` — bank memory, A20, PIT, DMA, PIC and IRQ0 tests

```
{{dis:0B70-0C4E}}
```

```
{{dis:0C4E-0D94}}
```

Three of these are absolute gates, each ending in `HLT`:

* **A20 (`F80C52`)** — writes `55AAh` to `CS:[8000h]` = `F800:8000` = linear
  `100000h` and requires `0000:0000` to be unchanged. A 20-bit-wrapping address
  bus fails here with `ADDRESS 20 LINE ERROR`.
* **8237 (`F80CD7`)** — writes `FFh`/`00h` twice into each of `01,03,05,07,09,0B,0D,0F`
  and reads each back twice; the 16-bit value must match. `DMA ERROR`.
* **IRQ0 (`F80D38`)** — installs a handler at `0000:0020`, checks that *no*
  interrupt arrives while the master IMR is `FFh`, then sets counter 0 to
  `001Ah`, writes `FEh` to the master IMR and requires the interrupt to arrive
  within 32 polls. `TIMER INTERRUPT ERROR`.

### 1.15 `F80D94`–`F80F62` — memory-switch defaults, extended-memory sizing, protected mode

```
{{dis:0D94-0E93}}
```

```
{{dis:0E93-0F63}}
```

`F80F5E` is the first unresolved transfer: protected-mode code at selector
`38h`, offset `1064h`. It returns by resetting the CPU (`F81263` /
`F81E98` / `F81E9D` all do `OUT 0F0h` + `HLT`) and coming back through the
`0000:0404` shutdown vector.

### 1.16 `F81263`–`F81312` — protected-mode return paths

```
{{dis:1263-126C}}
```

```
{{dis:12B4-1313}}
```

### 1.17 `F8174B`–`F81896` — final configuration and the hand-over

```
{{dis:174B-1897}}
```

### 1.18 Helper routines used above

```
{{dis:1897-18F1}}
```

```
{{dis:19BF-1B34}}
```

```
{{dis:1DCB-1F8D}}
```

(`F81F8D` is a single `00h` alignment filler; `F81F8E` is the service-mode
entry, off the boot path.)

