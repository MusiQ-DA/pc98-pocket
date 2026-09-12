# The Franken-ROM lesson: how a mixed-generation BIOS ROM manufactured a phantom CPU bug

*Suggested placement:* wiki page or experience-report issue. Companion to the technical
note **`nuv30_66_verification.md`** (nuV30 0x66/0x67 verification).

| | |
|---|---|
| Date | 2026-09-13 |
| Project | pc98-pocket — a PC-98 FPGA core using nuV30 (μPD70116) |
| One-line summary | We spent days proving a CPU core innocent of a bug that a spliced, mixed-generation ROM image had manufactured. |

---

## Summary

During PC-98 ROM-BASIC bring-up we chased a "short-jump mis-target after a `0x66`
prefix" through the CPU core, its prefetch queue, its IP tracking — and eventually into
die-level microcode tables. Every layer checked out. The real cause was upstream of the
CPU entirely: **our deployed 96 KB BIOS image was a splice of parts from two different
ROM generations** (a "Franken-ROM"), and the interrupt vector we entered through
pointed into the middle of an instruction whose bytes straddled the 64 KB segment wrap.

The core (nuV30) was silicon-accurate the whole time. This note is the postmortem: how
the illusion was constructed, how to detect such an image in minutes, and the
diagnostic order we should have followed.

## 1. The symptom

The PC-98 boot contract ends with BIOS POST installing `IVT[1E] = E800:0000` and
executing `int 1E` to enter ROM BASIC. The boot bench showed:

- POST ran to completion; the machine entered `E800:0000`;
- it then arrived at `E800:FFDA` (which begins `E9 20 FF` → `jmp FEFD`) and never
  executed `E800:FFE1` / `FE95`;
- a naive disassembly of the entry bytes predicted a landing at `E800:FFE1` —
  **seven bytes higher than observed**.

An apparent, perfectly reproducible, 7-byte mis-target of an `EB D6` short jump,
seemingly preceded by a mysterious `66` byte. That looks exactly like a core bug in
prefix handling, queue tracking, or IP arithmetic.

## 2. How the illusion was constructed (three layers)

### Layer 1 — a wrong-generation lens: `0x66` is not a prefix on a V30

Disassembling the entry stream with 386-era eyes reads `66 18 77 D5` as
*(o32) sbb [bx+0xd5], dh* — a 4-byte instruction — after which `89 DE mov si,bx`,
`F3 A4 rep movsb`, `EB D6 jmp FFE1`. On a V30, `0x66` is a **reserved 2-byte NOP that
consumes a ModR/M byte** (see the companion verification note; it is in the die's
`ucdecode`, pointing at a one-row, do-nothing control sequence — not in the prefix PLA).
The correct decode of the same bytes is:

```
E800:0000: 06          push es
E800:0001: 66 18       reserved NOP (2 bytes: opcode + ModR/M)
E800:0003: 77 D5       ja  E800:FFDA        ; evaluates CF/ZF as of entry
E800:0005: 89 DE       mov si, bx
E800:0007: F3 A4       rep movsb            ; CX=0 -> retires clean
E800:0009: EB D6       jmp E800:FFE1        ; 0x000B - 0x2A = 0xFFE1
```

The `int 1E` entry flags were CF=0, ZF=0, so **the JA was taken** — correctly — to
`0x0005 + sext(0xFFD5) = 0xFFDA`. The `EB D6` jump was never executed at all.

**The entire "7 bytes off" was the gap between the never-executed JMP's target and the
executed JA's target** (`0xFFE1 − 0xFFDA = 7`). A phantom offset, assembled from two
real instructions.

### Layer 2 — the entry bytes were never code: an instruction straddling the 64 KB wrap

Where did `06 66 18 77 D5 …` come from? In the ROM generation our E800 area belonged
to, the segment tail is the end of a command-processor routine that uses the same
four-instruction idiom four times ("if the buffer pointer is past `[0x1866]`, skip the
copy"). The fourth instance straddles the 64 KB segment wrap:

```
E800:FFFB: 89 F8           mov ax, di
E800:FFFD: 01 C8           add ax, cx
E800:FFFF: 3B 06 66 18     cmp ax, [0x1866]   ; opcode at FFFF —
                                             ; ModR/M + disp16 wrap into 0000..0002
E800:0003: 77 D5           ja  FFDA           ; skip-copy branch
E800:0005: 89 DE           mov si, bx
E800:0007: F3 A4           rep movsb
E800:0009: EB D6           jmp FFE1           ; copy-done branch
```

In an intact machine, control *flows across* the wrap linearly — `E800:0000` is never
an entry point, and `06 66 18` are simply the ModR/M and displacement of the `cmp`.
Our corrupted image, however, had `IVT[1E] → E800:0000`, so the decoder **resynchronized
at an arbitrary byte boundary** inside that wrapped instruction:

- `06` reinterpreted as `push es`,
- `66 18` reinterpreted as the reserved 2-byte NOP,
- `77 d5` reinterpreted as a *standalone* JA — which then evaluated whatever flags the
  caller happened to leave behind.

A vector entry is a decoder resynchronization point: any byte sequence can become
"instructions" there. Combined with a segment wrap, *some* boundary like this always
exists in a large ROM; it is only a matter of whether a vector points at it.

### Layer 3 — why the image looked credible: a mixed-generation splice

The deployed 96 KB image combined an **E800-area part from one ROM generation with an
FD80-area part from another**. Consequences:

- The FD80 (POST) part was internally consistent — POST ran to completion, memory
  count, keyboard test, ITF handoff all worked. A half-working image is far more
  convincing than a dead one.
- Every late-boot oddity was therefore attributed to our bring-up (core, timers,
  keyboard, work areas) instead of the image.
- The corruption even explained earlier red herrings downstream of the bad entry: a
  fake dispatch table, an `int` frame eaten by an epilogue `ret`, and `SS` ending up
  equal to the flags word (a stray `17` byte executed as `POP SS`).

Detection was one hash away the whole time (§3).

## 3. Detection: the one-minute checks

1. **Check the vector-entry signature before anything else.**
   For a proper PC-9801UX-class BIOS, `E800:0000` — the `IVT[1E]` target, file offset
   `0x0000` with the image mapped at physical `0xE8000` — must begin
   **`EB 22`** (short jump to `E800:0024` = the real BASIC INIT).
   Ours began `06 66 18 77 D5`. That single check ends the investigation.

   | | deployed image (broken) | correct UX image |
   |---|---|---|
   | `E800:0000` (file `0x0000`) | `06 66 18 77 D5 …` (mid-instruction data) | **`EB 22`** → `jmp E800:0024` → BASIC INIT |

2. **Hash the whole image against known-good dumps — and hash the halves separately.**
   A whole-file match proves provenance; a *partial* match (one region matches dump A,
   another matches dump B) is the fingerprint of a splice.
   Reference hashes for the correct UX set:
   `bios.rom` md5 `3af0ae018c5710eec6e2811064814138`,
   `itf.rom` `1d295699ffeab0f0e24e09381299259d`,
   `sound.rom` `42c271f8b720e796a484cc1165ff4914`,
   `font.rom` `4133b0be0d470920da60b9ed28d2614f`.
   (Our broken image: md5 `bd59a125b6a675e4758166b0341026a1`.)

3. **Disassemble across segment-wrap boundaries (FFFF ↔ 0000) before trusting any
   listing.** A disassembly that starts at a vector target *inside* a wrapped
   instruction is fiction — plausible, self-consistent fiction.

4. **Know your reference emulator's CPU generation.** np2kai's i386c path treats `0x66`
   as an operand-size prefix for every CPU type; on our byte stream it consumed
   `66 18 77 D5` as one 4-byte `o32 SBB`, clobbered flags, and **never evaluated the
   JA**. Its "golden trace" silently confirmed a byte stream that V30 silicon never
   sees. Emulator agreement is only evidence if the emulator models your silicon.

5. **Notice repeated idioms.** The `cmp / ja / mov si,bx / rep movsb / jmp` idiom
   appears four times in that routine. Recognizing the pattern is what exposed the
   wrap — the fourth instance's "missing" first bytes were sitting at offset `0x0000`.

## 4. The correct diagnostic order (what we should have done)

1. **Input provenance and internal consistency** — hashes vs. known dumps, entry-point
   signatures, idiom/wrap checks. *Minutes.*
2. **Architectural state at the entry** — flags, registers, IVT contents, work areas.
   A conditional branch at a vector entry evaluates the *caller's* flags; ours were
   CF=0/ZF=0, which alone explains the taken JA.
3. **Only then the core** — with a directed, isolated testbench (ours: T1–T4 and
   variants A–L in `sim/tb_cpu_v30_stub.sv`) that removes the ROM from the equation
   entirely.

We ran it backwards: days of RTL-level testbenches and die-table forensics *first*,
which — to be fair — is what eventually proved the core innocent and forced the
question back onto the image. But the hash check in §3 would have reached the same
answer on day one.

## 5. Generalizable lessons

- **A corrupt input can simulate a precise, reproducible, "obviously wrong" hardware
  bug.** Reproducibility is not authenticity.
- **A vector entry is a decoder resync point.** Mid-instruction bytes become real
  instructions; with a 64 KB segment wrap in play, such boundaries are guaranteed to
  exist somewhere in a large ROM.
- **A conditional branch at a vector entry evaluates the caller's flags** — before
  blaming the branch, ask what the flags actually were.
- **Half-working images are the most dangerous kind.** POST passing certifies the POST
  half, and says nothing about the half you are about to jump into.
- **Keep a known-good signature list for your ROM set** (entry bytes, idiom positions,
  per-region hashes) and check it in CI before any long simulation run.
- **The reference emulator is a witness, not a judge** — check which CPU generation its
  opcode tables actually encode.

## 6. Condensed timeline

1. **Symptom.** Boot lands at `E800:FFDA`, expected `FFE1`; suspected mis-targeted
   `EB D6` after a `66` "prefix".
2. **Workaround era.** Patched the ROM byte `0x66 → 0x90` (np2-following). The machine
   progressed — but that path *executes* `18 77 D5` as `sbb [bx+0xd5], dh`, a real
   memory write to DS:0x05B5 and a flag clobber that silicon never performs. A
   workaround that "works" is not proof of a diagnosis.
3. **Core-investigation era.** Directed testbenches (T1–T4, variants A–L) plus
   re-reading the vendored die tables. Verdict: nuV30 matches silicon — `0x66` is a
   2-byte reserved NOP, and the JA was correctly taken at the entry flags. The core was
   innocent; the question moved to "why does the ROM contain this stream at a vector
   target?"
4. **Resolution.** Obtained the correct UX ROM set: `E800:0000 = EB 22`; the deployed
   image was identified as a two-generation splice. With the correct image the machine
   enters BASIC INIT (`jmp E800:0024` → `mov ax,0x60; mov ss,ax` …), initializes with
   SS=DS=0x0060, and writes "MEMORY 000KB OK" to the screen. The `0x66 → 0x90` patch
   auto-disabled itself (the correct image contains no `0x66` there). The nuV30 core
   remained untouched throughout.

## References

- Companion technical note: **`nuv30_66_verification.md`** — die-table evidence and
  directed test results for nuV30's `0x66`/`0x67` behavior.
- Testbench: `sim/tb_cpu_v30_stub.sv` (variants A–L, directed T1–T4).
- nuV30 (upstream): https://github.com/wickerwaka/nuV30 — `ucdecode`/`ucrom`/PLA
  transcriptions and `hdl/rtl/ucore/`.
- np2kai: `i386c/ia32/inst_table.c` (0x66/0x67 as `INST_PREFIX`) and
  `i286c/v30patch.c` (`{0x66, v30_reserved}` — correctly not a prefix, though it
  consumes 1 byte where silicon consumes 2).
