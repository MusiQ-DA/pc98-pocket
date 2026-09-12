# nuV30 verification note: V30 reserved opcodes 0x66 / 0x67 — a 2-byte ModR/M-consuming NOP

*Suggested issue title:* **[Verification] 0x66/0x67 on V30: nuV30 matches the die (reserved 2-byte NOP, not a prefix) — verified during PC-98 ROM-BASIC bring-up**

| | |
|---|---|
| Date | 2026-09-13 |
| Core under test | nuV30 (vendored at `pcxt-base/src/fpga/core/v30/` in our downstream project **pc98-pocket**, from `wickerwaka/nuV30`) |
| Test vehicle | `sim/tb_cpu_v30_stub.sv` (variants A–L) plus directed tests T1–T4 |
| Result | **No core bug. nuV30's 0x66/0x67 behavior is silicon-accurate. No change requested.** |

---

## Executive summary

While bringing up PC-98 ROM-BASIC boot on an FPGA core built around nuV30, we suspected a
short-jump mis-target that appeared to be caused by a `0x66` "prefix". Investigation
(decode-table forensics + directed simulation) concluded:

1. **On the V30, `0x66` and `0x67` are reserved opcodes that consume a ModR/M byte —
   a 2-byte no-operation instruction.** No PSW change, no register change, no
   architectural side effect. They are *not* prefixes (no 80386-style operand-size /
   address-size prefix exists on this CPU generation).
2. The die tables vendored in nuV30 prove it directly:
   - `ucdecode` has a **valid entry for 0x66 and 0x67, both pointing at bank 12**,
     whose single row is an E-terminated, do-nothing control sequence.
   - PLA3 classifies `62 / 63 / 66 / 67` as **HAS_MODRM**; `0x66` is not in the
     die's prefix set at all.
   - `0x63`, in contrast, has **no ucdecode entry in any row group** — it is the
     genuinely undefined one.
3. The "mis-targeted jump" never executed. The branch that fired was `77 D5` (**JA**),
   correctly taken at the entry flags (CF=0, ZF=0). The 7-byte discrepancy was the gap
   between the JA target and a JMP that was never reached.
4. The suspicious byte stream itself turned out to be **mid-instruction data in a
   corrupted, mixed-generation ROM image** — see the companion note,
   *The Franken-ROM lesson* (`franken_rom_lesson.md`). No real V30 ever executes that
   stream at that address.

This note documents the verification so the behavior is on record, and offers a small
hardening suggestion (§6). **No fix to nuV30 is needed or wanted** — in fact both
"obvious" fixes would be wrong (§6).

---

## 1. Background: why we looked

The PC-98 boot contract ends with the BIOS installing `IVT[1E] = E800:0000` and
executing `int 1E` to enter ROM BASIC. Our full-system boot bench observed the machine
arriving at `E800:FFDA` while a naive disassembly of the entry bytes suggested it should
reach `E800:FFE1` — an apparent 7-byte mis-target of an `EB D6` short jump, seemingly
after a `0x66` byte:

```
E800:0000: 06              push es
E800:0001: 66 18 77 D5     (o32) sbb [bx+0xd5], dh    ; if 0x66 were a 386 prefix
E800:0005: 89 DE           mov si, bx
E800:0007: F3 A4           rep movsb
E800:0009: EB D6           jmp E800:FFE1              ; "lands 7 bytes low"?
```

That reading is wrong twice: `0x66` is not a prefix on the V30, and the byte stream was
never real code at that address (§4 below and the companion note).

## 2. What the die says

All evidence below was re-read first-hand from the tables vendored **inside nuV30**
(`ucdecode.hex`, `ucrom.hex`, `pla3_tables.svh` — derived from the third-party V20/V30
die transcriptions credited in the nuV30 README, decoded per `V20UCDIS.PAS` field
layout).

### 2.1 `0x66` is not in the prefix PLA

The die's prefix classification covers the segment overrides (`26/2E/36/3E`),
`F0/F1`, the REP pair (`F2/F3`), and the V30-specific REPC/REPNC (`64/65`).
`0x66` asserts none of the prefix outputs; the decode path treats it as an ordinary
opcode with **HAS_MODRM** set (`pla3_native(0x66) = 14'h0100`, prefix bit clear).

### 2.2 `ucdecode`: 0x62/0x66/0x67 have entries; 0x63 does not

Direct lookups from the vendored `ucdecode.hex` (value `0x200` bit = valid;
low bits = microcode bank):

| opcode | ucdecode[rowgrp 0..3] | meaning |
|---|---|---|
| `0x62` | `29E 29F 2A0 000` | CHKIND — a real multi-row instruction (3 entries) |
| `0x63` | `000 000 000 000` | **no entry — genuinely undefined** |
| `0x64` | — (prefix: REPC) | not an opcode |
| `0x66` | `20C 000 000 000` | valid → **bank 12** |
| `0x67` | `20C 000 000 000` | valid → **bank 12** (shared with 0x66) |

Row groups 1–3 being zero for `0x66`/`0x67` is the *normal* shape for any instruction
whose microcode sequence is ≤ 4 rows — it is the same shape as, e.g., `0x60` PUSHR
(`28E 000 000 000`). It does **not** mean "undefined".

### 2.3 Bank 12 row 0 is a complete, one-row NOP

`ucrom[0x30]` (bank 12, row 0) = `0x1FFFFBFF`, which decodes to:

- no source operand, no destination operand (s1/d1 = no-move),
- **F = 0** (no flag write), **W = 0** (no register writeback),
- **E = 1** (end of sequence),
- TY = CTL with `ictl = 0xF` (no internal action) and `ectl = 7` (no bus cycle).

That is a complete instruction in a single control row: consume the opcode, consume the
ModR/M (because PLA3 said HAS_MODRM), do nothing, end. **`66 /r` = 2-byte reserved NOP.**

For contrast, executing the truly-undefined `0x63` substitutes `row_nop` words and
marches the micro-PC forward (~49 rows, in simulation) until it happens to hit an
E-terminated row — it only "terminates" by adjacency to other opcodes' rows. That is
the textbook behavior of an undefined encoding; `0x66` is not in that category.

### 2.4 The 8086 precedent does not apply

On the 8086, `60–6F` alias the conditional branches `70–7F`. The V20/V30 redefines that
space (`60/61` = PUSHR/POPR, `62` = CHKIND, `64/65` = REPC/REPNC, `63/66/67` =
reserved), so no 8086-era folklore about `0x66` carries over.

## 3. What nuV30 actually does (RTL trace)

Observed in simulation on our vendored copy (upstream: `hdl/rtl/ucore/`; module names
from `v30_core` / the EU):

```
S_OPC_POP  : opcode 0x66 popped (pc+1)
S_DECODE   : pla3_native(0x66) = 14'h0100, prefix bit clear -> regular decode
             ld_hasrm = 1 (HAS_MODRM)  -> S_MODRM
S_MODRM    : next byte taken as ModR/M (pc+1)
             (our stream: 0x18 = mod 00, rm 000 -> [BX+SI], no displacement)
S_BIND     : mod != 3 -> one speculative operand preread is issued;
             the result is discarded (the micro-row never uses it)
S_ENTER    : upc = {page 0, opc 0x66, loc 0} -> ucdecode -> bank 12
S_ROW      : single E-terminated control row -> instruction ends
```

Net effect: **IP advances exactly 2 bytes; PSW unchanged; no architectural register
changed.** The only externally visible difference from a literal NOP is the discarded
preread that the bind stage performs when `mod ≠ 3` — worth remembering when matching
bus traces cycle-for-cycle.

## 4. Directed test results

Testbench `sim/tb_cpu_v30_stub.sv` (Verilator; CPU state injected via the `bkd_load`
backdoor; every instruction retirement logged with PSW and registers). Variants A–L
replay the entry bytes under different hypotheses; T1–T4 are directed JA/0x66
isolation tests:

| test | stream | entry PSW | observed outcome | verdict |
|---|---|---|---|---|
| T1 | `77 D5` alone | 0x0002 (CF=0, ZF=0) | JA taken → 0xFFD7 (= 2 − 0x2B) | JA logic correct |
| T2 | `66 18 77 D5` | 0x0002 | 5 byte-pops, then JA taken → 0xFFDA | `0x66` = clean 2-byte NOP |
| T3 | `66 18 77 D5 89 DE` | 0x0047 (CF=1, ZF=1) | JA **not** taken; `89 DE mov si,bx` executed; SI = 04E0 | `0x66` left the injected flags intact for the JA |
| T4 | T2 relocated | 0x0002 | identical result | not an address/queue artifact |

Retirement log for the exact corrupted-ROM entry bytes (variant A):

```
[0] IP=0000 op=06 66    PSW=F002   ; push es
[1] IP=0001 op=66 18    PSW=F002   ; 0x66 opcode pop
[2] IP=0002 op=18 77    PSW=F002   ; ModR/M pop -> 2-byte reserved NOP completes
[3] IP=0003 op=77 d5    PSW=F002   ; JA opcode pop
[4] IP=0004 op=d5 89    PSW=F002   ; JA disp8 pop
[5] IP=0005 op=89 de    PSW=F002   ; JA evaluates here: CF=0, ZF=0 -> taken
[6] IP=ffda             PSW=F002   ; target = 0x0005 + sext(0xFFD5) = 0xFFDA
```

Observations:

- **PSW constant across the 0x66** (no flag writes — this is what T3 exploits).
- **No register changes** (AX/BX/CX/DX/SI/DI/SP identical before/after).
- **Byte consumption exact**: 5 bytes for `06 66 18 77 D5`; no queue or PC residue —
  the following `89 DE` / `F3 A4` decode normally, and `rep movsb` with CX=0 retires
  clean.
- **`EB D6` never executed.** Reaching 0xFFDA is the *specified* result of `77 D5`
  under the entry flags. The "7 bytes off" was `0xFFE1 − 0xFFDA` — the never-executed
  JMP's target minus the executed JA's target.

## 5. Comparison with reference emulators

| implementation | treats 0x66 as | byte consumption | valid for V30? |
|---|---|---|---|
| **nuV30** | reserved opcode (ModR/M-consuming NOP) | 2 | **yes — matches the die** |
| **np2kai `i386c`** (`i386c/ia32/inst_table.c`) | `INST_PREFIX` — operand-size prefix, unconditionally (no CPU-type guard; 0x67 = address-size) | 1 (+ semantics of next insn) | **no** — 80386-generation behavior |
| **np2kai `i286c`** (`i286c/v30patch.c`, `v30patch_op[]` → `v30_reserved`) | reserved no-op | **1** (handler burns 2 clocks, no ModR/M fetch) | direction correct (not a prefix), byte count differs from silicon |
| **Intel 8086** | Jcc alias space (`60–6F` ≡ `70–7F`) | — | no — space redefined on V20/V30 |

Measured on the same byte stream: np2kai's i386c path consumed `66 18 77 D5` as one
4-byte `o32 SBB`, clobbered the flags (FL 0000 → 0095), and **never evaluated the JA at
all**. That is a consistent 386 read of the stream — and it is precisely the "golden
trace" that made us doubt the core. An emulator agreement is only evidence if the
emulator models your CPU generation.

Side note for np2kai (out of scope here, but worth recording): `v30_reserved()` in
`i286c/v30patch.c` consumes only the opcode byte; real silicon consumes a ModR/M byte
as well. Any V30-era code stream containing `63–67` will desynchronize that core by one
byte relative to hardware.

## 6. Conclusion and suggestion

- **No change to nuV30.** `0x66`/`0x67` as ModR/M-consuming 2-byte NOPs is what the die
  says, and what the core does.
- Both "obvious fixes" would be **wrong**:
  - making `0x66` a 1-byte NOP breaks byte synchronization on *both* `0x66` and `0x67`;
  - making it a prefix imports 80386 semantics into a V30.
- Optional hardening, if maintainers are interested: a directed suite case locking the
  behavior — (a) IP advances by exactly 2 for `66 /r` and `67 /r`, (b) PSW and all
  registers unchanged, (c) both a `mod = 00` and a `mod = 11` ModR/M byte, and
  (d) the discarded preread (one read bus cycle) for `mod ≠ 3`. The vendored
  SingleStepTests/v20 gate already exercises the opcode space broadly; this would pin
  the *reserved* semantics explicitly.

## Appendix: how to reproduce

- Testbench: `sim/tb_cpu_v30_stub.sv` (downstream repo *pc98-pocket*); state injection
  via `bkd_load`, flat 1 MB memory, retirement log with PSW.
- Die-table lookups: `ucdecode.hex` / `ucrom.hex` / `pla3_tables.svh` in the vendored
  core (addresses used above: `ucdecode[0x66*4] = 0x20C`, `ucrom[0x30] = 0x1FFFFBFF`).
- The corrupted ROM that started all this, and why its bytes contained `66 18 77 D5`
  at a vector target, are covered in the companion note: **`franken_rom_lesson.md`**.
