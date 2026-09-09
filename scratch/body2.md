
## 2. Every I/O port the ITF touches, in program order

This is the boot path with **no key held at power-on** and a cold start
(`0439h` reads 0, PPI-C reads `FFh`). Values are given where they are an
immediate or a traceable constant; `—` means a read, `?` means the value is
computed at run time and the surrounding disassembly says how.

Reads whose result is branched on are listed here too, but §3 is the section
that matters for them.

{{iotable}}

### 2.1 The three port-initialisation tables, as plain OUT lists

The walker at `F800D3` (§1.4) is entered three times. Decoded:

**Table 1 — `F800E5`, 13 entries, reached by falling through from `F800D0`,
resumes at `F80101`:**

    OUT 0011, 44     8237 command register
    OUT 0037, 92     8255 #1 mode set: A in, B in, C out
    OUT 0037, 07     PPI-C bit 3 := 1   (buzzer off)
    OUT 0050, 00     NMI control
    OUT 0037, 0D     PPI-C bit 6 := 1
    OUT 0046, 82     8255 #2 mode set
    OUT 0046, 0F     8255 #2 port C bit 7 := 1
    OUT 0037, 0C     PPI-C bit 6 := 0
    OUT 0037, 0F     PPI-C bit 7 := 1
    OUT 0037, 0A     PPI-C bit 5 := 0
    OUT 006A, 07     MODE FF2: reg 3 := 1
    OUT 006A, 04     MODE FF2: reg 2 := 0
    OUT 006A, 06     MODE FF2: reg 3 := 0

**Table 2 — `F803EE`, 5 entries, reached by `JMP 00D3h` from `F803EB`,
resumes at `F803FA`:**

    OUT 0068, 02     MODE FF1: reg 1 := 0
    OUT 00A8, 37     digital palette 0
    OUT 00AA, 15     digital palette 1
    OUT 00AC, 26     digital palette 2
    OUT 00AE, 04     digital palette 3

**Table 3 — `F805E6`, 10 entries, reached by `JMP 00D3h` from `F805E3`,
resumes at `F805FC`:**

    OUT 0029, 00     DMA bank-select register, channel 0
    OUT 0029, 01     ... channel 1
    OUT 0029, 02     ... channel 2
    OUT 0029, 03     ... channel 3
    OUT 001B, 00     8237 master clear
    OUT 0027, 00     DMA bank ch3 := 0
    OUT 0021, 00     DMA bank ch0 := 0
    OUT 0023, 00     DMA bank ch1 := 0
    OUT 0025, 00     DMA bank ch2 := 0
    OUT 0011, 40     8237 command register := 40h

### 2.2 Ports touched only on the ITF service path (`STOP`+`SHIFT`+`CTRL`)

Reached from `F80786` → `F81F8E`. Not on the normal boot path, listed for
completeness: `0BEh` (FDD interface mode change), `090h`/`092h`/`094h`
(640 KB FDC status/data/control), `0C8h`/`0CAh`/`0CCh` (1 MB FDC
status/data/control), and the 8237 setup at `F833DE`–`F83438`
(`009h`, `00Bh`, `00Dh`, `00Fh`, `015h`, `017h`, `019h`, `023h`, `025h`),
which ends in `FF E5  JMP BP`.

## 3. Every place the ITF polls a port and branches

Each entry says which value lets execution continue. Where a poll has no
timeout it is marked **hard**; a re-implementation that does not satisfy it
hangs the machine.

| addr | port | test | branch | what lets it continue |
|------|------|------|--------|-----------------------|
| `F80054` | `0439h` | `OR AL,AL` | `JNZ 007F` | either way is fine — `00h` means "cold start, reset the 8255/8251 first", non-zero skips that. `00h` is the safe reset value. |
| `F8008C` | `35h` | `TEST AL,80h` | `JNZ 0099` | **bit 7 must be 1**, else the ITF does `MOV SS,[0406] / MOV SP,[0404] / RETF` into whatever RAM happens to hold. Cold-start value `FFh` is correct. |
| `F8009B` | `35h` | `TEST AL,20h` | `JNZ 00BC` | **bit 5 must be 1**, else `SYSTEM SHUTDOWN` and hang at `F800BA`. |
| `F80119` | `42h` | `TEST AL,02h` | `JZ 012B` | **bit 1 must be 0**. If set: `OUT 37h,0Bh`, `OUT 0F0h,00h` (CPU reset) and `JMP $`. |
| `F8012D` | `42h` | `TEST AL,20h` | `JNZ 0133` | either — selects `043Fh := 42h` (bit set) or `40h` (bit clear). |
| `F8013E` | `33h` | `TEST AL,08h` | `JNZ 0148` | either — `06Eh := 01h` or `00h`. Also read at `F80165`, `F801D6`, `F801E5`, `F80218`, `F802C1`, `F80316`, `F80325`, `F80339`, always bit 3, always choosing between two GDC/CRT parameter sets. Bit 3 set selects the "07 90 65" SYNC timings. |
| `F80224`, `F80268` | `31h` | `TEST AL,08h` | `JZ`/`JNZ` | either — chooses the CRT parameter triple written to `70h`/`72h`/`74h`. |
| `F8029F` | `31h` | `TEST AL,04h` | `JZ 02A7` | either — bit set adds `OUT 68h,05h`. |
| `F802AD` | `42h` | `TEST AL,10h` | `JNZ 02B5` | either — bit clear adds `OUT 6Ah,41h`. |
| `F80476`, `F804B4` | `60h` | `TEST AL,04h` | `JZ` (loop) | **hard.** Text-GDC FIFO-empty. Bit 2 must eventually read 1 or the parameter writer never returns. A status port stuck at `00h` hangs here. |
| `F80484`, `F804C2` | `A0h` | `TEST AL,04h` | `JZ` (loop) | **hard.** Same for the graphic GDC. |
| `F8038A` | `60h` | `TEST AL,20h` | `JNZ 0388` | **hard.** Wait for VSYNC status *low*. |
| `F80390` | `60h` | `TEST AL,20h` | `JZ 038E` | **hard.** Then wait *high*. |
| `F80396` | `60h` | `TEST AL,20h` | `JNZ 0394` | **hard.** Then wait *low* again; the whole triple runs twice (`LOOP 0388`). Bit 5 of port `60h` must actually toggle. |
| `F803A4`, `F803B0`, `F803BC`, `F803D2` | `A0h` | `TEST AL,20h` | as above | **hard.** The same low/high/low sequence on the graphic GDC, three times, plus one more wait-for-high at `F803D0`. |
| `F804D9`, `F804DF` | `60h` | `TEST AL,20h` | `JZ`/`JNZ` | **hard.** The "wait one retrace" helper: wait for bit 5 == 0 then bit 5 == 1. Called ten times on the boot path. |
| `F80593` | (memory) | `OR DX,DX` | `JNZ 0595` | **hard.** The 32 KB ROM checksum must be zero. Silent hang. |
| `F805BB` | `42h` | `TEST AL,20h` | `JNZ 05C2` | either — PIT channel 1 divisor `03E6h` (set) or `04CDh` (clear). |
| `F80646` | `43h` | `TEST AL,01h` | `JZ 0642` | **hard.** Keyboard 8251 TxRDY. Every keyboard command send waits here with no timeout. `43h` reading `00h` hangs; `FFh` passes. |
| `F80661` | `43h` | `TEST AL,02h` | `JNZ 0669` | soft — RxRDY with a 32768-iteration timeout; timing out is a legal answer. |
| `F8067B` | `43h` | `TEST AL,02h` | `JNZ 0684` | soft — the power-on key scan, `3000h` iterations × 6. |
| `F80720` | `42h` | `TEST AL,20h` | `JNZ 0727` | either — beep divisor. |
| `F80822`, `F80828` | (memory) | `REP SCASD` / `SCASB` | `JNZ 0836` | soft — graphic VRAM at `A0000` must read back `FF/AA/55/00`; failure prints `TEXT VIDEO RAM ERROR` and continues. |
| `F8089B` | `7FDDh` | `TEST AL,04h` | `JNZ 08A8` | either — 0 = "Processor is 80386", 1 = "Processor is 70116 (V30)". Only on the information screen. |
| `F80906`, `F80918` | (memory) | via `F8092A` | `JNZ 0972` | soft — character-generator RAM test through `A1h`/`A3h`/`A5h` and the `A4000` window; failure prints `KANJI CG RAM ERROR`. |
| `F809BD` | `31h` | `TEST AL,10h` | `JZ 09FA` | either — bit set runs the memory-switch cell test at `A000:3FE2…`. |
| `F809DE` | (memory) | read/modify/verify | `JNZ 09ED` | soft — `MEMORY SWITCH ERROR`. |
| `F80A26` | CF from `F818BE` | `JC 0A58` | | soft-ish — base 128 KB must read back `01/FF/AA/55/00`; otherwise `MEMORY ERROR` then `CLI ; JMP $`. **Effectively hard.** |
| `F80A2A` | `33h` | `TEST AL,04h` | `JNZ 0A4F` | **bit 2 must read 0.** It is the parity-error latch; set means `PARITY ERROR` then `CLI ; JMP $`. |
| `F80AB2`, `F80ACD` | (memory) | `OR DX,DX` | `JZ` | **hard-ish.** With `043Dh := 12h` the system BIOS ROM must be visible at `F8000` (32 KB) and `E8000` (64 KB) and each must checksum to zero, else `ROM SUM ERROR`. |
| `F80B19` | `0F0h` | `TEST AL,20h` | `JNZ 0B45` | either — bit clear also shadows `D7000`→`97000`. |
| `F80B49` | `7FDBh` | `TEST AL,40h` | `JNZ 0B51` | either — `043Fh := 80h` (set) or `82h` (clear). |
| `F80BA7` | (memory) | `CMP [B000:0],AA55h` | `JZ 0BB3` | either — presence test for the bank-memory window opened by `043Fh := 22h`. |
| `F80BF1`, `F80C13` | `33h` | `TEST AL,04h` | `JNZ 0C23` | parity again, this time on the bank window; failure prints `EMS ERROR` and continues. |
| `F80C5F` | (memory) | `CMP [0000:0],55AAh` | `JZ 0C6B` | **hard.** A20 test: writing `F800:8000` must *not* alter `0000:0000`. Failure prints `ADDRESS 20 LINE ERROR` then `HLT`. |
| `F80CA1` | `71h`/`73h`/`75h` | `CMP AH,AL` | `JNZ 0CAD` | **hard.** 8253 latch-and-read-back on all three counters must return what was written (`FFh`, then `00h`). Failure: `TIMER ERROR` + `HLT`. |
| `F80CE3` | `01h`…`0Fh` | `CMP BX,AX` | `JNZ 0CF1` | **hard.** 8237 address/count register read-back, `FFh` then `00h`, all eight registers. Failure: `DMA ERROR` + `HLT`. |
| `F80D0B`, `F80D1F` | `02h`, `0Ah` | `CMP AH,AL` | `JNZ` | **hard.** 8259 IMR read-back on master and slave, `00h` then `FFh`. Failure: `TIMER INTERRUPT ERROR` + `HLT`. |
| `F80D4B` | `AH` | `TEST AH,0FFh` | `JZ 0D57` | **hard.** With the master IMR at `FFh` no IRQ0 may reach the CPU during 32 polls. |
| `F80D6F` | `AH` | `TEST AH,0FFh` | `JNZ 0D7D` | **hard.** After `OUT 71h` counter0 := `001Ah` and `OUT 02h,0FEh`, **IRQ0 must fire within 32 polls**. Failure: `TIMER INTERRUPT ERROR` + `HLT`. |
| `F80D96` | `31h` | `TEST AL,10h` | `JZ 0DDA` | either — bit set writes the memory-switch defaults. |
| `F80DB9` | `7FDBh` | `TEST AL,40h` | `JNZ 0DC2` | either — memory-switch byte `+0Ah` := `04h` or `03h`. |
| `F80DFA` | (memory) | `CMP DH,AL` | `JNZ 0DFF` | either — compares the measured extended-memory size against the memory-switch value at `A000:3FEA`; mismatch keeps testing, match jumps to `F80E93`. |
| `F80EA1` | `42h` | `TEST AL,02h` | `JZ 0EA8` | **bit 1 clear enters protected mode** at `F80F5E`. Bit 1 set skips straight to `F812B4`. |
| `F80EEB` | (registers) | `REP SCASW` | `JZ 0EF0` | **hard.** `LIDT`/`LGDT` then `SIDT`/`SGDT` must return the same 10 bytes for `FFFF`, `AAAA`, `5555`, `0000`. Failure → `F81263` → `PPI-C bit 5 := 1`, `OUT 0F0h,00h`, CPU reset. |
| `F812B6` | `42h` | `TEST AL,02h` | `JNZ 12C2` | bit 1 set → straight to the final configuration. |
| `F812BE` | `7FDDh` | `TEST AL,04h` | `JZ 12C5` | bit 2 clear (386 mode) → the second protected-mode entry at `F8130E`; bit 2 set → `F8174B`. |
| `F8176F`, `F81786`, `F81792` | `43h`/`41h` | keyboard reply | | soft — sends `9Fh` and looks for `FAh`, `A0h`, `80h`; a timeout just leaves `0000:0481` bit 6 clear. |
| `F817A1` | `7FDBh` | `TEST AL,40h` | `JNZ 17A9` | either — `043Fh := 80h` or `82h`. |
| `F817B2` | `0F0h` | `TEST AL,40h` | `JNZ 17C5` | either — bit clear reads `0CC4h` into `0000:0484`. |
| `F817C9` | `0F0h` | `TEST AL,20h` | `JNZ 17D0` | either — `053Dh := 06h` or `46h`. |
| `F817E4` | `7FDDh` | `TEST AL,04h` | `JZ 17FB` | **bit 2 clear (386 mode) causes a deliberate CPU reset**: `PPI-C bit 7 := 0`, `SS:SP` saved to `0000:0404/0406`, `OUT 0F0h,07h`, `HLT`. Execution must come back at `F80000`, take the `bit 7 == 0` branch at `F8008C`, and `RETF` to `F817FB`. Bit 2 set skips all of that. |
| `F81843` | `42h` | `TEST AL,02h` | `JNZ 185A` | either — bit clear runs `FNINIT`/`FNSTSW` and sets MP in CR0 if a 387 answered. |
| `F81EF7`, `F81F05` | (memory) | `CMP AX,3333h` / `5555h` | `JNZ 1F1B` | either — GRCG plane test; result only sets or clears bit 6 of `0000:054D`. |
| `F81F7F` | `A0h` | `TEST AL,02h` | `JNZ 1F77` | **hard.** Graphic-GDC FIFO-full must clear. |
| `F81F8A` | `A0h` | `TEST AL,04h` | `JZ 1F82` | **hard.** Graphic-GDC FIFO-empty must set. |

### 3.1 `F8343A` and the FDC polls (service path only)

The brief asked specifically about `F8343A`. It is reached only from
`F81F8E`, i.e. only when `STOP`+`SHIFT`+`CTRL` were held at power-on
(`AH == 91h` at `F80773`). On the ordinary boot path this code never runs.

```
{{dis:343A-34AB}}
```

Read as three FDC primitives, each selecting between the 640 KB interface
(`90h`/`92h`) and the 1 MB interface (`C8h`/`CAh`) on **bit 0 of port `0BEh`**
(1 → 640 KB side, 0 → 1 MB side):

* **`F8343A` — wait not-busy.** `XOR CX,CX` gives 65536 tries. `TEST AL,10h`
  sets ZF when MSR bit 4 (FDC busy, `CB`) is *clear*, and `LOOPNE` continues
  while ZF == 0, i.e. **while the FDC still reports busy**. It falls out either
  when bit 4 reads 0 (then `JNZ` is not taken, `CLC`, return with CF=0 = OK) or
  when `CX` reaches 0 with bit 4 still set (`JNZ 3482` → `STC`, CF=1 = timeout).
  **To continue: MSR bit 4 must read 0 within 65536 polls.**
* **`F83458` — send a command byte.** Waits for `MSR & C0h == 80h`
  (RQM=1, DIO=0 → the FDC wants a byte from the CPU), then `OUT 92h/0CAh, AH`.
  Same 65536-try `LOOPNE`, CF=1 on timeout.
  **To continue: MSR bits 7..6 must read `10b`.**
* **`F83485` — read a result byte.** Waits for `MSR & C0h == C0h`
  (RQM=1, DIO=1), then `IN AL,92h/0CAh`. **To continue: MSR bits 7..6 must
  read `11b`.**

`F834AB`/`F834C8` are the keyboard companion: reset the 8251 with commands
`3Ah`, `32h`, `16h`, then wait up to `4000h` polls for `43h` bit 1 (RxRDY)
and require the byte read from `41h` to be **`61h`** (the keyboard self-test
reply). CF=1 otherwise.

### 3.2 The reported hang at `08383`, and the `000C` / `000D` writes

The observation is "writes ports `000C` and `000D`, then the CPU reads around
address `08383` repeatedly".

`8383h` is the **low 16 bits of `F8383`**, and `F80383` is:

```
{{dis:0381-039C}}
```

The mapping is exact, not approximate: the ROM occupies `F8000`–`FFFFF`, so
`(F8000 + off) & FFFF == 8000 + off`, and `8383h` can only be ROM offset
`0383h`. `F80383` is the last instruction before the ITF starts waiting for
**bit 5 of the text-GDC status port `60h`** to go low, then high, then low —
twice over (`CX = 2`). With `60h` stuck at any constant value the CPU spins on
`F80388`–`F8038C` (if bit 5 reads 1) or `F8038E`–`F80392` (if it reads 0)
forever, and the instruction fetches sit exactly where the hardware trace put
them. No other spin loop in the image lands near `8383h`: the complete list of
self-jumps in the ROM is `8004`–`802D` and `8048` (the CPU flag/register
self-test traps), `80BA` (`SYSTEM SHUTDOWN`), `8129` (waiting for the CPU reset
it just asked for), `8595` (ROM checksum), `8A56`/`8A62` (memory error),
`9E53` (message control bit 7), and `A03E`/`A048`/`A052`/`B5C1`/`B5E0` in the
service mode. Nothing in the ROM reads a fixed RAM address around linear
`08383` in a loop either. I am confident this is the hang.

The `000C`/`000D` half I cannot reconcile cleanly, and I would rather say so
than invent a story. **This ROM never executes `OUT 0Ch` or `OUT 0Dh` on the
boot path.** The only `OUT 0Dh,AL` instructions in the whole image are at
`F8341E` and `F83424`, inside the DMA setup that is reachable only from the
service path, and there is no `OUT 0Ch,AL` anywhere. The candidates, best
first:

1. **The values `0Dh` and `0Ch`, not the ports.** At `F803C6` the ITF writes
   `0Dh` to `A2h` and then to `62h` (µPD7220 `BCTRL`, display on) and at
   `F803DC` writes `0Ch` to the same two ports (display off). Those are the
   only places in the boot path where `0Ch` and `0Dh` appear as data on
   consecutive writes — but they come *after* the `F80388` loop, so if the
   machine really stops at `8383` it never reaches them.
2. **A truncated port number.** The last port written before entering the
   loop is `6Ch` (`F80383  OUT 6Ch,AL` — the border-colour register, value
   `00h`). If the trace only captured the low nibble of the port, `6Ch` shows
   as `Ch`. Nothing on the path writes a port whose low nibble is `Dh` at that
   point, so this explains one of the two writes and not the other.
3. **The service path was entered.** If the keyboard interface returns
   plausible-looking garbage the key scan at `F80672` could in principle
   produce `AH == 91h` and divert to `F81F8E`, where `OUT 0Dh` (DMA channel 3
   address, `F8341E`/`F83424`) is genuinely executed. But `F81F8E` runs
   `OUT 0BEh`, `OUT 94h`/`0CCh`, and the FDC polls first, and it would have to
   get past `F80388` to have run at all — the observed hang address says it
   did not.

So: the `8383` hang is the GDC vertical-sync wait; the `000C`/`000D` writes
are most likely the border-colour write at `F80383` plus one more the trace
attributed to a port number, and I could not pin the second one down.

## 4. The hand-over: `OUT 043Dh, 12h`

Port `043Dh` is the ROM bank select. `10h` maps the ITF ROM at `F8000`;
`12h` maps the system BIOS ROM there instead. The ITF writes `12h` in two
different places, and only the second is the hand-over.

**(a) `F80A9D` — temporary, inside the shadow stub.** The stub copied to
`0000:0000` writes `043Dh := 12h` so that it can checksum and copy the real
BIOS ROM, and finishes with `043Dh := 10h` at `F80B6A` to map the ITF back in.
This is not the hand-over.

**(b) `F81892` — the real hand-over.** Because the write itself unmaps the
code that is executing, the ITF assembles a six-byte stub in low RAM and
jumps to it:

```
{{dis:186F-1897}}
```

`0000:04F8` ends up holding

    EE            OUT DX,AL              ; DX = 043Dh, AL = 12h
    EA 02 00 80 FD  JMP FAR FD80:0002

so the sequence is: set `DX = 043Dh` and `AL = 12h` in ROM, far-jump to
`0000:04F8`, write `12h` to `043Dh` (the ITF vanishes from `F8000` at that
instant), and far-jump into the system BIOS at **`FD80:0002`** (linear
`FD802`). Note the PPI writes immediately before: `PPI-C bit 7 := 1` and
`PPI-C bit 5 := 0`, which is exactly the combination that, on the next CPU
reset, sends `F8009B` down the `SYSTEM SHUTDOWN` branch rather than a cold
start.

**Everything that must succeed before `F81892` is reached**, in order:

1. `F80000`–`F8004E` CPU flag and register self-test — no I/O, but every step
   must produce the architecturally correct flags.
2. `F8008C` port `35h` bit 7 must read 1; `F8009B` bit 5 must read 1.
3. `F80119` port `42h` bit 1 must read 0.
4. `F8013C`–`F8042D` the whole display initialisation, including the
   **hard** GDC FIFO waits (`60h`/`A0h` bit 2) and the **hard** vertical-sync
   waits (`60h`/`A0h` bit 5).
5. `F80593` the 32 KB ROM checksum must be zero.
6. `F80646` every keyboard command send must see `43h` bit 0 (TxRDY).
7. `F80822`/`F80906`/`F809DE` VRAM, CG and memory-switch tests — these only
   print a message and carry on, so they are not blocking.
8. `F80A26`/`F80A2A` the base 128 KB must read back correctly and `33h` bit 2
   (parity) must be 0, or the ITF stops with `CLI ; JMP $`.
9. `F80AB2`/`F80ACD` with `043Dh := 12h`, the BIOS ROM at `F8000` (32 KB) and
   the extension ROM at `E8000` (64 KB) must each checksum to zero, and the
   shadow copy to `98000`/`88000` must work.
10. `F80C5F` the A20 test — `F800:8000` must not alias `0000:0000`.
11. `F80CA1` 8253 latch/read-back on all three counters.
12. `F80CE3` 8237 address/count read-back on channels 0–3.
13. `F80D0B`/`F80D1F` 8259 master and slave IMR read-back.
14. `F80D4B` no interrupt while masked, then `F80D6F` **IRQ0 must actually
    fire** once counter 0 is loaded with `001Ah` and the master IMR is `FEh`.
15. `F80EEB` the descriptor-table registers must survive `LGDT`/`SGDT` and
    `LIDT`/`SIDT`, then the protected-mode block at `38h:1064h` must return.
16. `F817E4` in 386 mode, the deliberate CPU reset must round-trip: `OUT 0F0h,07h`
    must reset the CPU, the ITF must restart at `F80000`, see `35h` bit 7 == 0,
    and `RETF` through `0000:0404`/`0406` back to `F817FB`.
17. `F81861` a final PIT setup, `F8186C` the GRCG/EGC probe (`A0h` FIFO polls,
    **hard**).

Only then does `F8187B` build the stub and `F81892` jump to it.

## 5. What a re-implementation has to provide, in the order the ITF demands it

1. **A correct 8086-compatible flag model, and 386 instructions.** The first
   79 bytes are a flag self-test that hangs on any discrepancy, and the ROM
   later needs `66`-prefixed string ops, `SHL r32,imm`, `PUSH imm16`,
   `SHL r8,imm8`, `LGDT/LIDT/SGDT/SIDT/SMSW/LMSW` and `FNINIT/FNSTSW`.
2. **Port `0439h`** readable and writable. Returning `00h` is the safe answer.
3. **8255 #1 at `31h`/`33h`/`35h`/`37h`** with a working bit-set/reset control
   port. Port C must read back what was written: after `OUT 37h,92h` and
   `OUT 35h,0FFh` the read at `F8008A` must give bit 7 = 1 and bit 5 = 1.
   Port `33h` bit 2 (parity latch) must read 0.
4. **8255 #2 at `42h`/`46h`.** `42h` bit 1 must read 0. Bits 4 and 5 only
   select variants.
5. **8253 at `71h`/`73h`/`75h`/`77h`** with real counters: the latch command
   (`00h`/`40h`/`80h`) must return what was loaded, and channel 0 must generate
   IRQ0.
6. **Twin µPD7220 at `60h`/`62h` and `A0h`/`A2h`.** This is the biggest single
   requirement and the one the observed hang is about. The status ports must
   provide, at minimum: bit 2 = FIFO empty (must become 1), bit 1 = FIFO full
   (must become 0), and **bit 5 = vertical sync/blank, which must actually
   toggle**. The command/parameter FIFO must accept the blocks listed in §1.7
   without stalling.
7. **The mode registers `68h`, `6Ah`, `6Ch`, `6Eh`, `70h`–`76h`, `7Ch`, `7Eh`**
   as write-only sinks at the very least; the GRCG (`7Ch`/`7Eh`) must really
   work if `0000:054D` bit 6 is to be set correctly, but a non-working GRCG only
   clears a flag, it does not hang.
8. **A ROM image whose 32 KB word-wise checksum is zero.**
9. **Keyboard 8251 at `41h`/`43h`.** Status bit 0 (TxRDY) must read 1 — this is
   an untimed wait and is the second most likely place to hang. Bit 1 (RxRDY)
   may stay 0 forever; every receive has a timeout.
10. **8259 pair at `00h`/`02h` and `08h`/`0Ah`** with a readable IMR and a real
    IRQ0 path from PIT channel 0.
11. **8237 at `01h`–`1Fh` plus the bank registers `21h`–`27h` and `29h`**, with
    readable 16-bit address and count registers.
12. **Bank/ROM control: `043Dh`** (`10h` = ITF, `12h` = BIOS), **`043Fh`**,
    **`0461h`**, **`0467h`**, **`053Dh`**, and a shadow-RAM region at `88000`
    and `98000` that can be written when `0461h := 0Eh` and read back after
    `0461h := 0Ch`.
13. **A system BIOS ROM behind `043Dh = 12h`**: 32 KB at `F8000` and 64 KB at
    `E8000`, each checksumming to zero, with an entry point at `FD80:0002`.
14. **A 21-bit (or wider) address bus** — `F800:8000` must not wrap onto
    `0000:0000`.
15. **At least 128 KB of base RAM** that passes the `FF/AA/55/00` pattern test,
    plus whatever extended memory is claimed by the memory-switch byte at
    `A000:3FEA`.
16. **`OUT 0F0h` must reset the CPU** and restart execution at `F800:0000` with
    the PPI port C latch preserved, because the ITF uses that as its way back
    from protected mode. It writes `07h` at `F81E9D` and `00h` at `F81E98`.
17. **`0F2h`, `0F6h`** (protected-mode/A20 gate) and **`0F0h` read** (mode
    status bits 5 and 6).
18. **`7FDBh`, `7FDDh`, `7FDFh`, `0CC4h`** as readable configuration ports.
    `7FDDh` bit 2 is the one that matters: **0 selects the 386 path**, which
    includes the protected-mode tests and the CPU-reset round trip; **1 selects
    the V30 path**, which skips both. If the reset round trip is not
    implemented, reporting `7FDDh` bit 2 = 1 is the cheap way past it — at the
    cost of the machine calling itself a V30.
19. The graphic VRAM planes at `A8000`/`B0000` (and `A0000`/`A2000` text,
    `A4000` CG window, `A000:3FE0`+ memory switches) — failures here only
    print messages.
20. Nothing at all for the FDC or the service-mode DMA setup, unless
    `STOP`+`SHIFT`+`CTRL` is to work.

## Appendix A — messages in the ROM

Each message is `attribute byte, ASCIIZ text, control byte`; control bit 0 =
beep, bit 1 = keep the buzzer on, bit 7 = `CLI ; JMP $` after printing.

{{msgs}}

## Appendix B — data regions

| range | contents |
|-------|----------|
| `F800E5`–`F80100` | port table 1 (13 entries) |
| `F803EE`–`F803F9` | port table 2 (5 entries) |
| `F8042F`–`F8045E` | analogue palette table, 16 × (G,R,B) |
| `F804E5`–`F8057E` | µPD7220 parameter blocks |
| `F805E6`–`F805FB` | port table 3 (10 entries) |
| `F80F63`–`F80FE2` | 128 bytes copied to `0000:8000` — IDT/GDT pseudo-descriptors for the first protected-mode entry |
| `F80FE3`–`F80FE8` | the descriptor prototype the loop at `F80F10`–`F80F30` expands into 256 GDT entries |
| `F80F63`–`F8125F` | this whole region also contains the protected-mode code entered at `38h:1064h`; **not disassembled** |
| `F81313`–`F8174A` | likewise for the second entry (`38h:159Dh`), including its own template at `F81416`; **not disassembled** |
| `F81B34`–`F81DCA` | messages |
| `F81E88`–`F81E97` | `"0123456789ABCDEF"` for the hex printer |
| `F8205E`–`F833DD` | 1248 × (C,H,R,N) — the format ID table for a 1.2 MB 2HD disk, 8 sectors of 1024 bytes × 2 heads × 78 tracks (service mode) |

## Appendix C — unreferenced code

`F8196F` (an NMI/parity handler that reads `33h` bit 1/2 and prints
`PARITY ERROR - BASE MEMORY` / `- EXTENDED MEMORY`) and `F8199A` (a spurious-
interrupt handler that reads the 8259 ISR through `OUT 00h,0Bh` / `IN AL,00h`
and issues the right EOI) are complete and correct routines that nothing in
this image installs. They are presumably installed by the system BIOS after
the hand-over, or are left over from a shared source tree.
